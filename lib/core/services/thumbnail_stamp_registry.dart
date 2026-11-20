import 'dart:collection';

import 'package:vaultexplorer/core/utils/raw_entry.dart';

/// The size and modified time each file had the last time a directory listing
/// reported it.
///
/// A cached thumbnail is only as good as the file it was made from. The cache
/// key used to be just the path, so a file replaced under the same name --
/// pasted over, imported over, or changed by another app while the vault was
/// closed -- kept showing its old thumbnail. Directory listings already carry
/// each file's size and modified time, so the listing layer records them here
/// and the thumbnail cache folds them into its keys: a changed file simply
/// misses the cache and is thumbnailed again.
///
/// No lookup ever costs a native call. Whatever a tile is about to ask the
/// cache for was listed a moment earlier, which is when its stamp was
/// recorded.
class ThumbnailStampRegistry {
  ThumbnailStampRegistry._();

  /// Most files remembered at once. The oldest records go first; a file that
  /// has none falls back to a path-only key (see [segmentFor]).
  static const int maxEntries = 100000;

  static final LinkedHashMap<String, (int size, int modifiedSecs)> _stamps =
      LinkedHashMap<String, (int, int)>();

  static String _key(String uri, String path) => '$uri\u0000$path';

  /// Paths are compared the way listings build them: `dir/name`, with no
  /// leading slash (the root is the empty string).
  static String normalizePath(String path) {
    var start = 0;
    while (start < path.length && path.codeUnitAt(start) == 0x2F) {
      start++;
    }
    return start == 0 ? path : path.substring(start);
  }

  static String _join(String dirPath, String name) {
    final dir = normalizePath(dirPath);
    if (dir.isEmpty) return name;
    return dir.endsWith('/') ? '$dir$name' : '$dir/$name';
  }

  /// Records one file. Returns true when the file was already known with a
  /// *different* stamp, i.e. its content changed since it was last listed.
  static bool record(String uri, String path, int size, int modifiedSecs) {
    if (size < 0) return false;
    final key = _key(uri, normalizePath(path));
    final previous = _stamps.remove(key);
    _stamps[key] = (size, modifiedSecs < 0 ? 0 : modifiedSecs);
    if (_stamps.length > maxEntries) {
      _stamps.remove(_stamps.keys.first);
    }
    return previous != null &&
        (previous.$1 != size || previous.$2 != modifiedSecs);
  }

  /// Records every plain file of a wire-format listing of [dirPath] (see
  /// [RawEntry]). Directories, symbolic links and `System:*` lines are
  /// skipped. Returns the full paths of files whose stamp changed.
  static List<String> recordWire(
    String uri,
    String dirPath,
    Iterable<String> rawList,
  ) {
    List<String>? changed;
    for (final line in rawList) {
      if (!line.startsWith('F|')) continue;
      final sizeEnd = line.indexOf('|', 2);
      if (sizeEnd < 0) continue;
      final timeEnd = line.indexOf('|', sizeEnd + 1);
      if (timeEnd < 0) continue;
      final size = int.tryParse(line.substring(2, sizeEnd));
      final secs = int.tryParse(line.substring(sizeEnd + 1, timeEnd));
      if (size == null || secs == null) continue;
      final path = _join(dirPath, line.substring(timeEnd + 1));
      if (record(uri, path, size, secs)) (changed ??= <String>[]).add(path);
    }
    return changed ?? const <String>[];
  }

  /// [recordWire] for entries that are already parsed.
  static List<String> recordEntries(
    String uri,
    String dirPath,
    Iterable<RawEntry> entries,
  ) {
    List<String>? changed;
    for (final e in entries) {
      if (e.isDir || e.isSymlink || e.isPlaceholder) continue;
      final path = _join(dirPath, e.name);
      if (record(uri, path, e.sizeBytes, e.modifiedSecs)) {
        (changed ??= <String>[]).add(path);
      }
    }
    return changed ?? const <String>[];
  }

  /// The piece of a cache key that ties a thumbnail to the file's current
  /// content, or null when the file was never listed (the key then stays
  /// path-only, exactly as before).
  static String? segmentFor(String uri, String path) {
    final s = _stamps[_key(uri, normalizePath(path))];
    return s == null ? null : '@${s.$1}.${s.$2}';
  }

  /// Forgets everything recorded for one container.
  static void forgetContainer(String uri) {
    final prefix = '$uri\u0000';
    _stamps.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Forgets one file.
  static void forget(String uri, String path) =>
      _stamps.remove(_key(uri, normalizePath(path)));

  static int get length => _stamps.length;

  static void clearForTesting() => _stamps.clear();
}
