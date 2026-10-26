import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/biometric_enrollment_guard.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/features/lock/lock_gate_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

class _FakeSettingsService implements AppSettingsService {
  _FakeSettingsService(this.settings);
  AppSettings settings;

  @override
  Future<AppSettings> loadSettings() async => settings;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopSecureScreenPolicy implements SecureScreenPolicy {
  @override
  Future<void> apply({required bool preference}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Answers [checkMaster] with a fixed result and, like the real guard when it
/// reverts, switches the persisted settings to the password.
class _FakeGuard implements BiometricEnrollmentGuard {
  _FakeGuard(this.result, this.settingsService);
  final BiometricGuardResult result;
  final _FakeSettingsService settingsService;
  int checks = 0;

  @override
  Future<BiometricGuardResult> checkMaster() async {
    checks++;
    if (result == BiometricGuardResult.reverted) {
      settingsService.settings = settingsService.settings.copyWith(
        masterUnlockMethod: MasterUnlockMethod.password,
      );
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readSecure':
          return null;
        case 'writeSecure':
          return true;
        case 'deleteSecure':
          return true;
        default:
          return null;
      }
    });

    container = ProviderContainer();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('LockGateController Tests', () {
    test('initializes with default state and checks password validation', () async {
      final subscription = container.listen(lockGateProvider, (_, _) {});
      addTearDown(subscription.close);

      final controller = container.read(lockGateProvider.notifier);
      final initialState = container.read(lockGateProvider);

      expect(initialState.checking, isFalse);
      expect(initialState.error, isNull);

      final l10n = AppLocalizationsEn();
      final wrongPassword = await controller.checkPassword('', l10n);
      expect(wrongPassword, isFalse);
    });

    test('onPatternComplete/onPinComplete no-op before settings load (or '
        'when master password is disabled, since _init never assigns '
        'state.settings on that path) rather than throwing', () async {
      final subscription = container.listen(lockGateProvider, (_, _) {});
      addTearDown(subscription.close);

      final controller = container.read(lockGateProvider.notifier);
      final l10n = AppLocalizationsEn();

      await controller.onPatternComplete([0, 1, 2, 3], l10n);
      expect(container.read(lockGateProvider).error, isNull);

      await controller.onPinComplete('1234', l10n);
      expect(container.read(lockGateProvider).error, isNull);
    });
  });

  group('LockGateController biometric guard', () {
    // The controller starts loading as soon as it is built; with the master
    // password off that ends in a navigate request. Waiting for it keeps the
    // load from overwriting what the test is about to check.
    Future<void> settled(ProviderContainer c) async {
      for (var i = 0; i < 100; i++) {
        if (c.read(lockGateProvider).navigateTick > 0) return;
        await Future<void>.delayed(Duration.zero);
      }
      fail('the gate never finished loading');
    }

    ProviderContainer containerWith(BiometricGuardResult result) {
      final service = _FakeSettingsService(
        AppSettings(masterUnlockMethod: MasterUnlockMethod.biometrics),
      );
      final guard = _FakeGuard(result, service);
      final c = ProviderContainer(
        overrides: [
          appSettingsServiceProvider.overrideWithValue(service),
          secureScreenPolicyProvider.overrideWithValue(_NoopSecureScreenPolicy()),
          biometricEnrollmentGuardProvider.overrideWithValue(guard),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a changed device never reaches the biometric prompt: the gate '
        'falls back to the password and says why', () async {
      final c = containerWith(BiometricGuardResult.reverted);
      final subscription = c.listen(lockGateProvider, (_, _) {});
      addTearDown(subscription.close);
      await settled(c);

      final l10n = AppLocalizationsEn();
      await c.read(lockGateProvider.notifier).tryBiometric(l10n);

      final state = c.read(lockGateProvider);
      expect(state.settings!.masterUnlockMethod, MasterUnlockMethod.password);
      expect(state.biometricsChanged, isTrue);
      expect(state.showPasswordFallback, isTrue);
      expect(state.error, l10n.biometricsChangedFallbackMessage);
    });

    test('when the keystore cannot answer, the attempt is refused and the '
        'password is offered without claiming biometrics changed', () async {
      final c = containerWith(BiometricGuardResult.unavailable);
      final subscription = c.listen(lockGateProvider, (_, _) {});
      addTearDown(subscription.close);
      await settled(c);

      final l10n = AppLocalizationsEn();
      await c.read(lockGateProvider.notifier).tryBiometric(l10n);

      final state = c.read(lockGateProvider);
      expect(state.biometricsChanged, isFalse);
      expect(state.showPasswordFallback, isTrue);
      expect(state.error, l10n.biometricNotAvailable);
    });
  });
}