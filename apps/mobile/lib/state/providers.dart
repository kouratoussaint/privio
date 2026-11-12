import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env.dart';
import '../data/services/account_api.dart';
import '../data/services/auth_service.dart';
import '../data/services/permission_gateway.dart';
import '../data/storage/local_cache.dart';
import '../data/storage/local_flags.dart';
import '../data/storage/local_store.dart';

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

/// Stockage local chiffré (fichier AES-GCM en production, mémoire dans les tests).
final localStoreProvider = Provider<LocalStore>((ref) => MemoryLocalStore());

/// Cache local des discussions et messages (purgé à expiration, même hors ligne).
final localCacheProvider = Provider<LocalCache>((ref) => LocalCache(ref.watch(localStoreProvider)));
