import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/settings_nav.dart';

/// Lot 8.5c — guide « Découvrir Privio ».
TestDeps _deps({bool seen = false}) =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true)..discover = seen,
      )
      ..api.account = const Account(
        userId: 'u1',
        phoneE164: '+22670000001',
        phoneDiscoverable: false,
        profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
      );

Future<void> _start(WidgetTester tester, TestDeps deps) async {
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('montré une fois à l’arrivée, 6 écrans, « C’est parti » referme', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    expect(find.byKey(const Key('discover.screen')), findsOneWidget);
    expect(deps.flags.discover, isTrue, reason: 'vu : ne revient plus');
    expect(find.text('Bienvenue sur Privio'), findsWidgets);
    expect(find.byKey(const Key('discover.emoji')), findsOneWidget, reason: 'émoji animé');
    final titles = [
      'Démarrer une discussion',
      'Vos messages s’effacent',
      'Les groupes',
      'Appels audio et vidéo',
      'Votre protection',
    ];
    for (final t in titles) {
      await tester.tap(find.byKey(const Key('discover.next')));
      await tester.pumpAndSettle();
      expect(find.text(t), findsOneWidget);
    }
    expect(find.text('C’est parti'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discover.next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discover.screen')), findsNothing);
    expect(find.byType(PrivioNavBar), findsOneWidget);
  });

  testWidgets('« Passer » referme ; déjà vu : rien à l’ouverture', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(find.byKey(const Key('discover.skip')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discover.screen')), findsNothing);

    final again = _deps(seen: true);
    await _start(tester, again);
    expect(find.byKey(const Key('discover.screen')), findsNothing);
  });

  testWidgets('toujours accessible : Paramètres › Aide › Découvrir Privio', (tester) async {
    final deps = _deps(seen: true);
    await _start(tester, deps);
    await tester.tap(
      find.descendant(of: find.byType(PrivioNavBar), matching: find.text('Paramètres')),
    );
    await tester.pumpAndSettle();
    await openSettingsEntry(tester, 'settings.help');
    await tester.tap(find.byKey(const Key('help.discover')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('discover.screen')), findsOneWidget);
    // Glisser vers la page suivante fonctionne aussi.
    await tester.drag(find.byKey(const Key('discover.pages')), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Démarrer une discussion'), findsOneWidget);
  });
}
