import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:privio/app.dart';

import 'parcours.dart';

/// Lot 6.1 (ADR-055) : mesures de vitesse sur un émulateur d'entrée de gamme (mode
/// « profile », comme une version publiée). Compte de mesure préparé par
/// scripts/emulateur/preparer_mesure.py : 300 discussions, dont une de 1 000 messages.
///
/// Seuils (au-delà, la CI échoue) :
const seuilDemarrageMs = 3000; // lancement → premier écran affiché
const seuilOuvertureMs = 2000; // toucher la discussion → messages affichés
const seuilImageP90Ms = 20; // 90 % des images construites en moins de 20 ms (défilement)

Future<FrameTimingSummarizer> _images(WidgetTester tester, Future<void> Function() action) async {
  final timings = <FrameTiming>[];
  await Future<void>.delayed(const Duration(seconds: 2));
  SchedulerBinding.instance.addTimingsCallback(timings.addAll);
  await action();
  for (var i = 0; i < 10 && timings.isEmpty; i++) {
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  await Future<void>.delayed(const Duration(seconds: 2));
  SchedulerBinding.instance.removeTimingsCallback(timings.addAll);
  return FrameTimingSummarizer(timings);
}

Map<String, Object> _resume(FrameTimingSummarizer s) => {
  'images': s.frameBuildTime.length,
  'construction_moyenne_ms': s.averageFrameBuildTime.inMicroseconds / 1000,
  'construction_p90_ms': s.p90FrameBuildTime.inMicroseconds / 1000,
  'construction_pire_ms': s.worstFrameBuildTime.inMicroseconds / 1000,
  'images_hors_budget': s.missedFrameBuildBudget,
  'rendu_p90_ms': s.p90FrameRasterizerTime.inMicroseconds / 1000,
};

/// Joue les mesures et renvoie les résultats (les seuils : [verifierSeuils]).
Future<Map<String, Object>> mesurerVitesse(
  WidgetTester tester, {
  required List<Override> overrides,
  required Future<int> Function() depuisLancement,
}) async {
  final mesures = <String, Object>{};
  await tester.pumpWidget(
    ProviderScope(overrides: overrides, retry: (_, _) => null, child: const PrivioApp()),
  );
  // ── Démarrage à froid : du lancement du processus au premier écran ──────────────
  final attente = Stopwatch()..start();
  while (find.byKey(const Key('onboarding.continue')).evaluate().isEmpty) {
    await tester.pump(const Duration(milliseconds: 16));
    if (attente.elapsed > const Duration(seconds: 60)) {
      fail('Premier écran non affiché en 60 s\nÉcran\u202F: ${ecran()}');
    }
  }
  await tester.pump();
  final demarrage = await depuisLancement();
  mesures['demarrage_ms'] = demarrage;
  etape('démarrage\u202F: $demarrage ms');

  // ── Connexion du compte de mesure ───────────────────────────────────────────────
  await toucher(tester, cle('onboarding.consent'));
  await toucher(tester, cle('onboarding.continue'));
  await toucher(tester, cle('welcome.phone'));
  await attendre(tester, cle('phone.input'));
  await tester.enterText(cle('phone.input'), '70000003');
  await toucher(tester, cle('phone.submit'));
  // Un code a pu être demandé pour ce numéro il y a moins d'une minute (préparation du
  // compte de mesure) : on redemande alors une fois.
  try {
    await attendre(tester, cle('otp.input'), max: const Duration(seconds: 20));
  } on TestFailure {
    await tester.pump(const Duration(seconds: 45));
    await toucher(tester, cle('phone.submit'));
    await attendre(tester, cle('otp.input'));
  }
  final liste = Stopwatch()..start();
  await tester.enterText(cle('otp.input'), '123456');
  // Autorisations facultatives (si l'écran est proposé), puis la liste.
  await attendre(
    tester,
    find.byWidgetPredicate(
      (w) =>
          w.key == const Key('permissions.later') || (w is Text && w.data == 'Discussion longue'),
    ),
    max: const Duration(seconds: 60),
  );
  if (cle('permissions.later').evaluate().isNotEmpty) {
    // Le temps passé sur l'écran des autorisations ne compte pas.
    await tester.tap(cle('permissions.later'));
    liste.reset();
  }
  while (find.text('Discussion longue').evaluate().isEmpty) {
    await tester.pump(const Duration(milliseconds: 16));
    if (liste.elapsed > const Duration(seconds: 60)) {
      fail('Liste des discussions non affichée en 60 s\nÉcran\u202F: ${ecran()}');
    }
  }
  mesures['liste_300_ms'] = liste.elapsedMilliseconds;
  etape('liste de 300 discussions affichée\u202F: ${liste.elapsedMilliseconds} ms');

  // ── Défilement des 300 discussions ──────────────────────────────────────────────
  final defile = await _images(tester, () async {
    final vue = find.byType(Scrollable).first;
    for (var i = 0; i < 12; i++) {
      await tester.fling(vue, const Offset(0, -700), 2500);
      await poser(tester, const Duration(seconds: 2));
    }
    for (var i = 0; i < 12; i++) {
      await tester.fling(vue, const Offset(0, 700), 2500);
      await poser(tester, const Duration(seconds: 2));
    }
  });
  mesures['defilement_300'] = _resume(defile);
  etape('défilement\u202F: ${_resume(defile)}');
  await attendre(tester, find.text('Discussion longue'));

  // ── Ouverture de la discussion de 1 000 messages ────────────────────────────────
  final ouverture = Stopwatch()..start();
  await tester.tap(find.text('Discussion longue'));
  // Ouverte sur le premier message non lu ou sur le dernier : des messages sont affichés.
  while (find.textContaining(RegExp(r'^Message \d+')).evaluate().isEmpty ||
      find.byKey(const Key('chat.input')).evaluate().isEmpty) {
    await tester.pump(const Duration(milliseconds: 16));
    if (ouverture.elapsed > const Duration(seconds: 30)) {
      fail('Discussion de 1 000 messages non affichée en 30 s\nÉcran\u202F: ${ecran()}');
    }
  }
  mesures['ouverture_1000_ms'] = ouverture.elapsedMilliseconds;
  etape('ouverture\u202F: ${ouverture.elapsedMilliseconds} ms');

  final historique = await _images(tester, () async {
    final vue = find.byType(Scrollable).first;
    for (var i = 0; i < 15; i++) {
      await tester.fling(vue, const Offset(0, 700), 2500);
      await poser(tester, const Duration(seconds: 2));
    }
  });
  mesures['defilement_1000'] = _resume(historique);
  etape('historique\u202F: ${_resume(historique)}');

  return mesures;
}

/// Échoue si une mesure dépasse son seuil (après publication des mesures).
void verifierSeuils(Map<String, Object> m) {
  num p90(String cle) => ((m[cle] as Map?)?['construction_p90_ms'] as num?) ?? 9999;
  expect(m['demarrage_ms'] as int, lessThan(seuilDemarrageMs), reason: 'démarrage à froid');
  expect(m['ouverture_1000_ms'] as int, lessThan(seuilOuvertureMs), reason: 'ouverture');
  expect(p90('defilement_300'), lessThan(seuilImageP90Ms), reason: 'défilement, 300 discussions');
  expect(p90('defilement_1000'), lessThan(seuilImageP90Ms), reason: 'défilement, 1 000 messages');
}
