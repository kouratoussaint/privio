import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/stickers.dart';
import 'package:privio/ui/features/conversations/sticker_creator.dart';

import '../helpers/fakes.dart';

/// Lot 7.4 — autocollants personnels : créer (détourage, texte, « Partageable »), envoyer,
/// recevoir, ajouter un autocollant partageable reçu, retirer de sa collection.
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
  bool cutout = true,
  void Function(TestDeps)? before,
}) async {
  final d = deps ?? _deps();
  await d.messaging.startDirectConversation('u2');
  before?.call(d);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...d.overrides,
        subjectCutoutProvider.overrideWithValue((_) async => cutout ? testPng(size: 48) : null),
        stickerRendererProvider.overrideWithValue((_) async => testPng(size: 64)),
      ],
      retry: (_, _) => null,
      child: const PrivioApp(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
  return d;
}

Future<void> _tap(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> _openStickers(WidgetTester tester) async {
  await _tap(tester, 'composer.emoji');
  await _tap(tester, 'expression.tab.stickers');
}

void main() {
  testWidgets('créer : photo détourée, texte, partageable, puis l’envoyer', (tester) async {
    final deps = await _openBob(tester);
    await _openStickers(tester);
    expect(find.text('Mes autocollants'), findsOneWidget);
    await _tap(tester, 'sticker.create');
    await _tap(tester, 'sticker.source.gallery');
    expect(find.byKey(const Key('sticker.cutout')), findsOneWidget, reason: 'sujet détouré');
    await tester.enterText(find.byKey(const Key('sticker.text')), 'Bravo !');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sticker.caption')), findsOneWidget);
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
    await tester.pumpAndSettle();
    await _tap(tester, 'sticker.shareable');
    await _tap(tester, 'sticker.save');

    final item = deps.messaging.myStickers.single;
    expect(item.shareable, isTrue);
    expect(find.text('Autocollant ajouté à vos autocollants'), findsOneWidget);
    expect(find.byKey(Key('sticker.mine.${item.id}')), findsOneWidget);
    expect(deps.messaging.sentCustomStickers, isEmpty, reason: 'rien n’est envoyé sans toucher');

    await _tap(tester, 'sticker.mine.${item.id}');
    expect(deps.messaging.sentCustomStickers, [item.id]);
    final sent = deps.messaging.messages['conv-bob']!.last;
    expect(sent.body, kCustomStickerShareable);
    expect(find.byType(CustomStickerImage), findsWidgets);
  });

  testWidgets('détourage impossible : recadrage de la photo seulement', (tester) async {
    await _openBob(tester, cutout: false);
    await _openStickers(tester);
    await _tap(tester, 'sticker.create');
    await _tap(tester, 'sticker.source.camera');
    expect(find.byKey(const Key('sticker.photo')), findsOneWidget);
    expect(find.textContaining('Détourage impossible sur cette photo'), findsOneWidget);
    final sw = tester.widget<SwitchListTile>(find.byKey(const Key('sticker.cutout_switch')));
    expect(sw.onChanged, isNull);
  });

  testWidgets('retirer un autocollant de sa collection (appui long)', (tester) async {
    final deps = await _openBob(
      tester,
      before: (d) {
        d.messaging.myStickers.add(const StickerItem(id: 'st-1', path: 'u1/st-1'));
        d.messaging.stickerFiles['u1/st-1'] = testPng();
      },
    );
    await _openStickers(tester);
    await tester.longPress(find.byKey(const Key('sticker.mine.st-1')));
    await tester.pumpAndSettle();
    await _tap(tester, 'sticker.remove.confirm');
    expect(deps.messaging.myStickers, isEmpty);
    expect(find.byKey(const Key('sticker.mine.st-1')), findsNothing);
  });

  testWidgets('reçu : partageable → « Ajouter à mes autocollants » ; privé → non', (tester) async {
    late String shared;
    late String private;
    final deps = await _openBob(
      tester,
      before: (d) {
        shared = d.messaging.receiveCustomSticker('conv-bob', 'u2').id;
        private = d.messaging.receiveCustomSticker('conv-bob', 'u2', shareable: false).id;
      },
    );
    expect(find.byType(CustomStickerImage), findsNWidgets(2));
    await tester.longPress(
      find.descendant(
        of: find.byKey(Key('message.$private')),
        matching: find.byType(CustomStickerImage),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action.save_sticker')), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.longPress(
      find.descendant(
        of: find.byKey(Key('message.$shared')),
        matching: find.byType(CustomStickerImage),
      ),
    );
    await tester.pumpAndSettle();
    await _tap(tester, 'action.save_sticker');
    expect(deps.messaging.myStickers, hasLength(1));
    expect(find.text('Autocollant ajouté à vos autocollants'), findsOneWidget);
  });
}
