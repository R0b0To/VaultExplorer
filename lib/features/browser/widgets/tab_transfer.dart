import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart'
    show BrowserTabState;
import 'package:vaultexplorer/features/browser/widgets/tab_drag_session.dart';

/// A tab on its way from one window to another.
class TabTransfer {
  const TabTransfer({required this.tab, required this.sourceViewId, this.path});

  /// The tab as it is in the window it comes from.
  final BrowserTabState tab;

  /// Where in its container a folder tab is (null for the root, and for tabs
  /// that are not folders).
  final String? path;

  /// The window the tab comes from.
  final int sourceViewId;
}

/// The tab strips that a dragged tab can be dropped into. Every strip adds
/// itself while it is on screen.
final TabDropTargets<TabTransfer> tabDropTargets =
    TabDropTargets<TabTransfer>();
