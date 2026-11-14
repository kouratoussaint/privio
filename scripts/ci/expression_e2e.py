#!/usr/bin/env python3
"""Test bout à bout du lot 7.3b contre un Supabase local COMPLET (PostgREST, Storage,
fonctions) : photo en vue unique (fichier lisible seulement après ouverture, plus après
fermeture, jamais par l'expéditeur), recherche de GIF sans clé (indisponible, pas d'erreur
cachée), aperçus des liens (adresses locales refusées).

Usage : expression_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <CONV> <DB_URL>
"""
import json
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

API, KEY, TA, TB, CONV, DB = sys.argv[1:7]
PHOTO = (Path(__file__).parent / "fixtures" / "photo_640.jpg").read_bytes()


def check(cond, label, detail=""):
    if cond:
        print(f"✅ {label}")
    else:
        print(f"❌ {label}\n   {detail}")
        sys.exit(1)


def http(method, path, body=None, token=None, headers=None):
    h = {"apikey": KEY, **(headers or {})}
    if token:
        h["Authorization"] = f"Bearer {token}"
    data = body if isinstance(body, (bytes, type(None))) else json.dumps(body).encode()
    if data is not None and not isinstance(body, bytes):
        h.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(API + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def rpc(name, params, token):
    status, raw = http("POST", f"/rest/v1/rpc/{name}", params, token)
    return status, (json.loads(raw) if raw else None)


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


def msg(token, mid):
    _, rows = rpc("get_messages", {"p_conversation_id": CONV}, token)
    return next(m for m in rows if m["id"] == mid)


def readable(token, path):
    status, _ = http("GET", f"/storage/v1/object/authenticated/photos/{path}", token=token)
    return status == 200


# --- Vue unique -------------------------------------------------------------------------
sql("delete from private.photo_quota_daily")
q = {"conversation_id": CONV, "client_msg_id": str(uuid.uuid4()), "view_once": "1"}
status, raw = http("POST", "/functions/v1/photo-send?" + urllib.parse.urlencode(q), PHOTO, TA,
                   {"Content-Type": "image/jpeg"})
check(status == 200, "photo en vue unique envoyée", raw[:200])
mid = json.loads(raw)["id"]
path = sql(f"select media_path from public.messages where id = '{mid}'")
q2 = {**q, "client_msg_id": str(uuid.uuid4()), "caption": "légende"}
status, raw = http("POST", "/functions/v1/photo-send?" + urllib.parse.urlencode(q2), PHOTO, TA,
                   {"Content-Type": "image/jpeg"})
check(status == 422, "vue unique avec légende : refusée", raw[:200])
check(msg(TA, mid)["view_once"] and msg(TA, mid)["media_path"] is None, "l'expéditrice n'a pas le fichier")
check(not readable(TA, path), "ni par le stockage")
check(msg(TB, mid)["media_path"] is None and not readable(TB, path), "B : rien avant l'ouverture")
status, _ = rpc("open_view_once", {"p_message_id": mid}, TB)
check(status in (200, 204), "B ouvre", status)
check(msg(TB, mid)["media_path"] == path and readable(TB, path), "B lit le fichier")
check(msg(TA, mid)["opened_count"] == 1, "A voit « Ouvert »")
rpc("close_view_once", {"p_message_id": mid}, TB)
check(not readable(TB, path), "fermée : plus lisible")
status, err = rpc("open_view_once", {"p_message_id": mid}, TB)
check(status == 400 and err.get("message") == "VIEW_ONCE_UNAVAILABLE", "on ne la rouvre pas", err)
check(sql(f"select state from private.media_objects where path = '{path}'") == "purge",
      "fichier en attente d'effacement")

# --- GIF --------------------------------------------------------------------------------
status, _ = http("GET", "/functions/v1/gif-search?q=chat")
check(status == 401, "recherche de GIF : connexion exigée", status)
status, raw = http("GET", "/functions/v1/gif-search?q=chat", token=TA)
check(status == 503 and json.loads(raw).get("error") == "GIF_UNAVAILABLE",
      "sans clé KLIPY (local) : « indisponible », pas d'erreur cachée", raw[:200])
q = {"conversation_id": CONV, "client_msg_id": str(uuid.uuid4()), "slug": "chat-content"}
status, raw = http("POST", "/functions/v1/gif-send?" + urllib.parse.urlencode(q), b"", TA)
check(status == 503, "envoi de GIF sans clé : indisponible", raw[:200])
q["slug"] = "../../etc"
status, raw = http("POST", "/functions/v1/gif-send?" + urllib.parse.urlencode(q), b"", TA)
check(status == 422, "nom de GIF invalide : refusé", raw[:200])

# --- Aperçus des liens -------------------------------------------------------------------
for body, label in [
    ("Va voir http://127.0.0.1:54321/rest/v1/ stp", "adresse locale"),
    ("Va voir http://169.254.169.254/latest/meta-data/ stp", "adresse de métadonnées"),
    ("Aucun lien ici", "message sans lien"),
]:
    _, rows = rpc("send_message", {"p_conversation_id": CONV, "p_client_msg_id": str(uuid.uuid4()),
                                   "p_body": body}, TA)
    lid = rows[0]["id"]
    status, raw = http("POST", f"/functions/v1/link-preview?message_id={lid}", b"", TA)
    check(status == 200 and json.loads(raw).get("preview") is False, f"aperçu refusé : {label}", raw[:200])
    check(msg(TA, lid)["link_preview"] is None, f"aucun aperçu enregistré : {label}")
status, raw = http("POST", f"/functions/v1/link-preview?message_id={lid}", b"", TB)
check(status == 403, "seul l'expéditeur demande un aperçu", raw[:200])
print("Lot 7.3b (vue unique, GIF, aperçus des liens) : OK")
