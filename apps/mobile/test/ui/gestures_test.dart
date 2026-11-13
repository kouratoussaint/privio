import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/core/widgets/swipe_actions.dart';

import '../helpers/fakes.dart';

/// Lot 2.F — actions rapides (gestes).
TestDeps _deps() =>
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

Future<TestDeps> _openChat(WidgetTester tester, {TestDeps? deps}) async {
  final d = deps ?? _deps();
  await d.messaging.startDirectConversation('u2');
  d.messaging.receive('conv-bob', 'Message de Bob');
  await tester.pumpWidget(
    ProviderScope(overrides: d.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
  return d;
}

Future<void> _doubleTap(WidgetTester tester, Finder f) async {
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('glisser un message vers la droite\u202F: répondre', (tester) async {
    await _openChat(tester);
    await tester.drag(find.text('Message de Bob'), const Offset(120, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer.context')), findsOneWidget);
    expect(find.text('Répondre à'), findsOneWidget);
  });

  testWidgets('double appui\u202F: réaction par défaut ❤️, puis retirée', (tester) async {
    await _openChat(tester);
    await _doubleTap(tester, find.text('Message de Bob'));
    expect(find.byKey(const Key('reaction.❤️')), findsOneWidget);
    await _doubleTap(tester, find.text('Message de Bob'));
    expect(find.byKey(const Key('reaction.❤️')), findsNothing);
  });

  testWidgets('réaction du double appui réglable dans les Paramètres', (tester) async {
    final deps = _deps()..flags.quick = '👍';
    await _openChat(tester, deps: deps);
    await _doubleTap(tester, find.text('Message de Bob'));
    expect(find.byKey(const Key('reaction.👍')), findsOneWidget);
  });

  testWidgets('glisser vers la gauche\u202F: suppression avec choix selon l’auteur', (
    tester,
  ) async {
    await _openChat(tester);
    // Message reçu : seulement « pour moi ».
    await tester.drag(find.text('Message de Bob'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('swipe.delete_me')), findsOneWidget);
    expect(find.byKey(const Key('swipe.delete_all')), findsNothing);
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();
    expect(find.text('Message de Bob'), findsOneWidget, reason: 'jamais de suppression d’office');

    // Mon message : aussi « pour tout le monde ».
    await tester.enterText(find.byKey(const Key('chat.input')), 'À effacer');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    await tester.drag(find.text('À effacer'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('swipe.delete_all')));
    await tester.pumpAndSettle();
    expect(find.text('À effacer'), findsNothing);
    expect(find.text('Message supprimé'), findsOneWidget);
  });

  testWidgets(
    'toucher une citation\u202F: remonte au message d’origine, même loin dans la discussion',
    (tester) async {
      final d = _deps();
      await d.messaging.startDirectConversation('u2');
      final original = d.messaging.receive('conv-bob', 'Rendez-vous au marché à 9 h');
      for (var i = 0; i < 40; i++) {
        d.messaging.receive('conv-bob', 'Message intermédiaire $i');
      }
      final now = DateTime.now();
      d.messaging.messages['conv-bob']!.add(
        ChatMessage(
          id: 'srv-reponse',
          senderId: 'u2',
          body: 'Tu confirmes\u202F?',
          replyToId: original.id,
          replyPreview: original.body,
          replyKind: 'text',
          sentAt: now,
          expiresAt: now.add(const Duration(hours: 72)),
          updatedAt: now,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(overrides: d.overrides, retry: (_, _) => null, child: const PrivioApp()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation.conv-bob')));
      await tester.pumpAndSettle();
      // Seule la citation affiche ce texte : l'original est trop haut pour être construit.
      expect(find.text('Rendez-vous au marché à 9 h'), findsOneWidget);

      await tester.tap(find.byKey(const Key('bubble.quote')));
      await tester.pumpAndSettle();
      // L'original est maintenant construit et visible (la réponse, tout en bas, ne l'est plus).
      final shown = find.text('Rendez-vous au marché à 9 h');
      expect(shown, findsOneWidget);
      expect(find.byKey(const Key('bubble.quote')), findsNothing);
      expect(tester.getRect(find.byType(ListView)).contains(tester.getCenter(shown)), isTrue);
      expect(find.textContaining('Ce message a été effacé.'), findsNothing);
    },
  );

  testWidgets('toucher une citation dont l’original a expiré\u202F: message clair', (tester) async {
    final d = _deps();
    await d.messaging.startDirectConversation('u2');
    final now = DateTime.now();
    // L'original expire pendant que la discussion est ouverte.
    final original = d.messaging.receive(
      'conv-bob',
      'Ancien message',
      expiresAt: now.add(const Duration(seconds: 1)),
    );
    d.messaging.messages['conv-bob']!.add(
      ChatMessage(
        id: 'srv-reponse',
        senderId: 'u2',
        body: 'Tu confirmes\u202F?',
        replyToId: original.id,
        replyPreview: original.body,
        replyKind: 'text',
        sentAt: now,
        expiresAt: now.add(const Duration(hours: 72)),
        updatedAt: now,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(overrides: d.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1300)));
    await tester.tap(find.byKey(const Key('bubble.quote')));
    await tester.pump(const Duration(milliseconds: 500)); // après le délai du double appui
    expect(find.textContaining('Ce message a été effacé.'), findsOneWidget);
  });

  testWidgets('glisser un petit peu\u202F: rien ne se passe', (tester) async {
    await _openChat(tester);
    await tester.drag(find.text('Message de Bob'), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer.context')), findsNothing);
  });

  testWidgets('actions disponibles aussi pour TalkBack (sans geste)', (tester) async {
    final semantics = tester.ensureSemantics();
    await _openChat(tester);
    final swipe = find.ancestor(
      of: find.text('Message de Bob'),
      matching: find.byType(SwipeActions),
    );
    final data = tester.getSemantics(swipe.first).getSemanticsData();
    expect(data.customSemanticsActionIds, isNotEmpty);
    semantics.dispose();
  });

  testWidgets(
    'liste\u202F: glisser à droite épingle, à gauche archive (avec «\u202FAnnuler\u202F»)',
    (tester) async {
      final deps = _deps();
      await deps.messaging.startDirectConversation('u2');
      deps.messaging.receive('conv-bob', 'Salut');
      await tester.pumpWidget(
        ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
      );
      await tester.pumpAndSettle();

      await tester.drag(find.byKey(const Key('conversation.conv-bob')), const Offset(150, 0));
      await tester.pumpAndSettle();
      expect(deps.messaging.pinned, isTrue);

      await tester.drag(find.byKey(const Key('conversation.conv-bob')), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(deps.messaging.archived, isTrue);
      expect(find.byKey(const Key('conversation.conv-bob')), findsNothing);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(deps.messaging.archived, isFalse);
      expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
    },
  );
}
