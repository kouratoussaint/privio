import 'dart:convert';

/// Configuration injectée à la compilation (`--dart-define`).
///
/// `SUPABASE_URL` et `SUPABASE_PUBLISHABLE_KEY` sont PUBLICS par conception : l'accès
/// aux données est protégé par la RLS et les RPC, pas par le secret de cette clé.
/// Aucun secret serveur (clé service-role, compte de service FCM) ne doit transiter ici :
/// l'application refuse de démarrer si la clé fournie ressemble à une clé secrète.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.1.0');
  static const environment = String.fromEnvironment('PRIVIO_ENV', defaultValue: 'dev');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  static bool get publishableKeyLooksSecret => keyLooksSecret(supabasePublishableKey);

  /// Détecte une clé secrète Supabase (nouveau format `sb_secret_…`) ou une clé JWT
  /// historique portant le rôle `service_role`.
  static bool keyLooksSecret(String key) {
    if (key.startsWith('sb_secret_')) return true;
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final role = (jsonDecode(payload) as Map<String, dynamic>)['role'];
      return role == 'service_role';
    } on Object {
      return false;
    }
  }
}
