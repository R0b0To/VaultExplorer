import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/data/models/browser_tab_edge_swipe.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_search_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_chrome_hub.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/models/browser_viewport_options.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/widgets/adaptive_browser_app_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_app_bar_factory.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_new_tab_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_tab_strip.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_content_view.dart';
import 'package:vaultexplorer/features/browser/widgets/fast_scrollbar.dart';
import 'package:vaultexplorer/features/browser/widgets/gated_page_scroll_physics.dart';
import 'package:vaultexplorer/features/browser/widgets/settle_touch_page_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

/// Directory a duplicated / newly opened tab should start in for [nav]'s
/// current location. Inside an archive the "directory" is a virtual path in
/// the archive, which another tab can't open directly, so fall back to the
/// directory that contains the archive file.
String browserTabDuplicatePath(FileBrowserNavigationState nav) {
  final archive = nav.archiveContext;
  if (archive != null) {
    final idx = archive.pathStackEntryIndex - 1;
    if (idx >= 0 && idx < nav.pathStack.length) {
      return nav.pathStack[idx].fatPath;
    }
    return '';
  }
  return nav.currentDirPath;
}

typedef BrowserHomeBuilder =
    Widget Function({
      required BrowserTabsConfig workspace,
      required ValueChanged<Widget?> onFloatingActionChanged,
      required ValueChanged<Widget?> onBottomBarChanged,
    });

/// Builds the route that shows the file manager with tab support. Replaces
/// pushing a bare directory viewport: with a single tab it looks and behaves
/// the same, and opening more tabs reveals the tab strip.
Route<void> buildBrowserTabsRoute({
  required MountedContainer container,
  required MountedContainer? Function(int volId) resolveContainer,
  required List<MountedContainer> Function() mountedContainers,
  required MountedContainer? Function() primaryLocalContainer,
  Widget Function(BrowserTabsConfig workspace, int? currentVolId)?
  drawerBuilder,
  VoidCallback? Function(int volId)? userActivityFor,
  ValueChanged<BrowserTabsConfig?>? onWorkspaceChanged,
  bool closeRouteWhenEmpty = true,
  bool includeDashboardTab = false,
  VoidCallback? onEmpty,
  VoidCallback? onNewTab,
  ValueChanged<BrowserTabState>? onDuplicate,
  BrowserHomeBuilder? homeBuilder,
}) {
  return MaterialPageRoute<void>(
    builder: (_) => SkinAreaScope(
      area: SkinArea.files,
      child: BrowserTabsShell(
        initialContainer: container,
        resolveContainer: resolveContainer,
        mountedContainers: mountedContainers,
        primaryLocalContainer: primaryLocalContainer,
        drawerBuilder: drawerBuilder,
        userActivityFor: userActivityFor,
        onWorkspaceChanged: onWorkspaceChanged,
        closeRouteWhenEmpty: closeRouteWhenEmpty,
        includeDashboardTab: includeDashboardTab,
        onEmpty: onEmpty,
        onNewTab: onNewTab,
        onDuplicate: onDuplicate,
        homeBuilder: homeBuilder,
      ),
    ),
  );
}

/// Fixed browser frame with one sliding viewport per open location. Each file
/// tab's Riverpod state is keyed by its tab id, so repeated locations remain
/// independent while the shell chrome stays stationary.
class BrowserTabsShell extends ConsumerStatefulWidget {
  final MountedContainer? initialContainer;
  final MountedContainer? Function(int volId) resolveContainer;
  final List<MountedContainer> Function() mountedContainers;
  final MountedContainer? Function() primaryLocalContainer;
  final Widget Function(BrowserTabsConfig workspace, int? currentVolId)?
  drawerBuilder;
  final VoidCallback? Function(int volId)? userActivityFor;
  final ValueChanged<BrowserTabsConfig?>? onWorkspaceChanged;
  final bool closeRouteWhenEmpty;
  final bool includeDashboardTab;
  final BrowserHomeBuilder? homeBuilder;
  final VoidCallback? onEmpty;
  final VoidCallback? onNewTab;
  final ValueChanged<BrowserTabState>? onDuplicate;

  /// How every directory viewport in this shell should look.
  final BrowserViewportOptions viewportOptions;

  /// True when this shell is the app's root surface (decoy mode): there is no
  /// route beneath it, so closing the last tab reopens
  /// [primaryLocalContainer] and back at the root leaves the app.
  final bool appRoot;

  const BrowserTabsShell({
    super.key,
    this.initialContainer,
    required this.resolveContainer,
    required this.mountedContainers,
    required this.primaryLocalContainer,
    this.drawerBuilder,
    this.userActivityFor,
    this.onWorkspaceChanged,
    this.closeRouteWhenEmpty = true,
    this.includeDashboardTab = false,
    this.homeBuilder,
    this.onEmpty,
    this.onNewTab,
    this.onDuplicate,
    this.viewportOptions = const BrowserViewportOptions(),
    this.appRoot = false,
  });

  @override
  ConsumerState<BrowserTabsShell> createState() => _BrowserTabsShellState();
}

/// Compatibility name retained for existing route builders and integrations.
typedef BrowserTabsHost = BrowserTabsShell;

class _BrowserTabsShellState extends ConsumerState<BrowserTabsShell>
    with TickerProviderStateMixin {
  /// How far past the first or last tab a drag has to go before it counts as
  /// asking for something there (a new tab, or looping to the other end).
  static const double _newTabSwipeThreshold = 72;

  /// A quick flick loops with less travel than a slow drag: at least this much
  /// travel, and at least this speed (logical px/s), in the matching direction.
  static const double _loopFlingMinOverscroll = 12;
  static const double _loopFlingVelocity = 800;

  /// How many times the platform touch slop a sideways drag must travel before
  /// the tab pager claims it. A list inside a tab starts scrolling after one
  /// slop of vertical travel, so a vertical scroll that drifts sideways keeps
  /// the gesture; only a clearly horizontal swipe reaches the pager's larger
  /// slop first. Raise it to make accidental tab swipes rarer still.
  static const double _tabPagerSlopFactor = 2.0;

  /// With tab swiping off, a left swipe anywhere offers a new tab. It has to be
  /// quick (a slow drag is a long-press drag selecting items, say) and mostly
  /// horizontal, and it is given up on if the finger goes back the other way.
  static const Duration _newTabSwipeMaxDuration = Duration(milliseconds: 700);
  static const double _newTabSwipeBackoff = 40;

  late final BrowserTabsConfig _workspace;
  late final ProviderSubscription<BrowserTabsState> _workspaceSubscription;
  late final VaultEngineEvents _vaultEvents;
  late final PageController _pageController;
  late final ProviderSubscription<BrowserChromeHub> _chromeSubscription;
  late final AnimationController _appBarVisibilityController;
  late final AnimationController _tabBarVisibilityController;

  /// Fades the pages back in after the tabs loop, so wrapping from one end to
  /// the other reads as a transition rather than a jump.
  late final AnimationController _loopTransitionController;
  late final Animation<double> _loopFade = Tween<double>(
    begin: 0.35,
    end: 1.0,
  ).animate(_loopTransitionController);
  final Map<TabId, GlobalKey> _directoryViewKeys = {};
  final Map<TabId, GlobalKey> _dashboardViewKeys = {};
  bool _popScheduled = false;
  bool _drawerOpenOrDragging = false;
  bool _edgeDrawerGestureActive = false;
  bool _restoreAppBarScheduled = false;
  bool _restoreTabBarScheduled = false;
  bool _newTabPromptScheduled = false;
  bool _loopScheduled = false;

  /// True while a fast-scroll handle is held. The handle scrolls with a stream
  /// of `jumpTo` calls that read as scroll direction; with the app bar at the
  /// bottom, reacting to them resizes the list under the handle and the bar
  /// flickers. The bar stays put until the handle is released.
  bool _scrollbarDragging = false;
  bool _scrollbarDragEndedAtTop = false;

  /// How long after its last movement a list still counts as scrolling. A
  /// scroll that is really running reports every frame; this only guards
  /// against an end that was never reported (the page was closed mid-fling),
  /// which would otherwise leave tab swiping locked.
  static const Duration _pageScrollFreshFor = Duration(milliseconds: 250);

  /// Tab swiping is only for a view that is standing still: a touch that lands
  /// while a list is scrolling (or that is what stops it) only stops the
  /// scroll, and cannot also swipe to another tab. Decided once per touch, in
  /// [_onBrowserPointerDown], and read by the pager's physics.
  final PagerSwipeGate _swipeGate = PagerSwipeGate();
  final Stopwatch _pageScrollClock = Stopwatch()..start();
  bool _pageScrollActive = false;
  Duration _lastPageScrollAt = Duration.zero;

  /// A touch can itself end a fling, and the list reports that end before the
  /// browser hears about the touch. The end stays visible until the frame is
  /// over so that touch is still seen as the one that stopped the scroll.
  bool _pageScrollEndPending = false;
  bool _pageScrollEndResetScheduled = false;

  /// A drag that started on the first and/or last tab, and so may end up
  /// asking for something past it. [_edgeOverscrollForward] is how far it was
  /// pulled past the last tab (left swipe), [_edgeOverscrollBackward] past the
  /// first tab (right swipe).
  bool _edgeSwipeEligible = false;

  /// The pane the drag in [_edgeSwipeEligible] is swiping tabs in; null for
  /// the single pager over all tabs.
  TabPane? _edgeSwipePane;
  bool _edgeSwipeStartedAtFirst = false;
  bool _edgeSwipeStartedAtLast = false;
  double _edgeOverscrollForward = 0;
  double _edgeOverscrollBackward = 0;

  /// Whether a left swipe anywhere offers a new tab (the "no tab swiping"
  /// setting). Kept up to date by the build.
  bool _newTabSwipeAnywhere = false;
  int _pointersDown = 0;
  Duration _lastPointerEventTime = Duration.zero;
  int? _newTabSwipePointer;
  Offset _newTabSwipeStart = Offset.zero;
  Duration _newTabSwipeStartTime = Duration.zero;
  bool? _wasDualPane;
  bool? _requestedSplitAvailable;

  /// Dual pane: where each pane is on screen (for dropping a dragged tab on
  /// it), each pane's pager, the pane a dragged tab is currently over, and
  /// the pane whose pager just wrapped round (only that one fades).
  final Map<TabPane, GlobalKey> _paneKeys = {
    for (final pane in TabPane.values)
      pane: GlobalKey(debugLabel: 'pane-$pane'),
  };
  final Map<TabPane, GlobalKey<_PaneTabPagerState>> _panePagerKeys = {
    for (final pane in TabPane.values)
      pane: GlobalKey<_PaneTabPagerState>(debugLabel: 'pager-$pane'),
  };
  final ValueNotifier<TabPane?> _dropPane = ValueNotifier<TabPane?>(null);
  TabPane? _loopingPane;
  Set<TabId> _requestedVisibleTabs = const <TabId>{};
  int? _pageViewDrivenActiveIndex;

  BrowserTabsState get _workspaceState =>
      ref.read(browserTabsProvider(_workspace));
  BrowserTabs get _workspaceActions =>
      ref.read(browserTabsProvider(_workspace).notifier);

  /// What the tabs have contributed to the window chrome. Held alive for the
  /// lifetime of this shell; viewports reach the same instance through the
  /// provider.
  BrowserChromeHub get _chrome => _chromeSubscription.read();

  @override
  void initState() {
    super.initState();
    _workspace = BrowserTabsConfig.create(
      initialContainer: widget.initialContainer,
      includeDashboardTab: widget.includeDashboardTab,
      appRoot: widget.appRoot,
    );
    final initialState = ref.read(browserTabsProvider(_workspace));
    // Pages keep taking touches while a swipe is still settling, so a vertical
    // scroll can start right after changing tabs instead of waiting for the
    // pager's spring to come fully to rest.
    _pageController = SettleTouchPageController(
      initialPage: initialState.activeIndex,
    );
    _chromeSubscription = ref.listenManual<BrowserChromeHub>(
      browserChromeProvider(_workspace),
      (_, _) {},
    );
    _appBarVisibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    _tabBarVisibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1.0,
    );
    _loopTransitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1.0,
    );
    _workspaceSubscription = ref.listenManual<BrowserTabsState>(
      browserTabsProvider(_workspace),
      _onTabsChanged,
    );
    _vaultEvents = ref.read(vaultEngineEventsProvider);
    _vaultEvents.addContainerLockedListener(_onVolumeGone);
    _vaultEvents.addUsbContainerDetachedListener(_onVolumeGone);
    widget.onWorkspaceChanged?.call(_workspace);
  }

  @override
  void dispose() {
    widget.onWorkspaceChanged?.call(null);
    _vaultEvents.removeContainerLockedListener(_onVolumeGone);
    _vaultEvents.removeUsbContainerDetachedListener(_onVolumeGone);
    _workspaceSubscription.close();
    _pageController.dispose();
    _chromeSubscription.close();
    _appBarVisibilityController.dispose();
    _tabBarVisibilityController.dispose();
    _loopTransitionController.dispose();
    _dropPane.dispose();
    super.dispose();
  }

  void _onVolumeGone(int volId) {
    if (!mounted) return;
    _workspaceActions.closeByVolId(volId);
  }

  void _onTabsChanged(BrowserTabsState? previous, BrowserTabsState next) {
    // Side by side, each pane's pager follows its own tab.
    for (final key in _panePagerKeys.values) {
      key.currentState?.syncTo(next);
    }
    final pageViewChangedActiveTab =
        previous?.activeTabId != next.activeTabId &&
        next.activeIndex == _pageViewDrivenActiveIndex;
    if (pageViewChangedActiveTab) _pageViewDrivenActiveIndex = null;

    if (previous?.activeTabId != next.activeTabId) {
      // A handle drag cannot outlive the page it was on.
      _scrollbarDragging = false;
      _scrollbarDragEndedAtTop = false;
    }

    // Closing tabs leaves the pager's offset pointing past the new last page
    // (or at the wrong tab). The scroll physics would then spring back to the
    // edge, which reads as a slide. The target is inside the old extents too,
    // so jumping now, before the list shrinks, switches directly.
    final tabsShrank =
        previous != null &&
        next.tabs.length < previous.tabs.length &&
        next.tabs.isNotEmpty &&
        next.activeIndex >= 0;
    if (_isPureTabReorder(previous, next) || tabsShrank) {
      if (_pageController.hasClients) {
        final target = next.activeIndex;
        final current = _pageController.page;
        if (current == null || (current - target).abs() > 0.01) {
          // Keep the active tab's logical page selected in the same frame as
          // the reordered list, so PageView never paints the old index's tab.
          _pageController.jumpToPage(target);
        }
      } else {
        _schedulePageSync();
      }
    } else if (!pageViewChangedActiveTab) {
      _schedulePageSync();
    }

    final liveTabIds = next.tabs.map((tab) => tab.tabId).toSet();
    _directoryViewKeys.removeWhere((id, _) => !liveTabIds.contains(id));
    _dashboardViewKeys.removeWhere((id, _) => !liveTabIds.contains(id));
    if (next.tabs.isEmpty && !_popScheduled) {
      _popScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _popScheduled = false;
        if (_workspaceState.tabs.isNotEmpty) return;
        if (widget.appRoot) {
          // Nothing lies beneath an app-root browser (decoy mode), so closing
          // the last tab reopens the primary location instead of leaving.
          final fallback = widget.primaryLocalContainer();
          if (fallback != null) _workspaceActions.openTab(fallback);
          return;
        }
        if (!widget.closeRouteWhenEmpty) {
          widget.onEmpty?.call();
          return;
        }
        final route = ModalRoute.of(context);
        final navigator = Navigator.of(context);
        if (route == null) return;
        if (route.isCurrent) {
          navigator.pop();
        } else if (route.isActive) {
          navigator.removeRoute(route);
        }
      });
    }
  }

  bool _isPureTabReorder(BrowserTabsState? previous, BrowserTabsState next) {
    if (previous == null ||
        previous.tabs.length != next.tabs.length ||
        previous.activeTabId != next.activeTabId) {
      return false;
    }
    final nextIds = next.tabs.map((tab) => tab.tabId).toSet();
    if (nextIds.length != previous.tabs.length ||
        !previous.tabs.every((tab) => nextIds.contains(tab.tabId))) {
      return false;
    }
    for (var index = 0; index < previous.tabs.length; index++) {
      if (previous.tabs[index].tabId != next.tabs[index].tabId) return true;
    }
    return false;
  }

  void _schedulePageSync() {
    if (_workspaceState.tabs.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      final state = _workspaceState;
      if (state.tabs.isEmpty) return;
      final target = state.activeIndex;
      final current = _pageController.page;
      if (current == null || (current - target).abs() > 0.01) {
        _pageController.jumpToPage(target);
      }
    });
  }

  void _onPageChanged(int index) {
    if (index < 0 || index >= _workspaceState.tabs.length) return;
    if (index == _workspaceState.activeIndex) return;
    _pageViewDrivenActiveIndex = index;
    _workspaceActions.activateIndex(index);
  }

  void _focusTab(TabId tabId) {
    if (_workspaceState.activeTabId == tabId) return;
    _workspaceActions.activate(tabId);
  }

  void _handleBackToDashboard() {
    final activeTabId = _workspaceState.activeTabId;
    if (activeTabId == null) return;
    if (_workspaceActions.returnToDashboardAtRoot(activeTabId)) return;
    if (_workspace.includeDashboardTab) {
      _workspaceActions.replaceActiveWithDashboard();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  Widget _buildTabContent(BrowserTabState tab, {required bool isActive}) {
    if (tab.isDashboard) {
      return KeyedSubtree(
        key: _dashboardViewKeys.putIfAbsent(tab.tabId, GlobalKey.new),
        child:
            widget.homeBuilder?.call(
              workspace: _workspace,
              onFloatingActionChanged: (action) =>
                  _chrome.setFloatingAction(tab.tabId, action),
              onBottomBarChanged: (bar) => _chrome.setBottomBar(tab.tabId, bar),
            ) ??
            const SizedBox.expand(),
      );
    }
    return SkinAreaScope(
      area: SkinArea.files,
      child: DirectoryContentView(
        key: _directoryViewKeys.putIfAbsent(tab.tabId, GlobalKey.new),
        container: tab.container!,
        tabId: tab.tabId,
        workspaceConfig: _workspace,
        initialPath: tab.initialPath,
        resolveContainer: widget.resolveContainer,
        thumbnailCacheMode: widget.viewportOptions.thumbnailCacheMode,
        thumbnailQuality: widget.viewportOptions.thumbnailQuality,
        showBackButton: widget.viewportOptions.showBackButton,
        wrapAppBarTitle: widget.viewportOptions.wrapAppBarTitle,
        onOpenStorageSwitcher: widget.viewportOptions.onOpenStorageSwitcher,
        onUserActivity: isActive
            ? widget.userActivityFor?.call(tab.volId!)
            : null,
      ),
    );
  }

  /// One pane of the dual-pane layout: its own tab strip above a pager over its
  /// own tabs. Swiping sideways in the pane moves between that pane's tabs and
  /// leaves the other pane alone.
  Widget _buildDualPaneViewport(
    TabPane pane, {
    required List<BrowserTabState> groupTabs,
    required TabId shownTabId,
    required TabId? activeTabId,
    required Widget stripSlot,
    required bool swipeEnabled,
    required bool autoHideAppBar,
    required bool autoHideTabBar,
  }) {
    final isActive = shownTabId == activeTabId;
    return Expanded(
      child: Stack(
        key: _paneKeys[pane],
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              stripSlot,
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.axis == Axis.vertical) {
                      _handleAppBarScroll(
                        notification,
                        enabled: autoHideAppBar,
                        autoHideTabBar: autoHideTabBar,
                        active: isActive,
                      );
                    } else {
                      // The pane's own pager: its ends are the ends of this
                      // pane's tabs, not of the whole workspace.
                      _handleTabEdgeSwipe(notification, pane: pane);
                    }
                    return true;
                  },
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (event) {
                      _focusTab(shownTabId);
                      _onBrowserPointerDown(event);
                    },
                    onPointerMove: _onBrowserPointerMove,
                    onPointerUp: _onBrowserPointerUp,
                    onPointerCancel: _onBrowserPointerCancel,
                    child: _PaneTabPager(
                      key: _panePagerKeys[pane],
                      pane: pane,
                      tabs: groupTabs,
                      shownTabId: shownTabId,
                      onTabChanged: _focusTab,
                      pageBuilder: (tab) => _buildTabContent(
                        tab,
                        isActive: tab.tabId == activeTabId,
                      ),
                      gate: _swipeGate,
                      swipeEnabled: swipeEnabled,
                      slopFactor: _tabPagerSlopFactor,
                      fade: _loopingPane == pane
                          ? _loopFade
                          : const AlwaysStoppedAnimation<double>(1.0),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Shown while a tab dragged out of the other strip is held over this
          // pane: where it would land.
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<TabPane?>(
                valueListenable: _dropPane,
                builder: (context, hover, _) {
                  if (hover != pane) return const SizedBox.shrink();
                  final cs = Theme.of(context).colorScheme;
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.08),
                      border: Border.all(color: cs.primary, width: 2),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Where [pane] is on screen, for dropping a dragged tab on it.
  Rect? _paneBounds(TabPane pane) {
    final box = _paneKeys[pane]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Tells the tab engine whether the layout can show two panes. The width
  /// that decides this is only known while building, so it is published from a
  /// frame callback; only a change is worth one.
  void _publishSplitAvailable(bool available) {
    if (_requestedSplitAvailable == available) return;
    _requestedSplitAvailable = available;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _workspaceActions.setSplitAvailable(available);
    });
  }

  /// Tells the tabs which of them are on screen besides the active one. The
  /// layout decides this (dual-pane depends on the width actually available),
  /// so it is published from the layout pass; the hub ignores repeats.
  void _publishVisibleTabs(Set<TabId> visible) {
    // The layout asks on every build; only a change is worth a frame callback.
    if (setEquals(_requestedVisibleTabs, visible)) return;
    _requestedVisibleTabs = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chrome.setVisibleTabs(visible);
    });
  }

  void _onDrawerChanged(bool isOpen) {
    if (!mounted || _drawerOpenOrDragging == isOpen) return;
    setState(() => _drawerOpenOrDragging = isOpen);
  }

  void _onEdgeDrawerGestureChanged(bool active) {
    if (!mounted || _edgeDrawerGestureActive == active) return;
    setState(() => _edgeDrawerGestureActive = active);
  }

  bool _handleAppBarScroll(
    ScrollNotification notification, {
    required bool enabled,
    required bool autoHideTabBar,
    required bool active,
  }) {
    if (notification.metrics.axis == Axis.horizontal) {
      _handleTabEdgeSwipe(notification);
      return false;
    }
    _trackPageScroll(notification);
    if (!active) return false;

    if (_scrollbarDragging) {
      // Remember whether the handle ended up at the top, so releasing it can
      // bring the bar back there (see _onScrollbarDrag).
      _scrollbarDragEndedAtTop =
          notification.metrics.maxScrollExtent > 0.0 &&
          notification.metrics.pixels <= 0.0;
      return false;
    }

    _updateChromeVisibilityFromScroll(
      _appBarVisibilityController,
      notification,
      enabled: enabled,
      barHeight: kToolbarHeight,
    );
    _updateChromeVisibilityFromScroll(
      _tabBarVisibilityController,
      notification,
      enabled: autoHideTabBar,
      barHeight: kBrowserTabStripHeight,
    );
    return false;
  }

  void _updateChromeVisibilityFromScroll(
    AnimationController controller,
    ScrollNotification notification, {
    required bool enabled,
    required double barHeight,
  }) {
    if (!enabled) {
      if (controller.value != 1.0) {
        controller.animateTo(
          1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    void setProgress(double value) {
      controller.value = value.clamp(0.0, 1.0).toDouble();
    }

    final metrics = notification.metrics;
    final canScroll = metrics.maxScrollExtent > 0.0;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      if (canScroll && metrics.pixels <= 0.0 && delta <= 0.0) {
        setProgress(1.0);
      } else if (delta != 0.0) {
        setProgress(controller.value - (delta / barHeight));
      }
    } else if (notification is OverscrollNotification) {
      if (notification.overscroll != 0.0) {
        setProgress(controller.value - (notification.overscroll / barHeight));
      }
    } else if (notification is ScrollEndNotification) {
      if (canScroll && metrics.pixels <= 0.0) {
        controller.animateTo(
          1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else if (controller.value > 0.0 && controller.value < 1.0) {
        controller.animateTo(
          controller.value >= 0.5 ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  /// Whether a list inside a page is scrolling right now, or was a moment ago
  /// and was stopped by the touch being handled.
  bool get _pageIsScrolling {
    if (_pageScrollEndPending) return true;
    return _pageScrollActive &&
        _pageScrollClock.elapsed - _lastPageScrollAt < _pageScrollFreshFor;
  }

  /// Follows the vertical scrolling of the lists in the pages, the same way the
  /// hold-to-select container does, for [_pageIsScrolling].
  void _trackPageScroll(ScrollNotification notification) {
    if (notification is ScrollStartNotification ||
        notification is ScrollUpdateNotification ||
        notification is OverscrollNotification) {
      _pageScrollActive = true;
      _pageScrollEndPending = false;
      _lastPageScrollAt = _pageScrollClock.elapsed;
    } else if (notification is ScrollEndNotification) {
      _pageScrollActive = false;
      _pageScrollEndPending = true;
      if (!_pageScrollEndResetScheduled) {
        _pageScrollEndResetScheduled = true;
        // A touch that stops a fling may not cause a frame by itself, and the
        // flag must not outlive that touch.
        _afterThisFrame(() {
          _pageScrollEndPending = false;
          _pageScrollEndResetScheduled = false;
        });
      }
    }
  }

  void _onBrowserPointerDown(PointerDownEvent event) {
    // The count only goes wrong if a finger's end was never seen (the layout
    // changed under it); nothing has been heard for a while then, so start over.
    if (_pointersDown > 0 &&
        event.timeStamp - _lastPointerEventTime > const Duration(seconds: 3)) {
      _pointersDown = 0;
    }
    _lastPointerEventTime = event.timeStamp;
    _pointersDown++;
    // The first finger decides whether this touch may swipe between tabs. It
    // stays decided until the next touch: the pager reads it when the finger
    // lets go too, which is after this handler has seen the lift.
    if (_pointersDown == 1) _swipeGate.locked = _pageIsScrolling;
    // A second finger (pinching to zoom the grid, say) is not a swipe.
    final startsSwipe =
        _pointersDown == 1 &&
        _newTabSwipeAnywhere &&
        !_newTabPromptScheduled &&
        !_drawerOpenOrDragging &&
        !_edgeDrawerGestureActive;
    _newTabSwipePointer = startsSwipe ? event.pointer : null;
    if (startsSwipe) {
      _newTabSwipeStart = event.position;
      _newTabSwipeStartTime = event.timeStamp;
    }
  }

  void _onBrowserPointerMove(PointerMoveEvent event) {
    _lastPointerEventTime = event.timeStamp;
    if (event.pointer != _newTabSwipePointer) return;
    if (_drawerOpenOrDragging ||
        _edgeDrawerGestureActive ||
        event.position.dx - _newTabSwipeStart.dx > _newTabSwipeBackoff) {
      _newTabSwipePointer = null;
    }
  }

  void _onBrowserPointerUp(PointerUpEvent event) {
    _lastPointerEventTime = event.timeStamp;
    if (_pointersDown > 0) _pointersDown--;
    if (event.pointer != _newTabSwipePointer) return;
    _newTabSwipePointer = null;
    if (!_newTabSwipeAnywhere ||
        _drawerOpenOrDragging ||
        _edgeDrawerGestureActive) {
      return;
    }
    final delta = event.position - _newTabSwipeStart;
    final elapsed = event.timeStamp - _newTabSwipeStartTime;
    final isLeftSwipe =
        delta.dx <= -_newTabSwipeThreshold &&
        delta.dx.abs() >= delta.dy.abs() * 2 &&
        elapsed <= _newTabSwipeMaxDuration;
    if (isLeftSwipe) _scheduleNewTabPrompt();
  }

  void _onBrowserPointerCancel(PointerCancelEvent event) {
    _lastPointerEventTime = event.timeStamp;
    if (_pointersDown > 0) _pointersDown--;
    if (event.pointer == _newTabSwipePointer) _newTabSwipePointer = null;
  }

  bool _onScrollbarDrag(FastScrollbarDragNotification notification) {
    if (_scrollbarDragging == notification.dragging) return true;
    _scrollbarDragging = notification.dragging;
    if (notification.dragging) {
      _scrollbarDragEndedAtTop = false;
      return true;
    }
    // Released: show the bar if the list ended up at the top, otherwise never
    // leave it stranded half-way.
    final atTop = _scrollbarDragEndedAtTop;
    _scrollbarDragEndedAtTop = false;
    for (final controller in [
      _appBarVisibilityController,
      _tabBarVisibilityController,
    ]) {
      final value = controller.value;
      final double? target = atTop
          ? 1.0
          : (value > 0.0 && value < 1.0)
          ? (value >= 0.5 ? 1.0 : 0.0)
          : null;
      if (target != null && target != value) {
        controller.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }
    return true;
  }

  void _resetEdgeSwipe() {
    _edgeSwipeEligible = false;
    _edgeSwipeStartedAtFirst = false;
    _edgeSwipeStartedAtLast = false;
    _edgeOverscrollForward = 0;
    _edgeOverscrollBackward = 0;
  }

  /// Watches horizontal drags for being pulled past the first or last tab and
  /// acts on them as the person's tab-edge-swipe setting says: offer a new tab
  /// past the last one (the first tab's right swipe belongs to the drawer), or
  /// wrap around to the tab at the other end.
  ///
  /// [pane] is the pane whose pager was swiped in the dual-pane layout: its
  /// ends are the first and last tab of that pane's group. Null is the single
  /// pager over every tab.
  void _handleTabEdgeSwipe(ScrollNotification notification, {TabPane? pane}) {
    // Something underneath (a media carousel, say) took the horizontal drag, so
    // it is not a swipe for the browser to act on.
    if (notification is ScrollStartNotification) _newTabSwipePointer = null;
    if (_newTabPromptScheduled || _loopScheduled) return;

    if (notification is ScrollStartNotification) {
      final state = _workspaceState;
      final settings = ref.read(appSettingsControllerProvider).settings;
      _resetEdgeSwipe();
      final group = pane == null ? state.tabs : state.tabsInPane(pane);
      final shownId = pane == null
          ? state.activeTabId
          : state.activeTabIdOfPane(pane);
      final shownIndex = shownId == null
          ? -1
          : group.indexWhere((tab) => tab.tabId == shownId);
      _edgeSwipePane = pane;
      _edgeSwipeEligible =
          notification.dragDetails != null &&
          settings.useBrowserTabs &&
          settings.tabEdgeSwipe.hasEdgeActions &&
          shownIndex >= 0;
      if (_edgeSwipeEligible) {
        _edgeSwipeStartedAtFirst = shownIndex == 0;
        _edgeSwipeStartedAtLast = shownIndex == group.length - 1;
      }
      return;
    }
    if (!_edgeSwipeEligible) {
      if (notification is ScrollEndNotification) _resetEdgeSwipe();
      return;
    }

    final metrics = notification.metrics;
    if (notification is OverscrollNotification) {
      // At the last page a positive horizontal overscroll means the person
      // tried to move on to a tab that is not there; at the first page, a
      // negative one means they tried to move back past it.
      if (_edgeSwipeStartedAtLast &&
          notification.overscroll > 0 &&
          metrics.extentAfter <= 0) {
        _edgeOverscrollForward += notification.overscroll;
      } else if (_edgeSwipeStartedAtFirst &&
          notification.overscroll < 0 &&
          metrics.extentBefore <= 0) {
        _edgeOverscrollBackward -= notification.overscroll;
      }
    } else if (notification is ScrollUpdateNotification) {
      // Bouncing scroll physics reports the out-of-range movement as updates
      // rather than OverscrollNotifications.
      final delta = notification.scrollDelta ?? 0;
      if (_edgeSwipeStartedAtLast && delta > 0 && metrics.extentAfter <= 0) {
        _edgeOverscrollForward += delta;
      } else if (_edgeSwipeStartedAtFirst &&
          delta < 0 &&
          metrics.extentBefore <= 0) {
        _edgeOverscrollBackward -= delta;
      }
    } else if (notification is ScrollEndNotification) {
      final forward = _edgeOverscrollForward;
      final backward = _edgeOverscrollBackward;
      final startedAtFirst = _edgeSwipeStartedAtFirst;
      final startedAtLast = _edgeSwipeStartedAtLast;
      final swipePane = _edgeSwipePane;
      // Pixels per second along the swipe: negative towards the next tab.
      final velocity = notification.dragDetails?.primaryVelocity ?? 0.0;
      _resetEdgeSwipe();
      if (_drawerOpenOrDragging || _edgeDrawerGestureActive) return;

      final loops = ref
          .read(appSettingsControllerProvider)
          .settings
          .tabEdgeSwipe
          .loops;
      if (loops) {
        final tabCount = swipePane == null
            ? _workspaceState.tabs.length
            : _workspaceState.paneTabCount(swipePane);
        if (tabCount < 2) return;
        final wantsNext =
            forward >= _newTabSwipeThreshold ||
            (forward >= _loopFlingMinOverscroll &&
                velocity <= -_loopFlingVelocity);
        final wantsPrevious =
            backward >= _newTabSwipeThreshold ||
            (backward >= _loopFlingMinOverscroll &&
                velocity >= _loopFlingVelocity);
        if (startedAtLast && wantsNext) {
          _scheduleLoopTo(0, pane: swipePane);
        } else if (startedAtFirst && wantsPrevious) {
          _scheduleLoopTo(tabCount - 1, pane: swipePane);
        }
        return;
      }
      if (startedAtLast && forward >= _newTabSwipeThreshold) {
        _scheduleNewTabPrompt(pane: swipePane);
      }
    }
  }

  /// Runs [action] after the current frame. A post-frame callback does not ask
  /// for a frame by itself, and nothing else is animating when a swipe ends on
  /// a finger lift, so one is requested; otherwise [action] would sit waiting
  /// until the next touch or notification happened to redraw the screen.
  void _afterThisFrame(VoidCallback action) {
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) => action());
    binding.ensureVisualUpdate();
  }

  void _scheduleNewTabPrompt({TabPane? pane}) {
    if (_newTabPromptScheduled) return;
    _newTabPromptScheduled = true;
    _afterThisFrame(() {
      if (!mounted) {
        _newTabPromptScheduled = false;
        return;
      }
      // The new tab joins the pane that was swiped past its last tab.
      if (pane != null) _workspaceActions.focusPane(pane);
      unawaited(
        _openNewTabSheet().whenComplete(() {
          _afterThisFrame(() => _newTabPromptScheduled = false);
        }),
      );
    });
  }

  /// Wraps to the tab at [index] once the drag that asked for it has finished
  /// dispatching its notifications.
  void _scheduleLoopTo(int index, {TabPane? pane}) {
    if (_loopScheduled) return;
    _loopScheduled = true;
    _afterThisFrame(() {
      _loopScheduled = false;
      if (!mounted) return;
      _loopToIndex(index, pane: pane);
    });
  }

  void _loopToIndex(int index, {TabPane? pane}) {
    final state = _workspaceState;
    if (pane != null) {
      // Side by side, only the swiped pane wraps round, within its own tabs.
      final group = state.tabsInPane(pane);
      if (index < 0 || index >= group.length) return;
      final target = group[index].tabId;
      if (target == state.activeTabIdOfPane(pane)) return;
      _loopingPane = pane;
      _loopTransitionController.value = 0.0;
      unawaited(
        _loopTransitionController.animateTo(1.0, curve: Curves.easeOut),
      );
      // The pane's pager follows the workspace and brings the tab up.
      _workspaceActions.activate(target);
      return;
    }
    _loopingPane = null;
    if (index < 0 || index >= state.tabs.length) return;
    if (index == state.activeIndex) return;
    if (!_pageController.hasClients) {
      _workspaceActions.activateIndex(index);
      return;
    }
    _loopTransitionController.value = 0.0;
    unawaited(_loopTransitionController.animateTo(1.0, curve: Curves.easeOut));
    // The pager reports the page change like a swipe would, which activates
    // the tab.
    _pageController.jumpToPage(index);
  }

  void _showLimitReached() {
    showAppSnackBar(
      context,
      message: context.l10n.browserTabLimitReached(kMaxBrowserTabs),
      tone: AppBannerTone.warning,
    );
  }

  Future<void> _openNewTabSheet() async {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    final active = _workspaceState.activeTab;
    if (active == null) return;
    // Respect this shell's workspace boundary. In decoy mode this callback
    // intentionally returns no vaults, even if the engine still has sessions
    // left over from an earlier normal-mode run.
    final mountedVaults = List<MountedContainer>.unmodifiable(
      widget.mountedContainers(),
    );
    final choice = await BrowserNewTabSheet.show(
      context,
      mountedVaults: mountedVaults,
      primaryLocalContainer: widget.primaryLocalContainer(),
      allowDashboard: widget.includeDashboardTab,
    );
    if (!mounted || choice == null) return;
    if (choice.container == null) {
      if (_workspaceActions.openNewDashboardTab() == null) {
        _showLimitReached();
      }
      return;
    }
    final path = choice.path;
    var container = choice.container!;
    final wasMountedVault = mountedVaults.any(
      (vault) => vault.uri == container.uri,
    );
    if (wasMountedVault) {
      final currentVaults = await ref
          .read(vaultAutomationApiProvider)
          .getActiveContainerSessions();
      if (!mounted) return;
      final current = currentVaults
          .where((vault) => vault.uri == container.uri)
          .firstOrNull;
      if (current == null) {
        showAppSnackBar(
          context,
          message:
              '${container.displayName}: ${context.l10n.vaultStatusLocked}',
          tone: AppBannerTone.warning,
        );
        return;
      }
      container = current;
    }
    final tabId = _workspaceActions.openTab(
      container,
      initialPath: (path == null || path.isEmpty) ? null : path,
    );
    if (tabId == null) _showLimitReached();
  }

  void _duplicate(BrowserTabState tab) {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    final container = tab.container;
    if (tab.isDashboard) {
      _workspaceActions.openDashboardTab();
      return;
    }
    if (container == null) return;
    final nav = ref.read(fileBrowserNavigationProvider(tab.tabId));
    final path = browserTabDuplicatePath(nav);
    final tabId = _workspaceActions.openTab(
      container,
      initialPath: path.isEmpty ? null : path,
    );
    if (tabId == null) _showLimitReached();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<ExternalStorageLocation>>(
      externalStorageLocationsProvider,
      (previous, next) {
        if (previous == null) return;
        for (final loc in previous) {
          if (!next.any((n) => n.volId == loc.volId)) {
            _workspaceActions.closeByVolId(loc.volId);
          }
        }
      },
    );
    return _buildTabs(context);
  }

  Widget _buildTabs(BuildContext context) {
    final tabs = ref.watch(browserTabsListProvider(_workspace));
    if (tabs.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }

    final activeTab = ref.watch(activeBrowserTabProvider(_workspace));
    final activeTabId = activeTab?.tabId;
    final activeContainer = activeTab?.container;
    // The app bar holds the search field, so while a search is open it stays
    // fully visible however far the list has scrolled. The collapsed state is
    // kept, and comes back when the search ends.
    final searchActive =
        activeTabId != null &&
        activeTab?.isDashboard != true &&
        ref.watch(
          fileBrowserSearchProvider(
            activeTabId,
          ).select((search) => search.active),
        );
    final toolbarSettingsUri =
        activeContainer == null || activeContainer.isLocalStorage
        ? null
        : activeContainer.uri;
    final autoHideAppBar = ref.watch(
      fileManagerToolbarSettingsProvider(
        toolbarSettingsUri,
      ).select((settings) => settings.config.autoHideAppBar),
    );
    final autoHideTabBar = ref.watch(
      fileManagerToolbarSettingsProvider(
        toolbarSettingsUri,
      ).select((settings) => settings.config.autoHideTabBar),
    );
    if (!autoHideAppBar &&
        _appBarVisibilityController.value != 1.0 &&
        !_restoreAppBarScheduled) {
      _restoreAppBarScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreAppBarScheduled = false;
        if (mounted) _appBarVisibilityController.value = 1.0;
      });
    }
    if (!autoHideTabBar &&
        _tabBarVisibilityController.value != 1.0 &&
        !_restoreTabBarScheduled) {
      _restoreTabBarScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreTabBarScheduled = false;
        if (mounted) _tabBarVisibilityController.value = 1.0;
      });
    }
    final selectionHasItems = ref.watch(
      aggregatedTabsSelectionProvider(
        _workspace,
      ).select((selection) => selection.hasSelection),
    );
    final hasMultipleTabs = ref.watch(hasActiveBrowserTabsProvider(_workspace));
    final tabsEnabled = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.useBrowserTabs),
    );
    final useDualPaneBrowsing = ref.watch(
      appSettingsControllerProvider.select(
        (s) => s.settings.useDualPaneBrowsing,
      ),
    );
    final tabEdgeSwipe = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.tabEdgeSwipe),
    );
    final appBarAtBottom = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.appBarAtBottom),
    );
    final orientation = MediaQuery.orientationOf(context);
    final minDualPaneWidth = orientation == Orientation.landscape
        ? 640.0
        : 720.0;
    final availableWidth =
        MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal;
    final splitAvailable =
        tabsEnabled &&
        useDualPaneBrowsing &&
        availableWidth >= minDualPaneWidth;
    _publishSplitAvailable(splitAvailable);
    // Each pane shows its own tab: the pair is read from the engine, not
    // guessed from the tab order.
    final paneTabIds = ref.watch(
      browserTabsProvider(_workspace).select(
        (s) => s.isSplit
            ? (
                s.activeTabIdOfPane(TabPane.primary),
                s.activeTabIdOfPane(TabPane.secondary),
              )
            : null,
      ),
    );
    final dualPaneForTabStrip = splitAvailable && paneTabIds != null;
    // Side by side, each pane swipes between its own tabs, so "first tab" and
    // "wraps around" are about the focused pane's tabs. Only the left pane's
    // first tab hands its right swipe to the side menu: that is the pane the
    // menu comes out from.
    final focusedPane = activeTab?.pane;
    final focusedTabs = !dualPaneForTabStrip || focusedPane == null
        ? tabs
        : tabs.where((tab) => tab.pane == focusedPane).toList();
    final isFirstTab =
        focusedTabs.first.tabId == activeTabId &&
        (!dualPaneForTabStrip || focusedPane == TabPane.primary);
    // Swiping past an end wraps around, within the tabs of the pager swiped.
    final loopTabs =
        tabsEnabled &&
        (dualPaneForTabStrip ? focusedTabs.length > 1 : hasMultipleTabs) &&
        tabEdgeSwipe.loops;
    // Without tab swiping every tab acts like the first one: the side menu
    // opens from any tab, and a left swipe anywhere offers a new tab.
    final tabSwipingOff = tabsEnabled && !tabEdgeSwipe.swipesBetweenTabs;
    _newTabSwipeAnywhere = tabSwipingOff;
    final systemBackGestureInsetLeft = MediaQuery.systemGestureInsetsOf(
      context,
    ).left;
    final strip = BrowserTabStrip(
      workspaceConfig: _workspace,
      onNewTab: widget.onNewTab ?? _openNewTabSheet,
      onDuplicate: widget.onDuplicate ?? _duplicate,
    );
    Widget paneStrip(TabPane pane) => BrowserTabStrip(
      key: ValueKey<TabPane>(pane),
      workspaceConfig: _workspace,
      onNewTab: widget.onNewTab ?? _openNewTabSheet,
      onDuplicate: widget.onDuplicate ?? _duplicate,
      pane: pane,
      paneBounds: _paneBounds,
      onDragOverPane: (over) => _dropPane.value = over,
    );
    final drawer = activeTab == null
        ? null
        : widget.drawerBuilder?.call(
            _workspace,
            activeTab.isDashboard ? null : activeTab.volId,
          );
    double visibleAppBarHeight() =>
        (autoHideAppBar && !searchActive
            ? _appBarVisibilityController.value
            : 1.0) *
        kToolbarHeight;

    double tabStripVisibleHeight() =>
        (autoHideTabBar ? _tabBarVisibilityController.value : 1.0) *
        kBrowserTabStripHeight;

    /// Bottom edge of the chrome stacked at the top of the screen: the status
    /// bar, app bar and tab strip.
    double browserChromeBottom() {
      final visibleTabStripHeight = tabsEnabled && tabs.isNotEmpty
          ? tabStripVisibleHeight()
          : 0.0;
      final visibleTopBarHeight = appBarAtBottom ? 0.0 : visibleAppBarHeight();
      final regularChromeHeight = visibleTopBarHeight + visibleTabStripHeight;
      final hasTopSelectionOverlay =
          !appBarAtBottom &&
          selectionHasItems &&
          _chrome.selectionAppBar.value != null;
      final topChromeHeight =
          hasTopSelectionOverlay && regularChromeHeight < kToolbarHeight
          ? kToolbarHeight
          : regularChromeHeight;
      return MediaQuery.paddingOf(context).top +
          (appBarAtBottom ? visibleTabStripHeight : topChromeHeight);
    }

    /// Whether a drag that begins at [position] may pull the drawer out. The
    /// chrome is off limits (a tab strip scrolls sideways; buttons are
    /// buttons), wherever the app bar sits.
    bool canStartDrawerGestureAt(Offset position) {
      if (position.dy < browserChromeBottom()) return false;
      if (!appBarAtBottom) return true;
      // Read, don't subscribe: this runs from a pointer handler, and
      // MediaQuery.of here would make the whole shell rebuild for every
      // MediaQuery change (the keyboard animating, say) from then on.
      final media = context.getInheritedWidgetOfExactType<MediaQuery>()?.data;
      if (media == null) return true;
      final appBarTop =
          media.size.height -
          media.viewInsets.bottom -
          media.padding.bottom -
          visibleAppBarHeight();
      return position.dy < appBarTop;
    }

    final Widget appBar = AdaptiveBrowserAppBar(
      workspaceConfig: _workspace,
      appBarListenable: _chrome.appBar,
      fallback: BrowserAppBarFallback(
        title: activeTab?.container?.displayName ?? '',
        showBackButton: widget.viewportOptions.showBackButton,
        preferBackButton: !tabsEnabled,
        onBackPressed: tabsEnabled ? null : _handleBackToDashboard,
      ),
    );
    final Widget appBarSlot = _TopAppBarSlot(
      workspaceConfig: _workspace,
      visibility: _appBarVisibilityController,
      autoHide: autoHideAppBar,
      searchActive: searchActive,
      appBar: appBar,
      selectionAppBarListenable: _chrome.selectionAppBar,
    );
    // The strip(s) slide away together with the tab bar auto-hide.
    Widget stripSlotFor(Widget child) => ClipRect(
      child: AnimatedBuilder(
        animation: _tabBarVisibilityController,
        builder: (context, child) => Align(
          alignment: Alignment.topCenter,
          heightFactor: autoHideTabBar
              ? _tabBarVisibilityController.value
              : 1.0,
          child: SizedBox(height: kBrowserTabStripHeight, child: child),
        ),
        child: child,
      ),
    );
    final Widget tabStripSlot = stripSlotFor(strip);
    final Widget bottomBarSlot = ValueListenableBuilder<Widget?>(
      valueListenable: _chrome.bottomBar,
      builder: (context, bottomBar, _) => bottomBar ?? const SizedBox.shrink(),
    );

    final shell = Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (!appBarAtBottom) appBarSlot,
                // Side by side, each pane carries its own strip instead.
                if (tabsEnabled && tabs.isNotEmpty && !dualPaneForTabStrip)
                  tabStripSlot,
                Expanded(
                  child: NotificationListener<FastScrollbarDragNotification>(
                    onNotification: _onScrollbarDrag,
                    // Not a LayoutBuilder: it reruns whenever the viewport's
                    // height changes (every frame of an app bar or tab bar
                    // auto-hide, the keyboard opening), and each run rebuilt
                    // the pager and with it every mounted tab. The width test
                    // below needs no constraints; the shell fills the window.
                    child: Builder(
                      builder: (context) {
                        final dualPane = dualPaneForTabStrip;

                        if (_wasDualPane != dualPane) {
                          final wasDualPane = _wasDualPane;
                          _wasDualPane = dualPane;
                          if (wasDualPane == true && !dualPane) {
                            _schedulePageSync();
                            // A drag cannot outlive the layout it was in.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _dropPane.value = null;
                            });
                          }
                        }

                        if (dualPane) {
                          final ids = paneTabIds!;
                          final firstId = ids.$1!;
                          final secondId = ids.$2!;
                          final firstTab = tabs.firstWhere(
                            (tab) => tab.tabId == firstId,
                            orElse: () => tabs.first,
                          );
                          final secondTab = tabs.firstWhere(
                            (tab) => tab.tabId == secondId,
                            orElse: () => tabs.last,
                          );
                          _publishVisibleTabs({firstId, secondId});
                          final swipeEnabled =
                              tabsEnabled &&
                              tabEdgeSwipe.swipesBetweenTabs &&
                              !_drawerOpenOrDragging &&
                              !_edgeDrawerGestureActive;
                          return Row(
                            children: [
                              _buildDualPaneViewport(
                                TabPane.primary,
                                groupTabs: tabs
                                    .where((tab) => tab.pane == TabPane.primary)
                                    .toList(),
                                shownTabId: firstTab.tabId,
                                activeTabId: activeTabId,
                                stripSlot: stripSlotFor(
                                  paneStrip(TabPane.primary),
                                ),
                                swipeEnabled: swipeEnabled,
                                autoHideAppBar: autoHideAppBar,
                                autoHideTabBar: autoHideTabBar,
                              ),
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: Theme.of(context).dividerColor,
                              ),
                              _buildDualPaneViewport(
                                TabPane.secondary,
                                groupTabs: tabs
                                    .where(
                                      (tab) => tab.pane == TabPane.secondary,
                                    )
                                    .toList(),
                                shownTabId: secondTab.tabId,
                                activeTabId: activeTabId,
                                stripSlot: stripSlotFor(
                                  paneStrip(TabPane.secondary),
                                ),
                                swipeEnabled: swipeEnabled,
                                autoHideAppBar: autoHideAppBar,
                                autoHideTabBar: autoHideTabBar,
                              ),
                            ],
                          );
                        }

                        _publishVisibleTabs(const <TabId>{});
                        // Only the pager gets the larger touch slop; every page
                        // keeps the platform's own, so lists inside a tab scroll
                        // as usual.
                        final pageMedia = MediaQuery.of(context);
                        final pagerMedia = pageMedia.copyWith(
                          gestureSettings: DeviceGestureSettings(
                            touchSlop:
                                (pageMedia.gestureSettings.touchSlop ??
                                    kTouchSlop) *
                                _tabPagerSlopFactor,
                          ),
                        );
                        return Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: _onBrowserPointerDown,
                          onPointerMove: _onBrowserPointerMove,
                          onPointerUp: _onBrowserPointerUp,
                          onPointerCancel: _onBrowserPointerCancel,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notification) =>
                                _handleAppBarScroll(
                                  notification,
                                  enabled: autoHideAppBar,
                                  autoHideTabBar: autoHideTabBar,
                                  active: activeTabId != null,
                                ),
                            child: FadeTransition(
                              opacity: _loopFade,
                              child: MediaQuery(
                                data: pagerMedia,
                                child: PageView.builder(
                                  controller: _pageController,
                                  // The larger slop would otherwise swallow the
                                  // first stretch of the swipe; count the drag
                                  // from the touch-down so it still tracks.
                                  dragStartBehavior: DragStartBehavior.down,
                                  clipBehavior: Clip.hardEdge,
                                  // The gated physics snap to pages themselves
                                  // (PageView would put its own ahead of them, out
                                  // of reach of the gate).
                                  pageSnapping: false,
                                  physics: GatedPageScrollPhysics(
                                    gate: _swipeGate,
                                    parent:
                                        tabsEnabled &&
                                            tabEdgeSwipe.swipesBetweenTabs &&
                                            !_drawerOpenOrDragging &&
                                            !_edgeDrawerGestureActive
                                        ? const AlwaysScrollableScrollPhysics()
                                        : const NeverScrollableScrollPhysics(),
                                  ),
                                  itemCount: tabs.length,
                                  onPageChanged: _onPageChanged,
                                  findChildIndexCallback: (key) {
                                    if (key is! ValueKey<TabId>) return null;
                                    final index = tabs.indexWhere(
                                      (tab) => tab.tabId == key.value,
                                    );
                                    return index < 0 ? null : index;
                                  },
                                  itemBuilder: (context, index) {
                                    final tab = tabs[index];
                                    final pageIsActive =
                                        tab.tabId == activeTabId;
                                    // Whether the page's tickers run (thumbnail loading,
                                    // folder previews) follows what is on screen, not
                                    // which tab is active: the active tab only changes
                                    // once a swipe passes the half-way point, which used
                                    // to blank the leaving page and delay the entering
                                    // one for half the transition.
                                    return _BrowserTabPage(
                                      key: ValueKey<TabId>(tab.tabId),
                                      controller: _pageController,
                                      index: index,
                                      child: MediaQuery(
                                        data: pageMedia,
                                        child: _buildTabContent(
                                          tab,
                                          isActive: pageIsActive,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!appBarAtBottom)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopSelectionBarOverlay(
                workspaceConfig: _workspace,
                selectionAppBarListenable: _chrome.selectionAppBar,
              ),
            ),
        ],
      ),
      floatingActionButton: ValueListenableBuilder<Widget?>(
        valueListenable: _chrome.floatingAction,
        builder: (context, action, _) => action ?? const SizedBox.shrink(),
      ),
      bottomNavigationBar: appBarAtBottom
          ? Padding(
              // Scaffold lets the keyboard cover its bottom bar, and the app
              // bar holds the search field, so it rides above the keyboard.
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The app bar goes under this slot, at the screen's edge, and
                  // so takes over the system navigation inset it would pad for.
                  MediaQuery.removeViewInsets(
                    context: context,
                    removeBottom: true,
                    child: MediaQuery.removePadding(
                      context: context,
                      removeBottom: true,
                      child: bottomBarSlot,
                    ),
                  ),
                  _BottomAppBarSlot(
                    workspaceConfig: _workspace,
                    visibility: _appBarVisibilityController,
                    autoHide: autoHideAppBar,
                    searchActive: searchActive,
                    appBar: appBar,
                    selectionAppBarListenable: _chrome.selectionAppBar,
                  ),
                  _AppBarInsetFill(
                    area: activeTab?.isDashboard == true
                        ? SkinArea.dashboard
                        : SkinArea.files,
                  ),
                ],
              ),
            )
          : bottomBarSlot,
    );

    // Must wrap the whole screen: the system-bar probe points sit *behind* the
    // status/nav bars, outside the SafeArea that the app bar and
    // DirectoryContentView live in. Without this, nothing re-applies the
    // theme's style after a full-screen viewer (which sets light icons) closes.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUI.forTheme(Theme.of(context)),
      child: FullScreenDragDrawer(
        drawer: drawer,
        onDrawerChanged: _onDrawerChanged,
        onEdgeGestureChanged: _onEdgeDrawerGestureChanged,
        edgeGestureTop: browserChromeBottom(),
        edgeGestureTopBuilder: browserChromeBottom,
        canStartGestureAt: canStartDrawerGestureAt,
        // Reserve the left edge of the viewport for drawer opening while the
        // PageView keeps native swipes everywhere else. On the first tab a right
        // swipe may open it from anywhere, unless that swipe is what loops the
        // tabs round to the last one or the person turned that action off. With
        // tab swiping off there is no pager to keep out of the way.
        canOpenFromAnywhere:
            !(tabsEnabled && hasMultipleTabs) ||
            tabSwipingOff ||
            (isFirstTab &&
                switch (tabEdgeSwipe) {
                  BrowserTabEdgeSwipe.drawerAndNewTab => true,
                  // Side by side there is no pager to loop, so the swipe is free.
                  BrowserTabEdgeSwipe.loop => !loopTabs,
                  BrowserTabEdgeSwipe.noEdgeActions ||
                  BrowserTabEdgeSwipe.noTabSwiping => false,
                }),
        backGestureInsetLeft: systemBackGestureInsetLeft < 24
            ? 24
            : systemBackGestureInsetLeft,
        child: shell,
      ),
    );
  }
}

/// The top app bar stays in the normal auto-hiding layout slot. A selection
/// bar overlays it separately, so showing selection actions never changes the
/// viewport's layout.
class _TopAppBarSlot extends ConsumerWidget {
  const _TopAppBarSlot({
    required this.workspaceConfig,
    required this.visibility,
    required this.autoHide,
    required this.searchActive,
    required this.appBar,
    required this.selectionAppBarListenable,
  });

  final BrowserTabsConfig workspaceConfig;
  final Animation<double> visibility;
  final bool autoHide;
  final bool searchActive;
  final Widget appBar;
  final ValueListenable<BrowserAppBarFactory?> selectionAppBarListenable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSelection = ref.watch(
      aggregatedTabsSelectionProvider(
        workspaceConfig,
      ).select((selection) => selection.hasSelection),
    );
    return ValueListenableBuilder<BrowserAppBarFactory?>(
      valueListenable: selectionAppBarListenable,
      builder: (context, selectionAppBar, _) {
        final selecting = hasSelection && selectionAppBar != null;
        return ClipRect(
          child: AnimatedBuilder(
            animation: visibility,
            builder: (context, child) => Align(
              key: const Key('browser_app_bar_align'),
              alignment: Alignment.bottomCenter,
              heightFactor: autoHide && !searchActive
                  ? visibility.value
                  : 1.0,
              child: SizedBox(height: kToolbarHeight, child: child),
            ),
            child: SizedBox(
              height: kToolbarHeight,
              child: Offstage(offstage: selecting, child: appBar),
            ),
          ),
        );
      },
    );
  }
}

/// Selection actions cover the top toolbar and remain outside the layout
/// flow. When scroll reveals the normal app bar, this overlay already occupies
/// its position, so the listing does not jump when selection starts.
class _TopSelectionBarOverlay extends ConsumerWidget {
  const _TopSelectionBarOverlay({
    required this.workspaceConfig,
    required this.selectionAppBarListenable,
  });

  final BrowserTabsConfig workspaceConfig;
  final ValueListenable<BrowserAppBarFactory?> selectionAppBarListenable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSelection = ref.watch(
      aggregatedTabsSelectionProvider(
        workspaceConfig,
      ).select((selection) => selection.hasSelection),
    );
    return ValueListenableBuilder<BrowserAppBarFactory?>(
      valueListenable: selectionAppBarListenable,
      builder: (context, selectionAppBar, _) {
        if (!hasSelection || selectionAppBar == null) {
          return const SizedBox.shrink();
        }
        return Material(
          key: const ValueKey<String>('browser_selection_app_bar_overlay'),
          color: Theme.of(context).colorScheme.surfaceContainer,
          elevation: 0,
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              width: double.infinity,
              height: kToolbarHeight,
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: SkinAreaScope(
                  area: SkinArea.files,
                  child: Builder(
                    builder: (appBarContext) => selectionAppBar(appBarContext),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Paints the system navigation inset under a bottom app bar in the bar's own
/// color, so the bar seems to run to the very edge of the screen. It stays put
/// when the bar auto-hides, which keeps the pages clear of the system bar.
class _AppBarInsetFill extends StatelessWidget {
  const _AppBarInsetFill({required this.area});

  final SkinArea area;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.paddingOf(context).bottom;
    if (inset <= 0) return const SizedBox.shrink();
    return SkinAreaScope(
      area: area,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return ColoredBox(
            color:
                theme.appBarTheme.backgroundColor ?? theme.colorScheme.surface,
            child: SizedBox(width: double.infinity, height: inset),
          );
        },
      ),
    );
  }
}

/// The app bar slot for when the bar sits at the bottom of the screen.
///
/// It collapses towards the screen edge, and while something is selected the
/// selection app bar takes the bar's place. The browser's own bar stays built
/// underneath, hidden, so its state (an open search, say) is still there when
/// the selection ends. Selecting also brings back an auto-hidden bar, since the
/// selection actions have to be reachable.
class _BottomAppBarSlot extends ConsumerWidget {
  const _BottomAppBarSlot({
    required this.workspaceConfig,
    required this.visibility,
    required this.autoHide,
    required this.searchActive,
    required this.appBar,
    required this.selectionAppBarListenable,
  });

  final BrowserTabsConfig workspaceConfig;
  final Animation<double> visibility;
  final bool autoHide;

  /// A search is open: the bar holds its field, so it is kept fully visible.
  final bool searchActive;
  final Widget appBar;
  final ValueListenable<BrowserAppBarFactory?> selectionAppBarListenable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSelection = ref.watch(
      aggregatedTabsSelectionProvider(
        workspaceConfig,
      ).select((selection) => selection.hasSelection),
    );
    return ValueListenableBuilder<BrowserAppBarFactory?>(
      valueListenable: selectionAppBarListenable,
      builder: (context, selectionAppBar, _) {
        final selectionBar = hasSelection ? selectionAppBar : null;
        final selecting = selectionBar != null;
        return ClipRect(
          child: AnimatedBuilder(
            animation: visibility,
            builder: (context, child) => Align(
              key: const Key('browser_app_bar_align'),
              alignment: Alignment.topCenter,
              heightFactor: autoHide && !selecting && !searchActive
                  ? visibility.value
                  : 1.0,
              child: SizedBox(height: kToolbarHeight, child: child),
            ),
            // Down here there is no status bar for the bar to pad for.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Offstage(offstage: selecting, child: appBar),
                  if (selectionBar != null)
                    SkinAreaScope(
                      key: const Key('browser_selection_app_bar_overlay'),
                      area: SkinArea.files,
                      child: Builder(
                        builder: (appBarContext) => selectionBar(appBarContext),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// PageView lazily keeps only its nearby pages alive. Each browser tab owns
/// navigation and selection state, so retain its subtree after it scrolls out
/// of view.
///
/// It also decides whether the page's tickers are enabled. That has to follow
/// the page's position in the viewport rather than the active tab: during a
/// swipe both the leaving and the entering page are partly visible, and both
/// must keep painting their thumbnails until the leaving one is fully gone.
class _BrowserTabPage extends StatefulWidget {
  final PageController controller;
  final int index;
  final Widget child;

  const _BrowserTabPage({
    super.key,
    required this.controller,
    required this.index,
    required this.child,
  });

  @override
  State<_BrowserTabPage> createState() => _BrowserTabPageState();
}

class _BrowserTabPageState extends State<_BrowserTabPage>
    with AutomaticKeepAliveClientMixin<_BrowserTabPage> {
  /// A neighbour at rest sits exactly one page away; the small slack keeps
  /// floating-point noise at the end of a settle from counting as "visible".
  static const double _visibleSpan = 0.999;

  late bool _onScreen;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScrolled);
    _onScreen = _computeOnScreen();
  }

  @override
  void didUpdateWidget(covariant _BrowserTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScrolled);
      widget.controller.addListener(_onScrolled);
    }
    // A reorder or close can move this page to another index without any
    // scrolling, so re-evaluate here too.
    _onScreen = _computeOnScreen();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScrolled);
    super.dispose();
  }

  bool _computeOnScreen() {
    final controller = widget.controller;
    // Before the first layout there is no scroll position yet; the initial
    // page is the one being shown. `PageController.page` is avoided on
    // purpose: it asserts that content dimensions exist, which is not yet
    // true when a page is built during the viewport's first layout.
    var page = controller.initialPage.toDouble();
    if (controller.hasClients) {
      final position = controller.position;
      if (position.hasPixels &&
          position.hasViewportDimension &&
          position.viewportDimension > 0) {
        page = position.pixels / position.viewportDimension;
      }
    }
    return (page - widget.index).abs() < _visibleSpan;
  }

  void _onScrolled() {
    final onScreen = _computeOnScreen();
    if (onScreen == _onScreen || !mounted) return;
    setState(() => _onScreen = onScreen);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return TickerMode(enabled: _onScreen, child: widget.child);
  }
}

/// The pager of one pane in the dual-pane layout. Swiping sideways moves
/// between the tabs of that pane only; the other pane keeps what it shows.
///
/// It follows the workspace the way the single pager does: a tab switched from
/// elsewhere (the strip, a close, a move) is brought up without a slide, and a
/// page change the swipe itself made is not jumped back over.
class _PaneTabPager extends StatefulWidget {
  final TabPane pane;
  final List<BrowserTabState> tabs;
  final TabId? shownTabId;
  final ValueChanged<TabId> onTabChanged;
  final Widget Function(BrowserTabState tab) pageBuilder;
  final PagerSwipeGate gate;
  final bool swipeEnabled;

  /// The pager's touch slop, as a multiple of the platform's (see the single
  /// pager for why it is larger).
  final double slopFactor;
  final Animation<double> fade;

  const _PaneTabPager({
    super.key,
    required this.pane,
    required this.tabs,
    required this.shownTabId,
    required this.onTabChanged,
    required this.pageBuilder,
    required this.gate,
    required this.swipeEnabled,
    required this.slopFactor,
    required this.fade,
  });

  @override
  State<_PaneTabPager> createState() => _PaneTabPagerState();
}

class _PaneTabPagerState extends State<_PaneTabPager> {
  late final PageController _controller;

  /// The page a swipe has just reported. The workspace change that follows
  /// must not jump the pager there again while it is still settling.
  int? _drivenIndex;
  bool _jumping = false;

  static int _indexOf(List<BrowserTabState> tabs, TabId? id) =>
      id == null ? -1 : tabs.indexWhere((tab) => tab.tabId == id);

  static bool _sameTabs(List<BrowserTabState> a, List<BrowserTabState> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].tabId != b[i].tabId) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    final index = _indexOf(widget.tabs, widget.shownTabId);
    _controller = SettleTouchPageController(initialPage: index < 0 ? 0 : index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _PaneTabPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameTabs = _sameTabs(oldWidget.tabs, widget.tabs);
    if (sameTabs && oldWidget.shownTabId == widget.shownTabId) return;
    final index = _indexOf(widget.tabs, widget.shownTabId);
    if (sameTabs && _drivenIndex != null && _drivenIndex == index) {
      // The swipe got there by itself.
      return;
    }
    _drivenIndex = null;
    // A tab the list did not hold before can only be switched to once the new
    // list is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _indexOf(widget.tabs, widget.shownTabId);
      if (target >= 0) _jumpTo(target);
    });
  }

  /// Called as soon as the workspace changes, before the pager is rebuilt. A
  /// tab among the pages already laid out is switched to in the same frame, so
  /// a close or reorder never paints the wrong tab or springs back.
  void syncTo(BrowserTabsState next) {
    final group = next.tabsInPane(widget.pane);
    final target = _indexOf(group, next.activeTabIdOfPane(widget.pane));
    if (target < 0 || _drivenIndex == target) return;
    if (target < widget.tabs.length) _jumpTo(target);
  }

  void _jumpTo(int target) {
    if (!_controller.hasClients) return;
    final current = _controller.page;
    if (current != null && (current - target).abs() <= 0.01) return;
    _jumping = true;
    try {
      _controller.jumpToPage(target);
    } finally {
      _jumping = false;
    }
  }

  void _onPageChanged(int index) {
    // Our own jump reports a page change too; it is not a swipe.
    if (_jumping || index < 0 || index >= widget.tabs.length) return;
    final tab = widget.tabs[index];
    if (tab.tabId == widget.shownTabId) return;
    _drivenIndex = index;
    widget.onTabChanged(tab.tabId);
    // The rebuild this causes happens in the next frame; after it the page
    // change no longer counts as one the swipe just made.
    WidgetsBinding.instance.addPostFrameCallback((_) => _drivenIndex = null);
  }

  @override
  Widget build(BuildContext context) {
    final pageMedia = MediaQuery.of(context);
    final pagerMedia = pageMedia.copyWith(
      gestureSettings: DeviceGestureSettings(
        touchSlop:
            (pageMedia.gestureSettings.touchSlop ?? kTouchSlop) *
            widget.slopFactor,
      ),
    );
    final tabs = widget.tabs;
    return FadeTransition(
      opacity: widget.fade,
      child: MediaQuery(
        data: pagerMedia,
        child: PageView.builder(
          controller: _controller,
          dragStartBehavior: DragStartBehavior.down,
          clipBehavior: Clip.hardEdge,
          pageSnapping: false,
          physics: GatedPageScrollPhysics(
            gate: widget.gate,
            parent: widget.swipeEnabled
                ? const AlwaysScrollableScrollPhysics()
                : const NeverScrollableScrollPhysics(),
          ),
          itemCount: tabs.length,
          onPageChanged: _onPageChanged,
          findChildIndexCallback: (key) {
            if (key is! ValueKey<TabId>) return null;
            final index = tabs.indexWhere((tab) => tab.tabId == key.value);
            return index < 0 ? null : index;
          },
          itemBuilder: (context, index) {
            final tab = tabs[index];
            return _BrowserTabPage(
              key: ValueKey<TabId>(tab.tabId),
              controller: _controller,
              index: index,
              child: MediaQuery(
                data: pageMedia,
                child: widget.pageBuilder(tab),
              ),
            );
          },
        ),
      ),
    );
  }
}
