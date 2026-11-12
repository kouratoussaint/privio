# ADR-008 — Messages vocaux : stockage privé, mesure serveur, effacement physique

**Statut** : accepté (lot 3.1).

## Décision
- **Format** : AAC-LC mono 16 kHz, 32 kbit/s, dans un conteneur MP4 (`.m4a`). Environ
  120 Kio pour 30 s. Enregistré par le paquet `record` (MIT), lu par `audioplayers` (MIT),
  à partir de la mémoire : le son n'est jamais écrit en clair sur le disque, sauf le fichier
  temporaire d'enregistrement, privé à l'application et effacé dès l'arrêt.
- **Stockage serveur** : bucket Storage **privé** `voice` (1 Mio au plus, `audio/mp4`
  uniquement), chemin opaque `<discussion>/<uuid>.m4a`. **Aucune URL publique ni signée** :
  l'application télécharge avec son jeton, et la politique Storage `privio_voice_read`
  n'autorise la lecture qu'à un membre actif, tant que le message existe, n'est pas supprimé
  et n'a pas expiré (`private.can_read_voice`). Aucune politique d'écriture : l'application
  ne peut rien déposer elle-même.
- **Envoi** : fonction `voice-send` (Deno, sans dépendance). Elle réserve un chemin au nom de
  l'utilisateur (session active, membre, blocage, anti-abus), **mesure** le fichier, le dépose
  avec la clé de service, le valide (service uniquement) puis publie le message au nom de
  l'utilisateur. Idempotente par identifiant client, comme le texte.
- **Mesure (VOICE-007)** : la durée retenue est la plus longue entre l'en-tête du film,
  l'en-tête de piste et la **table des échantillons** (`stts`), qui fixe le minutage réel de la
  lecture. Toutes les pistes doivent être du son AAC ; fichiers fragmentés refusés.
  Limites : `voice_max_seconds` (30 s, +0,5 s de tolérance), `voice_max_bytes` (512 Kio).
- **Expiration et suppression** : le fichier devient illisible à l'instant de l'expiration ou
  de la suppression (la politique Storage dépend du message). L'effacement physique passe par
  l'API Storage — un `DELETE` SQL laisserait le fichier orphelin et il est bloqué par Storage :
  un déclencheur inscrit le fichier dans `private.media_objects`, la base appelle chaque minute
  la fonction `media-purge` (pg_cron + pg_net, jeton aléatoire créé par la migration) qui
  efface les fichiers puis leur trace. Réservations abandonnées : effacées après 1 h.
- **Signalement** : avec l'accord de la personne, le fichier d'un vocal signalé est conservé
  pour la modération jusqu'à l'échéance du signalement (90 j, décision B3), sans redevenir
  lisible par l'application.
- **Téléphone** : sons conservés chiffrés (AES-256-GCM, un fichier par son, clé Keystore
  distincte), indexés avec leur date d'expiration et effacés à l'échéance même sans réseau,
  dès la suppression du message, et à la déconnexion (voir ADR-007).

## Pourquoi
- Une URL signée vit jusqu'à son échéance et ne se révoque pas : elle pourrait survivre au
  message. Le téléchargement authentifié est vérifié à chaque requête (dossier 02).
- Un client modifié pourrait annoncer « 10 s » pour 5 minutes de son : la durée est mesurée
  par le serveur, et sur la table d'échantillons plutôt que sur les en-têtes.

## Limites connues
- La mesure lit la structure du fichier sans décoder le son : un fichier construit à la main
  peut contenir des données inaudibles ; il ne peut pas être **lu** plus longtemps que la
  limite.
- Pas de chiffrement de bout en bout (ADR-002) : le son est protégé en transit (TLS) et au
  repos par le stockage, lisible par le service.
- Un appareil rooté peut lire la mémoire de l'application ou enregistrer le son pendant la
  lecture ; `FLAG_SECURE` ne bloque pas l'audio.
- Effacement physique : au plus quelques minutes après l'expiration (le fichier est déjà
  illisible). Sauvegardes de la base : voir TTL-009 / décision B6.
