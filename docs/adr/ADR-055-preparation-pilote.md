# ADR-055 — Préparation du pilote : taille, vitesse, parcours sur émulateur, recette, journal technique, distribution

**Statut** : accepté (lot 6.1, décisions A à F du 19/11/2026, options recommandées ; logo
provisoire validé le même jour).

## Contexte
Avant d'envoyer Privio à des testeurs pilotes (réseaux modestes, téléphones d'entrée de
gamme, Android anciens), il faut : un APK léger, des temps de réponse surveillés, des
parcours complets vérifiés à chaque version sans téléphone, une liste de vérification
manuelle pour ce qu'un émulateur ne voit pas, un moyen de diagnostiquer un problème sans
service de rapport de plantage externe, et un canal de distribution simple et gratuit.

## Décision
- **A. Taille de l'APK** : le lecteur de QR code (rejoindre un groupe) est fourni par les **services Google** (`useUnbundled`, téléchargé par Google
  Play à l'installation, comme le détourage des autocollants) au lieu d'être embarqué
  (≈ 5 Mo de moins par APK) ; message clair si le lecteur se prépare encore. Polices Inter
  réduites aux écritures utiles (latin étendu, alphabet phonétique pour le mooré et le
  dioula, ponctuation, symboles monétaires : `tools/fonts/subset_inter.sh`). La CI échoue
  au-delà de **45 Mo (arm64)** et **40 Mo (32 bits)** et affiche les tailles dans son résumé.
- **B. Vitesse** : mesurée à chaque version sur un émulateur d'entrée de gamme (2 cœurs,
  2 Go, Android 7 et 14) en mode « profile » (comme une version publiée), avec un compte
  de mesure de **300 discussions dont une de 1 000 messages** (base locale seulement :
  `scripts/emulateur/`). Seuils qui font échouer la CI : **démarrage à froid < 3 s**
  (du lancement du processus au premier écran) ; **ouverture de la discussion de
  1 000 messages < 2 s** ; **défilement** des 300 discussions et des 1 000 messages :
  90 % des images construites en **moins de 20 ms**. Le temps de rendu graphique est
  publié mais pas soumis à seuil (l'émulateur dessine sans carte graphique).
  Ce que les mesures ont révélé et corrigé : la liste des discussions dépassait le délai
  du serveur (8 s) tant que les statistiques de la base n'étaient pas à jour après un
  remplissage massif ; les données de mesure sont donc analysées comme le ferait la base
  en service (`analyze`) ; avec des statistiques à jour, la liste de 300 discussions répond
  en ≈ 0,25 s et une page de 50 messages en ≈ 10 ms. Une bulle de vocal en attente
  débordait avec de grands caractères (corrigé).
- **C. Parcours complets sur émulateur** (Android 7 et 14, à chaque version, workflow
  « Émulateur Android ») contre le serveur local : inscription, demande de connexion,
  message, photo, vocal, effacement après lecture, groupe, verrouillage par code.
  L'application est la vraie (mêmes branchements que `main.dart`, réunis dans
  `lib/bootstrap.dart`), seuls l'appareil photo, le micro et les notifications sont
  remplacés ; une seconde personne agit par l'API. Les versions de test (debug, profile)
  peuvent joindre le serveur local en HTTP (`10.0.2.2`) ; la version publiée reste en
  HTTPS seulement. Le même parcours tourne sur ordinateur pour le mettre au point
  (`test_parcours/`). **Les appels restent testés sur téléphone.**
- **D. Recette** : `docs/RECETTE_PILOTE.md`, 84 points par thème à dérouler sur 2 ou
  3 téléphones avant chaque version pilote ; aucune version ne part avec un problème sur
  l'installation, l'inscription, les messages, l'effacement, les appels ou le verrouillage.
- **E. Journal technique** : pas de service externe de rapport de plantage. Journal local
  de **200 événements** au plus (démarrages : versions de Privio et d'Android, modèle du
  téléphone ; erreurs non rattrapées : **type et emplacement dans le code seulement**,
  jamais le texte de l'erreur, qui pourrait contenir un message, un nom ou un numéro).
  Joint **avec l'accord** de la personne (case décochée par défaut, contenu consultable
  avant l'envoi) à une demande d'assistance ; 16 000 caractères au plus, refusé par le
  serveur pour tout autre signalement ; lu dans le dossier de la console, effacé avec la
  demande. Les symboles des versions pilotes (traduction des emplacements d'une version
  obfusquée) sont gardés 90 jours par la CI.
- **F. Distribution** : Firebase App Distribution (gratuit, projet existant
  `privio-e1ef4`), workflow manuel « Distribution aux testeurs pilotes » : version de test
  signée avec la clé stable, pour téléphones arm64 ou 32 bits, envoyée à des groupes de
  testeurs, avec des notes de version. Prérequis : secret `FIREBASE_DISTRIBUTION_SA`.

## Conséquences
- Trois vérifications à chaque version : CI (analyse, tests, tailles), base de données,
  émulateur (parcours et vitesse). L'émulateur prend ≈ 30 min, en parallèle.
- Un lecteur de QR code absent (téléphone sans services Google à jour) affiche un message
  au lieu de s'ouvrir ; la saisie du code reste possible.
- Migration `20261119000100` (journal joint aux demandes d'assistance).
