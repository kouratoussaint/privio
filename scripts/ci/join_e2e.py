#!/usr/bin/env python3
"""Test bout à bout du lot 7.1b contre un Supabase local COMPLET (PostgREST, pg_net,
push-dispatch) : code d'invitation, demande d'adhésion notifiée aux administrateurs (sans
contenu), acceptation notifiée, @mention notifiée malgré la sourdine, code réinitialisé.

Usage : join_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
"""
import json
import re
import subprocess
import sys
import time
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


def push_logs(target_id, count):
    rows = []
    for _ in range(30):
        rows = [r for r in sql(
            f"select recipients || '|' || status from private.push_log where message_id = '{target_id}' order by id"
        ).splitlines() if r]
        if len(rows) >= count:
            return rows
        time.sleep(1)
    return rows


A = rpc("get_my_account", {}, TA)[1]["user_id"]
B = rpc("get_my_account", {}, TB)[1]["user_id"]
status, _ = rpc("register_push_token", {"p_token": "jeton-ci-d-alice-adhesion-" + "0" * 20}, TA)
check(status in (200, 204), "A enregistre le jeton de notification de son téléphone")
status, _ = rpc("register_push_token", {"p_token": "jeton-ci-de-bob-adhesion-" + "0" * 20}, TB)
check(status in (200, 204), "B enregistre le jeton de notification de son téléphone")

# --- Code du groupe ------------------------------------------------------------------
status, gid = rpc("create_group", {"p_title": "Tontine CI 7.1b"}, TA)
check(status == 200 and isinstance(gid, str), "A crée un groupe", gid)
status, code = rpc("get_group_invite_code", {"p_conversation_id": gid}, TA)
check(status == 200 and re.fullmatch(r"PRV-[2-9A-HJ-NP-Z]{6}", code or ""), f"code du groupe : {code}", code)
status, err = rpc("get_group_invite_code", {"p_conversation_id": gid}, TB)
check(status == 400 and err.get("message") == "NOT_MEMBER", "B (extérieur) ne lit pas le code", err)

status, rows = rpc("preview_group_by_code", {"p_code": code.lower().replace("-", " ")}, TB)
check(status == 200 and rows[0]["status"] == "approval" and rows[0]["title"] == "Tontine CI 7.1b"
      and rows[0]["conversation_id"] is None, "aperçu : nom du groupe, demande requise, pas d'identifiant", rows)
status, rows = rpc("preview_group_by_code", {"p_code": "PRV-22222Z"}, TB)
check(status == 200 and rows[0]["status"] == "invalid", "code faux : « invalid » (sans erreur)", rows)
hits = sql(f"select coalesce(sum(hits), 0) from private.rate_limit_hits where user_id = '{B}' and bucket = 'group_code'")
check(hits == "2", f"les essais sont comptés, même un code faux ({hits})", hits)

# --- Demande, notifiée aux administrateurs -------------------------------------------
status, rows = rpc("join_group_by_code", {"p_code": code}, TB)
check(status == 200 and rows[0]["status"] == "requested", "B demande à rejoindre", rows)
req = sql(f"select id from private.group_join_requests where conversation_id = '{gid}' and user_id = '{B}'")
check(len(req) == 36, "demande enregistrée", req)
logs = push_logs(req, 1)
check(logs and logs[0].startswith("1|"), f"push-dispatch : 1 administrateur prévenu ({logs})", logs)
body = sql("select coalesce(string_agg(convert_from(body,'utf8'),' '),'') from net.http_request_queue")
check("Tontine" not in body and B not in body, "aucun nom de groupe ni de personne dans l'appel de notification")
_, mine = rpc("list_my_join_requests", {}, TB)
check([r["title"] for r in mine] == ["Tontine CI 7.1b"], "B voit sa demande en attente", mine)

_, reqs = rpc("list_group_join_requests", {"p_conversation_id": gid}, TA)
check(len(reqs) == 1 and reqs[0]["user_id"] == B and "phone" not in json.dumps(reqs),
      "A voit la demande (sans numéro de téléphone)", reqs)
status, _ = rpc("respond_to_join_request", {"p_request_id": reqs[0]["request_id"], "p_approve": True}, TA)
check(status in (200, 204), "A accepte")
logs = push_logs(req, 2)
check(len(logs) == 2 and logs[1].startswith("1|"), f"B est prévenu de l'acceptation ({logs})", logs)
_, rows = rpc("preview_group_by_code", {"p_code": code}, TB)
check(rows[0]["status"] == "member" and rows[0]["conversation_id"] == gid, "B est membre", rows)

# --- @mention malgré la sourdine -----------------------------------------------------
status, _ = rpc("set_conversation_mute", {"p_conversation_id": gid,
                                          "p_until": "2099-01-01T00:00:00Z"}, TA)
check(status in (200, 204), "A met le groupe en sourdine")
status, rows = rpc("send_message", {"p_conversation_id": gid, "p_client_msg_id": str(uuid.uuid4()),
                                    "p_body": "Sans mention"}, TB)
check(status == 200, "B écrit sans mention (ancienne version de l'appel)", rows)
plain = rows[0]["id"]
status, rows = rpc("send_message", {"p_conversation_id": gid, "p_client_msg_id": str(uuid.uuid4()),
                                    "p_body": "@Alice tu viens ?", "p_mentions": [A, str(uuid.uuid4())]}, TB)
check(status == 200, "B mentionne A", rows)
mid = rows[0]["id"]
logs = push_logs(mid, 1)
check(logs and logs[0].startswith("1|"), f"A (sourdine) prévenue car mentionnée ({logs})", logs)
logs = push_logs(plain, 1)
check(logs and logs[0].startswith("0|"), f"message sans mention : sourdine respectée ({logs})", logs)
_, msgs = rpc("get_messages", {"p_conversation_id": gid}, TA)
check(next(m for m in msgs if m["id"] == mid)["mentions"] == [A], "mention lue par A (inconnu ignoré)", msgs)

# --- Code changé ---------------------------------------------------------------------
_, new = rpc("reset_group_invite_code", {"p_conversation_id": gid}, TA)
check(new != code, f"nouveau code : {new}")
_, rows = rpc("preview_group_by_code", {"p_code": code}, TB)
check(rows[0]["status"] == "invalid", "l'ancien code ne marche plus", rows)
print("Lot 7.1b (codes, demandes d'adhésion, mentions) : OK")
