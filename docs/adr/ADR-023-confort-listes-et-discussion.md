# ADR-023 — Confort : photo du groupe, onglet Groupes, repère des non lus, bouton « descendre »

**Statut** : accepté (lot 7.2c1, décisions du 14/11/2026, amendement 16).

## Contexte
La photo d'un groupe ne se changeait qu'en touchant la photo de la fiche (geste introuvable,
et impossible de l'ajouter à la création). L'onglet Groupes n'avait ni recherche, ni filtres,
ni actions rapides. Une discussion s'ouvrait toujours en bas, sans montrer où commencent les
messages non lus.

## Décision
- Photo du groupe : bouton « Ajouter une photo » / « Changer la photo » et pastille appareil
  photo pour ceux qui peuvent modifier les infos du groupe (administrateurs par défaut) ; à la
  création, la photo est choisie à côté du nom et envoyée juste après la création (un échec
  n'annule pas le groupe). Aucun changement côté serveur (`set_group_avatar` existant).
- Onglet Groupes : mêmes composants que Discussions (`ListSearchField`, `FilterBar`,
  `FilterPill`, `matchesSearch`) ; filtres Tous / Non lus / Épinglés ; « Archivés (n) » ouvre
  les archives des groupes (`/archived?kind=groupes`) ; séparés, les groupes archivés ne
  comptent plus dans « Archivées » de Discussions.
- Actions rapides : `SwipeableConversationTile` pour les groupes ; l'appui long propose
  « Quitter et supprimer » (`confirmLeaveGroup`, partagé avec la fiche) et, pour le créateur
  et les administrateurs, « Supprimer le groupe pour tous » (`chooseDelete`).
- Repère des non lus : le nombre de non lus est pris à l'ouverture ; la ligne se place avant
  le n-ième dernier message reçu arrivé avant l'ouverture, et la discussion s'y place s'il
  n'est pas déjà à l'écran. Il reste jusqu'à la sortie de la discussion.
- Bouton « descendre » : visible au-delà de 320 px au-dessus du bas ; compte les messages
  reçus pendant ce temps ; disparaît en bas.

## Preuves
Tests Flutter `test/ui/confort_test.dart` (11 cas), suite complète 379 tests ; captures du
lot. Le double du serveur des tests tient maintenant compte du « lu » pour les non lus et
des états épinglé / archivé de chaque groupe.
