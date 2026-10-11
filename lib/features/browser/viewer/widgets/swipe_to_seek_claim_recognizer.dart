import 'package:flutter/gestures.dart';

const double _seekGestureThreshold = 12.0;

/// Claims a clearly horizontal seek drag after a short movement threshold.
class SwipeToSeekClaimRecognizer extends HorizontalDragGestureRecognizer {
  SwipeToSeekClaimRecognizer({
    required this.canClaim,
    Set<PointerDeviceKind>? supportedDevices,
  }) : super(
         supportedDevices:
             supportedDevices ??
             const {
               PointerDeviceKind.touch,
               PointerDeviceKind.mouse,
               PointerDeviceKind.stylus,
               PointerDeviceKind.trackpad,
             },
       ) {
    onStart = (_) {};
  }

  final bool Function() canClaim;
  final Map<int, Offset> _movementByPointer = {};

  @override
  bool isPointerAllowed(PointerEvent event) =>
      canClaim() && super.isPointerAllowed(event);

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _movementByPointer[event.pointer] = Offset.zero;
    } else if (event is PointerMoveEvent) {
      final movement = (_movementByPointer[event.pointer] ?? Offset.zero) +
          event.delta;
      _movementByPointer[event.pointer] = movement;

      final dx = movement.dx.abs();
      final dy = movement.dy.abs();
      if (dx >= _seekGestureThreshold && dx > dy * 1.2) {
        resolve(GestureDisposition.accepted);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _movementByPointer.remove(event.pointer);
    }

    super.handleEvent(event);
  }

  void abort() => resolve(GestureDisposition.rejected);
}
