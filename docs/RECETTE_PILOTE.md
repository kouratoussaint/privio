# Recette du pilote — liste de vérification sur téléphones

Lot 6.1 (ADR-055). À dérouler **avant chaque version envoyée aux testeurs pilotes**, sur
**2 ou 3 téléphones** : un récent (Android 13 ou plus), un ancien ou d'entrée de gamme
(Android 7 à 10, 2 Go de mémoire), et si possible un 32 bits. Les parcours de base
(inscription, demande de connexion, message, photo, vocal, effacement, groupe,
verrouillage) sont déjà joués à chaque version sur émulateur (Android 7 et 14) ; cette
liste couvre ce que l'émulateur ne voit pas : vrais réseaux, vraies notifications, appels,
appareil photo, micro, empreinte, petits écrans.

Pour chaque point : ✅ conforme, ❌ problème (noter le téléphone, l'heure et joindre le
journal technique depuis Aide → Contacter l'assistance), ➖ non applicable.

| Téléphone | Modèle | Android | Processeur | Version de Privio |
|---|---|---|---|---|
| T1 | | | | |
| T2 | | | | |
| T3 | | | | |

## 1. Installation et premier lancement (8)
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 1 | La version s'installe par Firebase App Tester sans désinstaller la précédente | | | |
| 2 | Taille de l'APK : moins de 45 Mo (arm64) ou 40 Mo (32 bits) | | | |
| 3 | Premier écran affiché en moins de 3 s (téléphone ancien : moins de 5 s) | | | |
| 4 | Les engagements s'affichent, « Continuer » reste grisé sans la case cochée | | | |
| 5 | Aucune mention « communauté », aucune promesse de chiffrement de bout en bout | | | |
| 6 | Capture d'écran bloquée dès le premier écran | | | |
| 7 | Langue : français par défaut, typographie correcte (espaces avant « : ? ! ») | | | |
| 8 | Le guide « Découvrir Privio » s'affiche une fois après la création du compte | | | |

## 2. Inscription et compte (8)
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 9 | Code SMS reçu en moins d'une minute (vrai numéro +226) | | | |
| 10 | Le code se valide seul à 6 chiffres ; code faux : message clair | | | |
| 11 | Identifiant déjà pris : refusé avant l'envoi | | | |
| 12 | Inscriptions « sur liste » : un numéro non autorisé demande un code d'invitation | | | |
| 13 | Autorisations facultatives : « Plus tard » ne bloque rien | | | |
| 14 | Connexion sur un 2ᵉ téléphone : le 1ᵉʳ est déconnecté | | | |
| 15 | Vérification en deux étapes : activation, puis code demandé à la reconnexion | | | |
| 16 | Supprimer mon compte : confirmation, retour à l'accueil, plus de session | | | |

## 3. Contacts et demandes de connexion (6)
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 17 | Recherche par identifiant ; par numéro seulement si la personne l'a permis | | | |
| 18 | Demande envoyée avec un mot ; l'autre téléphone reçoit une notification | | | |
| 19 | Accepter : la discussion s'ouvre, le mot est le 1ᵉʳ message | | | |
| 20 | Refuser : notifié, nouvelle demande impossible pendant 5 min | | | |
| 21 | Bloquer depuis la demande : plus aucun message ni appel | | | |
| 22 | Inviter un proche par SMS (lien d'invitation) | | | |

## 4. Messages (10)
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 23 | Message reçu en moins de 3 s en 4G, Privio ouvert | | | |
| 24 | Coches : envoyé, distribué, lu (lu seulement quand la discussion est à l'écran) | | | |
| 25 | Répondre (glisser), réagir, modifier, supprimer pour tous | | | |
| 26 | Hors connexion : le message attend, puis part au retour du réseau | | | |
| 27 | Indicateur « écrit… » | | | |
| 28 | Message épinglé, favoris, recherche dans la discussion | | | |
| 29 | Grands émojis animés (1 à 3 émojis seuls) | | | |
| 30 | Aperçu d'un lien (sauf site sans aperçu) | | | |
| 31 | Vue unique : s'ouvre une fois, puis disparaît | | | |
| 32 | Défilement fluide dans une longue discussion (téléphone ancien compris) | | | |

## 5. Photos, vocaux, GIF, autocollants (9)
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 33 | Photo depuis l'appareil photo et la galerie (sélecteur du système) | | | |
| 34 | Retouche (recadrer, dessiner, texte) puis envoi avec légende | | | |
| 35 | Photo reçue lisible, plein écran, enregistrement bloqué | | | |
| 36 | Vocal : toucher le micro, arrêter, réécouter, envoyer | | | |
| 37 | Vocal : appui long, glisser pour annuler ou verrouiller | | | |
| 38 | Vocal reçu : lecture au haut-parleur et à l'oreille, vitesse ×1,5 / ×2 | | | |
| 39 | GIF : recherche et envoi | | | |
| 40 | Autocollant personnel créé depuis une photo (détourage) | | | |
| 41 | Mode éco : photos 1 024 px, vocaux allégés, médias reçus au toucher | | | |

## 6. Effacement et confidentialité (8)
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 42 | Durée de la discussion changée : annonce visible des deux côtés | | | |
| 43 | Message effacé à l'heure prévue chez les deux personnes | | | |
| 44 | Rappel avant effacement (notification) | | | |
| 45 | Effacer après lecture (30 s) : disparaît chez le lecteur et l'expéditeur | | | |
| 46 | Vider une discussion « pour nous deux » : demande acceptée, tout disparaît | | | |
| 47 | Discussions cachées : appui long sur le logo → code → la liste | | | |
| 48 | Discussion cachée : notification neutre, sonnerie sans nom | | | |
| 49 | « Ce que Privio garde » : texte à jour et compréhensible | | | |

## 7. Groupes (8)
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 50 | Créer un groupe, inviter (invitation, pas d'ajout forcé) | | | |
| 51 | Rejoindre par code ou QR code (lecteur de QR des services Google) | | | |
| 52 | Demande pour rejoindre : approuver, refuser | | | |
| 53 | @mention : notification même groupe en sourdine « mentions seulement » | | | |
| 54 | Administrateurs : envoi réservé, informations réservées, retirer un membre | | | |
| 55 | Sondage : voter, résultats, clore | | | |
| 56 | Groupe Annonces : seuls les administrateurs écrivent | | | |
| 57 | Quitter, transférer la propriété, supprimer le groupe | | | |

## 8. Appels (8) — jamais testés sur émulateur
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 58 | Appel audio Privio ouvert : sonnerie, décrocher, son clair des deux côtés | | | |
| 59 | Appel reçu téléphone verrouillé / Privio fermé : écran d'appel du système | | | |
| 60 | Volume d'appel suffisant ; haut-parleur, écouteur, oreillette Bluetooth | | | |
| 61 | Appel vidéo : caméra avant / arrière, image en petit (PiP) | | | |
| 62 | Appel de groupe (3 personnes) | | | |
| 63 | Appel en 3G / réseau faible : qualité réduite mais l'appel tient | | | |
| 64 | Appel manqué : notification et trace dans la discussion | | | |
| 65 | Coupure du réseau pendant un appel : reprise ou fin claire | | | |

## 9. Notifications (5)
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 66 | Notification Privio fermé, contenu masqué selon le réglage | | | |
| 67 | Toucher la notification ouvre la bonne discussion | | | |
| 68 | Sourdine d'une discussion respectée | | | |
| 69 | Téléphone en économie d'énergie : notifications toujours reçues | | | |
| 70 | Pastille de non-lus juste après lecture sur un autre écran | | | |

## 10. Verrouillage et sécurité (5)
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 71 | Verrouillage par code : délai respecté au retour | | | |
| 72 | Empreinte proposée, le code reste accepté | | | |
| 73 | 5 erreurs : attente imposée, gardée après redémarrage | | | |
| 74 | Code oublié : déconnexion et effacement des données du téléphone | | | |
| 75 | Aperçu des applications récentes masqué | | | |

## 11. Réseau, données et stockage (4)
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 76 | Mode avion puis retour : tout se resynchronise sans relancer | | | |
| 77 | Réseau 2G / EDGE : messages texte toujours envoyés | | | |
| 78 | Consommation affichée dans Stockage et données | | | |
| 79 | Vider le cache : les médias se rechargent au toucher | | | |

## 12. Assistance et console (5)
| # | Vérification | T1 | T2 | T3 |
|---|---|---|---|---|
| 80 | Aide → Contacter l'assistance, « Joindre le journal technique » décoché par défaut | | | |
| 81 | « Voir » le journal : versions et erreurs seulement, aucun message ni nom | | | |
| 82 | La console reçoit la demande, journal lisible dans le dossier ; réponse reçue | | | |
| 83 | Console : signalement traité, sanction appliquée | | | |
| 84 | Santé du service : version conseillée, bandeau « Mise à jour disponible » | | | |

## Bilan
| Téléphone | ✅ | ❌ | Remarques |
|---|---|---|---|
| T1 | | | |
| T2 | | | |
| T3 | | | |

Une version part aux testeurs seulement sans ❌ sur les sections 1, 2, 4, 6, 8 et 10.
