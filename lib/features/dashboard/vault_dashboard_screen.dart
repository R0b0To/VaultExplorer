import 'package:vaultexplorer/core/utils/local_storage_name.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
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
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/browser/browser_tabs_host.dart';
import 'package:vaultexplorer/features/browser/controllers/chrome_bar_slot.dart';
import 'package:vaultexplorer/features/browser/models/browser_tab_origin.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/widgets/external_file_drop_zone.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/dashboard/dashboard_toolbar_actions.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/app_navigation_drawer.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_launcher.dart';
import 'package:vaultexplorer/features/dashboard/widgets/create_container_sheet.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/features/dashboard/widgets/usb_create_container_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_dashboard_content_view.dart';
import 'package:vaultexplorer/features/dashboard/widgets/dashboard_app_bar.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/features/sync/ui/sync_status_banner.dart';
import 'package:vaultexplorer/features/unlock/unlock_sheet.dart';
import 'package:vaultexplorer/features/unlock/usb_unlock_sheet.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/widgets/layout/adaptive_page_route.dart';
import 'package:vaultexplorer/core/widgets/sheets/adaptive_sheet.dart';

const _kLogTag = 'VaultDashboardScreen';

class VaultDashboard extends ConsumerStatefulWidget {
  final ValueNotifier<List<MountedContainer>>? mountedNotifier;
  final ValueNotifier<MountedContainer?>? localStorageNotifier;
  final ValueChanged<int>? onNavigateTab;
  final BrowserTabsConfig? workspaceConfig;

  /// The workspace tab this dashboard is the page of. Several Vaults tabs can
  /// be open at once, so a hosted dashboard needs to know which one it is for
  /// its own search text, toolbar actions and "am I the focused tab" checks.
  final TabId? tabId;
  final bool embedded;
  final ValueChanged<Widget?>? onFloatingActionChanged;
  final ValueChanged<Widget?>? onBottomBarChanged;

  /// Opens [container] in the browser. Home tiles and unlock flows pass
  /// [BrowserTabOrigin.home] to record that the storage was opened here.
  final void Function(MountedContainer container, {BrowserTabOrigin origin})?
  onOpenBrowser;
  final bool backPreviewOnly;

  const VaultDashboard({
    super.key,
    this.mountedNotifier,
    this.localStorageNotifier,
    this.onNavigateTab,
    this.workspaceConfig,
    this.tabId,
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
  // Every mounted (non-preview) dashboard, oldest first. Tab pages are kept
  // alive, so with several Vaults tabs open each one observes the app
  // lifecycle; the work that is only needed once per resume is left to the
  // oldest one (see [didChangeAppLifecycleState]).
  static final List<VaultDashboardState> _liveInstances = [];

  // Holds this tab's bottom bar for the chrome hub. See [ChromeBarSlot].
  final ChromeBarSlot _bottomBarSlot = ChromeBarSlot();

  SessionLockController get _lockController =>
      ref.read(sessionLockControllerProvider);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _isFabVisible = true;
  late final ProviderContainer _container;
  DashboardToolbarActions? _toolbarActions;

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
  // When the pending permission check was started for an external storage
  // (SD card / USB) rather than the primary local storage, this holds the
  // container to open once the grant lands (see _openLocalStorage).
  MountedContainer? _pendingLocalStorageOriginContainer;
  int _localStoragePermissionRequestId = 0;
  void showAddOptionsSheet() => _showAddOptionsSheet();

  /// Opens Local storage (or an external raw-path storage [external] --
  /// SD card / USB volume), first walking the person through granting
  /// all-files access when it is missing. Exposed so the app shell's drawer
  /// can use the same flow as the dashboard's own.
  Future<void> openLocalStorage({
    int? currentVolId,
    MountedContainer? external,
  }) =>
      _openLocalStorage(currentVolId: currentVolId, external: external);

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
      widget.localStorageNotifier?.value = null;
      return;
    }
    final displayName = localStorageDisplayName(context.l10n.localStorageCardTitle);
    final root = await const DecoyLocalRepository().primaryRoot();
    if (!mounted) return;
    setState(() {
      _localStorageContainer = buildLocalStorageContainer(
        rootPath: root.path,
        displayName: displayName,
      );
    });
    widget.localStorageNotifier?.value = _localStorageContainer;
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
    // Session-lock wiring (configure, background/resume handling, app-lock
    // gate) lives in MainShell: Home is replaced by the vault's tab when a
    // vault is opened from it, so this widget is not always alive.
    WidgetsBinding.instance.addObserver(this);
    _liveInstances.add(this);
    _checkStorageAccess();
    _toolbarActions = _container
        .read(dashboardToolbarActionsProvider)
        .forTab(widget.tabId);
    // Published after the first frame: notifying listeners while the tree is
    // still being built would throw.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _toolbarActions!.addVault.value = showAddOptionsSheet;
    });
    _toolbarActions!.searchQuery.addListener(_onSearchQueryChanged);
  }

  bool get _isSearchFiltering =>
      (_toolbarActions?.searchQuery.value.trim().isNotEmpty ?? false);

  void _onSearchQueryChanged() {
    if (mounted) setState(() {});
  }

  /// [items] narrowed to the vaults whose name contains the toolbar's search
  /// text. Only the shown list is filtered; stored order is untouched.
  List<VaultListItem> _applySearchFilter(List<VaultListItem> items) {
    final query = _toolbarActions?.searchQuery.value.trim().toLowerCase() ?? '';
    if (query.isEmpty) return items;
    return items
        .where((item) => item.name.toLowerCase().contains(query))
        .toList(growable: false);
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
    final toolbar = _toolbarActions;
    if (toolbar != null) {
      toolbar.searchQuery.removeListener(_onSearchQueryChanged);
      // Only clear what is still ours: a newer dashboard instance may have
      // registered already (Home is rebuilt when a vault replaces its tab).
      if (toolbar.addVault.value == showAddOptionsSheet) {
        toolbar.addVault.value = null;
      }
    }
    _dashboardAppBarAnimController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _liveInstances.remove(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    VeLog.d(_kLogTag, 'didChangeAppLifecycleState: $state');
    if (state == AppLifecycleState.resumed) {
      // The vault list is shared by every Vaults tab, so one of them
      // refreshing it is enough. Each tab still re-checks its own storage
      // permission flow below.
      if (_liveInstances.firstOrNull == this) {
        ref.read(vaultDashboardControllerProvider.notifier).handleRefresh();
      }
      unawaited(_handleAppResume());
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
      localStorageNotifier: widget.localStorageNotifier,
      onOpenLocalStorage: () =>
          unawaited(_openLocalStorage(currentVolId: currentVolId)),
      onOpenExternalStorage: (externalContainer) => unawaited(
        _openLocalStorage(
          currentVolId: externalContainer.volId,
          external: externalContainer,
        ),
      ),
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
      onOpenCategory: (category) {
        if (workspaceActions != null) {
          final tabId = workspaceActions.openCategoryTab(
            category,
            primaryLocalContainer: _localStorageContainer,
            includeVaults: true,
          );
          if (tabId == null && mounted) {
            showAppSnackBar(
              context,
              message: context.l10n.browserTabLimitReached(kMaxBrowserTabs),
              tone: AppBannerTone.warning,
            );
          }
          return;
        }
      },
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

  Future<void> _openLocalStorage({
    int? currentVolId,
    MountedContainer? external,
  }) async {
    if (currentVolId == kDecoyLocalVolId) return;

    final lifecycle = ref.read(vaultLifecycleApiProvider);
    final hasAccess = await lifecycle.hasAllFilesAccess();
    if (!mounted) return;

    if (hasAccess) {
      await _navigateToLocalStorage(currentVolId, target: external);
      return;
    }

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
      _pendingLocalStorageOriginVolId = external?.volId ?? currentVolId;
      _pendingLocalStorageOriginContainer = external;
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

    await _navigateToLocalStorage(currentVolId, target: external);
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
    final originContainer = _pendingLocalStorageOriginContainer;
    _pendingLocalStoragePermissionCheck = false;
    _pendingLocalStorageOriginVolId = null;
    _pendingLocalStorageOriginContainer = null;

    if (granted) {
      await _navigateToLocalStorage(originVolId, target: originContainer);
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

  Future<void> _navigateToLocalStorage(
    int? currentVolId, {
    MountedContainer? target,
  }) async {
    var container = target ?? _localStorageContainer;
    if (container == null) {
      // Shouldn't normally happen -- _checkStorageAccess populates this
      // before the card is even shown -- but fall back to resolving it
      // fresh rather than doing nothing if the cache is somehow empty.
      final root = await const DecoyLocalRepository().primaryRoot();
      if (!mounted) return;
      container = buildLocalStorageContainer(
        rootPath: root.path,
        displayName: localStorageDisplayName(context.l10n.localStorageCardTitle),
      );
      setState(() => _localStorageContainer = container);
      widget.localStorageNotifier?.value = container;
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

  Future<void> _showUnlockSheet({
    String? uri,
    String? name,
    List<String>? droppedPaths,
  }) async {
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
    // Read the live setting. `state.appSettings` is a snapshot that is only
    // refreshed by loadAll(), so right after the toggle was changed it still
    // held the old value for exactly one unlock attempt.
    final autoOpen = _container
        .read(appSettingsControllerProvider)
        .settings
        .autoOpenOnUnlock;

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
        adaptivePageRoute(
          context,
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
              droppedPaths: droppedPaths,
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

  /// Desktop: container files or a vault folder dragged in from the OS file
  /// manager and dropped on the dashboard. One that is already on the
  /// dashboard behaves like tapping its card (opened if it is unlocked, else
  /// the unlock sheet with its saved settings); anything else opens the
  /// add-a-vault sheet with the drop already selected.
  Future<void> _handleExternalVaultDrop(List<String> paths) async {
    if (!mounted || paths.isEmpty) return;
    final controller = ref.read(vaultDashboardControllerProvider.notifier);
    if (ref.read(vaultDashboardControllerProvider).actionInFlight) return;
    if (paths.length == 1) {
      final known = controller
          .getDisplayItems()
          .where((item) => p.equals(item.uri, paths.single))
          .firstOrNull;
      if (known != null) {
        openItem(known);
        return;
      }
    }
    await _showUnlockSheet(droppedPaths: paths);
  }

  Future<void> _showUsbUnlockSheet({ContainerRecord? existingRecord}) async {
    final dashboardController = _container.read(
      vaultDashboardControllerProvider.notifier,
    );
    final state = _container.read(vaultDashboardControllerProvider);
    if (state.actionInFlight) return;
    dashboardController.setActionInFlight(true);

    // Read the live setting. `state.appSettings` is a snapshot that is only
    // refreshed by loadAll(), so right after the toggle was changed it still
    // held the old value for exactly one unlock attempt.
    final autoOpen = _container
        .read(appSettingsControllerProvider)
        .settings
        .autoOpenOnUnlock;

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
        adaptivePageRoute(
          context,
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
    if (PlatformFeatures.usbHost) {
      try {
        final devices = await ref
            .read(vaultLifecycleApiProvider)
            .listUsbDevices();
        hasUsb = devices.isNotEmpty;
      } catch (e) {
        VeLog.w(_kLogTag, 'USB device enumeration failed', e);
      }
    }

    if (!mounted) return;
    ref
        .read(vaultDashboardControllerProvider.notifier)
        .setActionInFlight(false);
    HapticFeedback.lightImpact();

    final cs = Theme.of(context).colorScheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    showAdaptiveSheet(
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
    openContainerConfig(context, uri: uri, currentLabel: currentLabel);
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
    reorderEnabled: !_isSearchFiltering,
    filteredEmpty: _isSearchFiltering && displayItems.isEmpty,
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
    final displayItems = _applySearchFilter(
      ref.read(vaultDashboardControllerProvider.notifier).getDisplayItems(),
    );

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
    // Only whether this Vaults tab is the focused one matters here. Watching
    // the whole workspace state rebuilt the Dashboard on every unrelated tab
    // change.
    final ownTabId = widget.tabId;
    final dashboardIsActive = workspaceConfig == null
        ? true
        : ref.watch(
            activeBrowserTabProvider(workspaceConfig).select(
              (tab) =>
                  tab == null ||
                  (ownTabId == null ? tab.isDashboard : tab.tabId == ownTabId),
            ),
          );
    // In a hosted tab the shell owns a fixed app bar, so dashboard scrolling
    // never collapses or resizes it. Standalone mode retains its old behavior.
    final autoHideAppBar =
        !widget.embedded && toolbarSettings.config.autoHideAppBar;
    const dashboardAppBar = DashboardAppBar();

    final dashboardScrollContent = NotificationListener<ScrollNotification>(
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
    // Desktop: container files / vault folders dragged in from the OS file
    // manager. Off while a vault is being added or unlocked, and only on the
    // Home tab that is actually showing.
    final dashboardContent = ExternalFileDropZone(
      label: context.l10n.dropVaultOverlayLabel,
      enabled: !state.actionInFlight,
      isActive: () => mounted && dashboardIsActive,
      onDropped: (paths) => unawaited(_handleExternalVaultDrop(paths)),
      child: dashboardScrollContent,
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
            // Desktop adds and creates vaults from the toolbar instead.
            if (!PlatformFeatures.isDesktop) ...[
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
        // A stable slot rather than a new widget per build: see [ChromeBarSlot].
        widget.onBottomBarChanged?.call(
          _bottomBarSlot.publish(state.showUndoBar ? dashboardBottomBar : null),
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
