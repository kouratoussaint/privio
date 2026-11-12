# ADR-010 — Groupes : invitations, rôles et réglages

**Statut** : accepté (lot 3.3). Un groupe est une discussion à plusieurs ; aucune autre
structure (pas de regroupement de groupes, pas d'annuaire public, pas de lien d'invitation).

## Décision
- **Même moteur que le 1:1** : un groupe est une `conversation` de type `group` ; messages,
  vocaux, photos (quota de 5 par jour, groupes inclus), réactions, réponses, modification,
  durée de vie, expiration et purge suivent exactement les mêmes règles et le même stockage
  privé (ADR-008, ADR-009).
- **Invitations obligatoires** : personne n'est ajouté de force. Un administrateur invite ;
  l'invité accepte ou refuse depuis l'onglet Groupes. Invitation valable
  `group_invitation_ttl_days` (7 j), purgée ensuite. Une personne bloquée (dans un sens ou
  dans l'autre) par l'invitant n'est pas invitée. Limites anti-abus administrables :
  `group_create_daily_limit` (10 groupes par jour) et `group_invite_hourly_limit`
  (60 invitations par heure).
- **Taille maximale (décision B2)** : `group_max_members` = **100, valeur provisoire**,
  administrable (bornes 2 à 100). Les invitations en attente comptent dans la limite, pour
  qu'un groupe ne puisse pas la dépasser lorsque tout le monde accepte. En attente de votre
  décision définitive.
- **Rôles** : un seul propriétaire (`owner`), des administrateurs (`admin`), des membres.
  Administrateurs : inviter, retirer un membre (un administrateur ne retire pas un autre
  administrateur ; seul le propriétaire le peut), nommer administrateur, changer les
  réglages, supprimer pour tous le message d'un membre. Propriétaire : en plus, retirer le
  rôle d'administrateur et confier le groupe. Si le propriétaire part (ou supprime son
  compte), le groupe est confié automatiquement à l'administrateur le plus ancien, à défaut
  au membre le plus ancien.
- **Réglages** (`set_group_settings`) : envoi de messages « tous » ou « administrateurs » ;
  modification du nom, de la description, de la photo et de la durée des messages
  « administrateurs » (par défaut) ou « tous ».
- **Historique** : un nouveau membre ne voit que les messages envoyés **après son arrivée** ;
  une personne retirée ou partie ne voit plus rien du groupe (messages, vocaux, photos,
  photo du groupe) — contrôlé par le serveur (RLS et fonctions), pas par l'application.
- **Événements** : création, arrivée, départ, retrait, rôles, nom, description, photo et
  réglages sont des messages système `{e, a, t, v}` (événement, auteur, cible, valeur)
  affichés en français par l'application ; ils expirent comme les autres messages.
- **Accusés dans un groupe** : « reçu » et « lu » n'apparaissent que lorsque **tous** les
  autres membres ont reçu ou lu (minimum sur les membres).
- **Photo du groupe** : même chaîne que la photo de profil (`avatar-set` avec
  `conversation_id`, JPEG réécrit sans métadonnées, bucket privé `avatars`), lisible par les
  seuls membres actifs ; l'ancienne est effacée physiquement.
- **Sourdine** : `set_conversation_mute` (8 h, 1 semaine, toujours), appliquée aux
  notifications du lot 4.1.
- **Signalement** : on peut signaler le groupe entier (sans viser une personne) ou un
  message d'un membre.

## Limites connues
- Pas de lien ni de code d'invitation : on invite par identifiant, numéro autorisé ou
  parmi ses contacts.
- Bloquer quelqu'un n'empêche pas de voir ses messages dans un groupe commun (il faut
  quitter le groupe ou le signaler) ; cela empêche seulement de s'inviter mutuellement.
- L'indicateur d'écriture d'un groupe affiche « quelqu'un écrit… » sans nommer la personne.
- Pas de chiffrement de bout en bout (ADR-002).
