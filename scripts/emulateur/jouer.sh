#!/usr/bin/env bash
# Lot 6.1 (ADR-055) : sur l'émulateur démarré par la CI, joue le parcours complet (mode
# debug) puis les mesures de vitesse (mode profile, comme une version publiée).
# Serveur : Supabase LOCAL de la CI, joint depuis l'émulateur à l'adresse 10.0.2.2.
set -euo pipefail
cd "$(dirname "$0")/../../apps/mobile"
: "${SB_KEY:?clé publique locale absente}"
DEVICE=${DEVICE:-emulator-5554}
DEFINES=(
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321
  --dart-define=SUPABASE_PUBLISHABLE_KEY="$SB_KEY"
  --dart-define=PRIVIO_ENV=local
)
RESUME=${GITHUB_STEP_SUMMARY:-/dev/null}
VERSION=$(adb -s "$DEVICE" shell getprop ro.build.version.release | tr -d '\r')

echo "### Android $VERSION — parcours complet" >> "$RESUME"
debut=$(date +%s)
parcours=0
flutter test integration_test/parcours_test.dart -d "$DEVICE" "${DEFINES[@]}" --reporter expanded || parcours=$?
if [ "$parcours" -eq 0 ]; then
  echo "✅ inscription, demande de connexion, message, photo, vocal, effacement, groupe, verrouillage ($(( $(date +%s) - debut )) s)" >> "$RESUME"
else
  echo "❌ parcours en échec (voir le journal de l'étape)" >> "$RESUME"
fi

# Mesures : application neuve (aucune session du parcours précédent).
adb -s "$DEVICE" uninstall com.privio.app >/dev/null 2>&1 || true
echo "### Android $VERSION — vitesse (émulateur d'entrée de gamme, mode profile)" >> "$RESUME"
statut=0
flutter drive --profile -d "$DEVICE" "${DEFINES[@]}" \
  --driver=test_driver/mesures.dart --target=integration_test/vitesse_test.dart || statut=$?
if [ -f build/mesures.json ]; then
  python3 - build/mesures.json >> "$RESUME" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])).get("mesures", {})
def ligne(nom, cle, seuil):
    v = m.get(cle)
    if v is None: return f"| {nom} | — | {seuil} |"
    return f"| {nom} | {v} ms | {seuil} |"
print("| Mesure | Résultat | Seuil |\n|---|---|---|")
print(ligne("Démarrage : moteur Flutter et Dart prêts", "demarrage_dart_ms", "(détail)"))
print(ligne("Démarrage : Privio initialisé (serveur, stockage sécurisé)", "demarrage_initialise_ms", "(détail)"))
print(ligne("Démarrage à froid → premier écran", "demarrage_ms", "< 3 000 ms"))
print(ligne("Connexion → liste de 300 discussions", "liste_300_ms", "(suivi)"))
print(ligne("Ouverture d'une discussion de 1 000 messages", "ouverture_1000_ms", "< 2 000 ms"))
for nom, cle in (("Défilement de 300 discussions", "defilement_300"),
                 ("Défilement de 1 000 messages", "defilement_1000")):
    d = m.get(cle) or {}
    print(f"| {nom} : 90 % des images construites en | {d.get('construction_p90_ms', '—')} ms "
          f"({d.get('images_hors_budget', '—')}/{d.get('images', '—')} hors budget, rendu p90 "
          f"{d.get('rendu_p90_ms', '—')} ms) | < 20 ms |")
PY
  cp build/mesures.json "$RUNNER_TEMP/mesures-android-$VERSION.json" 2>/dev/null || true
fi
[ "$parcours" -eq 0 ] || exit "$parcours"
exit $statut
