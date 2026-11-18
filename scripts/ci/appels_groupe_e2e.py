#!/usr/bin/env python3
"""Test bout à bout des appels de groupe (lot 9.4) contre un Supabase local COMPLET
(base, temps réel, fonction « call-sfu ») :
  1. A crée un groupe avec B ; A lance un appel de groupe ; B est prévenu en temps réel
     (« group_call ») et son téléphone sonne (my_group_calls) ;
  2. relais : B, qui n'a pas rejoint, ne peut rien demander au relais ; une demande mal
     formée est refusée ; celle de A atteint l'étape du relais (non configuré en CI, ou
     description de session refusée par Cloudflare) ;
  3. B rejoint : deux personnes ; A ne peut pas lancer un appel à deux en même temps ;
  4. A puis B quittent : l'appel se termine, trace « group_call » dans la discussion.

Usage : appels_groupe_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
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


def post(path, params, token):
    h = {"apikey": KEY, "Content-Type": "application/json", "Authorization": f"Bearer {token}"}
    req = urllib.request.Request(f"{API}{path}", data=json.dumps(params).encode(),
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


def rpc(name, params, token):
    return post(f"/rest/v1/rpc/{name}", params, token)


def sfu(params, token):
    return post("/functions/v1/call-sfu", params, token)


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


# ------------------------------------------------------------------ 1. Lancer l'appel
s, G = rpc("create_group", {"p_title": "Appel CI", "p_invitee_ids": [B]}, TA)
check(s == 200 and isinstance(G, str), "A crée un groupe", G)
s, inv = rpc("list_my_invitations", {}, TB)
iid = next((i["invitation_id"] for i in inv if i["conversation_id"] == G), None)
s, r = rpc("respond_to_invitation", {"p_invitation_id": iid, "p_accept": True}, TB)
check(s == 200, "B rejoint le groupe", r)

result = {}
sig = asyncio.run(listen_while(
    TB, B, lambda: result.update(start=rpc("start_group_call",
                                           {"p_conversation_id": G, "p_kind": "audio"}, TA)),
    "group_call"))
s, call = result["start"]
check(s == 200 and call["status"] == "active" and call["my_state"] == "joined",
      "A lance un appel de groupe", call)
C = call["id"]
check(sig is not None and C in json.dumps(sig),
      "B est prévenu en temps réel (sans contenu)", sig)
s, mine = rpc("my_group_calls", {}, TB)
check(s == 200 and any(c["id"] == C and c["my_state"] == "ringing" for c in mine),
      "le téléphone de B sonne", mine)

# ------------------------------------------------------------------ 2. Relais
s, r = sfu({"action": "push", "call_id": C, "sdp": "v=0", "tracks": [{"mid": "0", "kind": "audio"}]}, TB)
check(s == 403 and r.get("error") == "CALL_NOT_FOUND", "B (pas dans l'appel) n'accède pas au relais", r)
s, r = sfu({"action": "push", "call_id": C, "sdp": "v=0", "tracks": [{"mid": "0", "kind": "écran"}]}, TA)
check(s == 422, "piste inconnue refusée", r)
s, r = sfu({"action": "pull", "call_id": C, "tracks": [{"session": "inconnue", "name": "audio-x"}]}, TA)
check(s == 403 and r.get("error") == "SFU_FORBIDDEN", "pistes hors de l'appel refusées", r)
s, r = sfu({"action": "push", "call_id": C, "sdp": "v=0\r\n", "tracks": [{"mid": "0", "kind": "audio"}]}, TA)
check((s == 503 and r.get("error") == "SFU_NOT_CONFIGURED") or (s == 502 and r.get("error") == "SFU_FAILED"),
      "A atteint le relais (non configuré en CI, ou description refusée)", r)
s, r = post("/functions/v1/call-sfu", {"action": "push", "call_id": C}, "jeton-faux")
check(s in (401, 403), "sans jeton valable : refusé", r)

# ------------------------------------------------------------------ 3. Rejoindre
s, r = rpc("join_group_call", {"p_call_id": C}, TB)
check(s == 200 and r["joined_count"] == 2 and r["my_state"] == "joined", "B rejoint l'appel", r)
s, convs = rpc("list_conversations", {}, TA)
ab = next((c["conversation_id"] for c in convs if c["kind"] == "direct" and c.get("peer_id") == B), None)
if ab:
    s, r = rpc("start_call", {"p_conversation_id": ab}, TA)
    check(s >= 400 and "CALL_ALREADY_ACTIVE" in json.dumps(r), "pas d'appel à deux pendant l'appel de groupe", r)
s, r = rpc("set_group_call_media", {"p_call_id": C, "p_camera": False, "p_muted": True}, TB)
check(s == 200 and any(p["user_id"] == B and p["muted"] for p in r["participants"]),
      "micro coupé affiché aux autres", r)

# ------------------------------------------------------------------ 4. Fin et trace
s, r = rpc("leave_group_call", {"p_call_id": C}, TA)
check(s == 200 and r["status"] == "active", "A part, l'appel continue", r)
s, r = rpc("leave_group_call", {"p_call_id": C}, TB)
check(s == 200 and r["status"] == "ended", "B part : appel terminé", r)
s, msgs = rpc("get_messages", {"p_conversation_id": G}, TA)
trace = [m for m in msgs if m.get("kind") == "system" and '"group_call"' in (m.get("body") or "")]
check(trace and json.loads(trace[0]["body"])["v"].startswith("ended:"),
      "trace de l'appel dans la discussion, avec sa durée", trace)
check(sql(f"select count(*) from private.group_call_participants where call_id = '{C}' "
          f"and (sfu_session is not null or tracks <> '{{}}')") == "0",
      "sessions du relais oubliées à la fin")

s, r = rpc("leave_group", {"p_conversation_id": G}, TB)
check(s in (200, 204), "B quitte le groupe (nettoyage)", r)
print("Appels de groupe (lot 9.4) : OK")
