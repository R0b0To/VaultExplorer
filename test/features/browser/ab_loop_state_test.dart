import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/models/ab_loop_state.dart';

void main() {
  const duration = Duration(minutes: 2);

  group('AbLoopState.advance', () {
    test('first press marks A at the current position', () {
      final result = AbLoopState.empty.advance(
        const Duration(seconds: 12),
        duration,
      );
      expect(result.event, AbLoopEvent.startMarked);
      expect(result.state.a, const Duration(seconds: 12));
      expect(result.state.b, isNull);
      expect(result.state.isPending, isTrue);
      expect(result.state.isActive, isFalse);
    });

    test('second press marks B and starts the loop', () {
      const pending = AbLoopState(a: Duration(seconds: 12));
      final result = pending.advance(const Duration(seconds: 30), duration);
      expect(result.event, AbLoopEvent.loopStarted);
      expect(result.state.a, const Duration(seconds: 12));
      expect(result.state.b, const Duration(seconds: 30));
      expect(result.state.isActive, isTrue);
    });

    test('third press clears the loop', () {
      const active = AbLoopState(
        a: Duration(seconds: 12),
        b: Duration(seconds: 30),
      );
      final result = active.advance(const Duration(seconds: 20), duration);
      expect(result.event, AbLoopEvent.cleared);
      expect(result.state.isEmpty, isTrue);
    });

    test('B before A is rejected and A is kept', () {
      const pending = AbLoopState(a: Duration(seconds: 30));
      final result = pending.advance(const Duration(seconds: 10), duration);
      expect(result.event, AbLoopEvent.endTooClose);
      expect(result.state, pending);
    });

    test('B closer to A than the minimum length is rejected', () {
      const pending = AbLoopState(a: Duration(seconds: 30));
      final result = pending.advance(
        const Duration(seconds: 30, milliseconds: 200),
        duration,
      );
      expect(result.event, AbLoopEvent.endTooClose);
      expect(result.state, pending);
    });

    test('B exactly the minimum length after A is accepted', () {
      const pending = AbLoopState(a: Duration(seconds: 30));
      final result = pending.advance(
        const Duration(seconds: 30) + AbLoopState.minLength,
        duration,
      );
      expect(result.event, AbLoopEvent.loopStarted);
    });

    test('B at the very end is pulled back by the end guard', () {
      const pending = AbLoopState(a: Duration(seconds: 30));
      final result = pending.advance(duration, duration);
      expect(result.event, AbLoopEvent.loopStarted);
      expect(result.state.b, duration - AbLoopState.endGuard);
    });

    test('A past the end of a known duration is clamped to it', () {
      final result = AbLoopState.empty.advance(
        const Duration(minutes: 3),
        duration,
      );
      expect(result.state.a, duration);
    });

    test('an unknown duration applies no upper clamp', () {
      const pending = AbLoopState(a: Duration(seconds: 5));
      final result = pending.advance(
        const Duration(seconds: 50),
        Duration.zero,
      );
      expect(result.event, AbLoopEvent.loopStarted);
      expect(result.state.b, const Duration(seconds: 50));
    });

    test('a negative position is clamped to zero', () {
      final result = AbLoopState.empty.advance(
        const Duration(seconds: -1),
        duration,
      );
      expect(result.state.a, Duration.zero);
    });
  });

  group('AbLoopState equality', () {
    test('compares by both ends', () {
      expect(
        const AbLoopState(a: Duration(seconds: 1), b: Duration(seconds: 2)),
        const AbLoopState(a: Duration(seconds: 1), b: Duration(seconds: 2)),
      );
      expect(
        const AbLoopState(a: Duration(seconds: 1)),
        isNot(const AbLoopState(a: Duration(seconds: 2))),
      );
    });
  });
}
