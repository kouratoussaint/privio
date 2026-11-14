import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/errors/app_failure.dart';
import 'package:privio/data/services/photo_picker.dart';
import 'package:privio/data/storage/local_cache.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

/// Lot 3.2 — photos et photo de profil, via les écrans réels.
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
  await tester.pumpWidget(
    ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
}

Future<TestDeps> _openChatWithBob(WidgetTester tester, {TestDeps? deps}) async {
  final d = deps ?? _deps();
  await _start(tester, d);
  await tester.tap(find.byKey(const Key('discussions.new')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('search.input')), 'bob_ouaga');
  await tester.tap(find.byKey(const Key('search.submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('search.write')));
  await tester.pumpAndSettle();
  return d;
}

/// Bouton photo → galerie → aperçu (légende) → envoi.
Future<void> _sendPhoto(WidgetTester tester, {String caption = ''}) async {
  await tester.tap(find.byKey(const Key('composer.photo')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('photo.gallery')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('photo.compose')), findsOneWidget);
  if (caption.isNotEmpty) await tester.enterText(find.byKey(const Key('photo.caption')), caption);
  await tester.tap(find.byKey(const Key('photo.send')));
  await tester.pumpAndSettle();
}

String _snack(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)))
    .data!;

void main() {
  testWidgets('envoyer une photo avec légende\u202F: compteur, aperçu, bulle', (tester) async {
    final deps = await _openChatWithBob(tester);
    await tester.tap(find.byKey(const Key('composer.photo')));
    await tester.pumpAndSettle();
    expect(find.text('Il vous reste 5 photos aujourd’hui (5 par jour).'), findsOneWidget);
    await tester.tap(find.byKey(const Key('photo.gallery')));
    await tester.pumpAndSettle();
    expect(deps.photos.sources, [PhotoSource.gallery]);
    expect(find.byKey(const Key('photo.compose.quota')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('photo.caption')), 'Le marché de Ouaga');
    await tester.tap(find.byKey(const Key('photo.send')));
    await tester.pumpAndSettle();

    final id = 'srv-${deps.messaging.sentClientIds.single}';
    expect(deps.messaging.sentCaptions.single, 'Le marché de Ouaga');
    expect(deps.messaging.storedPhotos.values.single.sublist(0, 2), [0xFF, 0xD8]);
    expect(find.byKey(Key('photo.open.msg-$id')), findsOneWidget, reason: 'photo affichée');
    expect(find.text('Le marché de Ouaga'), findsOneWidget);
    expect(
      deps.vault.files.keys,
      contains(LocalCache.messageMediaKey(id)),
      reason: 'gardée chiffrée sur le téléphone, sans retéléchargement',
    );
    expect(deps.messaging.photoDownloads, isEmpty);
  });

  testWidgets('photos du jour épuisées\u202F: choix désactivés, explication', (tester) async {
    final deps = _deps();
    deps.messaging.photosUsed = 5;
    await _openChatWithBob(tester, deps: deps);
    // Lot 4.4 : icône atténuée avec la pastille « 0 » avant même de toucher.
    expect(
      find.descendant(of: find.byKey(const Key('composer.photo')), matching: find.text('0')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('composer.photo')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prochaines photos demain'), findsOneWidget);
    await tester.tap(find.byKey(const Key('photo.gallery')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(deps.photos.sources, isEmpty);
    expect(find.byKey(const Key('photo.compose')), findsNothing);
  });

  testWidgets('compteur changé après l’ouverture de la discussion\u202F: la feuille le relit', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    deps.messaging.photosUsed = 5; // photos envoyées depuis un autre appareil
    await tester.tap(find.byKey(const Key('composer.photo')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prochaines photos demain'), findsOneWidget);
  });

  testWidgets('quota épuisé entre-temps (autre appareil)\u202F: refus du serveur affiché', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    await tester.tap(find.byKey(const Key('composer.photo')));
    await tester.pumpAndSettle();
    deps.messaging.photosUsed = 5; // le compteur a changé depuis l'ouverture de la feuille
    await tester.tap(find.byKey(const Key('photo.gallery')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.storedPhotos, isEmpty);
    expect(find.textContaining('Non envoyé'), findsOneWidget);
    expect(_snack(tester), const AppFailure(FailureCode.photoQuotaReached).message);
  });

  testWidgets('aperçu annulé ou sélection abandonnée\u202F: rien n’est envoyé', (tester) async {
    final deps = await _openChatWithBob(tester);
    await tester.tap(find.byKey(const Key('composer.photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo.camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo.compose.cancel')));
    await tester.pumpAndSettle();
    deps.photos.photo = null;
    await tester.tap(find.byKey(const Key('composer.photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo.gallery')));
    await tester.pumpAndSettle();
    expect(deps.messaging.sentClientIds, isEmpty);
    expect(deps.vault.files, isEmpty);
  });

  testWidgets('photo reçue\u202F: téléchargée, agrandie sans aucun bouton de partage', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    final m = deps.messaging.receivePhoto('conv-bob', caption: 'Coucher de soleil');
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(deps.messaging.photoDownloads, [m.mediaPath]);
    await tester.tap(find.byKey(Key('photo.open.msg-${m.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo.viewer')), findsOneWidget);
    expect(find.byIcon(Icons.share), findsNothing);
    expect(find.byIcon(Icons.download), findsNothing);
    expect(find.textContaining('Enregistrer'), findsNothing);
    expect(find.text('Coucher de soleil'), findsWidgets);
    await tester.tap(find.byKey(const Key('photo.viewer.close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('photo.viewer')), findsNothing);
  });

  testWidgets('hors connexion\u202F: photo jamais téléchargée → message, réessai possible', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    deps.messaging.offline = true;
    final m = deps.messaging.receivePhoto('conv-bob');
    // Le message arrive avec la liste (déjà en cache), mais le fichier ne passe pas.
    deps.messaging.offline = false;
    deps.realtime.emit('conv-bob');
    await tester.pump();
    deps.messaging.offline = true;
    await tester.pumpAndSettle();
    expect(find.byKey(Key('photo.retry.msg-${m.id}')), findsOneWidget);
    deps.messaging.offline = false;
    await tester.tap(find.byKey(Key('photo.retry.msg-${m.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('photo.open.msg-${m.id}')), findsOneWidget);
  });

  testWidgets('photo envoyée hors connexion\u202F: elle attend, puis part sans doublon', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    deps.messaging.offline = true;
    await _sendPhoto(tester, caption: 'En attente');
    final clientId = deps.messaging.sentClientIds.single;
    expect(find.byKey(Key('pending.$clientId')), findsOneWidget);
    expect(
      find.byKey(Key('photo.open.out-$clientId')),
      findsOneWidget,
      reason: 'la photo en attente s’affiche depuis le coffre local',
    );
    deps.messaging.offline = false;
    deps.realtime.emit('conv-bob', event: 'reconnected');
    await tester.pumpAndSettle();
    expect(deps.messaging.sentClientIds, everyElement(clientId));
    expect(deps.messaging.storedPhotos, hasLength(1));
    expect(find.byKey(Key('photo.open.msg-srv-$clientId')), findsOneWidget);
    expect(deps.vault.files.keys.where((k) => k.startsWith('out-')), isEmpty);
  });

  testWidgets('répondre à une photo\u202F; une photo ne se modifie pas\u202F; supprimée pour moi', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    final m = deps.messaging.receivePhoto('conv-bob', caption: 'Plage');
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Plage'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action.edit')), findsNothing);
    await tester.tap(find.byKey(const Key('action.reply')));
    await tester.pumpAndSettle();
    expect(find.text('📷 Plage'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('chat.input')), 'Magnifique');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(const Key('bubble.quote')), matching: find.text('📷 Plage')),
      findsOneWidget,
    );

    await tester.longPress(find.text('Plage'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('action.delete_me')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('photo.open.msg-${m.id}')), findsNothing);
    expect(deps.vault.files.keys, isNot(contains(LocalCache.messageMediaKey(m.id))));
  });

  testWidgets('liste\u202F: aperçu «\u202F📷 Photo\u202F» et photo de profil du correspondant', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    deps.messaging
      ..bobAvatarPath = 'u2/avatar.jpg'
      ..storedAvatars['u2/avatar.jpg'] = testJpeg(width: 64, height: 64)
      ..receivePhoto('conv-bob');
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('avatar.photo.u2/avatar.jpg')),
      findsOneWidget,
      reason: 'en-tête de la discussion',
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('📷 Photo'), findsOneWidget);
    expect(find.byKey(const Key('avatar.photo.u2/avatar.jpg')), findsOneWidget);

    // Bloqué : plus de photo de profil.
    deps.messaging.blocked.add(FakeMessagingApi.bob.id);
    deps.realtime.emit('conv-bob');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('avatar.photo.u2/avatar.jpg')), findsNothing);
  });

  testWidgets('photo de profil\u202F: choisir, puis retirer (Paramètres → Ma fiche)', (
    tester,
  ) async {
    final deps = _deps();
    await _start(tester, deps);
    await tester.tap(find.text('Paramètres'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('my.photo')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('avatar.remove')), findsNothing, reason: 'pas encore de photo');
    await tester.tap(find.byKey(const Key('avatar.gallery')));
    await tester.pumpAndSettle();
    expect(_snack(tester), 'Photo de profil mise à jour.');
    final path = deps.api.account!.profile!.avatarPath!;
    expect(find.byKey(Key('avatar.photo.$path')), findsOneWidget);
    expect(deps.api.avatars[path]!.sublist(0, 2), [0xFF, 0xD8]);
    await tester.pump(const Duration(seconds: 5)); // le message de confirmation disparaît
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('my.photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('avatar.remove')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('avatar.photo.$path')), findsNothing);
    expect(deps.api.account!.profile!.avatarPath, isNull);
  });

  testWidgets('appareil photo indisponible\u202F: message clair', (tester) async {
    final deps = await _openChatWithBob(tester);
    deps.photos.failure = const AppFailure(FailureCode.cameraUnavailable);
    await tester.tap(find.byKey(const Key('composer.photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo.camera')));
    await tester.pumpAndSettle();
    expect(_snack(tester), const AppFailure(FailureCode.cameraUnavailable).message);
  });

  testWidgets('plusieurs photos\u202F: limite du jour, retrait, un message par photo (lot 4.5)', (
    tester,
  ) async {
    final deps = _deps();
    deps.messaging.photosUsed = 2; // 3 restantes
    deps.photos.many = [testJpeg(), testJpeg(), testJpeg(), testJpeg()];
    await _openChatWithBob(tester, deps: deps);
    await tester.tap(find.byKey(const Key('composer.photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo.gallery')));
    await tester.pumpAndSettle();
    expect(deps.photos.limits, [3], reason: 'jamais plus que les photos restantes');
    expect(find.text('1 sur 3'), findsOneWidget);
    expect(find.text('Ce sont vos dernières photos du jour (5 par jour).'), findsOneWidget);

    // Légende de la 1re, puis retrait de la 2e.
    await tester.enterText(find.byKey(const Key('photo.caption')), 'Première');
    await tester.tap(find.byKey(const Key('photo.compose.thumb.1')));
    await tester.pumpAndSettle();
    expect(find.text('2 sur 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('photo.compose.remove')));
    await tester.pumpAndSettle();
    expect(find.text('2 sur 2'), findsOneWidget);
    expect(find.text('Après l’envoi\u202F: 1 photo aujourd’hui (5 par jour).'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('photo.caption')), 'Troisième');
    await tester.tap(find.byKey(const Key('photo.send')));
    await tester.pumpAndSettle();

    expect(deps.messaging.sentClientIds, hasLength(2));
    expect(deps.messaging.sentCaptions, ['Première', 'Troisième']);
    expect(deps.messaging.storedPhotos, hasLength(2));
  });

  testWidgets('appareil photo\u202F: toujours une seule photo', (tester) async {
    final deps = await _openChatWithBob(tester);
    await tester.tap(find.byKey(const Key('composer.photo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('photo.camera')));
    await tester.pumpAndSettle();
    expect(deps.photos.limits, isEmpty);
    expect(find.text('Envoyer une photo'), findsOneWidget);
    expect(find.byKey(const Key('photo.compose.remove')), findsNothing);
  });
}
