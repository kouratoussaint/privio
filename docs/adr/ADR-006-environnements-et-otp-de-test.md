# ADR-006 — Environnements et numéros OTP de test

**Statut** : accepté.

- `dev` : Supabase local (CLI + Docker), numéros de test +226 70 00 00 01/02/03, code 123456.
- `staging` : projet Supabase gratuit (se met en pause après 7 jours d'inactivité).
- `production` : projet Supabase Pro (B8), à créer avant le pilote.

`supabase config push` recopierait les numéros de test vers un projet hébergé, valables
10 ans. La commande est interdite : `scripts/guards.sh` la bloque dans tout workflow ou script.
Le workflow de déploiement n'exécute que `supabase db push` (migrations), jamais la config.
Sur les projets hébergés, Auth (téléphone, fournisseur SMS via Send SMS hook, e-mail désactivé)
se configure dans le tableau de bord.
