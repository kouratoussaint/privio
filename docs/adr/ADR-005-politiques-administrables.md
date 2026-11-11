# ADR-005 — Politiques administrables

**Statut** : accepté.

`private.policy_definitions` déclare type, défaut, bornes, valeurs autorisées, visibilité
client et **`implemented`**. Un déclencheur refuse : mauvais type (`POLICY_TYPE_INVALID`), valeur
hors bornes (`POLICY_OUT_OF_BOUNDS`, ex. durée > 72 h), activation d'une fonction non livrée
(`FEATURE_NOT_IMPLEMENTED`). Chaque changement incrémente la version et s'inscrit dans
`policy_history`, en ajout seul. Une politique ne se supprime pas, elle se désactive.
Le client lit uniquement les clés visibles via `get_client_policies()`. Chaque étape passe
`implemented` à `true` par migration quand la fonctionnalité est livrée et testée.
