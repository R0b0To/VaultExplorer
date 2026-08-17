import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';
import 'package:vaultexplorer/core/utils/retry.dart';

void main() {
  test('a successful first attempt returns immediately, with no retry',
      () {
    fakeAsync((async) {
      var calls = 0;
      int? result;
      retryWithBackoff<int>((attempt) async {
        calls++;
        return 42;
      }).then((r) => result = r);

      async.flushMicrotasks();

      expect(calls, 1);
      expect(result, 42);
    });
  });

  test('retries after transient failures and returns the eventual success',
      () {
    fakeAsync((async) {
      var calls = 0;
      int? result;
      retryWithBackoff<int>((attempt) async {
        calls++;
        if (calls < 3) throw Exception('transient failure');
        return 99;
      }).then((r) => result = r);

      async.elapse(const Duration(seconds: 10));

      expect(calls, 3);
      expect(result, 99);
    });
  });

  test('the attempt callback receives a 0-indexed attempt number', () {
    fakeAsync((async) {
      final seenAttempts = <int>[];
      retryWithBackoff<int>((attempt) async {
        seenAttempts.add(attempt);
        if (attempt < 2) throw Exception('fail');
        return 1;
      }).then((_) {});

      async.elapse(const Duration(seconds: 10));

      expect(seenAttempts, [0, 1, 2]);
    });
  });

  test('exhausting maxAttempts rethrows the last error', () {
    fakeAsync((async) {
      var calls = 0;
      Object? caughtError;
      retryWithBackoff<int>(
        (attempt) async {
          calls++;
          throw Exception('always fails');
        },
        maxAttempts: 3,
      ).catchError((e) {
        caughtError = e;
        return -1;
      });

      async.elapse(const Duration(seconds: 30));

      expect(calls, 3);
      expect(caughtError, isA<Exception>());
    });
  });

  test('delay follows exponential backoff: initialDelay, then multiplied '
      'by multiplier each subsequent attempt', () {
    fakeAsync((async) {
      final callTimes = <Duration>[];
      retryWithBackoff<int>(
        (attempt) async {
          callTimes.add(async.elapsed);
          throw Exception('fail');
        },
        maxAttempts: 4,
        initialDelay: const Duration(milliseconds: 100),
        multiplier: 2.0,
        maxDelay: const Duration(seconds: 10),
      ).catchError((_) => -1);

      async.elapse(const Duration(seconds: 5));

      expect(callTimes, [
        Duration.zero,
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 300), // 100 + 200
        const Duration(milliseconds: 700), // 300 + 400
      ]);
    });
  });

  test('the delay never exceeds maxDelay, even once the exponential curve '
      'would otherwise blow past it', () {
    fakeAsync((async) {
      final callTimes = <Duration>[];
      retryWithBackoff<int>(
        (attempt) async {
          callTimes.add(async.elapsed);
          throw Exception('fail');
        },
        maxAttempts: 3,
        initialDelay: const Duration(milliseconds: 1000),
        multiplier: 10.0,
        maxDelay: const Duration(milliseconds: 1500),
      ).catchError((_) => -1);

      async.elapse(const Duration(seconds: 10));

      expect(callTimes, [
        Duration.zero,
        const Duration(milliseconds: 1000), // initialDelay, uncapped yet
        const Duration(milliseconds: 2500), // 1000 + capped 1500, not 10000
      ]);
    });
  });

  test('retryIf returning false stops retrying immediately, without '
      'waiting out the backoff delay', () {
    fakeAsync((async) {
      var calls = 0;
      Object? caughtError;
      retryWithBackoff<int>(
        (attempt) async {
          calls++;
          throw Exception('non-retryable');
        },
        maxAttempts: 5,
        retryIf: (e) => false,
      ).catchError((e) {
        caughtError = e;
        return -1;
      });

      async.elapse(const Duration(seconds: 1));

      expect(calls, 1);
      expect(caughtError, isA<Exception>());
    });
  });

  test('retryIf returning true for some errors but not others stops at '
      'the first non-retryable error', () {
    fakeAsync((async) {
      var calls = 0;
      Object? caughtError;
      retryWithBackoff<int>(
        (attempt) async {
          calls++;
          throw calls == 1 ? 'transient' : 'fatal';
        },
        maxAttempts: 5,
        initialDelay: const Duration(milliseconds: 10),
        retryIf: (e) => e == 'transient',
      ).catchError((e) {
        caughtError = e;
        return -1;
      });

      async.elapse(const Duration(seconds: 1));

      expect(calls, 2);
      expect(caughtError, 'fatal');
    });
  });

  test('maxAttempts must be greater than zero', () {
    expect(
      retryWithBackoff<int>((attempt) async => 1, maxAttempts: 0),
      throwsA(isA<AssertionError>()),
    );
  });
}
