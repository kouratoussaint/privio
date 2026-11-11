# Rapport — Étape 1 : fondation (11 novembre 2026)

## Livré
- **Base** : 4 migrations (fondations de sécurité, politiques administrables, identité et
  recherche, appareil unique). Refus par défaut, schéma `private` non exposé, aucune fonction
  exécutable par `anon`.
- **Application** : écrans 01 Démarrage, 02 Engagements, 03 Accueil (un seul bouton
  téléphone), 04 Numéro, 05 Code SMS (renvoi après 60 s), 06 Profil (disponibilité de
  l'identifiant en direct), 07 Autorisations facultatives ; navigation Discussions / Groupes /
  Paramètres (états vides) ; paramètres : profil, découvrabilité par numéro, déconnexion.
- **Sécurité Android** : FLAG_SECURE global, sauvegardes et transferts désactivés, session dans
  le Keystore, refus de démarrer avec une clé secrète, partage de texte vers d'autres apps retiré.
- **Identité visuelle** : recréation vectorielle **provisoire** du logo n° 1 (`docs/brand/`),
  icône adaptative, icône de notification, écran de lancement. **À valider.**
- **CI** : garde-fous, tests SQL sur Supabase réel, test d'intégration Auth, Flutter
  (format, analyse, tests), APK de test (arm64 et 32 bits) en artefacts ; déploiement manuel des migrations.

## Résultats de tests (exécutés le 11/11/2026 dans l'environnement de développement)
| Suite | Résultat |
|---|---|
| Garde-fous de conformité | 9/9 ✅ |
| pgTAP (PostgreSQL 16 + imitation du schéma `auth`) | 57/57 ✅ |
| Concurrence réelle sur l'identifiant (scénario AUTH n°4) | ✅ 1 succès, 1 `HANDLE_TAKEN` |
| Flutter : analyse `--fatal-infos` | 0 problème ✅ |
| Flutter : tests unitaires, widgets, parcours complet | 66/66 ✅ |
| Workflows (actionlint) | ✅ |

**Non encore exécuté — sera prouvé au premier passage de la CI GitHub :**
1. les mêmes tests pgTAP sur un **vrai** Supabase (PostgreSQL 17, vraies tables `auth`) ;
2. le test d'intégration `auth_smoke_test.sh` (OTP réel, trigger, révocation d'appareil) ;
3. la **compilation de l'APK** (pas de SDK Android dans l'environnement de développement).

**Vérification manuelle à faire sur téléphone :** capture d'écran bloquée, aperçu masqué dans
les applications récentes, icône lisible sur l'écran d'accueil.

## Défauts trouvés et corrigés pendant l'étape
- Droits par défaut PostgreSQL : un retrait par schéma est sans effet → durcissement explicite
  (`private.harden_privileges()`) en fin de chaque migration.
- Contrainte CHECK appelant une fonction : bloquait la modification du nom → règle intégrée.
- Contrôleur de session : rechargement en boucle lors d'une session révoquée → corrigé et testé.

## Limites connues
- Photo de profil, suppression de compte, changement de numéro : étapes suivantes.
- Purge des compteurs de limitation échus : tâche planifiée à l'étape 2.
- Actions GitHub référencées par version majeure (`@v4`) : à figer par empreinte SHA (étape 6).
- Points ouverts : B1 à B10 (`00_DECISIONS_VALIDEES_v1.1.md`).
