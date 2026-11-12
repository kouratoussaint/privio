#!/usr/bin/env python3
"""Test bout à bout des photos et photos de profil (lot 3.2) contre un Supabase local
COMPLET : quota journalier (5), métadonnées retirées par le serveur (GPS…), lecture réservée,
remboursement d'un fichier refusé, idempotence, expiration et effacement physique.

Usage : photo_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <CONVERSATION> <DB_URL>
"""
import json
import struct
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

API, KEY, TA, TB, CONV, DB = sys.argv[1:7]
BASE = (Path(__file__).parent / "fixtures" / "photo_640.jpg").read_bytes()
SECRET = b"PRIVIO-GPS-12.3714N-1.5197W"


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


def rpc(name, params, token):
    _, raw = http("POST", f"/rest/v1/rpc/{name}", params, token)
    return json.loads(raw) if raw else None


def login(phone):
    http("POST", "/auth/v1/otp", {"phone": phone})
    _, raw = http("POST", "/auth/v1/verify", {"type": "sms", "phone": phone, "token": "123456"})
    return json.loads(raw)["access_token"]


def segment(marker, payload):
    return bytes([0xFF, marker]) + struct.pack(">H", len(payload) + 2) + payload


def with_metadata(jpeg):
    """Photo « de téléphone » : EXIF avec position GPS, commentaire, données après la fin."""
    exif = segment(0xE1, b"Exif\0\0MM\0*\0\0\0\x08" + SECRET)
    comment = segment(0xFE, b"Prise par " + SECRET)
    return jpeg[:2] + exif + jpeg[2:-2] + comment + jpeg[-2:] + b"VIDEO-APRES-LA-FIN" + SECRET


def send_photo(token, data, client_id=None, caption=None):
    cid = client_id or str(uuid.uuid4())
    q = {"conversation_id": CONV, "client_msg_id": cid}
    if caption:
        q["caption"] = caption
    status, raw = http("POST", "/functions/v1/photo-send?" + urllib.parse.urlencode(q), data, token,
                       {"Content-Type": "image/jpeg"})
    try:
        return status, json.loads(raw), cid
    except ValueError:
        return status, {"raw": raw[:200]}, cid


def used(token):
    return rpc("get_photo_quota", {}, token)["used"]


def gone(bucket, path):
    return sql(f"select count(*) from storage.objects where bucket_id = '{bucket}' and name = '{path}'") == "0"


def purge_and_wait(bucket, path):
    sql("select private.request_media_purge()")
    for _ in range(40):
        if gone(bucket, path):
            return True
        time.sleep(0.5)
    return False


# --- Quota et envoi ----------------------------------------------------------------
quota = rpc("get_photo_quota", {}, TA)
check(quota["limit"] == 5 and quota["used"] == 0, "quota du jour : 5 photos, aucune utilisée", quota)

status, msg, cid = send_photo(TA, with_metadata(BASE), caption="Marché de Ouaga")
check(status == 200 and msg.get("media_width") == 640 and msg.get("media_height") == 480,
      "photo envoyée par photo-send (640 × 480, dimensions lues par le serveur)", f"{status} {msg}")
check(msg.get("body") == "Marché de Ouaga", "légende publiée avec la photo", msg)
PATH = msg["media_path"]
check(used(TA) == 1, "1 photo décomptée")
status, again, _ = send_photo(TA, with_metadata(BASE), cid)
check(status == 200 and again["id"] == msg["id"] and used(TA) == 1,
      "renvoi (même identifiant client) : même message, pas de second débit", f"{status} {again}")

# --- Le destinataire reçoit une photo NETTOYÉE --------------------------------------
status, photo = http("GET", f"/storage/v1/object/authenticated/photos/{PATH}", token=TB)
check(status == 200 and photo[:2] == b"\xff\xd8" and photo[-2:] == b"\xff\xd9",
      "le destinataire télécharge une photo JPEG valide", status)
check(SECRET not in photo, "position GPS et commentaire retirés par le serveur")
check(b"\xff\xe1" not in photo and b"Exif" not in photo, "aucun bloc EXIF dans le fichier stocké")
check(b"VIDEO-APRES-LA-FIN" not in photo, "données ajoutées après l'image retirées")

status, _ = http("GET", f"/storage/v1/object/authenticated/photos/{PATH}")
check(status != 200, f"sans jeton : téléchargement refusé ({status})")
status, _ = http("GET", f"/storage/v1/object/public/photos/{PATH}")
check(status != 200, f"aucune URL publique ({status})")
TC = login("+22670000003")
status, _ = http("GET", f"/storage/v1/object/authenticated/photos/{PATH}", token=TC)
check(status != 200, f"un tiers ne peut pas télécharger la photo ({status})")
status, _ = http("POST", f"/storage/v1/object/photos/{CONV}/{uuid.uuid4()}.jpg", BASE, TB,
                 {"Content-Type": "image/jpeg"})
check(status >= 400, f"dépôt direct dans le stockage refusé à l'application ({status})")

# --- Fichier refusé : remboursé ----------------------------------------------------
status, body, _ = send_photo(TA, b"\x89PNG\r\n\x1a\n" + b"\0" * 500)
check(status == 422 and body.get("error") == "MEDIA_INVALID", "fichier qui n'est pas un JPEG : refusé",
      f"{status} {body}")
huge = bytearray(BASE)
sof = huge.find(b"\xff\xc0")
struct.pack_into(">HH", huge, sof + 5, 5000, 5000)
status, body, _ = send_photo(TA, bytes(huge))
check(status == 422 and body.get("error") == "MEDIA_INVALID", "photo de 5000 × 5000 : refusée", f"{status} {body}")
check(used(TA) == 1, "fichiers refusés : quota remboursé (toujours 1 photo décomptée)")

# --- Limite de 5 par jour ------------------------------------------------------------
for i in range(4):
    status, body, _ = send_photo(TA, BASE)
    check(status == 200, f"photo {i + 2}/5 envoyée", f"{status} {body}")
status, body, _ = send_photo(TA, BASE)
check(status == 429 and body.get("error") == "PHOTO_QUOTA_REACHED", "6e photo du jour : refusée", f"{status} {body}")
check(used(TA) == 5, "compteur : 5 sur 5")

# --- Photo de profil ---------------------------------------------------------------
status, raw = http("POST", "/functions/v1/avatar-set", with_metadata(BASE), TA, {"Content-Type": "image/jpeg"})
avatar = json.loads(raw).get("avatar_path", "")
check(status == 200 and avatar, "photo de profil enregistrée par avatar-set", raw[:200])
check(rpc("get_my_account", {}, TA)["profile"]["avatar_path"] == avatar, "le profil porte la nouvelle photo")
status, pic = http("GET", f"/storage/v1/object/authenticated/avatars/{avatar}", token=TB)
check(status == 200 and SECRET not in pic and b"Exif" not in pic,
      "un correspondant voit la photo de profil, sans métadonnées", status)
status, _ = http("GET", f"/storage/v1/object/authenticated/avatars/{avatar}")
check(status != 200, f"photo de profil : jamais sans jeton ({status})")
status, raw = http("POST", "/functions/v1/avatar-set", BASE, TA, {"Content-Type": "image/jpeg"})
second = json.loads(raw).get("avatar_path", "")
check(status == 200 and second and second != avatar, "nouvelle photo de profil", raw[:200])
check(purge_and_wait("avatars", avatar), "l'ancienne photo de profil est effacée du stockage")
rpc("remove_avatar", {}, TA)
check(purge_and_wait("avatars", second), "photo de profil retirée : effacée du stockage")

# --- Expiration et effacement physique ----------------------------------------------
sql(f"update public.messages set sent_at = now() - interval '10 minutes', "
    f"expires_at = now() - interval '1 second' where id = '{msg['id']}'")
status, _ = http("GET", f"/storage/v1/object/authenticated/photos/{PATH}", token=TB)
check(status != 200, f"photo expirée : téléchargement refusé immédiatement ({status})")
sql("select private.purge_expired()")
check(purge_and_wait("photos", PATH), "photo expirée effacée du stockage par media-purge")
print("Test bout à bout des photos : OK")
