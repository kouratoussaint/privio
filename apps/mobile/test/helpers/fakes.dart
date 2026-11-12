import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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
    );
  }

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
    for (final id in conversations.keys) _summary(id),
  ];

  @override
  Future<FoundUser?> findByHandle(String handle) async {
    handleSearches.add(handle);
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
    if (blocked.contains(bob.id)) throw const AppFailure(FailureCode.blocked);
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
       messaging = messaging ?? FakeMessagingApi();

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
