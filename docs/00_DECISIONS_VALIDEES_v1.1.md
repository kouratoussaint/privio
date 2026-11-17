# Décisions validées — PRIVIO v1.1 (amendement du 11 novembre 2026)

Ce document **amende** `dossier_v1.0/00_DECISIONS_VALIDÉES.md`. En cas de contradiction,
la v1.1 prévaut. Toutes les autres décisions de la v1.0 restent en vigueur.

## Amendement 1 — Chiffrement de bout en bout retiré du périmètre
Décision du commanditaire : pas d'E2EE au MVP **ni au lancement**.

Exigences retirées : SEC-001, SEC-002, SEC-003, SEC-010, GROUP-010 (volet chiffrement),
tests P0 « E2EE », invariant « impossible de désactiver le chiffrement ».

Exigences reformulées :
- **TTL-009** : les sauvegardes de la base (offre Pro : quotidiennes, 7 jours) peuvent contenir
  du contenu expiré jusqu'à 7 jours. Après toute restauration, la purge est relancée (décision B6).
- **« Pas de lecture admin »** : règle de procédure, plus une garantie technique. Aucun écran de
  la console n'affiche de contenu ; tout accès service-role est journalisé.
- **Promesse affichée (A2)** : « messages effacés après 72 h, protégés pendant leur transport ».
  Jamais « chiffré de bout en bout ». Un garde-fou CI bloque cette expression dans l'application.

## Décisions A1 à A6 (validées)
| # | Décision |
|---|---|
| A1 | Le serveur stocke le contenu sans l'indexer ni l'afficher en console ; il peut faire des validations techniques (durée des vocaux, format des photos, mentions). |
| A2 | Promesse affichée ci-dessus. |
| A3 | Le présent amendement. |
| A4 | Un seul appareil actif par compte. Une connexion OTP sur un nouveau téléphone révoque l'ancien (ses sessions Auth sont supprimées). Changement de numéro depuis l'appareil connecté, avec OTP sur le nouveau numéro (étape ultérieure). |
| A5 | Android 7.0 minimum (SDK 24), imposé par Flutter 3.47. |
| A6 | Dépôt GitHub privé, code propriétaire. |

## Points restant à trancher
B1 délais d'édition/suppression · B2 taille max des groupes (100 provisoire) ·
B3 conservation signalements/journaux · B4 connexion admin (vérifier la disponibilité MFA selon
l'offre Supabase) · B5 hébergement console · B6 sauvegardes · B7 budget + fournisseur SMS +226 ·
B8 sections vides du dossier v1.0.

**Nouveau (B9)** : numéros recyclés par les opérateurs — le nouveau détenteur d'un numéro
réattribué pourrait accéder au compte de l'ancien. Proposition : suppression automatique des
comptes inactifs après une durée à fixer, et alerte à la reconnexion d'un compte dormant.

**Nouveau (B10)** : conditions d'utilisation et politique de confidentialité à rédiger avant
le pilote (l'écran 02 recueille aujourd'hui un consentement aux engagements affichés uniquement).

## Amendement 2 — Design (lot 2.D, 12 novembre 2026)
Validé sur maquettes (canevas « PRIVIO — Maquettes lot 2.D ») :
- **Bulles envoyées : violet plein, texte blanc** (variante B). Modifie le guide de marque, qui
  prévoyait « violet très pâle ». Clair : `#5B1FB8` ; sombre : `#7A2FD9`. Contrastes AA vérifiés.
- **En-tête : violet profond `#5B1FB8`** (couleur issue du dégradé du logo n° 1), contenu sur
  une feuille claire à coins arrondis. Sombre : bleu nuit `#0C1438`.
- Navigation inchangée : Discussions / Groupes / Paramètres. Logo n° 1 uniquement.
- Aucun bouton non livré n'est affiché (photo, vocal, emoji, appel) : ils apparaissent avec leur lot.

## Amendement 3 — Retours sur le design et durée configurable (12 novembre 2026)
Demandés par le commanditaire après test sur téléphone :
- **Polices réduites de 8 %** sur toute l'application (le corps passe de 16 à 14,5 sp ; titres
  réduits d'autant). Plancher conservé à 12 sp, sauf l'heure et la minuterie des bulles (11 sp).
  Modifie l'échelle typographique du guide de marque.
- **Informations hors message** (heure, minuterie, « modifié », accusés) plus petites et
  semi-transparentes ; contraste perçu ≥ 4,5:1 vérifié par les tests.
- **Réactions** : petite pastille sans contour, accrochée au coin inférieur de la bulle, sans
  recouvrir le texte ni le message suivant.
- **Fond des discussions** : motif original « vie privée » (cadenas, bouclier, clé, œil barré,
  minuterie, empreinte, bulle) à 6-7 % d'opacité. Dessin propre à Privio, sans reprise d'un
  motif existant.
- **Nouvelle fonctionnalité — durée d'expiration configurable** (ajout au cahier des charges) :
  - par discussion : 5 min, 1 h, 8 h, 24 h ou 72 h ; réglable par chaque membre ; s'applique
    aux nouveaux messages ; un message système annonce le changement aux deux personnes ;
  - par message : choisie dans la zone de saisie pour le prochain message seulement, jamais
    plus longue que la durée de la discussion ;
  - bornes : minimum administrable (`message_ttl_min_minutes`, 5 min par défaut), maximum =
    invariant 72 h (`message_ttl_hours`), toujours imposé par le serveur.

## Amendement 4 — Signalement et suppression de compte (lot 2.5, 12 novembre 2026)
- **B3 (appliquée par défaut, administrable)** : signalements et copie d'un message signalé
  conservés **90 jours** (`report_retention_days`), puis effacés par la purge automatique.
  Journaux techniques : 30 jours, à appliquer avec la console (lot 5).
- **Copie du message signalé** : jointe uniquement si la personne qui signale coche la case
  (cochée par défaut, explicitement expliquée) ; lue par la seule équipe de modération.
- **Suppression de compte** : confirmation par saisie de « SUPPRIMER » ; messages envoyés
  effacés chez tous les correspondants ; profil, numéro, appareils, blocages et appartenances
  supprimés ; cache local et clé détruits. Les signalements visant le compte restent jusqu'à
  échéance, sans lien vers le compte.

## Amendement 5 — Groupes, actions rapides, notifications (12 novembre 2026)
- **B2** : taille maximale d'un groupe **25 membres** par défaut, réglable par l'administration
  entre 2 et 100 (`group_max_members`). Remplace la valeur provisoire de 100.
- **Actions rapides (ajout au cahier des charges, lot 2.F)** : glisser un message vers la droite
  = répondre ; double appui = réaction par défaut (❤️, réglable dans les Paramètres ; pas sur
  les vocaux, pour ne pas retarder leurs boutons) ; glisser vers la gauche = supprimer, toujours
  avec choix et confirmation ; toucher une citation = remonter au message d'origine ; dans la
  liste, glisser à droite = épingler, à gauche = archiver (avec « Annuler »). Toutes ces
  actions restent disponibles par l'appui long et pour TalkBack.
- **Notifications (lot 4.1)** : sans contenu ni nom, voir ADR-011.

## Amendement 6 — Console d'administration dans l'application (13 novembre 2026)
- **B4 / B5** : la console d'administration est **entièrement intégrée à l'application
  mobile**. Il n'y a ni console web ni hébergement séparé (B5 sans objet).
- **Accès** : réservé au **seul compte dont le numéro vérifié est +226 75 49 35 18**. Pour
  tout autre compte, la console n'existe pas (aucune entrée visible).
- **Contrôle côté serveur** : le droit d'administrer est vérifié par la base pour chaque
  action (fonctions réservées, jamais une simple condition dans l'application). Le numéro de
  l'administrateur est enregistré dans un réglage privé du serveur, modifiable par
  déploiement, et non écrit dans le code de l'application.
- Les rôles multiples prévus au dossier v1.0 (opérateur, support, analyste, sécurité) ne
  sont pas créés en v1 : un seul administrateur. La protection supplémentaire de l'accès
  (code ou empreinte à l'ouverture de la console, appui sur le verrouillage du lot 4.2) sera
  proposée et validée au lot 5.1.
- **Validé le 13/11/2026 (lot 5.1, ADR-015)** : code Privio ou empreinte à chaque ouverture
  (verrouillage obligatoire pour ouvrir la console) ; console refermée après 5 min sans action
  et à la sortie de l'app. Tableau de bord en nombres seulement : comptes et activité,
  groupes et demandes, santé technique, signalements en attente. Chaque consultation est
  journalisée (90 jours).

## Amendement 7 — Confidentialité et « vider la discussion » (13 novembre 2026)
- L'utilisateur règle le maximum de sa confidentialité : statut « en ligne » / « vu à »,
  photo de profil, invitations dans les groupes (tout le monde / mes contacts / personne),
  accusés de lecture, indicateur d'écriture, durée par défaut des messages. Réglages **non
  réciproques**. Détails : ADR-013.
- **Vider la discussion** : effacement de tous les messages **sans aucune trace** (pas de
  « Message supprimé »). Deux choix : pour nous deux **avec l'accord de l'autre**, ou
  seulement chez moi. Dans un groupe, les **administrateurs** vident pour tous.

## Amendement 8 — Demande de connexion avant le premier message (13 novembre 2026)
- On ne peut plus écrire directement à une personne avec qui l'on n'a pas encore de
  discussion : le premier contact est une **demande de connexion** (petit mot facultatif de
  140 caractères). La personne **accepte** (la discussion s'ouvre chez les deux), **refuse**
  (l'expéditeur est **prévenu**) ou **bloque**. Demandes croisées : connexion immédiate.
- Le mot devient le premier message après acceptation et **s'efface 5 minutes plus tard** ;
  en cas de refus ou d'expiration, il est effacé aussitôt.
- Une demande sans réponse **expire après 24 h** ; après un refus, **5 minutes** d'attente ;
  **3 demandes au plus vers une même personne par jour** (décision A). Valeurs administrables.
- Réglage personnel « Qui peut m'envoyer une demande » : tout le monde (défaut) / personne.
- Les discussions existantes restent ouvertes ; écrire en privé à un membre d'un groupe
  passe aussi par une demande. Détails : ADR-014.

## Amendement 9 — Réglages et statistiques dans la console (13 novembre 2026, lot 5.2)
- Tous les réglages en service sont modifiables depuis la console (les techniques dans
  « Avancé ») ; simple confirmation « avant → après » à chaque changement ; retour à la valeur
  par défaut et « Rétablir » depuis l'historique.
- Invariants non modifiables : 72 h au plus, captures d'écran, copie, transfert, partage,
  export et galerie interdits, fuseau des quotas ; les fonctions non développées (vidéos,
  documents, appels vidéo) ne peuvent pas être activées.
- Statistiques sur 30 jours, nombres anonymes seulement ; comptes actifs relevés chaque soir.
- Réglages propres à un groupe ou à un compte : reportés. Un seul administrateur en v1.
  Détails : ADR-016.

## Amendement 10 — Modération (13 novembre 2026, lot 5.3)
- Décisions : classer sans suite, avertir, suspendre (24 h, 7 jours, 30 jours, sans limite),
  réactiver, supprimer le message signalé, fermer un groupe signalé. Motif interne obligatoire,
  jamais montré à la personne ; elle voit le motif du signalement (spam, harcèlement…).
- La console affiche l'@identifiant de la personne qui signale et de la personne signalée,
  jamais leur numéro. La copie jointe (texte, photo, vocal) s'affiche à la demande ; chaque
  lecture est journalisée.
- Une contestation par sanction. Le compte de l'administration ne peut pas être sanctionné.
- Notification sans contenu à l'administration pour chaque signalement, demande d'assistance
  et contestation.
- Compte suspendu : l'application affiche l'écran « Compte suspendu » (motif, fin,
  contestation) au lieu de déconnecter ; le serveur refuse tout le reste.
- Sanctions gardées 1 an (sauf suspension sans limite encore active). Lot 5.4 : comptes et
  réponses aux demandes d'assistance. Détails : ADR-017.

## Amendement 11 — Comptes et assistance (14 novembre 2026, lot 5.4)
- Recherche de comptes par @identifiant, par nom, ou par numéro COMPLET seulement ; le numéro
  n'est jamais affiché ni inscrit au journal ; chaque recherche et chaque fiche ouverte sont
  journalisées.
- Fiche sans numéro, contact, discussion ni message ; avertir, suspendre ou réactiver sans
  signalement ; « Déconnecter le téléphone » (perte ou vol) ; compte administrateur protégé.
- Une réponse par demande d'assistance (modèles modifiables), notifiée sans contenu, lisible
  dans Aide → Mes demandes ; pour continuer, la personne envoie une nouvelle demande.
  Détails : ADR-018.

## Amendement 12 — Fiches, invitations par code, @mentions (14 novembre 2026, lot 7.1)
- Lot 7.1 découpé : 7.1a (fiches contact et groupe) puis 7.1b (rejoindre un groupe, @mentions).
- « À propos » : 140 caractères ; visible par défaut par « Mes contacts » (réglage « Qui voit
  mon À propos » : tout le monde, mes contacts, personne).
- Médias de la discussion : seulement ceux encore présents (72 h au plus), jamais enregistrables.
- 7.1b : invitation de l'extérieur par code et QR code dans l'application (pas de lien web) ;
  accord d'un administrateur obligatoire par défaut, désactivable par groupe ; une @mention
  notifie la personne même si le groupe est en sourdine.
- Précisions de mise en œuvre (7.1b, ADR-019) : 20 essais de code par heure (réglable dans la
  console) ; une personne retirée par un administrateur repasse toujours par une demande ;
  après un refus, pas de nouvelle demande pendant 24 h.

## Amendement 13 — Finitions, animations et sons (14 novembre 2026, lot 7.2)
- Lot 7.2 découpé : 7.2a (finitions et corrections), 7.2b (animations, sons, illustrations
  animées), puis 7.2c (le « confort » prévu : bouton descendre, non lus, sélection, etc.).
- Fonds : les écrans en liste sont blancs (comme Discussions) ; les écrans de réglages et les
  fiches ont un fond clair et une carte blanche par section (comme Paramètres).
- « Vider la discussion » depuis une fiche : le choix et la confirmation s'ouvrent sur la
  fiche, qui reste affichée.
- « Ma fiche » (Paramètres → ligne du profil) : photo, **nom modifiable** (quelques fois par
  jour), À propos ; l'@identifiant ne se change pas (décision : non).
- Confidentialité propre à une discussion : accusés de lecture et « en train d'écrire »
  (discussions et groupes) ; en ligne / vu à, photo, À propos (discussions à deux, pour ce
  contact). Chaque réglage : comme dans mes réglages, activé ou désactivé.
- « Hors connexion » : un échec isolé (retour de veille) n'est plus annoncé ; vérification
  silencieuse, puis bandeau au bout de 5 s si le serveur reste injoignable.
- 7.2b validé en entier (transitions, animations de la discussion, verrouillage, sons courts
  créés pour Privio, illustrations animées dessinées en code) ; réglage « Sons et vibrations
  dans l'application » activé par défaut ; « réduire les animations » du téléphone respecté.

## Amendement 14 — Lu à l'écran, suppressions, groupes séparés (14 novembre 2026, lot 7.2b1)
- 7.2b découpé : 7.2b1 (ces corrections, livré d'abord), puis 7.2b2 (animations et sons).
- « Lu » n'est envoyé que si la discussion est vraiment à l'écran (application au premier plan
  et déverrouillée, discussion au-dessus de tout) ; sinon seulement « distribué ».
- Supprimer une discussion à deux : « Seulement chez moi » (elle revient, vide, avec un
  nouveau message) ou « Pour nous deux » (accord de l'autre, comme pour vider).
- Supprimer un groupe : le créateur **et les administrateurs**, pour tous ; chaque membre voit
  une ligne « Le groupe X a été supprimé » dans l'onglet Groupes (pas de notification). Un
  membre « Quitte et supprime ». Un groupe fermé par Privio ne se supprime pas.
- Groupes et discussions **séparés par défaut** ; réglage « Groupes dans Discussions » dans
  Paramètres pour les remettre ensemble.


## Amendement 15 — Animations, sons, photos à côté des messages (14 novembre 2026, lot 7.2b2)
- Liste d'animations et de sons validée (amendement 13) ; réglage « Sons et vibrations »
  activé par défaut. Sons courts créés pour Privio (aucun son tiers), muets en mode silencieux
  du téléphone ; « Réduire les animations » du téléphone respecté.
- Ajout demandé : **photo de l'auteur à côté des messages reçus**, dans une discussion
  (photo du correspondant) comme dans un groupe (photo du membre, ou ses initiales). Elle se
  place à côté du dernier message d'une suite du même auteur ; dans un groupe, le nom de
  l'auteur n'apparaît qu'en tête de sa suite.

## Amendement 16 — Lot 7.2c : confort (14 novembre 2026)
- Ajouts au lot : photo du groupe visible et ajoutable dès la création ; dans l'onglet Groupes,
  recherche et filtres comme dans Discussions ; actions rapides sur les groupes (épingler,
  archiver, quitter et supprimer, supprimer pour tous).
- Messages épinglés : dans une discussion à deux, les deux personnes ; dans un groupe, les
  administrateurs ; 3 au plus à la fois.
- Favoris et messages épinglés **s'effacent avec le message** : ils ne prolongent jamais sa
  durée de vie (engagement d'effacement inchangé).
- Notifications d'un groupe : option « Mentions seulement » (en plus de la sourdine).
- Découpage : 7.2c1 (photo du groupe, Groupes, actions rapides, bouton « descendre »,
  repère des non lus), puis 7.2c2 (sélection multiple, infos du message, épinglés, favoris,
  mentions seulement).

## Amendement 17 — Lot 7.3 : expression (14 novembre 2026)
- Google a fermé le service Tenor aux applications le 30 juin 2026 : **KLIPY** fournit les
  GIF ; « tout public » par défaut, avec un réglage ; images de la recherche servies par
  KLIPY (seulement quand l'onglet GIF est ouvert) ; le GIF choisi est copié dans le
  stockage privé de Privio et s'efface avec le message.
- Autocollants : 24 dessins originaux (mascotte « Bulle »), en français ; ajustements et
  éventuelles expressions en mooré et dioula plus tard.
- Aperçu des liens préparé par le serveur de Privio (le site ne voit pas les personnes) ;
  réglage « Aperçus des liens » dans Confidentialité, activé par défaut.
- Fond d'écran : par défaut dans Paramètres, et propre à une discussion depuis sa fiche ;
  une photo choisie reste sur le téléphone.
- Vue unique : photos et vocaux.
- Découpage : 7.3a (émojis, autocollants, retouche photo, fond d'écran), puis 7.3b (vue
  unique, GIF, aperçus des liens).

## Amendement 18 — Santé du service et lot 10.4 (17 novembre 2026)
- **Lot 5.7 avant 10.4** (choix du 17/11/2026). Rubrique « Santé du service » de la
  console (ADR-047).
- **A** : version **conseillée** (bandeau, fermable) et version **minimale** (écran
  bloquant), comparées au numéro de compilation ; lien de téléchargement réglable dans la
  console.
- **B** : alertes de l'administration par notification sans contenu, au plus une par type
  toutes les 6 h : effacements automatiques en retard, pic de codes SMS, échecs de
  notifications ou d'appels, relais des appels au-delà de 80 % du volume gratuit.
- **C** : parcours d'inscription compté **par le serveur** (codes envoyés, vérifiés, profils
  créés, changements de numéro compris) ; coût estimé avec un prix unitaire saisi dans la
  console. Aucun numéro conservé pour ces chiffres.
- **Lot 10.4 (décisions prises, à développer)** : « Vérifié en personne » par QR code
  temporaire (2 min) scanné face à face, visible sur les deux téléphones ; badge retiré
  quand le contact change de téléphone ou de numéro, avec un avis pour revérifier ; surnom
  privé visible par moi seul, partout dans l'application, vrai nom rappelé dans la fiche,
  gardé sur le serveur pour mon compte.

## Amendement 19 — « Vérifié en personne » et surnom privé (17 novembre 2026)
Lot 10.4 développé selon les décisions de l'amendement 18 (ADR-048).
- **Vérification** : QR code créé pour un contact précis, valable 2 minutes, à usage
  unique (seule son empreinte est gardée) ; un seul scan, face à face, vérifie les deux
  personnes. Elle atteste une rencontre, sans chiffrement de bout en bout.
- **Badge retiré** quand le contact se connecte à nouveau (Privio ne reconnaît pas un
  téléphone d'une connexion à l'autre : une reconnexion compte comme un nouveau
  téléphone) ou change de numéro ; avis fermable dans la discussion, qui revient si la
  situation change encore.
- **Surnom privé** : 40 caractères, pour une personne avec qui je partage une discussion
  (à deux ou de groupe) ; il remplace le nom partout pour moi ; la fiche montre
  « Surnom · vrai nom » ; une @mention insère toujours le vrai nom.

## Amendement 20 — Groupes « Annonces » et sondages éphémères (17 novembre 2026)
Lot 10.5 (ADR-049).
- **A** : « Annonces » est un vrai type de groupe, choisi à la création et définitif : seuls
  les administrateurs écrivent ; un membre ne voit ni la liste ni les numéros des autres
  membres ; jusqu'à 500 membres, réglable dans la console.
- **B** : les membres d'un groupe « Annonces » réagissent et votent aux sondages ; ils
  n'écrivent pas.
- **C** : sondages dans les groupes, par toute personne qui peut y écrire (seulement les
  administrateurs dans un groupe « Annonces ») ; pas dans les discussions à deux.
- **D** : le créateur choisit « vote anonyme » (par défaut : totaux seulement, même pour
  lui) ou « votes visibles » (noms des votants ; jamais montrés à un simple membre d'un
  groupe « Annonces »).
- Par défaut (proposés le 17/11/2026) : 2 à 10 choix, une réponse ou plusieurs ; vote
  modifiable tant que le sondage est ouvert ; fermeture par son créateur ; effacé avec les
  messages, jamais par « Effacer après lecture ».

