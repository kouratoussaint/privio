import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/theme/privio_tokens.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/features/conversations/chat_motion.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/menu.dart';

/// Lot 8.1b — bulles à queue, coches « lu », menu ⋮, liste des réactions.
TestDeps _deps() =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true),
      )
      ..api.account = const Account(
        userId: 'u1',
        phoneE164: '+22670000001',
        phoneDiscoverable: false,
        profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
      );

Future<TestDeps> _openBob(WidgetTester tester, {List<String> bodies = const []}) async {
  final deps = _deps();
  await deps.messaging.startDirectConversation('u2');
  for (final b in bodies) {
    deps.messaging.receive('conv-bob', b);
  }
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
  return deps;
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('chat.input')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('chat.send')));
  await tester.pumpAndSettle();
}

Finder _tailOf(String id) => find.descendant(
  of: find.byKey(Key('message.$id')),
  matching: find.byKey(const Key('bubble.tail')),
);

Future<void> _menu(WidgetTester tester, String item) async {
  await tester.tap(find.byKey(const Key('chat.menu')));
  await tester.pumpAndSettle();
  await tapMenuItem(tester, Key(item));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('queue seulement sur le premier message d’une suite', (tester) async {
    final deps = await _openBob(tester, bodies: ['Un', 'Deux']);
    final ids = [for (final m in deps.messaging.messages['conv-bob']!) m.id];
    expect(_tailOf(ids[0]), findsOneWidget);
    expect(_tailOf(ids[1]), findsNothing);
    await _send(tester, 'Moi');
    await _send(tester, 'Encore moi');
    final mine = [for (final m in deps.messaging.messages['conv-bob']!.skip(2)) m.id];
    expect(_tailOf(mine[0]), findsOneWidget, reason: 'nouvelle suite, de moi');
    expect(_tailOf(mine[1]), findsNothing);
  });

  testWidgets('coches « lu » en jaune doux, « reçu » inchangé', (tester) async {
    final deps = await _openBob(tester);
    await _send(tester, 'Tu as vu ?');
    deps.messaging.peerDeliveredUpTo = DateTime.now().add(const Duration(seconds: 1));
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    final delivered = tester.widget<AnimatedTicks>(find.byKey(const Key('delivery.delivered')));
    expect(delivered.color, isNot(PrivioColors.readTick));
    deps.messaging.peerReadUpTo = DateTime.now().add(const Duration(seconds: 1));
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    final read = tester.widget<AnimatedTicks>(find.byKey(const Key('delivery.read')));
    expect(read.color, PrivioColors.readTick);
  });

  group('menu ⋮', () {
    testWidgets('discussion à deux : toutes les entrées', (tester) async {
      await _openBob(tester, bodies: ['Salut']);
      await tester.tap(find.byKey(const Key('chat.menu')));
      await tester.pumpAndSettle();
      // Lot 8.5a : 5 actions, puis « Voir plus ».
      expect(find.byKey(const Key('chat.menu.wallpaper')), findsNothing);
      await tester.tap(find.byKey(const Key('menu.more')));
      await tester.pumpAndSettle();
      for (final k in [
        'chat.menu.info',
        'chat.menu.search',
        'chat.menu.media',
        'chat.menu.favorites',
        'chat.menu.ttl',
        'chat.menu.mute',
        'chat.menu.wallpaper',
        'chat.clear',
        'chat.menu.block',
        'chat.menu.report',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('chat.menu.leave')), findsNothing);
    });

    testWidgets('voir la fiche, rechercher, médias', (tester) async {
      await _openBob(tester, bodies: ['Salut']);
      await _menu(tester, 'chat.menu.info');
      expect(find.byKey(const Key('contact.ttl')), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await _menu(tester, 'chat.menu.search');
      expect(find.byKey(const Key('chat.search_input')), findsOneWidget);
    });

    testWidgets('sourdine depuis le menu', (tester) async {
      final deps = await _openBob(tester, bodies: ['Salut']);
      await _menu(tester, 'chat.menu.mute');
      await tester.tap(find.byKey(const Key('mute.8')));
      await tester.pumpAndSettle();
      expect(deps.messaging.muted['conv-bob']?.isAfter(DateTime.now()), isTrue);
    });

    testWidgets('bloquer depuis le menu', (tester) async {
      final deps = await _openBob(tester, bodies: ['Salut']);
      await _menu(tester, 'chat.menu.block');
      await tester.tap(find.byKey(const Key('chat.block.confirm')));
      await tester.pumpAndSettle();
      expect(deps.messaging.blocked, contains('u2'));
    });

    testWidgets('groupe : infos, notifications, quitter ; pas de « Bloquer »', (tester) async {
      final deps = _deps();
      deps.messaging
        ..seedGroup('g1', 'Famille', members: {'u2': 'member'})
        ..receiveInGroup('g1', 'u2', 'Coucou');
      await tester.pumpWidget(
        ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(PrivioNavBar), matching: find.text('Groupes')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation.g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('menu.more')));
      await tester.pumpAndSettle();
      for (final k in [
        'chat.menu.info',
        'chat.menu.notifications',
        'chat.menu.invite',
        'chat.menu.leave',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('chat.menu.block')), findsNothing);
      await tapMenuItem(tester, const Key('chat.menu.notifications'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat.menu.mute')), findsOneWidget);
    });
  });
}
