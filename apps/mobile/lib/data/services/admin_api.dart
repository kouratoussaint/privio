import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/app_failure.dart';
import '../../domain/models/console.dart';
import '../../domain/models/moderation.dart';

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

  // Lot 5.3 : modération
  Future<List<ModerationReport>> reports(String status);
  Future<void> takeReports(List<String> ids);
  Future<ReportEvidence> evidence(String reportId);

  /// dismiss, warn, suspend (days : 1, 7, 30 ou null = sans limite), delete_message, close_group.
  Future<void> moderate(List<String> ids, String action, String note, {int? days});
  Future<void> liftSuspension(String userId, String note);
  Future<List<Sanction>> sanctions(String userId);
  Future<List<Sanction>> appeals();
  Future<void> answerAppeal(String sanctionId, {required bool lift, required String note});

  // Lot 5.4 : comptes et assistance
  /// @identifiant, nom, ou numéro (lot 5.6 : 4 chiffres au moins, n'importe où).
  Future<List<AccountHit>> searchAccounts(String query);

  /// Lot 5.5 : tous les comptes, par ordre alphabétique, page par page. Lot 5.6 : filtre
  /// (clé de [kAccountFilters], « all » par défaut).
  Future<ConsolePage<AccountHit>> accountsPage(int page, {int size = 25, String filter = 'all'});

  /// Lot 5.6 : retirer la photo, imposer un nouvel identifiant (renvoie l'identifiant
  /// provisoire), déconnecter un appareil précis, identifiants réservés.
  Future<void> removeAvatar(String userId, String note);
  Future<String> resetHandle(String userId, String note);
  Future<void> disconnectOneDevice(String userId, String deviceId, String note);
  Future<ReservedHandles> reservedHandles();
  Future<void> reserveHandle(String handle, {required bool reserved});

  /// Lot 5.5 : journal filtré par type d'action et par période (jours), page par page.
  Future<ConsolePage<JournalEntry>> journalPage({
    String? type,
    int? days,
    int page = 1,
    int size = 30,
  });
  Future<ConsoleAccount> account(String userId);

  /// warn ou suspend (days : 1, 7, 30 ou null = sans limite), sans signalement.
  Future<void> sanctionUser(
    String userId,
    String action, {
    required String reason,
    required String note,
    int? days,
  });
  Future<void> disconnectDevice(String userId, String note);
  Future<void> replySupport(String reportId, String reply);

  /// Lot 8.4a : vérification en deux étapes d'un compte ; réinitialisation (code oublié).
  Future<ConsoleTwoStep> twoStep(String userId);
  Future<void> resetTwoStep(String userId, String note);
}

/// Lot 8.4a : vérification en deux étapes vue par la console.
class ConsoleTwoStep {
  const ConsoleTwoStep({required this.enabled, this.resetRequestedAt});

  final bool enabled;
  final DateTime? resetRequestedAt;

  factory ConsoleTwoStep.fromJson(Map<String, dynamic> j) => ConsoleTwoStep(
    enabled: j['enabled'] as bool? ?? false,
    resetRequestedAt: j['reset_requested_at'] == null
        ? null
        : DateTime.parse(j['reset_requested_at'] as String),
  );
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
  Future<List<ModerationReport>> reports(String status) async => (await _rows('console_reports', {
    'p_status': status,
  })).map(ModerationReport.fromJson).toList();

  @override
  Future<void> takeReports(List<String> ids) =>
      _guard(() => _client.rpc<dynamic>('console_take_reports', params: {'p_ids': ids}));

  @override
  Future<ReportEvidence> evidence(String reportId) => _guard(() async {
    final res = await _client.rpc<dynamic>(
      'console_report_evidence',
      params: {'p_report_id': reportId},
    );
    return ReportEvidence.fromJson(Map<String, dynamic>.from(res as Map));
  });

  @override
  Future<void> moderate(List<String> ids, String action, String note, {int? days}) => _guard(
    () => _client.rpc<dynamic>(
      'console_moderate',
      params: {'p_report_ids': ids, 'p_action': action, 'p_note': note, 'p_days': days},
    ),
  );

  @override
  Future<void> liftSuspension(String userId, String note) => _guard(
    () => _client.rpc<dynamic>(
      'console_lift_suspension',
      params: {'p_user_id': userId, 'p_note': note},
    ),
  );

  @override
  Future<List<Sanction>> sanctions(String userId) async =>
      (await _rows('console_sanctions', {'p_user_id': userId})).map(Sanction.fromJson).toList();

  @override
  Future<List<Sanction>> appeals() async =>
      (await _rows('console_appeals')).map(Sanction.fromJson).toList();

  @override
  Future<void> answerAppeal(String sanctionId, {required bool lift, required String note}) =>
      _guard(
        () => _client.rpc<dynamic>(
          'console_answer_appeal',
          params: {'p_sanction_id': sanctionId, 'p_lift': lift, 'p_note': note},
        ),
      );

  @override
  Future<ConsolePage<AccountHit>> accountsPage(int page, {int size = 25, String filter = 'all'}) =>
      _guard(() async {
        final j = Map<String, dynamic>.from(
          await _client.rpc<dynamic>(
            'console_accounts_page',
            params: {'p_page': page, 'p_size': size, 'p_filter': filter},
          ) as Map,
        );
        return ConsolePage(
          total: (j['total'] as num).toInt(),
          page: (j['page'] as num).toInt(),
          size: (j['size'] as num).toInt(),
          rows: [
            for (final r in j['rows'] as List)
              AccountHit.fromJson(Map<String, dynamic>.from(r as Map)),
          ],
          letters: {
            for (final e in Map<String, dynamic>.from(j['letters'] as Map).entries)
              e.key: (e.value as num).toInt(),
          },
          counts: {
            for (final e in Map<String, dynamic>.from(j['counts'] as Map? ?? const {}).entries)
              e.key: (e.value as num).toInt(),
          },
        );
      });

  @override
  Future<void> removeAvatar(String userId, String note) => _guard(
    () => _client.rpc<dynamic>(
      'console_remove_avatar',
      params: {'p_user_id': userId, 'p_note': note},
    ),
  );

  @override
  Future<String> resetHandle(String userId, String note) => _guard(
    () async => await _client.rpc<dynamic>(
      'console_reset_handle',
      params: {'p_user_id': userId, 'p_note': note},
    ) as String,
  );

  @override
  Future<void> disconnectOneDevice(String userId, String deviceId, String note) => _guard(
    () => _client.rpc<dynamic>(
      'console_disconnect_device',
      params: {'p_user_id': userId, 'p_note': note, 'p_device_id': deviceId},
    ),
  );

  @override
  Future<ReservedHandles> reservedHandles() => _guard(
    () async => ReservedHandles.fromJson(
      Map<String, dynamic>.from(await _client.rpc<dynamic>('console_reserved_handles') as Map),
    ),
  );

  @override
  Future<void> reserveHandle(String handle, {required bool reserved}) => _guard(
    () => _client.rpc<dynamic>(
      'console_reserve_handle',
      params: {'p_handle': handle, 'p_reserved': reserved},
    ),
  );

  @override
  Future<ConsolePage<JournalEntry>> journalPage({
    String? type,
    int? days,
    int page = 1,
    int size = 30,
  }) => _guard(() async {
    final j = Map<String, dynamic>.from(
      await _client.rpc<dynamic>(
        'console_journal_page',
        params: {'p_type': type, 'p_days': days, 'p_page': page, 'p_size': size},
      ) as Map,
    );
    return ConsolePage(
      total: (j['total'] as num).toInt(),
      page: (j['page'] as num).toInt(),
      size: (j['size'] as num).toInt(),
      rows: [
        for (final r in j['rows'] as List)
          JournalEntry.fromJson(Map<String, dynamic>.from(r as Map)),
      ],
    );
  });

  @override
  Future<List<AccountHit>> searchAccounts(String query) async => (await _rows(
    'console_search_accounts',
    {'p_query': query},
  )).map(AccountHit.fromJson).toList();

  @override
  Future<ConsoleAccount> account(String userId) => _guard(() async {
    final res = await _client.rpc<dynamic>('console_account', params: {'p_user_id': userId});
    return ConsoleAccount.fromJson(Map<String, dynamic>.from(res as Map));
  });

  @override
  Future<void> sanctionUser(
    String userId,
    String action, {
    required String reason,
    required String note,
    int? days,
  }) => _guard(
    () => _client.rpc<dynamic>(
      'console_sanction_user',
      params: {
        'p_user_id': userId,
        'p_action': action,
        'p_reason': reason,
        'p_note': note,
        'p_days': days,
      },
    ),
  );

  @override
  Future<ConsoleTwoStep> twoStep(String userId) => _guard(
    () async => ConsoleTwoStep.fromJson(
      Map<String, dynamic>.from(
        await _client.rpc<dynamic>('console_two_step', params: {'p_user_id': userId}) as Map,
      ),
    ),
  );

  @override
  Future<void> resetTwoStep(String userId, String note) => _guard(
    () => _client.rpc<dynamic>(
      'console_reset_two_step',
      params: {'p_user_id': userId, 'p_note': note},
    ),
  );

  @override
  Future<void> disconnectDevice(String userId, String note) => _guard(
    () => _client.rpc<dynamic>(
      'console_disconnect_device',
      params: {'p_user_id': userId, 'p_note': note},
    ),
  );

  @override
  Future<void> replySupport(String reportId, String reply) => _guard(
    () => _client.rpc<dynamic>(
      'console_reply_support',
      params: {'p_report_id': reportId, 'p_reply': reply},
    ),
  );

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
