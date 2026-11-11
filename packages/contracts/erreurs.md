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

Codes prévus aux étapes suivantes (dossier 07) : `NOT_MEMBER`, `BLOCKED`, `MESSAGE_EXPIRED`,
`PHOTO_QUOTA_REACHED`, `VOICE_TOO_LONG`, `FEATURE_DISABLED`, `POLICY_VERSION_CONFLICT`,
`MEDIA_NOT_FOUND`, `DEVICE_REVOKED`.
