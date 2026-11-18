# ADR-054 — Console : pilotage

**Statut** : accepté (lot 5.9, décisions du 18/11/2026 : options recommandées A à G).

## Contexte
Avant le pilote, le propriétaire de la console doit pouvoir limiter les inscriptions,
adapter quelques réglages à un compte ou à un groupe, basculer d'un coup les réglages du
pilote, annoncer une maintenance à l'avance et suivre l'usage réel, sans jamais voir de
contenu.

## Décision
Tout est réservé au **propriétaire** (migration `20261118000500`).
- **A. Inscriptions** : « Ouvertes », « Sur liste » ou « Fermées » (réglages
  `signups_enabled` et `signups_mode`). Sur liste : numéros autorisés (collés dans la
  console, 8 chiffres = +226) ou **code d'invitation** (8 caractères sans 0/O ni 1/I,
  nombre d'utilisations, 1 à 90 jours). Vérifié par le serveur à la création du profil
  (`SIGNUPS_LIST_ONLY`) ; l'application demande alors le code (`redeem_signup_code`,
  10 essais par heure), puis crée le profil. Les comptes existants ne sont jamais touchés.
- **B. Exceptions** : portées « user » et « group » de `private.policies` (prévues dès la
  migration 2), avec date de fin facultative et motif. Compte : photos par jour, création
  de groupes, appels vidéo. Groupe : membres au plus (jusqu'à 500), photos, aperçus des
  liens. Lues par `private.user_policy` / `private.group_policy` dans les vérifications du
  serveur ; les réglages lus par l'application tiennent compte des exceptions du compte.
  Une exception expirée est désactivée (les réglages ne s'effacent jamais ; historique).
- **C. Préréglages** fixes : « Mode pilote » (inscriptions sur liste, groupes de 25,
  Annonces de 200, liens d'invitation coupés) et « Mode normal » (inscriptions ouvertes,
  groupes de 50, Annonces de 500, liens d'invitation). Les changements sont montrés avant
  d'appliquer ; chaque réglage passe par `console_set_policy` (bornes, historique).
- **D. Message programmé** : un seul, début et fin (30 jours au plus) ; pendant sa période,
  il remplace le message d'information immédiat (`get_client_policies`).
- **E. Statistiques** : rétention par semaine d'inscription (comptes revenus au moins 1, 7,
  30 jours après l'inscription, parmi ceux inscrits depuis assez longtemps) ; langue
  choisie (envoyée par l'application, `devices.language`) ; usage des fonctions par jour
  (compteurs existants, plus les appels de groupe).
- **F. Export** : fichier CSV de nombres agrégés, fabriqué par l'application et partagé par
  le menu d'Android ; seule exception à l'interdiction de partager, journalisée
  (`console_log_export`).
- **G. Nouveau téléphone** : la première ouverture de la console sur un téléphone jamais vu
  pour la console (par toute personne de l'équipe) crée une alerte « Console ouverte sur un
  nouveau téléphone » (notification au propriétaire, Santé du service, journal).

## Limites
- Les exceptions de groupe (photos, aperçus) sont vérifiées par le serveur ; l'application
  garde le bouton et affiche le refus.
- La rétention est calculée sur la dernière activité connue de chaque compte.

## Preuves
pgTAP `46_console_pilotage` ; `scripts/ci/console_pilotage_e2e.py` ; tests Flutter
`console_pilotage_test.dart`.
