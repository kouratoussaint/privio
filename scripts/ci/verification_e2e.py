#!/usr/bin/env python3
"""Test bout à bout du lot 10.4 (« Vérifié en personne » et surnom privé) contre un Supabase
local COMPLET :
  1. A crée un code (QR) pour B ; seule l'empreinte du code est gardée ;
  2. B scanne en se trompant de personne : refusé ; B scanne le code de A : vérifié ;
     A reçoit aussitôt le signal temps réel « labels_changed » (sans contenu) ;
  3. les deux comptes voient « verified » ; le code ne sert qu'une fois ;
  4. B semble passer sur un nouveau téléphone, puis change de numéro : chez A le badge
     tombe (« device », puis « both ») avec un avis, qui se ferme ; A est prévenu en temps
     réel de l'arrivée d'un téléphone de B ;
  5. surnom privé : A nomme B ; B n'en voit rien ; retrait du surnom.
L'état de B (téléphone, numéro) est rétabli à la fin : les tests suivants utilisent son jeton.

Usage : verification_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
"""
import asyncio
import json
import subprocess
import sys
import urllib.error
import urllib.request

import websockets

API, KEY, TA, TB, DB = sys.argv[1:6]


def check(cond, label, detail=""):
    if cond:
        print(f"✅ {label}")
    else:
        print(f"❌ {label}\n   {detail}")
        sys.exit(1)


def rpc(name, params, token):
    h = {"apikey": KEY, "Content-Type": "application/json", "Authorization": f"Bearer {token}"}
    req = urllib.request.Request(f"{API}/rest/v1/rpc/{name}", data=json.dumps(params).encode(),
                                 method="POST", headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, (json.loads(raw) if raw else None)
        except ValueError:
            return e.code, raw.decode(errors="replace")


def user_id(token):
    h = {"apikey": KEY, "Authorization": f"Bearer {token}"}
    req = urllib.request.Request(f"{API}/auth/v1/user", headers=h)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read())["id"]


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


def labels(token):
    s, r = rpc("my_contact_labels", {}, token)
    check(s == 200, "my_contact_labels répond", r)
    return {row["user_id"]: row for row in r}


A = user_id(TA)
B = user_id(TB)
WS = API.replace("https://", "wss://").replace("http://", "ws://") + \
    f"/realtime/v1/websocket?apikey={KEY}&vsn=1.0.0"


async def listen_while(token, uid, action, event="labels_changed", timeout=10):
    """Rejoint le canal privé de [uid], lance [action], attend [event] ; renvoie le message."""
    async with websockets.connect(WS) as ws:
        await ws.send(json.dumps({
            "topic": f"realtime:user:{uid}", "event": "phx_join", "ref": "1", "join_ref": "1",
            "payload": {"config": {"broadcast": {"ack": False, "self": False},
                                   "presence": {"key": "", "enabled": False},
                                   "postgres_changes": [], "private": True},
                        "access_token": token}}))
        while True:
            m = json.loads(await asyncio.wait_for(ws.recv(), 15))
            if m["event"] == "phx_reply":
                check(m["payload"].get("status") == "ok", "canal privé rejoint", m)
                break
        await asyncio.sleep(1)
        action()
        try:
            while True:
                m = json.loads(await asyncio.wait_for(ws.recv(), timeout))
                if m["event"] == "broadcast" and m["payload"].get("event") == event:
                    return m
        except asyncio.TimeoutError:
            return None


# ------------------------------------------------------------------ 1. Code de A pour B
s, r = rpc("create_verification_code", {"p_user_id": B}, TA)
check(s == 200 and len(r.get("code", "")) == 32 and r.get("seconds") == 120,
      "A obtient un code de vérification valable 2 minutes", r)
CODE = r["code"]
check(sql(f"select count(*) from private.verification_codes where code_hash::text like '%{CODE}%'") == "0"
      and sql(f"select count(*) from private.verification_codes where code_hash = "
              f"extensions.digest('{CODE}', 'sha256')") == "1",
      "seule l'empreinte du code est gardée")
s, r = rpc("verification_code_status", {"p_code": CODE}, TA)
check(r == "pending", "code en attente", r)

# ------------------------------------------------------------------ 2. B scanne
s, r = rpc("confirm_verification_code", {"p_code": CODE, "p_user_id": B}, TB)
check(s >= 400 and "VERIFY_WRONG_PERSON" in json.dumps(r), "B se trompe de fiche : refusé", r)

result = {}


def scan():
    result["scan"] = rpc("confirm_verification_code", {"p_code": CODE, "p_user_id": A}, TB)


sig = asyncio.run(listen_while(TA, A, scan))
s, r = result["scan"]
check(s == 200 and r.get("user_id") == A, "B scanne le code de A : vérifié", r)
check(sig is not None, "A est prévenu en temps réel (« labels_changed »)", "aucun signal en 10 s")
check(CODE not in json.dumps(sig), "le signal ne contient pas le code", json.dumps(sig)[:300])

# ------------------------------------------------------------------ 3. Les deux côtés
check(labels(TA).get(B, {}).get("verification") == "verified", "A voit B « Vérifié en personne »")
check(labels(TB).get(A, {}).get("verification") == "verified", "B voit A « Vérifié en personne »")
s, r = rpc("verification_code_status", {"p_code": CODE}, TA)
check(r == "verified", "A voit le résultat de son code", r)
s, r = rpc("confirm_verification_code", {"p_code": CODE, "p_user_id": A}, TB)
check(s >= 400 and "VERIFY_CODE_EXPIRED" in json.dumps(r), "le code ne sert qu'une fois", r)

# ------------------------------------------------------------------ 4. Le badge tombe
# Un téléphone de B arrive (ligne déjà révoquée : la session de B reste valable).
fake = {}


def new_phone():
    fake["id"] = sql(
        "insert into public.devices (user_id, session_id, platform, app_version, revoked_at, "
        f"revoked_reason) values ('{B}', gen_random_uuid(), 'android', 'ci', now(), 'logout') "
        "returning id").splitlines()[0]


sig = asyncio.run(listen_while(TA, A, new_phone))
sql(f"delete from public.devices where id = '{fake['id']}'")
check(sig is not None, "A est prévenu quand un téléphone de B se connecte", "aucun signal en 10 s")

# Téléphone de B différent de celui de la vérification.
side = "hi" if A < B else "lo"
saved_dev = sql(f"select device_{side} from private.in_person_verifications "
                f"where user_lo = least('{A}'::uuid, '{B}'::uuid) and user_hi = greatest('{A}'::uuid, '{B}'::uuid)")
sql(f"update private.in_person_verifications set device_{side} = gen_random_uuid() "
    f"where user_lo = least('{A}'::uuid, '{B}'::uuid) and user_hi = greatest('{A}'::uuid, '{B}'::uuid)")
lab = labels(TA)[B]
check(lab["verification"] == "lapsed" and lab["lapse"] == "device" and lab["notice"] is True,
      "nouveau téléphone de B : badge retiré chez A, avis à revérifier", lab)
check(labels(TB)[A]["verification"] == "verified", "B voit toujours A vérifié (A n'a pas changé)")
s, r = rpc("dismiss_verification_notice", {"p_user_id": B}, TA)
check(s in (200, 204), "A ferme l'avis", r)
lab = labels(TA)[B]
check(lab["verification"] == "lapsed" and lab["notice"] is False, "avis fermé, badge toujours retiré", lab)

phone = sql(f"select phone from auth.users where id = '{B}'")
try:
    sql(f"update auth.users set phone = '22670009999' where id = '{B}'")
    lab = labels(TA)[B]
    check(lab["lapse"] == "both" and lab["notice"] is True, "nouveau numéro en plus : l'avis revient", lab)
finally:
    sql(f"update auth.users set phone = '{phone}' where id = '{B}'")
    sql(f"update private.in_person_verifications set device_{side} = nullif('{saved_dev}', '')::uuid "
        f"where user_lo = least('{A}'::uuid, '{B}'::uuid) and user_hi = greatest('{A}'::uuid, '{B}'::uuid)")
check(labels(TA)[B]["verification"] == "verified", "situation d'origine : de nouveau vérifié")
check(sql("select count(*) from private.in_person_verifications "
          f"where encode(phone_lo, 'escape') like '%{phone[-6:]}%' "
          f"or encode(phone_hi, 'escape') like '%{phone[-6:]}%'") == "0",
      "aucun numéro en clair dans les vérifications")

# ------------------------------------------------------------------ 5. Surnom privé
s, r = rpc("set_contact_nickname", {"p_user_id": B, "p_nickname": "  Mon   frère "}, TA)
check(s == 200 and r == "Mon frère", "A donne un surnom à B (espaces nettoyés)", r)
check(labels(TA)[B]["nickname"] == "Mon frère", "A retrouve son surnom (gardé sur le serveur)")
check(labels(TB)[A]["nickname"] is None, "B ne voit pas le surnom que A lui donne")
s, r = rpc("set_contact_nickname", {"p_user_id": B, "p_nickname": "x" * 41}, TA)
check(s >= 400 and "NICKNAME_INVALID" in json.dumps(r), "surnom de plus de 40 caractères refusé", r)
s, r = rpc("set_contact_nickname", {"p_user_id": A, "p_nickname": "Moi"}, TA)
check(s >= 400 and "NICKNAME_NOT_ALLOWED" in json.dumps(r), "pas de surnom pour soi-même", r)
s, r = rpc("set_contact_nickname", {"p_user_id": B, "p_nickname": ""}, TA)
check(s == 200 and r is None and labels(TA)[B]["nickname"] is None, "surnom retiré", r)

print("Vérification en personne et surnom privé (lot 10.4) : OK")
