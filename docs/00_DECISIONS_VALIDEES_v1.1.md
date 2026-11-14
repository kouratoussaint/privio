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

