"""Lot 6.1 : crée le compte de mesure (connexion Auth +22670000003, code de test local)
puis remplit ses 300 discussions (donnees_vitesse.sql). Base LOCALE seulement.

Usage : preparer_mesure.py <API> <PUBLISHABLE_KEY> <DB_URL>
"""
import json
import pathlib
import subprocess
import sys
import urllib.error
import urllib.request

API, KEY, DB = sys.argv[1:4]
if "127.0.0.1" not in API and "localhost" not in API:
    sys.exit("Base locale seulement.")


def post(path, body):
    req = urllib.request.Request(f"{API}{path}", data=json.dumps(body).encode(),
                                 headers={"apikey": KEY, "Content-Type": "application/json"},
                                 method="POST")
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read() or b"null")


post("/auth/v1/otp", {"phone": "+22670000003"})
post("/auth/v1/verify", {"phone": "+22670000003", "token": "123456", "type": "sms"})
sql = pathlib.Path(__file__).with_name("donnees_vitesse.sql")
subprocess.run(["psql", DB, "-v", "ON_ERROR_STOP=1", "-q", "-c", "set privio.seed_local = 'oui'",
                "-f", str(sql)], check=True)
print("Compte de mesure prêt : 300 discussions, dont une de 1 000 messages.")
