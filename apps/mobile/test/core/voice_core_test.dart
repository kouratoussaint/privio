import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/errors/app_failure.dart';
import 'package:privio/data/storage/local_cache.dart';
import 'package:privio/data/storage/local_store.dart';
import 'package:privio/data/storage/media_vault.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/state/messaging_providers.dart';
import 'package:privio/ui/features/conversations/voice_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lot 3.1 — messages vocaux : modèle, coffre chiffré, effacement local, erreurs.
class _Keys implements LocalKeySource {
  List<int>? key;

  @override
  Future<List<int>> loadOrCreate() async => key ??= List<int>.generate(32, (i) => i * 3 % 256);

  @override
  Future<void> delete() async => key = null;
}

ChatMessage _voice(String id, DateTime sent, Duration ttl, {DateTime? deletedAt}) => ChatMessage(
  id: id,
  kind: 'voice',
  senderId: 'u2',
  sentAt: sent,
  expiresAt: sent.add(ttl),
  updatedAt: sent,
  deletedAt: deletedAt,
  mediaPath: deletedAt == null ? 'conv/$id.m4a' : null,
  durationMs: deletedAt == null ? 12000 : null,
);

void main() {
  group('modèle', () {
    test('un vocal fait l\'aller-retour JSON (chemin, durée, citation)', () {
      final now = DateTime.utc(2026, 11, 12, 10);
      final m = ChatMessage.fromJson(
        ChatMessage(
          id: 'm1',
          kind: 'voice',
          senderId: 'u2',
          sentAt: now,
          expiresAt: now.add(const Duration(hours: 1)),
          updatedAt: now,
          mediaPath: 'c/x.m4a',
          durationMs: 12345,
          replyToId: 'm0',
          replyKind: 'voice',
        ).toJson(),
      );
      expect(m.isVoice, isTrue);
      expect(m.hasPlayableVoice, isTrue);
      expect(m.mediaPath, 'c/x.m4a');
      expect(m.durationMs, 12345);
      expect(m.replyKind, 'voice');
    });

    test('vocal supprimé pour tous : plus écoutable', () {
      final now = DateTime.now();
      expect(_voice('m', now, const Duration(hours: 1), deletedAt: now).hasPlayableVoice, isFalse);
    });

    test('un vocal ne se modifie jamais ; durée maximale lue dans les politiques', () {
      final now = DateTime.now();
      final rules = MessagingRules.fromPolicies(const {'voice_max_seconds': 20});
      expect(rules.canEdit(_voice('m', now, const Duration(hours: 1)), now), isFalse);
      expect(rules.voiceMax, const Duration(seconds: 20));
      expect(const MessagingRules().voiceMax, const Duration(seconds: 30));
    });

    test('durées affichées et annoncées', () {
      expect(formatVoiceDuration(const Duration(milliseconds: 7400)), '0:07');
      expect(formatVoiceDuration(const Duration(seconds: 65)), '1:05');
      expect(spokenVoiceDuration(const Duration(milliseconds: 12400)), '12 secondes');
      expect(spokenVoiceDuration(const Duration(milliseconds: 900)), '1 seconde');
    });

    test('file d\'envoi : un vocal garde son type et sa durée', () {
      final o = OutboxItem.fromJson(
        OutboxItem(
          clientId: 'c1',
          conversationId: 'conv',
          body: '',
          createdAt: DateTime.now(),
          kind: 'voice',
          durationMs: 4200,
        ).toJson(),
      );
      expect(o.isVoice, isTrue);
      expect(o.durationMs, 4200);
    });
  });

  group('effacement local des sons (même sans réseau)', () {
    late DateTime now;
    late MemoryMediaVault vault;
    late LocalCache cache;

    setUp(() {
      now = DateTime.utc(2026, 11, 12, 10);
      vault = MemoryMediaVault();
      cache = LocalCache(MemoryLocalStore(), media: vault, clock: () => now);
    });

    test('un son est effacé du téléphone à l\'expiration de son message', () async {
      await cache.ensureLoaded();
      final key = LocalCache.messageMediaKey('m1');
      await cache.putMedia(key, [1, 2, 3], now.add(const Duration(minutes: 5)));
      expect(await cache.readMedia(key), [1, 2, 3]);
      now = now.add(const Duration(minutes: 6));
      expect(await cache.readMedia(key), isNull, reason: 'expiré : jamais relu');
      await cache.purgeExpired();
      await cache.readMedia('rien'); // attend la fin des écritures
      expect(vault.files, isEmpty, reason: 'fichier effacé du coffre');
    });

    test('un son déjà expiré n\'est jamais écrit', () async {
      await cache.putMedia('msg-x', [1], now.subtract(const Duration(seconds: 1)));
      await cache.readMedia('rien');
      expect(vault.files, isEmpty);
    });

    test('vocal supprimé pour tous : son effacé dès la synchronisation', () async {
      await cache.putMessages('conv', [_voice('m1', now, const Duration(hours: 1))]);
      await cache.putMedia(LocalCache.messageMediaKey('m1'), [
        9,
      ], now.add(const Duration(hours: 1)));
      await cache.putMessages('conv', [
        _voice('m1', now, const Duration(hours: 1), deletedAt: now),
      ]);
      await cache.readMedia('rien');
      expect(vault.files, isEmpty);
    });

    test('« supprimer pour moi » : message et son retirés', () async {
      await cache.putMessages('conv', [_voice('m1', now, const Duration(hours: 1))]);
      await cache.putMedia(LocalCache.messageMediaKey('m1'), [
        9,
      ], now.add(const Duration(hours: 1)));
      await cache.removeMessage('conv', 'm1');
      await cache.readMedia('rien');
      expect(cache.messages('conv'), isEmpty);
      expect(vault.files, isEmpty);
    });

    test('file d\'envoi : son retiré à l\'envoi, ou après 72 h sans réseau', () async {
      final item = OutboxItem(
        clientId: 'c1',
        conversationId: 'conv',
        body: '',
        createdAt: now,
        kind: 'voice',
        durationMs: 3000,
      );
      await cache.addOutbox(item, media: [7, 7]);
      expect(await cache.readMedia(LocalCache.outboxMediaKey('c1')), [7, 7]);
      await cache.removeOutbox('c1');
      await cache.readMedia('rien');
      expect(vault.files, isEmpty);

      await cache.addOutbox(item, media: [7, 7]);
      now = now.add(const Duration(hours: 73));
      await cache.purgeExpired();
      await cache.readMedia('rien');
      expect(cache.outbox, isEmpty);
      expect(vault.files, isEmpty);
    });

    test('déconnexion : coffre entièrement effacé', () async {
      await cache.putMedia('msg-a', [1], now.add(const Duration(hours: 1)));
      await cache.wipe();
      expect(vault.files, isEmpty);
    });

    test('l\'index des sons survit à un redémarrage (et l\'échéance avec lui)', () async {
      final store = MemoryLocalStore();
      final first = LocalCache(store, media: vault, clock: () => now);
      await first.putMedia('msg-a', [5], now.add(const Duration(minutes: 1)));
      await first.readMedia('rien');
      now = now.add(const Duration(minutes: 2));
      final restarted = LocalCache(store, media: vault, clock: () => now);
      await restarted.ensureLoaded();
      await restarted.readMedia('rien');
      expect(vault.files, isEmpty, reason: 'purgé au chargement, hors connexion');
    });
  });

  group('coffre chiffré', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('privio_vault'));
    tearDown(() async => dir.delete(recursive: true));

    test('son chiffré au repos, relu à l\'identique ; altération rejetée', () async {
      final keys = _Keys();
      final vault = EncryptedMediaVault(keys: keys, directory: () async => dir);
      final sound = Uint8List.fromList(utf8.encode('ftypM4A secret de la mairie'));
      await vault.put('msg-1', sound);
      final file = File('${dir.path}/${EncryptedMediaVault.folder}/msg-1.bin');
      expect(latin1.decode(await file.readAsBytes()), isNot(contains('mairie')));
      expect(await vault.get('msg-1'), sound);

      final bytes = await file.readAsBytes();
      bytes[bytes.length - 1] ^= 0xFF;
      await file.writeAsBytes(bytes);
      expect(await vault.get('msg-1'), isNull);
      expect(await file.exists(), isFalse);
    });

    test('effacement : dossier ET clé détruits', () async {
      final keys = _Keys();
      final vault = EncryptedMediaVault(keys: keys, directory: () async => dir);
      await vault.put('msg-1', [1, 2]);
      await vault.wipe();
      expect(await Directory('${dir.path}/${EncryptedMediaVault.folder}').exists(), isFalse);
      expect(keys.key, isNull);
    });

    test('clé de coffre refusée si elle n\'est pas un nom de fichier sûr', () async {
      final vault = EncryptedMediaVault(keys: _Keys(), directory: () async => dir);
      expect(() => vault.put('../evasion', [1]), throwsArgumentError);
    });
  });

  group('erreurs du serveur', () {
    test('codes renvoyés par voice-send', () {
      for (final (code, expected) in [
        ('VOICE_TOO_LONG', FailureCode.voiceTooLong),
        ('MEDIA_INVALID', FailureCode.mediaInvalid),
        ('MEDIA_TOO_LARGE', FailureCode.mediaTooLarge),
        ('NOT_MEMBER', FailureCode.notMember),
        ('BLOCKED', FailureCode.blocked),
        ('STORAGE_UNAVAILABLE', FailureCode.mediaUnavailable),
      ]) {
        expect(
          toAppFailure(FunctionException(status: 422, details: {'error': code})).code,
          expected,
          reason: code,
        );
      }
    });

    test('pas de réseau pendant l\'envoi : on réessaiera', () {
      expect(
        toAppFailure(const FunctionsFetchException(details: 'socket')).code,
        FailureCode.network,
      );
    });

    test('téléchargement refusé (expiré, supprimé, non membre) : plus disponible', () {
      expect(
        toAppFailure(const StorageException('Object not found', statusCode: '400')).code,
        FailureCode.mediaNotFound,
      );
      expect(
        toAppFailure(const StorageException('boom', statusCode: '500')).code,
        FailureCode.mediaUnavailable,
      );
    });
  });
}
