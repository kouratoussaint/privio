## DÉCISION DÉFINITIVE — AUTHENTIFICATION TÉLÉPHONE UNIQUEMENT (11 novembre 2026)
**Cette décision remplace toute mention antérieure de connexion ou inscription par e-mail.**
- Inscription ET connexion uniquement par numéro de téléphone vérifié via OTP Supabase Auth (E.164, +226 par défaut).
- Aucun écran de choix téléphone/e-mail, aucun OTP e-mail, aucun mot de passe ou connexion par e-mail. Un e-mail facultatif de contact, s'il est ajouté plus tard, ne sera jamais un identifiant d'authentification.
- Chaque compte possède un `auth.users.id` et un identifiant Privio (`handle`) unique.
- Recherche de contacts par numéro vérifié (avec consentement de découvrabilité) OU par identifiant Privio, avec limitation des recherches et protection anti-énumération.
- Développement : numéros de test et OTP prédéfinis de Supabase Auth, uniquement dans les environnements isolés, sans envoi de SMS réel.
- Production : prestataire SMS réel configurable via Supabase Auth, sans dépendance directe à un fournisseur dans Flutter ; tester la délivrabilité +226 avant lancement.
- OTP de test strictement interdits en production. Anti-abus, délais de renvoi, limitation des essais, sécurité des sessions et récupération de compte après changement/perte du numéro à définir sans contourner la vérification.
- Critères de recette : inscription et reconnexion téléphone, OTP valide/invalide/expiré, quota renvoi, recherche numéro/handle, confidentialité, absence de parcours e-mail, impossibilité de déployer les OTP de test en production.

# Plan de tests et critères d'acceptation
## P0 — bloquants avant mise en production
- TTL : à `expires_at - 1 s` lecture autorisée; à `expires_at` lecture refusée, y compris RPC, realtime, Storage et cache; message non lu expire.
- Édition, réponse, réaction et changement de groupe ne prolongent pas TTL.
- 5 photos/jour : 20 requêtes concurrentes, maximum 5 unités acceptées; retry idempotent ne double-compte pas; groupe inclus; fuseau Africa/Ouagadougou testé à minuit.
- Vocal 30 s : UI arrête à 30 s; envoi de durée déclarée >30 rejeté; auditer contournements possibles liés à E2EE.
- E2EE : serveur, admin et opérateur ne peuvent lire plaintext; échange de clés, appareil révoqué, ajout/retrait membre et changement de clé testés; audit crypto indépendant requis.
- RLS : utilisateur A ne lit pas conversation de B; membre retiré ne récupère pas nouveaux messages; service-role absent de clients.
- Partage : aucun bouton transfert/partage/copie/export en politique interdite; API refuse opérations prohibées; FLAG_SECURE vérifié sur appareils Android cibles; limites documentées.
- FCM : payload sans plaintext; notifications désactivées respectées; jetons expirés traités; clic sur message expiré ne révèle rien.
- Admin : MFA, RBAC, audit, rollback, validation des bornes; impossible de désactiver E2EE/RLS/audit.
- CI : lint/analyse/tests, migration validation, APK de debug téléchargeable; clés de production protégées.

## P1 — qualité MVP
- UX : 28 écrans, thèmes clair/sombre, petit écran, lecteurs d'écran, français simple, 3G instable.
- Offline : file d'attente, retour réseau, expiration locale, doublons, quotas au moment de l'acceptation serveur.
- Photo : compression, affichage quota, album >solde rejeté sans dépassement.
- Groupes : invitations, rôles, mute, sortie, suppression membre et chiffrement.
- Support : blocage, signalement avec consentement explicite, suppression compte.

## Tests automatiques attendus
Unitaires Dart/TS/SQL; widget tests Flutter; tests d'intégration Supabase local; tests RLS multi-rôles; tests E2E Android (au moins parcours critiques); tests CI; tests charge pour quotas et purge; contrôle dépendances/licences; tests de restauration sauvegardes et de confidentialité des logs.

## Définition de terminé
Code versionné; migrations reproductibles; documentation; critères P0 réussis; tests P1 documentés; revue sécurité et confidentialité; APK de test généré; aucune communauté dans le produit.

## Scénarios supplémentaires obligatoires — AUTH/CONTACT
1. Inscription téléphone valide avec OTP SMS : succès, profil créé, identifiant Privio unique.
2. Inscription avec numéro vérifié et OTP correct : succès ; aucun parcours e-mail disponible.
3. Numéro invalide, OTP erroné/expiré, tentatives répétées : erreurs contrôlées et limitations.
4. Deux utilisateurs choisissent le même identifiant Privio simultanément : un seul obtient le handle, l’autre reçoit une erreur exploitable.
5. Recherche par handle : retrouve le compte autorisé, sans divulguer ses coordonnées privées.
6. Recherche par numéro : retrouve seulement un numéro vérifié et découvrable ; sinon réponse non révélatrice.
7. Recherche massive, utilisateurs bloqués et compte supprimé : aucun contournement de confidentialité.
8. Reconnexion, renouvellement de session et changement de méthode : identité stable et clés E2EE protégées.


