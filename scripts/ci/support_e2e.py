#!/usr/bin/env python3
"""Test bout à bout des comptes et de l'assistance (lot 5.4) contre un Supabase local
COMPLET : recherche par numéro complet (jamais renvoyé), fiche sans contenu, réponse à une
demande d'assistance notifiée (journal de push-dispatch) et visible dans « Mes demandes »,
puis « Déconnecter le téléphone » : la session est réellement coupée côté API.

Usage : support_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
(A = +22670000001 est désigné administrateur ; B est déconnecté à la fin : dernier test.)
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


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


B = rpc("get_my_account", {}, TB)[1]["user_id"]
A = rpc("get_my_account", {}, TA)[1]["user_id"]
before = sql("select value from private.runtime_settings where key = 'admin_phone_e164'")
sql("update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164'")
try:
    # --- Recherche et fiche ----------------------------------------------------------
    status, found = rpc("console_search_accounts", {"p_query": "70 00 00 02"}, TA)
    check(status == 200 and [f["user_id"] for f in found] == [B], "recherche par numéro complet", found)
    # Lot 5.6 : numéro visible dans la console (et seulement là), recherche dès 4 chiffres.
    check(found[0].get("phone_e164") == "+22670000002", "console : numéro renvoyé", found)
    status, data = rpc("console_search_accounts", {"p_query": "700"}, TA)
    check(isinstance(data, dict) and data.get("message") == "SEARCH_PHONE_INCOMPLETE", "moins de 4 chiffres : refusé", data)
    status, fiche = rpc("console_account", {"p_user_id": B}, TA)
    check(status == 200 and fiche["user_id"] == B and fiche["device"] is not None, "fiche du compte", fiche)
    check(fiche.get("phone_e164") == "+22670000002", "fiche : numéro (console)")

    # --- Assistance --------------------------------------------------------------------
    status, rid = rpc("report", {"p_reason": "support", "p_details": "Les vocaux ne partent plus"}, TB)
    check(status == 200, "B envoie une demande d'assistance", rid)
    status, data = rpc("console_reply_support", {"p_report_id": rid,
                                                 "p_reply": "Mettez à jour l'application puis réessayez."}, TA)
    check(status in (200, 204), "l'administration répond", data)
    logged = ""
    for _ in range(30):
        logged = sql(f"select recipients || '|' || status from private.push_log where message_id = '{rid}' "
                     "and created_at > now() - interval '1 minute' order by created_at desc limit 1")
        if logged.startswith("1|"):
            break
        time.sleep(1)
    check(logged.startswith("1|"), f"push-dispatch a calculé 1 destinataire pour la réponse ({logged})", logged)
    _, mine = rpc("my_support_requests", {}, TB)
    check(any(m["id"] == rid and m["reply"].startswith("Mettez à jour") for m in mine),
          "« Mes demandes » : la réponse est visible", mine)

    # Lot 6.1 : journal technique joint (avec accord), lu dans la console.
    status, rid2 = rpc("report", {"p_reason": "support", "p_details": "Privio se ferme",
                                  "p_tech_log": "19/11 10:42 Erreur application · StateError"}, TB)
    check(status == 200, "demande avec journal technique", rid2)
    status, data = rpc("report", {"p_reason": "spam", "p_reported_user_id": A,
                                  "p_tech_log": "journal"}, TB)
    check(isinstance(data, dict) and data.get("message") == "REPORT_INVALID",
          "journal refusé hors assistance", data)
    _, opened = rpc("console_reports", {"p_status": "open"}, TA)
    check(any(r["id"] == rid2 and r.get("tech_log", "").startswith("19/11") for r in opened),
          "la console lit le journal joint", opened)

    # --- Déconnecter le téléphone -------------------------------------------------------
    status, n = rpc("console_disconnect_device", {"p_user_id": B, "p_note": "Téléphone volé"}, TA)
    check(status == 200 and n >= 1, "téléphone de B déconnecté", n)
    status, data = rpc("get_my_account", {}, TB)
    check(isinstance(data, dict) and data.get("message") == "AUTH_REQUIRED",
          "B doit se reconnecter (session coupée côté API)", data)
finally:
    sql(f"update private.runtime_settings set value = '{before}' where key = 'admin_phone_e164'")
print("Comptes et assistance : OK")
