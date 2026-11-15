# ADR-038 — Appels vidéo à deux

**Statut** : accepté (lot 9.2, décisions du 15/11/2026 : A chacun allume ou coupe sa caméra
à tout moment, sans demande ; B qualité selon le réseau ; C on décroche toujours caméra
coupée ; D petite fenêtre quand on quitte Privio ; E relais Cloudflare seulement si la
liaison directe échoue, comme pour l'audio).

## Décision
- **Mise en relation** : celle de l'audio (ADR-036/037). `start_call(…, 'video')` est
  accepté (migration `20261115000600`) ; le message de réveil indique le type
  (« Appel vidéo Privio entrant », jamais de nom) ; la trace devient « Appel vidéo sortant ·
  01:05 », « Appel vidéo manqué »…
- **Une seule liaison pour tout l'appel** : chaque appel (audio compris) prévoit dès le début
  la place de la vidéo (transceiver `sendrecv`) et un petit canal de données négocié des
  deux côtés. Allumer ou couper sa caméra remplace seulement l'image envoyée : aucune
  nouvelle négociation, aucun signal en plus par le serveur. Le canal annonce
  `{"cam": true|false}` au correspondant.
- **Décrocher** : toujours caméra coupée (décision C), Privio ouvert ou écran verrouillé.
  La caméra n'est demandée au téléphone qu'au moment où on l'allume ; refusée, un message
  s'affiche et l'appel continue.
- **Appeler en vidéo** (🎥 dans une discussion à deux et sur la fiche du contact) : caméra
  avant allumée dès l'appel.
- **Son** : appel vidéo, ou image allumée pendant un appel audio → haut-parleur (on regarde
  l'écran) ; pas de capteur de proximité tant qu'une image passe.
- **Qualité** (décision B) : capture jusqu'à 720p. Données mobiles : envoi réduit de moitié
  (≈ 360p), 350 kbit/s, 20 images/s — de l'ordre de 2 à 3 Mo par minute dans chaque sens.
  Wi-Fi : 720p, 1,5 Mbit/s. Réglage changé au passage Wi-Fi ↔ données ; WebRTC baisse
  encore la qualité seul si la connexion est faible.
- **Écran** : image du correspondant en plein écran, la mienne en petit (déplaçable, bouton
  « Changer de caméra ») ; boutons micro, caméra, son, raccrocher, réduire.
- **Petite fenêtre** (décision D) : pendant un appel avec image, quitter Privio l'ouvre
  (Android 8+, automatique sur Android 12+) ; seule l'image y est affichée. Captures et
  enregistrement de l'écran restent bloqués (FLAG_SECURE).
- « Ce que Privio garde » : ni la voix ni l'image ne sont enregistrées ni gardées.

## Compatibilité
Un téléphone resté sur une version d'avant 9.2 n'a pas la place de la vidéo dans sa liaison :
l'appel audio fonctionne, l'image ne passe pas. Tous les testeurs doivent mettre à jour.

## Preuves
`supabase/tests/database/35_appels_video.test.sql` ; `scripts/ci/appels_e2e.py` (appel vidéo
lancé, vu par l'appelé, annulé) ; `test/ui/appels_video_test.dart` (8 cas). L'image elle-même
(caméra, qualité, petite fenêtre) se vérifie sur deux téléphones.
