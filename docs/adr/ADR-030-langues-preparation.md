# ADR-030 — Langues : préparation (mooré, dioula)

**Statut** : accepté (lot 8.2a, décisions du 15/11/2026 : A choix dans Paramètres et à
l'accueil, français par défaut ; B propositions mooré et dioula pré-remplies dans le
tableau seulement ; C console d'administration en français uniquement ; D une langue
n'apparaît que lorsque toute la priorité P1 est traduite et relue ; E découpage 8.2a /
8.2b ; F relecture par des traducteurs natifs).

## Décision
- **Textes extraits** : les 1 048 textes de l'application mobile sont dans
  `apps/mobile/lib/l10n/app_fr.arb` (gen-l10n, code généré versionné dans
  `lib/l10n/gen/`). Les écrans lisent `L.t.<clé>` ; `L.use(locale)` est appelé par
  `PrivioApp` à chaque changement de langue, et le sous-arbre est reconstruit
  (`KeyedSubtree`). Le texte français affiché est inchangé (suite complète verte sans
  modifier les attentes).
- **Langues déclarées** : `fr` (publiée), `mos`, `dyu` (`kReleasedLanguages = ['fr']`).
  `app_mos.arb` et `app_dyu.arb` sont vides : tout texte absent retombe sur le
  français. Les composants Android (dates, boutons système, TalkBack) restent en
  français pour mos/dyu (`FallbackLocalizationsDelegate`). Le SMS reste en français.
- **Choix de la langue** : Paramètres → Langue (mooré et dioula grisés « Traduction en
  cours ») ; un sélecteur sur l'accueil et la bienvenue n'apparaît qu'à partir de deux
  langues publiées. Le choix est gardé sur le téléphone (`privio.language`).
- **Traductions** : tableau partagé « Privio — Traductions mooré et dioula » (clé,
  priorité P1/P2/P3, écran, français, longueur conseillée, propositions mooré et dioula
  marquées « À vérifier », statut par langue, remarques). Les propositions sont des
  brouillons non fiables ; **rien n'entre dans l'application avant relecture**
  (lot 8.2b). Les textes validés (engagements) sont signalés.
- **Outil** : `tools/l10n` (extraction par package:analyzer) pour repérer les textes
  restés en dur ; test `test/ui/langue_test.dart` qui refuse un `Text('…')` français en
  dur hors console, et vérifie que les ARB mos/dyu ont les mêmes clés et accolades.
- Console d'administration : français uniquement, non extraite.

## Preuves
`test/ui/langue_test.dart` (7 cas : écran Langue, sélecteur masqué, sélecteur affiché
si deux langues, repli français en mooré, pluriels, cohérence des ARB, aucun texte en
dur) ; suite complète ; captures de contrôle avec les brouillons (hors dépôt).
