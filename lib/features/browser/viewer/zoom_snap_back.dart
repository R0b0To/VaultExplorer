import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Friction passed to the viewers' [InteractiveViewer]s as
/// `interactionEndFrictionCoefficient`. Shared so [pinchInertiaDuration]
/// matches the value the viewer was actually built with.
const double kZoomInteractionEndFriction = 0.0005;

/// How long an [InteractiveViewer] keeps changing the zoom on its own after a
/// pinch is released.
///
/// When a pinch ends with some speed left, the viewer glides the scale on for
/// a moment (it writes the transformation every frame until it is done). An
/// animation started in `onInteractionEnd` would fight that glide and lose, so
/// a "spring back to 1x" has to wait until it is over. This mirrors the
/// viewer's own end-of-glide time (`ln(0.1 / speed) / ln(friction / 100)`) plus
/// a small margin, and is [Duration.zero] when the pinch ended without speed.
Duration pinchInertiaDuration(
  ScaleEndDetails details, {
  double friction = kZoomInteractionEndFriction,
}) {
  final speed = details.scaleVelocity.abs();
  if (speed < 0.1) return Duration.zero;
  final seconds = math.log(0.1 / speed) / math.log(friction / 100);
  if (seconds.isNaN || seconds.isInfinite || seconds <= 0) {
    return Duration.zero;
  }
  return Duration(milliseconds: (seconds * 1000).round() + 60);
}

/// Below this zoom the view counts as "zoomed out" and springs back to 1x
/// where a viewer asks for that.
const double kZoomedOutThreshold = 0.99;
