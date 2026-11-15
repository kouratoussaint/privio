# ADR-037 — Appels reçus Privio fermé ou téléphone verrouillé

**Statut** : accepté (lot 9.1b ; s'appuie sur les décisions du 15/11/2026 de l'ADR-036 :
C pas de nom tant que le téléphone ou Privio est verrouillé ; E on décroche sans le code
Privio, le reste de l'application reste verrouillé).

## Décision
- **Réveil du téléphone** (migration `20261115000500`) : `start_call` confie à
  `push-dispatch` un identifiant d'appel seul (`private.notify_call(id, 'ring')`).
  `push-dispatch` demande les jetons à `push_call_targets` (réservée au service : l'appelé,
  appareils actifs, appel encore en sonnerie) et envoie un **message de données seul**,
  prioritaire, valable 45 s : `{type:'call', call_id, conversation_id, created_at}`. Ni nom,
  ni numéro, ni texte. La sourdine d'une discussion ne coupe pas la sonnerie.
- **Appel non décroché** (annulé par l'appelant ou expiré) : `finish_call` appelle
  `notify_call(id, 'missed')` ; `push-dispatch` envoie `{type:'call_end'}` (la sonnerie du
  téléphone s'arrête), puis la notification **« Appel manqué »** sans nom (canal
  « Messages », masquée sur l'écran verrouillé), coupée si la discussion est en sourdine.
  Rien pour un appel décroché, refusé, ou « occupé ».
- **Écran d'appel du téléphone** (`flutter_callkit_incoming`) : affiché par le
  gestionnaire de messages en arrière-plan (Privio fermé ou en arrière-plan), plein écran
  par-dessus le verrouillage, texte unique **« Appel Privio entrant »**, sans photo ni
  numéro. Sa propre notification d'appel manqué est désactivée (le serveur s'en charge).
  « Refuser », Privio fermé : le refus part au serveur (session lue dans le stockage
  sécurisé) ; « Décrocher » ouvre Privio, qui reprend l'appel sans demander le code.
  Privio au premier plan : son propre écran sonne, celui du téléphone s'efface.
- **Pendant l'appel** : appel déclaré au téléphone (service de premier plan « appel ») →
  il continue écran éteint ou Privio en arrière-plan ; notification « Appel en cours » avec
  « Raccrocher » (sans nom). Canal natif `privio/call` : écran d'appel par-dessus l'écran de
  verrouillage (retiré dès que l'appel est réduit en bandeau : le verrouillage du téléphone
  revient) et capteur de proximité (écran éteint à l'oreille, écouteur seulement).
- **Sortie du son** : un geste = haut-parleur ; avec un appareil Bluetooth ou un casque
  branché, choix « Écouteur du téléphone / Haut-parleur / Bluetooth / Casque filaire ».
  Autorisation « Appareils à proximité » demandée au premier appel, jamais bloquante.
- **Changement de réseau** (Wi-Fi ↔ données) ou coupure : l'appel n'est plus raccroché au
  premier incident. Affichage « Connexion faible, reconnexion… » ; l'appelant renégocie la
  liaison (nouvelle offre avec redémarrage ICE) au changement de réseau ou après 2 s de
  coupure, l'appelé répond comme au début. Abandon après 30 s sans liaison (« Appel
  interrompu »). Plafond de signaux par appel porté à 500.
- **Connexion faible** : toutes les 3 s, aller-retour > 600 ms ou > 8 % de paquets perdus →
  « Connexion faible » sous la durée, l'appel continue.
- **Android 14+** : l'affichage plein écran des appels doit être autorisé ; Privio le
  propose une seule fois à l'ouverture (« Autoriser » ouvre le réglage).

## Limites connues
- Un téléphone en économie d'énergie agressive, ou une application « arrêtée de force »,
  peut ne pas recevoir le message de réveil : l'appel sonne alors à la prochaine
  ouverture de Privio s'il est encore en cours.
- Sans compte de service FCM, rien n'est envoyé (compte rendu `not_configured`).

## Preuves
`supabase/tests/database/34_appels_notifications.test.sql` (10 tests) ;
`scripts/ci/appels_e2e.py` (réveil une seule fois ; annulé → sonnerie puis « Appel
manqué » ; décroché → rien) ; `test/ui/appels_systeme_test.dart` (12 cas). Sonnerie
téléphone verrouillé, écran éteint, Bluetooth et changement de réseau : sur téléphones.
