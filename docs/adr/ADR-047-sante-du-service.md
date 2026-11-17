# ADR-047 — Santé du service (console)

**Statut** : accepté (lot 5.7, décisions du 17/11/2026 : A version conseillée (bandeau)
puis version minimale (écran bloquant), lien de téléchargement réglable dans la console ;
B alertes de l'administration par notification pour les quatre cas proposés — effacements
en retard, pic de codes SMS, échecs de notifications ou d'appels, relais à 80 % ;
C parcours d'inscription compté par le serveur).

## Décision
- **Versions** (migration `20261117000100`, thème `health` des réglages, affiché dans la
  rubrique « Santé du service » et pas dans « Réglages ») : `app_recommended_build` et
  `app_min_build` (numéro de compilation, après le « + » de `0.1.0+69` ; 0 = aucune),
  `app_update_url` (vide ou `https://…`, 300 caractères, vérifié par le serveur). Les
  téléphones les lisent avec les autres réglages (`get_client_policies`, relus au retour
  dans l'app). En dessous de la conseillée : bandeau « Mise à jour disponible » en haut de
  Discussions et Groupes, fermable pour la session. En dessous de la minimale : écran
  « Mettez Privio à jour » au-dessus de toute l'application (sous le verrouillage), bouton
  « Mettre à jour » (lien) et « Réessayer ». Une version de développement (sans numéro)
  n'est jamais bloquée. La console liste les versions installées (téléphones actifs,
  30 jours) ; toucher une version la propose comme conseillée ou minimale (confirmation
  « avant → après » habituelle).
- **Appels** : un déclencheur sur `private.calls` compte chaque appel terminé (audio /
  vidéo ; réussi, échoué — connexion perdue ou impossible —, sans réponse) et la durée des
  appels réussis dans les compteurs journaliers. À la fin d'un appel, chaque téléphone
  envoie `report_call_quality(appel, relais, octets)` : relais = candidat « relay » d'un
  côté de la paire choisie (statistiques WebRTC) ; un compte rendu par téléphone, seulement
  pour un appel décroché de moins d'un jour. Volume du relais estimé par le plus grand des
  deux comptes rendus de l'appel, cumulé par mois et comparé aux 1 000 Go gratuits de
  Cloudflare.
- **Inscriptions et SMS** : un déclencheur sur `auth.users` inscrit dans `private.sms_log`
  (type et heure seulement, ni numéro ni compte) chaque code envoyé
  (`confirmation_sent_at`, `recovery_sent_at`, `phone_change_sent_at`) et chaque code
  vérifié (`last_sign_in_at` dans l'heure qui suit un code ; numéro effectivement changé).
  Profils créés : compteur sur `profiles`. Coût estimé = codes × `sms_unit_cost` (FCFA,
  réglé dans la console). Journal gardé 35 jours.
- **Diagnostics** : notification de test (`console_test_push`, une toutes les 30 s ; le
  résultat de push-dispatch s'affiche), test du relais (`call-ice` avec `{"test": true}`,
  réservé à l'administration par `console_relay_test`, ne renvoie jamais l'accès au
  relais), état de toutes les tâches automatiques `privio_*` (dernier passage, retard).
- **Alertes** (`private.check_health_alerts`, toutes les 10 min) : effacement des messages
  en retard (dernier passage > 10 min, en échec, ou message expiré depuis plus de 10 min),
  codes SMS en une heure au-delà de `sms_alert_per_hour` (30) ou de 3 fois la moyenne des
  7 derniers jours, notifications en échec > 20 % sur 1 h (10 envois au moins) ou appels
  échoués > 30 % sur 24 h (5 appels au moins), relais > 800 Go dans le mois. Au plus une
  alerte par type toutes les 6 h ; notification sans contenu à l'administration
  (push-dispatch, `alert_*`) ; interrupteur `health_alerts_enabled`. Alertes gardées
  30 jours, listées dans la console.
- Consultations et tests inscrits au journal de la console (`health`, `health_push`,
  `health_relay`).

## Limites
- Les applications antérieures au lot 5.7 ne connaissent ni le bandeau ni le blocage, et
  ne signalent pas leurs appels (part du relais sous-estimée tant qu'elles restent).
- Le volume du relais et le coût des SMS sont des estimations, pas les factures.
- Si `pg_cron` s'arrête, les alertes s'arrêtent aussi : l'état des tâches reste visible
  dans la console.

## Preuves
pgTAP `40_sante_service` (versions, lien, parcours d'inscription, appels et relais,
santé, diagnostics, alertes, nettoyage) ; `scripts/ci/sante_e2e.py` (vrai service Auth :
codes de connexion et de changement de numéro comptés ; appels comptés ; call-ice en mode
test ; notification de test traitée par push-dispatch) ; `test/ui/sante_service_test.dart`
(bandeau, blocage, rubrique de la console, choix d'une version, lien https, compte rendu de
fin d'appel).
