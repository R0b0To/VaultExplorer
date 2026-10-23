import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter/widgets.dart';

/// A [PageController] whose pager keeps handing touches to its pages while it
/// is still settling.
///
/// A [Scrollable] makes everything inside it ignore pointers for as long as its
/// position moves by itself: a swipe's fling settling onto the next page, or an
/// animated page change. The spring behind that settle keeps running well after
/// the page has visibly arrived, so a finger that lands right after a swipe
/// never reaches the list on the new page. Vertical scrolling is dead until the
/// last fraction of a pixel has come to rest.
///
/// This controller gives its position a [ScrollContext] that never turns that
/// pointer-ignoring on, so a touch during the settle reaches the page. The
/// pager itself still sees it first, as always: it pauses the settle for the
/// touch, and if the touch turns into a vertical scroll (the pager needs a
/// clearly horizontal drag to claim it), it carries on to the page it was
/// heading for. A horizontal drag still catches the page mid-flight.
///
/// The one thing given up is the guard against a second finger reaching the
/// pages while another one is dragging the pager sideways.
///
/// `PageController` casts its position to a private type, so the position class
/// cannot be swapped. [PageController.createScrollPosition] and
/// [ScrollContext] are the supported extension points, which is why this goes
/// through the context.
class SettleTouchPageController extends PageController {
  SettleTouchPageController({
    super.initialPage,
    super.keepPage,
    super.viewportFraction,
  });

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return super.createScrollPosition(
      physics,
      _AlwaysTouchableScrollContext(context),
      oldPosition,
    );
  }
}

/// Passes everything on to the [Scrollable]'s own context, except that the
/// pages are never told to ignore pointers.
class _AlwaysTouchableScrollContext implements ScrollContext {
  const _AlwaysTouchableScrollContext(this._inner);

  final ScrollContext _inner;

  @override
  BuildContext? get notificationContext => _inner.notificationContext;

  @override
  BuildContext get storageContext => _inner.storageContext;

  @override
  TickerProvider get vsync => _inner.vsync;

  @override
  AxisDirection get axisDirection => _inner.axisDirection;

  @override
  double get devicePixelRatio => _inner.devicePixelRatio;

  @override
  void setIgnorePointer(bool value) => _inner.setIgnorePointer(false);

  @override
  void setCanDrag(bool value) => _inner.setCanDrag(value);

  @override
  void setSemanticsActions(Set<SemanticsAction> actions) =>
      _inner.setSemanticsActions(actions);

  @override
  void saveOffset(double offset) => _inner.saveOffset(offset);
}
