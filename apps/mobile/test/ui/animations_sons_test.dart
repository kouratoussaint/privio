import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/state/feedback_providers.dart';
import 'package:privio/ui/core/motion/motion.dart';

import '../helpers/fakes.dart';
import '../helpers/settings_nav.dart';

/// Lot 7.2b2 — animations, sons, illustrations ; photo de l'auteur à côté des messages.
TestDeps _deps({bool sounds = true}) =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true)..sounds = sounds,
      )
      ..api.account = const Account(
        userId: 'u1',
        phoneE164: '+22670000001',
        phoneDiscoverable: false,
        profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
      );

Future<void> _openBob(WidgetTester tester, TestDeps deps) async {
  await deps.messaging.startDirectConversation('u2');
  deps.messaging.receive('conv-bob', 'Bonjour');
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('chat.input')), text);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('chat.send')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sons : envoi, réception, réaction', (tester) async {
    final deps = _deps();
    await _openBob(tester, deps);
    deps.sounds.played.clear();

    await _send(tester, 'Salut');
    expect(deps.sounds.played, [PrivioSound.sent]);

    final m = deps.messaging.receive('conv-bob', 'Ça va ?');
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(deps.sounds.played.last, PrivioSound.received);

    expect(m.body, 'Ça va ?');
    await tester.tap(find.text('Ça va ?'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Ça va ?'));
    await tester.pumpAndSettle();
    expect(deps.sounds.played.last, PrivioSound.reaction);
  });

  testWidgets('« Sons et vibrations » coupé : aucun son', (tester) async {
    final deps = _deps(sounds: false);
    await _openBob(tester, deps);
    await _send(tester, 'Salut');
    deps.messaging.receive('conv-bob', 'Ça va ?');
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(deps.sounds.played, isEmpty);
  });

  testWidgets('réglage dans Paramètres, activé par défaut', (tester) async {
    final deps = _deps();
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav.Paramètres')));
    await tester.pumpAndSettle();
    await openSettingsEntry(tester, 'settings.notifications');
    final tile = find.byKey(const Key('settings.sounds'));
    await tester.ensureVisible(tile);
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(deps.flags.sounds, isFalse);
  });

  // Lot 8.1b : la photo passe sur le PREMIER message d'une suite, en haut à gauche.
  testWidgets('photo du correspondant à côté du premier message d’une suite', (tester) async {
    final deps = _deps();
    await _openBob(tester, deps);
    await _send(tester, 'Moi');
    final a = deps.messaging.receive('conv-bob', 'Un');
    final b = deps.messaging.receive('conv-bob', 'Deux');
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(find.byKey(Key('message.avatar.${a.id}')), findsOneWidget, reason: 'premier');
    expect(find.byKey(Key('message.avatar.${b.id}')), findsNothing, reason: 'pas les suivants');
    final avatar = tester.getRect(find.byKey(Key('message.avatar.${a.id}')));
    final bubble = tester.getRect(find.byKey(Key('message.${a.id}')));
    expect((avatar.top - bubble.top).abs(), lessThan(8), reason: 'en haut de la bulle');

    await _send(tester, 'Encore moi');
    // Mes messages n'ont jamais de photo.
    expect(find.byKey(Key('message.avatar.${a.id}')), findsOneWidget);
  });

  testWidgets('discussion vidée chez moi : son de balayage, les bulles se dissolvent', (
    tester,
  ) async {
    final deps = _deps();
    await _openBob(tester, deps);
    for (final t in ['Un', 'Deux', 'Trois']) {
      deps.messaging.receive('conv-bob', t);
    }
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    deps.sounds.played.clear();

    await tester.tap(find.byKey(const Key('chat.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clear.me')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clear.confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(deps.sounds.played, contains(PrivioSound.cleared));
    expect(find.text('Trois'), findsOneWidget, reason: 'encore visible pendant la dissolution');
    await tester.pumpAndSettle();
    expect(find.text('Trois'), findsNothing);
    expect(find.text('Un'), findsNothing);
  });

  testWidgets('animations réduites : rien ne bouge, l’état final s’affiche', (tester) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: AppearIn(child: Text('Bonjour')),
        ),
      ),
    );
    final fade = tester.widget<FadeTransition>(find.byType(FadeTransition));
    expect(fade.opacity.value, 1);
  });
}
