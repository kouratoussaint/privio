import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/diagnostics/tech_log.dart';
import 'package:privio/domain/models/account.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fakes.dart';

/// Lot 6.1 (ADR-055) — journal technique local : sans contenu ni nom, joint à une
/// demande d'assistance seulement avec l'accord de la personne.
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

Future<void> _scrollTap(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).last);
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _openSupport(WidgetTester tester, TestDeps deps) async {
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Paramètres'));
  await tester.pumpAndSettle();
  await _scrollTap(tester, find.byKey(const Key('settings.help')));
  await _scrollTap(tester, find.byKey(const Key('help.contact')));
  await tester.enterText(find.byKey(const Key('help.message')), 'Privio se ferme');
}

StackTrace _stack() => StackTrace.fromString(
  'build_id: \'abc123\'\n'
  'isolate_dso_base: 7a00000000\n'
  '#0      ChatScreen._send (package:privio/ui/features/chat/chat_screen.dart:812:5)\n'
  '#1      _Handler.run (package:privio/state/x.dart:10:1)\n'
  'texte libre qui ne doit pas sortir\n'
  '${List.generate(12, (i) => '#${i + 2}      f$i (package:privio/a.dart:$i:1)').join('\n')}',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('une erreur est notée par son type et son emplacement, jamais son texte', () async {
    final log = TechLog(now: () => DateTime(2026, 11, 19, 10, 42));
    log.started(appVersion: '0.1.0+90', android: '13', model: 'TECNO Spark 10');
    log.error('application', StateError('Message de Bob au +22670000002'), _stack());
    final out = log.export();
    expect(out, contains('19/11 10:42 Démarrage · Privio 0.1.0+90 · Android 13 · TECNO Spark 10'));
    expect(out, contains('Erreur application · StateError'));
    expect(out, contains("build_id: 'abc123'"));
    expect(out, contains('chat_screen.dart:812'));
    expect(out, isNot(contains('Bob')));
    expect(out, isNot(contains('2267')));
    expect(out, isNot(contains('texte libre')));
    expect(RegExp(r'^#\d', multiLine: true).allMatches(out).length, 8, reason: '8 lignes au plus');
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });

  test('200 entrées au plus ; l’export garde les plus récentes sous 16 000 caractères', () async {
    final log = TechLog();
    for (var i = 0; i < 260; i++) {
      log.error('application', ArgumentError('x' * 50), _stack());
    }
    expect(log.entries.length, TechLog.maxEntries);
    final out = log.export();
    expect(out.length, lessThanOrEqualTo(TechLog.maxExportChars));
    expect(out.split('\n').last, log.entries.last.split('\n').last);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final reloaded = TechLog();
    await reloaded.load();
    expect(reloaded.entries.length, TechLog.maxEntries, reason: 'conservé sur le téléphone');
  });

  testWidgets('assistance : le journal ne part que si la case est cochée', (tester) async {
    final deps = _deps();
    deps.techLog.started(appVersion: '0.1.0+90', android: '13');
    await _openSupport(tester, deps);
    expect(
      tester.widget<CheckboxListTile>(find.byKey(const Key('help.techlog'))).value,
      isFalse,
      reason: 'décoché par défaut',
    );
    await tester.tap(find.byKey(const Key('help.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.reports.single['techLog'], isNull);

    await _scrollTap(tester, find.byKey(const Key('help.contact')));
    await tester.enterText(find.byKey(const Key('help.message')), 'Toujours le même souci');
    await tester.tap(find.byKey(const Key('help.techlog.show')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Démarrage · Privio 0.1.0+90'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('help.techlog')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('help.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.reports.last['techLog'], contains('Démarrage · Privio 0.1.0+90'));
    expect(deps.messaging.reports.last['details'], 'Toujours le même souci');
    await tester.pump(const Duration(milliseconds: 400));
  });
}
