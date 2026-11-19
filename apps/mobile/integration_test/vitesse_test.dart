import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/appareil.dart';
import 'support/vitesse.dart';

/// Lot 6.1 (ADR-055) : mesures de vitesse sur un émulateur d'entrée de gamme (mode
/// « profile », comme une version publiée), seuils dans support/vitesse.dart.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('vitesse\u202F: démarrage, 300 discussions, discussion de 1 000 messages', (
    tester,
  ) async {
    final mesures = <String, Object>{};
    binding.reportData = {'mesures': mesures};
    // Les mesures sont publiées même si un seuil est dépassé.
    mesures.addAll(
      await mesurerVitesse(
        tester,
        overrides: await applicationSurEmulateur(),
        depuisLancement: () async =>
            await const MethodChannel('privio/device').invokeMethod<int>('sinceStart') ?? -1,
      ),
    );
    verifierSeuils(mesures);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
