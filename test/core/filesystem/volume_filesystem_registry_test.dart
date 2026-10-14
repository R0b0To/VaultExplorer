import 'package:test/test.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/filesystem/volume_filesystem_registry.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

MountedContainer _container({
  required int volId,
  String format = 'veracrypt',
}) =>
    MountedContainer(
      uri: 'content://test/$volId',
      displayName: 'test-$volId',
      volId: volId,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 0,
      freeSpace: 0,
      containerFormat: format,
    );

void main() {
  setUp(VolumeFilesystemRegistry.clearForTesting);
  tearDown(VolumeFilesystemRegistry.clearForTesting);

  group('filesystemTypeFromLabel', () {
    test('maps every label native can report', () {
      // Exactly the strings produced by fsGetFilesystemLabel() in fs_ops.cpp.
      expect(filesystemTypeFromLabel('FAT12'), FilesystemType.fat32);
      expect(filesystemTypeFromLabel('FAT16'), FilesystemType.fat32);
      expect(filesystemTypeFromLabel('FAT32'), FilesystemType.fat32);
      expect(filesystemTypeFromLabel('exFAT'), FilesystemType.exfat);
      expect(filesystemTypeFromLabel('NTFS'), FilesystemType.ntfs);
      expect(filesystemTypeFromLabel('ext2'), FilesystemType.ext);
      expect(filesystemTypeFromLabel('ext3'), FilesystemType.ext);
      expect(filesystemTypeFromLabel('ext4'), FilesystemType.ext);
    });

    test('is case-insensitive and trims whitespace', () {
      expect(filesystemTypeFromLabel(' EXT4 '), FilesystemType.ext);
      expect(filesystemTypeFromLabel('exfat'), FilesystemType.exfat);
    });

    test('unknown, empty and null labels stay unknown (never guessed)', () {
      expect(filesystemTypeFromLabel(null), isNull);
      expect(filesystemTypeFromLabel(''), isNull);
      expect(filesystemTypeFromLabel('btrfs'), isNull);
      expect(filesystemTypeFromLabel('ext'), isNull);
    });
  });

  group('VolumeFilesystemRegistry', () {
    test('records, looks up and forgets per volume id', () {
      expect(VolumeFilesystemRegistry.lookup(3), isNull);
      VolumeFilesystemRegistry.record(3, FilesystemType.ext);
      VolumeFilesystemRegistry.record(4, FilesystemType.ntfs);
      expect(VolumeFilesystemRegistry.lookup(3), FilesystemType.ext);
      expect(VolumeFilesystemRegistry.lookup(4), FilesystemType.ntfs);
      VolumeFilesystemRegistry.forget(3);
      expect(VolumeFilesystemRegistry.lookup(3), isNull);
      expect(VolumeFilesystemRegistry.lookup(4), FilesystemType.ntfs);
    });

    test('recording null clears a stale entry for a re-used volume id', () {
      VolumeFilesystemRegistry.record(5, FilesystemType.ext);
      VolumeFilesystemRegistry.record(5, null);
      expect(VolumeFilesystemRegistry.lookup(5), isNull);
    });
  });

  group('isDestinationCaseSensitive', () {
    test('ext volume is case-sensitive; FAT/exFAT/NTFS are not', () {
      VolumeFilesystemRegistry.record(1, FilesystemType.ext);
      VolumeFilesystemRegistry.record(2, FilesystemType.fat32);
      VolumeFilesystemRegistry.record(3, FilesystemType.exfat);
      VolumeFilesystemRegistry.record(4, FilesystemType.ntfs);
      expect(isDestinationCaseSensitive(_container(volId: 1)), isTrue);
      expect(isDestinationCaseSensitive(_container(volId: 2)), isFalse);
      expect(isDestinationCaseSensitive(_container(volId: 3)), isFalse);
      expect(isDestinationCaseSensitive(_container(volId: 4)), isFalse);
    });

    test('an unrecorded volume is treated as case-insensitive', () {
      expect(isDestinationCaseSensitive(_container(volId: 9)), isFalse);
    });

    test('local storage (negative volId) is never looked up', () {
      VolumeFilesystemRegistry.record(-1, FilesystemType.ext);
      expect(isDestinationCaseSensitive(_container(volId: -1)), isFalse);
      expect(detectedFilesystemType(_container(volId: -1)), isNull);
    });

    test('encrypted folder-vault formats are case-sensitive', () {
      for (final f in [
        ContainerFormat.cryptomator,
        ContainerFormat.gocryptfs,
        ContainerFormat.cryfs,
      ]) {
        expect(
          isDestinationCaseSensitive(_container(volId: 7, format: f.wire)),
          isTrue,
          reason: f.wire,
        );
      }
    });
  });

  group('resolveFilesystemType', () {
    test('encrypted folder-vault formats resolve to encryptedVault', () {
      for (final f in [
        ContainerFormat.cryptomator,
        ContainerFormat.gocryptfs,
        ContainerFormat.cryfs,
      ]) {
        expect(
          resolveFilesystemType(_container(volId: 7, format: f.wire)),
          FilesystemType.encryptedVault,
          reason: f.wire,
        );
      }
    });

    test('disk-image volumes follow the ext policy switch', () {
      VolumeFilesystemRegistry.record(1, FilesystemType.ext);
      VolumeFilesystemRegistry.record(2, FilesystemType.fat32);
      VolumeFilesystemRegistry.record(3, FilesystemType.ntfs);

      expect(
        resolveFilesystemType(_container(volId: 1)),
        kAllowCaseDistinctNamesInExtContainers
            ? FilesystemType.extPortable
            : FilesystemType.unknownConservative,
      );
      // Name rules for every other disk-image volume are unchanged.
      expect(
        resolveFilesystemType(_container(volId: 2)),
        FilesystemType.unknownConservative,
      );
      expect(
        resolveFilesystemType(_container(volId: 3)),
        FilesystemType.unknownConservative,
      );
      expect(
        resolveFilesystemType(_container(volId: 99)),
        FilesystemType.unknownConservative,
      );
    });
  });

  group('FilesystemType.extPortable', () {
    test('is unknownConservative with only case sensitivity relaxed', () {
      final portable = FilesystemRules.extPortable;
      final conservative = FilesystemRules.unknownConservative;
      expect(portable.caseSensitive, isTrue);
      expect(conservative.caseSensitive, isFalse);
      expect(portable.illegalCharCodes, conservative.illegalCharCodes);
      expect(portable.disallowControlChars, conservative.disallowControlChars);
      expect(
        portable.disallowReservedDeviceNames,
        conservative.disallowReservedDeviceNames,
      );
      expect(
        portable.disallowTrailingSpaceOrDot,
        conservative.disallowTrailingSpaceOrDot,
      );
      expect(portable.maxComponentLength, conservative.maxComponentLength);
      expect(
        portable.maxComponentLengthIsUtf8Bytes,
        conservative.maxComponentLengthIsUtf8Bytes,
      );
      expect(portable.maxPathLength, conservative.maxPathLength);
    });

    test('is wired into FilesystemRules.of and label()', () {
      final l10n = AppLocalizationsEn();
      expect(
        FilesystemRules.of(FilesystemType.extPortable),
        same(FilesystemRules.extPortable),
      );
      expect(
        FilesystemType.extPortable.label(l10n),
        l10n.filesystemLabelThisContainer,
      );
    });
  });
}
