import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/domain/models/console_team.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../test/helpers/fakes.dart';

/// Captures d'écran de la console (revue du design, hors CI) :
///   flutter test test_parcours/captures_console_test.dart --update-goldens
/// Les images vont dans test_parcours/captures/.
const _pin = '258014';

Future<void> _fonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  await load('Inter', [
    'assets/fonts/Inter-Regular.ttf',
    'assets/fonts/Inter-Medium.ttf',
    'assets/fonts/Inter-SemiBold.ttf',
    'assets/fonts/Inter-Bold.ttf',
  ]);
  final sdk = Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/flutter';
  await load('MaterialIcons', ['$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
  await load('Roboto', ['$sdk/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf']);
}

/// Capture pleine hauteur (contenu entier visible), puis retour à la taille d'un téléphone.
Future<void> _shot(WidgetTester tester, String name, {double height = 5600}) async {
  tester.view.physicalSize = Size(1080, height);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('captures/$name.png'));
  tester.view.physicalSize = const Size(1080, 2340);
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _section(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(const Key('console.menu')));
  await _settle(tester);
  final item = find.byKey(Key('console.tab.$id'));
  for (var k = 0; k < 10 && item.evaluate().isEmpty; k++) {
    await tester.drag(find.byKey(const Key('console.drawer')), const Offset(0, -300));
    await _settle(tester);
  }
  await tester.ensureVisible(item);
  await _settle(tester);
  await tester.tap(item);
  await _settle(tester);
}

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin.$d')));
    await tester.pump();
  }
  await _settle(tester);
}

void main() {
  testWidgets('captures de la console', (tester) async {
    await _fonts();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final deps = TestDeps(
        auth: FakeAuthService(signedIn: true),
        flags: FakeLocalFlags(onboarding: true, permissions: true),
      )
      ..admin.admin = true
      ..admin.role = ConsoleRole.owner
      ..admin.staffTwoStep = true
      ..api.account = const Account(
        userId: 'u1',
        phoneE164: '+22670000001',
        phoneDiscoverable: false,
        profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
      );
    final salt = List<int>.generate(16, (i) => i);
    deps.lockStore.config = AppLockConfig(
      enabled: true,
      delaySeconds: 3600,
      salt: base64Encode(salt),
      hash: await const FastPinHasher().hash(_pin, salt, 1),
    );
    await tester.pumpWidget(
      ProviderScope(overrides: deps.overrides, retry: (_, _) => null, child: const PrivioApp()),
    );
    await _settle(tester);
    await _type(tester, _pin);
    await tester.tap(find.descendant(of: find.byType(PrivioNavBar), matching: find.text('Paramètres')));
    await _settle(tester);
    for (var k = 0; k < 30 && find.byKey(const Key('settings.console')).evaluate().isEmpty; k++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
      await _settle(tester);
    }
    await tester.ensureVisible(find.byKey(const Key('settings.console')));
    await _settle(tester);
    await tester.tap(find.byKey(const Key('settings.console')));
    await _settle(tester);
    await _type(tester, _pin);
    await _shot(tester, '00_accueil');
    await tester.tap(find.byKey(const Key('console.menu')));
    await _settle(tester);
    await _shot(tester, '01_menu', height: 2340);
    await tester.tapAt(const Offset(400, 300));
    await _settle(tester);
    var i = 2;
    for (final id in const [
      'reports', 'accounts', 'groups', 'moderation', 'templates', 'sites', 'features',
      'policies', 'stats', 'health', 'journal', 'team', 'signups', 'pilot',
    ]) {
      await _section(tester, id);
      await _shot(tester, '${(i++).toString().padLeft(2, '0')}_$id');
    }
  });
}
