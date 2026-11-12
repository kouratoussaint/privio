import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

/// Stockage local brut : un seul document JSON, chiffré au repos.
abstract interface class LocalStore {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> data);
  Future<void> wipe();
}

/// Source de la clé de chiffrement locale (Keystore Android en production).
abstract interface class LocalKeySource {
  Future<List<int>> loadOrCreate();
  Future<void> delete();
}

class SecureStorageKeySource implements LocalKeySource {
  SecureStorageKeySource({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _name = 'privio.local_store_key';
  final FlutterSecureStorage _storage;

  @override
  Future<List<int>> loadOrCreate() async {
    final existing = await _storage.read(key: _name);
    if (existing != null) return base64Decode(existing);
    final random = Random.secure();
    final key = List<int>.generate(32, (_) => random.nextInt(256));
    await _storage.write(key: _name, value: base64Encode(key));
    return key;
  }

  @override
  Future<void> delete() => _storage.delete(key: _name);
}

/// Fichier chiffré en AES-256-GCM (authentifié : toute altération est détectée).
/// Format : 12 octets de vecteur aléatoire (neuf à chaque écriture) + chiffré + étiquette.
/// Écriture atomique (fichier temporaire puis renommage). Voir docs/adr/ADR-007.
class EncryptedFileStore implements LocalStore {
  EncryptedFileStore({LocalKeySource? keys, Future<Directory> Function()? directory})
    : _keys = keys ?? SecureStorageKeySource(),
      _directory = directory ?? getApplicationSupportDirectory;

  static const fileName = 'privio_store.bin';
  static final _aes = AesGcm.with256bits();

  final LocalKeySource _keys;
  final Future<Directory> Function() _directory;
  SecretKey? _key;

  Future<SecretKey> _secretKey() async => _key ??= SecretKey(await _keys.loadOrCreate());

  Future<File> _file() async => File('${(await _directory()).path}/$fileName');

  @override
  Future<Map<String, dynamic>?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    try {
      final box = SecretBox.fromConcatenation(
        bytes,
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      final clear = await _aes.decrypt(box, secretKey: await _secretKey());
      return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } on Object {
      // Fichier illisible (clé perdue, altération) : on repart de zéro, sans planter.
      await file.delete();
      return null;
    }
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    final file = await _file();
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: await _secretKey(),
      nonce: _aes.newNonce(),
    );
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(box.concatenation(), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<void> wipe() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
    final tmp = File('${file.path}.tmp');
    if (await tmp.exists()) await tmp.delete();
    // Nouvelle clé au prochain compte : l'ancien contenu ne pourra jamais être relu.
    await _keys.delete();
    _key = null;
  }
}

/// Stockage en mémoire (tests).
class MemoryLocalStore implements LocalStore {
  Map<String, dynamic>? data;
  int writes = 0;

  @override
  Future<Map<String, dynamic>?> read() async =>
      data == null ? null : jsonDecode(jsonEncode(data)) as Map<String, dynamic>;

  @override
  Future<void> write(Map<String, dynamic> d) async {
    writes++;
    data = jsonDecode(jsonEncode(d)) as Map<String, dynamic>;
  }

  @override
  Future<void> wipe() async => data = null;
}
