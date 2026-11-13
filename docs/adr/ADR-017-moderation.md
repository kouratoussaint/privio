# ADR-017 — Signalements et modération

**Statut** : accepté (lot 5.3, décisions du 13/11/2026, amendement 10).

## Décision
- **File** (`console_reports(statut)`) : signalements `open` (à traiter), `reviewing` (en cours,
  `console_take_reports`) et `closed` (traités, 90 jours). Chaque ligne porte la cible
  (@identifiant et nom, jamais le numéro), l'@identifiant de la personne qui signale, le
  nombre de signalements et de personnes sur 90 jours, la suspension en cours, le nombre de
  sanctions, la présence d'une copie et la protection du compte administrateur. L'application
  regroupe les signalements d'une même cible en dossier.
- **Copie jointe** (`console_report_evidence`) : texte, et pour une photo ou un vocal, lecture
  du fichier gardé par `report_hold_until` grâce à la politique de stockage
  `privio_evidence_read` (`private.can_read_evidence` : administration + signalement en cours).
  Chaque lecture est inscrite au journal.
- **Décisions** (`console_moderate`) : `dismiss`, `warn`, `suspend` (1, 7, 30 jours ou sans
  limite), `delete_message`, `close_group` ; motif interne obligatoire ; tout le dossier est
  clos d'un coup. `console_lift_suspension` réactive. `ADMIN_PROTECTED` pour le compte
  administrateur.
- **Sanctions** (`private.sanctions`) : avertissement ou suspension, motif montré (celui des
  signalements) et motif interne, contestation unique (`submit_appeal`), réponse
  (`console_answer_appeal`). Gardées 1 an, sauf suspension sans limite encore active.
- **Compte suspendu** : `private.require_active_user()` refuse `ACCOUNT_SUSPENDED`, sauf pour
  les RPC nécessaires à l'écran dédié (compte, appareil, notifications, situation,
  contestation, avertissement, réglages visibles, suppression du compte). La liste se fonde
  sur le chemin de la requête posé par l'API (`request.path`), que l'application ne peut pas
  modifier. L'application affiche aussitôt l'écran « Compte suspendu » (signal temps réel
  `moderation`) au lieu de déconnecter, pour que la personne voie le motif et puisse contester.
- **Groupe fermé** : `posting = 'closed'` ; envoi, invitations et réouverture refusés
  (`GROUP_CLOSED`, déclencheurs) ; message système « Ce groupe a été fermé par Privio ».
- **Notifications à l'administration** : signalement, demande d'assistance, contestation →
  pg_net → `push-dispatch` (`admin_event`, sans contenu) → téléphones de l'administration ;
  l'appui ouvre la console (code demandé).

## Preuves
pgTAP `20_moderation`, `scripts/ci/moderation_e2e.py` (dont le refus réel par l'API d'un
compte suspendu), tests Flutter `test/ui/moderation_test.dart`.
