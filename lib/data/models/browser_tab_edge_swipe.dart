import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// What swiping sideways past the first or the last file-manager tab does.
enum BrowserTabEdgeSwipe {
  /// A right swipe on the first tab pulls out the side drawer, and a left
  /// swipe on the last tab offers a new tab (default).
  drawerAndNewTab,

  /// Swiping past either end wraps around to the tab at the other end. The
  /// drawer is then opened from the left screen edge (or the menu button) on
  /// every tab, and new tabs come from the tab strip.
  loop;

  bool get loops => this == BrowserTabEdgeSwipe.loop;

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
    BrowserTabEdgeSwipe.drawerAndNewTab => l10n.tabEdgeSwipeDrawerAndNewTabLabel,
    BrowserTabEdgeSwipe.loop => l10n.tabEdgeSwipeLoopLabel,
  };

  String getLocalizedDescription(AppLocalizations l10n) => switch (this) {
    BrowserTabEdgeSwipe.drawerAndNewTab =>
      l10n.tabEdgeSwipeDrawerAndNewTabDesc,
    BrowserTabEdgeSwipe.loop => l10n.tabEdgeSwipeLoopDesc,
  };

  String toJson() => name;

  static BrowserTabEdgeSwipe fromJson(String? value) => switch (value) {
    'loop' => BrowserTabEdgeSwipe.loop,
    _ => BrowserTabEdgeSwipe.drawerAndNewTab,
  };
}
