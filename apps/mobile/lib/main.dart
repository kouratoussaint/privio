import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'data/services/account_api.dart';
import 'data/services/audio/audio_engine.dart';
import 'data/services/audio/voice_recorder.dart';
import 'data/services/auth_service.dart';
import 'data/services/messaging_api.dart';
import 'data/services/push_service.dart';
import 'data/services/photo_picker.dart';
import 'data/services/realtime_service.dart';
import 'data/storage/local_flags.dart';
import 'data/storage/local_store.dart';
import 'data/storage/media_vault.dart';
import 'data/storage/secure_session_storage.dart';
import 'state/messaging_providers.dart';
import 'state/providers.dart';
import 'state/push_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(
      const ConfigErrorApp(
        reason:
            'Configuration absente : compilez avec --dart-define=SUPABASE_URL=… '
            'et --dart-define=SUPABASE_PUBLISHABLE_KEY=… (voir README).',
      ),
    );
    return;
  }
  if (Env.publishableKeyLooksSecret) {
    runApp(
      const ConfigErrorApp(
        reason:
            'Clé refusée : une clé SECRÈTE Supabase ne doit jamais être intégrée à '
            'l\'application. Utilisez la clé publique (publishable).',
      ),
    );
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
  );
  final client = Supabase.instance.client;

  runApp(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        authServiceProvider.overrideWithValue(SupabaseAuthService(client.auth)),
        accountApiProvider.overrideWithValue(SupabaseAccountApi(client)),
        localFlagsProvider.overrideWithValue(SharedPrefsLocalFlags()),
        localStoreProvider.overrideWithValue(EncryptedFileStore()),
        pushServiceProvider.overrideWithValue(FirebasePushService()),
        mediaVaultProvider.overrideWithValue(EncryptedMediaVault()),
        voiceRecorderProvider.overrideWithValue(DeviceVoiceRecorder()),
        audioEngineProvider.overrideWithValue(DeviceAudioEngine()),
        photoPickerProvider.overrideWithValue(DevicePhotoPicker()),
        messagingApiProvider.overrideWithValue(SupabaseMessagingApi(client)),
        realtimeServiceProvider.overrideWithValue(SupabaseRealtimeService(client)),
      ],
      child: const PrivioApp(),
    ),
  );
}
