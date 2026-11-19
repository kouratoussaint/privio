import 'dart:io' show Platform;

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/services/account_api.dart';
import 'data/services/admin_api.dart';
import 'data/services/audio/audio_engine.dart';
import 'data/services/audio/voice_recorder.dart';
import 'data/services/auth_service.dart';
import 'data/services/call_system.dart';
import 'data/services/calls_api.dart';
import 'data/services/device_services.dart';
import 'data/services/group_calls_api.dart';
import 'data/services/messaging_api.dart';
import 'data/services/photo_picker.dart';
import 'data/services/push_service.dart';
import 'data/services/realtime_service.dart';
import 'data/storage/app_lock_store.dart';
import 'data/storage/local_flags.dart';
import 'data/storage/local_store.dart';
import 'data/storage/media_vault.dart';
import 'state/app_lock_providers.dart';
import 'state/call_controller.dart';
import 'state/console_providers.dart';
import 'state/data_providers.dart';
import 'state/messaging_providers.dart';
import 'state/providers.dart';
import 'state/push_providers.dart';
import 'state/group_call_controller.dart';

/// Lot 6.1 : branchements de production, en deux parties pour les parcours complets
/// sur émulateur (vrai serveur local, vrais services) qui ne remplacent que le
/// matériel : appareil photo, micro, notifications.

/// Services du serveur (Supabase).
List<Override> privioServerOverrides(SupabaseClient client) => [
  authServiceProvider.overrideWithValue(SupabaseAuthService(client.auth)),
  accountApiProvider.overrideWithValue(SupabaseAccountApi(client)),
  messagingApiProvider.overrideWithValue(SupabaseMessagingApi(client)),
  callsApiProvider.overrideWithValue(SupabaseCallsApi(client)),
  groupCallsApiProvider.overrideWithValue(SupabaseGroupCallsApi(client)),
  adminApiProvider.overrideWithValue(SupabaseAdminApi(client)),
  realtimeServiceProvider.overrideWithValue(SupabaseRealtimeService(client)),
];

/// Services du téléphone.
List<Override> privioDeviceOverrides({
  PhotoPicker? photos,
  VoiceRecorder? recorder,
  PushService? push,
  CallSystem? callSystem,
}) => [
  localFlagsProvider.overrideWithValue(SharedPrefsLocalFlags()),
  localStoreProvider.overrideWithValue(EncryptedFileStore()),
  pushServiceProvider.overrideWithValue(push ?? FirebasePushService()),
  mediaVaultProvider.overrideWithValue(EncryptedMediaVault()),
  voiceRecorderProvider.overrideWithValue(recorder ?? DeviceVoiceRecorder()),
  audioEngineProvider.overrideWithValue(DeviceAudioEngine()),
  photoPickerProvider.overrideWithValue(photos ?? DevicePhotoPicker()),
  if (callSystem != null)
    callSystemProvider.overrideWithValue(callSystem)
  else if (Platform.isAndroid)
    callSystemProvider.overrideWithValue(DeviceCallSystem()),
  appLockStoreProvider.overrideWithValue(SecureAppLockStore()),
  biometricGateProvider.overrideWithValue(DeviceBiometricGate()),
  networkMonitorProvider.overrideWithValue(DeviceNetworkMonitor()),
];
