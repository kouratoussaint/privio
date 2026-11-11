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
login() {
  post /auth/v1/otp "{\"phone\":\"$PHONE\"}" >/dev/null
  post /auth/v1/verify "{\"type\":\"sms\",\"phone\":\"$PHONE\",\"token\":\"123456\"}" \
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
echo "Test d'intégration Auth/RPC : OK"
