# ADR-049 — Groupes « Annonces » et sondages éphémères

**Statut** : accepté (lot 10.5, décisions du 17/11/2026 : A un vrai type de groupe, choisi
à la création et définitif, où seuls les administrateurs écrivent et où un membre ne voit
ni la liste ni les numéros des autres membres, jusqu'à 500 membres réglables dans la
console ; B les membres réagissent et votent, sans écrire ; C sondages dans les groupes,
par toute personne qui peut y écrire ; D le créateur choisit « vote anonyme » (par défaut)
ou « votes visibles »).

## Décision
- **Type** (migration `20261118000100`) : colonne `conversations.announcement`, fixée par
  `create_group(…, p_announcement)` ; `posting` vaut alors `admins`. Un déclencheur refuse
  tout changement du type et toute ouverture à tous (`ANNOUNCEMENT_LOCKED`, aussi pour
  `set_group_settings`). La fermeture par la modération (lot 5.3) reste possible.
- **Plafond** : réglage `announcement_max_members` (500, de 2 à 1 000, rubrique Groupes
  de la console) ; `private.group_member_cap` choisit le plafond selon le type pour les
  invitations, les acceptations, les demandes d'adhésion et l'état d'un code de groupe.
- **Membres cachés** (`private.hides_members`) : pour un simple membre d'un groupe
  « Annonces », `get_conversation_members` ne renvoie que les administrateurs et lui-même ;
  les arrivées, départs et retraits des autres membres n'apparaissent ni dans les messages
  ni dans l'aperçu de la liste ; les réactions des autres membres arrivent sans auteur
  (« Un membre ») ; les groupes en commun ne citent un groupe « Annonces » que si l'autre
  personne y est administratrice. Le nombre de membres reste affiché (« Annonces ·
  N membres »).
- **Sondage** : message de type `poll` dont le corps est la question (1 à 200 caractères ;
  aperçu « 📊 question » dans la liste, recherche, notification neutre comme tout message) ;
  choix, réglages et fermeture dans `private.polls` ; votes dans `private.poll_votes`
  (effacés en cascade avec le message, ou dès sa suppression pour tous). 2 à 10 choix
  différents de 80 caractères au plus ; une réponse par défaut, ou plusieurs.
  `send_poll` : groupes seulement (`POLL_GROUP_ONLY`), mêmes droits d'écriture, même durée
  et même limite d'envoi qu'un message. `vote_poll(message, choix)` remplace mes votes
  (liste vide : vote retiré), 120 votes par heure, refusé si le sondage est fermé.
  `close_poll` : son créateur seulement. Chaque vote ou fermeture prévient les membres
  (`message_changed`, sans contenu). Un sondage n'est jamais touché par « Effacer après
  lecture » (on doit pouvoir voter) ; on n'y répond pas et il ne se modifie pas.
- **Ce que voit chacun** (`poll` de `get_messages`) : choix, totaux, nombre de votants, mes
  choix, fermeture ; les votants par choix seulement pour un vote visible, et jamais pour
  un simple membre d'un groupe « Annonces » (la liste des membres y est cachée). Un vote
  anonyme ne révèle les votants à personne, pas même au créateur.
- **Application** : « Type de groupe » à la création (Discussion ou Annonces, « définitif ») ;
  bandeau « Groupe d'annonces : seuls les administrateurs écrivent. Vous pouvez réagir et
  voter. » ; fiche du groupe sans le réglage d'écriture, avec une note à la place de la
  liste pour un membre. ⋮ → « Nouveau sondage » : question, choix (ajouter, retirer),
  « Plusieurs réponses », « Vote anonyme ». Bulle : choix touchables avec barres et totaux
  (après mon vote, pour le créateur, ou une fois fermé), « Retirer mon vote », « Voir les
  votes » (votes visibles), « Sondage fermé ». Appui long sur mon sondage : « Fermer le
  sondage ».

## Limites
- Les versions antérieures au lot 10.5 affichent un sondage comme un simple texte (sa
  question), sans pouvoir voter, et ne proposent pas le type « Annonces ».
- Le nombre de membres d'un groupe « Annonces » reste visible de tous.
- Un sondage exige le réseau (pas de file d'envoi hors connexion).

## Preuves
pgTAP `42_annonces_sondages` (type et verrou, plafond, membres et événements cachés,
réactions anonymes, groupes en commun, sondages : validation, groupes seulement,
plusieurs réponses, vote changé ou retiré, fermeture, anonymat même pour le créateur,
votants cachés dans un groupe « Annonces », non lus, effacer après lecture ignoré,
suppression pour tous, purge) ; `scripts/ci/annonces_e2e.py` (vrai Supabase, signal temps
réel du vote) ; tests Flutter `annonces_sondages_test.dart`.
