#!/usr/bin/env python3
"""Test bout à bout du lot 7.2c2 contre un Supabase local COMPLET (PostgREST réel) :
messages épinglés (3 au plus, visibles des deux), favoris personnels (plusieurs d'un coup),
infos d'un message (distribué, lu, avec l'heure), « Mentions seulement » dans un groupe.

Usage : confort_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
"""
import json
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

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


def send(conv, body, token):
    _, rows = rpc("send_message", {"p_conversation_id": conv, "p_client_msg_id": str(uuid.uuid4()),
                                   "p_body": body}, token)
    return rows[0]["id"]


B = rpc("get_my_account", {}, TB)[1]["user_id"]
_, conv = rpc("start_direct_conversation", {"p_other_user_id": B}, TA)
ids = [send(conv, f"Confort {i}", TA) for i in range(4)]

# --- Épinglés -------------------------------------------------------------------------
for i in range(3):
    status, err = rpc("pin_message", {"p_message_id": ids[i], "p_pin": True}, TB if i == 0 else TA)
    check(status in (200, 204), f"épinglé {i + 1}", err)
status, err = rpc("pin_message", {"p_message_id": ids[3], "p_pin": True}, TA)
check(status == 400 and err.get("message") == "PIN_LIMIT_REACHED", "un quatrième : refusé", err)
_, pins = rpc("list_pinned_messages", {"p_conversation_id": conv}, TB)
check(len(pins) == 3 and {p["message_id"] for p in pins} == set(ids[:3]), "B voit les 3 épinglés", pins)
rpc("pin_message", {"p_message_id": ids[0], "p_pin": False}, TA)
_, pins = rpc("list_pinned_messages", {"p_conversation_id": conv}, TB)
check(len(pins) == 2, "désépinglé pour les deux")

# --- Favoris --------------------------------------------------------------------------
status, n = rpc("set_message_favorites", {"p_message_ids": ids[1:3], "p_on": True}, TB)
check(status == 200 and n == 2, "deux favoris d'un coup", n)
_, favs = rpc("list_favorite_messages", {"p_conversation_id": conv}, TB)
check({f["message_id"] for f in favs} == set(ids[1:3]), "liste des favoris de B", favs)
_, favs = rpc("list_favorite_messages", {"p_conversation_id": conv}, TA)
check(favs == [], "personnels : A n'en voit aucun")

# --- Infos d'un message -----------------------------------------------------------------
status, err = rpc("get_message_info", {"p_message_id": ids[3]}, TB)
check(status == 400 and err.get("message") == "NOT_SENDER", "seulement ses propres messages", err)
_, info = rpc("get_message_info", {"p_message_id": ids[3]}, TA)
check(len(info) == 1 and not info[0]["read"], "pas encore lu", info)
_, msgs = rpc("get_messages", {"p_conversation_id": conv}, TB)
last = max(m["sent_at"] for m in msgs)
rpc("mark_conversation", {"p_conversation_id": conv, "p_delivered_up_to": last, "p_read_up_to": last}, TB)
_, info = rpc("get_message_info", {"p_message_id": ids[3]}, TA)
check(info[0]["delivered"] and info[0]["read"] and info[0]["read_at"], "lu, avec l'heure", info)

# --- Mentions seulement --------------------------------------------------------------
_, gid = rpc("create_group", {"p_title": "Groupe CI mentions", "p_invitee_ids": [B]}, TA)
_, invs = rpc("list_my_invitations", {}, TB)
inv = next(i for i in invs if i["conversation_id"] == gid)
rpc("respond_to_invitation", {"p_invitation_id": inv["invitation_id"], "p_accept": True}, TB)
status, _ = rpc("set_notify_mode", {"p_conversation_id": gid, "p_mode": "mentions"}, TB)
_, mode = rpc("get_notify_mode", {"p_conversation_id": gid}, TB)
check(status in (200, 204) and mode == "mentions", "B : mentions seulement", mode)
check(sql(f"select notify_mode from public.conversation_members where conversation_id = '{gid}' "
          f"and user_id = '{B}'") == "mentions", "enregistré côté serveur")
status, err = rpc("set_notify_mode", {"p_conversation_id": conv, "p_mode": "mentions"}, TB)
check(status == 400 and err.get("message") == "NOT_GROUP", "pas pour une discussion à deux", err)
status, err = rpc("push_targets", {"p_token": "x", "p_message_id": ids[3]}, TA)
check(status in (401, 403, 404), "destinataires des notifications : réservé au serveur", err)

# --- Lot 7.3a : autocollant ---------------------------------------------------------------
status, rows = rpc("send_sticker", {"p_conversation_id": conv, "p_client_msg_id": str(uuid.uuid4()),
                                    "p_sticker": "privio/merci"}, TA)
check(status == 200 and rows and rows[0]["id"], "autocollant envoyé", rows)
_, msgs = rpc("get_messages", {"p_conversation_id": conv}, TB)
check(any(m["kind"] == "sticker" and m["body"] == "privio/merci" for m in msgs), "B reçoit l'autocollant")
status, err = rpc("send_sticker", {"p_conversation_id": conv, "p_client_msg_id": str(uuid.uuid4()),
                                   "p_sticker": "../../etc/passwd"}, TA)
check(status == 400 and err.get("message") == "BODY_INVALID", "nom invalide refusé", err)
print("Lot 7.2c2 (épinglés, favoris, infos, mentions seulement, autocollants) : OK")
