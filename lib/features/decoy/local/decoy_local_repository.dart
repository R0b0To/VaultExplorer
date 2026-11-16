import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/core/utils/perf_trace.dart';
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

  // Recently listed folders, least recently used first. This used to be a
  // single slot, so going from folder A to B and back to A listed A again
  // from scratch (a new isolate plus a stat per file). Entries are only
  // reused while the folder's own modification time is unchanged -- adding,
  // removing or renaming a child updates it -- and for at most [_cacheTtl],
  // which bounds how long an in-place change to a file's size can go unseen.
  static final LinkedHashMap<String, _CachedListing> _cache =
      LinkedHashMap<String, _CachedListing>();
  static const int _cacheMaxFolders = 16;
  static const _cacheTtl = Duration(seconds: 15);

  /// Clears the in-memory cache of directory listings.
  static void clearCache() {
    _cache.clear();
  }

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
  Future<List<RawEntry>> listDirectory(String path, {bool refresh = false}) async {
    final perfT0 = PerfTrace.begin();
    final cached = _cache.remove(path);
    if (!refresh && cached != null) {
      // One stat of the folder itself decides whether the cached listing is
      // still good; far cheaper than listing and stat'ing every child again.
      final age = DateTime.now().difference(cached.cachedAt);
      if (age < _cacheTtl) {
        final modified = await _folderModified(path);
        if (modified != null && modified == cached.folderModified) {
          _cache[path] = cached; // re-insert: most recently used
          PerfTrace.count('local.list.cache_hit');
          PerfTrace.end('local.list.cached', perfT0);
          return cached.entries;
        }
      }
    }
    PerfTrace.count('local.list.cache_miss');

    // Stat the folder *before* listing it: a change that lands while the
    // listing runs then leaves a newer mtime on disk than the one remembered,
    // so the next lookup re-lists instead of trusting a half-old result.
    final folderModified = await _folderModified(path);
    final out = await Isolate.run(() => _listDirectorySync(path));
    PerfTrace.end('local.list.isolate', perfT0, slowMs: 150);

    final result = List<RawEntry>.unmodifiable(out);
    if (folderModified != null) {
      _cache[path] = _CachedListing(result, folderModified, DateTime.now());
      while (_cache.length > _cacheMaxFolders) {
        _cache.remove(_cache.keys.first);
      }
    }

    return result;
  }

  /// The folder's own last-modified time, or null when it cannot be read.
  static Future<DateTime?> _folderModified(String path) async {
    try {
      final stat = await FileStat.stat(path);
      return stat.type == FileSystemEntityType.notFound ? null : stat.modified;
    } catch (_) {
      return null;
    }
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
    clearCache();
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

  Future<String> rename(String path, String newName) async {
    clearCache();
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
    clearCache();
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }

  Future<String> copyInto(String sourcePath, String destDirPath) async {
    clearCache();
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

  Future<String> moveInto(String sourcePath, String destDirPath) async {
    clearCache();
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

List<RawEntry> _listDirectorySync(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return <RawEntry>[];
  final entries = <RawEntry>[];
  try {
    final items = dir.listSync(followLinks: false);
    for (final item in items) {
      try {
        if (item is Directory) {
          int modifiedSecs = 0;
          try {
            final stat = item.statSync();
            modifiedSecs = stat.modified.millisecondsSinceEpoch ~/ 1000;
          } catch (_) {
            // Folder metadata is optional; keep the entry with modifiedSecs 0
            // if stat fails because of permissions or a concurrent filesystem change.
          }
          final name = _baseName(item.path);
          final lower = name.toLowerCase();
          entries.add(RawEntry(
            name: name,
            isDir: true,
            sizeBytes: 0,
            modifiedSecs: modifiedSecs,
            lowercaseName: lower,
            extension: '',
          ));
        } else if (item is File) {
          final stat = item.statSync();
          final name = _baseName(item.path);
          final lower = name.toLowerCase();
          final dot = lower.lastIndexOf('.');
          final ext = dot < 0 ? '' : lower.substring(dot + 1);
          entries.add(RawEntry(
            name: name,
            isDir: false,
            sizeBytes: stat.size,
            modifiedSecs: stat.modified.millisecondsSinceEpoch ~/ 1000,
            lowercaseName: lower,
            extension: ext,
          ));
        }
      } catch (_) {
        continue;
      }
    }
  } catch (_) {
    // Unreadable directory or stream error mid-listing
  }
  return entries;
}

/// Last path segment of an entry returned by `Directory.listSync`.
///
/// Those paths are always `<directory>/<name>` with `/` separators on Android,
/// so cutting after the last `/` is exact and avoids `package:path`'s full
/// parse of every entry (a listing of thousands of files called it once each).
String _baseName(String path) => path.substring(path.lastIndexOf('/') + 1);

class _CachedListing {
  _CachedListing(this.entries, this.folderModified, this.cachedAt);

  final List<RawEntry> entries;
  final DateTime folderModified;
  final DateTime cachedAt;
}
