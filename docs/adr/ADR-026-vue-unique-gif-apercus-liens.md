# ADR-026 — Vue unique, GIF (KLIPY), aperçus des liens

**Statut** : accepté (lot 7.3b, décisions du 14/11/2026, amendement 17 : A, B, C, E, G).

## Décision
- **Vue unique** (photos et vocaux) : interrupteur « 1 » dans l'aperçu d'une photo (la
  légende est alors désactivée : une photo en vue unique n'en a pas) et dans la préécoute
  d'un vocal. Le message porte `view_once` ; le serveur ne donne le chemin du fichier
  (`get_messages`, `can_read_photo`, `can_read_voice`) qu'à un destinataire qui vient de
  l'ouvrir (`open_view_once`), pendant 2 minutes au plus et jusqu'à `close_view_once` ;
  jamais à l'expéditeur, jamais une seconde fois. Quand tous les destinataires ont fermé,
  le fichier est purgé. L'application ne range jamais un média en vue unique sur le
  téléphone (ni chez l'expéditeur ni chez le destinataire) : il reste en mémoire le temps
  de l'affichage ; la photo s'affiche sans aucun bouton (captures bloquées comme partout)
  et se ferme seule au bout de 2 minutes. L'expéditeur voit « Pas encore ouverte » /
  « Ouverte » (« Ouverte par n » dans un groupe).
- **GIF** : fournisseur KLIPY (Tenor a fermé son API le 30/06/2026). La clé reste sur le
  serveur (secret GitHub `KLIPY_API_KEY` → secret des fonctions). `gif-search` relaie la
  recherche (tendances si vide) avec un identifiant client pseudonyme (`gif_customer_id`,
  300 recherches par heure) ; les vignettes du sélecteur viennent directement de KLIPY
  (décision C). À l'envoi, `gif-send` télécharge le GIF depuis les seuls serveurs KLIPY,
  vérifie qu'il s'agit bien d'un GIF ou WebP (≤ 2048 px, ≤ 4 Mio) et le copie dans le
  bucket privé `gifs` : les destinataires le lisent avec leur jeton, jamais chez KLIPY.
  Contenu « Tout public » par défaut, « Modéré » possible (Confidentialité → Contenu des
  GIF), réglage gardé sur le téléphone.
- **Aperçus des liens** : quand j'envoie un message contenant un lien et que le réglage
  « Aperçus des liens » (Confidentialité, activé par défaut) est actif, l'application
  demande l'aperçu au serveur (`link-preview`, mes messages seulement, 60 par heure). Le
  serveur visite la page avec des protections contre la falsification de requêtes (http(s)
  seulement, ports 80/443, aucune adresse privée, locale ou de métadonnées, résolution DNS
  vérifiée, 3 redirections, 5 s, page ≤ 512 Ko, image ≤ 300 Ko JPEG/PNG/WebP) et range
  titre, description, site et image (bucket privé `previews`). Ni mon téléphone ni celui de
  mes contacts ne contacte le site. L'aperçu disparaît avec le message (supprimé pour tous,
  expiré). Toucher la carte ouvre le lien dans le navigateur **après confirmation**.

## Preuves
pgTAP `29_vue_unique_gif_liens` (suite : 29 fichiers, 900 assertions) ;
`scripts/ci/expression_e2e.py` (vue unique de bout en bout, GIF 401/503/422, aperçus
refusés pour les adresses locales et de métadonnées) ; tests Flutter
`test/ui/vue_unique_gif_test.dart` (12 cas) ; suite complète 413 tests.
Non vérifiable depuis l'environnement de développement (pas d'accès à Internet) : la
recherche KLIPY réelle et un aperçu de lien réussi — à vérifier sur staging et téléphone.
