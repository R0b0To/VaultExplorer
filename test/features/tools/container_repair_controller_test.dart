import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/container_repair_controller.dart';

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
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('ContainerRepairController Tests', () {
    test('initializes with idle state and no selected target', () {
      final state = container.read(containerRepairProvider);

      expect(state.target, isNull);
      expect(state.diagnosing, isFalse);
      expect(state.actionRunning, isFalse);
      expect(state.isWorking, isFalse);
      expect(state.logLines, isEmpty);
    });

    test('pickMountedVolume sets MountedVolumeTarget', () {
      final controller = container.read(containerRepairProvider.notifier);
      final vault = _testContainer(volId: 1, uri: 'file:///vault.hc', name: 'Main Vault');

      controller.pickMountedVolume(vault);

      final target = container.read(containerRepairProvider).target;
      expect(target, isA<MountedVolumeTarget>());
      expect((target as MountedVolumeTarget).displayName, 'Main Vault');
    });

    test('pickMountedFolderVault sets FolderVaultTarget', () {
      final controller = container.read(containerRepairProvider.notifier);
      final vault = _testContainer(volId: 2, uri: 'file:///cryfs_vault', name: 'CryFS Vault');

      controller.pickMountedFolderVault(vault);

      final target = container.read(containerRepairProvider).target;
      expect(target, isA<FolderVaultTarget>());
      expect((target as FolderVaultTarget).displayName, 'CryFS Vault');
    });

    test('appendLogLine appends output and changeTarget resets state', () {
      final controller = container.read(containerRepairProvider.notifier);

      controller.appendLogLine('[INFO] Scanning partition table...');
      expect(container.read(containerRepairProvider).logLines, ['[INFO] Scanning partition table...']);

      controller.changeTarget();
      expect(container.read(containerRepairProvider).target, isNull);
      expect(container.read(containerRepairProvider).logLines, isEmpty);
    });
  });
}