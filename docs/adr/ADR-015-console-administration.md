# ADR-015 — Console d'administration dans l'application

**Statut** : accepté (lot 5.1, décisions du 13/11/2026, amendement 6).

## Contexte
L'amendement 6 place la console **dans l'application mobile**, réservée au seul compte dont
le numéro vérifié est +226 75 49 35 18. Il reste à fixer : la protection à l'ouverture, le
contenu du tableau de bord et la façon de compter l'activité alors que les messages
s'effacent en 72 h au plus.

## Décision
- **Qui** : le serveur compare le numéro VÉRIFIÉ du compte (`private.user_contacts`) au
  réglage privé `admin_phone_e164` (`private.runtime_settings`, posé par migration, modifiable
  par déploiement ; jamais dans l'application). `public.console_access()` renvoie vrai ou faux
  sans jamais lever d'erreur ; chaque fonction de la console appelle
  `private.require_console_admin()` (session active + administrateur, sinon `ADMIN_REQUIRED`).
  L'application n'affiche l'entrée « Administration » (Paramètres) que si le serveur répond
  vrai ; pour tout autre compte, la console n'existe pas.
- **Protection à l'ouverture** (choix du propriétaire) : code Privio ou empreinte à CHAQUE
  ouverture. Sans verrouillage actif, la console ne s'ouvre pas et propose de l'activer. Elle
  se referme après 5 min sans action, quand l'app passe en arrière-plan, ou d'un appui sur le
  cadenas. Le code n'est vérifié que sur le téléphone (lot 4.2) : la sécurité réelle reste la
  vérification serveur ci-dessus, et l'appareil unique (A4).
- **Tableau de bord** (`public.console_dashboard()`, JSON) : des NOMBRES seulement, jamais de
  contenu, de nom, d'identifiant ni de numéro. Sections : comptes (total, actifs 24 h et
  7 jours, nouveaux), activité (messages du jour et sur 7 jours, vocaux, photos, messages
  conservés), groupes et demandes (groupes, créés, invitations et demandes en attente,
  acceptées, refusées), santé technique (notifications envoyées et en échec, derniers passages
  des effacements, messages expirés non effacés, fichiers à effacer, stockage vocaux et
  photos), signalements en attente (traitement au lot 5.3).
- **Compteurs anonymes** : `private.daily_stats (jour, nom, valeur)` alimentée par des
  déclencheurs (messages par type, discussions, invitations, demandes et réponses). Ni
  identifiant ni contenu. Comptage à partir du déploiement (date affichée). Gardés 400 jours.
- **Journal** : chaque consultation est inscrite dans `private.admin_audit` (administrateur,
  action, date), conservé `admin_audit_retention_days` jours (90 par défaut, 30 à 365).
- Tables et réglages restent dans le schéma `private` (illisibles depuis l'application).

## Conséquences
- Changer d'administrateur = changer le réglage au déploiement ; aucun nouvel APK.
- Les lots 5.2 (politiques, statistiques détaillées) et 5.3 (modération) ajouteront leurs
  fonctions derrière `require_console_admin()` et le même journal.

## Preuves
pgTAP `18_console` (accès, session révoquée, anonyme, compteurs, nombres seulement, journal,
nettoyage), `scripts/ci/console_e2e.py` en CI, tests Flutter `test/ui/console_test.dart`
(entrée masquée, refus serveur, verrouillage obligatoire, code, empreinte, 5 min, arrière-plan).
