import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:privio/app.dart';
import 'package:privio/core/errors/app_failure.dart';
import 'package:privio/data/services/share_service.dart';
import 'package:privio/data/storage/app_lock_store.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/ui/features/home/home_shell.dart';

import '../helpers/fakes.dart';

/// Lot 8.1c — changer de numéro, inviter un ami.
const _pin = '258014';

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

Finder _tab(String label) =>
    find.descendant(of: find.byType(PrivioNavBar), matching: find.text(label));

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.byKey(Key('pin.$d')));
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Future<void> _openChangePhone(WidgetTester tester) async {
  await tester.tap(_tab('Paramètres'));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('settings.profile')));
  await tester.pumpAndSettle();
  final phone = find.byKey(const Key('my.phone'));
  await tester.scrollUntilVisible(phone, 200, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(phone);
  await tester.pumpAndSettle();
  await tester.tap(phone);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('phone_change.screen')), findsOneWidget);
}

Future<void> _ask(WidgetTester tester, String number) async {
  await tester.enterText(find.byKey(const Key('phone_change.input')), number);
  await tester.tap(find.byKey(const Key('phone_change.send')));
  await tester.pumpAndSettle();
}

void main() {
  group('changer de numéro', () {
    testWidgets('code envoyé au nouveau numéro, mauvais code, puis bon code', (tester) async {
      final deps = _deps();
      await _start(tester, deps);
      await _openChangePhone(tester);
      expect(find.textContaining('+226 70 00 00 01'), findsOneWidget);
      await _ask(tester, '70 00 00 05');
      expect(deps.auth.phoneChangeRequests, ['+22670000005']);
      expect(find.textContaining('+226 70 00 00 05'), findsOneWidget);
      expect(deps.auth.changedPhone, isNull, reason: 'rien ne change avant le code');

      await tester.enterText(find.byKey(const Key('phone_change.code')), '000000');
      await tester.pumpAndSettle();
      expect(find.text(const AppFailure(FailureCode.otpInvalidOrExpired).message), findsOneWidget);
      expect(deps.auth.changedPhone, isNull);

      deps.api.account = const Account(
        userId: 'u1',
        phoneE164: '+22670000005',
        phoneDiscoverable: false,
        profile: Profile(handle: 'toussaint_bf', displayName: 'Toussaint'),
      );
      await tester.enterText(find.byKey(const Key('phone_change.code')), '123456');
      await tester.pumpAndSettle();
      expect(deps.auth.changedPhone, '+22670000005');
      expect(find.byKey(const Key('phone_change.screen')), findsNothing);
      expect(find.text('Numéro changé.'), findsOneWidget);
      expect(find.text('+226 70 00 00 05'), findsWidgets, reason: 'Ma fiche à jour');
    });

    testWidgets('numéro déjà pris, ou le même : refusés', (tester) async {
      final deps = _deps();
      await _start(tester, deps);
      await _openChangePhone(tester);
      await _ask(tester, '70 00 00 02');
      expect(find.text(const AppFailure(FailureCode.phoneTaken).message), findsOneWidget);
      await _ask(tester, '70 00 00 01');
      expect(find.text('C’est déjà votre numéro.'), findsOneWidget);
      await _ask(tester, '12');
      expect(find.text(const AppFailure(FailureCode.phoneInvalid).message), findsOneWidget);
      expect(deps.auth.phoneChangeRequests, isEmpty);
    });

    testWidgets('verrouillage activé : code Privio demandé d’abord', (tester) async {
      final deps = _deps();
      final salt = List<int>.generate(16, (i) => i);
      deps.lockStore.config = AppLockConfig(
        enabled: true,
        delaySeconds: 60,
        salt: base64Encode(salt),
        hash: await const FastPinHasher().hash(_pin, salt, 1),
      );
      await _start(tester, deps);
      await _type(tester, _pin); // déverrouiller l'application
      await _openChangePhone(tester);
      await _ask(tester, '70 00 00 05');
      expect(deps.auth.phoneChangeRequests, isEmpty, reason: 'pas encore');
      await _type(tester, '000000');
      expect(find.text('Code incorrect.'), findsOneWidget);
      await _type(tester, _pin);
      expect(deps.auth.phoneChangeRequests, ['+22670000005']);
      expect(find.byKey(const Key('phone_change.code')), findsOneWidget);
    });
  });

  group('inviter un ami', () {
    testWidgets('Paramètres → Inviter un ami : mon identifiant, sans promesse', (tester) async {
      final deps = _deps();
      final shared = <String>[];
      await _start(
        tester,
        deps,
        extra: [shareTextProvider.overrideWithValue((t) async => shared.add(t))],
      );
      await tester.tap(_tab('Paramètres'));
      await tester.pumpAndSettle();
      final invite = find.byKey(const Key('settings.invite'));
      await tester.scrollUntilVisible(invite, 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(invite);
      await tester.pumpAndSettle();
      await tester.tap(invite);
      await tester.pumpAndSettle();
      expect(shared.single, contains('@toussaint_bf'));
      expect(shared.single.toLowerCase(), isNot(contains('chiffr')));
    });

    testWidgets('personne introuvable : l’inviter', (tester) async {
      final deps = _deps();
      final shared = <String>[];
      await _start(
        tester,
        deps,
        extra: [shareTextProvider.overrideWithValue((t) async => shared.add(t))],
      );
      await tester.tap(find.byKey(const Key('discussions.new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('search.input')), 'inconnu_bf');
      await tester.tap(find.byKey(const Key('search.submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('search.invite')));
      await tester.pumpAndSettle();
      expect(shared.single, contains('@toussaint_bf'));
    });
  });
}
