import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/gestures.dart';

/// Claims a vertical drag that starts on a brightness/volume edge strip,
/// resolving eagerly in the gesture arena before parent scrollables can claim it.
class EdgeSwipeClaimRecognizer extends VerticalDragGestureRecognizer {
  EdgeSwipeClaimRecognizer({required this.canClaim})
    : super(supportedDevices: const {PointerDeviceKind.touch}) {
    onStart = (_) {};
  }

  final bool Function() canClaim;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      canClaim() && super.isPointerAllowed(event);

  @override
  void handleEvent(PointerEvent event) {
    // Eagerly resolve as accepted once vertical movement begins on the edge,
    // locking out ancestor scrollables before touch-slop is crossed.
    if (event is PointerMoveEvent) {
      final dy = event.delta.dy.abs();
      final dx = event.delta.dx.abs();
      if (dy > dx && dy > 2.0) {
        resolve(GestureDisposition.accepted);
      }
    }
    super.handleEvent(event);
  }

  void abort() => resolve(GestureDisposition.rejected);
}