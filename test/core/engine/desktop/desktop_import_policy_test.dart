// Tests for the pure import rules of the desktop engine (lib/core/engine/desktop/desktop_import_policy.dart).
//
// The first group runs the shared known-answer table test/fixtures/import_policy_golden.tsv; Android's
// ImportExportHandlersGoldenTest.kt runs the very same file against ImportExportHandlers.kt. The rest covers
// what only the Dart side has: the planning of a folder's children.
import 'dart:io';

import 'package:test/test.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_import_policy.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';

void main() {
  group('shared golden table', () {
    final file = File('test/fixtures/import_policy_golden.tsv');

    test('the fixture is readable', () {
      expect(file.existsSync(), isTrue, reason: 'expected ${file.path} (resolved from ${file.absolute.path})');
    });

    test('every row agrees with the Dart implementation', () {
      final failures = <String>[];
      var rows = 0;
      for (final line in file.readAsLinesSync()) {
        if (line.trim().isEmpty || line.startsWith('#')) continue;
        final f = line.split('\t');
        rows++;
        switch (f[0]) {
          case 'unique':
            final taken = f[2] == '-' ? <String>{} : f[2].split('|').toSet();
            final got = uniqueNameAgainst(taken, f[3], caseSensitive: f[1] == 'true');
            if (got != f[4]) failures.add('unique "${f[3]}" vs {${f[2]}} (caseSensitive=${f[1]}): expected "${f[4]}", got "$got"');
          case 'margin':
            final got = fitsWithinSafetyMargin(int.parse(f[1]), int.parse(f[2]));
            if (got != (f[3] == 'true')) failures.add('margin ${f[1]} into ${f[2]}: expected ${f[3]}, got $got');
          case 'fold':
            final got = foldName(f[2], f[1] == 'true');
            if (got != f[3]) failures.add('fold "${f[2]}" (caseSensitive=${f[1]}): expected "${f[3]}", got "$got"');
          default:
            failures.add('unknown row kind "${f[0]}"');
        }
      }
      expect(rows, greaterThan(0));
      expect(failures, isEmpty);
    });
  });

  group('importNameIssues', () {
    test('a null rule set is not validated', () {
      expect(importNameIssues('a:b', null, isDir: false), isEmpty);
    });

    test('the conservative rules reject names some filesystem cannot hold', () {
      for (final bad in ['a:b', 'a*b', 'CON', 'trailing dot.', 'trailing space ']) {
        expect(importNameIssues(bad, FilesystemType.unknownConservative, isDir: false), isNotEmpty, reason: bad);
      }
    });

    test('ordinary names pass both rule sets', () {
      for (final good in ['Notes.txt', 'CONNIE', 'archive.tar.gz']) {
        expect(importNameIssues(good, FilesystemType.unknownConservative, isDir: false), isEmpty, reason: good);
        expect(importNameIssues(good, FilesystemType.encryptedVault, isDir: false), isEmpty, reason: good);
      }
    });

    test('a vault takes names the conservative rules refuse', () {
      expect(importNameIssues('a:b', FilesystemType.encryptedVault, isDir: false), isEmpty);
    });
  });

  group('planChildImports', () {
    List<ImportChild> files(List<String> names) => [for (final n in names) ImportChild(n, isDir: false)];
    List<String?> dests(List<ChildImportPlan> plans) => [for (final p in plans) p.destName];

    test('names that differ only by case get unique names on a case-insensitive destination', () {
      final plans = planChildImports(
        files(['Notes.txt', 'notes.txt', 'NOTES.TXT']),
        fsType: null,
        caseSensitive: false,
      );
      expect(dests(plans), ['Notes.txt', 'notes (1).txt', 'NOTES (2).TXT']);
    });

    test('a case-sensitive destination keeps them all', () {
      final plans = planChildImports(
        files(['Notes.txt', 'notes.txt', 'NOTES.TXT']),
        fsType: null,
        caseSensitive: true,
      );
      expect(dests(plans), ['Notes.txt', 'notes.txt', 'NOTES.TXT']);
    });

    test('a unique name never lands on another sibling', () {
      final plans = planChildImports(
        files(['Notes.txt', 'notes.txt', 'notes (1).txt']),
        fsType: null,
        caseSensitive: false,
      );
      expect(dests(plans), ['Notes.txt', 'notes (2).txt', 'notes (1).txt']);
    });

    test('names already in the destination folder are avoided too', () {
      final plans = planChildImports(
        files(['a.txt', 'A.txt']),
        fsType: null,
        caseSensitive: false,
        existingFolded: {'a (1).txt'},
      );
      expect(dests(plans), ['a.txt', 'A (2).txt']);
    });

    test('invalid names are skipped with their reasons, the rest still import', () {
      final plans = planChildImports(
        files(['ok.txt', 'a:b.txt', 'also ok.txt']),
        fsType: FilesystemType.unknownConservative,
        caseSensitive: false,
      );
      expect(plans.map((p) => p.isSkipped), [false, true, false]);
      expect(plans[1].destName, isNull);
      expect(plans[1].skipReasons, isNotEmpty);
      expect(plans[0].destName, 'ok.txt');
      expect(plans[2].destName, 'also ok.txt');
    });

    test('an empty folder plans nothing', () {
      expect(planChildImports(const [], fsType: null, caseSensitive: false), isEmpty);
    });
  });

  group('digestsEqual', () {
    test('equal, different and different-length digests', () {
      expect(digestsEqual([1, 2, 3], [1, 2, 3]), isTrue);
      expect(digestsEqual([1, 2, 3], [1, 2, 4]), isFalse);
      expect(digestsEqual([1, 2, 3], [1, 2]), isFalse);
      expect(digestsEqual(const [], const []), isTrue);
    });
  });
}
