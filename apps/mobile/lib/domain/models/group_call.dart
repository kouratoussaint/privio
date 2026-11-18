import 'contact_labels.dart';

/// Lot 9.4 — personne d'un appel de groupe (ADR-052).
class GroupCallParticipant {
  const GroupCallParticipant({
    required this.userId,
    required this.state,
    required this._name,
    this.avatar,
    this.camera = false,
    this.muted = false,
    this.session,
    this.tracks = const {},
    this.joinedAt,
  });

  final String userId;

  /// 'ringing' (son téléphone sonne) ou 'joined' (dans l'appel).
  final String state;

  /// Lot 10.4 : surnom privé s'il y en a un.
  String get name => ContactLabels.nameOf(userId, _name);
  final String _name;
  final String? avatar;
  final bool camera;
  final bool muted;

  /// Session au relais et noms des pistes publiées (« audio », « video ») : seulement pour
  /// les personnes dans l'appel, vues par une personne dans l'appel.
  final String? session;
  final Map<String, String> tracks;
  final DateTime? joinedAt;

  bool get joined => state == 'joined';

  factory GroupCallParticipant.fromJson(Map<String, dynamic> j) => GroupCallParticipant(
    userId: j['user_id'] as String,
    state: j['state'] as String,
    name: j['name'] as String? ?? '',
    avatar: j['avatar'] as String?,
    camera: j['camera'] as bool? ?? false,
    muted: j['muted'] as bool? ?? false,
    session: j['session'] as String?,
    tracks: {
      for (final e in (j['tracks'] as Map? ?? const {}).entries)
        if (e.value is String) '${e.key}': e.value as String,
    },
    joinedAt: j['joined_at'] == null ? null : DateTime.parse(j['joined_at'] as String),
  );
}

/// Lot 9.4 — appel de groupe, tel que vu par un membre du groupe.
class GroupCallInfo {
  const GroupCallInfo({
    required this.id,
    required this.conversationId,
    required this.status,
    required this.startedBy,
    this.kind = 'audio',
    this.rings = false,
    this.createdAt,
    this.answeredAt,
    this.myState,
    this.joinedCount = 0,
    this.max = 8,
    this.participants = const [],
    this.existing = false,
  });

  final String id;
  final String conversationId;

  /// 'active' ou 'ended'.
  final String status;
  final String startedBy;
  final String kind;

  /// Groupe de 16 membres ou moins : les téléphones sonnent.
  final bool rings;
  final DateTime? createdAt;
  final DateTime? answeredAt;

  /// Ma place : 'ringing', 'joined', 'left', 'declined', 'missed' ou null.
  final String? myState;
  final int joinedCount;
  final int max;
  final List<GroupCallParticipant> participants;

  /// « Appeler » dans un groupe où un appel était déjà en cours : on l'a rejoint.
  final bool existing;

  bool get active => status == 'active';
  bool get video => kind == 'video';
  bool get ringingMe => active && myState == 'ringing';
  bool get joinedMe => active && myState == 'joined';
  bool get full => joinedCount >= max;
  List<GroupCallParticipant> get joined => [
    for (final p in participants)
      if (p.joined) p,
  ];

  /// Nom de la personne qui a lancé l'appel (si elle est visible).
  String? get starterName {
    for (final p in participants) {
      if (p.userId == startedBy) return p.name;
    }
    return null;
  }

  factory GroupCallInfo.fromJson(Map<String, dynamic> j) => GroupCallInfo(
    id: j['id'] as String,
    conversationId: j['conversation_id'] as String,
    status: j['status'] as String? ?? 'active',
    startedBy: j['started_by'] as String? ?? '',
    kind: j['kind'] as String? ?? 'audio',
    rings: j['rings'] as bool? ?? false,
    createdAt: j['created_at'] == null ? null : DateTime.parse(j['created_at'] as String),
    answeredAt: j['answered_at'] == null ? null : DateTime.parse(j['answered_at'] as String),
    myState: j['my_state'] as String?,
    joinedCount: (j['joined_count'] as num?)?.toInt() ?? 0,
    max: (j['max'] as num?)?.toInt() ?? 8,
    participants: [
      for (final p in (j['participants'] as List<dynamic>? ?? const []))
        GroupCallParticipant.fromJson(Map<String, dynamic>.from(p as Map)),
    ],
    existing: j['existing'] as bool? ?? false,
  );
}

/// Piste reçue du relais : à qui elle appartient et à quel emplacement de la liaison.
class SfuTrack {
  const SfuTrack({required this.mid, required this.session, required this.name, this.error});

  final String? mid;
  final String session;
  final String name;
  final String? error;

  factory SfuTrack.fromJson(Map<String, dynamic> j) => SfuTrack(
    mid: j['mid'] as String?,
    session: j['session'] as String? ?? '',
    name: j['name'] as String? ?? '',
    error: j['error'] as String?,
  );
}

/// Offre du relais pour recevoir des pistes.
class SfuPull {
  const SfuPull({required this.sdp, required this.renegotiate, required this.tracks});

  final String? sdp;
  final bool renegotiate;
  final List<SfuTrack> tracks;

  factory SfuPull.fromJson(Map<String, dynamic> j) => SfuPull(
    sdp: j['sdp'] as String?,
    renegotiate: j['renegotiate'] as bool? ?? false,
    tracks: [
      for (final t in (j['tracks'] as List<dynamic>? ?? const []))
        SfuTrack.fromJson(Map<String, dynamic>.from(t as Map)),
    ],
  );
}
