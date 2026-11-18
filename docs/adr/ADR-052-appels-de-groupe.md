# ADR-052 — Appels de groupe audio et vidéo

**Statut** : accepté (lot 9.4, décisions du 17/11/2026 — amendement 21 : relais Cloudflare
Realtime, 8 participants, lancés par tout membre qui peut écrire, sonnerie si le groupe a
16 membres au plus).

## Contexte
À deux, la voix et l'image passent de téléphone à téléphone (ADR-036, ADR-038). À
plusieurs, chaque téléphone devrait envoyer sa voix (et son image) à chacun des autres :
trop pour un téléphone en données mobiles. Un relais (SFU) reçoit une fois chaque piste et
la redistribue.

## Décision
- **Relais** : Cloudflare Realtime (SFU). Une seule liaison WebRTC par téléphone vers le
  relais ; ma voix (et mon image) y sont publiées une fois ; les pistes des autres arrivent
  par la même liaison. La clé du relais (`CLOUDFLARE_REALTIME_APP_ID`,
  `CLOUDFLARE_REALTIME_APP_TOKEN`) reste dans la fonction `call-sfu` ; elle est transmise
  aux fonctions par `deploy-db.yml` (avertissement si elle manque). Aucun enregistrement :
  le relais transmet, il ne garde rien ; Privio ne garde que des identifiants de session et
  de pistes, effacés à la fin de l'appel.
- **Base** (migration `20261118000300`) : `private.group_calls` (un seul appel en cours par
  groupe) et `private.group_call_participants` (sonne, dans l'appel, parti, refusé, manqué ;
  session et pistes au relais ; micro, caméra). Fonctions `start_group_call` (rejoint
  l'appel en cours s'il y en a un), `join_group_call`, `decline_group_call`,
  `leave_group_call`, `group_call_state` (présence toutes les 4 s), `set_group_call_media`,
  `my_group_calls`. Signal temps réel `group_call` (sans contenu) : à tout le groupe quand
  quelqu'un arrive ou part, aux personnes de l'appel pour le micro et la caméra.
- **Règles** : groupe seulement (`GROUP_CALL_GROUP_ONLY`) ; lancé par toute personne qui
  peut écrire (`check_can_post` : groupe fermé ou réservé aux administrateurs, dont
  « Annonces ») ; tout membre peut rejoindre ; **8 personnes au plus** (`GROUP_CALL_FULL`) ;
  un seul appel à la fois par personne : appeler à deux pendant un appel de groupe est
  refusé (`CALL_ALREADY_ACTIVE`), et une personne dans un appel de groupe est « occupée »
  pour un appel à deux. Interrupteurs de la console : ceux des appels audio et vidéo.
- **Sonnerie** : groupe de **16 membres ou moins** → le téléphone des autres membres sonne
  (écran d'appel du téléphone, « Appel de groupe Privio », jamais de nom), sauf sourdine du
  groupe, « Recevoir des appels » coupé ou blocage avec la personne qui appelle ; sans
  réponse en 45 s : « Appel de groupe manqué » (notification sans nom). Groupe plus grand :
  pas de sonnerie ; notification « Un appel de groupe a commencé » (sans nom ni titre),
  bandeau « Appel de groupe en cours · N personnes — Rejoindre » dans le groupe. Groupe
  « Annonces » : qui sonne reste caché aux simples membres ; les personnes **dans** l'appel
  se voient (elles ont choisi de rejoindre).
- **Relais, vérifications** (fonction `call-sfu`, actions `push`, `pull`, `answer`,
  `close`) : sous le jeton de l'utilisateur, `group_call_sfu` vérifie qu'il est dans
  l'appel et ne demande que des pistes d'autres personnes du même appel (`SFU_FORBIDDEN`) ;
  `group_call_set_sfu` (réservée à la fonction) enregistre sa session et ses pistes.
  Réseau : les serveurs de `call-ice` (STUN et TURN Cloudflare) servent aussi pendant un
  appel de groupe.
- **Fin** : quand la dernière personne part ; personne sans nouvelles 40 s : sortie ;
  sonnerie sans réponse 45 s : manquée (tâche planifiée chaque minute et à chaque lecture).
  Trace dans la discussion `{"e":"group_call","k":"audio","v":"ended:183"}` (auteur : la
  personne qui a lancé l'appel) ou `"missed"` si personne n'a rejoint ; elle s'efface comme
  les autres messages.
- **Application** : boutons 📞 et 🎥 dans la barre d'un groupe (si on peut y écrire) ;
  écran d'appel de groupe posé au-dessus de Privio : sonnerie (groupe, « Lancé par … »,
  personnes déjà dans l'appel, « Refuser » / « Rejoindre »), puis mosaïque de 8 cases
  (image si la caméra est allumée, sinon photo et nom ; micro coupé signalé), micro,
  caméra, sortie du son (écouteurs et Bluetooth d'office, comme à deux), « Quitter »,
  réduction en bandeau. On rejoint toujours caméra coupée ; l'appel vidéo allume la caméra
  de la personne qui le lance. Image réduite à plusieurs : ≈ 240p (150 kbit/s) en données
  mobiles ou Mode éco, ≈ 480p (450 kbit/s) en Wi-Fi. Liaison perdue : nouvelle liaison au
  relais (« Reconnexion… »), abandon au bout de 30 s.

## Limites
- Pas de partage d'écran, pas de « lever la main », pas d'image principale de la personne
  qui parle (mosaïque égale).
- Sans clé du relais configurée, les appels de groupe sont indisponibles (message clair) ;
  les appels à deux ne sont pas touchés.
- Les versions antérieures au lot 9.4 ne sonnent pas pour un appel de groupe et affichent
  sa trace comme un événement inconnu.

## Preuves
pgTAP `44_appels_groupe` (règles, sonnerie et sourdine, rejoindre l'appel en cours, refus,
occupé pour un appel à deux, sessions et pistes au relais, droits, 8 au plus, fin et trace,
sonnerie manquée, personne sans nouvelles, grand groupe sans sonnerie) ;
`scripts/ci/appels_groupe_e2e.py` (temps réel, fonction `call-sfu`) ; tests Flutter
`appels_groupe_test.dart`.
