/// Modération (lot 5.3) : signalements vus par la console, sanctions, situation d'un compte.
library;

/// Motifs de signalement, en français.
const kReportReasons = <String, String>{
  'spam': 'Spam',
  'harassment': 'Harcèlement',
  'inappropriate': 'Contenu inapproprié',
  'threat': 'Menace',
  'impersonation': 'Usurpation d’identité',
  'other': 'Autre',
  'support': 'Demande d’assistance',
};

String reasonLabel(String? r) => kReportReasons[r] ?? 'Autre';

/// Décisions, en français (journal, signalements traités).
const kDecisionLabels = <String, String>{
  'dismissed': 'Classé sans suite',
  'warned': 'Avertissement',
  'suspended': 'Suspension',
  'message_deleted': 'Message supprimé',
  'group_closed': 'Groupe fermé',
};

/// Un signalement tel que la console le voit (jamais de numéro de téléphone).
class ModerationReport {
  const ModerationReport({
    required this.id,
    required this.kind,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.details,
    this.takenAt,
    this.decision,
    this.decisionNote,
    this.decidedAt,
    this.reporterHandle,
    this.reportedUserId,
    this.reportedHandle,
    this.reportedName,
    this.reportedSince,
    this.conversationId,
    this.groupTitle,
    this.groupClosed = false,
    this.messageId,
    this.evidenceKind,
    this.reports90d = 0,
    this.reporters90d = 0,
    this.suspended = false,
    this.suspendedUntil,
    this.sanctionsCount = 0,
    this.protected = false,
  });

  final String id;

  /// account, message, group, support.
  final String kind;
  final String reason;
  final String? details;

  /// open, reviewing, closed.
  final String status;
  final DateTime createdAt;
  final DateTime? takenAt;
  final String? decision;
  final String? decisionNote;
  final DateTime? decidedAt;
  final String? reporterHandle;
  final String? reportedUserId;
  final String? reportedHandle;
  final String? reportedName;
  final DateTime? reportedSince;
  final String? conversationId;
  final String? groupTitle;
  final bool groupClosed;
  final String? messageId;

  /// text, voice, photo — null si aucune copie jointe.
  final String? evidenceKind;
  final int reports90d;
  final int reporters90d;
  final bool suspended;

  /// Fin de la suspension en cours (null avec [suspended] = sans limite).
  final DateTime? suspendedUntil;
  final int sanctionsCount;

  /// Compte de l'administration : ne peut pas être sanctionné.
  final bool protected;

  /// Dossier : les signalements visant la même cible sont traités ensemble.
  String get target => switch (kind) {
    'support' => 'support:$id',
    'group' => 'group:$conversationId',
    _ => 'user:${reportedUserId ?? id}',
  };

  static DateTime? _d(Object? v) => v is String ? DateTime.tryParse(v) : null;

  factory ModerationReport.fromJson(Map<String, dynamic> j) => ModerationReport(
    id: j['id'] as String,
    kind: j['kind'] as String? ?? 'account',
    reason: j['reason'] as String? ?? 'other',
    details: j['details'] as String?,
    status: j['status'] as String? ?? 'open',
    createdAt: DateTime.parse(j['created_at'] as String),
    takenAt: _d(j['taken_at']),
    decision: j['decision'] as String?,
    decisionNote: j['decision_note'] as String?,
    decidedAt: _d(j['decided_at']),
    reporterHandle: j['reporter_handle'] as String?,
    reportedUserId: j['reported_user_id'] as String?,
    reportedHandle: j['reported_handle'] as String?,
    reportedName: j['reported_name'] as String?,
    reportedSince: _d(j['reported_since']),
    conversationId: j['conversation_id'] as String?,
    groupTitle: j['group_title'] as String?,
    groupClosed: j['group_closed'] as bool? ?? false,
    messageId: j['message_id'] as String?,
    evidenceKind: j['evidence_kind'] as String?,
    reports90d: (j['reports_90d'] as num?)?.toInt() ?? 0,
    reporters90d: (j['reporters_90d'] as num?)?.toInt() ?? 0,
    suspended: j['suspended'] as bool? ?? false,
    suspendedUntil: _d(j['suspended_until']),
    sanctionsCount: (j['sanctions_count'] as num?)?.toInt() ?? 0,
    protected: j['protected'] as bool? ?? false,
  );
}

/// Les signalements d'une même cible, regroupés (ordre d'arrivée conservé).
List<List<ModerationReport>> groupDossiers(List<ModerationReport> reports) {
  final byTarget = <String, List<ModerationReport>>{};
  for (final r in reports) {
    byTarget.putIfAbsent(r.target, () => []).add(r);
  }
  return byTarget.values.toList();
}

/// Copie jointe par la personne qui signale.
class ReportEvidence {
  const ReportEvidence({
    required this.kind,
    this.body,
    this.sentAt,
    this.mediaPath,
    this.durationMs,
  });

  final String kind;
  final String? body;
  final DateTime? sentAt;
  final String? mediaPath;
  final int? durationMs;

  factory ReportEvidence.fromJson(Map<String, dynamic> j) => ReportEvidence(
    kind: j['kind'] as String? ?? 'text',
    body: j['body'] as String?,
    sentAt: DateTime.tryParse(j['sent_at'] as String? ?? ''),
    mediaPath: j['media_path'] as String?,
    durationMs: (j['duration_ms'] as num?)?.toInt(),
  );
}

/// Une sanction (fiche d'un compte, contestations).
class Sanction {
  const Sanction({
    required this.id,
    required this.kind,
    required this.reason,
    required this.createdAt,
    this.until,
    this.note,
    this.liftedAt,
    this.appealText,
    this.appealDecision,
    this.userId,
    this.handle,
    this.displayName,
    this.appealAt,
  });

  final String id;

  /// warning, suspension.
  final String kind;
  final String reason;
  final DateTime createdAt;
  final DateTime? until;
  final String? note;
  final DateTime? liftedAt;
  final String? appealText;
  final String? appealDecision;
  final String? userId;
  final String? handle;
  final String? displayName;
  final DateTime? appealAt;

  static DateTime? _d(Object? v) => v is String ? DateTime.tryParse(v) : null;

  factory Sanction.fromJson(Map<String, dynamic> j) => Sanction(
    id: (j['id'] ?? j['sanction_id']) as String,
    kind: j['kind'] as String? ?? 'suspension',
    reason: j['user_reason'] as String? ?? 'other',
    createdAt: DateTime.parse(j['created_at'] as String),
    until: _d(j['until']),
    note: j['note'] as String?,
    liftedAt: _d(j['lifted_at']),
    appealText: j['appeal_text'] as String?,
    appealDecision: j['appeal_decision'] as String?,
    userId: j['user_id'] as String?,
    handle: j['handle'] as String?,
    displayName: j['display_name'] as String?,
    appealAt: _d(j['appeal_at']),
  );
}

/// Situation du compte connecté (écran « Compte suspendu », avertissement).
class ModerationStatus {
  const ModerationStatus({this.suspension, this.warning});

  final SuspensionInfo? suspension;
  final WarningInfo? warning;

  static const none = ModerationStatus();

  factory ModerationStatus.fromJson(Map<String, dynamic> j) {
    final s = j['suspension'];
    final w = j['warning'];
    return ModerationStatus(
      suspension: s is Map ? SuspensionInfo.fromJson(Map<String, dynamic>.from(s)) : null,
      warning: w is Map ? WarningInfo.fromJson(Map<String, dynamic>.from(w)) : null,
    );
  }
}

class SuspensionInfo {
  const SuspensionInfo({
    required this.id,
    required this.reason,
    this.until,
    this.appealed = false,
    this.appealDecision,
  });

  final String id;
  final String reason;

  /// null = sans limite.
  final DateTime? until;
  final bool appealed;

  /// upheld (maintenue) ou null (pas encore examinée).
  final String? appealDecision;

  factory SuspensionInfo.fromJson(Map<String, dynamic> j) => SuspensionInfo(
    id: j['id'] as String,
    reason: j['reason'] as String? ?? 'other',
    until: DateTime.tryParse(j['until'] as String? ?? ''),
    appealed: j['appealed'] as bool? ?? false,
    appealDecision: j['appeal_decision'] as String?,
  );
}

class WarningInfo {
  const WarningInfo({required this.id, required this.reason});

  final String id;
  final String reason;

  factory WarningInfo.fromJson(Map<String, dynamic> j) =>
      WarningInfo(id: j['id'] as String, reason: j['reason'] as String? ?? 'other');
}
