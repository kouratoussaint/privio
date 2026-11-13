# ADR-013 — Confidentialité avancée, présence et « vider la discussion »

**Statut** : accepté (lot 4.3, décisions du 13/11/2026). Exigences SEC-009 et suivantes.

## Réglages de confidentialité (écran « Confidentialité »)
Tous appliqués **par la base**, pas seulement masqués dans l'application. « Mes contacts » =
personnes avec qui l'on a une discussion à deux. Une personne bloquée (dans un sens ou dans
l'autre) ne voit jamais rien. Réglages **non réciproques** (décision) : cacher ses
informations n'empêche pas de voir celles des autres.

| Réglage | Valeurs | Défaut | Effet côté serveur |
|---|---|---|---|
| En ligne et « vu à » | tout le monde / mes contacts / personne | mes contacts | `get_presence` ne répond qu'aux personnes autorisées, et seulement entre personnes partageant une discussion |
| Photo de profil | idem | tout le monde | chemin masqué dans la recherche, la liste, les membres ; **fichier refusé** par le stockage |
| Invitations dans les groupes | idem | tout le monde | invitation ignorée sans le révéler |
| Accusés de lecture | oui / non | oui | « lu » masqué (« reçu » reste) ; dans un groupe, « lu » ne compte que les membres qui partagent leurs accusés |
| « En train d'écrire » | oui / non | oui | `signal_typing` n'émet rien |
| Durée par défaut | 5 min … 72 h | 72 h | appliquée aux discussions et groupes **créés** par la personne |

Restent ailleurs : être trouvé par son numéro (désactivé par défaut), personnes bloquées,
verrouillage (ADR-012), captures toujours bloquées (non modifiable).

## Présence
- L'application ouverte se signale toutes les minutes (`touch_presence`) ; en arrière-plan,
  elle signale qu'elle est fermée. « En ligne » dure `presence_online_seconds` (75 s) après le
  dernier signal ; « vu à » = dernier signal. Affichage : en-tête de la discussion à deux et
  fiche du contact, rafraîchi toutes les 30 s. Pas de présence dans les groupes.

## Vider une discussion
- **Seulement chez moi** : `conversation_members.cleared_before` ; tout ce qui a été envoyé
  avant devient invisible pour moi (messages, réactions, vocaux, photos, aperçu, non lus),
  sans rien changer chez les autres. La copie gardée sur le téléphone est effacée.
- **Pour nous deux** (discussion à deux) : une demande est envoyée ; l'autre l'accepte ou la
  refuse depuis un bandeau dans la discussion (aperçu « Propose de vider la discussion » dans
  la liste). Valable `clear_request_ttl_hours` (24 h), annulable, limitée à
  `clear_request_daily_limit` (10) par jour. Si les deux le demandent, c'est un accord.
  Impossible si l'un a bloqué l'autre ou si le compte de l'autre est supprimé (vider chez
  soi reste possible).
- **Pour tous les membres** (groupe) : propriétaire et administrateurs, sans demande.
- Un vidage pour tous **supprime définitivement** tous les messages, y compris les messages
  système : **aucun « Message supprimé », aucune mention**. Les vocaux et photos sont effacés
  du stockage par `media-purge`. Les téléphones effacent leur copie en lisant `cleared_at`.
- Un signalement déjà envoyé garde sa copie de preuve (si la personne l'avait acceptée).

## Limites connues
- La demande de vidage ne déclenche pas de notification : elle apparaît à l'ouverture de
  Privio (liste et discussion).
- Un message envoyé entre la demande et l'accord est effacé aussi (tout ce qui existe au
  moment de l'accord).
- La présence repose sur l'application ouverte : un téléphone sans réseau apparaît « vu à »
  l'heure de son dernier signal.
