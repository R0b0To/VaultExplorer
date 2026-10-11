/// What a press of the A-B repeat button did, so the viewer can say so.
enum AbLoopEvent {
  /// The loop start (A) was marked at the current position.
  startMarked,

  /// The loop end (B) was marked and the section now repeats.
  loopStarted,

  /// B was too close to A (the playhead cannot be before A once A is
  /// marked), so nothing changed.
  endTooClose,

  /// The loop was removed.
  cleared,
}

/// The A-B repeat section of the video that is currently playing.
///
/// Held in memory for one playing item only: it is dropped when the viewer
/// moves to another file, and never persisted.
///
/// Pure Dart (no Flutter imports) so the button's state machine can be
/// unit-tested on its own.
class AbLoopState {
  const AbLoopState({this.a, this.b});

  /// Where the repeated section starts, or null while no loop is being set.
  final Duration? a;

  /// Where it ends. Only ever set together with [a]; null while the person
  /// has marked A but not yet B.
  final Duration? b;

  static const AbLoopState empty = AbLoopState();

  /// Shortest section the loop accepts. Anything shorter would just stutter.
  static const Duration minLength = Duration(milliseconds: 500);

  /// How far short of the end of the video B is kept, so the jump back to A
  /// always happens while playing. Matches AB_LOOP_END_GUARD_MS in
  /// NativePlayerManager.kt, which clamps the same way on its side.
  static const Duration endGuard = Duration(milliseconds: 150);

  bool get isEmpty => a == null && b == null;

  /// A has been marked, B has not.
  bool get isPending => a != null && b == null;

  /// Both ends are set: the section is repeating.
  bool get isActive => a != null && b != null;

  /// One press of the toolbar button: mark A, then mark B (which starts the
  /// loop), then clear.
  ///
  /// [position] is where playback is right now; [duration] the length of the
  /// video, or [Duration.zero] while it is not known yet.
  ({AbLoopState state, AbLoopEvent event}) advance(
    Duration position,
    Duration duration,
  ) {
    if (isActive) {
      return (state: empty, event: AbLoopEvent.cleared);
    }

    if (isEmpty) {
      return (
        state: AbLoopState(a: _clampToVideo(position, duration)),
        event: AbLoopEvent.startMarked,
      );
    }

    final start = a!;
    var end = _clampToVideo(position, duration);
    if (duration > Duration.zero) {
      final latestEnd = duration - endGuard;
      if (end > latestEnd) end = latestEnd;
    }
    if (end - start < minLength) {
      return (state: this, event: AbLoopEvent.endTooClose);
    }
    return (
      state: AbLoopState(a: start, b: end),
      event: AbLoopEvent.loopStarted,
    );
  }

  static Duration _clampToVideo(Duration value, Duration duration) {
    if (value < Duration.zero) return Duration.zero;
    if (duration > Duration.zero && value > duration) return duration;
    return value;
  }

  @override
  bool operator ==(Object other) =>
      other is AbLoopState && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);
}
