import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Réglages du verrouillage de l'application (SEC-004), propres à ce téléphone.
///
/// Le code n'est jamais gardé : seulement son empreinte PBKDF2-HMAC-SHA256 salée, dans le
/// stockage sécurisé Android (chiffré par le Keystore). Voir ADR-012.
class AppLockConfig {
  const AppLockConfig({
    this.enabled = false,
    this.delaySeconds = 60,
    this.biometrics = false,
    this.salt,
    this.hash,
    this.iterations = AppLockConfig.defaultIterations,
    this.failures = 0,
    this.retryAt,
  });

  static const defaultIterations = 20000;

  /// Délais proposés avant de redemander le code, en secondes.
  static const delays = [0, 60, 300, 1800];

  final bool enabled;
  final int delaySeconds;
  final bool biometrics;
  final String? salt;
  final String? hash;
  final int iterations;

  /// Essais manqués d'affilée, et heure avant laquelle aucun essai n'est accepté.
  final int failures;
  final DateTime? retryAt;

  AppLockConfig copyWith({
    bool? enabled,
    int? delaySeconds,
    bool? biometrics,
    String? salt,
    String? hash,
    int? iterations,
    int? failures,
    DateTime? retryAt,
    bool clearRetry = false,
  }) => AppLockConfig(
    enabled: enabled ?? this.enabled,
    delaySeconds: delaySeconds ?? this.delaySeconds,
    biometrics: biometrics ?? this.biometrics,
    salt: salt ?? this.salt,
    hash: hash ?? this.hash,
    iterations: iterations ?? this.iterations,
    failures: failures ?? this.failures,
    retryAt: clearRetry ? null : (retryAt ?? this.retryAt),
  );

  Map<String, dynamic> toJson() => {
    'v': 1,
    'enabled': enabled,
    'delay': delaySeconds,
    'biometrics': biometrics,
    'salt': salt,
    'hash': hash,
    'iterations': iterations,
    'failures': failures,
    'retry_at': retryAt?.toUtc().toIso8601String(),
  };

  factory AppLockConfig.fromJson(Map<String, dynamic> j) => AppLockConfig(
    enabled: j['enabled'] as bool? ?? false,
    delaySeconds: (j['delay'] as num?)?.toInt() ?? 60,
    biometrics: j['biometrics'] as bool? ?? false,
    salt: j['salt'] as String?,
    hash: j['hash'] as String?,
    iterations: (j['iterations'] as num?)?.toInt() ?? defaultIterations,
    failures: (j['failures'] as num?)?.toInt() ?? 0,
    retryAt: j['retry_at'] == null ? null : DateTime.parse(j['retry_at'] as String),
  );
}

abstract interface class AppLockStore {
  Future<AppLockConfig> read();
  Future<void> write(AppLockConfig config);
  Future<void> clear();
}

class SecureAppLockStore implements AppLockStore {
  SecureAppLockStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'privio.app_lock';
  final FlutterSecureStorage _storage;

  @override
  Future<AppLockConfig> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return const AppLockConfig();
      return AppLockConfig.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } on Object {
      // Illisible : on ne bloque pas l'accès à son propre téléphone pour autant.
      return const AppLockConfig();
    }
  }

  @override
  Future<void> write(AppLockConfig config) =>
      _storage.write(key: _key, value: jsonEncode(config.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class MemoryAppLockStore implements AppLockStore {
  AppLockConfig config = const AppLockConfig();

  @override
  Future<AppLockConfig> read() async => config;

  @override
  Future<void> write(AppLockConfig c) async => config = c;

  @override
  Future<void> clear() async => config = const AppLockConfig();
}

/// Empreinte du code : PBKDF2-HMAC-SHA256, 256 bits. Calculée hors du fil de l'interface.
class PinHasher {
  const PinHasher({this.useIsolate = true});

  final bool useIsolate;

  static List<int> newSalt() {
    final r = Random.secure();
    return List<int>.generate(16, (_) => r.nextInt(256));
  }

  Future<String> hash(String pin, List<int> salt, int iterations) async {
    Future<List<int>> run() async {
      final key = await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      ).deriveKeyFromPassword(password: pin, nonce: salt);
      return key.extractBytes();
    }

    final bytes = useIsolate ? await Isolate.run(run) : await run();
    return base64Encode(bytes);
  }
}

/// Comparaison en temps constant de deux empreintes.
bool sameHash(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  if (x.length != y.length) return false;
  var diff = 0;
  for (var i = 0; i < x.length; i++) {
    diff |= x[i] ^ y[i];
  }
  return diff == 0;
}
