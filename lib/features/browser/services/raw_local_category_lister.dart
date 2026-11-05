import 'dart:io';

import 'package:vaultexplorer/features/browser/services/category_scan.dart';

/// Files `stat`ted at once when a folder holds many matches.
const _statBatchSize = 32;

/// A [CategoryDirectoryLister] for plain phone storage, built for scanning
/// rather than browsing.
///
/// The general listing behind the file manager reports every entry of a
/// folder with its size and date, which costs one awaited `stat` per file and
/// per sub-folder. A category scan reads none of that for most entries: it
/// needs the names of the sub-folders to descend into, and the size and date
/// of the files that match. So this lister
///
///  - reports sub-folders by name only, without touching them,
///  - drops every file [matches] rejects before it costs anything, and
///  - `stat`s only the files that match, a few at a time.
///
/// A folder with thousands of unrelated files is then one directory read, not
/// thousands of system calls.
///
/// The `.nomedia` marker is always reported when present (see
/// [CategoryScanner.respectNoMedia]); the scanner ignores it otherwise.
///
/// [rootPath] is the absolute path of the storage; the paths the scanner
/// passes are relative to it, with '' for the root itself. A folder that
/// cannot be listed gives null.
CategoryDirectoryLister rawLocalCategoryLister({
  required String rootPath,
  required bool Function(String fileName) matches,
}) {
  final root = rootPath.length > 1 && rootPath.endsWith('/')
      ? rootPath.substring(0, rootPath.length - 1)
      : rootPath;

  return (dirPath) async {
    final path = dirPath.isEmpty ? root : '$root/$dirPath';
    final out = <String>[];
    final matching = <File>[];
    var readSomething = false;
    try {
      await for (final entity in Directory(path).list(followLinks: false)) {
        readSomething = true;
        final slash = entity.path.lastIndexOf('/');
        final name = slash < 0 ? entity.path : entity.path.substring(slash + 1);
        if (entity is Directory) {
          out.add('D|0|0|$name');
        } else if (entity is File) {
          if (name == kNoMediaMarkerName) {
            out.add('F|0|0|$name');
          } else if (matches(name)) {
            matching.add(entity);
          }
        }
      }
    } on FileSystemException {
      // Not there, not allowed, or the stream broke part-way: what was read
      // before that still counts, but a folder that gave nothing at all is
      // reported as unlistable.
      if (!readSomething) return null;
    }

    for (var i = 0; i < matching.length; i += _statBatchSize) {
      final batch = matching.skip(i).take(_statBatchSize).toList();
      final stats = await Future.wait(
        batch.map((file) async {
          try {
            return await file.stat();
          } on FileSystemException {
            return null;
          }
        }),
      );
      for (var j = 0; j < batch.length; j++) {
        final stat = stats[j];
        // A file deleted between being listed and being read is just gone.
        if (stat == null || stat.type == FileSystemEntityType.notFound) {
          continue;
        }
        final file = batch[j];
        final name = file.path.substring(file.path.lastIndexOf('/') + 1);
        final modified = stat.modified.millisecondsSinceEpoch ~/ 1000;
        out.add('F|${stat.size}|$modified|$name');
      }
    }
    return out;
  };
}
