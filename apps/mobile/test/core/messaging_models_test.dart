import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/util/ids.dart';
import 'package:privio/core/util/time_format.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/core/phone/phone_number.dart';

void main() {
  test('identifiant client : UUID v4 valide et unique', () {
    final ids = {for (var i = 0; i < 1000; i++) uuidV4()};
    expect(ids.length, 1000);
    for (final id in ids.take(20)) {
      expect(
        id,
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    }
  });

  test('un message n\'est plus visible à son heure d\'expiration (P0)', () {
    final sent = DateTime.utc(2026, 11, 12, 10);
    final m = ChatMessage(
      id: 'm',
      senderId: 'a',
      body: 'x',
      sentAt: sent,
      expiresAt: sent.add(const Duration(hours: 72)),
      updatedAt: sent,
    );
    expect(m.isVisibleAt(m.expiresAt.subtract(const Duration(seconds: 1))), isTrue);
    expect(m.isVisibleAt(m.expiresAt), isFalse);
    expect(m.isVisibleAt(m.expiresAt.add(const Duration(seconds: 1))), isFalse);
  });

  test('temps restant lisible', () {
    final now = DateTime.utc(2026, 11, 12, 10);
    expect(formatRemaining(now.add(const Duration(hours: 71, minutes: 59)), now: now), '71 h');
    expect(formatRemaining(now.add(const Duration(minutes: 45)), now: now), '45 min');
    expect(formatRemaining(now.add(const Duration(seconds: 20)), now: now), '< 1 min');
  });

  test('décodage des réponses serveur', () {
    final s = ConversationSummary.fromJson({
      'conversation_id': 'c1',
      'kind': 'direct',
      'peer_id': 'u2',
      'peer_handle': 'bob_ouaga',
      'peer_display_name': 'Bob',
      'peer_deleted': false,
      'blocked': false,
      'unread_count': 3,
      'pinned': true,
      'archived': false,
      'sort_at': '2026-11-12T10:00:00+00:00',
      'last_body': 'Salut',
      'last_sent_at': '2026-11-12T10:00:00+00:00',
    });
    expect((s.title, s.unreadCount, s.pinned), ('Bob', 3, true));
    final m = ChatMessage.fromJson({
      'id': 'm1',
      'sender_id': 'u2',
      'body': null,
      'sent_at': '2026-11-12T10:00:00+00:00',
      'expires_at': '2026-11-15T10:00:00+00:00',
      'deleted_at': '2026-11-12T10:05:00+00:00',
      'updated_at': '2026-11-12T10:05:00+00:00',
      'reactions': [
        {'user_id': 'u1', 'emoji': '👍'},
      ],
    });
    expect(m.isDeleted, isTrue);
    expect(m.reactions.single.emoji, '👍');
  });

  test('recherche : chiffres = numéro, sinon identifiant', () {
    const looksLikePhone = PhoneNumber.looksLikePhone;
    expect(looksLikePhone('70 00 00 02'), isTrue);
    expect(looksLikePhone('+22670000002'), isTrue);
    expect(looksLikePhone('bob_ouaga'), isFalse);
    expect(looksLikePhone('@bob2026'), isFalse);
  });
}
