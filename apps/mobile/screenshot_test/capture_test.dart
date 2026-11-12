// Captures d'écran automatiques (avant/après design). Hors suite de tests normale :
//   flutter test screenshot_test/capture_test.dart --dart-define=SHOTS_DIR=/chemin
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';

import '../test/helpers/fakes.dart';

const _outDir = String.fromEnvironment('SHOTS_DIR', defaultValue: '/tmp/privio_shots');
final _boundary = GlobalKey();

/// Données de démonstration pour la liste (plusieurs correspondants).
class ShowcaseMessagingApi extends FakeMessagingApi {
  @override
  Future<List<ConversationSummary>> listConversations() async {
    final now = DateTime.now();
    ConversationSummary c(
      String id,
      String name,
      String handle,
      String? body, {
      int unread = 0,
      bool pinned = false,
      Duration ago = Duration.zero,
      String? sender,
      bool read = false,
    }) => ConversationSummary(
      id: id,
      peerId: 'p-$id',
      peerHandle: handle,
      peerDisplayName: name,
      peerDeleted: false,
      blocked: false,
      unreadCount: unread,
      pinned: pinned,
      archived: false,
      sortAt: now.subtract(ago),
      lastMessageId: 'm-$id',
      lastSenderId: sender ?? 'p-$id',
      lastBody: body,
      lastSentAt: now.subtract(ago),
      peerReadUpTo: read ? now : null,
    );
    final real = await super.listConversations();
    return [
      ...real,
      c(
        'c1',
        'Amina Diallo',
        'amina_d',
        'On se voit à 15 h ?',
        unread: 2,
        ago: const Duration(minutes: 3),
      ),
      c('c2', 'Marc Koné', 'marc_k', 'Le dossier est prêt.', ago: const Duration(minutes: 40)),
      c(
        'c3',
        'Famille Ouédraogo',
        'fam_oued',
        'On se voit dimanche ?',
        pinned: true,
        ago: const Duration(hours: 20),
      ),
      c('c4', 'Sophie Traoré', 'sophie_t', 'Merci pour hier !', ago: const Duration(hours: 68)),
      c(
        'c5',
        'Awa Sawadogo',
        'awa_s',
        'Merci beaucoup !',
        sender: FakeMessagingApi.me,
        read: true,
        ago: const Duration(days: 2),
      ),
    ];
  }
}

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    inter.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await inter.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
  }
}

Future<void> _shot(WidgetTester tester, String name, {bool settle = true}) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  // Enregistrement en cours : animation continue, on capture l'image telle quelle.
  if (settle) await tester.pumpAndSettle();
  if (!settle) await tester.pump();
  final boundary = _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 2)))!;
  final bytes = (await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png)))!;
  Directory(_outDir).createSync(recursive: true);
  File('$_outDir/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
}

TestDeps _ready() {
  final deps =
      TestDeps(
          messaging: ShowcaseMessagingApi(),
          auth: FakeAuthService(signedIn: true),
          flags: FakeLocalFlags(onboarding: true, permissions: true),
        )
        ..api.account = const Account(
          userId: 'u1',
          phoneE164: '+22670000001',
          phoneDiscoverable: false,
          profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
        );
  return deps;
}

Future<void> _pump(WidgetTester tester, TestDeps deps) async {
  // Rendu « tactile » comme sur un téléphone (pas de cadre de focus clavier).
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: ProviderScope(
        overrides: deps.overrides,
        retry: (_, _) => null,
        child: const PrivioApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadFonts);

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final suffix = brightness == Brightness.light ? 'clair' : 'sombre';

    testWidgets('captures $suffix', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(tester.view.reset);

      // 02 — accueil (premier lancement)
      await _pump(tester, TestDeps());
      await _shot(tester, '02_accueil_$suffix');

      // 08 — discussions, 10 — conversation, 22 — paramètres
      final deps = _ready();
      await _pump(tester, deps);
      await tester.tap(find.byKey(const Key('discussions.new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('search.input')), 'bob_ouaga');
      await tester.tap(find.byKey(const Key('search.submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search.write')));
      await tester.pumpAndSettle();
      final m = deps.messaging;
      m.receive('conv-bob', 'Bonjour Toussaint !');
      await tester.enterText(find.byKey(const Key('chat.input')), 'Bonjour Bob ! Ça va ?');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat.send')));
      await tester.pumpAndSettle();
      final q = m.receive('conv-bob', 'Très bien. As-tu fini le dossier du projet ?');
      await tester.enterText(find.byKey(const Key('chat.input')), 'Oui, terminé hier soir.');
      await tester.pumpAndSettle();
      m.peerReadUpTo = DateTime.now().add(const Duration(seconds: 1));
      deps.realtime.emit('conv-bob');
      await tester.pumpAndSettle();
      await tester.longPress(find.text(q.body!));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action.reply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.send')));
      await tester.pumpAndSettle();
      await m.setReaction(q.id, '👍');
      m.receive('conv-bob', 'Parfait, on valide à 15 h.');
      deps.realtime.emit('conv-bob');
      await tester.pumpAndSettle();
      await _shot(tester, '10_conversation_$suffix');

      // 14 — vocaux (lot 3.1) : enregistrement, préécoute, bulles avec lecture
      m.receiveVoice('conv-bob', durationMs: 12000);
      deps.realtime.emit('conv-bob');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.mic')));
      await tester.pump();
      for (var i = 0; i < 50; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await _shot(tester, '14_vocal_enregistrement_$suffix', settle: false);
      await tester.tap(find.byKey(const Key('voice.stop')));
      await tester.pumpAndSettle();
      await _shot(tester, '14_vocal_preecoute_$suffix');
      await tester.tap(find.byKey(const Key('voice.send')));
      await tester.pumpAndSettle();
      final heard = m.messages['conv-bob']!.firstWhere((x) => x.isVoice && x.senderId != 'u1');
      await tester.tap(find.byKey(Key('voice.play.${heard.id}')));
      await tester.pumpAndSettle();
      deps.audio.emitPosition(const Duration(seconds: 5));
      await tester.pump();
      await _shot(tester, '14_vocal_conversation_$suffix');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await _shot(tester, '08_discussions_$suffix');

      await tester.tap(find.text('Paramètres'));
      await tester.pumpAndSettle();
      await _shot(tester, '22_parametres_$suffix');
    });
  }
}
