# ADR-031 — Paramètres réorganisés, menus ⋮ des listes

**Statut** : accepté (lot 8.3a, décisions du 15/11/2026 : A structure validée, Sécurité
sur un écran séparé ; B Groupes garde l'icône QR **et** le menu ⋮ ; F découpage 8.3a /
8.3b / 8.4).

## Contexte
L'écran Paramètres mélangeait les thèmes (« À propos » sous Confidentialité, langue et
fond d'écran sous « Notifications et gestes »), présentait des doublons (verrouillage et
personnes bloquées à la fois dans Paramètres et Confidentialité ; À propos dans Paramètres
et Ma fiche) et dépassait deux écrans de défilement.

## Décision
- **Paramètres** : une page courte, une ligne par écran. Carte du profil (→ Ma fiche) avec
  un bouton **Mon QR code**. *Mon compte* : Confidentialité, Sécurité. *Préférences* :
  Notifications et sons, Discussions, Apparence, Langue. *Ce téléphone* : Stockage et
  données. *Privio* : Inviter un ami, Aide et assistance. Puis Se déconnecter, Supprimer
  mon compte, version.
- Nouveaux écrans : **Sécurité** (verrouillage, changer de numéro, captures d'écran et
  appareil unique en information), **Notifications et sons**, **Discussions** (fond
  d'écran, réaction du double appui, groupes dans Discussions, archivées).
- **Confidentialité** : « Qui voit quoi » (en ligne, photo, À propos), nouvelle section
  « Qui peut me joindre » (me trouver par mon numéro, demandes de connexion, invitations
  dans un groupe, personnes bloquées), Messages, Liens et GIF. Le verrouillage passe dans
  Sécurité.
- **Menu ⋮** en haut des listes :
  - Discussions : nouvelle discussion (correction du 15/11/2026 : remplace « nouveau
    groupe », qui a son bouton dans l'onglet Groupes), scanner un QR code, demandes de connexion (nombre),
    archivées (toujours accessibles), messages favoris de toutes les discussions, tout
    marquer comme lu, verrouiller Privio maintenant (si le code est activé).
  - Groupes (icône QR gardée) : rejoindre un groupe, demandes envoyées (feuille avec
    « Annuler »), archivés, tout marquer comme lu, verrouiller maintenant.
- **Tout marquer comme lu** : geste voulu, donc l'accusé « lu » part comme à l'ouverture
  d'une discussion (selon le réglage Accusés de lecture). La confirmation le dit. Les
  discussions archivées ne sont pas touchées. La règle du lot 7.2b1 (« lu » seulement si la
  discussion est à l'écran) reste vraie pour tout accusé automatique.
- **Favoris de toutes les discussions** : fonction serveur `list_all_favorite_messages()`
  (migration `20261115000100`), mêmes règles que `list_favorite_messages` (membre actif,
  message non expiré, non supprimé, non masqué chez moi, envoyé après l'arrivée dans le
  groupe), 500 au plus. Chaque favori indique sa discussion ; toucher y ramène.
- **Verrouiller maintenant** : `AppLockController.lockNow()` (sans effet si le code n'est
  pas activé).

## Preuves
`test/ui/parametres_menus_test.dart` (6 cas) ; tests existants adaptés aux nouveaux
chemins (`test/helpers/settings_nav.dart`) ; `supabase/tests/database/30_favoris_tous.test.sql`.
