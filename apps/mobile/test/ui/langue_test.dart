import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/l10n/l10n.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 8.2a — langues : textes sortis du code, choix de la langue, repli en français.
TestDeps _deps({bool signedIn = true, bool onboarding = true}) =>
    TestDeps(
        auth: FakeAuthService(signedIn: signedIn),
        flags: FakeLocalFlags(onboarding: onboarding, permissions: true),
      )
      ..api.account = const Account(
        userId: 'u1',
        phoneE164: '+22670000001',
        phoneDiscoverable: false,
        profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
      );

Future<void> _start(WidgetTester tester, TestDeps deps, {List<Override> extra = const []}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...deps.overrides, ...extra],
      retry: (_, _) => null,
      child: const PrivioApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openLanguage(WidgetTester tester) async {
  await tester.tap(
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text('Paramètres')),
  );
  await tester.pumpAndSettle();
  final tile = find.byKey(const Key('settings.language'));
  await tester.scrollUntilVisible(tile, 200, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

final _released = releasedLanguagesProvider.overrideWithValue(const ['fr', 'mos', 'dyu']);

void main() {
  tearDown(() => L.use(const Locale('fr')));

  testWidgets('Paramètres → Langue : français ; mooré et dioula « Traduction en cours »', (
    tester,
  ) async {
    final deps = _deps();
    await _start(tester, deps);
    await _openLanguage(tester);
    expect(find.byKey(const Key('language.screen')), findsOneWidget);
    final mos = tester.widget<RadioListTile<String>>(find.byKey(const Key('language.mos')));
    final dyu = tester.widget<RadioListTile<String>>(find.byKey(const Key('language.dyu')));
    expect(mos.enabled, isFalse);
    expect(dyu.enabled, isFalse);
    expect(find.text('Traduction en cours'), findsNWidgets(2));
    await tester.tap(find.byKey(const Key('language.mos')));
    await tester.pumpAndSettle();
    expect(deps.flags.lang, 'fr', reason: 'langue pas encore proposée');
  });

  testWidgets('écran de bienvenue : pas de choix tant qu’il n’y a que le français', (tester) async {
    await _start(tester, _deps(signedIn: false, onboarding: false));
    expect(find.byKey(const Key('onboarding.continue')), findsOneWidget);
    expect(find.byKey(const Key('language.chip')), findsNothing);
  });

  testWidgets('langue publiée : choix dès le premier écran, gardé sur le téléphone', (
    tester,
  ) async {
    final deps = _deps(signedIn: false, onboarding: false);
    await _start(tester, deps, extra: [_released]);
    await tester.tap(find.byKey(const Key('language.chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language.sheet.dyu')));
    await tester.pumpAndSettle();
    expect(deps.flags.lang, 'dyu');
    expect(L.t.localeName, 'dyu');
    // Textes non traduits : en français ; boutons standard d'Android : en français.
    expect(find.byKey(const Key('onboarding.continue')), findsOneWidget);
    final ctx = tester.element(find.byKey(const Key('onboarding.continue')));
    expect(MaterialLocalizations.of(ctx).cancelButtonLabel, 'Annuler');
    expect(find.text('Langue : Dioula'), findsOneWidget);
  });

  testWidgets('mooré choisi : l’application fonctionne (repli en français)', (tester) async {
    final deps = _deps()..flags.lang = 'mos';
    await deps.messaging.startDirectConversation('u2');
    deps.messaging.receive('conv-bob', 'Salut');
    await _start(tester, deps, extra: [_released]);
    expect(L.t.localeName, 'mos');
    await tester.tap(find.byKey(const Key('conversation.conv-bob')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('chat.menu')));
    await tester.pumpAndSettle();
    expect(find.text('Voir la fiche'), findsOneWidget);
  });

  test('pluriels et paramètres, dans chaque langue', () {
    for (final code in kLanguages.keys) {
      L.use(Locale(code));
      expect(L.t.selectedCount(1), '1 sélectionné', reason: code);
      expect(L.t.selectedCount(3), '3 sélectionnés', reason: code);
      // Règle française : 0 et 1 au singulier (les autres langues ont leurs propres règles).
      if (code == 'fr') expect(L.t.membersCount(0), '0 membre');
      expect(L.t.evtTitleOther('Awa', 'Famille'), 'Awa a renommé le groupe « Famille »');
    }
  });

  test('fichiers de traduction : mêmes clés et mêmes paramètres que le français', () {
    final dir = Directory('lib/l10n');
    final fr =
        jsonDecode(File('${dir.path}/app_fr.arb').readAsStringSync()) as Map<String, dynamic>;
    final holders = RegExp(r'\{([A-Za-z]+)[,}]');
    for (final code in ['mos', 'dyu']) {
      final arb =
          jsonDecode(File('${dir.path}/app_$code.arb').readAsStringSync()) as Map<String, dynamic>;
      expect(arb['@@locale'], code);
      for (final e in arb.entries) {
        if (e.key.startsWith('@')) continue;
        expect(fr.containsKey(e.key), isTrue, reason: '$code : clé inconnue ${e.key}');
        final want = holders.allMatches(fr[e.key] as String).map((m) => m[1]).toSet();
        final got = holders.allMatches(e.value as String).map((m) => m[1]).toSet();
        expect(got, want, reason: '$code : paramètres de ${e.key}');
      }
    }
  });

  test('aucun texte français écrit en dur dans les écrans (hors console)', () {
    final literal = RegExp(r'''\bText\(\s*'[^'$]*[a-zàâçéèêëîïôûùü]{3,}''');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final p = f.path.replaceAll(r'\', '/');
      if (!p.endsWith('.dart') || p.contains('/console/') || p.contains('/l10n/gen/')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (literal.hasMatch(lines[i])) offenders.add('$p:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}
