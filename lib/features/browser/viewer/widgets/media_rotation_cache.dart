import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/utils/lru_cache.dart';


class MediaRotationCache {
  MediaRotationCache._();
  static final _cache = LruCache<String, int>(2000);

  static String _key(MountedContainer container, String filePath) =>
      '${container.uri}:$filePath';

  static int? get(MountedContainer container, String filePath) =>
      _cache[_key(container, filePath)];

  static void put(MountedContainer container, String filePath, int quarterTurns) {
    _cache[_key(container, filePath)] = quarterTurns % 4;
  }

  static void clear() => _cache.clear();
}
