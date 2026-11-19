import 'dart:io';

import 'package:flutter/widgets.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/bootstrap.dart';
import 'package:privio/state/console_providers.dart';
import 'package:privio/state/messaging_providers.dart';
import 'package:privio/state/providers.dart';
import 'package:privio/state/call_controller.dart';
import 'package:privio/state/group_call_controller.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../integration_test/support/fixtures.dart';
import '../integration_test/support/parcours.dart';
import '../test/helpers/fakes.dart';

/// Lot 6.1 : le parcours complet, exécuté sur l'ordinateur (sans émulateur) contre le
/// serveur local. Sert à mettre au point le parcours ; la CI le joue sur émulateur
/// (integration_test/parcours_test.dart). Usage :
///   SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_PUBLISHABLE_KEY=… \
///   flutter test test_parcours/parcours_hote_test.dart
class _Reseau extends LiveTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _Reseau();
  final url = Platform.environment['SUPABASE_URL'] ?? 'http://127.0.0.1:54321';
  final cleApi = Platform.environment['SUPABASE_PUBLISHABLE_KEY'] ?? '';

  testWidgets('parcours complet (ordinateur, serveur local)', (tester) async {
    // Fenêtre de test fixe (les coordonnées des touchers suivent la taille réelle).
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final client = SupabaseClient(url, cleApi);
    final deps = TestDeps();
    deps.recorder.audio = vocalTest;
    deps.photos.photo = photoTest;
    deps.push.available = false;
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
    await parcoursComplet(
      tester,
      overrides: [...privioServerOverrides(client), ...appareils],
      url: url,
      cleApi: cleApi,
    );
  }, timeout: const Timeout(Duration(minutes: 10)));
}
