import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Session-lived cache of each media file's *true* content aspect ratio
/// (width / height), as reported directly by native -- from
/// `getImageThumbnailWithSize` / `getVideoThumbnailWithSize` (see
/// [ThumbnailWithSize]) while a thumbnail is made, or from
/// `probeImageDimensions` (headers only, no decode) ahead of time. Never
/// decoded on the Dart side.
///
/// The gallery lays a folder out from these, so a ratio that is missing is a
/// tile that will change shape later. That is why this is sized for whole
/// folders, not for what fits on screen: the old 2,000-entry LRU evicted the
/// start of a 5,000-photo folder while you were still scrolling its end, so
/// every trip back up re-learned (and re-shuffled) everything.
///
/// Stored per container, then per directory, then by file name -- the shape the
/// gallery asks in ([lookupIn]) -- so reading a whole directory back does not
/// build a path string per file. Keyed by `container.uri` (not the volume slot)
/// so a ratio survives lock/unlock of the same vault.
///
/// Memory only: nothing about a vault's content is written anywhere, so the
/// "thumbnail cache disabled" privacy mode stays honest.
class MediaAspectRatioCache {
  MediaAspectRatioCache._();

  /// Per container. ~100 bytes an entry, so a full cache is on the order of
  /// 10 MB, released as soon as the vault is closed ([clearForUri]).
  static const int maxEntriesPerContainer = 120000;

  static final Map<String, _ContainerRatios> _byUri = {};

  static double? get(MountedContainer container, String filePath) =>
      _getByPath(container.uri, filePath);

  /// A lookup for the files directly inside [dirPath] ("" = the container's
  /// root, or a view whose entry names already are full paths, like the
  /// category views). Returns the ratio of `dirPath/name`, or null.
  static double? Function(String name) lookupIn(
    MountedContainer container,
    String dirPath,
  ) {
    final uri = container.uri;
    if (dirPath.isEmpty) return (name) => _getByPath(uri, name);
    return (name) {
      if (name.contains('/')) return _getByPath(uri, '$dirPath/$name');
      return _byUri[uri]?.dirs[dirPath]?[name];
    };
  }

  static void put(
    MountedContainer container,
    String filePath,
    int width,
    int height,
  ) {
    if (width <= 0 || height <= 0) return;
    final ratio = width / height;
    final slash = filePath.lastIndexOf('/');
    final dir = slash < 0 ? '' : filePath.substring(0, slash);
    final name = slash < 0 ? filePath : filePath.substring(slash + 1);

    final c = _byUri.putIfAbsent(container.uri, _ContainerRatios.new);
    final names = c.dirs.putIfAbsent(dir, () => <String, double>{});
    if (names[name] == null) c.count++;
    names[name] = ratio;
    if (c.count > maxEntriesPerContainer) {
      c.evict(maxEntriesPerContainer * 9 ~/ 10, keepDir: dir);
    }
  }

  static void clear() => _byUri.clear();

  static void clearForUri(String uri) => _byUri.remove(uri);

  static double? _getByPath(String uri, String filePath) {
    final c = _byUri[uri];
    if (c == null) return null;
    final slash = filePath.lastIndexOf('/');
    if (slash < 0) return c.dirs['']?[filePath];
    return c.dirs[filePath.substring(0, slash)]?[filePath.substring(slash + 1)];
  }
}

class _ContainerRatios {
  /// Insertion-ordered, so the oldest directories are evicted first.
  final Map<String, Map<String, double>> dirs = {};
  int count = 0;

  /// Drops the oldest directories until at most [keep] entries remain, never
  /// the one being filled right now ([keepDir]).
  void evict(int keep, {required String keepDir}) {
    final doomed = <String>[];
    var remaining = count;
    for (final entry in dirs.entries) {
      if (remaining <= keep) break;
      if (entry.key == keepDir) continue;
      doomed.add(entry.key);
      remaining -= entry.value.length;
    }
    for (final key in doomed) {
      dirs.remove(key);
    }
    count = remaining;
  }
}
