import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/state/feedback_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:privio/core/media/photo_processing.dart';
import 'package:privio/ui/features/conversations/expression_panel.dart';
import 'package:privio/ui/features/conversations/photo_editor.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';
import '../helpers/settings_nav.dart';

/// Lot 7.3a — émojis, autocollants, retouche photo, fond d'écran.
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

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

Future<TestDeps> _openBob(WidgetTester tester, {List<String> bodies = const ['Salut']}) async {
  final deps = _deps();
  await deps.messaging.startDirectConversation('u2');
  for (final b in bodies) {
    deps.messaging.receive('conv-bob', b);
  }
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
  return deps;
}

void main() {
  test('grands émojis : 1 à 3 émojis seuls', () {
    for (final t in ['😀', '😀😂👍', '❤️', '🇧🇫', '👍🏾', '👨‍👩‍👧', ' 🎉 ']) {
      expect(isJumboEmoji(t), isTrue, reason: t);
    }
    for (final t in ['😀😂👍🎉', 'ok 😀', '1', '', 'Merci', '😀a', '#']) {
      expect(isJumboEmoji(t), isFalse, reason: t);
    }
  });

  test('chaque autocollant a son image', () {
    expect(kPrivioStickers, hasLength(24));
    expect({for (final s in kPrivioStickers) s.id}, hasLength(24));
    expect(stickerOf('privio/merci')?.label, 'Merci\u202F!');
    expect(stickerOf('autre/inconnu'), isNull);
  });

  group('panneau émojis et autocollants', () {
    testWidgets('envoyer un autocollant : il s’affiche sans bulle, avec le son', (tester) async {
      final deps = await _openBob(tester);
      expect(find.byKey(const Key('expression.panel')), findsNothing);
      await tester.tap(find.byKey(const Key('composer.emoji')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expression.panel')), findsOneWidget);
      await tester.tap(find.byKey(const Key('expression.tab.stickers')));
      await tester.pumpAndSettle();
      deps.sounds.played.clear();
      await tester.tap(find.byKey(const Key('sticker.merci')));
      await tester.pumpAndSettle();
      expect(deps.messaging.sentStickers, ['privio/merci']);
      expect(deps.sounds.played, contains(PrivioSound.sent));
      expect(
        find.descendant(
          of: find.byType(ListView).first,
          matching: find.byKey(const Key('sticker.image.merci')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('expression.panel')), findsOneWidget, reason: 'reste ouvert');

      // « Retour » ferme d'abord le panneau, sans quitter la discussion.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expression.panel')), findsNothing);
      expect(find.byKey(const Key('chat.input')), findsOneWidget);
    });

    testWidgets('choisir un émoji l’ajoute au message ; toucher le champ ferme le panneau', (
      tester,
    ) async {
      await _openBob(tester);
      await tester.tap(find.byKey(const Key('composer.emoji')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.tag_faces));
      await tester.pumpAndSettle();
      await tester.tap(find.text('😀').first);
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(find.byKey(const Key('chat.input')));
      expect(input.controller!.text, '😀');
      expect(find.byKey(const Key('chat.send')), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat.input')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('expression.panel')), findsNothing);
    });

    testWidgets('liste des discussions : « 🙂 Merci ! »', (tester) async {
      final deps = await _openBob(tester);
      await tester.tap(find.byKey(const Key('composer.emoji')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('expression.tab.stickers')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sticker.merci')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('🙂 Merci'), findsOneWidget);
      expect(deps.messaging.sentStickers, hasLength(1));
    });
  });

  testWidgets('message fait seulement d’émojis : affiché en grand', (tester) async {
    await _openBob(tester, bodies: ['👍', 'Super 👍']);
    final big = tester.widget<Text>(find.text('👍'));
    expect(big.style?.fontSize, 44);
    final normal = tester.widget<Text>(find.text('Super 👍'));
    expect(normal.style?.fontSize, isNot(44));
  });

  testWidgets('réagir avec n’importe quel émoji', (tester) async {
    final deps = await _openBob(tester, bodies: ['Réagis ici']);
    await tester.longPress(find.text('Réagis ici'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('react.more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reaction.picker')), findsOneWidget);
    await tester.tap(find.byIcon(Icons.tag_faces));
    await tester.pumpAndSettle();
    await tester.tap(find.text('😀').first);
    await tester.pumpAndSettle();
    final m = deps.messaging.messages['conv-bob']!.firstWhere((m) => m.body == 'Réagis ici');
    expect(m.reactions.single.emoji, '😀');
  });

  test('retouche dans un isolat (comme sur le téléphone)', () async {
    final bytes = testJpeg(width: 80, height: 40);
    final rotated = await compute(applyPhotoEdit, PhotoEdit.rotate(bytes));
    expect((rotated.width, rotated.height), (40, 80));
    final cropped = await compute(applyPhotoEdit, PhotoEdit.crop(bytes, const [0, 0, 0.5, 0.5]));
    expect((cropped.width, cropped.height), (40, 20));
    final drawn = await compute(
      applyPhotoEdit,
      PhotoEdit.draw(bytes, const [
        (0xFFE63946, 0.05, [(0.2, 0.5), (0.8, 0.5)]),
      ]),
    );
    expect(drawn.bytes, isNot(bytes));
  });

  testWidgets('écran de retouche avec un vrai isolat : « Terminé » aboutit', (tester) async {
    PhotoEditorScreen.inline = false;
    addTearDown(() => PhotoEditorScreen.inline = true);
    PreparedPhoto? result;
    final photo = PreparedPhoto(bytes: testJpeg(width: 80, height: 40), width: 80, height: 40);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await Navigator.of(context).push<PreparedPhoto>(
              MaterialPageRoute(builder: (_) => PhotoEditorScreen(photo: photo)),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor.rotate')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor.draw')));
    await tester.pumpAndSettle();
    final canvas = tester.getRect(find.byKey(const Key('editor.canvas')));
    await tester.dragFrom(canvas.center - const Offset(20, 0), const Offset(40, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('editor.done')));
    for (var i = 0; i < 20 && result == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    expect(result, isNotNull, reason: '« Terminé » ne tourne plus sans fin');
    expect((result!.width, result!.height), (40, 80));
  });

  group('retouche avant l’envoi', () {
    Future<void> openEditor(WidgetTester tester, TestDeps deps) async {
      deps.photos.photo = testJpeg(width: 80, height: 40);
      await tester.tap(find.byKey(const Key('composer.photo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo.gallery')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo.compose.edit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photo.editor')), findsOneWidget);
    }

    img.Image sent(TestDeps deps) => img.decodeJpg(deps.messaging.storedPhotos.values.last)!;

    testWidgets('pivoter : la photo envoyée est tournée', (tester) async {
      final deps = await _openBob(tester);
      await openEditor(tester, deps);
      await tester.tap(find.byKey(const Key('editor.rotate')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor.done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo.send')));
      await tester.pumpAndSettle();
      expect((sent(deps).width, sent(deps).height), (40, 80));
    });

    testWidgets('recadrer : la photo envoyée est plus petite', (tester) async {
      final deps = await _openBob(tester);
      await openEditor(tester, deps);
      await tester.tap(find.byKey(const Key('editor.crop')));
      await tester.pumpAndSettle();
      final canvas = tester.getRect(find.byKey(const Key('editor.canvas')));
      final gesture = await tester.startGesture(canvas.bottomRight - const Offset(2, 2));
      await gesture.moveBy(const Offset(-20, -10));
      await gesture.moveBy(Offset(-canvas.width / 2 + 20, -canvas.height / 3 + 10));
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor.crop.apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor.done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo.send')));
      await tester.pumpAndSettle();
      expect(sent(deps).width, lessThan(80));
      expect(sent(deps).height, lessThan(40));
    });

    testWidgets('dessiner, annuler, dessiner : le trait est dans la photo envoyée', (tester) async {
      final deps = await _openBob(tester);
      await openEditor(tester, deps);
      await tester.tap(find.byKey(const Key('editor.draw')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor.color.2')));
      final canvas = tester.getRect(find.byKey(const Key('editor.canvas')));
      await tester.dragFrom(canvas.center - const Offset(30, 0), const Offset(60, 0));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor.undo')), findsOneWidget);
      await tester.tap(find.byKey(const Key('editor.undo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor.undo')), findsNothing);
      await tester.dragFrom(canvas.center - const Offset(30, 0), const Offset(60, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor.done')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('photo.send')));
      await tester.pumpAndSettle();
      final image = sent(deps);
      final px = image.getPixel(image.width ~/ 2, image.height ~/ 2);
      expect(px.r, greaterThan(150), reason: 'trait rouge au centre');
      expect(px.b, lessThan(150));
    });
  });

  group('fond d’écran', () {
    testWidgets('par défaut dans Paramètres, puis propre à une discussion', (tester) async {
      final deps = _deps();
      await deps.messaging.startDirectConversation('u2');
      deps.messaging.receive('conv-bob', 'Salut');
      await tester.pumpWidget(
        ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
      );
      await tester.pumpAndSettle();
      await tester.tap(_tab('Paramètres'));
      await tester.pumpAndSettle();
      await openSettingsEntry(tester, 'settings.chats');
      await tester.ensureVisible(find.byKey(const Key('settings.wallpaper')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings.wallpaper')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('wallpaper.lavande')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wallpaper.lavande')));
      await tester.pumpAndSettle();
      expect(deps.flags.wallpapers[null], 'color:lavande');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(_tab('Discussions'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation.conv-bob')));
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate((w) => w is ColoredBox && w.color == const Color(0xFFEDE7FB)),
        findsWidgets,
      );

      await tester.tap(find.byKey(const Key('chat.contact')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('fiche.wallpaper')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.byKey(const Key('fiche.wallpaper')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fiche.wallpaper')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('wallpaper.dots')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wallpaper.dots')));
      await tester.pumpAndSettle();
      expect(deps.flags.wallpapers['conv-bob'], 'pattern:dots');
      await tester.ensureVisible(find.byKey(const Key('wallpaper.default')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wallpaper.default')));
      await tester.pumpAndSettle();
      expect(deps.flags.wallpapers.containsKey('conv-bob'), isFalse);
    });
  });
}
