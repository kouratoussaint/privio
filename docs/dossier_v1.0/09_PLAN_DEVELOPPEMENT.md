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

# Feuille de route pour Claude
## Étape 0 — Audit de faisabilité
Auditer Supabase Free, Auth SMS OTP, coût Realtime/Storage/Edge Functions, E2EE Flutter, purge 72 h et FCM. Produire ADR et liste des décisions à confirmer. Pas de promesse de sécurité non vérifiée.
## Étape 1 — Fondation
Monorepo GitHub, Flutter, React, Supabase local, environnements, conventions, CI, tokens design, auth basique, migrations initiales et RLS.
## Étape 2 — Messagerie privée
Profils, contacts, conversations, E2EE avec bibliothèque éprouvée, messages texte, réponses/réactions, reçus, TTL, synchro et cache local.
## Étape 3 — Médias et groupes
Vocaux 30 s, photos 5/jour, Storage privé, quotas atomiques, groupes E2EE, permissions, invitations.
## Étape 4 — Confidentialité et notifications
FLAG_SECURE, restrictions, signalements, FCM, mode économie de données, contrôles offline.
## Étape 5 — Console admin
RBAC/MFA, tableaux de bord, politiques versionnées, audit, feature flags, supervision, gestion utilisateurs et groupes.
## Étape 6 — Stabilisation
Tests P0/P1, sécurité externe, mesures de performance, alertes coût, documentation déploiement, GitHub Actions APK, pilote Android.
## V2
Appels audio/vidéo (7 min vidéo) et statuts; pas de communautés.
## V3
Paiements, abonnements, organisations, iOS/Web et appareils liés.

## Cadence de livraison
Chaque étape : proposition technique → fichiers modifiés → migration → tests → démonstration → validation humaine. Claude ne doit pas annoncer un module « terminé » sans preuves de tests et sans liste des limitations.
