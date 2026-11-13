import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:privio/domain/models/messaging.dart';

/// Lot 3.3 — modèles de groupe : lecture des RPC, droits, textes des événements.
ConversationSummary _group({String? role, String posting = 'all', String infoEditing = 'admins'}) =>
    ConversationSummary.fromJson({
      'conversation_id': 'g1',
      'kind': 'group',
      'blocked': false,
      'sort_at': '2026-11-12T10:00:00Z',
      'title': 'Famille',
      'description': 'Les nouvelles',
      'avatar_path': 'groups/g1/a.jpg',
      'member_count': 4,
      'my_role': role,
      'posting': posting,
      'info_editing': infoEditing,
      'last_sender_name': 'Awa',
      'muted_until': '2099-01-01T00:00:00Z',
    });

ChatMessage _event(Map<String, Object?> j, {String sender = 'u2'}) => ChatMessage(
  id: 'e',
  kind: 'system',
  senderId: sender,
  body: jsonEncode(j),
  sentAt: DateTime(2026),
  expiresAt: DateTime(2027),
  updatedAt: DateTime(2026),
);

void main() {
  test('résumé de groupe\u202F: titre, photo, nombre de membres, sourdine', () {
    final s = _group(role: 'member');
    expect(s.isGroup, isTrue);
    expect(s.title, 'Famille');
    expect(s.avatarPath, 'groups/g1/a.jpg');
    expect(s.memberCount, 4);
    expect(s.lastSenderName, 'Awa');
    expect(s.isMuted(DateTime(2026, 11, 12)), isTrue);
    expect(s.copyWith(pinned: true).groupTitle, 'Famille');
  });

  test('droits\u202F: écrire et modifier selon le rôle et les réglages', () {
    expect(_group(role: 'member').canPost, isTrue);
    expect(_group(role: 'member', posting: 'admins').canPost, isFalse);
    expect(_group(role: 'admin', posting: 'admins').canPost, isTrue);
    expect(_group(role: 'member').canEditInfo, isFalse);
    expect(_group(role: 'member', infoEditing: 'all').canEditInfo, isTrue);
    expect(_group(role: 'owner').isOwner, isTrue);
    expect(_group(role: 'admin').isOwner, isFalse);
  });

  test('membres et invitations depuis les RPC', () {
    final m = GroupMember.fromJson({
      'user_id': 'u2',
      'handle': 'bob',
      'display_name': 'Bob',
      'role': 'owner',
    });
    expect(m.roleLabel, 'Propriétaire');
    expect(m.isAdmin, isTrue);
    final i = GroupInvitation.fromJson({
      'invitation_id': 'i1',
      'conversation_id': 'g1',
      'title': 'Famille',
      'inviter_name': 'Bob',
      'member_count': 3,
      'expires_at': '2026-11-19T10:00:00Z',
    });
    expect(i.inviterName, 'Bob');
    expect(i.memberCount, 3);
  });

  test('textes des événements de groupe', () {
    expect(
      groupEventText(_event({'e': 'created', 'a': 'Bob', 'v': 'Famille'}), me: 'u1'),
      'Bob a créé le groupe «\u202FFamille\u202F»',
    );
    expect(
      groupEventText(_event({'e': 'joined', 'a': 'Toussaint'}, sender: 'u1'), me: 'u1'),
      'Vous avez rejoint le groupe',
    );
    expect(
      groupEventText(_event({'e': 'removed', 'a': 'Bob', 't': 'Awa'}), me: 'u1'),
      'Bob a retiré Awa du groupe',
    );
    expect(
      groupEventText(_event({'e': 'owner_changed', 'a': null, 't': 'Awa'}), me: 'u1'),
      'Awa est maintenant propriétaire du groupe',
    );
    expect(
      groupEventText(_event({'e': 'posting', 'a': 'Bob', 'v': 'admins'}), me: 'u1'),
      'Bob a réservé l’envoi de messages aux administrateurs',
    );
    // Durée (format « ttl: ») et contenu inconnu : pas d'événement de groupe.
    final ttl = ChatMessage(
      id: 't',
      kind: 'system',
      senderId: 'u2',
      body: 'ttl:3600',
      sentAt: DateTime(2026),
      expiresAt: DateTime(2027),
      updatedAt: DateTime(2026),
    );
    expect(groupEventText(ttl, me: 'u1'), isNull);
    expect(groupEventText(_event({'e': 'inconnu'}), me: 'u1'), isNull);
  });
}
