import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/tools/models/storage_tree.dart';

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

/// root
///  ├─ docs/        report.pdf (300), notes.txt (50)
///  ├─ media/       clip.mp4 (5000), photos/ a.jpg (700), b.png (200)
///  ├─ empty/
///  └─ readme (10)
StorageTree _sample() {
  final root = StorageNode.dir(name: '', path: '');
  final docs = _d(root, 'docs');
  _f(docs, 'report.pdf', 300, mtime: 100);
  _f(docs, 'notes.txt', 50, mtime: 200);
  final media = _d(root, 'media');
  _f(media, 'clip.mp4', 5000, mtime: 300);
  final photos = _d(media, 'photos');
  _f(photos, 'a.jpg', 700, mtime: 400);
  _f(photos, 'b.png', 200, mtime: 150);
  _d(root, 'empty');
  _f(root, 'readme', 10);
  root.recomputeTotals();
  return StorageTree(root: root);
}

void main() {
  group('StorageCategory.of', () {
    test('classifies by extension, case-insensitively', () {
      expect(StorageCategory.of('a.JPG'), StorageCategory.images);
      expect(StorageCategory.of('clip.mkv'), StorageCategory.videos);
      expect(StorageCategory.of('song.flac'), StorageCategory.audio);
      expect(StorageCategory.of('doc.pdf'), StorageCategory.documents);
      expect(StorageCategory.of('x.7z'), StorageCategory.archives);
    });

    test('no extension, trailing dot, or unknown extension is other', () {
      expect(StorageCategory.of('readme'), StorageCategory.other);
      expect(StorageCategory.of('weird.'), StorageCategory.other);
      expect(StorageCategory.of('data.bin'), StorageCategory.other);
    });
  });

  group('totals', () {
    test('folders carry exact recursive size and file count', () {
      final t = _sample();
      expect(t.totalBytes, 300 + 50 + 5000 + 700 + 200 + 10);
      expect(t.fileCount, 6);
      expect(t.find('media')!.sizeBytes, 5900);
      expect(t.find('media/photos')!.fileCount, 2);
      expect(t.find('empty')!.sizeBytes, 0);
    });

    test('children are sorted largest first', () {
      final t = _sample();
      expect(t.root.children.map((c) => c.name).toList(), [
        'media',
        'docs',
        'readme',
        'empty',
      ]);
    });

    test('a folder takes its newest file as modified time', () {
      final t = _sample();
      expect(t.find('media')!.modifiedSecs, 400);
      expect(t.find('docs')!.modifiedSecs, 200);
    });

    test('isEmptyFolder is true only when no file is beneath', () {
      final t = _sample();
      expect(t.find('empty')!.isEmptyFolder, isTrue);
      expect(t.find('docs')!.isEmptyFolder, isFalse);
      expect(t.find('readme')!.isEmptyFolder, isFalse);
    });
  });

  group('find', () {
    test('resolves nested paths, root, and misses', () {
      final t = _sample();
      expect(t.find('')!.path, '');
      expect(t.find('media/photos/a.jpg')!.sizeBytes, 700);
      expect(t.find('media/nope'), isNull);
      expect(t.find('readme/child'), isNull);
    });
  });

  group('largestFiles', () {
    test('returns the top N largest first', () {
      final t = _sample();
      final top = t.largestFiles(3).map((f) => f.name).toList();
      expect(top, ['clip.mp4', 'a.jpg', 'report.pdf']);
    });

    test('limit larger than file count returns all', () {
      expect(_sample().largestFiles(100), hasLength(6));
    });

    test('limit zero is empty and where filters', () {
      final t = _sample();
      expect(t.largestFiles(0), isEmpty);
      final images = t.largestFiles(
        10,
        where: (f) => f.category == StorageCategory.images,
      );
      expect(images.map((f) => f.name).toList(), ['a.jpg', 'b.png']);
    });
  });

  group('categoryTotals', () {
    test('sums bytes and counts per bucket', () {
      final totals = _sample().categoryTotals();
      expect(totals[StorageCategory.images]!.bytes, 900);
      expect(totals[StorageCategory.images]!.count, 2);
      expect(totals[StorageCategory.videos]!.bytes, 5000);
      expect(totals[StorageCategory.documents]!.bytes, 350);
      expect(totals[StorageCategory.other]!.bytes, 10);
      expect(totals.containsKey(StorageCategory.audio), isFalse);
    });

    test('categoryTotalsOf limits to one subtree', () {
      final t = _sample();
      final totals = StorageTree.categoryTotalsOf(t.find('media/photos')!);
      expect(totals[StorageCategory.images]!.bytes, 900);
      expect(totals.containsKey(StorageCategory.videos), isFalse);
    });
  });

  group('remove', () {
    test('subtracts from every ancestor and detaches', () {
      final t = _sample();
      final clip = t.find('media/clip.mp4')!;
      expect(t.remove(clip), isTrue);
      expect(t.find('media/clip.mp4'), isNull);
      expect(t.find('media')!.sizeBytes, 900);
      expect(t.totalBytes, 300 + 50 + 700 + 200 + 10);
      expect(t.fileCount, 5);
      expect(clip.parent, isNull);
    });

    test('re-ranks siblings after a size change', () {
      final t = _sample();
      // media (5900) outranks docs (350); removing clip makes media 900.
      t.remove(t.find('media/clip.mp4')!);
      expect(t.root.children.first.name, 'media'); // 900 > 350 still
      t.remove(t.find('media/photos')!);
      // media is now empty (0) and must sink below docs and readme.
      expect(t.root.children.map((c) => c.name).toList(), [
        'docs',
        'readme',
        'empty',
        'media',
      ]);
    });

    test('removing a folder removes its whole weight', () {
      final t = _sample();
      t.remove(t.find('media')!);
      expect(t.totalBytes, 360);
      expect(t.fileCount, 3);
    });

    test('root and detached nodes cannot be removed', () {
      final t = _sample();
      expect(t.remove(t.root), isFalse);
      final clip = t.find('media/clip.mp4')!;
      t.remove(clip);
      expect(t.remove(clip), isFalse);
    });

    test('folder timestamp follows the newest remaining file', () {
      final t = _sample();
      t.remove(t.find('media/clip.mp4')!); // mtime 300
      expect(t.find('media')!.modifiedSecs, 400);
      t.remove(t.find('media/photos/a.jpg')!); // mtime 400
      expect(t.find('media')!.modifiedSecs, 150);
    });
  });

  group('replace', () {
    test('swaps a subtree and adjusts ancestors by the difference', () {
      final t = _sample();
      final old = t.find('docs')!;
      final fresh = StorageNode.dir(name: 'docs', path: 'docs');
      fresh.addChild(
        StorageNode.file(
          name: 'report.pdf',
          path: 'docs/report.pdf',
          sizeBytes: 9000,
        ),
      );
      fresh.recomputeTotals();
      expect(t.replace(old, fresh), isTrue);
      expect(t.find('docs')!.sizeBytes, 9000);
      expect(t.totalBytes, 9000 + 5000 + 700 + 200 + 10);
      expect(t.root.children.first.name, 'docs');
      expect(fresh.parent, same(t.root));
      expect(old.parent, isNull);
    });

    test('refuses to replace the root or a stranger', () {
      final t = _sample();
      final stranger = StorageNode.dir(name: 'x', path: 'x');
      expect(t.replace(t.root, stranger), isFalse);
      expect(
        t.replace(stranger, StorageNode.dir(name: 'x', path: 'x')),
        isFalse,
      );
    });
  });

  group('resolveSelection', () {
    test('sums bytes, files and folders', () {
      final t = _sample();
      final s = t.resolveSelection(['docs', 'media/clip.mp4']);
      expect(s.nodes, hasLength(2));
      expect(s.bytes, 350 + 5000);
      expect(s.files, 3);
      expect(s.folders, 1);
      expect(s.hasFolder, isTrue);
    });

    test('a selected folder swallows selected descendants', () {
      final t = _sample();
      final s = t.resolveSelection([
        'media',
        'media/clip.mp4',
        'media/photos/a.jpg',
      ]);
      expect(s.nodes.map((n) => n.path).toList(), ['media']);
      expect(s.bytes, 5900); // not double counted
      expect(s.files, 3);
    });

    test('ignores the root, unknown paths and duplicates', () {
      final t = _sample();
      final s = t.resolveSelection(['', 'ghost/file', 'readme', 'readme']);
      expect(s.nodes.map((n) => n.path).toList(), ['readme']);
    });

    test('empty selection is the shared empty value', () {
      final s = _sample().resolveSelection(const []);
      expect(s.isEmpty, isTrue);
      expect(s.bytes, 0);
    });

    test('a path that vanished is dropped, not an error', () {
      final t = _sample();
      t.remove(t.find('readme')!);
      expect(t.resolveSelection(['readme']).isEmpty, isTrue);
    });
  });

  group('StorageSort', () {
    List<String> order(StorageSort sort) {
      final kids = _sample().root.children.toList()..sort(sort.compare);
      return kids.map((c) => c.name).toList();
    }

    test('size is biggest first', () {
      expect(order(StorageSort.size), ['media', 'docs', 'readme', 'empty']);
    });

    test('name puts folders first, then A-Z', () {
      expect(order(StorageSort.name), ['docs', 'empty', 'media', 'readme']);
    });

    test('files is most files first, size breaking ties', () {
      expect(order(StorageSort.files), ['media', 'docs', 'readme', 'empty']);
    });

    test('date is newest first, undated last', () {
      // media 400, docs 200, readme/empty undated (size breaks that tie)
      expect(order(StorageSort.date), ['media', 'docs', 'readme', 'empty']);
    });
  });

  group('isComplete', () {
    test('false when truncated, unreadable or incomplete', () {
      final root = StorageNode.dir(name: '', path: '');
      expect(StorageTree(root: root).isComplete, isTrue);
      expect(StorageTree(root: root, truncated: true).isComplete, isFalse);
      expect(StorageTree(root: root, unreadableDirs: 1).isComplete, isFalse);
      expect(StorageTree(root: root, incompleteDirs: 2).isComplete, isFalse);
    });
  });
}
