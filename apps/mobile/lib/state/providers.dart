import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/env.dart';
import '../core/media/photo_processing.dart';
import '../data/services/account_api.dart';
import '../data/services/audio/audio_engine.dart';
import '../data/services/audio/voice_recorder.dart';
import '../data/services/auth_service.dart';
import '../data/services/permission_gateway.dart';
import '../data/services/photo_picker.dart';
import '../data/storage/local_cache.dart';
import '../data/storage/local_flags.dart';
import '../data/storage/local_store.dart';
import '../data/storage/media_vault.dart';

/// Dépendances injectées dans main.dart (implémentations réelles) ou dans les tests (faux).
final authServiceProvider = Provider<AuthService>(
  (ref) => throw UnimplementedError('authServiceProvider doit être surchargé'),
);
final accountApiProvider = Provider<AccountApi>(
  (ref) => throw UnimplementedError('accountApiProvider doit être surchargé'),
);
final localFlagsProvider = Provider<LocalFlags>(
  (ref) => throw UnimplementedError('localFlagsProvider doit être surchargé'),
);
final permissionGatewayProvider = Provider<PermissionGateway>(
  (ref) => const DevicePermissionGateway(),
);
final appVersionProvider = Provider<String>((ref) => Env.appVersion);

/// Lot 5.7 : ouvre un lien dans le navigateur du téléphone (remplacé dans les tests).
final openExternalUrlProvider = Provider<Future<bool> Function(Uri uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication).catchError((Object _) => false),
);

/// Stockage local chiffré (fichier AES-GCM en production, mémoire dans les tests).
final localStoreProvider = Provider<LocalStore>((ref) => MemoryLocalStore());

/// Coffre chiffré des sons (un fichier AES-GCM par son en production, mémoire en test).
final mediaVaultProvider = Provider<MediaVault>((ref) => MemoryMediaVault());

/// Cache local des discussions, messages et sons (purgé à expiration, même hors ligne).
final localCacheProvider = Provider<LocalCache>(
  (ref) => LocalCache(ref.watch(localStoreProvider), media: ref.watch(mediaVaultProvider)),
);

/// Micro et lecteur (implémentations Android dans main.dart, faux dans les tests).
final voiceRecorderProvider = Provider<VoiceRecorder>(
  (ref) => throw UnimplementedError('voiceRecorderProvider doit être surchargé'),
);
final audioEngineProvider = Provider<AudioEngine>(
  (ref) => throw UnimplementedError('audioEngineProvider doit être surchargé'),
);

/// Appareil photo et sélecteur de photos du système.
final photoPickerProvider = Provider<PhotoPicker>(
  (ref) => throw UnimplementedError('photoPickerProvider doit être surchargé'),
);

/// Préparation d'une photo (rotation, taille, JPEG sans métadonnées), hors du fil de
/// l'interface ; remplaçable dans les tests.
/// Lot 10.3 : [eco] → photo allégée (Mode éco).
typedef PhotoPreparer = Future<PreparedPhoto> Function(Uint8List raw, {bool avatar, bool eco});
final photoPreparerProvider = Provider<PhotoPreparer>(
  (ref) =>
      (raw, {avatar = false, eco = false}) =>
          avatar ? prepareAvatar(raw) : preparePhoto(raw, eco: eco),
);
