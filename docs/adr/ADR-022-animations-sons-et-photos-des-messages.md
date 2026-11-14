# ADR-022 — Animations, sons, illustrations animées ; photo à côté des messages

**Statut** : accepté (lot 7.2b2, décisions du 14/11/2026, amendements 13 et 15).

## Contexte
L'application paraissait figée : aucune transition, aucun retour sonore, des icônes
statiques. La liste des éléments animés et sonores a été validée (amendement 13), avec la
photo de l'auteur à côté des messages (amendement 15).

## Décision
- **Règles communes** (`ui/core/motion/motion.dart`) : durées courtes (160, 260, 420 ms),
  « Réduire les animations » du téléphone respecté (état final directement), animations en
  boucle figées dans les tests automatiques (`Motion.loopsEnabled`). Aucune minuterie : les
  délais font partie des contrôleurs d'animation.
- **Transitions d'écran** : glissement léger et fondu (`PrivioPageTransitionsBuilder`).
- **Discussion** : bulle envoyée qui monte de la zone de saisie, message reçu en fondu,
  coches qui se dessinent, points d'écriture animés, micro ↔ envoyer qui se transforme,
  réaction qui saute et émoji qui s'envole au double appui, message supprimé pour tous qui se
  froisse, messages expirés, vidés ou supprimés chez moi qui se dissolvent (en cascade quand
  la discussion est vidée), balai depuis une fiche.
- **Ailleurs** : pastilles et onglet choisi qui rebondissent, bandeau « hors connexion » qui
  glisse, lignes fantômes pendant le chargement, coche de réussite dans les messages
  « enregistré », « copié », « demande envoyée »…, points du code qui se remplissent et se
  secouent sur un code faux.
- **Illustrations dessinées par l'application** (`illustrations.dart`) : logo qui respire
  (démarrage, accueil, verrou), trois petites scènes à l'accueil, icônes animées des
  engagements, de l'aide, des autorisations, du numéro et du code SMS, des écrans vides.
  Aucune image animée téléchargée (poids, données mobiles).
- **Sons** (`assets/sounds`, 82 Ko au total, générés par `tools/sons/generer_sons.py`) :
  envoi, réception (discussion à l'écran seulement), vider, supprimer, réaction, début et fin
  de vocal, déverrouillage, code faux, réussite. Lecture courte sans prendre le focus audio
  (la musique en cours n'est pas coupée), muette en mode silencieux. Vibrations légères aux
  mêmes moments. Réglage local « Sons et vibrations » (activé par défaut), lu au démarrage :
  tant qu'il n'est pas lu, silence.
- **Photo à côté des messages reçus** : colonne de 28 px à gauche des messages reçus, photo
  sur le dernier message d'une suite du même auteur (même jour) ; discussion à deux : photo
  du correspondant (selon sa confidentialité), groupe : photo du membre ou ses initiales.
  Dans un groupe, le nom de l'auteur seulement en tête de sa suite.
- Non retenu pour l'instant : l'avatar qui « vole » de la liste vers la discussion (Hero),
  incompatible avec les onglets gardés en mémoire (mêmes avatars dans deux onglets).

## Preuves
Tests Flutter `test/ui/animations_sons_test.dart` (sons joués, réglage coupé, photo sur le
dernier message d'une suite, dissolution en cascade, animations réduites), suite complète
368 tests ; captures du lot.
