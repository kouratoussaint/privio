# PRIVIO — messagerie privée et éphémère

Application Android (Flutter) adossée à Supabase. Messages effacés après 72 heures, pas de
transfert ni de copie, captures d'écran bloquées sur Android. Pas de chiffrement de bout en bout
(décision du 11/11/2026, voir `docs/adr/ADR-002`). **Aucune communauté, dans aucune version.**

## Structure
```
apps/mobile/          Application Flutter Android (com.privio.app)
apps/admin/           Console React/TypeScript (étape 5)
packages/contracts/   Contrats client ↔ serveur (codes d'erreur)
supabase/             config.toml (local), migrations SQL, tests pgTAP
scripts/              garde-fous CI, tests SQL locaux, test d'intégration Auth
tools/brand/          générateur reproductible du logo provisoire
docs/                 décisions v1.1, ADR, rapport d'étape, dossier de référence v1.0
.github/workflows/    CI (tests + APK) et déploiement manuel des migrations
```

## Mise en route sur GitHub (une seule fois)
1. Pousser ce dépôt dans votre dépôt **privé**.
2. *Settings → Secrets and variables → Actions → Variables* (valeurs **publiques**) :
   - `STAGING_SUPABASE_URL` : URL du projet staging (`https://<ref>.supabase.co`)
   - `STAGING_SUPABASE_PUBLISHABLE_KEY` : clé **publishable** (jamais la clé secrète)
3. *Settings → Environments → New environment* `staging`, avec les **secrets** :
   - `SUPABASE_ACCESS_TOKEN` (jeton personnel Supabase), `SUPABASE_PROJECT_REF`,
     `SUPABASE_DB_PASSWORD`
4. *Actions → « Déployer les migrations (manuel) »* → staging.
5. Dans le tableau de bord Supabase staging : *Authentication → Sign In / Providers* :
   activer **Phone**, désactiver **Email** ; ajouter les numéros de test
   (`22670000001=123456`…) avec une date d'expiration. Ne **jamais** utiliser
   `supabase config push`.
6. Chaque push sur `main`/`develop` produit les artefacts `privio-apk-arm64-<n>` et `privio-apk-32bits-<n>` (onglet Actions).

## Développement local
```bash
# Base de données (Docker requis)
supabase start
supabase test db
scripts/ci/auth_smoke_test.sh

# Sans Docker (PostgreSQL + pgTAP + pg_prove installés)
scripts/db/run_local_tests.sh

# Application
cd apps/mobile
flutter test
flutter run --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
            --dart-define=SUPABASE_PUBLISHABLE_KEY=<clé publique locale>
```
Numéros de test locaux : +226 70 00 00 01 / 02 / 03, code `123456`.

## Règles non négociables vérifiées en CI (`scripts/guards.sh`)
Aucune communauté · aucune authentification e-mail · jamais de `config push` · numéros de test
uniquement en local · aucune clé secrète dans l'app · aucun fichier sensible versionné ·
aucune promesse de chiffrement de bout en bout · FLAG_SECURE · sauvegardes Android désactivées.
