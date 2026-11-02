import 'package:flutter/gestures.dart';

/// Vertical travel after which a clearly vertical drag on an edge strip is
/// claimed, as a multiple of the device's touch slop. It stays below 1 so a
/// vertical scrollable around the strip, which claims after one slop, can
/// never take such a drag first. (Slop is about 8 px on Android, 18 px where
/// the platform does not say.)
const double kEdgeSwipeClaimSlopFactor = 0.75;

/// How much further a drag must have moved vertically than sideways before the
/// strip claims it. A curved or diagonal swipe that merely leans downward at
/// the start moves sideways too, so it stays unclaimed and can still change
/// the item.
const double kEdgeSwipeClaimDominance = 2.0;

/// Whether [movement], the net movement of a touch since it landed on an edge
/// strip, is a clearly vertical drag that the strip should claim. [touchSlop]
/// is the device's touch slop.
///
/// It is judged on the movement so far rather than on a single pointer event:
/// the first events of a curved or L-shaped swipe are often vertical-leaning
/// even though the swipe as a whole is not.
bool edgeSwipeClaimsMovement(Offset movement, {double touchSlop = kTouchSlop}) {
  final dx = movement.dx.abs();
  final dy = movement.dy.abs();
  return dy >= touchSlop * kEdgeSwipeClaimSlopFactor &&
      dy >= dx * kEdgeSwipeClaimDominance;
}

/// Claims a vertical drag that starts on a brightness/volume edge strip,
/// resolving in the gesture arena before parent scrollables can claim it.
class EdgeSwipeClaimRecognizer extends VerticalDragGestureRecognizer {
  EdgeSwipeClaimRecognizer({required this.canClaim})
    : super(supportedDevices: const {PointerDeviceKind.touch}) {
    onStart = (_) {};
  }

  final bool Function() canClaim;
  final Map<int, Offset> _movementByPointer = {};

  @override
  bool isPointerAllowed(PointerEvent event) =>
      canClaim() && super.isPointerAllowed(event);

  // Only [edgeSwipeClaimsMovement] decides. The stock vertical-drag test would
  // claim after 18 px of vertical travel whatever the sideways travel was.
  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => false;

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _movementByPointer[event.pointer] = Offset.zero;
    } else if (event is PointerMoveEvent) {
      final movement =
          (_movementByPointer[event.pointer] ?? Offset.zero) + event.delta;
      _movementByPointer[event.pointer] = movement;
      // Resolve as accepted once the drag is clearly vertical, locking out
      // ancestor scrollables before their touch slop is crossed.
      if (edgeSwipeClaimsMovement(
        movement,
        touchSlop: computeHitSlop(event.kind, gestureSettings),
      )) {
        resolve(GestureDisposition.accepted);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _movementByPointer.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  void abort() => resolve(GestureDisposition.rejected);
}
