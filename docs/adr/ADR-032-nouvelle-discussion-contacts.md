# ADR-032 — Nouvelle discussion : mes contacts et recherche

**Statut** : accepté (lot 8.3b, décision C du 15/11/2026 : contacts seulement, sans les
membres de mes groupes).

## Décision
- **Contacts** = personnes avec qui j'ai une discussion à deux (demande acceptée),
  y compris archivée ou vide, sans les personnes bloquées ni les comptes supprimés.
  Calculés sur le téléphone depuis la liste des discussions : aucune nouvelle donnée
  demandée au serveur.
- Écran : champ « Nom, @identifiant ou numéro » ; raccourcis quand le champ est vide
  (nouveau groupe, scanner un QR code, inviter un ami, demandes de connexion) ;
  « Mes contacts (n) » par ordre alphabétique ; toucher ouvre la discussion.
- En tapant : filtre **local** et immédiat sur le nom et l'identifiant (minuscules, sans
  accents, lettres du mooré et du dioula comprises, `@` facultatif). Rien n'est envoyé au
  serveur pendant la saisie.
- Nouvelles personnes : ligne « Chercher « … » sur Privio » ou touche Rechercher du
  clavier → recherche **exacte** inchangée (identifiant complet ou numéro complet, limitée
  par le serveur). Pas d'annuaire, pas de suggestions d'inconnus.
- Le bouton QR de la barre du haut devient un raccourci de la liste.

## Preuves
`test/ui/nouvelle_discussion_test.dart` (5 cas) ; `connection_requests_test.dart` adapté.
