# ADR-053 — Console : équipe et modération

**Statut** : accepté (lot 5.8, décisions du 18/11/2026 : options recommandées A à F).

## Contexte
La console (lots 5.1 à 5.7) n'était ouverte qu'à un seul compte, celui dont le numéro est
le réglage serveur `admin_phone_e164`. Pour le pilote, plusieurs personnes doivent pouvoir
traiter les signalements et les demandes d'assistance, chacune avec des droits limités.

## Décision
- **A. Trois rôles** (migration `20261118000400`, table `private.console_staff`) :
  - **Propriétaire** : le compte `admin_phone_e164` (inchangé) ; tout ;
  - **Modérateur** : signalements hors assistance, preuves, sanctions, contestations,
    groupes, sites sans aperçu, suivi de la modération ;
  - **Assistance** : demandes d'assistance (répondre, classer), fiches des comptes,
    déconnexion d'un téléphone, réinitialisation des deux étapes ; aucune sanction.
  - Tableau de bord (chiffres seulement) et réponses types : toute l'équipe. Réglages,
    fonctionnalités, statistiques, santé du service, journal et équipe : propriétaire.
  - Vérification par le serveur à chaque appel : `private.require_console(rôles)`.
    `require_console_admin()` devient « propriétaire seul » : toute fonction non ouverte
    explicitement reste réservée au propriétaire. Les signalements et contestations sont
    filtrés selon le rôle (`private.report_for_role`). Une personne de l'équipe est
    protégée des sanctions (comme le propriétaire) : on la retire d'abord de l'équipe.
- **B. Ajout** par le propriétaire, au numéro d'un compte Privio existant (10 personnes au
  plus). **Vérification en deux étapes obligatoire** pour l'équipe : sans elle, la console
  affiche « Vérification en deux étapes obligatoire » (`CONSOLE_TWO_STEP_REQUIRED`).
  Ajouts, changements de rôle et retraits sont au journal ; l'entrée « Administration »
  apparaît ou disparaît aussitôt (signal temps réel « moderation »).
- **C. Groupes** : liste (recherche, filtres signalés, fermés, Annonces), fiche (type,
  membres, administrateurs, propriétaire, création, dernier message, signalements) ;
  **jamais les messages**. Fermer (plus personne n'écrit, invitations annulées), rouvrir
  (événement « Ce groupe a été rouvert par Privio »), supprimer (comme une suppression par
  le groupe, définitive) ; motif obligatoire, journalisé ; les signalements en attente du
  groupe sont traités par la décision.
- **D. Réponses types** (`private.console_templates`) : réponses d'assistance et motifs de
  décision ; écrites par le propriétaire, proposées à l'équipe dans les fenêtres
  « Répondre », « Décision » et « Fermer / supprimer le groupe ». 40 au plus.
- **E. Sites sans aperçu** (`private.preview_blocked_sites`) : domaine et sous-domaines ;
  le lien reste dans le message, Privio ne lit pas la page (`link_preview_target`).
- **F. Suivi de la modération** (7 ou 30 jours) : reçus, traités, en attente, plus ancien
  en attente, délai moyen, contestations, demandes d'assistance et réponses, par motif, par
  décision, par personne.
- **Alertes** : `push_admin_targets(jeton, événement)` : signalements et contestations →
  propriétaire et modérateurs ; assistance → propriétaire et assistance ; le reste →
  propriétaire.
- **Journal** : chaque ligne indique qui a agi et son rôle ; nouveaux types « Groupes » et
  « Équipe ».

## Limites
- Le blocage d'un site porte sur l'adresse du lien, pas sur les redirections qu'elle suit.
- Le tableau de bord montre les mêmes chiffres à toute l'équipe.

## Preuves
pgTAP `45_console_equipe` ; `scripts/ci/console_equipe_e2e.py` ; tests Flutter
`console_equipe_test.dart`.
