import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../../l10n/l10n.dart';

/// Lot 9.1b — intégration de l'appel au téléphone (ADR-037) : écran d'appel plein écran
/// quand Privio est fermé ou le téléphone verrouillé, appel maintenu écran éteint (service
/// de premier plan), affichage par-dessus l'écran de verrouillage, capteur de proximité.
/// Interface : remplacée dans les tests (et sans effet hors Android).
enum CallSystemAction { accept, decline, end }

class CallSystemEvent {
  const CallSystemEvent(this.action, this.callId);

  final CallSystemAction action;
  final String callId;
}

abstract interface class CallSystem {
  /// Actions faites hors de Privio : écran d'appel du téléphone, notification d'appel.
  Stream<CallSystemEvent> get events;

  /// Appel décroché depuis l'écran d'appel du téléphone pendant que Privio était fermé.
  Future<String?> acceptedCall();

  /// Privio en arrière-plan : l'écran d'appel du téléphone sonne (sans nom).
  Future<void> showIncoming(String callId, {bool video = false});

  /// Privio revenu au premier plan : son propre écran d'appel prend le relais.
  Future<void> hideIncoming(String callId);

  /// Appel en cours : maintenu écran éteint ou Privio en arrière-plan.
  Future<void> activate(String callId, {bool video = false});
  Future<void> connected(String callId);
  Future<void> end(String callId);

  /// Écran d'appel visible par-dessus l'écran de verrouillage du téléphone.
  Future<void> setOverLock(bool on);

  /// Écran éteint à l'oreille (écouteur seulement).
  /// Lot 9.3 : appel en cours → les touches de volume règlent le flux d'appel, et un
  /// volume d'appel très bas (moins de 40 %) est remonté à 60 %.
  Future<void> setCallAudio(bool on);

  Future<void> setProximity(bool on);

  /// Lot 9.2 : petite fenêtre au-dessus des autres applications quand on quitte Privio
  /// pendant un appel avec image ; [pipMode] : Privio affiché dans cette fenêtre.
  Future<void> setPip(bool allowed);
  Stream<bool> get pipMode;

  /// Android 14+ : affichage plein écran des appels autorisé par l'utilisateur.
  Future<bool> fullScreenAllowed();
  Future<void> openFullScreenSettings();
}

/// Sans intégration (tests, autres plateformes).
class NoCallSystem implements CallSystem {
  const NoCallSystem();

  @override
  Stream<CallSystemEvent> get events => const Stream.empty();
  @override
  Future<String?> acceptedCall() async => null;
  @override
  Future<void> showIncoming(String callId, {bool video = false}) async {}
  @override
  Future<void> hideIncoming(String callId) async {}
  @override
  Future<void> activate(String callId, {bool video = false}) async {}
  @override
  Future<void> setPip(bool allowed) async {}
  @override
  Stream<bool> get pipMode => const Stream.empty();
  @override
  Future<void> connected(String callId) async {}
  @override
  Future<void> end(String callId) async {}
  @override
  Future<void> setOverLock(bool on) async {}
  @override
  Future<void> setProximity(bool on) async {}

  @override
  Future<void> setCallAudio(bool on) async {}
  @override
  Future<bool> fullScreenAllowed() async => true;
  @override
  Future<void> openFullScreenSettings() async {}
}

/// Paramètres de l'écran d'appel du téléphone : JAMAIS de nom ni de numéro (décision C) —
/// il s'affiche aussi téléphone verrouillé. Identifiant = celui de l'appel Privio.
CallKitParams incomingCallParams(
  String callId, {
  Duration ring = const Duration(seconds: 45),
  bool video = false,
}) => CallKitParams(
  id: callId,
  nameCaller: video ? L.t.callVideoIncomingLocked : L.t.callIncomingLocked,
  appName: 'Privio',
  handle: '',
  type: video ? 1 : 0,
  duration: ring.inMilliseconds,
  missedCallNotification: const NotificationParams(showNotification: false),
  callingNotification: NotificationParams(
    showNotification: true,
    isShowCallback: true,
    subtitle: L.t.callOngoingNotice,
    callbackText: L.t.raccrocher,
  ),
  android: AndroidParams(
    isCustomNotification: false,
    isShowLogo: false,
    isShowFullLockedScreen: true,
    isShowCallID: false,
    backgroundColor: '#2A0F5C',
    actionColor: '#5B1FB8',
    textColor: '#FFFFFF',
    incomingCallNotificationChannelName: L.t.callChannelIncoming,
    missedCallNotificationChannelName: L.t.callChannelMissed,
    isImportant: true,
    textAccept: L.t.decrocher,
    textDecline: L.t.refuser2,
  ),
);

/// Action faite sur l'écran d'appel du téléphone ou sa notification (null : sans intérêt).
CallSystemEvent? callSystemEventOf(CallEvent? e) {
  CallSystemEvent? of(CallSystemAction a, String id) =>
      id.length == 36 ? CallSystemEvent(a, id) : null;
  return switch (e) {
    CallEventActionCallAccept(:final callKitParams) => of(
      CallSystemAction.accept,
      callKitParams.id,
    ),
    CallEventActionCallDecline(:final callKitParams) => of(
      CallSystemAction.decline,
      callKitParams.id,
    ),
    CallEventActionCallEnded(:final callKitParams) => of(CallSystemAction.end, callKitParams.id),
    _ => null,
  };
}

class DeviceCallSystem implements CallSystem {
  DeviceCallSystem({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(_name) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pipChanged') _pip.add(call.arguments == true);
    });
  }

  static const _name = 'privio/call';
  final MethodChannel _channel;
  final _pip = StreamController<bool>.broadcast();

  @override
  Stream<bool> get pipMode => _pip.stream;

  @override
  Future<void> setPip(bool allowed) => _safe(() => _channel.invokeMethod<void>('pip', allowed));

  @override
  Stream<CallSystemEvent> get events =>
      FlutterCallkitIncoming.onEvent.map(callSystemEventOf).where((e) => e != null).cast();

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } on Object {
      // L'intégration au téléphone est un plus : l'appel continue sans elle.
    }
  }

  @override
  Future<String?> acceptedCall() async {
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final c in calls) {
        if (c.isAccepted && c.id.length == 36) return c.id;
      }
    } on Object {
      // Ignoré.
    }
    return null;
  }

  @override
  Future<void> showIncoming(String callId, {bool video = false}) => _safe(
    () => FlutterCallkitIncoming.showCallkitIncoming(incomingCallParams(callId, video: video)),
  );

  @override
  Future<void> hideIncoming(String callId) =>
      _safe(() => FlutterCallkitIncoming.hideCallkitIncoming(incomingCallParams(callId)));

  @override
  Future<void> activate(String callId, {bool video = false}) => _safe(() async {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls.any((c) => c.id == callId && c.isAccepted)) return;
    await FlutterCallkitIncoming.startCall(incomingCallParams(callId, video: video));
  });

  @override
  Future<void> connected(String callId) =>
      _safe(() => FlutterCallkitIncoming.setCallConnected(callId));

  @override
  Future<void> end(String callId) => _safe(() => FlutterCallkitIncoming.endCall(callId));

  @override
  Future<void> setOverLock(bool on) => _safe(() => _channel.invokeMethod<void>('overLock', on));

  @override
  Future<void> setProximity(bool on) => _safe(() => _channel.invokeMethod<void>('proximity', on));

  @override
  Future<void> setCallAudio(bool on) => _safe(() => _channel.invokeMethod<void>('callAudio', on));

  @override
  Future<bool> fullScreenAllowed() async {
    try {
      return await FlutterCallkitIncoming.canUseFullScreenIntent();
    } on Object {
      return true;
    }
  }

  @override
  Future<void> openFullScreenSettings() =>
      _safe(() => FlutterCallkitIncoming.requestFullIntentPermission());
}
