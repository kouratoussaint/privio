import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/push_service.dart';
import 'messaging_providers.dart';
import 'providers.dart';

final pushServiceProvider = Provider<PushService>(
  (ref) => throw UnimplementedError('pushServiceProvider doit être surchargé'),
);

/// Discussion à ouvrir après le toucher d'une notification (consommée par la navigation).
final openConversationRequestProvider = NotifierProvider<OpenRequest, String?>(OpenRequest.new);

class OpenRequest extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String conversationId) => state = conversationId;
  void consume() => state = null;
}

/// Notifications de cet appareil : jeton enregistré auprès du serveur tant que l'utilisateur
/// est connecté ET les a laissées activées ; retiré sinon.
final pushProvider = AsyncNotifierProvider<PushController, bool>(PushController.new);

class PushController extends AsyncNotifier<bool> {
  StreamSubscription<String>? _refresh;
  StreamSubscription<String>? _opened;

  @override
  Future<bool> build() async {
    ref.onDispose(() {
      _refresh?.cancel();
      _opened?.cancel();
    });
    final userId = ref.watch(currentUserIdProvider);
    final push = ref.watch(pushServiceProvider);
    if (userId == null || !await push.initialize()) return false;

    // Ouverture depuis une notification (app fermée, puis app déjà lancée).
    final initial = await push.initialConversation();
    if (initial != null) ref.read(openConversationRequestProvider.notifier).request(initial);
    _opened = push.openedConversations.listen(
      (id) => ref.read(openConversationRequestProvider.notifier).request(id),
    );

    final enabled = await ref.read(localFlagsProvider).pushEnabled();
    if (enabled) await _register();
    _refresh = push.tokenRefresh.listen((t) => unawaited(_send(t)));
    return enabled;
  }

  Future<void> _send(String token) async {
    if (!(state.value ?? true)) return;
    try {
      await ref.read(accountApiProvider).registerPushToken(token);
    } on Object {
      // Réseau absent : nouvel essai au prochain lancement ou rafraîchissement.
    }
  }

  Future<void> _register() async {
    final token = await ref.read(pushServiceProvider).token();
    if (token != null) await _send(token);
  }

  /// Interrupteur des Paramètres.
  Future<void> setEnabled(bool value) async {
    await ref.read(localFlagsProvider).setPushEnabled(value);
    state = AsyncData(value);
    if (value) {
      await _register();
    } else {
      await ref.read(accountApiProvider).unregisterPushToken().catchError((Object _) {});
      await ref.read(pushServiceProvider).deleteToken().catchError((Object _) {});
    }
  }
}

/// Déconnexion ou suppression du compte : plus aucune notification pour ce téléphone.
Future<void> forgetPushToken(Ref ref, {required bool serverSide}) async {
  if (serverSide) {
    await ref.read(accountApiProvider).unregisterPushToken().catchError((Object _) {});
  }
  await ref.read(pushServiceProvider).deleteToken().catchError((Object _) {});
}
