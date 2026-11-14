# ADR-024 — Messages épinglés, favoris, infos d'un message, « Mentions seulement »

**Statut** : accepté (lot 7.2c2, décisions du 14/11/2026, amendement 16).

## Contexte
Messages importants difficiles à retrouver, pas de moyen de savoir quand un message a été
lu, pas d'action sur plusieurs messages, et des groupes trop bavards pour garder les
notifications.

## Décision
- **Épinglés** : `private.message_pins` (un message, une ligne ; clé étrangère en cascade
  sur `messages`). `pin_message` : à deux, les deux personnes ; groupe, administrateurs ;
  3 au plus parmi les messages encore présents (`PIN_LIMIT_REACHED`) ; signal `pin` aux
  membres. `list_pinned_messages` ne renvoie que des messages encore visibles (non expirés,
  non supprimés, non masqués chez moi, après mon arrivée). Bandeau dans la discussion ;
  un message plus ancien que la page chargée est montré dans une feuille.
- **Favoris** : `private.message_favorites`, personnels ; `set_message_favorites` accepte
  plusieurs messages (sélection multiple, 100 au plus) ; `list_favorite_messages`.
  Épinglés et favoris disparaissent avec le message (filtrés dès l'expiration, effacés en
  cascade à la purge) : la durée de vie d'un message n'est jamais prolongée.
- **Infos d'un message** : les accusés restent des bornes (`delivered_up_to`,
  `read_up_to`) ; `private.receipt_marks` note quand elles avancent (gardé 4 jours, purge
  quotidienne). `get_message_info` (auteur seulement) donne, par destinataire présent à
  l'envoi, distribué / lu et l'heure ; la lecture est cachée si la personne a coupé ses
  accusés (`read_receipts_on`). `mark_conversation` garde la règle du lot 7.2b1-bis.
- **Mentions seulement** : `conversation_members.notify_mode` (`all` / `mentions`, groupes
  seulement) ; `push_targets` n'envoie plus rien en mode « mentions » sauf si la personne
  est @mentionnée (une mention passe aussi la sourdine, comme avant).
- **Sélection multiple** : côté application, avec les appels existants (supprimer pour moi,
  pour tout le monde) et `set_message_favorites`. « Pour tout le monde » n'est proposé que
  si chaque message sélectionné le permet. Pas de copie ni de transfert (engagements).
- Les messages courts de la discussion se remplacent au lieu de s'empiler.

## Preuves
pgTAP `27_confort2` ; `scripts/ci/confort_e2e.py` (PostgREST réel) ; tests Flutter
`test/ui/confort2_test.dart` (9 cas), suite complète 388 tests ; captures du lot.
