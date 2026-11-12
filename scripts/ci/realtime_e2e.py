#!/usr/bin/env python3
"""Test temps réel bout à bout (même protocole que l'application Flutter).

Usage : realtime_e2e.py <API_URL> <CLE_PUBLIQUE> <JETON_A> <JETON_B> <CONVERSATION_ID>
  1. B rejoint son canal PRIVÉ « user:<B> » → accepté ;
  2. B tente de rejoindre le canal privé de A → refusé ;
  3. A envoie un message → B reçoit le signal « message » avec l'identifiant de discussion,
     et le signal ne contient pas le texte.
"""
import asyncio, json, sys, urllib.request, uuid
import websockets

API, KEY, TA, TB, CONV = sys.argv[1:6]

def http(path, body=None, tok=None, method="POST"):
    h = {"apikey": KEY, "Content-Type": "application/json"}
    if tok: h["Authorization"] = "Bearer " + tok
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, headers=h, method=method)
    return json.loads(urllib.request.urlopen(req).read() or b"null")

uid_a = http("/auth/v1/user", tok=TA, method="GET")["id"]
uid_b = http("/auth/v1/user", tok=TB, method="GET")["id"]
WS = API.replace("https://", "wss://").replace("http://", "ws://") + f"/realtime/v1/websocket?apikey={KEY}&vsn=1.0.0"

def join_msg(topic, token, ref):
    return json.dumps({"topic": "realtime:" + topic, "event": "phx_join", "ref": ref, "join_ref": ref,
        "payload": {"config": {"broadcast": {"ack": False, "self": False},
                               "presence": {"key": "", "enabled": False},
                               "postgres_changes": [], "private": True},
                    "access_token": token}})

async def wait_reply(ws, topic):
    while True:
        m = json.loads(await asyncio.wait_for(ws.recv(), 15))
        if m["topic"] == "realtime:" + topic and m["event"] in ("phx_reply", "phx_error", "system"):
            return m

def ok(cond, label, detail=""):
    print(("✅ " if cond else "❌ ") + label + ("" if cond else f"\n   {detail}"))
    if not cond: sys.exit(1)

async def main():
    async with websockets.connect(WS) as ws:
        await ws.send(join_msg("user:" + uid_a, TB, "1"))
        r = await wait_reply(ws, "user:" + uid_a)
        ok(r["payload"].get("status") != "ok", "B ne peut pas écouter le canal privé de A", json.dumps(r)[:300])

    async with websockets.connect(WS) as ws:
        await ws.send(join_msg("user:" + uid_b, TB, "2"))
        r = await wait_reply(ws, "user:" + uid_b)
        ok(r["payload"].get("status") == "ok", "B rejoint son propre canal privé", json.dumps(r)[:300])
        await asyncio.sleep(1)
        texte = "Signal temps réel " + uuid.uuid4().hex[:6]
        http("/rest/v1/rpc/send_message", {"p_conversation_id": CONV,
             "p_client_msg_id": str(uuid.uuid4()), "p_body": texte}, tok=TA)
        got = None
        try:
            while got is None:
                m = json.loads(await asyncio.wait_for(ws.recv(), 10))
                if m["event"] == "broadcast" and m["payload"].get("event") == "message":
                    got = m
        except asyncio.TimeoutError:
            pass
        ok(got is not None, "B reçoit le signal en temps réel après l'envoi de A", "aucun signal en 10 s")
        inner = got["payload"].get("payload", {})
        ok(inner.get("conversation_id") == CONV, "le signal désigne la bonne discussion", json.dumps(inner))
        ok(texte not in json.dumps(got), "le signal ne contient pas le texte du message", json.dumps(got)[:300])

asyncio.run(main())
print("Test temps réel bout à bout : OK")
