#!/usr/bin/env bash
# Lot 6.1 : réduit les polices Inter de l'application aux alphabets utiles (latin étendu,
# dont mooré et dioula : ɛ ɔ ɲ ŋ ʋ ɩ, tons et nasales ; ponctuation française ; symboles).
# Les caractères absents (autres écritures) s'affichent avec la police du téléphone.
# Usage : tools/fonts/subset_inter.sh <dossier des polices Inter d'origine>
# Prérequis : pip install fonttools
set -euo pipefail
src=${1:?dossier des polices Inter d’origine}
dst="$(dirname "$0")/../../apps/mobile/assets/fonts"
ranges="U+0000-00FF,U+0100-024F,U+0250-02AF,U+02B0-02FF,U+0300-036F,U+1E00-1EFF,U+2000-206F,\
U+20A0-20CF,U+2100-214F,U+2190-21FF,U+2200-22FF,U+2460-24FF,U+25A0-25FF,U+2600-26FF,U+FB00-FB06"
for w in Regular Medium SemiBold Bold; do
  pyftsubset "$src/Inter-$w.ttf" --output-file="$dst/Inter-$w.ttf" --unicodes="$ranges" \
    --layout-features='*' --name-IDs='*' --name-legacy --notdef-outline
done
