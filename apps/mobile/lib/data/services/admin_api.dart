import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/console.dart';

/// Console d'administration (lot 5.1). Le serveur vérifie le droit d'accès à CHAQUE appel ;
/// l'application ne fait qu'afficher ou masquer l'entrée.
abstract interface class AdminApi {
  /// Vrai seulement pour le compte administrateur (jamais d'erreur).
  Future<bool> consoleAccess();

  /// Tableau de bord (nombres seulement) ; consultation journalisée par le serveur.
  Future<ConsoleDashboard> dashboard();
}

class SupabaseAdminApi implements AdminApi {
  SupabaseAdminApi(this._client);

  final SupabaseClient _client;

  @override
  Future<bool> consoleAccess() async {
    try {
      return await _client.rpc<dynamic>('console_access') == true;
    } on Object {
      return false;
    }
  }

  @override
  Future<ConsoleDashboard> dashboard() async {
    try {
      final res = await _client.rpc<dynamic>('console_dashboard');
      return ConsoleDashboard.fromJson(Map<String, dynamic>.from(res as Map));
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }
}
