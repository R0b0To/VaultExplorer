import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.cachePath);
  final String cachePath;

  @override
  Future<String?> getApplicationCachePath() async => cachePath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory thumbsDir;
  late PathProviderPlatform originalPlatform;

  // ThumbnailCacheService._getAppCacheRoot() resolves getApplicationCache-
  // Directory() exactly once and caches the Future in a static field for
  // the rest of the process's life -- so unlike discrete_mode_repository_
  // test.dart's per-test setUp, this fakes PathProviderPlatform ONCE for
  // the whole file (setUpAll). Re-pointing it per-test wouldn't work here:
  // only the very first call across the whole file would actually take
  // effect. Every test instead shares one temp root and only the "thumbs"
  // subdirectory enforceDiskBudget operates on is reset between tests.
  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('thumbnail_disk_budget_test_');
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDownAll(() {
    PathProviderPlatform.instance = originalPlatform;
    tempDir.deleteSync(recursive: true);
  });

  setUp(() {
    thumbsDir = Directory('${tempDir.path}/thumbs');
    if (thumbsDir.existsSync()) thumbsDir.deleteSync(recursive: true);
    thumbsDir.createSync(recursive: true);
  });

  File writeFile(String name, int sizeBytes, DateTime modified) {
    final file = File('${thumbsDir.path}/$name');
    file.writeAsBytesSync(List.filled(sizeBytes, 0));
    file.setLastModifiedSync(modified);
    return file;
  }

  Set<String> remainingNames() => thumbsDir
      .listSync()
      .map((e) => e.path.substring(thumbsDir.path.length + 1))
      .toSet();

  test('does nothing when the thumbs directory does not exist yet', () async {
    thumbsDir.deleteSync(recursive: true);

    await ThumbnailCacheService.enforceDiskBudget(1000);

    expect(thumbsDir.existsSync(), isFalse);
  });

  test('deletes nothing when total size is already under budget', () async {
    writeFile('a.jpg', 100, DateTime(2026, 1, 1));
    writeFile('b.jpg', 100, DateTime(2026, 1, 2));

    await ThumbnailCacheService.enforceDiskBudget(1000);

    expect(remainingNames(), {'a.jpg', 'b.jpg'});
  });

  test(
    'evicts oldest-first down to 80% of budget when over budget',
    () async {
      // 5 files at 100 bytes = 500 total. Budget 300 -> target is 80% of
      // that, 240. Deleting the 3 oldest (300 bytes) brings the running
      // total to 200, which is <= 240, so the loop stops there -- matches
      // enforceDiskBudget's own targetBytes/sort-by-modified/delete-
      // oldest-until-under-target algorithm exactly.
      writeFile('1-oldest.jpg', 100, DateTime(2026, 1, 1));
      writeFile('2.jpg', 100, DateTime(2026, 1, 2));
      writeFile('3.jpg', 100, DateTime(2026, 1, 3));
      writeFile('4.jpg', 100, DateTime(2026, 1, 4));
      writeFile('5-newest.jpg', 100, DateTime(2026, 1, 5));

      await ThumbnailCacheService.enforceDiskBudget(300);

      expect(remainingNames(), {'4.jpg', '5-newest.jpg'});
    },
  );

  test(
    'a .tmp file is never counted toward the budget, so it alone never '
    'triggers an eviction pass',
    () async {
      // Deliberately far larger than the budget -- if .tmp files counted
      // toward totalBytes this would trigger eviction (and, having no
      // other files, would have nothing eligible to evict anyway); the
      // real point is that enforceDiskBudget returns early via
      // `totalBytes <= maxBytes` without ever touching this file, rather
      // than counting it and then skipping it during the eviction loop.
      writeFile('in-progress.jpg.tmp', 10000, DateTime(2026, 1, 1));

      await ThumbnailCacheService.enforceDiskBudget(50);

      expect(remainingNames(), {'in-progress.jpg.tmp'});
    },
  );
}
