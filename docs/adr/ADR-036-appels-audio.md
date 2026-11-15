# ADR-036 — Appels audio à deux

**Statut** : accepté (lot 9.1a, décisions du 15/11/2026 : A relais Cloudflare ; B seuls les
contacts appellent, réglage « Recevoir des appels » ; C pas de nom sur l'écran de sonnerie
quand Privio est verrouillé ; D seulement une trace dans la discussion, pas d'historique ;
E on décroche sans le code, le reste reste verrouillé ; F découpage 9.1a / 9.1b / 9.2).

## Décision
- **Voix de téléphone à téléphone** (WebRTC, `flutter_webrtc`) ; la base ne fait que la
  mise en relation. Aucun enregistrement, aucun son sur le serveur.
- **Base** (migration `20261115000400`) : `private.calls` (état : sonne, décroché, refusé,
  manqué, annulé, terminé), `private.call_signals` (descriptions de session et candidats
  réseau, effacés à la fin de l'appel), `private.call_settings` (« Recevoir des appels »).
  Fonctions : `start_call` (contact seulement, jamais en cas de blocage, un appel à la
  fois, « occupé » si le correspondant est déjà en appel), `answer_call`, `decline_call`,
  `end_call`, `send_call_signal`, `call_state` (état + signaux reçus ; sert de présence),
  `my_open_call`, `can_use_call_relay`. Sans réponse en 45 s : manqué ; sans nouvelles
  d'un téléphone pendant 60 s : terminé (`pg_cron` chaque minute). Chaque évènement est
  annoncé au correspondant sur son canal privé (`call`).
- **Trace** : message système `{"e":"call","k":"audio","v":"ended:183"}` (auteur :
  l'appelant), affiché selon chacun (« Appel sortant · 03:03 », « Appel manqué »…), qui
  s'efface comme les messages. Les appels terminés sont gardés 7 jours sans contenu
  (diagnostic), puis effacés.
- **Relais** : fonction `call-ice`, seulement pendant un appel : STUN Cloudflare gratuit et,
  si la clé est configurée (secrets GitHub `CLOUDFLARE_TURN_KEY_ID` /
  `CLOUDFLARE_TURN_API_TOKEN` → secrets des fonctions), un accès TURN valable 2 h. La clé
  ne quitte jamais le serveur.
- **Application** : bouton 📞 (discussion à deux, fiche du contact) ; écran d'appel posé
  au-dessus de toute l'application (verrouillage compris) ; sonnerie et tonalité d'attente
  ; micro, haut-parleur, raccrocher, réduire en bandeau ; « Recevoir des appels » dans
  Confidentialité. Appels reçus quand Privio est ouvert (9.1a) ; téléphone fermé ou
  verrouillé : lot 9.1b.

## Preuves
`supabase/tests/database/33_appels.test.sql` ; `scripts/ci/appels_e2e.py` (mise en relation
et `call-ice` contre un Supabase local complet) ; `test/ui/appels_test.dart` (10 cas).
La qualité de la voix se vérifie sur deux téléphones.
