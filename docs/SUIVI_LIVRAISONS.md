# PRIVIO — Suivi des livraisons

Mis à jour à chaque livraison. Dernière mise à jour : 13/11/2026 — 2.F, 4.2 et 4.3 validés ; 4.4 et 4.5 livrés (à tester) ; feuille de route étendue (lots 4.5 à 4.7, étapes 7 à 9). Statuts : ✅ validé · 🧪 livré, à tester · 🔨 en cours · ⏳ à venir · ⛔ bloqué.

Chaque lot se clôt par : CI verte + APK (sauf lots serveur) + vos tests sur téléphone.
Un lot n'est validé qu'après votre retour.

## Étape 1 — Fondation
| Lot | Contenu | Vos tests | Statut |
|---|---|---|---|
| — | Clé de signature stable (installation par-dessus) | Mise à jour sans désinstaller | ✅ 12/11/2026 |
| 1.0 | Connexion téléphone + code, profil, appareil unique, politiques, CI, logo provisoire | Inscription, 3 onglets, capture bloquée | ✅ 12/11/2026 |

## Étape 2 — Discussions 1:1
Prérequis de test à partir du lot 2.2 : **deux téléphones** avec deux numéros de test
(70 00 00 01 et 70 00 00 02), car un compte ne s'ouvre que sur un appareil.

| Lot | Contenu | Vos tests | Statut |
|---|---|---|---|
| 2.1 | Serveur : conversations, messages, expiration 72 h + purge automatique, accusés, réactions, réponses, modification (60 min), suppression pour tous (jusqu'à l'expiration), blocage, temps réel | Aucun (preuve : CI + déploiement staging) | ✅ 12/11/2026 |
| 2.2 | App : liste des discussions, recherche d'une personne, démarrer une discussion, conversation de base (texte, temps réel), fiche contact, bloquer | Trouver l'autre compte, échanger des messages, bloquer/débloquer | ✅ 12/11/2026 |
| 2.3 | App : accusés envoyé/reçu/lu, réponses citées, réactions, modification (60 min), suppression pour moi / pour tous, accessibilité des bulles | Appui long sur un message, accusés entre les deux téléphones | ✅ 12/11/2026 |
| 2.4 | App : stockage local chiffré, envoi hors ligne, effacement local à expiration même hors ligne, recherche, épinglage, archivage, indicateur « en train d'écrire » | Mode avion : écrire, puis se reconnecter | ✅ 12/11/2026 |
| 2.5 | Signalement (message, contact), assistance, suppression de compte, aide | Signaler un message, supprimer un compte de test | ✅ 12/11/2026 |

## Lot 2.D — Design (inséré avant le lot 2.4)
| Lot | Contenu | Vos tests | Statut |
|---|---|---|---|
| 2.D-1 | Maquettes clair/sombre (accueil, discussions, conversation, paramètres) | Validation visuelle | ✅ 12/11/2026 — bulles B, en-tête violet profond |
| 2.D-2 | Intégration dans l'application, captures avant/après | Parcourir l'app en clair et en sombre | ✅ 12/11/2026 (retours intégrés au 2.D-3) |
| 2.D-3 | Corrections : polices −8 %, heure discrète, réactions compactes, motif « vie privée » | Lire une conversation | ✅ 12/11/2026 |

## Lot 2.E — Durée d'expiration configurable (ajout du 12/11/2026)
| Lot | Contenu | Vos tests | Statut |
|---|---|---|---|
| 2.E | Durée par discussion (5 min à 72 h, annonce aux deux) et par message (jamais plus que la discussion) | Régler 1 h, envoyer un message de 5 min | ✅ 12/11/2026 |

## Lot 2.F — Actions rapides (ajout du 12/11/2026)
| Lot | Contenu | Vos tests | Statut |
|---|---|---|---|
| 2.F | Glisser à droite = répondre ; double appui = réaction (❤️, réglable) ; glisser à gauche = supprimer (avec choix) ; toucher une citation = remonter au message ; liste : glisser à droite = épingler, à gauche = archiver (« Annuler ») | Essayer chaque geste sur un message reçu et sur un message envoyé | ✅ 13/11/2026 |

## Étape 3 — Médias et groupes
| Lot | Contenu | Vos tests | Statut |
|---|---|---|---|
| 3.1 | Messages vocaux : micro (toucher = mains libres, maintenir = glisser pour annuler ou verrouiller), arrêt automatique à 30 s, préécoute obligatoire, lecture avec vitesse 1×/1,5×/2×, envoi hors ligne ; serveur : stockage privé, durée mesurée, effacement physique à l'expiration (ADR-008) | Envoyer un vocal de 10 s et l'écouter sur l'autre téléphone ; laisser l'enregistrement aller jusqu'à 30 s ; régler 5 min et vérifier qu'il disparaît des deux côtés | ✅ 12/11/2026 |
| 3.2 | Photos : appareil photo ou galerie (aucune autorisation), aperçu avec légende, compteur du jour (5, groupes inclus, remboursé si l'envoi échoue), visionneuse sans enregistrement ni partage, envoi hors ligne ; métadonnées (GPS…) retirées sur le téléphone ET par le serveur ; photo de profil (Paramètres) visible sauf en cas de blocage (ADR-009) | Envoyer une photo avec légende et l'ouvrir sur l'autre téléphone ; envoyer 5 photos puis vérifier le refus de la 6e ; mettre une photo de profil et la voir chez l'autre ; bloquer puis vérifier qu'elle disparaît | ✅ 12/11/2026 |
| 3.3 | Groupes : création, invitations à accepter ou refuser, rôles (propriétaire, administrateurs, membres), retrait, départ (groupe confié automatiquement), réglages (qui écrit, qui modifie), nom, description, photo du groupe, sourdine, signalement du groupe, historique visible depuis l'arrivée, filtre « Groupes » ; taille max **25** (B2, réglable 2–100) (ADR-010) | Créer un groupe et inviter l'autre téléphone ; accepter l'invitation ; échanger texte, vocal et photo ; nommer administrateur ; activer « Seuls les administrateurs écrivent » et vérifier le bandeau chez l'autre ; retirer puis réinviter ; quitter le groupe | ✅ 12/11/2026 |

## Étape 4 — Notifications et confidentialité
| Lot | Contenu | Statut |
|---|---|---|
| 4.1 | Notifications FCM sans contenu ni nom, masquées sur l'écran verrouillé, une par discussion ; ouverture de la discussion au toucher ; interrupteur dans les Paramètres ; pas de notification en sourdine, en cas de blocage ou pour l'expéditeur (ADR-011). **Compte de service FCM requis** (secret `FCM_SERVICE_ACCOUNT_B64`, en place sur staging) | ✅ 13/11/2026 |
| 4.2 | Verrouillage : code Privio à 6 chiffres + empreinte facultative, délai réglable, attente après 5 erreurs, « code oublié » = déconnexion ; bandeau hors connexion immédiat et reprise automatique ; écran « Stockage et données » : photos reçues téléchargées toujours / en Wi-Fi / à la demande, données consommées par mois, place occupée et effacement des médias (ADR-012). **Tests** : activer le code, fermer puis rouvrir Privio ; se tromper 5 fois ; essayer l'empreinte ; régler « Jamais » et recevoir une photo ; couper puis remettre les données mobiles | ✅ 13/11/2026 |
| 4.3 | Confidentialité avancée (écran « Confidentialité ») : en ligne / « vu à », photo de profil, invitations dans les groupes (tout le monde / mes contacts / personne), accusés de lecture, « en train d'écrire », durée par défaut ; présence dans l'en-tête et la fiche contact ; **vider la discussion** sans trace : pour nous deux avec accord (demande 24 h, bandeau Accepter/Refuser), seulement chez moi, groupe par les administrateurs (ADR-013). **Tests** : régler « Personne » pour en ligne et vérifier sur l'autre téléphone ; couper les accusés ; demander à vider puis accepter sur l'autre téléphone ; vider chez soi seulement | ✅ 13/11/2026 |
| 4.4 | Finitions UX issues de l'audit du 13/11/2026 (textes et lisibilité, sans nouvelle fonction ni changement serveur) : textes d'inscription, de recherche, d'erreur et d'aide raccourcis ; aide au code SMS ; 4 filtres visibles sur un écran de 320 dp ; bandeau de blocage avec « Débloquer » ; « Non envoyé » / « En attente de réseau » ; un seul message de quota photo (« dès minuit ») et icône photo atténuée à 0 ; vocal « 30 s max. » avec vibration à 5 s de la fin ; titres « Infos » ; diagnostic de connexion déplacé dans l'Aide ; 8 nouvelles questions dans l'Aide ; typographie française (espaces fines, ’) vérifiée en CI (`scripts/typo_fr.py`). **Inchangés sur décision** : rappels de durée des messages (R-14 non validé), écran et case des engagements. **Tests** : écran le plus étroit possible (filtre « Groupes ») ; bloquer puis « Débloquer » depuis la discussion ; envoyer 5 photos ; enregistrer un vocal jusqu'à la fin ; parcourir l'Aide | 🧪 13/11/2026 |
| 4.5 | Navigation et médias : double appui sur Retour pour quitter ; nouvelle barre de navigation (piste C : trait violet, pastilles de non-lus et d'invitations) ; plusieurs photos à la fois (un message par photo, dans la limite du jour) ; vocal : pause et reprise de l'enregistrement, spectre pendant l'enregistrement et dans la bulle ; aide mise à jour. **Tests** : appuyer deux fois sur Retour ; choisir 3 photos dans la galerie, en retirer une, envoyer ; enregistrer un vocal en mains libres, mettre en pause, reprendre, envoyer ; écouter un vocal reçu et toucher le spectre pour avancer | 🧪 13/11/2026 |
| 4.6 | Durée des messages : 5 min, 15 min, 30 min, 1 h, 6 h, 12 h, 24 h, 48 h + « Personnalisé » (72 h au plus) ; sélecteur et rappels compacts ; engagement « 72 heures » inchangé | ⏳ |
| 4.7 | Demande de connexion avant le premier message : accepter / refuser (l'expéditeur est prévenu) / bloquer ; expiration 7 j ; délai avant nouvelle demande ; réglage « Qui peut m'envoyer une demande » (amendement 8) | ⏳ |

## Étape 5 — Console d'administration
| Lot | Contenu | Statut |
|---|---|---|
| 5.1 | Console **dans l'application**, visible et utilisable uniquement par le compte +226 75 49 35 18 (vérification par le serveur) ; tableau de bord | ⏳ |
| 5.2 | Politiques modifiables + historique, statistiques | ⏳ |
| 5.3 | Signalements et modération (décision B3) | ⏳ |

## Étape 6 — Préparation du pilote
| Lot | Contenu | Statut |
|---|---|---|
| 6.1 | Clé de signature stable, version optimisée, tests de non-régression | ⏳ |
| 6.2 | Projet de production, vrai fournisseur SMS (B7), retrait des numéros de test | ⏳ |
| 6.3 | Conditions d'utilisation, confidentialité (B10), numéros recyclés (B9) | ⏳ |

## Étape 7 — Discussions enrichies (après la console)
| Lot | Contenu | Statut |
|---|---|---|
| 7.1 | Fiche contact et groupe : photo en grand, « À propos », médias de la discussion, sourdine à deux, durée et « Vider » depuis la fiche, groupes en commun, lien d'invitation et demandes d'adhésion, @mentions | ⏳ |
| 7.2 | Confort : bouton « descendre », repère « X non lus », sélection multiple, infos du message, messages épinglés et favoris, notifications par discussion | ⏳ |
| 7.3 | Expression : émojis, autocollants Privio, GIF (service externe via le serveur, sans clé dans l'application), légende / recadrage / dessin sur photo, aperçu des liens, fond d'écran, vue unique pour les médias | ⏳ |

## Étape 8 — Compte et réglages
| Lot | Contenu | Statut |
|---|---|---|
| 8.1 | QR code de l'identifiant, « Inviter un ami », changer de numéro, thème clair / sombre / automatique, taille du texte | ⏳ |
| 8.2 | Langues : français, mooré, dioula (traductions à relire par des locuteurs natifs) | ⏳ |

## Étape 9 — Appels (après le pilote)
| Lot | Contenu | Statut |
|---|---|---|
| 9.1 | Appels audio à deux (service relais gratuit de préférence) | ⏳ |
| 9.2 | Appels vidéo à deux | ⏳ |

## Décisions en attente
| # | Sujet | Nécessaire avant |
|---|---|---|
| B1 | ✅ Modification 60 min, suppression pour tous jusqu'à expiration (12/11/2026) | — |
| B2 | ✅ 25 membres par groupe par défaut, réglable 2–100 (12/11/2026) | — |
| B3 | ✅ Signalements 90 j, journaux 30 j (appliqué par défaut, administrable) | — |
| B4/B5 | ✅ Console intégrée à l'application, réservée au compte +226 75 49 35 18 ; pas de console web (13/11/2026) | — |
| B11 | ✅ Durées : liste 5 min → 48 h + « Personnalisé », 72 h au plus, engagement inchangé (13/11/2026) | — |
| B12 | ✅ Demande de connexion avant le premier message ; refus notifié à l'expéditeur (13/11/2026) | lot 4.7 |
| B13 | ✅ GIF conservés ; appels après le pilote, service gratuit de préférence (13/11/2026) | lots 7.3, 9.1 |
| B14 | Vérification en deux étapes : à prévoir, non planifiée | — |
| B6/B7 | Sauvegardes, budget, fournisseur SMS +226 | lot 6.2 |
| B9/B10 | Numéros recyclés, documents légaux | lot 6.3 |
| Logo | Validation de la recréation provisoire | lot 6.1 |
