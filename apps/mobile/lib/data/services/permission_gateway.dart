import 'package:permission_handler/permission_handler.dart';

/// Autorisations facultatives (AUTH-004) : jamais bloquantes pour l'utilisation.
abstract interface class PermissionGateway {
  Future<bool> requestNotifications();

  /// Lot 9.1b : appareils Bluetooth pendant un appel (Android 12+ : « Appareils à proximité »).
  Future<bool> requestNearbyDevices();

  /// Lot 9.2 : caméra, au moment où on l'allume pendant un appel.
  Future<bool> requestCamera();
}

class DevicePermissionGateway implements PermissionGateway {
  const DevicePermissionGateway();

  @override
  Future<bool> requestNotifications() async => (await Permission.notification.request()).isGranted;

  @override
  Future<bool> requestNearbyDevices() async =>
      (await Permission.bluetoothConnect.request()).isGranted;

  @override
  Future<bool> requestCamera() async => (await Permission.camera.request()).isGranted;
}
