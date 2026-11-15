#!/usr/bin/env python3
"""Notifications (lot 4.1), de bout en bout sur Supabase local :
déclencheur sur messages → pg_net → push-dispatch → destinataires calculés par la base.
Sans compte de service FCM en CI : la fonction répond « not_configured » ; on vérifie le
calcul des destinataires (pas l'expéditeur, pas en sourdine) via le journal sans contenu.
Usage : push_e2e.py <API> <CLE> <JETON_A> <JETON_B> <CONVERSATION> <DB_URL>
"""
import json, subprocess, sys, time, urllib.request, uuid

API, KEY, TA, TB, CONV, DB = sys.argv[1:7]

def http(path, body, tok):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode(), method="POST",
        headers={"apikey": KEY, "Authorization": "Bearer " + tok, "Content-Type": "application/json"})
    try:
        return json.loads(urllib.request.urlopen(req).read() or b"null")
    except urllib.error.HTTPError as e:
        return json.loads(e.read() or b"null")

def sql(q):
    return subprocess.run(["psql", DB, "-tAc", q], capture_output=True, text=True).stdout.strip()

def ok(cond, label, detail=""):
    print(("✅ " if cond else "❌ ") + label + ("" if cond else f"\n   {detail}"))
    if not cond: sys.exit(1)

def wait_log(message_id):
    for _ in range(30):
        row = sql(f"select recipients || '|' || status from private.push_log where message_id = '{message_id}'")
        if row: return row
        time.sleep(1)
    return ""

r = http("/rest/v1/rpc/register_push_token", {"p_token": "jeton-ci-de-bob-" + uuid.uuid4().hex}, TB)
ok(r is None, "B enregistre le jeton de notification de son téléphone", r)

m = http("/rest/v1/rpc/send_message", {"p_conversation_id": CONV, "p_client_msg_id": str(uuid.uuid4()),
         "p_body": "Message à notifier"}, TA)
mid = m[0]["id"]
row = wait_log(mid)
ok(row != "", "la base appelle push-dispatch à l'arrivée du message (pg_net)", "aucun compte rendu en 30 s")
ok(row.split("|")[0] == "1", "un seul destinataire : B, jamais l'expéditeur", row)
ok(row.split("|")[1] in ("not_configured", "sent", "partial"), "compte rendu cohérent", row)
ok(sql("select count(*) from private.push_log where message_id = '%s' and status like '%%Message%%'" % mid) == "0",
   "le journal ne contient aucun texte", "")

http("/rest/v1/rpc/set_conversation_mute", {"p_conversation_id": CONV,
     "p_until": "2099-01-01T00:00:00Z"}, TB)
m2 = http("/rest/v1/rpc/send_message", {"p_conversation_id": CONV, "p_client_msg_id": str(uuid.uuid4()),
          "p_body": "Pendant la sourdine"}, TA)
row2 = wait_log(m2[0]["id"])
ok(row2.startswith("0|"), "discussion en sourdine : personne n'est notifié", row2)
http("/rest/v1/rpc/set_conversation_mute", {"p_conversation_id": CONV, "p_until": None}, TB)
# Lot 8.4b : rappel avant effacement (non lu, durée 72 h, s'efface dans 3 h).
m3 = http("/rest/v1/rpc/send_message", {"p_conversation_id": CONV, "p_client_msg_id": str(uuid.uuid4()),
          "p_body": "Bientôt effacé"}, TA)
mid3 = m3[0]["id"]
wait_log(mid3)
B_ID = "(select user_id from private.push_tokens limit 1)"
before = sql(f"select coalesce(read_up_to::text, '') from public.conversation_members "
             f"where conversation_id = '{CONV}' and user_id = {B_ID}")
sql(f"update public.messages set sent_at = now() - interval '69 hours', expires_at = now() + interval '3 hours' "
    f"where id = '{mid3}'")
sql(f"update public.conversation_members set read_up_to = null "
    f"where conversation_id = '{CONV}' and user_id = {B_ID}")
n = sql("select private.send_expiry_reminders()")
ok(n == "1", "rappel avant effacement : un destinataire (B)", n)
rid = sql("select id from private.expiry_reminders order by created_at desc limit 1")
row3 = wait_log(rid)
ok(row3.split("|")[0] == "1", "push-dispatch : rappel envoyé au téléphone de B", row3)
ok(sql("select private.send_expiry_reminders()") == "0", "pas de second rappel pour la même discussion", "")
sql(f"delete from public.messages where id = '{mid3}'")
sql(f"update public.conversation_members set read_up_to = "
    f"{'null' if not before else repr(before)}::timestamptz "
    f"where conversation_id = '{CONV}' and user_id = {B_ID}")
print("Test notifications bout à bout : OK")
