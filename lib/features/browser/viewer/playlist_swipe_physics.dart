import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kLongPressTimeout, kTouchSlop;
import 'package:flutter/physics.dart' show ScrollSpringSimulation, Simulation;
import 'package:flutter/widgets.dart';

/// Net distance, in logical pixels, that a finger has to travel along the
/// paging axis between touch-down and release for the touch to count as a swipe
/// to another item. It is deliberately close to the touch slop: the drag
/// recognizer only starts counting after the slop, so the page itself has moved
/// far less than this by the time the finger lifts.
const double kPlaylistSwipeMinDistance = 32.0;

/// How far off the paging axis the overall movement may point. The distance
/// across may be up to this many times the distance along (2.0 is about 63
/// degrees off the axis), so a diagonal or sloping swipe still counts.
const double kPlaylistSwipeMaxCrossRatio = 2.0;

/// Speed, in logical px/s, of a release against the overall direction that
/// reads as a deliberate change of mind rather than the tail of a curve.
const double kPlaylistSwipeReversalVelocity = 400.0;

/// Reads the overall movement of one touch and says whether it is a swipe to
/// the next item (`1`), to the previous item (`-1`), or neither (`0`).
///
/// [delta] is the movement from touch-down to release in global coordinates.
/// [axisDirection] is the scroll direction of the pager, which turns it into
/// movement along and across the paging axis. Only the net movement matters:
/// the path the finger took on the way, and the direction it happened to be
/// moving at the instant it lifted, are ignored. That is what lets a curved or
/// diagonal swipe count.
int playlistSwipeDirection(
  Offset delta,
  AxisDirection axisDirection, {
  double minDistance = kPlaylistSwipeMinDistance,
  double maxCrossRatio = kPlaylistSwipeMaxCrossRatio,
}) {
  // Along the axis, positive when the content is pulled toward the next item.
  final double along = switch (axisDirection) {
    AxisDirection.down => -delta.dy,
    AxisDirection.up => delta.dy,
    AxisDirection.right => -delta.dx,
    AxisDirection.left => delta.dx,
  };
  final double cross = switch (axisDirection) {
    AxisDirection.down || AxisDirection.up => delta.dx,
    AxisDirection.right || AxisDirection.left => delta.dy,
  };
  if (along.abs() < minDistance) return 0;
  if (cross.abs() > along.abs() * maxCrossRatio) return 0;
  return along > 0 ? 1 : -1;
}

/// Which item a finished touch should still switch to even though the pager
/// never took it: `1` for the next, `-1` for the previous, `0` for none.
///
/// A curved or L-shaped swipe often starts out steep, and then another
/// recognizer wins the touch before the pager does (most often the zoom
/// recognizer of the item itself, which accepts any drag after a longer
/// travel and then has nothing to pan). The pager never sees such a touch, so
/// its physics can't settle it. This judges it by its overall movement
/// instead, the way [PlaylistSwipePageScrollPhysics] does for the touches the
/// pager does take.
///
/// It declines when something else legitimately owns the touch: [isLocked]
/// (zoomed, pinching, a brightness, volume or seek drag, a page change under
/// way), [isDismissing], or a long press (the finger stayed put long enough
/// to hold the video at another speed before it moved), or when the page
/// changed while the finger was down.
int playlistSwipeFallbackDirection({
  required PlaylistSwipeSummary swipe,
  required AxisDirection axisDirection,
  required int currentIndex,
  required bool isLocked,
  required bool isDismissing,
}) {
  if (isLocked || isDismissing || swipe.heldBeforeMoving) return 0;
  if (currentIndex != swipe.startPage) return 0;
  return playlistSwipeDirection(swipe.delta, axisDirection);
}

/// The overall movement of a finished touch, and the page it began on.
class PlaylistSwipeSummary {
  const PlaylistSwipeSummary({
    required this.delta,
    required this.startPage,
    this.heldBeforeMoving = false,
  });

  /// Movement from touch-down to release, in global coordinates.
  final Offset delta;

  /// The page that was showing when the finger landed.
  final int startPage;

  /// Whether the finger stayed put for as long as a long press takes before it
  /// started to move.
  final bool heldBeforeMoving;
}

/// Records where the touch that drags the playlist pager began and ended, so
/// [PlaylistSwipePageScrollPhysics] can judge the whole swipe when it settles.
///
/// It is a plain mutable object, so updating it never rebuilds anything. The
/// owner feeds it from a raw pointer [Listener]: that sees the finger lift
/// before the drag recognizer does, which is what makes the summary available
/// to the physics in time.
class PlaylistSwipeTracker {
  Offset? _start;
  int _startPage = 0;
  Duration _startTime = Duration.zero;
  bool _movedPastSlop = false;
  bool _heldBeforeMoving = false;
  PlaylistSwipeSummary? _released;

  /// A single finger landed at [position] while [page] was showing.
  void begin(Offset position, int page, {Duration timeStamp = Duration.zero}) {
    _start = position;
    _startPage = page;
    _startTime = timeStamp;
    _movedPastSlop = false;
    _heldBeforeMoving = false;
    _released = null;
  }

  /// The finger moved to [position]. Only used to tell a long press, where the
  /// finger rests before it moves, from a swipe.
  void move(Offset position, {Duration timeStamp = Duration.zero}) {
    final start = _start;
    if (start == null || _movedPastSlop) return;
    if ((position - start).distance > kTouchSlop) {
      _movedPastSlop = true;
      _heldBeforeMoving = timeStamp - _startTime >= kLongPressTimeout;
    }
  }

  /// The finger lifted at [position]. Returns the summary of the touch, or
  /// null if no touch was being tracked.
  ///
  /// The summary is only good for the rest of the current event dispatch,
  /// which is when the pager asks for it. It is dropped right after, so a
  /// touch the pager never took part in can't leak into a later, unrelated
  /// settle such as the end of a programmatic page animation.
  PlaylistSwipeSummary? release(Offset position) {
    final start = _start;
    _start = null;
    if (start == null) return null;
    final summary = PlaylistSwipeSummary(
      delta: position - start,
      startPage: _startPage,
      heldBeforeMoving: _heldBeforeMoving,
    );
    _released = summary;
    scheduleMicrotask(() {
      if (identical(_released, summary)) _released = null;
    });
    return summary;
  }

  /// Forgets the touch: it was cancelled, or a second finger made it a pinch.
  void cancel() {
    _start = null;
    _released = null;
  }

  /// Hands over the summary of the touch that just ended, once.
  PlaylistSwipeSummary? take() {
    final summary = _released;
    _released = null;
    return summary;
  }
}

/// [PageScrollPhysics] that settle a swipe by its overall movement.
///
/// The stock page physics decide on release from two things only: whether the
/// page was dragged past halfway, and whether the horizontal speed of the last
/// instant counts as a fling. A short swipe that is diagonal, or that curves so
/// the finger is moving mostly sideways-of-the-axis when it lifts, fails both
/// tests and snaps back to the page it came from.
///
/// These physics look at the touch as a whole instead. When the net movement
/// from touch-down to release is a swipe (see [playlistSwipeDirection]) the
/// pager goes to the neighbouring page in that direction. Anything the stock
/// physics would already have done further than that, such as a fast fling
/// past the halfway point, is left alone, and a hard throw back against the
/// swipe direction still cancels it.
///
/// A [PageView] puts its own page-snapping physics outermost, ahead of any it
/// is given, so these could not take effect from inside it. Use them with
/// `pageSnapping: false`; they snap to pages themselves.
///
/// Assumes a `viewportFraction` of 1, as the viewer's pager has.
class PlaylistSwipePageScrollPhysics extends PageScrollPhysics {
  const PlaylistSwipePageScrollPhysics({super.parent, required this.tracker});

  final PlaylistSwipeTracker tracker;

  @override
  PlaylistSwipePageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return PlaylistSwipePageScrollPhysics(
      parent: buildParent(ancestor),
      tracker: tracker,
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final target = _overallSwipeTarget(position, velocity);
    if (target == null) {
      return super.createBallisticSimulation(position, velocity);
    }
    // Don't start the spring against the swipe it is about to complete.
    final towardTarget = target > position.pixels
        ? math.max(velocity, 0.0)
        : math.min(velocity, 0.0);
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      target,
      towardTarget,
      tolerance: toleranceFor(position),
    );
  }

  /// Where the page should settle (in scroll pixels) because of the overall
  /// swipe, or null to leave the settling to the stock page physics.
  double? _overallSwipeTarget(ScrollMetrics position, double velocity) {
    // Always consume the summary, so it can only ever apply to this release.
    final summary = tracker.take();
    if (summary == null) return null;

    final pageExtent = position.viewportDimension;
    if (!pageExtent.isFinite || pageExtent <= 0) return null;

    final direction = playlistSwipeDirection(
      summary.delta,
      position.axisDirection,
    );
    if (direction == 0) return null;
    // A hard throw the other way is a change of mind, not a curve in the path.
    if (velocity * direction < -kPlaylistSwipeReversalVelocity) return null;

    // The page the stock physics would pick, so a faster, longer swipe is
    // never cut short to a single page.
    final tolerance = toleranceFor(position);
    var page = position.pixels / pageExtent;
    if (velocity < -tolerance.velocity) {
      page -= 0.5;
    } else if (velocity > tolerance.velocity) {
      page += 0.5;
    }
    final stockPage = page.roundToDouble();
    final swipePage = (summary.startPage + direction).toDouble();
    final targetPage = direction > 0
        ? math.max(stockPage, swipePage)
        : math.min(stockPage, swipePage);

    final target = targetPage * pageExtent;
    // Past either end there is no page to go to: bounce back the stock way.
    if (target < position.minScrollExtent - tolerance.distance ||
        target > position.maxScrollExtent + tolerance.distance) {
      return null;
    }
    if ((target - position.pixels).abs() < tolerance.distance) return null;
    return target;
  }
}
