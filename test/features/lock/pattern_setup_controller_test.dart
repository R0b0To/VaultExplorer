import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/lock/widgets/pattern_setup_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;
  late ProviderSubscription subscription;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'hashPasswordSha256') {
        return Uint8List.fromList(List.filled(32, 1));
      }
      return null;
    });

    container = ProviderContainer();
    subscription = container.listen(patternSetupProvider, (_, __) {});
  });

  tearDown(() {
    subscription.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('PatternSetupController Tests', () {
    test('initializes in draw step with no errors', () {
      final state = container.read(patternSetupProvider);

      expect(state.step, PatternSetupStep.draw);
      expect(state.error, isNull);
      expect(state.completedHash, isNull);
    });

    test('entering short pattern (<4 nodes) sets validation error and resets', () async {
      final controller = container.read(patternSetupProvider.notifier);

      await controller.submitPattern(
        [0, 1, 2],
        tooShortMessage: 'Pattern too short',
        mismatchMessage: 'Mismatch',
      );
      final state = container.read(patternSetupProvider);

      expect(state.step, PatternSetupStep.draw);
      expect(state.resetKey, 1);
      expect(state.completedHash, isNull);
    });

    test('valid first pattern transitions to confirm step', () async {
      final controller = container.read(patternSetupProvider.notifier);

      await controller.submitPattern(
        [0, 1, 2, 3],
        tooShortMessage: 'Pattern too short',
        mismatchMessage: 'Mismatch',
      );
      final state = container.read(patternSetupProvider);

      expect(state.step, PatternSetupStep.confirm);
      expect(state.error, isNull);
      expect(state.showError, isFalse);
    });

    test('matching second pattern computes completedHash', () async {
      final controller = container.read(patternSetupProvider.notifier);

      await controller.submitPattern(
        [0, 1, 2, 3],
        tooShortMessage: 'Pattern too short',
        mismatchMessage: 'Mismatch',
      );
      await controller.submitPattern(
        [0, 1, 2, 3],
        tooShortMessage: 'Pattern too short',
        mismatchMessage: 'Mismatch',
      );

      final state = container.read(patternSetupProvider);
      expect(state.completedHash, isNotNull);
      expect(state.error, isNull);
    });

    test('mismatching second pattern triggers error and resets', () async {
      final controller = container.read(patternSetupProvider.notifier);

      await controller.submitPattern(
        [0, 1, 2, 3],
        tooShortMessage: 'Pattern too short',
        mismatchMessage: 'Mismatch',
      );
      await controller.submitPattern(
        [0, 1, 2, 4],
        tooShortMessage: 'Pattern too short',
        mismatchMessage: 'Mismatch',
      );

      final state = container.read(patternSetupProvider);
      expect(state.completedHash, isNull);
      expect(state.step, PatternSetupStep.draw);
    });
  });
}