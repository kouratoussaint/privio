#!/usr/bin/env bash
# Garde-fous de conformité PRIVIO, exécutés en CI à chaque push / PR.
# Chaque règle traduit une décision du dossier ; un échec bloque la fusion.
set -uo pipefail
cd "$(dirname "$0")/.."
FAIL=0
check() { # check "<description>" <commande qui doit ne rien afficher>
  local desc="$1"; shift
  local out; out="$("$@" 2>/dev/null || true)"
  if [ -n "$out" ]; then echo "❌ $desc"; echo "$out" | sed 's/^/   /'; FAIL=1; else echo "✅ $desc"; fi
}
PRODUCT_CODE="apps/mobile/lib apps/mobile/android/app/src supabase/migrations supabase/functions apps/admin/src packages/contracts"
existing() { for d in $PRODUCT_CODE; do [ -e "$d" ] && echo "$d"; done; }

check "Aucune « communauté » dans le code produit (décision définitive)" \
  grep -rniE "communaut|communit" $(existing)

check "Aucune authentification par e-mail ou mot de passe dans l'application" \
  grep -rnE "signInWithPassword|signUp\(|email:|OtpType\.email|OtpType\.magiclink" apps/mobile/lib

check "Jamais de « supabase config push » (recopierait les OTP de test vers un projet hébergé)" \
  grep -rn "config push" .github scripts --include=*.yml --include=*.yaml --include=*.sh --exclude=guards.sh

check "Numéros OTP de test uniquement dans supabase/config.toml (local)" \
  bash -c "grep -rln 'test_otp' --include=*.toml --include=*.env --include=*.json . | grep -v '^./supabase/config.toml$'"

check "Aucune clé secrète Supabase ni service-role dans l'application" \
  bash -c "grep -rnE 'service_role|sb_secret_|SERVICE_ROLE' apps/mobile/lib apps/mobile/android/app/src | grep -v 'apps/mobile/lib/core/config/env.dart'"

check "Aucun fichier sensible versionné (keystore, google-services.json, .env)" \
  bash -c "git ls-files | grep -E '\.(jks|keystore|p12|pem)$|google-services\.json$|(^|/)\.env$' || true"

check "Aucune promesse de chiffrement de bout en bout dans l'interface (décision du 11/11/2026)" \
  grep -rniE "bout en bout|end-to-end|e2ee" apps/mobile/lib

check "FLAG_SECURE présent dans MainActivity" \
  bash -c "grep -q 'FLAG_SECURE' apps/mobile/android/app/src/main/kotlin/com/privio/app/MainActivity.kt || echo 'FLAG_SECURE absent'"

check "Sauvegardes Android désactivées" \
  bash -c "grep -q 'android:allowBackup=\"false\"' apps/mobile/android/app/src/main/AndroidManifest.xml || echo 'allowBackup non désactivé'"

check "Médias : aucune URL publique ou signée dans l'application (lecture avec le jeton uniquement)" \
  grep -rnE "getPublicUrl|createSignedUrl" apps/mobile/lib

check "Médias : aucun bucket Storage public dans les migrations" \
  bash -c "grep -rniE \"insert into storage.buckets\" -A2 supabase/migrations | grep -iE \"'[a-z_]+', *true\" || true"

check "Clé de service uniquement dans les fonctions serveur (jamais dans l'app ni la console)" \
  bash -c "grep -rln 'SUPABASE_SERVICE_ROLE_KEY\|SUPABASE_SECRET_KEYS' apps packages 2>/dev/null || true"

exit $FAIL
