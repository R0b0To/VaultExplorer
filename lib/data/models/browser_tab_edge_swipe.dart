import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// How swiping sideways between the file-manager tabs behaves, and what
/// swiping past the first or the last tab does.
enum BrowserTabEdgeSwipe {
  /// A right swipe on the first tab pulls out the side drawer, and a left
  /// swipe on the last tab offers a new tab (default).
  drawerAndNewTab,

  /// Swiping past either end wraps around to the tab at the other end. The
  /// drawer is then opened from the left screen edge (or the menu button) on
  /// every tab, and new tabs come from the tab strip.
  loop,

  /// Swiping past either end does nothing. The drawer is opened from the left
  /// screen edge (or the menu button), and new tabs come from the tab strip.
  noEdgeActions,

  /// Swiping does not change tabs at all (they change from the tab strip).
  /// Every tab then acts like the first one: a right swipe anywhere opens the
  /// drawer and a left swipe anywhere offers a new tab.
  noTabSwiping;

  /// Whether a horizontal swipe moves between tabs.
  bool get swipesBetweenTabs => this != BrowserTabEdgeSwipe.noTabSwiping;

  /// Whether swiping past an end wraps around to the other end.
  bool get loops => this == BrowserTabEdgeSwipe.loop;

  /// Whether swiping past the first or last tab does something at all.
  bool get hasEdgeActions =>
      this == BrowserTabEdgeSwipe.drawerAndNewTab ||
      this == BrowserTabEdgeSwipe.loop;

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
    BrowserTabEdgeSwipe.drawerAndNewTab =>
      l10n.tabEdgeSwipeDrawerAndNewTabLabel,
    BrowserTabEdgeSwipe.loop => l10n.tabEdgeSwipeLoopLabel,
    BrowserTabEdgeSwipe.noEdgeActions => l10n.tabEdgeSwipeNoEdgeActionsLabel,
    BrowserTabEdgeSwipe.noTabSwiping => l10n.tabEdgeSwipeNoTabSwipingLabel,
  };

  String getLocalizedDescription(AppLocalizations l10n) => switch (this) {
    BrowserTabEdgeSwipe.drawerAndNewTab =>
      l10n.tabEdgeSwipeDrawerAndNewTabDesc,
    BrowserTabEdgeSwipe.loop => l10n.tabEdgeSwipeLoopDesc,
    BrowserTabEdgeSwipe.noEdgeActions => l10n.tabEdgeSwipeNoEdgeActionsDesc,
    BrowserTabEdgeSwipe.noTabSwiping => l10n.tabEdgeSwipeNoTabSwipingDesc,
  };

  String toJson() => name;

  static BrowserTabEdgeSwipe fromJson(String? value) => switch (value) {
    'loop' => BrowserTabEdgeSwipe.loop,
    'noEdgeActions' => BrowserTabEdgeSwipe.noEdgeActions,
    'noTabSwiping' => BrowserTabEdgeSwipe.noTabSwiping,
    _ => BrowserTabEdgeSwipe.drawerAndNewTab,
  };
}
