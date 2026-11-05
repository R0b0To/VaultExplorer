import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/services/raw_local_category_lister.dart';

bool _isImage(String name) => name.endsWith('.jpg') || name.endsWith('.png');

void main() {
  late Directory root;

  Future<List<RawEntry>?> list(
    String dir, {
    bool Function(String)? matches,
  }) async {
    final raw = await rawLocalCategoryLister(
      rootPath: root.path,
      matches: matches ?? _isImage,
    )(dir);
    return raw == null ? null : RawEntry.parseAll(raw);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lister_test');
    await Directory('${root.path}/DCIM/Camera').create(recursive: true);
    await File('${root.path}/top.jpg').writeAsBytes(List.filled(7, 1));
    await File('${root.path}/notes.txt').writeAsString('x');
    await File(
      '${root.path}/DCIM/Camera/a.jpg',
    ).writeAsBytes(List.filled(3, 1));
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  group('rawLocalCategoryLister', () {
    test('reports folders by name and only the files that match', () async {
      final entries = (await list(''))!;
      final byName = {for (final e in entries) e.name: e};
      expect(byName.keys.toSet(), {'DCIM', 'top.jpg'});
      expect(byName['DCIM']!.isDir, isTrue);
      expect(byName['top.jpg']!.isDir, isFalse);
      expect(byName['top.jpg']!.sizeBytes, 7);
      expect(byName['top.jpg']!.modifiedSecs, greaterThan(0));
    });

    test('lists a sub-folder by its path relative to the root', () async {
      final entries = (await list('DCIM/Camera'))!;
      expect(entries.map((e) => e.name), ['a.jpg']);
      expect(entries.single.sizeBytes, 3);
    });

    test('never asks the predicate about folders', () async {
      final asked = <String>[];
      await list(
        '',
        matches: (n) {
          asked.add(n);
          return false;
        },
      );
      expect(asked, contains('notes.txt'));
      expect(asked, isNot(contains('DCIM')));
    });

    test('reports the .nomedia marker without it needing to match', () async {
      await File('${root.path}/DCIM/.nomedia').writeAsString('');
      final entries = (await list('DCIM'))!;
      final marker = entries.where((e) => e.name == '.nomedia');
      expect(marker, hasLength(1));
      expect(marker.single.isDir, isFalse);
    });

    test('a folder that does not exist is unlistable, not empty', () async {
      expect(await list('nope'), isNull);
    });

    test('an empty folder is an empty listing', () async {
      await Directory('${root.path}/Empty').create();
      expect(await list('Empty'), isEmpty);
    });

    test('a root given with a trailing slash works the same', () async {
      final raw = await rawLocalCategoryLister(
        rootPath: '${root.path}/',
        matches: _isImage,
      )('DCIM/Camera');
      expect(RawEntry.parseAll(raw!).map((e) => e.name), ['a.jpg']);
    });

    test('many matches are all reported, beyond one stat batch', () async {
      for (var i = 0; i < 100; i++) {
        await File('${root.path}/DCIM/p$i.png').writeAsBytes([i]);
      }
      final entries = (await list('DCIM'))!;
      expect(entries.where((e) => e.name.endsWith('.png')), hasLength(100));
    });

    test('a name containing a pipe survives the wire format', () async {
      await File('${root.path}/a|b.jpg').writeAsBytes([1]);
      final entries = (await list(''))!;
      expect(entries.map((e) => e.name), contains('a|b.jpg'));
    });

    test('symbolic links are not followed or reported', () async {
      await Link('${root.path}/link').create('${root.path}/DCIM');
      final entries = (await list(''))!;
      expect(entries.map((e) => e.name), isNot(contains('link')));
    });
  });
}
