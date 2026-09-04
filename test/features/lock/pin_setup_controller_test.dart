import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/lock/widgets/pin_setup_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;
  late ProviderSubscription subscription;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'hashPasswordSha256') {
        return Uint8List.fromList(List.filled(32, 2));
      }
      return null;
    });

    container = ProviderContainer();
    subscription = container.listen(pinSetupProvider, (_, _) {});
  });

  tearDown(() {
    subscription.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('PinSetupController Tests', () {
    test('initializes in enter step with no errors', () {
      final state = container.read(pinSetupProvider);

      expect(state.step, PinSetupStep.enter);
      expect(state.error, isNull);
      expect(state.completedHash, isNull);
    });

    test('valid first PIN transitions to confirm step', () async {
      final controller = container.read(pinSetupProvider.notifier);

      await controller.submitPin(
        '1234',
        mismatchMessage: 'PINs do not match',
      );
      final state = container.read(pinSetupProvider);

      expect(state.step, PinSetupStep.confirm);
      expect(state.error, isNull);
    });

    test('matching second PIN computes completedHash', () async {
      final controller = container.read(pinSetupProvider.notifier);

      await controller.submitPin(
        '1234',
        mismatchMessage: 'PINs do not match',
      );
      await controller.submitPin(
        '1234',
        mismatchMessage: 'PINs do not match',
      );

      final state = container.read(pinSetupProvider);
      expect(state.completedHash, isNotNull);
      expect(state.error, isNull);
    });

    test('mismatching second PIN triggers error and resets', () async {
      final controller = container.read(pinSetupProvider.notifier);

      await controller.submitPin(
        '1234',
        mismatchMessage: 'PINs do not match',
      );
      await controller.submitPin(
        '5678',
        mismatchMessage: 'PINs do not match',
      );

      final state = container.read(pinSetupProvider);
      expect(state.completedHash, isNull);
      expect(state.step, PinSetupStep.enter);
    });
  });
}