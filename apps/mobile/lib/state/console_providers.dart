import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/admin_api.dart';
import '../domain/models/console.dart';
import 'messaging_providers.dart';

final adminApiProvider = Provider<AdminApi>(
  (ref) => throw UnimplementedError('adminApiProvider doit être surchargé'),
);

/// Afficher l'entrée « Administration » (Paramètres) : réponse du serveur, recalculée au
/// changement de compte. Aucune condition locale (numéro, etc.) dans l'application.
final consoleAccessProvider = FutureProvider<bool>((ref) async {
  if (ref.watch(currentUserIdProvider) == null) return false;
  return ref.watch(adminApiProvider).consoleAccess();
});

final consoleDashboardProvider = FutureProvider.autoDispose<ConsoleDashboard>(
  (ref) => ref.watch(adminApiProvider).dashboard(),
);
