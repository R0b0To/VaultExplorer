import 'package:test/test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';

MountedContainer _c(String uri) => MountedContainer(
  uri: uri,
  displayName: uri,
  volId: 1,
  rootFiles: const [],
  mountedAt: DateTime(2026),
  totalSpace: 0,
  freeSpace: 0,
);

void main() {
  final a = _c('content://vault/a');
  final b = _c('content://vault/b');

  test('get and put by full path, and the per-directory lookup agree', () {
    MediaAspectRatioCache.clear();
    MediaAspectRatioCache.put(a, 'Photos/2024/x.jpg', 400, 300);
    expect(MediaAspectRatioCache.get(a, 'Photos/2024/x.jpg'), 400 / 300);
    expect(MediaAspectRatioCache.lookupIn(a, 'Photos/2024')('x.jpg'), 400 / 300);
    expect(MediaAspectRatioCache.lookupIn(a, 'Photos/2024')('y.jpg'), null);
    expect(MediaAspectRatioCache.get(b, 'Photos/2024/x.jpg'), null);
  });

  test('root-level files and views whose names are full paths', () {
    MediaAspectRatioCache.clear();
    MediaAspectRatioCache.put(a, 'root.png', 100, 200);
    MediaAspectRatioCache.put(a, 'deep/dir/pic.png', 300, 100);
    expect(MediaAspectRatioCache.lookupIn(a, '')('root.png'), 0.5);
    // Category views pass the full path as the entry name with an empty dir.
    expect(MediaAspectRatioCache.lookupIn(a, '')('deep/dir/pic.png'), 3.0);
    // And a nested name under a non-empty dir still resolves.
    expect(MediaAspectRatioCache.lookupIn(a, 'deep')('dir/pic.png'), 3.0);
  });

  test('ignores invalid sizes and clears per container', () {
    MediaAspectRatioCache.clear();
    MediaAspectRatioCache.put(a, 'bad.jpg', 0, 10);
    MediaAspectRatioCache.put(a, 'bad2.jpg', 10, -1);
    expect(MediaAspectRatioCache.get(a, 'bad.jpg'), null);
    expect(MediaAspectRatioCache.get(a, 'bad2.jpg'), null);
    MediaAspectRatioCache.put(a, 'k.jpg', 1, 1);
    MediaAspectRatioCache.put(b, 'k.jpg', 2, 1);
    MediaAspectRatioCache.clearForUri(a.uri);
    expect(MediaAspectRatioCache.get(a, 'k.jpg'), null);
    expect(MediaAspectRatioCache.get(b, 'k.jpg'), 2.0);
  });

  test('holds a whole large folder, and evicts old directories first', () {
    MediaAspectRatioCache.clear();
    for (var i = 0; i < 50000; i++) {
      MediaAspectRatioCache.put(a, 'big/$i.jpg', 4, 3);
    }
    // Far beyond the old 2,000-entry LRU, nothing lost.
    expect(MediaAspectRatioCache.get(a, 'big/0.jpg'), 4 / 3);
    expect(MediaAspectRatioCache.get(a, 'big/49999.jpg'), 4 / 3);

    MediaAspectRatioCache.clear();
    MediaAspectRatioCache.put(a, 'old/1.jpg', 1, 1);
    for (var i = 0; i < MediaAspectRatioCache.maxEntriesPerContainer; i++) {
      MediaAspectRatioCache.put(a, 'new/$i.jpg', 1, 1);
    }
    expect(MediaAspectRatioCache.get(a, 'old/1.jpg'), null);
    expect(MediaAspectRatioCache.get(a, 'new/${MediaAspectRatioCache.maxEntriesPerContainer - 1}.jpg'), 1.0);
  });
}
