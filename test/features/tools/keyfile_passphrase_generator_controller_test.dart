import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/tools/services/keyfile_passphrase_generator_service.dart';
import 'package:vaultexplorer/features/tools/widgets/keyfile_passphrase_generator_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'hashBytesSha256') {
        return '0' * 64;
      }
      return null;
    });

    container = ProviderContainer();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('KeyfilePassphraseGeneratorController Tests', () {
    test('initializes with default passphrase tab and diceware mode', () {
      final state = container.read(keyfilePassphraseGeneratorProvider);

      expect(state.selectedTab, GeneratorTab.passphrase);
      expect(state.passphraseMode, PassphraseMode.diceware);
      expect(state.dicewareWordCount, 5);
      expect(state.dicewareSeparator, '-');
      expect(state.dicewareCasing, PasswordCasing.lowercase);
    });

    test('setSelectedTab switches between passphrase and keyfile modes', () {
      final controller = container.read(keyfilePassphraseGeneratorProvider.notifier);

      controller.setSelectedTab(GeneratorTab.keyfile);
      expect(container.read(keyfilePassphraseGeneratorProvider).selectedTab, GeneratorTab.keyfile);

      controller.setSelectedTab(GeneratorTab.passphrase);
      expect(container.read(keyfilePassphraseGeneratorProvider).selectedTab, GeneratorTab.passphrase);
    });

    test('setKeyfileType and presets update configuration state', () {
      final controller = container.read(keyfilePassphraseGeneratorProvider.notifier);

      controller.setKeyfileType(KeyfileType.image);
      expect(container.read(keyfilePassphraseGeneratorProvider).keyfileType, KeyfileType.image);

      controller.setImagePreset(ImageKeyfileResolution.res512);
      expect(container.read(keyfilePassphraseGeneratorProvider).imagePreset, ImageKeyfileResolution.res512);

      controller.setKeyfileType(KeyfileType.binary);
      controller.setBinaryPreset(KeyfileSizePreset.bytes64kb);
      expect(container.read(keyfilePassphraseGeneratorProvider).binaryPreset, KeyfileSizePreset.bytes64kb);
    });

    test('setCustomLength and character pool mutators update state', () {
      final controller = container.read(keyfilePassphraseGeneratorProvider.notifier);

      controller.setCustomLength(32);
      expect(container.read(keyfilePassphraseGeneratorProvider).customLength, 32);

      controller.setCustomUseUppercase(false);
      expect(container.read(keyfilePassphraseGeneratorProvider).customUseUppercase, isFalse);

      controller.setCustomExcludeAmbiguous(true);
      expect(container.read(keyfilePassphraseGeneratorProvider).customExcludeAmbiguous, isTrue);
    });
  });
}