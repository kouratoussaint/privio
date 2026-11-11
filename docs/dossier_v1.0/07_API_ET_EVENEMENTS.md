## DÉCISION DÉFINITIVE — AUTHENTIFICATION TÉLÉPHONE UNIQUEMENT (11 novembre 2026)
**Cette décision remplace toute mention antérieure de connexion ou inscription par e-mail.**
- Inscription ET connexion uniquement par numéro de téléphone vérifié via OTP Supabase Auth (E.164, +226 par défaut).
- Aucun écran de choix téléphone/e-mail, aucun OTP e-mail, aucun mot de passe ou connexion par e-mail. Un e-mail facultatif de contact, s'il est ajouté plus tard, ne sera jamais un identifiant d'authentification.
- Chaque compte possède un `auth.users.id` et un identifiant Privio (`handle`) unique.
- Recherche de contacts par numéro vérifié (avec consentement de découvrabilité) OU par identifiant Privio, avec limitation des recherches et protection anti-énumération.
- Développement : numéros de test et OTP prédéfinis de Supabase Auth, uniquement dans les environnements isolés, sans envoi de SMS réel.
- Production : prestataire SMS réel configurable via Supabase Auth, sans dépendance directe à un fournisseur dans Flutter ; tester la délivrabilité +226 avant lancement.
- OTP de test strictement interdits en production. Anti-abus, délais de renvoi, limitation des essais, sécurité des sessions et récupération de compte après changement/perte du numéro à définir sans contourner la vérification.
- Critères de recette : inscription et reconnexion téléphone, OTP valide/invalide/expiré, quota renvoi, recherche numéro/handle, confidentialité, absence de parcours e-mail, impossibilité de déployer les OTP de test en production.

# Contrats API et événements — version initiale
Claude doit formaliser en OpenAPI 3.1 et types Dart/TypeScript. Les chemins suivants sont conceptuels et peuvent être adaptés aux conventions Supabase.

| Action | Endpoint / fonction | Entrée | Sortie / erreurs |
|---|---|---|---|
| Créer conversation | `POST /functions/v1/conversation-create` | membres, type, nonce | id; 401/403/409/422 |
| Envoyer message | `POST /functions/v1/message-send` | conversation_id, client_nonce, ciphertext, header, media_refs | id, sent_at, expires_at; 401/403/409/413/429 |
| Réserver photos | `POST /functions/v1/photo-reserve` | units, idempotency_key | reservation_id, remaining; 409/429 |
| Finaliser média | `POST /functions/v1/media-commit` | reservation_id, object_ref | message/media ref; 403/409 |
| Lire conversation | PostgREST/RPC sécurisée | cursor, limit | enveloppes non expirées uniquement |
| Récupérer média | `POST /functions/v1/media-access` | media_id | URL courte bornée TTL ou flux proxy |
| Marquer lu | `POST /functions/v1/receipt` | message_id, status | accepted; 403/410 |
| Lire politiques | `GET /functions/v1/policy-effective` | version app, contexte | snapshot signé/versionné |
| Signaler | `POST /functions/v1/report-create` | cible, preuve volontaire | ticket |
| Admin changer politique | `POST /functions/v1/admin-policy-update` | clé, portée, valeur, version attendue | nouvelle version + audit |

## Événements
`message.created`, `message.expired`, `message.deleted`, `receipt.updated`, `member.added`, `member.removed`, `policy.changed`, `notification.requested`, `notification.failed`, `media.purge_failed`. Les événements ne transportent jamais le contenu déchiffré.

## Erreurs normalisées
`AUTH_REQUIRED`, `NOT_MEMBER`, `BLOCKED`, `MESSAGE_EXPIRED`, `PHOTO_QUOTA_REACHED`, `VOICE_TOO_LONG`, `FEATURE_DISABLED`, `POLICY_VERSION_CONFLICT`, `RATE_LIMITED`, `MEDIA_NOT_FOUND`, `DEVICE_REVOKED`, `ENCRYPTION_KEY_CHANGED`.

## Notifications FCM
Payload minimal : `type`, `conversation_id` opaque, `event_id`, `sent_at`, éventuellement `expires_at` (sans plaintext, nom privé, aperçu, numéro de téléphone). Jetons par appareil; vérification d'authentification à l'ouverture; pas de contenu sensible dans les logs.
