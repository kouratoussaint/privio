#!/usr/bin/env python3
"""Test bout à bout de la confidentialité et du vidage (lot 4.3) contre un Supabase local
COMPLET : réglages, photo de profil masquée jusque dans le stockage, présence, « vider chez
moi », « vider pour nous deux » avec accord (fichiers effacés du stockage, aucune trace).

Usage : privacy_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <CONVERSATION> <DB_URL>
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

API, KEY, TA, TB, CONV, DB = sys.argv[1:7]
FIX = Path(__file__).parent / "fixtures"


def ok(label):
    print(f"✅ {label}")


def fail(label, detail):
    print(f"❌ {label}\n   {detail}")
    sys.exit(1)


def check(cond, label, detail=""):
    ok(label) if cond else fail(label, detail)


def http(method, path, body=None, token=None, headers=None):
    h = {"apikey": KEY, **(headers or {})}
    if token:
        h["Authorization"] = f"Bearer {token}"
    data = body if isinstance(body, (bytes, type(None))) else json.dumps(body).encode()
    if data is not None and not isinstance(body, bytes):
        h.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(API + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def rpc(name, params, token):
    status, raw = http("POST", f"/rest/v1/rpc/{name}", params, token)
    return status, (json.loads(raw) if raw else None)


def error_of(data):
    return data.get("message") if isinstance(data, dict) else None


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


def privacy(token, presence="contacts", receipts=True, typing=True, avatar="everyone",
            invites="everyone", ttl=None):
    return rpc("set_my_privacy", {
        "p_presence_visibility": presence, "p_read_receipts": receipts,
        "p_typing_indicator": typing, "p_avatar_visibility": avatar,
        "p_group_invites": invites, "p_default_ttl_seconds": ttl}, token)


def summary(token):
    _, rows = rpc("list_conversations", {}, token)
    return next((r for r in rows if r["conversation_id"] == CONV), None)


def gone(bucket, path):
    return sql(f"select count(*) from storage.objects where bucket_id = '{bucket}' and name = '{path}'") == "0"


def purge_and_wait(bucket, path):
    sql("select private.request_media_purge()")
    for _ in range(40):
        if gone(bucket, path):
            return True
        time.sleep(0.5)
    return False


# --- Réglages ----------------------------------------------------------------------
status, rows = rpc("get_my_privacy", {}, TA)
check(status == 200 and rows[0]["presence_visibility"] == "contacts", "réglages par défaut lisibles", rows)
status, data = privacy(TA, presence="amis")
check(error_of(data) == "PRIVACY_SETTING_INVALID", "valeur inconnue refusée", data)

# --- Photo de profil : masquée jusque dans le stockage -------------------------------
status, raw = http("POST", "/functions/v1/avatar-set", (FIX / "photo_640.jpg").read_bytes(), TA,
                   {"Content-Type": "image/jpeg"})
avatar = json.loads(raw).get("avatar_path", "")
check(status == 200 and avatar, "Alice pose une photo de profil", raw[:200])
status, _ = http("GET", f"/storage/v1/object/authenticated/avatars/{avatar}", token=TB)
check(status == 200, "« tout le monde » : Bob voit la photo")
privacy(TA, avatar="nobody")
status, _ = http("GET", f"/storage/v1/object/authenticated/avatars/{avatar}", token=TB)
check(status != 200, f"« personne » : le fichier est refusé à Bob ({status})")
check(summary(TB)["peer_avatar_path"] is None, "et la liste ne donne plus le chemin")
privacy(TA)

# --- Présence ------------------------------------------------------------------------
_, me = rpc("get_my_account", {}, TA)
rpc("touch_presence", {"p_online": True}, TA)
status, rows = rpc("get_presence", {"p_user_id": me["user_id"]}, TB)
check(status == 200 and rows[0]["visible"] and rows[0]["online"], "Bob (contact) voit Alice en ligne", rows)
rpc("touch_presence", {"p_online": False}, TA)
_, rows = rpc("get_presence", {"p_user_id": me["user_id"]}, TB)
check(not rows[0]["online"] and rows[0]["last_seen_at"], "application fermée : « vu à » seulement", rows)
privacy(TA, presence="nobody")
_, rows = rpc("get_presence", {"p_user_id": me["user_id"]}, TB)
check(not rows[0]["visible"] and rows[0]["last_seen_at"] is None, "« personne » : rien n'est donné", rows)
privacy(TA)

# --- Vider chez moi ------------------------------------------------------------------
rpc("send_message", {"p_conversation_id": CONV, "p_client_msg_id": str(uuid.uuid4()), "p_body": "Avant"}, TA)
time.sleep(0.2)
status, res = rpc("clear_conversation", {"p_conversation_id": CONV, "p_scope": "me"}, TB)
check(status == 200 and res == "cleared", "Bob vide la discussion chez lui", res)
_, rows = rpc("get_messages", {"p_conversation_id": CONV}, TB)
check(rows == [], "chez Bob : vide", rows)
_, rows = rpc("get_messages", {"p_conversation_id": CONV}, TA)
check(any(r["body"] == "Avant" for r in rows), "chez Alice : les messages restent", len(rows))
check(summary(TB)["cleared_before"] is not None, "la liste de Bob donne l'heure du vidage")

# --- Vider pour nous deux : accord, fichiers effacés, aucune trace --------------------
time.sleep(0.2)
cid = str(uuid.uuid4())
q = urllib.parse.urlencode({"conversation_id": CONV, "client_msg_id": cid})
status, raw = http("POST", f"/functions/v1/voice-send?{q}", (FIX / "vocal_5s.m4a").read_bytes(), TA,
                   {"Content-Type": "audio/mp4"})
check(status == 200, "Alice envoie un vocal", raw[:200])
VOICE = json.loads(raw)["media_path"]
status, res = rpc("clear_conversation", {"p_conversation_id": CONV, "p_scope": "everyone"}, TA)
check(res == "requested", "Alice demande à vider pour les deux", res)
check(summary(TB)["clear_request_by"] == me["user_id"], "Bob voit la demande")
status, res = rpc("respond_clear_request", {"p_conversation_id": CONV, "p_accept": True}, TB)
check(status == 200 and res == "cleared", "Bob accepte", res)
for t, who in ((TA, "Alice"), (TB, "Bob")):
    _, rows = rpc("get_messages", {"p_conversation_id": CONV}, t)
    check(rows == [], f"chez {who} : discussion vide, sans « Message supprimé »", rows)
check(sql(f"select count(*) from public.messages where conversation_id = '{CONV}'") == "0",
      "aucun message ne reste en base (pas même système)")
check(purge_and_wait("voice", VOICE), "le vocal est effacé du stockage")
status, data = rpc("respond_clear_request", {"p_conversation_id": CONV, "p_accept": True}, TB)
check(error_of(data) == "CLEAR_REQUEST_NOT_FOUND", "demande close après accord", data)

print("Confidentialité et vidage de discussion : OK")
