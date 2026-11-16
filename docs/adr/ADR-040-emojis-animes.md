# ADR-040 — Émojis animés et grands

**Statut** : accepté (lot 8.5b, décisions du 16/11/2026 : D Noto Animated Emoji, 150 émojis
intégrés ; E grands quand le message n'a que 1, 2 ou 3 émojis, l'animation joue 2 fois puis
s'arrête, toucher la rejoue).

## Décision
- **Source** : Noto Animated Emoji (Google), licence CC BY 4.0. Les 150 émojis les plus
  utilisés sont **copiés dans l'application** (`assets/emoji/<code>.json`, animations Lottie,
  ~8,6 Mo de JSON, ~1 Mo compressé dans l'APK). **Rien n'est téléchargé** pendant
  l'utilisation : Google ne voit pas quels émojis s'affichent, aucune donnée consommée.
  Le paquet `animated_emoji` (qui télécharge les émojis manquants chez Google) n'est **pas**
  utilisé ; seul `lottie` lit les fichiers.
- Correspondance émoji → fichier : `lib/ui/core/emoji/animated_emoji_assets.g.dart` (clé =
  points de code sans le sélecteur U+FE0F, pour que ❤ et ❤️ se retrouvent).
- **Affichage** (`BigEmojisText`) : message de 1, 2 ou 3 émojis seuls → 96, 72 ou 56 points
  par émoji. Animé s'il fait partie des 150, sinon fixe en grand. Lecture 2 fois puis arrêt ;
  toucher l'émoji la rejoue. « Réduire les animations » du téléphone : image fixe.
- **Crédit** : Aide › Licences (`showLicensePage`), entrée « Noto Animated Emoji » ;
  `assets/emoji/LICENSE.txt`.

## Preuves
`test/ui/emojis_animes_test.dart` (fichiers présents et lisibles, reconnaissance avec ou sans
U+FE0F, tailles 1 > 2 > 3, émoji non animé fixe) ; `expression_test.dart` adapté.
