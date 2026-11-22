import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/engine/desktop/dropped_paths.dart';

// What a drop from the OS file manager contributes to an import. The filesystem part runs against a real
// temp directory; the Windows-only rules use a Windows path context, which is checked before anything is
// read from disk, so they run on any host.

List<String> _described(DroppedImportSet set) => [
      for (final e in set.accepted) '${p.basename(e.path)}:${e.isDir ? 'dir' : 'file'}',
    ];

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('dropped_paths_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  String makeFile(String name) {
    final f = File(p.join(tmp.path, name))..createSync(recursive: true);
    return f.path;
  }

  String makeDir(String name) {
    final d = Directory(p.join(tmp.path, name))..createSync(recursive: true);
    return d.path;
  }

  test('accepts files and folders and tells them apart', () {
    final a = makeFile('a.txt');
    final photos = makeDir('photos');

    final set = resolveDroppedPaths([a, photos]);

    expect(_described(set), equals(['a.txt:file', 'photos:dir']));
    expect(set.skipped, equals(0));
  });

  test('leaves out paths that are missing, relative, empty or repeated', () {
    final a = makeFile('a.txt');

    final set = resolveDroppedPaths([
      a,
      a, // the same path twice
      p.join(tmp.path, 'gone.txt'), // vanished
      'relative/file.txt',
      '',
    ]);

    expect(_described(set), equals(['a.txt:file']));
    expect(set.skipped, equals(4));
  });

  test('does not import a vault into itself', () {
    final vault = makeFile('vault.hc');
    final lookalike = makeFile('vault.hc.bak');
    final docs = makeDir('docs');

    // The container file itself, and the folder that contains it, are both refused ...
    expect(resolveDroppedPaths([vault], vaultHostPath: vault).accepted, isEmpty);
    final parent = resolveDroppedPaths([tmp.path], vaultHostPath: vault);
    expect(parent.accepted, isEmpty);
    expect(parent.skipped, equals(1));

    // ... but a sibling, and a path that merely starts with the same characters, are fine.
    final ok = resolveDroppedPaths([lookalike, docs], vaultHostPath: vault);
    expect(_described(ok), equals(['vault.hc.bak:file', 'docs:dir']));
    expect(ok.skipped, equals(0));
  });

  test('follows a symlink to what it points at', () {
    final target = makeFile('real.txt');
    final folder = makeDir('real_dir');
    final fileLink = p.join(tmp.path, 'file_link');
    final dirLink = p.join(tmp.path, 'dir_link');
    final broken = p.join(tmp.path, 'broken_link');
    try {
      Link(fileLink).createSync(target);
      Link(dirLink).createSync(folder);
      Link(broken).createSync(p.join(tmp.path, 'nowhere'));
    } on FileSystemException {
      return; // no symlink permission (Windows without developer mode)
    }

    final set = resolveDroppedPaths([fileLink, dirLink, broken]);

    expect(_described(set), equals(['file_link:file', 'dir_link:dir']));
    expect(set.skipped, equals(1));
  });

  test('Windows: the vault is matched ignoring case, and a drive root has no name', () {
    final windows = p.Context(style: p.Style.windows);

    final set = resolveDroppedPaths(
      [r'C:\Data\Vault.hc', r'D:\'],
      vaultHostPath: r'c:\data\vault.hc',
      context: windows,
    );

    expect(set.accepted, isEmpty);
    expect(set.skipped, equals(2));
  });
}
