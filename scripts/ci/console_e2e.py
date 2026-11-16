#!/usr/bin/env python3
"""Test bout à bout de la console (lot 5.1) contre un Supabase local COMPLET : seul le
compte dont le numéro vérifié est enregistré côté serveur y accède ; le tableau de bord ne
contient que des nombres ; chaque consultation est journalisée.

Usage : console_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
(A = +22670000001, désigné administrateur pour ce test ; le réglage est rétabli à la fin.)
"""
import json
import subprocess
import sys
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


before = sql("select value from private.runtime_settings where key = 'admin_phone_e164'")
check(before.startswith("+226"), "numéro administrateur enregistré côté serveur")
sql("update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164'")
try:
    status, ok = rpc("console_access", {}, TB)
    check(status == 200 and ok is False, "autre compte : pas de console", ok)
    status, data = rpc("console_dashboard", {}, TB)
    check(isinstance(data, dict) and data.get("message") == "ADMIN_REQUIRED",
          "autre compte : tableau de bord refusé par le serveur", data)
    req = urllib.request.Request(f"{API}/rest/v1/rpc/console_dashboard", data=b"{}", method="POST",
                                 headers={"apikey": KEY, "Content-Type": "application/json"})
    try:
        urllib.request.urlopen(req, timeout=60)
        check(False, "anonyme : tableau de bord refusé")
    except urllib.error.HTTPError as e:
        check(e.code in (401, 403, 404), f"anonyme : tableau de bord refusé ({e.code})")

    status, ok = rpc("console_access", {}, TA)
    check(status == 200 and ok is True, "administrateur : console accessible", ok)
    n0 = int(sql("select count(*) from private.admin_audit where action = 'dashboard'"))
    status, d = rpc("console_dashboard", {}, TA)
    check(status == 200 and isinstance(d, dict), "tableau de bord reçu", d)
    for section in ("accounts", "activity", "groups", "requests", "health", "reports"):
        check(section in d, f"section « {section} » présente")
    check(d["accounts"]["total"] >= 2 and d["activity"]["messages_7d"] >= 1,
          f"nombres cohérents ({d['accounts']['total']} comptes, {d['activity']['messages_7d']} messages sur 7 j)", d)
    raw = json.dumps(d)
    check("+226" not in raw and "2267" not in raw and "Bonjour" not in raw and "smoke" not in raw,
          "aucun numéro, contenu ni identifiant dans le tableau de bord")
    check(int(sql("select count(*) from private.admin_audit where action = 'dashboard'")) == n0 + 1,
          "consultation inscrite au journal de la console")

    # --- Lot 5.2 : réglages, statistiques, journal ---------------------------------
    status, data = rpc("console_set_policy", {"p_key": "photo_daily_limit", "p_value": 4}, TB)
    check(isinstance(data, dict) and data.get("message") == "ADMIN_REQUIRED",
          "autre compte : modification d'un réglage refusée", data)
    _, pols = rpc("console_policies", {}, TA)
    pol = {p["key"]: p for p in pols}
    check(len(pols) >= 47 and pol["group_max_members"]["label"] == "Membres au plus par groupe",
          f"{len(pols)} réglages listés avec leur libellé", pols[:1])
    before = pol["photo_daily_limit"]["value"]
    status, val = rpc("console_set_policy", {"p_key": "photo_daily_limit", "p_value": 4}, TA)
    check(status == 200 and val == 4, "photos par jour : 4", val)
    _, client = rpc("get_client_policies", {}, TB)
    check(client["values"]["photo_daily_limit"] == 4, "les téléphones reçoivent la nouvelle valeur")
    status, data = rpc("console_set_policy", {"p_key": "message_ttl_hours", "p_value": 24}, TA)
    check(isinstance(data, dict) and data.get("message") == "POLICY_LOCKED", "72 h : cadenas", data)
    status, data = rpc("console_set_policy", {"p_key": "photo_daily_limit", "p_value": 99}, TA)
    check(isinstance(data, dict) and data.get("message") == "POLICY_OUT_OF_BOUNDS", "hors bornes : refusé", data)
    rpc("console_set_policy", {"p_key": "photo_daily_limit", "p_value": before}, TA)
    _, hist = rpc("console_policy_history", {"p_key": "photo_daily_limit"}, TA)
    check(len(hist) >= 2 and hist[0]["after"] == before and hist[1]["after"] == 4, "historique : 4 puis retour", hist[:2])
    _, journal = rpc("console_journal", {}, TA)
    check(journal[0]["action"] == "policy" and journal[0]["key"] == "photo_daily_limit",
          "journal : dernier changement de réglage", journal[:1])
    status, st = rpc("console_stats", {}, TA)
    check(status == 200 and len(st["days"]) == 30, "statistiques sur 30 jours", st)
    today = st["days"][-1]
    check(today["text"] + today["voice"] + today["photo"] >= 1 and (today["active"] or 0) >= 1,
          f"aujourd'hui : {today['text']} textes, {today['voice']} vocaux, {today['photo']} photos, {today['active']} actifs")
    check(len(st["versions"]) >= 1, f"versions installées : {st['versions']}")
    raw = json.dumps(st) + json.dumps(journal)
    check("+226" not in raw and "2267" not in raw and "Bonjour" not in raw,
          "statistiques et journal : aucun numéro ni contenu")

    # Lot 5.5 : fonctionnalités, comptes A–Z, journal filtré.
    status, page = rpc("console_accounts_page", {"p_page": 1, "p_size": 25}, TA)
    check(status == 200 and page["total"] >= 2 and len(page["rows"]) >= 2 and page["letters"],
          "lot 5.5 : comptes par ordre alphabétique, index A–Z", {k: page.get(k) for k in ("total", "letters")})
    check("+226" not in json.dumps(page), "liste des comptes : aucun numéro")
    status, data = rpc("console_accounts_page", {"p_page": 1}, TB)
    check(isinstance(data, dict) and data.get("message") == "ADMIN_REQUIRED", "liste refusée à un autre compte", data)
    status, val = rpc("console_set_policy", {"p_key": "gif_enabled", "p_value": False}, TA)
    check(status == 200 and val is False, "GIF coupés depuis la console", val)
    status, data = rpc("gif_customer_id", {}, TB)
    check(isinstance(data, dict) and data.get("message") == "FEATURE_DISABLED",
          "le serveur refuse aussitôt la recherche de GIF", data)
    _, pol = rpc("get_client_policies", {}, TB)
    check(pol["values"].get("gif_enabled") is False, "les téléphones voient l'interrupteur coupé", pol["values"].get("gif_enabled"))
    rpc("console_set_policy", {"p_key": "gif_enabled", "p_value": True}, TA)
    status, jp = rpc("console_journal_page", {"p_type": "settings", "p_days": 1, "p_page": 1, "p_size": 10}, TA)
    check(status == 200 and jp["total"] >= 2 and all(r["type"] == "settings" for r in jp["rows"]),
          "journal filtré : fonctionnalités et réglages du jour", jp.get("total"))
finally:
    sql(f"update private.runtime_settings set value = '{before}' where key = 'admin_phone_e164'")
print("Console d'administration (dont lot 5.5) : OK")
