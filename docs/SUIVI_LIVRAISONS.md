# PRIVIO — Suivi des livraisons

Mis à jour à chaque livraison. Dernière mise à jour : lot 3.2 livré le 12/11/2026 (lots 3.1 et 3.2 à tester). Statuts : ✅ validé · 🧪 livré, à tester · 🔨 en cours · ⏳ à venir · ⛔ bloqué.

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

## Étape 3 — Médias et groupes
| Lot | Contenu | Vos tests | Statut |
|---|---|---|---|
| 3.1 | Messages vocaux : micro (toucher = mains libres, maintenir = glisser pour annuler ou verrouiller), arrêt automatique à 30 s, préécoute obligatoire, lecture avec vitesse 1×/1,5×/2×, envoi hors ligne ; serveur : stockage privé, durée mesurée, effacement physique à l'expiration (ADR-008) | Envoyer un vocal de 10 s et l'écouter sur l'autre téléphone ; laisser l'enregistrement aller jusqu'à 30 s ; régler 5 min et vérifier qu'il disparaît des deux côtés | 🧪 12/11/2026 |
| 3.2 | Photos : appareil photo ou galerie (aucune autorisation), aperçu avec légende, compteur du jour (5, groupes inclus, remboursé si l'envoi échoue), visionneuse sans enregistrement ni partage, envoi hors ligne ; métadonnées (GPS…) retirées sur le téléphone ET par le serveur ; photo de profil (Paramètres) visible sauf en cas de blocage (ADR-009) | Envoyer une photo avec légende et l'ouvrir sur l'autre téléphone ; envoyer 5 photos puis vérifier le refus de la 6e ; mettre une photo de profil et la voir chez l'autre ; bloquer puis vérifier qu'elle disparaît | 🧪 12/11/2026 |
| 3.3 | Groupes : création, rôles, invitations, taille max (décision B2) | | ⏳ |

## Étape 4 — Notifications et confidentialité
| Lot | Contenu | Statut |
|---|---|---|
| 4.1 | Notifications FCM sans contenu (fichier Firebase requis) | ⏳ |
| 4.2 | Verrouillage de l'app (empreinte/code), états hors ligne et erreurs, économie de données | ⏳ |

## Étape 5 — Console d'administration
| Lot | Contenu | Statut |
|---|---|---|
| 5.1 | Connexion admin sécurisée, rôles (décisions B4, B5) | ⏳ |
| 5.2 | Politiques modifiables + historique, statistiques | ⏳ |
| 5.3 | Signalements et modération (décision B3) | ⏳ |

## Étape 6 — Préparation du pilote
| Lot | Contenu | Statut |
|---|---|---|
| 6.1 | Clé de signature stable, version optimisée, tests de non-régression | ⏳ |
| 6.2 | Projet de production, vrai fournisseur SMS (B7), retrait des numéros de test | ⏳ |
| 6.3 | Conditions d'utilisation, confidentialité (B10), numéros recyclés (B9) | ⏳ |

## Décisions en attente
| # | Sujet | Nécessaire avant |
|---|---|---|
| B1 | ✅ Modification 60 min, suppression pour tous jusqu'à expiration (12/11/2026) | — |
| B2 | Taille maximale des groupes | lot 3.3 |
| B3 | ✅ Signalements 90 j, journaux 30 j (appliqué par défaut, administrable) | — |
| B4/B5 | Connexion admin, hébergement console | lot 5.1 |
| B6/B7 | Sauvegardes, budget, fournisseur SMS +226 | lot 6.2 |
| B9/B10 | Numéros recyclés, documents légaux | lot 6.3 |
| Logo | Validation de la recréation provisoire | lot 6.1 |
