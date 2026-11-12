# ADR-011 — Notifications FCM sans contenu

**Statut** : accepté (lot 4.1).

**Contenu affiché** : toujours **générique** — titre « Privio », texte « Nouveau message » (ou
« Nouveau message dans un groupe »). Jamais de texte du message, jamais de nom d'expéditeur.
Visibilité « privée » sur l'écran verrouillé, une seule notification par discussion
(remplacée par les suivantes), canal Android « Messages ». Seule donnée transmise au
téléphone : l'identifiant de la discussion, pour l'ouvrir au toucher.

**Chaîne d'envoi** : déclencheur sur `messages` → la base appelle `push-dispatch` (pg_net)
avec un jeton interne aléatoire (migration) → la fonction demande à la base la liste des
jetons destinataires (`push_targets`) → envoi FCM HTTP v1 avec le compte de service →
compte rendu sans contenu (`push_log`, 7 jours) et suppression des jetons refusés.

**Destinataires** (calculés par la base, jamais par l'app) : membres actifs de la discussion,
sauf l'expéditeur, les discussions en sourdine, les blocages dans un sens ou l'autre, les
appareils révoqués ; rien pour un message expiré, supprimé ou système.

**Jetons** : un par appareil ACTIF (`private.push_tokens`, schéma non exposé) ; supprimés à la
déconnexion, à la révocation de l'appareil (connexion sur un autre téléphone), à la suppression
du compte, et quand FCM les refuse. L'utilisateur peut couper les notifications (Paramètres).

**Secrets** : le compte de service FCM n'existe que dans les fonctions Supabase
(`FCM_SERVICE_ACCOUNT`), transmis par le déploiement depuis le secret GitHub
`FCM_SERVICE_ACCOUNT_B64` de l'environnement `staging`. Sans lui, rien n'est envoyé (compte
rendu `not_configured`) et l'application fonctionne normalement.

**Configuration Firebase côté app** : identifiants PUBLICS (projet, application, clé d'API)
dans `firebase_options.dart` et `res/values/firebase.xml` — `google-services.json` n'est pas
versionné. La clé d'API doit être **restreinte** dans Google Cloud (application Android
`com.privio.app` + empreinte SHA-256 de la clé de signature).

**Choix assumé** : jetons FCM « classiques » (`getToken`), dépréciés dans firebase_messaging 17
au profit de l'identifiant d'installation (FID). Le FID exige un drapeau du manifeste qui
désactive les jetons ET un envoi serveur par `fid` : migration à faire d'un seul bloc
(client + serveur), après le pilote.

**Preuves** : tests SQL (destinataires, sourdine, blocage, révocation, jetons refusés), tests
Flutter (enregistrement, renouvellement, interrupteur, déconnexion, ouverture), test bout à
bout en CI (déclencheur → pg_net → fonction → destinataires).
