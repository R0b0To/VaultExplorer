import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/features/dashboard/widgets/create_container_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('CreateContainerController Tests', () {
    test('initializes with VeraCrypt and FAT defaults', () {
      final state = container.read(createContainerProvider);

      expect(state.format, CreateFormat.veracrypt);
      expect(state.fileSystem, 'FAT');
      expect(state.sizeUnit, 'MB');
      expect(state.quickFormat, isTrue);
      expect(state.isFolderVault, isFalse);
      expect(state.enableHiddenVolume, isFalse);
    });

    test('setFormat automatically updates default filesystem and algorithm choices', () {
      final controller = container.read(createContainerProvider.notifier);

      // Switching to LUKS1 defaults to ext4
      controller.setFormat(CreateFormat.luks1);
      var state = container.read(createContainerProvider);
      expect(state.format, CreateFormat.luks1);
      expect(state.fileSystem, 'ext4');

      // Switching to LUKS2 keeps ext4
      controller.setFormat(CreateFormat.luks2);
      state = container.read(createContainerProvider);
      expect(state.format, CreateFormat.luks2);
      expect(state.fileSystem, 'ext4');

      // Switching back to VeraCrypt resets default to FAT
      controller.setFormat(CreateFormat.veracrypt);
      state = container.read(createContainerProvider);
      expect(state.format, CreateFormat.veracrypt);
      expect(state.fileSystem, 'FAT');
    });

    test('setVaultKind switches between container file and directory vault modes', () {
      final controller = container.read(createContainerProvider.notifier);

      controller.setVaultKind(true);
      expect(container.read(createContainerProvider).isFolderVault, isTrue);

      controller.setFolderVaultFormat('gocryptfs');
      expect(container.read(createContainerProvider).folderVaultFormat, 'gocryptfs');

      controller.setVaultKind(false);
      expect(container.read(createContainerProvider).isFolderVault, isFalse);
    });

    test('setEnableHiddenVolume toggles hidden volume state', () {
      final controller = container.read(createContainerProvider.notifier);

      controller.setEnableHiddenVolume(true);
      expect(container.read(createContainerProvider).enableHiddenVolume, isTrue);

      controller.setHiddenSizeUnit('GB');
      expect(container.read(createContainerProvider).hiddenSizeUnit, 'GB');
    });
  });
}