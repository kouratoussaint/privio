import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/messaging.dart';
import 'messaging_providers.dart';

// ------------------------------------------------------------------------
// Réglages de confidentialité (lot 4.3) — appliqués par le serveur.
// ------------------------------------------------------------------------
final privacyProvider = AsyncNotifierProvider<PrivacyController, PrivacySettings>(
  PrivacyController.new,
);

class PrivacyController extends AsyncNotifier<PrivacySettings> {
  @override
  Future<PrivacySettings> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const PrivacySettings();
    return ref.read(messagingApiProvider).getMyPrivacy();
  }

  /// Affiché aussitôt, puis confirmé ; refus du serveur : retour à l'état précédent.
  Future<void> save(PrivacySettings next) async {
    final before = state.value ?? const PrivacySettings();
    state = AsyncData(next);
    try {
      await ref.read(messagingApiProvider).setMyPrivacy(next);
      // Photo, accusés : la liste des autres ne change pas, mais la nôtre peut (durée).
      ref.invalidate(conversationsProvider);
    } on Object {
      state = AsyncData(before);
      rethrow;
    }
  }
}

// ------------------------------------------------------------------------
// Présence
// ------------------------------------------------------------------------
const kPresencePoll = Duration(seconds: 30);
const kPresenceBeat = Duration(seconds: 60);

/// Statut d'une personne (rafraîchi toutes les 30 s tant qu'il est affiché).
final presenceProvider = StreamProvider.autoDispose.family<UserPresence, String>((ref, userId) {
  final api = ref.read(messagingApiProvider);
  final out = StreamController<UserPresence>();
  Future<void> poll() async {
    UserPresence p;
    try {
      p = await api.getPresence(userId);
    } on Object {
      p = const UserPresence();
    }
    if (!out.isClosed) out.add(p);
  }

  unawaited(poll());
  final timer = Timer.periodic(kPresencePoll, (_) => unawaited(poll()));
  ref.onDispose(() {
    timer.cancel();
    unawaited(out.close());
  });
  return out.stream;
});

/// Signale au serveur que l'application est ouverte (toutes les minutes) ou fermée.
/// Rien n'est envoyé hors session. Les erreurs (réseau) sont ignorées.
class PresenceBeacon extends ConsumerStatefulWidget {
  const PresenceBeacon({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PresenceBeacon> createState() => _PresenceBeaconState();
}

class _PresenceBeaconState extends ConsumerState<PresenceBeacon> {
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onShow: _start, onHide: _stop);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  void _send({required bool online}) {
    if (ref.read(currentUserIdProvider) == null) return;
    unawaited(
      ref.read(messagingApiProvider).touchPresence(online: online).catchError((Object _) {}),
    );
  }

  void _start() {
    if (!mounted) return;
    _send(online: true);
    _timer?.cancel();
    _timer = Timer.periodic(kPresenceBeat, (_) => _send(online: true));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    if (mounted) _send(online: false);
  }

  @override
  Widget build(BuildContext context) {
    // Connexion : premier signal sans attendre la minute.
    ref.listen(currentUserIdProvider, (prev, next) {
      if (next != null && prev == null) _send(online: true);
    });
    return widget.child;
  }
}

/// « en ligne », « vu aujourd'hui à 14:05 », « vu hier à 09:12 », « vu le 12/11 à 18:40 ».
String presenceLabel(UserPresence p, DateTime now) {
  if (!p.visible) return '';
  if (p.online) return 'en ligne';
  final seen = p.lastSeenAt?.toLocal();
  if (seen == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(seen.hour)}:${two(seen.minute)}';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(seen.year, seen.month, seen.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'vu aujourd\'hui à $time';
  if (diff == 1) return 'vu hier à $time';
  return 'vu le ${two(seen.day)}/${two(seen.month)} à $time';
}
