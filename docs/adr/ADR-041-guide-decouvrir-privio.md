# ADR-041 — Guide « Découvrir Privio »

**Statut** : accepté (lot 8.5c, décision F du 16/11/2026 : guide après la création du
compte, montré aussi une fois aux testeurs existants, avec images et icônes animées,
accessible dans Paramètres).

## Décision
- **6 écrans** à faire défiler (`DiscoverScreen`, route `/discover`) : Bienvenue ; Démarrer
  une discussion ; Vos messages s'effacent ; Les groupes ; Appels audio et vidéo ; Votre
  protection. Chaque écran : grand disque coloré avec l'icône de la fonction, un **émoji
  animé** (parmi les 150 intégrés, ADR-040), deux **petites icônes animées** autour ; titre et
  texte apparaissent en fondu ; fond et bouton prennent la couleur de l'écran ; points de
  progression animés. « Passer » en haut, « Suivant » puis « C'est parti ».
- **Quand** : à la première arrivée sur l'accueil après la connexion (nouveau compte ou
  compte existant), une seule fois (`LocalFlags.discoverSeen`, marqué dès l'ouverture),
  avant la proposition d'affichage plein écran des appels. Ensuite : Paramètres › Aide ›
  « Découvrir Privio ».
- Les textes ne promettent rien sur le chiffrement (décision du 15/11/2026) et ne
  décrivent que ce qui existe.

## Preuves
`test/ui/guide_test.dart` (montré une fois, 6 écrans, « Passer », déjà vu, accès depuis
Aide, glisser).
