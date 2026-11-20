import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/services/category_media_index_api.dart';
import 'package:vaultexplorer/features/browser/services/category_walk_policy.dart';
import 'package:vaultexplorer/features/browser/services/device_category_index.dart';
import 'package:vaultexplorer/features/browser/services/device_category_index_store.dart';

RawEntry _e(String path, [int size = 1, int modified = 1]) =>
    RawEntry(name: path, isDir: false, sizeBytes: size, modifiedSecs: modified);

bool _isImage(String n) => n.endsWith('.jpg') || n.endsWith('.png');
bool _isHidden(String n) => n.startsWith('.');

const _key = DeviceCategoryIndexKey(
  rootPath: '/storage/emulated/0',
  categoryKey: 'gallery',
  showHidden: false,
);

/// A reversible stand-in for AES: XOR with a byte. A different [secret] on
/// the way back models a key that was wiped and regenerated.
IndexBytesTransform _xor(int secret) =>
    (data) async => Uint8List.fromList([for (final b in data) b ^ secret]);

void main() {
  late Directory dir;
  late DeviceCategoryIndexStore store;

  DeviceCategoryIndexStore storeWith({
    int encryptKey = 0x5a,
    int decryptKey = 0x5a,
  }) => DeviceCategoryIndexStore(
    directory: () async => dir,
    encrypt: _xor(encryptKey),
    decrypt: _xor(decryptKey),
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('device_index_test');
    dir = Directory('${dir.path}/idx'); // not created yet: save must create it
    store = storeWith();
  });

  tearDown(() async {
    final parent = dir.parent;
    if (await parent.exists()) await parent.delete(recursive: true);
  });

  group('DeviceCategoryIndexStore', () {
    test('what is saved is what is loaded', () async {
      await store.save('k', [_e('DCIM/a.jpg', 10, 20), _e('b.png', 30, 40)]);
      final loaded = (await store.load('k'))!;
      expect(loaded.map((e) => e.name), ['DCIM/a.jpg', 'b.png']);
      expect(loaded.map((e) => e.sizeBytes), [10, 30]);
      expect(loaded.map((e) => e.modifiedSecs), [20, 40]);
    });

    test('nothing is readable as plain text on disk', () async {
      await store.save('k', [_e('Secret Folder/private photo.jpg')]);
      final bytes = await dir
          .list()
          .where((f) => f is File)
          .cast<File>()
          .first
          .then((f) => f.readAsBytes());
      final text = String.fromCharCodes(bytes);
      expect(text, isNot(contains('Secret Folder')));
      expect(text, isNot(contains('private photo')));
    });

    test(
      'a different key cannot read the file, and the file is dropped',
      () async {
        await store.save('k', [_e('a.jpg')]);
        final wrong = storeWith(decryptKey: 0x11);
        expect(await wrong.load('k'), isNull);
        // It was unreadable, so it was removed rather than retried forever.
        expect(await store.load('k'), isNull);
      },
    );

    test('a corrupt file is treated as missing', () async {
      await store.save('k', [_e('a.jpg')]);
      final file = await dir.list().where((f) => f is File).cast<File>().first;
      await file.writeAsBytes([1, 2, 3, 4, 5]);
      expect(await store.load('k'), isNull);
    });

    test('keys do not mix: each has its own file', () async {
      await store.save('one', [_e('1.jpg')]);
      await store.save('two', [_e('2.jpg')]);
      expect((await store.load('one'))!.single.name, '1.jpg');
      expect((await store.load('two'))!.single.name, '2.jpg');
      expect(await store.load('three'), isNull);
    });

    test('file names are stable and filesystem-safe', () {
      final a = DeviceCategoryIndexStore.fileNameForKey(
        'gallery|0|/storage/emulated/0',
      );
      expect(
        a,
        DeviceCategoryIndexStore.fileNameForKey(
          'gallery|0|/storage/emulated/0',
        ),
      );
      expect(RegExp(r'^[0-9a-f]{16}\.idx$').hasMatch(a), isTrue);
      expect(
        a,
        isNot(
          DeviceCategoryIndexStore.fileNameForKey(
            'gallery|1|/storage/emulated/0',
          ),
        ),
      );
    });

    test('a name with a line break is not stored, the others are', () async {
      await store.save('k', [
        _e('good.jpg'),
        _e('bad\nname.jpg'),
        _e('also good.jpg'),
      ]);
      expect((await store.load('k'))!.map((e) => e.name), [
        'good.jpg',
        'also good.jpg',
      ]);
    });

    test('names with pipes and unicode survive', () async {
      await store.save('k', [_e('a|b.jpg'), _e('日本語/写真.jpg')]);
      expect((await store.load('k'))!.map((e) => e.name), [
        'a|b.jpg',
        '日本語/写真.jpg',
      ]);
    });

    test('clear removes everything', () async {
      await store.save('k', [_e('a.jpg')]);
      await store.clear();
      expect(await store.load('k'), isNull);
      expect(await dir.exists(), isFalse);
    });

    test('a large list round-trips', () async {
      final big = [
        for (var i = 0; i < 20000; i++) _e('DCIM/Camera/IMG_$i.jpg', i, i),
      ];
      await store.save('k', big);
      final loaded = (await store.load('k'))!;
      expect(loaded, hasLength(20000));
      expect(loaded.last.name, 'DCIM/Camera/IMG_19999.jpg');
      // Repetitive paths compress well: far below the plain-text size.
      final onDisk = await dir
          .list()
          .where((f) => f is File)
          .cast<File>()
          .first
          .then((f) => f.length());
      expect(onDisk, lessThan(20000 * 25));
    });
  });

  group('DeviceCategoryIndex', () {
    CategoryMediaIndexApi api(
      Future<Object?> Function(String, Map<String, Object?>) fn,
    ) => CategoryMediaIndexApi(fn);

    Future<dynamic> lookup(
      DeviceCategoryIndex index, {
      bool showHidden = false,
    }) => index.lookup(
      DeviceCategoryIndexKey(
        rootPath: '/r',
        categoryKey: 'gallery',
        showHidden: showHidden,
      ),
      extensions: const ['jpg', 'png'],
      matches: _isImage,
      isHidden: _isHidden,
      skipDirectory: skipDeviceCategoryFolder,
    );

    test('seed is empty at first, then what was remembered', () async {
      final index = DeviceCategoryIndex();
      expect(await index.seed(_key), isNull);
      await index.remember(_key, [_e('a.jpg')]);
      expect((await index.seed(_key))!.single.name, 'a.jpg');
    });

    test(
      'a new instance reads it back from disk: it survives a restart',
      () async {
        await DeviceCategoryIndex(
          store: store,
        ).remember(_key, [_e('a.jpg', 5, 6)]);
        final next = DeviceCategoryIndex(store: store);
        final seed = (await next.seed(_key))!;
        expect(seed.single.name, 'a.jpg');
        expect(seed.single.sizeBytes, 5);
      },
    );

    test(
      'keys are separate: another category, root or hidden setting is a miss',
      () async {
        final index = DeviceCategoryIndex(store: store);
        await index.remember(_key, [_e('a.jpg')]);
        expect(
          await index.seed(
            const DeviceCategoryIndexKey(
              rootPath: '/storage/emulated/0',
              categoryKey: 'images',
              showHidden: false,
            ),
          ),
          isNull,
        );
        expect(
          await index.seed(
            const DeviceCategoryIndexKey(
              rootPath: '/sdcard',
              categoryKey: 'gallery',
              showHidden: false,
            ),
          ),
          isNull,
        );
        expect(
          await index.seed(
            const DeviceCategoryIndexKey(
              rootPath: '/storage/emulated/0',
              categoryKey: 'gallery',
              showHidden: true,
            ),
          ),
          isNull,
        );
      },
    );

    test(
      'remembering an empty list forgets, so a stale list does not return',
      () async {
        final index = DeviceCategoryIndex(store: store);
        await index.remember(_key, [_e('a.jpg')]);
        await index.remember(_key, const []);
        expect(await index.seed(_key), isNull);
        expect(await DeviceCategoryIndex(store: store).seed(_key), isNull);
      },
    );

    test('an unchanged list is not written again, a changed one is', () async {
      var writes = 0;
      final counting = DeviceCategoryIndexStore(
        directory: () async => dir,
        encrypt: (d) async {
          writes++;
          return d;
        },
        decrypt: (d) async => d,
      );
      final index = DeviceCategoryIndex(store: counting);
      await index.remember(_key, [_e('a.jpg'), _e('b.jpg')]);
      expect(writes, 1);
      // Same files, found in another order: still the same result.
      await index.remember(_key, [_e('b.jpg'), _e('a.jpg')]);
      expect(writes, 1);
      await index.remember(_key, [_e('a.jpg'), _e('b.jpg', 99)]);
      expect(writes, 2);
    });

    test('a store that fails never breaks the scan', () async {
      final broken = DeviceCategoryIndexStore(
        directory: () async => throw const FileSystemException('no disk'),
        encrypt: (d) async => d,
        decrypt: (d) async => d,
      );
      final index = DeviceCategoryIndex(store: broken);
      await index.remember(_key, [_e('a.jpg')]); // must not throw
      expect(
        (await index.seed(_key))!.single.name,
        'a.jpg',
      ); // memory still works
    });

    test('clear forgets memory and disk', () async {
      final index = DeviceCategoryIndex(store: store);
      await index.remember(_key, [_e('a.jpg')]);
      await index.clear();
      expect(await index.seed(_key), isNull);
      expect(await DeviceCategoryIndex(store: store).seed(_key), isNull);
    });

    test('lookup is null without a platform index', () async {
      expect(await lookup(DeviceCategoryIndex()), isNull);
    });

    test('lookup filters the rows with the walk rules', () async {
      final index = DeviceCategoryIndex(
        media: api(
          (m, a) async => {
            'entries': [
              'F|1|1|DCIM/a.jpg',
              'F|1|1|DCIM/notes.txt',
              'F|1|1|.hidden/h.jpg',
              'F|1|1|Android/data/x/d.jpg',
              'F|1|1|Pictures/cache/c.jpg',
            ],
          },
        ),
      );
      final hit = await lookup(index);
      expect((hit.entries as List<RawEntry>).map((e) => e.name), [
        'DCIM/a.jpg',
      ]);
      expect(hit.limitReached, isFalse);
    });

    test('lookup is skipped while hidden files are shown', () async {
      var asked = false;
      final index = DeviceCategoryIndex(
        media: api((m, a) async {
          asked = true;
          return {
            'entries': ['F|1|1|a.jpg'],
          };
        }),
      );
      expect(await lookup(index, showHidden: true), isNull);
      expect(asked, isFalse);
    });

    test('an empty index answer means "walk", not "nothing here"', () async {
      final index = DeviceCategoryIndex(
        media: api((m, a) async => {'entries': <String>[]}),
      );
      expect(await lookup(index), isNull);
    });

    test('everything filtered away also means "walk"', () async {
      final index = DeviceCategoryIndex(
        media: api(
          (m, a) async => {
            'entries': ['F|1|1|Android/data/x/d.jpg'],
          },
        ),
      );
      expect(await lookup(index), isNull);
    });

    test('a failing index means "walk"', () async {
      final index = DeviceCategoryIndex(
        media: api((m, a) async => throw StateError('x')),
      );
      expect(await lookup(index), isNull);
    });

    test(
      'over the limit the list is cut and flagged; exactly the limit is not',
      () async {
        Future<dynamic> run(int n, {bool truncated = false}) => lookup(
          DeviceCategoryIndex(
            maxResults: 3,
            media: api(
              (m, a) async => {
                'entries': [for (var i = 0; i < n; i++) 'F|1|1|p$i.jpg'],
                'truncated': truncated,
              },
            ),
          ),
        );
        final over = await run(4);
        expect((over.entries as List).length, 3);
        expect(over.limitReached, isTrue);
        final exact = await run(3);
        expect((exact.entries as List).length, 3);
        expect(exact.limitReached, isFalse);
        final flagged = await run(3, truncated: true);
        expect(flagged.limitReached, isTrue);
      },
    );

    test('asks the platform for one more than the limit', () async {
      Map<String, Object?>? args;
      final index = DeviceCategoryIndex(
        maxResults: 50,
        media: api((m, a) async {
          args = a;
          return {
            'entries': ['F|1|1|a.jpg'],
          };
        }),
      );
      await lookup(index);
      expect(args!['limit'], 51);
      expect(args!['rootPath'], '/r');
    });
  });
}
