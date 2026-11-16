import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/ui/core/motion/motion.dart';
import 'package:privio/ui/features/home/home_shell.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

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

/// Lot 8.5a — menus en carte flottante, « Voir plus », barre allégée, animations,
/// Paramètres réordonnés.
void main() {
  testWidgets('barre d’une discussion : plus de loupe, « Rechercher » dans ⋮', (tester) async {
    await _openBob(tester, bodies: ['Salut']);
    expect(find.byKey(const Key('chat.search')), findsNothing);
    expect(find.byKey(const Key('chat.call')), findsOneWidget);
    expect(find.byKey(const Key('chat.video')), findsOneWidget);
    await tester.tap(find.byKey(const Key('chat.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.menu.search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.search_input')), findsOneWidget);
    // Seul le bouton pour fermer la recherche apparaît.
    await tester.tap(find.byKey(const Key('chat.search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.search_input')), findsNothing);
    expect(find.byKey(const Key('chat.search')), findsNothing);
  });

  testWidgets('menu long : 5 actions, puis « Voir plus »', (tester) async {
    await _openBob(tester, bodies: ['Salut']);
    await tester.tap(find.byKey(const Key('chat.menu')));
    await tester.pump(const Duration(milliseconds: 60));
    // Ouverture animée (carte qui grandit depuis le bouton).
    expect(find.byType(ScaleTransition), findsWidgets);
    await tester.pumpAndSettle();
    for (final k in ['info', 'search', 'media', 'favorites', 'ttl']) {
      expect(find.byKey(Key('chat.menu.$k')), findsOneWidget, reason: k);
    }
    expect(find.byKey(const Key('chat.menu.block')), findsNothing);
    expect(find.text('Voir plus'), findsOneWidget);
    await tester.tap(find.byKey(const Key('menu.more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.menu.block')), findsOneWidget);
    expect(find.byKey(const Key('menu.more')), findsNothing);
    // Toucher à côté ferme le menu.
    await tester.tapAt(const Offset(5, 590));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.menu.info')), findsNothing);
  });

  testWidgets('menu court (≤ 6 actions) : tout est visible', (tester) async {
    await _openBob(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discussions.menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu.more')), findsNothing);
    expect(find.byKey(const Key('discussions.menu.read_all')), findsOneWidget);
  });

  testWidgets('listes en cascade et Paramètres : Supprimer avant Se déconnecter', (tester) async {
    await _openBob(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: find.byKey(const Key('conversation.conv-bob')),
        matching: find.byType(AppearIn),
      ),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(of: find.byType(PrivioNavBar), matching: find.text('Paramètres')),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.signout')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    final del = tester.getTopLeft(find.byKey(const Key('settings.delete'))).dy;
    final out = tester.getTopLeft(find.byKey(const Key('settings.signout'))).dy;
    expect(del, lessThan(out));
  });
}
