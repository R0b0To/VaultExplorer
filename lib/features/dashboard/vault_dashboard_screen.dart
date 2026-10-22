import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/activity/clipboard_fab.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_activity_stack.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/full_screen_drag_drawer.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/browser/browser_tabs_host.dart';
import 'package:vaultexplorer/features/browser/models/browser_tab_origin.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/app_navigation_drawer.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/create_container_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/usb_create_container_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_dashboard_content_view.dart';
import 'package:vaultexplorer/features/dashboard/widgets/dashboard_app_bar.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';
import 'package:vaultexplorer/features/sync/ui/sync_status_banner.dart';
import 'package:vaultexplorer/features/unlock/unlock_sheet.dart';
import 'package:vaultexplorer/features/unlock/usb_unlock_sheet.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';

const _kLogTag = 'VaultDashboardScreen';

class VaultDashboard extends ConsumerStatefulWidget {
  final ValueNotifier<List<MountedContainer>>? mountedNotifier;
  final ValueChanged<int>? onNavigateTab;
  final BrowserTabsConfig? workspaceConfig;
  final bool embedded;
  final ValueChanged<Widget?>? onFloatingActionChanged;
  final ValueChanged<Widget?>? onBottomBarChanged;
  /// Opens [container] in the browser. Home tiles and unlock flows pass
  /// [BrowserTabOrigin.home] so that back at the root returns here.
  final void Function(MountedContainer container, {BrowserTabOrigin origin})?
  onOpenBrowser;
  final bool backPreviewOnly;

  const VaultDashboard({
    super.key,
    this.mountedNotifier,
    this.onNavigateTab,
    this.workspaceConfig,
    this.embedded = false,
    this.onFloatingActionChanged,
    this.onBottomBarChanged,
    this.onOpenBrowser,
    this.backPreviewOnly = false,
  });

  @override
  ConsumerState<VaultDashboard> createState() => VaultDashboardState();
}

class VaultDashboardState extends ConsumerState<VaultDashboard>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  SessionLockController get _lockController =>
      ref.read(sessionLockControllerProvider);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isFabVisible = true;
  bool _isEnforcingLock = false;
  late final ProviderContainer _container;

  // Cached stand-in [MountedContainer] for real device storage (see
  // buildLocalStorageContainer), refreshed whenever all-files access is
  // (re-)checked. Doubles as the "do we currently have access" flag --
  // null means no access (or not yet checked), non-null means
  // [LocalStorageCard] can render and cross-container paste can resolve
  // it. This has to be pre-built and held rather than constructed lazily
  // inside resolveContainer, because resolveContainer is a synchronous
  // callback but resolving the real storage root is async (see
  // DecoyLocalRepository.primaryRoot).
  MountedContainer? _localStorageContainer;
  MountedContainer? get localStorageContainer => _localStorageContainer;
  bool _pendingLocalStoragePermissionCheck = false;
  late final AnimationController _dashboardAppBarAnimController =
      AnimationController(vsync: this, duration: AppMotion.short2, value: 1.0);
  int? _pendingLocalStorageOriginVolId;
  int _localStoragePermissionRequestId = 0;
  void showAddOptionsSheet() => _showAddOptionsSheet();

  void reloadDashboard() {
    ref.read(vaultDashboardControllerProvider.notifier).loadAll();
  }

  BrowserTabsState? get _workspaceState {
    final config = widget.workspaceConfig;
    return config == null ? null : ref.read(browserTabsProvider(config));
  }

  BrowserTabs? get _workspaceActions {
    final config = widget.workspaceConfig;
    return config == null
        ? null
        : ref.read(browserTabsProvider(config).notifier);
  }

  Future<void> _checkStorageAccess() async {
    final hasAccess = await ref
        .read(vaultLifecycleApiProvider)
        .hasAllFilesAccess();
    if (!mounted) return;
    if (!hasAccess) {
      setState(() => _localStorageContainer = null);
      return;
    }
    final displayName = context.l10n.localStorageCardTitle;
    final root = await const DecoyLocalRepository().primaryRoot();
    if (!mounted) return;
    setState(() {
      _localStorageContainer = buildLocalStorageContainer(
        rootPath: root.path,
        displayName: displayName,
      );
    });
  }

  Future<void> _handleAppResume() async {
    await _checkStorageAccess();
    if (!mounted || !_pendingLocalStoragePermissionCheck) return;
    await _finishLocalStoragePermissionRequest(
      _localStoragePermissionRequestId,
    );
  }

  // Resolves either a real, currently-mounted vault OR the cached local
  // storage pseudo-container by volId. Used as `resolveContainer` for
  // every pushed FileBrowserScreen -- vault and Local Storage alike --
  // so a cross-container paste can look up whichever side of the
  // transfer it didn't open from. A vault-only lookup here (the old
  // behavior) is exactly what caused "cross-container paste requires
  // both containers to be mounted": Local Storage never appears in
  // `state.mounted` (see getDisplayItems's doc comment), so pasting
  // between it and a vault, in either direction, always failed to
  // resolve the container it didn't open from.
  /// Public so MainShell's own file-manager launches can resolve other
  /// volumes (cross-vault paste, tabs) the same way the dashboard does.
  MountedContainer? resolveAnyContainer(int volId) =>
      _resolveAnyContainer(volId);

  MountedContainer? _resolveAnyContainer(int volId) {
    if (volId == kDecoyLocalVolId) return _localStorageContainer;
    if (volId <= kExternalStorageBaseVolId) {
      return ref
          .read(externalStorageLocationsProvider.notifier)
          .resolveContainer(volId);
    }
    for (final c in ref.read(vaultDashboardControllerProvider).mounted) {
      if (c.volId == volId) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Cache the ProviderContainer so asynchronous callbacks (like auto-lock
    // and container unmounting) remain safe even after this widget is unmounted.
    _container = ProviderScope.containerOf(context, listen: false);
    if (widget.backPreviewOnly) return;
    _lockController.configure(
      settings: () => _container.read(appSettingsControllerProvider).settings,
      lockAllMountedContainers: _lockAllMountedContainers,
      lockImmediateOverrideContainers: _lockImmediateOverrideContainers,
      lockScreenLockOnlyContainers: _lockScreenLockOnlyContainers,
      enforceAppLock: _enforceAppLock,
    );
    _lockController.notifyAppUnlocked();
    WidgetsBinding.instance.addObserver(this);
    _checkStorageAccess();
  }

  @override
  void didUpdateWidget(covariant VaultDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  bool _handleDashboardScrollNotification(
    ScrollNotification notification, {
    required bool autoHideAppBar,
    required bool dashboardIsActive,
  }) {
    if (notification.metrics.axis != Axis.vertical || !dashboardIsActive) {
      return false;
    }

    void setProgress(double value) {
      final progress = value.clamp(0.0, 1.0).toDouble();
      if (_dashboardAppBarAnimController.value != progress) {
        _dashboardAppBarAnimController.value = progress;
      }
    }

    if (!autoHideAppBar) {
      if (_dashboardAppBarAnimController.value != 1.0) setProgress(1.0);
      return false;
    }

    final canScroll = notification.metrics.maxScrollExtent > 0.0;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      final pixels = notification.metrics.pixels;
      if (canScroll && pixels <= 0.0 && delta <= 0.0) {
        setProgress(1.0);
      } else if (delta != 0.0) {
        setProgress(
          _dashboardAppBarAnimController.value - (delta / kToolbarHeight),
        );
      }
    } else if (notification is OverscrollNotification) {
      final overscroll = notification.overscroll;
      if (overscroll != 0.0) {
        setProgress(
          _dashboardAppBarAnimController.value - (overscroll / kToolbarHeight),
        );
      }
    } else if (notification is ScrollEndNotification) {
      final pixels = notification.metrics.pixels;
      if (canScroll && pixels <= 0.0) {
        if (_dashboardAppBarAnimController.value != 1.0) {
          _dashboardAppBarAnimController.animateTo(
            1.0,
            duration: AppMotion.short2,
            curve: Curves.easeOutCubic,
          );
        }
      } else if (_dashboardAppBarAnimController.value > 0.0 &&
          _dashboardAppBarAnimController.value < 1.0) {
        _dashboardAppBarAnimController.animateTo(
          _dashboardAppBarAnimController.value >= 0.5 ? 1.0 : 0.0,
          duration: AppMotion.short2,
          curve: Curves.easeOutCubic,
        );
      }
    }
    return false;
  }

  void _handleDashboardPointerDown(PointerDownEvent _) {
    _lockController.scheduleAutoLock();
    _container
        .read(vaultDashboardControllerProvider.notifier)
        .resetAllAutoCloseTimers();
  }

  @override
  void dispose() {
    _dashboardAppBarAnimController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    VeLog.d(_kLogTag, 'didChangeAppLifecycleState: $state');
    if (state == AppLifecycleState.resumed) {
      ref.read(vaultDashboardControllerProvider.notifier).handleRefresh();
      unawaited(_handleAppResume());
    }
    _lockController.handleAppLifecycleState(state);
  }

  Future<void> _enforceAppLock() async {
    VeLog.i(
      _kLogTag,
      '_enforceAppLock: called (isEnforcingLock=$_isEnforcingLock)',
    );
    if (!mounted || _isEnforcingLock) return;
    _isEnforcingLock = true;
    try {
      final mode = await disguiseModeApi.getMode();
      if (!mounted) return;

      final navigator = Navigator.of(context);
      navigator.popUntil((route) => route.isFirst);

      if (mode == DisguiseMode.decoy) {
        VeLog.i(
          _kLogTag,
          '_enforceAppLock: decoy mode active, disabling secure screen instead of locking',
        );
        await _container.read(secureScreenPolicyProvider).disableForDecoy();
        return;
      }

      final settings = _container.read(appSettingsControllerProvider).settings;
      if (settings.useMasterPassword && settings.masterPasswordHash != null) {
        VeLog.i(
          _kLogTag,
          '_enforceAppLock: master password set -> pushing LockGateScreen',
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

  Future<void> _lockAllMountedContainers() async {
    final state = _container.read(vaultDashboardControllerProvider);
    final mountedList = state.mounted;
    final lifecycle = _container.read(vaultLifecycleApiProvider);
    final controller = _container.read(
      vaultDashboardControllerProvider.notifier,
    );

    VeLog.i(
      _kLogTag,
      '_lockAllMountedContainers: locking ${mountedList.length} container(s): '
      '${mountedList.map((c) => c.volId).toList()}',
    );

    for (final c in List<MountedContainer>.from(mountedList)) {
      if (state.records[c.uri]?.isExemptFromGlobalLock == true) {
        VeLog.d(
          _kLogTag,
          '_lockAllMountedContainers: volId=${c.volId} exempt (per-container '
          'Auto-Lock Duration configured), skipping',
        );
        continue;
      }
      if (!controller.acquireLockGuard(c.volId)) {
        VeLog.d(
          _kLogTag,
          '_lockAllMountedContainers: volId=${c.volId} guard busy, skipping',
        );
        continue;
      }
      try {
        final locked = await lifecycle.lockContainer(c.uri);
        if (locked) controller.onContainerLocked(c.volId);
      } finally {
        controller.releaseLockGuard(c.volId);
      }
    }
  }

  // Companion to _lockAllMountedContainers, for containers explicitly
  // configured to "Immediately" (ContainerRecord.autoCloseImmediately).
  // Called by SessionLockController on real screen-off/backgrounding events,
  // independent of the app-wide sweep above and its timing -- see
  // SessionLockController's class doc comment and _lockImmediateOverrides.
  // These containers are exempt from _lockAllMountedContainers (they're
  // "isExemptFromGlobalLock"), so there's no overlap/double-locking between
  // the two methods.
  Future<void> _lockImmediateOverrideContainers() async {
    final state = _container.read(vaultDashboardControllerProvider);
    final mountedList = state.mounted;
    final lifecycle = _container.read(vaultLifecycleApiProvider);
    final controller = _container.read(
      vaultDashboardControllerProvider.notifier,
    );

    final targets = mountedList
        .where((c) => state.records[c.uri]?.autoCloseImmediately == true)
        .toList(growable: false);
    if (targets.isEmpty) return;

    VeLog.i(
      _kLogTag,
      '_lockImmediateOverrideContainers: locking ${targets.length} '
      'Immediately-configured container(s): ${targets.map((c) => c.volId).toList()}',
    );

    for (final c in targets) {
      if (!controller.acquireLockGuard(c.volId)) {
        VeLog.d(
          _kLogTag,
          '_lockImmediateOverrideContainers: volId=${c.volId} guard busy, skipping',
        );
        continue;
      }
      try {
        final locked = await lifecycle.lockContainer(c.uri);
        if (locked) controller.onContainerLocked(c.volId);
      } finally {
        controller.releaseLockGuard(c.volId);
      }
    }
  }

  // Companion to _lockImmediateOverrideContainers, for containers
  // explicitly configured to "Screen Lock Only"
  // (ContainerRecord.autoCloseScreenLockOnly). Called by
  // SessionLockController ONLY from handleScreenOff -- never from
  // handleAppLifecycleState's resumed-after-backgrounding branch, since
  // ignoring mere app-backgrounding (screen still on) is exactly what this
  // mode means -- see SessionLockController's class doc comment and
  // _lockScreenLockOnlyOverrides. These containers are also exempt from
  // _lockAllMountedContainers (they're "isExemptFromGlobalLock"), so
  // there's no overlap/double-locking between the two methods.
  Future<void> _lockScreenLockOnlyContainers() async {
    final state = _container.read(vaultDashboardControllerProvider);
    final mountedList = state.mounted;
    final lifecycle = _container.read(vaultLifecycleApiProvider);
    final controller = _container.read(
      vaultDashboardControllerProvider.notifier,
    );

    final targets = mountedList
        .where((c) => state.records[c.uri]?.autoCloseScreenLockOnly == true)
        .toList(growable: false);
    if (targets.isEmpty) return;

    VeLog.i(
      _kLogTag,
      '_lockScreenLockOnlyContainers: locking ${targets.length} '
      'Screen-Lock-Only container(s): ${targets.map((c) => c.volId).toList()}',
    );

    for (final c in targets) {
      if (!controller.acquireLockGuard(c.volId)) {
        VeLog.d(
          _kLogTag,
          '_lockScreenLockOnlyContainers: volId=${c.volId} guard busy, skipping',
        );
        continue;
      }
      try {
        final locked = await lifecycle.lockContainer(c.uri);
        if (locked) controller.onContainerLocked(c.volId);
      } finally {
        controller.releaseLockGuard(c.volId);
      }
    }
  }

  /// Opens [container] in an additional file-manager tab (long-press menu of
  /// the drawer's vaults and storages).
  void _openInNewTab(MountedContainer container) {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    if (_workspaceActions?.openTab(container) == null && mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.browserTabLimitReached(kMaxBrowserTabs),
        tone: AppBannerTone.warning,
      );
    }
  }

  Widget _buildDrawer({int? currentVolId, BrowserTabsConfig? workspace}) {
    final workspaceActions = workspace == null
        ? null
        : ref.read(browserTabsProvider(workspace).notifier);
    return AppNavigationDrawer(
      currentVolId: currentVolId,
      onOpenInNewTab:
          workspaceActions == null ||
              !ref.read(appSettingsControllerProvider).settings.useBrowserTabs
          ? null
          : _openInNewTab,
      primaryLocalContainer: _localStorageContainer,
      onOpenLocalStorage: () =>
          unawaited(_openLocalStorage(currentVolId: currentVolId)),
      selectedTabIndex: 0,
      onSelectTab: widget.onNavigateTab,
      keepBrowserTabsOnNavigate:
          widget.onOpenBrowser != null && workspaceActions != null,
      onSelectContainer: (newContainer) {
        // Inside the tabbed file manager the drawer switches the *active tab*
        // instead of replacing the whole route (which would drop every tab).
        if (workspaceActions != null) {
          if (widget.onOpenBrowser != null) {
            widget.onOpenBrowser!(newContainer);
          } else {
            workspaceActions.replaceActive(newContainer);
          }
          return;
        }
        if (currentVolId == null) {
          Navigator.push(context, _buildBrowserRoute(newContainer));
        } else {
          Navigator.pushReplacement(context, _buildBrowserRoute(newContainer));
        }
      },
      onUnlockVault: openItem,
      onAddVault: _showAddOptionsSheet,
    );
  }

  Route<void> _buildBrowserRoute(MountedContainer container) {
    return buildBrowserTabsRoute(
      container: container,
      resolveContainer: _resolveAnyContainer,
      mountedContainers: () =>
          ref.read(vaultDashboardControllerProvider).mounted,
      primaryLocalContainer: () => _localStorageContainer,
      drawerBuilder: (workspace, volId) =>
          _buildDrawer(currentVolId: volId, workspace: workspace),
      // Unknown / on-device volIds are ignored by the controller, which
      // matches the old local-storage route's no-op callback.
      userActivityFor: (volId) =>
          () => ref
              .read(vaultDashboardControllerProvider.notifier)
              .onUserActivityForContainer(volId),
    );
  }

  Route<void> _buildLocalStorageRoute(MountedContainer container) =>
      _buildBrowserRoute(container);

  Future<void> _openLocalStorage({int? currentVolId}) async {
    if (currentVolId == kDecoyLocalVolId) return;

    final lifecycle = ref.read(vaultLifecycleApiProvider);
    final hasAccess = await lifecycle.hasAllFilesAccess();
    if (!mounted) return;

    if (!hasAccess) {
      final shouldRequestAccess = await showAppConfirmDialog(
        context,
        title: context.l10n.localStoragePermissionTitle,
        message: context.l10n.filesPermissionMessage,
        confirmLabel: context.l10n.localStorageGrantAccess,
      );
      if (!mounted) return;
      if (!shouldRequestAccess) {
        await _promptToHideStorageLocations();
        return;
      }

      final sdkInt = await lifecycle.getAndroidSdkInt();
      if (!mounted) return;
      if (sdkInt >= 30) {
        final requestId = ++_localStoragePermissionRequestId;
        _pendingLocalStoragePermissionCheck = true;
        _pendingLocalStorageOriginVolId = currentVolId;
        final settingsOpened = await lifecycle.requestAllFilesAccess(
          openSettings: true,
        );
        if (!mounted) return;

        final accessGranted = await lifecycle.hasAllFilesAccess();
        if (accessGranted || !settingsOpened) {
          await _finishLocalStoragePermissionRequest(requestId);
        }
        return;
      }

      final granted = await lifecycle.requestAllFilesAccess();
      if (!mounted) return;
      if (!granted) {
        await _promptToHideStorageLocations();
        return;
      }
    }

    await _navigateToLocalStorage(currentVolId);
  }

  Future<void> _finishLocalStoragePermissionRequest(int requestId) async {
    if (!mounted ||
        !_pendingLocalStoragePermissionCheck ||
        requestId != _localStoragePermissionRequestId) {
      return;
    }

    final granted = await ref
        .read(vaultLifecycleApiProvider)
        .hasAllFilesAccess();
    if (!mounted ||
        !_pendingLocalStoragePermissionCheck ||
        requestId != _localStoragePermissionRequestId) {
      return;
    }

    final originVolId = _pendingLocalStorageOriginVolId;
    _pendingLocalStoragePermissionCheck = false;
    _pendingLocalStorageOriginVolId = null;

    if (granted) {
      await _navigateToLocalStorage(originVolId);
    } else {
      await _promptToHideStorageLocations();
    }
  }

  Future<void> _promptToHideStorageLocations() async {
    if (!mounted) return;
    final shouldHide = await showAppConfirmDialog(
      context,
      title: context.l10n.hideStorageLocationsTitle,
      message: context.l10n.hideStorageLocationsPrompt,
      confirmLabel: context.l10n.hide,
    );
    if (!mounted || !shouldHide) return;
    await ref
        .read(appSettingsControllerProvider.notifier)
        .updateSettings(
          (settings) => settings.copyWith(showStorageLocationsInDrawer: false),
        );
  }

  Future<void> _navigateToLocalStorage(int? currentVolId) async {
    var container = _localStorageContainer;
    if (container == null) {
      // Shouldn't normally happen -- _checkStorageAccess populates this
      // before the card is even shown -- but fall back to resolving it
      // fresh rather than doing nothing if the cache is somehow empty.
      final root = await const DecoyLocalRepository().primaryRoot();
      if (!mounted) return;
      container = buildLocalStorageContainer(
        rootPath: root.path,
        displayName: context.l10n.localStorageCardTitle,
      );
      setState(() => _localStorageContainer = container);
    }
    if (widget.onOpenBrowser != null) {
      widget.onOpenBrowser!(container);
      return;
    }
    final tabs = _workspaceState;
    final actions = _workspaceActions;
    if (tabs != null && actions != null) {
      actions.replaceActive(container);
      return;
    }
    if (currentVolId == null) {
      await Navigator.push(context, _buildLocalStorageRoute(container));
    } else {
      await Navigator.pushReplacement(
        context,
        _buildLocalStorageRoute(container),
      );
    }
  }

  Future<void> _showUnlockSheet({String? uri, String? name}) async {
    final dashboardController = _container.read(
      vaultDashboardControllerProvider.notifier,
    );
    final state = _container.read(vaultDashboardControllerProvider);
    if (uri != null && state.mounted.any((c) => c.uri == uri)) {
      showAppSnackBar(context, message: context.l10n.containerAlreadyMounted);
      return;
    }
    if (state.actionInFlight) return;
    dashboardController.setActionInFlight(true);

    final record = uri != null ? state.records[uri] : null;
    final docProvider =
        record?.documentProvider ?? state.appSettings.defaultDocumentProvider;
    final autoMountFolders =
        record?.documentProviderFolders
            .where((f) => f.autoMount)
            .map((f) => f.path)
            .toList() ??
        const <String>[];
    final autoOpen = state.appSettings.autoOpenOnUnlock;

    MountedContainer? newlyMountedContainer;
    try {
      String? rememberedPassword;
      if (uri != null &&
          record?.unlockMethod == ContainerUnlockMethod.rememberPassword) {
        rememberedPassword = await _container
            .read(containerRepositoryProvider)
            .getPassword(uri);
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(
            area: SkinArea.dashboard,
            child: UnlockSheet(
              onMounted: (container, {record}) {
                dashboardController.onContainerMounted(
                  container,
                  record: record,
                );
                newlyMountedContainer = container;
                if (autoOpen && widget.onOpenBrowser != null) {
                  widget.onOpenBrowser!(
                    container,
                    origin: BrowserTabOrigin.home,
                  );
                }
              },
              openBrowserRoute: autoOpen && widget.onOpenBrowser == null
                  ? (container) => _buildBrowserRoute(container)
                  : null,
              initialUri: uri,
              initialName: name,
              prefillPassword: rememberedPassword,
              documentProvider: docProvider,
              autoMountFolders: autoMountFolders,
              mountedUris: state.mounted.map((c) => c.uri).toList(),
            ),
          ),
        ),
      );
      await dashboardController.loadAll();
      if (newlyMountedContainer != null) {
        await dashboardController.refreshContainerSpace(
          newlyMountedContainer!.volId,
        );
      }
    } finally {
      // Opening a vault can replace the dashboard tab while this route is
      // still open. The shared controller outlives that widget, so always
      // release the guard even if the dashboard itself has been disposed.
      dashboardController.setActionInFlight(false);
    }
  }

  Future<void> _showUsbUnlockSheet({ContainerRecord? existingRecord}) async {
    final dashboardController = _container.read(
      vaultDashboardControllerProvider.notifier,
    );
    final state = _container.read(vaultDashboardControllerProvider);
    if (state.actionInFlight) return;
    dashboardController.setActionInFlight(true);

    final autoOpen = state.appSettings.autoOpenOnUnlock;

    MountedContainer? newlyMountedContainer;
    try {
      String? rememberedPassword;
      if (existingRecord != null &&
          existingRecord.unlockMethod ==
              ContainerUnlockMethod.rememberPassword) {
        rememberedPassword = await _container
            .read(containerRepositoryProvider)
            .getPassword(existingRecord.uri);
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(
            area: SkinArea.dashboard,
            child: UsbUnlockSheet(
              onMounted: (container, {record}) {
                dashboardController.onContainerMounted(
                  container,
                  record: record,
                );
                newlyMountedContainer = container;
                if (autoOpen && widget.onOpenBrowser != null) {
                  widget.onOpenBrowser!(
                    container,
                    origin: BrowserTabOrigin.home,
                  );
                }
              },
              onReconnected: (container, migratedRecord, oldUri) {
                dashboardController.onUsbContainerReconnected(
                  container,
                  migratedRecord,
                  oldUri,
                );
                newlyMountedContainer = container;
              },
              openBrowserRoute: autoOpen && widget.onOpenBrowser == null
                  ? (container) => _buildBrowserRoute(container)
                  : null,
              documentProvider:
                  existingRecord?.documentProvider ??
                  state.appSettings.defaultDocumentProvider,
              autoMountFolders:
                  existingRecord?.documentProviderFolders
                      .where((f) => f.autoMount)
                      .map((f) => f.path)
                      .toList() ??
                  const <String>[],
              existingRecord: existingRecord,
              prefillPassword: rememberedPassword,
            ),
          ),
        ),
      );
      await dashboardController.loadAll();
      if (newlyMountedContainer != null) {
        await dashboardController.refreshContainerSpace(
          newlyMountedContainer!.volId,
        );
      }
    } finally {
      dashboardController.setActionInFlight(false);
    }
  }

  void _showUsbCreateSheet() {
    final state = ref.read(vaultDashboardControllerProvider);
    if (state.actionInFlight) return;
    ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(true);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SkinAreaScope(
          area: SkinArea.dashboard,
          child: const UsbCreateContainerSheet(),
        ),
      ),
    ).whenComplete(() {
      if (mounted)
        ref
            .read(vaultDashboardControllerProvider.notifier)
            .setActionInFlight(false);
    });
  }

  Future<void> _showCreateSheet() async {
    final state = ref.read(vaultDashboardControllerProvider);
    if (state.actionInFlight) return;
    ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(true);
    try {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(
            area: SkinArea.dashboard,
            child: const CreateContainerSheet(),
          ),
        ),
      );
      if (mounted) {
        await ref.read(vaultDashboardControllerProvider.notifier).loadAll();
      }
    } finally {
      if (mounted)
        ref
            .read(vaultDashboardControllerProvider.notifier)
            .setActionInFlight(false);
    }
  }

  Future<void> _showAddOptionsSheet() async {
    final state = ref.read(vaultDashboardControllerProvider);
    if (state.actionInFlight) return;
    ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(true);

    bool hasUsb = false;
    try {
      final devices = await ref
          .read(vaultLifecycleApiProvider)
          .listUsbDevices();
      hasUsb = devices.isNotEmpty;
    } catch (e) {
      VeLog.w(_kLogTag, 'USB device enumeration failed', e);
    }

    if (!mounted) return;
    ref
        .read(vaultDashboardControllerProvider.notifier)
        .setActionInFlight(false);
    HapticFeedback.lightImpact();

    final cs = Theme.of(context).colorScheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    showModalBottomSheet(
      context: context,
      isScrollControlled: isLandscape,
      constraints: isLandscape
          ? BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5)
          : null,
      builder: (sheetContext) => AppBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                context.l10n.addAVaultTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            SheetOptionTile(
              icon: Icons.lock_open_rounded,
              iconColor: cs.primary,
              title: context.l10n.mountExistingContainerTitle,
              subtitle: context.l10n.mountExistingContainerSubtitle,
              onTap: () {
                Navigator.pop(sheetContext);
                _showUnlockSheet();
              },
            ),
            if (hasUsb) ...[
              SheetOptionTile(
                icon: Icons.usb_rounded,
                iconColor: cs.tertiary,
                title: context.l10n.mountUsbDriveTitle,
                subtitle: context.l10n.mountUsbDriveSubtitle,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showUsbUnlockSheet();
                },
              ),
              SheetOptionTile(
                icon: Icons.usb_off_rounded,
                iconColor: cs.error,
                title: context.l10n.formatUsbDriveTitle,
                subtitle: context.l10n.formatUsbDriveSubtitle,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showUsbCreateSheet();
                },
              ),
            ],
            SheetOptionTile(
              icon: Icons.add_box_rounded,
              iconColor: cs.secondary,
              title: context.l10n.createNewContainerTitle,
              subtitle: context.l10n.createNewContainerSubtitle,
              onTap: () {
                Navigator.pop(sheetContext);
                _showCreateSheet();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showContainerConfig({
    required String uri,
    required String currentLabel,
  }) {
    HapticFeedback.mediumImpact();
    final state = ref.read(vaultDashboardControllerProvider);
    final existing = state.records[uri];
    MountedContainer? mountedContainer;
    for (final m in state.mounted) {
      if (m.uri == uri) {
        mountedContainer = m;
        break;
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SkinAreaScope(
          area: SkinArea.dashboard,
          child: ContainerConfigScreen(
            uri: uri,
            currentLabel: currentLabel,
            existingRecord: existing,
            appSettings: state.appSettings,
            mountedContainer: mountedContainer,
            onSaved: (record) => ref
                .read(vaultDashboardControllerProvider.notifier)
                .updateContainerRecord(uri, record),
          ),
        ),
      ),
    );
  }

  Future<void> _openBrowser(MountedContainer container) async {
    final openBrowser = widget.onOpenBrowser;
    if (openBrowser != null) {
      openBrowser(container, origin: BrowserTabOrigin.home);
      return;
    }
    await Navigator.push(context, _buildBrowserRoute(container));
    if (mounted) {
      ref
          .read(vaultDashboardControllerProvider.notifier)
          .refreshContainerSpace(container.volId);
    }
  }

  void openItem(VaultListItem item) {
    switch (item) {
      case MountedVaultItem(:final container):
        _openBrowser(container);
      case LockedVaultItem(:final record):
        record.isUsbSource
            ? _showUsbUnlockSheet(existingRecord: record)
            : _showUnlockSheet(uri: item.uri, name: item.name);
    }
  }

  void _requestEdit(VaultListItem item) {
    _showContainerConfig(uri: item.uri, currentLabel: item.name);
  }

  void _requestDelete(VaultListItem item) {
    if (item.isMounted) {
      showAppSnackBar(
        context,
        message: context.l10n.lockBeforeRemovingWarning,
        tone: AppBannerTone.warning,
      );
      return;
    }
    ref
        .read(vaultDashboardControllerProvider.notifier)
        .handleSwipeToRemove(item.uri, (item as LockedVaultItem).record);
  }

  Widget _buildBody(
    List<VaultListItem> displayItems,
    VaultDashboardViewState state,
    AppSettings appSettings,
  ) => VaultDashboardContentView(
    items: displayItems,
    state: state,
    settings: appSettings,
    onAdd: _showAddOptionsSheet,
    onOpen: openItem,
    onEdit: _requestEdit,
    onDelete: _requestDelete,
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultDashboardControllerProvider);
    final appSettingsState = ref.watch(appSettingsControllerProvider);
    final toolbarSettings = ref.watch(fileManagerToolbarSettingsProvider(null));
    final appSettings = appSettingsState.settings;
    final displayItems = ref
        .read(vaultDashboardControllerProvider.notifier)
        .getDisplayItems();

    if (widget.backPreviewOnly) {
      return ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: _buildBody(displayItems, state, appSettings),
      );
    }

    if (widget.mountedNotifier != null) {
      widget.mountedNotifier!.value = List.unmodifiable(state.mounted);
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final double undoBarHeight = 64.0 + (bottomInset > 0 ? bottomInset : 16.0);
    final workspaceConfig = widget.workspaceConfig;
    final workspaceState = workspaceConfig == null
        ? null
        : ref.watch(browserTabsProvider(workspaceConfig));
    final dashboardIsActive = workspaceState?.activeTab?.isDashboard ?? true;
    // In a hosted tab the shell owns a fixed app bar, so dashboard scrolling
    // never collapses or resizes it. Standalone mode retains its old behavior.
    final autoHideAppBar =
        !widget.embedded && toolbarSettings.config.autoHideAppBar;
    const dashboardAppBar = DashboardAppBar();

    final dashboardContent = NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _handleDashboardScrollNotification(
          notification,
          autoHideAppBar: autoHideAppBar,
          dashboardIsActive: dashboardIsActive,
        );
        if (notification is UserScrollNotification &&
            notification.metrics.axis == Axis.vertical) {
          final direction = notification.direction;
          if (direction == ScrollDirection.forward) {
            if (!_isFabVisible) setState(() => _isFabVisible = true);
          } else if (direction == ScrollDirection.reverse) {
            if (_isFabVisible) setState(() => _isFabVisible = false);
          }
        }
        return false;
      },
      child: Column(
        children: [
          const SyncStatusBanner(),
          Expanded(child: _buildBody(displayItems, state, appSettings)),
        ],
      ),
    );

    final dashboardFloatingAction = AnimatedSlide(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      offset: _isFabVisible ? Offset.zero : const Offset(0, 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _isFabVisible ? 1.0 : 0.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const ClipboardFab(heroTag: 'dashboard_clipboard_fab'),
            const SizedBox(height: 12),
            SizedBox(
              width: 64,
              height: 64,
              child: FloatingActionButton(
                onPressed: _isFabVisible ? _showAddOptionsSheet : null,
                child: const Icon(Icons.add_rounded, size: 28),
              ),
            ),
          ],
        ),
      ),
    );
    final dashboardBottomBar = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: state.showUndoBar ? undoBarHeight : 0.0,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Container(
          height: undoBarHeight,
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            bottomInset > 0 ? bottomInset : 16.0,
          ),
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            offset: state.showUndoBar ? Offset.zero : const Offset(0, 1.5),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: state.showUndoBar ? 1.0 : 0.0,
              child: _FloatingUndoBar(
                label: state.recentlyDeletedRecord?.label ?? '',
                onUndo: () => ref
                    .read(vaultDashboardControllerProvider.notifier)
                    .handleUndo(),
              ),
            ),
          ),
        ),
      ),
    );
    if (widget.embedded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onFloatingActionChanged?.call(dashboardFloatingAction);
        widget.onBottomBarChanged?.call(
          state.showUndoBar ? dashboardBottomBar : null,
        );
      });
    }

    // Hosted content is a viewport body only. BrowserTabsHost owns the single
    // app bar and tab strip, and PageView owns horizontal navigation.
    if (widget.embedded) {
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handleDashboardPointerDown,
        child: dashboardContent,
      );
    }

    final isDrawerHosted = FullScreenDragDrawerScope.maybeOf(context) != null;
    final Widget screen = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDashboardPointerDown,
      child: Scaffold(
        key: _scaffoldKey,
        drawerEnableOpenDragGesture: false,
        drawer: null,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              ClipRect(
                child: AnimatedBuilder(
                  animation: _dashboardAppBarAnimController,
                  builder: (context, _) {
                    final factor = autoHideAppBar
                        ? _dashboardAppBarAnimController.value
                        : 1.0;
                    if (factor == 0.0) return const SizedBox.shrink();
                    return Align(
                      alignment: Alignment.bottomCenter,
                      heightFactor: factor,
                      child: SizedBox(
                        height: kToolbarHeight,
                        child: MediaQuery.removePadding(
                          context: context,
                          removeTop: true,
                          child: dashboardAppBar,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Expanded(child: dashboardContent),
            ],
          ),
        ),
        floatingActionButton: dashboardFloatingAction,
        bottomNavigationBar: state.showUndoBar
            ? dashboardBottomBar
            : const SizedBox.shrink(),
      ),
    );

    if (isDrawerHosted) return screen;
    return FullScreenDragDrawer(
      drawer: _buildDrawer(workspace: workspaceConfig),
      child: screen,
    );
  }
}

class _FloatingUndoBar extends StatelessWidget {
  final String label;
  final VoidCallback onUndo;
  const _FloatingUndoBar({required this.label, required this.onUndo});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return FloatingPill(
      color: cs.inverseSurface,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.delete_outline_rounded,
            size: AppIconSize.standard,
            color: cs.onInverseSurface,
          ),
          const SizedBox(width: 12),
          Flexible(
            child: AnimatedSwitcher(
              duration: AppMotion.short2,
              child: Text(
                context.l10n.removedLabelUndo(label),
                key: ValueKey(label),
                style: textTheme.labelLarge?.copyWith(
                  color: cs.onInverseSurface,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onUndo,
            style: TextButton.styleFrom(
              foregroundColor: cs.inversePrimary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              context.l10n.undo,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
