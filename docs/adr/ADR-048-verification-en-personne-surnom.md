# ADR-048 — « Vérifié en personne » et surnom privé

**Statut** : accepté (lot 10.4, décisions du 17/11/2026 : QR code temporaire de 2 minutes
scanné face à face, « Vérifié en personne » sur les deux téléphones ; badge retiré quand le
contact se connecte sur un nouveau téléphone ou change de numéro, avec un avis proposant de
revérifier ; surnom privé visible par moi seul, partout, « Surnom · vrai nom » dans la
fiche, gardé sur le serveur pour mon compte).

## Contexte
Privio n'a pas de chiffrement de bout en bout : la vérification ne compare pas des clés.
Elle atteste que deux personnes se sont **vues** et que le compte en face est bien celui
de la personne rencontrée. Le risque visé est la carte SIM volée ou réattribuée : un
nouveau téléphone ou un nouveau numéro doit faire tomber l'attestation.

## Décision
- **Code** (migration `20261117000200`) : `create_verification_code(contact)` renvoie un
  code aléatoire de 128 bits, valable **2 minutes**, à usage unique, créé **pour un contact
  précis** (discussion à deux existante, aucun blocage) ; 10 codes par heure. Seule
  l'empreinte SHA-256 du code est gardée (`private.verification_codes`) ; un nouveau code
  pour le même contact remplace le précédent. Le QR code contient `privio:v:<code>`.
- **Scan** : `confirm_verification_code(code, personne attendue)` — refusé si le code a été
  créé pour quelqu'un d'autre, ou par une autre personne que celle dont la fiche est
  ouverte (`VERIFY_WRONG_PERSON`), s'il est inconnu (`VERIFY_CODE_INVALID`), expiré ou déjà
  utilisé (`VERIFY_CODE_EXPIRED`) ; 30 essais par heure. **Un seul scan vérifie les deux
  personnes** : une ligne par paire (`private.in_person_verifications`) garde, pour
  chacun, le téléphone actif (ligne `devices`) et l'empreinte de son numéro (SHA-256, jamais
  le numéro). La personne qui montre le code reçoit le signal temps réel
  `labels_changed` ; son écran demande aussi l'état du code toutes les 2 secondes
  (`verification_code_status`).
- **Badge qui tombe** : `my_contact_labels()` compare, pour chaque contact vérifié, son
  téléphone actif et l'empreinte de son numéro actuels à ceux du jour de la vérification.
  Différents : `lapsed` (« device », « phone » ou « both ») et **avis** dans la discussion
  (« Bob utilise maintenant un nouveau téléphone. Revérifiez en personne dès que
  possible. » — « Revérifier » ou fermer). Fermer l'avis
  (`dismiss_verification_notice`) retient la situation vue : l'avis revient si elle change
  encore. Toute nouvelle connexion du contact compte comme un nouveau téléphone (y compris
  une reconnexion après déconnexion par la console) : Privio ne peut pas reconnaître un
  téléphone d'une connexion à l'autre. Un déclencheur sur `devices` prévient aussitôt les
  personnes qui l'avaient vérifié (`labels_changed`, sans contenu). Revérifier remet tout à
  zéro, avis compris.
- **Surnom privé** (`set_contact_nickname`, 40 caractères, espaces nettoyés, vide =
  retiré, 60 changements par heure) : seulement pour une personne avec qui je partage une
  discussion (à deux ou de groupe) ; gardé dans `private.contact_nicknames` pour mon compte,
  jamais renvoyé à quelqu'un d'autre.
- **Application** : `my_contact_labels()` (surnoms et vérifications, une ligne par
  personne) est lu à chaque synchronisation de la liste des discussions et copié sur le
  téléphone (affichage hors connexion, effacé à la déconnexion). Le surnom remplace le nom
  **partout** : liste, en-tête, messages et membres des groupes, auteur des annonces de
  groupe, mentions proposées, recherche (par le surnom comme par le vrai nom), carte d'une
  personne, appels. La fiche et la carte affichent « Surnom · vrai nom ». Une @mention
  insère toujours le vrai nom : le surnom ne quitte jamais mon compte. Le badge (bouclier
  vert) s'affiche dans l'en-tête de la discussion, la fiche, la carte d'une personne et la
  liste des membres d'un groupe. Écran « Vérifier en personne » depuis la fiche : « Montrer
  mon code » (QR et décompte, « Nouveau code » à l'expiration) ou « Scanner son code ».

## Limites
- La vérification atteste une rencontre, pas une identité officielle.
- Les versions antérieures au lot 10.4 n'affichent ni badge ni surnom ; elles ne
  reçoivent pas non plus le signal `labels_changed` (aucun effet).
- Hors connexion, le badge affiché est celui de la dernière synchronisation.

## Preuves
pgTAP `41_verification_surnom` (code lié à une personne, empreinte seule, 2 minutes,
usage unique, mauvaise personne, les deux côtés, badge qui tombe pour un nouveau téléphone
puis un nouveau numéro, avis fermé puis revenu, revérification, aucun numéro en clair,
surnom privé et invisible de l'autre, tables inaccessibles, blocage) ;
`scripts/ci/verification_e2e.py` (vrai Supabase : signal temps réel à la personne qui
montre le code et à l'arrivée d'un téléphone du contact, état rétabli) ; tests Flutter
`verification_surnom_test.dart` (surnom partout et dans la recherche, gardé sur le
serveur, QR et décompte, code expiré, scan réussi ou refusé, avis et « Revérifier »,
groupes).
