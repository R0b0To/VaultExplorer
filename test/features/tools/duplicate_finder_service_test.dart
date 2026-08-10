import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/duplicate_finder_models.dart';

void main() {
  group('VaultFileItem Tests', () {
    final container1 = MountedContainer(
      volId: 1,
      displayName: 'Vault A',
      containerFormat: 'veracrypt',
      uri: 'file:///vault_a.hc',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 100000000,
      freeSpace: 50000000,
    );

    final container2 = MountedContainer(
      volId: 2,
      displayName: 'Vault B',
      containerFormat: 'luks2',
      uri: 'file:///vault_b.luks',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 100000000,
      freeSpace: 50000000,
    );

    test('unique ID combines volId and relativePath', () {
      final item1 = VaultFileItem(
        container: container1,
        relativePath: 'photos/beach.jpg',
        name: 'beach.jpg',
        sizeBytes: 1024,
        modifiedSecs: 1700000000,
      );

      final item2 = VaultFileItem(
        container: container2,
        relativePath: 'photos/beach.jpg',
        name: 'beach.jpg',
        sizeBytes: 1024,
        modifiedSecs: 1700000000,
      );

      expect(item1.id, equals('1:photos/beach.jpg'));
      expect(item2.id, equals('2:photos/beach.jpg'));
      expect(item1, isNot(equals(item2)));
    });
  });

  group('DuplicateGroup Tests', () {
    final container = MountedContainer(
      volId: 10,
      displayName: 'Main Vault',
      containerFormat: 'cryfs',
      uri: 'file:///main_vault',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 100000000,
      freeSpace: 50000000,
    );

    test('totalWasteBytes calculates correct redundant space', () {
      final file1 = VaultFileItem(
        container: container,
        relativePath: 'photos/2024/beach.jpg',
        name: 'beach.jpg',
        sizeBytes: 4200000, // 4.2 MB
        modifiedSecs: 1700000000,
      );

      final file2 = VaultFileItem(
        container: container,
        relativePath: 'backups/imports/IMG_0042.jpg',
        name: 'IMG_0042.jpg',
        sizeBytes: 4200000,
        modifiedSecs: 1700000050,
      );

      final file3 = VaultFileItem(
        container: container,
        relativePath: 'temp/beach_copy.jpg',
        name: 'beach_copy.jpg',
        sizeBytes: 4200000,
        modifiedSecs: 1700000100,
      );

      final group = DuplicateGroup(
        id: 'group_1',
        sizeBytes: 4200000,
        fullHash: 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
        files: [file1, file2, file3],
      );

      // 3 copies of 4.2 MB => 2 redundant copies => 8.4 MB wasted
      expect(group.totalWasteBytes, equals(4200000 * 2));
    });
  });

  group('DuplicateScanProgress Tests', () {
    test('progressFraction advances properly through stages', () {
      expect(
        const DuplicateScanProgress(stage: DuplicateScanStage.idle).progressFraction,
        equals(0.0),
      );

      expect(
        const DuplicateScanProgress(stage: DuplicateScanStage.indexing).progressFraction,
        equals(0.15),
      );

      final p2 = const DuplicateScanProgress(
        stage: DuplicateScanStage.partialHashing,
        totalCandidatesToHash: 10,
        processedCandidates: 5,
      );
      expect(p2.progressFraction, closeTo(0.35, 0.01));

      final p3 = const DuplicateScanProgress(
        stage: DuplicateScanStage.fullHashing,
        totalCandidatesToHash: 10,
        processedCandidates: 5,
      );
      expect(p3.progressFraction, closeTo(0.75, 0.01));

      expect(
        const DuplicateScanProgress(stage: DuplicateScanStage.complete).progressFraction,
        equals(1.0),
      );
    });
  });
}
