import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 4.5 : barre de navigation (piste C) et double appui sur Retour pour quitter.
void main() {
  late List<MethodCall> platformCalls;

  setUp(() => platformCalls = []);

  Future<TestDeps> pumpApp(WidgetTester tester, {void Function(TestDeps)? seed}) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) {
      platformCalls.add(c);
      return Future.value();
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
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
    seed?.call(deps);
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    return deps;
  }

  bool exited() => platformCalls.any((c) => c.method == 'SystemNavigator.pop');

  Finder tab(String label) =>
      find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

  testWidgets('un appui sur Retour prévient, le second quitte', (tester) async {
    await pumpApp(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text(HomeShell.exitHint), findsOneWidget);
    expect(exited(), isFalse);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exited(), isTrue);
  });

  testWidgets('au-delà de 2 s, le second appui prévient à nouveau', (tester) async {
    await pumpApp(tester);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(exited(), isFalse);
    expect(find.text(HomeShell.exitHint), findsOneWidget);
  });

  testWidgets('depuis Paramètres, Retour ramène à Discussions', (tester) async {
    await pumpApp(tester);
    await tester.tap(tab('Paramètres'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discussions.new')), findsOneWidget);
    expect(find.text(HomeShell.exitHint), findsNothing);
    expect(exited(), isFalse);
  });

  testWidgets('un écran ouvert depuis Paramètres se ferme normalement', (tester) async {
    await pumpApp(tester);
    await tester.tap(tab('Paramètres'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.privacy')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings.privacy')), findsOneWidget);
    expect(exited(), isFalse);
  });

  testWidgets('pastilles : discussions non lues et invitations de groupe', (tester) async {
    final deps = await pumpApp(
      tester,
      seed: (d) => d.messaging.invitations.add(
        const GroupInvitation(id: 'i1', conversationId: 'g9', title: 'Famille', memberCount: 4),
      ),
    );
    await deps.messaging.startDirectConversation('u2');
    deps.messaging.receive('conv-bob', 'Salut');
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    final nav = find.byType(PrivioNavBar);
    expect(find.descendant(of: nav, matching: find.text('1')), findsNWidgets(2));
    expect(find.bySemanticsLabel('Groupes, 1 en attente'), findsOneWidget);
  });
}
