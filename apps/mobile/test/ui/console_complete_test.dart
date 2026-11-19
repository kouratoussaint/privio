import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/moderation.dart';
import 'package:privio/domain/models/console.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/console_nav.dart';
import '../helpers/fakes.dart';

/// Lot 5.5 — console complète : menu latéral et tuiles, comptes A–Z paginés,
/// fonctionnalités et message d'information, journal filtrable ; effets dans l'application.
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

ConsolePolicy _feature(String key, String label, int order) => ConsolePolicy(
  key: key,
  category: 'features',
  label: label,
  unit: 'bool',
  valueType: 'boolean',
  value: true,
  defaultValue: true,
  sortOrder: order,
);

void main() {
  testWidgets('menu latéral et tuiles de l’accueil', (tester) async {
    final deps = _deps(admin: true);
    await _openConsoleTab(tester, deps, 'dashboard');
    // Lot 5.10 : toutes les rubriques en tuiles, par partie (l'accueil défile).
    for (final s in ['reports', 'accounts', 'stats', 'journal', 'features', 'policies']) {
      await tester.scrollUntilVisible(
        find.byKey(Key('console.tile.$s')),
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('console.dashboard')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.byKey(Key('console.tile.$s')), findsOneWidget, reason: s);
    }
    await tester.ensureVisible(find.byKey(const Key('console.tile.features')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('console.tile.features')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('console.features')), findsOneWidget);
    expect(find.text('Fonctionnalités'), findsWidgets);
    await openConsoleSection(tester, 'dashboard');
    expect(find.byKey(const Key('console.dashboard')), findsOneWidget);
  });

  testWidgets('comptes : tous, A–Z, 25 par page, lettres à droite', (tester) async {
    final deps = _deps(admin: true);
    const names = ['Zoé', 'Amina', 'Émile', 'Bob'];
    for (var i = 0; i < 30; i++) {
      deps.admin.accounts['x$i'] = _acc(
        i,
        i < 4 ? names[i] : 'Moussa ${i.toString().padLeft(2, '0')}',
      );
    }
    await _openConsoleTab(tester, deps, 'accounts');
    expect(find.text('30 comptes · page 1 sur 2'), findsOneWidget);
    final first = tester.getTopLeft(find.text('Amina')).dy;
    expect(tester.getTopLeft(find.text('Bob')).dy, greaterThan(first));
    expect(tester.getTopLeft(find.text('Émile')).dy, greaterThan(first), reason: 'É avec les E');
    expect(find.text('Zoé'), findsNothing, reason: 'Z : page 2');
    // La lettre Z ouvre la page 2.
    await tester.tap(find.byKey(const Key('accounts.letter.Z')));
    await tester.pumpAndSettle();
    expect(find.text('30 comptes · page 2 sur 2'), findsOneWidget);
    expect(find.text('Zoé'), findsOneWidget);
    // Pages numérotées.
    await tester.tap(find.byKey(const Key('pager.1')));
    await tester.pumpAndSettle();
    expect(find.text('Amina'), findsOneWidget);
    expect(deps.admin.journalEntries.any((e) => e.action == 'account_list'), isTrue);
  });

  testWidgets('fonctionnalités : interrupteur confirmé, message d’information, engagements', (
    tester,
  ) async {
    final deps = _deps(admin: true);
    deps.admin.policyList.addAll([
      _feature('calls_video_enabled', 'Appels vidéo', 30),
      _feature('voice_enabled', 'Messages vocaux', 40),
      const ConsolePolicy(
        key: 'announcement_text',
        category: 'features',
        label: 'Message d’information',
        unit: 'text',
        valueType: 'string',
        value: '',
        defaultValue: '',
        sortOrder: 100,
      ),
    ]);
    await _openConsoleTab(tester, deps, 'features');
    await tester.tap(find.byKey(const Key('feature.calls_video_enabled')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feature.confirm')), findsOneWidget);
    await tester.tap(find.byKey(const Key('feature.confirm.ok')));
    await tester.pumpAndSettle();
    expect(deps.admin.policyList.firstWhere((p) => p.key == 'calls_video_enabled').value, false);
    expect(find.text('Désactivé pour tous'), findsOneWidget);

    await tester.tap(find.byKey(const Key('feature.announcement_text')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('announcement.input')), 'Maintenance à 22 h');
    await tester.tap(find.byKey(const Key('announcement.publish')));
    await tester.pumpAndSettle();
    expect(
      deps.admin.policyList.firstWhere((p) => p.key == 'announcement_text').value,
      'Maintenance à 22 h',
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('feature.message_ttl_hours')),
      find.byKey(const Key('console.features')),
      const Offset(0, -200),
    );
    // Lot 5.10 : titre, puis la valeur avec la mention.
    expect(find.text('Durée de vie maximale d’un message'), findsOneWidget);
    expect(find.textContaining('72 h · Fixé'), findsOneWidget);
  });

  testWidgets('journal : par type d’action, par période, pages', (tester) async {
    final deps = _deps(admin: true);
    await _openConsoleTab(tester, deps, 'policies');
    // Un changement de réglage, puis le journal.
    await deps.admin.setPolicy('photo_daily_limit', 3);
    await openConsoleSection(tester, 'journal');
    expect(find.byKey(const Key('journal.count')), findsOneWidget);
    await tester.tap(find.byKey(const Key('journal.type.settings')));
    await tester.pumpAndSettle();
    expect(deps.admin.journalQueries.last, ('settings', null, 1));
    expect(find.textContaining('Photos par compte et par jour'), findsOneWidget);
    expect(find.text('Consultation du tableau de bord'), findsNothing);
    await tester.tap(find.byKey(const Key('journal.days.7')));
    await tester.pumpAndSettle();
    expect(deps.admin.journalQueries.last, ('settings', 7, 1));
    await tester.tap(find.byKey(const Key('journal.type.all')));
    await tester.pumpAndSettle();
    expect(deps.admin.journalQueries.last, (null, 7, 1));
  });
}
