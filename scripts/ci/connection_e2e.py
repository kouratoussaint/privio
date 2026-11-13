#!/usr/bin/env python3
"""Test bout à bout des demandes de connexion (lot 4.7) contre un Supabase local COMPLET :
pas d'écriture directe à un inconnu ; demande avec mot ; refus (l'expéditeur le voit et doit
attendre) ; nouvelle demande acceptée (le mot devient le 1er message, effacé après 5 min) ;
demandes croisées ; notifications sans contenu calculées par la base (journal).

Usage : connection_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime

API, KEY, TA, TB, DB = sys.argv[1:6]


def check(cond, label, detail=""):
    if cond:
        print(f"✅ {label}")
    else:
        print(f"❌ {label}\n   {detail}")
        sys.exit(1)


def http(method, path, body=None, token=None):
    h = {"apikey": KEY, "Content-Type": "application/json"}
    if token:
        h["Authorization"] = f"Bearer {token}"
    data = None if body is None else json.dumps(body).encode()
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


def login(phone):
    http("POST", "/auth/v1/otp", {"phone": phone})
    _, raw = http("POST", "/auth/v1/verify", {"type": "sms", "phone": phone, "token": "123456"})
    return json.loads(raw)["access_token"]


def uid(token):
    return rpc("get_my_account", {}, token)[1]["user_id"]


def push_rows(request_id, expected):
    for _ in range(30):
        rows = sql(f"select count(*) from private.push_log where message_id = '{request_id}'")
        if int(rows or 0) >= expected:
            return int(rows)
        time.sleep(1)
    return int(sql(f"select count(*) from private.push_log where message_id = '{request_id}'") or 0)


TC = login("+22670000003")
A, B, C = uid(TA), uid(TB), uid(TC)
# Carla aussi a un téléphone qui reçoit les notifications (réponse à sa demande).
rpc("register_device", {"p_platform": "android", "p_app_version": "ci"}, TC)
status, data = rpc("register_push_token", {"p_token": "jeton-ci-de-carla-" + "0" * 24}, TC)
check(status in (200, 204), "Carla enregistre le jeton de notification de son téléphone", data)
sql(f"delete from private.connection_requests where from_user in ('{A}','{B}','{C}') "
    f"or to_user in ('{A}','{B}','{C}')")

# --- Plus d'écriture directe -----------------------------------------------------
status, data = rpc("start_direct_conversation", {"p_other_user_id": B}, TC)
check(error_of(data) == "CONNECTION_REQUIRED", "Carla ne peut pas écrire directement à Bob", data)
_, st = rpc("connection_status", {"p_user_id": B}, TC)
check(st[0]["state"] == "none", "aucune relation entre Carla et Bob", st)

# --- Demande avec mot, puis refus -----------------------------------------------
status, sent = rpc("send_connection_request", {"p_user_id": B, "p_note": "Bonjour Bob, ici Carla"}, TC)
check(status == 200 and sent[0]["state"] == "requested", "Carla envoie une demande avec un mot", sent)
req1 = sent[0]["request_id"]
check(push_rows(req1, 1) >= 1, "Bob est notifié (journal sans contenu : 1 envoi calculé)")
_, inbox = rpc("list_connection_requests", {}, TB)
mine = [r for r in inbox if r["id"] == req1]
check(len(mine) == 1 and mine[0]["direction"] == "incoming" and mine[0]["note"] == "Bonjour Bob, ici Carla",
      "Bob voit la demande et le mot", inbox)
check("phone" not in json.dumps(mine), "aucun numéro de téléphone dans la demande")
status, resp = rpc("respond_connection_request", {"p_request_id": req1, "p_action": "refuse"}, TB)
check(status == 200 and resp[0]["state"] == "refused", "Bob refuse", resp)
check(sql(f"select note is null from private.connection_requests where id = '{req1}'") == "t",
      "refus : le mot est effacé du serveur")
_, outbox = rpc("list_connection_requests", {}, TC)
r1 = [r for r in outbox if r["id"] == req1]
check(r1 and r1[0]["status"] == "refused" and r1[0]["retry_at"], "Carla voit le refus et l'heure de nouvel essai", outbox)
check(sql(f"select count(*) from private.connection_requests where id = '{req1}'") == "1"
      and push_rows(req1, 2) == 2, "Carla est notifiée du refus")
status, data = rpc("send_connection_request", {"p_user_id": B}, TC)
check(error_of(data) == "CONNECTION_RETRY_LATER", "redemander tout de suite : refusé", data)

# --- 6 minutes plus tard : nouvelle demande, acceptée ----------------------------
sql(f"update private.connection_requests set answered_at = answered_at - interval '6 minutes' where id = '{req1}'")
status, sent = rpc("send_connection_request", {"p_user_id": B, "p_note": "Je réessaie !"}, TC)
check(status == 200 and sent[0]["state"] == "requested", "après 5 min : nouvelle demande", sent)
req2 = sent[0]["request_id"]
status, resp = rpc("respond_connection_request", {"p_request_id": req2, "p_action": "accept"}, TB)
check(status == 200 and resp[0]["state"] == "accepted" and resp[0]["conversation_id"],
      "Bob accepte : discussion ouverte", resp)
conv = resp[0]["conversation_id"]
for token, who in ((TB, "Bob"), (TC, "Carla")):
    _, msgs = rpc("get_messages", {"p_conversation_id": conv}, token)
    check(len(msgs) == 1 and msgs[0]["body"] == "Je réessaie !" and msgs[0]["sender_id"] == C,
          f"{who} : le mot est le premier message de la discussion", msgs)
    life = (datetime.fromisoformat(msgs[0]["expires_at"]) - datetime.fromisoformat(msgs[0]["sent_at"])).total_seconds()
    check(life == 300, f"{who} : ce premier message s'efface après 5 min ({life:.0f} s)")
_, convs = rpc("list_conversations", {}, TC)
check(any(c["conversation_id"] == conv for c in convs), "la discussion apparaît chez Carla", convs)
_, st = rpc("connection_status", {"p_user_id": C}, TB)
check(st[0]["state"] == "connected" and st[0]["conversation_id"] == conv, "Bob et Carla sont connectés", st)

# --- Demandes croisées Alice ↔ Carla --------------------------------------------
status, sent = rpc("send_connection_request", {"p_user_id": C}, TA)
check(sent[0]["state"] == "requested", "Alice demande Carla", sent)
status, sent = rpc("send_connection_request", {"p_user_id": A}, TC)
check(status == 200 and sent[0]["state"] == "connected" and sent[0]["conversation_id"],
      "Carla demande Alice en même temps : connectées tout de suite", sent)

# --- Réglage « personne » ----------------------------------------------------------
rpc("set_connection_settings", {"p_accept_requests": False}, TA)
status, data = rpc("send_connection_request", {"p_user_id": A}, TB)
already = isinstance(data, list) and data and data[0]["state"] == "connected"
check(already or error_of(data) == "CONNECTION_NOT_ALLOWED",
      "Alice n'accepte plus de demandes : Bob ne peut pas lui en envoyer", data)
rpc("set_connection_settings", {"p_accept_requests": True}, TA)

print("Demandes de connexion : OK")
