import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/console_team.dart';
import 'package:privio/ui/features/console/console_screen.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 5.10 — console : rubriques en trois parties (menu et accueil dans le même ordre),
/// couleur de la rubrique appliquée à ses commandes.
const _pin = '258014';

TestDeps _deps({ConsoleRole role = ConsoleRole.owner}) =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true),
      )
      ..admin.admin = true
      ..admin.role = role
      ..admin.staffTwoStep = true
      ..api.account = const Account(
        userId: 'u1',
        phoneE164: '+22670000001',
        phoneDiscoverable: false,
        profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
      );

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin.$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _openConsole(WidgetTester tester, TestDeps deps) async {
  final salt = List<int>.generate(16, (i) => i);
  deps.lockStore.config = AppLockConfig(
    enabled: true,
    delaySeconds: 3600,
    salt: base64Encode(salt),
    hash: await const FastPinHasher().hash(_pin, salt, 1),
  );
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await _type(tester, _pin);
  await tester.tap(
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text('Paramètres')),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('settings.console')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(find.byKey(const Key('settings.console')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings.console')));
  await tester.pumpAndSettle();
  await _type(tester, _pin);
}

void main() {
  testWidgets('menu : trois parties, rubriques rangées dans le même ordre que l’accueil', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await _openConsole(tester, _deps());
    await tester.tap(find.byKey(const Key('console.menu')));
    await tester.pumpAndSettle();
    double y(String k) => tester.getTopLeft(find.byKey(Key(k))).dy;
    final order = [
      'console.tab.dashboard',
      'console.group.moderation',
      for (final s in ConsoleSection.values.where((s) => s.group == ConsolePart.moderation))
        'console.tab.${s.id}',
      'console.group.service',
      for (final s in ConsoleSection.values.where((s) => s.group == ConsolePart.service))
        'console.tab.${s.id}',
      'console.group.setup',
      for (final s in ConsoleSection.values.where((s) => s.group == ConsolePart.setup))
        'console.tab.${s.id}',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        y(order[i]),
        greaterThan(y(order[i - 1])),
        reason: '${order[i]} après ${order[i - 1]}',
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const Key('console.drawer')),
        matching: find.text('MODÉRATION'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('console.drawer')),
        matching: find.text('SUIVI DU SERVICE'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('console.drawer')),
        matching: find.text('CONFIGURATION'),
      ),
      findsOneWidget,
    );

    // Accueil : une tuile par rubrique, sous le titre de sa partie.
    await tester.tapAt(const Offset(390, 300));
    await tester.pumpAndSettle();
    for (final s in ConsoleSection.values.skip(1)) {
      expect(find.byKey(Key('console.tile.${s.id}')), findsOneWidget, reason: s.id);
    }
    expect(
      y('console.tile.pilot'),
      greaterThan(y('console.dashboard.group.setup')),
      reason: 'Pilotage dans « Configuration »',
    );
    expect(ConsoleSection.pilot.icon, isNot(ConsoleSection.policies.icon), reason: 'icône propre');
  });

  testWidgets('assistance : seulement la partie « Modération »', (tester) async {
    await _openConsole(tester, _deps(role: ConsoleRole.support));
    await tester.tap(find.byKey(const Key('console.menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('console.group.moderation')), findsOneWidget);
    expect(find.byKey(const Key('console.group.service')), findsNothing);
    expect(find.byKey(const Key('console.group.setup')), findsNothing);
  });

  testWidgets('la rubrique applique sa couleur à ses filtres', (tester) async {
    await _openConsole(tester, _deps());
    await tester.tap(find.byKey(const Key('console.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('console.tab.reports')));
    await tester.pumpAndSettle();
    final chip = tester.widget<ChoiceChip>(find.byKey(const Key('reports.queue.open')));
    expect(chip.selected, isTrue);
    expect(chip.selectedColor, ConsoleSection.reports.color);

    await tester.tap(find.byKey(const Key('console.menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('console.tab.groups')));
    await tester.pumpAndSettle();
    final g = tester.widget<ChoiceChip>(find.byKey(const Key('groups.filter.all')));
    expect(g.selectedColor, ConsoleSection.groups.color);
  });
}
