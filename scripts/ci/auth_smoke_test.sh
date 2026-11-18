#!/usr/bin/env bash
# Test d'intégration RÉEL contre un Supabase local (supabase start) :
# Auth téléphone (numéros de test), trigger de synchronisation du numéro, RPC, RLS,
# révocation de session par un second appareil, inscription e-mail refusée.
set -euo pipefail
eval "$(supabase status -o env 2>/dev/null)"
API="${API_URL:?API_URL introuvable}"
KEY="${PUBLISHABLE_KEY:-${ANON_KEY:?clé publique introuvable}}"
PHONE="+22670000001"
pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; echo "   $2"; exit 1; }
post() { # post <chemin> <json> [jeton]
  local auth=(); [ -n "${3:-}" ] && auth=(-H "Authorization: Bearer $3")
  curl -sS -X POST "$API$1" -H "apikey: $KEY" -H "Content-Type: application/json" "${auth[@]}" -d "$2"
}
login() { # login [numéro]
  local phone="${1:-$PHONE}"
  post /auth/v1/otp "{\"phone\":\"$phone\"}" >/dev/null
  post /auth/v1/verify "{\"type\":\"sms\",\"phone\":\"$phone\",\"token\":\"123456\"}" \
    | python3 -c 'import sys,json; print(json.load(sys.stdin).get("access_token",""))'
}

R=$(post /auth/v1/signup '{"email":"x@example.com","password":"Motdepasse123!"}')
echo "$R" | grep -qiE 'disabled|not allowed|signup' && pass "inscription par e-mail refusée" \
  || fail "inscription par e-mail refusée" "$R"

T1=$(login); [ -n "$T1" ] && pass "connexion OTP (numéro de test) → session" || fail "connexion OTP" "pas de jeton"

R=$(post /rest/v1/rpc/get_my_account '{}' "$T1")
echo "$R" | grep -q '"phone_e164" *: *"+22670000001"' && pass "numéro vérifié synchronisé (trigger auth.users)" \
  || fail "synchronisation du numéro" "$R"

R=$(post /rest/v1/rpc/create_profile '{"p_handle":"Smoke_Test","p_display_name":"Test CI"}' "$T1")
echo "$R" | grep -q 'smoke_test' && pass "création de profil (identifiant normalisé)" || fail "create_profile" "$R"

R=$(post /rest/v1/rpc/register_device '{"p_platform":"android","p_app_version":"ci"}' "$T1")
echo "$R" | grep -qE '^"[0-9a-f-]{36}"$' && pass "appareil 1 enregistré" || fail "register_device 1" "$R"

T2=$(login)
R=$(post /rest/v1/rpc/register_device '{"p_platform":"android","p_app_version":"ci"}' "$T2")
echo "$R" | grep -qE '^"[0-9a-f-]{36}"$' && pass "appareil 2 enregistré" || fail "register_device 2" "$R"

R=$(post /rest/v1/rpc/get_my_account '{}' "$T1")
echo "$R" | grep -q 'AUTH_REQUIRED' && pass "appareil 1 révoqué : accès refusé malgré un jeton non expiré" \
  || fail "révocation de l'appareil 1" "$R"

R=$(post /rest/v1/rpc/get_my_account '{}' "$T2")
echo "$R" | grep -q 'smoke_test' && pass "appareil 2 actif" || fail "appareil 2" "$R"

R=$(post /rest/v1/rpc/get_my_account '{}')
echo "$R" | grep -qiE 'permission denied|42501|AUTH_REQUIRED' && pass "anonyme refusé sur les RPC" \
  || fail "accès anonyme" "$R"

R=$(curl -sS "$API/rest/v1/profiles?select=*" -H "apikey: $KEY")
echo "$R" | grep -qiE 'permission denied|42501|\[\]' && pass "anonyme : aucune lecture de profils" \
  || fail "lecture anonyme des profils" "$R"

# ---------------- Lot 2.1 : échange réel entre deux comptes ----------------
json() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }
TB=$(login +22670000002); [ -n "$TB" ] && pass "second compte connecté" || fail "second compte" "pas de jeton"
post /rest/v1/rpc/create_profile '{"p_handle":"smoke_peer","p_display_name":"Pair CI"}' "$TB" >/dev/null
post /rest/v1/rpc/register_device '{"p_platform":"android","p_app_version":"ci"}' "$TB" >/dev/null

PEER=$(post /rest/v1/rpc/find_user_by_handle '{"p_handle":"smoke_peer"}' "$T2" | json "d[0]['id']")
# Lot 4.7 : premier contact par demande de connexion, acceptée par le destinataire.
R=$(post /rest/v1/rpc/start_direct_conversation "{\"p_other_user_id\":\"$PEER\"}" "$T2")
echo "$R" | grep -q 'CONNECTION_REQUIRED' && pass "pas d'écriture directe à un inconnu" \
  || fail "écriture directe refusée" "$R"
REQ=$(post /rest/v1/rpc/send_connection_request "{\"p_user_id\":\"$PEER\"}" "$T2" | json "d[0]['request_id']")
echo "$REQ" | grep -qE '^[0-9a-f-]{36}$' && pass "demande de connexion envoyée" || fail "send_connection_request" "$REQ"
CONV=$(post /rest/v1/rpc/respond_connection_request "{\"p_request_id\":\"$REQ\",\"p_action\":\"accept\"}" "$TB" \
  | json "d[0]['conversation_id']")
echo "$CONV" | grep -qE '^[0-9a-f-]{36}$' && pass "demande acceptée : discussion ouverte" \
  || fail "respond_connection_request" "$CONV"

R=$(post /rest/v1/rpc/send_message "{\"p_conversation_id\":\"$CONV\",\"p_client_msg_id\":\"44444444-4444-4444-4444-444444444444\",\"p_body\":\"Bonjour depuis la CI\"}" "$T2")
MID=$(echo "$R" | json "d[0]['id']"); EXP=$(echo "$R" | json "d[0]['expires_at']")
[ -n "$MID" ] && pass "message envoyé (expire le $EXP)" || fail "send_message" "$R"

R=$(post /rest/v1/rpc/get_messages "{\"p_conversation_id\":\"$CONV\"}" "$TB")
echo "$R" | grep -q "Bonjour depuis la CI" && pass "le destinataire lit le message" || fail "get_messages" "$R"
R=$(post /rest/v1/rpc/list_conversations '{}' "$TB" | json "d[0]['unread_count']")
[ "$R" = "1" ] && pass "1 message non lu chez le destinataire" || fail "non lus" "$R"
R=$(post /rest/v1/rpc/edit_message "{\"p_message_id\":\"$MID\",\"p_body\":\"x\"}" "$TB")
echo "$R" | grep -q 'NOT_SENDER' && pass "le destinataire ne peut pas modifier le message" || fail "NOT_SENDER" "$R"
R=$(curl -sS "$API/rest/v1/messages?select=body" -H "apikey: $KEY")
echo "$R" | grep -qiE 'permission denied|42501' && pass "anonyme : aucune lecture de messages" || fail "lecture anonyme des messages" "$R"
python3 "$(dirname "$0")/realtime_e2e.py" "$API" "$KEY" "$T2" "$TB" "$CONV"
python3 "$(dirname "$0")/voice_e2e.py" "$API" "$KEY" "$T2" "$TB" "$CONV" "${DB_URL:?DB_URL introuvable}"
python3 "$(dirname "$0")/photo_e2e.py" "$API" "$KEY" "$T2" "$TB" "$CONV" "$DB_URL"
python3 "$(dirname "$0")/group_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
python3 "$(dirname "$0")/push_e2e.py" "$API" "$KEY" "$T2" "$TB" "$CONV" "$DB_URL"
python3 "$(dirname "$0")/privacy_e2e.py" "$API" "$KEY" "$T2" "$TB" "$CONV" "$DB_URL"
python3 "$(dirname "$0")/connection_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
python3 "$(dirname "$0")/invitation_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
python3 "$(dirname "$0")/join_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
python3 "$(dirname "$0")/finitions_e2e.py" "$API" "$KEY" "$T2" "$TB" "$CONV"
python3 "$(dirname "$0")/suppression_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
python3 "$(dirname "$0")/confort_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
python3 "$(dirname "$0")/expression_e2e.py" "$API" "$KEY" "$T2" "$TB" "$CONV" "$DB_URL"
python3 "$(dirname "$0")/appels_e2e.py" "$API" "$KEY" "$T2" "$TB" "$CONV" "$DB_URL"
python3 "$(dirname "$0")/console_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
python3 "$(dirname "$0")/moderation_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
# Lot 8.1c : changement de numéro (numéros de test 004 et 005, comptes indépendants).
python3 "$(dirname "$0")/numero_e2e.py" "$API" "$KEY" "$DB_URL"
python3 "$(dirname "$0")/deux_etapes_e2e.py" "$API" "$KEY" "$DB_URL"
# Lot 5.7 : santé du service (après les connexions, les appels et le changement de numéro).
python3 "$(dirname "$0")/sante_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
# Lot 10.4 : vérification en personne et surnom privé (rétablit l'état de B à la fin).
python3 "$(dirname "$0")/verification_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
# Lot 7.4 : autocollants personnels (Storage, fonction « sticker »).
python3 "$(dirname "$0")/stickers_e2e.py" "$API" "$KEY" "$T2" "$TB" "$CONV" "$DB_URL"
# Lot 10.5 : groupes « Annonces » et sondages éphémères.
python3 "$(dirname "$0")/annonces_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
# Lot 9.4 : appels de groupe (temps réel, fonction « call-sfu »).
python3 "$(dirname "$0")/appels_groupe_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
# Dernier : déconnecte le téléphone de B.
python3 "$(dirname "$0")/support_e2e.py" "$API" "$KEY" "$T2" "$TB" "$DB_URL"
echo "Test d'intégration Auth/RPC/messagerie/temps réel/vocaux/photos/groupes/notifications/confidentialité/demandes de connexion/invitations/codes et mentions/finitions/suppression/console/modération/assistance/santé du service/vérification en personne/annonces et sondages/autocollants personnels/appels de groupe : OK"
