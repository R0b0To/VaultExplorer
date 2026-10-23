import 'package:flutter/physics.dart' show Simulation;
import 'package:flutter/widgets.dart';

/// A switch that decides, touch by touch, whether a pager may be swiped.
///
/// It is a plain mutable object so flipping it never rebuilds anything: the
/// owner sets [locked] when a touch lands, and [GatedPageScrollPhysics] reads it
/// while that touch drags the pager and when it lets go.
class PagerSwipeGate {
  /// While true, swiping the pager moves nothing and letting go settles it back
  /// on the page it was on.
  bool locked = false;
}

/// [PageScrollPhysics] that obey a [PagerSwipeGate].
///
/// While the gate is locked, a drag does not move the pager and a fling does
/// not carry it to the next page. The pager still takes part in the gesture, so
/// the touch is swallowed rather than handed on, which is the point: a swipe
/// that is not allowed to change tabs should do nothing at all.
///
/// A [PageView] puts its own page-snapping physics outermost, ahead of any it is
/// given, so the fling could not be gated from inside it. Use this with
/// `pageSnapping: false`; it snaps to pages itself.
class GatedPageScrollPhysics extends PageScrollPhysics {
  const GatedPageScrollPhysics({super.parent, required this.gate});

  final PagerSwipeGate gate;

  @override
  GatedPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return GatedPageScrollPhysics(parent: buildParent(ancestor), gate: gate);
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (gate.locked) return 0.0;
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // With no velocity the pager settles on the nearest page, which is the one
    // it never left.
    return super.createBallisticSimulation(
      position,
      gate.locked ? 0.0 : velocity,
    );
  }
}
