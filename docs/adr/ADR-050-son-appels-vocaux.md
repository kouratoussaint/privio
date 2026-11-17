# ADR-050 — Son des appels, écouteurs et envoi des vocaux

**Statut** : accepté (lot 9.3, retours de tests du 17/11/2026 : volume des appels très
faible, haut-parleur et écouteurs à vérifier ; décisions : bascule automatique vers les
accessoires, vocal envoyé dès qu'on lève le doigt par défaut).

## Constat
- Les touches de volume pendant un appel réglaient le flux des médias, pas celui de
  l'appel : le son paraissait très faible et ne montait pas.
- Au début d'un appel, l'application choisissait explicitement l'écouteur. La
  bibliothèque de routage (AudioSwitch, dans flutter_webrtc) gardait alors ce choix même
  quand des écouteurs ou des AirPods se connectaient.

## Décision
- **Mode communication** : `Helper.setAndroidAudioConfiguration(communication)` à
  l'ouverture de la liaison (mode `IN_COMMUNICATION`, flux `VOICE_CALL`, usage
  « communication vocale »).
- **Touches de volume** : canal `privio/call` → `callAudio` ; pendant tout l'appel (même
  réduit), `volumeControlStream = STREAM_VOICE_CALL` ; à la fin, retour au réglage par
  défaut. Au début de l'appel, un volume d'appel inférieur à 40 % du maximum est remonté à
  60 % (jamais baissé).
- **Sortie choisie d'office** : Bluetooth, sinon écouteurs filaires, sinon écouteur du
  téléphone (appel audio) ou haut-parleur (appel vidéo).
- **Accessoires en cours d'appel** (`mediaDevices.ondevicechange`) : un accessoire qui
  arrive (Bluetooth ou filaire) prend le son aussitôt ; si la sortie utilisée disparaît, le
  son revient à la meilleure sortie restante (même ordre). Un choix fait à la main (bouton
  de sortie) reste tant qu'aucun accessoire n'arrive.
- **Vocaux** : réglage gardé sur le téléphone, Paramètres → Discussions → « Écouter les
  vocaux avant de les envoyer », désactivé par défaut. Désactivé : lever le doigt envoie ;
  enregistrement verrouillé → bouton « Envoyer » à droite et « Écouter » (oreille) dans le
  bandeau. Activé : comportement précédent (préécoute). L'arrêt à la durée maximale envoie
  aussi le vocal en envoi direct.

## Limites
- Certains téléphones limitent le volume d'appel par leurs propres réglages : Privio ne
  dépasse pas le maximum du téléphone.
- Les écouteurs Bluetooth demandent l'autorisation « Appareils à proximité » (Android 12
  et plus) ; refusée, le son passe par l'écouteur ou le haut-parleur.

## Preuves
Tests Flutter `son_appels_test.dart` (flux d'appel ouvert puis rendu, Bluetooth d'office,
casque puis AirPods branchés et retirés, choix manuel conservé, vidéo avec écouteurs,
réglage des vocaux) et `voice_test.dart` (envoi direct en relâchant, bouton « Envoyer » de
l'enregistrement verrouillé, préécoute avec le réglage).
