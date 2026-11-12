#!/usr/bin/env python3
"""Test bout à bout des messages vocaux (lot 3.1) contre un Supabase local COMPLET
(base, Auth, Storage, fonctions) : envoi par voice-send, mesure serveur, téléchargement
réservé aux membres, expiration, effacement physique par media-purge appelée par la base.

Usage : voice_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <CONVERSATION> <DB_URL>
(A et B sont les deux membres de la discussion ; le script connecte un 3e compte, C.)
"""
import json
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API, KEY, TA, TB, CONV, DB = sys.argv[1:7]
FIXTURE = (Path(__file__).parent / "fixtures" / "vocal_5s.m4a").read_bytes()


def ok(label):
    print(f"✅ {label}")


def fail(label, detail):
    print(f"❌ {label}\n   {detail}")
    sys.exit(1)


def check(cond, label, detail=""):
    ok(label) if cond else fail(label, detail)


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


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


def send_voice(token, data, client_id=None, conv=CONV):
    cid = client_id or str(uuid.uuid4())
    status, raw = http("POST", f"/functions/v1/voice-send?conversation_id={conv}&client_msg_id={cid}",
                       data, token, {"Content-Type": "audio/mp4"})
    try:
        return status, json.loads(raw), cid
    except ValueError:
        return status, {"raw": raw[:200]}, cid


def login(phone):
    http("POST", "/auth/v1/otp", {"phone": phone})
    _, raw = http("POST", "/auth/v1/verify", {"type": "sms", "phone": phone, "token": "123456"})
    return json.loads(raw)["access_token"]


def patch_box(data, box, fn):
    """Modifie le contenu d'une boîte MP4 (première occurrence) via fn(bytearray, début)."""
    out = bytearray(data)
    at = out.find(box.encode())
    assert at > 4, box
    fn(out, at + 4)  # début du contenu de la boîte
    return bytes(out)


def stretch_samples(buf, body):
    entries = struct.unpack_from(">I", buf, body + 4)[0]
    for i in range(entries):
        at = body + 8 + i * 8 + 4
        struct.pack_into(">I", buf, at, struct.unpack_from(">I", buf, at)[0] * 8)


# Comme après un déploiement : media-purge appelée sans jeton déclare son adresse.
status, raw = http("POST", "/functions/v1/media-purge")
check(status == 200 and b'"registered":true' in raw, "fonctions joignables, adresse déclarée à la base", raw)

# --- Envoi valide ----------------------------------------------------------------
status, msg, cid = send_voice(TA, FIXTURE)
check(status == 200 and msg.get("media_path", "").startswith(CONV + "/"),
      "vocal de 5 s envoyé par voice-send", f"{status} {msg}")
check(4900 <= msg["media_duration_ms"] <= 5200,
      f"durée MESURÉE par le serveur : {msg['media_duration_ms']} ms", msg)
PATH = msg["media_path"]
status, again, _ = send_voice(TA, FIXTURE, cid)
check(status == 200 and again["id"] == msg["id"], "renvoi (même identifiant client) : même message",
      f"{status} {again}")

_, raw = http("POST", "/rest/v1/rpc/get_messages", {"p_conversation_id": CONV}, TB)
voice = [m for m in json.loads(raw) if m["id"] == msg["id"]]
check(voice and voice[0]["kind"] == "voice" and voice[0]["body"] is None,
      "le destinataire voit un message vocal, sans texte", raw[:300])

status, audio = http("GET", f"/storage/v1/object/authenticated/voice/{PATH}", token=TB)
check(status == 200 and audio == FIXTURE, "le destinataire télécharge le son (identique)", status)
status, _ = http("GET", f"/storage/v1/object/authenticated/voice/{PATH}")
check(status != 200, f"sans jeton : téléchargement refusé ({status})")
status, _ = http("GET", f"/storage/v1/object/public/voice/{PATH}")
check(status != 200, f"aucune URL publique ({status})")

# --- Un tiers ne peut ni lire ni écrire ---------------------------------------------
TC = login("+22670000003")
http("POST", "/rest/v1/rpc/create_profile", {"p_handle": "smoke_tiers", "p_display_name": "Tiers"}, TC)
http("POST", "/rest/v1/rpc/register_device", {"p_platform": "android", "p_app_version": "ci"}, TC)
status, _ = http("GET", f"/storage/v1/object/authenticated/voice/{PATH}", token=TC)
check(status != 200, f"un tiers ne peut pas télécharger le son ({status})")
status, body, _ = send_voice(TC, FIXTURE)
check(status == 403 and body.get("error") == "NOT_MEMBER", "un tiers ne peut pas envoyer dans la discussion",
      f"{status} {body}")
status, _ = http("POST", f"/storage/v1/object/voice/{CONV}/{uuid.uuid4()}.m4a", FIXTURE, TB,
                 {"Content-Type": "audio/mp4"})
check(status >= 400, f"dépôt direct dans le stockage refusé à l'application ({status})")

# --- Mesure serveur : refus -------------------------------------------------------
status, body, _ = send_voice(TA, b"pas du son" * 100)
check(status == 422 and body.get("error") == "MEDIA_INVALID", "fichier qui n'est pas un son : refusé",
      f"{status} {body}")
status, body, _ = send_voice(TA, patch_box(FIXTURE, "stts", stretch_samples))
check(status == 422 and body.get("error") == "VOICE_TOO_LONG",
      "son de 40 s (en-têtes annonçant 5 s) : refusé, la table d'échantillons fait foi", f"{status} {body}")
status, body, _ = send_voice(TA, patch_box(FIXTURE, "hdlr", lambda b, at: b.__setitem__(slice(at + 8, at + 12), b"vide")))
check(status == 422 and body.get("error") == "MEDIA_INVALID", "piste vidéo : refusée", f"{status} {body}")
status, body, _ = send_voice(TA, b"\0" * (1024 * 1024 + 1))
check(status == 413 and body.get("error") == "MEDIA_TOO_LARGE", "plus de 1 Mio : refusé", f"{status} {body}")
status, body, _ = send_voice(None, FIXTURE)
check(status == 401, f"sans jeton : envoi refusé ({status})")

# --- Expiration puis effacement physique ------------------------------------------
sql(f"update public.messages set sent_at = now() - interval '10 minutes', "
    f"expires_at = now() - interval '1 second' where id = '{msg['id']}'")
status, _ = http("GET", f"/storage/v1/object/authenticated/voice/{PATH}", token=TB)
check(status != 200, f"vocal expiré : téléchargement refusé immédiatement ({status})")
sql("select private.purge_expired()")
check(sql(f"select state from private.media_objects where path = '{PATH}'") == "purge",
      "purge : fichier en attente d'effacement physique")
request_id = sql("select private.request_media_purge()")
check(request_id != "", "la base appelle media-purge (pg_net)", "aucun appel : adresse des fonctions inconnue ?")
for _ in range(40):
    if sql(f"select count(*) from storage.objects where bucket_id = 'voice' and name = '{PATH}'") == "0":
        break
    time.sleep(0.5)
check(sql(f"select count(*) from storage.objects where bucket_id = 'voice' and name = '{PATH}'") == "0",
      "fichier effacé du stockage par media-purge (API Storage)",
      sql(f"select status_code, content from net._http_response where id = {request_id}"))
check(sql(f"select count(*) from private.media_objects where path = '{PATH}'") == "0",
      "plus aucune trace du fichier dans la base")
print("Test bout à bout des messages vocaux : OK")
