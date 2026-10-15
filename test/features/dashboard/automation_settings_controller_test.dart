import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_automation_api.dart';
import 'package:vaultexplorer/features/dashboard/widgets/automation_settings_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engineChannel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  const cameraChannel = MethodChannel('com.aeidolon.vaultexplorer/camera');
  late ProviderContainer container;
  final cameraCalls = <String>[];

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, (call) async {
      switch (call.method) {
        case 'getAutomationVaultConfig':
          return {
            'tier': 'NONE',
            'format': 'veracrypt',
            'hasStoredPassword': false,
            'hasStoredKeyfiles': false,
            'captureEnabled': false,
          };
        case 'setAutomationTier':
          return true;
        case 'setAutomationCaptureEnabled':
          return true;
        default:
          return null;
      }
    });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, (call) async {
      cameraCalls.add(call.method);
      switch (call.method) {
        case 'hasPermissions':
          // Camera/microphone NOT granted: the opt-in must still persist.
          return false;
        default:
          return null;
      }
    });

    cameraCalls.clear();
    container = ProviderContainer();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(engineChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(cameraChannel, null);
    container.dispose();
  });

  group('AutomationSettingsController Tests', () {
    const uri = 'file:///vault.hc';
    const format = 'veracrypt';
    final provider = automationSettingsProvider(uri, format);

    test('initializes with default tier and capture flag', () {
      final state = container.read(provider);

      expect(state.tier, AutomationTier.none);
      expect(state.captureEnabled, isFalse);
    });

    test('setTier and setCaptureEnabled update configuration state', () async {
      final controller = container.read(provider.notifier);
      final l10n = AppLocalizationsEn();

      await controller.setTier(AutomationTier.full);
      expect(container.read(provider).tier, AutomationTier.full);

      await controller.setCaptureEnabled(true, l10n);
      expect(container.read(provider).captureEnabled, isTrue);

      await controller.setTier(AutomationTier.none);
      expect(container.read(provider).tier, AutomationTier.none);
    });

    test(
      'setCaptureEnabled is a pure opt-in and never checks or requests '
      'camera/microphone permissions',
      () async {
        final controller = container.read(provider.notifier);

        await controller.setCaptureEnabled(true, AppLocalizationsEn());

        // Device permissions are shown as live rows on the screen instead,
        // so a missing one must not block (or be hidden behind) the switch.
        expect(container.read(provider).captureEnabled, isTrue);
        expect(cameraCalls, isEmpty);
      },
    );
  });
}