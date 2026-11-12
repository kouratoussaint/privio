# ADR-009 — Photos (5 par jour) et photo de profil

**Statut** : accepté (lot 3.2). Complète l'ADR-008 (même chaîne : stockage privé, contrôle
serveur, effacement physique par `media-purge`).

## Décision
- **Choix de la photo** : `image_picker` (BSD) — appareil photo du téléphone ou sélecteur de
  photos du système. **Aucune autorisation** demandée (ni appareil photo, ni lecture de la
  galerie) ; rien n'est enregistré dans la galerie par Privio (PHOTO-007). Le fichier
  temporaire est lu puis effacé aussitôt.
- **Préparation sur le téléphone** (paquet `image`, pur Dart, MIT, hors du fil de
  l'interface) : rotation selon l'EXIF appliquée aux pixels, plus grand côté ramené à
  1600 px, JPEG qualité 80 (≈ 150 à 400 Kio), **toutes les métadonnées retirées** (position
  GPS, appareil, date). Photo de profil : carré de 512 px.
- **Contrôle serveur** (`photo-send`, `avatar-set`) : le JPEG est relu segment par segment et
  **réécrit** sans EXIF, XMP, ICC, commentaires ni données ajoutées après l'image (vidéo des
  « photos animées »). Seuls les JPEG de base, étendus et progressifs, en 1 ou 3 composantes,
  sont acceptés. Limites administrables : `photo_max_bytes` (1 Mio), `photo_max_dimension`
  (2048 px) ; profil : `avatar_max_bytes` (256 Kio), 1024 px.
- **Quota (PHOTO-004)** : `photo_daily_limit` (5), par compte et par jour du fuseau
  `quota_timezone` (Ouagadougou), groupes inclus. Le débit se fait **dans la même
  transaction** que la réservation du fichier (`prepare_photo_message`) : jamais « compter
  puis insérer ». La réservation est créée d'abord ; un renvoi avec le même identifiant
  client la retrouve et **ne débite rien** (même en cas d'appels simultanés).
- **Remboursement** : fichier refusé par la fonction (illisible, trop grand) ou réservation
  abandonnée plus d'une heure → photo remboursée. **Jamais** après acceptation (une photo
  supprimée pour tous reste décomptée).
- **Lecture** : bucket privé `photos`, lecture par un membre actif tant que le message
  existe, n'est pas supprimé et n'a pas expiré (comme les vocaux). Bucket privé `avatars` :
  lecture par toute personne connectée, **sauf en cas de blocage** dans un sens ou dans
  l'autre ; la liste des discussions ne donne pas la photo d'un contact bloqué.
- **Photo de profil** : seul le serveur peut la poser (colonne non modifiable par
  l'application). L'ancienne est effacée au remplacement, au retrait et à la suppression du
  compte.
- **Téléphone** : photos gardées chiffrées dans le coffre (ADR-007, ADR-008), effacées à
  l'expiration du message, à sa suppression et à la déconnexion ; photos de profil gardées
  7 jours au plus.
- **Visionneuse** (écran 15) : zoom, légende ; aucun bouton enregistrer, partager ni
  transférer ; captures bloquées par `FLAG_SECURE`.

## Limites connues
- Selon le téléphone, l'application appareil photo peut garder sa propre copie de la photo
  prise : c'est un comportement du fabricant, hors du contrôle de Privio.
- Une photo affichée peut être photographiée avec un autre appareil.
- Le téléchargement est automatique à l'ouverture de la discussion ; le téléchargement
  manuel (économie de données, DATA-003) arrive au lot 4.2.
- Pas de chiffrement de bout en bout (ADR-002).
