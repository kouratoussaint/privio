# ADR-033 — Vérification en deux étapes

**Statut** : accepté (lot 8.4a, décisions du 15/11/2026 : A découpage 8.4a / 8.4b / 8.4c ;
B facultative ; C code oublié : réinitialisation par l'assistance depuis la console).

## Contexte
L'accès à un compte ne repose que sur le SMS. Une carte SIM volée ou réattribuée (numéros
recyclés, B9) suffit donc à ouvrir le compte, et la connexion déconnecte aussitôt le
téléphone du propriétaire.

## Décision
- **Code de sécurité** à 6 chiffres, facultatif (Paramètres → Sécurité → Vérification en
  deux étapes ; invitation « Protégez votre compte » dans Discussions jusqu'à « Plus tard »).
  Nommé « code de sécurité » pour ne pas le confondre avec le code reçu par SMS (« code de
  vérification ») ni avec le code de verrouillage du téléphone. Gardé haché (bcrypt,
  pgcrypto) dans `private.two_step` ; jamais lisible par l'application.
- **Session en attente** : après le SMS sur un compte protégé, la session existe mais
  `private.session_is_active()` la refuse tant que le code n'a pas été saisi
  (`private.two_step_sessions`). Elle ne peut donc ni lire, ni écrire, ni enregistrer
  l'appareil (`register_device`) : **le téléphone déjà connecté le reste**. Seules
  `two_step_state`, `verify_two_step` et `request_two_step_reset` lui sont ouvertes
  (`private.require_session_user()`). Après le bon code, l'application enregistre
  l'appareil, ce qui déconnecte l'ancien (règle « un seul téléphone »).
- **Essais** : 5 erreurs, puis attente d'1 minute qui double à chaque erreur (24 h au plus),
  comptées sur le serveur.
- **Changement de numéro** : `authorize_phone_change(code)` ouvre 15 minutes ; un
  déclencheur sur `auth.users` refuse sinon tout changement de numéro d'un compte protégé
  (`TWO_STEP_REQUIRED`), même hors de l'application. L'autorisation sert une fois.
- **Changer / désactiver** : code actuel exigé.
- **Code oublié** : depuis l'écran du code, « Code oublié ? » envoie une demande
  d'assistance (une par 24 h) ; la console affiche « Deux étapes : activée · code oublié,
  demande du … » dans la fiche du compte et propose « Réinitialiser les deux étapes »
  (motif obligatoire, journalisé). Le téléphone en attente vérifie toutes les 30 s et
  s'ouvre une fois la vérification désactivée.

## Preuves
`supabase/tests/database/31_deux_etapes.test.sql` (45 cas) ;
`scripts/ci/deux_etapes_e2e.py` (Auth réel : session en attente sans accès, ancien
téléphone conservé, changement de numéro refusé sans code) ;
`test/ui/deux_etapes_test.dart` (7 cas) ; `support_accounts_test.dart` (console).
Numéros de test 22670000006 et 007 : `supabase/config.toml`, local uniquement.
