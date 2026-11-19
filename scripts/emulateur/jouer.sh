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

# Démarrage à froid de la vraie application (mode profile, comme une version publiée) :
# du lancement du processus au premier écran dessiné, noté par l'application elle-même.
echo "### Android $VERSION — vitesse (émulateur d'entrée de gamme, mode profile)" >> "$RESUME"
flutter build apk --profile --target-platform android-x64 "${DEFINES[@]}"
adb -s "$DEVICE" uninstall com.privio.app >/dev/null 2>&1 || true
adb -s "$DEVICE" install -r build/app/outputs/flutter-apk/app-profile.apk >/dev/null
temps=()
for essai in 1 2 3 4; do
  adb -s "$DEVICE" shell am force-stop com.privio.app
  sleep 3
  adb -s "$DEVICE" logcat -c
  adb -s "$DEVICE" shell am start -n com.privio.app/.MainActivity >/dev/null
  ms=""
  for _ in $(seq 1 60); do
    ms=$(adb -s "$DEVICE" logcat -d -s flutter:I | grep -a 'Privio' | grep -aoE '[0-9]+ ms' | tail -1 | grep -oE '[0-9]+' || true)
    [ -n "$ms" ] && break
    sleep 0.5
  done
  echo "Démarrage à froid n° $essai : ${ms:-?} ms"
  temps+=("${ms:-99999}")
done
# Le 1er lancement suit l'installation (préparation du code par Android) : médiane des 3 suivants.
mediane=$(printf '%s\n' "${temps[@]:1}" | sort -n | sed -n 2p)
echo "| Démarrage à froid → premier écran (médiane de 3 ; 1er lancement : ${temps[0]} ms) | $mediane ms | < 3 000 ms |" > build/demarrage.md
demarrage=0
if [ "$mediane" -ge 3000 ]; then
  echo "::error::Démarrage à froid trop lent sur Android $VERSION : $mediane ms (seuil 3 000 ms)"
  demarrage=1
fi

# Mesures dans l'application : neuve (aucune session du parcours précédent).
adb -s "$DEVICE" uninstall com.privio.app >/dev/null 2>&1 || true
statut=0
mkdir -p build && rm -f build/mesures.json
set +e
flutter drive --profile -d "$DEVICE" "${DEFINES[@]}" \
  --driver=test_driver/mesures.dart --target=integration_test/vitesse_test.dart \
  2>&1 | tee build/drive.log
statut=${PIPESTATUS[0]}
set -e
# Seuil dépassé : le pilote ne publie rien, les mesures sont reprises du journal.
if [ ! -f build/mesures.json ]; then
  grep -o 'MESURES {.*}' build/drive.log | tail -1 | sed 's/^MESURES //' > build/mesures.json || true
  [ -s build/mesures.json ] || rm -f build/mesures.json
fi
if [ -f build/mesures.json ]; then
  python3 - build/mesures.json >> "$RESUME" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])).get("mesures", {})
def ligne(nom, cle, seuil):
    v = m.get(cle)
    if v is None: return f"| {nom} | — | {seuil} |"
    return f"| {nom} | {v} ms | {seuil} |"
print("| Mesure | Résultat | Seuil |\n|---|---|---|")
print(open("build/demarrage.md").read().strip())
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
else
  { echo "| Mesure | Résultat | Seuil |"; echo "|---|---|---|"; cat build/demarrage.md; } >> "$RESUME"
fi
[ "$parcours" -eq 0 ] || exit "$parcours"
[ "$demarrage" -eq 0 ] || exit 1
exit $statut
