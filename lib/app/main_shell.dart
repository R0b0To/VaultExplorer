import 'dart:async';

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
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/browser_tabs_host.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/models/browser_tab_origin.dart';
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
  final bool returnToDecoyOnBackground;

  const MainShell({
    super.key,
    this.hideDashboardUntilShareHandled = false,
    this.returnToDecoyOnBackground = false,
  });

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with WidgetsBindingObserver {
  int _index = 0;
  late bool _hideDashboard = widget.hideDashboardUntilShareHandled;
  final ValueNotifier<List<MountedContainer>> _mountedNotifier = ValueNotifier(
    const [],
  );
  final GlobalKey<VaultDashboardState> _dashboardKey =
      GlobalKey<VaultDashboardState>();
  MountedContainer? _cachedLocalStorageContainer;

  MountedContainer? get _primaryLocalStorageContainer {
    final dashboard = _dashboardKey.currentState;
    return dashboard == null
        ? _cachedLocalStorageContainer
        : dashboard.localStorageContainer;
  }

  void _cacheDashboardLocalStorageContainer() {
    final dashboard = _dashboardKey.currentState;
    if (dashboard != null) {
      _cachedLocalStorageContainer = dashboard.localStorageContainer;
    }
  }

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
  BrowserTabOrigin _browserInitialOrigin = BrowserTabOrigin.other;

  /// Back on Home asks for a second press before leaving the app.
  bool _exitArmed = false;
  Timer? _exitArmTimer;
  BrowserTabsConfig? _browserWorkspace;

  BrowserTabsState? get _browserWorkspaceState {
    final workspace = _browserWorkspace;
    return workspace == null ? null : ref.read(browserTabsProvider(workspace));
  }

  BrowserTabs? get _browserWorkspaceActions {
    final workspace = _browserWorkspace;
    return workspace == null
        ? null
        : ref.read(browserTabsProvider(workspace).notifier);
  }

  bool get _isBrowserContentVisible => _index == 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.returnToDecoyOnBackground &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      // System pickers and similar operations deliberately suppress auto-lock;
      // they may briefly background this activity but should not close the
      // revealed vault shell while the external operation is in progress.
      if (ref.read(sessionLockControllerProvider).isLockSuppressed) return;
      final navigator = Navigator.of(context, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _exitArmTimer?.cancel();
    _mountedNotifier.dispose();
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
    var returningToHome = false;
    if (newIndex == 0) {
      final workspace = _browserWorkspaceState;
      returningToHome =
          _index != 0 || workspace?.activeTab?.isDashboard != true;
      if (workspace?.activeTab == null) {
        _browserWorkspaceActions?.openDashboardTab();
      } else {
        _browserWorkspaceActions?.replaceActiveWithDashboard();
      }
    }
    if (_index != newIndex) {
      setState(() {
        _index = newIndex;
        _builtTabs.add(newIndex);
      });
    }
    if (returningToHome) _dashboardKey.currentState?.reloadDashboard();
  }

  void _showBrowserTabLimit() {
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: context.l10n.browserTabLimitReached(kMaxBrowserTabs),
      tone: AppBannerTone.warning,
    );
  }

  void _armExit() {
    _exitArmTimer?.cancel();
    setState(() => _exitArmed = true);
    showAppSnackBar(
      context,
      message: context.l10n.pressBackAgainToExit,
      tone: AppBannerTone.info,
    );
    _exitArmTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _exitArmed = false);
    });
  }

  void _openBrowser(
    MountedContainer container, {
    BrowserTabOrigin origin = BrowserTabOrigin.other,
  }) {
    _cacheDashboardLocalStorageContainer();
    final state = _browserWorkspaceState;
    final actions = _browserWorkspaceActions;
    if (state == null || actions == null) {
      // Queue an early open request until the browser workspace has created
      // its initial Dashboard tab and published its controller.
      setState(() {
        _browserInitialContainer = container;
        _browserInitialOrigin = origin;
      });
      return;
    }

    final active = state.activeTab;
    final tabsEnabled = ref
        .read(appSettingsControllerProvider)
        .settings
        .useBrowserTabs;
    if (active == null) {
      if (actions.openTab(container, origin: origin) == null) {
        _showBrowserTabLimit();
        return;
      }
    } else if (!tabsEnabled && active.isDashboard) {
      // In single-tab mode keep the Dashboard as a hidden tab so root-back
      // returns to it. Reuse the existing browser tab on subsequent opens to
      // avoid accumulating invisible tabs while the tab strip is disabled.
      final existingBrowserTab = state.tabs
          .where((tab) => !tab.isDashboard)
          .firstOrNull;
      if (existingBrowserTab == null) {
        if (actions.openTab(container, origin: origin) == null) {
          _showBrowserTabLimit();
          return;
        }
      } else {
        actions.activate(existingBrowserTab.tabId);
        if (existingBrowserTab.volId != container.volId) {
          actions.replaceActive(container, origin: origin);
        } else {
          // Preserve the latest entry point when reopening the same storage.
          actions.setOrigin(existingBrowserTab.tabId, origin);
        }
      }
    } else if (active.isDashboard || active.volId != container.volId) {
      // Regular navigation from the sidebar or Dashboard stays in the current
      // tab. The drawer's explicit long-press action owns new-tab creation.
      actions.replaceActive(container, origin: origin);
    }
    setState(() {
      _index = 0;
      _builtTabs.add(0);
    });
  }

  /// Drawer "Local storage" tap. With all-files access this opens the
  /// container directly. Without it there is no container, and the tap used
  /// to do nothing; the grant prompt has to be shown instead. That flow lives
  /// in the Dashboard, which is not always built: its tab may have been
  /// closed, and dual-pane browsing mounts only the two visible tabs. In that
  /// case the Dashboard tab is brought back first (without touching the other
  /// tabs) and the flow starts once it has mounted.
  Future<void> _openLocalStorageFromDrawer({
    int? currentVolId,
    BrowserTabs? workspaceActions,
  }) async {
    final primary = _primaryLocalStorageContainer;
    if (primary != null) {
      _openBrowser(primary);
      return;
    }

    var dashboard = _dashboardKey.currentState;
    if (dashboard == null) {
      final actions = workspaceActions ?? _browserWorkspaceActions;
      if (actions == null) return;
      actions.openDashboardTab();
      // A tab switch takes a frame or two to build the page.
      for (var frame = 0; frame < 5 && dashboard == null; frame++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        dashboard = _dashboardKey.currentState;
      }
    }
    await dashboard?.openLocalStorage(currentVolId: currentVolId);
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

  void _onBrowserWorkspaceChanged(BrowserTabsConfig? workspace) {
    _browserWorkspace = workspace;
    final pending = _browserInitialContainer;
    if (workspace != null && pending != null) {
      _browserInitialContainer = null;
      ref
          .read(browserTabsProvider(workspace).notifier)
          .openTab(pending, origin: _browserInitialOrigin);
      _browserInitialOrigin = BrowserTabOrigin.other;
      _index = 0;
    }
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _openNewBrowserTab() async {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    final actions = _browserWorkspaceActions;
    if (actions == null) return;
    _cacheDashboardLocalStorageContainer();
    final choice = await BrowserNewTabSheet.show(
      context,
      mountedVaults: _mountedNotifier.value,
      primaryLocalContainer: _primaryLocalStorageContainer,
    );
    if (!mounted || choice == null) return;
    if (choice.container == null) {
      if (actions.openNewDashboardTab() == null) {
        _showBrowserTabLimit();
        return;
      }
      setState(() => _index = 0);
      return;
    }
    final path = choice.path;
    final tabId = actions.openTab(
      choice.container!,
      initialPath: path == null || path.isEmpty ? null : path,
    );
    if (tabId == null) {
      _showBrowserTabLimit();
      return;
    }
    setState(() => _index = 0);
  }

  void _duplicateBrowserTab(BrowserTabState tab) {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    final actions = _browserWorkspaceActions;
    final container = tab.container;
    if (actions == null) return;
    if (tab.isDashboard) {
      actions.openDashboardTab();
      return;
    }
    if (container == null) return;
    final nav = ref.read(fileBrowserNavigationProvider(tab.tabId));
    final path = browserTabDuplicatePath(nav);
    if (actions.openTab(container, initialPath: path.isEmpty ? null : path) ==
        null) {
      _showBrowserTabLimit();
      return;
    }
    setState(() => _index = 0);
  }

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
        final activeTabId = _browserWorkspaceState?.activeTabId;
        if (activeTabId != null) {
          _browserWorkspaceActions?.closeOthers(activeTabId);
        }
      },
    );
    final workspace = _browserWorkspace;
    if (workspace != null) {
      ref.listen(
        browserTabsProvider(workspace).select((state) => state.activeTabId),
        (previous, next) {
          if (mounted && previous != next) setState(() {});
        },
      );
    }
    final tabsEnabled = ref.watch(
      appSettingsControllerProvider.select(
        (state) => state.settings.useBrowserTabs,
      ),
    );

    final isHidden = _hideDashboard || _handlingQuickCapture;

    Widget buildDashboardTab({
      bool backPreviewOnly = false,
      bool embedded = false,
      BrowserTabsConfig? workspaceConfig,
      ValueChanged<Widget?>? onFloatingActionChanged,
      ValueChanged<Widget?>? onBottomBarChanged,
    }) => SkinAreaScope(
      area: SkinArea.dashboard,
      child: VaultDashboard(
        key: backPreviewOnly ? null : _dashboardKey,
        mountedNotifier: backPreviewOnly ? null : _mountedNotifier,
        onNavigateTab: _onTabTap,
        workspaceConfig: backPreviewOnly ? null : workspaceConfig,
        backPreviewOnly: backPreviewOnly,
        embedded: embedded,
        onFloatingActionChanged: onFloatingActionChanged,
        onBottomBarChanged: onBottomBarChanged,
        onOpenBrowser: _openBrowser,
      ),
    );

    final body = IndexedStack(
      index: _index == 0 ? 0 : _index - 1,
      children: [
        // The browser workspace owns the single Dashboard page. Keeping an
        // empty slot here preserves the app destination index without building
        // a second, hidden Dashboard route.
        const SizedBox.expand(),
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
      final fromDashboard = _dashboardKey.currentState?.resolveAnyContainer(
        volId,
      );
      if (fromDashboard != null) return fromDashboard;
      final localStorage = _cachedLocalStorageContainer;
      return localStorage?.volId == volId ? localStorage : null;
    }

    Widget buildDrawer({int? currentVolId, BrowserTabsConfig? workspace}) {
      final workspaceActions = workspace == null
          ? null
          : ref.read(browserTabsProvider(workspace).notifier);
      return AppNavigationDrawer(
        currentVolId: currentVolId,
        primaryLocalContainer: _primaryLocalStorageContainer,
        onOpenInNewTab: workspaceActions == null || !tabsEnabled
            ? null
            : (container) {
                if (workspaceActions.openTab(container) == null && mounted) {
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
        keepBrowserTabsOnNavigate: workspaceActions != null,
        onSelectContainer: _openBrowser,
        onOpenLocalStorage: () => unawaited(
          _openLocalStorageFromDrawer(
            currentVolId: currentVolId,
            workspaceActions: workspaceActions,
          ),
        ),
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
    final Widget persistentBrowser = TickerMode(
      enabled: browserContentVisible,
      child: Offstage(
        offstage: !browserContentVisible,
        child: SkinAreaScope(
          area: SkinArea.files,
          child: BrowserTabsShell(
            key: const ValueKey('main-shell-browser-tabs-host'),
            initialContainer: null,
            resolveContainer: resolveContainer,
            mountedContainers: () => _mountedNotifier.value,
            primaryLocalContainer: () => _primaryLocalStorageContainer,
            drawerBuilder: (workspace, volId) =>
                buildDrawer(currentVolId: volId, workspace: workspace),
            closeRouteWhenEmpty: false,
            includeDashboardTab: true,
            homeBuilder:
                ({
                  required workspace,
                  required onFloatingActionChanged,
                  required onBottomBarChanged,
                }) => buildDashboardTab(
                  embedded: true,
                  workspaceConfig: workspace,
                  onFloatingActionChanged: onFloatingActionChanged,
                  onBottomBarChanged: onBottomBarChanged,
                ),
            onEmpty: () => _browserWorkspaceActions?.openDashboardTab(),
            onWorkspaceChanged: _onBrowserWorkspaceChanged,
            onNewTab: _openNewBrowserTab,
            onDuplicate: _duplicateBrowserTab,
          ),
        ),
      ),
    );
    final Widget appBody = Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: _index == 0, child: body),
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
        _browserWorkspaceState?.activeTab?.isDashboard ?? false;
    final atHome =
        _index == 0 && (!browserContentVisible || dashboardLocationIsActive);
    return PopScope(
      // Leaving the app from Home takes two backs: the first arms the exit and
      // says so, the second (within the window) lets the system leave. This
      // holds with or without other tabs open, because hidden tabs never veto.
      canPop: atHome && _exitArmed,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        // The focused folder tab handles back itself.
        if (browserContentVisible && !dashboardLocationIsActive) return;
        if (atHome) {
          _armExit();
          return;
        }
        _onTabTap(0);
      },
      child: content,
    );
  }
}
