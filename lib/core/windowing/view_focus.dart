import 'package:flutter/widgets.dart';

/// Whether keyboard focus is in the same window as [context].
///
/// `HardwareKeyboard` handlers hear every key press of the app, whichever
/// window it was typed in. With more than one window open, a handler that acts
/// on "the focused thing" has to check that the focus is in its own window
/// first, or a Delete typed in one window would also run in the others.
///
/// Returns true when nothing holds focus or when there is a single window, so
/// behaviour with one window is unchanged.
bool keyboardFocusIsInViewOf(BuildContext context) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return true;
  final focusedView = View.maybeOf(focused)?.viewId;
  final ownView = View.maybeOf(context)?.viewId;
  if (focusedView == null || ownView == null) return true;
  return focusedView == ownView;
}
