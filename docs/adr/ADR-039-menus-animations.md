# ADR-039 — Menus en carte flottante et animations

**Statut** : accepté (lot 8.5a, décisions du 16/11/2026 : A style 1 « carte flottante » ;
B « Voir plus » sur les menus longs, sauf l'appui long sur un message, inchangé ; C
animations discrètes et rapides).

## Décision
- **Menu commun** `PrivioMenu` (`lib/ui/core/widgets/privio_menu.dart`) : carte blanche
  arrondie posée au-dessus de toute l'application (navigateur racine), ouverte près du
  bouton ⋮ ou de l'élément appuyé, qui grandit depuis ce point (fondu + échelle, 260 ms).
  Chaque action a une icône dans une pastille de couleur (famille d'action) ; les actions
  dangereuses sont séparées, en rouge. Le menu s'ouvre du côté de l'écran où il tient.
- **« Voir plus »** : plus de 6 actions → les 5 premières, puis « Voir plus » qui déplie le
  reste dans la même carte.
- Utilisé pour : ⋮ des listes Discussions et Groupes, ⋮ d'une discussion ou d'un groupe,
  appui long sur une discussion de la liste, gestion d'un membre de groupe, ⋮ d'une demande
  de connexion. L'appui long sur un message n'a pas changé (décision B).
- **Barre d'une discussion** : la loupe est retirée (« Rechercher » est dans ⋮) ; seul le
  bouton pour fermer la recherche apparaît pendant une recherche.
- **Animations** (règles de l'ADR du lot 7.2b2 : courtes, coupées si le téléphone demande
  de réduire les animations) : lignes des listes Discussions et Groupes en cascade à
  l'ouverture, sections des Paramètres en cascade, cartes de réglages en fondu, changement
  d'onglet en fondu et léger glissement, menus animés ; transitions d'écran inchangées
  (glissement et fondu).
- **Listes** : lignes plus aérées (marge verticale 15 au lieu de 10), photos inchangées.
- **Paramètres** : « Supprimer mon compte » avant « Se déconnecter ».

## Preuves
`test/ui/menus_animations_test.dart` (4 cas) ; tests existants adaptés (`tapMenuItem` :
déplie « Voir plus » si besoin).
