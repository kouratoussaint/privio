import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../errors/app_failure.dart';

/// Photo prête à partir : JPEG sans aucune métadonnée, orientation appliquée.
class PreparedPhoto {
  const PreparedPhoto({required this.bytes, required this.width, required this.height});

  final Uint8List bytes;
  final int width;
  final int height;
}

/// Plus grand côté d'une photo envoyée, et qualité JPEG (≈ 150 à 400 Kio).
const kPhotoMaxSide = 1600;
const kPhotoQuality = 80;

/// Photo de profil : carré de 512 pixels.
const kAvatarSide = 512;

/// Prépare une photo de discussion (hors du fil de l'interface).
Future<PreparedPhoto> preparePhoto(Uint8List raw) =>
    _run(raw, square: false, maxSide: kPhotoMaxSide, quality: kPhotoQuality);

/// Prépare une photo de profil : recadrée au centre, carrée.
Future<PreparedPhoto> prepareAvatar(Uint8List raw) =>
    _run(raw, square: true, maxSide: kAvatarSide, quality: 85);

Future<PreparedPhoto> _run(
  Uint8List raw, {
  required bool square,
  required int maxSide,
  required int quality,
}) async {
  final result = await compute(_process, (raw, square, maxSide, quality));
  if (result == null) throw const AppFailure(FailureCode.mediaInvalid);
  return result;
}

/// Décodage, rotation selon l'EXIF, redimensionnement, puis encodage JPEG SANS EXIF :
/// la position GPS, l'appareil, la date de prise de vue ne quittent jamais le téléphone.
/// (Le serveur retire de nouveau toute métadonnée, par précaution.)
PreparedPhoto? processPhotoSync(
  Uint8List raw, {
  bool square = false,
  int maxSide = kPhotoMaxSide,
  int quality = kPhotoQuality,
}) => _process((raw, square, maxSide, quality));

PreparedPhoto? _process((Uint8List, bool, int, int) args) {
  final (raw, square, maxSide, quality) = args;
  img.Image? decoded;
  try {
    decoded = img.decodeImage(raw);
  } on Object {
    return null;
  }
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  if (square) {
    image = img.copyResizeCropSquare(image, size: maxSide);
  } else if (image.width > maxSide || image.height > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
  }
  if (image.hasAlpha) {
    // JPEG sans transparence : fond blanc plutôt que noir.
    final flat = img.Image(width: image.width, height: image.height)
      ..clear(img.ColorRgb8(255, 255, 255));
    image = img.compositeImage(flat, image);
  }
  image.exif = img.ExifData();
  final bytes = img.encodeJpg(image, quality: quality);
  return PreparedPhoto(bytes: bytes, width: image.width, height: image.height);
}
