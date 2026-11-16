import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';

import '../helpers/fakes.dart';
import '../helpers/menu.dart';

/// Lot 10.1 — Effacer après lecture : réglage depuis ⋮, bandeau, annonce, messages suivants
/// seulement, échéance après lecture.
Future<TestDeps> _openChat(WidgetTester tester, {void Function(TestDeps)? before}) async {
  final deps =
      TestDeps(
          auth: FakeAuthService(signedIn: true),
          flags: FakeLocalFlags(onboarding: true, permissions: true),
        )
        ..api.account = const Account(
          userId: 'u1',
          phoneE164: '+22670000001',
          phoneDiscoverable: false,
          profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
        );
  await deps.messaging.startDirectConversation('u2');
  deps.messaging.receive('conv-bob', 'Salut');
  before?.call(deps);
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
  return deps;
}

Future<void> _choose(WidgetTester tester, int seconds) async {
  await tester.tap(find.byKey(const Key('chat.menu')));
  await tester.pumpAndSettle();
  await tapMenuItem(tester, const Key('chat.menu.erase'));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('erase.sheet')), findsOneWidget);
  await tester.tap(find.byKey(Key('erase.option.$seconds')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('activer 5 min : annonce, bandeau, messages suivants seulement', (tester) async {
    final deps = await _openChat(tester);
    expect(find.byKey(const Key('chat.erase_banner')), findsNothing);
    await _choose(tester, 300);
    expect(deps.messaging.readEraseSets.single, ('conv-bob', 300));
    expect(find.text('Vous avez activé l’effacement après lecture (5 minutes).'), findsOneWidget);
    expect(find.byKey(const Key('chat.erase_banner')), findsOneWidget);
    expect(find.text('Effacement après lecture : 5 minutes'), findsOneWidget);
    // Le message reçu avant l'activation n'est pas concerné.
    expect(find.byKey(const Key('bubble.erase')), findsNothing);

    await tester.enterText(find.byKey(const Key('chat.input')), 'Code de la porte : 1234');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.messages['conv-bob']!.last.readEraseSeconds, 300);
    expect(find.byKey(const Key('bubble.erase')), findsOneWidget);

    // Désactiver depuis le bandeau.
    await tester.tap(find.byKey(const Key('chat.erase_banner')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('erase.option.0')));
    await tester.pumpAndSettle();
    expect(deps.messaging.readEraseSets.last, ('conv-bob', null));
    expect(find.byKey(const Key('chat.erase_banner')), findsNothing);
    expect(find.text('Vous avez désactivé l’effacement après lecture.'), findsOneWidget);
  });

  testWidgets('message reçu : lu à l’ouverture, effacé 30 s après', (tester) async {
    late ChatMessage secret;
    final deps = await _openChat(
      tester,
      before: (d) {
        d.messaging.readErase['conv-bob'] = 30;
        secret = d.messaging.receive('conv-bob', 'Secret');
      },
    );
    expect(find.text('Secret'), findsOneWidget);
    expect(find.byKey(const Key('bubble.erase')), findsOneWidget);
    // Lu à l'écran : échéance = lecture + 30 s (au lieu de 72 h).
    final now = DateTime.now();
    final m = deps.messaging.messages['conv-bob']!.firstWhere((x) => x.id == secret.id);
    expect(m.expiresAt.isBefore(now.add(const Duration(seconds: 31))), isTrue);
    // Rafraîchissement suivant : l'échéance arrive sur le téléphone.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    // Échéance passée (simulée) : le message disparaît de l'écran.
    final list = deps.messaging.messages['conv-bob']!;
    final i = list.indexWhere((x) => x.id == secret.id);
    list[i] = ChatMessage.fromJson({
      ...list[i].toJson(),
      'expires_at': DateTime.now().subtract(const Duration(seconds: 1)).toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.text('Secret'), findsNothing);
    expect(find.text('Salut'), findsOneWidget);
  });

  test('qui peut régler ; annonce lue depuis le message système', () {
    ConversationSummary s({String kind = 'direct', String? role, bool blocked = false}) =>
        ConversationSummary(
          id: 'c',
          kind: kind,
          peerId: kind == 'direct' ? 'u2' : null,
          peerHandle: null,
          peerDisplayName: null,
          peerDeleted: false,
          blocked: blocked,
          unreadCount: 0,
          pinned: false,
          archived: false,
          sortAt: DateTime(2026, 11, 16),
          myRole: role,
        );
    expect(s().canSetReadErase, isTrue);
    expect(s(blocked: true).canSetReadErase, isFalse);
    expect(s(kind: 'group', role: 'member').canSetReadErase, isFalse);
    expect(s(kind: 'group', role: 'admin').canSetReadErase, isTrue);
    final sys = ChatMessage(
      id: 's',
      kind: 'system',
      senderId: 'u2',
      body: 'erase:3600',
      sentAt: DateTime(2026, 11, 16),
      expiresAt: DateTime(2026, 11, 19),
      updatedAt: DateTime(2026, 11, 16),
    );
    expect(sys.systemEraseSeconds, 3600);
    expect(sys.systemTtlSeconds, isNull);
  });
}
