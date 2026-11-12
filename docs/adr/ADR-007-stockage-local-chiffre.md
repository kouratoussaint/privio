# ADR-007 — Stockage local chiffré, hors connexion et effacement à expiration

**Statut** : accepté (lot 2.4).

**Décision** : les discussions, messages et envois en attente sont conservés dans **un seul
fichier chiffré en AES-256-GCM** (`cryptography`, pur Dart, licence Apache-2.0), avec une clé de
256 bits générée sur le téléphone et gardée dans le **Keystore Android**
(`flutter_secure_storage`). Vecteur aléatoire neuf à chaque écriture ; chiffrement authentifié
(toute altération est détectée et le fichier est écarté) ; écriture atomique.

**Pourquoi pas SQLCipher** : `sqlcipher_flutter_libs` est en fin de vie et toute bibliothèque
native ajoute un risque de compilation (compileSdk 37, AGP 9). Le volume est faible (72 h au
plus), un document chiffré suffit et la recherche se fait en mémoire.

**Garanties** :
- rien d'expiré n'est conservé : purge à chaque lecture et écriture, et toutes les 30 s,
  **même sans réseau** ; l'aperçu d'un message expiré est aussi effacé de la liste ;
- un message en attente d'envoi n'attend jamais plus de 72 h ;
- déconnexion ou compte ouvert sur un autre téléphone : fichier **et clé** détruits ;
- les sauvegardes Android restent désactivées (ADR-003, manifeste).

**Hors connexion** : l'application affiche d'abord le contenu local, puis synchronise. Un envoi
entre dans la file chiffrée avant de partir ; sans réseau il attend et repart seul (toutes les
15 s, au retour du réseau, à la reconnexion temps réel ou au retour dans l'app), avec le même
identifiant client : jamais de doublon côté serveur.

**Limite connue** : un téléphone rooté ou compromis peut lire la mémoire de l'application.
