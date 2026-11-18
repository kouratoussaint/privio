// Lot 5.8 — console : équipe et modération (ADR-053).

/// Rôles dans la console.
enum ConsoleRole {
  owner('Propriétaire'),
  moderator('Modérateur'),
  support('Assistance');

  const ConsoleRole(this.label);

  final String label;

  static ConsoleRole? of(String? v) => switch (v) {
    'owner' => ConsoleRole.owner,
    'moderator' => ConsoleRole.moderator,
    'support' => ConsoleRole.support,
    _ => null,
  };

  bool get isOwner => this == ConsoleRole.owner;

  /// Signalements (hors assistance), sanctions, groupes, sites sans aperçu, suivi.
  bool get moderates => this == ConsoleRole.owner || this == ConsoleRole.moderator;

  /// Demandes d'assistance, déconnexion d'un téléphone, deux étapes.
  bool get assists => this == ConsoleRole.owner || this == ConsoleRole.support;
}

/// Ma place dans la console.
class ConsoleMe {
  const ConsoleMe({required this.role, this.twoStep = true});

  final ConsoleRole role;

  /// Deux étapes activées (obligatoire pour l'équipe, pas pour le propriétaire).
  final bool twoStep;

  bool get blocked => !role.isOwner && !twoStep;

  factory ConsoleMe.fromJson(Map<String, dynamic> j) => ConsoleMe(
    role: ConsoleRole.of(j['role'] as String?) ?? ConsoleRole.support,
    twoStep: j['two_step'] as bool? ?? false,
  );
}

class StaffMember {
  const StaffMember({
    required this.userId,
    required this.role,
    this.name,
    this.handle,
    this.avatar,
    this.phone,
    this.addedAt,
    this.twoStep = false,
    this.lastActionAt,
  });

  final String userId;
  final ConsoleRole role;
  final String? name;
  final String? handle;
  final String? avatar;
  final String? phone;
  final DateTime? addedAt;
  final bool twoStep;
  final DateTime? lastActionAt;

  factory StaffMember.fromJson(Map<String, dynamic> j) => StaffMember(
    userId: j['user_id'] as String,
    role: ConsoleRole.of(j['role'] as String?) ?? ConsoleRole.support,
    name: j['name'] as String?,
    handle: j['handle'] as String?,
    avatar: j['avatar'] as String?,
    phone: j['phone'] as String?,
    addedAt: _date(j['added_at']),
    twoStep: j['two_step'] as bool? ?? false,
    lastActionAt: _date(j['last_action_at']),
  );
}

/// Groupe vu par la console : jamais les messages.
class ConsoleGroup {
  const ConsoleGroup({
    required this.id,
    required this.title,
    this.announcement = false,
    this.closed = false,
    this.posting = 'all',
    this.createdAt,
    this.lastActivity,
    this.members = 0,
    this.admins = 0,
    this.ownerHandle,
    this.reportsOpen = 0,
    this.reports90d = 0,
  });

  final String id;
  final String title;
  final bool announcement;
  final bool closed;
  final String posting;
  final DateTime? createdAt;
  final DateTime? lastActivity;
  final int members;
  final int admins;
  final String? ownerHandle;
  final int reportsOpen;
  final int reports90d;

  factory ConsoleGroup.fromJson(Map<String, dynamic> j) => ConsoleGroup(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    announcement: j['announcement'] as bool? ?? false,
    closed: j['closed'] as bool? ?? false,
    posting: j['posting'] as String? ?? 'all',
    createdAt: _date(j['created_at']),
    lastActivity: _date(j['last_activity']),
    members: (j['members'] as num?)?.toInt() ?? 0,
    admins: (j['admins'] as num?)?.toInt() ?? 0,
    ownerHandle: j['owner_handle'] as String?,
    reportsOpen: (j['reports_open'] as num?)?.toInt() ?? 0,
    reports90d: (j['reports_90d'] as num?)?.toInt() ?? 0,
  );
}

/// Filtres de la liste des groupes (clé serveur → libellé).
const kGroupFilters = <String, String>{
  'all': 'Tous',
  'reported': 'Signalés',
  'closed': 'Fermés',
  'announcement': 'Annonces',
};

/// Réponse type : « support » (réponse d'assistance) ou « decision » (motif de décision).
class ConsoleTemplate {
  const ConsoleTemplate({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
  });

  final String id;
  final String kind;
  final String title;
  final String body;

  factory ConsoleTemplate.fromJson(Map<String, dynamic> j) => ConsoleTemplate(
    id: j['id'] as String,
    kind: j['kind'] as String,
    title: j['title'] as String? ?? '',
    body: j['body'] as String? ?? '',
  );
}

class ModerationPerson {
  const ModerationPerson({required this.name, this.role, this.decided = 0, this.avgHours});

  final String name;
  final ConsoleRole? role;
  final int decided;
  final double? avgHours;
}

/// Suivi de la modération sur 7 ou 30 jours.
class ModerationStats {
  const ModerationStats({
    required this.days,
    this.received = 0,
    this.decided = 0,
    this.supportReceived = 0,
    this.supportAnswered = 0,
    this.openNow = 0,
    this.oldestOpenHours,
    this.avgHours,
    this.appeals = 0,
    this.byReason = const {},
    this.byDecision = const {},
    this.byPerson = const [],
  });

  final int days;
  final int received;
  final int decided;
  final int supportReceived;
  final int supportAnswered;
  final int openNow;
  final int? oldestOpenHours;
  final double? avgHours;
  final int appeals;
  final Map<String, int> byReason;
  final Map<String, int> byDecision;
  final List<ModerationPerson> byPerson;

  factory ModerationStats.fromJson(Map<String, dynamic> j) {
    Map<String, int> counts(Object? v) => {
      for (final e in Map<String, dynamic>.from(v as Map? ?? const {}).entries)
        e.key: (e.value as num).toInt(),
    };
    return ModerationStats(
      days: (j['days'] as num?)?.toInt() ?? 7,
      received: (j['received'] as num?)?.toInt() ?? 0,
      decided: (j['decided'] as num?)?.toInt() ?? 0,
      supportReceived: (j['support_received'] as num?)?.toInt() ?? 0,
      supportAnswered: (j['support_answered'] as num?)?.toInt() ?? 0,
      openNow: (j['open_now'] as num?)?.toInt() ?? 0,
      oldestOpenHours: (j['oldest_open_hours'] as num?)?.toInt(),
      avgHours: (j['avg_hours'] as num?)?.toDouble(),
      appeals: (j['appeals'] as num?)?.toInt() ?? 0,
      byReason: counts(j['by_reason']),
      byDecision: counts(j['by_decision']),
      byPerson: [
        for (final p in (j['by_person'] as List<dynamic>? ?? const []))
          ModerationPerson(
            name: (p as Map)['name'] as String? ?? '—',
            role: ConsoleRole.of(p['role'] as String?),
            decided: (p['decided'] as num?)?.toInt() ?? 0,
            avgHours: (p['avg_hours'] as num?)?.toDouble(),
          ),
      ],
    );
  }
}

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String);

// ---------------------------------------------------------------------------
// Lot 5.9 — pilotage
// ---------------------------------------------------------------------------
class SignupCode {
  const SignupCode({
    required this.code,
    this.label,
    this.maxUses = 1,
    this.uses = 0,
    this.expiresAt,
    this.active = true,
  });

  final String code;
  final String? label;
  final int maxUses;
  final int uses;
  final DateTime? expiresAt;
  final bool active;

  factory SignupCode.fromJson(Map<String, dynamic> j) => SignupCode(
    code: j['code'] as String,
    label: j['label'] as String?,
    maxUses: (j['max_uses'] as num?)?.toInt() ?? 1,
    uses: (j['uses'] as num?)?.toInt() ?? 0,
    expiresAt: _date(j['expires_at']),
    active: j['active'] as bool? ?? false,
  );
}

/// Inscriptions : 'open', 'list' ou 'closed' ; numéros autorisés ; codes d'invitation.
class SignupsState {
  const SignupsState({
    required this.mode,
    this.phones = const [],
    this.codes = const [],
    this.passes7d = 0,
  });

  final String mode;
  final List<String> phones;
  final List<SignupCode> codes;
  final int passes7d;

  factory SignupsState.fromJson(Map<String, dynamic> j) => SignupsState(
    mode: j['mode'] as String? ?? 'open',
    phones: [for (final p in (j['phones'] as List<dynamic>? ?? const [])) p as String],
    codes: [
      for (final c in (j['codes'] as List<dynamic>? ?? const []))
        SignupCode.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
    passes7d: (j['passes_7d'] as num?)?.toInt() ?? 0,
  );
}

const kSignupModes = <String, String>{'open': 'Ouvertes', 'list': 'Sur liste', 'closed': 'Fermées'};

/// Exception (réglage propre à un compte ou à un groupe).
class PolicyOverride {
  const PolicyOverride({
    required this.scope,
    required this.id,
    required this.key,
    required this.label,
    required this.value,
    this.globalValue,
    this.target,
    this.expiresAt,
    this.note,
  });

  /// 'user' ou 'group'.
  final String scope;
  final String id;
  final String key;
  final String label;
  final Object? value;
  final Object? globalValue;
  final String? target;
  final DateTime? expiresAt;
  final String? note;

  factory PolicyOverride.fromJson(Map<String, dynamic> j) => PolicyOverride(
    scope: j['scope'] as String,
    id: j['id'] as String,
    key: j['key'] as String,
    label: j['label'] as String? ?? j['key'] as String,
    value: j['value'],
    globalValue: j['global'],
    target: j['target'] as String?,
    expiresAt: _date(j['expires_at']),
    note: j['note'] as String?,
  );
}

/// Réglages qu'une exception peut changer (clé → libellé, type).
const kUserOverrideKeys = <String, (String, bool)>{
  'photo_daily_limit': ('Photos par jour', false),
  'group_create_enabled': ('Création de groupes', true),
  'calls_video_enabled': ('Appels vidéo', true),
};
const kGroupOverrideKeys = <String, (String, bool)>{
  'group_max_members': ('Membres au plus (jusqu’à 500)', false),
  'photo_enabled': ('Photos', true),
  'link_preview_enabled': ('Aperçus des liens', true),
};

String overrideValueText(Object? v) => switch (v) {
  true => 'oui',
  false => 'non',
  null => '—',
  _ => '$v',
};

class PresetChange {
  const PresetChange({required this.key, required this.label, this.before, this.after});

  final String key;
  final String label;
  final Object? before;
  final Object? after;

  factory PresetChange.fromJson(Map<String, dynamic> j) => PresetChange(
    key: j['key'] as String,
    label: j['label'] as String? ?? j['key'] as String,
    before: j['before'],
    after: j['after'],
  );
}

const kPresets = <String, String>{'pilot': 'Mode pilote', 'normal': 'Mode normal'};

class ScheduledAnnouncement {
  const ScheduledAnnouncement({
    required this.text,
    required this.startsAt,
    required this.endsAt,
    this.live = false,
  });

  final String text;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool live;

  factory ScheduledAnnouncement.fromJson(Map<String, dynamic> j) => ScheduledAnnouncement(
    text: j['text'] as String,
    startsAt: DateTime.parse(j['starts_at'] as String),
    endsAt: DateTime.parse(j['ends_at'] as String),
    live: j['live'] as bool? ?? false,
  );
}

class RetentionWeek {
  const RetentionWeek({
    required this.week,
    required this.signups,
    this.d1 = 0,
    this.r1 = 0,
    this.d7 = 0,
    this.r7 = 0,
    this.d30 = 0,
    this.r30 = 0,
  });

  final DateTime week;
  final int signups;

  /// dN : inscrits depuis au moins N jours ; rN : revenus au moins N jours après.
  final int d1;
  final int r1;
  final int d7;
  final int r7;
  final int d30;
  final int r30;
}

/// Statistiques en plus (lot 5.9) : rétention, langues, usage des fonctions par jour.
class StatsExtra {
  const StatsExtra({this.retention = const [], this.languages = const {}, this.usage = const []});

  final List<RetentionWeek> retention;
  final Map<String, int> languages;
  final List<(DateTime, Map<String, int>)> usage;

  factory StatsExtra.fromJson(Map<String, dynamic> j) {
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return StatsExtra(
      retention: [
        for (final r in (j['retention'] as List<dynamic>? ?? const []))
          RetentionWeek(
            week: DateTime.parse((r as Map)['week'] as String),
            signups: n(r['signups']),
            d1: n(r['d1']),
            r1: n(r['r1']),
            d7: n(r['d7']),
            r7: n(r['r7']),
            d30: n(r['d30']),
            r30: n(r['r30']),
          ),
      ],
      languages: {
        for (final e in Map<String, dynamic>.from(j['languages'] as Map? ?? const {}).entries)
          e.key: n(e.value),
      },
      usage: [
        for (final d in (j['usage'] as List<dynamic>? ?? const []))
          (
            DateTime.parse((d as Map)['day'] as String),
            {
              for (final e in Map<String, dynamic>.from(d['values'] as Map? ?? const {}).entries)
                e.key: n(e.value),
            },
          ),
      ],
    );
  }
}

const kUsageMetrics = <String, String>{
  'messages_text': 'Textes',
  'messages_voice': 'Vocaux',
  'messages_photo': 'Photos',
  'messages_gif': 'GIF',
  'messages_sticker': 'Autocollants',
  'messages_poll': 'Sondages',
  'calls_audio': 'Appels audio',
  'calls_video': 'Appels vidéo',
  'group_calls_audio': 'Appels de groupe audio',
  'group_calls_video': 'Appels de groupe vidéo',
};

const kLanguages = <String, String>{
  'fr': 'Français',
  'mos': 'Mooré',
  'dyu': 'Dioula',
  'unknown': 'Non indiquée',
};
