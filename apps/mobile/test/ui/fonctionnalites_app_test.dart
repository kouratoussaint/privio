import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 5.5 — effets des interrupteurs de la console dans l'application.
TestDeps _deps(Map<String, Object?> policies) {
  final d =
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
  d.messaging.policies = {...d.messaging.policies, ...policies};
  return d;
}

Future<void> _start(WidgetTester tester, TestDeps deps) async {
  await deps.messaging.startDirectConversation('u2');
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Finder _tab(String l) => find.descendant(of: find.byType(PrivioNavBar), matching: find.text(l));

void main() {
  testWidgets('tout activé : boutons présents, pas de message', (tester) async {
    await _start(tester, _deps({}));
    expect(find.byKey(const Key('announcement.banner')), findsNothing);
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.call')), findsOneWidget);
    expect(find.byKey(const Key('chat.video')), findsOneWidget);
    expect(find.byKey(const Key('chat.mic')), findsOneWidget);
    expect(find.byKey(const Key('composer.photo')), findsOneWidget);
  });

  testWidgets('appels, vocaux et photos coupés : boutons masqués', (tester) async {
    await _start(
      tester,
      _deps({'calls_audio_enabled': false, 'voice_enabled': false, 'photo_enabled': false}),
    );
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.call')), findsNothing);
    expect(find.byKey(const Key('chat.video')), findsNothing, reason: 'la vidéo suppose l’audio');
    expect(find.byKey(const Key('chat.mic')), findsNothing);
    expect(find.byKey(const Key('composer.photo')), findsNothing);
    final send = tester.widget<IconButton>(find.byKey(const Key('chat.send')));
    expect(send.onPressed, isNull, reason: 'rien à envoyer');
    await tester.enterText(find.byType(TextField).last, 'Salut');
    await tester.pumpAndSettle();
    expect(tester.widget<IconButton>(find.byKey(const Key('chat.send'))).onPressed, isNotNull);
  });

  testWidgets('vidéo seule coupée ; groupes et liens coupés', (tester) async {
    await _start(
      tester,
      _deps({
        'calls_video_enabled': false,
        'group_create_enabled': false,
        'group_invite_links_enabled': false,
      }),
    );
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('groups.new')), findsNothing);
    expect(find.byKey(const Key('groups.join')), findsNothing);
    await tester.tap(_tab('Discussions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.call')), findsOneWidget);
    expect(find.byKey(const Key('chat.video')), findsNothing);
  });

  testWidgets('message d’information : affiché à tous, fermable', (tester) async {
    await _start(tester, _deps({'announcement_text': 'Maintenance ce soir à 22 h'}));
    expect(find.byKey(const Key('announcement.banner')), findsOneWidget);
    expect(find.text('Maintenance ce soir à 22 h'), findsOneWidget);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    expect(find.text('Maintenance ce soir à 22 h'), findsWidgets);
    await tester.tap(find.byKey(const Key('announcement.close')).last);
    await tester.pumpAndSettle();
    expect(find.text('Maintenance ce soir à 22 h'), findsNothing);
  });
}
