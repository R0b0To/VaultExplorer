import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/lock/lock_gate_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

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
  });
}