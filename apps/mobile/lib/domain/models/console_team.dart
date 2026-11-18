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
