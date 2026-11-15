import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';
import '../helpers/settings_nav.dart';

/// Lot 4.1 — notifications (jeton, interrupteur, déconnexion, ouverture d'une discussion).
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

Future<void> _launch(WidgetTester tester, TestDeps deps) async {
  await deps.messaging.startDirectConversation('u2');
  deps.messaging.receive('conv-bob', 'Salut');
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSettingsSwitch(WidgetTester tester) async {
  await tester.tap(find.text('Paramètres'));
  await tester.pumpAndSettle();
  await openSettingsEntry(tester, 'settings.notifications');
  // En haut de l'écran : la barre de navigation ne doit pas recouvrir l'interrupteur.
  await tester.ensureVisible(find.byKey(const Key('settings.push')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('connecté\u202F: le jeton de cet appareil est enregistré, puis renouvelé', (
    tester,
  ) async {
    final deps = _deps();
    await _launch(tester, deps);
    expect(deps.api.pushTokens, ['jeton-fcm-de-test-000000000001']);

    deps.push.refreshTo('jeton-fcm-renouvele-0000000002');
    await tester.pumpAndSettle();
    expect(deps.api.pushTokens.last, 'jeton-fcm-renouvele-0000000002');
  });

  testWidgets('interrupteur\u202F: couper retire le jeton\u202F; réactiver le renvoie', (
    tester,
  ) async {
    final deps = _deps();
    await _launch(tester, deps);
    await _openSettingsSwitch(tester);
    await tester.tap(find.byKey(const Key('settings.push')));
    await tester.pumpAndSettle();
    expect(deps.api.pushUnregistered, 1);
    expect(deps.push.deleted, 1);
    expect(deps.flags.push, isFalse);

    await tester.tap(find.byKey(const Key('settings.push')));
    await tester.pumpAndSettle();
    expect(deps.api.pushTokens, hasLength(2));
  });

  testWidgets('notifications coupées\u202F: aucun jeton envoyé au démarrage', (tester) async {
    final deps = _deps()..flags.push = false;
    await _launch(tester, deps);
    expect(deps.api.pushTokens, isEmpty);
  });

  testWidgets('déconnexion\u202F: jeton retiré du serveur et de Firebase', (tester) async {
    final deps = _deps();
    await _launch(tester, deps);
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.signout')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byKey(const Key('settings.signout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.signout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.signout.confirm')));
    await tester.pumpAndSettle();
    expect(deps.api.pushUnregistered, 1);
    expect(deps.push.deleted, 1);
  });

  testWidgets('toucher une notification ouvre la bonne discussion', (tester) async {
    final deps = _deps();
    await _launch(tester, deps);
    deps.push.open('conv-bob');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.input')), findsOneWidget);
    expect(find.text('Salut'), findsOneWidget);
  });

  testWidgets('application lancée depuis une notification\u202F: discussion ouverte', (
    tester,
  ) async {
    final deps = _deps()..push.initial = 'conv-bob';
    await _launch(tester, deps);
    expect(find.byKey(const Key('chat.input')), findsOneWidget);
  });

  testWidgets('Firebase indisponible\u202F: l’application fonctionne normalement', (tester) async {
    final deps = _deps()..push.available = false;
    await _launch(tester, deps);
    expect(deps.api.pushTokens, isEmpty);
    expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
  });
}
