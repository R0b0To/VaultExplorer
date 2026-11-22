import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Where the last pointer went down, in global coordinates.
///
/// A context menu opens from a callback that only knows which item was
/// tapped, not where; this lets it open at the click or the long-press that
/// asked for it.
abstract final class LastPointer {
  static Offset? position;
  static bool _installed = false;

  /// Starts tracking. Needs the Flutter bindings, so call it after
  /// `WidgetsFlutterBinding.ensureInitialized()`.
  static void ensureInstalled() {
    if (_installed) return;
    _installed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      if (event is PointerDownEvent) position = event.position;
    });
  }
}
