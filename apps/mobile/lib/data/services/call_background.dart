import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../storage/secure_session_storage.dart';
import 'call_system.dart';

/// Lot 9.1b — ce qui tourne quand Privio est fermé ou en arrière-plan (ADR-037).
///
/// 1. Message de données « call » (push-dispatch) : l'écran d'appel du téléphone sonne,
///    sans nom. « call_end » : il s'arrête (appel annulé ou expiré).
/// 2. « Refuser » sur cet écran, Privio fermé : le refus part au serveur pour que
///    l'appelant l'entende tout de suite (sinon, son appel sonne jusqu'à l'expiration).
///    « Décrocher » ouvre Privio, qui reprend l'appel (CallController.checkOpenCall).

/// Un message trop ancien (réseau du téléphone coupé longtemps) ne fait plus sonner.
const _staleRing = Duration(seconds: 40);

@pragma('vm:entry-point')
Future<void> privioBackgroundMessage(RemoteMessage message) async {
  await handleCallPush(
    message.data,
    show: FlutterCallkitIncoming.showCallkitIncoming,
    end: FlutterCallkitIncoming.endCall,
  );
}

/// Logique testable du message de données (sans Firebase).
Future<void> handleCallPush(
  Map<String, dynamic> data, {
  required Future<void> Function(CallKitParams params) show,
  required Future<void> Function(String id) end,
  DateTime Function() now = DateTime.now,
}) async {
  final id = data['call_id'];
  if (id is! String || id.length != 36) return;
  switch (data['type']) {
    case 'call':
      final created = DateTime.tryParse('${data['created_at']}');
      if (created != null && now().difference(created) > _staleRing) return;
      final left = created == null
          ? const Duration(seconds: 45)
          : const Duration(seconds: 45) - now().difference(created);
      await show(incomingCallParams(id, ring: left, video: data['kind'] == 'video'));
    case 'call_end':
      await end(id);
  }
}

@pragma('vm:entry-point')
Future<void> privioCallkitBackground(CallEvent event) async {
  final e = callSystemEventOf(event);
  if (e == null || e.action != CallSystemAction.decline) return;
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(),
        detectSessionInUri: false,
      ),
    ).timeout(const Duration(seconds: 10));
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return;
    await client
        .rpc<dynamic>('decline_call', params: {'p_call_id': e.callId})
        .timeout(const Duration(seconds: 10));
  } on Object {
    // Sans réseau : l'appel de l'autre personne s'arrêtera seul (« Pas de réponse »).
  }
}
