# ADR-051 — Autocollants personnels

**Statut** : accepté (lot 7.4, retours de tests et décisions du 17/11/2026 : création depuis
une photo avec détourage automatique sur le téléphone, collection gardée sur le serveur
pour mon compte, option « Partageable » choisie à la création).

## Décision
- **Création, sur le téléphone** : photo (appareil ou galerie) réduite et nettoyée comme
  pour un envoi ; détourage du sujet par Google ML Kit (`google_mlkit_subject_segmentation`,
  modèle fourni par les services Google Play, déclaré dans le manifeste) ; si le détourage
  échoue, la photo entière se recadre. Pincer et glisser dans un cadre carré ; texte
  facultatif (30 caractères, blanc cerné de noir) ; interrupteur « Partageable ». Image
  finale : PNG transparent de 512 px, réduit au besoin sous 500 Ko.
- **Collection** (migration `20261118000200`) : `private.user_stickers`, 60 par compte
  (`STICKER_LIMIT`), 30 créations par heure ; fichiers dans le compartiment privé
  « stickers » sous `<compte>/<id>`, lisibles par leur propriétaire seul
  (`private.can_read_sticker`). Rien de la collection n'est un message : elle n'est pas
  soumise aux 72 h, et son propriétaire la vide quand il veut (appui long → « Retirer »).
- **Fonction « sticker »** (jeton de l'utilisateur, toutes les règles dans la base ; clé de
  service seulement pour les fichiers) : `add` (PNG ou WebP vérifié, 512 px et 512 Ko au
  plus), `remove`, `send`, `save`.
- **Envoi** : le serveur recopie le fichier pour le message (`msg/<discussion>/…`, suivi
  dans `private.media_objects` comme un GIF) ; message de type `sticker`, corps
  `perso/partageable` ou `perso/prive`, dimensions renseignées. La copie s'efface avec le
  message (72 h au plus, suppression pour tous, effacement de la discussion) ; retirer
  l'autocollant de ma collection ne touche pas les messages envoyés. Envoi en ligne
  seulement (pas de file d'attente hors connexion).
- **Ajouter un autocollant reçu** : seulement s'il est `perso/partageable`
  (`STICKER_NOT_SHAREABLE` sinon) ; le serveur recopie le fichier dans ma collection, où
  il reste partageable.
- **Application** : onglet « Autocollants » du panneau 😊 → « Mes autocollants » (bande
  horizontale : « + » pour créer, toucher pour envoyer, appui long pour retirer), puis les
  autocollants Privio ; bulle sans fond comme les autres autocollants ; appui long sur un
  autocollant partageable reçu → « Ajouter à mes autocollants ».

## Limites
- Le détourage dépend des services Google Play (installés sur la plupart des téléphones
  Android) ; au premier usage, le modèle peut demander une connexion.
- Les versions antérieures au lot 7.4 affichent un autocollant personnel reçu comme un
  autocollant sans image.
- Pas d'autocollant animé.

## Preuves
pgTAP `43_autocollants_perso` (réservation, dépôt validé par le serveur seulement, 512 px
et 512 Ko, collection privée, 60 au plus, envoi idempotent après copie, partageable ou
privé, lecture par le destinataire seulement, ajout refusé pour un privé, copie effacée
avec le message, collection intacte, retrait) ; `scripts/ci/stickers_e2e.py` (vrai
Storage et fonction « sticker ») ; tests Flutter `autocollants_perso_test.dart`.

## Correctif du 19/11/2026 (7.4-bis)
Sur téléphone, rien ne se passait après le choix de la photo. Pendant le choix, Privio
passe en arrière-plan ; au retour, le panneau des autocollants peut s'être refermé (le
champ de saisie reprend le focus). Le parcours dépendait du bouton « + » de ce panneau et
s'arrêtait en silence avant d'ouvrir l'éditeur. Désormais, tout ce dont il a besoin
(navigation, annonces, verrou, sélecteur et préparation de la photo) est pris dès le
toucher du « + » ; seul l'écran de la discussion doit rester ouvert. Nouveau test
`le panneau se referme pendant le choix de la photo` (il échoue avec l'ancienne version).
