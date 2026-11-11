import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:privio/core/errors/app_failure.dart';
import 'package:privio/core/theme/privio_theme.dart';
import 'package:privio/data/services/account_api.dart';
import 'package:privio/data/services/auth_service.dart';
import 'package:privio/data/services/permission_gateway.dart';
import 'package:privio/data/storage/local_flags.dart';
import 'package:privio/domain/models/account.dart';
import 'package:privio/state/providers.dart';
import 'package:privio/state/session_controller.dart';

class FakeAuthService implements AuthService {
  FakeAuthService({this.signedIn = false});

  bool signedIn;
  final _changes = StreamController<void>.broadcast();
  final List<String> otpRequests = [];
  AppFailure? requestFailure;
  String validCode = '123456';

  @override
  bool get hasSession => signedIn;

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> requestOtp(String phoneE164) async {
    if (requestFailure != null) throw requestFailure!;
    otpRequests.add(phoneE164);
  }

  @override
  Future<void> verifyOtp({required String phoneE164, required String code}) async {
    if (code != validCode) throw const AppFailure(FailureCode.otpInvalidOrExpired);
    signedIn = true;
    _changes.add(null);
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    _changes.add(null);
  }
}

class FakeAccountApi implements AccountApi {
  Account? account;
  AppFailure? accountFailure;
  final Set<String> takenHandles = {'alice_bf'};
  int registeredDevices = 0;
  int unregisteredDevices = 0;

  @override
  Future<Account> getMyAccount() async {
    if (accountFailure != null) throw accountFailure!;
    return account ??
        const Account(userId: 'u1', phoneE164: '+22670000001', phoneDiscoverable: false);
  }

  @override
  Future<Profile> createProfile({required String handle, required String displayName}) async {
    if (takenHandles.contains(handle)) throw const AppFailure(FailureCode.handleTaken);
    final profile = Profile(handle: handle, displayName: displayName);
    account = Account(
      userId: 'u1',
      phoneE164: '+22670000001',
      phoneDiscoverable: false,
      profile: profile,
    );
    return profile;
  }

  @override
  Future<bool> isHandleAvailable(String handle) async => !takenHandles.contains(handle);

  @override
  Future<bool> setPhoneDiscoverable(bool value) async => value;

  @override
  Future<String> registerDevice({required String appVersion}) async {
    registeredDevices++;
    return 'device-1';
  }

  @override
  Future<void> unregisterCurrentDevice() async => unregisteredDevices++;
}

class FakeLocalFlags implements LocalFlags {
  FakeLocalFlags({this.onboarding = false, this.permissions = false});

  bool onboarding;
  bool permissions;

  @override
  Future<bool> onboardingDone() async => onboarding;
  @override
  Future<void> setOnboardingDone() async => onboarding = true;
  @override
  Future<bool> permissionsSeen() async => permissions;
  @override
  Future<void> setPermissionsSeen() async => permissions = true;
  @override
  Future<void> clearAccountScoped() async => permissions = false;
}

class FakePermissionGateway implements PermissionGateway {
  int requests = 0;
  @override
  Future<bool> requestNotifications() async {
    requests++;
    return true;
  }
}

class TestDeps {
  TestDeps({FakeAuthService? auth, FakeAccountApi? api, FakeLocalFlags? flags})
    : auth = auth ?? FakeAuthService(),
      api = api ?? FakeAccountApi(),
      flags = flags ?? FakeLocalFlags();

  final FakeAuthService auth;
  final FakeAccountApi api;
  final FakeLocalFlags flags;
  final permissions = FakePermissionGateway();

  List<Override> get overrides => [
    authServiceProvider.overrideWithValue(auth),
    accountApiProvider.overrideWithValue(api),
    localFlagsProvider.overrideWithValue(flags),
    permissionGatewayProvider.overrideWithValue(permissions),
    appVersionProvider.overrideWithValue('0.1.0-test'),
  ];

  /// Conteneur dont le contrôleur de session reste écouté, comme dans l'application.
  ProviderContainer container() {
    final c = ProviderContainer(overrides: overrides, retry: (_, _) => null);
    c.listen(sessionControllerProvider, (_, _) {});
    return c;
  }

  /// Monte un écran isolé dans un MaterialApp thémé.
  Widget wrap(Widget child) => ProviderScope(
    overrides: overrides,
    retry: (_, _) => null,
    child: MaterialApp(theme: PrivioTheme.light, home: child),
  );
}
