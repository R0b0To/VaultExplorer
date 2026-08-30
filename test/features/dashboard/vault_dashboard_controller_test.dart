import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';

MountedContainer _testContainer({
  required int volId,
  required String uri,
  required String name,
  bool readOnly = false,
}) =>
    MountedContainer(
      volId: volId,
      uri: uri,
      displayName: name,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      readOnly: readOnly,
      containerFormat: 'veracrypt',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'deleteSecure':
          return true;
        case 'readSecure':
          return null;
        case 'writeSecure':
          return true;
        case 'syncBackgroundService':
          return null;
        case 'getSpaceInfo':
          return [1000000, 500000];
        case 'hasAllFilesAccess':
          return true;
        case 'getActiveContainerSessions':
          return {'sessions': <Map<String, dynamic>>[]};
        default:
          return null;
      }
    });

    container = ProviderContainer();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('VaultDashboardController Tests', () {
    test('onContainerMounted adds container and updates display items', () async {
      final controller = container.read(vaultDashboardControllerProvider.notifier);
      await controller.loadAll();

      final testVault = _testContainer(volId: 1, uri: 'file:///vault1.hc', name: 'Vault 1');

      controller.onContainerMounted(testVault);

      final state = container.read(vaultDashboardControllerProvider);
      expect(state.mounted, contains(testVault));

      final displayItems = controller.getDisplayItems();
      expect(displayItems, hasLength(1));
      expect(displayItems.first, isA<MountedVaultItem>());
      expect(displayItems.first.name, 'Vault 1');
    });

    test('onContainerLocked removes container from mounted list', () async {
      final controller = container.read(vaultDashboardControllerProvider.notifier);
      await controller.loadAll();

      final testVault = _testContainer(volId: 1, uri: 'file:///vault1.hc', name: 'Vault 1');

      controller.onContainerMounted(testVault);
      expect(container.read(vaultDashboardControllerProvider).mounted, hasLength(1));

      controller.onContainerLocked(1);
      expect(container.read(vaultDashboardControllerProvider).mounted, isEmpty);
    });

    test('reordering items updates recordsOrder in manual sort mode', () async {
      final controller = container.read(vaultDashboardControllerProvider.notifier);
      await controller.loadAll();

      final vaultA = _testContainer(volId: 1, uri: 'file:///vaultA.hc', name: 'Vault A');
      final vaultB = _testContainer(volId: 2, uri: 'file:///vaultB.hc', name: 'Vault B');

      controller.onContainerMounted(vaultA);
      controller.onContainerMounted(vaultB);

      var items = controller.getDisplayItems();
      expect(items, hasLength(2));
      expect(items[0].name, 'Vault A');
      expect(items[1].name, 'Vault B');

      await controller.handleReorder(0, 1);

      items = controller.getDisplayItems();
      expect(items, hasLength(2));
      expect(items[0].name, 'Vault B');
      expect(items[1].name, 'Vault A');
    });

    test('acquireLockGuard and releaseLockGuard manage in-memory lock state', () {
      final controller = container.read(vaultDashboardControllerProvider.notifier);

      expect(controller.acquireLockGuard(10), isTrue);
      expect(controller.acquireLockGuard(10), isFalse);

      controller.releaseLockGuard(10);
      expect(controller.acquireLockGuard(10), isTrue);
      controller.releaseLockGuard(10);
    });
  });
}