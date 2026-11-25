import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/quick_capture_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/core/windowing/view_focus.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/core/widgets/layout/docked_content_frame.dart';
import 'package:vaultexplorer/core/widgets/layout/resizable_split_pane.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_title_bar.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/models/new_tab_behavior.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/browser_tabs_host.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_session_store.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/models/browser_tab_origin.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_new_tab_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_title_bar_tabs.dart';
import 'package:vaultexplorer/features/browser/file_manager_environment.dart';
import 'package:vaultexplorer/features/browser/file_manager_window.dart';
import 'package:vaultexplorer/features/dashboard/drawer_unlock_flow.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_screen.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/app_navigation_drawer.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/share_import/share_import_flow.dart';
import 'package:vaultexplorer/features/camera/quick_capture_screen.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';
import 'package:vaultexplorer/core/widgets/menus/back_dismissible_menu_anchor.dart';

const _kLogTag = 'MainShell';

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
  late final ProviderContainer _container;
  bool _isEnforcingLock = false;
  late bool _hideDashboard = widget.hideDashboardUntilShareHandled;
  final ValueNotifier<List<MountedContainer>> _mountedNotifier = ValueNotifier(
    const [],
  );
  final ValueNotifier<MountedContainer?> _localStorageNotifier = ValueNotifier(
    null,
  );
  // One key per Vaults tab: several can be open at once, and a GlobalKey may
  // only be mounted once.
  final Map<TabId, GlobalKey<VaultDashboardState>> _dashboardKeys = {};

  GlobalKey<VaultDashboardState> _dashboardKeyFor(TabId tabId) =>
      _dashboardKeys.putIfAbsent(tabId, GlobalKey<VaultDashboardState>.new);

  /// The state of the Vaults tab in front, or of any mounted one when none is.
  /// The shell uses it for what is shared by all of them (the local-storage
  /// container, resolving a vault, opening the Add sheet), so it does not
  /// matter which one answers as long as the focused one is preferred.
  VaultDashboardState? get _dashboard {
    final active = _browserWorkspaceState?.activeTab;
    if (active != null && active.isDashboard) {
      final focused = _dashboardKeys[active.tabId]?.currentState;
      if (focused != null) return focused;
    }
    for (final key in _dashboardKeys.values) {
      final state = key.currentState;
      if (state != null) return state;
    }
    return null;
  }
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _scaffoldDrawerOpen = false;
  double _dockedSidebarWidth = AppBreakpoints.dockedSidebarWidth;
  final ValueNotifier<double> _dualPaneSplitFraction = ValueNotifier(0.5);

  // Holds the app body (Home/browser tabs, Tools, Settings) so rotating a
  // tablet or resizing a desktop window, which swaps the docked sidebar layout
  // for the modal-drawer one, moves the live body instead of rebuilding it:
  // open tabs, scroll positions and half-typed fields all survive.
  final GlobalKey _appBodyKey = GlobalKey(debugLabel: 'main-shell-app-body');
  MountedContainer? _cachedLocalStorageContainer;

  MountedContainer? get _primaryLocalStorageContainer {
    final dashboard = _dashboard;
    return dashboard == null
        ? _cachedLocalStorageContainer
        : dashboard.localStorageContainer;
  }

  void _cacheDashboardLocalStorageContainer() {
    final dashboard = _dashboard;
    if (dashboard != null) {
      _cachedLocalStorageContainer = dashboard.localStorageContainer;
    }
  }

  MountedContainer? _resolveContainer(int volId) {
    for (final c in _mountedNotifier.value) {
      if (c.volId == volId) return c;
    }
    if (volId <= kExternalStorageBaseVolId) {
      final external = ref
          .read(externalStorageLocationsProvider.notifier)
          .resolveContainer(volId);
      if (external != null) return external;
    }
    final fromDashboard = _dashboard?.resolveAnyContainer(
      volId,
    );
    if (fromDashboard != null) return fromDashboard;
    final localStorage = _cachedLocalStorageContainer;
    return localStorage?.volId == volId ? localStorage : null;
  }

  void _onScaffoldDrawerChanged(bool isOpen) {
    if (!mounted || _scaffoldDrawerOpen == isOpen) return;
    OpenDrawerBackGuard.setDrawerOpen(this, isOpen);
    setState(() => _scaffoldDrawerOpen = isOpen);
  }

  /// Hides the docked sidebar, or brings it back. Saved with the other
  /// interface settings, so it stays the way the person left it. Only reached
  /// from windows wide enough to dock the sidebar; elsewhere the menu is a
  /// modal drawer and there is nothing to hide.
  void _toggleDockedSidebar() {
    final collapsed = !ref
        .read(appSettingsControllerProvider)
        .settings
        .dockedSidebarCollapsed;
    unawaited(
      ref
          .read(appSettingsControllerProvider.notifier)
          .updateSettings(
            (settings) => settings.copyWith(dockedSidebarCollapsed: collapsed),
          ),
    );
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

  /// The tabs the person left open the last time this vault was revealed from
  /// Mask Mode, picked up again so they resume where they were instead of
  /// starting from an empty Home. Null for a normal launch, and when nothing
  /// is left to resume. See [BrowserSessionStore].
  BrowserTabsConfig? _restoredBrowserWorkspace;

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

  /// Keyboard shortcuts for tabs, for a tablet with a keyboard or a desktop
  /// window: Ctrl+T (Cmd+T on macOS) opens Home in a tab, Ctrl+W (Cmd+W)
  /// closes the tab in front, Ctrl+Tab / Ctrl+Shift+Tab cycle through tabs.
  /// They call the same tab actions as the tab strip and do nothing unless
  /// browser tabs are on and the tab pages (not Tools or Settings) are showing.
  ///
  /// This is a global key handler rather than a `Shortcuts` widget on purpose:
  /// a widget only hears keys while something inside it has focus, and giving
  /// the shell a focus node of its own would make it win the autofocus of
  /// fields that open later (a search bar, say).
  bool _handleTabShortcutKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    // Only while this page is the one in front: not under a dialog, a sheet or
    // another page, whose own fields keep their keys.
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    // Keys typed in another window (a file manager window) are not for this
    // shell's tabs.
    if (!keyboardFocusIsInViewOf(context)) return false;
    final keyboard = HardwareKeyboard.instance;
    final useMeta = Theme.of(context).platform == TargetPlatform.macOS;
    final primary = useMeta
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final key = event.logicalKey;
    if (primary && !keyboard.isAltPressed) {
      if (key == LogicalKeyboardKey.keyT) {
        _shortcutNewTab();
        return true;
      }
      if (key == LogicalKeyboardKey.keyW) {
        _shortcutCloseTab();
        return true;
      }
    }
    if (keyboard.isControlPressed && key == LogicalKeyboardKey.tab) {
      _shortcutCycleTab(keyboard.isShiftPressed ? -1 : 1);
      return true;
    }
    return false;
  }

  bool get _tabShortcutsActive =>
      _index == 0 &&
      ref.read(appSettingsControllerProvider).settings.useBrowserTabs;

  void _shortcutNewTab() {
    if (!_tabShortcutsActive) return;
    unawaited(_openNewBrowserTab());
  }

  void _shortcutCloseTab() {
    if (!_tabShortcutsActive) return;
    final state = _browserWorkspaceState;
    final activeTabId = state?.activeTabId;
    // The last tab stays: closing it would leave nothing to show.
    if (state == null || activeTabId == null || state.tabs.length < 2) return;
    _browserWorkspaceActions?.closeTab(activeTabId);
  }

  void _shortcutCycleTab(int step) {
    if (!_tabShortcutsActive) return;
    final state = _browserWorkspaceState;
    if (state == null || state.tabs.length < 2 || state.activeIndex < 0) {
      return;
    }
    final count = state.tabs.length;
    _browserWorkspaceActions?.activateIndex(
      (state.activeIndex + step + count) % count,
    );
  }

  bool get _isBrowserContentVisible => _index == 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_handleTabShortcutKey);
    FileManagerEnvironment.instance.attach(
      resolveContainer: _resolveContainer,
      mountedContainers: () =>
          ref.read(vaultDashboardControllerProvider).mounted,
      primaryLocalContainer: () => _primaryLocalStorageContainer,
      openWindow: (container, initialPath) =>
          openFileManagerWindow(container: container, initialPath: initialPath),
      openVaultsWindow: (title) => openFileManagerWindow(title: title),
    );
    // Cached so asynchronous lock callbacks stay safe after this widget is
    // unmounted.
    _container = ProviderScope.containerOf(context, listen: false);
    if (widget.returnToDecoyOnBackground) {
      _restoredBrowserWorkspace = _container
          .read(browserSessionStoreProvider)
          .resumable();
    }
    _quickCaptureColdStart = ref.read(pendingQuickCaptureLaunchProvider).take();
    if (!_quickCaptureColdStart) {
      // The Settings tab used to be the thing that created -- and so started
      // loading -- this keepAlive controller on the first frame. The
      // dashboard, file browser and authenticator registry later read its
      // `.settings` and expect it already loaded, so creating it here keeps
      // that timing now that the tab itself is built lazily.
      ref.read(appSettingsControllerProvider);
      _configureSessionLock();
    }
    final policy = _secureScreenPolicy; // Eagerly evaluate while mounted
    // Revealed from Mask Mode: the persisted mode is still `decoy`, so mark
    // the vault as visible or later "decoy -> disable FLAG_SECURE" syncs
    // (dashboard load, mount changes, app-lock enforcement) would strip the
    // screenshot block the user asked for.
    if (widget.returnToDecoyOnBackground) policy.beginRevealedVault();
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
    final lockController = ref.read(sessionLockControllerProvider);
    var leaveToDecoy = false;
    if (widget.returnToDecoyOnBackground &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused)) {
      // System pickers and similar operations deliberately suppress auto-lock;
      // they may briefly background this activity but should not close the
      // revealed vault shell while the external operation is in progress.
      //
      // The same goes for a running audio/video recording
      // ([SessionLockController.isVaultAutoLockPaused] is held for exactly as
      // long as one is in progress). Popping to the decoy would dispose the
      // capture screen, which ends the recording and throws the take away --
      // and nothing is being locked by it, so there is nothing to gain. The
      // vault shell simply stays as the person left it until the next time the
      // app is backgrounded without a recording running.
      leaveToDecoy =
          !lockController.isLockSuppressed &&
          !lockController.isVaultAutoLockPaused;
    }
    if (leaveToDecoy) {
      // Nothing from the vault may keep playing in the decoy identity.
      unawaited(BackgroundPlaybackHost.instance.closeAndWait());
      final navigator = Navigator.of(context, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
    }
    // Background/resume locking is driven from here rather than from the
    // Dashboard: Home is replaced by the vault's tab when a vault is opened
    // from it, so the Dashboard (and its observer) is gone for as long as the
    // person is inside a vault.
    if (!_quickCaptureColdStart) {
      lockController.handleAppLifecycleState(state);
    }
    // Re-scan physical storage volumes (SD card / USB) when the app comes
    // back to the foreground: a volume inserted while backgrounded is then
    // picked up without a full restart. Only user-added locations are
    // persisted, so the reload can't lose them.
    if (state == AppLifecycleState.resumed) {
      ref
          .read(externalStorageLocationsProvider.notifier)
          .refreshSystemVolumes();
    }
  }

  void _configureSessionLock() {
    final lockController = ref.read(sessionLockControllerProvider);
    lockController.configure(
      settings: () => _container.read(appSettingsControllerProvider).settings,
      lockAllMountedContainers: () => _container
          .read(vaultDashboardControllerProvider.notifier)
          .lockAllMountedContainersForAutoLock(),
      // Containers set to "Immediately", locked on real background/screen-off
      // events independently of the app-wide sweep (see SessionLockController).
      lockImmediateOverrideContainers: () => _container
          .read(vaultDashboardControllerProvider.notifier)
          .lockImmediatelyConfiguredContainers(),
      // Containers set to "Screen Lock Only"; SessionLockController only calls
      // this from handleScreenOff, never for mere backgrounding.
      lockScreenLockOnlyContainers: () => _container
          .read(vaultDashboardControllerProvider.notifier)
          .lockScreenLockOnlyConfiguredContainers(),
      enforceAppLock: _enforceAppLock,
    );
    lockController.notifyAppUnlocked(preserveBackgroundState: true);
    unawaited(_resumePersistedVaultAutoLock());
  }

  Future<void> _resumePersistedVaultAutoLock() async {
    await _container.read(appSettingsControllerProvider.notifier).load();
    if (!mounted) return;
    await ref
        .read(sessionLockControllerProvider)
        .resumeFromPersistedBackgroundState(evaluateAppLock: false);
  }

  Future<void> _enforceAppLock() async {
    VeLog.i(
      _kLogTag,
      '_enforceAppLock: called (isEnforcingLock=$_isEnforcingLock)',
    );
    if (!mounted || _isEnforcingLock) return;
    _isEnforcingLock = true;
    try {
      // Native windows (vault settings on desktop) are not routes of the
      // navigator popped below, so they are closed here: nothing from a vault
      // may stay on screen behind the lock gate.
      SecondaryWindows.instance.closeAll();
      final mode = await disguiseModeApi.getMode();
      if (!mounted) return;

      // Background audio must not outlive the app lock.
      final lockSettings = _container
          .read(appSettingsControllerProvider)
          .settings;
      if (mode == DisguiseMode.decoy || lockSettings.masterLockActive) {
        unawaited(BackgroundPlaybackHost.instance.closeAndWait());
      }

      final navigator = Navigator.of(context);
      // In the decoy identity there is no lock gate: "locking the app" only
      // means going back to the decoy page. That pop would dispose a live
      // capture screen and end its recording, so it waits for the recording
      // to finish (see didChangeAppLifecycleState, same reasoning).
      final recordingActive = _container
          .read(sessionLockControllerProvider)
          .isVaultAutoLockPaused;
      if (mode == DisguiseMode.decoy && recordingActive) {
        VeLog.i(
          _kLogTag,
          '_enforceAppLock: decoy mode with a recording active, staying on the current page',
        );
      } else {
        navigator.popUntil((route) => route.isFirst);
      }

      if (mode == DisguiseMode.decoy) {
        VeLog.i(
          _kLogTag,
          '_enforceAppLock: decoy mode active, disabling secure screen instead of locking',
        );
        await _container.read(secureScreenPolicyProvider).disableForDecoy();
        return;
      }

      final settings = _container.read(appSettingsControllerProvider).settings;
      if (settings.masterLockActive) {
        VeLog.i(
          _kLogTag,
          '_enforceAppLock: master lock set -> pushing LockGateScreen',
        );
        navigator.pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const LockGateScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
          (route) => false,
        );
      } else {
        VeLog.d(
          _kLogTag,
          '_enforceAppLock: no master password set, nothing to push',
        );
        _container.read(sessionLockControllerProvider).notifyAppUnlocked();
      }
    } finally {
      _isEnforcingLock = false;
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
    FileManagerEnvironment.instance.detach();
    HardwareKeyboard.instance.removeHandler(_handleTabShortcutKey);
    WidgetsBinding.instance.removeObserver(this);
    OpenDrawerBackGuard.setDrawerOpen(this, false);
    _exitArmTimer?.cancel();
    _mountedNotifier.dispose();
    _localStorageNotifier.dispose();
    _dualPaneSplitFraction.dispose();
    _vaultEngineEvents.removeIncomingShareRequestListener(
      _onIncomingShareRequest,
    );
    _vaultEngineEvents.removeQuickCaptureRequestedListener(
      _onQuickCaptureRequested,
    );
    if (widget.returnToDecoyOnBackground) {
      // Safe: calling the cached service directly without using `ref`
      unawaited(_secureScreenPolicy.endRevealedVault());
    } else {
      disguiseModeApi.getMode().then((mode) {
        if (mode == DisguiseMode.decoy) {
          _secureScreenPolicy.disableForDecoy();
        }
      });
    }
    super.dispose();
  }

  void _onTabTap(int newIndex) {
    var returningToHome = false;
    if (newIndex == 0) {
      final workspace = _browserWorkspaceState;
      returningToHome =
          _index != 0 || workspace?.activeTab?.isDashboard != true;
      final tabsEnabled = ref
          .read(appSettingsControllerProvider)
          .settings
          .useBrowserTabs;
      if (workspace?.activeTab == null) {
        _browserWorkspaceActions?.openDashboardTab();
      } else if (tabsEnabled && workspace!.tabs.any((tab) => tab.isDashboard)) {
        // A Vaults tab is already open: go to it instead of turning the tab
        // in front, which may hold a vault, into a second one.
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
    if (returningToHome) _dashboard?.reloadDashboard();
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

  void _openCategoryTab(FileCategory category) {
    _cacheDashboardLocalStorageContainer();
    final actions = _browserWorkspaceActions;
    if (actions == null) return;
    final tabId = actions.openCategoryTab(
      category,
      primaryLocalContainer: _primaryLocalStorageContainer,
      includeVaults: true,
    );
    if (tabId == null && mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.browserTabLimitReached(kMaxBrowserTabs),
        tone: AppBannerTone.warning,
      );
      return;
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
    MountedContainer? external,
  }) async {
    final primary = _primaryLocalStorageContainer;
    if (primary != null && external == null) {
      _openBrowser(primary);
      return;
    }

    var dashboard = _dashboard;
    if (dashboard == null) {
      final actions = workspaceActions ?? _browserWorkspaceActions;
      if (actions == null) return;
      actions.openDashboardTab();
      // A tab switch takes a frame or two to build the page.
      for (var frame = 0; frame < 5 && dashboard == null; frame++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        dashboard = _dashboard;
      }
    }
    await dashboard?.openLocalStorage(
      currentVolId: currentVolId,
      external: external,
    );
  }

  /// Same as [_openLocalStorageFromDrawer], but for an external raw-path
  /// storage (SD card / USB): brings the Dashboard up first if needed, then
  /// opens the volume through its all-files-access permission flow.
  Future<void> _openExternalStorageFromDrawer(
    MountedContainer externalContainer, {
    BrowserTabs? workspaceActions,
  }) =>
      _openLocalStorageFromDrawer(
        currentVolId: externalContainer.volId,
        workspaceActions: workspaceActions,
        external: externalContainer,
      );

  void _openVaultFromDrawer(VaultListItem item) {
    switch (item) {
      case MountedVaultItem(:final container):
        _openBrowser(container);
      case LockedVaultItem(:final record):
        // The drawer is a navigation surface: tapping a locked vault means
        // "take me there", exactly like tapping a mounted one. It therefore
        // always has one unlock path (independent of whether the Dashboard
        // tab happens to be mounted) and always opens the vault afterwards.
        unawaited(_showDrawerUnlock(record));
    }
  }

  Future<void> _showDrawerUnlock(ContainerRecord record) => showDrawerUnlock(
    context: context,
    ref: ref,
    record: record,
    isMounted: () => mounted,
    onOpen: _openBrowser,
  );

  void _onBrowserWorkspaceChanged(BrowserTabsConfig? workspace) {
    _browserWorkspace = workspace;
    if (workspace != null && widget.returnToDecoyOnBackground) {
      // Revealed from Mask Mode: keep these tabs alive for when the app goes
      // back to the decoy, so the next reveal resumes them. Nothing to do on
      // the null call from dispose -- the store simply keeps holding them.
      _container.read(browserSessionStoreProvider).hold(_container, workspace);
    }
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

  /// Opens a new tab the way the "New tab" setting asks: a copy of the tab in
  /// front, the prompt, or a fixed storage. A storage that cannot be opened
  /// right now falls back to the prompt.
  Future<void> _openNewBrowserTab() async {
    final settings = ref.read(appSettingsControllerProvider).settings;
    if (!settings.useBrowserTabs) return;
    final actions = _browserWorkspaceActions;
    if (actions == null) return;
    // Don't offer a picker whose every choice would fail.
    if (_browserWorkspaceState?.atLimit ?? false) {
      _showBrowserTabLimit();
      return;
    }
    _cacheDashboardLocalStorageContainer();
    final active = _browserWorkspaceState?.activeTab;
    switch (settings.newTabBehavior) {
      case NewTabBehavior.duplicate:
        if (active != null) {
          _duplicateBrowserTab(active);
          return;
        }
      case NewTabBehavior.specificStorage:
        final choice = await BrowserNewTabSheet.resolveConfiguredStorage(
          context,
          storageId: settings.newTabStorageId,
          currentContainer: active?.container,
          primaryLocalContainer: _primaryLocalStorageContainer,
        );
        if (!mounted) return;
        if (choice != null) {
          _applyBrowserNewTabChoice(choice);
          return;
        }
      case NewTabBehavior.prompt:
        break;
    }
    final choice = await BrowserNewTabSheet.show(
      context,
      // Read the keepAlive controller directly: the notifier is only a mirror
      // and used to go stale while Home was off-screen.
      mountedVaults: ref.read(vaultDashboardControllerProvider).mounted,
      primaryLocalContainer: _primaryLocalStorageContainer,
    );
    if (!mounted || choice == null) return;
    _applyBrowserNewTabChoice(choice);
  }

  void _applyBrowserNewTabChoice(BrowserNewTabChoice choice) {
    final actions = _browserWorkspaceActions;
    if (actions == null) return;
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
      if (actions.openNewDashboardTab() == null) {
        _showBrowserTabLimit();
        return;
      }
      setState(() => _index = 0);
      return;
    }
    if (tab.isCategory) {
      if (actions.openCategoryTab(
            tab.category!,
            primaryLocalContainer: tab.primaryLocalContainer,
            includeVaults: tab.includeVaults,
          ) ==
          null) {
        _showBrowserTabLimit();
        return;
      }
      setState(() => _index = 0);
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
    // Keep the notifier (read by Tools and container resolution) in sync with
    // the keepAlive dashboard controller. The Dashboard widget used to be its
    // only writer, from its own build, so a lock/unlock done while Home was
    // not built (drawer, another tab) left the list stale until Home was shown.
    ref.listen<List<MountedContainer>>(
      vaultDashboardControllerProvider.select((state) => state.mounted),
      (_, mounted) => _mountedNotifier.value = List.unmodifiable(mounted),
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

    // Forget the keys of Vaults tabs that have been closed.
    final openTabs = _browserWorkspaceState?.tabs;
    if (openTabs != null) {
      _dashboardKeys.removeWhere(
        (id, _) => !openTabs.any((tab) => tab.tabId == id),
      );
    }

    // Tablet landscape and desktop windows get the navigation menu as a
    // permanent sidebar; everything else keeps the modal drawer. [docked] says
    // the window is big enough for the sidebar, and it also means "no modal
    // drawer", whether or not the sidebar is currently shown: a person who
    // hid it gets the full width back, and a menu button that brings the
    // sidebar back in place, never an overlay on top of the content.
    final docked = AppBreakpoints.useDockedSidebarFor(
      MediaQuery.sizeOf(context),
    );
    final sidebarCollapsed = ref.watch(
      appSettingsControllerProvider.select(
        (state) => state.settings.dockedSidebarCollapsed,
      ),
    );
    final sidebarShown = docked && !sidebarCollapsed;
    final hasWindowsTitleBar = PlatformFeatures.isWindows;

    Widget buildDashboardTab({
      bool backPreviewOnly = false,
      bool embedded = false,
      BrowserTabsConfig? workspaceConfig,
      TabId? tabId,
      ValueChanged<Widget?>? onFloatingActionChanged,
      ValueChanged<Widget?>? onBottomBarChanged,
    }) => SkinAreaScope(
      area: SkinArea.dashboard,
      child: VaultDashboard(
        key: backPreviewOnly || tabId == null ? null : _dashboardKeyFor(tabId),
        tabId: tabId,
        mountedNotifier: backPreviewOnly ? null : _mountedNotifier,
        localStorageNotifier: backPreviewOnly ? null : _localStorageNotifier,
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
      index: _index,
      children: [
        // The browser workspace owns the Vaults (Dashboard) pages. Keeping an
        // empty slot here preserves the app destination index without building
        // a second, hidden Dashboard route.
        const SizedBox.expand(),
        if (_builtTabs.contains(1))
          SkinAreaScope(
            area: SkinArea.tools,
            child: ToolsScreen(
              mountedContainers: _mountedNotifier,
              localStorageContainer: _localStorageNotifier,
              onNavigateTab: _onTabTap,
              onOpenInBrowser: _openBrowser,
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

    Widget buildDrawer({
      int? currentVolId,
      BrowserTabsConfig? workspace,
      bool docked = false,
    }) {
      final workspaceActions = workspace == null
          ? null
          : ref.read(browserTabsProvider(workspace).notifier);
       return AppNavigationDrawer(
        docked: docked,
        onHideSidebar: (docked && !hasWindowsTitleBar)
            ? _toggleDockedSidebar
            : null,
        currentVolId: currentVolId,
        primaryLocalContainer: _primaryLocalStorageContainer,
        localStorageNotifier: _localStorageNotifier,
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
        onOpenExternalStorage: (externalContainer) => unawaited(
          _openExternalStorageFromDrawer(
            externalContainer,
            workspaceActions: workspaceActions,
          ),
        ),
        onUnlockVault: _openVaultFromDrawer,
        onOpenCategory: _openCategoryTab,
        onAddVault: () {
          _onTabTap(0);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _dashboard?.showAddOptionsSheet();
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
            resolveContainer: _resolveContainer,
            mountedContainers: () =>
                ref.read(vaultDashboardControllerProvider).mounted,
            primaryLocalContainer: () => _primaryLocalStorageContainer,
            // A docked sidebar replaces the drawer, so the browser must not
            // build (or offer to open) one of its own.
            drawerBuilder: docked
                ? null
                : (workspace, volId) =>
                      buildDrawer(currentVolId: volId, workspace: workspace),
            closeRouteWhenEmpty: false,
            includeDashboardTab: true,
            externallyHostedTabStrip: PlatformFeatures.isWindows,
            onDualPaneSplitFractionChanged: PlatformFeatures.isWindows
                ? (fraction) => _dualPaneSplitFraction.value = fraction
                : null,
            restoredWorkspace: _restoredBrowserWorkspace,
            homeBuilder:
                ({
                  required workspace,
                  required tabId,
                  required onFloatingActionChanged,
                  required onBottomBarChanged,
                }) => buildDashboardTab(
                  embedded: true,
                  workspaceConfig: workspace,
                  tabId: tabId,
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
    final Widget appBody = KeyedSubtree(
      key: _appBodyKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Offstage(offstage: _index == 0, child: body),
          persistentBrowser,
        ],
      ),
    );

    // The sidebar/drawer highlights the vault whose tab is in front; Tools and
    // Settings, which live in the content area, highlight themselves.
    final activeMainTab = _index == 0 ? _browserWorkspaceState?.activeTab : null;
    final activeVolId = (activeMainTab == null || activeMainTab.isDashboard)
        ? null
        : activeMainTab.volId;

    Widget shellBody = appBody;
    if (sidebarShown) {
      shellBody = LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = (constraints.maxWidth - 8)
              .clamp(1.0, double.infinity)
              .toDouble();
          return ResizableSplitPane(
            axis: Axis.horizontal,
            initialFraction: _dockedSidebarWidth / availableWidth,
            minFirstExtent: 220,
            minSecondExtent: 480,
            maxFirstExtent: 460,
            dividerExtent: 8,
            onFirstExtentChanged: (extent) {
              if (!mounted || (_dockedSidebarWidth - extent).abs() < 0.5) {
                return;
              }
              setState(() => _dockedSidebarWidth = extent);
            },
            first: buildDrawer(
              docked: true,
              currentVolId: activeVolId,
              workspace: _browserWorkspace,
            ),
            second: DockedContentFrame(
              consumedWidth: _dockedSidebarWidth + 8,
              child: appBody,
            ),
          );
        },
      );
    }

    final browserTabsState = workspace == null
        ? null
        : ref.watch(browserTabsProvider(workspace));
    final showWorkspaceTabs = browserContentVisible &&
        tabsEnabled &&
        workspace != null &&
        browserTabsState != null;
    final titleBarLeadingWidth = sidebarShown ? _dockedSidebarWidth + 8 : 48.0;
    final Widget shellTitleTabs = !showWorkspaceTabs
        ? const SizedBox.shrink()
        : BrowserTitleBarTabs(
            workspace: workspace,
            docked: sidebarShown,
            splitFraction: _dualPaneSplitFraction,
            onNewTab: _openNewBrowserTab,
            onDuplicate: _duplicateBrowserTab,
          );
    final Widget? windowsTitleBar = hasWindowsTitleBar
        ? DesktopWindowTitleBar(
            height: 32,
            tabs: shellTitleTabs,
            leadingWidth: titleBarLeadingWidth,
            leadingDraggable: sidebarShown,
            leading: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SizedBox(
                width: 48,
                height: 32,
                child: Builder(
                  builder: (buttonContext) => IconButton(
                    icon: Icon(
                      sidebarShown
                          ? Icons.menu_open_rounded
                          : Icons.menu_rounded,
                      size: 18,
                    ),
                    tooltip: sidebarShown
                        ? buttonContext.l10n.hideSidebarTooltip
                        : buttonContext.l10n.showSidebarTooltip,
                    onPressed: docked
                        ? _toggleDockedSidebar
                        : () => Scaffold.of(buttonContext).openDrawer(),
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(32, 32),
                      maximumSize: const Size(32, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ),
            ),
          )
        : null;

    final Widget scaffoldBody = windowsTitleBar == null
        ? shellBody
        : Column(
            children: [
              windowsTitleBar,
              Expanded(child: shellBody),
            ],
          );
    // Always in the tree, so the Scaffold below keeps its place when the window
    // is resized across the docking breakpoint. Menu buttons in the pages read
    // it to bring a hidden sidebar back; it only reports "hidden" when this
    // window can dock one.
    final Widget scaffold = DockedSidebarToggle(
      collapsed: docked && sidebarCollapsed,
      onToggle: _toggleDockedSidebar,
      hostedInTitleBar: hasWindowsTitleBar,
      child: Scaffold(
        key: _scaffoldKey,
        onDrawerChanged: _onScaffoldDrawerChanged,
        resizeToAvoidBottomInset: !browserContentVisible,
        // Tools and Settings have no horizontal pager, so let a drawer drag
        // start anywhere in their content, too.
        drawerEdgeDragWidth: double.maxFinite,
        drawerEnableOpenDragGesture: _index != 0 && !docked,
        drawer: isHidden || docked
            ? null
            : buildDrawer(
                currentVolId: activeVolId,
                workspace: _browserWorkspace,
              ),
        body: scaffoldBody,
      ),
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
      //
      // When this shell was revealed from Mask Mode's decoy, Home is not the
      // end of the line: back goes straight to the decoy underneath, with no
      // exit hint. The decoy is the one that asks for the second back before
      // the app is left (see the app-root back handling in
      // DirectoryContentView).
      canPop:
          atHome &&
          !_scaffoldDrawerOpen &&
          !OpenDrawerBackGuard.hasOpenDrawer &&
          (_exitArmed || widget.returnToDecoyOnBackground),
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        // A menu is open: this press closes it (BackDismissibleMenuAnchor).
        if (OpenMenuBackGuard.hasOpenMenu) return;
        if (_scaffoldDrawerOpen) {
          scheduleMicrotask(() {
            if (mounted && _scaffoldDrawerOpen) {
              _scaffoldKey.currentState?.closeDrawer();
            }
          });
          return;
        }
        // BrowserTabsHost closes its drawer after all route back handlers have
        // observed this press.
        if (OpenDrawerBackGuard.hasOpenDrawer) return;
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
