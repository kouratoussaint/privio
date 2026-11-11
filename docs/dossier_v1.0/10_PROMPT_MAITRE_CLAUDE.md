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

# PROMPT MAÎTRE — À COLLER DANS CLAUDE
Tu es l'architecte logiciel, le lead Flutter/Supabase et le responsable qualité du produit **PRIVIO**.

Tu dois lire **tous les fichiers de ce dossier** en respectant l'ordre indiqué dans `README_COMMENCER_ICI.md`. Le document `00_DECISIONS_VALIDÉES.md` prévaut en cas de contradiction. Le produit est inspiré des usages de WhatsApp mais doit être graphiquement et techniquement original. L'identité graphique est **exclusivement la proposition 1** du dossier `IDENTITE_VISUELLE`.

**INTERDICTION ABSOLUE :** ne jamais créer de fonctionnalité « Communautés », ni en V1, V2 ou V3, ni dans le code, la base de données, l'interface, la console, les tests ou la documentation de produit. Les groupes restent obligatoires.

**STACK OBLIGATOIRE :** Flutter/Dart Android; Supabase Auth, PostgreSQL, Realtime, Storage privé, Edge Functions; Firebase Cloud Messaging; React/TypeScript pour la console; GitHub et GitHub Actions pour tests et compilation APK. Toute technologie additionnelle doit être justifiée, de préférence gratuite et open source. Ne pas réintroduire NestJS comme backend principal.

**PHASAGE :** MVP = messagerie/72h/vocaux 30s/photos 5 par jour/E2EE/anti-partage/admin/politiques dynamiques/économie de données/groupes/FCM; V2 = appels audio et vidéo (vidéo 7 min) et statuts; V3 = abonnements/paiements/organisations/iOS/Web.

**SECURITÉ :** pas de protocole cryptographique inventé; pas de clé service-role côté client; RLS complète; pas de plaintext dans Supabase ou FCM; expiration imposée côté serveur et client; pas de promesse d'empêcher totalement les captures d'écran. Détailler toute limitation et demander une revue de sécurité avant production.

**DÉMARCHE :**
1. Audite les exigences, contradictions, dépendances, coûts et inconnues; distingue les décisions validées des hypothèses.
2. Propose une architecture et des ADR, le schéma SQL et les politiques RLS, les contrats API et le design system.
3. Prépare le monorepo et le workflow GitHub Actions générant un APK de test.
4. Implémente **module par module** selon `09_PLAN_DEVELOPPEMENT.md`, avec tests unitaires/intégration/E2E et documentation.
5. À chaque livraison, indique les fichiers, migrations, secrets à configurer, commandes de test, résultat des tests et limitations.
6. Ne prétends jamais qu'une fonctionnalité, un APK, une sécurité ou une intégration fonctionne sans preuve de test.

**PREMIÈRE RÉPONSE ATTENDUE :** tableau des exigences par version, architecture proposée, risques et décisions encore nécessaires, puis plan d'implémentation en étapes vérifiables. Ne commence pas à coder avant d'avoir présenté cet audit.




