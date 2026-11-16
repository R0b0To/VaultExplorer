import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Lets a screen keep its bottom bar up to date without making the whole tab
/// shell rebuild every time it does.
///
/// The shell watches the bottom bar published to `BrowserChromeHub` with a
/// `ValueListenableBuilder` whose builder constructs the `Scaffold`, the pager
/// and therefore every mounted tab. The hub's `ValueNotifier` only skips
/// notifying for an *identical* widget, and a screen builds a new bar widget on
/// each of its builds. So a screen that republished its bar after every build
/// made the shell rebuild every tab, which rebuilt the screen, which published
/// a new bar again: one complete rebuild of the screen, and of every tile in it,
/// on every frame, forever, with nothing happening.
///
/// The hub is instead given [barWidget], which never changes for the life of
/// the slot. What it shows is swapped inside it by [publish], and that rebuilds
/// only the bar.
class ChromeBarSlot {
  final ValueNotifier<Widget?> _content = ValueNotifier<Widget?>(null);

  late final Widget _slotWidget = ValueListenableBuilder<Widget?>(
    valueListenable: _content,
    builder: (context, content, _) => content ?? const SizedBox.shrink(),
  );

  /// The stable widget to hand to the hub (the same instance every time).
  Widget get barWidget => _slotWidget;

  /// Shows [content] in the slot and returns what to publish to the hub: null
  /// when there is no bar, otherwise the stable [barWidget].
  ///
  /// Call it from a post-frame callback, not from `build`: it notifies.
  Widget? publish(Widget? content) {
    _content.value = content;
    return content == null ? null : _slotWidget;
  }
}
