#!/usr/bin/env python3
"""Test bout à bout du lot 10.5 (groupes « Annonces » et sondages éphémères) contre un
Supabase local COMPLET :
  1. A crée un groupe « Annonces » et invite B, qui accepte ; le type ne change pas ;
  2. B n'écrit pas, ne voit que les administrateurs, mais réagit ;
  3. A publie un sondage anonyme ; B vote, change d'avis ; A reçoit le signal temps réel
     « message_changed » (sans contenu) ; personne ne voit qui a voté quoi ;
  4. A ferme le sondage : plus de vote ; sondage et votes effacés avec le message.

Usage : annonces_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
"""
import asyncio
import json
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

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


A = user_id(TA)
B = user_id(TB)
WS = API.replace("https://", "wss://").replace("http://", "ws://") + \
    f"/realtime/v1/websocket?apikey={KEY}&vsn=1.0.0"


async def listen_while(token, uid, action, event, timeout=10):
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


def poll_of(conv, msg, token):
    s, r = rpc("get_messages", {"p_conversation_id": conv}, token)
    check(s == 200, "get_messages répond", r)
    return next((m["poll"] for m in r if m["id"] == msg), None)


# ------------------------------------------------------------------ 1. Groupe « Annonces »
s, G = rpc("create_group", {"p_title": "Infos CI", "p_invitee_ids": [B], "p_announcement": True}, TA)
check(s == 200 and isinstance(G, str), "A crée un groupe « Annonces »", G)
s, inv = rpc("list_my_invitations", {}, TB)
iid = next((i["invitation_id"] for i in inv if i["conversation_id"] == G), None)
s, r = rpc("respond_to_invitation", {"p_invitation_id": iid, "p_accept": True}, TB)
check(s == 200, "B rejoint le groupe", r)
s, convs = rpc("list_conversations", {}, TB)
row = next((c for c in convs if c["conversation_id"] == G), {})
check(row.get("announcement") is True and row.get("posting") == "admins",
      "B voit un groupe « Annonces » où seuls les administrateurs écrivent", row)
s, r = rpc("set_group_settings", {"p_conversation_id": G, "p_posting": "all"}, TA)
check(s >= 400 and "ANNOUNCEMENT_LOCKED" in json.dumps(r), "le groupe ne s'ouvre pas à tous", r)

# ------------------------------------------------------------------ 2. Ce que fait un membre
s, r = rpc("send_message", {"p_conversation_id": G, "p_client_msg_id": str(uuid.uuid4()),
                            "p_body": "Moi aussi"}, TB)
check(s >= 400 and "POSTING_RESTRICTED" in json.dumps(r), "B n'écrit pas", r)
s, r = rpc("send_message", {"p_conversation_id": G, "p_client_msg_id": str(uuid.uuid4()),
                            "p_body": "Réunion samedi"}, TA)
check(s == 200, "A publie une annonce", r)
M1 = r[0]["id"]
s, r = rpc("set_reaction", {"p_message_id": M1, "p_emoji": "👍"}, TB)
check(s in (200, 204), "B réagit", r)
s, members = rpc("get_conversation_members", {"p_conversation_id": G}, TB)
check(s == 200 and {m["user_id"] for m in members} == {A, B},
      "B ne voit que l'administratrice et lui-même", members)

# ------------------------------------------------------------------ 3. Sondage
s, r = rpc("send_poll", {"p_conversation_id": G, "p_client_msg_id": str(uuid.uuid4()),
                         "p_question": "Nettoyage samedi ?", "p_options": ["Oui", "Non"]}, TB)
check(s >= 400 and "POSTING_RESTRICTED" in json.dumps(r), "B ne crée pas de sondage", r)
s, r = rpc("send_poll", {"p_conversation_id": G, "p_client_msg_id": str(uuid.uuid4()),
                         "p_question": "Nettoyage samedi ?", "p_options": ["Oui", "Non"]}, TA)
check(s == 200, "A publie un sondage", r)
P = r[0]["id"]
state = poll_of(G, P, TB)
check(state and state["options"] == ["Oui", "Non"] and state["anonymous"] is True,
      "B voit le sondage (vote anonyme par défaut)", state)

result = {}
sig = asyncio.run(listen_while(
    TA, A, lambda: result.update(vote=rpc("vote_poll", {"p_message_id": P, "p_options": [0]}, TB)),
    "message_changed"))
s, r = result["vote"]
check(s == 200 and r["counts"] == [1, 0] and r["mine"] == [0], "B vote « Oui »", r)
check(sig is not None, "A est prévenu en temps réel du vote", "aucun signal en 10 s")
s, r = rpc("vote_poll", {"p_message_id": P, "p_options": [1]}, TB)
check(s == 200 and r["counts"] == [0, 1], "B change d'avis", r)
s, r = rpc("vote_poll", {"p_message_id": P, "p_options": [0, 1]}, TB)
check(s >= 400 and "POLL_INVALID" in json.dumps(r), "une seule réponse", r)
a_state = poll_of(G, P, TA)
check(a_state["by_option"] is None and a_state["voters"] == 1,
      "vote anonyme : même A ne voit pas qui a voté", a_state)

s, r = rpc("close_poll", {"p_message_id": P}, TB)
check(s >= 400 and "NOT_SENDER" in json.dumps(r), "seule l'autrice ferme le sondage", r)
s, r = rpc("close_poll", {"p_message_id": P}, TA)
check(s in (200, 204), "A ferme le sondage", r)
s, r = rpc("vote_poll", {"p_message_id": P, "p_options": [0]}, TB)
check(s >= 400 and "POLL_CLOSED" in json.dumps(r), "sondage fermé : plus de vote", r)

# ------------------------------------------------------------------ 4. Effacé avec le message
sql(f"update public.messages set sent_at = now() - interval '2 hours', "
    f"expires_at = now() - interval '1 second' where id = '{P}'")
sql("select private.purge_expired()")
check(sql(f"select count(*) from private.polls where message_id = '{P}'") == "0"
      and sql(f"select count(*) from private.poll_votes where message_id = '{P}'") == "0",
      "sondage et votes effacés avec le message")

s, r = rpc("leave_group", {"p_conversation_id": G}, TB)
check(s in (200, 204), "B quitte le groupe (nettoyage)", r)
print("Groupes « Annonces » et sondages éphémères (lot 10.5) : OK")
