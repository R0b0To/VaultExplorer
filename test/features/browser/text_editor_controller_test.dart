import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_controller.dart';

MountedContainer _testContainer() => MountedContainer(
      volId: 1,
      uri: 'file:///vault.hc',
      displayName: 'Vault',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      containerFormat: 'veracrypt',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;
  late ProviderSubscription subscription;

  const testContent = 'Hello, encrypted world!';
  final testBytes = Uint8List.fromList(utf8.encode(testContent));

  final testVault = _testContainer();
  final provider = textEditorLoadProvider(1, '/notes.txt');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getFileSize':
          return testBytes.length;
        case 'readFileChunk':
          return testBytes;
        case 'writeFileChunk':
        case 'finishWrite':
        case 'deleteFile':
        case 'renameFile':
          return true;
        default:
          return null;
      }
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

  group('TextEditorController Tests', () {
    test('initializes and loads plaintext content', () async {
      final controller = container.read(provider.notifier);

      await controller.load(testVault, 'Failed to load', 'Invalid text encoding');

      final state = container.read(provider);
      expect(state.loadedText, 'Hello, encrypted world!');
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
    });

    test('save writes updated text content and returns null error on success', () async {
      final controller = container.read(provider.notifier);

      await controller.load(testVault, 'Failed to load', 'Invalid text encoding');
      final error = await controller.save(testVault, 'Updated text', 'Write back failed');

      expect(error, isNull);
    });
  });
}