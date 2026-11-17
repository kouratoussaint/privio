import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/services/call_engine.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/console.dart';
import 'package:privio/state/messaging_providers.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/console_nav.dart';
import '../helpers/fakes.dart';

/// Lot 5.7 — santé du service (ADR-047) : version conseillée (bandeau) et minimale
/// (blocage), rubrique « Santé du service » de la console, compte rendu de fin d'appel.
const _pin = '258014';

TestDeps _deps({bool admin = false, String version = '0.1.0+60'}) =>
    TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true),
      )
      ..admin.admin = admin
      ..appVersion = version
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

Future<void> _openHealth(WidgetTester tester, TestDeps deps) async {
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
  await tester.ensureVisible(find.byKey(const Key('settings.console')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings.console')));
  await tester.pumpAndSettle();
  await _type(tester, _pin);
  await openConsoleSection(tester, 'health');
}

ConsolePolicy _health(String key, String label, String unit, Object value, {int? max}) =>
    ConsolePolicy(
      key: key,
      category: 'health',
      label: label,
      unit: unit,
      valueType: value is bool ? 'boolean' : (value is String ? 'string' : 'integer'),
      value: value,
      defaultValue: value is bool ? true : (value is String ? '' : 0),
      min: value is int ? 0 : null,
      max: value is int ? (max ?? 1000000) : null,
      clientVisible: true,
    );

final _healthPolicies = [
  _health('app_recommended_build', 'Version conseillée', 'build', 0),
  _health('app_min_build', 'Version minimale', 'build', 0),
  _health('app_update_url', 'Lien de mise à jour', 'text', ''),
  _health('sms_unit_cost', 'Prix d’un SMS', 'fcfa', 25, max: 10000),
  _health('health_alerts_enabled', 'Alertes par notification', 'bool', true),
];

ConsoleHealth _sample() => ConsoleHealth(
  generatedAt: DateTime(2026, 11, 17, 10),
  devices: 12,
  belowRecommended: 4,
  installed: const [
    InstalledVersion(version: '0.1.0+69', build: 69, devices: 8),
    InstalledVersion(version: '0.1.0+60', build: 60, devices: 4),
  ],
  callsAudio30d: 20,
  callsVideo30d: 5,
  callsOk30d: 18,
  callsFailed30d: 2,
  callsUnanswered30d: 5,
  callSeconds30d: 18 * 150,
  callsReported30d: 16,
  callsRelayed30d: 4,
  relayBytesMonth: 12400000000,
  codes30d: 40,
  codesMonth: 30,
  verified30d: 34,
  profiles30d: 21,
  phoneChange30d: 2,
  unitCost: 25,
  costMonth: 750,
  cost30d: 1000,
  jobs: [
    CronJob(
      job: 'privio_purge_expired',
      schedule: '* * * * *',
      lastRun: CronRun(at: DateTime.now().subtract(const Duration(minutes: 1)), ok: true),
    ),
    CronJob(
      job: 'privio_media_purge',
      schedule: '* * * * *',
      lastRun: CronRun(at: DateTime.now().subtract(const Duration(hours: 2)), ok: true),
    ),
  ],
  adminPushTargets: 1,
  alerts: [
    HealthAlert(
      kind: 'sms',
      at: DateTime.now().subtract(const Duration(hours: 1)),
      detail: const {'codes_hour': 45, 'threshold': 30},
    ),
  ],
);

void main() {
  test('numéro de compilation et niveau de mise à jour', () {
    expect(buildNumberOf('0.1.0+69'), 69);
    expect(buildNumberOf('0.1.0'), isNull);
    expect(buildNumberOf('0.1.0+abc'), isNull);
    expect(formatPolicyValue('build', 0), 'Aucune');
    expect(formatPolicyValue('build', 69), 'n° 69');
    expect(formatPolicyValue('fcfa', 1500), '1 500 FCFA');
    final rules = MessagingRules.fromPolicies(const {
      'app_min_build': 55,
      'app_recommended_build': 69,
      'app_update_url': ' https://privio.example/a.apk ',
    });
    expect(rules.minBuild, 55);
    expect(rules.recommendedBuild, 69);
    expect(rules.updateUrl, 'https://privio.example/a.apk');
  });

  testWidgets('version conseillée : bandeau dans Discussions et Groupes, lien, fermeture', (
    tester,
  ) async {
    final deps = _deps(version: '0.1.0+60');
    deps.messaging.policies = {
      'app_recommended_build': 69,
      'app_min_build': 50,
      'app_update_url': 'https://privio.example/privio.apk',
    };
    await _start(tester, deps);
    expect(find.byKey(const Key('update.banner')), findsOneWidget);
    expect(find.text('Une nouvelle version de Privio est disponible.'), findsOneWidget);
    expect(find.byKey(const Key('update.required')), findsNothing);
    await tester.tap(find.byKey(const Key('update.banner.open')));
    await tester.pumpAndSettle();
    expect(deps.openedUrls, [Uri.parse('https://privio.example/privio.apk')]);

    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update.banner')), findsOneWidget);
    await tester.tap(find.byKey(const Key('update.banner.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update.banner')), findsNothing);
    await tester.tap(_tab('Discussions'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update.banner')), findsNothing, reason: 'fermé pour la session');
  });

  testWidgets('version à jour ou de développement : rien', (tester) async {
    final deps = _deps(version: '0.1.0+69');
    deps.messaging.policies = {'app_recommended_build': 69, 'app_min_build': 60};
    await _start(tester, deps);
    expect(find.byKey(const Key('update.banner')), findsNothing);
    expect(find.byKey(const Key('update.required')), findsNothing);

    final dev = _deps(version: '0.1.0');
    dev.messaging.policies = {'app_recommended_build': 69, 'app_min_build': 69};
    await _start(tester, dev);
    expect(find.byKey(const Key('update.required')), findsNothing);
  });

  testWidgets('version minimale : écran bloquant, mise à jour, sans lien puis réessayer', (
    tester,
  ) async {
    final deps = _deps(version: '0.1.0+60');
    deps.messaging.policies = {'app_min_build': 65, 'app_update_url': ''};
    await _start(tester, deps);
    expect(find.byKey(const Key('update.required')), findsOneWidget);
    expect(find.text('Mettez Privio à jour'), findsOneWidget);
    expect(find.textContaining('pas encore disponible'), findsOneWidget);
    expect(find.text('Version installée : 0.1.0+60'), findsOneWidget);
    expect(find.byKey(const Key('update.required.open')), findsNothing);
    // L'application dessous ne répond plus.
    await tester.tap(_tab('Paramètres'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update.required')), findsOneWidget);

    // L'administration ajoute le lien : « Réessayer » relit les réglages.
    deps.messaging.policies = {
      'app_min_build': 65,
      'app_update_url': 'https://privio.example/privio.apk',
    };
    await tester.tap(find.byKey(const Key('update.required.retry')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('update.required.open')));
    await tester.pumpAndSettle();
    expect(deps.openedUrls.single.host, 'privio.example');

    // Version minimale abaissée : l'application revient.
    deps.messaging.policies = {'app_min_build': 0};
    await tester.tap(find.byKey(const Key('update.required.retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('update.required')), findsNothing);
  });

  testWidgets('console : santé du service (versions, appels, SMS, diagnostics, alertes)', (
    tester,
  ) async {
    final deps = _deps(admin: true);
    deps.admin
      ..policyList.addAll(_healthPolicies)
      ..healthData = _sample()
      ..relayResult = const RelayTestResult('ok', ms: 140);
    await _openHealth(tester, deps);
    expect(find.byKey(const Key('console.health')), findsOneWidget);
    expect(deps.admin.healthCalls, 1);
    expect(find.text('12'), findsWidgets);
    expect(find.byKey(const Key('health.version.0.1.0+69')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('health.version.0.1.0+60')),
        matching: find.textContaining('4 téléphones'),
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(find.byKey(const Key('health.relay_gauge')), 300);
    expect(find.textContaining('12,4 Go sur 1 000 Go gratuits'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('health.relay_share')), matching: find.text('25 %')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('health.calls_avg')),
        matching: find.text('2 min 30'),
      ),
      findsOneWidget,
    );

    await tester.scrollUntilVisible(find.byKey(const Key('health.cost')), 300);
    expect(find.textContaining('750 FCFA ce mois-ci'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const Key('health.verified')), matching: find.text('34')),
      findsOneWidget,
    );

    // Diagnostics : notification de test et relais.
    await tester.scrollUntilVisible(find.byKey(const Key('health.test_relay')), 300);
    await tester.tap(find.byKey(const Key('health.test_push')));
    await tester.pump();
    expect(deps.admin.pushTests, 1);
    expect(find.byKey(const Key('health.push_sent')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('health.test_relay')), 300);
    await tester.tap(find.byKey(const Key('health.test_relay')));
    await tester.pumpAndSettle();
    expect(find.text('Relais disponible (réponse en 140 ms)'), findsOneWidget);
    // Tâche en retard signalée.
    await tester.scrollUntilVisible(find.byKey(const Key('health.job.privio_media_purge')), 300);
    expect(
      find.descendant(
        of: find.byKey(const Key('health.job.privio_media_purge')),
        matching: find.byIcon(Icons.warning_amber_rounded),
      ),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(find.byKey(const Key('health.alert.0')), 300);
    expect(find.text('Pic de codes SMS'), findsOneWidget);
    expect(find.textContaining('45 codes en une heure'), findsOneWidget);
    expect(
      deps.admin.journalEntries.map((e) => e.action),
      containsAll(['health', 'health_push', 'health_relay']),
    );
  });

  testWidgets('console : choisir une version installée comme version conseillée', (tester) async {
    final deps = _deps(admin: true);
    deps.admin
      ..policyList.addAll(_healthPolicies)
      ..healthData = _sample();
    await _openHealth(tester, deps);
    await tester.ensureVisible(find.byKey(const Key('health.version.0.1.0+69')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('health.version.0.1.0+69')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('health.version.recommend')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('policy.editor.app_recommended_build')), findsOneWidget);
    expect(find.text('n° 69'), findsWidgets);
    await tester.tap(find.byKey(const Key('policy.save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('policy.confirm.change')), findsOneWidget);
    expect(find.text('Aucune  →  n° 69'), findsOneWidget);
    await tester.tap(find.byKey(const Key('policy.confirm.ok')));
    await tester.pumpAndSettle();
    expect(deps.admin.policyList.firstWhere((p) => p.key == 'app_recommended_build').value, 69);

    // Lien de mise à jour : https obligatoire.
    await tester.ensureVisible(find.byKey(const Key('policy.app_update_url')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('policy.app_update_url')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('update_url.input')), 'http://privio.example');
    await tester.tap(find.byKey(const Key('update_url.save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('https://'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('update_url.input')),
      'https://privio.example/privio.apk',
    );
    await tester.tap(find.byKey(const Key('update_url.save')));
    await tester.pumpAndSettle();
    expect(
      deps.admin.policyList.firstWhere((p) => p.key == 'app_update_url').value,
      'https://privio.example/privio.apk',
    );
  });

  testWidgets('santé : refusée sans droit d’administration', (tester) async {
    final deps = _deps();
    await expectLater(deps.admin.health(), throwsA(anything));
    expect((await deps.admin.testRelay()).relay, 'error');
  });

  testWidgets('fin d’un appel : compte rendu (relais, volume) envoyé au serveur', (tester) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    await _start(tester, deps);
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.call')));
    await tester.pump(const Duration(milliseconds: 500));
    final id = deps.calls.calls.keys.last;
    deps.calls
      ..peerAnswer(id)
      ..peerSignal(id, 'answer', {'type': 'answer', 'sdp': 'b'});
    await tester.pump(const Duration(milliseconds: 500));
    deps.callEngine.onState!(CallMediaState.connected);
    await tester.pump(const Duration(milliseconds: 500));
    deps.callEngine
      ..traffic = 2 * 1024 * 1024
      ..relay = true;
    await tester.tap(find.byKey(const Key('call.hangup')));
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pump();
    expect(deps.calls.reports, [(id, true, 2 * 1024 * 1024)]);
  });
}
