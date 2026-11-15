# ADR-034 — Rappel avant effacement

**Statut** : accepté (lot 8.4b, décisions du 15/11/2026 : D 4 h avant l'effacement ;
E activé par défaut).

## Décision
- **Dans la bulle** : le compte à rebours (déjà affiché) est mis en valeur — sablier,
  couleur d'alerte (jaune des coches « lu » sur le violet), texte gras — quand un message
  d'une durée de **12 h ou plus** s'efface dans **moins de 4 h**. Lecteur d'écran :
  « S'efface bientôt, dans … ». Les messages courts (5 min…6 h) ne sont jamais mis en valeur.
- **Notification** (serveur, `pg_cron` toutes les 10 minutes,
  `private.send_expiry_reminders()`) : pour chaque membre ayant des messages **non lus**
  reçus d'autres personnes, de 12 h ou plus, qui s'effacent dans moins de 4 h, une
  notification **sans nom ni contenu** : « Des messages non lus vont bientôt s'effacer ».
  L'appui ouvre la discussion. **Au plus une par discussion et par 12 h**
  (`private.expiry_reminders`, purgé après 7 jours). Respecte la sourdine, « Mentions
  seulement », les blocages, les messages masqués ou vidés, l'arrivée dans un groupe.
- **Réglage** : Paramètres → Notifications et sons → « Rappel avant effacement »,
  gardé sur le serveur (`private.reminder_settings`), **activé par défaut**.
- Chemin d'envoi identique aux autres notifications : la base confie à `push-dispatch`
  un identifiant seul (pg_net) ; la fonction obtient les jetons par
  `push_expiry_reminder_targets` (réservée au service, jeton `x-privio-push`).

## Preuves
`supabase/tests/database/32_rappel_effacement.test.sql` (15 cas) ; `push_e2e.py`
(rappel envoyé via push-dispatch, une seule fois) ; `test/ui/rappel_effacement_test.dart`.
