# ADR-014 — Demande de connexion avant le premier message

**Statut** : accepté (lot 4.7, décisions du 13/11/2026, amendement 8).

## Contexte
Jusqu'au lot 4.6, trouver quelqu'un (identifiant ou numéro autorisé) suffisait pour lui
écrire. Le propriétaire veut que le premier contact soit une **demande**, que l'autre accepte
ou refuse, pour limiter les messages non sollicités.

## Décision
- **Table `private.connection_requests`** (jamais lisible directement par les utilisateurs) :
  expéditeur, destinataire, mot facultatif, statut `pending` → `accepted` / `refused` /
  `cancelled` / `expired`, échéance. Une seule demande en attente par sens et par paire.
- **RPC** : `connection_status`, `send_connection_request`, `respond_connection_request`
  (`accept` / `refuse` / `block`), `cancel_connection_request`, `list_connection_requests`,
  `get_connection_settings`, `set_connection_settings`.
- `start_direct_conversation` n'ouvre plus qu'une discussion **existante** ; sinon
  `CONNECTION_REQUIRED`. Une discussion à deux n'est créée que par l'acceptation d'une demande
  (ou une demande croisée). « Mes contacts » (ADR-013) = connexions acceptées.
- **Mot** : 140 caractères ; effacé du serveur dès la réponse ou l'expiration (contrainte :
  pas de mot hors d'une demande en attente). À l'acceptation, il devient le premier message,
  envoyé au nom de l'expéditeur, avec une durée de 5 min (`connection_note_ttl_minutes`), et
  sans notification « nouveau message » pour la personne qui vient d'accepter.
- **Règles anti-abus** (politiques administrables) : expiration 24 h ; 5 min d'attente après
  un refus ; 3 demandes au plus vers une même personne par jour (fuseau des quotas) ; garde-fou
  global `conversation_create_hourly_limit`.
- **Blocage et refus de toute demande** : même erreur `CONNECTION_NOT_ALLOWED` ; rien ne révèle
  à l'expéditeur qu'il est bloqué. Un blocage depuis une demande n'envoie aucune notification.
- **Notifications** (push-dispatch, sans nom ni contenu) : « Nouvelle demande de connexion »
  au destinataire, « Votre demande de connexion a été acceptée » et « Réponse à votre demande
  de connexion » à l'expéditeur. Toucher la notification ouvre l'écran « Demandes ». Temps réel :
  événement `request` sur le canal de la personne.
- **Nettoyage planifié** toutes les 10 minutes : demandes échues marquées `expired` (mot effacé),
  demandes closes depuis 7 jours supprimées.
- **Interrupteur** `connection_requests_required` (vrai par défaut) : faux = écriture directe
  comme avant (utilisé par les tests antérieurs ; réglable plus tard depuis la console).

## Application
Recherche : « Écrire » (connectés), « Envoyer une demande » (avec mot), « Demande envoyée ·
Annuler », « Accepter sa demande », ou refus récent avec l'heure du nouvel essai. Encart en
tête de la liste des discussions, pastille de l'onglet Discussions, écran « Demandes de
connexion » (reçues : Accepter / Refuser / Bloquer ; envoyées : en attente, refusée, expirée),
réglage dans Confidentialité, question dans l'Aide.

## Conséquences
- Les discussions déjà ouvertes ne changent pas.
- Une personne hors ligne plus de 24 h ne verra pas une demande échue : l'expéditeur la voit
  « expirée » et peut redemander.
