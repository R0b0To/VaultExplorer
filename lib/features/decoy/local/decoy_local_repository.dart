import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';

/// Real, on-disk file operations for the decoy's local storage explorer.
///
/// This intentionally never touches the vault engine APIs, vault containers,
/// or any encryption code -- everything here operates on plain phone
/// storage through `dart:io`, the same way the existing decoy archive
/// screen already reads Downloads for zip files. It exists so the decoy
/// can offer a genuine, fully-functional file manager for real device
/// storage, reusing [RawEntry] -- the same directory-entry value type the
/// vault file manager's list/sort/selection widgets already work with --
/// without pulling any of the vault machinery into the decoy.
class DecoyLocalRepository {
  const DecoyLocalRepository();

  /// Resolves the true public storage root (e.g. `/storage/emulated/0`),
  /// independent of Android version/OEM quirks -- same approach the decoy
  /// archive screen already uses to find Downloads, generalized to return
  /// the root itself rather than joining `Download` onto it.
  Future<Directory> primaryRoot() async {
    try {
      final appExternal = await getExternalStorageDirectory();
      if (appExternal == null) {
        return Directory('/storage/emulated/0');
      }
      var dir = appExternal;
      while (dir.path.isNotEmpty && p.basename(dir.path) != 'Android') {
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      return p.basename(dir.path) == 'Android' ? dir.parent : appExternal;
    } catch (_) {
      return Directory('/storage/emulated/0');
    }
  }

  /// Lists the immediate children of [path] as [RawEntry] values, sourced
  /// straight from `dart:io` stats -- no wire-format parsing needed since
  /// there's no native backend in between for plain local files.
  ///
  /// Entries that can't be stat'd (permission-denied system folders,
  /// broken symlinks, races with a concurrent delete elsewhere) are
  /// skipped rather than failing the whole listing, mirroring how the
  /// decoy archive screen already tolerates a failed Downloads scan.
  Future<List<RawEntry>> listDirectory(String path) async {
    final dir = Directory(path);
    final out = <RawEntry>[];
    if (!await dir.exists()) return out;
    try {
      await for (final item in dir.list(followLinks: false)) {
        try {
          final stat = await item.stat();
          final isDir = stat.type == FileSystemEntityType.directory;
          out.add(RawEntry(
            name: p.basename(item.path),
            isDir: isDir,
            sizeBytes: isDir ? 0 : stat.size,
            modifiedSecs: stat.modified.millisecondsSinceEpoch ~/ 1000,
          ));
        } catch (_) {
          continue;
        }
      }
    } catch (_) {
      // Unreadable directory or stream error mid-listing
    }
    return out;
  }

  /// Recursive byte total for a folder -- used for the selection summary
  /// only when the user is looking at a small enough selection that this
  /// is worth computing; unreadable subtrees are skipped rather than
  /// aborting the whole count.
  Future<int> folderSize(String path) async {
    int total = 0;
    try {
      await for (final entity in Directory(path).list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // Unreadable file mid-tree -- keep counting the rest.
          }
        }
      }
    } catch (_) {
      // Unreadable subtree -- return whatever was counted so far.
    }
    return total;
  }

  Future<Directory> createFolder(String parentPath, String desiredName) async {
    final name = desiredName.trim();
    if (name.isEmpty) {
      throw ArgumentError('Folder name cannot be empty');
    }
    var dir = Directory(p.join(parentPath, name));
    var suffix = 1;
    while (await dir.exists()) {
      dir = Directory(p.join(parentPath, '$name ($suffix)'));
      suffix++;
    }
    return dir.create(recursive: false);
  }

  /// Renames the file/folder at [path] to [newName], staying in the same
  /// parent directory. Throws [StateError] if something with that name
  /// already exists there.
  Future<String> rename(String path, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Name cannot be empty');
    }
    final parent = p.dirname(path);
    final target = p.join(parent, trimmed);
    if (await FileSystemEntity.type(target) != FileSystemEntityType.notFound) {
      throw StateError('"$trimmed" already exists here');
    }
    final isDir = await FileSystemEntity.isDirectory(path);
    final entity = isDir ? Directory(path) : File(path);
    final renamed = await entity.rename(target);
    return renamed.path;
  }

  Future<void> delete(String path) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }

  /// Copies [sourcePath] (file or folder, recursively) into [destDirPath],
  /// auto-renaming with a `(1)`, `(2)`, … suffix on a name collision.
  /// Returns the final path it was copied to.
  Future<String> copyInto(String sourcePath, String destDirPath) async {
    final name = await _uniqueName(destDirPath, p.basename(sourcePath));
    final destPath = p.join(destDirPath, name);
    final type = await FileSystemEntity.type(sourcePath);
    if (type == FileSystemEntityType.directory) {
      await _copyDirRecursive(Directory(sourcePath), Directory(destPath));
    } else {
      await File(sourcePath).copy(destPath);
    }
    return destPath;
  }

  /// Moves [sourcePath] into [destDirPath]. Tries a same-volume rename
  /// first (instant); falls back to copy-then-delete for cross-volume
  /// moves (e.g. internal storage → SD card), which `rename()` can't do.
  Future<String> moveInto(String sourcePath, String destDirPath) async {
    final name = await _uniqueName(destDirPath, p.basename(sourcePath));
    final destPath = p.join(destDirPath, name);
    try {
      final type = await FileSystemEntity.type(sourcePath);
      final entity = type == FileSystemEntityType.directory ? Directory(sourcePath) : File(sourcePath);
      final moved = await entity.rename(destPath);
      return moved.path;
    } on FileSystemException {
      final copiedPath = await copyInto(sourcePath, destDirPath);
      await delete(sourcePath);
      return copiedPath;
    }
  }

  Future<void> _copyDirRecursive(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(followLinks: false)) {
      final newPath = p.join(dst.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirRecursive(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  Future<String> _uniqueName(String destDir, String name) async {
    if (await FileSystemEntity.type(p.join(destDir, name)) == FileSystemEntityType.notFound) {
      return name;
    }
    final ext = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    var i = 1;
    while (true) {
      final candidate = '$base ($i)$ext';
      if (await FileSystemEntity.type(p.join(destDir, candidate)) == FileSystemEntityType.notFound) {
        return candidate;
      }
      i++;
    }
  }
}
