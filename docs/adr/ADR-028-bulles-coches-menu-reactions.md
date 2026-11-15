# ADR-028 — Bulles à queue, coches « lu », menu ⋮, liste des réactions

**Statut** : accepté (lot 8.1b, décisions du 15/11/2026 : A bulle à queue et arrondis 10,
B jaune doux, C menus, D liste des réactions, E découpage 8.1b / 8.1c). Remplace, pour la
photo de l'auteur, la règle du lot 7.2b2 (« dernier message d'une suite »).

## Décision
- **Photo de l'auteur** : en haut à gauche du **premier** message d'une suite (même auteur,
  même jour) ; les suivants n'en ont pas et restent alignés.
- **Bulle** (`BubbleShape`) : arrondis de 10 ; le premier message d'une suite porte une
  queue de 8 × 10 en haut, du côté de l'auteur, et ce coin est pointu. La place de la queue
  est toujours réservée, pour l'alignement. Autocollants, GIF et grands émojis : sans bulle
  ni queue. L'ombre, l'effet d'appui et le contour d'échec suivent la forme.
- **Coches « lu »** : jaune doux `#FFD84D` (`PrivioColors.readTick`) sur la bulle violette
  — contraste 6,5:1 (clair) et 4,7:1 (sombre), couleur opposée au violet ; « envoyé » et
  « reçu » restent en blanc translucide. Sur un autocollant ou un GIF (pastille claire),
  « lu » reste violet.
- **Menu ⋮** : à deux — Voir la fiche, Rechercher, Médias, Messages favoris, Durée des
  messages, Sourdine / Réactiver, Fond d'écran, Vider, Bloquer, Signaler ; groupe — Infos du
  groupe, Rechercher, Médias, Messages favoris, Notifications (sourdine, mentions
  seulement), Fond d'écran, Inviter (administrateurs), Vider, Quitter le groupe, Signaler.
  Chaque entrée réutilise l'action existante (mêmes confirmations, mêmes règles serveur).
- **Réactions** : appui simple sur une réaction → liste « Toutes (n) » puis un onglet par
  émoji (photo, nom ; « Vous » en tête, toucher pour retirer) ; double appui → ajouter ou
  retirer ma réaction. Le lecteur d'écran propose l'action « Réagir » / « Retirer ».

## Preuves
Tests Flutter `test/ui/bulles_menu_test.dart` (7 cas), `chat_actions_test.dart` et
`animations_sons_test.dart` mis à jour ; suite complète 430 tests ; captures.
