"""Test bout à bout de la vérification en deux étapes (lot 8.4a) contre un Supabase local
COMPLET (Auth réel) : un nouveau téléphone qui a reçu le SMS reste sans accès tant que le
code de vérification n'est pas saisi, et le téléphone déjà connecté le reste ; après le bon
code, le nouveau téléphone prend la place de l'ancien ; le changement de numéro est refusé
par le serveur sans le code. Numéros de test locaux uniquement (supabase/config.toml).

Usage : deux_etapes_e2e.py <API_URL> <CLÉ_PUBLIQUE> <DB_URL>
"""
import json
import subprocess
import sys
import urllib.error
import urllib.request

API, KEY, DB = sys.argv[1:4]
PHONE, NEW = "+22670000006", "+22670000007"
PIN = "258014"


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


def rpc(name, token, body=None):
    return http("POST", f"/rest/v1/rpc/{name}", body or {}, token)


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


def login(phone):
    http("POST", "/auth/v1/otp", {"phone": phone})
    _, raw = http("POST", "/auth/v1/verify", {"type": "sms", "phone": phone, "token": "123456"})
    return json.loads(raw)["access_token"]


old = login(PHONE)
_, raw = http("GET", "/auth/v1/user", token=old)
me = json.loads(raw)["id"]
status, _ = rpc("create_profile", old, {"p_handle": "deux_etapes", "p_display_name": "Deux"})
check(status in (200, 204), "profil créé", status)
status, _ = rpc("register_device", old, {"p_platform": "android", "p_app_version": "0.1.0"})
check(status == 200, "premier téléphone enregistré", status)
status, raw = rpc("enable_two_step", old, {"p_pin": PIN})
check(status in (200, 204), "vérification en deux étapes activée", (status, raw[:200]))

# Nouveau téléphone : SMS reçu, mais aucun accès sans le code.
new = login(PHONE)
_, raw = rpc("two_step_state", new)
check(json.loads(raw)["verified"] is False, "nouveau téléphone : en attente du code", raw)
status, raw = rpc("get_my_account", new)
check(status >= 400 and b"AUTH_REQUIRED" in raw, "nouveau téléphone : compte illisible",
      (status, raw[:200]))
status, raw = rpc("register_device", new, {"p_platform": "android", "p_app_version": "0.1.0"})
check(status >= 400, "nouveau téléphone : ne peut pas déconnecter l'ancien", (status, raw[:200]))
status, _ = rpc("get_my_account", old)
check(status == 200, "l'ancien téléphone reste connecté", status)

status, raw = rpc("verify_two_step", new, {"p_pin": "000111"})
check(json.loads(raw)["ok"] is False, "mauvais code : refusé", raw)
status, raw = rpc("verify_two_step", new, {"p_pin": PIN})
check(json.loads(raw)["ok"] is True, "bon code : accepté", raw)
status, _ = rpc("register_device", new, {"p_platform": "android", "p_app_version": "0.1.0"})
check(status == 200, "nouveau téléphone enregistré", status)
status, raw = rpc("get_my_account", old)
check(status >= 400 and b"AUTH_REQUIRED" in raw, "l'ancien téléphone est alors déconnecté",
      (status, raw[:200]))

# Changement de numéro : refusé par le serveur sans le code, accepté après.
status, raw = http("PUT", "/auth/v1/user", {"phone": NEW}, new)
check(status == 200, "code SMS envoyé au nouveau numéro", (status, raw[:200]))
status, raw = http("POST", "/auth/v1/verify",
                   {"type": "phone_change", "phone": NEW, "token": "123456"}, new)
check(status >= 400, "sans code de vérification : changement refusé", (status, raw[:200]))
check(sql(f"select phone_e164 from private.user_contacts where user_id = '{me}'") == PHONE,
      "numéro inchangé")
status, raw = rpc("authorize_phone_change", new, {"p_pin": PIN})
check(json.loads(raw)["ok"] is True, "code de vérification saisi", raw)
# Même code SMS (le changement est resté en attente côté Auth).
status, raw = http("POST", "/auth/v1/verify",
                   {"type": "phone_change", "phone": NEW, "token": "123456"}, new)
check(status == 200, "avec le code : changement validé", (status, raw[:200]))
check(sql(f"select phone_e164 from private.user_contacts where user_id = '{me}'") == NEW,
      "numéro changé")

print("Lot 8.4a (vérification en deux étapes) : OK")
