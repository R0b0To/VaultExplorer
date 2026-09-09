import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';

void main() {
  group('DecoyLocalRepository Caching & Listing Tests', () {
    late Directory tempDir;
    const repo = DecoyLocalRepository();

    setUp(() async {
      DecoyLocalRepository.clearCache();
      tempDir = await Directory.systemTemp.createTemp('decoy_repo_test_');
      await Directory('${tempDir.path}/subfolder1').create();
      await Directory('${tempDir.path}/subfolder2').create();
      await File('${tempDir.path}/file1.txt').writeAsString('hello world');
    });

    tearDown(() async {
      DecoyLocalRepository.clearCache();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('listDirectory reads immediate children and recognizes directories without stat', () async {
      final entries = await repo.listDirectory(tempDir.path);
      expect(entries.length, 3);

      final folders = entries.where((e) => e.isDir).toList();
      final files = entries.where((e) => !e.isDir).toList();

      expect(folders.length, 2);
      expect(folders.map((f) => f.name), containsAll(['subfolder1', 'subfolder2']));
      expect(folders.every((f) => f.sizeBytes == 0), isTrue);

      expect(files.length, 1);
      expect(files.first.name, 'file1.txt');
      expect(files.first.sizeBytes, greaterThan(0));
    });

    test('listDirectory caches the result and returns cached list on subsequent call', () async {
      final first = await repo.listDirectory(tempDir.path);
      expect(first.length, 3);

      // Create another file on disk that wouldn't be in the cache
      await File('${tempDir.path}/file2.txt').writeAsString('second file');

      // Without refresh, cached result is returned
      final cached = await repo.listDirectory(tempDir.path);
      expect(cached.length, 3);
      expect(cached, same(first));

      // With refresh: true, cache is bypassed and updated
      final refreshed = await repo.listDirectory(tempDir.path, refresh: true);
      expect(refreshed.length, 4);
    });

    test('clearCache invalidates cached entries', () async {
      await repo.listDirectory(tempDir.path);
      DecoyLocalRepository.clearCache();

      await File('${tempDir.path}/file3.txt').writeAsString('third');
      final fresh = await repo.listDirectory(tempDir.path);
      expect(fresh.any((e) => e.name == 'file3.txt'), isTrue);
    });
  });
}
