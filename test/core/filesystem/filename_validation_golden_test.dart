// Runs the shared golden cases in test/fixtures/filename_validation_golden.json
// against the Dart side of the filename validator. The Kotlin side
// (FilesystemNameValidatorGoldenTest.kt) runs the exact same file against
// FilesystemNameValidator.kt.
//
// The two validators are intentionally kept as separate, hand-maintained
// implementations across the JNI boundary (docs/architecture.md, ADR-005
// item 3) rather than unified into one. This test doesn't change that; it
// exists so that if a rule changes on one side and someone forgets to
// mirror it on the other, a test fails immediately instead of the two
// implementations silently drifting apart. Add a case to the JSON file and
// both this test and the Kotlin one pick it up.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/name_validation.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

/// Maps the fixture's `kind` string to the Dart [FilesystemType] the Kotlin
/// side's `FilesystemNameValidator.Kind` enum entry corresponds to. These
/// are the only two kinds the Kotlin validator ever validates against (see
/// its `kindFor()`), so they're the only two this shared fixture covers.
FilesystemType _fsTypeForKind(String kind) => switch (kind) {
      'ENCRYPTED_VAULT' => FilesystemType.encryptedVault,
      'UNKNOWN_CONSERVATIVE' => FilesystemType.unknownConservative,
      _ => throw ArgumentError('Unknown golden-fixture kind: "$kind"'),
    };

void main() {
  final l10n = AppLocalizationsEn();

  // `flutter test` / `dart test` run with the repo root as the working
  // directory, so this path is stable regardless of which test file is
  // running or how it was invoked.
  final fixtureFile = File('test/fixtures/filename_validation_golden.json');

  test('shared filename-validation golden fixture is readable', () {
    expect(
      fixtureFile.existsSync(),
      isTrue,
      reason:
          'Expected ${fixtureFile.path} relative to the working directory. '
          'This test (and its Kotlin counterpart, '
          'FilesystemNameValidatorGoldenTest.kt) both depend on this exact '
          'path; if the test runner\'s working directory has changed, fix '
          'the path here rather than skipping the test.',
    );
  });

  final decoded =
      jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  final cases = decoded['cases'] as List<dynamic>;

  group('filename validation golden cases (Dart side)', () {
    for (final raw in cases) {
      final testCase = raw as Map<String, dynamic>;
      final name = testCase['name'] as String;
      final kind = testCase['kind'] as String;
      final expectedValid = testCase['valid'] as bool;
      final note = testCase['note'] as String?;

      final description = '"$name" on $kind should be '
          '${expectedValid ? "valid" : "invalid"}'
          '${note != null ? " ($note)" : ""}';

      test(description, () {
        final result = validateEntryName(
          name,
          _fsTypeForKind(kind),
          entryType: EntryType.file,
          l10n: l10n,
        );
        expect(
          result.isValid,
          expectedValid,
          reason: result.isValid
              ? 'expected invalid, but got no issues'
              : 'expected valid, but got: ${result.issues.join(", ")}',
        );
      });
    }
  });
}
