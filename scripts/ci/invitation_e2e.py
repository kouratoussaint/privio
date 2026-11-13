#!/usr/bin/env python3
"""Test bout à bout des invitations de groupe notifiées (lot 4.8) contre un Supabase local
COMPLET : la création d'un groupe reste rapide ; chaque invité reçoit une notification sans
contenu (journal calculé par push-dispatch) et voit l'invitation ; plus rien après réponse.

Usage : invitation_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

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
        return e.code, (json.loads(raw) if raw else None)


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()




def push_log(target_id):
    for _ in range(30):
        row = sql(f"select recipients, status from private.push_log where message_id = '{target_id}'")
        if row:
            return row
        time.sleep(1)
    return ""


# Bob (second compte du test) est l'invité ; son appareil est déjà enregistré.
TC = TB
status, data = rpc("register_push_token", {"p_token": "jeton-ci-de-bob-invite-" + "0" * 20}, TC)
check(status in (200, 204), "Bob enregistre le jeton de notification de son téléphone", data)
C = rpc("get_my_account", {}, TC)[1]["user_id"]

# --- Création avec invitation : rapide, notifiée --------------------------------------
t0 = time.time()
status, gid = rpc("create_group", {"p_title": "Groupe CI 4.8", "p_invitee_ids": [C]}, TA)
elapsed = (time.time() - t0) * 1000
check(status == 200 and isinstance(gid, str), "groupe créé avec une invitation", gid)
check(elapsed < 1000, f"création côté serveur rapide ({elapsed:.0f} ms)")
inv = sql(f"select id from private.group_invitations where conversation_id = '{gid}' and invitee_id = '{C}'")
check(len(inv) == 36, "invitation enregistrée", inv)
log = push_log(inv)
check(log.startswith("1|"), f"push-dispatch a calculé 1 destinataire pour l'invitation ({log})", log)
check("Groupe CI" not in sql(f"select coalesce(string_agg(convert_from(body,'utf8'),' '),'') from net.http_request_queue"),
      "aucun titre de groupe dans les appels de notification")

_, invs = rpc("list_my_invitations", {}, TC)
mine = [i for i in invs if i["conversation_id"] == gid]
check(len(mine) == 1, "Bob voit l'invitation", invs)
check("phone" not in json.dumps(mine), "aucun numéro de téléphone dans l'invitation")

# --- Après réponse : plus de notification possible -----------------------------------
status, joined = rpc("respond_to_invitation", {"p_invitation_id": mine[0]["invitation_id"], "p_accept": True}, TC)
check(status == 200 and joined == gid, "Bob accepte et rejoint le groupe", joined)
token = sql("select value from private.runtime_settings where key = 'push_dispatch_token'")
left = sql(f"select count(*) from public.push_invitation_targets('{token}', '{inv}')")
check(left == "0", "invitation acceptée : plus aucune cible de notification", left)
print("Invitations de groupe notifiées : OK")
