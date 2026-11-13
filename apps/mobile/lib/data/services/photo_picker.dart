import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/errors/app_failure.dart';

enum PhotoSource { camera, gallery }

/// Choix d'une photo (PHOTO-001). Le fichier temporaire est lu puis effacé aussitôt :
/// la photo n'est conservée ensuite que chiffrée. Rien n'est enregistré dans la galerie.
abstract interface class PhotoPicker {
  /// Octets de la photo choisie, ou null si la personne a renoncé.
  Future<Uint8List?> pick(PhotoSource source);

  /// Plusieurs photos de la galerie (lot 4.5), au plus [limit] ; liste vide si la
  /// personne a renoncé.
  Future<List<Uint8List>> pickMany({required int limit});
}

/// Implémentation Android : appareil photo du téléphone ou sélecteur de photos du système
/// (aucune autorisation de lire toute la galerie n'est demandée).
class DevicePhotoPicker implements PhotoPicker {
  DevicePhotoPicker() : _picker = ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: source == PhotoSource.camera ? ImageSource.camera : ImageSource.gallery,
        // Première réduction faite par Android (mémoire) ; la préparation finale suit.
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 92,
        requestFullMetadata: false,
      );
      if (file == null) return null;
      return await file.readAsBytes();
    } on PlatformException {
      throw const AppFailure(FailureCode.cameraUnavailable);
    } finally {
      await _delete(file);
    }
  }

  @override
  Future<List<Uint8List>> pickMany({required int limit}) async {
    var files = const <XFile>[];
    try {
      files = await _picker.pickMultiImage(
        limit: limit < 1 ? 1 : limit,
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 92,
        requestFullMetadata: false,
      );
      // Le sélecteur du système peut ignorer la limite : on la fait respecter ici.
      final kept = files.take(limit < 1 ? 1 : limit);
      return [for (final f in kept) await f.readAsBytes()];
    } on PlatformException {
      throw const AppFailure(FailureCode.cameraUnavailable);
    } finally {
      for (final f in files) {
        await _delete(f);
      }
    }
  }

  static Future<void> _delete(XFile? file) async {
    final path = file?.path;
    if (path == null) return;
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
