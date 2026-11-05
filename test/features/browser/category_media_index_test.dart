import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/services/category_media_index_api.dart';
import 'package:vaultexplorer/features/browser/services/category_walk_policy.dart';

RawEntry _row(String path, [int size = 1, int modified = 1]) =>
    RawEntry(name: path, isDir: false, sizeBytes: size, modifiedSecs: modified);

bool _isImage(String name) => name.endsWith('.jpg') || name.endsWith('.png');
bool _isHidden(String name) => name.startsWith('.');

List<RawEntry> _filter(
  List<RawEntry> rows, {
  bool showHidden = false,
  bool Function(String)? skip,
}) => filterCategoryIndexRows(
  rows,
  matches: _isImage,
  isHidden: _isHidden,
  showHidden: showHidden,
  skipDirectory: skip,
);

void main() {
  group('filterCategoryIndexRows', () {
    test('keeps only names the category matches', () {
      final kept = _filter([_row('a.jpg'), _row('b.txt'), _row('d/c.png')]);
      expect(kept.map((e) => e.name), ['a.jpg', 'd/c.png']);
    });

    test('drops files under a hidden folder unless hidden files are shown', () {
      final rows = [
        _row('.thumbs/a.jpg'),
        _row('ok/b.jpg'),
        _row('ok/.c/d.jpg'),
      ];
      expect(_filter(rows).map((e) => e.name), ['ok/b.jpg']);
      expect(_filter(rows, showHidden: true), hasLength(3));
    });

    test('applies the skip rule to every folder above a file', () {
      final rows = [
        _row('Android/data/app/a.jpg'),
        _row('Android/media/app/b.jpg'),
        _row('Pictures/cache/c.jpg'),
        _row('DCIM/d.jpg'),
      ];
      final kept = _filter(rows, skip: skipDeviceCategoryFolder);
      expect(kept.map((e) => e.name), [
        'Android/media/app/b.jpg',
        'DCIM/d.jpg',
      ]);
    });

    test('ignores directory rows', () {
      final dir = const RawEntry(
        name: 'x.jpg',
        isDir: true,
        sizeBytes: 0,
        modifiedSecs: 0,
      );
      expect(_filter([dir, _row('y.jpg')]).map((e) => e.name), ['y.jpg']);
    });

    test('keeps size and date untouched', () {
      final kept = _filter([_row('a.jpg', 123, 456)]).single;
      expect(kept.sizeBytes, 123);
      expect(kept.modifiedSecs, 456);
    });
  });

  group('CategoryMediaIndexApi', () {
    Future<CategoryMediaIndexRows?> ask(
      Future<Object?> Function(String, Map<String, Object?>) fn,
    ) => CategoryMediaIndexApi(fn).query(
      rootPath: '/storage/emulated/0',
      extensions: const ['jpg', 'png'],
      limit: 100,
    );

    test(
      'sends the root, the extensions and the limit to the right method',
      () async {
        String? method;
        Map<String, Object?>? args;
        await ask((m, a) async {
          method = m;
          args = a;
          return {'entries': <String>[], 'truncated': false};
        });
        expect(method, 'queryCategoryIndex');
        expect(args!['rootPath'], '/storage/emulated/0');
        expect(args!['extensions'], ['jpg', 'png']);
        expect(args!['limit'], 100);
      },
    );

    test('parses wire entries and the truncated flag', () async {
      final rows = (await ask(
        (m, a) async => {
          'entries': ['F|5|99|DCIM/a.jpg', 'F|6|98|b.png'],
          'truncated': true,
        },
      ))!;
      expect(rows.entries.map((e) => e.name), ['DCIM/a.jpg', 'b.png']);
      expect(rows.entries.first.sizeBytes, 5);
      expect(rows.entries.first.modifiedSecs, 99);
      expect(rows.truncated, isTrue);
    });

    test('a malformed row is skipped, the rest kept', () async {
      final rows = (await ask(
        (m, a) async => {
          'entries': ['garbage', 'F|1|1|ok.jpg', 42],
        },
      ))!;
      expect(rows.entries.map((e) => e.name), ['ok.jpg']);
      expect(rows.truncated, isFalse);
    });

    test(
      'null, a wrong shape or a thrown error all mean "cannot answer"',
      () async {
        expect(await ask((m, a) async => null), isNull);
        expect(await ask((m, a) async => 'nope'), isNull);
        expect(await ask((m, a) async => {'entries': 'nope'}), isNull);
        expect(await ask((m, a) async => throw StateError('channel')), isNull);
      },
    );
  });
}
