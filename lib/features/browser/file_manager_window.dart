import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_frame.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_title_bar.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/core/widgets/layout/docked_content_frame.dart';
import 'package:vaultexplorer/core/widgets/layout/resizable_split_pane.dart';
import 'package:vaultexplorer/core/windowing/secondary_windows.dart';
import 'package:vaultexplorer/core/windowing/view_focus.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/features/browser/browser_tab_paths.dart';
import 'package:vaultexplorer/features/browser/browser_tabs_host.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/file_manager_environment.dart';
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_new_tab_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_title_bar_tabs.dart';
import 'package:vaultexplorer/features/dashboard/drawer_unlock_flow.dart';
import 'package:vaultexplorer/features/dashboard/widgets/app_navigation_drawer.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

int _fileManagerWindowSerial = 0;

/// Opens [container] at [initialPath] in a new window of its own.
///
/// Each call opens another window, with its own tabs, its own location and
/// its own selection; the vaults, the clipboard, transfers and settings are
/// the app's, shared with every other window. Returns false when native
/// windows are not available, so the caller can open a tab instead. Menus go
/// through `FileManagerEnvironment.openWindow`, which ends up here.
bool openFileManagerWindow({
  required MountedContainer container,
  String? initialPath,
}) {
  return SecondaryWindows.instance.open(
    key: 'files:${++_fileManagerWindowSerial}',
    title: container.displayName,
    size: const Size(1100, 760),
    constraints: const BoxConstraints(minWidth: 560, minHeight: 400),
    builder: (_) =>
        FileManagerWindow(container: container, initialPath: initialPath),
  );
}

/// The content of a file manager window: the main window's layout (the title
/// row with the tabs in it, the sidebar beside the file browser) minus the
/// dashboard, with a tab workspace of its own.
///
/// What the sidebar opens, it opens in this window's tabs. Tools and Settings
/// open as pages over the file manager, and "Add a vault" is not offered: both
/// belong to the main window's dashboard.
///
/// Closing its last tab closes the window.
class FileManagerWindow extends ConsumerStatefulWidget {
  const FileManagerWindow({
    super.key,
    required this.container,
    this.initialPath,
  });

  final MountedContainer container;
  final String? initialPath;

  @override
  ConsumerState<FileManagerWindow> createState() => _FileManagerWindowState();
}

class _FileManagerWindowState extends ConsumerState<FileManagerWindow> {
  /// A workspace of its own: tabs are keyed by this, so nothing here is shared
  /// with the main window's tabs even though the providers are.
  late final BrowserTabsConfig _workspace = BrowserTabsConfig.create(
    initialContainer: widget.container,
    initialPath: widget.initialPath,
  );

  final FileManagerEnvironment _env = FileManagerEnvironment.instance;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// The browser keeps its tabs' state when the sidebar docks or undocks as
  /// the window is resized, because it is moved between the two layouts by
  /// this key.
  final GlobalKey _browserKey = GlobalKey(debugLabel: 'fileManagerBrowser');

  double _sidebarWidth = AppBreakpoints.dockedSidebarWidth;
  final ValueNotifier<double> _dualPaneSplitFraction = ValueNotifier(0.5);

  BrowserTabs get _actions =>
      ref.read(browserTabsProvider(_workspace).notifier);
  BrowserTabsState get _state => ref.read(browserTabsProvider(_workspace));
  bool get _tabsEnabled =>
      ref.read(appSettingsControllerProvider).settings.useBrowserTabs;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleShortcutKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleShortcutKey);
    _dualPaneSplitFraction.dispose();
    super.dispose();
  }

  MountedContainer? _resolveContainer(int volId) {
    final resolved = _env.resolveContainer(volId);
    if (resolved != null) return resolved;
    return volId == widget.container.volId ? widget.container : null;
  }

  /// Ctrl+W and Ctrl+Tab, as in the main window. They are global key
  /// handlers, so they only answer while this window holds the focus.
  bool _handleShortcutKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    if (!keyboardFocusIsInViewOf(context)) return false;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    if (keyboard.isControlPressed && !keyboard.isAltPressed) {
      if (key == LogicalKeyboardKey.keyW) {
        _closeActiveTab();
        return true;
      }
    }
    if (keyboard.isControlPressed && key == LogicalKeyboardKey.tab) {
      if (!_tabsEnabled) return false;
      _cycleTab(keyboard.isShiftPressed ? -1 : 1);
      return true;
    }
    return false;
  }

  void _closeActiveTab() {
    final state = _state;
    final activeTabId = state.activeTabId;
    if (!_tabsEnabled || state.tabs.length < 2 || activeTabId == null) {
      // The last tab goes with its window.
      SecondaryWindowScope.maybeOf(context)?.close();
      return;
    }
    _actions.closeTab(activeTabId);
  }

  void _cycleTab(int step) {
    final state = _state;
    if (state.tabs.length < 2 || state.activeIndex < 0) return;
    final count = state.tabs.length;
    _actions.activateIndex((state.activeIndex + step + count) % count);
  }

  void _showTabLimit() {
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: context.l10n.browserTabLimitReached(kMaxBrowserTabs),
      tone: AppBannerTone.warning,
    );
  }

  /// A sidebar tap on a storage or vault: shown in the tab in front, like the
  /// main window's sidebar does. The long-press "open in new tab" is
  /// [_openInNewTab].
  void _openContainer(MountedContainer container) {
    final active = _state.activeTab;
    if (active == null) {
      if (_actions.openTab(container) == null) _showTabLimit();
    } else if (active.volId != container.volId) {
      _actions.replaceActive(container);
    }
  }

  void _openInNewTab(MountedContainer container) {
    if (_actions.openTab(container) == null) _showTabLimit();
  }

  void _openCategory(FileCategory category) {
    final tabId = _actions.openCategoryTab(
      category,
      primaryLocalContainer: _env.primaryLocalContainer(),
      includeVaults: true,
    );
    if (tabId == null) _showTabLimit();
  }

  /// This device's storage, from the sidebar. Where it cannot be opened
  /// without asking for a permission first (the dashboard's flow, in the main
  /// window) there is nothing to open here.
  void _openLocalStorage() {
    final primary = _env.primaryLocalContainer();
    if (primary != null) _openContainer(primary);
  }

  void _unlockVault(VaultListItem item) {
    switch (item) {
      case MountedVaultItem(:final container):
        _openContainer(container);
      case LockedVaultItem(:final record):
        unawaited(
          showDrawerUnlock(
            context: context,
            ref: ref,
            record: record,
            isMounted: () => mounted,
            onOpen: _openContainer,
          ),
        );
    }
  }

  Future<void> _openNewTab() async {
    if (!_tabsEnabled) return;
    // Don't offer a picker whose every choice would fail.
    if (_state.atLimit) {
      _showTabLimit();
      return;
    }
    final choice = await BrowserNewTabSheet.show(
      context,
      currentContainer: _state.activeTab?.container,
      mountedVaults: _env.mountedContainers(),
      primaryLocalContainer: _env.primaryLocalContainer(),
      // There is no dashboard in this window.
      allowDashboard: false,
    );
    final container = choice?.container;
    if (!mounted || choice == null || container == null) return;
    final path = choice.path;
    final tabId = _actions.openTab(
      container,
      initialPath: path == null || path.isEmpty ? null : path,
    );
    if (tabId == null) _showTabLimit();
  }

  void _duplicateTab(BrowserTabState tab) {
    if (!_tabsEnabled || tab.isDashboard) return;
    if (tab.isCategory) {
      final tabId = _actions.openCategoryTab(
        tab.category!,
        primaryLocalContainer: tab.primaryLocalContainer,
        includeVaults: tab.includeVaults,
      );
      if (tabId == null) _showTabLimit();
      return;
    }
    final container = tab.container;
    if (container == null) return;
    final path = browserTabDuplicatePath(
      ref.read(fileBrowserNavigationProvider(tab.tabId)),
    );
    final tabId = _actions.openTab(
      container,
      initialPath: path.isEmpty ? null : path,
    );
    if (tabId == null) _showTabLimit();
  }

  /// The sidebar, the same menu as the main window's. [currentVolId] is the
  /// storage of the tab in front, which the menu highlights.
  Widget _buildSidebar({int? currentVolId, bool docked = false}) {
    return AppNavigationDrawer(
      docked: docked,
      currentVolId: currentVolId,
      primaryLocalContainer: _env.primaryLocalContainer(),
      onOpenInNewTab: _tabsEnabled ? _openInNewTab : null,
      keepBrowserTabsOnNavigate: true,
      onSelectContainer: _openContainer,
      onOpenLocalStorage: _openLocalStorage,
      onUnlockVault: _unlockVault,
      onOpenCategory: _openCategory,
    );
  }

  /// Keeps the title bar showing where this window is, for the taskbar and
  /// the window switcher.
  void _syncTitle(WidgetRef ref, SecondaryWindowEntry? entry) {
    if (entry == null) return;
    final active = ref.watch(
      browserTabsProvider(_workspace).select((state) => state.activeTab),
    );
    final container = active?.container;
    if (active == null || container == null) return;
    final leaf = ref.watch(
      fileBrowserNavigationProvider(
        active.tabId,
      ).select((nav) => nav.pathStack.isEmpty ? '' : nav.pathStack.last.label),
    );
    final name = container.displayName;
    final title = leaf.isEmpty || leaf == name ? name : '$name – $leaf';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) entry.setTitle(title);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entry = SecondaryWindowScope.maybeOf(context);
    final docked = AppBreakpoints.useDockedSidebarFor(
      MediaQuery.sizeOf(context),
    );
    // Windows without a native title bar draw the main window's caption row,
    // with the tabs in it, across the whole width (sidebar included).
    final customCaption =
        PlatformFeatures.isWindows && !NativeWindowChrome.of(context);
    final tabsEnabled = ref.watch(
      appSettingsControllerProvider.select(
        (state) => state.settings.useBrowserTabs,
      ),
    );
    // The sidebar highlights the storage of the tab in front.
    final activeVolId = ref.watch(
      browserTabsProvider(_workspace).select((state) {
        final tab = state.activeTab;
        return tab == null || tab.isDashboard ? null : tab.volId;
      }),
    );

    Widget body = KeyedSubtree(
      key: _browserKey,
      child: SkinAreaScope(
        area: SkinArea.files,
        child: BrowserTabsShell(
          key: ValueKey<int>(_workspace.sessionId),
          restoredWorkspace: _workspace,
          resolveContainer: _resolveContainer,
          mountedContainers: _env.mountedContainers,
          primaryLocalContainer: _env.primaryLocalContainer,
          // A docked sidebar replaces the drawer, so the browser must not
          // build (or offer to open) one of its own.
          drawerBuilder: docked
              ? null
              : (workspace, volId) => _buildSidebar(currentVolId: volId),
          closeRouteWhenEmpty: false,
          // The caption row below is where the tabs go, so that they line up
          // with the sidebar.
          externallyHostedTabStrip: customCaption,
          onDualPaneSplitFractionChanged: customCaption
              ? (fraction) => _dualPaneSplitFraction.value = fraction
              : null,
          onEmpty: entry?.close,
        ),
      ),
    );

    if (docked) {
      final browser = body;
      body = LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = (constraints.maxWidth - 8)
              .clamp(1.0, double.infinity)
              .toDouble();
          return ResizableSplitPane(
            axis: Axis.horizontal,
            initialFraction: _sidebarWidth / availableWidth,
            minFirstExtent: 220,
            minSecondExtent: 480,
            maxFirstExtent: 460,
            dividerExtent: 8,
            onFirstExtentChanged: (extent) {
              if (!mounted || (_sidebarWidth - extent).abs() < 0.5) return;
              setState(() => _sidebarWidth = extent);
            },
            first: _buildSidebar(docked: true, currentVolId: activeVolId),
            second: DockedContentFrame(
              consumedWidth: _sidebarWidth + 8,
              child: browser,
            ),
          );
        },
      );
    }

    final Widget? titleBar = customCaption
        ? DesktopWindowTitleBar(
            height: 32,
            tabs: tabsEnabled
                ? BrowserTitleBarTabs(
                    workspace: _workspace,
                    docked: docked,
                    splitFraction: _dualPaneSplitFraction,
                    onNewTab: _openNewTab,
                    onDuplicate: _duplicateTab,
                  )
                : const SizedBox.shrink(),
            leadingWidth: docked ? _sidebarWidth + 8 : 48.0,
            leadingDraggable: docked,
            leading: docked
                ? SizedBox(width: _sidebarWidth + 8)
                : SizedBox(
                    width: 48,
                    child: Builder(
                      builder: (buttonContext) => IconButton(
                        icon: const Icon(Icons.menu_rounded, size: 18),
                        tooltip: buttonContext.l10n.storageLocationsTitle,
                        onPressed: () => Scaffold.of(buttonContext).openDrawer(),
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
          )
        : null;

    final Widget layout = Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      drawer: docked ? null : _buildSidebar(currentVolId: activeVolId),
      body: titleBar == null
          ? body
          : Column(
              children: [
                titleBar,
                Expanded(child: body),
              ],
            ),
    );

    return Consumer(
      // The layout is passed as the child so that a title change only reruns
      // the builder below, not the whole file browser.
      child: layout,
      builder: (context, ref, child) {
        _syncTitle(ref, entry);
        return child!;
      },
    );
  }
}
