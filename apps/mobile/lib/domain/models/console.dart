/// Tableau de bord de la console (lot 5.1) : des NOMBRES seulement, calculés par le
/// serveur. Aucun contenu, aucun nom, aucun numéro.
class ConsoleDashboard {
  const ConsoleDashboard({
    required this.generatedAt,
    this.countingSince,
    this.accountsTotal = 0,
    this.active24h = 0,
    this.active7d = 0,
    this.new7d = 0,
    this.messagesToday = 0,
    this.messages7d = 0,
    this.voice7d = 0,
    this.photos7d = 0,
    this.messagesLive = 0,
    this.groupsTotal = 0,
    this.groupsCreated7d = 0,
    this.invitationsPending = 0,
    this.invitations7d = 0,
    this.requestsPending = 0,
    this.requestsSent7d = 0,
    this.requestsAccepted7d = 0,
    this.requestsRefused7d = 0,
    this.pushSent24h = 0,
    this.pushFailed24h = 0,
    this.pushNotConfigured24h = 0,
    this.purgeMessages,
    this.purgeMedia,
    this.expiredWaiting = 0,
    this.filesWaiting = 0,
    this.storageVoiceBytes = 0,
    this.storagePhotoBytes = 0,
    this.reportsOpen = 0,
  });

  final DateTime generatedAt;

  /// Premier jour des compteurs d'activité (déploiement de la console).
  final DateTime? countingSince;

  final int accountsTotal;
  final int active24h;
  final int active7d;
  final int new7d;

  final int messagesToday;
  final int messages7d;
  final int voice7d;
  final int photos7d;

  /// Messages actuellement conservés (avant leur effacement à expiration).
  final int messagesLive;

  final int groupsTotal;
  final int groupsCreated7d;
  final int invitationsPending;
  final int invitations7d;

  final int requestsPending;
  final int requestsSent7d;
  final int requestsAccepted7d;
  final int requestsRefused7d;

  final int pushSent24h;
  final int pushFailed24h;
  final int pushNotConfigured24h;
  final CronRun? purgeMessages;
  final CronRun? purgeMedia;

  /// Messages expirés depuis plus de 5 min et pas encore effacés (doit rester à 0).
  final int expiredWaiting;

  /// Fichiers en attente d'effacement physique.
  final int filesWaiting;
  final int storageVoiceBytes;
  final int storagePhotoBytes;

  final int reportsOpen;

  static int _int(Map<String, dynamic>? m, String k) => (m?[k] as num?)?.toInt() ?? 0;

  factory ConsoleDashboard.fromJson(Map<String, dynamic> j) {
    Map<String, dynamic>? sec(String k) =>
        j[k] is Map ? Map<String, dynamic>.from(j[k] as Map) : null;
    final a = sec('accounts');
    final act = sec('activity');
    final g = sec('groups');
    final r = sec('requests');
    final h = sec('health');
    final rep = sec('reports');
    return ConsoleDashboard(
      generatedAt: DateTime.tryParse(j['generated_at'] as String? ?? '') ?? DateTime.now(),
      countingSince: DateTime.tryParse(j['counting_since'] as String? ?? ''),
      accountsTotal: _int(a, 'total'),
      active24h: _int(a, 'active_24h'),
      active7d: _int(a, 'active_7d'),
      new7d: _int(a, 'new_7d'),
      messagesToday: _int(act, 'messages_today'),
      messages7d: _int(act, 'messages_7d'),
      voice7d: _int(act, 'voice_7d'),
      photos7d: _int(act, 'photos_7d'),
      messagesLive: _int(act, 'messages_live'),
      groupsTotal: _int(g, 'total'),
      groupsCreated7d: _int(g, 'created_7d'),
      invitationsPending: _int(g, 'invitations_pending'),
      invitations7d: _int(g, 'invitations_7d'),
      requestsPending: _int(r, 'pending'),
      requestsSent7d: _int(r, 'sent_7d'),
      requestsAccepted7d: _int(r, 'accepted_7d'),
      requestsRefused7d: _int(r, 'refused_7d'),
      pushSent24h: _int(h, 'push_sent_24h'),
      pushFailed24h: _int(h, 'push_failed_24h'),
      pushNotConfigured24h: _int(h, 'push_not_configured_24h'),
      purgeMessages: CronRun.fromJson(h?['purge_messages_last']),
      purgeMedia: CronRun.fromJson(h?['purge_media_last']),
      expiredWaiting: _int(h, 'expired_waiting'),
      filesWaiting: _int(h, 'files_waiting'),
      storageVoiceBytes: _int(h, 'storage_voice_bytes'),
      storagePhotoBytes: _int(h, 'storage_photo_bytes'),
      reportsOpen: _int(rep, 'open'),
    );
  }
}

/// Dernier passage d'une tâche planifiée du serveur.
class CronRun {
  const CronRun({required this.at, required this.ok});

  final DateTime at;
  final bool ok;

  static CronRun? fromJson(Object? j) {
    if (j is! Map) return null;
    final at = DateTime.tryParse(j['at'] as String? ?? '');
    if (at == null) return null;
    return CronRun(at: at, ok: j['status'] == 'succeeded');
  }
}

/// « 0 o », « 820 Ko », « 12,4 Mo », « 1,2 Go » (unités de 1 024).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes o';
  const units = ['Ko', 'Mo', 'Go', 'To'];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final text = v >= 100 || i == 0
      ? v.round().toString()
      : v.toStringAsFixed(1).replaceAll('.', ',').replaceAll(',0', '');
  return '$text ${units[i]}';
}
