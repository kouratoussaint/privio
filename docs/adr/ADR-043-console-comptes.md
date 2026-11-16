# ADR-043 — Comptes dans la console : numéro, photo, fiche, appareils, @ réservés

**Statut** : accepté (lot 5.6, décisions du 16/11/2026 : A numéro visible dans la liste et la
fiche ; B recherche par numéro ; C fiche selon la maquette ; D appareils avec modèle, Android,
version de l'app, dernière connexion et « Déconnecter cet appareil » ; E identifiants réservés
gérés dans la console, mots déjà réservés pré-remplis ; F filtres Tous, Suspendus, Supprimés,
Nouveaux 7 j, Inactifs 30 j, Deux étapes). Idées 7, 8 et 9 du plan d'enrichissement de la
console (1 à 19 validées le 16/11/2026).

## Contexte
Le lot 5.4 (ADR-018) avait fixé que la console ne montre jamais le numéro de téléphone. Pour
l'assistance pendant le pilote, l'équipe a besoin de reconnaître un compte par son numéro et sa
photo. La décision A du 16/11/2026 revient sur cette règle **pour la console seulement**.

## Décision
- **Numéro et photo** (migration `20261116000200`) : `console_accounts_page`,
  `console_search_accounts` et `console_account` renvoient `phone_e164` et `avatar_path`
  (photo absente pour un compte supprimé). Rien ne change ailleurs dans l'application : les
  autres personnes ne voient toujours pas le numéro. La photo est lue avec le jeton de la
  session (droit `can_read_evidence` de l'administration), jamais par une adresse publique.
  Les consultations restent inscrites au journal ; le numéro cherché n'y est jamais écrit.
- **Recherche** : numéro dès 4 chiffres, n'importe où dans le numéro (30 résultats au plus).
- **Filtres** (`p_filter` : `all`, `suspended`, `deleted`, `new`, `inactive`, `two_step`) :
  l'index A–Z et les pages suivent le filtre ; la réponse donne le nombre de comptes par filtre
  (`counts`). « Inactif » : dernier passage (présence ou téléphone) il y a plus de 30 jours.
- **Appareils** : `devices.model` et `devices.os_version` ; `register_device` accepte
  `p_model` et `p_os_version` (facultatifs : les anciennes versions de l'app restent
  compatibles). L'app les lit par le canal natif `privio/device` (fabricant + modèle, version
  d'Android) et réenregistre le téléphone une fois par lancement (version de l'app tenue à
  jour). La fiche liste les 10 derniers téléphones, actif ou non, avec le motif de fin
  (remplacé, déconnexion, équipe, compte supprimé). `console_disconnect_device` accepte
  `p_device_id` pour ne déconnecter qu'un appareil.
- **Retirer la photo** (`console_remove_avatar`) : motif interne obligatoire, compte de
  l'administration protégé, inscrit au journal (`avatar_remove`).
- **Changer l'identifiant** (`console_reset_handle`) : l'identifiant est remplacé aussitôt par
  un identifiant neutre (`compte_xxxxxxxx`) et `profiles.handle_reset_at` est posé ; signal
  `moderation` au téléphone. `my_moderation_status` renvoie `handle_reset` : l'app affiche
  « Choisissez un nouvel identifiant » par-dessus Privio (mêmes règles qu'à l'inscription) ;
  `choose_new_handle` n'est permis que dans ce cas, une fois.
- **Identifiants réservés** : table `private.reserved_handles` ; `create_profile`,
  `is_handle_available` et `choose_new_handle` les refusent comme « déjà pris » (la liste
  n'est pas révélée). Les mots toujours réservés (`privio`, `admin`, `support`,
  `moderation`…) restent dans `handle_is_valid` et s'affichent sous cadenas
  (`HANDLE_ALWAYS_RESERVED`). Réserver ne retire rien à un compte qui porte déjà l'identifiant.
- **Fiche** (maquette validée) : en-tête dégradé bleu (photo, nom, @, pastilles Actif /
  Suspendu / Deux étapes / Nouveau / Identifiant à changer, numéro) ; tuiles Discussions,
  Groupes, Signalé (90 j, en rouge si > 0), Dernière activité ; Téléphones ; Compte
  (inscription, notifications, deux étapes) ; Actions en tuiles colorées ; Historique
  (sanctions, demandes d'assistance, actions de l'équipe, du plus récent au plus ancien).
- **Journal** : `avatar_remove`, `handle_reset` (Comptes), `reserved_handle` (Réglages) ;
  la liste des comptes note le filtre consulté.

## Preuves
`supabase/tests/database/37_console_comptes.test.sql` (52 tests) et
`21_comptes_assistance.test.sql` adapté ; `scripts/ci/console_e2e.py` (numéro dans la liste,
modèle et Android, filtre, recherche partielle, @ réservé refusé puis libéré) et
`support_e2e.py` adapté ; `test/ui/console_comptes_test.dart` (6 cas) et
`support_accounts_test.dart` adapté.
