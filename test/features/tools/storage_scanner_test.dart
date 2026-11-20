import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/tools/services/storage_scanner.dart';

/// A fake volume: directory path -> wire-format listing lines.
class _FakeVolume {
  _FakeVolume(this.dirs);
  final Map<String, List<String>?> dirs;
  final List<String> listed = [];
  final Set<String> throwOn = {};

  Future<List<String>?> list(String path) async {
    listed.add(path);
    if (throwOn.contains(path)) throw StateError('boom');
    if (!dirs.containsKey(path)) return <String>[];
    return dirs[path];
  }
}

void main() {
  test('builds a tree with exact totals from wire-format listings', () async {
    final vol = _FakeVolume({
      '': ['D|0|0|docs', 'F|10|5|readme'],
      'docs': ['F|300|7|a.pdf', 'D|0|0|sub'],
      'docs/sub': ['F|4|9|b.txt'],
    });
    final tree = await StorageScanner(listDirectory: vol.list).scan();
    expect(tree.totalBytes, 314);
    expect(tree.fileCount, 3);
    expect(tree.find('docs/sub/b.txt')!.sizeBytes, 4);
    expect(tree.find('docs')!.sizeBytes, 304);
    expect(tree.isComplete, isTrue);
  });

  test('file names containing the wire separator survive', () async {
    final vol = _FakeVolume({
      '': ['F|5|0|we|rd.txt'],
    });
    final tree = await StorageScanner(listDirectory: vol.list).scan();
    expect(tree.find('we|rd.txt')!.sizeBytes, 5);
  });

  test('an empty volume is a valid empty tree', () async {
    final tree = await StorageScanner(listDirectory: _FakeVolume({'': []}).list)
        .scan();
    expect(tree.totalBytes, 0);
    expect(tree.root.children, isEmpty);
    expect(tree.isComplete, isTrue);
  });

  test('a folder that throws is counted, not fatal', () async {
    final vol = _FakeVolume({
      '': ['D|0|0|bad', 'D|0|0|ok'],
      'ok': ['F|7|0|x.bin'],
    })..throwOn.add('bad');
    final tree = await StorageScanner(listDirectory: vol.list).scan();
    expect(tree.unreadableDirs, 1);
    expect(tree.totalBytes, 7);
    expect(tree.isComplete, isFalse);
  });

  test('a null listing is counted as unreadable', () async {
    final vol = _FakeVolume({
      '': ['D|0|0|gone'],
      'gone': null,
    });
    final tree = await StorageScanner(listDirectory: vol.list).scan();
    expect(tree.unreadableDirs, 1);
  });

  test('a malformed line no longer aborts the scan', () async {
    final vol = _FakeVolume({
      '': ['D|0|0|bad', 'F|1|0|fine'],
      'bad': ['this is not a wire string'],
    });
    final tree = await StorageScanner(listDirectory: vol.list).scan();
    expect(tree.unreadableDirs, 1);
    expect(tree.find('fine')!.sizeBytes, 1);
  });

  test(
    'System:TRUNCATED marks the tree incomplete but keeps real entries',
    () async {
      final vol = _FakeVolume({
        '': ['F|9|0|a', 'System:TRUNCATED'],
      });
      final tree = await StorageScanner(listDirectory: vol.list).scan();
      expect(tree.incompleteDirs, 1);
      expect(tree.totalBytes, 9);
      expect(tree.isComplete, isFalse);
    },
  );

  test('stops at maxEntries and says so', () async {
    final vol = _FakeVolume({
      '': [for (var i = 0; i < 10; i++) 'F|1|0|f$i'],
    });
    final tree = await StorageScanner(
      listDirectory: vol.list,
      maxEntries: 4,
    ).scan();
    expect(tree.truncated, isTrue);
    expect(tree.fileCount, 4);
  });

  test('a depth cutoff is reported rather than silently dropped', () async {
    final vol = _FakeVolume({
      '': ['D|0|0|a'],
      'a': ['D|0|0|b'],
      'a/b': ['F|1|0|deep'],
    });
    final tree = await StorageScanner(
      listDirectory: vol.list,
      maxDepth: 1,
    ).scan();
    expect(tree.truncated, isTrue);
    expect(tree.find('a/b/deep'), isNull);
  });

  test('cancellation stops the walk and marks the result truncated', () async {
    final vol = _FakeVolume({
      '': ['D|0|0|a', 'D|0|0|b'],
      'a': ['F|1|0|x'],
      'b': ['F|1|0|y'],
    });
    var calls = 0;
    final tree = await StorageScanner(
      listDirectory: vol.list,
      isCancelled: () => ++calls > 2, // allow root + first child only
    ).scan();
    expect(tree.truncated, isTrue);
    expect(vol.listed.length, lessThan(3));
  });

  test('reports progress after every folder', () async {
    final vol = _FakeVolume({
      '': ['D|0|0|a', 'F|2|0|r'],
      'a': ['F|3|0|x'],
    });
    final seen = <StorageScanProgress>[];
    await StorageScanner(listDirectory: vol.list, onProgress: seen.add).scan();
    expect(seen, hasLength(2));
    expect(seen.last.files, 2);
    expect(seen.last.bytes, 5);
    expect(seen.last.dirs, 2);
  });

  test('scanFolder rescans one subtree into a detached node', () async {
    final vol = _FakeVolume({
      'docs': ['F|50|0|n.txt', 'D|0|0|s'],
      'docs/s': ['F|5|0|z'],
    });
    final out = await StorageScanner(listDirectory: vol.list)
        .scanFolder(name: 'docs', path: 'docs');
    expect(out.node.path, 'docs');
    expect(out.node.sizeBytes, 55);
    expect(out.node.parent, isNull);
    expect(out.node.children.first.name, 'n.txt'); // largest first
    expect(vol.listed, ['docs', 'docs/s']);
  });
}
