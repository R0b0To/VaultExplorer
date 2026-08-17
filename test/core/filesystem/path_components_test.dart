import 'package:test/test.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/core/filesystem/path_components.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  final l10n = AppLocalizationsEn();

  group('success', () {
    test('joins parent segments and a valid leaf name with "/"', () {
      final result = const PathComponents(
        parentSegments: ['Documents', 'Receipts'],
        name: '2026-01.pdf',
        type: EntryType.file,
        fsType: FilesystemType.fat32,
      ).validateAndBuild(l10n);

      expect(result, isA<PathBuildSuccess>());
      expect((result as PathBuildSuccess).path, 'Documents/Receipts/2026-01.pdf');
    });

    test('an empty parentSegments list produces just the leaf name', () {
      final result = const PathComponents(
        parentSegments: [],
        name: 'root-file.txt',
        type: EntryType.file,
        fsType: FilesystemType.fat32,
      ).validateAndBuild(l10n);

      expect(result, isA<PathBuildSuccess>());
      expect((result as PathBuildSuccess).path, 'root-file.txt');
    });

    test('parent segments are not re-validated — a segment that would fail '
        'validation today is passed through unchanged since it already '
        'exists on the volume', () {
      final result = const PathComponents(
        parentSegments: ['Weird:Folder'], // ':' would fail fat32 validation
        name: 'file.txt',
        type: EntryType.file,
        fsType: FilesystemType.fat32,
      ).validateAndBuild(l10n);

      expect(result, isA<PathBuildSuccess>());
      expect((result as PathBuildSuccess).path, 'Weird:Folder/file.txt');
    });
  });

  group('failure — invalid leaf name', () {
    test('propagates the exact issues from validateEntryName', () {
      final result = const PathComponents(
        parentSegments: ['Documents'],
        name: 'CON',
        type: EntryType.file,
        fsType: FilesystemType.fat32,
      ).validateAndBuild(l10n);

      expect(result, isA<PathBuildFailure>());
      final issues = (result as PathBuildFailure).issues;
      expect(
        issues.map((i) => i.reason),
        contains(NameValidationReason.reservedDeviceName),
      );
    });

    test('an illegal character in the leaf name fails even with valid '
        'parent segments', () {
      final result = const PathComponents(
        parentSegments: ['Documents'],
        name: 'bad:name.txt',
        type: EntryType.file,
        fsType: FilesystemType.fat32,
      ).validateAndBuild(l10n);

      expect(result, isA<PathBuildFailure>());
    });
  });

  group('failure — total path length', () {
    test('exactly at the fat32 260-char limit succeeds', () {
      // 'Documents/' is 10 chars; pad the name so the total is exactly 260.
      final name = 'f${'a' * (260 - 10 - 1)}'; // 'Documents/' + name = 260
      final result = PathComponents(
        parentSegments: const ['Documents'],
        name: name,
        type: EntryType.file,
        fsType: FilesystemType.fat32,
      ).validateAndBuild(l10n);
      // Guard against a mistaken length calculation invalidating the test
      // itself.
      expect('Documents/$name'.length, 260);
      expect(result, isA<PathBuildSuccess>());
    });

    test('one character over the fat32 limit fails with a path-length '
        'issue, even though the leaf name alone is valid', () {
      final name = 'f${'a' * (261 - 10 - 1)}'; // total = 261
      final result = PathComponents(
        parentSegments: const ['Documents'],
        name: name,
        type: EntryType.file,
        fsType: FilesystemType.fat32,
      ).validateAndBuild(l10n);

      expect('Documents/$name'.length, 261);
      expect(result, isA<PathBuildFailure>());
      final issues = (result as PathBuildFailure).issues;
      expect(issues, hasLength(1));
      expect(issues.single.reason, NameValidationReason.componentTooLong);
      expect(issues.single.message, l10n.validationPathTooLong(261, 'FAT32', 260));
    });

    test('ext allows a much longer total path (4096)', () {
      final name = 'a' * 200;
      final parent = List.generate(15, (i) => 'folder$i'); // ~150 chars
      final result = PathComponents(
        parentSegments: parent,
        name: name,
        type: EntryType.file,
        fsType: FilesystemType.ext,
      ).validateAndBuild(l10n);

      expect(result, isA<PathBuildSuccess>());
    });
  });
}
