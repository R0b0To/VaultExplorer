import 'dart:async';
import 'dart:math' as math;
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
import 'package:vaultexplorer/core/widgets/activity/app_bar_authenticator_button.dart';
import 'package:vaultexplorer/core/widgets/activity/clipboard_fab.dart';
import 'package:vaultexplorer/core/widgets/activity/floating_activity_stack.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/browser/browser_tabs_host.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_new_tab_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_tab_strip.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/app_navigation_drawer.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/create_container_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/dashboard_empty_state.dart';
import 'package:vaultexplorer/features/dashboard/widgets/usb_create_container_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_card_row.dart';
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
  final BrowserTabsController? browserTabs;
  final ValueListenable<double>? tabPagePosition;
  final int? tabPageIndex;
  final ValueChanged<MountedContainer>? onOpenBrowser;
  final VoidCallback? onNewBrowserTab;
  final ValueChanged<BrowserTab>? onDuplicateBrowserTab;
  final ValueChanged<BrowserTab>? onActivateBrowserTab;
  final ValueChanged<bool>? onVerticalScrollActivity;

  const VaultDashboard({
    super.key,
    this.mountedNotifier,
    this.onNavigateTab,
    this.browserTabs,
    this.tabPagePosition,
    this.tabPageIndex,
    this.onOpenBrowser,
    this.onNewBrowserTab,
    this.onDuplicateBrowserTab,
    this.onActivateBrowserTab,
    this.onVerticalScrollActivity,
  });

  @override
  ConsumerState<VaultDashboard> createState() => VaultDashboardState();
}

class VaultDashboardState extends ConsumerState<VaultDashboard>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  SessionLockController get _lockController =>
      ref.read(sessionLockControllerProvider);
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _dashboardSwipeBodyKey = GlobalKey();
  bool _isFabVisible = true;
  bool _verticalScrollActive = false;
  double _drawerDragDistance = 0.0;
  bool _isTouchFromEdge = false;
  int _dashboardPointerCount = 0;
  int? _dashboardSwipePointer;
  Offset? _dashboardSwipeStart;
  int? _dashboardSwipeStartTabIndex;
  bool _dashboardSwipeRejected = false;
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
  // Live tab list of the file manager route currently on top (null when none).
  BrowserTabsController? _browserTabs;
  late final AnimationController _dashboardAppBarAnimController =
      AnimationController(vsync: this, duration: AppMotion.short2, value: 1.0)
        ..addListener(_onDashboardAppBarAnimationChanged);
  int? _pendingLocalStorageOriginVolId;
  int _localStoragePermissionRequestId = 0;
  void showAddOptionsSheet() => _showAddOptionsSheet();

  void reloadDashboard() {
    ref.read(vaultDashboardControllerProvider.notifier).loadAll();
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
    _attachBrowserTabs(widget.browserTabs);
    // Cache the ProviderContainer so asynchronous callbacks (like auto-lock
    // and container unmounting) remain safe even after this widget is unmounted.
    _container = ProviderScope.containerOf(context, listen: false);
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
    if (oldWidget.browserTabs != widget.browserTabs) {
      _attachBrowserTabs(widget.browserTabs);
    }
  }

  void _attachBrowserTabs(BrowserTabsController? tabs) {
    final attachedTabs = tabs ?? widget.browserTabs;
    if (identical(attachedTabs, _browserTabs)) return;
    _browserTabs?.removeListener(_onBrowserTabsChanged);
    _browserTabs?.appBarVisibility.removeListener(
      _onDashboardAppBarVisibilityChanged,
    );
    _browserTabs = attachedTabs;
    attachedTabs?.addListener(_onBrowserTabsChanged);
    attachedTabs?.appBarVisibility.addListener(
      _onDashboardAppBarVisibilityChanged,
    );
    _syncDashboardAppBarFromTabs();
  }

  void _onBrowserTabsChanged() {
    // Stop an in-flight Dashboard animation when the active location changes;
    // the newly active screen's visibility becomes the shared value.
    _dashboardAppBarAnimController.stop();
    if (_browserTabs?.activeTab?.isDashboard != true) {
      _setVerticalScrollActivity(false);
    }
    _syncDashboardAppBarFromTabs();
  }

  void _onDashboardAppBarVisibilityChanged() {
    _syncDashboardAppBarFromTabs();
  }

  void _syncDashboardAppBarFromTabs() {
    final tabs = _browserTabs;
    if (tabs == null) return;
    final visibility = tabs.appBarVisibility.value;
    if ((_dashboardAppBarAnimController.value - visibility).abs() > 0.001) {
      _dashboardAppBarAnimController.value = visibility;
    }
  }

  void _setVerticalScrollActivity(bool scrolling) {
    if (_verticalScrollActive == scrolling) return;
    _verticalScrollActive = scrolling;
    widget.onVerticalScrollActivity?.call(scrolling);
  }

  Widget _pinDashboardChrome(Widget child) {
    final pagePosition = widget.tabPagePosition;
    final pageIndex = widget.tabPageIndex;
    final tabs = widget.browserTabs ?? _browserTabs;
    if (pagePosition == null ||
        pageIndex == null ||
        tabs?.activeTab?.isDashboard == false) {
      return child;
    }
    return LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder<double>(
        valueListenable: pagePosition,
        child: child,
        builder: (context, position, child) {
          final direction = Directionality.of(context) == TextDirection.rtl
              ? -1.0
              : 1.0;
          return Transform.translate(
            offset: Offset(
              (position - pageIndex) * constraints.maxWidth * direction,
              0,
            ),
            child: child,
          );
        },
      ),
    );
  }

  void _onDashboardAppBarAnimationChanged() {
    final tabs = _browserTabs;
    if (tabs != null && tabs.activeTab?.isDashboard != true) return;
    tabs?.setAppBarVisibility(_dashboardAppBarAnimController.value);
  }

  bool _handleDashboardScrollNotification(
    ScrollNotification notification, {
    required bool autoHideAppBar,
    required BrowserTabsController? tabs,
  }) {
    if (notification.metrics.axis != Axis.vertical ||
        (tabs != null && tabs.activeTab?.isDashboard != true)) {
      return false;
    }

    void setProgress(double value) {
      final progress = value.clamp(0.0, 1.0).toDouble();
      if (_dashboardAppBarAnimController.value != progress) {
        _dashboardAppBarAnimController.value = progress;
      }
      tabs?.setAppBarVisibility(progress);
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

  void _handleDashboardPointerDown(PointerDownEvent event) {
    _lockController.scheduleAutoLock();
    _container
        .read(vaultDashboardControllerProvider.notifier)
        .resetAllAutoCloseTimers();
    _dashboardPointerCount++;
    if (_dashboardPointerCount != 1) {
      _dashboardSwipeRejected = true;
      return;
    }

    final edgeInset = math.max(
      72.0,
      MediaQuery.systemGestureInsetsOf(context).left,
    );
    _isTouchFromEdge = event.position.dx <= edgeInset;
    _drawerDragDistance = 0.0;
    _dashboardSwipePointer = event.pointer;
    _dashboardSwipeStart = event.position;
    _dashboardSwipeStartTabIndex = _browserTabs?.activeIndex;
    final bodyRenderObject = _dashboardSwipeBodyKey.currentContext
        ?.findRenderObject();
    final bodyBounds = bodyRenderObject is RenderBox
        ? (bodyRenderObject.localToGlobal(Offset.zero) & bodyRenderObject.size)
        : null;
    _dashboardSwipeRejected =
        _isTouchFromEdge || !(bodyBounds?.contains(event.position) ?? false);
  }

  void _handleDashboardPointerMove(PointerMoveEvent event) {
    final start = _dashboardSwipeStart;
    if (event.pointer != _dashboardSwipePointer ||
        start == null ||
        _dashboardSwipeRejected) {
      return;
    }
    if (_dashboardPointerCount != 1) {
      _dashboardSwipeRejected = true;
      return;
    }
    final offset = event.position - start;
    if (offset.distance < 14.0) return;
    if (offset.dx.abs() <= offset.dy.abs()) {
      _dashboardSwipeRejected = true;
      return;
    }
    _drawerDragDistance = offset.dx;
  }

  void _handleDashboardPointerUp(PointerEvent event, {bool cancelled = false}) {
    if (event.pointer == _dashboardSwipePointer) {
      if (!cancelled &&
          !_dashboardSwipeRejected &&
          _dashboardPointerCount == 1) {
        _finishHorizontalSwipe(
          tabsEnabled: ref
              .read(appSettingsControllerProvider)
              .settings
              .useBrowserTabs,
        );
      } else {
        _drawerDragDistance = 0.0;
      }
      _dashboardSwipePointer = null;
      _dashboardSwipeStart = null;
      _dashboardSwipeStartTabIndex = null;
      _dashboardSwipeRejected = false;
    }
    _dashboardPointerCount = math.max(0, _dashboardPointerCount - 1);
  }

  void _finishHorizontalSwipe({required bool tabsEnabled}) {
    final distance = _drawerDragDistance;
    _drawerDragDistance = 0.0;
    if (_isTouchFromEdge || distance.abs() < 60.0) return;

    final tabs = _browserTabs;
    if (tabsEnabled && tabs != null && tabs.length > 0) {
      final startIndex = _dashboardSwipeStartTabIndex ?? tabs.activeIndex;
      if (distance < 0.0 && startIndex == tabs.length - 1) {
        (widget.onNewBrowserTab ?? _openDashboardNewTab)();
        return;
      }
      if (distance > 0.0 && startIndex == 0) {
        _scaffoldKey.currentState?.openDrawer();
        return;
      }
      // The host PageView handles tab changes so a drag can be released or
      // cancelled while its neighboring page tracks the gesture.
      return;
    }

    if (distance > 0.0) _scaffoldKey.currentState?.openDrawer();
  }

  @override
  void dispose() {
    _browserTabs?.removeListener(_onBrowserTabsChanged);
    _browserTabs?.appBarVisibility.removeListener(
      _onDashboardAppBarVisibilityChanged,
    );
    _dashboardAppBarAnimController
      ..removeListener(_onDashboardAppBarAnimationChanged)
      ..dispose();
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

  Future<void> _openExternalStorage(ExternalStorageLocation loc) async {
    final container = buildExternalStorageContainer(
      rootPath: loc.resolvedUri,
      displayName: loc.displayName,
      volId: loc.volId,
    );
    await _openBrowser(container);
  }

  Future<void> _openDashboardNewTab() async {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    final tabs = widget.browserTabs ?? _browserTabs;
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
      mountedVaults: ref.read(vaultDashboardControllerProvider).mounted,
      primaryLocalContainer: _localStorageContainer,
    );
    if (!mounted || choice == null) return;
    if (choice.container == null) {
      tabs.openDashboardTab();
      return;
    }
    final key = tabs.openTab(
      choice.container!,
      initialPath: (choice.path == null || choice.path!.isEmpty)
          ? null
          : choice.path,
    );
    if (key == null) {
      showAppSnackBar(
        context,
        message: context.l10n.browserTabLimitReached(kMaxBrowserTabs),
        tone: AppBannerTone.warning,
      );
      return;
    }
  }

  void _duplicateDashboardTab(BrowserTab tab) {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    final tabs = widget.browserTabs ?? _browserTabs;
    final container = tab.container;
    if (tabs == null) return;
    if (tab.isDashboard) {
      tabs.openDashboardTab();
      return;
    }
    if (container == null) return;
    final nav = ref.read(fileBrowserNavigationProvider(tab.key));
    final path = browserTabDuplicatePath(nav);
    final key = tabs.openTab(
      container,
      initialPath: path.isEmpty ? null : path,
    );
    if (key == null) {
      showAppSnackBar(
        context,
        message: context.l10n.browserTabLimitReached(kMaxBrowserTabs),
        tone: AppBannerTone.warning,
      );
      return;
    }
  }

  void _promptRenameExternalStorage(ExternalStorageLocation loc) {
    final ctrl = TextEditingController(text: loc.displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.renameStorageLocationTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: context.l10n.displayNameTitle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final text = ctrl.text.trim();
              if (text.isNotEmpty) {
                ref
                    .read(externalStorageLocationsProvider.notifier)
                    .renameLocation(loc.id, text);
              }
              Navigator.pop(ctx);
            },
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );
  }

  void _confirmRemoveExternalStorage(ExternalStorageLocation loc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.removeStorageLocationTitle),
        content: Text(
          context.l10n.removeStorageLocationConfirm(loc.displayName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              ref
                  .read(externalStorageLocationsProvider.notifier)
                  .removeLocation(loc.id);
              Navigator.pop(ctx);
            },
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
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
  void _openInNewTab(BrowserTabsController tabs, MountedContainer container) {
    if (!ref.read(appSettingsControllerProvider).settings.useBrowserTabs) {
      return;
    }
    if (tabs.openTab(container) == null && mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.browserTabLimitReached(kMaxBrowserTabs),
        tone: AppBannerTone.warning,
      );
    }
  }

  Widget _buildDrawer({int? currentVolId, BrowserTabsController? tabs}) {
    return AppNavigationDrawer(
      currentVolId: currentVolId,
      onOpenInNewTab:
          tabs == null ||
              !ref.read(appSettingsControllerProvider).settings.useBrowserTabs
          ? null
          : (container) => _openInNewTab(tabs, container),
      primaryLocalContainer: _localStorageContainer,
      onOpenLocalStorage: () =>
          unawaited(_openLocalStorage(currentVolId: currentVolId)),
      selectedTabIndex: 0,
      onSelectTab: widget.onNavigateTab,
      keepBrowserTabsOnNavigate: widget.onOpenBrowser != null && tabs != null,
      onSelectContainer: (newContainer) {
        // Inside the tabbed file manager the drawer switches the *active tab*
        // instead of replacing the whole route (which would drop every tab).
        final tabs = _browserTabs;
        if (tabs != null) {
          if (widget.onOpenBrowser != null) {
            widget.onOpenBrowser!(newContainer);
          } else {
            tabs.replaceActive(newContainer);
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
      drawerBuilder: (tabs, volId) =>
          _buildDrawer(currentVolId: volId, tabs: tabs),
      // Unknown / on-device volIds are ignored by the controller, which
      // matches the old local-storage route's no-op callback.
      userActivityFor: (volId) =>
          () => ref
              .read(vaultDashboardControllerProvider.notifier)
              .onUserActivityForContainer(volId),
      onTabsController: _attachBrowserTabs,
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
    final tabs = _browserTabs;
    if (tabs != null) {
      tabs.replaceActive(container);
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
    final state = ref.read(vaultDashboardControllerProvider);
    if (uri != null && state.mounted.any((c) => c.uri == uri)) {
      showAppSnackBar(context, message: context.l10n.containerAlreadyMounted);
      return;
    }
    if (state.actionInFlight) return;
    ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(true);

    String? rememberedPassword;
    if (uri != null) {
      final record = state.records[uri];
      if (record?.unlockMethod == ContainerUnlockMethod.rememberPassword) {
        rememberedPassword = await ref
            .read(containerRepositoryProvider)
            .getPassword(uri);
      }
    }
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
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(
            area: SkinArea.dashboard,
            child: UnlockSheet(
              onMounted: (container, {record}) {
                ref
                    .read(vaultDashboardControllerProvider.notifier)
                    .onContainerMounted(container, record: record);
                newlyMountedContainer = container;
                if (autoOpen && widget.onOpenBrowser != null) {
                  widget.onOpenBrowser!(container);
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
      if (mounted) {
        await ref.read(vaultDashboardControllerProvider.notifier).loadAll();
        if (newlyMountedContainer != null) {
          ref
              .read(vaultDashboardControllerProvider.notifier)
              .refreshContainerSpace(newlyMountedContainer!.volId);
        }
      }
    } finally {
      if (mounted)
        ref
            .read(vaultDashboardControllerProvider.notifier)
            .setActionInFlight(false);
    }
  }

  Future<void> _showUsbUnlockSheet({ContainerRecord? existingRecord}) async {
    final state = ref.read(vaultDashboardControllerProvider);
    if (state.actionInFlight) return;
    ref.read(vaultDashboardControllerProvider.notifier).setActionInFlight(true);

    String? rememberedPassword;
    if (existingRecord != null &&
        existingRecord.unlockMethod == ContainerUnlockMethod.rememberPassword) {
      rememberedPassword = await ref
          .read(containerRepositoryProvider)
          .getPassword(existingRecord.uri);
    }
    final autoOpen = state.appSettings.autoOpenOnUnlock;

    MountedContainer? newlyMountedContainer;
    try {
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SkinAreaScope(
            area: SkinArea.dashboard,
            child: UsbUnlockSheet(
              onMounted: (container, {record}) {
                ref
                    .read(vaultDashboardControllerProvider.notifier)
                    .onContainerMounted(container, record: record);
                newlyMountedContainer = container;
                if (autoOpen && widget.onOpenBrowser != null) {
                  widget.onOpenBrowser!(container);
                }
              },
              onReconnected: (container, migratedRecord, oldUri) {
                ref
                    .read(vaultDashboardControllerProvider.notifier)
                    .onUsbContainerReconnected(
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
      if (mounted) {
        await ref.read(vaultDashboardControllerProvider.notifier).loadAll();
        if (newlyMountedContainer != null) {
          ref
              .read(vaultDashboardControllerProvider.notifier)
              .refreshContainerSpace(newlyMountedContainer!.volId);
        }
      }
    } finally {
      if (mounted)
        ref
            .read(vaultDashboardControllerProvider.notifier)
            .setActionInFlight(false);
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
      openBrowser(container);
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
    AppSettings appSettings, {
    required bool settingsLoaded,
  }) {
    if (displayItems.isEmpty && !state.isLoading) {
      return EmptyState(onAdd: _showAddOptionsSheet);
    }

    final vaultList = ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      itemCount: displayItems.length,
      onReorderItem: (oldIndex, newIndex) => ref
          .read(vaultDashboardControllerProvider.notifier)
          .handleReorder(oldIndex, newIndex),
      proxyDecorator: (child, index, animation) {
        return AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final animValue = Curves.easeInOut.transform(animation.value);
            final elevation = Tween<double>(
              begin: 0,
              end: 8,
            ).transform(animValue);
            return Material(
              elevation: elevation,
              color: Colors.transparent,
              shadowColor: Theme.of(
                context,
              ).colorScheme.shadow.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: child,
            );
          },
          child: child,
        );
      },
      itemBuilder: (context, i) {
        final item = displayItems[i];
        return VaultCardRow(
          key: ValueKey(item.uri),
          index: i,
          item: item,
          record: state.records[item.uri],
          appSettings: appSettings,
          onOpen: () => openItem(item),
          onEdit: () => _requestEdit(item),
          onDelete: () => _requestDelete(item),
          onLocked: (volId) => ref
              .read(vaultDashboardControllerProvider.notifier)
              .onContainerLocked(volId),
          isRemoving: state.animatingOutUris.contains(item.uri),
          isInserting: state.animatingInUris.contains(item.uri),
          dragEnabled:
              appSettings.containerSortMode == ContainerSortMode.manual,
        );
      },
    );

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: vaultList,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(vaultDashboardControllerProvider);
    final appSettingsState = ref.watch(appSettingsControllerProvider);
    final toolbarSettings = ref.watch(fileManagerToolbarSettingsProvider(null));
    final appSettings = appSettingsState.settings;
    final displayItems = ref
        .read(vaultDashboardControllerProvider.notifier)
        .getDisplayItems();

    if (widget.mountedNotifier != null) {
      widget.mountedNotifier!.value = List.unmodifiable(state.mounted);
    }

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final double undoBarHeight = 64.0 + (bottomInset > 0 ? bottomInset : 16.0);
    final browserTabs = widget.browserTabs ?? _browserTabs;
    final dashboardIsActive = browserTabs?.activeTab?.isDashboard ?? true;
    final autoHideAppBar = toolbarSettings.config.autoHideAppBar;
    final dashboardTabStrip =
        browserTabs == null ||
            browserTabs.isEmpty ||
            !appSettings.useBrowserTabs
        ? null
        : BrowserTabStrip(
            controller: browserTabs,
            storageKey: 'browser-tab-strip-scroll-position',
            onNewTab: widget.onNewBrowserTab ?? _openDashboardNewTab,
            onDuplicate: widget.onDuplicateBrowserTab ?? _duplicateDashboardTab,
            onActivateTab: widget.onActivateBrowserTab,
          );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handleDashboardPointerDown,
      onPointerMove: _handleDashboardPointerMove,
      onPointerUp: _handleDashboardPointerUp,
      onPointerCancel: (event) =>
          _handleDashboardPointerUp(event, cancelled: true),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: widget.tabPagePosition == null
            ? null
            : Colors.transparent,
        drawerEnableOpenDragGesture: false,
        drawer: _buildDrawer(tabs: browserTabs),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _pinDashboardChrome(
                ClipRect(
                  child: AnimatedBuilder(
                    animation: _dashboardAppBarAnimController,
                    builder: (context, _) {
                      final factor = !autoHideAppBar
                          ? 1.0
                          : _dashboardAppBarAnimController.value;
                      if (factor == 0.0) return const SizedBox.shrink();
                      if (!dashboardIsActive) {
                        return SizedBox(height: kToolbarHeight * factor);
                      }
                      return Align(
                        alignment: Alignment.bottomCenter,
                        heightFactor: factor,
                        child: SizedBox(
                          height: kToolbarHeight,
                          child: MediaQuery.removePadding(
                            context: context,
                            removeTop: true,
                            child: AppBar(
                              primary: false,
                              leading: Builder(
                                builder: (ctx) => IconButton(
                                  icon: Icon(
                                    Icons.menu_rounded,
                                    color: Theme.of(
                                      ctx,
                                    ).appBarTheme.foregroundColor,
                                  ),
                                  tooltip: context.l10n.storageLocationsTitle,
                                  onPressed: () =>
                                      Scaffold.of(ctx).openDrawer(),
                                ),
                              ),
                              title: Text(
                                context.l10n.appNameVaultExplorer,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              actions: const [
                                AppBarAuthenticatorButton(),
                                AppBarTransferButton(),
                                SizedBox(width: 4),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              if (dashboardTabStrip != null)
                dashboardIsActive
                    ? SizedBox(
                        height: kBrowserTabStripHeight,
                        child: _pinDashboardChrome(dashboardTabStrip),
                      )
                    : const SizedBox(height: kBrowserTabStripHeight),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.axis == Axis.vertical) {
                      if (notification is ScrollStartNotification) {
                        _setVerticalScrollActivity(true);
                      } else if (notification is ScrollEndNotification) {
                        _setVerticalScrollActivity(false);
                      }
                    }
                    _handleDashboardScrollNotification(
                      notification,
                      autoHideAppBar: autoHideAppBar,
                      tabs: browserTabs,
                    );
                    if (notification is UserScrollNotification &&
                        notification.metrics.axis == Axis.vertical) {
                      final direction = notification.direction;
                      if (direction == ScrollDirection.forward) {
                        if (!_isFabVisible)
                          setState(() => _isFabVisible = true);
                      } else if (direction == ScrollDirection.reverse) {
                        if (_isFabVisible)
                          setState(() => _isFabVisible = false);
                      }
                    }
                    return false;
                  },
                  child: KeyedSubtree(
                    key: _dashboardSwipeBodyKey,
                    child: Column(
                      children: [
                        // Auto-sync progress / attention; takes no space when idle.
                        _pinDashboardChrome(
                          Visibility(
                            visible: dashboardIsActive,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: const SyncStatusBanner(),
                          ),
                        ),
                        Expanded(
                          child: _buildBody(
                            displayItems,
                            state,
                            appSettings,
                            settingsLoaded: !appSettingsState.loading,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: AnimatedSlide(
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
        ),
        bottomNavigationBar: AnimatedContainer(
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
        ),
      ),
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
