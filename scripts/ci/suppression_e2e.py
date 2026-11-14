#!/usr/bin/env python3
"""Test bout à bout du lot 7.2b1 contre un Supabase local COMPLET (PostgREST réel) :
groupe supprimé pour tous par un administrateur (messages et photo effacés, avis aux
membres), discussion supprimée chez moi puis revenue avec un nouveau message.

Usage : suppression_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
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


def listed(token, cid):
    _, rows = rpc("list_conversations", {}, token)
    return any(c["conversation_id"] == cid for c in rows)


B = rpc("get_my_account", {}, TB)[1]["user_id"]

# --- Groupe supprimé pour tous ---------------------------------------------------------
_, gid = rpc("create_group", {"p_title": "Groupe CI à supprimer", "p_invitee_ids": [B]}, TA)
_, invs = rpc("list_my_invitations", {}, TB)
inv = next(i for i in invs if i["conversation_id"] == gid)
rpc("respond_to_invitation", {"p_invitation_id": inv["invitation_id"], "p_accept": True}, TB)
status, rows = rpc("send_message", {"p_conversation_id": gid, "p_client_msg_id": str(uuid.uuid4()),
                                    "p_body": "Message du groupe"}, TA)
check(status == 200 and listed(TB, gid), "groupe avec un membre et un message")
status, err = rpc("delete_conversation", {"p_conversation_id": gid, "p_scope": "everyone"}, TB)
check(status == 400 and err.get("message") == "NOT_ADMIN", "un membre ne le supprime pas", err)
status, r = rpc("delete_conversation", {"p_conversation_id": gid, "p_scope": "everyone"}, TA)
check(status == 200 and r == "deleted", "le créateur le supprime pour tous", r)
check(not listed(TA, gid) and not listed(TB, gid), "disparu des deux listes")
check(sql(f"select count(*) from public.messages where conversation_id = '{gid}'") == "0",
      "messages effacés de la base")
_, notices = rpc("list_group_deletion_notices", {}, TB)
mine = [n for n in notices if n["title"] == "Groupe CI à supprimer"]
check(len(mine) == 1, "le membre voit « Le groupe … a été supprimé »", notices)
rpc("dismiss_group_deletion_notice", {"p_id": mine[0]["id"]}, TB)
_, notices = rpc("list_group_deletion_notices", {}, TB)
check(not any(n["id"] == mine[0]["id"] for n in notices), "avis fermé")
_, notices = rpc("list_group_deletion_notices", {}, TA)
check(not any(n["title"] == "Groupe CI à supprimer" for n in notices), "pas d'avis pour l'auteur")

# --- Discussion supprimée chez moi -----------------------------------------------------
_, conv = rpc("start_direct_conversation", {"p_other_user_id": B}, TA)
rpc("send_message", {"p_conversation_id": conv, "p_client_msg_id": str(uuid.uuid4()),
                     "p_body": "Avant suppression"}, TB)
status, r = rpc("delete_conversation", {"p_conversation_id": conv, "p_scope": "me"}, TA)
check(status == 200 and r == "deleted" and not listed(TA, conv), "A la supprime chez elle")
check(listed(TB, conv), "B la garde")
rpc("send_message", {"p_conversation_id": conv, "p_client_msg_id": str(uuid.uuid4()),
                     "p_body": "Après suppression"}, TB)
check(listed(TA, conv), "nouveau message de B : elle revient chez A")
_, msgs = rpc("get_messages", {"p_conversation_id": conv}, TA)
bodies = [m["body"] for m in msgs if m["kind"] == "text"]
check("Avant suppression" not in bodies and "Après suppression" in bodies,
      "sans l'ancien historique", bodies)
print("Lot 7.2b1 (suppression de discussions et de groupes) : OK")
