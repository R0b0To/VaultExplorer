import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/settings/logcat_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;
  late ProviderSubscription subscription;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'clearLog') return true;
      return null;
    });

    container = ProviderContainer();
    subscription = container.listen(logcatControllerProvider, (_, _) {});
  });

  tearDown(() {
    subscription.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('LogcatController Tests', () {
    test('initializes with default query and appOnly filter mode', () {
      final state = container.read(logcatControllerProvider);

      expect(state.searchQuery, isEmpty);
      expect(state.filterMode, LogFilterMode.appOnly);
      expect(state.streamError, isFalse);
      expect(state.saving, isFalse);
      expect(state.clearing, isFalse);
    });

    test('setSearchQuery and setFilterMode update filtering options', () {
      final controller = container.read(logcatControllerProvider.notifier);

      controller.setSearchQuery('VeraCrypt');
      expect(container.read(logcatControllerProvider).searchQuery, 'VeraCrypt');

      controller.setFilterMode(LogFilterMode.all);
      expect(container.read(logcatControllerProvider).filterMode, LogFilterMode.all);

      controller.setSearchQuery('');
      expect(container.read(logcatControllerProvider).searchQuery, isEmpty);
    });

    test('isLineAccepted extension filters noise and matches app keywords', () {
      const state = LogcatState(
        filterMode: LogFilterMode.appOnly,
        searchQuery: 'VeraCrypt',
      );

      expect(state.isLineAccepted('D/VeraCrypt: Volume header decrypted'), isTrue);
      expect(state.isLineAccepted('D/OpenGLRenderer: Frame rendered'), isFalse);
      expect(state.isLineAccepted('D/Cryptomator: Unlocked'), isFalse);
    });
  });
}