import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_info_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;
  late ProviderSubscription subscription;

  const uri = 'file:///vault.hc';
  final provider = vaultInfoProvider(uri);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getVaultInfo') {
        return <String, dynamic>{
          'format': 'veracrypt',
          'cipher': 'AES',
          'hash': 'SHA-512',
          'fileSystem': 'FAT',
        };
      }
      return null;
    });

    container = ProviderContainer();
    subscription = container.listen(provider, (_, __) {});
  });

  tearDown(() {
    subscription.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('VaultInfoController Tests', () {
    test('initializes and loads container metadata', () async {
      final controller = container.read(provider.notifier);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(provider);
      expect(state.loadState, VaultInfoLoadState.loaded);
      expect(state.info['cipher'], 'AES');
      expect(state.info['hash'], 'SHA-512');
    });

    test('retry re-runs metadata load', () async {
      final controller = container.read(provider.notifier);
      await Future<void>.delayed(Duration.zero);

      controller.retry();
      await Future<void>.delayed(Duration.zero);

      final state = container.read(provider);
      expect(state.loadState, VaultInfoLoadState.loaded);
      expect(state.info['format'], 'veracrypt');
    });
  });
}