/// Modération (lot 5.3) : signalements vus par la console, sanctions, situation d'un compte.
library;

import '../../l10n/l10n.dart';

/// Motifs de signalement, en français.
Map<String, String> get kReportReasons => <String, String>{
  'spam': L.t.spam,
  'harassment': L.t.harcelement,
  'inappropriate': L.t.contenuInapproprie,
  'threat': L.t.menace,
  'impersonation': L.t.usurpationIdentite,
  'other': L.t.autre,
  'support': L.t.demandeAssistance,
};

String reasonLabel(String? r) => kReportReasons[r] ?? L.t.autre;

/// Décisions, en français (journal, signalements traités).
Map<String, String> get kDecisionLabels => <String, String>{
  'dismissed': L.t.classeSansSuite,
  'warned': L.t.avertissement,
  'suspended': L.t.suspension,
  'message_deleted': L.t.messageSupprime,
  'group_closed': L.t.groupeFerme,
  'answered': L.t.repondue,
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
    this.reply,
    this.repliedAt,
  });

  final String id;

  /// Lot 5.4 : réponse de l'équipe à une demande d'assistance.
  final String? reply;
  final DateTime? repliedAt;

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
    reply: j['reply'] as String?,
    repliedAt: _d(j['replied_at']),
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

// ---------------------------------------------------------------------------
// Lot 5.4 : comptes et assistance
// ---------------------------------------------------------------------------

/// Résultat de recherche (jamais de numéro).
class AccountHit {
  const AccountHit({
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.createdAt,
    this.deleted = false,
    this.suspended = false,
  });

  final String userId;
  final String handle;
  final String displayName;
  final DateTime createdAt;
  final bool deleted;
  final bool suspended;

  factory AccountHit.fromJson(Map<String, dynamic> j) => AccountHit(
    userId: j['user_id'] as String,
    handle: j['handle'] as String,
    displayName: j['display_name'] as String? ?? '',
    createdAt: DateTime.parse(j['created_at'] as String),
    deleted: j['deleted'] as bool? ?? false,
    suspended: j['suspended'] as bool? ?? false,
  );
}

/// Une demande d'assistance et la réponse de l'équipe.
class SupportRequest {
  const SupportRequest({
    required this.id,
    required this.createdAt,
    this.details,
    this.reply,
    this.repliedAt,
  });

  final String id;
  final DateTime createdAt;
  final String? details;
  final String? reply;
  final DateTime? repliedAt;

  bool get answered => reply != null;

  factory SupportRequest.fromJson(Map<String, dynamic> j) => SupportRequest(
    id: j['id'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    details: j['details'] as String?,
    reply: j['reply'] as String?,
    repliedAt: DateTime.tryParse(j['replied_at'] as String? ?? ''),
  );
}

/// Fiche d'un compte dans la console : aucun numéro, contact, discussion ni message.
class ConsoleAccount {
  const ConsoleAccount({
    required this.userId,
    required this.handle,
    required this.displayName,
    required this.createdAt,
    this.avatarPath,
    this.deleted = false,
    this.lastSeenDay,
    this.suspended = false,
    this.suspendedUntil,
    this.protected = false,
    this.platform,
    this.appVersion,
    this.deviceSince,
    this.pushEnabled = false,
    this.directs = 0,
    this.groups = 0,
    this.reportsReceived90d = 0,
    this.reportsMade90d = 0,
    this.support = const [],
  });

  final String userId;
  final String handle;
  final String displayName;
  final DateTime createdAt;
  final String? avatarPath;
  final bool deleted;
  final DateTime? lastSeenDay;
  final bool suspended;
  final DateTime? suspendedUntil;
  final bool protected;

  /// Téléphone actif (null : aucun).
  final String? platform;
  final String? appVersion;
  final DateTime? deviceSince;
  final bool pushEnabled;
  final int directs;
  final int groups;
  final int reportsReceived90d;
  final int reportsMade90d;
  final List<SupportRequest> support;

  bool get hasDevice => platform != null;

  factory ConsoleAccount.fromJson(Map<String, dynamic> j) {
    final d = j['device'] is Map ? Map<String, dynamic>.from(j['device'] as Map) : null;
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return ConsoleAccount(
      userId: j['user_id'] as String,
      handle: j['handle'] as String,
      displayName: j['display_name'] as String? ?? '',
      createdAt: DateTime.parse(j['created_at'] as String),
      avatarPath: j['avatar_path'] as String?,
      deleted: j['deleted'] as bool? ?? false,
      lastSeenDay: DateTime.tryParse(j['last_seen_day'] as String? ?? ''),
      suspended: j['suspended'] as bool? ?? false,
      suspendedUntil: DateTime.tryParse(j['suspended_until'] as String? ?? ''),
      protected: j['protected'] as bool? ?? false,
      platform: d?['platform'] as String?,
      appVersion: d?['app_version'] as String?,
      deviceSince: DateTime.tryParse(d?['since'] as String? ?? ''),
      pushEnabled: d?['push'] as bool? ?? false,
      directs: n('directs'),
      groups: n('groups'),
      reportsReceived90d: n('reports_received_90d'),
      reportsMade90d: n('reports_made_90d'),
      support: [
        for (final s in (j['support'] as List? ?? const []))
          SupportRequest.fromJson(Map<String, dynamic>.from(s as Map)),
      ],
    );
  }
}
