import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/models/category_index.dart';
import 'package:vaultexplorer/features/browser/services/vault_category_index_store.dart';

/// A vault stood in for by a map of path -> bytes.
class _MemoryVault implements CategoryIndexStorage {
  _MemoryVault({this.readOnly = false});

  final bool readOnly;
  final Map<String, Uint8List> files = {};
  int writes = 0;

  @override
  Future<bool> fileExists(String dir, String name) async =>
      files.containsKey('$dir/$name');

  @override
  Future<Uint8List?> read(String path) async => files[path];

  @override
  Future<bool> write(String dir, String path, Uint8List bytes) async {
    if (readOnly) return false;
    writes++;
    files[path] = bytes;
    return true;
  }

  @override
  Future<bool> delete(String path) async {
    if (readOnly) return false;
    files.remove(path);
    return true;
  }
}

CategoryIndexSection _section(List<String> paths, {int built = 1000}) =>
    CategoryIndexSection(
      builtAtSecs: built,
      entries: [for (final p in paths) CategoryIndexEntry(p, 10, 20)],
    );

VaultCategoryIndexStore _store(_MemoryVault vault) =>
    VaultCategoryIndexStore(vault, metaDir: '.vaultexplorer');

void main() {
  group('VaultCategoryIndex', () {
    test('survives a round trip through JSON', () {
      final index = VaultCategoryIndex.empty
          .withSection('images', _section(['a.jpg', 'Trips/b.png']))
          .withSection('audio', _section(['m.mp3'], built: 5));
      final restored = VaultCategoryIndex.fromJson(
        jsonDecode(jsonEncode(index.toJson())),
      );
      expect(restored.sections.keys.toSet(), {'images', 'audio'});
      expect(restored.sections['images']!.entries.map((e) => e.path), [
        'a.jpg',
        'Trips/b.png',
      ]);
      expect(restored.sections['audio']!.builtAtSecs, 5);
    });

    test('an unknown version or shape reads as empty', () {
      expect(
        VaultCategoryIndex.fromJson({'v': 99, 'categories': {}}).sections,
        isEmpty,
      );
      expect(VaultCategoryIndex.fromJson('junk').sections, isEmpty);
      expect(VaultCategoryIndex.fromJson(null).sections, isEmpty);
    });

    test('one bad entry does not discard the rest', () {
      final restored = VaultCategoryIndex.fromJson({
        'v': 1,
        'categories': {
          'images': {
            'built': 1,
            'files': [
              ['ok.jpg', 1, 2],
              ['no-size.jpg'],
              ['', 1, 2],
              'junk',
            ],
          },
          'broken': 'x',
        },
      });
      expect(restored.sections.keys.toList(), ['images']);
      expect(restored.sections['images']!.entries, hasLength(1));
    });

    test('same-entries check ignores order and build time', () {
      expect(
        _section(['a.jpg', 'b.jpg'])
            .hasSameEntriesAs(_section(['b.jpg', 'a.jpg'], built: 9)),
        isTrue,
      );
      expect(
        _section(['a.jpg']).hasSameEntriesAs(_section(['a.jpg', 'b.jpg'])),
        isFalse,
      );
      expect(
        _section(['a.jpg']).hasSameEntriesAs(_section(['c.jpg'])),
        isFalse,
      );
    });
  });

  group('VaultCategoryIndexStore', () {
    test('has no index until something is saved', () async {
      expect((await _store(_MemoryVault()).load()).sections, isEmpty);
    });

    test('keeps the index in the vault configuration folder', () async {
      final vault = _MemoryVault();
      await _store(vault).saveSection('images', _section(['a.jpg']));
      expect(vault.files.keys, ['.vaultexplorer/category_index.json']);
    });

    test('saves a category and loads it back', () async {
      final vault = _MemoryVault();
      final store = _store(vault);
      expect(await store.saveSection('images', _section(['a.jpg'])), isTrue);
      final loaded = await store.load();
      expect(loaded.sections['images']!.entries.single.path, 'a.jpg');
    });

    test('saving one category keeps the others', () async {
      final store = _store(_MemoryVault());
      await store.saveSection('images', _section(['a.jpg']));
      await store.saveSection('audio', _section(['m.mp3']));
      final loaded = await store.load();
      expect(loaded.sections.keys.toSet(), {'images', 'audio'});
    });

    test('does not rewrite the file when nothing changed', () async {
      final vault = _MemoryVault();
      final store = _store(vault);
      await store.saveSection('images', _section(['a.jpg', 'b.jpg']));
      await store.saveSection('images', _section(['b.jpg', 'a.jpg'], built: 2));
      expect(vault.writes, 1);
      await store.saveSection('images', _section(['a.jpg']));
      expect(vault.writes, 2);
    });

    test(
      'a read-only vault can be read from but is never written to',
      () async {
        final writable = _MemoryVault();
        await _store(writable).saveSection('images', _section(['a.jpg']));
        final readOnly = _MemoryVault(readOnly: true)
          ..files.addAll(writable.files);
        final store = _store(readOnly);
        expect((await store.load()).sections['images'], isNotNull);
        expect(await store.saveSection('images', _section(['z.jpg'])), isFalse);
        expect(
          (await store.load()).sections['images']!.entries.single.path,
          'a.jpg',
        );
      },
    );

    test('a damaged file counts as no index', () async {
      final vault = _MemoryVault();
      vault.files['.vaultexplorer/category_index.json'] = Uint8List.fromList(
        utf8.encode('{not json'),
      );
      expect((await _store(vault).load()).sections, isEmpty);
      // ...and the next save replaces it.
      expect(
        await _store(vault).saveSection('images', _section(['a.jpg'])),
        isTrue,
      );
      expect((await _store(vault).load()).sections.keys, ['images']);
    });

    test('delete removes the file, and is fine when there is none', () async {
      final vault = _MemoryVault();
      final store = _store(vault);
      expect(await store.delete(), isTrue);
      await store.saveSection('images', _section(['a.jpg']));
      expect(await store.delete(), isTrue);
      expect(vault.files, isEmpty);
    });
  });
}
