import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../../core/config/firebase_options.dart';

/// Notifications (lot 4.1). Le contenu affiché est GÉNÉRIQUE et fixé par le serveur :
/// « Nouveau message » — jamais de texte ni de nom. Le téléphone ne reçoit que
/// l'identifiant de la discussion, pour l'ouvrir quand on touche la notification.
abstract interface class PushService {
  /// Prépare le service ; faux si Firebase est indisponible (l'app fonctionne sans).
  Future<bool> initialize();
  Future<String?> token();
  Stream<String> get tokenRefresh;
  Future<void> deleteToken();

  /// Discussion à ouvrir quand l'app est lancée depuis une notification.
  Future<String?> initialConversation();

  /// Discussions ouvertes en touchant une notification, app déjà lancée.
  Stream<String> get openedConversations;
}

/// Jetons FCM « classiques » (getToken / onTokenRefresh / deleteToken), dépréciés dans
/// firebase_messaging 17 au profit de l'identifiant d'installation (FID). Choix assumé
/// pour le pilote : le FID exige d'activer un drapeau du manifeste (qui désactive alors les
/// jetons) ET de changer l'envoi serveur (`fid` au lieu de `token`). Migration prévue, à
/// faire d'un seul bloc client + serveur (ADR-011).
// ignore_for_file: deprecated_member_use
class FirebasePushService implements PushService {
  bool _ready = false;

  @override
  Future<bool> initialize() async {
    if (_ready) return true;
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: privioFirebaseOptions);
      _ready = true;
    } on Object {
      _ready = false;
    }
    return _ready;
  }

  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  @override
  Future<String?> token() async => await initialize() ? _fm.getToken() : null;

  @override
  Stream<String> get tokenRefresh => _ready ? _fm.onTokenRefresh : const Stream.empty();

  @override
  Future<void> deleteToken() async {
    if (await initialize()) await _fm.deleteToken();
  }

  static String? _conversationOf(RemoteMessage? m) {
    final id = m?.data['conversation_id'];
    return id is String && id.length == 36 ? id : null;
  }

  @override
  Future<String?> initialConversation() async =>
      await initialize() ? _conversationOf(await _fm.getInitialMessage()) : null;

  @override
  Stream<String> get openedConversations => _ready
      ? FirebaseMessaging.onMessageOpenedApp.map(_conversationOf).where((id) => id != null).cast()
      : const Stream.empty();
}
