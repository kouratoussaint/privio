import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/settings_nav.dart';

/// Lot 8.4a — vérification en deux étapes : réglage, code après le SMS sur un nouveau
/// téléphone, code oublié, changement de numéro protégé, invitation dans Discussions.
const _pin = '258014';

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

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin.$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Finder _tab(String l) => find.descendant(of: find.byType(PrivioNavBar), matching: find.text(l));

Future<void> _openTwoStep(WidgetTester tester) async {
  await tester.tap(_tab('Paramètres'));
  await tester.pumpAndSettle();
  await openSettingsEntry(tester, 'settings.security');
  await tester.tap(find.byKey(const Key('security.two_step')));
  await tester.pumpAndSettle();
}

String _message(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('pin.message'))).data ?? '';

void main() {
  testWidgets('activer : code trop simple, codes différents, puis activé', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await _openTwoStep(tester);
    expect(find.text('Désactivée'), findsOneWidget);
    await tester.tap(find.byKey(const Key('two_step.enable')));
    await tester.pumpAndSettle();
    await _type(tester, '123456');
    expect(_message(tester), contains('trop simple'));
    await _type(tester, _pin);
    await _type(tester, '258015');
    expect(_message(tester), contains('ne correspondent pas'));
    await _type(tester, _pin);
    await _type(tester, _pin);
    expect(deps.api.twoStepPin, _pin);
    expect(find.text('Vérification en deux étapes activée.'), findsOneWidget);
    expect(find.text('Activée'), findsOneWidget);

    // Changer le code, puis désactiver (mauvais code d'abord).
    await tester.tap(find.byKey(const Key('two_step.change')));
    await tester.pumpAndSettle();
    await _type(tester, _pin);
    await _type(tester, '470258');
    await _type(tester, '470258');
    expect(deps.api.twoStepPin, '470258');
    expect(find.text('Code de sécurité modifié.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('two_step.disable')));
    await tester.pumpAndSettle();
    await _type(tester, _pin);
    expect(_message(tester), 'Code incorrect.');
    await _type(tester, '470258');
    expect(deps.api.twoStepPin, isNull);
    expect(find.text('Désactivée'), findsOneWidget);
  });

  testWidgets('nouveau téléphone : code demandé après le SMS, puis Privio s’ouvre', (tester) async {
    final deps = _deps()..api.newSessionPending(_pin);
    await _start(tester, deps);
    expect(find.byKey(const Key('two_step.intro')), findsOneWidget);
    expect(find.byType(PrivioNavBar), findsNothing, reason: 'aucun accès en attendant');
    await _type(tester, '000111');
    expect(_message(tester), 'Code incorrect.');
    expect(deps.api.registeredDevices, 0, reason: 'l’autre téléphone reste connecté');
    await _type(tester, _pin);
    expect(deps.api.registeredDevices, 1);
    expect(find.byType(PrivioNavBar), findsOneWidget);
  });

  testWidgets('trop d’essais : attente affichée', (tester) async {
    final deps = _deps()..api.newSessionPending(_pin);
    await _start(tester, deps);
    for (var i = 0; i < 5; i++) {
      await _type(tester, '00011$i');
    }
    expect(_message(tester), startsWith('Trop d’essais'));
  });

  testWidgets('code oublié : demande à l’assistance, puis réinitialisé', (tester) async {
    final deps = _deps()..api.newSessionPending(_pin);
    await _start(tester, deps);
    await tester.ensureVisible(find.byKey(const Key('two_step.forgot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('two_step.forgot')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('two_step.reset.confirm')));
    await tester.pumpAndSettle();
    expect(deps.api.twoStepResetAt, isNotNull);
    expect(find.byKey(const Key('two_step.reset.sent')), findsOneWidget);
    // L'assistance désactive la vérification (console).
    deps.api.twoStepPin = null;
    await tester.ensureVisible(find.byKey(const Key('two_step.refresh')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('two_step.refresh')));
    await tester.pumpAndSettle();
    expect(find.byType(PrivioNavBar), findsOneWidget);
    expect(deps.api.registeredDevices, 1);
  });

  testWidgets('se connecter avec un autre numéro', (tester) async {
    final deps = _deps()..api.newSessionPending(_pin);
    await _start(tester, deps);
    await tester.ensureVisible(find.byKey(const Key('two_step.signout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('two_step.signout')));
    await tester.pumpAndSettle();
    expect(deps.auth.hasSession, isFalse);
  });

  testWidgets('changer de numéro : code de sécurité demandé', (tester) async {
    final deps = _deps()..api.twoStepPin = _pin;
    await _start(tester, deps);
    await tester.tap(_tab('Paramètres'));
    await tester.pumpAndSettle();
    await openSettingsEntry(tester, 'settings.security');
    await tester.tap(find.byKey(const Key('security.phone')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('phone_change.input')), '70000005');
    await tester.tap(find.byKey(const Key('phone_change.send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('saisissez votre code de sécurité'), findsOneWidget);
    await _type(tester, '000111');
    expect(_message(tester), 'Code incorrect.');
    expect(find.byKey(const Key('phone_change.code')), findsNothing);
    await _type(tester, _pin);
    expect(deps.api.phoneChangeAuthorized, isTrue);
    expect(find.byKey(const Key('phone_change.code')), findsOneWidget, reason: 'SMS envoyé');
  });

  testWidgets('Discussions : invitation « Protégez votre compte »', (tester) async {
    final deps = _deps()..flags.twoStepPromptClosed = false;
    await _start(tester, deps);
    expect(find.byKey(const Key('two_step.prompt')), findsOneWidget);
    await tester.tap(find.byKey(const Key('two_step.prompt.enable')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('two_step.enable')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('two_step.prompt.later')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('two_step.prompt')), findsNothing);
    expect(deps.flags.twoStepPromptClosed, isTrue);
  });
}
