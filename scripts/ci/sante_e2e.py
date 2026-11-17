#!/usr/bin/env python3
"""Test bout à bout de la santé du service (lot 5.7) contre un Supabase local COMPLET :
les codes SMS envoyés et vérifiés par le vrai service Auth sont comptés (connexion et
changement de numéro, joués plus tôt par le test de fumée et numero_e2e.py) ; les appels
d'appels_e2e.py sont comptés ; la rubrique Santé est réservée à l'administration ; la
notification de test passe par push-dispatch ; le test du relais (call-ice) ne renvoie
aucun accès.

Usage : sante_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
(A = +22670000001, désigné administrateur pour ce test ; le réglage est rétabli à la fin.)
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


def post(path, params, token):
    h = {"apikey": KEY, "Content-Type": "application/json", "Authorization": f"Bearer {token}"}
    req = urllib.request.Request(f"{API}{path}", data=json.dumps(params).encode(), method="POST",
                                 headers=h)
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


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


def count(kind, purpose):
    return int(sql(f"select count(*) from private.sms_log where kind = '{kind}' and purpose = '{purpose}'"))


# Codes réellement envoyés et vérifiés par Auth (numéros de test : aucun SMS ne part).
check(count("code", "login") >= 2, "codes de connexion comptés (Auth)", count("code", "login"))
check(count("verified", "login") >= 2, "connexions vérifiées comptées (Auth)", count("verified", "login"))
check(count("code", "phone_change") >= 1, "code de changement de numéro compté", count("code", "phone_change"))
check(count("verified", "phone_change") >= 1, "changement de numéro vérifié compté",
      count("verified", "phone_change"))
check(sql("select count(*) from information_schema.columns where table_schema = 'private' "
          "and table_name = 'sms_log' and column_name in ('phone', 'user_id')") == "0",
      "journal des codes sans numéro ni compte")
check(int(sql("select coalesce(sum(value), 0) from private.daily_stats where metric like 'calls\\_%'")) >= 1,
      "appels de appels_e2e.py comptés")

admin_before = sql("select value from private.runtime_settings where key = 'admin_phone_e164'")
sql("update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164'")
try:
    status, data = rpc("console_health", {}, TB)
    check(isinstance(data, dict) and data.get("message") == "ADMIN_REQUIRED",
          "autre compte : santé refusée par le serveur", data)
    status, h = rpc("console_health", {}, TA)
    check(status == 200 and isinstance(h, dict), "administration : santé du service", (status, h))
    check(h["signup"]["codes_30d"] >= 2 and h["signup"]["verified_30d"] >= 2,
          "parcours d'inscription : codes envoyés et vérifiés", h["signup"])
    check("+226" not in json.dumps(h) and "2267000" not in json.dumps(h), "aucun numéro dans la santé")
    check(any(j["job"] == "privio_health_alerts" for j in h["diagnostics"]["jobs"]),
          "tâche des alertes planifiée (pg_cron)", h["diagnostics"]["jobs"])
    check(isinstance(h["versions"]["installed"], list), "versions installées listées")

    # Test du relais : réservé, aucun accès renvoyé.
    status, r = post("/functions/v1/call-ice", {"test": True}, TB)
    check(status == 403, "test du relais refusé à un autre compte", (status, r))
    status, r = post("/functions/v1/call-ice", {"test": True}, TA)
    check(status == 200 and r.get("relay") in ("ok", "not_configured", "failed"),
          f"test du relais : {r.get('relay') if isinstance(r, dict) else r}", (status, r))
    check("iceServers" not in r and "credential" not in json.dumps(r), "aucun accès au relais renvoyé", r)

    # Notification de test : passe par push-dispatch (compte rendu dans le journal).
    status, test_id = rpc("console_test_push", {}, TA)
    check(status == 200 and isinstance(test_id, str), "notification de test demandée", (status, test_id))
    status, again = rpc("console_test_push", {}, TA)
    check(isinstance(again, dict) and again.get("message") == "RATE_LIMITED", "pas deux tests en 30 s", again)
    row = ""
    for _ in range(40):
        row = sql(f"select status from private.push_log where message_id = '{test_id}'")
        if row:
            break
        time.sleep(0.5)
    check(row != "", f"push-dispatch a traité la notification de test ({row})")
    status, h = rpc("console_health", {}, TA)
    check(h["diagnostics"]["last_test"]["result"] is not None, "résultat du test affiché", h["diagnostics"])

    # Alertes : la vérification tourne sans erreur sur la vraie base.
    out = sql("select private.check_health_alerts()")
    check(out.startswith("{"), f"vérification des alertes exécutée ({out})")
    check(sql("select count(*) from private.admin_audit where action in ('health', 'health_relay', 'health_push')") != "0",
          "consultations et tests journalisés")
finally:
    sql(f"update private.runtime_settings set value = '{admin_before}' where key = 'admin_phone_e164'")
    sql("delete from private.admin_alerts")

print("Santé du service (lot 5.7) : OK")
