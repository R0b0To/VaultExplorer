import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_chrome_hub.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/models/browser_viewport_options.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/widgets/adaptive_browser_app_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_app_bar_factory.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_new_tab_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_tab_strip.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_content_view.dart';
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
    with SingleTickerProviderStateMixin {
  static const double _newTabSwipeThreshold = 72;

  late final BrowserTabsConfig _workspace;
  late final ProviderSubscription<BrowserTabsState> _workspaceSubscription;
  late final VaultEngineEvents _vaultEvents;
  late final PageController _pageController;
  late final ProviderSubscription<BrowserChromeHub> _chromeSubscription;
  late final AnimationController _appBarVisibilityController;
  final Map<TabId, GlobalKey> _directoryViewKeys = {};
  final Map<TabId, GlobalKey> _dashboardViewKeys = {};
  bool _popScheduled = false;
  bool _drawerOpenOrDragging = false;
  bool _edgeDrawerGestureActive = false;
  bool _restoreAppBarScheduled = false;
  bool _newTabPromptScheduled = false;
  bool _lastTabSwipeEligible = false;
  bool? _wasDualPane;
  List<TabId>? _dualPaneTabIds;
  double _lastTabNextOverscroll = 0;
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
    _pageController = PageController(initialPage: initialState.activeIndex);
    _chromeSubscription = ref.listenManual<BrowserChromeHub>(
      browserChromeProvider(_workspace),
      (_, _) {},
    );
    _appBarVisibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
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
    super.dispose();
  }

  void _onVolumeGone(int volId) {
    if (!mounted) return;
    _workspaceActions.closeByVolId(volId);
  }

  void _onTabsChanged(BrowserTabsState? previous, BrowserTabsState next) {
    final pageViewChangedActiveTab =
        previous?.activeTabId != next.activeTabId &&
        next.activeIndex == _pageViewDrivenActiveIndex;
    if (pageViewChangedActiveTab) _pageViewDrivenActiveIndex = null;

    if (_isPureTabReorder(previous, next)) {
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

  Widget _buildDualPaneViewport(
    BrowserTabState tab, {
    required bool isActive,
    required bool autoHideAppBar,
  }) {
    return Expanded(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.axis == Axis.vertical) {
            _handleAppBarScroll(
              notification,
              enabled: autoHideAppBar,
              active: isActive,
            );
          }
          // Each pane owns its scroll notifications. In particular, its
          // horizontal overscroll must not trigger the tab-strip edge action.
          return true;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _focusTab(tab.tabId),
          child: TickerMode(
            enabled: true,
            child: _buildTabContent(tab, isActive: isActive),
          ),
        ),
      ),
    );
  }

  List<TabId> _resolveDualPaneTabIds(
    List<BrowserTabState> tabs,
    TabId? activeTabId,
  ) {
    final activeIndex = tabs.indexWhere((tab) => tab.tabId == activeTabId);
    final currentPair = _dualPaneTabIds;
    final pairStillOpen =
        currentPair != null &&
        currentPair.length == 2 &&
        tabs.any((tab) => tab.tabId == currentPair[0]) &&
        tabs.any((tab) => tab.tabId == currentPair[1]);
    final activeIsInPair = currentPair?.contains(activeTabId) ?? false;
    if (!pairStillOpen || !activeIsInPair) {
      final firstIndex = activeIndex >= tabs.length - 1
          ? tabs.length - 2
          : activeIndex.clamp(0, tabs.length - 2).toInt();
      _dualPaneTabIds = [tabs[firstIndex].tabId, tabs[firstIndex + 1].tabId];
    } else {
      final pair = currentPair;
      final firstPairIndex = tabs.indexWhere((tab) => tab.tabId == pair[0]);
      final secondPairIndex = tabs.indexWhere((tab) => tab.tabId == pair[1]);
      if (firstPairIndex > secondPairIndex) {
        _dualPaneTabIds = [pair[1], pair[0]];
      }
    }
    return _dualPaneTabIds!;
  }

  /// Tells the tabs which of them are on screen besides the active one. The
  /// layout decides this (dual-pane depends on the width actually available),
  /// so it is published from the layout pass; the hub ignores repeats.
  void _publishVisibleTabs(Set<TabId> visible) {
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
    required bool active,
  }) {
    if (notification.metrics.axis == Axis.horizontal) {
      _handleNewTabSwipe(notification);
      return false;
    }
    if (!active) return false;

    if (!enabled) {
      if (_appBarVisibilityController.value != 1.0) {
        _appBarVisibilityController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
      return false;
    }

    void setProgress(double value) {
      _appBarVisibilityController.value = value.clamp(0.0, 1.0).toDouble();
    }

    final metrics = notification.metrics;
    final canScroll = metrics.maxScrollExtent > 0.0;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      if (canScroll && metrics.pixels <= 0.0 && delta <= 0.0) {
        setProgress(1.0);
      } else if (delta != 0.0) {
        setProgress(
          _appBarVisibilityController.value - (delta / kToolbarHeight),
        );
      }
    } else if (notification is OverscrollNotification) {
      if (notification.overscroll != 0.0) {
        setProgress(
          _appBarVisibilityController.value -
              (notification.overscroll / kToolbarHeight),
        );
      }
    } else if (notification is ScrollEndNotification) {
      if (canScroll && metrics.pixels <= 0.0) {
        _appBarVisibilityController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else if (_appBarVisibilityController.value > 0.0 &&
          _appBarVisibilityController.value < 1.0) {
        _appBarVisibilityController.animateTo(
          _appBarVisibilityController.value >= 0.5 ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }
    return false;
  }

  void _handleNewTabSwipe(ScrollNotification notification) {
    if (_newTabPromptScheduled) return;

    if (notification is ScrollStartNotification) {
      final state = _workspaceState;
      final tabsEnabled = ref
          .read(appSettingsControllerProvider)
          .settings
          .useBrowserTabs;
      _lastTabSwipeEligible =
          notification.dragDetails != null &&
          tabsEnabled &&
          state.activeIndex >= 0 &&
          state.activeIndex == state.tabs.length - 1;
      _lastTabNextOverscroll = 0;
      return;
    }
    if (!_lastTabSwipeEligible) {
      if (notification is ScrollEndNotification) {
        _lastTabNextOverscroll = 0;
        _lastTabSwipeEligible = false;
      }
      return;
    }

    if (notification is OverscrollNotification &&
        notification.metrics.extentAfter <= 0 &&
        notification.overscroll > 0) {
      // At the final page, a positive horizontal overscroll means the user
      // tried to move forward to a tab that does not exist yet.
      _lastTabNextOverscroll += notification.overscroll;
    } else if (notification is ScrollUpdateNotification &&
        notification.metrics.extentAfter <= 0 &&
        (notification.scrollDelta ?? 0) > 0) {
      // Bouncing scroll physics reports the out-of-range movement as updates
      // rather than OverscrollNotifications.
      _lastTabNextOverscroll += notification.scrollDelta!;
    } else if (notification is ScrollEndNotification) {
      final shouldPrompt =
          _lastTabNextOverscroll >= _newTabSwipeThreshold &&
          !_drawerOpenOrDragging &&
          !_edgeDrawerGestureActive;
      _lastTabNextOverscroll = 0;
      _lastTabSwipeEligible = false;
      if (shouldPrompt && !_newTabPromptScheduled) {
        _newTabPromptScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            _newTabPromptScheduled = false;
            return;
          }
          unawaited(
            _openNewTabSheet().whenComplete(() {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _newTabPromptScheduled = false;
              });
            }),
          );
        });
      }
    }
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
    final choice = await BrowserNewTabSheet.show(
      context,
      mountedVaults: widget.mountedContainers(),
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
    final tabId = _workspaceActions.openTab(
      choice.container!,
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
    final toolbarSettingsUri =
        activeContainer == null || activeContainer.isLocalStorage
        ? null
        : activeContainer.uri;
    final autoHideAppBar = ref.watch(
      fileManagerToolbarSettingsProvider(
        toolbarSettingsUri,
      ).select((settings) => settings.config.autoHideAppBar),
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
    final isFirstTab = tabs.first.tabId == activeTabId;
    final hasMultipleTabs = ref.watch(hasActiveBrowserTabsProvider(_workspace));
    final tabsEnabled = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.useBrowserTabs),
    );
    final useDualPaneBrowsing = ref.watch(
      appSettingsControllerProvider.select(
        (s) => s.settings.useDualPaneBrowsing,
      ),
    );
    final orientation = MediaQuery.of(context).orientation;
    final minDualPaneWidth = orientation == Orientation.landscape
        ? 640.0
        : 720.0;
    final availableWidth =
        MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal;
    final dualPaneForTabStrip =
        tabsEnabled &&
        useDualPaneBrowsing &&
        tabs.length > 1 &&
        availableWidth >= minDualPaneWidth;
    final dualPaneTabIds = dualPaneForTabStrip
        ? _resolveDualPaneTabIds(tabs, activeTabId)
        : null;
    final secondaryTabId = dualPaneTabIds == null
        ? null
        : dualPaneTabIds.first == activeTabId
        ? dualPaneTabIds.last
        : dualPaneTabIds.first;
    final systemBackGestureInsetLeft = MediaQuery.of(
      context,
    ).systemGestureInsets.left;
    final strip = BrowserTabStrip(
      workspaceConfig: _workspace,
      onNewTab: widget.onNewTab ?? _openNewTabSheet,
      onDuplicate: widget.onDuplicate ?? _duplicate,
      secondaryTabId: secondaryTabId,
    );
    final drawer = activeTab == null
        ? null
        : widget.drawerBuilder?.call(
            _workspace,
            activeTab.isDashboard ? null : activeTab.volId,
          );
    double browserChromeBottom() {
      final visibleAppBarHeight =
          (autoHideAppBar ? _appBarVisibilityController.value : 1.0) *
          kToolbarHeight;
      final visibleTabStripHeight = tabsEnabled && tabs.isNotEmpty
          ? kBrowserTabStripHeight
          : 0.0;
      return MediaQuery.paddingOf(context).top +
          visibleAppBarHeight +
          visibleTabStripHeight;
    }

    final shell = Scaffold(
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                ClipRect(
                  child: AnimatedBuilder(
                    animation: _appBarVisibilityController,
                    builder: (context, child) => Align(
                      key: const Key('browser_app_bar_align'),
                      alignment: Alignment.bottomCenter,
                      heightFactor: autoHideAppBar
                          ? _appBarVisibilityController.value
                          : 1.0,
                      child: SizedBox(height: kToolbarHeight, child: child),
                    ),
                    child: AdaptiveBrowserAppBar(
                      workspaceConfig: _workspace,
                      appBarListenable: _chrome.appBar,
                      fallback: BrowserAppBarFallback(
                        title: activeTab?.container?.displayName ?? '',
                        showBackButton: widget.viewportOptions.showBackButton,
                        preferBackButton: !tabsEnabled,
                        onBackPressed: tabsEnabled ? null : _handleBackToDashboard,
                      ),
                    ),
                  ),
                ),
                if (tabsEnabled && tabs.isNotEmpty) strip,
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, viewportConstraints) {
                      final orientation = MediaQuery.of(context).orientation;
                      final minDualPaneWidth = orientation == Orientation.landscape
                          ? 640.0
                          : 720.0;
                      final dualPane =
                          tabsEnabled &&
                          useDualPaneBrowsing &&
                          tabs.length > 1 &&
                          viewportConstraints.maxWidth >= minDualPaneWidth;

                      if (_wasDualPane != dualPane) {
                        final wasDualPane = _wasDualPane;
                        _wasDualPane = dualPane;
                        if (wasDualPane == true && !dualPane) {
                          _schedulePageSync();
                        }
                      }

                      if (dualPane) {
                        final pair = _resolveDualPaneTabIds(tabs, activeTabId);
                        final firstTab = tabs.firstWhere(
                          (tab) => tab.tabId == pair[0],
                        );
                        final secondTab = tabs.firstWhere(
                          (tab) => tab.tabId == pair[1],
                        );
                        _publishVisibleTabs({pair[0], pair[1]});
                        return Row(
                          children: [
                            _buildDualPaneViewport(
                              firstTab,
                              isActive: firstTab.tabId == activeTabId,
                              autoHideAppBar: autoHideAppBar,
                            ),
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: Theme.of(context).dividerColor,
                            ),
                            _buildDualPaneViewport(
                              secondTab,
                              isActive: secondTab.tabId == activeTabId,
                              autoHideAppBar: autoHideAppBar,
                            ),
                          ],
                        );
                      }

                      _publishVisibleTabs(const <TabId>{});
                      return NotificationListener<ScrollNotification>(
                        onNotification: (notification) => _handleAppBarScroll(
                          notification,
                          enabled: autoHideAppBar,
                          active: activeTabId != null,
                        ),
                        child: PageView.builder(
                          controller: _pageController,
                          clipBehavior: Clip.hardEdge,
                          physics:
                              tabsEnabled &&
                                  !_drawerOpenOrDragging &&
                                  !_edgeDrawerGestureActive
                              ? const PageScrollPhysics(
                                  parent: AlwaysScrollableScrollPhysics(),
                                )
                              : const NeverScrollableScrollPhysics(),
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
                            final pageIsActive = tab.tabId == activeTabId;
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
                              child: _buildTabContent(
                                tab,
                                isActive: pageIsActive,
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
            // The selection app bar floats above the top of the browser
            // rather than taking the (auto-hiding) app bar's slot, so it is
            // visible when that slot is collapsed and nothing shifts.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _SelectionBarOverlay(
                workspaceConfig: _workspace,
                selectionAppBarListenable: _chrome.selectionAppBar,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: ValueListenableBuilder<Widget?>(
        valueListenable: _chrome.floatingAction,
        builder: (context, action, _) => action ?? const SizedBox.shrink(),
      ),
      bottomNavigationBar: ValueListenableBuilder<Widget?>(
        valueListenable: _chrome.bottomBar,
        builder: (context, bottomBar, _) =>
            bottomBar ?? const SizedBox.shrink(),
      ),
    );

    return FullScreenDragDrawer(
      drawer: drawer,
      onDrawerChanged: _onDrawerChanged,
      onEdgeGestureChanged: _onEdgeDrawerGestureChanged,
      edgeGestureTop: browserChromeBottom(),
      edgeGestureTopBuilder: browserChromeBottom,
      canStartGestureAt: (position) => position.dy >= browserChromeBottom(),
      // Reserve the left edge of the viewport for drawer opening while the
      // PageView keeps native swipes everywhere else.
      canOpenFromAnywhere: !(tabsEnabled && hasMultipleTabs) || isFirstTab,
      backGestureInsetLeft: systemBackGestureInsetLeft < 24
          ? 24
          : systemBackGestureInsetLeft,
      child: shell,
    );
  }
}

/// The selection app bar, laid over the top of the browser.
///
/// Selecting while the app bar has auto-hidden must still show the selection
/// actions, and must not push the list down. So the bar is an overlay: it
/// covers the app bar slot when that is visible and the top of the content
/// when it is collapsed, and the layout underneath never changes.
class _SelectionBarOverlay extends ConsumerWidget {
  const _SelectionBarOverlay({
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
        return SizedBox(
          key: const Key('browser_selection_app_bar_overlay'),
          height: kToolbarHeight,
          child: SkinAreaScope(
            area: SkinArea.files,
            child: Builder(
              builder: (appBarContext) => selectionAppBar(appBarContext),
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
