# ADR-019 — Rejoindre un groupe par code, demandes d'adhésion, @mentions

**Statut** : accepté (lot 7.1b, décisions du 14/11/2026, amendement 12).

## Décision
- **Code d'invitation** : `PRV-XXXXXX` (6 signes parmi 32, sans 0/O ni 1/I), un par groupe,
  créé à la première ouverture par un administrateur (`get_group_invite_code`), changé par
  `reset_group_invite_code` (l'ancien cesse aussitôt de marcher). Table privée
  `private.group_invite_codes` : jamais lisible par l'application. **Aucun lien web** : le code
  se dit, se recopie, ou se scanne (QR code affiché par l'administrateur, qui ne contient que
  le code). Saisie tolérante (minuscules, espaces, sans « PRV- »).
- **Essais limités** : `group_code_hourly_limit` (20 par heure, réglable dans la console). Un
  code faux NE lève PAS d'erreur (statut `invalid`) : une erreur annulerait la transaction,
  donc aussi le compteur d'essais. Un code ne révèle rien d'un groupe fermé par Privio, ni à
  une personne bloquée par un administrateur (même réponse qu'un code faux).
- **Aperçu** (`preview_group_by_code`) : nom et nombre de membres seulement ; l'identifiant
  du groupe n'est donné qu'à un membre (ouvrir) ou à une personne qui a déjà demandé
  (annuler).
- **Entrée** (`join_group_by_code`) : directe si le groupe l'autorise, sinon **demande**
  (réglage `conversations.join_approval`, vrai par défaut, `set_group_join_approval`). Une
  invitation en attente vaut accord ; une personne **retirée** par un administrateur repasse
  toujours par une demande (`private.group_removals`). Refus : pas de nouvelle demande pendant
  24 h. Demandes valables `group_invitation_ttl_days`, purgées 30 jours après traitement.
- **Demandes** : liste et réponse réservées aux administrateurs (`list_group_join_requests`,
  `respond_to_join_request`) ; l'acceptation passe par le même chemin qu'une invitation
  acceptée (message système « a rejoint »). Notifications **sans contenu** via
  `join_request_id` → `push_join_request_targets` : « Nouvelle demande pour rejoindre un
  groupe » (administrateurs ; l'appui ouvre la fiche du groupe) puis « Votre demande pour
  rejoindre un groupe a été acceptée » (le groupe s'ouvre). Signal temps réel `join_request`.
- **@mentions** : `send_message(…, p_mentions uuid[])` (50 au plus ; seuls les membres actifs
  du groupe sont retenus, sans erreur pour les autres ; ignorées en discussion à deux) ;
  `private.message_mentions`, effacées avec le message. `push_targets` renvoie `mentioned` :
  une personne mentionnée est prévenue **même en sourdine**, par « Vous avez été mentionné
  dans un groupe ». `get_messages` renvoie `mentions` ; l'application met « @Nom » en valeur
  (la sienne surlignée). Le paramètre n'est envoyé que s'il y a des mentions : une application
  à jour reste compatible avec un serveur d'avant le lot.

## Conséquences
- `mobile_scanner` (lecture du QR code, modèle ML Kit inclus dans l'application : pas de
  téléchargement au premier scan) et `qr_flutter` (affichage). La permission « appareil
  photo » est désormais déclarée ; elle est demandée au premier scan ou à la première photo
  prise avec l'appareil.
- Les captures d'écran restent bloquées sur l'écran du code : il se montre ou se recopie.

## Preuves
pgTAP `23_rejoindre_mentions`, `scripts/ci/join_e2e.py` (PostgREST, pg_net et push-dispatch
réels : 1 administrateur prévenu, acceptation prévenue, mention prévenue malgré la sourdine,
sourdine respectée sans mention), tests Flutter `test/ui/join_mentions_test.dart`.
