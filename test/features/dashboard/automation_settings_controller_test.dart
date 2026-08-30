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
      switch (call.method) {
        case 'hasPermissions':
          return true;
        default:
          return null;
      }
    });

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
  });
}