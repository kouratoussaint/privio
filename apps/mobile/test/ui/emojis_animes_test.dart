import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/core/emoji/animated_emoji_assets.g.dart';
import 'package:privio/ui/core/emoji/big_emojis.dart';

import '../helpers/fakes.dart';

/// Lot 8.5b — émojis animés (Noto Animated Emoji, intégrés) et grands.
Future<void> _openBob(WidgetTester tester, List<String> bodies) async {
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
  for (final b in bodies) {
    deps.messaging.receive('conv-bob', b);
  }
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
}

double _size(WidgetTester tester, Finder f) => tester.getSize(f.first).height;

void main() {
  test('150 émojis animés intégrés, fichiers présents et lisibles', () {
    expect(kAnimatedEmojiAssets, hasLength(150));
    for (final file in kAnimatedEmojiAssets.values) {
      final f = File('assets/emoji/$file.json');
      expect(f.existsSync(), isTrue, reason: file);
      final j = jsonDecode(f.readAsStringSync()) as Map;
      expect(j['layers'], isNotNull, reason: 'animation Lottie : $file');
    }
    expect(File('assets/emoji/LICENSE.txt').readAsStringSync(), contains('CC BY 4.0'));
  });

  test('reconnaissance d’un émoji, avec ou sans sélecteur U+FE0F', () {
    expect(BigEmojis.assetFor('❤️'), isNotNull);
    expect(BigEmojis.assetFor('❤'), BigEmojis.assetFor('❤️'));
    expect(BigEmojis.assetFor('😂'), 'assets/emoji/1f602.json');
    expect(BigEmojis.assetFor('🦕'), isNull, reason: 'pas dans les 150');
    expect(BigEmojis.sizeFor(1), greaterThan(BigEmojis.sizeFor(2)));
    expect(BigEmojis.sizeFor(2), greaterThan(BigEmojis.sizeFor(3)));
    expect(BigEmojis.split('😂 🙂'), ['😂', '🙂']);
  });

  testWidgets('1, 2 ou 3 émojis : de plus en plus petits ; non animés : fixes', (tester) async {
    await _openBob(tester, ['😂', '😂🙂', '😂🙂🦕', 'Bravo 😂']);
    final bigs = find.byKey(const Key('bubble.big_emojis'));
    expect(bigs, findsNWidgets(3));
    // Chaque message : nombre d'émojis animés, fixes, et taille d'un émoji.
    final groups = <(int, int, double)>[];
    for (var k = 0; k < 3; k++) {
      final animated = find.descendant(
        of: bigs.at(k),
        matching: find.byKey(const Key('emoji.animated')),
      );
      final still = find.descendant(of: bigs.at(k), matching: find.byKey(const Key('emoji.still')));
      groups.add((animated.evaluate().length, still.evaluate().length, _size(tester, animated)));
    }
    groups.sort((a, b) => (a.$1 + a.$2).compareTo(b.$1 + b.$2));
    expect(groups.map((g) => (g.$1, g.$2)).toList(), [(1, 0), (2, 0), (2, 1)]);
    expect(groups[0].$3, greaterThan(groups[1].$3));
    expect(groups[1].$3, greaterThan(groups[2].$3));
    expect(find.text('Bravo 😂'), findsOneWidget, reason: 'texte avec émoji : normal');
  });
}
