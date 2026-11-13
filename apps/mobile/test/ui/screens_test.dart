import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/ui/features/auth/otp_screen.dart';
import 'package:privio/ui/features/auth/phone_screen.dart';
import 'package:privio/ui/features/onboarding/onboarding_screen.dart';
import 'package:privio/ui/features/profile_setup/profile_setup_screen.dart';

import '../helpers/fakes.dart';

void main() {
  testWidgets(
    'onboarding\u202F: «\u202FContinuer\u202F» exige le consentement, aucune promesse E2EE',
    (tester) async {
      final deps = TestDeps();
      await tester.pumpWidget(deps.wrap(const OnboardingScreen()));
      final button = find.byKey(const Key('onboarding.continue'));
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.ensureVisible(find.byKey(const Key('onboarding.consent')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('onboarding.consent')));
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);

      final allText = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join(' ');
      expect(allText.toLowerCase(), isNot(contains('bout en bout')));
      expect(allText, contains('72 heures'));
    },
  );

  testWidgets('numéro invalide\u202F: erreur, aucun SMS demandé', (tester) async {
    final deps = TestDeps();
    await tester.pumpWidget(deps.wrap(const PhoneScreen()));
    await tester.enterText(find.byKey(const Key('phone.input')), '1234');
    await tester.tap(find.byKey(const Key('phone.submit')));
    await tester.pump();
    expect(find.textContaining('Numéro incomplet'), findsOneWidget);
    expect(deps.auth.otpRequests, isEmpty);
  });

  testWidgets('numéro burkinabè à 8 chiffres → OTP demandé en +226', (tester) async {
    final deps = TestDeps();
    await tester.pumpWidget(deps.wrap(const PhoneScreen()));
    await tester.enterText(find.byKey(const Key('phone.input')), '70 00 00 01');
    await tester.tap(find.byKey(const Key('phone.submit')));
    await tester.pump();
    expect(deps.auth.otpRequests, ['+22670000001']);
  });

  testWidgets('OTP\u202F: renvoi bloqué 60 s, code faux signalé', (tester) async {
    final deps = TestDeps();
    await tester.pumpWidget(deps.wrap(const OtpScreen(phoneE164: '+22670000001')));
    expect(find.text('Renvoyer le code dans 60 s'), findsOneWidget);
    expect(find.byKey(const Key('otp.help')), findsNothing);
    await tester.tap(find.byKey(const Key('otp.resend')));
    expect(deps.auth.otpRequests, isEmpty);

    await tester.enterText(find.byKey(const Key('otp.input')), '000000');
    await tester.pump();
    expect(
      find.text('Ce code ne fonctionne pas. Vérifiez-le ou demandez-en un nouveau.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 60));
    expect(find.text('Renvoyer le code'), findsOneWidget);
    // Lot 4.4 : aide quand le SMS n'arrive pas, seulement quand on peut renvoyer.
    expect(find.byKey(const Key('otp.help')), findsOneWidget);
    await tester.tap(find.byKey(const Key('otp.resend')));
    await tester.pump();
    expect(deps.auth.otpRequests, ['+22670000001']);
    await tester.pump(const Duration(seconds: 61));
  });

  testWidgets('profil\u202F: identifiant invalide puis identifiant pris', (tester) async {
    final deps = TestDeps();
    await tester.pumpWidget(deps.wrap(const ProfileSetupScreen()));
    await tester.enterText(find.byKey(const Key('profile.handle')), 'ab');
    await tester.pump();
    expect(find.text('Au moins 3 caractères.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('profile.handle')), 'Alice_BF');
    await tester.pump(ProfileSetupScreen.availabilityDebounce);
    await tester.pump();
    expect(find.textContaining('déjà pris'), findsOneWidget);
  });
}
