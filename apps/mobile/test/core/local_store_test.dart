import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/data/storage/local_cache.dart';
import 'package:privio/data/storage/local_store.dart';
import 'package:privio/domain/models/messaging.dart';

class _MemoryKeys implements LocalKeySource {
  List<int>? key;
  int created = 0;

  @override
  Future<List<int>> loadOrCreate() async {
    if (key == null) created++;
    return key ??= List<int>.generate(32, (i) => (i * 7 + created) % 256);
  }

  @override
  Future<void> delete() async => key = null;
}

ChatMessage _msg(String id, String body, DateTime sent, Duration ttl) => ChatMessage(
  id: id,
  senderId: 'u2',
  body: body,
  sentAt: sent,
  expiresAt: sent.add(ttl),
  updatedAt: sent,
);

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('privio_store'));
  tearDown(() async => dir.delete(recursive: true));

  test('fichier chiffré\u202F: relecture exacte, aucun texte en clair sur le disque', () async {
    final keys = _MemoryKeys();
    final store = EncryptedFileStore(keys: keys, directory: () async => dir);
    await store.write({'secret': 'Rendez-vous à 15 h derrière la mairie'});
    final raw = await File('${dir.path}/${EncryptedFileStore.fileName}').readAsBytes();
    expect(latin1.decode(raw, allowInvalid: true), isNot(contains('mairie')));
    expect(utf8.decode(raw, allowMalformed: true), isNot(contains('mairie')));
    final again = EncryptedFileStore(keys: keys, directory: () async => dir);
    expect((await again.read())!['secret'], 'Rendez-vous à 15 h derrière la mairie');
  });

  test('fichier altéré ou mauvaise clé\u202F: rejeté sans planter, puis supprimé', () async {
    final keys = _MemoryKeys();
    final store = EncryptedFileStore(keys: keys, directory: () async => dir);
    await store.write({'a': 1});
    final file = File('${dir.path}/${EncryptedFileStore.fileName}');
    final bytes = await file.readAsBytes();
    bytes[bytes.length - 1] ^= 0xFF;
    await file.writeAsBytes(bytes);
    expect(await EncryptedFileStore(keys: keys, directory: () async => dir).read(), isNull);
    expect(await file.exists(), isFalse);
  });

  test('effacement\u202F: fichier ET clé détruits (ancien contenu illisible à jamais)', () async {
    final keys = _MemoryKeys();
    final store = EncryptedFileStore(keys: keys, directory: () async => dir);
    await store.write({'a': 1});
    await store.wipe();
    expect(await File('${dir.path}/${EncryptedFileStore.fileName}').exists(), isFalse);
    expect(keys.key, isNull);
  });

  test('cache\u202F: les messages expirés sont retirés du disque, même hors connexion', () async {
    var now = DateTime.utc(2026, 11, 12, 10);
    final store = MemoryLocalStore();
    final cache = LocalCache(store, clock: () => now);
    await cache.ensureLoaded();
    await cache.putMessages('c1', [
      _msg('court', 'Expire vite', now, const Duration(minutes: 5)),
      _msg('long', 'Reste', now, const Duration(hours: 72)),
    ]);
    expect(jsonEncode(store.data), contains('Expire vite'));

    now = now.add(const Duration(minutes: 6));
    await cache.purgeExpired();
    expect(cache.messages('c1').map((m) => m.id), ['long']);
    expect(jsonEncode(store.data), isNot(contains('Expire vite')));
  });

  test('cache\u202F: aperçu expiré effacé de la liste, envoi trop ancien abandonné', () async {
    var now = DateTime.utc(2026, 11, 12, 10);
    final store = MemoryLocalStore();
    final cache = LocalCache(store, clock: () => now);
    await cache.ensureLoaded();
    await cache.putConversations([
      ConversationSummary(
        id: 'c1',
        peerId: 'u2',
        peerHandle: 'bob',
        peerDisplayName: 'Bob',
        peerDeleted: false,
        blocked: false,
        unreadCount: 1,
        pinned: false,
        archived: false,
        sortAt: now,
        lastMessageId: 'm',
        lastBody: 'Aperçu secret',
        lastSentAt: now,
        lastExpiresAt: now.add(const Duration(hours: 1)),
      ),
    ]);
    await cache.addOutbox(
      OutboxItem(clientId: 'x', conversationId: 'c1', body: 'b', createdAt: now),
    );
    now = now.add(const Duration(hours: 73));
    await cache.purgeExpired();
    expect(cache.conversations.single.lastBody, isNull);
    expect(cache.conversations.single.unreadCount, 0);
    expect(cache.outbox, isEmpty);
    expect(jsonEncode(store.data), isNot(contains('Aperçu secret')));
  });

  test('cache\u202F: effacement complet à la déconnexion', () async {
    final store = MemoryLocalStore();
    final cache = LocalCache(store);
    await cache.ensureLoaded();
    await cache.putMessages('c1', [_msg('m', 'x', DateTime.now(), const Duration(hours: 1))]);
    await cache.wipe();
    expect(store.data, isNull);
    expect(cache.messages('c1'), isEmpty);
  });
}
