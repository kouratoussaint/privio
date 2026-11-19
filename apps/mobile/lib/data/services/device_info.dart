import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lot 5.6 : modèle du téléphone et version d'Android, transmis à l'enregistrement de
/// l'appareil pour que l'assistance (console) sache sur quel téléphone se trouve un compte.
class DeviceInfo {
  const DeviceInfo({this.model, this.osVersion});

  final String? model;
  final String? osVersion;
}

abstract interface class DeviceInfoSource {
  /// Jamais d'erreur : informations absentes si le téléphone ne les donne pas.
  Future<DeviceInfo> read();
}

/// Canal natif « privio/device » (MainActivity) : fabricant + modèle, version d'Android.
class PlatformDeviceInfo implements DeviceInfoSource {
  const PlatformDeviceInfo();

  static const _channel = MethodChannel('privio/device');

  @override
  Future<DeviceInfo> read() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('info');
      String? text(Object? v) {
        final s = v is String ? v.trim() : '';
        return s.isEmpty ? null : s;
      }

      return DeviceInfo(model: text(m?['model']), osVersion: text(m?['os']));
    } on Object {
      return const DeviceInfo();
    }
  }
}

/// Lot 6.1 : temps écoulé depuis le lancement du processus (null si indisponible).
Future<int?> millisecondsSinceProcessStart() async {
  try {
    return await const MethodChannel('privio/device').invokeMethod<int>('sinceStart');
  } on Object {
    return null;
  }
}

final deviceInfoProvider = Provider<DeviceInfoSource>((ref) => const PlatformDeviceInfo());
