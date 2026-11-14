# ADR-025 — Émojis, autocollants Privio, retouche photo, fond d'écran

**Statut** : accepté (lot 7.3a, décisions du 14/11/2026, amendement 17).

## Décision
- **Émojis** : panneau `emoji_picker_flutter` (hors connexion, en français, émojis récents
  gardés sur le téléphone) à la place du clavier ; « Retour » le ferme d'abord. Un message
  de 1 à 3 émojis seuls s'affiche en grand, sans fond de bulle. Les réactions acceptent
  n'importe quel émoji (le serveur acceptait déjà 1 à 16 caractères sans lettre ni chiffre).
- **Autocollants** : 24 dessins originaux générés par `tools/autocollants/generer_autocollants.py`
  (aucune image tierce), intégrés à l'application en WebP (377 Ko au total). Nouveau type de
  message `sticker` dont le corps est le nom « série/nom » (vérifié par le serveur :
  `^[a-z0-9_]{1,40}/[a-z0-9_]{1,40}$`) : aucune image n'est envoyée ni stockée. RPC
  `send_sticker` (même parcours que le texte : file d'attente, reprise hors connexion) ; un
  autocollant ne se modifie pas (`messages_sticker_guard`), compte comme non lu, se cite,
  se supprime et reçoit des réactions. Un nom inconnu (série future) s'affiche comme
  « Autocollant indisponible — mettez Privio à jour ».
- **Retouche photo** : sur le téléphone, sur la photo déjà réduite et sans métadonnées
  (paquet `image`, dans un isolat) : pivoter d'un quart de tour, recadrer (poignées aux
  coins), dessiner (6 couleurs, annuler) ; les traits sont gravés avant un pivotement ou un
  recadrage ; le résultat reste un JPEG aux mêmes limites.
- **Fond d'écran** : préférences locales (`privio.wallpaper`, `privio.wallpaper.<id>`),
  valeurs `pattern:*`, `color:*` ou `photo:<chemin>` ; la photo est réduite puis copiée
  dans le dossier privé de l'application et n'est jamais envoyée ; l'ancienne photo est
  effacée quand on en change.

## Preuves
pgTAP `28_autocollants` ; `scripts/ci/confort_e2e.py` (autocollant par PostgREST réel) ;
tests Flutter `test/ui/expression_test.dart` (11 cas) ; suite complète 399 tests ; captures.
