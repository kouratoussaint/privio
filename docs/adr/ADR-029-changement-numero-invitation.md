# ADR-029 — Changer de numéro, inviter un ami

**Statut** : accepté (lot 8.1c, décisions du 15/11/2026 : C code Privio demandé si le
verrouillage est activé, contacts non prévenus ; D partage de l'identifiant seulement).

## Décision
- **Changer de numéro** (Ma fiche → Numéro → Changer) : parcours natif de Supabase Auth —
  `updateUser(phone)` envoie un code au NOUVEAU numéro, `verifyOTP(type: phone_change)`
  le valide. Tant que le code n'est pas saisi, rien ne change. Le déclencheur existant
  `on_auth_user_phone_sync` recopie le numéro confirmé dans `private.user_contacts` (le
  réglage « trouvable par numéro » est conservé) : **aucune migration**. Compte,
  identifiant, discussions et groupes inchangés ; l'ancien numéro est libéré ; personne
  n'est prévenu (le numéro n'est jamais affiché dans Privio). Un numéro déjà utilisé est
  refusé (`phone_exists` → « Ce numéro est déjà utilisé par un autre compte Privio. »).
  Si le verrouillage est activé, le code Privio est demandé avant l'envoi du SMS.
  Prérequis du projet hébergé : « Enable phone confirmations » activé (sinon Auth
  changerait le numéro sans code).
- **Inviter un ami** (Paramètres → Inviter un ami ; Nouvelle discussion → personne
  introuvable → « Inviter cette personne ») : partage Android (`share_plus`) d'un court
  texte avec mon identifiant, sans promesse de chiffrement ; le lien de téléchargement sera
  ajouté quand il existera.
- Deux numéros de test locaux ajoutés (`22670000004`, `22670000005`) dans
  `supabase/config.toml`, jamais poussés vers un projet hébergé.

## Preuves
`scripts/ci/numero_e2e.py` (13 vérifications contre GoTrue réel : code vers le nouveau
numéro, rien avant le code, numéro pris refusé, mauvais code refusé, numéro privé suivi,
même compte, ancien numéro libéré) ; tests Flutter `test/ui/numero_invitation_test.dart`
(5 cas) ; suite complète 435 tests.
