# ADR-002 — Messagerie sans chiffrement de bout en bout

**Statut** : accepté (décision du commanditaire, 11/11/2026).

**Conséquences acceptées** : le contenu est lisible par quiconque accède à la base (clé
service-role, tableau de bord Supabase, réquisition, faille RLS). Les sauvegardes peuvent
contenir du contenu expiré jusqu'à 7 jours.

**Atténuations** : RLS en refus par défaut et testée ; aucune clé secrète dans l'application
(refus au démarrage si détectée) ; expiration à 72 h imposée côté serveur ; aucun écran admin
de lecture de contenu ; journalisation des accès privilégiés (étape 5) ; promesse affichée
limitée au transport chiffré (TLS).

**Réversibilité** : le contenu reste traité comme une charge opaque côté serveur (pas
d'indexation, pas de recherche serveur), ce qui laisse possible un ajout ultérieur du
chiffrement, au prix de retirer les validations serveur de contenu (A1).
