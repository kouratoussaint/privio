#!/usr/bin/env python3
"""Test bout à bout du lot 5.8 (console : équipe et modération) contre un Supabase local
COMPLET :
  1. A (propriétaire) ajoute B comme modérateur ; B voit l'entrée « Administration » mais
     la console reste fermée tant qu'il n'a pas activé la vérification en deux étapes ;
  2. B active les deux étapes : tableau de bord oui, réglages non ;
  3. B bloque un site : un lien vers ce site n'a plus d'aperçu ;
  4. B ferme, rouvre puis supprime un groupe (motif obligatoire) ; suivi de la modération ;
  5. le journal du propriétaire dit qui a agi ; A retire B de l'équipe (état rétabli).

Usage : console_equipe_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <DB_URL>
"""
import json
import subprocess
import sys
import urllib.error
import urllib.request
import uuid

API, KEY, TA, TB, DB = sys.argv[1:6]
PIN = "482915"


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


def refused(r, code):
    return code in json.dumps(r)


B = rpc("get_my_account", {}, TB)[1]["user_id"]
before = sql("select value from private.runtime_settings where key = 'admin_phone_e164'")
sql("update private.runtime_settings set value = '+22670000001' where key = 'admin_phone_e164'")
two_step = False
try:
    # ------------------------------------------------------------------ 1. Équipe
    s, r = rpc("console_team_add", {"p_phone": "+22670000002", "p_role": "moderator"}, TB)
    check(s >= 400 and refused(r, "ADMIN_REQUIRED"), "B ne s'ajoute pas lui-même", r)
    s, r = rpc("console_team_add", {"p_phone": "+22670000002", "p_role": "moderator"}, TA)
    check(s == 200 and r["role"] == "moderator", "A ajoute B comme modérateur", r)
    s, ok = rpc("console_access", {}, TB)
    check(s == 200 and ok is True, "B voit l'entrée Administration", ok)
    s, me = rpc("console_me", {}, TB)
    check(s == 200 and me["role"] == "moderator" and me["two_step"] is False, "rôle et deux étapes à activer", me)
    s, r = rpc("console_dashboard", {}, TB)
    check(s >= 400 and refused(r, "CONSOLE_TWO_STEP_REQUIRED"), "sans deux étapes : console fermée", r)

    # ------------------------------------------------------------------ 2. Deux étapes
    s, r = rpc("enable_two_step", {"p_pin": PIN}, TB)
    check(s in (200, 204), "B active la vérification en deux étapes", r)
    two_step = True
    s, r = rpc("console_dashboard", {}, TB)
    check(s == 200 and "accounts" in r, "B ouvre le tableau de bord", r)
    s, r = rpc("console_policies", {}, TB)
    check(s >= 400 and refused(r, "ADMIN_REQUIRED"), "modérateur : pas les réglages", r)
    s, r = rpc("console_journal_page", {}, TB)
    check(s >= 400 and refused(r, "ADMIN_REQUIRED"), "ni le journal", r)

    # ------------------------------------------------------------------ 3. Sites sans aperçu
    s, domain = rpc("console_block_site", {"p_site": "https://www.site-bloque.example/promo", "p_blocked": True}, TB)
    check(s == 200 and domain == "site-bloque.example", "B bloque un site", domain)
    s, conv = rpc("start_direct_conversation", {"p_other_user_id": B}, TA)
    check(s == 200, "discussion A–B", conv)
    s, msg = rpc("send_message", {"p_conversation_id": conv, "p_client_msg_id": str(uuid.uuid4()),
                                  "p_body": "Regarde https://site-bloque.example/gain"}, TA)
    check(s == 200, "A envoie un lien vers ce site", msg)
    s, target = rpc("link_preview_target", {"p_message_id": msg[0]["id"]}, TA)
    check(s == 200 and target is None, "pas d'aperçu pour ce site (le lien reste)", target)
    rpc("console_block_site", {"p_site": "site-bloque.example", "p_blocked": False}, TB)

    # ------------------------------------------------------------------ 4. Groupes
    s, g = rpc("create_group", {"p_title": "Groupe CI 5.8", "p_invitee_ids": []}, TA)
    check(s == 200, "A crée un groupe", g)
    s, page = rpc("console_groups_page", {"p_query": "groupe ci 5.8"}, TB)
    check(s == 200 and page["total"] == 1 and "messages" not in page["rows"][0],
          "B trouve le groupe (sans messages)", page)
    s, r = rpc("console_group_action", {"p_id": g, "p_action": "close", "p_note": ""}, TB)
    check(s >= 400 and refused(r, "MODERATION_NOTE_REQUIRED"), "motif obligatoire", r)
    s, r = rpc("console_group_action", {"p_id": g, "p_action": "close", "p_note": "Test de la CI"}, TB)
    check(s == 200 and r["closed"] is True, "B ferme le groupe", r)
    s, r = rpc("send_message", {"p_conversation_id": g, "p_client_msg_id": str(uuid.uuid4()), "p_body": "Encore"}, TA)
    check(s >= 400 and refused(r, "GROUP_CLOSED"), "plus personne n'écrit", r)
    s, r = rpc("console_group_action", {"p_id": g, "p_action": "reopen", "p_note": "Test de la CI"}, TB)
    check(s == 200 and r["closed"] is False, "B rouvre le groupe", r)
    s, r = rpc("console_group_action", {"p_id": g, "p_action": "delete", "p_note": "Test de la CI"}, TB)
    check(s == 200, "B supprime le groupe", r)
    s, stats = rpc("console_moderation_stats", {"p_days": 7}, TB)
    check(s == 200 and "by_person" in stats, "suivi de la modération", stats)
    s, tpl = rpc("console_templates", {}, TB)
    check(s == 200 and any(t["kind"] == "support" for t in tpl) and any(t["kind"] == "decision" for t in tpl),
          "réponses types disponibles", tpl)

    # ------------------------------------------------------------------ 5. Journal, retrait
    s, jp = rpc("console_journal_page", {"p_type": "groups"}, TA)
    check(s == 200 and jp["total"] >= 3 and all(r["by_role"] == "moderator" for r in jp["rows"][:3]),
          "journal : qui a agi (modérateur)", jp)
    s, r = rpc("console_team_remove", {"p_user_id": B}, TA)
    check(s in (200, 204), "A retire B de l'équipe", r)
    s, ok = rpc("console_access", {}, TB)
    check(s == 200 and ok is False, "B n'a plus accès", ok)
finally:
    if two_step:
        rpc("disable_two_step", {"p_pin": PIN}, TB)
    sql(f"delete from private.console_staff where user_id = '{B}'")
    sql(f"update private.runtime_settings set value = '{before}' where key = 'admin_phone_e164'")
print("Console : équipe et modération (lot 5.8) : OK")
