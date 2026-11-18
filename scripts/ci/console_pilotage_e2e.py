#!/usr/bin/env python3
"""Test bout à bout du lot 5.9 (console : pilotage) contre un Supabase local COMPLET :
  1. A (propriétaire) passe les inscriptions « Sur liste » : B, déjà inscrit, n'est pas
     touché ; un code d'invitation est créé ;
  2. exceptions : appels vidéo coupés pour B seul (réglages de son application, appel
     refusé par le serveur), puis retirés ;
  3. préréglage « Mode pilote » : aperçu des changements (sans les appliquer) ;
  4. message d'information programmé : affiché à B pendant sa période ;
  5. statistiques (langue, rétention, usage), export journalisé ; console ouverte sur un
     nouveau téléphone : alerte.
État rétabli à la fin.

Usage : console_pilotage_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
"""
import datetime as dt
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
        try:
            return e.code, (json.loads(raw) if raw else None)
        except ValueError:
            return e.code, raw.decode(errors="replace")


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


def iso(d):
    return d.astimezone(dt.timezone.utc).isoformat()


B = rpc("get_my_account", {}, TB)[1]["user_id"]
before = sql("select value from private.runtime_settings where key = 'admin_phone_e164'")
sql("update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164'")
try:
    # ------------------------------------------------------------------ 1. Inscriptions
    s, r = rpc("console_set_signups", {"p_mode": "list"}, TB)
    check(s >= 400 and "ADMIN_REQUIRED" in json.dumps(r), "B ne règle pas les inscriptions", r)
    s, r = rpc("console_set_signups", {"p_mode": "list"}, TA)
    check(s == 200 and r == "list", "A : inscriptions sur liste", r)
    s, st = rpc("signup_status", {}, TB)
    check(s == 200 and st["mode"] == "list", "état des inscriptions lisible avant le profil", st)
    s, convs = rpc("list_conversations", {}, TB)
    check(s == 200, "B (déjà inscrit) n'est pas touché", convs)
    s, code = rpc("console_signup_code_create", {"p_label": "CI", "p_max_uses": 2, "p_days": 1}, TA)
    check(s == 200 and len(code) == 8, "code d'invitation créé", code)
    s, r = rpc("console_signup_phones", {"p_text": "70 99 99 01\n+22670999902", "p_add": True}, TA)
    check(s == 200 and r["count"] == 2, "numéros autorisés ajoutés", r)
    s, info = rpc("console_signups", {}, TA)
    check(s == 200 and "+22670999901" in info["phones"] and any(c["code"] == code for c in info["codes"]),
          "liste et codes affichés", info)

    # ------------------------------------------------------------------ 2. Exceptions
    s, r = rpc("console_set_override", {"p_scope": "user", "p_id": B, "p_key": "calls_video_enabled",
                                        "p_value": False, "p_days": 1, "p_note": "Test CI"}, TA)
    check(s in (200, 204), "A coupe la vidéo pour B seul", r)
    s, pol = rpc("get_client_policies", {}, TB)
    check(s == 200 and pol["values"]["calls_video_enabled"] is False, "l'application de B le sait", pol)
    s, pa = rpc("get_client_policies", {}, TA)
    check(s == 200 and pa["values"]["calls_video_enabled"] is True, "A garde la vidéo", pa)
    A = rpc("get_my_account", {}, TA)[1]["user_id"]
    s, direct = rpc("start_direct_conversation", {"p_other_user_id": A}, TB)
    check(s == 200, "discussion B–A", direct)
    s, r = rpc("start_call", {"p_conversation_id": direct, "p_kind": "video"}, TB)
    check(s >= 400 and "FEATURE_DISABLED" in json.dumps(r), "appel vidéo de B refusé", r)
    s, lst = rpc("console_overrides", {"p_user_id": B}, TA)
    check(s == 200 and len(lst) == 1 and lst[0]["target"].startswith("@"), "exception listée", lst)
    rpc("console_set_override", {"p_scope": "user", "p_id": B, "p_key": "calls_video_enabled",
                                 "p_value": None, "p_days": None, "p_note": None}, TA)
    s, pol = rpc("get_client_policies", {}, TB)
    check(pol["values"]["calls_video_enabled"] is True, "exception retirée", pol)

    # ------------------------------------------------------------------ 3. Préréglage
    s, ch = rpc("console_preset", {"p_name": "pilot", "p_apply": False}, TA)
    check(s == 200 and any(c["key"] == "group_max_members" or c["key"] == "group_invite_links_enabled"
                           for c in ch), "aperçu du mode pilote", ch)

    # ------------------------------------------------------------------ 4. Message programmé
    now = dt.datetime.now(dt.timezone.utc)
    s, r = rpc("console_set_scheduled_announcement", {
        "p_text": "Maintenance CI", "p_starts": iso(now - dt.timedelta(minutes=1)),
        "p_ends": iso(now + dt.timedelta(hours=1))}, TA)
    check(s in (200, 204), "message programmé", r)
    s, pol = rpc("get_client_policies", {}, TB)
    check(pol["values"]["announcement_text"] == "Maintenance CI", "B le voit pendant sa période", pol)
    rpc("console_set_scheduled_announcement", {"p_text": "", "p_starts": None, "p_ends": None}, TA)

    # ------------------------------------------------------------------ 5. Statistiques
    s, r = rpc("set_device_language", {"p_language": "fr"}, TB)
    check(s in (200, 204), "langue de B transmise", r)
    s, ex = rpc("console_stats_extra", {"p_days": 7}, TA)
    check(s == 200 and ex["languages"].get("fr", 0) >= 1 and len(ex["usage"]) == 7 and "retention" in ex,
          "statistiques : langue, usage, rétention", ex)
    s, r = rpc("console_log_export", {"p_days": 7}, TA)
    check(s in (200, 204), "export journalisé", r)
    sql("delete from private.console_devices")
    sql("delete from private.admin_alerts where kind = 'console_device'")
    rpc("console_me", {}, TA)
    rpc("console_me", {}, TA)
    check(sql("select count(*) from private.admin_alerts where kind = 'console_device'") == "1",
          "console ouverte sur un nouveau téléphone : une alerte")
finally:
    rpc("console_set_signups", {"p_mode": "open"}, TA)
    sql("delete from private.signup_allowed_phones where phone_e164 in ('+22670999901', '+22670999902')")
    sql("update private.policies set enabled = false where scope_type = 'user'")
    sql("delete from private.scheduled_announcement")
    sql(f"update private.runtime_settings set value = '{before}' where key = 'admin_phone_e164'")
print("Console : pilotage (lot 5.9) : OK")
