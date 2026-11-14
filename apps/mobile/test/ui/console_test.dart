import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:privio/app.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/console.dart';
import 'package:privio/router/routes.dart';
import 'package:privio/state/messaging_providers.dart';
import 'package:privio/state/session_controller.dart';
import 'package:privio/ui/features/console/console_screen.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 5.1 — console d'administration dans l'application (amendement 6).
const _pin = '258014';

TestDeps _deps({bool admin = true}) =>
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

Future<void> _withLock(TestDeps d, {bool biometrics = false}) async {
  final salt = List<int>.generate(16, (i) => i);
  d.lockStore.config = AppLockConfig(
    enabled: true,
    delaySeconds: 3600,
    biometrics: biometrics,
    salt: base64Encode(salt),
    hash: await const FastPinHasher().hash(_pin, salt, 1),
  );
  d.biometrics.isAvailable = biometrics;
}

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin.$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _start(WidgetTester tester, TestDeps deps, {bool locked = false}) async {
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  if (locked) await _type(tester, _pin); // déverrouillage de l'application au démarrage
}

final _dashScroll = find
    .descendant(of: find.byKey(const Key('console.dashboard')), matching: find.byType(Scrollable))
    .first;

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

Future<void> _openConsole(WidgetTester tester) async {
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
}

void main() {
  test('tailles lisibles', () {
    expect(formatBytes(0), '0 o');
    expect(formatBytes(820 * 1024), '820 Ko');
    expect(formatBytes(12 * 1024 * 1024 + 410 * 1024), '12,4 Mo');
    expect(formatBytes(3 * 1024 * 1024), '3 Mo');
    expect(formatBytes(1288490189), '1,2 Go');
  });

  test('lecture du tableau de bord (nombres seulement)', () {
    final d = ConsoleDashboard.fromJson({
      'generated_at': '2026-11-13T18:30:00Z',
      'counting_since': '2026-11-13',
      'accounts': {'total': 2, 'active_24h': 1, 'active_7d': 2, 'new_7d': 2},
      'activity': {'messages_today': 3, 'messages_7d': 3, 'voice_7d': 1, 'photos_7d': 0},
      'groups': {'total': 1, 'invitations_pending': 1},
      'requests': {'pending': 0, 'accepted_7d': 1, 'refused_7d': 0},
      'health': {
        'push_sent_24h': 4,
        'purge_messages_last': {'at': '2026-11-13T18:29:00Z', 'status': 'succeeded'},
        'purge_media_last': null,
        'storage_voice_bytes': 2048,
      },
      'reports': {'open': 1},
    });
    expect(d.accountsTotal, 2);
    expect(d.messagesToday, 3);
    expect(d.invitationsPending, 1);
    expect(d.purgeMessages?.ok, isTrue);
    expect(d.purgeMedia, isNull);
    expect(d.storageVoiceBytes, 2048);
    expect(d.reportsOpen, 1);
    expect(d.countingSince, DateTime(2026, 11, 13));
  });

  testWidgets('autre compte : aucune entrée « Administration »', (tester) async {
    final deps = _deps(admin: false);
    await _start(tester, deps);
    await tester.tap(_tab('Paramètres'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.signout')),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byKey(const Key('settings.console')), findsNothing);
    expect(find.text('Administration'), findsNothing);
  });

  testWidgets('autre compte qui force l’adresse /console : le serveur refuse', (tester) async {
    final deps = _deps(admin: false);
    await _withLock(deps);
    await _start(tester, deps, locked: true);
    unawaited(GoRouter.of(tester.element(find.byType(HomeShell))).push(Routes.console));
    await tester.pumpAndSettle();
    await _type(tester, _pin);
    expect(find.text('Accès réservé à l’administration de Privio.'), findsOneWidget);
    expect(find.byKey(const Key('console.dashboard')), findsNothing);
    expect(deps.admin.dashboardCalls, 0);
  });

  testWidgets('administrateur sans verrouillage : il faut d’abord l’activer', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await _openConsole(tester);
    expect(find.byKey(const Key('console.lock_required')), findsOneWidget);
    expect(find.text('Verrouillage obligatoire'), findsOneWidget);
    expect(deps.admin.dashboardCalls, 0, reason: 'aucun chiffre avant le verrouillage');

    await tester.tap(find.byKey(const Key('console.enable_lock')));
    await tester.pumpAndSettle();
    await _type(tester, _pin);
    await _type(tester, _pin);
    expect(find.text('Verrouillage activé.'), findsOneWidget);
    // De retour sur la console : le code est maintenant demandé.
    expect(find.byKey(const Key('console.pin')), findsOneWidget);
    expect(find.text('Code Privio'), findsOneWidget);
  });

  testWidgets('administrateur : code demandé à chaque ouverture, puis le tableau de bord', (
    tester,
  ) async {
    final deps = _deps();
    await _withLock(deps);
    await _start(tester, deps, locked: true);
    await _openConsole(tester);
    expect(find.text('Confirmez votre identité pour ouvrir la console.'), findsOneWidget);
    expect(deps.admin.dashboardCalls, 0);

    await _type(tester, '000001');
    expect(find.text('Code incorrect.'), findsOneWidget);
    expect(find.byKey(const Key('console.dashboard')), findsNothing);

    await _type(tester, _pin);
    expect(find.byKey(const Key('console.dashboard')), findsOneWidget);
    expect(deps.admin.dashboardCalls, 1);
    expect(find.text('42'), findsOneWidget); // comptes
    expect(find.text('Actifs (24\u00A0h)'), findsOneWidget);
    expect(find.text('860'), findsOneWidget); // messages sur 7 jours
    await tester.scrollUntilVisible(
      find.byKey(const Key('console.health.voice')),
      200,
      scrollable: _dashScroll,
    );
    expect(find.text('3,3 Mo'), findsOneWidget); // stockage vocaux
    expect(find.textContaining('+226'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('console.privacy_note')),
      200,
      scrollable: _dashScroll,
    );
    expect(find.textContaining('aucun message, nom ni numéro'), findsOneWidget);
    expect(find.textContaining('Activité comptée depuis le 13/11/2026'), findsOneWidget);

    // Refermer, puis rouvrir : le code est redemandé.
    await tester.tap(find.byKey(const Key('console.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('console.pin')), findsOneWidget);
    expect(find.byKey(const Key('console.dashboard')), findsNothing);
  });

  testWidgets('console refermée après 5 min sans action', (tester) async {
    final deps = _deps();
    await _withLock(deps);
    await _start(tester, deps, locked: true);
    await _openConsole(tester);
    await _type(tester, _pin);
    expect(find.byKey(const Key('console.dashboard')), findsOneWidget);

    await tester.pump(ConsoleScreen.idleTimeout - const Duration(seconds: 1));
    expect(find.byKey(const Key('console.dashboard')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('console.dashboard')), findsNothing);
    expect(find.text('Console refermée après 5 min sans action.'), findsOneWidget);
  });

  testWidgets('une action relance le délai de 5 min', (tester) async {
    final deps = _deps();
    await _withLock(deps);
    await _start(tester, deps, locked: true);
    await _openConsole(tester);
    await _type(tester, _pin);
    await tester.pump(const Duration(minutes: 4));
    await tester.drag(find.byKey(const Key('console.dashboard')), const Offset(0, -100));
    await tester.pump(const Duration(minutes: 4));
    expect(find.byKey(const Key('console.dashboard')), findsOneWidget);
  });

  testWidgets('sortie de l’application : la console se referme', (tester) async {
    final deps = _deps();
    await _withLock(deps);
    await _start(tester, deps, locked: true);
    await _openConsole(tester);
    await _type(tester, _pin);
    expect(find.byKey(const Key('console.dashboard')), findsOneWidget);
    for (final s in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('console.dashboard')), findsNothing);
    expect(find.byKey(const Key('console.pin')), findsOneWidget);
  });

  testWidgets('empreinte : ouvre la console', (tester) async {
    final deps = _deps();
    await _withLock(deps, biometrics: true);
    await _start(tester, deps); // déverrouillée par l'empreinte au démarrage
    expect(find.byKey(const Key('lock.screen')), findsNothing);
    await _openConsole(tester);
    deps.biometrics.accept = false;
    await tester.tap(find.byKey(const Key('console.biometrics')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('console.dashboard')), findsNothing);
    deps.biometrics.accept = true;
    await tester.tap(find.byKey(const Key('console.biometrics')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('console.dashboard')), findsOneWidget);
  });

  // -------------------------------------------------------------------------
  // Lot 5.2 : réglages, statistiques, journal
  // -------------------------------------------------------------------------
  Future<TestDeps> openTab(WidgetTester tester, String tab) async {
    final deps = _deps();
    await _withLock(deps);
    await _start(tester, deps, locked: true);
    await _openConsole(tester);
    await _type(tester, _pin);
    await tester.ensureVisible(find.byKey(Key('console.tab.$tab')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('console.tab.$tab')));
    await tester.pumpAndSettle();
    return deps;
  }

  test('valeurs avec leur unité', () {
    expect(formatPolicyValue('min', 60), '60 min');
    expect(formatPolicyValue('j', 1), '1 jour');
    expect(formatPolicyValue('j', 7), '7 jours');
    expect(formatPolicyValue('car', 4000), '4 000 caractères');
    expect(formatPolicyValue('o', 1048576), '1 Mo');
    expect(formatPolicyValue('bool', true), 'Oui');
    expect(formatPolicyValue('nb', 10080), '10 080');
  });

  testWidgets('réglages : par thème, cadenas sur les invariants', (tester) async {
    await openTab(tester, 'policies');
    expect(find.text('Médias'), findsOneWidget);
    expect(find.text('Groupes'), findsOneWidget);
    expect(find.text('Photos par compte et par jour'), findsOneWidget);
    expect(find.text('Membres au plus par groupe'), findsOneWidget);
    // « Avancé » et « Fixés » sont repliés.
    expect(find.text('Taille maximale d’une photo'), findsNothing);
    await tester.tap(find.text('Fixés (sécurité)'));
    await tester.pumpAndSettle();
    expect(find.text('Durée de vie maximale d’un message : 72 h'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('policy.message_ttl_hours')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('policy.message_ttl_hours')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('policy.editor.message_ttl_hours')),
      findsNothing,
      reason: 'un invariant ne s’ouvre pas',
    );
  });

  testWidgets('modifier un réglage : limites, confirmation avant → après, journal', (tester) async {
    final deps = await openTab(tester, 'policies');
    await tester.tap(find.byKey(const Key('policy.photo_daily_limit')));
    await tester.pumpAndSettle();
    expect(find.text('Entre 0 et 10 · par défaut 5'), findsOneWidget);
    expect(find.text('Compté sur la journée en cours.'), findsOneWidget);
    final save = find.byKey(const Key('policy.save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: 'rien n’a changé');

    await tester.tap(find.byKey(const Key('policy.minus')));
    await tester.tap(find.byKey(const Key('policy.minus')));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('policy.value'))).data, '3');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('5  →  3'), findsOneWidget);
    // Annuler : rien n'est envoyé.
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(deps.admin.policyChanges, isEmpty);

    await tester.tap(save);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('policy.confirm.ok')));
    await tester.pumpAndSettle();
    expect(deps.admin.policyList.first.value, 3);
    expect(find.text('Réglage enregistré : Photos par compte et par jour = 3'), findsOneWidget);
    // La liste montre la nouvelle valeur et la valeur par défaut.
    expect(find.textContaining('3 · par défaut : 5'), findsOneWidget);

    // Journal.
    await tester.ensureVisible(find.byKey(const Key('console.tab.journal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('console.tab.journal')));
    await tester.pumpAndSettle();
    expect(find.text('Réglage « Photos par compte et par jour » : défaut → 3'), findsOneWidget);
    expect(find.text('Consultation du tableau de bord'), findsOneWidget);
  });

  testWidgets('limites : impossible de dépasser le maximum', (tester) async {
    final deps = await openTab(tester, 'policies');
    await tester.tap(find.byKey(const Key('policy.group_max_members')));
    await tester.pumpAndSettle();
    final slider = find.byKey(const Key('policy.slider'));
    await tester.drag(slider, const Offset(2000, 0));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(find.byKey(const Key('policy.value'))).data, '100');
    expect(tester.widget<IconButton>(find.byKey(const Key('policy.plus'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('policy.default')));
    await tester.pump();
    expect(tester.widget<Text>(find.byKey(const Key('policy.value'))).data, '25');
    expect(deps.admin.policyChanges, isEmpty);
  });

  testWidgets('interrupteur et historique : rétablir une ancienne valeur', (tester) async {
    final deps = await openTab(tester, 'policies');
    await tester.tap(find.byKey(const Key('policy.connection_requests_required')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('policy.switch')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('policy.save')));
    await tester.pumpAndSettle();
    expect(find.text('Oui  →  Non'), findsOneWidget);
    await tester.tap(find.byKey(const Key('policy.confirm.ok')));
    await tester.pumpAndSettle();
    expect(deps.admin.policyList[2].value, false);

    // Retour à « Oui », puis rétablir « Non » depuis l'historique.
    await tester.tap(find.byKey(const Key('policy.connection_requests_required')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('policy.default')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('policy.save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('policy.confirm.ok')));
    await tester.pumpAndSettle();
    expect(deps.admin.policyList[2].value, true);

    await tester.tap(find.byKey(const Key('policy.connection_requests_required')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('policy.history.0')), findsOneWidget);
    await tester.tap(find.byKey(const Key('policy.restore.1')));
    await tester.pumpAndSettle();
    expect(find.text('Oui  →  Non'), findsOneWidget);
    await tester.tap(find.byKey(const Key('policy.confirm.ok')));
    await tester.pumpAndSettle();
    expect(deps.admin.policyList[2].value, false);
    expect(deps.admin.policyChanges.length, 3);
  });

  testWidgets('refus du serveur : message clair, rien n’est changé', (tester) async {
    final deps = await openTab(tester, 'policies');
    // Le serveur a changé entre-temps de bornes : il refuse.
    deps.admin.policyList[0] = const ConsolePolicy(
      key: 'photo_daily_limit',
      category: 'media',
      label: 'Photos par compte et par jour',
      unit: 'nb',
      valueType: 'integer',
      value: 5,
      defaultValue: 5,
      min: 0,
      max: 4,
    );
    await tester.tap(find.byKey(const Key('policy.photo_daily_limit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('policy.plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('policy.save')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('policy.confirm.ok')));
    await tester.pumpAndSettle();
    expect(find.text('Valeur hors des limites autorisées pour ce réglage.'), findsOneWidget);
    expect(deps.admin.policyChanges, isEmpty);
  });

  testWidgets('statistiques : 30 jours, parts, versions, tableau', (tester) async {
    final deps = await openTab(tester, 'stats');
    expect(deps.admin.statsCalls, 1);
    expect(find.text('Messages par jour'), findsOneWidget);
    expect(find.text('Texte'), findsOneWidget);
    expect(find.text('123 · 84 %'), findsOneWidget); // 40+41+42 sur 147
    // Toucher la dernière barre : le jour et la valeur.
    final bars = find.byKey(const Key('stats.bars.messages'));
    final box = tester.getRect(find.descendant(of: bars, matching: find.byType(CustomPaint)).first);
    await tester.tapAt(Offset(box.right - 2, box.bottom - 5));
    await tester.pumpAndSettle();
    expect(find.text('13/11 : 48'), findsOneWidget);

    final list = find
        .descendant(of: find.byKey(const Key('console.stats')), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.byKey(const Key('stats.version.0.1.0+27')),
      300,
      scrollable: list,
    );
    expect(find.text('12 · 80 %'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('stats.table')), 300, scrollable: list);
    await tester.tap(find.byKey(const Key('stats.table')));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    expect(find.textContaining('+226'), findsNothing);
  });

  test('réglage changé : pris en compte par le téléphone au retour dans l’app', () async {
    final deps = _deps(admin: false);
    final c = deps.container();
    addTearDown(c.dispose);
    deps.messaging.policies = {'message_edit_window_minutes': 60};
    await c.read(sessionControllerProvider.future);
    expect((await c.read(messagingRulesProvider.future)).editWindow.inMinutes, 60);
    deps.messaging.policies = {'message_edit_window_minutes': 15};
    c.listen(realtimeSignalsProvider, (_, _) {});
    deps.realtime.emit('', event: 'resume');
    await Future<void>.delayed(Duration.zero);
    expect((await c.read(messagingRulesProvider.future)).editWindow.inMinutes, 15);
  });
}
