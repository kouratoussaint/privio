# ADR-046 — Mode éco

**Statut** : accepté (lot 10.3, décisions A–I du 16/11/2026).

## Décision
- **Un interrupteur (A, B, I)** : « Mode éco » en haut de Paramètres → Stockage et données,
  activé **à la main seulement** (aucune bascule automatique selon le réseau), gardé sur le
  téléphone (`LocalFlags.ecoMode`). Tant qu'il est actif, une feuille verte s'affiche en haut
  de Discussions ; la toucher ouvre le réglage.
- **Photos envoyées (C)** : 1 024 px au plus, JPEG qualité 65 (au lieu de 1 600 px,
  qualité 80) — environ 2 à 3 fois plus légères. Les retouches (pivoter, recadrer, dessiner)
  réencodent avec la qualité de la photo (`PreparedPhoto.quality`).
- **Vocaux envoyés (D)** : AAC 16 kb/s au lieu de 32 kb/s (même fréquence, voix claire).
- **Réception (E)** : photos, vocaux et GIF téléchargés seulement au toucher ; le choix
  « téléchargement automatique des photos » est suspendu (grisé) tant que le mode est actif.
  Photos de profil et autocollants restent affichés (petits, ou intégrés à l'application).
- **GIF et aperçus (F)** : onglet GIF masqué ; GIF reçus en « GIF · toucher pour afficher » ;
  aucun aperçu de lien demandé à l'envoi ni affiché à la réception — le lien reste cliquable.
- **Appels (G)** : vidéo toujours en image réduite (≈ 360p), même en Wi-Fi.
- **Consommation (H)** : en haut de l'écran, ce mois-ci et le mois précédent ; détail par
  type (photos, vocaux, GIF, appels — octets mesurés par la liaison à la fin de l'appel —,
  autres) ; « Économisé ce mois-ci », **estimation** : envois allégés (photo ≈ 1,5 fois sa
  taille, vocal 1 fois) et téléchargements évités (photo selon ses dimensions, GIF
  ≈ 300 Kio), retirés si la personne télécharge finalement le média.

## Limites
- L'économie affichée est une estimation, pas une mesure de l'opérateur.
- Les médias reçus déjà sur le téléphone restent affichés.

## Preuves
`test/ui/mode_eco_test.dart` (4 cas : activation et feuille verte, réception au toucher et
économie comptée puis retirée, onglet GIF masqué et aucun aperçu, photo allégée),
`test/ui/appels_video_test.dart` (image réduite en Wi-Fi, données de l'appel comptées),
`test/ui/data_saving_test.dart` adapté (détail par type).
