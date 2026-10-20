import 'dart:async';

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
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/widgets/adaptive_browser_app_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_new_tab_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_tab_strip.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_content_view.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

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
/// pushing a bare [FileBrowserScreen]: with a single tab it looks and behaves
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
  });

  @override
  ConsumerState<BrowserTabsShell> createState() => _BrowserTabsShellState();
}

/// Compatibility name retained for existing route builders and integrations.
typedef BrowserTabsHost = BrowserTabsShell;

class _BrowserTabsShellState extends ConsumerState<BrowserTabsShell> {
  late final BrowserTabsConfig _workspace;
  late final ProviderSubscription<BrowserTabsState> _workspaceSubscription;
  late final VaultEngineEvents _vaultEvents;
  late final PageController _pageController;
  late final ValueNotifier<PreferredSizeWidget?> _activeAppBar;
  late final ValueNotifier<PreferredSizeWidget?> _selectionAppBar;
  late final ValueNotifier<Widget?> _activeFloatingAction;
  late final ValueNotifier<Widget?> _activeBottomBar;
  final Map<TabId, ValueChanged<PreferredSizeWidget>> _appBarCallbacks = {};
  final Map<TabId, PreferredSizeWidget> _appBarsByTab = {};
  final Map<TabId, PreferredSizeWidget?> _selectionAppBarsByTab = {};
  final Map<TabId, Widget?> _floatingActionsByTab = {};
  final Map<TabId, Widget?> _bottomBarsByTab = {};
  bool _popScheduled = false;
  bool _drawerOpenOrDragging = false;
  bool _edgeDrawerGestureActive = false;
  TabId? _lastActiveTabId;

  BrowserTabsState get _workspaceState =>
      ref.read(browserTabsProvider(_workspace));
  BrowserTabs get _workspaceActions =>
      ref.read(browserTabsProvider(_workspace).notifier);

  @override
  void initState() {
    super.initState();
    _workspace = BrowserTabsConfig.create(
      initialContainer: widget.initialContainer,
      includeDashboardTab: widget.includeDashboardTab,
    );
    final initialState = ref.read(browserTabsProvider(_workspace));
    _lastActiveTabId = initialState.activeTabId;
    _pageController = PageController(initialPage: initialState.activeIndex);
    _activeAppBar = ValueNotifier<PreferredSizeWidget?>(null);
    _selectionAppBar = ValueNotifier<PreferredSizeWidget?>(null);
    _activeFloatingAction = ValueNotifier<Widget?>(null);
    _activeBottomBar = ValueNotifier<Widget?>(null);
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
    _activeAppBar.dispose();
    _selectionAppBar.dispose();
    _activeFloatingAction.dispose();
    _activeBottomBar.dispose();
    super.dispose();
  }

  void _onVolumeGone(int volId) {
    if (!mounted) return;
    _workspaceActions.closeByVolId(volId);
  }

  void _onTabsChanged(BrowserTabsState? previous, BrowserTabsState next) {
    _schedulePageSync();

    final liveTabIds = next.tabs.map((tab) => tab.tabId).toSet();
    _appBarCallbacks.removeWhere((id, _) => !liveTabIds.contains(id));
    _appBarsByTab.removeWhere((id, _) => !liveTabIds.contains(id));
    _selectionAppBarsByTab.removeWhere((id, _) => !liveTabIds.contains(id));
    _floatingActionsByTab.removeWhere((id, _) => !liveTabIds.contains(id));
    _bottomBarsByTab.removeWhere((id, _) => !liveTabIds.contains(id));
    final activeTabId = next.activeTabId;
    if (_lastActiveTabId != activeTabId) {
      _lastActiveTabId = activeTabId;
      _activeAppBar.value = activeTabId == null
          ? null
          : _appBarsByTab[activeTabId];
      _activeFloatingAction.value = activeTabId == null
          ? null
          : _floatingActionsByTab[activeTabId];
      _activeBottomBar.value = activeTabId == null
          ? null
          : _bottomBarsByTab[activeTabId];
    }
    if (next.tabs.isEmpty && !_popScheduled) {
      _popScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _popScheduled = false;
        if (_workspaceState.tabs.isNotEmpty) return;
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

  void _onPageChanged(int index, List<BrowserTabState> tabs) {
    if (index < 0 || index >= tabs.length) return;
    _workspaceActions.activateIndex(index);
  }

  void _onDrawerChanged(bool isOpen) {
    if (!mounted || _drawerOpenOrDragging == isOpen) return;
    setState(() => _drawerOpenOrDragging = isOpen);
  }

  void _onEdgeDrawerGestureChanged(bool active) {
    if (!mounted || _edgeDrawerGestureActive == active) return;
    setState(() => _edgeDrawerGestureActive = active);
  }

  ValueChanged<PreferredSizeWidget> _appBarCallbackFor(TabId tabId) =>
      _appBarCallbacks.putIfAbsent(
        tabId,
        () => (appBar) {
          if (!mounted || _workspaceState.activeTabId != tabId) return;
          _appBarsByTab[tabId] = appBar;
          _activeAppBar.value = appBar;
        },
      );

  ValueChanged<PreferredSizeWidget?> _selectionAppBarCallbackFor(TabId tabId) =>
      (appBar) {
        if (!mounted) return;
        _selectionAppBarsByTab[tabId] = appBar;
        if (_workspaceState.activeTabId == tabId) {
          // The visible tab's preference decides whether the aggregate
          // selection UI belongs in the stationary app bar or bottom slot.
          _selectionAppBar.value = appBar;
          return;
        }
        final aggregate = ref.read(aggregatedTabsSelectionProvider(_workspace));
        if (!aggregate.hasSelection) {
          _selectionAppBar.value = null;
          return;
        }
        if (appBar != null) {
          _selectionAppBar.value = appBar;
          return;
        }
        for (final entry in aggregate.itemsByTab.entries) {
          if (entry.value.isEmpty) continue;
          final candidate = _selectionAppBarsByTab[entry.key];
          if (candidate != null) {
            _selectionAppBar.value = candidate;
            return;
          }
        }
      };

  ValueChanged<Widget?> _floatingActionCallbackFor(TabId tabId) => (action) {
    _floatingActionsByTab[tabId] = action;
    if (!mounted || _workspaceState.activeTabId != tabId) return;
    _activeFloatingAction.value = action;
  };

  ValueChanged<Widget?> _bottomBarCallbackFor(TabId tabId) => (bottomBar) {
    _bottomBarsByTab[tabId] = bottomBar;
    if (!mounted || _workspaceState.activeTabId != tabId) return;
    _activeBottomBar.value = bottomBar;
  };

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
    final nav = active.isDashboard
        ? null
        : ref.read(fileBrowserNavigationProvider(active.tabId));
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
      _workspaceActions.replaceActiveWithDashboard();
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
    final isFirstTab = tabs.first.tabId == activeTabId;
    final hasMultipleTabs = ref.watch(hasActiveBrowserTabsProvider(_workspace));
    final tabsEnabled = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.useBrowserTabs),
    );
    final systemBackGestureInsetLeft = MediaQuery.of(
      context,
    ).systemGestureInsets.left;
    final strip = BrowserTabStrip(
      workspaceConfig: _workspace,
      onNewTab: widget.onNewTab ?? _openNewTabSheet,
      onDuplicate: widget.onDuplicate ?? _duplicate,
    );
    final drawer = activeTab == null
        ? null
        : widget.drawerBuilder?.call(
            _workspace,
            activeTab.isDashboard ? null : activeTab.volId,
          );

    final shell = Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AdaptiveBrowserAppBar(
              workspaceConfig: _workspace,
              appBarListenable: _activeAppBar,
              fallback: const SizedBox(height: kToolbarHeight),
              selectionAppBarListenable: _selectionAppBar,
            ),
            if (tabsEnabled && tabs.isNotEmpty) strip,
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                clipBehavior: Clip.hardEdge,
                physics:
                    hasMultipleTabs &&
                        tabsEnabled &&
                        !_drawerOpenOrDragging &&
                        !_edgeDrawerGestureActive
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemCount: tabs.length,
                onPageChanged: (index) => _onPageChanged(index, tabs),
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
                  final Widget page;
                  if (tab.isDashboard) {
                    page =
                        widget.homeBuilder?.call(
                          workspace: _workspace,
                          onFloatingActionChanged: _floatingActionCallbackFor(
                            tab.tabId,
                          ),
                          onBottomBarChanged: _bottomBarCallbackFor(tab.tabId),
                        ) ??
                        const SizedBox.expand();
                  } else {
                    page = SkinAreaScope(
                      area: SkinArea.files,
                      child: DirectoryContentView(
                        key: ValueKey<TabId>(tab.tabId),
                        container: tab.container!,
                        tabId: tab.tabId,
                        workspaceConfig: _workspace,
                        initialPath: tab.initialPath,
                        resolveContainer: widget.resolveContainer,
                        showBackButton: true,
                        onUserActivity: pageIsActive
                            ? widget.userActivityFor?.call(tab.volId!)
                            : null,
                        onAppBarChanged: _appBarCallbackFor(tab.tabId),
                        onSelectionAppBarChanged: _selectionAppBarCallbackFor(
                          tab.tabId,
                        ),
                        onFloatingActionChanged: _floatingActionCallbackFor(
                          tab.tabId,
                        ),
                        onBottomBarChanged: _bottomBarCallbackFor(tab.tabId),
                      ),
                    );
                  }
                  return _BrowserTabPage(
                    key: ValueKey<TabId>(tab.tabId),
                    child: TickerMode(enabled: pageIsActive, child: page),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: ValueListenableBuilder<Widget?>(
        valueListenable: _activeFloatingAction,
        builder: (context, action, _) => action ?? const SizedBox.shrink(),
      ),
      bottomNavigationBar: ValueListenableBuilder<Widget?>(
        valueListenable: _activeBottomBar,
        builder: (context, bottomBar, _) =>
            bottomBar ?? const SizedBox.shrink(),
      ),
    );

    return FullScreenDragDrawer(
      drawer: drawer,
      onDrawerChanged: _onDrawerChanged,
      onEdgeGestureChanged: _onEdgeDrawerGestureChanged,
      // Reserve the left edge of the viewport for drawer opening while the
      // PageView keeps native swipes everywhere else.
      canOpenFromAnywhere: !(tabsEnabled && hasMultipleTabs) || isFirstTab,
      edgeGestureTop:
          MediaQuery.paddingOf(context).top +
          kToolbarHeight +
          (tabsEnabled && tabs.isNotEmpty ? kBrowserTabStripHeight : 0),
      backGestureInsetLeft: systemBackGestureInsetLeft < 24
          ? 24
          : systemBackGestureInsetLeft,
      child: shell,
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
