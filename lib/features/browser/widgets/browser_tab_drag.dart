import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// How far (logical pixels) a mouse has to travel with a tab held before the
/// press counts as a drag and not as a click.
///
/// The stock immediate drag recognizer starts after a single pixel for a
/// mouse, so a click with a slightly unsteady hand would turn into a drag and
/// never select the tab. A few pixels is what browsers use too.
const double kTabDragSlop = 4;

/// Starts a reorder drag of a tab as soon as the pointer has moved
/// [kTabDragSlop] while pressed, in place of
/// [ReorderableDelayedDragStartListener]'s press-and-hold.
///
/// Used for tabs on desktop. Touch and pen keep the platform's own slop, which
/// is already generous.
class BrowserTabDragStartListener extends ReorderableDragStartListener {
  const BrowserTabDragStartListener({
    super.key,
    required super.child,
    required super.index,
    super.enabled,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      _TabDragRecognizer(debugOwner: this);
}

class _TabDragRecognizer extends MultiDragGestureRecognizer {
  // Only the primary button (a finger counts as one) picks a tab up. The stock
  // filter accepts every button, so a right click that wobbled a little would
  // drag the tab and swallow its menu.
  _TabDragRecognizer({super.debugOwner})
    : super(allowedButtonsFilter: (buttons) => buttons == kPrimaryButton);

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _TabDragPointerState(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'tab drag';
}

class _TabDragPointerState extends MultiDragPointerState {
  _TabDragPointerState(
    super.initialPosition,
    super.kind,
    super.gestureSettings,
  );

  @override
  void checkForResolutionAfterMove() {
    assert(pendingDelta != null);
    final slop = kind == PointerDeviceKind.mouse
        ? kTabDragSlop
        : computeHitSlop(kind, gestureSettings);
    if (pendingDelta!.distance > slop) resolve(GestureDisposition.accepted);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    starter(initialPosition);
  }
}

/// A tab that has been pulled out of the strip, drawn floating where the
/// pointer is. Meant to be the overlay child of an [OverlayPortal], so it can
/// be drawn outside the strip's own bounds.
///
/// [topLeft] is where the ghost's top-left corner is, in window coordinates
/// (what pointer events report); the ghost draws nothing while it is null. It
/// ignores pointer events: the drag underneath it keeps receiving them.
class TabTearOffGhost extends StatelessWidget {
  const TabTearOffGhost({
    super.key,
    required this.topLeft,
    required this.size,
    required this.child,
  });

  final ValueListenable<Offset?> topLeft;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset?>(
      valueListenable: topLeft,
      child: IgnorePointer(
        child: SizedBox.fromSize(size: size, child: child),
      ),
      builder: (context, position, child) {
        if (position == null) return const SizedBox.shrink();
        // The overlay is not necessarily at the window's origin, so window
        // coordinates are converted into its own.
        final overlay = Overlay.maybeOf(context)?.context.findRenderObject();
        final local = overlay is RenderBox && overlay.attached
            ? overlay.globalToLocal(position)
            : position;
        return Positioned(left: local.dx, top: local.dy, child: child!);
      },
    );
  }
}
