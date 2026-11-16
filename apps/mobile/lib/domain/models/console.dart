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
  });

  final int id;

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
  'views': 'Consultations',
};

/// Même classement que le serveur (`private.journal_type`).
String journalTypeOf(String action) => switch (action) {
  'account' || 'account_search' || 'account_list' || 'lift' => 'accounts',
  'moderation' || 'evidence' || 'appeal' => 'reports',
  'policy' => 'settings',
  'two_step_reset' || 'disconnect' => 'security',
  'reply' => 'support',
  _ => 'views',
};

/// Page d'une liste paginée.
class ConsolePage<T> {
  const ConsolePage({
    required this.total,
    required this.page,
    required this.size,
    required this.rows,
    this.letters = const {},
  });

  final int total;
  final int page;
  final int size;
  final List<T> rows;

  /// Comptes : première position (0…) de chaque initiale (A–Z, « # » pour le reste).
  final Map<String, int> letters;

  int get pages => total == 0 ? 1 : (total + size - 1) ~/ size;

  /// Page où commence l'initiale [letter].
  int? pageOf(String letter) {
    final pos = letters[letter];
    return pos == null ? null : pos ~/ size + 1;
  }
}
