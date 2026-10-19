import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_new_tab_sheet.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_tab_strip.dart';

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
  Widget Function(BrowserTabsController tabs, int currentVolId)? drawerBuilder,
  VoidCallback? Function(int volId)? userActivityFor,
  ValueChanged<BrowserTabsController?>? onTabsController,
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
      ),
    ),
  );
}

/// Hosts one [FileBrowserScreen] per open tab. Inactive tabs stay mounted in
/// an [IndexedStack] so their scroll position, path stack, selection, search
/// and archive state survive switching; each tab's Riverpod state is scoped
/// by its tab key (see [BrowserTab.key]) instead of its volume, so two tabs
/// on the same vault are independent.
class BrowserTabsHost extends ConsumerStatefulWidget {
  final MountedContainer initialContainer;
  final MountedContainer? Function(int volId) resolveContainer;
  final List<MountedContainer> Function() mountedContainers;
  final MountedContainer? Function() primaryLocalContainer;

  /// Builds the navigation drawer for a tab on [currentVolId]. The drawer's
  /// "switch vault" actions should call `tabs.replaceActive` while hosted.
  final Widget Function(BrowserTabsController tabs, int currentVolId)?
  drawerBuilder;

  /// Returns the auto-lock activity callback for the tab on [volId]. Only
  /// the active tab's callback is wired, so a vault used only through a
  /// background tab keeps its normal idle timer.
  final VoidCallback? Function(int volId)? userActivityFor;

  /// Called with the live controller once the host is mounted, and with null
  /// when it is disposed, so the owner can route its own drawer actions
  /// (e.g. "open local storage") into the tab list.
  final ValueChanged<BrowserTabsController?>? onTabsController;

  const BrowserTabsHost({
    super.key,
    required this.initialContainer,
    required this.resolveContainer,
    required this.mountedContainers,
    required this.primaryLocalContainer,
    this.drawerBuilder,
    this.userActivityFor,
    this.onTabsController,
  });

  @override
  ConsumerState<BrowserTabsHost> createState() => _BrowserTabsHostState();
}

class _BrowserTabsHostState extends ConsumerState<BrowserTabsHost> {
  late final BrowserTabsController _tabs;
  late final VaultEngineEvents _vaultEvents;
  bool _popScheduled = false;

  @override
  void initState() {
    super.initState();
    _tabs = BrowserTabsController(widget.initialContainer);
    _tabs.addListener(_onTabsChanged);
    _vaultEvents = ref.read(vaultEngineEventsProvider);
    _vaultEvents.addContainerLockedListener(_onVolumeGone);
    _vaultEvents.addUsbContainerDetachedListener(_onVolumeGone);
    widget.onTabsController?.call(_tabs);
  }

  @override
  void dispose() {
    widget.onTabsController?.call(null);
    _vaultEvents.removeContainerLockedListener(_onVolumeGone);
    _vaultEvents.removeUsbContainerDetachedListener(_onVolumeGone);
    _tabs.removeListener(_onTabsChanged);
    _tabs.dispose();
    super.dispose();
  }

  /// A vault was locked or a USB container detached: every tab on it goes
  /// away; the route only closes once no tab is left.
  void _onVolumeGone(int volId) {
    if (!mounted) return;
    _tabs.closeByVolId(volId);
  }

  void _onTabsChanged() {
    if (!_tabs.isEmpty || _popScheduled) return;
    _popScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
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

  void _showLimitReached() {
    showAppSnackBar(
      context,
      message: context.l10n.browserTabLimitReached(kMaxBrowserTabs),
      tone: AppBannerTone.warning,
    );
  }

  Future<void> _openNewTabSheet() async {
    if (_tabs.atLimit) {
      _showLimitReached();
      return;
    }
    final active = _tabs.activeTab;
    if (active == null) return;
    final nav = ref.read(fileBrowserNavigationProvider(active.key));
    final choice = await BrowserNewTabSheet.show(
      context,
      currentContainer: active.container,
      currentDirPath: browserTabDuplicatePath(nav),
      mountedVaults: widget.mountedContainers(),
      primaryLocalContainer: widget.primaryLocalContainer(),
    );
    if (!mounted || choice == null) return;
    final path = choice.path;
    final key = _tabs.openTab(
      choice.container,
      initialPath: (path == null || path.isEmpty) ? null : path,
    );
    if (key == null) _showLimitReached();
  }

  void _duplicate(BrowserTab tab) {
    final nav = ref.read(fileBrowserNavigationProvider(tab.key));
    final path = browserTabDuplicatePath(nav);
    final key = _tabs.openTab(
      tab.container,
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

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final showStrip = tabs.length > 1;
    final activeKey = _tabs.activeKey;
    final compactStrip =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final overlayStyle =
        theme.appBarTheme.systemOverlayStyle ??
        (theme.brightness == Brightness.dark
            ? AppSystemUI.transparentDark
            : SystemUiOverlayStyle.dark);

    // The tree shape is identical for one tab and for many (Column ->
    // Expanded -> MediaQuery -> IndexedStack, keyed children): going from
    // one tab to two only swaps the first Column slot, so no screen is ever
    // rebuilt from scratch just because the strip appeared.
    return Column(
      children: [
        if (showStrip)
          AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: ColoredBox(
              color: cs.surfaceContainerLow,
              child: SafeArea(
                bottom: false,
                child: BrowserTabStrip(
                  controller: _tabs,
                  onNewTab: _openNewTabSheet,
                  onDuplicate: _duplicate,
                  compact: compactStrip,
                ),
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            // The strip already absorbed the status-bar inset; each tab's own
            // Scaffold/AppBar must not add it a second time.
            removeTop: showStrip,
            child: IndexedStack(
              index: _tabs.activeIndex,
              sizing: StackFit.expand,
              children: [
                for (final tab in tabs)
                  TickerMode(
                    key: ValueKey<int>(tab.key),
                    enabled: tab.key == activeKey,
                    child: FileBrowserScreen(
                      container: tab.container,
                      tabKey: tab.key,
                      initialPath: tab.initialPath,
                      resolveContainer: widget.resolveContainer,
                      drawer: widget.drawerBuilder?.call(_tabs, tab.volId),
                      showBackButton: true,
                      onUserActivity: tab.key == activeKey
                          ? widget.userActivityFor?.call(tab.volId)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
