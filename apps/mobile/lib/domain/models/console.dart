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

// ---------------------------------------------------------------------------
// Lot 5.2 : réglages, statistiques, journal
// ---------------------------------------------------------------------------

/// Thèmes des réglages, dans l'ordre d'affichage.
const kPolicyCategories = <String, String>{
  'messages': 'Messages',
  'media': 'Médias',
  'groups': 'Groupes',
  'requests': 'Demandes de connexion',
  'abuse': 'Anti-abus',
  'retention': 'Conservation',
  'advanced': 'Avancé',
  'locked': 'Fixés (sécurité)',
  'future': 'Pas encore développés',
};

/// Un réglage global du serveur, tel que la console l'affiche.
class ConsolePolicy {
  const ConsolePolicy({
    required this.key,
    required this.category,
    required this.label,
    required this.unit,
    required this.valueType,
    required this.value,
    required this.defaultValue,
    this.min,
    this.max,
    this.locked = false,
    this.advanced = false,
    this.sortOrder = 0,
    this.effect,
    this.clientVisible = false,
    this.updatedAt,
  });

  final String key;
  final String category;
  final String label;

  /// min, h, j, s, o (octets), px, car (caractères), nb (nombre), bool, text.
  final String unit;
  final String valueType;
  final Object? value;
  final Object? defaultValue;
  final int? min;
  final int? max;
  final bool locked;
  final bool advanced;
  final int sortOrder;
  final String? effect;
  final bool clientVisible;
  final DateTime? updatedAt;

  bool get isBool => valueType == 'boolean';
  bool get isInt => valueType == 'integer';
  bool get isDefault => value == defaultValue;

  /// Effet affiché avant confirmation.
  String get effectText =>
      effect ??
      (clientVisible
          ? 'Appliqué tout de suite par le serveur\u202F; les téléphones le prennent en compte au '
                'prochain retour dans l’application.'
          : 'Appliqué tout de suite par le serveur.');

  /// Pas des boutons − et + : 1, sauf pour les octets (16 Ko) et les pixels (64).
  int get step => switch (unit) {
    'o' => 16384,
    'px' => 64,
    _ => 1,
  };

  String format(Object? v) => formatPolicyValue(unit, v);

  factory ConsolePolicy.fromJson(Map<String, dynamic> j) => ConsolePolicy(
    key: j['key'] as String,
    category: j['category'] as String? ?? 'advanced',
    label: j['label'] as String? ?? j['key'] as String,
    unit: j['unit'] as String? ?? 'nb',
    valueType: j['value_type'] as String? ?? 'integer',
    value: _plain(j['value']),
    defaultValue: _plain(j['default_value']),
    min: (j['min_value'] as num?)?.toInt(),
    max: (j['max_value'] as num?)?.toInt(),
    locked: j['locked'] as bool? ?? false,
    advanced: j['advanced'] as bool? ?? false,
    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
    effect: j['effect'] as String?,
    clientVisible: j['client_visible'] as bool? ?? false,
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? ''),
  );
}

/// Les nombres JSON arrivent parfois en double (5.0) : on garde des entiers.
Object? _plain(Object? v) => v is num && v == v.roundToDouble() ? v.toInt() : v;

/// « 4 000 » avec espaces fines (milliers).
String formatThousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return b.toString();
}

/// Valeur d'un réglage avec son unité : « 60 min », « 24 h », « 7 j », « 512 Ko »…
String formatPolicyValue(String unit, Object? v) {
  if (v == null) return '—';
  if (v is bool) return v ? 'Oui' : 'Non';
  if (v is String) return v;
  final n = (v as num).toInt();
  return switch (unit) {
    'min' => '${formatThousands(n)} min',
    'h' => '$n h',
    'j' => n > 1 ? '$n jours' : '$n jour',
    's' => '$n s',
    'o' => formatBytes(n),
    'px' => '${formatThousands(n)} px',
    'car' => '${formatThousands(n)} caractères',
    // Lot 5.7 : numéro de compilation (0 : aucune) et prix en FCFA.
    'build' => n == 0 ? 'Aucune' : 'n° $n',
    'fcfa' => '${formatThousands(n)} FCFA',
    _ => formatThousands(n),
  };
}

/// Un changement de réglage (historique).
class PolicyChange {
  const PolicyChange({
    required this.key,
    required this.label,
    required this.after,
    required this.at,
    this.before,
    this.byConsole = true,
  });

  final String key;
  final String label;
  final Object? before;
  final Object? after;
  final bool byConsole;
  final DateTime at;

  factory PolicyChange.fromJson(Map<String, dynamic> j) => PolicyChange(
    key: j['key'] as String,
    label: j['label'] as String? ?? j['key'] as String,
    before: _plain(j['before']),
    after: _plain(j['after']),
    byConsole: j['by_console'] as bool? ?? true,
    at: DateTime.parse(j['created_at'] as String),
  );
}

/// Une journée de statistiques (nombres seulement).
class StatDay {
  const StatDay({
    required this.day,
    this.text = 0,
    this.voice = 0,
    this.photo = 0,
    this.active,
    this.newAccounts = 0,
    this.requests = 0,
    this.accepted = 0,
    this.refused = 0,
    this.pushSent = 0,
    this.pushFailed = 0,
  });

  final DateTime day;
  final int text;
  final int voice;
  final int photo;

  /// Comptes actifs (relevé du soir) ; null avant le premier relevé.
  final int? active;
  final int newAccounts;
  final int requests;
  final int accepted;
  final int refused;
  final int pushSent;
  final int pushFailed;

  int get messages => text + voice + photo;

  factory StatDay.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return StatDay(
      day: DateTime.parse(j['day'] as String),
      text: n('text'),
      voice: n('voice'),
      photo: n('photo'),
      active: (j['active'] as num?)?.toInt(),
      newAccounts: n('new_accounts'),
      requests: n('requests'),
      accepted: n('accepted'),
      refused: n('refused'),
      pushSent: n('push_sent'),
      pushFailed: n('push_failed'),
    );
  }
}

class ConsoleStats {
  const ConsoleStats({required this.days, this.versions = const [], this.countingSince});

  final List<StatDay> days;

  /// (version, téléphones actifs), de la plus répandue à la moins répandue.
  final List<(String, int)> versions;
  final DateTime? countingSince;

  int sum(int Function(StatDay d) f) => days.fold(0, (a, d) => a + f(d));

  factory ConsoleStats.fromJson(Map<String, dynamic> j) => ConsoleStats(
    days: [
      for (final d in (j['days'] as List? ?? const []))
        StatDay.fromJson(Map<String, dynamic>.from(d as Map)),
    ],
    versions: [
      for (final v in (j['versions'] as List? ?? const []))
        ((v as Map)['version'] as String, (v['devices'] as num).toInt()),
    ],
    countingSince: DateTime.tryParse(j['counting_since'] as String? ?? ''),
  );
}

/// Une entrée du journal de la console.
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.action,
    required this.at,
    this.key,
    this.label,
    this.before,
    this.after,
    this.detail = const {},
    this.by,
    this.byRole,
  });

  final int id;

  /// Lot 5.8 : qui a agi (nom) et son rôle (owner, moderator, support).
  final String? by;
  final String? byRole;

  /// Détail brut (modération : action, @identifiant, durée…).
  final Map<String, dynamic> detail;

  /// dashboard, stats, policy, moderation, evidence, lift, appeal.
  final String action;
  final DateTime at;
  final String? key;
  final String? label;
  final Object? before;
  final Object? after;

  factory JournalEntry.fromJson(Map<String, dynamic> j) => JournalEntry(
    id: (j['id'] as num).toInt(),
    action: j['action'] as String,
    at: DateTime.parse(j['created_at'] as String),
    key: j['key'] as String?,
    label: j['label'] as String?,
    before: _plain(j['before']),
    after: _plain(j['after']),
    detail: j['detail'] is Map ? Map<String, dynamic>.from(j['detail'] as Map) : const {},
    by: j['by'] as String?,
    byRole: j['by_role'] as String?,
  );
}

// ---------------------------------------------------------------------------
// Lot 5.5 : comptes A–Z paginés, journal filtrable
// ---------------------------------------------------------------------------

/// Types d'action du journal (filtre), dans l'ordre d'affichage.
const kJournalTypes = <String, String>{
  'accounts': 'Comptes',
  'reports': 'Signalements',
  'settings': 'Fonctionnalités et réglages',
  'security': 'Sécurité',
  'support': 'Assistance',
  'groups': 'Groupes',
  'team': 'Équipe',
  'views': 'Consultations',
};

/// Même classement que le serveur (`private.journal_type`).
String journalTypeOf(String action) => switch (action) {
  'account' ||
  'account_search' ||
  'account_list' ||
  'lift' ||
  'avatar_remove' ||
  'handle_reset' => 'accounts',
  'moderation' || 'evidence' || 'appeal' => 'reports',
  'group_close' || 'group_reopen' || 'group_delete' => 'groups',
  'policy' || 'reserved_handle' || 'template' || 'site' => 'settings',
  'two_step_reset' || 'disconnect' => 'security',
  'team_add' || 'team_role' || 'team_remove' => 'team',
  'reply' => 'support',
  _ => 'views',
};

/// Lot 5.6 : filtres de la liste des comptes (clé serveur → libellé), dans l'ordre.
const kAccountFilters = <String, String>{
  'all': 'Tous',
  'suspended': 'Suspendus',
  'deleted': 'Supprimés',
  'new': 'Nouveaux (7 j)',
  'inactive': 'Inactifs (30 j)',
  'two_step': 'Deux étapes',
};

/// Lot 5.6 : identifiants réservés (mots toujours réservés + ajoutés depuis la console).
class ReservedHandles {
  const ReservedHandles({this.base = const [], this.added = const []});

  final List<String> base;
  final List<ReservedHandle> added;

  factory ReservedHandles.fromJson(Map<String, dynamic> j) => ReservedHandles(
    base: [for (final h in (j['base'] as List? ?? const [])) h as String],
    added: [
      for (final r in (j['added'] as List? ?? const []))
        ReservedHandle.fromJson(Map<String, dynamic>.from(r as Map)),
    ],
  );
}

class ReservedHandle {
  const ReservedHandle({required this.handle, required this.createdAt, this.inUse = false});

  final String handle;
  final DateTime createdAt;

  /// Déjà porté par un compte (la réservation ne le lui retire pas).
  final bool inUse;

  factory ReservedHandle.fromJson(Map<String, dynamic> j) => ReservedHandle(
    handle: j['handle'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    inUse: j['in_use'] as bool? ?? false,
  );
}

/// Page d'une liste paginée.
class ConsolePage<T> {
  const ConsolePage({
    required this.total,
    required this.page,
    required this.size,
    required this.rows,
    this.letters = const {},
    this.counts = const {},
  });

  final int total;
  final int page;
  final int size;
  final List<T> rows;

  /// Comptes : première position (0…) de chaque initiale (A–Z, « # » pour le reste).
  final Map<String, int> letters;

  /// Lot 5.6 : comptes, nombre par filtre (« all », « suspended »…).
  final Map<String, int> counts;

  int get pages => total == 0 ? 1 : (total + size - 1) ~/ size;

  /// Page où commence l'initiale [letter].
  int? pageOf(String letter) {
    final pos = letters[letter];
    return pos == null ? null : pos ~/ size + 1;
  }
}

// ---------------------------------------------------------------------------
// Lot 5.7 : santé du service
// ---------------------------------------------------------------------------

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

Map<String, dynamic> _m(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

/// Une version installée sur les téléphones actifs (30 jours).
class InstalledVersion {
  const InstalledVersion({required this.version, required this.devices, this.build});

  final String version;
  final int? build;
  final int devices;
}

/// Une tâche automatique du serveur (pg_cron) : effacements, rappels, alertes…
class CronJob {
  const CronJob({required this.job, required this.schedule, this.lastRun, this.active = true});

  final String job;
  final String schedule;
  final CronRun? lastRun;
  final bool active;

  /// Libellé lisible (« privio_purge_expired » → « Effacement des messages »).
  String get label => kCronLabels[job] ?? job.replaceFirst('privio_', '').replaceAll('_', ' ');

  /// En retard : une tâche de chaque minute ou toutes les 10 minutes qui n'a pas tourné
  /// depuis plus de 15 minutes, ou dont le dernier passage a échoué.
  bool late(DateTime now) {
    if (lastRun case final r? when !r.ok) return true;
    final frequent = schedule.startsWith('* ') || schedule.startsWith('*/');
    if (!frequent || !active) return false;
    final r = lastRun;
    return r == null || now.difference(r.at) > const Duration(minutes: 15);
  }
}

const kCronLabels = <String, String>{
  'privio_purge_expired': 'Effacement des messages',
  'privio_media_purge': 'Effacement des fichiers',
  'privio_read_erasures': 'Effacer après lecture',
  'privio_expire_calls': 'Fin des appels sans réponse',
  'privio_expiry_reminders': 'Rappels avant effacement',
  'privio_health_alerts': 'Alertes de l’administration',
  'privio_purge_connection_requests': 'Demandes de connexion expirées',
  'privio_purge_push_log': 'Journal des notifications',
  'privio_purge_console': 'Journal de la console',
  'privio_purge_health': 'Alertes et codes anciens',
  'privio_snapshot_active_users': 'Relevé des comptes actifs',
  'privio_purge_join_requests': 'Demandes d’adhésion',
  'privio_purge_group_notices': 'Avis de groupes supprimés',
  'privio_purge_receipt_marks': 'Accusés anciens',
};

/// Une alerte envoyée à l'administration.
class HealthAlert {
  const HealthAlert({required this.kind, required this.at, this.detail = const {}});

  final String kind;
  final DateTime at;
  final Map<String, dynamic> detail;

  String get title => switch (kind) {
    'purge' => 'Effacement automatique en retard',
    'sms' => 'Pic de codes SMS',
    'failures' => 'Échecs de notifications ou d’appels',
    'relay' => 'Relais des appels à 80 %',
    _ => kind,
  };

  String get text => switch (kind) {
    'purge' =>
      '${_i(detail['expired_waiting'])} message(s) expiré(s) en attente'
          '${detail['late_minutes'] == null ? '' : ' · dernier passage il y a ${_i(detail['late_minutes'])} min'}',
    'sms' => '${_i(detail['codes_hour'])} codes en une heure (seuil ${_i(detail['threshold'])})',
    'failures' =>
      'Notifications\u202F: ${_i(detail['push_failed'])} échecs sur ${_i(detail['push_total'])} (1 h) · '
          'appels\u202F: ${_i(detail['calls_failed'])} sur ${_i(detail['calls_total'])} (24 h)',
    'relay' => '${formatBytes(_i(detail['bytes']))} ce mois-ci',
    _ => '',
  };
}

/// Résultat de la dernière notification de test.
class PushTestResult {
  const PushTestResult({required this.at, this.status, this.sent = 0, this.failed = 0});

  final DateTime at;

  /// null : pas encore traité ; « sent », « partial », « no_targets », « not_configured »…
  final String? status;
  final int sent;
  final int failed;

  String get text => switch (status) {
    null => 'en cours d’envoi…',
    'sent' => 'reçue par $sent téléphone${sent > 1 ? 's' : ''}',
    'partial' => '$sent envoyée(s), $failed en échec',
    'no_targets' => 'aucun téléphone de l’administration n’accepte les notifications',
    'not_configured' => 'notifications non configurées sur ce serveur',
    _ => 'en échec',
  };

  bool get ok => status == 'sent';
}

/// Résultat du test du relais des appels (fonction call-ice).
class RelayTestResult {
  const RelayTestResult(this.relay, {this.ms});

  /// « ok », « not_configured », « failed » ou « error » (fonction injoignable).
  final String relay;
  final int? ms;

  String get text => switch (relay) {
    'ok' => 'Relais disponible${ms == null ? '' : ' (réponse en $ms ms)'}',
    'not_configured' => 'Relais non configuré\u202F: seuls les appels directs passent (STUN)',
    'failed' => 'Le relais ne répond pas\u202F: les appels sur réseau difficile peuvent échouer',
    _ => 'Test impossible pour le moment',
  };

  bool get ok => relay == 'ok';
}

class ConsoleHealth {
  const ConsoleHealth({
    required this.generatedAt,
    this.minBuild = 0,
    this.recommendedBuild = 0,
    this.updateUrl = '',
    this.devices = 0,
    this.belowMin = 0,
    this.belowRecommended = 0,
    this.installed = const [],
    this.callsAudio30d = 0,
    this.callsVideo30d = 0,
    this.callsOk30d = 0,
    this.callsFailed30d = 0,
    this.callsUnanswered30d = 0,
    this.callSeconds30d = 0,
    this.callsReported30d = 0,
    this.callsRelayed30d = 0,
    this.relayBytesMonth = 0,
    this.relayFreeBytes = 1000 * 1000 * 1000 * 1000,
    this.codes30d = 0,
    this.codesMonth = 0,
    this.codes24h = 0,
    this.codes1h = 0,
    this.phoneChange30d = 0,
    this.verified30d = 0,
    this.profiles30d = 0,
    this.unitCost = 0,
    this.costMonth = 0,
    this.cost30d = 0,
    this.jobs = const [],
    this.expiredWaiting = 0,
    this.filesWaiting = 0,
    this.adminPushTargets = 0,
    this.lastTest,
    this.alertsEnabled = true,
    this.smsAlertPerHour = 30,
    this.alerts = const [],
  });

  final DateTime generatedAt;
  final int minBuild;
  final int recommendedBuild;
  final String updateUrl;
  final int devices;
  final int belowMin;
  final int belowRecommended;
  final List<InstalledVersion> installed;
  final int callsAudio30d;
  final int callsVideo30d;
  final int callsOk30d;
  final int callsFailed30d;
  final int callsUnanswered30d;
  final int callSeconds30d;
  final int callsReported30d;
  final int callsRelayed30d;
  final int relayBytesMonth;
  final int relayFreeBytes;
  final int codes30d;
  final int codesMonth;
  final int codes24h;
  final int codes1h;
  final int phoneChange30d;
  final int verified30d;
  final int profiles30d;
  final int unitCost;
  final int costMonth;
  final int cost30d;
  final List<CronJob> jobs;
  final int expiredWaiting;
  final int filesWaiting;
  final int adminPushTargets;
  final PushTestResult? lastTest;
  final bool alertsEnabled;
  final int smsAlertPerHour;
  final List<HealthAlert> alerts;

  int get callsTotal30d => callsAudio30d + callsVideo30d;

  /// Part des appels décrochés passés par le relais (null : aucun compte rendu).
  double? get relayShare => callsReported30d == 0 ? null : callsRelayed30d / callsReported30d;

  /// Durée moyenne d'un appel réussi.
  Duration? get averageCall =>
      callsOk30d == 0 ? null : Duration(seconds: callSeconds30d ~/ callsOk30d);

  double get relayUse => relayFreeBytes == 0 ? 0 : relayBytesMonth / relayFreeBytes;

  /// Part des codes envoyés qui ont été vérifiés (connexion et changement de numéro).
  double? get verifiedShare => codes30d == 0 ? null : (verified30d / codes30d).clamp(0, 1);

  factory ConsoleHealth.fromJson(Map<String, dynamic> j) {
    final v = _m(j['versions']);
    final c = _m(j['calls']);
    final s = _m(j['signup']);
    final d = _m(j['diagnostics']);
    final a = _m(j['alerts']);
    final test = _m(d['last_test']);
    final result = _m(test['result']);
    return ConsoleHealth(
      generatedAt: DateTime.tryParse(j['generated_at'] as String? ?? '') ?? DateTime.now(),
      minBuild: _i(v['min_build']),
      recommendedBuild: _i(v['recommended_build']),
      updateUrl: v['update_url'] as String? ?? '',
      devices: _i(v['devices']),
      belowMin: _i(v['below_min']),
      belowRecommended: _i(v['below_recommended']),
      installed: [
        for (final x in (v['installed'] as List? ?? const []))
          InstalledVersion(
            version: _m(x)['version'] as String? ?? '?',
            build: (_m(x)['build'] as num?)?.toInt(),
            devices: _i(_m(x)['devices']),
          ),
      ],
      callsAudio30d: _i(c['audio_30d']),
      callsVideo30d: _i(c['video_30d']),
      callsOk30d: _i(c['ok_30d']),
      callsFailed30d: _i(c['failed_30d']),
      callsUnanswered30d: _i(c['unanswered_30d']),
      callSeconds30d: _i(c['seconds_30d']),
      callsReported30d: _i(c['reported_30d']),
      callsRelayed30d: _i(c['relayed_30d']),
      relayBytesMonth: _i(c['relay_bytes_month']),
      relayFreeBytes: c['relay_free_bytes'] == null ? 1000000000000 : _i(c['relay_free_bytes']),
      codes30d: _i(s['codes_30d']),
      codesMonth: _i(s['codes_month']),
      codes24h: _i(s['codes_24h']),
      codes1h: _i(s['codes_1h']),
      phoneChange30d: _i(s['phone_change_30d']),
      verified30d: _i(s['verified_30d']),
      profiles30d: _i(s['profiles_30d']),
      unitCost: _i(s['unit_cost']),
      costMonth: _i(s['cost_month']),
      cost30d: _i(s['cost_30d']),
      jobs: [
        for (final x in (d['jobs'] as List? ?? const []))
          CronJob(
            job: _m(x)['job'] as String? ?? '?',
            schedule: _m(x)['schedule'] as String? ?? '',
            active: _m(x)['active'] as bool? ?? true,
            lastRun: CronRun.fromJson(_m(x)['at'] == null ? null : _m(x)),
          ),
      ],
      expiredWaiting: _i(d['expired_waiting']),
      filesWaiting: _i(d['files_waiting']),
      adminPushTargets: _i(d['push_targets']),
      lastTest: test.isEmpty
          ? null
          : PushTestResult(
              at: DateTime.tryParse(test['at'] as String? ?? '') ?? DateTime.now(),
              status: result['status'] as String?,
              sent: _i(result['sent']),
              failed: _i(result['failed']),
            ),
      alertsEnabled: a['enabled'] as bool? ?? true,
      smsAlertPerHour: a['sms_per_hour'] == null ? 30 : _i(a['sms_per_hour']),
      alerts: [
        for (final x in (a['recent'] as List? ?? const []))
          HealthAlert(
            kind: _m(x)['kind'] as String? ?? '?',
            at: DateTime.tryParse(_m(x)['at'] as String? ?? '') ?? DateTime.now(),
            detail: _m(_m(x)['detail']),
          ),
      ],
    );
  }
}
