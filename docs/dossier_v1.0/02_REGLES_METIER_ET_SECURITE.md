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

# Règles métier, sécurité et limites
## Valeurs initiales
| Code | Clé | Défaut | Note |
|---|---|---|---|
| TTL-72 | message_ttl_hours | 72 | invariant; réduction possible sous validation, jamais extension silencieuse |
| VOICE-30 | voice_max_seconds | 30 | contrôlé client + serveur |
| PHOTO-5 | photo_daily_limit | 5 | atomicité et idempotence |
| TZ | quota_timezone | Africa/Ouagadougou | fuseau quota |
| SHARE-I | internal_forward_enabled | false | UI + refus serveur |
| SHARE-E | external_share_enabled | false | UI, OS best effort |
| COPY | message_copy_enabled | false | best effort sur appareil |
| EXPORT | conversation_export_enabled | false | pas d'API d'export conversation |
| GALLERY | save_media_to_gallery_enabled | false | pas de sauvegarde volontaire |
| CAPTURE | screen_capture_allowed | false | FLAG_SECURE Android; non absolu |
| VIDEO-UP | video_upload_enabled | false | non implémenté au MVP sauf besoin explicite |
| DOC-UP | document_upload_enabled | false | non implémenté au MVP sauf besoin explicite |
| CALL-V | video_call_max_minutes | 7 | V2 |
| GROUP-MAX | group_max_members | 100 | hypothèse, à valider |

## Expiration
L'heure d'acceptation serveur est la seule référence. La lecture API, la livraison realtime et la délivrance de liens médias doivent refuser les contenus `now() >= expires_at`. Supabase Storage ne doit jamais exposer des objets privés par URL publique. Pour éviter qu'une URL signée vive au-delà du TTL, générer une URL à très courte durée et la borner à l'expiration, ou utiliser un proxy de lecture autorisé; une URL signée déjà émise ne peut pas toujours être révoquée immédiatement. Les copies téléchargées et photos externes échappent à toute garantie absolue. Les tâches de purge doivent supprimer métadonnées et objets; définir explicitement politique de rétention des sauvegardes, journaux et données de signalement. Le cache local chiffré doit appliquer l'expiration sans réseau, avec protections raisonnables contre la manipulation de l'horloge locale.

## Quotas
Chaque photo = une unité, groupe inclus. Décompte transactionnel dans PostgreSQL par compte + date locale + clé idempotente; jamais « compter puis insérer » en deux opérations. Définir remboursement sur échec pré-acceptation, non sur suppression après envoi. Prévenir doubles envois lors des retries. Les métadonnées déclaratives (durée vocal, taille fichier) doivent être corroborées autant que possible sans casser E2EE : un serveur aveugle au contenu ne peut pas prouver seul la durée réelle d'un média chiffré. Prévoir attestation/limites de protocole et revue du modèle de menace, ne pas prétendre à une validation parfaite.

## E2EE
Ne pas inventer un protocole cryptographique. Évaluer des bibliothèques éprouvées, leur maintenance/licence et leur compatibilité Flutter, y compris la gestion multi-appareils et des groupes. Le serveur conserve ciphertext, clés publiques et métadonnées minimales, jamais les clés privées ni le plaintext. Prévoir préclés, rotation, ajout/retrait de membre, changement d'appareil, récupération de compte, relecture et anti-rejeu. Pas de déchiffrement admin. Signalement : l'utilisateur choisit explicitement quelles preuves communiquer.

## Contrôle d'accès
RLS activée sur chaque table exposée; aucune clé service-role dans l'APK, le navigateur ou le dépôt. Edge Functions vérifient JWT, rôle et politiques. Les politiques ne doivent pas pouvoir être modifiées par un simple utilisateur. MFA administrateurs, RBAC, journal immuable/auditable, alertes, révocation. Les secrets FCM restent côté serveur. Rate limits sur authentification, invitations, messages et signalements.

## Administration dynamique
Hiérarchie proposée : invariant système > politique globale > plan/organisation (V3) > groupe > utilisateur; toute exception doit être explicitée et testée. Politiques versionnées, horodatées, auditées, avec rollback, validation de schéma, activation planifiée et feature flags. Une fonctionnalité non implémentée ne peut pas être activée par simple flag.

## Coûts et limites
Supabase gratuit et GitHub Actions gratuit ne garantissent pas une exploitation gratuite en production. SMS OTP, egress médias, stockage, realtime, fonctions et temps CI peuvent générer des coûts. Définir alertes de quotas et budget. L'envoi FCM est gratuit en principe, mais la logique serveur et le trafic associés peuvent être facturés.
