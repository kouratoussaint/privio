# ADR-021 — « Lu » à l'écran seulement ; supprimer une discussion ou un groupe

**Statut** : accepté (lot 7.2b1, décisions du 14/11/2026, amendement 14).

## Contexte
Une discussion ouverte se recharge toutes les 5 s et à chaque signal temps réel ; chaque
rechargement envoyait « lu ». Fiche ouverte par-dessus, application réduite, téléphone ou
Privio verrouillés : les messages étaient marqués lus sans avoir été vus.

## Décision
- `chatOnScreenProvider` : la discussion réellement affichée (application visible, Privio
  déverrouillé, route au-dessus de tout). `ChatController` n'envoie `read_up_to` que pour
  elle ; sinon seulement `delivered_up_to`. Quand elle revient à l'écran, ce qu'elle
  contient est marqué lu à ce moment. À la mise en arrière-plan, le retrait est immédiat
  (aucune image n'est dessinée quand l'application est cachée).
- `delete_conversation(p_conversation_id, p_scope)` :
  - discussion à deux, `me` : `hidden_at` et `cleared_before` (copie vidée) ; la liste
    l'exclut jusqu'au prochain message ;
  - discussion à deux, `everyone` : demande `clear_requests.then_delete` (même accord et même
    limite que « vider pour nous deux ») ; acceptée, la discussion est vidée et retirée des
    deux listes ;
  - groupe : créateur ou administrateur, groupe non fermé par Privio ; un avis par membre
    (`private.group_deletion_notices`, 30 jours), signal `group_deleted`, puis suppression de
    la discussion (messages, médias, invitations, codes, demandes : en cascade, fichiers
    effacés par la purge des médias).
- L'application efface sa copie locale des discussions qui ne sont plus listées.
- Séparation : préférence locale `groups_in_discussions` (faux par défaut) ; séparés, les
  groupes non lus comptent dans la pastille de l'onglet Groupes.

## Preuves
pgTAP `25_suppression`, `scripts/ci/suppression_e2e.py`, tests Flutter
`test/ui/suppression_test.dart` (fiche par-dessus, application cachée, suppressions,
séparation).
