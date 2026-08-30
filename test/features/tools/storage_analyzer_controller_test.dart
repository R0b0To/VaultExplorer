import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_controller.dart';

MountedContainer _testContainer({required int volId, required String uri, required String name}) =>
    MountedContainer(
      volId: volId,
      uri: uri,
      displayName: name,
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

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'getSpaceInfo') {
        return [1000000, 500000];
      }
      if (call.method == 'listDirectory') {
        return <String>[];
      }
      return null;
    });

    container = ProviderContainer();
    subscription = container.listen(storageAnalyzerProvider, (_, __) {});
  });

  tearDown(() {
    subscription.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('StorageAnalyzerController Tests', () {
    final vaultA = _testContainer(volId: 1, uri: 'file:///v1.hc', name: 'Vault 1');
    final vaultB = _testContainer(volId: 2, uri: 'file:///v2.hc', name: 'Vault 2');

    test('initializes with idle state and no selected container', () {
      final state = container.read(storageAnalyzerProvider);

      expect(state.selected, isNull);
      expect(state.loading, isFalse);
      expect(state.heaviest, isEmpty);
      expect(state.breakdown, isEmpty);
    });

    test('onMountedListChanged auto-selects first container when none selected', () async {
      final controller = container.read(storageAnalyzerProvider.notifier);

      controller.onMountedListChanged([vaultA, vaultB]);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(storageAnalyzerProvider).selected?.volId, 1);
    });

    test('selectTarget explicitly changes scan target and updates selected', () async {
      final controller = container.read(storageAnalyzerProvider.notifier);

      await controller.selectTarget(vaultB);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(storageAnalyzerProvider).selected?.volId, 2);
    });
  });
}