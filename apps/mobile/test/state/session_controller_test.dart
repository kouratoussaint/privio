import 'package:flutter_test/flutter_test.dart';
import 'package:privio/core/errors/app_failure.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/state/session_controller.dart';

import '../helpers/fakes.dart';

void main() {
  test('premier lancement → onboarding', () async {
    final deps = TestDeps();
    final c = deps.container();
    addTearDown(c.dispose);
    expect((await c.read(sessionControllerProvider.future)).stage, SessionStage.onboarding);
  });

  test('connecté sans profil → création de profil', () async {
    final deps = TestDeps(
      auth: FakeAuthService(signedIn: true),
      flags: FakeLocalFlags(onboarding: true),
    );
    final c = deps.container();
    addTearDown(c.dispose);
    expect((await c.read(sessionControllerProvider.future)).stage, SessionStage.needsProfile);
  });

  test('OTP validé → appareil enregistré (révocation des autres)', () async {
    final deps = TestDeps(flags: FakeLocalFlags(onboarding: true));
    final c = deps.container();
    addTearDown(c.dispose);
    await c.read(sessionControllerProvider.future);
    await deps.auth.verifyOtp(phoneE164: '+22670000001', code: '123456');
    await c.read(sessionControllerProvider.notifier).onOtpVerified();
    expect(deps.api.registeredDevices, 1);
    expect(c.read(sessionControllerProvider).value!.stage, SessionStage.needsProfile);
  });

  test('session révoquée par un autre appareil → déconnexion locale + message', () async {
    final deps = TestDeps(
      auth: FakeAuthService(signedIn: true),
      flags: FakeLocalFlags(onboarding: true, permissions: true),
    )..api.accountFailure = const AppFailure(FailureCode.authRequired);
    final c = deps.container();
    addTearDown(c.dispose);
    final state = await c.read(sessionControllerProvider.future);
    expect(state.stage, SessionStage.signedOut);
    expect(state.notice, kOtherDeviceNotice);
    expect(deps.auth.signedIn, isFalse);
  });

  test('déconnexion volontaire → appareil désenregistré, retour à l’accueil', () async {
    final deps =
        TestDeps(
            auth: FakeAuthService(signedIn: true),
            flags: FakeLocalFlags(onboarding: true, permissions: true),
          )
          ..api.account = const Account(
            userId: 'u1',
            phoneE164: '+22670000001',
            phoneDiscoverable: false,
            profile: Profile(handle: 'alice_bf', displayName: 'Alice'),
          );
    final c = deps.container();
    addTearDown(c.dispose);
    expect((await c.read(sessionControllerProvider.future)).stage, SessionStage.ready);
    await c.read(sessionControllerProvider.notifier).signOut();
    expect(deps.api.unregisteredDevices, 1);
    expect(c.read(sessionControllerProvider).value!.stage, SessionStage.signedOut);
    expect(deps.flags.permissions, isFalse);
  });
}
