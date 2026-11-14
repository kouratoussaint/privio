import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/theme/privio_palette.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/core/widgets/settings_card.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 7.2a — fonds et cartes, « Vider » sur la fiche, Ma fiche, confidentialité par
/// discussion, fausse alerte « hors connexion » au retour dans l'app.
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

Future<void> _start(WidgetTester tester, TestDeps deps) async {
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, String key, {double delta = 150}) async {
  await tester.scrollUntilVisible(
    find.byKey(Key(key)),
    delta,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _openBobFiche(WidgetTester tester, TestDeps deps) async {
  await deps.messaging.startDirectConversation('u2');
  await _start(tester, deps);
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('chat.contact')));
  await tester.pumpAndSettle();
}

Future<void> _openGroupFiche(WidgetTester tester, TestDeps deps) async {
  deps.messaging.seedGroup('g1', 'Voisins', members: {'u2': 'member'});
  await _start(tester, deps);
  await tester.tap(_tab('Groupes'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.g1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('chat.contact')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Ma fiche : ouverte depuis la ligne du profil ; nom modifiable', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(_tab('Paramètres'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.profile')));
    await tester.pumpAndSettle();
    expect(find.text('Ma fiche'), findsOneWidget);
    expect(find.text('@toussaint_bf · ne peut pas être changé'), findsOneWidget);

    await tester.tap(find.byKey(const Key('my.name')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('name.text')), '   ');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('name.save'))).onPressed,
      isNull,
      reason: 'nom vide : impossible',
    );
    await tester.enterText(find.byKey(const Key('name.text')), '  Toussaint   K. ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('name.save')));
    await tester.pumpAndSettle();
    expect(deps.api.displayNames, ['Toussaint K.']);
    expect(find.text('Nom enregistré.'), findsOneWidget);
    expect(find.byKey(const Key('my.title')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('my.title'))).data, 'Toussaint K.');

    await tester.tap(find.byKey(const Key('my.about')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('about.text')), 'Disponible le soir');
    await tester.tap(find.byKey(const Key('about.save')));
    await tester.pumpAndSettle();
    expect(deps.api.account!.profile!.about, 'Disponible le soir');
  });

  testWidgets('confidentialité de la discussion : accusés coupés, en ligne caché à Bob', (
    tester,
  ) async {
    final deps = _deps();
    await _openBobFiche(tester, deps);
    await _scrollTo(tester, 'conv_privacy.receipts');
    expect(find.text('Comme dans mes réglages (activés)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('conv_privacy.receipts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conv_privacy.receipts.off')));
    await tester.pumpAndSettle();
    expect(deps.messaging.convPrivacy['conv-bob']!.readReceipts, isFalse);
    expect(find.text('Désactivés'), findsOneWidget);

    await _scrollTo(tester, 'conv_privacy.presence');
    await tester.tap(find.byKey(const Key('conv_privacy.presence')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conv_privacy.presence.off')));
    await tester.pumpAndSettle();
    final saved = deps.messaging.convPrivacy['conv-bob']!;
    expect(saved.showPresence, isFalse);
    expect(saved.readReceipts, isFalse, reason: 'les autres choix sont gardés');
    expect(find.text('Caché à Bob'), findsOneWidget);

    await tester.tap(find.byKey(const Key('conv_privacy.presence')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conv_privacy.presence.default')));
    await tester.pumpAndSettle();
    expect(deps.messaging.convPrivacy['conv-bob']!.showPresence, isNull);
  });

  testWidgets('fiche groupe : cartes, confidentialité limitée, « Vider » reste sur la fiche', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging.receiveInGroup('g1', 'u2', 'À effacer');
    await _openGroupFiche(tester, deps);
    expect(find.byType(SettingsCard), findsWidgets);
    await _scrollTo(tester, 'conv_privacy.typing');
    expect(find.byKey(const Key('conv_privacy.presence')), findsNothing);
    expect(find.byKey(const Key('conv_privacy.avatar')), findsNothing);

    await _scrollTo(tester, 'group.clear', delta: -150);
    await tester.tap(find.byKey(const Key('group.clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clear.everyone')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clear.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Discussion vidée.'), findsOneWidget);
    expect(find.byKey(const Key('group.clear')), findsOneWidget, reason: 'toujours sur la fiche');
    expect(
      deps.messaging.messages['g1']!.where((m) => m.body == 'À effacer'),
      isEmpty,
      reason: 'vidé pour tous',
    );
  });

  testWidgets('fonds : liste des groupes blanche ; Confidentialité en cartes', (tester) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byKey(const Key('groups.new')));
    final sheet = PrivioPalette.of(ctx).sheet;
    expect(
      // Lot 7.2c1 : Material (et non ColoredBox) pour que les lignes touchables y
      // dessinent leur effet d'appui.
      find.byWidgetPredicate(
        (w) => (w is ColoredBox && w.color == sheet) || (w is Material && w.color == sheet),
      ),
      findsWidgets,
      reason: 'fond blanc comme Discussions',
    );
    await tester.tap(_tab('Paramètres'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.privacy')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsCard), findsWidgets);
  });

  testWidgets('retour dans l’app : un échec isolé n’affiche pas « hors connexion »', (
    tester,
  ) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    await _start(tester, deps);
    // Réseau pas encore rendu à l'app : le premier appel échoue…
    deps.messaging.offline = true;
    deps.realtime.emit('conv-bob', event: 'resume');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    // … puis revient avant la vérification.
    deps.messaging.offline = false;
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offline.banner')), findsNothing);
  });

  testWidgets('vraie coupure : « hors connexion » annoncé après vérification', (tester) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    await _start(tester, deps);
    deps.messaging.offline = true;
    deps.realtime.emit('conv-bob', event: 'resume');
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const Key('offline.banner')), findsNothing, reason: 'vérification en cours');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offline.banner')), findsOneWidget);
    deps.messaging.offline = false;
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('offline.banner')), findsNothing);
  });
}
