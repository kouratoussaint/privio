# ADR-056 — Volume des appels : traitement du son, mode « appel » protégé, mesure

**Statut** : accepté (lot 9.3c, audit du 19/11/2026 ; décisions A, B, C validées le même
jour). Complète l'ADR-050 et son correctif du 18/11/2026.

## Contexte
Après les correctifs du 17 et du 18/11 (volume d'appel remonté, haut-parleur imposé),
le son reste faible **des deux côtés, au haut-parleur** (Samsung Galaxy S22 Ultra,
Android 16). Un volume réglé à 90 % sans effet indique que le problème n'est pas le
réglage de volume mais le niveau du son ou la sortie réellement utilisée. L'audit du code
(Privio et bibliothèques) a trouvé :
1. le traitement du son **du téléphone** (anti-écho, anti-bruit) était utilisé d'office
   par la bibliothèque d'appel sur Android 10 et plus ; selon les téléphones, il baisse
   fortement la voix captée, surtout au haut-parleur ;
2. la bibliothèque des sons de Privio (tonalité d'attente, sonnerie, sons de l'application)
   remet **tout le téléphone** en mode normal et coupe le haut-parleur à chaque préparation
   d'un son, y compris pendant un appel ;
3. trois composants règlent la sortie du son (l'appel déclaré à Android, la bibliothèque
   d'appel, le correctif du 18/11) ; le composant de l'écran d'appel ne transmet pas les
   choix de sortie à Android ;
4. aucune mesure : les correctifs précédents ont été faits à l'aveugle.

## Décision
- **A. Mesure** : à la fin de chaque appel établi (à deux ou de groupe), une ligne au
  journal technique, sans contenu ni nom : durée, sortie choisie, **niveaux moyens du son
  reçu et envoyé** (statistiques de la liaison : énergie / durée, en dB), **état réel
  d'Android** relevé 3 s après la connexion et après chaque changement de sortie (mode,
  sortie réellement utilisée, haut-parleur activé, volume d'appel) et traitement du son
  utilisé. Lu par la console quand la personne joint son journal à une demande d'assistance.
- **B. Traitement du son de la bibliothèque d'appel** (anti-écho, anti-bruit, niveau
  automatique) au lieu de celui du téléphone, réglé une fois avant tout usage de la
  bibliothèque (`prepareCallAudio`, réglage `androidUseHardwareAudioProcessing: false`) :
  même niveau de voix captée sur tous les téléphones.
- **C. Mode « appel » protégé** : la tonalité d'attente garde le mode « appel » et la
  sortie de l'appel (haut-parleur d'emblée pour un appel vidéo) ; **aucun son de Privio
  pendant un appel** (`CallAudioGate`) ; à la connexion, mode « appel », sortie choisie et
  volume de cette sortie sont réimposés.
- **Après la mesure** (non décidé) : D. une seule autorité pour la sortie du son si le
  journal montre une sortie réelle différente de la sortie choisie ; E. renfort du son reçu
  si le journal montre un son reçu faible (au-dessous d'environ −35 dB).

## Conséquences
- Le traitement logiciel demande un peu plus de calcul pendant un appel (négligeable
  devant la vidéo).
- La sonnerie d'un appel entrant reste en mode normal (aucune voix en cours à ce moment).
- Test sur téléphone : un appel au haut-parleur d'au moins une minute, puis Aide →
  Contacter l'assistance → joindre le journal technique ; la console montre la ligne
  « Son de l'appel ».
- Tests : `volume_appels_test.dart` (niveaux, ligne du journal sans nom, sortie
  réimposée, sons coupés, tonalité d'un appel vidéo au haut-parleur).
