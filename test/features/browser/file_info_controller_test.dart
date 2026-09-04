import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/file_info_controller.dart';

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

  final testVault = _testContainer();
  const testEntry = RawEntry(
    name: 'photo.jpg',
    isDir: false,
    sizeBytes: 10,
    modifiedSecs: 1000,
  );

  final provider = fileInfoProvider(1, '/photo.jpg');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'readFileChunk') {
        return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]);
      }
      if (call.method == 'beginHashSession') {
        return null;
      }
      if (call.method == 'updateHashSession') {
        return null;
      }
      if (call.method == 'finishHashSession') {
        return {'SHA-256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'};
      }
      return null;
    });

    container = ProviderContainer();
    subscription = container.listen(provider, (_, _) {});
  });

  tearDown(() {
    subscription.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('FileInfoController Tests', () {
    test('initializes and loads file metadata with valid arguments', () async {
      final controller = container.read(provider.notifier);

      await controller.load(testVault, testEntry);

      final state = container.read(provider);
      expect(state.loading, isFalse);
      expect(state.metadata, isNotNull);
    });

    test('computeSha256 calculates and sets hash string', () async {
      final controller = container.read(provider.notifier);

      await controller.computeSha256(testVault, testEntry);

      final state = container.read(provider);
      expect(state.sha256, 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
      expect(state.calculatingSha256, isFalse);
    });
  });
}