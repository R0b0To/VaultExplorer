import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/tools/models/storage_cleanup.dart';
import 'package:vaultexplorer/features/tools/models/storage_tree.dart';

const _mib = 1024 * 1024;
const _now = 2000000000; // fixed "now" in unix seconds
const _year = 365 * 24 * 60 * 60;

StorageNode _f(StorageNode dir, String name, int size, {int mtime = 0}) {
  final path = dir.path.isEmpty ? name : '${dir.path}/$name';
  final n = StorageNode.file(
    name: name,
    path: path,
    sizeBytes: size,
    modifiedSecs: mtime,
  );
  dir.addChild(n);
  return n;
}

StorageNode _d(StorageNode dir, String name) {
  final path = dir.path.isEmpty ? name : '${dir.path}/$name';
  final n = StorageNode.dir(name: name, path: path);
  dir.addChild(n);
  return n;
}

CleanupSuggestion? _of(List<CleanupSuggestion> all, CleanupKind k) {
  for (final s in all) {
    if (s.kind == k) return s;
  }
  return null;
}

void main() {
  group('largeFileThreshold', () {
    test('is 2% of the volume, clamped to 5..100 MiB', () {
      expect(CleanupAnalyzer.largeFileThreshold(0), 5 * _mib);
      expect(CleanupAnalyzer.largeFileThreshold(100 * _mib), 5 * _mib);
      expect(CleanupAnalyzer.largeFileThreshold(1000 * _mib), 20 * _mib);
      expect(CleanupAnalyzer.largeFileThreshold(1 << 40), 100 * _mib);
    });
  });

  group('isTempName', () {
    test('recognises scratch and cache files', () {
      for (final n in [
        'Thumbs.db',
        'desktop.ini',
        '.DS_Store',
        'a.tmp',
        'b.TEMP',
        'file.crdownload',
        'x.part',
        '.x.swp',
        'notes.txt~',
        '.trashed-1700000000-IMG_1.jpg',
      ]) {
        expect(CleanupAnalyzer.isTempName(n), isTrue, reason: n);
      }
    });

    test('leaves real and meaningful files alone', () {
      for (final n in [
        'report.pdf',
        'tmp',
        'temp.txt',
        '.nomedia',
        'backup.bak',
        'a.tmpl',
      ]) {
        expect(CleanupAnalyzer.isTempName(n), isFalse, reason: n);
      }
    });
  });

  group('analyze', () {
    test('finds large files, largest first, using the scaled threshold', () {
      final root = StorageNode.dir(name: '', path: '');
      _f(root, 'big.mkv', 80 * _mib);
      _f(root, 'huge.mkv', 90 * _mib);
      _f(root, 'small.txt', 1 * _mib);
      root.recomputeTotals();
      // total ~171 MiB -> 2% ~3.4 MiB -> clamped to 5 MiB
      final s = _of(
        CleanupAnalyzer.analyze(StorageTree(root: root), nowSecs: _now),
        CleanupKind.largeFiles,
      )!;
      expect(s.nodes.map((n) => n.name).toList(), ['huge.mkv', 'big.mkv']);
      expect(s.bytes, 170 * _mib);
    });

    test('finds stale files only when old, sizeable and dated', () {
      final root = StorageNode.dir(name: '', path: '');
      _f(root, 'old.zip', 3 * _mib, mtime: _now - _year - 10);
      _f(root, 'recent.zip', 3 * _mib, mtime: _now - 1000);
      _f(root, 'tiny_old.txt', 100, mtime: _now - 2 * _year);
      _f(root, 'undated.bin', 3 * _mib); // mtime 0 = unknown
      root.recomputeTotals();
      final s = _of(
        CleanupAnalyzer.analyze(StorageTree(root: root), nowSecs: _now),
        CleanupKind.staleFiles,
      )!;
      expect(s.nodes.map((n) => n.name).toList(), ['old.zip']);
    });

    test('collects temp files', () {
      final root = StorageNode.dir(name: '', path: '');
      final d = _d(root, 'dl');
      _f(d, 'movie.mkv.part', 700);
      _f(d, 'Thumbs.db', 50);
      _f(d, 'keep.mkv', 900);
      root.recomputeTotals();
      final s = _of(
        CleanupAnalyzer.analyze(StorageTree(root: root), nowSecs: _now),
        CleanupKind.tempFiles,
      )!;
      expect(s.nodes.map((n) => n.name).toList(), [
        'movie.mkv.part',
        'Thumbs.db',
      ]);
      expect(s.bytes, 750);
    });

    test('reports only the topmost empty folder', () {
      final root = StorageNode.dir(name: '', path: '');
      final a = _d(root, 'a');
      _d(a, 'b');
      _d(a, 'c');
      final full = _d(root, 'full');
      _f(full, 'x', 1);
      _d(full, 'hollow');
      root.recomputeTotals();
      final s = _of(
        CleanupAnalyzer.analyze(StorageTree(root: root), nowSecs: _now),
        CleanupKind.emptyFolders,
      )!;
      expect(s.nodes.map((n) => n.path).toList(), ['a', 'full/hollow']);
      expect(s.bytes, 0);
    });

    test('never suggests protected or hidden folders', () {
      final root = StorageNode.dir(name: '', path: '');
      _d(root, 'lost+found');
      _d(root, 'System Volume Information');
      _d(root, r'$RECYCLE.BIN');
      _d(root, '.thumbnails');
      final wrapper = _d(root, 'wrapper'); // empty, but holds lost+found
      _d(wrapper, 'lost+found');
      final fine = _d(root, 'scratch');
      root.recomputeTotals();
      final s = _of(
        CleanupAnalyzer.analyze(StorageTree(root: root), nowSecs: _now),
        CleanupKind.emptyFolders,
      )!;
      expect(s.nodes.map((n) => n.path).toList(), [fine.path]);
    });

    test('omits kinds with nothing to show', () {
      final root = StorageNode.dir(name: '', path: '');
      _f(root, 'a.txt', 10);
      root.recomputeTotals();
      expect(
        CleanupAnalyzer.analyze(StorageTree(root: root), nowSecs: _now),
        isEmpty,
      );
    });

    test('caps each list at maxItemsPerKind but keeps the biggest', () {
      final root = StorageNode.dir(name: '', path: '');
      for (var i = 0; i < CleanupAnalyzer.maxItemsPerKind + 50; i++) {
        _f(root, 'f$i.tmp', i + 1);
      }
      root.recomputeTotals();
      final s = _of(
        CleanupAnalyzer.analyze(StorageTree(root: root), nowSecs: _now),
        CleanupKind.tempFiles,
      )!;
      expect(s.count, CleanupAnalyzer.maxItemsPerKind);
      expect(s.nodes.first.sizeBytes, CleanupAnalyzer.maxItemsPerKind + 50);
    });
  });
}
