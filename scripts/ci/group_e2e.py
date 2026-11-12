#!/usr/bin/env python3
"""Test bout à bout des groupes (lot 3.3) contre un Supabase local COMPLET : invitation
acceptée, historique depuis l'arrivée, photo de groupe (avatar-set), restriction de
publication, retrait d'un membre (plus d'accès, même aux fichiers), départ du propriétaire.

Usage : group_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API, KEY, TA, TB, DB = sys.argv[1:6]
PHOTO = (Path(__file__).parent / "fixtures" / "photo_640.jpg").read_bytes()


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
    data = json.loads(raw) if raw else None
    return status, data


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


def bodies(token, group):
    status, rows = rpc("get_messages", {"p_conversation_id": group}, token)
    return status, rows


TC = login("+22670000003")
A, B, C = uid(TA), uid(TB), uid(TC)

# --- Création, invitation acceptée -------------------------------------------------
status, G = rpc("create_group", {"p_title": "Famille CI", "p_invitee_ids": [B]}, TA)
check(status == 200 and G, "groupe créé, Bob invité", G)
_, invites = rpc("list_my_invitations", {}, TB)
mine = [i for i in invites if i["conversation_id"] == G]
check(len(mine) == 1 and mine[0]["title"] == "Famille CI", "Bob voit l'invitation", invites)
status, _ = rpc("get_messages", {"p_conversation_id": G}, TB)
check(status != 200, f"avant d'accepter : aucun message lisible ({status})")
status, joined = rpc("respond_to_invitation", {"p_invitation_id": mine[0]["invitation_id"], "p_accept": True}, TB)
check(status == 200 and joined == G, "Bob accepte et entre dans le groupe", joined)

rpc("send_message", {"p_conversation_id": G, "p_client_msg_id": str(uuid.uuid4()), "p_body": "Avant Carla"}, TA)
_, rows = bodies(TB, G)
check(any(r["body"] == "Avant Carla" and r["sender_name"] for r in rows),
      "Bob lit le message, avec le nom de l'expéditeur", rows)

# --- Photo du groupe ----------------------------------------------------------------
status, raw = http("POST", f"/functions/v1/avatar-set?conversation_id={G}", PHOTO, TA, {"Content-Type": "image/jpeg"})
avatar = json.loads(raw).get("avatar_path", "")
check(status == 200 and avatar.startswith(f"groups/{G}/"), "photo du groupe posée par avatar-set", raw[:200])
status, _ = http("POST", f"/functions/v1/avatar-set?conversation_id={G}", PHOTO, TB, {"Content-Type": "image/jpeg"})
check(status == 403, f"un simple membre ne change pas la photo du groupe ({status})")
status, _ = http("GET", f"/storage/v1/object/authenticated/avatars/{avatar}", token=TB)
check(status == 200, "un membre voit la photo du groupe")
status, _ = http("GET", f"/storage/v1/object/authenticated/avatars/{avatar}", token=TC)
check(status != 200, f"une personne extérieure ne la voit pas ({status})")

# --- Arrivée de Carla : historique depuis son arrivée seulement ----------------------
time.sleep(1.1)
status, count = rpc("invite_to_group", {"p_conversation_id": G, "p_user_ids": [C]}, TA)
check(status == 200 and count == 1, "Alice invite Carla", count)
_, invites = rpc("list_my_invitations", {}, TC)
inv = [i for i in invites if i["conversation_id"] == G][0]
rpc("respond_to_invitation", {"p_invitation_id": inv["invitation_id"], "p_accept": True}, TC)
_, rows = bodies(TC, G)
check(not any(r["body"] == "Avant Carla" for r in rows), "Carla ne voit pas les messages d'avant son arrivée",
      [r["body"] for r in rows])
status, _ = http("GET", f"/storage/v1/object/authenticated/avatars/{avatar}", token=TC)
check(status == 200, "Carla, devenue membre, voit la photo du groupe")

# --- Restriction de publication -----------------------------------------------------
rpc("set_group_settings", {"p_conversation_id": G, "p_posting": "admins"}, TA)
status, data = rpc("send_message", {"p_conversation_id": G, "p_client_msg_id": str(uuid.uuid4()), "p_body": "x"}, TB)
check(error_of(data) == "POSTING_RESTRICTED", "publication réservée : un membre ne peut plus écrire", data)
cid = str(uuid.uuid4())
status, raw = http("POST", f"/functions/v1/voice-send?conversation_id={G}&client_msg_id={cid}",
                   (Path(__file__).parent / "fixtures" / "vocal_5s.m4a").read_bytes(), TB,
                   {"Content-Type": "audio/mp4"})
check(status != 200 and b"POSTING_RESTRICTED" in raw, "ni envoyer de vocal", raw[:200])
rpc("set_group_settings", {"p_conversation_id": G, "p_posting": "all"}, TA)

# --- Retrait de Carla : plus aucun accès ---------------------------------------------
status, _ = rpc("remove_group_member", {"p_conversation_id": G, "p_user_id": C}, TA)
check(status in (200, 204), f"Alice retire Carla ({status})")
status, data = bodies(TC, G)
check(error_of(data) == "NOT_MEMBER", "Carla n'a plus accès aux messages", data)
status, _ = http("GET", f"/storage/v1/object/authenticated/avatars/{avatar}", token=TC)
check(status != 200, f"ni à la photo du groupe ({status})")

# --- Départ de la propriétaire --------------------------------------------------------
rpc("leave_group", {"p_conversation_id": G}, TA)
_, convs = rpc("list_conversations", {}, TB)
g = [c for c in convs if c["conversation_id"] == G][0]
check(g["my_role"] == "owner" and g["member_count"] == 1, "Alice partie : Bob devient propriétaire", g)
rpc("remove_group_avatar", {"p_conversation_id": G}, TB)
sql("select private.request_media_purge()")
for _ in range(40):
    if sql(f"select count(*) from storage.objects where bucket_id = 'avatars' and name = '{avatar}'") == "0":
        break
    time.sleep(0.5)
check(sql(f"select count(*) from storage.objects where bucket_id = 'avatars' and name = '{avatar}'") == "0",
      "photo du groupe retirée : effacée du stockage")
print("Test bout à bout des groupes : OK")
