# Codes d'erreur normalisés (contrat client ↔ serveur)

Les fonctions SQL lèvent `raise exception '<CODE>' using errcode = 'P0001'`.
Le client les lit dans `PostgrestException.message` (`lib/core/errors/app_failure.dart`).

| Code | Origine | Signification |
|---|---|---|
| `AUTH_REQUIRED` | toutes les RPC | non connecté, ou session révoquée (autre appareil) |
| `RATE_LIMITED` | recherche, profil | limite horaire atteinte |
| `HANDLE_INVALID` | `create_profile` | identifiant non conforme ou réservé |
| `HANDLE_TAKEN` | `create_profile` | identifiant déjà attribué |
| `DISPLAY_NAME_INVALID` | `create_profile` | nom vide ou > 40 caractères |
| `PHONE_NOT_VERIFIED` | `create_profile`, `set_phone_discoverable` | pas de numéro vérifié |
| `PROFILE_EXISTS` | `create_profile` | profil déjà créé |
| `POLICY_TYPE_INVALID` / `POLICY_OUT_OF_BOUNDS` / `FEATURE_NOT_IMPLEMENTED` | politiques | refus de configuration |
| `APPEND_ONLY` | historique | modification d'un journal immuable |

### Messagerie (lot 2.1)
| Code | Origine | Signification |
|---|---|---|
| `NOT_MEMBER` | RPC de discussion | l'appelant n'est pas membre de la discussion |
| `SELF_CONVERSATION` | `start_direct_conversation` | discussion avec soi-même |
| `USER_NOT_FOUND` | `start_direct_conversation` | destinataire inexistant ou supprimé |
| `BLOCKED` | démarrage, envoi | l'un des deux a bloqué l'autre |
| `BODY_INVALID` | envoi, modification | texte vide ou trop long (politique `message_max_chars`) |
| `IDEMPOTENCY_CONFLICT` | `send_message` | identifiant client déjà utilisé dans une autre discussion |
| `REPLY_NOT_FOUND` | `send_message` | message cité absent, expiré ou d'une autre discussion |
| `MESSAGE_NOT_FOUND` | actions sur un message | message inexistant ou inaccessible |
| `MESSAGE_EXPIRED` | actions sur un message | message expiré (aucune action possible) |
| `MESSAGE_DELETED` | modification, réaction | message supprimé pour tout le monde |
| `NOT_SENDER` | modification, suppression pour tous | réservé à l'expéditeur |
| `EDIT_WINDOW_EXPIRED` | `edit_message` | au-delà de 60 min (politique `message_edit_window_minutes`) |
| `DELETE_WINDOW_EXPIRED` | `delete_message_for_everyone` | au-delà du délai (politique, 72 h = jusqu'à expiration) |
| `REACTION_INVALID` | `set_reaction` | la réaction doit être un emoji |

### Durée configurable (lot 2.E)
| Code | Origine | Signification |
|---|---|---|
| `TTL_INVALID` | `set_conversation_ttl`, `send_message` | durée hors bornes (minimum administrable, maximum 72 h) |
| `MESSAGE_NOT_EDITABLE` | modification, suppression pour tous, réaction | message système (annonce de durée) |

### Signalement et compte (lot 2.5)
| Code | Origine | Signification |
|---|---|---|
| `REPORT_INVALID` | `report` | motif inconnu, cible incohérente, auto-signalement, assistance sans texte |
| `CONFIRMATION_REQUIRED` | `delete_my_account` | confirmation « SUPPRIMER » absente |

### Messages vocaux (lot 3.1)
La fonction `voice-send` répond `{ "error": "<CODE>" }` avec le statut HTTP indiqué ; le client
lit le code dans `FunctionException.details`. Le téléchargement d'un son refusé par Storage
(expiré, supprimé, non membre) donne `MEDIA_NOT_FOUND` côté application.

| Code | HTTP | Origine | Signification |
|---|---|---|---|
| `VOICE_TOO_LONG` | 422 | `voice-send`, `commit_voice_upload` | durée mesurée > `voice_max_seconds` (30 s, tolérance 0,5 s) |
| `VOICE_TOO_SHORT` | 422 | `voice-send` | moins de 0,5 s de son |
| `MEDIA_INVALID` | 422 | `voice-send` | pas un son AAC dans un MP4 non fragmenté (piste vidéo, fichier altéré…) |
| `MEDIA_TOO_LARGE` | 413 | `voice-send`, `commit_voice_upload` | taille > `voice_max_bytes` (512 Kio) ou > 1 Mio |
| `MEDIA_NOT_FOUND` | 409 | `send_voice_message` | fichier non déposé ou non validé (renvoyer le son) |
| `STORAGE_UNAVAILABLE` | 503 | `voice-send` | stockage momentanément indisponible (réessayer) |
| `NOT_MEMBER` / `BLOCKED` | 403 | `prepare_voice_message` | mêmes règles que le texte |
| `AUTH_REQUIRED` | 401 | toutes | jeton absent ou session révoquée |

Codes prévus aux étapes suivantes (dossier 07) : `PHOTO_QUOTA_REACHED`, `FEATURE_DISABLED`,
`POLICY_VERSION_CONFLICT`.
