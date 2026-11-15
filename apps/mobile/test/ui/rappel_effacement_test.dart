import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/util/time_format.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/settings_nav.dart';

/// Lot 8.4b — rappel avant effacement : compte à rebours mis en valeur 4 h avant
/// l'effacement d'un message de 12 h ou plus ; réglage (activé par défaut).
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

Future<void> _start(WidgetTester tester, TestDeps deps) async {
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('bientôt effacé : 4 h avant, messages de 12 h ou plus', () {
    final now = DateTime(2026, 11, 15, 12);
    DateTime ago(int h) => now.subtract(Duration(hours: h));
    DateTime inH(int h) => now.add(Duration(hours: h));
    expect(expiringSoon(ago(69), inH(3), now: now), isTrue, reason: '72 h, reste 3 h');
    expect(expiringSoon(ago(68), inH(4), now: now), isTrue, reason: 'reste 4 h pile');
    expect(expiringSoon(ago(67), inH(5), now: now), isFalse, reason: 'reste 5 h');
    expect(expiringSoon(ago(9), inH(3), now: now), isTrue, reason: '12 h, reste 3 h');
    expect(expiringSoon(ago(5), inH(1), now: now), isFalse, reason: 'durée 6 h : jamais');
    expect(expiringSoon(ago(73), ago(1), now: now), isFalse, reason: 'déjà effacé');
  });

  testWidgets('bulle : compte à rebours mis en valeur', (tester) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    final now = DateTime.now();
    final soon = deps.messaging.receive(
      'conv-bob',
      'Rendez-vous demain',
      sentAt: now.subtract(const Duration(hours: 69)),
      expiresAt: now.add(const Duration(hours: 3)),
    );
    final fresh = deps.messaging.receive('conv-bob', 'Tout récent');
    await _start(tester, deps);
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(Key('message.${soon.id}')),
        matching: find.byKey(const Key('bubble.soon')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(Key('message.${fresh.id}')),
        matching: find.byKey(const Key('bubble.soon')),
      ),
      findsNothing,
    );
    expect(find.bySemanticsLabel(RegExp('S’efface bientôt, dans')), findsOneWidget);
  });

  testWidgets('réglage « Rappel avant effacement », activé par défaut', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(
      find.descendant(of: find.byType(PrivioNavBar), matching: find.text('Paramètres')),
    );
    await tester.pumpAndSettle();
    await openSettingsEntry(tester, 'settings.notifications');
    final tile = find.byKey(const Key('settings.expiry_reminder'));
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(deps.api.expiryReminderOn, isFalse);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  });
}
