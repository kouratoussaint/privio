#!/usr/bin/env python3
"""Test bout à bout du lot 9.1a (appels audio) contre un Supabase local COMPLET :
mise en relation par la base (sonnerie, description de session, réponse, fin), trace
dans la discussion, et fonction call-ice (serveurs réseau seulement pendant un appel).
La voix elle-même passe de téléphone à téléphone (WebRTC) et se vérifie sur téléphones.

Usage : appels_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <CONVERSATION> <DB_URL>
"""
import json
import subprocess
import sys
import time
import urllib.error
import urllib.request

API, KEY, TA, TB, CONV, DB = sys.argv[1:7]


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
            return e.code, raw


def rpc(name, params, token):
    return post(f"/rest/v1/rpc/{name}", params, token)


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


def push_logs(target_id, count, tries=30):
    rows = []
    for _ in range(tries):
        rows = [r for r in sql(f"select recipients || '|' || status from private.push_log "
                               f"where message_id = '{target_id}' order by id").splitlines() if r]
        if len(rows) >= count:
            return rows
        time.sleep(1)
    return rows


status, _ = rpc("register_push_token", {"p_token": "jeton-ci-de-bob-appels-" + "0" * 20}, TB)
check(status in (200, 204), "B enregistre un jeton de notification", status)

status, _ = post("/functions/v1/call-ice", {}, TA)
check(status == 403, "call-ice : refusé hors appel", status)

status, call = rpc("start_call", {"p_conversation_id": CONV, "p_kind": "audio"}, TA)
check(status == 200 and call["status"] == "ringing", "A appelle B : ça sonne", (status, call))
cid = call["id"]
logs = push_logs(cid, 1)
check(len(logs) == 1 and logs[0].split("|")[0] == "1"
      and logs[0].split("|")[1] in ("not_configured", "sent", "partial"),
      "lot 9.1b : le téléphone de B est réveillé par l'appel (une seule fois)", logs)
status, opened = rpc("my_open_call", {}, TB)
check(status == 200 and opened and opened["id"] == cid and opened["outgoing"] is False,
      "B voit l'appel entrant", opened)

status, ice = post("/functions/v1/call-ice", {}, TA)
check(status == 200 and ice["iceServers"] and "stun:" in json.dumps(ice["iceServers"]),
      "call-ice : serveurs réseau pendant l'appel", (status, ice))

status, _ = rpc("send_call_signal", {"p_call_id": cid, "p_kind": "offer",
                                     "p_payload": {"type": "offer", "sdp": "v=0"}}, TA)
check(status == 200, "A envoie sa description de session", status)
status, st = rpc("call_state", {"p_call_id": cid, "p_after": 0}, TB)
check(status == 200 and len(st["signals"]) == 1 and st["signals"][0]["kind"] == "offer",
      "B la reçoit", st)
status, ans = rpc("answer_call", {"p_call_id": cid}, TB)
check(status == 200 and ans["status"] == "accepted", "B décroche", ans)
status, _ = rpc("send_call_signal", {"p_call_id": cid, "p_kind": "answer",
                                     "p_payload": {"type": "answer", "sdp": "v=0"}}, TB)
status, st = rpc("call_state", {"p_call_id": cid, "p_after": 0}, TA)
check(status == 200 and st["status"] == "accepted" and st["signals"][-1]["kind"] == "answer",
      "A reçoit la réponse", st)
status, end = rpc("end_call", {"p_call_id": cid, "p_reason": "hangup"}, TA)
check(status == 200 and end["status"] == "ended", "A raccroche", end)
trace = sql(f"select body from public.messages where conversation_id = '{CONV}' "
            f"and kind = 'system' order by sent_at desc limit 1")
check('"e": "call"' in trace and "ended:" in trace, "trace de l'appel dans la discussion", trace)
check(sql(f"select count(*) from private.call_signals where call_id = '{cid}'") == "0",
      "signaux effacés à la fin", "")
status, _ = post("/functions/v1/call-ice", {}, TB)
check(status == 403, "call-ice : refusé après l'appel", status)
check(len(push_logs(cid, 2, tries=5)) == 1, "lot 9.1b : appel décroché, pas d'« appel manqué »", "")

# Lot 9.1b : appel non décroché (A annule) : sonnerie arrêtée et « Appel manqué ».
status, call = rpc("start_call", {"p_conversation_id": CONV, "p_kind": "audio"}, TA)
check(status == 200 and call["status"] == "ringing", "A rappelle B", (status, call))
cid2 = call["id"]
push_logs(cid2, 1)
status, end = rpc("end_call", {"p_call_id": cid2, "p_reason": "hangup"}, TA)
check(status == 200 and end["status"] in ("cancelled", "missed"), "A annule avant la réponse", end)
logs = push_logs(cid2, 2)
check(len(logs) == 2 and all(r.split("|")[0] == "1" for r in logs),
      "B : sonnerie puis « Appel manqué »", logs)
# Lot 9.2 : appel vidéo (même mise en relation, type annoncé).
status, call = rpc("start_call", {"p_conversation_id": CONV, "p_kind": "video"}, TA)
check(status == 200 and call["kind"] == "video" and call["status"] == "ringing",
      "lot 9.2 : A lance un appel vidéo", (status, call))
status, opened = rpc("my_open_call", {}, TB)
check(status == 200 and opened and opened["kind"] == "video", "B voit l'appel vidéo entrant", opened)
status, end = rpc("end_call", {"p_call_id": call["id"], "p_reason": "hangup"}, TA)
check(status == 200, "A annule l'appel vidéo", end)
print("Lot 9.1a/9.1b/9.2 (appels audio et vidéo, mise en relation, réveil) : OK")
