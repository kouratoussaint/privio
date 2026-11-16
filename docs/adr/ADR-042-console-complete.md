# ADR-042 — Console complète

**Statut** : accepté (lot 5.5, décisions du 16/11/2026 : G menu latéral et accueil en tuiles
colorées ; H rubrique « Fonctionnalités » avec tous les interrupteurs proposés et un message
d'information ; I comptes A–Z en pages numérotées ; J réglages en tuiles avec icônes, journal
et signalements filtrables).

## Décision
- **Navigation** : menu latéral (`console.menu`) avec une couleur par rubrique — Accueil,
  Signalements, Comptes, Fonctionnalités, Réglages, Statistiques, Journal. L'accueil montre
  les rubriques en tuiles colorées (point rouge quand des signalements attendent), puis les
  chiffres du tableau de bord. Changement de rubrique animé.
- **Fonctionnalités** (migration `20261116000100`, catégorie `features`, visibles des
  téléphones) : inscriptions ouvertes, appels audio, appels vidéo, vocaux, photos, GIF, aperçus
  des liens, création de groupes, liens et codes d'invitation de groupe ; activés par défaut.
  Chaque changement est confirmé, inscrit au journal, et **vérifié par le serveur** :
  - déclencheurs : `profiles` (SIGNUPS_CLOSED), `private.calls` (audio/vidéo), `messages`
    (vocal, photo, GIF), `conversations` (groupe), `group_invite_codes` ;
  - fonctions : entrée par code (`group_of_code`), recherche de GIF (`gif_customer_id`),
    aperçus (`link_preview_target` ne renvoie plus de lien) ; erreur `FEATURE_DISABLED`.
  L'application lit les interrupteurs avec les autres réglages (`get_client_policies`, relu
  au retour dans l'app) et masque les boutons : 📞/🎥, micro (le bouton d'envoi le remplace),
  appareil photo, onglet GIF, « Nouveau groupe », « Rejoindre un groupe », code/QR d'un groupe.
- **Message d'information** (`announcement_text`, 200 caractères au plus) : bandeau en haut des
  listes Discussions et Groupes, fermable (revient si le texte change).
- **Non modifiables** : copie, transfert, partage, export, galerie, captures, 72 h restent des
  **engagements de Privio** (promis à l'inscription) ; affichés dans Fonctionnalités avec un
  cadenas, comme les fonctions pas encore développées (documents, vidéos).
- **Comptes** : liste complète par ordre alphabétique (accents ignorés : « Émile » avec les E),
  25 par page, pages numérotées, lettres A–Z à droite (`console_accounts_page` renvoie la
  première position de chaque initiale). La recherche reste au-dessus. Aucun numéro affiché.
  Chaque page consultée est inscrite au journal (`account_list`).
- **Journal** : filtres par type (Comptes, Signalements, Fonctionnalités et réglages,
  Sécurité, Assistance, Consultations) et par période (tout, 24 h, 7 jours, 30 jours), pages
  numérotées (`console_journal_page`).
- **Réglages** : tuiles blanches par thème avec icône et couleur ; les engagements et
  fonctionnalités sont passés dans « Fonctionnalités ». **Signalements** : dossiers en tuiles
  blanches ; filtres par file, type et motif inchangés.

## Correction du 16/11/2026 : bouton retour
Le bouton retour du téléphone refermait la console d'un coup. Il suit maintenant le chemin
parcouru : il ferme le menu latéral, puis la fiche ouverte (compte, dossier), puis revient
à la rubrique précédente jusqu'à l'Accueil ; la console ne se quitte que depuis l'Accueil
(`ConsoleBackScope`, `test/ui/console_back_test.dart`).

## Preuves
`supabase/tests/database/36_console_complete.test.sql` (28 tests) ; `scripts/ci/console_e2e.py`
(comptes A–Z, GIF coupés refusés aussitôt, journal filtré) ; `test/ui/console_complete_test.dart`
(4 cas) ; `test/ui/fonctionnalites_app_test.dart` (4 cas) ; tests de console existants adaptés
(`openConsoleSection`).
