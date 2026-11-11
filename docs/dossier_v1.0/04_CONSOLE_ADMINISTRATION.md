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

# Console administrateur — fonctions obligatoires
1. **Tableau de bord** : utilisateurs actifs, messages chiffrés (compteurs uniquement), groupes, erreurs, volume média, purge, coûts, taux notifications; pas de lecture du contenu.
2. **Comptes** : recherche, statut, suspension, réactivation, sessions, signalements, blocage abus; traçabilité.
3. **Messagerie** : TTL (bornes), édition, réactions, accusés, saisie, réponses, recherche, limites de débit, anti-spam.
4. **Médias** : quota photos, formats, taille, compression, vocal 30 s, vidéo/doc désactivés, politique de téléchargement.
5. **Sécurité** : anti-capture, transfert/partage/copie/export, paramètres de visibilité, verrouillage, MFA, surveillance, audit; les invariants ne sont pas désactivables.
6. **Groupes** : activation, membres max, rôles, invitations, restrictions, modération. **Pas de communautés**.
7. **Notifications** : catégories FCM, annonces, plages de silence, templates génériques, quotas et erreurs.
8. **Réseau** : économie de données, tailles limites, retries, politiques offline/cache.
9. **Politiques** : héritage, ciblage, versions, diff, rollback, approbation, planification, feature flags, canary rollout.
10. **Administration** : rôles RBAC (superadmin, opérateur, support, analyste, sécurité), MFA, séparation des tâches, journal des modifications.
11. **Support/modération** : tickets, signalements et preuves explicitement soumises, appels, réexamens, procédures.
12. **Infrastructure** : santé Supabase, FCM, Storage, quotas, purge, alertes, maintenance, statut déploiements.
13. **V2** : appels audio/vidéo, durée vidéo 7 min, statuts.
14. **V3** : abonnements, paiements, organisations, facturation, plateformes.

## Écrans admin prioritaires MVP
Login MFA; dashboard; utilisateurs/liste/détail; groupes/liste/détail; politiques globales; messagerie; médias; sécurité; notifications; journaux d'audit; rôles; signalements; système/santé; maintenance; historique des versions.

## Exigences transverses
Chaque réglage : clé stable, type, valeur par défaut, bornes, portée, rôle autorisé, validation serveur, affichage d'impact, historique et tests. Réponse claire si changement non applicable aux anciennes versions de l'APK. Les paramètres non livrés ne doivent pas apparaître comme activables.

## Paramètres de compte et de découverte — décisions produit

