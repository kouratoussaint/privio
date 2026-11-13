#!/usr/bin/env python3
"""Test bout à bout de la modération (lot 5.3) contre un Supabase local COMPLET : un
signalement notifie l'administration (journal de notification), la console suspend un
compte ; par l'API réelle, le compte suspendu est refusé partout sauf pour voir sa situation
et contester ; la réactivation rétablit l'accès.

Usage : moderation_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
(B = +22670000002 est désigné administrateur pour ce test ; A est le compte signalé.
Le réglage est rétabli à la fin.)
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


def err(data):
    return data.get("message") if isinstance(data, dict) else None


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


A = rpc("get_my_account", {}, TA)[1]["user_id"]
before = sql("select value from private.runtime_settings where key = 'admin_phone_e164'")
sql("update private.runtime_settings set value = '+22670000002' where key = 'admin_phone_e164'")
try:
    # --- Signalement : l'administration est notifiée (sans contenu) ---------------------
    status, rid = rpc("report", {"p_reason": "spam", "p_reported_user_id": A,
                                 "p_details": "Messages publicitaires"}, TB)
    check(status == 200 and isinstance(rid, str), "B signale A", rid)
    logged = ""
    for _ in range(30):
        logged = sql(f"select status from private.push_log where message_id = '{rid}'")
        if logged:
            break
        time.sleep(1)
    check(logged != "", f"push-dispatch a traité l'événement pour l'administration ({logged})")

    # --- File et suspension --------------------------------------------------------------
    _, items = rpc("console_reports", {"p_status": "open"}, TB)
    mine = [r for r in items if r["id"] == rid]
    check(len(mine) == 1 and mine[0]["kind"] == "account" and mine[0]["reported_user_id"] == A,
          "le signalement est dans la file", items[:1])
    check("+226" not in json.dumps(items), "aucun numéro dans la file")
    status, data = rpc("console_moderate", {"p_report_ids": [rid], "p_action": "suspend",
                                            "p_note": "Spam répété", "p_days": 1}, TB)
    check(status == 200 and data == 1, "A suspendu 24 h", data)

    # --- Compte suspendu : refus partout, sauf sa situation et la contestation ------------
    status, data = rpc("list_conversations", {}, TA)
    check(err(data) == "ACCOUNT_SUSPENDED", "suspendu : discussions refusées", data)
    status, data = rpc("send_message", {"p_conversation_id": "00000000-0000-0000-0000-000000000000",
                                        "p_client_msg_id": "55555555-5555-5555-5555-555555555555",
                                        "p_body": "x"}, TA)
    check(err(data) == "ACCOUNT_SUSPENDED", "suspendu : envoi refusé", data)
    status, acc = rpc("get_my_account", {}, TA)
    check(status == 200 and acc["user_id"] == A, "suspendu : son compte reste lisible (écran dédié)")
    status, st = rpc("my_moderation_status", {}, TA)
    check(status == 200 and st["suspension"]["reason"] == "spam" and "répété" not in json.dumps(st),
          "il voit sa suspension et son motif, pas la note interne", st)
    status, data = rpc("submit_appeal", {"p_sanction_id": st["suspension"]["id"],
                                         "p_text": "Je ne fais pas de publicité"}, TA)
    check(status in (200, 204), "il conteste", data)
    _, appeals = rpc("console_appeals", {}, TB)
    check(any(a["sanction_id"] == st["suspension"]["id"] for a in appeals), "contestation reçue dans la console")

    # --- Réactivation -------------------------------------------------------------------
    status, data = rpc("console_answer_appeal", {"p_sanction_id": st["suspension"]["id"], "p_lift": True,
                                                 "p_note": "Contestation acceptée"}, TB)
    check(status in (200, 204), "contestation acceptée : suspension levée", data)
    status, data = rpc("list_conversations", {}, TA)
    check(status == 200 and isinstance(data, list), "réactivé : discussions de nouveau accessibles", data)
    _, journal = rpc("console_journal", {}, TB)
    check(any(j["action"] == "moderation" for j in journal) and any(j["action"] == "appeal" for j in journal),
          "décisions inscrites au journal")
finally:
    sql(f"update private.runtime_settings set value = '{before}' where key = 'admin_phone_e164'")
print("Modération : OK")
