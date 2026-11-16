import 'l10n/l10n.dart';

import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';
import 'data/services/account_api.dart';
import 'data/services/admin_api.dart';
import 'data/services/audio/audio_engine.dart';
import 'data/services/device_services.dart';
import 'data/services/audio/voice_recorder.dart';
import 'data/services/auth_service.dart';
import 'data/services/messaging_api.dart';
import 'data/services/push_service.dart';
import 'data/services/photo_picker.dart';
import 'data/services/realtime_service.dart';
import 'data/storage/app_lock_store.dart';
import 'data/storage/local_flags.dart';
import 'data/storage/local_store.dart';
import 'data/storage/media_vault.dart';
import 'data/storage/secure_session_storage.dart';
import 'state/app_lock_providers.dart';
import 'state/console_providers.dart';
import 'state/data_providers.dart';
import 'state/messaging_providers.dart';
import 'state/providers.dart';
import 'state/push_providers.dart';
import 'data/services/calls_api.dart';
import 'data/services/call_background.dart';
import 'data/services/call_system.dart';
import 'state/call_controller.dart';
import 'ui/core/emoji/big_emojis.dart';

import 'package:flutter/foundation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    runApp(ConfigErrorApp(reason: L.t.configurationAbsenteCompilezAvecDart));
    return;
  }
  if (Env.publishableKeyLooksSecret) {
    runApp(ConfigErrorApp(reason: L.t.cleRefuseeCleSecreteSupabase));
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
    authOptions: FlutterAuthClientOptions(localStorage: SecureSessionStorage()),
  );
  final client = Supabase.instance.client;

  // Lot 8.5b : crédit des émojis animés intégrés (licence CC BY 4.0).
  LicenseRegistry.addLicense(
    () => Stream.value(
      const LicenseEntryWithLineBreaks(['Noto Animated Emoji'], kNotoAnimatedEmojiCredit),
    ),
  );

  // Lot 9.1b : appels reçus Privio fermé (message de réveil, écran d'appel du téléphone).
  if (Platform.isAndroid) {
    FirebaseMessaging.onBackgroundMessage(privioBackgroundMessage);
    try {
      await FlutterCallkitIncoming.onBackgroundMessage(privioCallkitBackground);
    } on Object {
      // Sans écran d'appel du téléphone, les appels sonnent Privio ouvert.
    }
  }

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
        callsApiProvider.overrideWithValue(SupabaseCallsApi(client)),
        if (Platform.isAndroid) callSystemProvider.overrideWithValue(DeviceCallSystem()),
        adminApiProvider.overrideWithValue(SupabaseAdminApi(client)),
        realtimeServiceProvider.overrideWithValue(SupabaseRealtimeService(client)),
        appLockStoreProvider.overrideWithValue(SecureAppLockStore()),
        biometricGateProvider.overrideWithValue(DeviceBiometricGate()),
        networkMonitorProvider.overrideWithValue(DeviceNetworkMonitor()),
      ],
      child: const PrivioApp(),
    ),
  );
}
