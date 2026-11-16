# ADR-044 — Effacer après lecture

**Statut** : accepté (lot 10.1, décisions du 16/11/2026 : A délais 30 s / 5 min / 1 h ;
B activation par l'une ou l'autre personne d'une discussion à deux, par les administrateurs
d'un groupe ; C dans un groupe, délai propre à chaque lecteur, suppression pour tous quand
tout le monde a lu ; D la copie de l'expéditeur disparaît après lecture plus le délai ;
E seulement les messages envoyés après l'activation).

## Décision
- **Réglage** : `conversations.read_erase_seconds` (30, 300, 3600 ou null) ;
  `set_read_erase(conversation, secondes)` vérifie le droit (B : `NOT_ADMIN` pour un membre de
  groupe, `BLOCKED`, `GROUP_CLOSED`, `READ_ERASE_INVALID`) et ajoute un message système
  `erase:N` (`erase:0` : désactivé). `list_conversations` renvoie le réglage.
- **E** : un déclencheur `before insert` copie le réglage sur chaque message
  (`messages.read_erase_seconds`), quel que soit le chemin d'envoi (texte, vocal, photo, GIF,
  autocollant, vue unique) ; jamais sur un message système. Changer le réglage ne touche pas
  aux messages déjà envoyés.
- **Lecture** : quand `mark_conversation` avance le « lu » d'un membre, chaque message
  concerné reçu jusque-là obtient une échéance pour ce lecteur (`private.read_erasures` :
  lecture + délai). Le message est relu par le téléphone du lecteur (signal
  `message_changed`), avec cette échéance comme `expires_at` : l'application l'efface à la
  seconde près (réveil dédié dans la discussion), même hors connexion.
- **C/D** : quand tous les membres qui pouvaient voir le message (hors expéditeur, présents)
  l'ont lu, `messages.expires_at` devient la dernière échéance : le message disparaît pour
  tout le monde, expéditeur compris, puis la purge habituelle le supprime du serveur (et ses
  fichiers). Dans une discussion à deux, c'est dès la lecture de l'autre personne.
- **Partout côté serveur** : `get_messages` et `list_conversations` appliquent l'échéance du
  lecteur ; `visible_message` (réagir, répondre, épingler…) et la lecture des fichiers
  (`can_read_photo`, `can_read_voice`, `can_read_gif`, `can_read_preview`) la refusent ; une
  tâche chaque minute (`apply_read_erasures`) masque les messages échus chez le lecteur
  (favoris, médias, épinglés) et termine les suppressions « lus par tous » si un membre est
  parti entre-temps.
- **Limite des 72 h** inchangée : un message jamais lu s'efface à sa durée normale.
- **Application** : ⋮ → « Effacer après lecture » (feuille : Désactivé, 30 secondes,
  5 minutes, 1 heure) ; bandeau rose « Effacement après lecture : 5 minutes » sous l'en-tête
  (touchable si l'on peut régler) ; annonce dans la discussion ; petite flamme à côté de
  l'heure des messages concernés.

## Limites connues
- Un membre qui ne rouvre jamais un groupe garde le message chez les autres jusqu'à sa
  lecture ou aux 72 h (le message n'est supprimé pour tous que quand tout le monde a lu).
- Comme pour le reste de Privio, rien n'empêche une photo de l'écran prise avec un autre
  appareil ; les captures d'écran restent bloquées (FLAG_SECURE).

## Preuves
`supabase/tests/database/38_effacer_apres_lecture.test.sql` (discussion à deux et groupe :
droits, messages suivants seulement, échéance par lecteur, copie de l'expéditeur, masquage
chez le lecteur seulement, suppression quand tous ont lu) ; `test/ui/effacer_apres_lecture_test.dart`
(3 cas) ; test d'intégration complet inchangé et vert.
