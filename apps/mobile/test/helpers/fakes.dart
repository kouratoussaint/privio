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
import 'package:privio/state/feedback_providers.dart';
import 'package:privio/data/services/sound_service.dart';
import 'package:privio/data/services/calls_api.dart';
import 'package:privio/data/services/call_engine.dart';
import 'package:privio/data/services/call_tones.dart';
import 'package:privio/domain/models/call.dart';
import 'package:privio/state/call_controller.dart';
import 'package:privio/data/services/call_system.dart';

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

  /// Lot 8.1c : changement de numéro.
  final List<String> phoneChangeRequests = [];
  String? changedPhone;
  Set<String> takenPhones = {'+22670000002'};

  @override
  Future<bool> requestPhoneChange(String newPhoneE164) async {
    if (takenPhones.contains(newPhoneE164)) throw const AppFailure(FailureCode.phoneTaken);
    phoneChangeRequests.add(newPhoneE164);
    return false;
  }

  @override
  Future<void> verifyPhoneChange({required String newPhoneE164, required String code}) async {
    if (code != validCode) throw const AppFailure(FailureCode.otpInvalidOrExpired);
    changedPhone = newPhoneE164;
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

  // --- Lot 8.4a : vérification en deux étapes ---------------------------------
  String? twoStepPin;
  bool twoStepVerified = true;
  int twoStepFailures = 0;
  DateTime? twoStepRetryAt;
  DateTime? twoStepResetAt;
  bool phoneChangeAuthorized = false;

  bool get _pending => twoStepPin != null && !twoStepVerified;

  /// Simule une connexion par SMS sur un nouveau téléphone (compte protégé).
  void newSessionPending(String pin) {
    twoStepPin = pin;
    twoStepVerified = false;
  }

  TwoStepCheck _check(String pin) {
    final now = DateTime.now();
    if (twoStepRetryAt != null && twoStepRetryAt!.isAfter(now)) {
      return TwoStepCheck(ok: false, retryAt: twoStepRetryAt, failures: twoStepFailures);
    }
    if (pin == twoStepPin) {
      twoStepFailures = 0;
      twoStepRetryAt = null;
      return const TwoStepCheck(ok: true);
    }
    twoStepFailures++;
    twoStepRetryAt = twoStepFailures >= 5 ? now.add(const Duration(minutes: 1)) : null;
    return TwoStepCheck(ok: false, retryAt: twoStepRetryAt, failures: twoStepFailures);
  }

  @override
  Future<TwoStepState> twoStepState() async => TwoStepState(
    enabled: twoStepPin != null,
    verified: twoStepPin == null || twoStepVerified,
    retryAt: twoStepRetryAt,
    resetRequestedAt: twoStepResetAt,
  );

  @override
  Future<void> enableTwoStep(String pin) async {
    if (_pending) throw const AppFailure(FailureCode.authRequired);
    if (twoStepPin != null) throw const AppFailure(FailureCode.twoStepAlreadyEnabled);
    twoStepPin = pin;
    twoStepVerified = true;
  }

  @override
  Future<TwoStepCheck> verifyTwoStep(String pin) async {
    if (twoStepPin == null) return const TwoStepCheck(ok: true);
    final r = _check(pin);
    if (r.ok) {
      twoStepVerified = true;
      twoStepResetAt = null;
    }
    return r;
  }

  @override
  Future<TwoStepCheck> changeTwoStep(String current, String next) async {
    if (_pending) throw const AppFailure(FailureCode.authRequired);
    final r = _check(current);
    if (r.ok) twoStepPin = next;
    return r;
  }

  @override
  Future<TwoStepCheck> disableTwoStep(String pin) async {
    if (_pending) throw const AppFailure(FailureCode.authRequired);
    final r = _check(pin);
    if (r.ok) twoStepPin = null;
    return r;
  }

  @override
  Future<TwoStepCheck> authorizePhoneChange(String pin) async {
    if (twoStepPin == null) return const TwoStepCheck(ok: true);
    final r = _check(pin);
    if (r.ok) phoneChangeAuthorized = true;
    return r;
  }

  @override
  Future<DateTime> requestTwoStepReset() async => twoStepResetAt ??= DateTime.now();

  /// Lot 8.4b : rappel avant effacement.
  bool expiryReminderOn = true;

  @override
  Future<bool> expiryReminder() async => expiryReminderOn;

  @override
  Future<bool> setExpiryReminder(bool on) async => expiryReminderOn = on;

  @override
  Future<Account> getMyAccount() async {
    if (_pending) throw const AppFailure(FailureCode.authRequired);
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

  /// Noms enregistrés (lot 7.2a).
  final List<String> displayNames = [];

  @override
  Future<String> setDisplayName(String name) async {
    final t = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty || t.length > 40) throw const AppFailure(FailureCode.displayNameInvalid);
    displayNames.add(t);
    final a = account!;
    final p = a.profile!;
    account = Account(
      userId: a.userId,
      phoneE164: a.phoneE164,
      phoneDiscoverable: a.phoneDiscoverable,
      profile: Profile(handle: p.handle, displayName: t, about: p.about, avatarPath: p.avatarPath),
    );
    return t;
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
    if (_pending) throw const AppFailure(FailureCode.authRequired);
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

  /// Les tests d'avant le lot 7.2b1 ouvrent les groupes depuis Discussions : « ensemble ».
  /// L'application, elle, sépare par défaut (testé dans test/ui/suppression_test.dart).
  bool groupsTogether = true;

  /// Lot 8.1a : apparence.
  String theme = 'system';
  String size = 'normal';
  @override
  Future<String> themeChoice() async => theme;
  @override
  Future<void> setThemeChoice(String value) async => theme = value;
  @override
  Future<String> textSize() async => size;
  @override
  Future<void> setTextSize(String value) async => size = value;

  /// Lot 8.2a : langue.
  String lang = 'fr';
  @override
  Future<String> language() async => lang;
  @override
  Future<void> setLanguage(String value) async => lang = value;

  /// Lot 7.3b : contenu des GIF, aperçus des liens.
  String gif = 'g';
  bool previews = true;
  @override
  Future<String> gifFilter() async => gif;
  @override
  Future<void> setGifFilter(String value) async => gif = value;
  @override
  Future<bool> linkPreviews() async => previews;
  @override
  Future<void> setLinkPreviews(bool value) async => previews = value;

  /// Lot 7.3a : fonds d'écran (null : par défaut).
  final Map<String?, String> wallpapers = {};
  @override
  Future<String?> wallpaper(String? conversationId) async => wallpapers[conversationId];
  @override
  Future<void> setWallpaper(String? conversationId, String? value) async =>
      value == null ? wallpapers.remove(conversationId) : wallpapers[conversationId] = value;

  /// Lot 7.2b2 : sons et vibrations (activés par défaut).
  bool sounds = true;
  @override
  Future<bool> soundsEnabled() async => sounds;
  @override
  Future<void> setSoundsEnabled(bool value) async => sounds = value;
  @override
  Future<bool> groupsInDiscussions() async => groupsTogether;
  @override
  Future<void> setGroupsInDiscussions(bool value) async => groupsTogether = value;

  /// Lot 8.4a : fermée par défaut dans les tests (listes inchangées) ; voir deux_etapes_test.
  bool twoStepPromptClosed = true;
  @override
  Future<bool> twoStepPromptDismissed() async => twoStepPromptClosed;
  @override
  Future<void> setTwoStepPromptDismissed() async => twoStepPromptClosed = true;

  bool fullScreenAsked = false;
  @override
  Future<bool> fullScreenCallsAsked() async => fullScreenAsked;
  @override
  Future<void> setFullScreenCallsAsked() async => fullScreenAsked = true;

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
  int nearbyRequests = 0;
  @override
  Future<bool> requestNotifications() async {
    requests++;
    return true;
  }

  @override
  Future<bool> requestNearbyDevices() async {
    nearbyRequests++;
    return true;
  }

  int cameraRequests = 0;
  bool cameraGranted = true;
  @override
  Future<bool> requestCamera() async {
    cameraRequests++;
    return cameraGranted;
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
    waveform: m.waveform,
    mentions: m.mentions,
    viewOnce: m.viewOnce,
    opened: m.opened,
    openedCount: m.openedCount,
    linkPreview: clearBody ? null : m.linkPreview,
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
    // Lot 7.2c1 : états propres à chaque groupe (épinglé, archivé).
    if (groups.containsKey(conversationId)) {
      if (pinned != null) {
        pinned ? groupPinned.add(conversationId) : groupPinned.remove(conversationId);
      }
      if (archived != null) {
        archived ? groupArchived.add(conversationId) : groupArchived.remove(conversationId);
      }
      return;
    }
    this.pinned = pinned ?? this.pinned;
    this.archived = archived ?? this.archived;
  }

  final Set<String> groupPinned = {};
  final Set<String> groupArchived = {};

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
    if (c == null) {
      // Lot 8.1a : membre d'un groupe commun (comme private.shares_conversation).
      final shared = groups.values.any(
        (g) => g.roles.containsKey(me) && g.roles.containsKey(userId),
      );
      final known = [bob, awa].where((u) => u.id == userId).firstOrNull;
      if (!shared || known == null) return null;
      return ContactProfile(
        userId: userId,
        handle: known.handle,
        displayName: known.displayName,
        about: contactAbout[userId],
        avatarPath: known.avatarPath,
      );
    }
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
      // Lot 7.2c1 : comme le serveur, les messages lus ne comptent plus.
      unreadCount: list.where((m) => m.senderId != me && _unread(id, m)).length,
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
      clearRequestDelete: deleteRequests.contains(id),
      clearRequestExpiresAt: clearRequests[id] == null
          ? null
          : DateTime.now().add(const Duration(hours: 24)),
    );
  }

  /// Messages encore visibles pour moi (après un « vider » éventuel).
  // -------------------------------------------------------------------------
  // Lot 7.2c2 : épinglés, favoris, infos d'un message, « Mentions seulement »
  // -------------------------------------------------------------------------
  final Map<String, List<String>> pins = {};
  final Set<String> favorites = {};
  final Map<String, String> notifyModes = {};

  /// Infos renvoyées pour un message (sinon : Bob, distribué, pas lu).
  final Map<String, List<MessageReceipt>> receipts = {};

  (String, ChatMessage)? _lookup(String messageId) {
    for (final e in messages.entries) {
      for (final m in e.value) {
        if (m.id == messageId) return (e.key, m);
      }
    }
    return null;
  }

  bool _usable(ChatMessage m) =>
      !m.isDeleted &&
      !m.isSystem &&
      m.expiresAt.isAfter(DateTime.now()) &&
      !hiddenForMe.contains(m.id);

  (String, ChatMessage) _requireUsable(String messageId) {
    final found = _lookup(messageId);
    if (found == null || found.$2.isSystem || hiddenForMe.contains(messageId)) {
      throw const AppFailure(FailureCode.messageNotFound);
    }
    if (found.$2.isDeleted) throw const AppFailure(FailureCode.messageDeleted);
    if (!found.$2.expiresAt.isAfter(DateTime.now())) {
      throw const AppFailure(FailureCode.messageExpired);
    }
    return found;
  }

  MessageRef _ref(ChatMessage m, [String? conversationId]) => MessageRef(
    id: m.id,
    conversationId: conversationId,
    senderId: m.senderId,
    senderName: m.senderName ?? (m.senderId == bob.id ? bob.displayName : null),
    kind: m.kind,
    body: m.body,
    sentAt: m.sentAt,
    at: m.sentAt,
    expiresAt: m.expiresAt,
  );

  @override
  Future<void> pinMessage(String messageId, {required bool pin}) async {
    _net();
    final (conv, m) = _requireUsable(messageId);
    final g = groups[conv];
    if (g != null && !g.isAdmin(me)) throw const AppFailure(FailureCode.notAdmin);
    final list = pins[conv] ??= [];
    if (!pin) {
      list.remove(m.id);
      return;
    }
    if (list.contains(m.id)) return;
    final active = list.where((id) {
      final found = _lookup(id);
      return found != null && _usable(found.$2);
    });
    if (active.length >= 3) throw const AppFailure(FailureCode.pinLimitReached);
    list.add(m.id);
  }

  @override
  Future<List<MessageRef>> listPinnedMessages(String conversationId) async {
    _net();
    return [
      for (final id in (pins[conversationId] ?? const <String>[]).reversed)
        if (_lookup(id) case (_, final m)? when _usable(m)) _ref(m),
    ];
  }

  @override
  Future<int> setFavorites(List<String> messageIds, {required bool on}) async {
    _net();
    var n = 0;
    for (final id in messageIds) {
      if (on) {
        _requireUsable(id);
        if (favorites.add(id)) n++;
      } else if (favorites.remove(id)) {
        n++;
      }
    }
    return n;
  }

  @override
  Future<List<MessageRef>> listFavorites(String conversationId) async {
    _net();
    final list = [
      for (final m in messages[conversationId] ?? const <ChatMessage>[])
        if (favorites.contains(m.id) && _usable(m)) _ref(m),
    ];
    return list.reversed.toList();
  }

  @override
  Future<List<MessageRef>> listAllFavorites() async {
    _net();
    final list = [
      for (final MapEntry(key: id, value: ms) in messages.entries)
        for (final m in ms)
          if (favorites.contains(m.id) && _usable(m)) _ref(m, id),
    ]..sort((x, y) => y.sentAt.compareTo(x.sentAt));
    return list;
  }

  @override
  Future<List<MessageReceipt>> getMessageInfo(String messageId) async {
    _net();
    final (_, m) = _requireUsable(messageId);
    if (m.senderId != me) throw const AppFailure(FailureCode.notSender);
    return receipts[messageId] ??
        [
          MessageReceipt(
            userId: bob.id,
            name: bob.displayName,
            delivered: true,
            deliveredAt: m.sentAt.add(const Duration(seconds: 2)),
            read: false,
          ),
        ];
  }

  @override
  Future<String> getNotifyMode(String conversationId) async {
    _net();
    return notifyModes[conversationId] ?? 'all';
  }

  @override
  Future<void> setNotifyMode(String conversationId, String mode) async {
    _net();
    if (mode == 'mentions' && !groups.containsKey(conversationId)) {
      throw const AppFailure(FailureCode.notGroup);
    }
    notifyModes[conversationId] = mode;
  }

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

  // --- Lot 7.2b1 : suppression -------------------------------------------------------
  /// Discussions supprimées chez moi (instant) ; elles reviennent avec un nouveau message.
  final Map<String, DateTime> hiddenAt = {};

  /// Demandes « pour nous deux » qui sont des suppressions.
  final Set<String> deleteRequests = {};
  final List<GroupDeletionNotice> deletionNotices = [];
  final List<String> dismissedNotices = [];

  bool _hiddenNow(String id) {
    final at = hiddenAt[id];
    if (at == null) return false;
    return !(messages[id] ?? const <ChatMessage>[]).any((m) => m.sentAt.isAfter(at));
  }

  void _hide(String id) {
    _wipeMine(id);
    hiddenAt[id] = DateTime.now();
  }

  void _wipeMine(String id) {
    messages[id]?.clear();
    clearedBefore[id] = DateTime.now();
  }

  @override
  Future<String> deleteConversation(String conversationId, {required bool everyone}) async {
    _net();
    final g = groups[conversationId];
    if (g != null) {
      if (!everyone) throw const AppFailure(FailureCode.unknown);
      if (!g.isAdmin(me)) throw const AppFailure(FailureCode.notAdmin);
      groups.remove(conversationId);
      messages.remove(conversationId);
      return 'deleted';
    }
    if (!everyone) {
      _hide(conversationId);
      return 'deleted';
    }
    if (blocked.contains(bob.id)) throw const AppFailure(FailureCode.clearNotAllowed);
    clearRequests[conversationId] = me;
    deleteRequests.add(conversationId);
    return 'requested';
  }

  @override
  Future<List<GroupDeletionNotice>> listGroupDeletionNotices() async {
    _net();
    return List.of(deletionNotices);
  }

  @override
  Future<void> dismissGroupDeletionNotice(String id) async {
    _net();
    dismissedNotices.add(id);
    deletionNotices.removeWhere((n) => n.id == id);
  }

  void _wipe(String id) {
    deleteRequests.remove(id);
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
      deleteRequests.remove(conversationId);
      return 'refused';
    }
    final delete = deleteRequests.contains(conversationId);
    _wipe(conversationId);
    if (delete) {
      _hide(conversationId);
      return 'deleted';
    }
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
  ChatMessage receive(String conversationId, String body, {DateTime? expiresAt, DateTime? sentAt}) {
    final now = DateTime.now();
    final m = ChatMessage(
      id: 'srv-${_seq++}',
      senderId: bob.id,
      body: body,
      sentAt: sentAt ?? now,
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

  /// Lot 8.3b : autres discussions à deux, toutes faites (liste des contacts).
  final Map<String, ConversationSummary> extraDirect = {};

  Future<List<ConversationSummary>> _listRaw() async => [
    for (final id in conversations.keys)
      if (!groups.containsKey(id) && !_hiddenNow(id)) _summary(id),
    ...extraDirect.values,
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

  // -------------------------------------------------------------------------
  // Lot 7.3b : vue unique, GIF, aperçus des liens
  // -------------------------------------------------------------------------
  final List<String> sentViewOnce = [];

  /// Fichier d'un message en vue unique (rendu lisible à l'ouverture).
  final Map<String, String> viewOncePaths = {};
  final List<String> viewOnceOpened = [];
  final List<String> viewOnceClosed = [];

  /// Reçoit une photo en vue unique (de Bob).
  ChatMessage receiveViewOncePhoto(String conversationId) {
    final now = DateTime.now();
    final id = 'srv-${_seq++}';
    final path = '$conversationId/$id.jpg';
    storedPhotos[path] = testJpeg(width: 40, height: 30);
    final m = ChatMessage(
      id: id,
      kind: 'photo',
      senderId: bob.id,
      sentAt: now,
      expiresAt: now.add(const Duration(hours: 72)),
      updatedAt: now,
      width: 40,
      height: 30,
      viewOnce: true,
    );
    viewOncePaths[id] = path;
    (messages[conversationId] ??= []).add(m);
    return m;
  }

  @override
  Future<void> openViewOnce(String messageId) async {
    _net();
    final found = _lookup(messageId);
    if (found == null ||
        !found.$2.viewOnce ||
        found.$2.senderId == me ||
        viewOnceOpened.contains(messageId)) {
      throw const AppFailure(FailureCode.viewOnceUnavailable);
    }
    viewOnceOpened.add(messageId);
    _replace(
      messageId,
      (m) => ChatMessage(
        id: m.id,
        kind: m.kind,
        senderId: m.senderId,
        sentAt: m.sentAt,
        expiresAt: m.expiresAt,
        updatedAt: DateTime.now(),
        width: m.width,
        height: m.height,
        durationMs: m.durationMs,
        mediaPath: viewOncePaths[m.id],
        viewOnce: true,
        opened: true,
      ),
    );
  }

  @override
  Future<void> closeViewOnce(String messageId) async {
    _net();
    viewOnceClosed.add(messageId);
    _replace(
      messageId,
      (m) => ChatMessage(
        id: m.id,
        kind: m.kind,
        senderId: m.senderId,
        sentAt: m.sentAt,
        expiresAt: m.expiresAt,
        updatedAt: DateTime.now(),
        width: m.width,
        height: m.height,
        durationMs: m.durationMs,
        viewOnce: true,
        opened: true,
      ),
    );
  }

  List<GifResult> gifResults = [
    for (var i = 0; i < 6; i++)
      GifResult(
        slug: 'gif-$i',
        url: 'https://static.klipy.com/gif-$i.webp',
        width: 200,
        height: 150,
      ),
  ];
  final List<(String, String)> gifSearches = [];
  final List<String> sentGifs = [];
  final Map<String, Uint8List> storedGifs = {};
  AppFailure? gifFailure;

  @override
  Future<(List<GifResult>, bool)> searchGifs(
    String query, {
    int page = 1,
    String filter = 'g',
  }) async {
    _net();
    gifSearches.add((query, filter));
    if (gifFailure != null) throw gifFailure!;
    return (gifResults, false);
  }

  @override
  Future<ChatMessage> sendGif({
    required String conversationId,
    required String clientMsgId,
    required String slug,
    String? replyToId,
    int? ttlSeconds,
    String filter = 'g',
  }) async {
    _net();
    if (gifFailure != null) throw gifFailure!;
    sentGifs.add(slug);
    final now = DateTime.now();
    final path = '$conversationId/$clientMsgId';
    storedGifs[path] = testJpeg(width: 200, height: 150);
    final m = ChatMessage(
      id: 'srv-$clientMsgId',
      kind: 'gif',
      senderId: me,
      replyToId: replyToId,
      sentAt: now,
      expiresAt: now.add(Duration(seconds: conversationTtl)),
      updatedAt: now,
      mediaPath: path,
      width: 200,
      height: 150,
    );
    final list = messages[conversationId] ??= [];
    if (!list.any((x) => x.id == m.id)) list.add(m);
    return m;
  }

  @override
  Future<Uint8List> downloadGif(String mediaPath) async {
    _net();
    final b = storedGifs[mediaPath];
    if (b == null) throw const AppFailure(FailureCode.mediaNotFound);
    return b;
  }

  final List<String> previewRequests = [];

  /// Aperçu « préparé par le serveur » pour les messages contenant ce lien.
  LinkPreview? nextPreview;

  @override
  Future<void> requestLinkPreview(String messageId) async {
    _net();
    previewRequests.add(messageId);
    final p = nextPreview;
    if (p == null) return;
    _replace(
      messageId,
      (m) => ChatMessage(
        id: m.id,
        kind: m.kind,
        senderId: m.senderId,
        body: m.body,
        sentAt: m.sentAt,
        expiresAt: m.expiresAt,
        updatedAt: DateTime.now(),
        linkPreview: p,
      ),
    );
  }

  final Map<String, Uint8List> storedLinkImages = {};

  @override
  Future<Uint8List> downloadLinkImage(String imagePath) async {
    _net();
    final b = storedLinkImages[imagePath];
    if (b == null) throw const AppFailure(FailureCode.mediaNotFound);
    return b;
  }

  /// Lot 7.3a : autocollants envoyés.
  final List<String> sentStickers = [];

  @override
  Future<ChatMessage> sendSticker({
    required String conversationId,
    required String clientMsgId,
    required String sticker,
    String? replyToId,
    int? ttlSeconds,
  }) async {
    _net();
    if (!RegExp(r'^[a-z0-9_]{1,40}/[a-z0-9_]{1,40}$').hasMatch(sticker)) {
      throw const AppFailure(FailureCode.bodyInvalid);
    }
    sentStickers.add(sticker);
    final now = DateTime.now();
    final m = ChatMessage(
      id: 'srv-$clientMsgId',
      senderId: me,
      kind: 'sticker',
      body: sticker,
      replyToId: replyToId,
      sentAt: now,
      expiresAt: now.add(Duration(seconds: conversationTtl)),
      updatedAt: now,
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
    bool viewOnce = false,
  }) async {
    sentClientIds.add(clientMsgId);
    sentWaveforms[clientMsgId] = waveform;
    if (viewOnce) sentViewOnce.add(clientMsgId);
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
      mediaPath: viewOnce ? null : path,
      durationMs: 5000,
      waveform: waveform,
      viewOnce: viewOnce,
    );
    if (viewOnce) viewOncePaths[m.id] = path;
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
    bool viewOnce = false,
  }) async {
    sentClientIds.add(clientMsgId);
    sentCaptions.add(caption);
    if (viewOnce) sentViewOnce.add(clientMsgId);
    if (viewOnce && caption != null && caption.trim().isNotEmpty) {
      throw const AppFailure(FailureCode.bodyInvalid);
    }
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
      mediaPath: viewOnce ? null : path,
      width: 40,
      height: 30,
      viewOnce: viewOnce,
    );
    if (viewOnce) viewOncePaths[m.id] = path;
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
  }) async {
    marks.add((conversationId, deliveredUpTo, readUpTo));
  }

  /// Lot 7.2b1 : accusés envoyés (discussion, distribué jusqu'à, lu jusqu'à).
  final List<(String, DateTime?, DateTime?)> marks = [];

  /// Dernier « lu » envoyé pour une discussion.
  DateTime? lastRead(String id) =>
      marks.where((m) => m.$1 == id && m.$3 != null).map((m) => m.$3).lastOrNull;

  /// Message reçu après le dernier « lu » (non lu).
  bool _unread(String id, ChatMessage m) {
    final read = lastRead(id);
    return read == null || m.sentAt.isAfter(read);
  }

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
      unreadCount: list.where((m) => m.senderId != me && !m.isSystem && _unread(g.id, m)).length,
      sortAt: last?.sentAt ?? g.createdAt,
      lastMessageId: last?.id,
      lastSenderId: last?.senderId,
      lastSenderName: last?.senderId == me ? null : last?.senderName,
      lastBody: last?.body,
      lastSentAt: last?.sentAt,
      lastExpiresAt: last?.expiresAt,
      lastKind: last?.kind ?? 'text',
      ttlSeconds: conversationTtl,
      pinned: groupPinned.contains(g.id),
      archived: groupArchived.contains(g.id),
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

  // Lot 7.2a : confidentialité par discussion.
  final Map<String, ConversationPrivacy> convPrivacy = {};

  @override
  Future<ConversationPrivacy> getConversationPrivacy(String conversationId) async {
    _net();
    return convPrivacy[conversationId] ?? const ConversationPrivacy();
  }

  @override
  Future<void> setConversationPrivacy(
    String conversationId,
    ConversationPrivacy privacy, {
    required bool group,
  }) async {
    _net();
    convPrivacy[conversationId] = privacy;
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
/// Lot 7.2b2 : sons joués (aucune lecture réelle dans les tests).
class FakeSoundPlayer implements SoundPlayer {
  final List<PrivioSound> played = [];

  @override
  Future<void> play(PrivioSound sound) async => played.add(sound);
}

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

  /// Lot 9.1a : signal d'appel.
  void emitCall(String conversationId, String callId) => _controller.add(
    RealtimeSignal(event: 'call', conversationId: conversationId, callId: callId),
  );

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

  /// Lot 8.4a : comptes protégés (id → demande de réinitialisation) ; réinitialisations.
  final Map<String, DateTime?> twoStepAccounts = {};
  final List<(String, String)> twoStepResets = [];

  @override
  Future<ConsoleTwoStep> twoStep(String userId) async => ConsoleTwoStep(
    enabled: twoStepAccounts.containsKey(userId),
    resetRequestedAt: twoStepAccounts[userId],
  );

  @override
  Future<void> resetTwoStep(String userId, String note) async {
    if (!twoStepAccounts.containsKey(userId)) {
      throw const AppFailure(FailureCode.twoStepNotEnabled);
    }
    twoStepAccounts.remove(userId);
    twoStepResets.add((userId, note));
  }

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
  final sounds = FakeSoundPlayer();
  final photos = FakePhotoPicker();
  final lockStore = MemoryAppLockStore();
  final biometrics = FakeBiometricGate();
  final network = FakeNetworkMonitor();
  // Lot 9.1a : appels.
  final calls = FakeCallsApi();
  final callEngine = FakeCallEngine();
  final tones = FakeCallTones();
  // Lot 9.1b : écran d'appel du téléphone, premier plan.
  final callSystem = FakeCallSystem();
  bool foreground = true;
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
    soundPlayerProvider.overrideWithValue(sounds),
    photoPickerProvider.overrideWithValue(photos),
    callsApiProvider.overrideWithValue(calls),
    callEngineFactoryProvider.overrideWithValue(() => callEngine),
    callTonesProvider.overrideWithValue(tones),
    callSystemProvider.overrideWithValue(callSystem),
    appForegroundProvider.overrideWithValue(() => foreground),
    callTimingsProvider.overrideWithValue(
      const CallTimings(
        fastPoll: Duration(milliseconds: 200),
        slowPoll: Duration(milliseconds: 400),
        endedLinger: Duration(milliseconds: 600),
      ),
    ),
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

// ---------------------------------------------------------------------------
// Lot 9.1a : appels
// ---------------------------------------------------------------------------
/// Serveur d'appels en mémoire, vu par « moi » (u1). Le correspondant est piloté par le test
/// (peerAnswer, peerHangUp, peerSignal, incoming).
class FakeCallsApi implements CallsApi {
  final Map<String, CallInfo> calls = {};
  final List<(String, String, Map<String, dynamic>)> sent = [];
  final Map<String, List<CallSignal>> inbox = {};
  bool accept = true;
  bool peerBusy = false;
  int _seq = 0;
  int _sig = 0;
  final List<String> ended = [];
  final List<String> declined = [];

  CallInfo _with(CallInfo c, String status, {DateTime? answeredAt, String? endReason}) => CallInfo(
    id: c.id,
    conversationId: c.conversationId,
    status: status,
    outgoing: c.outgoing,
    peerId: c.peerId,
    peerName: c.peerName,
    peerAvatar: c.peerAvatar,
    kind: c.kind,
    answeredAt: answeredAt ?? c.answeredAt,
    endReason: endReason ?? c.endReason,
  );

  @override
  Future<CallInfo> startCall(String conversationId, {String kind = 'audio'}) async {
    if (!accept) throw const AppFailure(FailureCode.callsDisabled);
    final c = CallInfo(
      id: 'call-${_seq++}',
      kind: kind,
      conversationId: conversationId,
      status: peerBusy ? 'missed' : 'ringing',
      outgoing: true,
      peerId: 'u2',
      peerName: 'Bob',
      endReason: peerBusy ? 'busy' : null,
    );
    calls[c.id] = c;
    return c;
  }

  /// Appel reçu de Bob.
  CallInfo incoming({String conversationId = 'conv-bob', String kind = 'audio'}) {
    final c = CallInfo(
      id: 'call-${_seq++}',
      kind: kind,
      conversationId: conversationId,
      status: 'ringing',
      outgoing: false,
      peerId: 'u2',
      peerName: 'Bob',
    );
    calls[c.id] = c;
    return c;
  }

  void peerAnswer(String id) =>
      calls[id] = _with(calls[id]!, 'accepted', answeredAt: DateTime.now());
  void peerEnd(String id, String status) => calls[id] = _with(calls[id]!, status);
  void peerSignal(String id, String kind, Map<String, dynamic> payload) =>
      (inbox[id] ??= []).add(CallSignal(id: ++_sig, kind: kind, payload: payload));

  @override
  Future<CallInfo> answer(String callId) async =>
      calls[callId] = _with(calls[callId]!, 'accepted', answeredAt: DateTime.now());

  @override
  Future<CallInfo> decline(String callId) async {
    declined.add(callId);
    return calls[callId] = _with(calls[callId]!, 'declined');
  }

  @override
  Future<CallInfo> end(String callId, {String reason = 'hangup'}) async {
    ended.add(callId);
    final c = calls[callId]!;
    return calls[callId] = _with(
      c,
      c.status == 'accepted' ? 'ended' : 'cancelled',
      endReason: reason,
    );
  }

  @override
  Future<void> signal(String callId, String kind, Map<String, dynamic> payload) async =>
      sent.add((callId, kind, payload));

  @override
  Future<CallSnapshot> state(String callId, {int after = 0}) async => CallSnapshot(calls[callId]!, [
    for (final s in inbox[callId] ?? const <CallSignal>[])
      if (s.id > after) s,
  ]);

  @override
  Future<CallInfo?> openCall() async => calls.values.where((c) => c.open && !c.outgoing).lastOrNull;

  @override
  Future<List<Map<String, dynamic>>> iceServers() async => const [
    {
      'urls': ['stun:stun.test'],
    },
  ];

  bool acceptCallsSetting = true;
  @override
  Future<bool> acceptCalls() async => acceptCallsSetting;
  @override
  Future<bool> setAcceptCalls(bool on) async => acceptCallsSetting = on;
}

class FakeCallEngine implements CallEngine {
  final List<String> log = [];
  void Function(CallMediaState)? onState;
  void Function(bool weak)? onQuality;
  void Function(bool on)? onPeerCamera;
  bool camera = false;
  bool? economy;
  int flips = 0;
  bool muted = false;
  bool speaker = false;
  List<AudioRoute> routes = const [AudioRoute.earpiece, AudioRoute.speaker];
  AudioRoute? selected;

  @override
  Future<void> open({
    required List<Map<String, dynamic>> iceServers,
    required void Function(Map<String, dynamic> candidate) onCandidate,
    required void Function(CallMediaState state) onState,
    void Function(bool weak)? onQuality,
    void Function(bool on)? onPeerCamera,
  }) async {
    log.add('open');
    this.onState = onState;
    this.onQuality = onQuality;
    this.onPeerCamera = onPeerCamera;
    onCandidate({'candidate': 'local-1'});
  }

  @override
  Future<void> setCamera(bool on, {bool front = true}) async {
    log.add('camera:$on');
    camera = on;
  }

  @override
  Future<void> switchCamera() async => flips++;

  @override
  Future<void> setEconomy(bool economy) async => this.economy = economy;

  @override
  Widget localView({bool mirror = true}) => SizedBox(key: Key('fake.local.$mirror'));

  @override
  Widget remoteView() => const SizedBox(key: Key('fake.remote'));

  @override
  Future<Map<String, dynamic>> restartIce() async {
    log.add('restart');
    return {'type': 'offer', 'sdp': 'o2'};
  }

  @override
  Future<List<AudioRoute>> audioRoutes() async => routes;

  @override
  Future<void> selectAudioRoute(AudioRoute route) async => selected = route;

  @override
  Future<Map<String, dynamic>> createOffer() async {
    log.add('offer');
    return {'type': 'offer', 'sdp': 'o'};
  }

  @override
  Future<Map<String, dynamic>> acceptOffer(Map<String, dynamic> offer) async {
    log.add('accept:${offer['sdp']}');
    return {'type': 'answer', 'sdp': 'a'};
  }

  @override
  Future<void> setAnswer(Map<String, dynamic> answer) async => log.add('answer:${answer['sdp']}');

  @override
  Future<void> addCandidate(Map<String, dynamic> c) async => log.add('ice:${c['candidate']}');

  @override
  Future<void> setMuted(bool m) async => muted = m;

  @override
  Future<void> setSpeaker(bool on) async => speaker = on;

  @override
  Future<void> close() async => log.add('close');
}

class FakeCallSystem implements CallSystem {
  final List<String> log = [];
  final _events = StreamController<CallSystemEvent>.broadcast();
  String? accepted;
  bool allowed = true;

  void emit(CallSystemAction a, String id) => _events.add(CallSystemEvent(a, id));

  @override
  Stream<CallSystemEvent> get events => _events.stream;
  @override
  Future<String?> acceptedCall() async => accepted;
  final _pip = StreamController<bool>.broadcast();
  void emitPip(bool on) => _pip.add(on);
  @override
  Stream<bool> get pipMode => _pip.stream;
  @override
  Future<void> setPip(bool allowed) async => log.add('pip:$allowed');
  @override
  Future<void> showIncoming(String callId, {bool video = false}) async =>
      log.add(video ? 'show-video:$callId' : 'show:$callId');
  @override
  Future<void> hideIncoming(String callId) async => log.add('hide:$callId');
  @override
  Future<void> activate(String callId, {bool video = false}) async => log.add('activate:$callId');
  @override
  Future<void> connected(String callId) async => log.add('connected:$callId');
  @override
  Future<void> end(String callId) async => log.add('end:$callId');
  @override
  Future<void> setOverLock(bool on) async => log.add('overLock:$on');
  @override
  Future<void> setProximity(bool on) async => log.add('proximity:$on');
  @override
  Future<bool> fullScreenAllowed() async => allowed;
  @override
  Future<void> openFullScreenSettings() async => log.add('settings');
}

class FakeCallTones implements CallTones {
  final List<String> log = [];
  @override
  Future<void> ring() async => log.add('ring');
  @override
  Future<void> ringback() async => log.add('ringback');
  @override
  Future<void> stop() async => log.add('stop');
}
