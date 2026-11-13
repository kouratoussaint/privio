import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:local_auth/local_auth.dart';

/// Déverrouillage par empreinte (facultatif) : jamais le seul moyen, le code reste valable.
abstract interface class BiometricGate {
  /// Vrai si le téléphone a un capteur et au moins une empreinte enregistrée.
  Future<bool> available();

  Future<bool> authenticate(String reason);
}

class NoBiometricGate implements BiometricGate {
  const NoBiometricGate();

  @override
  Future<bool> available() async => false;

  @override
  Future<bool> authenticate(String reason) async => false;
}

class DeviceBiometricGate implements BiometricGate {
  DeviceBiometricGate({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> available() async {
    try {
      if (!await _auth.canCheckBiometrics) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } on Object {
      return false;
    }
  }
}

/// Type de réseau (économie de données, reprise après coupure).
enum NetKind { wifi, mobile, other, none }

abstract interface class NetworkMonitor {
  Future<NetKind> current();
  Stream<NetKind> changes();
}

/// Par défaut (tests, plateformes sans information) : réseau supposé disponible.
class AssumeOnlineMonitor implements NetworkMonitor {
  const AssumeOnlineMonitor();

  @override
  Future<NetKind> current() async => NetKind.other;

  @override
  Stream<NetKind> changes() => const Stream.empty();
}

class DeviceNetworkMonitor implements NetworkMonitor {
  DeviceNetworkMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static NetKind _kind(List<ConnectivityResult> r) {
    if (r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet)) {
      return NetKind.wifi;
    }
    if (r.contains(ConnectivityResult.mobile)) return NetKind.mobile;
    if (r.isEmpty || r.every((x) => x == ConnectivityResult.none)) return NetKind.none;
    return NetKind.other;
  }

  @override
  Future<NetKind> current() async {
    try {
      return _kind(await _connectivity.checkConnectivity());
    } on Object {
      return NetKind.other;
    }
  }

  @override
  Stream<NetKind> changes() => _connectivity.onConnectivityChanged.map(_kind).distinct();
}
