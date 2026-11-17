#!/usr/bin/env python3
"""Test bout à bout des autocollants personnels (lot 7.4) contre un Supabase local COMPLET
(base, Storage, fonction « sticker ») :
  1. A crée un autocollant partageable et un privé (PNG) ; un fichier trop grand ou qui
     n'est pas une image est refusé ; la collection n'est lisible que par A ;
  2. A envoie les deux à B : chaque message a sa propre copie, lisible par B ;
  3. B ajoute l'autocollant partageable à sa collection, pas le privé ;
  4. A retire un autocollant de sa collection : le message déjà envoyé reste lisible ;
  5. message expiré : sa copie n'est plus lisible.

Usage : stickers_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <CONVERSATION> <DB_URL>
"""
import json
import struct
import subprocess
import sys
import urllib.error
import urllib.request
import uuid
import zlib

API, KEY, TA, TB, CONV, DB = sys.argv[1:7]


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


def fn(query, token, body=b""):
    status, raw = http("POST", f"/functions/v1/sticker?{query}", body, token,
                       {"Content-Type": "application/octet-stream"})
    try:
        return status, json.loads(raw) if raw else None
    except ValueError:
        return status, raw.decode(errors="replace")


def rpc(name, params, token):
    status, raw = http("POST", f"/rest/v1/rpc/{name}", params, token)
    return status, (json.loads(raw) if raw else None)


def sql(query):
    return subprocess.run(["psql", DB, "-tAc", query], check=True, capture_output=True,
                          text=True).stdout.strip()


def png(size, rgba=(120, 40, 200, 255)):
    """PNG RGBA valide, couleur unie (fond transparent sur les bords)."""
    rows = b""
    for y in range(size):
        rows += b"\x00"
        for x in range(size):
            edge = x < 4 or y < 4 or x >= size - 4 or y >= size - 4
            rows += bytes((0, 0, 0, 0)) if edge else bytes(rgba)
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def read(path, token):
    return http("GET", f"/storage/v1/object/authenticated/stickers/{path}", token=token)


# ------------------------------------------------------------------ 1. Collection
status, r = fn("action=add", TA, b"pas une image")
check(status == 422 and r.get("error") == "MEDIA_INVALID", "fichier qui n'est pas une image : refusé", r)
status, r = fn("action=add", TA, png(600))
check(status == 422 and r.get("error") == "MEDIA_INVALID", "image de plus de 512 px : refusée", r)
status, S1 = fn("action=add&shareable=1", TA, png(256))
check(status == 200 and S1.get("shareable") is True and S1.get("width") == 256,
      "A crée un autocollant partageable", S1)
status, S2 = fn("action=add", TA, png(128, (20, 160, 90, 255)))
check(status == 200 and S2.get("shareable") is False, "A crée un autocollant privé", S2)
status, mine = rpc("my_stickers", {}, TA)
check(status == 200 and {s["id"] for s in mine} >= {S1["id"], S2["id"]}, "A retrouve sa collection", mine)
status, body = read(S1["path"], TA)
check(status == 200 and body[:8] == b"\x89PNG\r\n\x1a\n", "A lit son fichier", status)
status, _ = read(S1["path"], TB)
check(status in (400, 403, 404), "B ne lit pas la collection de A", status)

# ------------------------------------------------------------------ 2. Envoi
def send(sticker_id):
    cm = str(uuid.uuid4())
    q = f"action=send&conversation_id={CONV}&client_msg_id={cm}&sticker_id={sticker_id}"
    status, r = fn(q, TA)
    status2, r2 = fn(q, TA)
    check(status == 200 and status2 == 200 and r["id"] == r2["id"], "envoi idempotent", (r, r2))
    return r


M1 = send(S1["id"])
check(M1["body"] == "perso/partageable" and M1["media_path"].startswith(f"msg/{CONV}/"),
      "autocollant partageable envoyé, avec sa propre copie", M1)
M2 = send(S2["id"])
check(M2["body"] == "perso/prive", "autocollant privé envoyé", M2)
status, msgs = rpc("get_messages", {"p_conversation_id": CONV}, TB)
got = {m["id"]: m for m in msgs}
check(M1["id"] in got and got[M1["id"]]["kind"] == "sticker" and got[M1["id"]]["media_width"] == 256,
      "B reçoit l'autocollant", got.get(M1["id"]))
status, body = read(M1["media_path"], TB)
check(status == 200 and body[:4] == b"\x89PNG", "B lit l'autocollant reçu", status)

# ------------------------------------------------------------------ 3. Ajouter à sa collection
status, r = fn(f"action=save&message_id={M2['id']}", TB)
check(status == 403 and r.get("error") == "STICKER_NOT_SHAREABLE", "autocollant privé : pas d'ajout", r)
status, SB = fn(f"action=save&message_id={M1['id']}", TB)
_, me_b = http("GET", "/auth/v1/user", token=TB)
check(status == 200 and SB["path"].startswith(json.loads(me_b)["id"] + "/"),
      "B ajoute l'autocollant partageable à sa collection", SB)
status, body = read(SB["path"], TB)
check(status == 200 and body[:4] == b"\x89PNG", "B lit sa copie", status)

# ------------------------------------------------------------------ 4. Retirer de la collection
status, r = fn(f"action=remove&id={S1['id']}", TA)
check(status == 200, "A retire un autocollant de sa collection", r)
status, _ = read(S1["path"], TA)
check(status in (400, 404), "fichier de la collection effacé", status)
status, _ = read(M1["media_path"], TB)
check(status == 200, "le message déjà envoyé reste lisible", status)

# ------------------------------------------------------------------ 5. Expiration
sql(f"update public.messages set sent_at = now() - interval '2 hours', "
    f"expires_at = now() - interval '1 second' where id = '{M2['id']}'")
status, _ = read(M2["media_path"], TB)
check(status in (400, 403, 404), "message expiré : copie illisible", status)

# Nettoyage : collections vidées.
fn(f"action=remove&id={S2['id']}", TA)
fn(f"action=remove&id={SB['id']}", TB)
print("Autocollants personnels (lot 7.4) : OK")
