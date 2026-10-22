import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_app_bar_factory.dart';
import 'package:vaultexplorer/features/dashboard/widgets/dashboard_app_bar.dart';

PreferredSizeWidget _buildDashboardAppBar(BuildContext context) =>
    const DashboardAppBar();

/// App bar the window shows while Home is the active tab.
final BrowserAppBarFactory dashboardBrowserAppBarFactory =
    _buildDashboardAppBar;

/// The window chrome that is visible right now, assembled from what each tab
/// has contributed.
///
/// Tabs contribute an app bar, a selection app bar, a floating action and a
/// bottom bar (directory viewports for themselves, the shell for Home). The hub
/// remembers each tab's contribution outside the widget tree and exposes the
/// active tab's as listenables that the shell renders, so the shell keeps no
/// per-tab maps or notifiers of its own.
///
/// Switching tabs keeps the previous app bar and floating action until the
/// newly active tab has published its own. Showing nothing in between would
/// flash the generic fallback toolbar or animate the FAB away and back.
class BrowserChromeHub {
  BrowserChromeHub({
    required BrowserTabsState initial,
    required AggregatedTabsSelection Function() readSelection,
    BrowserAppBarFactory? homeAppBar,
  }) : _readSelection = readSelection,
       _homeAppBar = homeAppBar ?? dashboardBrowserAppBarFactory,
       _activeTabId = initial.activeTabId {
    _appBar.value = initial.activeTab?.isDashboard == true ? _homeAppBar : null;
  }

  final AggregatedTabsSelection Function() _readSelection;
  final BrowserAppBarFactory _homeAppBar;

  final ValueNotifier<BrowserAppBarFactory?> _appBar =
      ValueNotifier<BrowserAppBarFactory?>(null);
  final ValueNotifier<BrowserAppBarFactory?> _selectionAppBar =
      ValueNotifier<BrowserAppBarFactory?>(null);
  final ValueNotifier<Widget?> _floatingAction = ValueNotifier<Widget?>(null);
  final ValueNotifier<Widget?> _bottomBar = ValueNotifier<Widget?>(null);
  final ValueNotifier<Set<TabId>> _visibleTabs = ValueNotifier<Set<TabId>>(
    const <TabId>{},
  );

  final Map<TabId, BrowserAppBarFactory> _appBars = {};
  final Map<TabId, BrowserAppBarFactory?> _selectionAppBars = {};
  final Map<TabId, Widget?> _floatingActions = {};
  final Map<TabId, Widget?> _bottomBars = {};

  TabId? _activeTabId;
  bool _disposed = false;

  /// App bar of the active tab. Null until the first one has been published.
  ValueListenable<BrowserAppBarFactory?> get appBar => _appBar;

  /// Selection app bar to show in place of [appBar], or null when the
  /// selection UI lives in the bottom bar or nothing is selected.
  ValueListenable<BrowserAppBarFactory?> get selectionAppBar => _selectionAppBar;

  ValueListenable<Widget?> get floatingAction => _floatingAction;
  ValueListenable<Widget?> get bottomBar => _bottomBar;

  /// Tabs on screen in addition to the active one (the second pane in
  /// dual-pane browsing); empty otherwise.
  ///
  /// "Active" means focused: it decides who gets back, chrome and activity.
  /// "Visible" is wider: every tab on screen must keep its listing fresh, so a
  /// tab is visible when it is active or listed here.
  ValueListenable<Set<TabId>> get visibleTabs => _visibleTabs;

  void setAppBar(TabId tabId, BrowserAppBarFactory factory) {
    if (_disposed) return;
    _appBars[tabId] = factory;
    if (_activeTabId == tabId) _appBar.value = factory;
  }

  void setSelectionAppBar(TabId tabId, BrowserAppBarFactory? factory) {
    if (_disposed) return;
    _selectionAppBars[tabId] = factory;
    if (_activeTabId == tabId) {
      // The visible tab's preference decides whether the aggregate selection
      // UI belongs in the stationary app bar or in the bottom slot.
      _selectionAppBar.value = factory ?? _selectionAppBarFor(tabId);
      return;
    }
    _selectionAppBar.value = _selectionAppBarFor(_activeTabId);
  }

  void setFloatingAction(TabId tabId, Widget? action) {
    if (_disposed) return;
    _floatingActions[tabId] = action;
    if (_activeTabId != tabId) return;
    _floatingAction.value = action;
  }

  /// Published by the shell's layout: the tabs shown besides the active one.
  void setVisibleTabs(Set<TabId> tabs) {
    if (_disposed || setEquals(_visibleTabs.value, tabs)) return;
    _visibleTabs.value = Set<TabId>.unmodifiable(tabs);
  }

  void setBottomBar(TabId tabId, Widget? bottomBar) {
    if (_disposed) return;
    _bottomBars[tabId] = bottomBar;
    if (_activeTabId != tabId) return;
    _bottomBar.value = bottomBar;
  }

  /// Follows the workspace: forgets closed tabs and, when the active tab
  /// changes, switches the visible chrome to that tab's contribution.
  void syncWorkspace(BrowserTabsState next) {
    if (_disposed) return;
    final live = next.tabs.map((tab) => tab.tabId).toSet();
    _appBars.removeWhere((id, _) => !live.contains(id));
    _selectionAppBars.removeWhere((id, _) => !live.contains(id));
    _floatingActions.removeWhere((id, _) => !live.contains(id));
    _bottomBars.removeWhere((id, _) => !live.contains(id));
    if (_visibleTabs.value.any((id) => !live.contains(id))) {
      _visibleTabs.value = Set<TabId>.unmodifiable(
        _visibleTabs.value.where(live.contains),
      );
    }

    final activeTabId = next.activeTabId;
    if (_activeTabId == activeTabId) return;
    _activeTabId = activeTabId;

    if (activeTabId == null) {
      _appBar.value = null;
    } else if (next.activeTab?.isDashboard == true) {
      _appBar.value = _homeAppBar;
    } else {
      // Keep the current app bar until the new tab's viewport has published
      // its own; publishing null here would flash the generic fallback.
      final nextAppBar = _appBars[activeTabId];
      if (nextAppBar != null) _appBar.value = nextAppBar;
    }
    _selectionAppBar.value = _selectionAppBarFor(activeTabId);
    if (activeTabId == null) {
      _floatingAction.value = null;
    } else if (_floatingActions.containsKey(activeTabId)) {
      // An unvisited tab has not published a FAB yet. Keep the current one
      // rather than passing through null, which animates the FAB away and
      // back in.
      _floatingAction.value = _floatingActions[activeTabId];
    }
    _bottomBar.value = activeTabId == null ? null : _bottomBars[activeTabId];
  }

  BrowserAppBarFactory? _selectionAppBarFor(TabId? activeTabId) {
    if (activeTabId != null && _selectionAppBars.containsKey(activeTabId)) {
      final own = _selectionAppBars[activeTabId];
      if (own != null) return own;
    }
    final aggregate = _readSelection();
    if (!aggregate.hasSelection) return null;
    for (final entry in aggregate.itemsByTab.entries) {
      if (entry.value.isEmpty) continue;
      final candidate = _selectionAppBars[entry.key];
      if (candidate != null) return candidate;
    }
    return null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _appBar.dispose();
    _selectionAppBar.dispose();
    _floatingAction.dispose();
    _bottomBar.dispose();
    _visibleTabs.dispose();
    _appBars.clear();
    _selectionAppBars.clear();
    _floatingActions.clear();
    _bottomBars.clear();
  }
}

/// One [BrowserChromeHub] per workspace. Held alive by the shell for as long
/// as it is mounted; disposed with it so the hub never keeps widgets from
/// closed tabs alive.
final browserChromeProvider = Provider.autoDispose
    .family<BrowserChromeHub, BrowserTabsConfig>((ref, config) {
      final hub = BrowserChromeHub(
        initial: ref.read(browserTabsProvider(config)),
        readSelection: () => ref.read(aggregatedTabsSelectionProvider(config)),
      );
      ref.listen<BrowserTabsState>(
        browserTabsProvider(config),
        (_, next) => hub.syncWorkspace(next),
      );
      ref.onDispose(hub.dispose);
      return hub;
    });
