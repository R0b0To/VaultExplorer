import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/quick_capture_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/browser_tabs_host.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_new_tab_sheet.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_screen.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/app_navigation_drawer.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/share_import/share_import_flow.dart';
import 'package:vaultexplorer/features/camera/quick_capture_screen.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';
import 'package:vaultexplorer/features/unlock/unlock_sheet.dart';
import 'package:vaultexplorer/features/unlock/usb_unlock_sheet.dart';

class MainShell extends ConsumerStatefulWidget {
  final bool hideDashboardUntilShareHandled;

  const MainShell({super.key, this.hideDashboardUntilShareHandled = false});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;
  late bool _hideDashboard = widget.hideDashboardUntilShareHandled;
  final ValueNotifier<List<MountedContainer>> _mountedNotifier = ValueNotifier(
    const [],
  );
  final GlobalKey<VaultDashboardState> _dashboardKey =
      GlobalKey<VaultDashboardState>();

  // Cached synchronously while the widget is mounted
  late final _secureScreenPolicy = ref.read(secureScreenPolicyProvider);
  late final _vaultEngineEvents = ref.read(vaultEngineEventsProvider);

  // Guards against the narrow race where a share intent arrives right as
  // MainShell is first built: the listener below and
  // _checkPendingShareOnStart's post-frame pull could otherwise both end
  // up resolving the same still-pending request and call
  // presentIncomingShareImport twice.
  bool _handlingShareRequest = false;
  int _shareSeq = 0;
  Route<dynamic>? _activeShareRoute;
  IncomingShareRequest? _lastHandledShareRequest;
  final DateTime _shellCreatedAt = DateTime.now();

  // Same narrow cold-start race as the share request above, but Quick
  // Capture has no payload/route-tracking to deduplicate against -- a
  // plain in-flight flag is enough since there's only ever one
  // QuickCaptureScreen route to push.
  bool _handlingQuickCapture = false;

  // True only when this shell was created because Quick Capture launched the
  // app and the startup gate already pulled that request (see
  // PendingQuickCaptureLaunch). That launch lives in its own task and ends
  // with SystemNavigator.pop() (see _onQuickCaptureRequested), so the
  // dashboard, Tools and Settings tabs would be built, laid out and then
  // thrown away without ever being seen -- build() paints a plain black
  // frame instead while the capture screen opens on top.
  bool _quickCaptureColdStart = false;

  // Tabs are built the first time they're opened and then kept alive.
  // IndexedStack builds every child up front, which on cold start meant
  // constructing the whole Tools hub and the Settings screen (and whatever
  // providers they watch) before the user could see the dashboard.
  final Set<int> _builtTabs = {0};
  MountedContainer? _browserInitialContainer;
  BrowserTabsController? _browserTabs;
  bool _browserVisible = false;

  bool get _isBrowserContentVisible {
    if (_index != 0) return false;
    final tabs = _browserTabs;
    if (tabs != null && !tabs.isEmpty) return true;
    return _browserVisible;
  }

  @override
  void initState() {
    super.initState();
    _quickCaptureColdStart = ref.read(pendingQuickCaptureLaunchProvider).take();
    if (!_quickCaptureColdStart) {
      // The Settings tab used to be the thing that created -- and so started
      // loading -- this keepAlive controller on the first frame. The
      // dashboard, file browser and authenticator registry later read its
      // `.settings` and expect it already loaded, so creating it here keeps
      // that timing now that the tab itself is built lazily.
      ref.read(appSettingsControllerProvider);
    }
    final policy = _secureScreenPolicy; // Eagerly evaluate while mounted
    ref.read(appSettingsServiceProvider).loadSettings().then((settings) {
      policy.apply(preference: settings.blockScreenshots);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_quickCaptureColdStart) {
        _onQuickCaptureRequested();
        return;
      }
      _checkPendingShareOnStart();
      _checkPendingQuickCaptureOnStart();
    });
    _vaultEngineEvents.addIncomingShareRequestListener(_onIncomingShareRequest);
    _vaultEngineEvents.addQuickCaptureRequestedListener(
      _onQuickCaptureRequested,
    );
  }

  Future<void> _checkPendingShareOnStart() async {
    final request = await ref
        .read(vaultFileIoApiProvider)
        .checkPendingShareRequest();
    if (request == null || !mounted) {
      if (_hideDashboard) {
        setState(() => _hideDashboard = false);
      }
      return;
    }
    // If the push listener already began presenting this share request,
    // avoid tearing down and recreating the share sheet.
    if (_handlingShareRequest) return;
    // This pull only ever runs once, from initState's first post-frame
    // callback -- if a MainShell this old is still around to run it, there
    // was nothing already on screen when the share arrived, so it's safe to
    // hand control back to the sharing app once the import finishes. Any
    // later share request reaches _onIncomingShareRequest straight from the
    // push listener below instead (isColdStart defaults to false there),
    // since by then the dashboard was already up and running. See
    // presentIncomingShareImport's isColdStart doc comment.
    _onIncomingShareRequest(request, isColdStart: true);
  }

  bool _isSameShareRequest(IncomingShareRequest? a, IncomingShareRequest? b) {
    if (a == null || b == null) return false;
    if (identical(a, b) || a == b) return true;
    if (a.toString() != "Instance of 'IncomingShareRequest'" &&
        a.toString() == b.toString()) {
      return true;
    }
    // Startup safety window: two incoming share triggers within 2 seconds
    // of shell creation represent the duplicate push/pull cold start race.
    if (DateTime.now().difference(_shellCreatedAt) <
        const Duration(seconds: 2)) {
      return true;
    }
    return false;
  }

  void _onIncomingShareRequest(
    IncomingShareRequest request, {
    bool isColdStart = false,
  }) {
    if (!mounted) return;

    // Deduplicate push/pull races while a share route is already active
    if (_handlingShareRequest &&
        _activeShareRoute != null &&
        _activeShareRoute!.isActive &&
        _isSameShareRequest(_lastHandledShareRequest, request)) {
      return;
    }
    _lastHandledShareRequest = request;

    final mySeq = ++_shareSeq;
    if (_activeShareRoute != null && _activeShareRoute!.isActive) {
      _activeShareRoute!.navigator?.removeRoute(_activeShareRoute!);
      _activeShareRoute = null;
    }
    _handlingShareRequest = true;
    presentIncomingShareImport(
      context,
      ref,
      request,
      isColdStart: isColdStart,
      onRouteCreated: (route) => _activeShareRoute = route,
      isCurrent: () => mounted && _shareSeq == mySeq,
    ).whenComplete(() {
      if (!mounted) return;
      if (_shareSeq == mySeq) {
        _handlingShareRequest = false;
        _activeShareRoute = null;
        _lastHandledShareRequest = null;
        if (_hideDashboard) {
          setState(() => _hideDashboard = false);
        }
      }
    });
  }

  Future<void> _checkPendingQuickCaptureOnStart() async {
    final pending = await ref
        .read(quickCaptureApiProvider)
        .checkPendingQuickCaptureRequest();
    if (!pending || !mounted) return;
    _onQuickCaptureRequested();
  }

  void _onQuickCaptureRequested() {
    if (!mounted || _handlingQuickCapture) return;
    setState(() => _handlingQuickCapture = true);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const QuickCaptureScreen()))
        .whenComplete(() {
          if (!mounted) return;
          _handlingQuickCapture = false;
          // When QuickCaptureScreen finishes (saved, cancelled via X, or backed out),
          // cleanly finish and remove the isolated QuickCaptureActivity task window.
          SystemNavigator.pop();
        });
  }

  @override
  void dispose() {
    _mountedNotifier.dispose();
    _browserTabs?.removeListener(_onBrowserTabsUpdated);
    _vaultEngineEvents.removeIncomingShareRequestListener(
      _onIncomingShareRequest,
    );
    _vaultEngineEvents.removeQuickCaptureRequestedListener(
      _onQuickCaptureRequested,
    );
    disguiseModeApi.getMode().then((mode) {
      if (mode == DisguiseMode.decoy) {
        // Safe: calling the cached service directly without using `ref`
        _secureScreenPolicy.disableForDecoy();
      }
    });
    super.dispose();
  }

  void _onTabTap(int newIndex) {
    final wasNavigating = _index != newIndex || _isBrowserContentVisible;
    if (newIndex == 0) {
      final tabs = _browserTabs;
      final dashboardTab = tabs?.dashboardTab;
      if (dashboardTab != null) {
        tabs!.activate(dashboardTab.key);
      } else {
        tabs?.replaceActiveWithDashboard();
      }
    }
    if (wasNavigating || _index != newIndex || _isBrowserContentVisible) {
      setState(() {
        _index = newIndex;
        _builtTabs.add(newIndex);
        _browserVisible = false;
      });
      if (newIndex == 0) {
        _dashboardKey.currentState?.reloadDashboard();
      }
    }
  }

  void _showBrowserTabLimit() {
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: context.l10n.browserTabLimitReached(kMaxBrowserTabs),
      tone: AppBannerTone.warning,
    );
  }

  void _openBrowser(MountedContainer container) {
    final tabs = _browserTabs;
    if (tabs == null) {
      setState(() {
        _browserInitialContainer = container;
        _browserVisible = true;
        _index = 0;
      });
      return;
    }

    final active = tabs.activeTab;
    final tabsEnabled = ref
        .read(appSettingsControllerProvider)
        .settings
        .useBrowserTabs;
    if (active?.isDashboard == true) {
      // Dashboard is a location in the tab strip. Opening a vault from it
      // navigates that same tab to the vault; Back at the vault root returns
      // to Dashboard in this tab.
      tabs.replaceActive(container, returnToDashboardOnRoot: true);
    } else if (active?.volId != container.volId && !tabsEnabled) {
      tabs.replaceActive(container);
    } else if (active?.volId != container.volId &&
        tabs.openTab(container) == null) {
      _showBrowserTabLimit();
      return;
    }
    setState(() {
      _browserVisible = true;
      _index = 0;
      _builtTabs.add(0);
    });
  }

  void _openVaultFromDrawer(VaultListItem item) {
    switch (item) {
      case MountedVaultItem(:final container):
        _openBrowser(container);
      case LockedVaultItem(:final record):
        // Reuse the dashboard's unlock flow when its location is mounted.
        // If the Dashboard tab was closed, present the same flow from the
        // shell instead of switching to Dashboard just to reach its widget.
        final dashboard = _dashboardKey.currentState;
        if (dashboard != null) {
          dashboard.openItem(item);
        } else {
          unawaited(_showDrawerUnlock(record));
        }
    }
  }

  Future<void> _showDrawerUnlock(ContainerRecord record) async {
    final state = ref.read(vaultDashboardControllerProvider);
    if (state.mounted.any((container) => container.uri == record.uri)) {
      showAppSnackBar(context, message: context.l10n.containerAlreadyMounted);
      return;
    }
    if (state.actionInFlight) return;

    final controller = ref.read(vaultDashboardControllerProvider.notifier);
    final repository = ref.read(containerRepositoryProvider);
    final navigator = Navigator.of(context);
    controller.setActionInFlight(true);

    MountedContainer? newlyMountedContainer;
    try {
      final rememberedPassword =
          record.unlockMethod == ContainerUnlockMethod.rememberPassword
          ? await repository.getPassword(record.uri)
          : null;
      if (!mounted) return;

      final autoOpen = state.appSettings.autoOpenOnUnlock;
      if (record.isUsbSource) {
        await navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => SkinAreaScope(
              area: SkinArea.dashboard,
              child: UsbUnlockSheet(
                existingRecord: record,
                prefillPassword: rememberedPassword,
                documentProvider: record.documentProvider,
                autoMountFolders: record.documentProviderFolders
                    .where((folder) => folder.autoMount)
                    .map((folder) => folder.path)
                    .toList(),
                onMounted: (container, {record}) {
                  controller.onContainerMounted(container, record: record);
                  newlyMountedContainer = container;
                  if (autoOpen && mounted) _openBrowser(container);
                },
                onReconnected: (container, migratedRecord, oldUri) {
                  controller.onUsbContainerReconnected(
                    container,
                    migratedRecord,
                    oldUri,
                  );
                  newlyMountedContainer = container;
                },
              ),
            ),
          ),
        );
      } else {
        await navigator.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => SkinAreaScope(
              area: SkinArea.dashboard,
              child: UnlockSheet(
                initialUri: record.uri,
                initialName: record.label,
                prefillPassword: rememberedPassword,
                documentProvider: record.documentProvider,
                autoMountFolders: record.documentProviderFolders
                    .where((folder) => folder.autoMount)
                    .map((folder) => folder.path)
                    .toList(),
                mountedUris: state.mounted
                    .map((container) => container.uri)
                    .toList(),
                onMounted: (container, {record}) {
                  controller.onContainerMounted(container, record: record);
                  newlyMountedContainer = container;
                  if (autoOpen && mounted) _openBrowser(container);
                },
              ),
            ),
          ),
        );
      }

      await controller.loadAll();
      if (newlyMountedContainer != null) {
        await controller.refreshContainerSpace(newlyMountedContainer!.volId);
      }
    } finally {
      controller.setActionInFlight(false);
    }
  }

  void _onBrowserTabsChanged(BrowserTabsController? tabs) {
    _browserTabs?.removeListener(_onBrowserTabsUpdated);
    _browserTabs = tabs;
    tabs?.addListener(_onBrowserTabsUpdated);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _onBrowserTabsUpdated() {
    final active = _browserTabs?.activeTab;
    if (!mounted || active == null) return;
    // Dashboard and file locations share one tab pager. Keep the host visible
    // for either kind of location so changing tabs can follow the finger.
    const shouldShowBrowser = true;
    if (_browserVisible == shouldShowBrowser) return;
    setState(() {
      _browserVisible = shouldShowBrowser;
      _index = 0;
    });
  }

  Future<void> _openNewBrowserTab() async {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    final tabs = _browserTabs;
    if (tabs == null) return;
    final active = tabs.activeTab;
    if (active == null) return;
    final nav = active.isDashboard
        ? null
        : ref.read(fileBrowserNavigationProvider(active.key));
    final choice = await BrowserNewTabSheet.show(
      context,
      currentContainer: active.container,
      currentDirPath: nav == null ? '' : browserTabDuplicatePath(nav),
      mountedVaults: _mountedNotifier.value,
      primaryLocalContainer: _dashboardKey.currentState?.localStorageContainer,
    );
    if (!mounted || choice == null) return;
    if (choice.container == null) {
      tabs.openDashboardTab();
      return;
    }
    final path = choice.path;
    final key = tabs.openTab(
      choice.container!,
      initialPath: path == null || path.isEmpty ? null : path,
    );
    if (key == null) {
      _showBrowserTabLimit();
      return;
    }
    setState(() => _browserVisible = true);
  }

  void _duplicateBrowserTab(BrowserTab tab) {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    final tabs = _browserTabs;
    final container = tab.container;
    if (tabs == null) return;
    if (tab.isDashboard) {
      tabs.openDashboardTab();
      return;
    }
    if (container == null) return;
    final nav = ref.read(fileBrowserNavigationProvider(tab.key));
    final path = browserTabDuplicatePath(nav);
    if (tabs.openTab(container, initialPath: path.isEmpty ? null : path) ==
        null) {
      _showBrowserTabLimit();
      return;
    }
    setState(() => _browserVisible = true);
  }

  List<_NavDestination> _destinations(BuildContext context) => [
    _NavDestination(
      icon: Icons.lock_outline_rounded,
      selectedIcon: Icons.lock_rounded,
      label: context.l10n.navBarVaultsLabel,
    ),
    _NavDestination(
      icon: Icons.build_outlined,
      selectedIcon: Icons.build_rounded,
      label: context.l10n.navBarToolsLabel,
    ),
    _NavDestination(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings_rounded,
      label: context.l10n.settingsTooltip,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_quickCaptureColdStart) {
      return const Scaffold(backgroundColor: Colors.black);
    }

    ref.listen<bool>(
      appSettingsControllerProvider.select(
        (state) => state.settings.useBrowserTabs,
      ),
      (previous, enabled) {
        if (enabled || previous == false) return;
        final tabs = _browserTabs;
        final activeKey = tabs?.activeKey ?? -1;
        if (activeKey >= 0) tabs!.closeOthers(activeKey);
      },
    );
    final tabsEnabled = ref.watch(
      appSettingsControllerProvider.select(
        (state) => state.settings.useBrowserTabs,
      ),
    );

    final cs = Theme.of(context).colorScheme;

    final destinations = _destinations(context);
    final isHidden = _hideDashboard || _handlingQuickCapture;

    Widget buildDashboardTab([
      ValueListenable<double>? pagePosition,
      int? pageIndex,
      ValueChanged<BrowserTab>? onActivateTab,
      ValueChanged<bool>? onVerticalScrollActivity,
      bool backPreviewOnly = false,
    ]) => SkinAreaScope(
      area: SkinArea.dashboard,
      child: VaultDashboard(
        key: backPreviewOnly ? null : _dashboardKey,
        mountedNotifier: backPreviewOnly ? null : _mountedNotifier,
        onNavigateTab: _onTabTap,
        browserTabs: backPreviewOnly ? null : _browserTabs,
        tabPagePosition: pagePosition,
        tabPageIndex: pageIndex,
        backPreviewOnly: backPreviewOnly,
        onOpenBrowser: _openBrowser,
        onNewBrowserTab: _openNewBrowserTab,
        onDuplicateBrowserTab: _duplicateBrowserTab,
        onActivateBrowserTab: onActivateTab,
        onVerticalScrollActivity: onVerticalScrollActivity,
      ),
    );

    final dashboardHosted =
        _browserTabs != null && _browserTabs!.tabs.isNotEmpty;
    final body = IndexedStack(
      index: _index,
      children: [
        // Each tab is its own page with its own colors; see SkinAreaScope.
        dashboardHosted ? const SizedBox.expand() : buildDashboardTab(),
        if (_builtTabs.contains(1))
          SkinAreaScope(
            area: SkinArea.tools,
            child: ToolsScreen(
              mountedContainers: _mountedNotifier,
              onNavigateTab: _onTabTap,
            ),
          )
        else
          const SizedBox.shrink(),
        if (_builtTabs.contains(2))
          const SkinAreaScope(
            area: SkinArea.settings,
            child: AppSettingsScreen(),
          )
        else
          const SizedBox.shrink(),
      ],
    );

    MountedContainer? resolveContainer(int volId) {
      for (final c in _mountedNotifier.value) {
        if (c.volId == volId) return c;
      }
      return _dashboardKey.currentState?.resolveAnyContainer(volId);
    }

    Widget buildDrawer({int? currentVolId, BrowserTabsController? tabs}) {
      return AppNavigationDrawer(
        currentVolId: currentVolId,
        primaryLocalContainer:
            _dashboardKey.currentState?.localStorageContainer,
        onOpenInNewTab: tabs == null || !tabsEnabled
            ? null
            : (container) {
                if (tabs.openTab(container) == null && mounted) {
                  showAppSnackBar(
                    context,
                    message: context.l10n.browserTabLimitReached(
                      kMaxBrowserTabs,
                    ),
                    tone: AppBannerTone.warning,
                  );
                }
              },
        selectedTabIndex: _index,
        onSelectTab: _onTabTap,
        keepBrowserTabsOnNavigate: tabs != null,
        onSelectContainer: (container) {
          // Already inside the tabbed file manager: switch the active tab
          // instead of stacking another file manager route.
          if (tabs != null) {
            tabs.replaceActive(container);
            return;
          }
          _openBrowser(container);
        },
        onUnlockVault: _openVaultFromDrawer,
        onAddVault: () {
          _onTabTap(0);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _dashboardKey.currentState?.showAddOptionsSheet();
          });
        },
      );
    }

    final browserContentVisible = _isBrowserContentVisible;
    final Widget persistentBrowser = Offstage(
      offstage: !browserContentVisible,
      child: SkinAreaScope(
        area: SkinArea.files,
        child: BrowserTabsHost(
          key: const ValueKey('main-shell-browser-tabs-host'),
          initialContainer: _browserInitialContainer,
          resolveContainer: resolveContainer,
          mountedContainers: () => _mountedNotifier.value,
          primaryLocalContainer: () =>
              _dashboardKey.currentState?.localStorageContainer,
          drawerBuilder: (tabs, volId) =>
              buildDrawer(currentVolId: volId, tabs: tabs),
          closeRouteWhenEmpty: false,
          includeDashboardTab: true,
          dashboardBuilder: _browserTabs == null
              ? null
              : (
                  pagePosition,
                  index,
                  onActivateTab,
                  onVerticalScrollActivity,
                  backPreviewOnly,
                ) => buildDashboardTab(
                  pagePosition,
                  index,
                  onActivateTab,
                  onVerticalScrollActivity,
                  backPreviewOnly,
                ),
          onEmpty: () {
            if (mounted && _browserVisible) {
              setState(() => _browserVisible = false);
            }
          },
          onTabsController: _onBrowserTabsChanged,
          onNewTab: _openNewBrowserTab,
          onDuplicate: _duplicateBrowserTab,
        ),
      ),
    );
    final Widget appBody = Stack(
      fit: StackFit.expand,
      children: [
        // The live Dashboard page is hosted in the tab pager. Keep the shell's
        // app destinations mounted without painting them under that pager.
        Offstage(offstage: browserContentVisible, child: body),
        persistentBrowser,
      ],
    );

    final Widget scaffold = Scaffold(
      // Tools and Settings have no horizontal pager, so let a drawer drag
      // start anywhere in their content, too.
      drawerEdgeDragWidth: double.maxFinite,
      drawerEnableOpenDragGesture: _index != 0,
      drawer: isHidden ? null : buildDrawer(),
      body: appBody,
    );

    // Keep the app shell mounted during share and Quick Capture flows, then
    // paint over it with a black screen while those flows are active.
    final Widget content = isHidden
        ? Stack(
            children: [
              Offstage(child: scaffold),
              const ColoredBox(color: Colors.black, child: SizedBox.expand()),
            ],
          )
        : scaffold;

    final dashboardLocationIsActive =
        _browserTabs?.activeTab?.isDashboard ?? false;
    return PopScope(
      canPop:
          _index == 0 && (!browserContentVisible || dashboardLocationIsActive),
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || (browserContentVisible && !dashboardLocationIsActive)) {
          return;
        }
        _onTabTap(0);
      },
      child: content,
    );
  }
}

class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class _NavRail extends StatelessWidget {
  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  const _NavRail({
    required this.destinations,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return NavigationRail(
      backgroundColor: cs.surfaceContainer,
      groupAlignment: 0.0,
      selectedIndex: selectedIndex,
      onDestinationSelected: onTap,
      labelType: NavigationRailLabelType.all,
      useIndicator: true,
      indicatorColor: cs.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      selectedIconTheme: IconThemeData(
        color: cs.onSecondaryContainer,
        size: 22,
      ),
      unselectedIconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 22),
      selectedLabelTextStyle: textTheme.labelSmall?.copyWith(
        color: cs.onSecondaryContainer,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: textTheme.labelSmall?.copyWith(
        color: cs.onSurfaceVariant,
        fontWeight: FontWeight.w500,
      ),
      destinations: [
        for (final d in destinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(d.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
    );
  }
}

class _MainBottomBarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _MainBottomBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: selected ? cs.secondaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  selected ? selectedIcon : icon,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(height: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
