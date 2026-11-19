import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/console.dart';
import 'package:privio/domain/models/console_team.dart';
import 'package:privio/ui/features/console/stats_export.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/console_nav.dart';
import '../helpers/fakes.dart';

/// Lot 5.9 — console : pilotage. Inscriptions sur liste et code d'invitation (jusque dans
/// le parcours d'inscription), préréglages, message programmé, exceptions, statistiques et
/// export, alerte « nouveau téléphone ».
const _pin = '258014';

TestDeps _deps() =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true),
      )
      ..admin.admin = true
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

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

Future<void> _openConsole(
  WidgetTester tester,
  TestDeps deps, {
  List<Override> extra = const [],
}) async {
  final salt = List<int>.generate(16, (i) => i);
  deps.lockStore.config = AppLockConfig(
    enabled: true,
    delaySeconds: 3600,
    salt: base64Encode(salt),
    hash: await const FastPinHasher().hash(_pin, salt, 1),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...deps.overrides, ...extra],
      retry: (_, _) => null,
      child: const PrivioApp(),
    ),
  );
  await tester.pumpAndSettle();
  await _type(tester, _pin);
  await tester.tap(_tab('Paramètres'));
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
  testWidgets('inscriptions : mode « Sur liste », numéros, code d’invitation', (tester) async {
    final deps = _deps();
    await _openConsole(tester, deps);
    await openConsoleSection(tester, 'signups');
    expect(find.byKey(const Key('signups.view')), findsOneWidget);
    await tester.tap(find.byKey(const Key('signups.mode.list')));
    await tester.pumpAndSettle();
    expect(deps.admin.signupMode, 'list');
    expect(find.textContaining('Seuls les numéros de la liste'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('signups.phones')),
      '70 00 00 05\n+22670000006\nabc',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('signups.phones.add')));
    await tester.pumpAndSettle();
    expect(deps.admin.signupPhoneList, ['+22670000005', '+22670000006']);

    await tester.scrollUntilVisible(
      find.byKey(const Key('signups.code.new')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    for (final m in tester.stateList<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))) {
      m.clearSnackBars();
    }
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('signups.code.new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('signups.code.new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('signups.code.label')), 'Pilote Bobo');
    await tester.tap(find.byKey(const Key('signups.code.uses.50')));
    await tester.tap(find.byKey(const Key('signups.code.create')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signups.code.created')), findsOneWidget);
    expect(find.text('PILOTE23'), findsWidgets);
    expect(deps.admin.signupCodes.single.maxUses, 50);
  });

  testWidgets('inscription sur invitation : le code est demandé, puis le profil est créé', (
    tester,
  ) async {
    final deps = TestDeps();
    deps.api
      ..signupMode = 'list'
      ..signupAllowed = false;
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('onboarding.consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboarding.consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboarding.continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('welcome.phone')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('phone.input')), '70000001');
    await tester.tap(find.byKey(const Key('phone.submit')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('otp.input')), '123456');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile.name')), 'Toussaint');
    await tester.enterText(find.byKey(const Key('profile.handle')), 'toussaint_bf');
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('profile.submit')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('signup.code.dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('signup.code')), 'FAUX2345');
    await tester.pump();
    await tester.tap(find.byKey(const Key('signup.code.submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('n’est pas valable'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('signup.code')), 'pilote23');
    await tester.pump();
    await tester.tap(find.byKey(const Key('signup.code.submit')));
    await tester.pumpAndSettle();
    expect(deps.api.redeemedCodes, ['pilote23']);
    expect(find.byKey(const Key('signup.code.dialog')), findsNothing);
    expect(find.byKey(const Key('permissions.later')), findsOneWidget);
  });

  testWidgets('pilotage : préréglage montré puis appliqué, message programmé', (tester) async {
    final deps = _deps();
    await _openConsole(tester, deps);
    await openConsoleSection(tester, 'pilot');
    await tester.tap(find.byKey(const Key('preset.pilot')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('preset.change.signups_mode')), findsOneWidget);
    expect(find.textContaining('ouvertes → sur liste'), findsOneWidget);
    await tester.tap(find.byKey(const Key('preset.apply')));
    await tester.pumpAndSettle();
    expect(deps.admin.pilotLog, ['preset:pilot']);
    expect(deps.admin.signupMode, 'list');

    await tester.tap(find.byKey(const Key('scheduled.new')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('scheduled.save'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('scheduled.text')), 'Maintenance ce soir');
    await tester.pump();
    await tester.tap(find.byKey(const Key('scheduled.save')));
    await tester.pumpAndSettle();
    expect(deps.admin.pilotLog.last, 'scheduled:Maintenance ce soir');
    expect(find.byKey(const Key('scheduled.current')), findsOneWidget);
    await tester.tap(find.byKey(const Key('scheduled.remove')));
    await tester.pumpAndSettle();
    expect(deps.admin.scheduled, isNull);
  });

  testWidgets('exception pour un groupe : 300 membres pendant 30 jours, puis retirée', (
    tester,
  ) async {
    final deps = _deps();
    await _openConsole(tester, deps);
    await openConsoleSection(tester, 'groups');
    await tester.tap(find.byKey(const Key('group.g1')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('overrides.add.group')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('overrides.add.group')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('override.number')), '600');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const Key('override.save'))).onPressed, isNull);
    await tester.enterText(find.byKey(const Key('override.number')), '300');
    await tester.pump();
    await tester.tap(find.byKey(const Key('override.save')));
    await tester.pumpAndSettle();
    expect(deps.admin.pilotLog, ['override:group:g1:group_max_members:300:30']);
    expect(find.byKey(const Key('override.group.group_max_members')), findsOneWidget);

    await openConsoleSection(tester, 'pilot');
    await tester.scrollUntilVisible(
      find.byKey(const Key('override.remove.group.group_max_members')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('override.group.group_max_members')), findsOneWidget);
    await tester.tap(find.byKey(const Key('override.remove.group.group_max_members')));
    await tester.pumpAndSettle();
    expect(deps.admin.overrideList, isEmpty);
  });

  testWidgets('statistiques : rétention, langues, usage, export CSV', (tester) async {
    final deps = _deps();
    final shared = <(String, String)>[];
    await _openConsole(
      tester,
      deps,
      extra: [shareCsvProvider.overrideWithValue((name, csv) async => shared.add((name, csv)))],
    );
    await openConsoleSection(tester, 'stats');
    await tester.scrollUntilVisible(
      find.byKey(const Key('stats.export')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('RÉTENTION'), findsOneWidget, reason: 'titre de section (lot 5.10)');
    expect(find.textContaining('Mooré'), findsOneWidget);
    expect(find.textContaining('Vocaux'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('stats.export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stats.export')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(deps.admin.exports, 1);
    expect(shared.single.$1, startsWith('privio-statistiques-'));
    expect(shared.single.$2, contains('semaine_inscription'));
    expect(shared.single.$2, contains('mos;3'));
  });

  test('CSV : nombres seulement, une ligne par jour', () {
    final csv = statsCsv(
      ConsoleStats(
        days: [
          StatDay.fromJson(const {'day': '2026-11-18', 'text': 3, 'voice': 2, 'new_accounts': 1}),
        ],
      ),
      StatsExtra(
        usage: [
          (DateTime(2026, 11, 18), const {'messages_voice': 2}),
        ],
      ),
    );
    final lines = csv.split('\n');
    expect(lines.first, startsWith('jour;actifs;nouveaux_comptes;messages'));
    expect(lines[1], startsWith('2026-11-18;;1;5'));
    expect(lines[1], contains(';2;'));
  });

  test('alerte : console ouverte sur un nouveau téléphone', () {
    final a = HealthAlert(
      kind: 'console_device',
      at: DateTime.utc(2026, 11, 18, 10),
      detail: const {'name': 'Modo', 'role': 'moderator', 'model': 'Tecno Spark'},
    );
    expect(a.title, 'Console ouverte sur un nouveau téléphone');
    expect(a.text, 'Modo (modérateur) · Tecno Spark');
  });
}
