import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  const api = VaultExplorerApi();

  final calls = <MethodCall>[];
  Object? nextResult;

  setUp(() {
    calls.clear();
    nextResult = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return nextResult;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('getAutomationKeyfiles', () {
    test('sends vaultUri and returns list of keyfile URIs', () async {
      nextResult = ['/storage/emulated/0/key1.bin', 'content://media/key2.bin'];

      final result = await api.getAutomationKeyfiles('/vaults/test_vault');

      expect(calls, hasLength(1));
      expect(calls.single.method, 'getAutomationKeyfiles');
      expect(calls.single.arguments, {'vaultUri': '/vaults/test_vault'});
      expect(result, ['/storage/emulated/0/key1.bin', 'content://media/key2.bin']);
    });

    test('returns null when channel returns null', () async {
      nextResult = null;

      final result = await api.getAutomationKeyfiles('/vaults/empty_vault');

      expect(result, isNull);
    });
  });

  group('setAutomationKeyfiles', () {
    test('sends vaultUri and keyfilePaths', () async {
      nextResult = true;

      final success = await api.setAutomationKeyfiles(
        '/vaults/test_vault',
        ['/storage/key.bin'],
      );

      expect(success, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'setAutomationKeyfiles');
      expect(calls.single.arguments, {
        'vaultUri': '/vaults/test_vault',
        'keyfilePaths': ['/storage/key.bin'],
      });
    });
  });

  group('getAutomationVaultConfig', () {
    test('parses hasStoredKeyfiles from map', () async {
      nextResult = {
        'tier': 'FULL',
        'hasStoredPassword': true,
        'hasStoredKeyfiles': true,
        'captureEnabled': false,
      };

      final config = await api.getAutomationVaultConfig('/vaults/test_vault');

      expect(config.tier, AutomationTier.full);
      expect(config.hasStoredPassword, isTrue);
      expect(config.hasStoredKeyfiles, isTrue);
      expect(config.captureEnabled, isFalse);
    });
  });
}
