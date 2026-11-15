/// Lot 9.1a — appel audio à deux, tel que vu par l'utilisateur (ADR-036).
class CallInfo {
  const CallInfo({
    required this.id,
    required this.conversationId,
    required this.status,
    required this.outgoing,
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
    this.kind = 'audio',
    this.answeredAt,
    this.endReason,
  });

  final String id;
  final String conversationId;

  /// 'ringing', 'accepted', 'declined', 'missed', 'cancelled' ou 'ended'.
  final String status;
  final bool outgoing;
  final String peerId;
  final String peerName;
  final String? peerAvatar;
  final String kind;
  final DateTime? answeredAt;

  /// 'busy', 'timeout', 'hangup', 'failed', 'lost', 'declined'.
  final String? endReason;

  bool get open => status == 'ringing' || status == 'accepted';

  factory CallInfo.fromJson(Map<String, dynamic> j) => CallInfo(
    id: j['id'] as String,
    conversationId: j['conversation_id'] as String,
    status: j['status'] as String,
    outgoing: j['outgoing'] as bool? ?? false,
    peerId: j['peer_id'] as String,
    peerName: j['peer_name'] as String? ?? '',
    peerAvatar: j['peer_avatar'] as String?,
    kind: j['kind'] as String? ?? 'audio',
    answeredAt: j['answered_at'] == null ? null : DateTime.parse(j['answered_at'] as String),
    endReason: j['end_reason'] as String?,
  );
}

/// Description de session ou candidat réseau envoyé par le correspondant.
class CallSignal {
  const CallSignal({required this.id, required this.kind, required this.payload});

  final int id;

  /// 'offer', 'answer' ou 'ice'.
  final String kind;
  final Map<String, dynamic> payload;

  factory CallSignal.fromJson(Map<String, dynamic> j) => CallSignal(
    id: (j['id'] as num).toInt(),
    kind: j['kind'] as String,
    payload: Map<String, dynamic>.from(j['payload'] as Map),
  );
}

/// État d'un appel et nouveaux signaux.
class CallSnapshot {
  const CallSnapshot(this.call, this.signals);

  final CallInfo call;
  final List<CallSignal> signals;

  factory CallSnapshot.fromJson(Map<String, dynamic> j) => CallSnapshot(CallInfo.fromJson(j), [
    for (final s in (j['signals'] as List<dynamic>? ?? const []))
      CallSignal.fromJson(Map<String, dynamic>.from(s as Map)),
  ]);
}
