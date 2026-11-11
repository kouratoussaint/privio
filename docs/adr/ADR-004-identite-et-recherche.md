# ADR-004 — Identité par téléphone et recherche

**Statut** : accepté.

- Authentification : **téléphone + OTP uniquement**. E-mail désactivé dans `config.toml`.
- Le numéro vérifié est copié par un trigger sur `auth.users` vers `private.user_contacts`
  (E.164), jamais dans une table exposée. Un format inattendu ne fait jamais échouer Auth.
- `profiles.handle` : 3–24 caractères `[a-z0-9_.]`, normalisé (minuscules, sans `@`), unique.
  L'attribution concurrente est arbitrée par l'index unique (test de concurrence réel).
- Recherche : correspondance **exacte** uniquement, par identifiant ou par numéro **découvrable**
  (désactivé par défaut). Réponse minimale, jamais de numéro ; blocages et comptes supprimés
  exclus ; réponse vide identique dans tous les cas d'échec. Limites horaires administrables
  (60 recherches par identifiant, 20 par numéro).
- Lecture directe de `profiles` limitée à son propre profil à l'étape 1 (étendue aux membres
  d'une même conversation à l'étape 2).
