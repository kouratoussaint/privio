import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

import 'local_store.dart';

/// Coffre local des sons (messages vocaux reçus, envoyés ou en attente d'envoi).
/// Chaque son est un fichier chiffré à part : le document principal reste léger.
abstract interface class MediaVault {
  Future<void> put(String key, List<int> bytes);
  Future<Uint8List?> get(String key);
  Future<void> delete(String key);
  Future<void> wipe();

  /// Place occupée sur le téléphone, en octets (fichiers chiffrés).
  Future<int> totalBytes();
}

/// Un fichier AES-256-GCM par son (vecteur aléatoire neuf à chaque écriture, écriture
/// atomique), avec une clé propre gardée dans le Keystore Android. Voir ADR-007.
class EncryptedMediaVault implements MediaVault {
  EncryptedMediaVault({LocalKeySource? keys, Future<Directory> Function()? directory})
    : _keys = keys ?? SecureStorageKeySource(keyName: 'privio.media_vault_key'),
      _directory = directory ?? getApplicationSupportDirectory;

  static const folder = 'privio_media';
  static final _aes = AesGcm.with256bits();
  static final _safe = RegExp(r'^[A-Za-z0-9_-]{1,80}$');

  final LocalKeySource _keys;
  final Future<Directory> Function() _directory;
  SecretKey? _key;

  Future<SecretKey> _secretKey() async => _key ??= SecretKey(await _keys.loadOrCreate());

  Future<Directory> _dir() async {
    final dir = Directory('${(await _directory()).path}/$folder');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _file(String key) async {
    if (!_safe.hasMatch(key)) throw ArgumentError.value(key, 'key');
    return File('${(await _dir()).path}/$key.bin');
  }

  @override
  Future<void> put(String key, List<int> bytes) async {
    final file = await _file(key);
    final box = await _aes.encrypt(bytes, secretKey: await _secretKey(), nonce: _aes.newNonce());
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(box.concatenation(), flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<Uint8List?> get(String key) async {
    final file = await _file(key);
    if (!await file.exists()) return null;
    try {
      final box = SecretBox.fromConcatenation(
        await file.readAsBytes(),
        nonceLength: _aes.nonceLength,
        macLength: _aes.macAlgorithm.macLength,
      );
      return Uint8List.fromList(await _aes.decrypt(box, secretKey: await _secretKey()));
    } on Object {
      await file.delete(); // illisible (clé perdue, altération) : on l'oublie
      return null;
    }
  }

  @override
  Future<void> delete(String key) async {
    final file = await _file(key);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> wipe() async {
    final dir = Directory('${(await _directory()).path}/$folder');
    if (await dir.exists()) await dir.delete(recursive: true);
    await _keys.delete();
    _key = null;
  }

  @override
  Future<int> totalBytes() async {
    final dir = Directory('${(await _directory()).path}/$folder');
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final f in dir.list()) {
      if (f is File) total += await f.length();
    }
    return total;
  }
}

/// Coffre en mémoire (tests).
class MemoryMediaVault implements MediaVault {
  final Map<String, Uint8List> files = {};

  @override
  Future<void> put(String key, List<int> bytes) async => files[key] = Uint8List.fromList(bytes);

  @override
  Future<Uint8List?> get(String key) async => files[key];

  @override
  Future<void> delete(String key) async => files.remove(key);

  @override
  Future<void> wipe() async => files.clear();

  @override
  Future<int> totalBytes() async => files.values.fold<int>(0, (a, b) => a + b.length);
}
