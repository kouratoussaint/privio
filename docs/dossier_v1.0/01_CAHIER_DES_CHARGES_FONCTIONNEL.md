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

# Cahier fonctionnel utilisateur — PRIVIO
Toutes les fonctionnalités ci-dessous sont **validées** sauf celles explicitement marquées « proposition à paramétrer »; elles doivent être implémentées selon la version indiquée. Une fonction administrable doit disposer d'un état par défaut, d'une validation côté serveur, d'une représentation UI et de tests.

## MVP
### AUTH — Compte
AUTH-001 inscription et connexion exclusivement par téléphone avec OTP Supabase Auth; AUTH-002 connexion/reconnexion; AUTH-003 profil (avatar, nom, identifiant, à-propos); AUTH-004 autorisations facultatives; AUTH-005 gestion sessions/appareils; AUTH-006 déconnexion et suppression compte; AUTH-007 biométrie locale optionnelle; AUTH-008 consentements et préférences.
### CONTACT — Contacts
CONTACT-001 recherche d'utilisateur; CONTACT-002 carnet d'adresses opt-in avec minimisation; CONTACT-003 ajout/consultation contact; CONTACT-004 invitation volontaire uniquement; CONTACT-005 blocage/déblocage; CONTACT-006 demandes de contact si politique active.
### CHAT — Discussions
CHAT-001 liste conversations 1:1; CHAT-002 envoyer/recevoir texte et emojis; CHAT-003 réponses contextualisées sans rétention après expiration; CHAT-004 réactions; CHAT-005 modification dans délai configurable sans prolonger TTL; CHAT-006 supprimer pour soi/tous selon politique; CHAT-007 statuts pending/sent/delivered/read; CHAT-008 saisie en cours; CHAT-009 recherche uniquement sur contenu accessible et déchiffré localement; CHAT-010 filtres toutes/non lues/favoris/groupes; CHAT-011 épingler/archiver/sourdine/marquer non lu; CHAT-012 brouillons locaux; CHAT-013 détection contrôlée des liens; CHAT-014 file d'attente hors ligne et reprise idempotente.
### VOICE — Vocaux
VOICE-001 maintenir/enregistrer; VOICE-002 verrouiller l'enregistrement; VOICE-003 arrêt automatique 30 s; VOICE-004 préécoute/annulation; VOICE-005 lecture/pause/progression/vitesse facultative; VOICE-006 compression et chiffrement; VOICE-007 validation serveur de durée/métadonnées sans déchiffrement.
### PHOTO — Photos
PHOTO-001 capture/galerie via permission appropriée; PHOTO-002 prévisualisation et légende; PHOTO-003 compression et chiffrement client; PHOTO-004 5 photos/jour/compte par défaut, chaque image = 1; PHOTO-005 compteur de quota; PHOTO-006 affichage médias autorisés; PHOTO-007 pas d'enregistrement automatique en galerie; PHOTO-008 vidéo/document indisponibles au MVP par défaut.
### TTL — Expiration
TTL-001 `sent_at` serveur; TTL-002 `expires_at = sent_at + 72h`; TTL-003 refus lecture/synchronisation à expiration; TTL-004 purge locale/cache/miniatures/index; TTL-005 suppression physique asynchrone; TTL-006 message non lu expire aussi; TTL-007 réponse/édition/réaction ne prolongent pas l'original; TTL-008 notification expirée ne révèle aucun contenu; TTL-009 impossibilité de restauration depuis sauvegardes.
### SECURITY — Confidentialité
SEC-001 chiffrement E2EE des messages et pièces jointes; SEC-002 clés côté appareil; SEC-003 vérification des identités; SEC-004 verrouillage local; SEC-005 FLAG_SECURE sur écrans sensibles Android; SEC-006 transfert interne désactivé; SEC-007 partage externe désactivé; SEC-008 copie/export/galerie désactivés; SEC-009 réglages en ligne/dernière présence/accusés; SEC-010 alertes de changement de clés; SEC-011 sessions inconnues révocables; SEC-012 blocage et signalement avec divulgation volontaire de preuve uniquement.
### GROUP — Groupes (pas de communautés)
GROUP-001 création et photo/description; GROUP-002 invitation/adhésion; GROUP-003 rôles propriétaire/admin/membre; GROUP-004 gestion membres; GROUP-005 restrictions de publication; GROUP-006 messagerie texte/vocaux/photos soumise aux quotas; GROUP-007 réponses/réactions; GROUP-008 mute/quitter/signaler; GROUP-009 limite configurable (100 proposé, non confirmé); GROUP-010 E2EE groupe avec gestion des changements de membres.
### PUSH — Notifications
PUSH-001 FCM messages/groupes/mentions/invitations/annonces; PUSH-002 notification générique sans texte déchiffré; PUSH-003 réglages globaux et par conversation; PUSH-004 silencieux et regroupement; PUSH-005 suppression best effort des notifications périmées; PUSH-006 permission Android et jetons révoqués.
### DATA — Réseau et stockage
DATA-001 économie de données; DATA-002 compression; DATA-003 téléchargement manuel médias; DATA-004 offline limité aux données non expirées; DATA-005 file d'envoi; DATA-006 reprise réseau; DATA-007 indicateur connexion; DATA-008 cache nettoyé; DATA-009 consommation et espace local.
### SUPPORT — Aide
SUP-001 FAQ; SUP-002 contact support; SUP-003 signalement utilisateur/message/groupe; SUP-004 anti-spam/rate limits; SUP-005 demande de réexamen; SUP-006 suppression compte et données selon règles applicables.

## V2
CALL-001 audio 1:1; CALL-002 vidéo 1:1; CALL-003 accepter/refuser/historique; CALL-004 micro/caméra/basculement; CALL-005 vidéo 7 min max par défaut, compte à rebours, avertissement et fin imposée côté service; CALL-006 adaptation réseau; CALL-007 confidentialité des appels et politique d'enregistrement; CALL-008 appels de groupe uniquement après validation de capacité et sécurité.
STATUS-001 texte/photo; STATUS-002 audience; STATUS-003 vues et réponses; STATUS-004 suppression; STATUS-005 durée configurable dans les bornes produit.

## V3
BILL-001 offres/abonnements; BILL-002 paiements Mobile Money via prestataire conforme; BILL-003 reçus/historique; ORG-001 espaces professionnels; IOS-001 application iOS; WEB-001 messagerie Web; DEVICE-001 multi-appareil avec E2EE vérifié.

**Exclusion absolue : COMMUNAUTÉS.**


