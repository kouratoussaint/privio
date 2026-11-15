"""Test bout à bout du changement de numéro (lot 8.1c) contre un Supabase local COMPLET :
le code part vers le NOUVEAU numéro ; tant qu'il n'est pas saisi, rien ne change ; un numéro
déjà utilisé est refusé ; un mauvais code est refusé ; après le bon code, le numéro privé
(private.user_contacts) suit, le compte (identifiant, profil) est le même et l'ancien numéro
est libéré. Numéros de test locaux uniquement (supabase/config.toml).

Usage : numero_e2e.py <API_URL> <CLÉ_PUBLIQUE> <DB_URL>
"""
import json
import subprocess
import sys
import urllib.error
import urllib.request

API, KEY, DB = sys.argv[1:4]
OLD, NEW, TAKEN = "+22670000004", "+22670000005", "+22670000002"


def check(cond, label, detail=""):
    if cond:
        print(f"✅ {label}")
    else:
        print(f"❌ {label}\n   {detail}")
        sys.exit(1)


def http(method, path, body=None, token=None):
    h = {"apikey": KEY, "Content-Type": "application/json"}
    if token:
        h["Authorization"] = f"Bearer {token}"
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(API + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


def login(phone):
    http("POST", "/auth/v1/otp", {"phone": phone})
    _, raw = http("POST", "/auth/v1/verify", {"type": "sms", "phone": phone, "token": "123456"})
    return json.loads(raw)["access_token"]


try:
    login(TAKEN)  # compte existant (en CI, déjà créé par le test de fumée)
except (KeyError, ValueError):
    pass
token = login(OLD)
status, raw = http("GET", "/auth/v1/user", token=token)
me = json.loads(raw)["id"]
status, _ = http("POST", "/rest/v1/rpc/create_profile",
                 {"p_handle": "numero_test", "p_display_name": "Numéro"}, token)
check(status in (200, 204), "profil créé", status)
check(sql(f"select phone_e164 from private.user_contacts where user_id = '{me}'") == OLD,
      "numéro privé = ancien numéro")

status, raw = http("PUT", "/auth/v1/user", {"phone": TAKEN}, token)
check(status == 422 and b"phone_exists" in raw,
      "numéro déjà utilisé par un autre compte : refusé", (status, raw[:200]))

status, raw = http("PUT", "/auth/v1/user", {"phone": NEW}, token)
check(status == 200, "code envoyé au nouveau numéro", (status, raw[:200]))
check(sql(f"select phone_e164 from private.user_contacts where user_id = '{me}'") == OLD,
      "avant le code : rien ne change")
check(sql(f"select phone_change from auth.users where id = '{me}'") == NEW.lstrip("+"),
      "changement en attente côté Auth")

status, raw = http("POST", "/auth/v1/verify",
                   {"type": "phone_change", "phone": NEW, "token": "000000"}, token)
check(status >= 400, "mauvais code : refusé", (status, raw[:200]))
check(sql(f"select phone_e164 from private.user_contacts where user_id = '{me}'") == OLD,
      "après un mauvais code : rien ne change")

status, raw = http("POST", "/auth/v1/verify",
                   {"type": "phone_change", "phone": NEW, "token": "123456"}, token)
check(status == 200, "bon code : changement validé", (status, raw[:200]))
check(sql(f"select phone_e164 from private.user_contacts where user_id = '{me}'") == NEW,
      "numéro privé = nouveau numéro")
check(sql(f"select handle from public.profiles where id = '{me}'") == "numero_test",
      "même compte, même identifiant")
check(sql(f"select count(*) from auth.users where phone = '{OLD.lstrip('+')}'") == "0",
      "ancien numéro libéré")
check(sql(f"select count(*) from private.user_contacts where phone_e164 = '{OLD}'") == "0",
      "ancien numéro absent des coordonnées privées")

print("Lot 8.1c (changement de numéro) : OK")
