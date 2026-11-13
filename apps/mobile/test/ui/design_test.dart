import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

/// Lot 2.D — comportements portés par le nouveau design.
Future<TestDeps> _withBob(WidgetTester tester) async {
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
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  return deps;
}

void main() {
  testWidgets('recherche locale et filtres de la liste', (tester) async {
    final deps = await _withBob(tester);
    deps.messaging.receive('conv-bob', 'Salut\u202F!');
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('discussions.search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Aucun résultat'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('discussions.search')), 'BOB');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('discussions.search')), '');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Non lues'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
    await tester.tap(find.text('Épinglées'));
    await tester.pumpAndSettle();
    expect(find.text('Aucun résultat'), findsOneWidget);
    await tester.tap(find.text('Toutes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
  });

  testWidgets(
    'rappel «\u202Fs’efface bientôt\u202F» seulement pour un message proche de l’expiration',
    (tester) async {
      final deps = await _withBob(tester);
      deps.messaging.receive('conv-bob', 'Loin de l’expiration');
      deps.realtime.emit('conv-bob');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expiring.conv-bob')), findsNothing);

      deps.messaging.receive(
        'conv-bob',
        'Bientôt effacé',
        expiresAt: DateTime.now().add(const Duration(hours: 2, minutes: 30)),
      );
      deps.realtime.emit('conv-bob');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expiring.conv-bob')), findsOneWidget);
      expect(find.text('2 h'), findsOneWidget);
    },
  );

  testWidgets('conversation\u202F: séparateur «\u202FAujourd’hui\u202F» et carte 72 heures', (
    tester,
  ) async {
    final deps = await _withBob(tester);
    deps.messaging.receive('conv-bob', 'Bonjour');
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(find.byKey(const Key('chat.expiry_notice')), findsOneWidget);
    expect(find.textContaining('s’effacent 72 h'), findsOneWidget);
  });
}
