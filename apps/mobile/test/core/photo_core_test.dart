import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privio/core/errors/app_failure.dart';
import 'package:privio/core/media/photo_processing.dart';
import 'package:privio/data/storage/local_cache.dart';
import 'package:privio/data/storage/local_store.dart';
import 'package:privio/data/storage/media_vault.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/state/messaging_providers.dart';
import 'package:privio/ui/features/conversations/chat_screen.dart' show quoteLabel;
import 'package:privio/ui/features/conversations/photo_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lot 3.2 — photos : préparation sur le téléphone, modèle, cache, erreurs.
Uint8List _jpegWithExif({int width = 40, int height = 20, int? orientation, bool gps = false}) {
  final image = img.Image(width: width, height: height)..clear(img.ColorRgb8(200, 30, 30));
  // Repère : coin supérieur gauche vert (pour vérifier la rotation).
  image.setPixelRgb(0, 0, 0, 255, 0);
  if (orientation != null) image.exif.imageIfd.orientation = orientation;
  if (gps) {
    image.exif.gpsIfd['GPSLatitudeRef'] = img.IfdValueAscii('N');
    image.exif.imageIfd['Make'] = img.IfdValueAscii('APPAREIL-SECRET');
  }
  return img.encodeJpg(image, quality: 90);
}

bool _hasExif(Uint8List jpeg) => latin1.decode(jpeg, allowInvalid: true).contains('Exif');

void main() {
  group('préparation sur le téléphone', () {
    test('aucune métadonnée ne quitte le téléphone (GPS, appareil)', () {
      final raw = _jpegWithExif(gps: true);
      expect(_hasExif(raw), isTrue, reason: 'la photo d’origine en contient');
      final out = processPhotoSync(raw)!;
      expect(_hasExif(out.bytes), isFalse);
      expect(latin1.decode(out.bytes, allowInvalid: true), isNot(contains('APPAREIL-SECRET')));
      expect(out.bytes.sublist(0, 2), [0xFF, 0xD8]);
    });

    test('photo prise en portrait\u202F: rotation appliquée avant de retirer l’EXIF', () {
      final out = processPhotoSync(_jpegWithExif(width: 40, height: 20, orientation: 6))!;
      expect((out.width, out.height), (20, 40));
    });

    test('grande photo réduite à 1600 px (proportions gardées)', () {
      final big = img.encodeJpg(img.Image(width: 3000, height: 2000), quality: 50);
      final out = processPhotoSync(big)!;
      expect((out.width, out.height), (1600, 1067));
    });

    test('petite photo gardée à sa taille', () {
      final out = processPhotoSync(_jpegWithExif(width: 300, height: 200))!;
      expect((out.width, out.height), (300, 200));
    });

    test('photo de profil\u202F: carré de 512 px', () {
      final raw = img.encodeJpg(img.Image(width: 800, height: 600), quality: 50);
      final out = processPhotoSync(raw, square: true, maxSide: kAvatarSide)!;
      expect((out.width, out.height), (512, 512));
    });

    test('image avec transparence (PNG)\u202F: convertie en JPEG', () {
      final png = img.encodePng(img.Image(width: 30, height: 30, numChannels: 4));
      final out = processPhotoSync(png)!;
      expect(out.bytes.sublist(0, 2), [0xFF, 0xD8]);
    });

    test('fichier illisible\u202F: refusé', () {
      expect(processPhotoSync(Uint8List.fromList(utf8.encode('pas une image'))), isNull);
    });
  });

  group('modèle', () {
    test('une photo fait l’aller-retour JSON (chemin, dimensions, légende)', () {
      final now = DateTime.utc(2026, 11, 12, 10);
      final m = ChatMessage.fromJson(
        ChatMessage(
          id: 'p1',
          kind: 'photo',
          senderId: 'u2',
          body: 'Le marché',
          sentAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
          updatedAt: now,
          mediaPath: 'c/p1.jpg',
          width: 1600,
          height: 1200,
        ).toJson(),
      );
      expect(m.hasViewablePhoto, isTrue);
      expect((m.width, m.height, m.body), (1600, 1200, 'Le marché'));
    });

    test('une photo ne se modifie pas', () {
      final now = DateTime.now();
      final m = ChatMessage(
        id: 'p',
        kind: 'photo',
        senderId: 'u1',
        body: 'x',
        sentAt: now,
        expiresAt: now.add(const Duration(hours: 1)),
        updatedAt: now,
        mediaPath: 'c/p.jpg',
        width: 1,
        height: 1,
      );
      expect(const MessagingRules().canEdit(m, now), isFalse);
    });

    test('compteur de photos du jour', () {
      final q = PhotoQuota.fromJson(const {
        'limit': 5,
        'used': 3,
        'resets_at': '2026-11-13T00:00:00Z',
      });
      expect(q.remaining, 2);
      expect(photoQuotaText(q), 'Il vous reste 2 photos aujourd’hui (5 par jour).');
      expect(photoQuotaText(const PhotoQuota(limit: 5, used: 4)), contains('1 photo aujourd’hui'));
      expect(
        photoQuotaText(const PhotoQuota(limit: 5, used: 7)),
        contains('Prochaines photos demain, dès minuit'),
      );
    });

    test('citations\u202F: vocal, photo avec ou sans légende, texte', () {
      expect(quoteLabel('photo', null), '📷 Photo');
      expect(quoteLabel('photo', 'Plage'), '📷 Plage');
      expect(quoteLabel('voice', null), 'Message vocal');
      expect(quoteLabel('text', 'Salut'), 'Salut');
    });

    test('hauteur d’une photo dans la bulle\u202F: proportions bornées', () {
      expect(photoBubbleHeight(1600, 1200), closeTo(177, 1));
      expect(photoBubbleHeight(100, 2000), 320);
      expect(photoBubbleHeight(2000, 100), 140);
      expect(photoBubbleHeight(null, null), kPhotoBubbleWidth);
    });

    test('photo de profil\u202F: profil, correspondant, résultat de recherche', () {
      expect(
        Profile.fromJson(const {'handle': 'a', 'display_name': 'A', 'avatar_path': 'u/x.jpg'})
            .avatarPath,
        'u/x.jpg',
      );
      final s = ConversationSummary.fromJson(
        ConversationSummary(
          id: 'c',
          peerId: 'p',
          peerHandle: 'b',
          peerDisplayName: 'B',
          peerDeleted: false,
          blocked: false,
          unreadCount: 0,
          pinned: false,
          archived: false,
          sortAt: DateTime.utc(2026),
          peerAvatarPath: 'p/a.jpg',
        ).toJson(),
      );
      expect(s.peerAvatarPath, 'p/a.jpg');
      expect(
        FoundUser.fromJson(const {
          'id': 'i',
          'handle': 'h',
          'display_name': 'D',
          'avatar_path': 'z',
        }).avatarPath,
        'z',
      );
    });

    test('clé de coffre d’une photo de profil\u202F: sûre et bornée', () {
      final key = LocalCache.avatarMediaKey(
        '00000000-0000-0000-0000-0000000000a1/11111111-2222-3333-4444-555555555555.jpg',
      );
      expect(RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(key), isTrue);
    });

    test('photo en attente\u202F: type, légende et dimensions conservés', () {
      final o = OutboxItem.fromJson(
        OutboxItem(
          clientId: 'c1',
          conversationId: 'conv',
          body: 'Légende',
          createdAt: DateTime.now(),
          kind: 'photo',
          width: 1600,
          height: 900,
        ).toJson(),
      );
      expect(
        (o.isPhoto, o.hasMedia, o.body, o.width, o.height),
        (true, true, 'Légende', 1600, 900),
      );
    });
  });

  test('photo supprimée pour tous\u202F: fichier effacé du téléphone', () async {
    final now = DateTime.now();
    final vault = MemoryMediaVault();
    final cache = LocalCache(MemoryLocalStore(), media: vault);
    ChatMessage photo({DateTime? deletedAt}) => ChatMessage(
      id: 'p1',
      kind: 'photo',
      senderId: 'u2',
      sentAt: now,
      expiresAt: now.add(const Duration(hours: 1)),
      updatedAt: now,
      deletedAt: deletedAt,
      mediaPath: deletedAt == null ? 'c/p1.jpg' : null,
      width: deletedAt == null ? 10 : null,
      height: deletedAt == null ? 10 : null,
    );
    await cache.putMessages('c', [photo()]);
    await cache.putMedia('msg-p1', [1, 2], now.add(const Duration(hours: 1)));
    await cache.putMessages('c', [photo(deletedAt: now)]);
    await cache.readMedia('rien');
    expect(vault.files, isEmpty);
  });

  test('quota atteint (photo-send)\u202F: message clair', () {
    expect(
      toAppFailure(const FunctionException(status: 429, details: {'error': 'PHOTO_QUOTA_REACHED'}))
          .code,
      FailureCode.photoQuotaReached,
    );
  });
}
