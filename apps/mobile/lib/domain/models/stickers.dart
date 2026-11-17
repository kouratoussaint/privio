import 'messaging.dart';

/// Lot 7.4 — autocollant de ma collection (ADR-051) : image PNG ou WebP de 512 px au plus,
/// gardée sur le serveur pour mon compte (60 au plus).
class StickerItem {
  const StickerItem({
    required this.id,
    required this.path,
    this.shareable = false,
    this.width,
    this.height,
  });

  final String id;

  /// Fichier dans le compartiment privé « stickers ».
  final String path;

  /// Partageable : un destinataire peut l'ajouter à ses autocollants.
  final bool shareable;
  final int? width;
  final int? height;

  factory StickerItem.fromJson(Map<String, dynamic> j) => StickerItem(
    id: j['id'] as String,
    path: j['path'] as String,
    shareable: j['shareable'] as bool? ?? false,
    width: (j['width'] as num?)?.toInt(),
    height: (j['height'] as num?)?.toInt(),
  );
}

/// Corps d'un message d'autocollant personnel.
const kCustomStickerShareable = 'perso/partageable';
const kCustomStickerPrivate = 'perso/prive';

/// Autocollant personnel (image propre au message), et non un dessin de Privio.
bool isCustomSticker(ChatMessage m) =>
    m.isSticker && !m.isDeleted && (m.body ?? '').startsWith('perso/');

/// Autocollant personnel que son auteur permet d'ajouter à sa collection.
bool isShareableSticker(ChatMessage m) =>
    isCustomSticker(m) && m.body == kCustomStickerShareable && m.mediaPath != null;
