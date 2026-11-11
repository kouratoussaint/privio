import 'package:permission_handler/permission_handler.dart';

/// Autorisations facultatives (AUTH-004) : jamais bloquantes pour l'utilisation.
abstract interface class PermissionGateway {
  Future<bool> requestNotifications();
}

class DevicePermissionGateway implements PermissionGateway {
  const DevicePermissionGateway();

  @override
  Future<bool> requestNotifications() async => (await Permission.notification.request()).isGranted;
}
