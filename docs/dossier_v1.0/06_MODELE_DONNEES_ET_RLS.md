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

# Modèle de données logique et RLS
## Tables principales
- `profiles` (id auth.users, handle unique, display_name, avatar_ref, about, created_at)
- `devices` (id, user_id, public_identity_key, push_token_ref, revoked_at, last_seen_at)
- `conversations` (id, type direct/group, created_by, created_at, status)
- `conversation_members` (conversation_id, user_id, role, joined_at, left_at, membership_version)
- `messages` (id, conversation_id, sender_id, client_nonce unique par sender, ciphertext, encryption_header, sent_at, expires_at, edited_at, deleted_at)
- `message_receipts` (message_id, user_id, delivered_at, read_at)
- `message_reactions` (message_id, user_id, emoji, created_at)
- `media_objects` (id, message_id, storage_key privé, media_kind, bytes, encrypted_metadata, expires_at, deletion_status)
- `photo_quota_daily` (user_id, quota_day, reserved_count, committed_count, updated_at)
- `photo_quota_events` (user_id, idempotency_key, quota_day, units, state, created_at)
- `blocks` (blocker_id, blocked_id, created_at)
- `reports` (id, reporter_id, target_kind, target_id, encrypted_evidence_submission_ref, status)
- `policies` (key, scope_type, scope_id, value_json, version, enabled, updated_by)
- `policy_history` (id, policy_key, before_json, after_json, actor_id, created_at)
- `admin_roles`, `admin_role_assignments`, `admin_audit_log`
- `notification_preferences`, `push_delivery_events` (sans contenu de message)

## Politiques d'accès — matrice
| Objet | Lecture | Écriture |
|---|---|---|
| profile | selon visibilité + blocage | propriétaire |
| device | propriétaire, opérateurs très restreints | propriétaire via fonction sécurisée |
| conversation | membres actifs | via fonction de création |
| message | membres actifs ET non expiré | via RPC/Edge Function contrôlée |
| media | membres actifs ET non expiré | via fonction sécurisée et bucket privé |
| policy publique | utilisateurs authentifiés (valeurs filtrées) | administrateurs autorisés seulement |
| audit admin | auditeurs autorisés | append-only serveur |

## Règles impératives
Activer RLS sur chaque table exposée; refuser par défaut. Ne jamais supposer que RLS sur `messages` protège automatiquement les objets Storage ou les flux Realtime. Vérifier chaque canal, bucket, fonction SQL `SECURITY DEFINER`, rôle de service et accès admin. Les messages expirés doivent être filtrés à la source et non seulement dans Flutter. Éviter que les index de recherche serveur contiennent du plaintext E2EE. Ne jamais placer le jeton FCM serveur dans une table exposée.

## SQL
Voir `TECHNIQUE/001_schema_depart.sql` pour un squelette illustratif non exhaustif. Claude doit produire des migrations complètes, tests RLS par rôle et plan de purge.

## Extension obligatoire — identité et recherche
- `profiles.handle` : unique, normalisé de manière cohérente (casse, caractères autorisés, longueur), indexé ; gérer les collisions de manière atomique.
- `profiles.phone_discoverable` : booléen, désactivé par défaut recommandé ; choix utilisateur explicite.
- `private_user_contacts` (ou équivalent non exposé) : `user_id`, `verified_phone_e164` nullable, dates de vérification ; accès strict, pas de SELECT global pour les clients. Ne pas dupliquer inutilement les secrets d’authentification.
- RPC/Edge Function `find_user_by_handle` et `find_user_by_phone` : authentification requise, réponses minimales, limitation des requêtes, blocages respectés, recherche par téléphone seulement si numéro vérifié et découvrabilité activée.
- Tout compte utilisateur doit posséder un numéro de téléphone vérifié ; l’e-mail n’est pas utilisé pour l’authentification.
