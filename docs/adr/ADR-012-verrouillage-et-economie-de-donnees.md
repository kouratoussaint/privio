# ADR-012 — Verrouillage de l'application, réseau et économie de données

**Statut** : accepté (lot 4.2). Exigences SEC-004, DATA-001, 003, 006, 007, 008, 009.

## Verrouillage (SEC-004)
- **Code Privio à 6 chiffres**, propre à l'application (indépendant du code du téléphone,
  car beaucoup de téléphones n'en ont pas). Codes trop simples refusés (chiffres identiques,
  suites). Saisie sur un pavé dessiné par Privio : aucun clavier, aucune suggestion, aucun
  presse-papiers.
- **Stockage** : seule l'empreinte PBKDF2-HMAC-SHA256 (sel aléatoire de 16 octets,
  20 000 itérations, calculée hors du fil de l'interface) est gardée, dans le stockage
  sécurisé Android (chiffré par le Keystore). Le code lui-même n'est jamais enregistré.
- **Empreinte digitale** (facultative, `local_auth`) : proposée à l'affichage de l'écran de
  verrouillage si le téléphone en a une enregistrée ; le code reste toujours accepté.
  L'activité Android devient une `FlutterFragmentActivity` (exigence de `local_auth`), thèmes
  AppCompat ; `FLAG_SECURE` inchangé.
- **Quand** : à chaque démarrage, puis au retour après un délai au choix (immédiatement,
  1 min par défaut, 5 min, 30 min). Une sortie volontaire vers l'appareil photo ou la galerie
  ne reverrouille pas.
- **Essais** : 5 essais libres, puis attente de 30 s doublée à chaque nouvelle erreur
  (plafond 15 min), conservée même si l'application est fermée.
- **Code oublié** : impossible à retrouver. Seule issue : se déconnecter, ce qui efface les
  données locales (messages gardés, médias, clés) ; on se reconnecte par SMS. Déconnexion,
  suppression du compte et ouverture du compte sur un autre téléphone effacent aussi le
  verrouillage.
- **Affichage** : tant que l'application est verrouillée (ou que son réglage n'est pas
  encore lu), aucun écran n'est construit visiblement ni annoncé à TalkBack ; l'écran de
  verrouillage a sa propre couche, au-dessus de la navigation.
- Prévu pour le lot 5.1 : l'ouverture de la console d'administration s'appuiera sur ce code.

## Réseau (DATA-006, DATA-007)
- `connectivity_plus` signale la coupure aussitôt (bandeau « Hors connexion » dans
  Discussions, Groupes et la discussion) ; au retour du réseau, les envois en attente partent
  et la liste se met à jour sans geste. Un réseau « présent » mais sans Internet reste détecté
  par l'échec des échanges, comme avant.

## Économie de données (DATA-001, 003, 008, 009) — écran « Stockage et données »
- **Photos reçues** : téléchargement automatique « Toujours » (par défaut), « En Wi-Fi
  seulement » ou « Jamais » ; sinon la photo s'affiche en attente et se télécharge au
  toucher (accessible à TalkBack). Rien ne part avant que le réglage soit lu. Les vocaux
  ne se téléchargent qu'à l'écoute ; ses propres envois ne sont jamais retéléchargés.
- **Données consommées** : octets de photos, vocaux et photos de profil reçus et envoyés,
  pour le mois en cours et le précédent, remise à zéro possible. Les messages texte ne sont
  pas comptés. Chiffres indicatifs, gardés sur le téléphone uniquement.
- **Espace** : nombre et taille des médias gardés (chiffrés) ; bouton pour les effacer
  (retéléchargeables tant que le message n'a pas expiré ; les envois en attente sont gardés).

## Limites connues
- Le code ne protège que l'application : il ne chiffre pas davantage les données (déjà
  chiffrées, ADR-007) et ne remplace pas le verrouillage du téléphone.
- Le compteur ne voit pas le trafic texte ni celui des autres applications.
