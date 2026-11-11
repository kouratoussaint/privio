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

# PRIVIO — Dossier maître à transmettre à Claude
**Version 1.0 — 11 novembre 2026 | Statut : périmètre validé, points d'implémentation à auditer**

## Ordre de lecture obligatoire
1. `00_DECISIONS_VALIDÉES.md` (source de vérité contractuelle)
2. `IDENTITE_VISUELLE/01_GUIDE_DE_MARQUE.md` + image `logo_option_1_reference.png`
3. `01_CAHIER_DES_CHARGES_FONCTIONNEL.md`
4. `02_REGLES_METIER_ET_SECURITE.md`
5. `03_ARCHITECTURE_SUPABASE_FIREBASE_GITHUB.md`
6. `04_CONSOLE_ADMINISTRATION.md`
7. `05_ECRANS_ET_PARCOURS.md`
8. `06_MODELE_DONNEES_ET_RLS.md`
9. `07_API_ET_EVENEMENTS.md`
10. `08_TESTS_CRITERES_ACCEPTATION.md`
11. `09_PLAN_DEVELOPPEMENT.md`
12. `10_PROMPT_MAITRE_CLAUDE.md`
13. `TECHNIQUE/` (exemples de configuration et CI, non prêts à déployer sans adaptation).

## Règle de préséance
En cas de contradiction : décisions validées > règles métier/sécurité > cahier fonctionnel > architecture > maquettes indicatives > exemples de code. Claude doit signaler toute contradiction et proposer une résolution avant de coder. Les exemples sont des amorces, pas une preuve de conformité.

## Livrables attendus de Claude
Code Flutter Android; console React; migrations Supabase, RLS et tests; Edge Functions; intégration FCM sans contenu en clair; pipeline GitHub Actions générant APK de test; documentation de déploiement; rapports de tests; revue sécurité du chiffrement et de l'expiration.

**Note logo :** image sélectionnée = concept graphique raster extrait d'une planche. La recréation vectorielle fidèle et les exports professionnels restent à produire/valider. Ne pas présenter ce fichier comme un SVG source ou un logo final haute définition.

## Mise à jour — inscription validée



