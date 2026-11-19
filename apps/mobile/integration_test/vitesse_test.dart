import 'dart:convert';

import 'package:flutter/foundation.dart';
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
    // Clavier simulé (le clavier réel ne reçoit pas les saisies du test, surtout en
    // mode « profile » où les vérifications de débogage sont absentes).
    tester.testTextInput.register();
    final mesures = <String, Object>{};
    binding.reportData = {'mesures': mesures};
    Future<int> depuisLancement() async =>
        await const MethodChannel('privio/device').invokeMethod<int>('sinceStart') ?? -1;
    // Étapes du démarrage : moteur et Dart prêts, puis initialisation de Privio.
    final dartPret = await depuisLancement();
    final overrides = await applicationSurEmulateur();
    final initialise = await depuisLancement();
    mesures['demarrage_dart_ms'] = dartPret;
    mesures['demarrage_initialise_ms'] = initialise;
    // Les mesures sont publiées même si un seuil est dépassé.
    await mesurerVitesse(
      tester,
      overrides: overrides,
      depuisLancement: depuisLancement,
      resultats: mesures,
    );
    // Aussi dans le journal : le pilote ne publie les données que si tout réussit.
    debugPrint('MESURES ${jsonEncode({'mesures': mesures})}');
    verifierSeuils(mesures);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
