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

# Architecture cible
## Schéma logique
Flutter Android (E2EE + cache local chiffré + FLAG_SECURE) ↔ Supabase Auth/PostgREST/Realtime/Storage privés ↔ PostgreSQL RLS + fonctions SQL transactionnelles. Edge Functions servent de façade sécurisée pour envoi, quotas, politiques et notifications. Edge Function (ou worker fiable) → FCM HTTP v1 → Android. React/TypeScript → endpoints admin sécurisés (MFA, RBAC), jamais service-role dans le navigateur. GitHub Actions → tests → APK signé de test → artefact/release.

## Structure dépôt
```
privio/
  apps/mobile/           # Flutter Android
  apps/admin/            # React TypeScript
  packages/contracts/    # schémas et contrats partagés
  supabase/migrations/    # SQL versionné
  supabase/functions/     # Edge Functions Deno
  docs/                  # cahier, ADR, design
  .github/workflows/     # CI, build APK
  README.md
```

## Décisions techniques
- Flutter stable fixé par version; état via Riverpod ou équivalent à justifier; navigation GoRouter ou équivalent.
- React + TypeScript + Vite; bibliothèque UI accessible et libre à sélectionner.
- Supabase Auth pour identité; éviter de supposer que SMS OTP est gratuit; aucune alternative e-mail pour l’authentification.
- Realtime pour événements de nouvelles enveloppes, jamais pour distribuer du plaintext. Revalidation RLS/expiration à chaque récupération.
- Storage bucket privé; objets à clés opaques; autorisations et expiration côté service; purge planifiée avec suivi des erreurs.
- FCM via credentials serveur et HTTP v1; payload minimal sans contenu privé; tokens par appareil, révocation et rotation.
- Planification : pg_cron si disponible sur l'offre retenue ou ordonnanceur externe fiable; aucune dépendance à une tâche opportuniste du client pour garantir la disparition serveur.
- Observabilité : logs expurgés, métriques d'échec, latence, coût, quotas, purge, FCM; éviter de journaliser ciphertext sensible inutilement.
- V2 : POC LiveKit/WebRTC pour appels, coût TURN/SFU et chiffrement E2EE média à évaluer; minuterie appliquée par service, pas uniquement client.
- V3 : iOS/Web avec design multi-appareil E2EE revu; paiements uniquement via prestataire sécurisé.

## Séquence envoi message
1. Client vérifie état local, chiffre et soumet idempotency_key + enveloppe.
2. Edge Function vérifie Auth, membership, blocage, feature flags, rate limit, quotas.
3. Fonction SQL atomique insère message et fixe sent_at/expires_at.
4. Événement realtime émis, notifications FCM génériques envoyées sans plaintext.
5. Client destinataire récupère sous RLS et TTL, déchiffre localement.
6. À expiration, refus de lecture, nettoyage local, purge serveur asynchrone suivie.

## Déploiement
Environnements `dev`, `staging`, `production` isolés. Aucun secret de production dans les artefacts APK ou logs CI. Migrations contrôlées, rollback, protection de branches, code review, scans de dépendances et contrôle des dépenses.

## Authentification validée — téléphone OTP Supabase Auth
Configurer et tester Supabase Auth pour **Phone OTP uniquement**. Le parcours téléphone dépend d’un fournisseur SMS externe et de ses coûts ; ne jamais promettre l’envoi gratuit de SMS. Éviter de divulguer l’existence d’un compte dans les réponses publiques. La session repose sur l’identifiant Supabase Auth stable, indépendamment du moyen choisi. Les identités secondaires éventuelles exigent vérification explicite. Recherche par handle ou numéro vérifié uniquement via une RPC/Edge Function sécurisée et limitée ; ne pas permettre de parcourir `auth.users` ni de rechercher directement dans des numéros exposés par une table publique.


