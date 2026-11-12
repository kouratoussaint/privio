import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

/// Lot 2.3 — actions sur les messages et accusés, via l'écran réel de conversation.
Future<TestDeps> _openChatWithBob(WidgetTester tester, {Map<String, Object?>? policies}) async {
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
  if (policies != null) deps.messaging.policies = policies;
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('discussions.new')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('search.input')), 'bob_ouaga');
  await tester.tap(find.byKey(const Key('search.submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('search.write')));
  await tester.pumpAndSettle();
  return deps;
}

Future<void> _send(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('chat.input')), text);
  await tester.tap(find.byKey(const Key('chat.send')));
  await tester.pumpAndSettle();
}

Future<void> _receive(WidgetTester tester, TestDeps deps, String text) async {
  deps.messaging.receive('conv-bob', text);
  deps.realtime.emit('conv-bob');
  await tester.pumpAndSettle();
}

Future<void> _openActions(WidgetTester tester, String text) async {
  await tester.longPress(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('réagir puis retirer sa réaction', (tester) async {
    final deps = await _openChatWithBob(tester);
    await _receive(tester, deps, 'Salut');
    await _openActions(tester, 'Salut');
    await tester.tap(find.byKey(const Key('react.👍')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reaction.👍')), findsOneWidget);

    await tester.tap(find.byKey(const Key('reaction.👍')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reaction.👍')), findsNothing);
  });

  testWidgets('répondre en citant un message', (tester) async {
    final deps = await _openChatWithBob(tester);
    await _receive(tester, deps, 'On se voit demain ?');
    await _openActions(tester, 'On se voit demain ?');
    await tester.tap(find.byKey(const Key('action.reply')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer.context')), findsOneWidget);
    await _send(tester, 'Oui, à 10 h');
    expect(find.byKey(const Key('composer.context')), findsNothing);
    final quote = find.byKey(const Key('bubble.quote'));
    expect(quote, findsOneWidget);
    expect(find.descendant(of: quote, matching: find.text('On se voit demain ?')), findsOneWidget);
  });

  testWidgets('modifier son message dans le délai', (tester) async {
    await _openChatWithBob(tester);
    await _send(tester, 'Bonjour');
    await _openActions(tester, 'Bonjour');
    await tester.tap(find.byKey(const Key('action.edit')));
    await tester.pumpAndSettle();
    expect(find.text('Modifier le message'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('chat.input')), 'Bonjour à toi');
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(find.text('Bonjour à toi'), findsOneWidget);
    expect(find.textContaining('modifié'), findsOneWidget);
  });

  testWidgets('délai de modification dépassé : action absente (règle serveur)', (tester) async {
    await _openChatWithBob(tester, policies: {'message_edit_window_minutes': 0});
    await _send(tester, 'Trop tard');
    await _openActions(tester, 'Trop tard');
    expect(find.byKey(const Key('action.edit')), findsNothing);
    expect(find.byKey(const Key('action.delete_all')), findsOneWidget);
  });

  testWidgets('supprimer pour tout le monde', (tester) async {
    await _openChatWithBob(tester);
    await _send(tester, 'Oups');
    await _openActions(tester, 'Oups');
    await tester.tap(find.byKey(const Key('action.delete_all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action.delete_all.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Oups'), findsNothing);
    expect(find.text('Message supprimé'), findsOneWidget);
  });

  testWidgets('supprimer pour moi un message reçu', (tester) async {
    final deps = await _openChatWithBob(tester);
    await _receive(tester, deps, 'À masquer');
    await _openActions(tester, 'À masquer');
    await tester.tap(find.byKey(const Key('action.delete_me')));
    await tester.pumpAndSettle();
    expect(find.text('À masquer'), findsNothing);
    expect(deps.messaging.hiddenForMe, hasLength(1));
  });

  testWidgets('message reçu : ni modifier ni supprimer pour tous, jamais copier/transférer', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    await _receive(tester, deps, 'Message de Bob');
    await _openActions(tester, 'Message de Bob');
    expect(find.byKey(const Key('action.reply')), findsOneWidget);
    expect(find.byKey(const Key('action.edit')), findsNothing);
    expect(find.byKey(const Key('action.delete_all')), findsNothing);
    expect(find.textContaining(RegExp('copier|transf', caseSensitive: false)), findsNothing);
  });

  testWidgets('accusés : envoyé, puis reçu, puis lu', (tester) async {
    final semantics = tester.ensureSemantics();
    final deps = await _openChatWithBob(tester);
    await _send(tester, 'Tu as reçu ?');
    expect(find.byKey(const Key('delivery.sent')), findsOneWidget);

    deps.messaging.peerDeliveredUpTo = DateTime.now().add(const Duration(seconds: 1));
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delivery.delivered')), findsOneWidget);

    deps.messaging.peerReadUpTo = DateTime.now().add(const Duration(seconds: 1));
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delivery.read')), findsOneWidget);
    // Le lecteur d'écran annonce « Lu » avec le texte de la bulle (nœud fusionné).
    expect(
      tester.getSemantics(find.byKey(const Key('delivery.read'))).label,
      allOf(contains('Tu as reçu ?'), contains('expire dans'), contains('Lu')),
    );
    semantics.dispose();
  });
}
