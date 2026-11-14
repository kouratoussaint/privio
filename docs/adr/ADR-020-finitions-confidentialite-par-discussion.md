# ADR-020 — Finitions : Ma fiche, confidentialité par discussion, alerte hors connexion

**Statut** : accepté (lot 7.2a, décisions du 14/11/2026, amendement 13).

## Décision
- **Nom affiché** : `set_my_display_name` (1 à 40 caractères, espaces nettoyés), limité par
  `display_name_daily_limit` (5 par jour, réglable dans la console) ; un nom inchangé n'est pas
  compté. L'@identifiant reste définitif. Les messages système déjà envoyés gardent l'ancien
  nom (ils l'enregistrent au moment de l'événement).
- **Confidentialité par discussion** : table privée `private.conversation_privacy` (une ligne
  par membre et discussion, supprimée quand tout revient « comme dans mes réglages »).
  - `read_receipts`, `typing_indicator` : discussions et groupes ; appliqués par
    `list_conversations` (accusés, y compris le « lu » agrégé d'un groupe) et `signal_typing`.
  - `show_presence`, `show_avatar`, `show_about` : discussions à deux ; `true` montre à ce
    contact, `false` cache, même si le réglage du compte dit le contraire. Appliqués par
    `get_presence`, `private.avatar_for` et `private.about_for`, donc partout où ce contact
    voit la personne (liste, fiche, membres d'un groupe commun, fichiers de photo de profil).
  - Un blocage passe toujours avant une exception (`private.visible_with`).
- **Hors connexion** : `OfflineController` distingue « aucun réseau » annoncé par le
  téléphone (bandeau immédiat) d'un échec d'appel (retour de veille, réseau rendu à l'app
  avec retard) : nouvelle tentative silencieuse à 2 s, bandeau à 5 s si rien n'a réussi.
- **Présentation** : `SettingsListView` / `SettingsCard` / `SettingsSectionTitle` /
  `SettingsNote` partagés ; écrans en liste sur fond blanc.

## Preuves
pgTAP `24_finitions`, `scripts/ci/finitions_e2e.py` (PostgREST réel, vu depuis l'autre
compte), tests Flutter `test/ui/finitions_test.dart` (dont retour de veille sans alerte et
vraie coupure annoncée).
