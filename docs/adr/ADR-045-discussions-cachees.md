# ADR-045 — Discussions cachées

**Statut** : accepté (lot 10.2, consigne du 16/11/2026 : « elles s'ouvrent sur appui du logo
Privio et validation par code Privio » ; décisions A–H du 16/11/2026).

## Décision
- **Ouvrir (A, B)** : appui **long** sur le logo Privio en haut de Discussions (aucune
  indication visible), puis le **code Privio** — jamais l'empreinte, qu'une autre personne
  peut avoir enregistrée sur un téléphone partagé. Le code est demandé à chaque fois, même
  s'il n'y a aucune discussion cachée (rien ne laisse deviner la fonction) ; code faux :
  « Code incorrect. », mêmes limites d'essais que le verrouillage.
- **Code Privio sans verrouillage** : au premier masquage, s'il n'y a pas encore de code, il
  est créé (`PinFlow.codeOnly`) sans activer le verrouillage à l'ouverture. Le code reste
  sur le téléphone (haché), jamais sur le serveur ; activer plus tard le verrouillage
  remplace ce code par le nouveau.
- **Masquer / ne plus masquer (C)** : appui long sur une discussion (ou ⋮ dans la
  discussion) → « Masquer la discussion » / « Ne plus masquer ». Discussions à deux et
  groupes. `set_conversation_secret` (migration `20261116000400`) pose
  `conversation_members.secret_at` pour **mon compte seulement (H)** : l'autre personne n'en
  sait rien ; l'état survit à une réinstallation.
- **Ce qui disparaît (D)** : `list_conversations` renvoie `secret` ; l'application range ces
  discussions à part (`listedConversationsProvider`) : absentes de Discussions, Groupes,
  Archivées, la recherche, la liste des contacts (nouvelle discussion, invitations de
  groupe), les favoris de toutes les discussions et le décompte des non-lus. L'alerte
  anti-usurpation continue de les connaître (sécurité).
- **Notifications (E)** : `push_targets` signale la discussion cachée ; `push-dispatch`
  envoie « Nouveau message », sans identifiant de discussion (toucher ouvre Privio
  normalement), regroupé sous une seule étiquette. Appel manqué : « Appel manqué », rien à
  ouvrir. Pas de rappel « messages bientôt effacés » pour une discussion cachée.
- **Appels (F)** : l'écran de sonnerie dans Privio montre « Appel Privio entrant », sans nom
  ni photo, pour une discussion cachée ; le nom apparaît une fois décroché (l'écran du
  téléphone, lui, n'affiche jamais de nom).
- **Refermer (G)** : la liste (`/hidden`) se referme quand on la quitte, quand Privio passe
  en arrière-plan (sauf appareil photo ou galerie ouverts depuis Privio) ou après 1 min sans
  action ; la discussion cachée ouverte se referme avec elle (retour à Discussions). Arriver
  sur `/hidden` sans le code ne montre rien.

## Preuves
`supabase/tests/database/39_discussions_cachees.test.sql` (état propre à chaque personne,
notification et sonnerie neutres, pas de rappel) ; `test/ui/discussions_cachees_test.dart`
(masquer avec création du code sans verrouillage, mauvais code, ouverture, fermeture en
arrière-plan, ne plus masquer, sonnerie neutre) ; test d'intégration complet vert.
