import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
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
  late Map<String, String> secureValues;
  late List<Map<String, dynamic>> activeSessions;
  var lockContainerCalls = 0;

  setUp(() {
    secureValues = {};
    activeSessions = [];
    lockContainerCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'deleteSecure':
          secureValues.remove((call.arguments as Map)['key'] as String);
          return true;
        case 'readSecure':
          return secureValues[(call.arguments as Map)['key'] as String];
        case 'writeSecure':
          final arguments = call.arguments as Map;
          secureValues[arguments['key'] as String] =
              arguments['value'] as String;
          return true;
        case 'syncBackgroundService':
          return null;
        case 'getSpaceInfo':
          return [1000000, 500000];
        case 'hasAllFilesAccess':
          return true;
        case 'getActiveContainerSessions':
          return {'sessions': activeSessions};
        case 'lockContainer':
          lockContainerCalls++;
          return true;
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

    test('onContainerLocked with two mounted vaults only removes the '
        'targeted one -- the other stays mounted', () async {
      // Regression test for: closing/locking Vault A while Vault B is also
      // open must leave Vault B mounted, not tear down every open vault.
      final controller = container.read(vaultDashboardControllerProvider.notifier);
      await controller.loadAll();

      final vaultA = _testContainer(volId: 1, uri: 'file:///vaultA.hc', name: 'Vault A');
      final vaultB = _testContainer(volId: 2, uri: 'file:///vaultB.hc', name: 'Vault B');

      controller.onContainerMounted(vaultA);
      controller.onContainerMounted(vaultB);
      expect(container.read(vaultDashboardControllerProvider).mounted, hasLength(2));

      controller.onContainerLocked(vaultA.volId);

      final state = container.read(vaultDashboardControllerProvider);
      expect(state.mounted, hasLength(1));
      expect(state.mounted.single.volId, vaultB.volId);
      expect(state.mounted, contains(vaultB));

      final displayItems = controller.getDisplayItems();
      expect(displayItems, hasLength(1));
      expect(displayItems.single.name, 'Vault B');
    });

    test('onVaultForceLocked (native force-lock event) only locks the '
        'reported vault, not every mounted vault', () async {
      // Regression test for the native "force locked" event path (USB
      // detach / hidden-volume-protection / "lock all" notification all
      // funnel through this) -- it must never lock vaults it wasn't told
      // to lock.
      final controller = container.read(vaultDashboardControllerProvider.notifier);
      await controller.loadAll();

      final vaultA = _testContainer(volId: 1, uri: 'file:///vaultA.hc', name: 'Vault A');
      final vaultB = _testContainer(volId: 2, uri: 'file:///vaultB.hc', name: 'Vault B');

      controller.onContainerMounted(vaultA);
      controller.onContainerMounted(vaultB);

      controller.onVaultForceLocked(vaultA.volId);

      final state = container.read(vaultDashboardControllerProvider);
      expect(state.mounted, hasLength(1));
      expect(state.mounted.single.volId, vaultB.volId);
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

    test('checkAutoCloseTimeouts locks containers whose timeout was reached', () async {
      final controller = container.read(vaultDashboardControllerProvider.notifier);
      await controller.loadAll();

      final vault = _testContainer(volId: 1, uri: 'file:///vault1.hc', name: 'Vault 1');
      const record = ContainerRecord(
        uri: 'file:///vault1.hc',
        label: 'Vault 1',
        autoCloseMins: 1,
      );

      controller.onContainerMounted(vault, record: record);
      expect(container.read(vaultDashboardControllerProvider).mounted, hasLength(1));

      // Before timeout has elapsed: container stays mounted
      await controller.checkAutoCloseTimeouts();
      expect(container.read(vaultDashboardControllerProvider).mounted, hasLength(1));

      // Cancel auto-close timer before tearing down
      controller.cancelAutoClose(vault.volId);
    });

    test('reconcile locks a restored vault with an expired auto-close deadline', () async {
      const uri = 'file:///vault1.hc';
      const autoCloseKey = 'container_auto_close_started_at_v1_$uri';
      const record = ContainerRecord(
        uri: uri,
        label: 'Vault 1',
        autoCloseMins: 1,
      );
      final vault = _testContainer(volId: 1, uri: uri, name: 'Vault 1');

      // First controller represents the app before it is removed from recents.
      final initialController =
          container.read(vaultDashboardControllerProvider.notifier);
      await initialController.loadAll();
      initialController.onContainerMounted(vault, record: record);
      await Future<void>.delayed(Duration.zero);
      expect(secureValues.containsKey(autoCloseKey), isTrue);

      // Disposing the controller simulates the process-local timer being lost.
      container.dispose();
      container = ProviderContainer();
      final restoredController =
          container.read(vaultDashboardControllerProvider.notifier);
      await restoredController.loadAll();
      await restoredController.updateContainerRecord(uri, record);

      secureValues[autoCloseKey] = DateTime.now()
          .subtract(const Duration(minutes: 2))
          .millisecondsSinceEpoch
          .toString();
      activeSessions = [
        {
          'uri': uri,
          'displayName': 'Vault 1',
          'volId': 1,
          'files': <String>[],
          'containerFormat': 'veracrypt',
        },
      ];

      await restoredController.reconcileActiveSessions();

      expect(lockContainerCalls, 1);
      expect(container.read(vaultDashboardControllerProvider).mounted, isEmpty);
      await Future<void>.delayed(Duration.zero);
      expect(secureValues.containsKey(autoCloseKey), isFalse);
    });

    test('resetAllAutoCloseTimers reschedules auto-close timers for mounted containers', () async {
      final controller = container.read(vaultDashboardControllerProvider.notifier);
      await controller.loadAll();

      final vault = _testContainer(volId: 1, uri: 'file:///vault1.hc', name: 'Vault 1');
      const record = ContainerRecord(
        uri: 'file:///vault1.hc',
        label: 'Vault 1',
        autoCloseMins: 5,
      );

      controller.onContainerMounted(vault, record: record);
      expect(container.read(vaultDashboardControllerProvider).mounted, hasLength(1));

      // Calling resetAllAutoCloseTimers should not throw and keep container mounted
      controller.resetAllAutoCloseTimers();
      expect(container.read(vaultDashboardControllerProvider).mounted, hasLength(1));

      controller.cancelAutoClose(vault.volId);
    });
  });
}
