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
import 'package:privio/data/services/device_services.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/state/app_lock_providers.dart';
import 'package:privio/state/data_providers.dart';
import 'package:privio/data/services/audio/voice_recorder.dart';
import 'package:privio/data/services/auth_service.dart';
import 'package:privio/data/services/messaging_api.dart';
import 'package:privio/data/services/realtime_service.dart';
import 'package:privio/data/storage/local_store.dart';
import 'package:privio/data/storage/media_vault.dart';
import 'package:privio/data/services/admin_api.dart';
import 'package:privio/data/services/permission_gateway.dart';
import 'package:privio/domain/models/console.dart';
import 'package:privio/domain/models/moderation.dart';
import 'package:privio/state/console_providers.dart';
import 'package:privio/data/services/push_service.dart';
import 'package:privio/data/services/photo_picker.dart';
import 'package:privio/data/storage/local_flags.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/state/messaging_providers.dart';
import 'package:privio/state/providers.dart';
import 'package:privio/state/push_providers.dart';
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
  /// Lot 5.3 : situation de modération renvoyée par le « serveur ».
  ModerationStatus moderation = ModerationStatus.none;
  String? appealText;
  int warningsAcknowledged = 0;

  @override
  Future<ModerationStatus> moderationStatus() async => moderation;

  @override
  Future<void> submitAppeal(String sanctionId, String text) async {
    final s = moderation.suspension;
    if (s == null || s.appealed) throw const AppFailure(FailureCode.appealNotAllowed);
    if (text.trim().length < 3) throw const AppFailure(FailureCode.appealInvalid);
    appealText = text;
    moderation = ModerationStatus(
      suspension: SuspensionInfo(id: s.id, reason: s.reason, until: s.until, appealed: true),
    );
  }

  @override
  Future<void> acknowledgeWarning(String sanctionId) async {
    warningsAcknowledged++;
    moderation = ModerationStatus(suspension: moderation.suspension);
  }

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

  /// Lot 7.1a : « À propos » enregistré.
  @override
  Future<String?> setAbout(String text) async {
    final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length > 140) throw const AppFailure(FailureCode.unknown);
    final a = account!;
    final p = a.profile!;
    account = Account(
      userId: a.userId,
      phoneE164: a.phoneE164,
      phoneDiscoverable: a.phoneDiscoverable,
      profile: Profile(
        handle: p.handle,
        displayName: p.displayName,
        about: t.isEmpty ? null : t,
        avatarPath: p.avatarPath,
      ),
    );
    return t.isEmpty ? null : t;
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

  final List<String> pushTokens = [];
  int pushUnregistered = 0;

  @override
  Future<void> registerPushToken(String token) async => pushTokens.add(token);

  @override
  Future<void> unregisterPushToken() async => pushUnregistered++;

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
  bool push = true;
  String quick = '❤️';

  @override
  Future<bool> pushEnabled() async => push;
  @override
  Future<void> setPushEnabled(bool value) async => push = value;
  @override
  Future<String> quickReaction() async => quick;
  @override
  Future<void> setQuickReaction(String emoji) async => quick = emoji;

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

  String autoPhoto = 'always';
  Map<String, int> usage = {};

  @override
  Future<String> photoAutoDownload() async => autoPhoto;
  @override
  Future<void> setPhotoAutoDownload(String value) async => autoPhoto = value;
  @override
  Future<Map<String, int>> dataUsage() async => Map.of(usage);
  @override
  Future<void> saveDataUsage(Map<String, int> value) async => usage = Map.of(value);
}

/// Empreinte rapide pour les tests (même interface, une seule itération, sans isolat).
class FastPinHasher extends PinHasher {
  const FastPinHasher() : super(useIsolate: false);

  @override
  Future<String> hash(String pin, List<int> salt, int iterations) => super.hash(pin, salt, 1);
}

class FakeBiometricGate implements BiometricGate {
  bool isAvailable = false;
  bool accept = true;
  int prompts = 0;

  @override
  Future<bool> available() async => isAvailable;

  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return accept;
  }
}

class FakeNetworkMonitor implements NetworkMonitor {
  NetKind kind = NetKind.mobile;
  final _changes = StreamController<NetKind>.broadcast();

  void set(NetKind k) {
    kind = k;
    _changes.add(k);
  }

  @override
  Future<NetKind> current() async => kind;

  @override
  Stream<NetKind> changes() => _changes.stream;
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

  /// La liste des discussions échoue (erreur du serveur, pas de réseau).
  bool failList = false;
  int conversationTtl = 72 * 3600;

  /// Dernier réglage de durée reçu (discussion, secondes).
  (String, int)? lastTtlSet;

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
    lastTtlSet = (conversationId, seconds);
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

  /// Lot 7.1a : fiches (À propos visible, groupes en commun).
  final contactAbout = <String, String>{};
  final commonGroups = <String, List<CommonGroup>>{};

  @override
  Future<ContactProfile?> getContactProfile(String userId) async {
    _net();
    final c = conversations.values.where((c) => c.peerId == userId).firstOrNull;
    if (c == null) return null;
    return ContactProfile(
      userId: userId,
      handle: c.peerHandle ?? 'inconnu',
      displayName: c.peerDisplayName ?? '',
      about: contactAbout[userId],
      avatarPath: c.peerAvatarPath,
    );
  }

  @override
  Future<List<CommonGroup>> listCommonGroups(String userId) async =>
      commonGroups[userId] ?? const [];

  @override
  Future<List<ChatMessage>> listConversationMedia(String conversationId) async => [
    for (final m in _messagesFor(conversationId).reversed)
      if ((m.kind == 'photo' || m.kind == 'voice') && m.mediaPath != null && m.deletedAt == null) m,
  ];

  /// Lot 5.4 : demandes d'assistance et réponses.
  final supportRequests = <SupportRequest>[];

  @override
  Future<List<SupportRequest>> mySupportRequests() async {
    _net();
    return List.of(supportRequests);
  }

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
    final list = _visible(id);
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
      clearedBefore: clearedBefore[id],
      clearRequestBy: clearRequests[id],
      clearRequestExpiresAt: clearRequests[id] == null
          ? null
          : DateTime.now().add(const Duration(hours: 24)),
    );
  }

  /// Messages encore visibles pour moi (après un « vider » éventuel).
  List<ChatMessage> _visible(String id) {
    final before = clearedBefore[id];
    return [
      for (final m in messages[id] ?? const <ChatMessage>[])
        if (before == null || m.sentAt.isAfter(before)) m,
    ];
  }

  // -------------------------------------------------------------------------
  // Confidentialité, présence, vider (lot 4.3)
  // -------------------------------------------------------------------------
  PrivacySettings privacy = const PrivacySettings();
  final List<PrivacySettings> privacySaves = [];
  bool failPrivacy = false;
  final List<bool> presenceTouches = [];
  final Map<String, UserPresence> presences = {};
  final Map<String, DateTime> clearedBefore = {};

  /// Demande « vider pour nous deux » en cours : identifiant de qui l'a faite.
  final Map<String, String> clearRequests = {};

  @override
  Future<PrivacySettings> getMyPrivacy() async {
    _net();
    return privacy;
  }

  @override
  Future<void> setMyPrivacy(PrivacySettings settings) async {
    _net();
    if (failPrivacy) throw const AppFailure(FailureCode.privacySettingInvalid);
    privacy = settings;
    privacySaves.add(settings);
  }

  @override
  Future<void> touchPresence({required bool online}) async => presenceTouches.add(online);

  @override
  Future<UserPresence> getPresence(String userId) async {
    _net();
    return presences[userId] ?? const UserPresence();
  }

  void _wipe(String id) {
    messages[id]?.clear();
    clearRequests.remove(id);
    clearedBefore[id] = DateTime.now();
  }

  @override
  Future<String> clearConversation(String conversationId, {required bool everyone}) async {
    _net();
    if (!everyone) {
      clearedBefore[conversationId] = DateTime.now();
      return 'cleared';
    }
    final g = groups[conversationId];
    if (g != null) {
      if (!g.isAdmin(me)) throw const AppFailure(FailureCode.notAdmin);
      _wipe(conversationId);
      return 'cleared';
    }
    if (blocked.contains(bob.id)) throw const AppFailure(FailureCode.clearNotAllowed);
    if (clearRequests[conversationId] == bob.id) {
      _wipe(conversationId);
      return 'cleared';
    }
    clearRequests[conversationId] = me;
    return 'requested';
  }

  @override
  Future<String> respondClearRequest(String conversationId, {required bool accept}) async {
    _net();
    final by = clearRequests[conversationId];
    if (by == null || by == me) throw const AppFailure(FailureCode.clearRequestNotFound);
    if (!accept) {
      clearRequests.remove(conversationId);
      return 'refused';
    }
    _wipe(conversationId);
    return 'cleared';
  }

  @override
  Future<void> cancelClearRequest(String conversationId) async {
    _net();
    if (clearRequests[conversationId] == me) clearRequests.remove(conversationId);
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
  Future<List<ConversationSummary>> listConversations() async {
    // Lot 4.8 : réseau lent simulé (la liste n'arrive qu'à l'ouverture de la barrière).
    if (listGate != null) await listGate!.future;
    return _list();
  }

  /// Lot 4.8 : barrières pour simuler un serveur lent (création, liste des discussions).
  Completer<void>? createGate;
  Completer<void>? listGate;

  Future<List<ConversationSummary>> _list() async {
    _net();
    if (failList) throw const AppFailure(FailureCode.unknown);
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

  // --- Demandes de connexion (lot 4.7) ------------------------------------------
  /// Comme le serveur avant le lot 4.7 si false (tests antérieurs : écriture directe).
  bool requestsRequired = false;

  /// Réglage de Bob : accepte-t-il les demandes ?
  bool peerAcceptsRequests = true;
  bool acceptRequests = true;
  final List<ConnectionRequest> requests = [];
  final List<(String, ConnectionAction)> responses = [];
  DateTime? retryAt;
  int _reqSeq = 0;

  bool _connected(String userId) => userId == bob.id && conversations.containsKey('conv-bob');

  /// Simule une demande reçue de Bob.
  ConnectionRequest receiveConnectionRequest({String? note}) {
    final now = DateTime.now();
    final r = ConnectionRequest(
      id: 'req-${_reqSeq++}',
      incoming: true,
      userId: bob.id,
      handle: bob.handle,
      displayName: bob.displayName,
      note: note,
      status: 'pending',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
    );
    requests.add(r);
    return r;
  }

  @override
  Future<ConnectionStatus> connectionStatus(String userId) async {
    _net();
    if (!requestsRequired || _connected(userId)) {
      return ConnectionStatus(
        state: LinkState.connected,
        conversationId: _connected(userId) ? 'conv-bob' : null,
      );
    }
    for (final r in requests.where((r) => r.userId == userId && r.pending)) {
      return ConnectionStatus(
        state: r.incoming ? LinkState.incoming : LinkState.outgoing,
        requestId: r.id,
      );
    }
    if (retryAt != null && retryAt!.isAfter(DateTime.now())) {
      return ConnectionStatus(state: LinkState.refused, retryAt: retryAt);
    }
    return const ConnectionStatus(state: LinkState.none);
  }

  @override
  Future<ConnectionSendResult> sendConnectionRequest(String userId, {String? note}) async {
    _net();
    if (!requestsRequired || _connected(userId)) {
      return ConnectionSendResult(
        connected: true,
        conversationId: await startDirectConversation(userId),
      );
    }
    if (!peerAcceptsRequests || blocked.contains(userId)) {
      throw const AppFailure(FailureCode.connectionNotAllowed);
    }
    final incoming = requests.where((r) => r.userId == userId && r.incoming && r.pending);
    if (incoming.isNotEmpty) {
      final id = await respondConnectionRequest(incoming.first.id, ConnectionAction.accept);
      return ConnectionSendResult(connected: true, conversationId: id);
    }
    final now = DateTime.now();
    final r = ConnectionRequest(
      id: 'req-${_reqSeq++}',
      incoming: false,
      userId: userId,
      handle: bob.handle,
      displayName: bob.displayName,
      note: note,
      status: 'pending',
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
    );
    requests.add(r);
    return ConnectionSendResult(connected: false, requestId: r.id);
  }

  @override
  Future<String?> respondConnectionRequest(String requestId, ConnectionAction action) async {
    _net();
    final r = requests.where((r) => r.id == requestId && r.pending).firstOrNull;
    if (r == null) throw const AppFailure(FailureCode.connectionRequestNotFound);
    requests.remove(r);
    responses.add((requestId, action));
    switch (action) {
      case ConnectionAction.accept:
        final id = await startDirectConversation(r.userId);
        if (r.note != null) {
          final now = DateTime.now();
          (messages[id] ??= []).add(
            ChatMessage(
              id: 'srv-${_seq++}',
              kind: 'text',
              senderId: r.incoming ? r.userId : me,
              body: r.note,
              sentAt: now,
              expiresAt: now.add(const Duration(minutes: 5)),
              updatedAt: now,
            ),
          );
        }
        return id;
      case ConnectionAction.block:
        blocked.add(r.userId);
        return null;
      case ConnectionAction.refuse:
        return null;
    }
  }

  @override
  Future<void> cancelConnectionRequest(String requestId) async {
    _net();
    requests.removeWhere((r) => r.id == requestId);
  }

  @override
  Future<List<ConnectionRequest>> listConnectionRequests() async => [...requests];

  @override
  Future<bool> getAcceptConnectionRequests() async => acceptRequests;

  @override
  Future<void> setAcceptConnectionRequests(bool accept) async {
    _net();
    acceptRequests = accept;
  }

  @override
  Future<List<ChatMessage>> getMessages(String conversationId, {int limit = 50}) async {
    _net();
    final g = groups[conversationId];
    if (g != null && !g.roles.containsKey(me)) throw const AppFailure(FailureCode.notMember);
    return _messagesFor(conversationId);
  }

  List<ChatMessage> _messagesFor(String conversationId) => [
    for (final m in _visible(conversationId))
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
    List<String> mentions = const [],
  }) async {
    sentClientIds.add(clientMsgId);
    sentTtls.add(ttlSeconds);
    sentMentions.add(mentions);
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
      mentions: g == null ? const [] : mentions.where(g.roles.containsKey).toList(),
    );
    final list = messages[conversationId] ??= [];
    if (!list.any((x) => x.id == m.id)) list.add(m);
    return m;
  }

  /// Mentions envoyées avec chaque message texte (lot 7.1b).
  final List<List<String>> sentMentions = [];

  /// Sons déposés côté « serveur » (chemin → octets) et téléchargements effectués.
  final Map<String, Uint8List> storedVoices = {};
  final List<String> downloads = [];
  AppFailure? voiceFailure;

  /// Profils sonores reçus avec les vocaux (lot 4.5), par identifiant client.
  final Map<String, List<int>?> sentWaveforms = {};

  @override
  Future<ChatMessage> sendVoice({
    required String conversationId,
    required String clientMsgId,
    required Uint8List audio,
    String? replyToId,
    int? ttlSeconds,
    List<int>? waveform,
  }) async {
    sentClientIds.add(clientMsgId);
    sentWaveforms[clientMsgId] = waveform;
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
      waveform: waveform,
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
    List<int>? waveform,
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
      waveform: waveform,
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
  ChatMessage receiveInGroup(
    String id,
    String senderId,
    String body, {
    List<String> mentions = const [],
  }) {
    final now = DateTime.now();
    final m = ChatMessage(
      id: 'srv-${_seq++}',
      senderId: senderId,
      senderName: names[senderId],
      body: body,
      sentAt: now,
      expiresAt: now.add(const Duration(hours: 72)),
      updatedAt: now,
      mentions: mentions,
    );
    (messages[id] ??= []).add(m);
    return m;
  }

  ConversationSummary _groupSummary(FakeGroup g) {
    final list = _visible(g.id);
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
      clearedBefore: clearedBefore[g.id],
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
    if (createGate != null) await createGate!.future;
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

  // ------------------------------------------------------------------------
  // Lot 7.1b : codes, demandes d'adhésion
  // ------------------------------------------------------------------------
  /// Groupes connus par code (code → groupe ; titre et membres pour l'aperçu).
  final Map<String, String> codes = {};
  final Map<String, GroupPreview> codePreviews = {};

  /// Demandes reçues (groupe → demandes) et mes demandes envoyées.
  final Map<String, List<JoinRequest>> joinRequests = {};
  final List<MyJoinRequest> myJoinRequests = [];
  final List<(String, bool)> joinResponses = [];
  final List<String> previewedCodes = [];
  int _codeSeq = 0;

  String _newCode() {
    const signs = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final n = _codeSeq++;
    return 'PRV-7K3Q${signs[n % 32]}X';
  }

  @override
  Future<String> getGroupInviteCode(String conversationId) async {
    _net();
    final g = _adminGroup(conversationId);
    final existing = codes.entries.where((e) => e.value == g.id).firstOrNull?.key;
    if (existing != null) return existing;
    final code = _newCode();
    codes[code] = g.id;
    return code;
  }

  @override
  Future<String> resetGroupInviteCode(String conversationId) async {
    _net();
    final g = _adminGroup(conversationId);
    codes.removeWhere((_, v) => v == g.id);
    final code = _newCode();
    codes[code] = g.id;
    return code;
  }

  @override
  Future<GroupJoinSettings> getGroupJoinSettings(String conversationId) async {
    _net();
    final g = _adminGroup(conversationId);
    return GroupJoinSettings(
      approvalRequired: g.joinApproval,
      hasCode: codes.containsValue(g.id),
      pendingRequests: joinRequests[g.id]?.length ?? 0,
    );
  }

  @override
  Future<void> setGroupJoinApproval(String conversationId, {required bool required}) async {
    _net();
    _adminGroup(conversationId).joinApproval = required;
  }

  @override
  Future<GroupPreview> previewGroupByCode(String code) async {
    _net();
    previewedCodes.add(code);
    return codePreviews[code] ?? const GroupPreview(status: JoinStatus.invalid);
  }

  @override
  Future<JoinResult> joinGroupByCode(String code) async {
    _net();
    final p = codePreviews[code];
    if (p == null) return const JoinResult(status: JoinStatus.invalid);
    switch (p.status) {
      case JoinStatus.open:
        final id = p.conversationId ?? 'grp-code';
        final g = groups[id] ?? seedGroup(id, p.title ?? 'Groupe', owner: bob.id);
        g.roles[me] = 'member';
        groupEvent(id, 'joined');
        codePreviews[code] = GroupPreview(
          status: JoinStatus.member,
          conversationId: id,
          title: p.title,
          memberCount: g.roles.length,
        );
        return JoinResult(status: JoinStatus.joined, conversationId: id);
      case JoinStatus.approval:
        codePreviews[code] = GroupPreview(
          status: JoinStatus.pending,
          conversationId: p.conversationId,
          title: p.title,
          memberCount: p.memberCount,
        );
        myJoinRequests.add(
          MyJoinRequest(
            conversationId: p.conversationId ?? 'grp-code',
            title: p.title ?? 'Groupe',
            createdAt: DateTime.now(),
          ),
        );
        return JoinResult(status: JoinStatus.requested, conversationId: p.conversationId);
      default:
        return JoinResult(status: p.status, conversationId: p.conversationId);
    }
  }

  @override
  Future<void> cancelJoinRequest(String conversationId) async {
    _net();
    myJoinRequests.removeWhere((r) => r.conversationId == conversationId);
  }

  @override
  Future<List<MyJoinRequest>> listMyJoinRequests() async {
    _net();
    return List.of(myJoinRequests);
  }

  @override
  Future<List<JoinRequest>> listGroupJoinRequests(String conversationId) async {
    _net();
    _adminGroup(conversationId);
    return List.of(joinRequests[conversationId] ?? const []);
  }

  @override
  Future<void> respondToJoinRequest(String requestId, {required bool approve}) async {
    _net();
    joinResponses.add((requestId, approve));
    for (final e in joinRequests.entries) {
      final r = e.value.where((x) => x.id == requestId).firstOrNull;
      if (r == null) continue;
      e.value.remove(r);
      if (approve) {
        groups[e.key]?.roles[r.userId] = 'member';
        groupEvent(e.key, 'joined', actor: r.userId);
      }
      return;
    }
    throw const AppFailure(FailureCode.joinRequestNotFound);
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
  bool joinApproval = true;
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

  /// Photos rendues par la sélection multiple (par défaut : la photo unique).
  List<Uint8List>? many;
  final List<int> limits = [];

  @override
  Future<List<Uint8List>> pickMany({required int limit}) async {
    sources.add(PhotoSource.gallery);
    limits.add(limit);
    if (failure != null) throw failure!;
    final all = many ?? (photo == null ? const <Uint8List>[] : [photo!]);
    return all.take(limit).toList();
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
    paused = false;
  }

  /// Lot 4.5 : pause / reprise et niveaux sonores simulés ([emitLevel]).
  bool paused = false;
  int pauses = 0;
  int resumes = 0;
  final _levels = StreamController<double>.broadcast();

  void emitLevel(double level) => _levels.add(level);

  @override
  Stream<double> get levels => _levels.stream;

  @override
  Future<void> pause() async {
    pauses++;
    paused = true;
  }

  @override
  Future<void> resume() async {
    resumes++;
    paused = false;
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

/// Console (lot 5.1) : le « serveur » décide de l'accès ; chaque consultation est comptée.
class FakeAdminApi implements AdminApi {
  bool admin = false;
  int dashboardCalls = 0;
  ConsoleDashboard board = ConsoleDashboard(
    generatedAt: DateTime(2026, 11, 13, 18, 30),
    countingSince: DateTime(2026, 11, 13),
    accountsTotal: 42,
    active24h: 17,
    active7d: 30,
    new7d: 5,
    messagesToday: 120,
    messages7d: 860,
    voice7d: 64,
    photos7d: 31,
    messagesLive: 400,
    groupsTotal: 6,
    groupsCreated7d: 2,
    invitationsPending: 3,
    requestsPending: 4,
    requestsAccepted7d: 9,
    requestsRefused7d: 1,
    pushSent24h: 210,
    storageVoiceBytes: 3 * 1024 * 1024 + 300 * 1024,
    storagePhotoBytes: 12 * 1024 * 1024,
    reportsOpen: 1,
  );

  /// Lot 5.2 : quelques réglages représentatifs, validés comme sur le serveur.
  final policyList = <ConsolePolicy>[
    const ConsolePolicy(
      key: 'photo_daily_limit',
      category: 'media',
      label: 'Photos par compte et par jour',
      unit: 'nb',
      valueType: 'integer',
      value: 5,
      defaultValue: 5,
      min: 0,
      max: 10,
      clientVisible: true,
      effect: 'Compté sur la journée en cours.',
    ),
    const ConsolePolicy(
      key: 'group_max_members',
      category: 'groups',
      label: 'Membres au plus par groupe',
      unit: 'nb',
      valueType: 'integer',
      value: 25,
      defaultValue: 25,
      min: 2,
      max: 100,
    ),
    const ConsolePolicy(
      key: 'connection_requests_required',
      category: 'requests',
      label: 'Premier contact par demande de connexion',
      unit: 'bool',
      valueType: 'boolean',
      value: true,
      defaultValue: true,
    ),
    const ConsolePolicy(
      key: 'photo_max_bytes',
      category: 'advanced',
      label: 'Taille maximale d’une photo',
      unit: 'o',
      valueType: 'integer',
      value: 1048576,
      defaultValue: 1048576,
      min: 131072,
      max: 2097152,
      advanced: true,
    ),
    const ConsolePolicy(
      key: 'message_ttl_hours',
      category: 'locked',
      label: 'Durée de vie maximale d’un message : 72 h',
      unit: 'h',
      valueType: 'integer',
      value: 72,
      defaultValue: 72,
      locked: true,
    ),
  ];
  final policyChanges = <PolicyChange>[];
  final journalEntries = <JournalEntry>[];
  int statsCalls = 0;
  ConsoleStats statsData = ConsoleStats(
    countingSince: DateTime(2026, 11, 13),
    days: [
      for (var i = 29; i >= 0; i--)
        StatDay(
          day: DateTime(2026, 11, 13).subtract(Duration(days: i)),
          text: i < 3 ? 40 + i : 0,
          voice: i < 3 ? 6 : 0,
          photo: i < 3 ? 2 : 0,
          active: i == 0 ? 17 : null,
          newAccounts: i == 0 ? 5 : 0,
          requests: i == 0 ? 10 : 0,
          accepted: i == 0 ? 8 : 0,
          refused: i == 0 ? 2 : 0,
          pushSent: i == 0 ? 90 : 0,
          pushFailed: i == 0 ? 10 : 0,
        ),
    ],
    versions: const [('0.1.0+27', 12), ('0.1.0+26', 3)],
  );

  void _audit(String action, {String? key, Object? before, Object? after}) => journalEntries.insert(
    0,
    JournalEntry(
      id: journalEntries.length + 1,
      action: action,
      at: DateTime(2026, 11, 13, 19, 30),
      key: key,
      label: key == null ? null : policyList.firstWhere((p) => p.key == key).label,
      before: before,
      after: after,
    ),
  );

  @override
  Future<List<ConsolePolicy>> policies() async {
    if (!admin) throw const AppFailure(FailureCode.adminRequired);
    return List.of(policyList);
  }

  @override
  Future<Object?> setPolicy(String key, Object value) async {
    if (!admin) throw const AppFailure(FailureCode.adminRequired);
    final i = policyList.indexWhere((p) => p.key == key);
    if (i < 0) throw const AppFailure(FailureCode.policyNotFound);
    final p = policyList[i];
    if (p.locked) throw const AppFailure(FailureCode.policyLocked);
    if (p.isInt && (value is! int || value < p.min! || value > p.max!)) {
      throw const AppFailure(FailureCode.policyOutOfBounds);
    }
    final before = p.updatedAt == null ? null : p.value;
    policyList[i] = ConsolePolicy(
      key: p.key,
      category: p.category,
      label: p.label,
      unit: p.unit,
      valueType: p.valueType,
      value: value,
      defaultValue: p.defaultValue,
      min: p.min,
      max: p.max,
      locked: p.locked,
      advanced: p.advanced,
      effect: p.effect,
      clientVisible: p.clientVisible,
      updatedAt: DateTime(2026, 11, 13, 19, 30),
    );
    policyChanges.insert(
      0,
      PolicyChange(
        key: key,
        label: p.label,
        before: before,
        after: value,
        at: DateTime(2026, 11, 13, 19, 30),
      ),
    );
    _audit('policy', key: key, before: before, after: value);
    return value;
  }

  @override
  Future<List<PolicyChange>> policyHistory(String key) async =>
      policyChanges.where((c) => c.key == key).toList();

  @override
  Future<ConsoleStats> stats() async {
    if (!admin) throw const AppFailure(FailureCode.adminRequired);
    statsCalls++;
    _audit('stats');
    return statsData;
  }

  @override
  Future<List<JournalEntry>> journal() async {
    if (!admin) throw const AppFailure(FailureCode.adminRequired);
    return List.of(journalEntries);
  }

  // --- Lot 5.3 : modération -------------------------------------------------
  final reportList = <ModerationReport>[];
  final appealList = <Sanction>[];
  final sanctionsByUser = <String, List<Sanction>>{};
  final evidenceById = <String, ReportEvidence>{};
  final moderations = <(List<String>, String, String, int?)>[];
  final lifted = <String>[];
  final appealAnswers = <(String, bool)>[];
  int evidenceReads = 0;

  ModerationReport _with(
    ModerationReport r, {
    required String status,
    String? decision,
    String? note,
  }) => ModerationReport(
    id: r.id,
    kind: r.kind,
    reason: r.reason,
    details: r.details,
    status: status,
    createdAt: r.createdAt,
    takenAt: DateTime(2026, 11, 13, 20),
    decision: decision ?? r.decision,
    decisionNote: note ?? r.decisionNote,
    decidedAt: decision == null ? r.decidedAt : DateTime(2026, 11, 13, 21),
    reporterHandle: r.reporterHandle,
    reportedUserId: r.reportedUserId,
    reportedHandle: r.reportedHandle,
    reportedName: r.reportedName,
    reportedSince: r.reportedSince,
    conversationId: r.conversationId,
    groupTitle: r.groupTitle,
    groupClosed: r.groupClosed || decision == 'group_closed',
    messageId: r.messageId,
    evidenceKind: r.evidenceKind,
    reports90d: r.reports90d,
    reporters90d: r.reporters90d,
    suspended: decision == 'suspended' || r.suspended,
    suspendedUntil: r.suspendedUntil,
    sanctionsCount: r.sanctionsCount,
    protected: r.protected,
  );

  @override
  Future<List<ModerationReport>> reports(String status) async {
    if (!admin) throw const AppFailure(FailureCode.adminRequired);
    return reportList.where((r) => r.status == status).toList();
  }

  @override
  Future<void> takeReports(List<String> ids) async {
    for (var i = 0; i < reportList.length; i++) {
      if (ids.contains(reportList[i].id) && reportList[i].status == 'open') {
        reportList[i] = _with(reportList[i], status: 'reviewing');
      }
    }
  }

  @override
  Future<ReportEvidence> evidence(String reportId) async {
    final e = evidenceById[reportId];
    if (e == null) throw const AppFailure(FailureCode.reportNotFound);
    evidenceReads++;
    _audit('evidence');
    return e;
  }

  @override
  Future<void> moderate(List<String> ids, String action, String note, {int? days}) async {
    if (note.trim().length < 3) throw const AppFailure(FailureCode.moderationNoteRequired);
    final targets = reportList.where((r) => ids.contains(r.id)).toList();
    if (targets.isEmpty) throw const AppFailure(FailureCode.reportNotFound);
    if ((action == 'warn' || action == 'suspend') && targets.any((r) => r.protected)) {
      throw const AppFailure(FailureCode.adminProtected);
    }
    moderations.add((ids, action, note, days));
    const decisions = {
      'dismiss': 'dismissed',
      'warn': 'warned',
      'suspend': 'suspended',
      'delete_message': 'message_deleted',
      'close_group': 'group_closed',
    };
    for (var i = 0; i < reportList.length; i++) {
      if (ids.contains(reportList[i].id)) {
        reportList[i] = _with(
          reportList[i],
          status: 'closed',
          decision: decisions[action],
          note: note,
        );
      }
    }
  }

  @override
  Future<void> liftSuspension(String userId, String note) async => lifted.add(userId);

  @override
  Future<List<Sanction>> sanctions(String userId) async => sanctionsByUser[userId] ?? const [];

  @override
  Future<List<Sanction>> appeals() async => List.of(appealList);

  @override
  Future<void> answerAppeal(String sanctionId, {required bool lift, required String note}) async {
    appealAnswers.add((sanctionId, lift));
    appealList.removeWhere((s) => s.id == sanctionId);
  }

  // --- Lot 5.4 : comptes et assistance ----------------------------------------
  final accounts = <String, ConsoleAccount>{};
  final searches = <String>[];
  final userSanctions = <(String, String, String, String, int?)>[];
  final disconnected = <String>[];
  final replies = <(String, String)>[];

  @override
  Future<List<AccountHit>> searchAccounts(String query) async {
    searches.add(query);
    final q = query.trim();
    if (RegExp(r'^[+0-9 .-]+$').hasMatch(q) && q.replaceAll(RegExp('[^0-9]'), '').length < 8) {
      throw const AppFailure(FailureCode.searchPhoneIncomplete);
    }
    final needle = q.toLowerCase().replaceFirst('@', '');
    return [
      for (final a in accounts.values)
        if (a.handle.startsWith(needle) || a.displayName.toLowerCase().contains(needle))
          AccountHit(
            userId: a.userId,
            handle: a.handle,
            displayName: a.displayName,
            createdAt: a.createdAt,
            suspended: a.suspended,
          ),
    ];
  }

  @override
  Future<ConsoleAccount> account(String userId) async {
    final a = accounts[userId];
    if (a == null) throw const AppFailure(FailureCode.accountNotFound);
    _audit('account');
    return a;
  }

  @override
  Future<void> sanctionUser(
    String userId,
    String action, {
    required String reason,
    required String note,
    int? days,
  }) async {
    if (accounts[userId]?.protected ?? false) throw const AppFailure(FailureCode.adminProtected);
    userSanctions.add((userId, action, reason, note, days));
  }

  @override
  Future<void> disconnectDevice(String userId, String note) async => disconnected.add(userId);

  @override
  Future<void> replySupport(String reportId, String reply) async {
    replies.add((reportId, reply));
    for (var i = 0; i < reportList.length; i++) {
      if (reportList[i].id == reportId) {
        reportList[i] = _with(reportList[i], status: 'closed', decision: 'answered');
      }
    }
  }

  @override
  Future<bool> consoleAccess() async => admin;

  @override
  Future<ConsoleDashboard> dashboard() async {
    if (!admin) throw const AppFailure(FailureCode.adminRequired);
    dashboardCalls++;
    _audit('dashboard');
    return board;
  }
}

class FakePushService implements PushService {
  bool available = true;
  String? currentToken = 'jeton-fcm-de-test-000000000001';
  String? initial;
  int deleted = 0;
  final _refresh = StreamController<String>.broadcast();
  final _opened = StreamController<String>.broadcast();

  void refreshTo(String token) {
    currentToken = token;
    _refresh.add(token);
  }

  void open(String conversationId) => _opened.add(conversationId);

  @override
  Future<bool> initialize() async => available;
  @override
  Future<String?> token() async => currentToken;
  @override
  Stream<String> get tokenRefresh => _refresh.stream;
  @override
  Future<void> deleteToken() async => deleted++;
  @override
  Future<String?> initialConversation() async => initial;
  @override
  Stream<String> get openedConversations => _opened.stream;
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
  final push = FakePushService();
  final admin = FakeAdminApi();
  final vault = MemoryMediaVault();
  final realtime = FakeRealtimeService();
  final recorder = FakeVoiceRecorder();
  final audio = FakeAudioEngine();
  final photos = FakePhotoPicker();
  final lockStore = MemoryAppLockStore();
  final biometrics = FakeBiometricGate();
  final network = FakeNetworkMonitor();
  DateTime Function() clock = DateTime.now;

  List<Override> get overrides => [
    appLockStoreProvider.overrideWithValue(lockStore),
    biometricGateProvider.overrideWithValue(biometrics),
    pinHasherProvider.overrideWithValue(const FastPinHasher()),
    lockClockProvider.overrideWithValue(() => clock()),
    networkMonitorProvider.overrideWithValue(network),
    authServiceProvider.overrideWithValue(auth),
    accountApiProvider.overrideWithValue(api),
    localFlagsProvider.overrideWithValue(flags),
    permissionGatewayProvider.overrideWithValue(permissions),
    appVersionProvider.overrideWithValue('0.1.0-test'),
    messagingApiProvider.overrideWithValue(messaging),
    adminApiProvider.overrideWithValue(admin),
    localStoreProvider.overrideWithValue(store),
    pushServiceProvider.overrideWithValue(push),
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
