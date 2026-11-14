import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/errors/app_failure.dart';
import 'package:privio/data/storage/local_cache.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';

import '../helpers/fakes.dart';

/// Lot 7.3b — vue unique (photo, vocal), GIF, aperçus des liens.
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

Future<TestDeps> _openBob(
  WidgetTester tester, {
  TestDeps? deps,
  void Function(TestDeps)? before,
}) async {
  final d = deps ?? _deps();
  await d.messaging.startDirectConversation('u2');
  d.messaging.receive('conv-bob', 'Salut');
  before?.call(d);
  await tester.pumpWidget(
    ProviderScope(overrides: d.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
  return d;
}

Future<void> _advance(WidgetTester tester, Duration d) async {
  for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 100)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('vue unique', () {
    testWidgets('photo envoyée en vue unique : pas de légende, pas de vignette, pas de cache', (
      tester,
    ) async {
      final deps = await _openBob(tester);
      deps.photos.photo = testJpeg(width: 80, height: 40);
      await tester.tap(find.byKey(const Key('composer.photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo.gallery')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('photo.caption')), 'Secret');
      await tester.tap(find.byKey(const Key('photo.compose.once')));
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byKey(const Key('photo.caption')));
      expect(field.enabled, isFalse, reason: 'une photo en vue unique n’a pas de légende');
      await tester.tap(find.byKey(const Key('photo.send')));
      await tester.pumpAndSettle();

      final clientId = deps.messaging.sentClientIds.last;
      expect(deps.messaging.sentViewOnce, [clientId]);
      expect(deps.messaging.sentCaptions.last, anyOf(isNull, isEmpty));
      final id = 'srv-$clientId';
      expect(find.byKey(Key('view_once.$id')), findsOneWidget);
      expect(find.byKey(Key('view_once.status.$id')), findsOneWidget);
      expect(find.text('Pas encore ouverte'), findsOneWidget);
      expect(find.byKey(const Key('photo.compose')), findsNothing);
      expect(
        deps.vault.files.keys.where((k) => k == LocalCache.messageMediaKey(id)),
        isEmpty,
        reason: 'l’expéditeur ne garde pas le média',
      );
    });

    testWidgets('photo reçue : ouverte une fois, puis « Ouverte » et plus rien à revoir', (
      tester,
    ) async {
      late ChatMessage m;
      final deps = await _openBob(
        tester,
        before: (d) => m = d.messaging.receiveViewOncePhoto('conv-bob'),
      );
      expect(find.text('Toucher pour ouvrir'), findsOneWidget);
      await tester.tap(find.byKey(Key('view_once.${m.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('view_once.viewer')), findsOneWidget);
      expect(deps.messaging.viewOnceOpened, [m.id]);

      await tester.tap(find.byKey(const Key('view_once.viewer.close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('view_once.viewer')), findsNothing);
      expect(deps.messaging.viewOnceClosed, [m.id]);
      expect(find.text('Ouverte'), findsOneWidget);

      // Toucher de nouveau ne rouvre rien.
      await tester.tap(find.byKey(Key('view_once.${m.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('view_once.viewer')), findsNothing);
      expect(deps.messaging.viewOnceOpened, [m.id]);
    });

    testWidgets('la photo se ferme seule au bout de 2 minutes', (tester) async {
      late ChatMessage m;
      final deps = await _openBob(
        tester,
        before: (d) => m = d.messaging.receiveViewOncePhoto('conv-bob'),
      );
      await tester.tap(find.byKey(Key('view_once.${m.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('view_once.viewer')), findsOneWidget);
      await tester.pump(const Duration(minutes: 2, seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('view_once.viewer')), findsNothing);
      expect(deps.messaging.viewOnceClosed, [m.id]);
    });

    testWidgets('déjà ouverte ailleurs : message clair', (tester) async {
      late ChatMessage m;
      final deps = await _openBob(
        tester,
        before: (d) => m = d.messaging.receiveViewOncePhoto('conv-bob'),
      );
      deps.messaging.viewOnceOpened.add(m.id);
      await tester.tap(find.byKey(Key('view_once.${m.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('view_once.viewer')), findsNothing);
      expect(find.text(const AppFailure(FailureCode.viewOnceUnavailable).message), findsOneWidget);
    });

    testWidgets('vocal en vue unique : interrupteur dans la préécoute', (tester) async {
      final deps = await _openBob(tester);
      await tester.tap(find.byKey(const Key('chat.mic')));
      await tester.pump();
      await _advance(tester, const Duration(seconds: 2));
      await tester.tap(find.byKey(const Key('voice.stop')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('voice.once')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('voice.send')));
      await tester.pumpAndSettle();
      final clientId = deps.messaging.sentClientIds.last;
      expect(deps.messaging.sentViewOnce, [clientId]);
      expect(find.byKey(Key('view_once.srv-$clientId')), findsOneWidget);
      expect(find.text('Pas encore écouté'), findsOneWidget);
    });
  });

  group('GIF', () {
    testWidgets('chercher puis envoyer un GIF (contenu tout public par défaut)', (tester) async {
      final deps = await _openBob(tester);
      await tester.tap(find.byKey(const Key('composer.emoji')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expression.tab.gifs')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gif.attribution')), findsOneWidget);
      expect(deps.messaging.gifSearches.first, ('', 'g'), reason: 'tendances à l’ouverture');

      await tester.enterText(find.byKey(const Key('gif.search')), 'bravo');
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(deps.messaging.gifSearches.last, ('bravo', 'g'));

      expect(find.byKey(const Key('expression.panel')), findsOneWidget);
      expect(find.byKey(const Key('gif.item.gif-2')), findsOneWidget);
      await tester.tap(find.byKey(const Key('gif.item.gif-2')));
      await tester.pumpAndSettle();
      expect(deps.messaging.sentGifs, ['gif-2']);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.startsWith('gif.bubble.'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('réglage « Modéré » transmis à la recherche', (tester) async {
      final d = _deps();
      d.flags.gif = 'pg13';
      final deps = await _openBob(tester, deps: d);
      await tester.tap(find.byKey(const Key('composer.emoji')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expression.tab.gifs')));
      await tester.pumpAndSettle();
      expect(deps.messaging.gifSearches.first.$2, 'pg13');
    });

    testWidgets('service indisponible : message et « Réessayer »', (tester) async {
      final d = _deps();
      d.messaging.gifFailure = const AppFailure(FailureCode.gifUnavailable);
      final deps = await _openBob(tester, deps: d);
      await tester.tap(find.byKey(const Key('composer.emoji')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expression.tab.gifs')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gif.error')), findsOneWidget);
      deps.messaging.gifFailure = null;
      await tester.tap(find.byKey(const Key('gif.retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gif.item.gif-0')), findsOneWidget);
    });

    testWidgets('liste des discussions : « GIF »', (tester) async {
      final deps = await _openBob(tester);
      await tester.tap(find.byKey(const Key('composer.emoji')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expression.tab.gifs')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('gif.item.gif-1')));
      await tester.pumpAndSettle();
      expect(deps.messaging.sentGifs, ['gif-1']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('conversation.conv-bob')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('conversation.conv-bob')),
          matching: find.textContaining('GIF'),
        ),
        findsOneWidget,
      );
    });
  });

  group('aperçus des liens', () {
    testWidgets('un lien envoyé : aperçu demandé au serveur et affiché', (tester) async {
      final deps = await _openBob(tester);
      deps.messaging.nextPreview = const LinkPreview(
        url: 'https://exemple.bf/article',
        title: 'Un article',
        description: 'Le résumé',
        site: 'exemple.bf',
      );
      await tester.enterText(
        find.byKey(const Key('chat.input')),
        'Regarde https://exemple.bf/article',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat.send')));
      await tester.pumpAndSettle();
      expect(deps.messaging.previewRequests, hasLength(1));
      expect(find.byKey(const Key('link.preview')), findsOneWidget);
      expect(find.text('Un article'), findsOneWidget);

      await tester.tap(find.byKey(const Key('link.preview')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('link.confirm')),
        findsOneWidget,
        reason: 'rien ne s’ouvre sans confirmation',
      );
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
    });

    testWidgets('sans lien, ou réglage désactivé : aucune demande', (tester) async {
      final d = _deps();
      d.flags.previews = false;
      final deps = await _openBob(tester, deps: d);
      await tester.enterText(find.byKey(const Key('chat.input')), 'Bonjour');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat.send')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('chat.input')), 'https://exemple.bf');
      await tester.pump();
      await tester.tap(find.byKey(const Key('chat.send')));
      await tester.pumpAndSettle();
      expect(deps.messaging.previewRequests, isEmpty);
    });

    testWidgets('Confidentialité : aperçus et contenu des GIF', (tester) async {
      final deps = _deps();
      await tester.pumpWidget(
        ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paramètres').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.privacy')));
      await tester.pumpAndSettle();
      final previews = find.byKey(const Key('privacy.link_previews'));
      await tester.scrollUntilVisible(previews, 200, scrollable: find.byType(Scrollable).last);
      await tester.tap(previews);
      await tester.pumpAndSettle();
      expect(deps.flags.previews, isFalse);
      await tester.tap(find.byKey(const Key('privacy.gif')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('privacy.gif.pg13')));
      await tester.pumpAndSettle();
      expect(deps.flags.gif, 'pg13');
      expect(find.text('Modéré'), findsOneWidget);
    });
  });
}
