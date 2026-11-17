# PRIVIO — Passation pour une nouvelle discussion

*Mise à jour : 18/11/2026, après la livraison des lots 9.3 et 7.4 (version 0.1.0+80).*

Ce document se lit en premier dans une nouvelle discussion. Il résume l'état du projet,
les règles, la façon de travailler et la suite. Il ne contient **aucun secret**.

---

## 1. Le projet en bref
**PRIVIO** : messagerie privée et éphémère pour Android, en français, pour le Burkina Faso
(réseaux modestes). Commanditaire : Toussaint. Le développement est confié à Claude.

- **Dépôt** : GitHub `kouratoussaint/privio` (privé, code propriétaire). Une seule branche :
  `main`.
- **Pile technique** : Flutter 3.47.8 (Riverpod 3, go_router), Supabase (PostgreSQL + RLS,
  fonctions RPC, Realtime, Storage, Edge Functions Deno, pg_cron, pg_net), Firebase Cloud
  Messaging, GitHub Actions. Les solutions gratuites ou open source sont privilégiées.
- **Environnements** : `dev` = Supabase local (numéros de test +226 70 00 00 01 à 06, code
  123456) ; `staging` = projet Supabase hébergé gratuit ; `production` reste à créer au lot 6.2.
- **Firebase** : projet `privio-e1ef4`, application `com.privio.app`.
- **Compte administrateur** (console dans l'application) : +226 75 49 35 18.

## 2. Règles non négociables
- Le nom est PRIVIO. Le **logo n° 1** a une recréation provisoire, encore à valider.
- **Les communautés sont supprimées pour toujours**, sans aucune trace dans le code. Un
  garde-fou de la CI le vérifie.
- **Pas de chiffrement de bout en bout**, ni au MVP ni au lancement. L'application ne doit
  jamais afficher « bout en bout », « E2EE » ou « end-to-end » (garde-fou CI). La promesse
  affichée est : « messages effacés après 72 h, protégés pendant leur transport ».
- **72 h au plus** de conservation pour tout message ; la purge automatique tourne chaque
  minute.
- Copie, transfert, partage, export, galerie et captures d'écran sont interdits
  (FLAG_SECURE). Ce sont des engagements de Privio.
- **Un seul appareil actif** par compte. Android 7.0 minimum.
- Les notifications ne contiennent **ni contenu ni nom**.
- La console d'administration est **dans l'application**, réservée au compte
  administrateur, et vérifiée par le serveur à chaque appel.
- Français simple. La typographie française est vérifiée par la CI
  (`scripts/typo_fr.py` : espaces fines insécables, apostrophe ’).

## 3. Sécurité (à respecter strictement)
- Ne **jamais** versionner `google-services.json`, un keystore (.jks, .p12, .pem) ou un `.env`.
- Ne **jamais** mettre la clé service-role ou une clé secrète Supabase dans l'application.
- Ne **jamais** lancer `supabase config push` : il recopierait les codes de test valables
  10 ans vers un projet hébergé.
- Le **jeton GitHub** (PAT) est fourni par Toussaint dans la discussion. Il ne doit jamais
  être écrit dans le dépôt, la config git ou la mémoire. Il est masqué dans les journaux.
  Il est à régénérer avant le pilote.
- Secrets GitHub déjà en place : `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD`,
  `SUPABASE_PROJECT_REF`, `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `FCM_SERVICE_ACCOUNT_B64`, `KLIPY_API_KEY`, `CLOUDFLARE_TURN_KEY_ID`,
  `CLOUDFLARE_TURN_API_TOKEN`.
- **Clé de signature des APK stable**, à ne jamais changer. Empreinte SHA-256 :
  `B8:54:D7:5B:1B:E6:8E:23:B7:9B:FB:17:93:75:91:8A:72:4D:D6:FC:8E:76:87:06:39:14:CF:9F:A1:53:51:1B`

## 4. Façon de travailler (consignes de Toussaint)
1. **Livraisons en lots**, suivies dans `docs/SUIVI_LIVRAISONS.md`. Statuts : ✅ validé,
   🧪 livré à tester, 🔨 en cours, ⏳ à venir.
2. **Avant chaque lot**, proposer les décisions (A, B, C…) avec une option recommandée, et
   les faire valider. Ensuite seulement, développer.
3. **Chaque lot** comprend : une migration si nécessaire, des tests pgTAP, un test de bout
   en bout `scripts/ci/*_e2e.py`, des tests Flutter, un ADR (`docs/adr/ADR-0xx`), un
   amendement dans `docs/00_DECISIONS_VALIDEES_v1.1.md` et la mise à jour du suivi.
4. **Un lot se termine** quand la CI est verte, que le serveur est déployé sur le staging
   (workflow « Déployer les migrations », environnement `staging`), que l'APK est livré
   avec la liste des tests à faire sur téléphone, et que Toussaint a fait ses tests. Un
   lot n'est ✅ qu'après son retour.
5. **À chaque livraison**, donner les **liens directs GitHub des deux APK** :
   `https://github.com/kouratoussaint/privio/actions/runs/<RUN>/artifacts/<ID>`, en arm64 et
   en 32 bits. Ils sont gardés 2 jours, et il faut être connecté à GitHub pour les
   télécharger. Envoyer aussi les fichiers dans la discussion.
6. **Une seule session à la fois** sur le dépôt. Avant de pousser, vérifier `main` sur
   GitHub et ne jamais forcer un push. Pour un gros lot, on peut faire tourner la CI sur
   une branche de travail (lancement manuel du workflow), puis faire une avance rapide de
   `main`.
7. Identité des commits : `Claude (Anthropic) <claude@anthropic.invalid>`.

## 5. Outillage d'une nouvelle session (conteneur vide)
- Cloner le dépôt et ajouter l'accès GitHub en écriture à la session.
- Flutter 3.47.8 : `git clone -b 3.47.8 https://github.com/flutter/flutter`, puis
  `flutter pub get` dans `apps/mobile`.
- Tests serveur en local, sans Docker : `apt install postgresql-16-pgtap
  libtap-parser-sourcehandler-pgtap-perl`, démarrer le cluster, puis lancer
  `scripts/db/run_local_tests.sh`. Les échecs des tests 10, 11, 17, 20, 21, 32, 34 et 35
  sont normaux en local : la version locale de Supabase n'a ni Storage ni pg_net. La CI
  fait foi.
- Deno (vérification des types des fonctions) : binaire publié sur GitHub (`denoland/deno`).
- Contrôles avant de pousser :
  - `flutter analyze --fatal-infos`
  - `dart format --line-length 100`
  - `scripts/guards.sh`
  - `python3 scripts/typo_fr.py --check …`
  - après modification d'un `.arb` : `flutter gen-l10n` (le code généré est versionné)
- Si une extension bloque `flutter test` en local, ne pas la contourner : faire tourner
  la CI sur une branche de travail.
- Textes de l'application dans `apps/mobile/lib/l10n/app_fr.arb`, lus via `L.t`. Les
  textes de la console restent en français dans le code.

## 6. État au 17/11/2026 (soir)
- **Validés sur téléphone** :
  - étapes 1 à 4 (discussions, médias, groupes, notifications, confidentialité, demandes
    de connexion) ;
  - console 5.1 à 5.6 ;
  - étape 7 (discussions enrichies) ;
  - étape 8, sauf 8.2b ;
  - étape 9 (appels audio et vidéo) ;
  - 10.1 (effacer après lecture) et 10.2 (discussions cachées).
- **Livrés, à tester** :
  - **10.3 Mode éco** (version 69) ;
  - **5.7 Santé du service** (version 73, ADR-047, migration `20261117000100`) :
    - versions conseillée (bandeau) et minimale (écran bloquant), lien de mise à jour ;
    - santé des appels et du relais Cloudflare ;
    - codes SMS et coût estimé ;
    - diagnostics (notification de test, test du relais, état des tâches) ;
    - alertes de l'administration ;
  - **10.4 « Vérifié en personne » et surnom privé** (version 75, ADR-048, migration
    `20261117000200`) :
    - QR code de 2 minutes créé pour un contact, scanné face à face ; un scan vérifie les
      deux téléphones ;
    - badge retiré quand le contact se reconnecte ou change de numéro, avis « Revérifier » ;
    - surnom privé partout, « Surnom · vrai nom » dans la fiche, gardé sur le serveur ;
  - **10.5 Groupes « Annonces » et sondages éphémères** (version 77, ADR-049, migration
    `20261118000100`) :
    - type « Annonces » choisi à la création, définitif : seuls les admins écrivent, les
      membres réagissent et votent sans voir les autres membres ; 500 membres (console) ;
    - sondages dans les groupes : 2 à 10 choix, une ou plusieurs réponses, anonyme par
      défaut ou votes visibles, vote modifiable, fermeture par le créateur ;
  - **9.3 Son des appels et vocaux** (version 78, ADR-050, application seulement) :
    touches de volume sur le flux d'appel, volume très bas remonté, écouteurs et
    Bluetooth d'office et en bascule automatique ; vocal envoyé dès qu'on lève le doigt
    (réglage « Écouter les vocaux avant de les envoyer ») ;
  - **7.4 Autocollants personnels** (version 80, ADR-051, migration `20261118000200`,
    fonction `sticker`) : création depuis une photo détourée par ML Kit, texte,
    « Partageable » ; collection de 60 gardée sur le serveur ; envoi par copie effacée
    avec le message.
- **Dernier commit de code** : `782a542` sur `main`. CI verte (run 80), staging déployé.
- Les branches `lot-5.7`, `lot-10.4`, `lot-10.5` et `lot-7.4` (identiques à des commits
  de `main`) restent sur GitHub. Toussaint peut les supprimer.

## 7. Suite prévue
1. **9.4 Appels de groupe** (décisions du 17/11/2026) : audio et vidéo par **Cloudflare
   Realtime SFU**, **8 participants** ; lancés par tout membre qui peut écrire
   (administrateurs seulement dans un groupe « Annonces ») ; sonnerie chez tous si le
   groupe a 16 membres au plus, sinon notification et bandeau « Rejoindre ». **Prérequis** :
   Toussaint crée une « app Realtime » (SFU) dans Cloudflare et ajoute les secrets GitHub
   `CLOUDFLARE_REALTIME_APP_ID` et `CLOUDFLARE_REALTIME_APP_TOKEN`.
2. **Console 5.8** : équipe et modération (plusieurs administrateurs avec des rôles, liste
   des groupes, réponses types, statistiques de modération, sites bloqués pour les
   aperçus).
3. **Console 5.9** : pilotage (inscriptions sur liste, réglages par compte et par groupe,
   préréglages, message programmé, export des statistiques).
4. **Étape 6 en dernier**, juste avant le pilote :
   - 6.1 : version optimisée et non-régression ;
   - 6.2 : production, fournisseur SMS +226 (B7), retrait des numéros de test ;
   - 6.3 : documents légaux (B10), numéros recyclés (B9).
5. **8.2b** : traductions mooré et dioula, mises de côté pour l'instant.

**Décisions encore ouvertes** :
- B6/B7 : sauvegardes, budget, fournisseur SMS ;
- B9/B10 : numéros recyclés, documents légaux ;
- validation du logo.

## 8. Phrase de reprise conseillée
> « Lis docs/PASSATION.md et docs/SUIVI_LIVRAISONS.md du dépôt kouratoussaint/privio,
> vérifie l'état de GitHub et de la CI, puis continue avec le lot 9.4 (appels de groupe, décisions déjà prises). Voici le jeton GitHub : … »
