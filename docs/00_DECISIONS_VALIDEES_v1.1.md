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
