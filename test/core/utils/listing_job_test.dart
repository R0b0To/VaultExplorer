import 'dart:async';

import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/listing_job.dart';

void main() {
  group('ListingJob', () {
    test('a completed job yields its value and ignores cancel', () async {
      final job = ListingJob<int>.completed(7);
      expect(await job.result, 7);
      job.cancel();
      expect(job.isCancelled, isTrue);
      expect(await job.result, 7);
    });

    test('cancel runs the cancel action exactly once', () {
      var cancels = 0;
      final job = ListingJob<int>(Completer<int?>().future, () => cancels++);
      expect(job.isCancelled, isFalse);
      job.cancel();
      job.cancel();
      expect(cancels, 1);
      expect(job.isCancelled, isTrue);
    });

    test('an uninterruptible job runs to the end even if cancelled', () async {
      final completer = Completer<int?>();
      final job = ListingJob<int>.uninterruptible(completer.future);
      job.cancel();
      completer.complete(5);
      expect(await job.result, 5);
    });

    test('map converts the value, keeps null, and forwards cancel', () async {
      var cancelled = false;
      final source = Completer<int?>();
      final mapped = ListingJob<int>(source.future, () => cancelled = true)
          .map((value) => 'v$value');
      source.complete(3);
      expect(await mapped.result, 'v3');

      final nullSource = Completer<int?>();
      final mappedNull = ListingJob<int>(nullSource.future, () {})
          .map((value) => 'v$value');
      nullSource.complete(null);
      expect(await mappedNull.result, isNull);

      mapped.cancel();
      expect(cancelled, isTrue);
    });

    test('map passes errors through', () async {
      final job = ListingJob<int>(
        Future<int?>.error(StateError('boom')),
        () {},
      ).map((v) => v);
      var failed = false;
      await job.result.catchError((Object _) {
        failed = true;
        return null;
      });
      expect(failed, isTrue);
    });
  });
}
