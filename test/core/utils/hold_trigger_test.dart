import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/hold_trigger.dart';

void main() {
  test('does not fire before the duration elapses', () {
    fakeAsync((async) {
      var fired = 0;
      final hold = HoldTrigger(
        duration: const Duration(seconds: 3),
        onComplete: () => fired++,
      );

      hold.start();
      async.elapse(const Duration(seconds: 2));

      expect(fired, 0);
      hold.dispose();
    });
  });

  test('fires exactly once at the full duration', () {
    fakeAsync((async) {
      var fired = 0;
      final hold = HoldTrigger(
        duration: const Duration(seconds: 3),
        onComplete: () => fired++,
      );

      hold.start();
      async.elapse(const Duration(seconds: 3));

      expect(fired, 1);
      hold.dispose();
    });
  });

  test('cancel before the duration elapses prevents firing', () {
    fakeAsync((async) {
      var fired = 0;
      final hold = HoldTrigger(
        duration: const Duration(seconds: 3),
        onComplete: () => fired++,
      );

      hold.start();
      async.elapse(const Duration(seconds: 2));
      hold.cancel();
      async.elapse(const Duration(seconds: 5));

      expect(fired, 0);
      hold.dispose();
    });
  });

  test('a second start() restarts the clock rather than stacking', () {
    fakeAsync((async) {
      var fired = 0;
      final hold = HoldTrigger(
        duration: const Duration(seconds: 3),
        onComplete: () => fired++,
      );

      hold.start();
      async.elapse(const Duration(seconds: 2));
      hold.start(); // restart: 2s of progress should be discarded
      async.elapse(const Duration(seconds: 2));

      expect(fired, 0); // only 2s since the restart, not 4s total

      async.elapse(const Duration(seconds: 1));
      expect(fired, 1);

      hold.dispose();
    });
  });

  test('holding well past the duration only fires once', () {
    fakeAsync((async) {
      var fired = 0;
      final hold = HoldTrigger(
        duration: const Duration(seconds: 3),
        onComplete: () => fired++,
      );

      hold.start();
      async.elapse(const Duration(seconds: 10));

      expect(fired, 1);
      hold.dispose();
    });
  });

  test('dispose after firing does not throw and does not fire again', () {
    fakeAsync((async) {
      var fired = 0;
      final hold = HoldTrigger(
        duration: const Duration(seconds: 3),
        onComplete: () => fired++,
      );

      hold.start();
      async.elapse(const Duration(seconds: 3));
      hold.dispose();
      async.elapse(const Duration(seconds: 3));

      expect(fired, 1);
    });
  });

  test('cancel without a prior start is a no-op', () {
    fakeAsync((async) {
      var fired = 0;
      final hold = HoldTrigger(
        duration: const Duration(seconds: 3),
        onComplete: () => fired++,
      );

      expect(() => hold.cancel(), returnsNormally);
      async.elapse(const Duration(seconds: 5));
      expect(fired, 0);

      hold.dispose();
    });
  });
}
