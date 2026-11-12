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
  testWidgets('régler la durée de la discussion : annonce et nouvelle durée', (tester) async {
    final deps = await _openChat(tester);
    expect(find.textContaining('s’effacent 72 h'), findsOneWidget);

    await tester.tap(find.byKey(const Key('chat.ttl')));
    await tester.pumpAndSettle();
    expect(find.text('Durée des messages'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ttl.3600')));
    await tester.pumpAndSettle();

    expect(deps.messaging.conversationTtl, 3600);
    expect(find.text('Vous avez réglé la durée des messages sur 1 h.'), findsOneWidget);
    expect(find.textContaining('s’effacent 1 h'), findsOneWidget);

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

  testWidgets('changement fait par le correspondant : annonce à son nom', (tester) async {
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
    expect(find.text('Bob a réglé la durée des messages sur 8 h.'), findsOneWidget);
  });
}
