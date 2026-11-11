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

# Écrans Android et parcours
Référence mobile de conception : **393 × 852 dp**, adaptable; SafeArea, claviers, accessibilité, petites tailles, thèmes clair/sombre. États obligatoires par écran : normal, chargement, vide, erreur, hors ligne si pertinent, accès refusé, expiration si pertinent.

## Inventaire MVP (28 écrans fonctionnels)
01 Splash/initialisation; 02 Onboarding confidentialité/72h; 03 Choix connexion/inscription; 04 Saisie du numéro de téléphone; 05 Vérification OTP; 06 Création profil; 07 Permissions facultatives; 08 Liste discussions; 09 Recherche globale; 10 Sélection contact; 11 Discussion individuelle; 12 Détails conversation/contact; 13 Composer/aperçu photo; 14 Enregistreur/préécoute vocal; 15 Visionneuse photo; 16 Info message/expiration; 17 Liste groupes; 18 Création groupe; 19 Discussion groupe; 20 Infos/participants/permissions groupe; 21 Notifications et préférences; 22 Paramètres généraux; 23 Confidentialité et sécurité; 24 Appareils et sessions; 25 Stockage/économie données; 26 Profil; 27 Blocage/signalement; 28 Aide/support.

## V2
29 Appels/historique; 30 Appel audio; 31 Appel vidéo avec minuterie; 32 Statuts/liste; 33 Créer statut; 34 Voir statut.

## V3
35 Abonnement/offres; 36 Paiements/reçus; 37 Espaces pro; 38 Appareils liés; déclinaisons iOS/Web distinctes.

## Navigation
MVP : onglets Discussions / Groupes / Paramètres; recherche et nouvelle discussion via actions de barre. V2 : navigation repensée pour Appels/Statuts sans saturer l'écran. **Jamais d'onglet Communautés**.

## Parcours critiques
- Inscription → consentement → OTP → profil → autorisations → discussions.
- Texte → chiffrement local → envoi idempotent → envoyé/livré/lu → TTL → disparition.
- Vocal → micro → minuterie 30 s → préécoute → chiffrement → envoi.
- Photo → sélecteur → quota visible → compression/chiffrement → acceptation atomique → expiration.
- Groupe → créer → inviter → permissions → envoyer → retirer membre (rotation de clés) → quitter.
- Hors ligne → lecture locale seulement si non expiré → file d'attente → retour réseau → validation des règles courantes.
- FCM → notification générique → ouverture → Auth + vérification TTL → déchiffrement local.

## Critères UI
Cibles 48 dp; couleurs de la charte; indicateur 72 h accessible; erreurs compréhensibles; permission refusée gérée sans blocage global; aucune action de transfert/partage interdite dans menus contextuels; pas de fausse promesse d'anti-capture absolue.

## Parcours d’inscription validé — correction obligatoire
Écran 03 : un seul choix « Continuer avec mon numéro de téléphone ». Écran 04 : formulaire numéro de téléphone uniquement. Écran 05 : saisie OTP SMS pour téléphone avec écran de confirmation adapté. Écran 06 : nom, identifiant Privio unique et photo facultative. Les autres écrans restent inchangés.
**Recherche de contacts :** proposer deux modes « Identifiant Privio » et « Numéro de téléphone » ; résultat par numéro seulement pour un numéro vérifié et découvrable, sans révéler les données privées. Afficher les erreurs, temporisations et états de réseau faible.
