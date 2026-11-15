# ADR-027 — Carte d'une personne, apparence, QR code de l'identifiant

**Statut** : accepté (lot 8.1a, décisions du 15/11/2026 : A carte en feuille, B QR lisible
seulement dans Privio, E découpage 8.1a / 8.1b).

## Décision
- **Carte d'une personne** : toucher le nom de l'auteur (groupe), la photo à côté d'un
  message, un membre dans la fiche d'un groupe ou un QR code scanné ouvre :
  - « Ma fiche » si c'est moi ;
  - la fiche du contact si une discussion à deux existe déjà ;
  - sinon une **feuille** : photo et nom en grand, identifiant, « À propos » (selon ses
    réglages, règle serveur `about_for`), groupes en commun, « Envoyer un message » ou
    demande de connexion (lot 4.7), Bloquer, Signaler.
  Pour un administrateur du groupe, la carte s'ouvre toujours (même pour un contact) et
  propose « Gérer ce membre » (actions d'administration existantes). Toucher la photo dans
  la liste des discussions ou des groupes ouvre la fiche du contact ou du groupe.
  Aucune modification serveur : `get_contact_profile` (membres d'une discussion commune),
  `list_common_groups`, `connection_status`, `find_user_by_handle` suffisent.
- **Apparence** (Paramètres → Apparence, réglages gardés sur le téléphone) : thème
  automatique (par défaut), clair ou sombre ; taille du texte Petit 0,9 / Normal 1 /
  Grand 1,15 / Très grand 1,3, multipliée par la taille réglée dans le téléphone.
- **QR code de l'identifiant** : Ma fiche → « Mon QR code » ; contenu `privio:@identifiant`,
  lisible seulement dans Privio (Nouvelle discussion → Scanner) ; le texte lu ne quitte pas
  le téléphone, seul l'identifiant reconnu est cherché (recherche limitée côté serveur).

## Preuves
Tests Flutter `test/ui/carte_apparence_test.dart` (10 cas) ; `groups_test.dart` mis à jour
(« Gérer ce membre ») ; suite complète 423 tests ; captures.
