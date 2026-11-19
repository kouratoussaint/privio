import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/bootstrap.dart';
import 'package:privio/state/call_controller.dart';
import 'package:privio/state/console_providers.dart';
import 'package:privio/state/group_call_controller.dart';
import 'package:privio/state/messaging_providers.dart';
import 'package:privio/state/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../integration_test/support/vitesse.dart';
import '../test/helpers/fakes.dart';

/// Lot 6.1 : déroulé des mesures de vitesse sur l'ordinateur (sans seuils : les temps
/// n'ont de sens que sur l'émulateur). Prérequis : scripts/emulateur/preparer_mesure.py.
class _Reseau extends LiveTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _Reseau();
  final url = Platform.environment['SUPABASE_URL'] ?? 'http://127.0.0.1:54321';
  final cleApi = Platform.environment['SUPABASE_PUBLISHABLE_KEY'] ?? '';

  testWidgets('vitesse (ordinateur, serveur local)', (tester) async {
    final client = SupabaseClient(url, cleApi);
    final deps = TestDeps();
    final serveurs = {
      authServiceProvider,
      accountApiProvider,
      messagingApiProvider,
      callsApiProvider,
      groupCallsApiProvider,
      adminApiProvider,
      realtimeServiceProvider,
    };
    final appareils = deps.overrides.where((o) => !serveurs.contains((o as dynamic).origin));
    final m = await mesurerVitesse(
      tester,
      overrides: [...privioServerOverrides(client), ...appareils],
      depuisLancement: () async => -1,
    );
    debugPrint('Mesures (ordinateur) : $m');
    expect(m['ouverture_1000_ms'], isNotNull);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
