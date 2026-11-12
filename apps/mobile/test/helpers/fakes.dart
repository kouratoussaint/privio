import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:image/image.dart' as img;
import 'package:privio/core/media/photo_processing.dart';
import 'package:privio/core/errors/app_failure.dart';
import 'package:privio/core/theme/privio_theme.dart';
import 'package:privio/data/services/account_api.dart';
import 'package:privio/data/services/audio/audio_engine.dart';
import 'package:privio/data/services/audio/voice_recorder.dart';
import 'package:privio/data/services/auth_service.dart';
import 'package:privio/data/services/messaging_api.dart';
import 'package:privio/data/services/realtime_service.dart';
import 'package:privio/data/storage/local_store.dart';
import 'package:privio/data/storage/media_vault.dart';
import 'package:privio/data/services/permission_gateway.dart';
import 'package:privio/data/services/photo_picker.dart';
import 'package:privio/data/storage/local_flags.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/state/messaging_providers.dart';
import 'package:privio/state/providers.dart';
import 'package:privio/state/session_controller.dart';

class FakeAuthService implements AuthService {
  FakeAuthService({this.signedIn = false});

  bool signedIn;
  final _changes = StreamController<void>.broadcast();
  final List<String> otpRequests = [];
  AppFailure? requestFailure;
  String validCode = '123456';

  @override
  bool get hasSession => signedIn;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> requestOtp(String phoneE164) async {
    if (requestFailure != null) throw requestFailure!;
    otpRequests.add(phoneE164);
  }

  @override
  Future<void> verifyOtp({required String phoneE164, required String code}) async {
    if (code != validCode) throw const AppFailure(FailureCode.otpInvalidOrExpired);
    signedIn = true;
    _changes.add(null);
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    _changes.add(null);
  }
}

class FakeAccountApi implements AccountApi {
  Account? account;
  AppFailure? accountFailure;
  final Set<String> takenHandles = {'alice_bf'};
  int registeredDevices = 0;
  int unregisteredDevices = 0;

  @override
  Future<Account> getMyAccount() async {
    if (accountFailure != null) throw accountFailure!;
    return account ??
        const Account(userId: 'u1', phoneE164: '+22670000001', phoneDiscoverable: false);
  }

  @override
  Future<Profile> createProfile({required String handle, required String displayName}) async {
    if (takenHandles.contains(handle)) throw const AppFailure(FailureCode.handleTaken);
    final profile = Profile(handle: handle, displayName: displayName);
    account = Account(
      userId: 'u1',
      phoneE164: '+22670000001',
      phoneDiscoverable: false,
      profile: profile,
    );
    return profile;
  }

  @override
  Future<bool> isHandleAvailable(String handle) async => !takenHandles.contains(handle);

  @override
  Future<bool> setPhoneDiscoverable(bool value) async => value;

  @override
  Future<String> registerDevice({required String appVersion}) async {
    registeredDevices++;
    return 'device-1';
  }

  @override
  Future<void> unregisterCurrentDevice() async => unregisteredDevices++;

  /// Photos de profil déposées (chemin → octets ; partagé avec la fausse messagerie).
  Map<String, Uint8List> avatars = {};

  @override
  Future<String> setAvatar(Uint8List jpeg) async {
    final path = 'u1/avatar-${avatars.length + 1}.jpg';
    avatars[path] = jpeg;
    final p = account?.profile;
    if (p != null) {
      account = Account(
        userId: account!.userId,
        phoneE164: account!.phoneE164,
        phoneDiscoverable: account!.phoneDiscoverable,
        profile: Profile(handle: p.handle, displayName: p.displayName, avatarPath: path),
      );
    }
    return path;
  }

  @override
  Future<void> removeAvatar() async {
    final p = account?.profile;
    if (p == null) return;
    account = Account(
      userId: account!.userId,
      phoneE164: account!.phoneE164,
      phoneDiscoverable: account!.phoneDiscoverable,
      profile: Profile(handle: p.handle, displayName: p.displayName),
    );
  }
}

class FakeLocalFlags implements LocalFlags {
  FakeLocalFlags({this.onboarding = false, this.permissions = false});

  bool onboarding;
  bool permissions;

  @override
  Future<bool> onboardingDone() async => onboarding;
  @override
  Future<void> setOnboardingDone() async => onboarding = true;
  @override
  Future<bool> permissionsSeen() async => permissions;
  @override
  Future<void> setPermissionsSeen() async => permissions = true;
  @override
  Future<void> clearAccountScoped() async => permissions = false;
}

class FakePermissionGateway implements PermissionGateway {
  int requests = 0;
  @override
  Future<bool> requestNotifications() async {
    requests++;
    return true;
  }
}

/// Fausse messagerie avec état : deux comptes, « me » (u1) et Bob (u2).
class FakeMessagingApi implements MessagingApi {
  static const me = 'u1';
  static const bob = FoundUser(id: 'u2', handle: 'bob_ouaga', displayName: 'Bob');

  final Map<String, ConversationSummary> conversations = {};
  final Map<String, List<ChatMessage>> messages = {};
  final Set<String> blocked = {};
  final List<String> phoneSearches = [];
  final List<String> handleSearches = [];
  final List<String> sentClientIds = [];
  bool failNextSend = false;
  int conversationTtl = 72 * 3600;

  /// Coupure réseau simulée : tout appel échoue comme sans connexion.
  bool offline = false;
  bool pinned = false;
  bool archived = false;
  int typingSignals = 0;

  void _net() {
    if (offline) throw const AppFailure(FailureCode.network);
  }

  final List<int?> sentTtls = [];
  DateTime? peerReadUpTo;
  DateTime? peerDeliveredUpTo;
  final Set<String> hiddenForMe = {};
  Map<String, Object?> policies = const {'message_edit_window_minutes': 60};
  int _seq = 0;

  ChatMessage _replace(String id, ChatMessage Function(ChatMessage) change) {
    for (final list in messages.values) {
      final i = list.indexWhere((m) => m.id == id);
      if (i >= 0) return list[i] = change(list[i]);
    }
    throw const AppFailure(FailureCode.messageNotFound);
  }

  ChatMessage _copy(
    ChatMessage m, {
    String? body,
    bool clearBody = false,
    DateTime? editedAt,
    DateTime? deletedAt,
    List<Reaction>? reactions,
  }) => ChatMessage(
    id: m.id,
    kind: m.kind,
    senderId: m.senderId,
    body: clearBody ? null : (body ?? m.body),
    replyToId: m.replyToId,
    replyPreview: m.replyPreview,
    sentAt: m.sentAt,
    expiresAt: m.expiresAt,
    editedAt: editedAt ?? m.editedAt,
    deletedAt: deletedAt ?? m.deletedAt,
    updatedAt: DateTime.now(),
    reactions: reactions ?? m.reactions,
    // Supprimé pour tous : plus de son (comme le serveur).
    mediaPath: clearBody ? null : m.mediaPath,
    durationMs: clearBody ? null : m.durationMs,
    width: clearBody ? null : m.width,
    height: clearBody ? null : m.height,
    senderName: m.senderName,
  );

  @override
  Future<void> editMessage(String messageId, String body) async =>
      _replace(messageId, (m) => _copy(m, body: body, editedAt: DateTime.now()));

  @override
  Future<void> deleteForEveryone(String messageId) async => _replace(
    messageId,
    (m) => _copy(m, clearBody: true, deletedAt: DateTime.now(), reactions: const []),
  );

  @override
  Future<int> setConversationTtl(String conversationId, int seconds) async {
    conversationTtl = seconds;
    final now = DateTime.now();
    (messages[conversationId] ??= []).add(
      ChatMessage(
        id: 'sys-${_seq++}',
        kind: 'system',
        senderId: me,
        body: 'ttl:$seconds',
        sentAt: now,
        expiresAt: now.add(Duration(seconds: seconds)),
        updatedAt: now,
      ),
    );
    return seconds;
  }

  @override
  Future<void> setConversationFlags(String conversationId, {bool? pinned, bool? archived}) async {
    _net();
    this.pinned = pinned ?? this.pinned;
    this.archived = archived ?? this.archived;
  }

  @override
  Future<void> signalTyping(String conversationId) async => typingSignals++;

  final List<Map<String, Object?>> reports = [];
  bool accountDeleted = false;

  @override
  Future<void> report({
    required String reason,
    String? reportedUserId,
    String? conversationId,
    String? messageId,
    String? details,
    bool includeMessage = false,
  }) async {
    _net();
    reports.add({
      'reason': reason,
      'user': reportedUserId,
      'conversation': conversationId,
      'message': messageId,
      'details': details,
      'include': includeMessage,
    });
  }

  @override
  Future<void> deleteMyAccount() async {
    _net();
    accountDeleted = true;
  }

  @override
  Future<void> deleteForMe(String messageId) async => hiddenForMe.add(messageId);

  @override
  Future<void> setReaction(String messageId, String emoji) async => _replace(
    messageId,
    (m) => _copy(
      m,
      reactions: [
        ...m.reactions.where((r) => r.userId != me),
        Reaction(userId: me, emoji: emoji),
      ],
    ),
  );

  @override
  Future<void> removeReaction(String messageId) async => _replace(
    messageId,
    (m) => _copy(m, reactions: m.reactions.where((r) => r.userId != me).toList()),
  );

  @override
  Future<Map<String, Object?>> getClientPolicies() async => policies;

  ConversationSummary _summary(String id, {bool? blockedFlag}) {
    final list = messages[id] ?? const <ChatMessage>[];
    final last = list.isEmpty ? null : list.last;
    return ConversationSummary(
      id: id,
      peerId: bob.id,
      peerHandle: bob.handle,
      peerDisplayName: bob.displayName,
      peerDeleted: false,
      blocked: blockedFlag ?? blocked.contains(bob.id),
      unreadCount: list.where((m) => m.senderId != me).length,
      sortAt: last?.sentAt ?? DateTime.now(),
      lastMessageId: last?.id,
      lastSenderId: last?.senderId,
      lastBody: last?.body,
      lastSentAt: last?.sentAt,
      lastExpiresAt: last?.expiresAt,
      lastKind: last?.kind ?? 'text',
      ttlSeconds: conversationTtl,
      pinned: pinned,
      archived: archived,
      peerReadUpTo: peerReadUpTo,
      peerDeliveredUpTo: peerDeliveredUpTo,
      peerAvatarPath: blocked.contains(bob.id) ? null : bobAvatarPath,
      mutedUntil: muted[id],
    );
  }

  /// Photo de profil de Bob (null : pas de photo).
  String? bobAvatarPath;

  /// Simule un message reçu de Bob.
  ChatMessage receive(String conversationId, String body, {DateTime? expiresAt}) {
    final now = DateTime.now();
    final m = ChatMessage(
      id: 'srv-${_seq++}',
      senderId: bob.id,
      body: body,
      sentAt: now,
      expiresAt: expiresAt ?? now.add(const Duration(hours: 72)),
      updatedAt: now,
    );
    (messages[conversationId] ??= []).add(m);
    return m;
  }

  @override
  Future<List<ConversationSummary>> listConversations() async => _list();

  Future<List<ConversationSummary>> _list() async {
    _net();
    return _listRaw();
  }

  Future<List<ConversationSummary>> _listRaw() async => [
    for (final id in conversations.keys)
      if (!groups.containsKey(id)) _summary(id),
    for (final g in groups.values)
      if (g.roles.containsKey(me)) _groupSummary(g),
  ];

  @override
  Future<FoundUser?> findByHandle(String handle) async {
    handleSearches.add(handle);
    if (handle == awa.handle) return awa;
    return handle == bob.handle && !blocked.contains(bob.id) ? bob : null;
  }

  @override
  Future<FoundUser?> findByPhone(String phoneE164) async {
    phoneSearches.add(phoneE164);
    return null;
  }

  @override
  Future<String> startDirectConversation(String otherUserId) async {
    const id = 'conv-bob';
    conversations[id] = _summary(id);
    messages.putIfAbsent(id, () => []);
    return id;
  }

  @override
  Future<List<ChatMessage>> getMessages(String conversationId, {int limit = 50}) async {
    _net();
    final g = groups[conversationId];
    if (g != null && !g.roles.containsKey(me)) throw const AppFailure(FailureCode.notMember);
    return _messagesFor(conversationId);
  }

  List<ChatMessage> _messagesFor(String conversationId) => [
    for (final m in messages[conversationId] ?? const <ChatMessage>[])
      if (!hiddenForMe.contains(m.id))
        if (m.replyToId == null)
          m
        else
          ChatMessage(
            id: m.id,
            kind: m.kind,
            senderId: m.senderId,
            body: m.body,
            replyToId: m.replyToId,
            replyPreview: _findBody(m.replyToId!),
            replyKind: _findKind(m.replyToId!),
            sentAt: m.sentAt,
            expiresAt: m.expiresAt,
            editedAt: m.editedAt,
            deletedAt: m.deletedAt,
            updatedAt: m.updatedAt,
            reactions: m.reactions,
            mediaPath: m.mediaPath,
            durationMs: m.durationMs,
            width: m.width,
            height: m.height,
            senderName: m.senderName,
          ),
  ];

  String? _findKind(String id) {
    for (final list in messages.values) {
      for (final m in list) {
        if (m.id == id) return m.isDeleted ? null : m.kind;
      }
    }
    return null;
  }

  String? _findBody(String id) {
    for (final list in messages.values) {
      for (final m in list) {
        if (m.id == id) return m.isDeleted ? null : m.body;
      }
    }
    return null;
  }

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String clientMsgId,
    required String body,
    String? replyToId,
    int? ttlSeconds,
  }) async {
    sentClientIds.add(clientMsgId);
    sentTtls.add(ttlSeconds);
    _net();
    if (failNextSend) {
      failNextSend = false;
      throw const AppFailure(FailureCode.network);
    }
    final g = groups[conversationId];
    if (g != null) {
      if (!g.roles.containsKey(me)) throw const AppFailure(FailureCode.notMember);
      if (g.posting == 'admins' && !g.isAdmin(me)) {
        throw const AppFailure(FailureCode.postingRestricted);
      }
    } else if (blocked.contains(bob.id)) {
      throw const AppFailure(FailureCode.blocked);
    }
    final now = DateTime.now();
    final m = ChatMessage(
      id: 'srv-$clientMsgId',
      senderId: me,
      body: body.trim(),
      replyToId: replyToId,
      sentAt: now,
      expiresAt: now.add(
        Duration(
          seconds: ttlSeconds == null || ttlSeconds > conversationTtl
              ? conversationTtl
              : ttlSeconds,
        ),
      ),
      updatedAt: now,
    );
    final list = messages[conversationId] ??= [];
    if (!list.any((x) => x.id == m.id)) list.add(m);
    return m;
  }

  /// Sons déposés côté « serveur » (chemin → octets) et téléchargements effectués.
  final Map<String, Uint8List> storedVoices = {};
  final List<String> downloads = [];
  AppFailure? voiceFailure;

  @override
  Future<ChatMessage> sendVoice({
    required String conversationId,
    required String clientMsgId,
    required Uint8List audio,
    String? replyToId,
    int? ttlSeconds,
  }) async {
    sentClientIds.add(clientMsgId);
    sentTtls.add(ttlSeconds);
    _net();
    if (voiceFailure != null) throw voiceFailure!;
    if (blocked.contains(bob.id)) throw const AppFailure(FailureCode.blocked);
    final list = messages[conversationId] ??= [];
    final existing = list.where((m) => m.id == 'srv-$clientMsgId').firstOrNull;
    if (existing != null) return existing;
    final now = DateTime.now();
    final path = '$conversationId/$clientMsgId.m4a';
    storedVoices[path] = audio;
    final m = ChatMessage(
      id: 'srv-$clientMsgId',
      kind: 'voice',
      senderId: me,
      replyToId: replyToId,
      sentAt: now,
      expiresAt: now.add(
        Duration(
          seconds: ttlSeconds == null || ttlSeconds > conversationTtl
              ? conversationTtl
              : ttlSeconds,
        ),
      ),
      updatedAt: now,
      mediaPath: path,
      durationMs: 5000,
    );
    list.add(m);
    return m;
  }

  @override
  Future<Uint8List> downloadVoice(String mediaPath) async {
    downloads.add(mediaPath);
    _net();
    final bytes = storedVoices[mediaPath];
    if (bytes == null) throw const AppFailure(FailureCode.mediaNotFound);
    return bytes;
  }

  // ---------------------------------------------------------------- photos
  int photoLimit = 5;
  int photosUsed = 0;
  final Map<String, Uint8List> storedPhotos = {};
  final Map<String, Uint8List> storedAvatars = {};
  final List<String> photoDownloads = [];
  final List<String?> sentCaptions = [];

  @override
  Future<PhotoQuota> getPhotoQuota() async {
    _net();
    return PhotoQuota(limit: photoLimit, used: photosUsed);
  }

  @override
  Future<ChatMessage> sendPhoto({
    required String conversationId,
    required String clientMsgId,
    required Uint8List jpeg,
    String? caption,
    String? replyToId,
    int? ttlSeconds,
  }) async {
    sentClientIds.add(clientMsgId);
    sentCaptions.add(caption);
    _net();
    final list = messages[conversationId] ??= [];
    final existing = list.where((m) => m.id == 'srv-$clientMsgId').firstOrNull;
    if (existing != null) return existing;
    if (photosUsed >= photoLimit) throw const AppFailure(FailureCode.photoQuotaReached);
    if (blocked.contains(bob.id)) throw const AppFailure(FailureCode.blocked);
    photosUsed++;
    final now = DateTime.now();
    final path = '$conversationId/$clientMsgId.jpg';
    storedPhotos[path] = jpeg;
    final m = ChatMessage(
      id: 'srv-$clientMsgId',
      kind: 'photo',
      senderId: me,
      body: caption == null || caption.trim().isEmpty ? null : caption.trim(),
      replyToId: replyToId,
      sentAt: now,
      expiresAt: now.add(
        Duration(
          seconds: ttlSeconds == null || ttlSeconds > conversationTtl
              ? conversationTtl
              : ttlSeconds,
        ),
      ),
      updatedAt: now,
      mediaPath: path,
      width: 40,
      height: 30,
    );
    list.add(m);
    return m;
  }

  @override
  Future<Uint8List> downloadPhoto(String mediaPath) async {
    photoDownloads.add(mediaPath);
    _net();
    final bytes = storedPhotos[mediaPath];
    if (bytes == null) throw const AppFailure(FailureCode.mediaNotFound);
    return bytes;
  }

  @override
  Future<Uint8List> downloadAvatar(String avatarPath) async {
    _net();
    final bytes = storedAvatars[avatarPath];
    if (bytes == null) throw const AppFailure(FailureCode.mediaNotFound);
    return bytes;
  }

  /// Simule une photo reçue de Bob.
  ChatMessage receivePhoto(String conversationId, {String? caption, DateTime? expiresAt}) {
    final now = DateTime.now();
    final id = 'srv-${_seq++}';
    final path = '$conversationId/$id.jpg';
    storedPhotos[path] = testJpeg();
    final m = ChatMessage(
      id: id,
      kind: 'photo',
      senderId: bob.id,
      body: caption,
      sentAt: now,
      expiresAt: expiresAt ?? now.add(const Duration(hours: 72)),
      updatedAt: now,
      mediaPath: path,
      width: 40,
      height: 30,
    );
    (messages[conversationId] ??= []).add(m);
    return m;
  }

  /// Simule un vocal reçu de Bob.
  ChatMessage receiveVoice(
    String conversationId, {
    int durationMs = 12000,
    DateTime? expiresAt,
    List<int> audio = const [1, 2, 3, 4],
  }) {
    final now = DateTime.now();
    final id = 'srv-${_seq++}';
    final path = '$conversationId/$id.m4a';
    storedVoices[path] = Uint8List.fromList(audio);
    final m = ChatMessage(
      id: id,
      kind: 'voice',
      senderId: bob.id,
      sentAt: now,
      expiresAt: expiresAt ?? now.add(const Duration(hours: 72)),
      updatedAt: now,
      mediaPath: path,
      durationMs: durationMs,
    );
    (messages[conversationId] ??= []).add(m);
    return m;
  }

  @override
  Future<void> markConversation(
    String conversationId, {
    DateTime? deliveredUpTo,
    DateTime? readUpTo,
  }) async {}

  @override
  Future<List<BlockedUser>> listBlockedUsers() async => [
    if (blocked.contains(bob.id))
      BlockedUser(id: bob.id, handle: bob.handle, displayName: bob.displayName),
  ];

  @override
  Future<void> blockUser(String userId) async => blocked.add(userId);

  @override
  Future<void> unblockUser(String userId) async => blocked.remove(userId);

  // -------------------------------------------------------------------------
  // Groupes
  // -------------------------------------------------------------------------
  static const awa = FoundUser(id: 'u3', handle: 'awa_s', displayName: 'Awa');
  static const names = {me: 'Toussaint', 'u2': 'Bob', 'u3': 'Awa', 'u4': 'Issa'};

  final Map<String, FakeGroup> groups = {};
  final List<GroupInvitation> invitations = [];
  final Map<String, DateTime?> muted = {};

  FakeGroup _group(String id) {
    final g = groups[id];
    if (g == null) throw const AppFailure(FailureCode.notGroup);
    if (!g.roles.containsKey(me)) throw const AppFailure(FailureCode.notMember);
    return g;
  }

  FakeGroup _adminGroup(String id) {
    final g = _group(id);
    if (!g.isAdmin(me)) throw const AppFailure(FailureCode.notAdmin);
    return g;
  }

  /// Ajoute un événement de groupe ({e, a, t, v}) comme le fait le serveur.
  void groupEvent(String id, String e, {String actor = me, String? target, String? value}) {
    final now = DateTime.now();
    (messages[id] ??= []).add(
      ChatMessage(
        id: 'sys-${_seq++}',
        kind: 'system',
        senderId: actor,
        senderName: names[actor],
        body: jsonEncode({
          'e': e,
          'a': names[actor],
          't': target == null ? null : names[target],
          'v': value,
        }),
        sentAt: now,
        expiresAt: now.add(Duration(seconds: conversationTtl)),
        updatedAt: now,
      ),
    );
  }

  /// Crée un groupe dont [owner] est propriétaire, avec [members] (rôle membre).
  FakeGroup seedGroup(
    String id,
    String title, {
    String owner = me,
    Map<String, String> members = const {},
    String posting = 'all',
    String infoEditing = 'admins',
    String? description,
  }) {
    final g = FakeGroup(id, title, description: description)
      ..posting = posting
      ..infoEditing = infoEditing
      ..roles[owner] = 'owner'
      ..roles.addAll(members);
    groups[id] = g;
    messages.putIfAbsent(id, () => []);
    return g;
  }

  /// Simule un message reçu dans un groupe.
  ChatMessage receiveInGroup(String id, String senderId, String body) {
    final now = DateTime.now();
    final m = ChatMessage(
      id: 'srv-${_seq++}',
      senderId: senderId,
      senderName: names[senderId],
      body: body,
      sentAt: now,
      expiresAt: now.add(const Duration(hours: 72)),
      updatedAt: now,
    );
    (messages[id] ??= []).add(m);
    return m;
  }

  ConversationSummary _groupSummary(FakeGroup g) {
    final list = messages[g.id] ?? const <ChatMessage>[];
    final last = list.isEmpty ? null : list.last;
    return ConversationSummary(
      id: g.id,
      kind: 'group',
      peerId: null,
      peerHandle: null,
      peerDisplayName: null,
      peerDeleted: false,
      blocked: false,
      unreadCount: list.where((m) => m.senderId != me && !m.isSystem).length,
      sortAt: last?.sentAt ?? g.createdAt,
      lastMessageId: last?.id,
      lastSenderId: last?.senderId,
      lastSenderName: last?.senderId == me ? null : last?.senderName,
      lastBody: last?.body,
      lastSentAt: last?.sentAt,
      lastExpiresAt: last?.expiresAt,
      lastKind: last?.kind ?? 'text',
      ttlSeconds: conversationTtl,
      pinned: false,
      archived: false,
      mutedUntil: muted[g.id],
      groupTitle: g.title,
      groupDescription: g.description,
      groupAvatarPath: g.avatarPath,
      memberCount: g.roles.length,
      myRole: g.roles[me],
      posting: g.posting,
      infoEditing: g.infoEditing,
    );
  }

  @override
  Future<String> createGroup({
    required String title,
    String? description,
    List<String> inviteeIds = const [],
  }) async {
    _net();
    if (title.trim().isEmpty || title.trim().length > 60) {
      throw const AppFailure(FailureCode.groupTitleInvalid);
    }
    final id = 'grp-${_seq++}';
    seedGroup(id, title.trim(), description: description).invited.addAll(inviteeIds);
    groupEvent(id, 'created', value: title.trim());
    return id;
  }

  @override
  Future<int> inviteToGroup(String conversationId, List<String> userIds) async {
    _net();
    final g = _adminGroup(conversationId);
    var n = 0;
    for (final u in userIds) {
      if (g.roles.containsKey(u) || g.invited.contains(u)) continue;
      g.invited.add(u);
      n++;
    }
    return n;
  }

  @override
  Future<List<GroupInvitation>> listInvitations() async {
    _net();
    return List.of(invitations);
  }

  @override
  Future<String?> respondToInvitation(String invitationId, {required bool accept}) async {
    _net();
    final i = invitations.indexWhere((x) => x.id == invitationId);
    if (i < 0) throw const AppFailure(FailureCode.invitationNotFound);
    final inv = invitations.removeAt(i);
    if (!accept) return null;
    final g =
        groups[inv.conversationId] ??
        seedGroup(inv.conversationId, inv.title, owner: bob.id, description: inv.description);
    g.roles[me] = 'member';
    groupEvent(inv.conversationId, 'joined');
    return inv.conversationId;
  }

  @override
  Future<List<GroupMember>> getMembers(String conversationId) async {
    _net();
    final g = _group(conversationId);
    const order = {'owner': 0, 'admin': 1, 'member': 2};
    final active = g.roles.entries.toList()
      ..sort((a, b) => order[a.value]!.compareTo(order[b.value]!));
    return [
      for (final e in active)
        GroupMember(userId: e.key, displayName: names[e.key] ?? e.key, role: e.value),
      if (g.isAdmin(me))
        for (final u in g.invited)
          GroupMember(userId: u, displayName: names[u] ?? u, role: 'member', invited: true),
    ];
  }

  @override
  Future<void> setMemberRole(String conversationId, String userId, {required bool admin}) async {
    _net();
    final g = _adminGroup(conversationId);
    if (!admin && g.roles[me] != 'owner') throw const AppFailure(FailureCode.notOwner);
    if (g.roles[userId] == null || g.roles[userId] == 'owner') {
      throw const AppFailure(FailureCode.roleInvalid);
    }
    g.roles[userId] = admin ? 'admin' : 'member';
    groupEvent(conversationId, admin ? 'admin_added' : 'admin_removed', target: userId);
  }

  @override
  Future<void> transferOwnership(String conversationId, String userId) async {
    _net();
    final g = _group(conversationId);
    if (g.roles[me] != 'owner') throw const AppFailure(FailureCode.notOwner);
    g.roles[me] = 'admin';
    g.roles[userId] = 'owner';
    groupEvent(conversationId, 'owner_changed', target: userId);
  }

  @override
  Future<void> removeMember(String conversationId, String userId) async {
    _net();
    final g = _adminGroup(conversationId);
    final role = g.roles[userId];
    if (role == 'owner' || (role == 'admin' && g.roles[me] != 'owner')) {
      throw const AppFailure(FailureCode.roleInvalid);
    }
    g.roles.remove(userId);
    g.invited.remove(userId);
    groupEvent(conversationId, 'removed', target: userId);
  }

  @override
  Future<void> leaveGroup(String conversationId) async {
    _net();
    final g = _group(conversationId);
    final wasOwner = g.roles.remove(me) == 'owner';
    groupEvent(conversationId, 'left');
    if (wasOwner && g.roles.isNotEmpty) {
      final next = g.roles.entries.firstWhere(
        (e) => e.value == 'admin',
        orElse: () => g.roles.entries.first,
      );
      g.roles[next.key] = 'owner';
    }
  }

  @override
  Future<void> updateGroupInfo(String conversationId, {String? title, String? description}) async {
    _net();
    final g = _group(conversationId);
    if (g.infoEditing == 'admins' && !g.isAdmin(me)) throw const AppFailure(FailureCode.notAdmin);
    if (title != null && title.trim() != g.title) {
      if (title.trim().isEmpty) throw const AppFailure(FailureCode.groupTitleInvalid);
      g.title = title.trim();
      groupEvent(conversationId, 'title', value: g.title);
    }
    if (description != null && description.trim() != (g.description ?? '')) {
      g.description = description.trim().isEmpty ? null : description.trim();
      groupEvent(conversationId, 'description');
    }
  }

  @override
  Future<void> setGroupSettings(
    String conversationId, {
    String? posting,
    String? infoEditing,
  }) async {
    _net();
    final g = _adminGroup(conversationId);
    if (posting != null && posting != g.posting) {
      g.posting = posting;
      groupEvent(conversationId, 'posting', value: posting);
    }
    if (infoEditing != null && infoEditing != g.infoEditing) {
      g.infoEditing = infoEditing;
      groupEvent(conversationId, 'info_editing', value: infoEditing);
    }
  }

  @override
  Future<void> setMute(String conversationId, DateTime? until) async {
    _net();
    muted[conversationId] = until;
  }

  @override
  Future<void> setGroupAvatar(String conversationId, Uint8List jpeg) async {
    _net();
    final g = _group(conversationId);
    if (g.infoEditing == 'admins' && !g.isAdmin(me)) throw const AppFailure(FailureCode.notAdmin);
    final path = 'groups/$conversationId/${_seq++}.jpg';
    storedAvatars[path] = jpeg;
    g.avatarPath = path;
    groupEvent(conversationId, 'photo');
  }

  @override
  Future<void> removeGroupAvatar(String conversationId) async {
    _net();
    final g = _group(conversationId);
    if (g.infoEditing == 'admins' && !g.isAdmin(me)) throw const AppFailure(FailureCode.notAdmin);
    g.avatarPath = null;
    groupEvent(conversationId, 'photo_removed');
  }
}

/// État d'un groupe dans le faux serveur.
class FakeGroup {
  FakeGroup(this.id, this.title, {this.description});

  final String id;
  String title;
  String? description;
  String? avatarPath;
  String posting = 'all';
  String infoEditing = 'admins';
  final DateTime createdAt = DateTime.now();

  /// Membres actifs : identifiant → rôle (owner, admin, member).
  final Map<String, String> roles = {};
  final Set<String> invited = {};

  bool isAdmin(String userId) => roles[userId] == 'owner' || roles[userId] == 'admin';
}

/// Petite photo JPEG valide (40 × 30) pour les tests.
Uint8List testJpeg({int width = 40, int height = 30}) {
  final image = img.Image(width: width, height: height)..clear(img.ColorRgb8(90, 40, 200));
  return img.encodeJpg(image, quality: 80);
}

/// Faux sélecteur : renvoie [photo] (null = la personne renonce).
class FakePhotoPicker implements PhotoPicker {
  Uint8List? photo = testJpeg();
  final List<PhotoSource> sources = [];
  AppFailure? failure;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    sources.add(source);
    if (failure != null) throw failure!;
    return photo;
  }
}

/// Faux micro : enregistre « instantanément » les octets [audio].
class FakeVoiceRecorder implements VoiceRecorder {
  MicPermission permission = MicPermission.granted;
  Uint8List audio = Uint8List.fromList(List<int>.generate(64, (i) => i));
  bool recording = false;
  int starts = 0;
  int cancels = 0;

  @override
  Future<MicPermission> ensurePermission() async => permission;

  @override
  Future<void> start() async {
    starts++;
    recording = true;
  }

  @override
  Future<Uint8List?> stop() async {
    if (!recording) return null;
    recording = false;
    return audio;
  }

  @override
  Future<void> cancel() async {
    cancels++;
    recording = false;
  }

  @override
  Future<void> dispose() async {}
}

/// Faux lecteur : retient ce qui est joué ; [finish] simule la fin du son.
class FakeAudioEngine implements AudioEngine {
  final _position = StreamController<Duration>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final List<Uint8List> played = [];
  bool playing = false;
  double speed = 1.0;
  Duration? seekedTo;

  void emitPosition(Duration d) => _position.add(d);
  void finish() {
    playing = false;
    _completed.add(null);
  }

  @override
  Stream<Duration> get position => _position.stream;
  @override
  Stream<void> get completed => _completed.stream;

  @override
  Future<void> play(Uint8List bytes, {double speed = 1.0}) async {
    played.add(bytes);
    this.speed = speed;
    playing = true;
  }

  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> resume() async => playing = true;
  @override
  Future<void> seek(Duration position) async => seekedTo = position;
  @override
  Future<void> setSpeed(double speed) async => this.speed = speed;
  @override
  Future<void> stop() async => playing = false;
  @override
  Future<void> dispose() async {}
}

class FakeRealtimeService implements RealtimeService {
  final _controller = StreamController<RealtimeSignal>.broadcast();
  final _status = ValueNotifier(const RealtimeStatus(RealtimeState.stopped));
  String? startedFor;

  @override
  ValueListenable<RealtimeStatus> get status => _status;

  void emit(String conversationId, {String event = 'message'}) =>
      _controller.add(RealtimeSignal(event: event, conversationId: conversationId));

  @override
  Stream<RealtimeSignal> get signals => _controller.stream;

  @override
  Future<void> start(String userId) async {
    startedFor = userId;
    _status.value = const RealtimeStatus(RealtimeState.connected);
  }

  @override
  Future<void> stop() async {
    startedFor = null;
    _status.value = const RealtimeStatus(RealtimeState.stopped);
  }
}

class TestDeps {
  TestDeps({
    FakeAuthService? auth,
    FakeAccountApi? api,
    FakeLocalFlags? flags,
    FakeMessagingApi? messaging,
  }) : auth = auth ?? FakeAuthService(),
       api = api ?? FakeAccountApi(),
       flags = flags ?? FakeLocalFlags(),
       messaging = messaging ?? FakeMessagingApi() {
    // Une photo de profil déposée est ensuite téléchargeable, comme sur le serveur.
    this.api.avatars = this.messaging.storedAvatars;
  }

  final FakeAuthService auth;
  final FakeAccountApi api;
  final FakeLocalFlags flags;
  final permissions = FakePermissionGateway();
  final FakeMessagingApi messaging;

  /// Stockage local partagé (permet de simuler un redémarrage de l'application).
  final store = MemoryLocalStore();
  final vault = MemoryMediaVault();
  final realtime = FakeRealtimeService();
  final recorder = FakeVoiceRecorder();
  final audio = FakeAudioEngine();
  final photos = FakePhotoPicker();

  List<Override> get overrides => [
    authServiceProvider.overrideWithValue(auth),
    accountApiProvider.overrideWithValue(api),
    localFlagsProvider.overrideWithValue(flags),
    permissionGatewayProvider.overrideWithValue(permissions),
    appVersionProvider.overrideWithValue('0.1.0-test'),
    messagingApiProvider.overrideWithValue(messaging),
    localStoreProvider.overrideWithValue(store),
    mediaVaultProvider.overrideWithValue(vault),
    realtimeServiceProvider.overrideWithValue(realtime),
    voiceRecorderProvider.overrideWithValue(recorder),
    audioEngineProvider.overrideWithValue(audio),
    photoPickerProvider.overrideWithValue(photos),
    // Préparation synchrone (pas d'isolat dans les tests de widgets).
    photoPreparerProvider.overrideWithValue(
      (raw, {avatar = false}) async =>
          processPhotoSync(raw, square: avatar, maxSide: avatar ? kAvatarSide : kPhotoMaxSide) ??
          (throw const AppFailure(FailureCode.mediaInvalid)),
    ),
  ];

  /// Conteneur dont le contrôleur de session reste écouté, comme dans l'application.
  ProviderContainer container() {
    final c = ProviderContainer(overrides: overrides, retry: (_, _) => null);
    c.listen(sessionControllerProvider, (_, _) {});
    return c;
  }

  /// Monte un écran isolé dans un MaterialApp thémé.
  Widget wrap(Widget child) => ProviderScope(
    overrides: overrides,
    retry: (_, _) => null,
    child: MaterialApp(theme: PrivioTheme.light, home: child),
  );
}
