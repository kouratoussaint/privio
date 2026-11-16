# ADR-018 — Comptes et assistance dans la console

**Statut** : accepté (lot 5.4, décisions du 14/11/2026, amendement 11).

## Décision
- **Recherche** (`console_search_accounts`) : @identifiant (préfixe), nom (contient), ou numéro
  COMPLET (8 chiffres burkinabè ou international) comparé au numéro vérifié ; un numéro partiel
  est refusé (`SEARCH_PHONE_INCOMPLETE`). Les résultats ne contiennent jamais de numéro ; le
  journal note seulement « par numéro » ou « par nom ».
- **Fiche** (`console_account`) : identité, état, dates (inscription, dernier passage au jour
  près), téléphone actif (plateforme, version, notifications), nombres de discussions et de
  groupes, signalements reçus et faits (90 jours), demandes d'assistance. Photo de profil
  lisible par l'administration (`can_read_evidence`, bucket `avatars`). Ouverture journalisée.
- **Actions** : `console_sanction_user` (avertir ou suspendre sans signalement, motif montré
  choisi) ; `console_lift_suspension` ; `console_disconnect_device` : signal temps réel
  `disconnected`, appareils révoqués (`admin`), sessions supprimées ; l'application ouverte
  revient à la connexion avec un message dédié. `ADMIN_PROTECTED` pour l'administration.
- **Assistance** : `console_reply_support` (une réponse, 2 à 1 000 caractères, demande close
  « répondue ») ; notification sans contenu (`support_reply_id` → `push_support_targets`) et
  signal `support` ; `my_support_requests` alimente Aide → Mes demandes (90 jours).

## Preuves
pgTAP `21_comptes_assistance`, `scripts/ci/support_e2e.py` (dont la session réellement coupée
par l'API), tests Flutter `test/ui/support_accounts_test.dart`.

> **16/11/2026** : la règle « numéro jamais affiché » est levée pour la console seulement (numéro et photo dans la liste, la recherche et la fiche) — voir ADR-043.
