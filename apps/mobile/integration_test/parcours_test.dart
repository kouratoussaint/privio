import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:privio/core/config/env.dart';

import 'support/appareil.dart';
import 'support/parcours.dart';

/// Lot 6.1 (ADR-055) : parcours complet sur émulateur Android (7 et 14), à chaque
/// version, contre le serveur local de la CI. Les appels restent testés sur téléphone.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('inscription, demande, message, photo, vocal, effacement, groupe, verrouillage', (
    tester,
  ) async {
    // Clavier simulé (le clavier réel ne reçoit pas les saisies du test, surtout en
    // mode « profile » où les vérifications de débogage sont absentes).
    tester.testTextInput.register();
    await parcoursComplet(
      tester,
      overrides: await applicationSurEmulateur(),
      url: Env.supabaseUrl,
      cleApi: Env.supabasePublishableKey,
    );
  }, timeout: const Timeout(Duration(minutes: 15)));
}
