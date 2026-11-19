# ADR-057 — Console : organisation et présentation harmonisées

**Statut** : accepté (lot 5.10, demande du 19/11/2026 : « incohérences sur l'organisation
des éléments et le design de certaines interfaces »).

## Constat (revue des 16 écrans de la console, captures)
- **Organisation** : menu de 15 rubriques sans regroupement, dans un ordre mêlant
  modération, suivi et configuration ; l'accueil n'affichait que 8 rubriques en tuiles
  (pas Réponses types, Sites sans aperçu, Suivi de la modération, Inscriptions, Pilotage,
  Équipe) ; carte « Signalements » en double avec sa tuile ; Pilotage et Réglages avec la
  même icône.
- **Couleurs** : chaque rubrique a sa couleur (menu, tuiles), mais les commandes de la
  plupart des rubriques restaient violettes ; Comptes (bleu), Journal (ardoise) et
  Réglages (une couleur par thème) faisaient chacun autrement.
- **Présentation** : quatre styles de titres de section ; trois styles de puces de filtre
  (dont une puce « Tout » du Journal qui paraissait désactivée) ; filtres des
  Signalements centrés sur deux lignes au-dessus d'une rangée coupée ; listes tantôt en
  cartes, tantôt nues (Groupes, Sites, Réponses types, Équipe) ; listes vides tantôt en
  grande illustration, tantôt en texte seul ; cartes vides affichées comme un simple trait
  (Fonctionnalités, Santé du service) ; index A–Z affiché sans aucun compte ; libellé
  « Durée de vie maximale d'un message : 72 h » coupé avant « : 72 h » ; boutons d'ajout de
  trois sortes (bouton plein, bouton « + » dans un titre, bouton contour).

## Décision
- **Trois parties**, dans le menu (titres) comme sur l'accueil (tuiles sous les mêmes
  titres, toutes les rubriques permises au rôle) : **Modération** (Signalements, Comptes,
  Groupes, Réponses types, Sites sans aperçu, Suivi de la modération), **Suivi du service**
  (Statistiques, Santé du service, Journal), **Configuration** (Fonctionnalités, Réglages,
  Inscriptions, Pilotage, Équipe). L'assistance ne voit que « Modération ». Carte
  « Signalements » en double retirée de l'accueil ; Pilotage prend une fusée.
- **Couleur de la rubrique** appliquée à toutes ses commandes (puces, boutons, barres,
  interrupteurs, champs, illustrations) par un thème propre à la rubrique
  (`consoleSectionTheme`), éclaircie en thème sombre ; plus de couleur codée par rubrique.
- **Une seule présentation** (`console_ui.dart`), celle des Paramètres : texte
  d'introduction ; titres de section en petites capitales (avec icône facultative) ;
  contenu en cartes (SettingsCard) ; rangées de filtres alignées qui défilent ; liste vide
  = ligne discrète dans sa carte (grande illustration seulement pour une page de liste
  entière) ; actions d'ajout en bouton contour sous la liste ; jamais de carte vide.
- Corrections : index A–Z masqué sans compte ; libellés « … : valeur » des engagements
  scindés (titre, puis valeur et mention) ; liste des Groupes, des Sites, des Réponses
  types, de l'Équipe et des codes d'invitation en cartes.

## Conséquences
- Le serveur n'est pas touché. Clés des tests conservées.
- Captures de revue : `flutter test test_parcours/captures_console_test.dart
  --update-goldens` (hors CI, images dans `test_parcours/captures/`, non versionnées).
- Tests : `console_design_test.dart` (ordre du menu et de l'accueil, parties selon le
  rôle, couleur de la rubrique sur les filtres) ; tests de la console adaptés aux titres en
  capitales et à l'accueil plus long.
