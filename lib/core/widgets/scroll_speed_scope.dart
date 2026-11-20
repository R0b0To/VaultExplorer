import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Tells the tiles of a scrollable whether it is moving too fast for them to
/// be worth loading yet (see `ScrollSpeedTracker`).
///
/// Provided by `FastScrollbar` around the list it wraps. A tile that asks
/// ([isFastOf]) is rebuilt when the answer changes, so it can start loading
/// the moment the scroll slows down: not when it stops.
///
/// Outside such a scrollable the answer is always "not fast", so widgets that
/// consult it behave exactly as they did without it.
class ScrollSpeedScope extends InheritedNotifier<ValueNotifier<bool>> {
  const ScrollSpeedScope({
    super.key,
    required ValueNotifier<bool> fast,
    required super.child,
  }) : super(notifier: fast);

  /// Whether the nearest enclosing scrollable is moving too fast to read, and
  /// subscribes [context] to changes of that.
  static bool isFastOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ScrollSpeedScope>();
    return scope?.notifier?.value ?? false;
  }
}
