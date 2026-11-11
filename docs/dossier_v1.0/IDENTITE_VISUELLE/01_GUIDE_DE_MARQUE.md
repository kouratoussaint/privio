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

# Guide d'identité visuelle — PRIVIO
## Positionnement
Privio : messagerie privée et éphémère, conviviale, moderne, rassurante, adaptée aux réseaux modestes. Ton français simple, clair et direct. Signature proposée, non encore formellement approuvée : **« Vos échanges. Votre confidentialité. »**

## Logo choisi
**Proposition 1** de la planche fournie : fond bleu nuit, dégradés violet/bleu, monogramme P évoquant une bulle de discussion, trois points de conversation, bouclier et cadenas, mot « Privio » en blanc. `logo_option_1_reference.png` est un recadrage de référence, non un master vectoriel. Respecter la composition générale; ne pas ajouter d'éléments ni adopter les concepts 2/3. Avant production, recréer proprement le symbole vectoriel, vérifier les espacements et la lisibilité à 24–48 px, obtenir validation.

## Palette de départ — à ajuster après échantillonnage exact du visuel
| Token | Valeur | Usage |
|---|---|---|
| `brand.navy` | `#111A42` | fonds premium, titres sur clair |
| `brand.purple` | `#8A35F2` | actions principales, accents |
| `brand.blue` | `#315BEE` | gradient et informations |
| `brand.lilac` | `#C879FF` | éclairages, accents secondaires |
| `surface.light` | `#F7F6FC` | fond clair |
| `surface.dark` | `#10152D` | fond sombre |
| `text.primary` | `#17182D` | texte principal clair |
| `text.inverse` | `#FFFFFF` | texte sur foncé |
| `status.success` | `#13866B` | succès, ne pas confondre avec couleur principale |
| `status.error` | `#C6354C` | erreur |

Les hexadécimaux sont des **tokens proposés**, non des couleurs officiellement extraites du logo. Claude doit vérifier le contraste (WCAG AA) et ne pas utiliser le violet clair pour du texte petit sur blanc.

## Typographie et iconographie
- Police libre : **Inter** (licence à vérifier au moment de l'intégration); fallback Noto Sans/Roboto.
- Titres 24–28 sp; sous-titres 18–20 sp; corps 14–16 sp; légendes >=12 sp selon contraste; support de l'échelle système.
- Icônes cohérentes, trait simple, coins arrondis; privilégier Material Symbols sous licence adaptée.
- Grille 4/8 dp; cibles tactiles >=48 dp; rayons 12–20 dp; animation discrète et désactivable.

## Composants visuels
- Barre supérieure : logo/nom Privio, recherche, menu; aucun emprunt visuel direct à WhatsApp.
- Navigation MVP : Discussions, Groupes, Paramètres. V2 ajoute Appels et Statuts après révision UX.
- Bulles de messages : sortants violet très pâle sur clair, entrants blanc; mode sombre à contraste vérifié; minuterie d'expiration discrète mais accessible.
- Carte de sécurité informative : « Les messages expirent après 72 heures »; ne jamais promettre confidentialité absolue.
- Compteur photos : « 3 photos restantes aujourd'hui ».
- Vocal : barre d'onde simple, compteur 00:30 max, préécoute.
- États : chargement, vide, erreur, hors ligne, contenu expiré, quota atteint, accès refusé, notification désactivée.

## Déclinaisons de logo à produire et faire valider
1. Logo complet horizontal, fonds clair/sombre.
2. Icône d'application Android adaptative (foreground/background séparés, zone sûre vérifiée).
3. Symbole monochrome clair et sombre.
4. Splash screen, favicon console, icône notification monochrome (FCM/Android).
5. Exports PNG 1024, 512, 192, 48 et SVG **uniquement après vectorisation réelle**.

## Interdits
Ne pas utiliser les logos WhatsApp, Signal ou Telegram; ne pas modifier la proposition retenue sans accord; ne pas apposer « 72h » au logo sélectionné (c'est le concept 3); ne pas intégrer d'images générées comme icônes système finales sans contrôle de netteté et licences.
