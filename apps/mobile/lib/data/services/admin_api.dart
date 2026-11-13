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

  /// Lot 5.2 : réglages globaux (tous, y compris ceux fixés).
  Future<List<ConsolePolicy>> policies();

  /// Modifie un réglage ; le serveur valide (type, bornes, cadenas) et journalise.
  Future<Object?> setPolicy(String key, Object value);

  Future<List<PolicyChange>> policyHistory(String key);

  Future<ConsoleStats> stats();

  Future<List<JournalEntry>> journal();
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

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on Object catch (e) {
      throw toAppFailure(e);
    }
  }

  Future<List<Map<String, dynamic>>> _rows(String fn, [Map<String, dynamic>? params]) =>
      _guard(() async {
        final res = await _client.rpc<dynamic>(fn, params: params) as List<dynamic>;
        return [for (final r in res) Map<String, dynamic>.from(r as Map)];
      });

  @override
  Future<List<ConsolePolicy>> policies() async =>
      (await _rows('console_policies')).map(ConsolePolicy.fromJson).toList();

  @override
  Future<Object?> setPolicy(String key, Object value) => _guard(
    () => _client.rpc<dynamic>('console_set_policy', params: {'p_key': key, 'p_value': value}),
  );

  @override
  Future<List<PolicyChange>> policyHistory(String key) async => (await _rows(
    'console_policy_history',
    {'p_key': key, 'p_limit': 20},
  )).map(PolicyChange.fromJson).toList();

  @override
  Future<ConsoleStats> stats() => _guard(() async {
    final res = await _client.rpc<dynamic>('console_stats', params: {'p_days': 30});
    return ConsoleStats.fromJson(Map<String, dynamic>.from(res as Map));
  });

  @override
  Future<List<JournalEntry>> journal() async =>
      (await _rows('console_journal', {'p_limit': 200})).map(JournalEntry.fromJson).toList();

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
