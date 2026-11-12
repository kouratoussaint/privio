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
      final path = file?.path;
      if (path != null) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    }
  }
}
