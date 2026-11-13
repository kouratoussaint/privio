import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';

import '../helpers/fakes.dart';

/// Lot 2.E — durée d'expiration configurable (discussion et message).
Future<TestDeps> _openChat(WidgetTester tester) async {
  final deps =
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
  await deps.messaging.startDirectConversation('u2');
  deps.messaging.receive('conv-bob', 'Salut');
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
  return deps;
}

void main() {
  testWidgets('régler la durée de la discussion\u202F: annonce et nouvelle durée', (tester) async {
    final deps = await _openChat(tester);
    expect(find.text('Messages effacés après 72\u00A0h'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('chat.ttl')), matching: find.text('72\u00A0h')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('chat.ttl')));
    await tester.pumpAndSettle();
    expect(find.text('Durée des messages'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ttl.3600')));
    await tester.pumpAndSettle();

    expect(deps.messaging.conversationTtl, 3600);
    expect(find.text('Vous avez réglé la durée des messages sur 1\u00A0h.'), findsOneWidget);
    expect(find.text('Messages effacés après 1\u00A0h'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chat.input')), 'Message court');
    await tester.pump(); // le bouton « Envoyer » remplace le micro
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.sentTtls.last, isNull, reason: 'la durée de la discussion s’applique');
    expect(find.text('59 min'), findsOneWidget);
  });

  testWidgets('durée d’un seul message, plafonnée par la discussion', (tester) async {
    final deps = await _openChat(tester);
    await tester.tap(find.byKey(const Key('composer.ttl')));
    await tester.pumpAndSettle();
    expect(find.text('Durée de ce message'), findsWidgets);
    await tester.tap(find.byKey(const Key('ttl.300')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer.ttl_chip')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('chat.input')), 'Très sensible');
    await tester.pump(); // le bouton « Envoyer » remplace le micro
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.sentTtls.last, 300);
    expect(
      find.byKey(const Key('composer.ttl_chip')),
      findsNothing,
      reason: 'la durée choisie ne vaut que pour un message',
    );
    expect(find.text('4 min'), findsOneWidget);

    // Discussion réglée sur 1 h : impossible de choisir plus long pour un message.
    await tester.tap(find.byKey(const Key('chat.ttl')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ttl.3600')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('composer.ttl')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ttl.300')), findsOneWidget);
    expect(find.byKey(const Key('ttl.86400')), findsNothing);
    expect(find.byKey(const Key('ttl.259200')), findsNothing);
  });

  testWidgets('changement fait par le correspondant\u202F: annonce à son nom', (tester) async {
    final deps = await _openChat(tester);
    final now = DateTime.now();
    deps.messaging.conversationTtl = 8 * 3600;
    deps.messaging.messages['conv-bob']!.add(
      ChatMessage(
        id: 'sys-bob',
        kind: 'system',
        senderId: 'u2',
        body: 'ttl:28800',
        sentAt: now,
        expiresAt: now.add(const Duration(hours: 8)),
        updatedAt: now,
      ),
    );
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(find.text('Bob a réglé la durée des messages sur 8\u00A0h.'), findsOneWidget);
  });

  testWidgets('8 puces + « Personnalisé » (lot 4.6)', (tester) async {
    await _openChat(tester);
    await tester.tap(find.byKey(const Key('chat.ttl')));
    await tester.pumpAndSettle();
    for (final s in [300, 900, 1800, 3600, 21600, 43200, 86400, 172800]) {
      expect(find.byKey(Key('ttl.$s')), findsOneWidget, reason: '$s s');
    }
    expect(find.byKey(const Key('ttl.259200')), findsNothing, reason: '72 h : pas de puce');
    expect(
      find.text('Personnalisé · 72\u00A0h'),
      findsOneWidget,
      reason: 'valeur actuelle hors puces',
    );
  });

  testWidgets('durée personnalisée 4 h 30 pour la discussion', (tester) async {
    final deps = await _openChat(tester);
    await tester.tap(find.byKey(const Key('chat.ttl')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ttl.custom')));
    await tester.pumpAndSettle();
    // Roulettes : 72 h 0 min au départ → 4 h 30.
    await _wheelTo(tester, 'ttl.custom.hours', from: 72, to: 4);
    await _wheelTo(tester, 'ttl.custom.minutes', from: 0, to: 6);
    expect(find.text('Valider 4\u00A0h\u00A030'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ttl.custom.ok')));
    await tester.pumpAndSettle();
    expect(deps.messaging.conversationTtl, 4 * 3600 + 30 * 60);
    expect(find.text('Messages effacés après 4\u00A0h\u00A030'), findsOneWidget);
  });

  testWidgets('personnalisé : moins de 5 min ou plus que la discussion refusé', (tester) async {
    await _openChat(tester);
    await tester.tap(find.byKey(const Key('composer.ttl')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ttl.custom')));
    await tester.pumpAndSettle();
    await _wheelTo(tester, 'ttl.custom.hours', from: 72, to: 0);
    expect(find.byKey(const Key('ttl.custom.error')), findsOneWidget);
    expect(find.text('Au moins 5\u00A0min.'), findsOneWidget);
    final ok = tester.widget<FilledButton>(find.byKey(const Key('ttl.custom.ok')));
    expect(ok.onPressed, isNull);
    await _wheelTo(tester, 'ttl.custom.minutes', from: 0, to: 2);
    expect(find.byKey(const Key('ttl.custom.error')), findsNothing);
    await tester.tap(find.byKey(const Key('ttl.custom.ok')));
    await tester.pumpAndSettle();
    expect(find.text('Ce message\u202F: 10\u00A0min'), findsOneWidget);
  });

  testWidgets('sélecteur lisible sur 320 dp avec une grande police', (tester) async {
    addTearDown(tester.view.reset);
    addTearDown(() => tester.platformDispatcher.clearTextScaleFactorTestValue());
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    await _openChat(tester);
    await tester.tap(find.byKey(const Key('chat.ttl')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('ttl.custom')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ttl.custom.ok')), findsOneWidget);
  });
}

/// Place une roulette sur le cran [to] (comme un geste, mais déterministe).
Future<void> _wheelTo(WidgetTester tester, String key, {required int from, required int to}) async {
  final wheel = tester.widget<ListWheelScrollView>(
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(ListWheelScrollView)),
  );
  (wheel.controller! as FixedExtentScrollController).jumpToItem(to);
  await tester.pumpAndSettle();
}
