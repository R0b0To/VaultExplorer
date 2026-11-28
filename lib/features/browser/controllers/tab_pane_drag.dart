import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';

/// What the tab strips and the pages of one workspace share while a tab is
/// dragged from one pane to the other.
///
/// They are not always in one place. Where the strips are drawn in the
/// window's title bar (Windows), they sit above the panes and know nothing of
/// the page that draws them; the page, in turn, is what highlights the pane a
/// tab is held over. This is the meeting point.
class TabPaneDrag {
  /// The pane that a dragged tab is held over, or null while it is over none.
  /// The page highlights that pane as the place the tab would go.
  final ValueNotifier<TabPane?> hover = ValueNotifier<TabPane?>(null);

  /// Where a pane is on screen, in window coordinates; set by the page for as
  /// long as it is on screen. The pane's own strip is inside this area when it
  /// is drawn in the pane, and above it when it is drawn in the title bar.
  Rect? Function(TabPane pane)? paneBounds;
}

/// The [TabPaneDrag] of a workspace. The page holds it for as long as it is
/// shown, and disposes it with it; the strips hold it as long as they are.
final tabPaneDragProvider = Provider.autoDispose
    .family<TabPaneDrag, BrowserTabsConfig>((ref, config) {
      final drag = TabPaneDrag();
      ref.onDispose(() {
        drag.paneBounds = null;
        drag.hover.dispose();
      });
      return drag;
    });
