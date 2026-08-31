import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppSettings keepVaultsRunningInBackground', () {
    test('defaults to false', () {
      final settings = AppSettings();
      expect(settings.keepVaultsRunningInBackground, isFalse);
    });

    test('copyWith updates keepVaultsRunningInBackground', () {
      final settings = AppSettings();
      final updated = settings.copyWith(keepVaultsRunningInBackground: true);
      expect(updated.keepVaultsRunningInBackground, isTrue);

      final reverted = updated.copyWith(keepVaultsRunningInBackground: false);
      expect(reverted.keepVaultsRunningInBackground, isFalse);
    });

    test('serializes and deserializes from JSON', () {
      final settings = AppSettings(keepVaultsRunningInBackground: true);
      final json = settings.toJson();
      expect(json['keepVaultsRunningInBackground'], isTrue);

      final restored = AppSettings.fromJson(json);
      expect(restored.keepVaultsRunningInBackground, isTrue);

      final restoredDefault = AppSettings.fromJson({});
      expect(restoredDefault.keepVaultsRunningInBackground, isFalse);
    });
  });

  group('typed keepalive integration', () {
    const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
    final log = <MethodCall>[];

    setUp(() {
      log.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
            log.add(call);
            if (call.method == ChannelMethods.syncBackgroundService) {
              return null;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'syncBackgroundService invokes channel method with enabled argument',
      () async {
      final api = VaultLifecycleApi(channel, VaultEngineEvents());

        await api.syncBackgroundService(enabled: true);
        expect(log.length, 1);
        expect(log.first.method, ChannelMethods.syncBackgroundService);
        expect(log.first.arguments, {'enabled': true});

        await api.syncBackgroundService(enabled: false);
        expect(log.length, 2);
        expect(log.last.method, ChannelMethods.syncBackgroundService);
        expect(log.last.arguments, {'enabled': false});
      },
    );

    test('event registry receives onVaultForceLocked notification', () async {
      int? reportedVolId;
      void listener(int volId) {
        reportedVolId = volId;
      }

      final events = VaultEngineEvents()..registerHandler(channel);
      events.addVaultForceLockedListener(listener);

      // Simulate native calling onVaultForceLocked
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final byteData = const StandardMethodCodec().encodeMethodCall(
        const MethodCall('onVaultForceLocked', {'volId': 42}),
      );

      await messenger.handlePlatformMessage(
        'com.aeidolon.vaultexplorer/engine',
        byteData,
        (ByteData? reply) {},
      );

      expect(reportedVolId, 42);

      events.removeVaultForceLockedListener(listener);

      // Verify removed listener is no longer called
      reportedVolId = null;
      await messenger.handlePlatformMessage(
        'com.aeidolon.vaultexplorer/engine',
        byteData,
        (ByteData? reply) {},
      );
      expect(reportedVolId, isNull);
    });
  });
}
