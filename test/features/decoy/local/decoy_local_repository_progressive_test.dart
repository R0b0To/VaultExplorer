import 'dart:io';

import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/listing_job.dart';
import 'package:vaultexplorer/core/utils/natural_sort.dart';
import 'package:vaultexplorer/core/utils/perf_trace.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';

/// Always shows a partial as soon as there are enough entries, so a test does
/// not depend on how fast the disk is.
const _eager = ProgressiveListingConfig(
  schedule: <Duration>[Duration.zero, Duration.zero],
  minPartialEntries: 500,
);

void main() {
  const repo = DecoyLocalRepository();
  late Directory root;

  Directory makeFolder(String name, {int files = 0, int dirs = 0}) {
    final dir = Directory('${root.path}/$name')..createSync();
    for (var i = 0; i < files; i++) {
      File('${dir.path}/IMG_${i + 1}.jpg').writeAsStringSync('x' * (i % 7));
    }
    for (var i = 0; i < dirs; i++) {
      Directory('${dir.path}/Folder $i').createSync();
    }
    return dir;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('progressive_listing');
    DecoyLocalRepository.clearCache();
    PerfTrace.reset();
    PerfTrace.sink = (_) {};
    VeLog.enabled = true;
  });

  tearDown(() {
    VeLog.enabled = false;
    PerfTrace.reset();
    DecoyLocalRepository.clearCache();
    root.deleteSync(recursive: true);
  });

  bool inOrder(List<RawEntry> entries) {
    // Folders first, then files, each in natural-name order.
    var seenFile = false;
    RawEntry? previous;
    for (final e in entries) {
      if (!e.isDir) seenFile = true;
      if (e.isDir && seenFile) return false;
      if (previous != null &&
          previous.isDir == e.isDir &&
          naturalCompare(previous.lowercaseName, e.lowercaseName) > 0) {
        return false;
      }
      previous = e;
    }
    return true;
  }

  group('listDirectoryProgressive', () {
    test('the finished listing is exactly what listDirectory returns', () async {
      final dir = makeFolder('mixed', files: 40, dirs: 5);

      final oneShot = await repo.listDirectory(dir.path, refresh: true);
      final progressive = await repo
          .listDirectoryProgressive(dir.path, refresh: true)
          .result;

      expect(progressive, isNotNull);
      expect(RawEntry.sameEntries(progressive!, oneShot), isTrue);
      expect(inOrder(progressive), isTrue);
    });

    test('a folder read quickly is never shown in part', () async {
      final dir = makeFolder('small', files: 300);
      var partials = 0;
      final entries = await repo
          .listDirectoryProgressive(
            dir.path,
            refresh: true,
            onPartial: (_) => partials++,
          )
          .result;
      expect(entries, hasLength(300));
      expect(partials, 0);
    });

    test('partials are sorted, grow, and are subsets of the final listing', () async {
      final dir = makeFolder('big', files: 6000, dirs: 40);
      final partials = <List<RawEntry>>[];
      final job = repo.listDirectoryProgressive(
        dir.path,
        refresh: true,
        config: _eager,
        onPartial: partials.add,
      );
      final entries = await job.result;

      expect(entries, hasLength(6040));
      expect(partials, isNotEmpty);
      final finalNames = {for (final e in entries!) e.name};
      var previousLength = 0;
      for (final partial in partials) {
        expect(partial.length, greaterThanOrEqualTo(500));
        expect(partial.length, greaterThan(previousLength));
        expect(partial.length, lessThanOrEqualTo(entries.length));
        expect(inOrder(partial), isTrue);
        expect(partial.every((e) => finalNames.contains(e.name)), isTrue);
        previousLength = partial.length;
      }
      expect(inOrder(entries), isTrue);
    });

    test('a cached folder returns at once, with no partials', () async {
      final dir = makeFolder('cached', files: 2500);
      final first = await repo
          .listDirectoryProgressive(dir.path, refresh: true, config: _eager)
          .result;

      var partials = 0;
      final second = await repo
          .listDirectoryProgressive(
            dir.path,
            config: _eager,
            onPartial: (_) => partials++,
          )
          .result;

      expect(identical(first, second), isTrue);
      expect(partials, 0);
      expect(PerfTrace.counterFor('local.list.cache_hit'), 1);
    });

    test('refresh: true re-reads even when the folder is cached', () async {
      final dir = makeFolder('refresh', files: 50);
      await repo.listDirectoryProgressive(dir.path).result;
      File('${dir.path}/new_file.txt').writeAsStringSync('hi');
      final again = await repo
          .listDirectoryProgressive(dir.path, refresh: true)
          .result;
      expect(again!.any((e) => e.name == 'new_file.txt'), isTrue);
    });

    test('a missing folder lists as empty', () async {
      final entries = await repo
          .listDirectoryProgressive('${root.path}/nope', refresh: true)
          .result;
      expect(entries, isEmpty);
    });
  });

  group('cancelling', () {
    test('after the first partial: no more partials, null result, nothing cached', () async {
      final dir = makeFolder('cancel', files: 30000);
      var partials = 0;
      late final ListingJob<List<RawEntry>> job;
      job = repo.listDirectoryProgressive(
        dir.path,
        refresh: true,
        config: _eager,
        onPartial: (_) {
          partials++;
          job.cancel();
        },
      );
      expect(await job.result, isNull);
      final seen = partials;
      expect(seen, 1);

      // Give the worker time to notice and stop; nothing more may arrive.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(partials, seen);

      // The cut-short run was not remembered: the next listing is a miss.
      final before = PerfTrace.counterFor('local.list.cache_hit');
      final full = await repo.listDirectoryProgressive(dir.path).result;
      expect(full, hasLength(30000));
      expect(PerfTrace.counterFor('local.list.cache_hit'), before);
    });

    test('immediately, before the worker has started', () async {
      final dir = makeFolder('early', files: 2000);
      var partials = 0;
      final job = repo.listDirectoryProgressive(
        dir.path,
        refresh: true,
        config: _eager,
        onPartial: (_) => partials++,
      );
      job.cancel();
      expect(await job.result, isNull);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(partials, 0);
    });

    test('cancelling twice, or after completion, is harmless', () async {
      final dir = makeFolder('twice', files: 10);
      final job = repo.listDirectoryProgressive(dir.path, refresh: true);
      final entries = await job.result;
      expect(entries, hasLength(10));
      job.cancel();
      job.cancel();
      expect(job.isCancelled, isTrue);
    });
  });
}
