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

### Photos et photo de profil (lot 3.2)
`photo-send` et `avatar-set` répondent `{ "error": "<CODE>" }` comme `voice-send`.

| Code | HTTP | Origine | Signification |
|---|---|---|---|
| `PHOTO_QUOTA_REACHED` | 429 | `prepare_photo_message` (via `photo-send`) | photos du jour épuisées (`photo_daily_limit`, 5 par défaut) |
| `MEDIA_INVALID` | 422 | `photo-send`, `avatar-set`, `commit_*` | pas un JPEG accepté, ou dimensions hors limites (photo remboursée) |
| `MEDIA_TOO_LARGE` | 413 | idem | taille hors limites (photo remboursée) |
| `BODY_INVALID` | 422 | `send_photo_message` | légende trop longue (`photo_caption_max_chars`, 1000) |
| `MESSAGE_NOT_EDITABLE` | — | `edit_message` | une photo (ou un vocal) ne se modifie pas |
| `USER_NOT_FOUND` | 404 | `prepare_avatar_upload` | profil absent ou supprimé |

Codes prévus aux étapes suivantes (dossier 07) : `FEATURE_DISABLED`, `POLICY_VERSION_CONFLICT`.

### Groupes (lot 3.3)
| Code | Origine | Signification |
|---|---|---|
| `NOT_GROUP` | fonctions de groupe | la discussion n'est pas un groupe |
| `NOT_ADMIN` | inviter, retirer, rôles, réglages, infos | réservé aux administrateurs (ou réglage « administrateurs ») |
| `NOT_OWNER` | `set_member_role` (retrait), `transfer_group_ownership` | réservé au propriétaire |
| `ROLE_INVALID` | rôles, retrait | rôle inconnu, propriétaire visé, administrateur retiré par un non-propriétaire |
| `SETTING_INVALID` | `set_group_settings` | valeur autre que `all` / `admins` |
| `GROUP_FULL` | `create_group`, `invite_to_group`, `respond_to_invitation` | `group_max_members` atteint (100 provisoire, B2), invitations en attente comprises |
| `GROUP_TITLE_INVALID` | `create_group`, `update_group_info` | nom vide ou > 60 caractères |
| `GROUP_DESCRIPTION_INVALID` | idem | description > 300 caractères |
| `INVITATION_NOT_FOUND` | `respond_to_invitation` | invitation absente, expirée ou déjà traitée |
| `POSTING_RESTRICTED` | envoi (texte, vocal, photo) | envoi réservé aux administrateurs |
| `NOT_MEMBER` | toutes | pas (ou plus) membre du groupe — HTTP 403 dans `avatar-set` |
| `RATE_LIMITED` | `create_group`, `invite_to_group` | trop de groupes créés ou d'invitations envoyées |

### Confidentialité et vidage (lot 4.3)
| Code | Origine | Signification |
|---|---|---|
| `PRIVACY_SETTING_INVALID` | `set_my_privacy` | valeur inconnue ou manquante |
| `TTL_INVALID` | `set_my_privacy` | durée par défaut hors bornes |
| `CLEAR_SCOPE_INVALID` | `clear_conversation` | portée autre que `me` / `everyone` |
| `CLEAR_NOT_ALLOWED` | `clear_conversation`, `respond_clear_request` | « pour nous deux » impossible : blocage ou compte supprimé |
| `CLEAR_REQUEST_NOT_FOUND` | `respond_clear_request` | aucune demande de l'autre personne en cours (annulée, refusée, échue) |
| `NOT_ADMIN` | `clear_conversation` (groupe, `everyone`) | réservé au propriétaire et aux administrateurs |


### Demandes de connexion (lot 4.7)
| Code | Origine | Signification |
|---|---|---|
| `CONNECTION_REQUIRED` | `start_direct_conversation` | aucune discussion existante : il faut d'abord une demande acceptée |
| `CONNECTION_NOT_ALLOWED` | `send_connection_request` | la personne n'accepte pas de demandes, ou un blocage existe (même réponse, le blocage n'est pas révélé) |
| `CONNECTION_RETRY_LATER` | `send_connection_request` | refus récent : attendre `connection_request_retry_minutes` (5 min) |
| `CONNECTION_DAILY_LIMIT` | `send_connection_request` | déjà `connection_request_daily_per_person` (3) demandes vers cette personne aujourd'hui |
| `CONNECTION_REQUEST_NOT_FOUND` | `respond_connection_request`, `cancel_connection_request` | demande inconnue, déjà traitée, annulée ou expirée |
| `CONNECTION_NOTE_TOO_LONG` | `send_connection_request` | mot de plus de `connection_note_max_chars` (140) caractères |

### Console d'administration (lot 5.1)
| Code | Origine | Signification |
|---|---|---|
| `ADMIN_REQUIRED` | `console_dashboard` (et toute fonction de la console) | le compte connecté n'est pas l'administrateur (même réponse pour tous ; `console_access` renvoie simplement `false`) |
| `POLICY_LOCKED` | `console_set_policy` (lot 5.2) | réglage fixé (invariant de sécurité) ou fonctionnalité non développée |
| `POLICY_NOT_FOUND` | `console_set_policy` (lot 5.2) | réglage inconnu |
| `POLICY_TYPE_INVALID` / `POLICY_OUT_OF_BOUNDS` / `FEATURE_NOT_IMPLEMENTED` | `console_set_policy` | mêmes refus que la validation des politiques (type, bornes, fonctionnalité) |

### Modération (lot 5.3)
| Code | Origine | Signification |
|---|---|---|
| `ACCOUNT_SUSPENDED` | toutes les RPC (sauf compte, appareil, notifications, situation, contestation, suppression du compte) | compte suspendu |
| `GROUP_CLOSED` | envoi, invitation, réglage d'écriture | groupe fermé par Privio |
| `MODERATION_NOTE_REQUIRED` | décisions de la console | motif interne absent (3 à 500 caractères) |
| `MODERATION_INVALID` | `console_moderate`, `console_reports` | décision qui ne s'applique pas au dossier (plusieurs cibles, durée hors choix…) |
| `REPORT_NOT_FOUND` | console | signalement déjà traité ou sans copie |
| `ADMIN_PROTECTED` | `console_moderate` | le compte de l'administration ne peut pas être sanctionné |
| `APPEAL_INVALID` / `APPEAL_NOT_ALLOWED` | `submit_appeal` | texte de 3 à 500 caractères ; une seule contestation par sanction |
| `APPEAL_NOT_FOUND` | `console_answer_appeal` | contestation déjà examinée |

### Comptes et assistance (lot 5.4)
| Code | Origine | Signification |
|---|---|---|
| `SEARCH_PHONE_INCOMPLETE` | `console_search_accounts` | numéro partiel : seul le numéro complet est accepté |
| `SEARCH_TOO_SHORT` | `console_search_accounts` | moins de 2 caractères |
| `ACCOUNT_NOT_FOUND` | `console_account`, `console_sanction_user` | compte inexistant ou supprimé |
| `SUPPORT_REPLY_INVALID` | `console_reply_support` | réponse de 2 à 1 000 caractères |

### Fiches (lot 7.1a)
| Code | Origine | Signification |
|---|---|---|
| `ABOUT_TOO_LONG` | `set_my_about` | « À propos » de plus de 140 caractères |

### Rejoindre un groupe, @mentions (lot 7.1b)
| Code | Origine | Signification |
|---|---|---|
| `JOIN_REQUEST_NOT_FOUND` | `respond_to_join_request` | demande inconnue, déjà traitée, annulée ou expirée |
| `GROUP_CLOSED` | `get_group_invite_code`, `reset_group_invite_code`, `set_group_join_approval`, `respond_to_join_request` | groupe fermé par Privio : plus de code ni d'entrée |
| `BODY_INVALID` | `send_message` | plus de 50 mentions |

Un code faux n'est pas une erreur : `preview_group_by_code` et `join_group_by_code`
renvoient un statut (`invalid`, `member`, `pending`, `declined`, `full`, `open`,
`approval`, puis `joined` ou `requested`), pour que les essais restent comptés.

### Finitions (lot 7.2a)
| Code | Origine | Signification |
|---|---|---|
| `DISPLAY_NAME_INVALID` | `set_my_display_name` | nom vide ou de plus de 40 caractères |
| `RATE_LIMITED` | `set_my_display_name` | trop de changements de nom aujourd'hui (`display_name_daily_limit`) |
| `PRIVACY_SETTING_INVALID` | `set_conversation_privacy` | en ligne, photo ou À propos demandés pour un groupe |
| `NOT_MEMBER` | `get_conversation_privacy`, `set_conversation_privacy` | discussion dont on ne fait pas partie |

