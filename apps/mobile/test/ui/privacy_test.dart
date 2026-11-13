import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/state/privacy_providers.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 4.3 — confidentialité avancée, présence, « vider la discussion », via les écrans réels.
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

Future<void> _start(WidgetTester tester, TestDeps deps) async {
  await deps.messaging.startDirectConversation('u2');
  deps.messaging
    ..receive('conv-bob', 'Premier message')
    ..receive('conv-bob', 'Deuxième message');
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

Future<void> _openPrivacy(WidgetTester tester) async {
  await tester.tap(_tab('Paramètres'));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('settings.privacy')),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(find.byKey(const Key('settings.privacy')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings.privacy')));
  await tester.pumpAndSettle();
}

Future<void> _openBob(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
}

Future<void> _clear(WidgetTester tester, String option) async {
  await tester.tap(find.byKey(const Key('chat.menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('chat.clear')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('clear.$option')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('clear.confirm')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('écran Confidentialité\u202F: visibilités, accusés, écriture, durée par défaut', (
    tester,
  ) async {
    final deps = _deps();
    await _start(tester, deps);
    await _openPrivacy(tester);
    expect(
      find.text('Mes contacts'),
      findsOneWidget,
      reason: 'présence\u202F: contacts par défaut',
    );

    await tester.tap(find.byKey(const Key('privacy.presence')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy.presence.nobody')));
    await tester.pumpAndSettle();
    expect(deps.messaging.privacy.presence, 'nobody');

    await tester.tap(find.byKey(const Key('privacy.avatar')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy.avatar.contacts')));
    await tester.pumpAndSettle();
    expect(deps.messaging.privacy.avatar, 'contacts');

    await tester.tap(find.byKey(const Key('privacy.invites')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy.invites.nobody')));
    await tester.pumpAndSettle();
    expect(deps.messaging.privacy.groupInvites, 'nobody');

    await tester.tap(find.byKey(const Key('privacy.receipts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy.typing')));
    await tester.pumpAndSettle();
    expect(deps.messaging.privacy.readReceipts, isFalse);
    expect(deps.messaging.privacy.typing, isFalse);

    await tester.scrollUntilVisible(
      find.byKey(const Key('privacy.ttl')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy.ttl')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy.ttl.3600')));
    await tester.pumpAndSettle();
    expect(deps.messaging.privacy.defaultTtlSeconds, 3600);
    await tester.tap(find.byKey(const Key('privacy.ttl')));
    await tester.pumpAndSettle();
    // 72 h n'a pas de puce (lot 4.6) : « Personnalisé », roulette des heures de 1 à 72.
    await tester.tap(find.byKey(const Key('privacy.ttl.custom')));
    await tester.pumpAndSettle();
    final hours = tester.widget<ListWheelScrollView>(
      find.descendant(
        of: find.byKey(const Key('privacy.ttl.custom.hours')),
        matching: find.byType(ListWheelScrollView),
      ),
    );
    (hours.controller! as FixedExtentScrollController).jumpToItem(72);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy.ttl.custom.ok')));
    await tester.pumpAndSettle();
    expect(deps.messaging.privacy.defaultTtlSeconds, isNull, reason: '72 h = pas de défaut');
    expect(deps.messaging.privacySaves, hasLength(7));
  });

  testWidgets('refus du serveur\u202F: réglage remis comme avant, message clair', (tester) async {
    final deps = _deps()..messaging.failPrivacy = true;
    await _start(tester, deps);
    await _openPrivacy(tester);
    await tester.tap(find.byKey(const Key('privacy.receipts')));
    await tester.pumpAndSettle();
    expect(find.text('Réglage de confidentialité invalide.'), findsOneWidget);
    final sw = tester.widget<SwitchListTile>(find.byKey(const Key('privacy.receipts')));
    expect(sw.value, isTrue);
  });

  testWidgets('«\u202Fen train d’écrire\u202F» désactivé\u202F: aucun signal envoyé', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging.privacy = const PrivacySettings(typing: false);
    await _start(tester, deps);
    await _openBob(tester);
    await tester.enterText(find.byKey(const Key('chat.input')), 'Bonjour');
    await tester.pump(const Duration(milliseconds: 100));
    expect(deps.messaging.typingSignals, 0);
  });

  testWidgets('présence\u202F: «\u202Fen ligne\u202F», «\u202Fvu hier\u202F», ou rien si caché', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging.presences['u2'] = const UserPresence(visible: true, online: true);
    await _start(tester, deps);
    expect(deps.messaging.presenceTouches, contains(true), reason: 'Privio ouvert\u202F: signalé');
    await _openBob(tester);
    expect(find.text('en ligne'), findsOneWidget);

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    deps.messaging.presences['u2'] = UserPresence(visible: true, lastSeenAt: yesterday);
    await tester.pump(kPresencePoll);
    await tester.pumpAndSettle();
    expect(find.textContaining('vu hier à'), findsOneWidget);

    deps.messaging.presences['u2'] = const UserPresence();
    await tester.pump(kPresencePoll);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.presence')), findsNothing);
    expect(find.text('@bob_ouaga'), findsOneWidget);

    // Application en arrière-plan : « hors ligne » signalé.
    for (final st in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(st);
    }
    await tester.pumpAndSettle();
    expect(deps.messaging.presenceTouches.last, isFalse);
  });

  testWidgets(
    'vider seulement chez moi\u202F: la discussion devient vide, sans «\u202FMessage supprimé\u202F»',
    (tester) async {
      final deps = _deps();
      await _start(tester, deps);
      await _openBob(tester);
      expect(find.text('Premier message'), findsOneWidget);
      await _clear(tester, 'me');
      expect(find.text('Discussion vidée.'), findsOneWidget);
      expect(find.text('Premier message'), findsNothing);
      expect(find.text('Deuxième message'), findsNothing);
      expect(find.text('Message supprimé'), findsNothing);
      expect(deps.messaging.clearedBefore['conv-bob'], isNotNull);
      expect(deps.messaging.messages['conv-bob'], hasLength(2), reason: 'Bob garde les siens');
    },
  );

  testWidgets('vider pour nous deux\u202F: demande, bandeau d’attente, annulation', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await _openBob(tester);
    await _clear(tester, 'everyone');
    expect(find.text('Demande envoyée à Bob.'), findsOneWidget);
    expect(deps.messaging.clearRequests['conv-bob'], 'u1');
    expect(find.byKey(const Key('clear.banner')), findsOneWidget);
    expect(find.textContaining('en attente de l’accord de Bob'), findsOneWidget);
    expect(find.text('Premier message'), findsOneWidget, reason: 'rien n’est effacé avant accord');

    await tester.tap(find.byKey(const Key('clear.cancel')));
    await tester.pumpAndSettle();
    expect(deps.messaging.clearRequests, isEmpty);
    expect(find.byKey(const Key('clear.banner')), findsNothing);
  });

  testWidgets('demande reçue\u202F: aperçu dans la liste\u202F; accepter vide tout, sans trace', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging.clearRequests['conv-bob'] = 'u2';
    await _start(tester, deps);
    expect(find.text('Propose de vider la discussion'), findsOneWidget);
    await _openBob(tester);
    expect(find.textContaining('Bob propose de vider toute la discussion'), findsOneWidget);
    await tester.tap(find.byKey(const Key('clear.accept')));
    await tester.pumpAndSettle();
    expect(find.text('Premier message'), findsNothing);
    expect(find.text('Message supprimé'), findsNothing);
    expect(find.byKey(const Key('clear.banner')), findsNothing);
    expect(deps.messaging.messages['conv-bob'], isEmpty);
  });

  testWidgets('demande reçue\u202F: refuser garde tout', (tester) async {
    final deps = _deps();
    deps.messaging.clearRequests['conv-bob'] = 'u2';
    await _start(tester, deps);
    await _openBob(tester);
    await tester.tap(find.byKey(const Key('clear.refuse')));
    await tester.pumpAndSettle();
    expect(find.text('Demande refusée.'), findsOneWidget);
    expect(find.text('Premier message'), findsOneWidget);
    expect(find.byKey(const Key('clear.banner')), findsNothing);
  });

  testWidgets(
    'groupe\u202F: un membre vide seulement chez lui\u202F; un administrateur pour tous',
    (tester) async {
      final deps = _deps();
      deps.messaging
        ..seedGroup('g1', 'Famille', owner: 'u2', members: {FakeMessagingApi.me: 'member'})
        ..receiveInGroup('g1', 'u2', 'Bonjour la famille');
      await _start(tester, deps);
      await tester.tap(find.byKey(const Key('conversation.g1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat.clear')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clear.everyone')), findsNothing, reason: 'membre simple');
      expect(find.byKey(const Key('clear.me')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      deps.messaging.groups['g1']!.roles[FakeMessagingApi.me] = 'admin';
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('conversation.g1')));
      await tester.pumpAndSettle();
      await _clear(tester, 'everyone');
      expect(find.text('Bonjour la famille'), findsNothing);
      expect(deps.messaging.messages['g1'], isEmpty);
    },
  );
}
