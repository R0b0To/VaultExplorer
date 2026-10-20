import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_new_tab_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_tab_strip.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

class _BrowserTabSwipePhysics extends ScrollPhysics {
  const _BrowserTabSwipePhysics({required this.gate, super.parent});

  final _BrowserTabSwipeGate gate;

  @override
  _BrowserTabSwipePhysics applyTo(ScrollPhysics? ancestor) =>
      _BrowserTabSwipePhysics(gate: gate, parent: buildParent(ancestor));

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) =>
      gate.allowSwipe && super.shouldAcceptUserOffset(position);

  @override
  double get minFlingDistance => 20.0;

  @override
  double get minFlingVelocity => 100.0;
}

class _BrowserTabSwipeGate {
  bool allowSwipe = true;
}

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

/// Builds the route that shows the file manager with tab support. Replaces
/// pushing a bare [FileBrowserScreen]: with a single tab it looks and behaves
/// the same, and opening more tabs reveals the tab strip.
Route<void> buildBrowserTabsRoute({
  required MountedContainer container,
  required MountedContainer? Function(int volId) resolveContainer,
  required List<MountedContainer> Function() mountedContainers,
  required MountedContainer? Function() primaryLocalContainer,
  Widget Function(BrowserTabsController tabs, int? currentVolId)? drawerBuilder,
  VoidCallback? Function(int volId)? userActivityFor,
  ValueChanged<BrowserTabsController?>? onTabsController,
  bool closeRouteWhenEmpty = true,
  bool includeDashboardTab = false,
  VoidCallback? onEmpty,
  VoidCallback? onNewTab,
  ValueChanged<BrowserTab>? onDuplicate,
}) {
  return MaterialPageRoute<void>(
    builder: (_) => SkinAreaScope(
      area: SkinArea.files,
      child: BrowserTabsHost(
        initialContainer: container,
        resolveContainer: resolveContainer,
        mountedContainers: mountedContainers,
        primaryLocalContainer: primaryLocalContainer,
        drawerBuilder: drawerBuilder,
        userActivityFor: userActivityFor,
        onTabsController: onTabsController,
        closeRouteWhenEmpty: closeRouteWhenEmpty,
        includeDashboardTab: includeDashboardTab,
        onEmpty: onEmpty,
        onNewTab: onNewTab,
        onDuplicate: onDuplicate,
      ),
    ),
  );
}

/// Hosts one page per open location. A horizontal [PageView] lets a tab follow
/// the finger while keeping each tab's navigation and selection state alive;
/// each file tab's Riverpod state is scoped by its tab key (see
/// [BrowserTab.key]) instead of its volume, so two tabs on the same vault are
/// independent.
class BrowserTabsHost extends ConsumerStatefulWidget {
  final MountedContainer? initialContainer;
  final MountedContainer? Function(int volId) resolveContainer;
  final List<MountedContainer> Function() mountedContainers;
  final MountedContainer? Function() primaryLocalContainer;

  /// Builds the navigation drawer for a tab on [currentVolId]. The drawer's
  /// "switch vault" actions should call `tabs.replaceActive` while hosted.
  final Widget Function(BrowserTabsController tabs, int? currentVolId)?
  drawerBuilder;

  /// Returns the auto-lock activity callback for the tab on [volId]. Only
  /// the active tab's callback is wired, so a vault used only through a
  /// background tab keeps its normal idle timer.
  final VoidCallback? Function(int volId)? userActivityFor;

  /// Called with the live controller once the host is mounted, and with null
  /// when it is disposed, so the owner can route its own drawer actions
  /// (e.g. "open local storage") into the tab list.
  final ValueChanged<BrowserTabsController?>? onTabsController;
  final bool closeRouteWhenEmpty;
  final bool includeDashboardTab;
  final Widget Function(
    ValueListenable<double> pagePosition,
    int index,
    ValueChanged<BrowserTab> onActivateTab,
    ValueChanged<bool> onVerticalScrollActivity,
    bool backPreviewOnly,
  )?
  dashboardBuilder;
  final VoidCallback? onEmpty;
  final VoidCallback? onNewTab;
  final ValueChanged<BrowserTab>? onDuplicate;

  const BrowserTabsHost({
    super.key,
    this.initialContainer,
    required this.resolveContainer,
    required this.mountedContainers,
    required this.primaryLocalContainer,
    this.drawerBuilder,
    this.userActivityFor,
    this.onTabsController,
    this.closeRouteWhenEmpty = true,
    this.includeDashboardTab = false,
    this.dashboardBuilder,
    this.onEmpty,
    this.onNewTab,
    this.onDuplicate,
  });

  @override
  ConsumerState<BrowserTabsHost> createState() => _BrowserTabsHostState();
}

class _BrowserTabsHostState extends ConsumerState<BrowserTabsHost> {
  static const _drawerTickerGracePeriod = Duration(milliseconds: 400);

  late final BrowserTabsController _tabs;
  late final VaultEngineEvents _vaultEvents;
  late final PageController _pageController;
  late final ValueNotifier<double> _pagePosition;
  final GlobalKey _tabStripKey = GlobalKey();
  final Set<int> _drawerTickerTabKeys = {};
  final Set<int> _verticallyScrollingTabKeys = {};
  final _BrowserTabSwipeGate _pageSwipeGate = _BrowserTabSwipeGate();
  late final _BrowserTabSwipePhysics _pageSwipePhysics =
      _BrowserTabSwipePhysics(gate: _pageSwipeGate);
  final Map<int, Timer> _drawerTickerTimers = {};
  bool _popScheduled = false;
  bool _pageDragActive = false;
  bool _pageSyncScheduled = false;
  int _pagePointerCount = 0;
  int? _lastActiveTabKey;
  int _lastTabCount = 0;

  @override
  void initState() {
    super.initState();
    _tabs = BrowserTabsController(
      widget.initialContainer,
      includeDashboardTab: widget.includeDashboardTab,
    );
    _lastActiveTabKey = _tabs.activeKey;
    _lastTabCount = _tabs.length;
    _pageController = PageController(initialPage: _tabs.activeIndex);
    _pagePosition = ValueNotifier(_tabs.activeIndex.toDouble());
    _pageController.addListener(_updatePagePosition);
    _tabs.addListener(_onTabsChanged);
    _vaultEvents = ref.read(vaultEngineEventsProvider);
    _vaultEvents.addContainerLockedListener(_onVolumeGone);
    _vaultEvents.addUsbContainerDetachedListener(_onVolumeGone);
    widget.onTabsController?.call(_tabs);
  }

  @override
  void dispose() {
    for (final timer in _drawerTickerTimers.values) {
      timer.cancel();
    }
    _drawerTickerTimers.clear();
    _drawerTickerTabKeys.clear();
    widget.onTabsController?.call(null);
    _vaultEvents.removeContainerLockedListener(_onVolumeGone);
    _vaultEvents.removeUsbContainerDetachedListener(_onVolumeGone);
    _tabs.removeListener(_onTabsChanged);
    _pageController.removeListener(_updatePagePosition);
    _pageController.dispose();
    _pagePosition.dispose();
    _tabs.dispose();
    super.dispose();
  }

  void _updatePagePosition() {
    if (!_pageController.hasClients) return;
    final page = _pageController.page;
    if (page != null && page.isFinite && _pagePosition.value != page) {
      _pagePosition.value = page;
    }
  }

  /// A vault was locked or a USB container detached: every tab on it goes
  /// away; the route only closes once no tab is left.
  void _onVolumeGone(int volId) {
    if (!mounted) return;
    _tabs.closeByVolId(volId);
  }

  void _onTabsChanged() {
    final tabCount = _tabs.length;
    final tabsWereRemoved = tabCount < _lastTabCount;
    _lastTabCount = tabCount;
    if (tabsWereRemoved &&
        !_pageDragActive &&
        tabCount > 0 &&
        _pageController.hasClients) {
      // A shorter PageView can leave its old page outside the new extent for
      // a frame. Move to the surviving tab before painting that empty range.
      _pageController.jumpToPage(_tabs.activeIndex);
    }
    _schedulePageSync();
    final liveTabKeys = _tabs.tabs.map((tab) => tab.key).toSet();
    final activeKey = _tabs.activeKey;
    if (_lastActiveTabKey != activeKey) {
      if (_lastActiveTabKey != null) {
        _verticallyScrollingTabKeys.remove(_lastActiveTabKey);
      }
      _lastActiveTabKey = activeKey;
    }
    _verticallyScrollingTabKeys.removeWhere(
      (key) => !liveTabKeys.contains(key),
    );
    _drawerTickerTabKeys.removeWhere((key) => !liveTabKeys.contains(key));
    for (final key in _drawerTickerTimers.keys.toList()) {
      if (liveTabKeys.contains(key)) continue;
      _drawerTickerTimers.remove(key)?.cancel();
      _drawerTickerTabKeys.remove(key);
    }
    if (!_tabs.isEmpty || _popScheduled) return;
    _popScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _popScheduled = false;
      if (!_tabs.isEmpty) return;
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

  void _schedulePageSync() {
    if (_pageSyncScheduled || _pageDragActive) return;
    _pageSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageSyncScheduled = false;
      if (!mounted || _pageDragActive || !_pageController.hasClients) {
        return;
      }
      final target = _tabs.activeIndex;
      if (target < 0 || target >= _tabs.length) return;
      final page = _pageController.page;
      if (page != null && (page - target).abs() < 0.001) return;
      _pageController.jumpToPage(target);
    });
  }

  void _activateTabFromStrip(BrowserTab tab) {
    final index = _tabs.tabs.indexWhere(
      (candidate) => candidate.key == tab.key,
    );
    if (index < 0) return;
    // A direct tab tap switches immediately without a page transition.
    if (_pageController.hasClients) {
      _pageController.jumpToPage(index);
    }
    _tabs.activate(tab.key);
  }

  void _setTabVerticalScrollActivity(int tabKey, bool scrolling) {
    if (scrolling) {
      _verticallyScrollingTabKeys.add(tabKey);
    } else {
      _verticallyScrollingTabKeys.remove(tabKey);
    }
  }

  void _handleTabPointerDown(PointerDownEvent event) {
    if (_pagePointerCount++ > 0) return;
    final allowSwipe = !_verticallyScrollingTabKeys.contains(_tabs.activeKey);
    if (_pageSwipeGate.allowSwipe == allowSwipe) return;
    _pageSwipeGate.allowSwipe = allowSwipe;
    if (mounted) setState(() {});
  }

  void _handleTabPointerEnd(PointerEvent event) {
    if (_pagePointerCount > 0) _pagePointerCount--;
    if (_pagePointerCount > 0 || _pageSwipeGate.allowSwipe) return;
    _pageSwipeGate.allowSwipe = true;
    if (mounted) setState(() {});
  }

  bool _handlePageScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _pageDragActive = true;
    } else if (notification is ScrollEndNotification) {
      final wasDragging = _pageDragActive;
      _pageDragActive = false;
      if (wasDragging) _schedulePageSync();
    }
    return false;
  }

  void _onPageChanged(int index, List<BrowserTab> tabs) {
    if (index < 0 || index >= tabs.length) return;
    _tabs.activate(tabs[index].key);
  }

  void _onTabDrawerChanged(int tabKey, bool isOpen) {
    _drawerTickerTimers.remove(tabKey)?.cancel();
    _drawerTickerTabKeys.add(tabKey);
    if (!isOpen) {
      _drawerTickerTimers[tabKey] = Timer(_drawerTickerGracePeriod, () {
        _drawerTickerTimers.remove(tabKey);
        _drawerTickerTabKeys.remove(tabKey);
        if (mounted) setState(() {});
      });
    }
    if (mounted) setState(() {});
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
    final active = _tabs.activeTab;
    if (active == null) return;
    final nav = active.isDashboard
        ? null
        : ref.read(fileBrowserNavigationProvider(active.key));
    final choice = await BrowserNewTabSheet.show(
      context,
      currentContainer: active.container,
      currentDirPath: nav == null ? '' : browserTabDuplicatePath(nav),
      mountedVaults: widget.mountedContainers(),
      primaryLocalContainer: widget.primaryLocalContainer(),
      allowDashboard: widget.includeDashboardTab,
    );
    if (!mounted || choice == null) return;
    if (choice.container == null) {
      _tabs.openDashboardTab();
      return;
    }
    final path = choice.path;
    final key = _tabs.openTab(
      choice.container!,
      initialPath: (path == null || path.isEmpty) ? null : path,
    );
    if (key == null) _showLimitReached();
  }

  void _duplicate(BrowserTab tab) {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    final container = tab.container;
    if (tab.isDashboard) {
      _tabs.openDashboardTab();
      return;
    }
    if (container == null) return;
    final nav = ref.read(fileBrowserNavigationProvider(tab.key));
    final path = browserTabDuplicatePath(nav);
    final key = _tabs.openTab(
      container,
      initialPath: path.isEmpty ? null : path,
    );
    if (key == null) _showLimitReached();
  }

  @override
  Widget build(BuildContext context) {
    // A removed external storage takes its tabs with it (the screens' own
    // handler would otherwise pop the whole route).
    ref.listen<List<ExternalStorageLocation>>(
      externalStorageLocationsProvider,
      (previous, next) {
        if (previous == null) return;
        for (final loc in previous) {
          if (!next.any((n) => n.volId == loc.volId)) {
            _tabs.closeByVolId(loc.volId);
          }
        }
      },
    );

    return BrowserTabsScope(
      controller: _tabs,
      child: ListenableBuilder(
        listenable: _tabs,
        builder: (context, _) => _buildTabs(context),
      ),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final tabs = _tabs.tabs;
    if (tabs.isEmpty) {
      // Transient: the route is being popped (see _onTabsChanged).
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }

    final activeKey = _tabs.activeKey;

    // The strip itself is rendered by each screen, directly under its own app
    // bar (the app bar lives inside the screen), so the host only has to hand
    // every tab the same strip widget. Only the visible tab shows it.
    final strip = BrowserTabStrip(
      key: _tabStripKey,
      controller: _tabs,
      onNewTab: widget.onNewTab ?? _openNewTabSheet,
      onDuplicate: widget.onDuplicate ?? _duplicate,
      onActivateTab: _activateTabFromStrip,
    );

    final dashboard = widget.dashboardBuilder;
    final dashboardBackPreview =
        dashboard != null && _tabs.activeTab?.returnToDashboardOnRoot == true
        ? IgnorePointer(
            child: SkinAreaScope(
              area: SkinArea.dashboard,
              child: dashboard(
                _pagePosition,
                _tabs.activeIndex,
                _activateTabFromStrip,
                (scrolling) => _setTabVerticalScrollActivity(
                  _tabs.dashboardTab?.key ?? -1,
                  scrolling,
                ),
                true,
              ),
            ),
          )
        : null;

    final pageView = Listener(
      onPointerDown: _handleTabPointerDown,
      onPointerUp: _handleTabPointerEnd,
      onPointerCancel: _handleTabPointerEnd,
      child: NotificationListener<ScrollNotification>(
        onNotification: _handlePageScroll,
        child: PageView.builder(
          controller: _pageController,
          physics: _pageSwipePhysics,
          clipBehavior: Clip.hardEdge,
          itemCount: tabs.length,
          onPageChanged: (index) => _onPageChanged(index, tabs),
          findChildIndexCallback: (key) {
            if (key is! ValueKey<int>) return null;
            final index = tabs.indexWhere((tab) => tab.key == key.value);
            return index < 0 ? null : index;
          },
          itemBuilder: (context, index) {
            final tab = tabs[index];
            final pageIsActive = tab.key == activeKey;
            final Widget page;
            if (tab.isDashboard) {
              page = dashboard == null
                  ? const SizedBox.expand()
                  : SkinAreaScope(
                      area: SkinArea.dashboard,
                      child: dashboard(
                        _pagePosition,
                        index,
                        _activateTabFromStrip,
                        (scrolling) =>
                            _setTabVerticalScrollActivity(tab.key, scrolling),
                        false,
                      ),
                    );
            } else {
              page = FileBrowserScreen(
                container: tab.container!,
                tabKey: tab.key,
                tabStrip: strip,
                initialPath: tab.initialPath,
                resolveContainer: widget.resolveContainer,
                onDrawerChanged: (isOpen) =>
                    _onTabDrawerChanged(tab.key, isOpen),
                onBackToDashboard: widget.closeRouteWhenEmpty
                    ? null
                    : widget.onEmpty,
                onSwipeToNewTab: widget.onNewTab ?? _openNewTabSheet,
                showBackButton: true,
                onVerticalScrollActivity: (scrolling) =>
                    _setTabVerticalScrollActivity(tab.key, scrolling),
                dashboardBackPreview: dashboardBackPreview,
                tabPagePosition: _pagePosition,
                tabPageIndex: index,
                onUserActivity: pageIsActive
                    ? widget.userActivityFor?.call(tab.volId!)
                    : null,
              );
            }
            return _BrowserTabPage(
              key: ValueKey<int>(tab.key),
              child: TickerMode(
                // Let a drawer finish closing after its tab becomes
                // inactive; otherwise its animation can reappear later.
                enabled: pageIsActive || _drawerTickerTabKeys.contains(tab.key),
                child: page,
              ),
            );
          },
        ),
      ),
    );

    final activeTab = _tabs.activeTab;
    final drawer = activeTab == null
        ? null
        : widget.drawerBuilder?.call(
            _tabs,
            activeTab.isDashboard ? null : activeTab.volId,
          );

    return FullScreenDragDrawer(
      drawer: drawer,
      canOpenFromAnywhere: _tabs.activeIndex == 0,
      onDrawerChanged: (isOpen) {
        final tab = _tabs.activeTab;
        if (tab != null && !tab.isDashboard) {
          _onTabDrawerChanged(tab.key, isOpen);
        }
      },
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: pageView,
      ),
    );
  }
}

/// PageView lazily keeps only its nearby pages alive. Each browser tab owns
/// navigation and selection state, so retain its subtree after it scrolls out
/// of view.
class _BrowserTabPage extends StatefulWidget {
  final Widget child;

  const _BrowserTabPage({super.key, required this.child});

  @override
  State<_BrowserTabPage> createState() => _BrowserTabPageState();
}

class _BrowserTabPageState extends State<_BrowserTabPage>
    with AutomaticKeepAliveClientMixin<_BrowserTabPage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
