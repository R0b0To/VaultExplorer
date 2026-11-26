/// When a tab that is being dragged counts as pulled out of its window.
///
/// Kept free of Flutter types (plain numbers in window coordinates, logical
/// pixels) so the rule can be tested on its own. The tab strip feeds it the
/// pointer position on every move of a tab drag.
abstract final class TabTearOffZone {
  /// How far past the strip, or past the window's side edges, the pointer has
  /// to be before releasing opens the tab in a window of its own.
  ///
  /// Large enough that the sideways wobble of an ordinary reorder never
  /// reaches it, small enough that a deliberate pull-out registers quickly.
  static const double distance = 28;

  /// Once a tab is held out, the pointer has to come this much further back
  /// before the tab counts as being in the strip again, so a pointer resting
  /// on the boundary does not flicker between the two.
  static const double hysteresis = 8;

  /// Whether a pointer at ([pointerX], [pointerY]) has pulled the tab out.
  ///
  /// [stripTop] and [stripBottom] are the vertical extent of the tab strip and
  /// [windowWidth] the width of the window it is in, all in the same window
  /// coordinates as the pointer. [wasTornOut] is the previous answer.
  static bool isTornOut({
    required double pointerX,
    required double pointerY,
    required double stripTop,
    required double stripBottom,
    required double windowWidth,
    bool wasTornOut = false,
  }) {
    final margin = wasTornOut ? distance - hysteresis : distance;
    if (pointerY < stripTop - margin || pointerY > stripBottom + margin) {
      return true;
    }
    if (pointerX < -margin || pointerX > windowWidth + margin) return true;
    return false;
  }
}
