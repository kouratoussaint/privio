#!/usr/bin/env python3
"""Test bout à bout du lot 7.2a contre un Supabase local COMPLET (PostgREST réel) :
nom affiché modifiable, confidentialité propre à une discussion (accusés de lecture,
en ligne, photo) vue depuis l'autre compte.

Usage : finitions_e2e.py <API_URL> <CLÉ_PUBLIQUE> <JETON_A> <JETON_B> <CONVERSATION>
"""
import json
import sys
import urllib.error
import urllib.request

API, KEY, TA, TB, CONV = sys.argv[1:6]


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
        return e.code, (json.loads(raw) if raw else None)


def conv_of(token):
    _, rows = rpc("list_conversations", {}, token)
    return next(c for c in rows if c["conversation_id"] == CONV)


A = rpc("get_my_account", {}, TA)[1]
_, prof = rpc("get_contact_profile", {"p_user_id": A["user_id"]}, TB)
original = prof[0]["display_name"]

# --- Nom affiché ---------------------------------------------------------------------
status, new = rpc("set_my_display_name", {"p_display_name": "  Alice   CI "}, TA)
check(status == 200 and new == "Alice CI", "A change son nom (espaces nettoyés)", new)
check(conv_of(TB)["peer_display_name"] == "Alice CI", "B voit le nouveau nom dans sa liste")
status, err = rpc("set_my_display_name", {"p_display_name": "x" * 41}, TA)
check(status == 400 and err.get("message") == "DISPLAY_NAME_INVALID", "41 caractères : refusé", err)
rpc("set_my_display_name", {"p_display_name": original}, TA)

# --- Confidentialité de la discussion ------------------------------------------------
rpc("mark_conversation", {"p_conversation_id": CONV, "p_read_up_to": "2099-01-01T00:00:00Z"}, TA)
status, _ = rpc("set_conversation_privacy", {"p_conversation_id": CONV, "p_read_receipts": False,
                                             "p_typing_indicator": None, "p_show_presence": False,
                                             "p_show_avatar": False, "p_show_about": None}, TA)
check(status in (200, 204), "A coupe accusés, en ligne et photo pour cette discussion")
_, mine = rpc("get_conversation_privacy", {"p_conversation_id": CONV}, TA)
check(mine[0]["read_receipts"] is False and mine[0]["show_presence"] is False
      and mine[0]["typing_indicator"] is None, "réglages relus", mine)
c = conv_of(TB)
check(c["peer_read_up_to"] is None, "B ne voit plus quand A a lu", c)
check(c["peer_avatar_path"] is None, "B ne voit plus la photo de A")
_, pres = rpc("get_presence", {"p_user_id": A["user_id"]}, TB)
check(pres[0]["visible"] is False, "B ne voit plus « en ligne / vu à » de A", pres)

status, _ = rpc("set_conversation_privacy", {"p_conversation_id": CONV, "p_read_receipts": None,
                                             "p_typing_indicator": None, "p_show_presence": True,
                                             "p_show_avatar": None, "p_show_about": None}, TA)
_, pres = rpc("get_presence", {"p_user_id": A["user_id"]}, TB)
check(pres[0]["visible"] is True, "montré à B (exception) : B voit « en ligne / vu à »", pres)
rpc("set_conversation_privacy", {"p_conversation_id": CONV, "p_read_receipts": None,
                                 "p_typing_indicator": None}, TA)
_, mine = rpc("get_conversation_privacy", {"p_conversation_id": CONV}, TA)
check(all(v is None for v in mine[0].values()), "retour à « comme dans mes réglages »", mine)
print("Lot 7.2a (nom, confidentialité par discussion) : OK")
