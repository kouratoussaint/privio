# ADR-001 — Pile technique et versions

**Statut** : accepté (étape 1).

- Flutter **3.47.8** (stable), fixé dans la CI. 3.47.9 écartée : publiée depuis moins de 14 jours.
- État : **Riverpod 3** (`AsyncNotifier`) ; navigation : **go_router 18** avec redirection pure
  (`router/routes.dart`, testée unitairement).
- Backend : Supabase (Auth téléphone, PostgreSQL + RLS, RPC `SECURITY DEFINER` à
  `search_path` vide). Schéma `private` jamais exposé par l'API.
- Session Supabase stockée dans le **Keystore Android** (`flutter_secure_storage`) et non dans
  SharedPreferences (stockage par défaut, en clair).
- CI : GitHub Actions ; tests SQL sur un vrai Supabase local ; APK de debug en artefact.
- Police Inter embarquée (licence OFL, fichier joint dans `assets/fonts`).
