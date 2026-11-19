import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:privio/bootstrap.dart';
import 'package:privio/core/config/env.dart';
import 'package:privio/data/storage/secure_session_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../test/helpers/fakes.dart';
import 'fixtures.dart';

/// Lot 6.1 : l'application telle qu'elle démarre sur un téléphone (main.dart), contre le
/// serveur local de la CI (10.0.2.2 depuis l'émulateur), avec appareil photo, micro et
/// notifications remplacés.
Future<List<Override>> applicationSurEmulateur() async {
  if (!Env.isConfigured) {
    throw StateError('SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY manquent (--dart-define).');
  }
  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
  );
  final client = Supabase.instance.client;
  return [
    ...privioServerOverrides(client),
    ...privioDeviceOverrides(
      photos: FakePhotoPicker()..photo = photoTest,
      recorder: FakeVoiceRecorder()..audio = vocalTest,
      push: FakePushService()..available = false,
    ),
  ];
}
