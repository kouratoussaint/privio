import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/messaging.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 7.1a — fiches contact et groupe : photo en grand, « À propos », durée, sourdine,
/// « Vider », médias de la discussion, groupes en commun.
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

Future<void> _openBobFiche(WidgetTester tester, TestDeps deps) async {
  await deps.messaging.startDirectConversation('u2');
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('conversation.conv-bob')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('chat.contact')));
  await tester.pumpAndSettle();
}

Finder get _list => find.byType(Scrollable).first;

Future<void> _scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(find.byKey(Key(key)), 150, scrollable: _list);
  await tester.pumpAndSettle();
}

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

void main() {
  testWidgets('fiche contact : À propos, photo en grand, groupes en commun', (tester) async {
    final deps = _deps();
    deps.messaging
      ..contactAbout['u2'] = 'Au travail jusqu’à 18 h'
      ..bobAvatarPath = 'u2/avatar.jpg'
      ..storedAvatars['u2/avatar.jpg'] = testJpeg(width: 64, height: 64)
      ..commonGroups['u2'] = const [CommonGroup(id: 'g-voisins', title: 'Voisins', memberCount: 4)];
    deps.messaging.seedGroup('g-voisins', 'Voisins');
    await _openBobFiche(tester, deps);
    expect(find.text('À propos'), findsOneWidget);
    expect(find.text('Au travail jusqu’à 18 h'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fiche.avatar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('avatar.viewer')), findsOneWidget);
    expect(find.byKey(const Key('avatar.viewer.edit')), findsNothing, reason: 'pas la sienne');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await _scrollTo(tester, 'contact.common_groups');
    expect(find.text('1 GROUPE EN COMMUN'), findsOneWidget);
    await _scrollTo(tester, 'contact.group.g-voisins');
    await tester.tap(find.byKey(const Key('contact.group.g-voisins')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('chat.members')), findsOneWidget, reason: 'le groupe est ouvert');
  });

  testWidgets('fiche contact : À propos caché par ses réglages → rien affiché', (tester) async {
    final deps = _deps();
    await _openBobFiche(tester, deps);
    expect(find.byKey(const Key('contact.about')), findsNothing);
    expect(find.text('@bob_ouaga'), findsOneWidget);
  });

  testWidgets('fiche contact : médias encore présents, photo en grand, vocaux', (tester) async {
    final deps = _deps();
    await deps.messaging.startDirectConversation('u2');
    deps.messaging
      ..receivePhoto('conv-bob')
      ..receiveVoice('conv-bob', durationMs: 12000)
      ..receive('conv-bob', 'Texte sans média');
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.contact')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, 'fiche.media.all');
    expect(find.text('2 éléments · effacés avec les messages'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fiche.media.all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('media.screen')), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Vocaux'), findsOneWidget);
    expect(find.textContaining('ne peuvent pas être enregistrés'), findsOneWidget);
    // La photo (téléchargement automatique selon le réglage) : toucher pour l'ouvrir ou la charger.
    final thumb = find.byWidgetPredicate(
      (w) =>
          w.key is ValueKey<String> &&
          ((w.key! as ValueKey<String>).value.startsWith('fiche.media.photo.') ||
              (w.key! as ValueKey<String>).value.startsWith('fiche.media.download.')),
    );
    expect(thumb, findsOneWidget);
  });

  testWidgets('fiche contact : sourdine 8 h puis réactivation', (tester) async {
    final deps = _deps();
    await _openBobFiche(tester, deps);
    expect(find.text('Activées'), findsOneWidget);
    await tester.tap(find.byKey(const Key('contact.mute')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mute.8')));
    await tester.pumpAndSettle();
    expect(deps.messaging.muted['conv-bob'], isNotNull);
    expect(find.textContaining('Désactivées jusqu’au'), findsOneWidget);
    await tester.tap(find.byKey(const Key('contact.mute')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mute.off')));
    await tester.pumpAndSettle();
    expect(find.text('Activées'), findsOneWidget);
  });

  testWidgets('fiche contact : durée des messages', (tester) async {
    final deps = _deps();
    await _openBobFiche(tester, deps);
    await tester.tap(find.byKey(const Key('contact.ttl')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('contact.ttl.86400')));
    await tester.pumpAndSettle();
    expect(deps.messaging.lastTtlSet, ('conv-bob', 86400));
    expect(find.text('24 h'), findsOneWidget);
  });

  testWidgets('fiche contact : « Vider » propose le choix sur la fiche et y reste', (tester) async {
    final deps = _deps();
    deps.messaging.receive('conv-bob', 'À effacer');
    await _openBobFiche(tester, deps);
    await tester.tap(find.byKey(const Key('contact.clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('clear.everyone')), findsOneWidget);
    await tester.tap(find.byKey(const Key('clear.me')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('clear.confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Discussion vidée.'), findsOneWidget);
    expect(find.byKey(const Key('contact.clear')), findsOneWidget, reason: 'toujours sur la fiche');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('À effacer'), findsNothing, reason: 'la discussion est vidée');
  });

  testWidgets('fiche groupe : photo en grand avec « Changer » pour un administrateur, médias', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging
      ..seedGroup('g-voisins', 'Voisins')
      ..storedAvatars['g/avatar.jpg'] = testJpeg(width: 64, height: 64)
      ..groups['g-voisins']!.avatarPath = 'g/avatar.jpg';
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(_tab('Groupes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conversation.g-voisins')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.contact')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fiche.avatar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('avatar.viewer')), findsOneWidget);
    expect(find.byKey(const Key('avatar.viewer.edit')), findsOneWidget);
    await tester.tap(find.byKey(const Key('avatar.viewer.edit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('group.photo.gallery')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await _scrollTo(tester, 'group.clear');
    expect(find.byKey(const Key('group.clear')), findsOneWidget);
    await _scrollTo(tester, 'fiche.media.all');
    expect(find.text('Aucune photo ni vocal pour l’instant'), findsOneWidget);
  });

  testWidgets('Paramètres : écrire son À propos', (tester) async {
    final deps = _deps();
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(_tab('Paramètres'));
    await tester.pumpAndSettle();
    expect(find.text('Ajouter un court texte de présentation'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings.about')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('about.text')), '  Disponible   le soir ');
    await tester.tap(find.byKey(const Key('about.save')));
    await tester.pumpAndSettle();
    expect(deps.api.account!.profile!.about, 'Disponible le soir');
    expect(find.text('Disponible le soir'), findsOneWidget);
    expect(find.text('À propos enregistré.'), findsOneWidget);
  });

  testWidgets('Confidentialité : « Qui voit mon À propos »', (tester) async {
    final deps = _deps();
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await tester.pumpAndSettle();
    await tester.tap(_tab('Paramètres'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings.privacy')),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('settings.privacy')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('privacy.about')),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('privacy.about')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('privacy.about.nobody')));
    await tester.pumpAndSettle();
    expect(deps.messaging.privacy.about, 'nobody');
  });
}
