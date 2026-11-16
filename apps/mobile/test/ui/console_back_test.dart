import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/moderation.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/console_nav.dart';
import '../helpers/fakes.dart';

/// Lot 5.5 (correction du 16/11/2026) — bouton retour du téléphone dans la console.
const _pin = '258014';

TestDeps _deps({bool admin = false}) =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true),
      )
      ..admin.admin = admin
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

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin.$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

Future<void> _openConsoleTab(WidgetTester tester, TestDeps deps, String tab) async {
  final salt = List<int>.generate(16, (i) => i);
  deps.lockStore.config = AppLockConfig(
    enabled: true,
    delaySeconds: 3600,
    salt: base64Encode(salt),
    hash: await const FastPinHasher().hash(_pin, salt, 1),
  );
  await _start(tester, deps);
  await _type(tester, _pin);
  await tester.tap(_tab('Paramètres'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('settings.console')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  // Lot 7.3a : une ligne de plus dans Paramètres : on s'assure qu'elle est bien visible.
  await tester.ensureVisible(find.byKey(const Key('settings.console')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings.console')));
  await tester.pumpAndSettle();
  await _type(tester, _pin);
  await openConsoleSection(tester, tab);
}

ConsoleAccount _acc(int i, String name) => ConsoleAccount(
  userId: 'x$i',
  handle: 'compte_$i',
  displayName: name,
  createdAt: DateTime(2026, 11, 1),
  lastSeenDay: DateTime(2026, 11, 13),
  platform: 'android',
  appVersion: '0.1.0+60',
  pushEnabled: true,
  directs: 0,
  groups: 0,
  reportsReceived90d: 0,
  support: const [],
);

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('retour : fiche, rubrique précédente, accueil, puis sortie', (tester) async {
    final deps = _deps(admin: true);
    deps.admin.accounts['x1'] = _acc(1, 'Amina');
    await _openConsoleTab(tester, deps, 'dashboard');
    await tester.tap(find.byKey(const Key('console.tile.journal')));
    await tester.pumpAndSettle();
    await openConsoleSection(tester, 'accounts');
    await tester.tap(find.byKey(const Key('account.x1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('accounts.list')), findsNothing, reason: 'fiche ouverte');

    await _back(tester);
    expect(find.byKey(const Key('accounts.list')), findsOneWidget, reason: 'fiche refermée');
    await _back(tester);
    expect(find.byKey(const Key('console.journal')), findsWidgets, reason: 'rubrique précédente');
    await _back(tester);
    expect(find.byKey(const Key('console.dashboard')), findsOneWidget);

    // Menu latéral : le retour le ferme seulement.
    await tester.tap(find.byKey(const Key('console.menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('console.drawer')), findsOneWidget);
    await _back(tester);
    expect(find.byKey(const Key('console.drawer')), findsNothing);
    expect(find.byKey(const Key('console.dashboard')), findsOneWidget);

    // Depuis l'accueil : on quitte la console.
    await _back(tester);
    expect(find.byKey(const Key('console.dashboard')), findsNothing);
    expect(find.byKey(const Key('settings.console')), findsOneWidget);
  });

  testWidgets('retour depuis un dossier de signalement : la liste', (tester) async {
    final deps = _deps(admin: true);
    await _openConsoleTab(tester, deps, 'reports');
    await _back(tester);
    expect(find.byKey(const Key('console.dashboard')), findsOneWidget, reason: 'vers l’accueil');
  });
}
