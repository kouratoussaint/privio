# ADR-016 — Réglages, statistiques et journal dans la console

**Statut** : accepté (lot 5.2, décisions du 13/11/2026, amendement 9).

## Décision
- **Réglages** : les définitions (`private.policy_definitions`) portent désormais leur thème,
  leur libellé français, leur unité, un cadenas (`admin_locked`), le rangement « Avancé »,
  l'ordre et l'effet affiché avant confirmation. `console_policies()` les liste avec la valeur
  effective ; `console_set_policy(clé, valeur)` écrit la politique GLOBALE (validation
  existante : type, bornes, fonctionnalité développée) et refuse les réglages sous cadenas
  (`POLICY_LOCKED`). L'historique existant (`policy_history`, ajout seul) garde l'auteur ;
  `console_policy_history(clé)` l'affiche. « Valeur par défaut » et « Rétablir » sont de simples
  écritures (aucune suppression : traçabilité).
- **Sous cadenas** : `message_ttl_hours` (72 h), captures, copie, transfert, partage, export,
  galerie, fuseau des quotas ; vidéos, documents et appels vidéo (non développés).
- **Prise d'effet** : immédiate côté serveur ; les téléphones relisent les réglages visibles
  au retour dans l'app et après une coupure (`messagingRulesProvider`).
- **Statistiques** (`console_stats`, 30 jours) : compteurs journaliers anonymes du lot 5.1,
  plus les notifications envoyées/en échec (déclencheur sur `push_log`) et le nombre de comptes
  actifs relevé chaque soir à 23 h 55 UTC (`privio_snapshot_active_users`) et à chaque
  consultation ; nouveaux comptes calculés depuis les profils ; versions de l'app des téléphones
  actifs (30 jours). Aucun identifiant, aucun contenu.
- **Journal** (`console_journal`) : consultations et changements de réglages (avant → après),
  conservés `admin_audit_retention_days` jours ; l'historique des réglages est gardé sans limite.
- Toutes ces fonctions passent par `require_console_admin()`.

## Reporté
Réglages par groupe ou par compte (la table le permet déjà : portées `group` / `user`) ;
textes d'aide de l'application qui citent encore les valeurs par défaut.

## Preuves
pgTAP `19_console_reglages`, `scripts/ci/console_e2e.py`, tests Flutter `test/ui/console_test.dart`.
