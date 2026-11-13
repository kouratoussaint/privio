import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/errors/app_failure.dart';
import 'package:privio/data/services/audio/voice_recorder.dart';
import 'package:privio/data/storage/local_cache.dart';
import 'package:privio/domain/models/account.dart';

import '../helpers/fakes.dart';

/// Lot 3.1 — messages vocaux, via l'écran réel de conversation.
Future<TestDeps> _openChatWithBob(WidgetTester tester, {TestDeps? deps}) async {
  final d =
      deps ??
      (TestDeps(
          auth: FakeAuthService(signedIn: true),
          flags: FakeLocalFlags(onboarding: true, permissions: true),
        )
        ..api.account = const Account(
          userId: 'u1',
          phoneE164: '+22670000001',
          phoneDiscoverable: false,
          profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
        ));
  await tester.pumpWidget(
    ProviderScope(overrides: d.overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('discussions.new')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('search.input')), 'bob_ouaga');
  await tester.tap(find.byKey(const Key('search.submit')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('search.write')));
  await tester.pumpAndSettle();
  return d;
}

/// Pendant un enregistrement, l'écran s'anime en continu : on avance le temps pas à pas.
Future<void> _advance(WidgetTester tester, Duration d) async {
  for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 100)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _recordLocked(WidgetTester tester, Duration length) async {
  await tester.tap(find.byKey(const Key('chat.mic')));
  await tester.pump();
  await _advance(tester, length);
  await tester.tap(find.byKey(const Key('voice.stop')));
  await tester.pumpAndSettle();
}

Future<void> _receiveVoice(WidgetTester tester, TestDeps deps) async {
  deps.messaging.receiveVoice('conv-bob');
  deps.realtime.emit('conv-bob');
  await tester.pumpAndSettle();
}

String _snack(WidgetTester tester) => tester
    .widget<Text>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Text)))
    .data!;

void main() {
  testWidgets('champ vide\u202F: micro\u202F; texte saisi\u202F: bouton Envoyer', (tester) async {
    await _openChatWithBob(tester);
    expect(find.byKey(const Key('chat.mic')), findsOneWidget);
    expect(find.byKey(const Key('chat.send')), findsNothing);
    await tester.enterText(find.byKey(const Key('chat.input')), 'Bonjour');
    await tester.pump();
    expect(find.byKey(const Key('chat.send')), findsOneWidget);
    expect(find.byKey(const Key('chat.mic')), findsNothing);
  });

  testWidgets('toucher le micro\u202F: enregistrer, arrêter, préécouter, envoyer', (tester) async {
    final deps = await _openChatWithBob(tester);
    await tester.tap(find.byKey(const Key('chat.mic')));
    await tester.pump();
    expect(find.byKey(const Key('voice.elapsed')), findsOneWidget);
    expect(
      find.byKey(const Key('voice.stop')),
      findsOneWidget,
      reason: 'verrouillé\u202F: bouton Arrêter',
    );
    await _advance(tester, const Duration(seconds: 3));
    expect(find.text('0:03'), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice.stop')));
    await tester.pumpAndSettle();

    // Préécoute obligatoire : rien n'est parti.
    expect(find.byKey(const Key('voice.preview')), findsOneWidget);
    expect(deps.messaging.storedVoices, isEmpty);
    await tester.tap(find.byKey(const Key('voice.preview_play')));
    await tester.pump();
    expect(deps.audio.played.single, deps.recorder.audio, reason: 'on réécoute ce qui a été dit');

    await tester.tap(find.byKey(const Key('voice.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.storedVoices.values.single, deps.recorder.audio);
    final sentId = 'srv-${deps.messaging.sentClientIds.single}';
    expect(find.byKey(Key('voice.play.$sentId')), findsOneWidget, reason: 'bulle vocale affichée');
    expect(find.byKey(const Key('chat.mic')), findsOneWidget, reason: 'retour au champ de saisie');
    // L'expéditeur réécoute son vocal sans le retélécharger.
    expect(deps.vault.files.keys, contains(LocalCache.messageMediaKey(sentId)));
    expect(deps.vault.files.keys.where((k) => k.startsWith('out-')), isEmpty);
  });

  testWidgets('préécoute supprimée\u202F: rien n’est envoyé', (tester) async {
    final deps = await _openChatWithBob(tester);
    await _recordLocked(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('voice.discard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice.preview')), findsNothing);
    expect(deps.messaging.sentClientIds, isEmpty);
  });

  testWidgets('annuler pendant l’enregistrement\u202F: rien n’est conservé', (tester) async {
    final deps = await _openChatWithBob(tester);
    await tester.tap(find.byKey(const Key('chat.mic')));
    await tester.pump();
    await _advance(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('voice.cancel')));
    await tester.pumpAndSettle();
    expect(deps.recorder.cancels, 1);
    expect(find.byKey(const Key('voice.preview')), findsNothing);
    expect(find.byKey(const Key('chat.mic')), findsOneWidget);
  });

  testWidgets('arrêt automatique à la limite de 30 s, puis préécoute', (tester) async {
    final deps = await _openChatWithBob(tester);
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
      c,
    ) async {
      if (c.method == 'HapticFeedback.vibrate') haptics.add(c.arguments);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.tap(find.byKey(const Key('chat.mic')));
    await tester.pump();
    await _advance(tester, const Duration(seconds: 24));
    expect(haptics, isEmpty);
    await _advance(tester, const Duration(seconds: 2));
    expect(find.textContaining('Arrêt dans'), findsOneWidget, reason: 'compte à rebours final');
    // Lot 4.4 : une vibration, une seule, quand il reste 5 s.
    expect(haptics, ['HapticFeedbackType.mediumImpact']);
    await _advance(tester, const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(deps.recorder.recording, isFalse, reason: 'arrêté juste avant 30 s');
    expect(find.byKey(const Key('voice.preview')), findsOneWidget);
    expect(find.text('0:29'), findsOneWidget);
  });

  testWidgets('enregistrement trop court\u202F: message d’aide, rien en préécoute', (tester) async {
    await _openChatWithBob(tester);
    await _recordLocked(tester, const Duration(milliseconds: 500));
    expect(find.byKey(const Key('voice.preview')), findsNothing);
    expect(_snack(tester), const AppFailure(FailureCode.voiceTooShort).message);
  });

  testWidgets('maintenir pour parler, relâcher pour préécouter', (tester) async {
    final deps = await _openChatWithBob(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('chat.mic'))));
    await tester.pump(const Duration(milliseconds: 600)); // appui long reconnu
    expect(deps.recorder.recording, isTrue);
    expect(find.text('Glisser pour annuler'), findsOneWidget);
    await _advance(tester, const Duration(seconds: 2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice.preview')), findsOneWidget);
  });

  testWidgets('maintenir puis glisser vers la gauche\u202F: annulé', (tester) async {
    final deps = await _openChatWithBob(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('chat.mic'))));
    await tester.pump(const Duration(milliseconds: 600));
    await _advance(tester, const Duration(seconds: 2));
    await gesture.moveBy(const Offset(-130, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(deps.recorder.cancels, 1);
    expect(find.byKey(const Key('voice.preview')), findsNothing);
  });

  testWidgets('maintenir puis glisser vers le haut\u202F: verrouillé, mains libres', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('chat.mic'))));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, -100));
    await tester.pump();
    await gesture.up();
    await _advance(tester, const Duration(seconds: 2));
    expect(deps.recorder.recording, isTrue, reason: 'continue sans le doigt');
    expect(find.byKey(const Key('voice.stop')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice.stop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice.preview')), findsOneWidget);
  });

  testWidgets('micro refusé\u202F: explication, l’application reste utilisable', (tester) async {
    final deps = await _openChatWithBob(tester);
    deps.recorder.permission = MicPermission.denied;
    await tester.tap(find.byKey(const Key('chat.mic')));
    await tester.pumpAndSettle();
    expect(_snack(tester), const AppFailure(FailureCode.microphoneDenied).message);
    expect(deps.recorder.starts, 0);
    expect(find.byKey(const Key('chat.input')), findsOneWidget);
  });

  testWidgets('micro refusé définitivement\u202F: proposer les réglages', (tester) async {
    final deps = await _openChatWithBob(tester);
    deps.recorder.permission = MicPermission.permanentlyDenied;
    await tester.tap(find.byKey(const Key('chat.mic')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice.open_settings')), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();
    expect(deps.recorder.starts, 0);
  });

  testWidgets('écouter un vocal reçu\u202F: téléchargé une seule fois, puis lu localement', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    await _receiveVoice(tester, deps);
    final id = deps.messaging.messages['conv-bob']!.last.id;
    expect(find.text('0:12'), findsOneWidget, reason: 'durée mesurée par le serveur');

    await tester.tap(find.byKey(Key('voice.play.$id')));
    await tester.pumpAndSettle();
    expect(deps.messaging.downloads, hasLength(1));
    expect(deps.audio.playing, isTrue);
    expect(deps.vault.files.keys, contains(LocalCache.messageMediaKey(id)));

    // Vitesse : 1× → 1,5×.
    await tester.tap(find.byKey(const Key('voice.speed')));
    await tester.pump();
    expect(deps.audio.speed, 1.5);

    // Pause, fin, puis nouvelle écoute : depuis le coffre, sans réseau.
    await tester.tap(find.byKey(Key('voice.play.$id')));
    await tester.pump();
    expect(deps.audio.playing, isFalse);
    deps.audio.finish();
    await tester.pumpAndSettle();
    deps.messaging.offline = true;
    await tester.tap(find.byKey(Key('voice.play.$id')));
    await tester.pumpAndSettle();
    expect(deps.audio.played, hasLength(2));
    expect(deps.messaging.downloads, hasLength(1));
  });

  testWidgets('hors connexion, son jamais téléchargé\u202F: message clair', (tester) async {
    final deps = await _openChatWithBob(tester);
    await _receiveVoice(tester, deps);
    final id = deps.messaging.messages['conv-bob']!.last.id;
    deps.messaging.offline = true;
    await tester.tap(find.byKey(Key('voice.play.$id')));
    await tester.pumpAndSettle();
    expect(_snack(tester), const AppFailure(FailureCode.network).message);
    expect(deps.audio.played, isEmpty);
  });

  testWidgets('vocal envoyé hors connexion\u202F: il attend, puis part sans doublon', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    deps.messaging.offline = true;
    await _recordLocked(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('voice.send')));
    await tester.pumpAndSettle();
    final clientId = deps.messaging.sentClientIds.single;
    expect(find.byKey(Key('pending.$clientId')), findsOneWidget);
    expect(find.textContaining('Message vocal ·'), findsOneWidget);
    expect(
      deps.vault.files.keys,
      contains(LocalCache.outboxMediaKey(clientId)),
      reason: 'le son attend chiffré sur le téléphone',
    );

    deps.messaging.offline = false;
    deps.realtime.emit('conv-bob', event: 'reconnected');
    await tester.pumpAndSettle();
    expect(deps.messaging.sentClientIds, everyElement(clientId), reason: 'même identifiant');
    expect(deps.messaging.storedVoices, hasLength(1));
    expect(find.byKey(Key('pending.$clientId')), findsNothing);
    expect(find.byKey(Key('voice.play.srv-$clientId')), findsOneWidget);
    expect(deps.vault.files.keys.where((k) => k.startsWith('out-')), isEmpty);
  });

  testWidgets('répondre à un vocal\u202F: citation «\u202FMessage vocal\u202F»', (tester) async {
    final deps = await _openChatWithBob(tester);
    await _receiveVoice(tester, deps);
    final id = deps.messaging.messages['conv-bob']!.last.id;
    await tester.longPress(find.byKey(Key('voice.duration.$id')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('action.edit')), findsNothing);
    await tester.tap(find.byKey(const Key('action.reply')));
    await tester.pumpAndSettle();
    expect(find.text('Message vocal (0:12)'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('chat.input')), 'Bien reçu');
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat.send')));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('bubble.quote')),
        matching: find.text('Message vocal'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('son vocal\u202F: jamais modifiable\u202F; supprimé pour moi, son effacé', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    await _recordLocked(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('voice.send')));
    await tester.pumpAndSettle();
    final id = 'srv-${deps.messaging.sentClientIds.single}';
    await tester.longPress(find.byKey(Key('voice.duration.$id')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('action.edit')),
      findsNothing,
      reason: 'un vocal ne se modifie pas',
    );
    expect(find.byKey(const Key('action.delete_all')), findsOneWidget);
    await tester.tap(find.byKey(const Key('action.delete_me')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('message.$id')), findsNothing);
    expect(deps.vault.files, isEmpty);
  });

  testWidgets('liste des discussions\u202F: «\u202FMessage vocal\u202F» en aperçu', (tester) async {
    final deps = await _openChatWithBob(tester);
    await _receiveVoice(tester, deps);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Message vocal'), findsOneWidget);
  });

  // ------------------------------------------------------------------ lot 4.5
  testWidgets('pause et reprise\u202F: le temps en pause ne compte pas, un seul vocal', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    await tester.tap(find.byKey(const Key('chat.mic')));
    await tester.pump();
    await _advance(tester, const Duration(seconds: 2));
    await tester.tap(find.byKey(const Key('voice.pause')));
    await tester.pump();
    expect(deps.recorder.paused, isTrue);
    expect(find.text('En pause'), findsOneWidget);
    await _advance(tester, const Duration(seconds: 5));
    expect(find.text('0:02'), findsOneWidget, reason: 'la pause ne compte pas');
    await tester.tap(find.byKey(const Key('voice.pause')));
    await tester.pump();
    expect(deps.recorder.paused, isFalse);
    await _advance(tester, const Duration(seconds: 2));
    expect(find.text('0:04'), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice.stop')));
    await tester.pumpAndSettle();
    expect(deps.recorder.pauses, 1);
    expect(deps.recorder.resumes, 1);
    await tester.tap(find.byKey(const Key('voice.send')));
    await tester.pumpAndSettle();
    expect(deps.messaging.storedVoices, hasLength(1), reason: 'un seul message vocal');
  });

  testWidgets('maintenir le micro\u202F: pas de bouton pause', (tester) async {
    await _openChatWithBob(tester);
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(const Key('chat.mic'))));
    await tester.pump(const Duration(seconds: 1));
    await _advance(tester, const Duration(milliseconds: 500));
    expect(find.byKey(const Key('voice.elapsed')), findsOneWidget);
    expect(find.byKey(const Key('voice.pause')), findsNothing);
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('spectre\u202F: en direct, puis envoyé avec le son et affiché dans la bulle', (
    tester,
  ) async {
    final deps = await _openChatWithBob(tester);
    await tester.tap(find.byKey(const Key('chat.mic')));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      deps.recorder.emitLevel(i.isEven ? 0.8 : 0.2);
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('voice.live_waveform')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice.stop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('voice.preview_waveform')), findsOneWidget);
    await tester.tap(find.byKey(const Key('voice.send')));
    await tester.pumpAndSettle();

    final cid = deps.messaging.sentClientIds.single;
    final wave = deps.messaging.sentWaveforms[cid]!;
    expect(wave, hasLength(40));
    expect(wave.reduce((a, b) => a > b ? a : b), 100, reason: 'le passage le plus fort vaut 100');
    expect(wave.every((v) => v >= 0 && v <= 100), isTrue);
    expect(find.byKey(Key('voice.waveform.srv-$cid')), findsOneWidget);
  });

  testWidgets('toucher le spectre pendant l’écoute\u202F: saut à cet endroit', (tester) async {
    final deps = await _openChatWithBob(tester);
    await _receiveVoice(tester, deps);
    final id = deps.messaging.messages['conv-bob']!.last.id;
    await tester.tap(find.byKey(Key('voice.play.$id')));
    await tester.pumpAndSettle();
    final wave = find.byKey(Key('voice.waveform.$id'));
    final box = tester.getRect(wave);
    await tester.tapAt(Offset(box.left + box.width * 0.5, box.center.dy));
    await tester.pump();
    final total = deps.messaging.messages['conv-bob']!.last.durationMs!;
    expect(deps.audio.seekedTo!.inMilliseconds, closeTo(total * 0.5, total * 0.05));
  });
}
