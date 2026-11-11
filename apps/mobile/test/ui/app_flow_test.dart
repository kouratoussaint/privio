import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';

import '../helpers/fakes.dart';

/// Parcours critique complet avec le vrai routeur et des services simulés :
/// onboarding → accueil → téléphone → OTP → profil → autorisations → discussions.
void main() {
  testWidgets('inscription par téléphone de bout en bout', (tester) async {
    final deps = TestDeps();
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();

    // 02 — engagements
    expect(find.text('Bienvenue sur Privio'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('onboarding.consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboarding.consent')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('onboarding.continue')));
    await tester.pumpAndSettle();

    // 03 — un seul choix, aucun e-mail ni mot de passe
    expect(find.byKey(const Key('welcome.phone')), findsOneWidget);
    expect(
      find.textContaining(RegExp('e-mail|email|mot de passe', caseSensitive: false)),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('welcome.phone')));
    await tester.pumpAndSettle();

    // 04 — numéro
    await tester.enterText(find.byKey(const Key('phone.input')), '70000001');
    await tester.tap(find.byKey(const Key('phone.submit')));
    await tester.pumpAndSettle();

    // 05 — OTP (validation automatique à 6 chiffres)
    expect(find.textContaining('+226 70 00 00 01'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('otp.input')), '123456');
    await tester.pumpAndSettle();
    expect(deps.api.registeredDevices, 1);

    // 06 — profil
    expect(find.text('Votre profil'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('profile.name')), 'Toussaint');
    await tester.enterText(find.byKey(const Key('profile.handle')), 'toussaint_bf');
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    await tester.tap(find.byKey(const Key('profile.submit')));
    await tester.pumpAndSettle();

    // 07 — autorisations facultatives
    await tester.tap(find.byKey(const Key('permissions.later')));
    await tester.pumpAndSettle();
    expect(deps.permissions.requests, 0);

    // 08 — trois onglets, aucune « communauté »
    expect(find.text('Aucune discussion pour l\'instant'), findsOneWidget);
    expect(find.text('Discussions'), findsOneWidget);
    expect(find.text('Groupes'), findsOneWidget);
    expect(find.text('Paramètres'), findsOneWidget);
    expect(find.textContaining(RegExp('communaut', caseSensitive: false)), findsNothing);

    // Paramètres : profil créé, découvrabilité désactivée par défaut
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    expect(find.text('Toussaint'), findsOneWidget);
    expect(find.textContaining('@toussaint_bf'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byKey(const Key('settings.discoverable'))).value,
      isFalse,
    );
  });
}
