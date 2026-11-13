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
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('3,3 Mo'), findsOneWidget); // stockage vocaux
    expect(find.textContaining('+226'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('console.privacy_note')),
      200,
      scrollable: find.byType(Scrollable).last,
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
}
