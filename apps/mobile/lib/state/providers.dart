import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env.dart';
import '../data/services/account_api.dart';
import '../data/services/auth_service.dart';
import '../data/services/permission_gateway.dart';
import '../data/storage/local_flags.dart';

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
