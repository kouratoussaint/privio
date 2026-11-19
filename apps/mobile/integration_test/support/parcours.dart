import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/services/account_api.dart';
import 'package:privio/data/services/messaging_api.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/home/home_shell.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lot 6.1 (ADR-055) : parcours complets de Privio contre le serveur local de la CI.
///
/// L'application est la vraie (vrais services, vrai serveur) ; seuls l'appareil photo,
/// le micro et les notifications sont remplacés. Une seconde personne (« Bob ») agit
/// en parallèle par l'API, comme le ferait un autre téléphone.

const pinParcours = '258014';

/// Trace lisible dans le journal de la CI.
void etape(String texte) => debugPrint('▶ Parcours\u202F: $texte');

/// Textes à l'écran (diagnostic d'un échec dans le journal de la CI).
String ecran() {
  final textes = <String>{};
  for (final e in find.byType(Text).evaluate()) {
    final t = (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText();
    if (t != null && t.trim().isNotEmpty) textes.add(t.trim());
  }
  return textes.take(60).join(' | ');
}

/// Attend que [f] apparaisse (temps réel : serveur, temps réel, animations).
Future<void> attendre(
  WidgetTester tester,
  Finder f, {
  Duration max = const Duration(seconds: 30),
  String? quoi,
}) async {
  final fin = DateTime.now().add(max);
  while (DateTime.now().isBefore(fin)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure(
    'Introuvable après ${max.inSeconds} s\u202F: ${quoi ?? f}\nÉcran\u202F: ${ecran()}',
  );
}

/// Attend que [f] disparaisse.
Future<void> attendreAbsence(
  WidgetTester tester,
  Finder f, {
  Duration max = const Duration(seconds: 30),
  String? quoi,
}) async {
  final fin = DateTime.now().add(max);
  while (DateTime.now().isBefore(fin)) {
    await tester.pump(const Duration(milliseconds: 200));
    if (f.evaluate().isEmpty) return;
  }
  throw TestFailure(
    'Toujours affiché après ${max.inSeconds} s\u202F: ${quoi ?? f}\nÉcran\u202F: ${ecran()}',
  );
}

/// Laisse l'écran se poser (au plus quelques secondes : certaines animations tournent).
Future<void> poser(WidgetTester tester, [Duration max = const Duration(seconds: 3)]) async {
  final fin = DateTime.now().add(max);
  do {
    await tester.pump(const Duration(milliseconds: 100));
  } while (SchedulerBinding.instance.hasScheduledFrame && DateTime.now().isBefore(fin));
}

/// Ferme les messages d'information du bas de l'écran (ils peuvent couvrir un bouton).
Future<void> fermerAnnonces(WidgetTester tester) async {
  for (final e in find.byType(ScaffoldMessenger).evaluate()) {
    (e as StatefulElement).state is ScaffoldMessengerState
        ? (e.state as ScaffoldMessengerState).clearSnackBars()
        : null;
  }
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> toucher(WidgetTester tester, Finder f) async {
  debugPrint('  · toucher $f');
  await attendre(tester, f);
  await fermerAnnonces(tester);
  await tester.ensureVisible(f.first);
  await poser(tester);
  await tester.tap(f.first);
  await poser(tester);
}

/// Revient à l'accueil (barre d'onglets visible), écran par écran.
Future<void> retourAccueil(WidgetTester tester) async {
  for (var i = 0; i < 6 && find.byType(PrivioNavBar).hitTestable().evaluate().isEmpty; i++) {
    etape('retour (${ecran().split(' | ').take(3).join(' | ')})');
    await tester.binding.handlePopRoute().timeout(
      const Duration(seconds: 5),
      onTimeout: () => false,
    );
    await poser(tester);
  }
  await attendre(tester, find.byType(PrivioNavBar), quoi: 'accueil');
}

/// Fait défiler la page jusqu'à [f] (sans attendre la fin des animations).
Future<void> defilerJusqua(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 30 && f.hitTestable().evaluate().isEmpty; i++) {
    if (f.evaluate().isNotEmpty) {
      await tester.ensureVisible(f.first);
      await poser(tester);
      continue;
    }
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
    await poser(tester);
  }
}

Finder onglet(String nom) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(nom));

Finder cle(String k) => find.byKey(Key(k));

/// Clé commençant par [prefixe] (identifiants de messages fixés par le serveur).
Finder clePrefixe(String prefixe, [String suffixe = '']) => find.byWidgetPredicate((w) {
  final k = w.key;
  return k is ValueKey<String> && k.value.startsWith(prefixe) && k.value.endsWith(suffixe);
});

/// Saisit [texte] et vérifie qu'il est bien dans le champ (un brouillon rechargé à
/// l'ouverture d'un écran peut l'avoir remplacé : on recommence alors).
Future<void> saisir(WidgetTester tester, Finder champ, String texte) async {
  await attendre(tester, champ);
  for (var essai = 0; essai < 5; essai++) {
    await tester.enterText(champ, texte);
    await tester.pump(const Duration(milliseconds: 500));
    final edit = find.descendant(of: champ, matching: find.byType(EditableText));
    final actuel = edit.evaluate().isEmpty
        ? null
        : tester.widget<EditableText>(edit.first).controller.text;
    // Champ mis en forme (numéro « 70 00 00 03 ») : on compare sans les espaces.
    if (actuel?.replaceAll(' ', '') == texte.replaceAll(' ', '')) return;
  }
  throw TestFailure('Saisie impossible dans $champ\nÉcran\u202F: ${ecran()}');
}

Future<void> taperCode(WidgetTester tester, String code) async {
  for (final d in code.split('')) {
    await tester.tap(cle('pin.$d'));
    await tester.pump(const Duration(milliseconds: 80));
  }
  await poser(tester);
}

/// Attend une condition côté serveur (lecture par l'API de Bob).
Future<T> serveur<T>(
  WidgetTester tester,
  Future<T?> Function() lire, {
  required String quoi,
  Duration max = const Duration(seconds: 30),
}) async {
  final fin = DateTime.now().add(max);
  while (DateTime.now().isBefore(fin)) {
    final v = await lire();
    if (v != null) return v;
    await tester.pump(const Duration(milliseconds: 500));
  }
  throw TestFailure(
    'Serveur\u202F: $quoi non constaté après ${max.inSeconds} s\nÉcran\u202F: ${ecran()}',
  );
}

/// Seconde personne, sur son propre client (aucune session partagée avec l'application).
class Pair {
  Pair._(this.client, this.account, this.api, this.id);

  final SupabaseClient client;
  final SupabaseAccountApi account;
  final SupabaseMessagingApi api;
  final String id;

  static Future<Pair> connecter(
    String url,
    String cleApi, {
    required String telephone,
    required String identifiant,
    required String nom,
  }) async {
    final client = SupabaseClient(
      url,
      cleApi,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    await client.auth.signInWithOtp(phone: telephone);
    await client.auth.verifyOTP(phone: telephone, token: '123456', type: OtpType.sms);
    final account = SupabaseAccountApi(client);
    await account.createProfile(handle: identifiant, displayName: nom);
    await account.registerDevice(appVersion: 'parcours');
    return Pair._(client, account, SupabaseMessagingApi(client), client.auth.currentUser!.id);
  }

  Future<List<ChatMessage>> messages(String conversationId) =>
      api.getMessages(conversationId, limit: 50);

  Future<ChatMessage?> message(String conversationId, bool Function(ChatMessage) test) async {
    final all = await messages(conversationId);
    for (final m in all) {
      if (test(m)) return m;
    }
    return null;
  }

  Future<void> ecrire(String conversationId, String texte) =>
      api.sendMessage(conversationId: conversationId, clientMsgId: _uuid(), body: texte);

  static int _n = 0;
  static String _uuid() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(12, '0');
    final n = (_n++).toRadixString(16).padLeft(8, '0');
    return '${n.substring(0, 8)}-0000-4000-8000-${t.substring(t.length - 12)}';
  }
}

/// Le parcours complet : inscription, demande de connexion, message, photo, vocal,
/// effacement, groupe, verrouillage.
Future<void> parcoursComplet(
  WidgetTester tester, {
  required List<Override> overrides,
  required String url,
  required String cleApi,
}) async {
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await poser(tester);

  // ── Inscription ──────────────────────────────────────────────────────────────
  etape('inscription par téléphone');
  await toucher(tester, cle('onboarding.consent'));
  await toucher(tester, cle('onboarding.continue'));
  await toucher(tester, cle('welcome.phone'));
  await attendre(tester, cle('phone.input'));
  await tester.enterText(cle('phone.input'), '70000001');
  await toucher(tester, cle('phone.submit'));
  await attendre(tester, cle('otp.input'));
  await tester.enterText(cle('otp.input'), '123456');
  await attendre(tester, cle('profile.name'));
  await tester.enterText(cle('profile.name'), 'Awa');
  await tester.enterText(cle('profile.handle'), 'awa_parcours');
  await tester.pump(const Duration(seconds: 2)); // vérification de disponibilité
  await toucher(tester, cle('profile.submit'));
  await toucher(tester, cle('permissions.later'));
  await attendre(tester, find.text('Aucune discussion pour l’instant'));

  final bob = await Pair.connecter(
    url,
    cleApi,
    telephone: '+22670000002',
    identifiant: 'bob_parcours',
    nom: 'Bob',
  );

  // ── Demande de connexion ────────────────────────────────────────────────────────
  etape('demande de connexion reçue puis acceptée');
  final awa = await bob.api.findByHandle('awa_parcours');
  expect(awa, isNotNull, reason: 'Bob trouve Awa par son identifiant');
  await bob.api.sendConnectionRequest(awa!.id, note: 'Bonjour, c’est Bob');
  await attendre(tester, cle('requests.banner'), quoi: 'encart de demande de connexion');
  await toucher(tester, cle('requests.banner'));
  await toucher(tester, clePrefixe('request.', '.accept'));
  await attendre(tester, cle('chat.input'), quoi: 'discussion ouverte après acceptation');
  await attendre(tester, find.text('Bonjour, c’est Bob'));
  final conv = await serveur(tester, () async {
    final l = await bob.api.listConversations();
    return l.isEmpty ? null : l.first.id;
  }, quoi: 'discussion créée');

  // ── Messages ────────────────────────────────────────────────────────────────────
  etape('message envoyé et reçu');
  await poser(tester);
  await saisir(tester, cle('chat.input'), 'Bonjour Bob');
  await toucher(tester, cle('chat.send'));
  await serveur(
    tester,
    () => bob.message(conv, (m) => m.body == 'Bonjour Bob'),
    quoi: 'message d’Awa reçu par Bob',
  );
  await bob.ecrire(conv, 'Salut Awa');
  await attendre(tester, find.text('Salut Awa'), quoi: 'réponse de Bob (temps réel)');

  // ── Photo ───────────────────────────────────────────────────────────────────────
  etape('photo');
  await toucher(tester, cle('composer.photo'));
  await toucher(tester, cle('photo.gallery'));
  await attendre(tester, cle('photo.compose'));
  await toucher(tester, cle('photo.send'));
  await attendre(
    tester,
    clePrefixe('photo.open.'),
    quoi: 'bulle photo',
    max: const Duration(seconds: 60),
  );
  await serveur(
    tester,
    () => bob.message(conv, (m) => m.kind == 'photo'),
    quoi: 'photo reçue par Bob',
  );

  // ── Vocal ───────────────────────────────────────────────────────────────────────
  etape('vocal');
  await tester.tap(cle('chat.mic'));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.tap(cle('voice.stop'));
  await attendre(tester, cle('voice.preview'));
  await toucher(tester, cle('voice.send'));
  await attendre(
    tester,
    clePrefixe('voice.play.'),
    quoi: 'bulle vocale',
    max: const Duration(seconds: 60),
  );
  await serveur(
    tester,
    () => bob.message(conv, (m) => m.kind == 'voice'),
    quoi: 'vocal reçu par Bob',
  );

  // ── Effacement ──────────────────────────────────────────────────────────────────
  etape('effacement après lecture (30 s)');
  await bob.api.setReadErase(conv, 30);
  await bob.ecrire(conv, 'Message éphémère');
  await attendre(tester, find.text('Message éphémère'), quoi: 'message à effacer après lecture');
  await attendreAbsence(
    tester,
    find.text('Message éphémère'),
    max: const Duration(seconds: 90),
    quoi: 'message effacé 30 s après lecture',
  );
  await bob.api.setReadErase(conv, null);

  // ── Groupe ──────────────────────────────────────────────────────────────────────
  etape('groupe');
  await retourAccueil(tester);
  await toucher(tester, onglet('Groupes'));
  await toucher(tester, cle('groups.new'));
  await attendre(tester, cle('group.title'));
  await saisir(tester, cle('group.title'), 'Famille parcours');
  await toucher(tester, cle('picker.user.${bob.id}'));
  await toucher(tester, cle('group.create'));
  await attendre(tester, cle('chat.members'), quoi: 'discussion de groupe ouverte');
  final invitation = await serveur(tester, () async {
    final l = await bob.api.listInvitations();
    return l.isEmpty ? null : l.first;
  }, quoi: 'invitation reçue par Bob');
  await bob.api.respondToInvitation(invitation.id, accept: true);
  await bob.ecrire(invitation.conversationId, 'Merci pour l’invitation');
  await attendre(
    tester,
    find.text('Merci pour l’invitation'),
    quoi: 'message de Bob dans le groupe',
  );

  // ── Verrouillage ────────────────────────────────────────────────────────────────
  etape('verrouillage par code');
  await retourAccueil(tester);
  await toucher(tester, onglet('Paramètres'));
  await defilerJusqua(tester, cle('settings.security'));
  await toucher(tester, cle('settings.security'));
  await toucher(tester, cle('security.lock'));
  await toucher(tester, cle('lock.enabled'));
  await taperCode(tester, pinParcours);
  await attendre(tester, find.text('Confirmez le code'));
  await taperCode(tester, pinParcours);
  await attendre(tester, find.text('Verrouillage activé.'), max: const Duration(seconds: 60));
  await toucher(tester, cle('lock.delay'));
  await toucher(tester, cle('lock.delay.0'));
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  // Application en arrière-plan : aucune image n'est dessinée, on attend sans « pump ».
  await Future<void>.delayed(const Duration(seconds: 1));
  for (final s in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
  await attendre(tester, cle('lock.screen'), quoi: 'écran de verrouillage au retour');
  await taperCode(tester, pinParcours);
  await attendreAbsence(tester, cle('lock.screen'), max: const Duration(seconds: 60));
  etape('terminé');
  await bob.client.dispose();
}
