# ADR-035 — Alerte anti-usurpation et « Ce que Privio garde »

**Statut** : accepté (lot 8.4c, décisions du 15/11/2026 : A texte validé ; B engagement
« pas de publicité, pas de revente de vos données » ; C alerte aussi sur la carte d'un
membre de groupe ; décision F antérieure : aucune mention du chiffrement).

## Décision
- **Alerte anti-usurpation**, calculée sur le téléphone (rien n'est envoyé) : un compte
  qui n'est PAS mon contact porte un nom identique à celui d'un de mes contacts (sans
  accents, majuscules ni espaces) ou à une lettre près (4 lettres au moins ; en dessous :
  identique seulement). Affichée sur une demande de connexion reçue, sur un résultat de
  recherche (Nouvelle discussion) et sur la carte d'un membre de groupe : « Attention :
  vous avez déjà un contact nommé X (@x). Ce compte est différent : @y. Vérifiez auprès
  de la personne… ». La photo n'est pas comparée.
- **« Ce que Privio garde »** : écran accessible depuis Aide et Confidentialité ; texte
  validé le 15/11/2026 (messages et médias effacés à la fin de leur durée, 72 h au plus ;
  compte jusqu'à sa suppression ; demandes de connexion 7 jours après réponse ;
  signalements et assistance 90 jours ; journal des notifications 7 jours ; journal de
  l'équipe 30 jours ; ce que Privio ne fait jamais ; copie protégée sur le téléphone).
  Toute évolution de ces durées doit mettre ce texte à jour (et les CGU, lot 6.3).

## Preuves
`test/ui/anti_usurpation_test.dart` (7 cas, dont l'absence du mot « chiffr… »).
