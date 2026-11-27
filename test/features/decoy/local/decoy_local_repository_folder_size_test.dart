import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';

void main() {
  group('DecoyLocalRepository folder size', () {
    const repo = DecoyLocalRepository();
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('decoy_folder_size_');
      await File('${root.path}/a.bin').writeAsBytes(List.filled(1000, 1));
      await Directory('${root.path}/sub/deeper').create(recursive: true);
      await File('${root.path}/sub/b.bin').writeAsBytes(List.filled(250, 2));
      await File(
        '${root.path}/sub/deeper/c.bin',
      ).writeAsBytes(List.filled(4096, 3));
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('folderSize adds up every file under the folder, however deep', () async {
      expect(await repo.folderSize(root.path), 5346);
      expect(await repo.folderSize('${root.path}/sub'), 4346);
    });

    test('folderSizeJob completes with the same total', () async {
      final job = repo.folderSizeJob(root.path);

      expect(await job.result, 5346);
      expect(job.isCancelled, isFalse);
    });

    test('a folder that does not exist, or holds no files, counts as zero', () async {
      final empty = await Directory('${root.path}/empty').create();

      expect(await repo.folderSize('${root.path}/missing'), 0);
      expect(await repo.folderSize(empty.path), 0);
      expect(await repo.folderSizeJob('${root.path}/missing').result, 0);
    });

    test('a job cancelled at once completes with null, not a partial total', () async {
      final job = repo.folderSizeJob(root.path)..cancel();

      expect(await job.result, isNull);
      expect(job.isCancelled, isTrue);

      // Cancelling again, after it has finished, is harmless.
      job.cancel();
      expect(await job.result, isNull);
    });
  });
}
