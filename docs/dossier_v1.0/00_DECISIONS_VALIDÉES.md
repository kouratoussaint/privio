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

# Décisions définitives de périmètre — PRIVIO
- Nom commercial : **Privio** (remplace FLASH72 dans tous les livrables).
- Identité graphique : **proposition 1** retenue par le commanditaire; bulle en forme de P, bouclier/cadenas, bleu nuit et violet; image de référence fournie.
- Produit : messagerie éphémère inspirée des usages de WhatsApp, sans reproduction de ses actifs graphiques, code, marque ni interface à l'identique.
- **COMMUNAUTÉS SUPPRIMÉES** : ne pas développer, dessiner, modéliser ni inclure dans MVP/V2/V3, menu, console, API ou backlog.
- MVP : Android Flutter; conversations 1:1 et groupes; texte, emojis, réponses, réactions, accusés, recherches; vocaux <=30 s; photos <=5 par utilisateur et par jour; expiration 72 h; chiffrement E2EE; restrictions de transfert/partage/copie/export/sauvegarde galerie; protection anti-capture Android; notifications FCM; mode économie de données; comptes/contacts/profils/sessions; modération et support; console Web avec politiques dynamiques.
- V2 : appels audio et vidéo (vidéo <=7 min par défaut), statuts. **Aucune communauté**.
- V3 : abonnements, paiements, organisations/espaces pro, iOS et messagerie Web; appareils liés si sécurité multi-appareil correctement conçue.
- Médias vidéo et documents : envoi désactivé par défaut au MVP; aucune obligation de pipeline complet MVP. Activation future via release + politique, pas via simple interrupteur si fonctionnalité non développée.
- Backend retenu : Supabase (Auth, PostgreSQL, Realtime, Storage, Edge Functions), FCM pour push; code sur GitHub et CI/APK via GitHub Actions. Console React/TypeScript. Appels V2 LiveKit/WebRTC à confirmer après POC.
- Fuseau initial quotas : Africa/Ouagadougou. Groupe max 100 = hypothèse à confirmer. **INSCRIPTION ET CONNEXION VALIDÉES : téléphone uniquement avec OTP Supabase Auth. Recherche par numéro ou identifiant Privio.** Le prestataire SMS et ses coûts restent à sélectionner.
- Durée 72 h : **invariant produit**. Tout changement administrateur doit rester compatible avec la promesse 72 h; possibilité de réduire, pas d'étendre sans validation explicite d'une nouvelle politique produit.
- Tous les paramètres utiles administrables dans des bornes sûres; impossible de désactiver chiffrement, RLS, audit admin, ou d'accorder lecture de conversations E2EE aux admins.
- Les restrictions anti-capture/anti-partage ne sont pas absolues sur appareil compromis ou caméra externe.


