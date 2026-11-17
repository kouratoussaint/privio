import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/stickers.dart';
import 'data_providers.dart';
import 'messaging_providers.dart';

/// Lot 7.4 — ma collection d'autocollants (ADR-051), gardée sur le serveur pour mon compte.
final myStickersProvider = AsyncNotifierProvider<MyStickersController, List<StickerItem>>(
  MyStickersController.new,
);

class MyStickersController extends AsyncNotifier<List<StickerItem>> {
  @override
  Future<List<StickerItem>> build() async {
    if (ref.watch(currentUserIdProvider) == null) return const [];
    try {
      return await ref.read(messagingApiProvider).listMyStickers();
    } on Object {
      // Hors connexion : collection vide pour l'instant, rechargée au prochain affichage.
      return const [];
    }
  }

  List<StickerItem> get _now => state.value ?? const [];

  /// Ajoute une image à ma collection (les erreurs remontent à l'écran).
  Future<StickerItem> add(Uint8List png, {bool shareable = false}) async {
    final item = await ref.read(messagingApiProvider).addSticker(png, shareable: shareable);
    ref.read(stickerBytesCache)[item.path] = png;
    countData(ref, sent: png.length);
    state = AsyncData([item, ..._now.where((s) => s.id != item.id)]);
    return item;
  }

  Future<void> remove(String id) async {
    await ref.read(messagingApiProvider).removeSticker(id);
    state = AsyncData([..._now.where((s) => s.id != id)]);
  }

  /// Ajoute un autocollant partageable reçu.
  Future<StickerItem> saveFromMessage(String messageId) async {
    final item = await ref.read(messagingApiProvider).saveSharedSticker(messageId);
    state = AsyncData([item, ..._now.where((s) => s.id != item.id)]);
    return item;
  }
}

/// Images déjà connues (créées sur ce téléphone, ou téléchargées).
final stickerBytesCache = Provider<Map<String, Uint8List>>((ref) {
  ref.watch(currentUserIdProvider);
  return {};
});

/// Image d'un autocollant personnel (collection ou message), téléchargée avec le jeton.
final stickerBytesProvider = FutureProvider.family<Uint8List, String>((ref, path) async {
  final cache = ref.read(stickerBytesCache);
  final known = cache[path];
  if (known != null) return known;
  final bytes = await ref.read(messagingApiProvider).downloadSticker(path);
  cache[path] = bytes;
  countData(ref, received: bytes.length);
  return bytes;
});
