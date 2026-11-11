# ADR-003 — Un seul appareil actif par compte

**Statut** : accepté (A4).

Après un OTP valide, l'application appelle `register_device`. La fonction, sérialisée par un
verrou consultatif : révoque les autres lignes `devices` (motif `new_device`) et **supprime
leurs sessions dans `auth.sessions`**. Toutes les politiques RLS et RPC exigent
`private.session_is_active()` : la session du JWT doit encore exister. Un ancien téléphone perd
donc l'accès immédiatement, même avec un jeton d'accès non expiré (vérifié par
`04_appareils.test.sql` et par le test d'intégration CI). L'application détecte `AUTH_REQUIRED`,
se déconnecte localement et explique pourquoi.
