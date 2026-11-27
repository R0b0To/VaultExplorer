import 'dart:async';

import 'package:flutter/gestures.dart'
    show
        GestureBinding,
        PointerEvent,
        PointerScrollEvent,
        PointerSignalEvent,
        PointerUpEvent,
        kMiddleMouseButton,
        kPrimaryMouseButton;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/core/widgets/desktop_window_title_bar.dart';
import 'package:vaultexplorer/core/windowing/app_windows.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/browser_tab_paths.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/file_manager_environment.dart';
import 'package:vaultexplorer/features/browser/models/file_category_presentation.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drag.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_tab_drag.dart';
import 'package:vaultexplorer/features/browser/widgets/tab_tear_off_zone.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

/// Leading icon for a location row in the new-tab picker.
class BrowserLocationIcon extends StatelessWidget {
  final MountedContainer container;
  final Color color;
  final double size;

  const BrowserLocationIcon({
    super.key,
    required this.container,
    required this.color,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    if (container.isExternalStorage) {
      return Icon(
        PlatformFeatures.externalStorageIcon,
        size: size,
        color: color,
      );
    }
    if (container.isLocalStorage) {
      return Icon(PlatformFeatures.localStorageIcon, size: size, color: color);
    }
    return ContainerFormatIcon(
      format: ContainerFormat.fromWire(container.containerFormat),
      color: color,
      size: size,
    );
  }
}

enum _TabMenuAction {
  close,
  closeOthers,
  closeToLeft,
  closeToRight,
  duplicate,
  moveToOtherPane,
}

/// Height of the strip; matches the text editor's tab strip.
const double kBrowserTabStripHeight = 40;
const double kBrowserTabItemWidth = 148;

/// File-manager tab strip with a horizontally scrollable reorderable row of
/// tabs and a new-tab button immediately after the last tab. Tapping switches
/// tabs; tapping the active tab opens its operation menu; long-press and drag
/// reorder tabs. The tab controller retains its horizontal offset while the
/// strip moves between screens.
///
/// On desktop the tabs behave like a browser's: a tab is selected as soon as it
/// is pressed and picked up as soon as the mouse moves with it (no press and
/// hold), and a tab pulled out of the strip, down into the window or out of its
/// side, floats under the pointer and opens in a window of its own when let
/// go. A window's last tab can be closed too, which closes the window.
///
/// With a [pane] the strip belongs to that pane in the dual-pane layout: it
/// lists only the pane's own tabs, switching a tab changes only that pane, the
/// new-tab button opens a tab in it, and its bottom edge marks whether the pane
/// has focus. Without one it is the single strip over all tabs.
///
/// The selected tab is drawn in the colour of the bar under the strip, with
/// flared feet, so it reads as part of that bar.
///
/// On desktop the mouse wheel scrolls the tabs sideways once they no longer
/// fit, a slim scrollbar appears along the top edge while the pointer is
/// over the strip, and a tab's close button is drawn only for the active tab
/// or the tab under the pointer.
class BrowserTabStrip extends ConsumerStatefulWidget {
  final BrowserTabsConfig workspaceConfig;
  final VoidCallback onNewTab;
  final ValueChanged<BrowserTabState> onDuplicate;
  final TabPane? pane;

  /// Where [TabPane]s are on screen, in global coordinates. With it a tab can
  /// be dragged out of this strip and dropped on the other pane.
  final Rect? Function(TabPane pane)? paneBounds;

  /// The pane a dragged tab is over right now (null when over none), so the
  /// owner can show where it would land.
  final ValueChanged<TabPane?>? onDragOverPane;
  final String storageKey;
  final double height;

  const BrowserTabStrip({
    super.key,
    required this.workspaceConfig,
    required this.onNewTab,
    required this.onDuplicate,
    this.pane,
    this.paneBounds,
    this.onDragOverPane,
    this.storageKey = 'browser-tab-strip-scroll-position',
    this.height = kBrowserTabStripHeight,
  });

  @override
  ConsumerState<BrowserTabStrip> createState() => _BrowserTabStripState();
}

class _BrowserTabStripState extends ConsumerState<BrowserTabStrip> {
  late final ScrollController _scrollController;
  final Map<TabId, GlobalKey> _tabItemKeys = {};
  TabId? _lastActiveTabId;
  int? _lastActiveIndex;

  /// The tab being dragged, and the other pane it is currently held over.
  TabId? _draggingTabId;
  TabPane? _hoverPane;

  /// Where the latest press landed (window coordinates), from which it is
  /// worked out how the pressed tab was grabbed once its drag starts.
  Offset? _lastPressPosition;

  /// Where the dragged tab was grabbed, relative to its top-left corner, so
  /// that the floating copy of it sits under the pointer the same way.
  Offset _grabOffset = Offset.zero;

  /// Whether the dragged tab is pulled far enough out of the strip that
  /// letting it go opens it in a window of its own (see [TabTearOffZone]).
  bool _tornOut = false;

  /// While [_tornOut]: the tab, and where the corner of its floating copy is
  /// (window coordinates; null while nothing floats).
  BrowserTabState? _tornOutTab;
  final ValueNotifier<Offset?> _tornOutGhost = ValueNotifier<Offset?>(null);
  final OverlayPortalController _tornOutPortal = OverlayPortalController();

  /// Hides the copy of the tab that the list drags while the floating one is
  /// out. After a release it stays hidden until the tab has left, so the list's
  /// drop animation is not seen.
  final ValueNotifier<bool> _dragProxyHidden = ValueNotifier<bool>(false);
  Timer? _fileDropHoverTimer;
  TabId? _fileDropHoverTabId;

  /// Whether the pointer is over the strip; keeps the slim scrollbar visible.
  final ValueNotifier<bool> _stripHovered = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: ref
          .read(browserTabsProvider(widget.workspaceConfig).notifier)
          .tabStripScrollOffsetOf(widget.pane ?? TabPane.primary),
      keepScrollOffset: false,
    )..addListener(_rememberScrollOffset);
    _scrollActiveIntoView(force: true);
  }

  @override
  void didUpdateWidget(covariant BrowserTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scrollActiveIntoView();
  }

  @override
  void dispose() {
    _fileDropHoverTimer?.cancel();
    _scrollController.removeListener(_rememberScrollOffset);
    _scrollController.dispose();
    _stripHovered.dispose();
    _tornOutGhost.dispose();
    _dragProxyHidden.dispose();
    super.dispose();
  }

  void _scheduleFileDropTabActivation(
    BrowserTabState tab,
    BrowserTabs actions,
  ) {
    if (tab.isDashboard || _fileDropHoverTabId == tab.tabId) return;
    _fileDropHoverTimer?.cancel();
    _fileDropHoverTabId = tab.tabId;
    _fileDropHoverTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted || _fileDropHoverTabId != tab.tabId) return;
      actions.activate(tab.tabId);
    });
  }

  void _cancelFileDropTabActivation(TabId tabId) {
    if (_fileDropHoverTabId != tabId) return;
    _fileDropHoverTimer?.cancel();
    _fileDropHoverTimer = null;
    _fileDropHoverTabId = null;
  }

  void _rememberScrollOffset() {
    if (!_scrollController.hasClients) return;
    ref
        .read(browserTabsProvider(widget.workspaceConfig).notifier)
        .setTabStripScrollOffset(
          _scrollController.position.pixels,
          pane: widget.pane ?? TabPane.primary,
        );
  }

  /// Turns the mouse wheel into sideways scrolling of the tabs. The list's own
  /// scrollable only reacts to horizontal deltas (or shift + wheel), so the
  /// plain vertical wheel is translated here. Registering with the resolver
  /// keeps it from also scrolling anything behind the strip.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    final delta = event.scrollDelta;
    // Horizontal gestures (trackpads, tilt wheels) are handled by the list.
    if (delta.dy == 0 || delta.dx.abs() > delta.dy.abs()) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= position.minScrollExtent) return;
    final target = (position.pixels + delta.dy)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if ((target - position.pixels).abs() < 0.5) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(target);
    });
  }

  /// Follows the pointer of a tab drag. The reorder list only moves the tab
  /// within this strip (and only sideways); the pointer itself may be over the
  /// other pane, which is what a drop there is decided by, or far out of the
  /// strip, which is what tearing the tab off into a window is decided by.
  void _trackDrag(PointerEvent event) {
    if (_draggingTabId == null) return;
    final pane = widget.pane;
    TabPane? over;
    if (pane != null) {
      final bounds = widget.paneBounds?.call(pane.other);
      if (bounds != null && bounds.contains(event.position)) {
        over = pane.other;
      }
    }
    if (over != _hoverPane) {
      _hoverPane = over;
      widget.onDragOverPane?.call(over);
    }
    _updateTearOff(event.position, overOtherPane: over != null);
  }

  void _onPointerUp(PointerUpEvent event) {
    // The release itself may be what carries the pointer out of the strip.
    _trackDrag(event);
    // The list reports the end of its drag right after this (_finishDrag). If
    // it never does, because it cancelled the drag (a tab was closed meanwhile,
    // say), nothing may be left floating.
    scheduleMicrotask(() {
      if (mounted && _draggingTabId != null) _resetDrag();
    });
  }

  /// The tab [id] if it can be torn off into a window of its own: there has to
  /// be somewhere to open one, and another tab to stay behind (pulling out a
  /// window's only tab would just swap the window for an identical one).
  BrowserTabState? _tearOffCandidate(TabId id) {
    if (!PlatformFeatures.isDesktop ||
        !FileManagerEnvironment.instance.canOpenTabWindow) {
      return null;
    }
    final state = ref.read(browserTabsProvider(widget.workspaceConfig));
    if (state.tabs.length < 2) return null;
    for (final tab in state.tabs) {
      if (tab.tabId == id) return tab;
    }
    return null;
  }

  void _updateTearOff(Offset pointer, {required bool overOtherPane}) {
    final id = _draggingTabId;
    final candidate = id == null || overOtherPane ? null : _tearOffCandidate(id);
    final strip = context.findRenderObject();
    var torn = false;
    if (candidate != null &&
        strip is RenderBox &&
        strip.attached &&
        strip.hasSize) {
      final top = strip.localToGlobal(Offset.zero).dy;
      // The window's own width, which MediaQuery may not be (a docked sidebar
      // takes its share off it for the content next to it).
      final view = View.of(context);
      torn = TabTearOffZone.isTornOut(
        pointerX: pointer.dx,
        pointerY: pointer.dy,
        stripTop: top,
        stripBottom: top + strip.size.height,
        windowWidth: view.physicalSize.width / view.devicePixelRatio,
        wasTornOut: _tornOut,
      );
    }
    if (torn) {
      _tornOutTab = candidate;
      _tornOutGhost.value = pointer - _grabOffset;
      if (!_tornOut) {
        _tornOut = true;
        _dragProxyHidden.value = true;
        _tornOutPortal.show();
      }
    } else if (_tornOut) {
      _tornOut = false;
      _dragProxyHidden.value = false;
      _tornOutGhost.value = null;
      _tornOutPortal.hide();
    }
  }

  /// Works out where on the tab the pointer took hold of it. Called as the list
  /// starts its drag, while the tab is still in place to be measured.
  void _noteGrab(TabId? id) {
    _grabOffset = Offset.zero;
    final press = _lastPressPosition;
    final box = id == null ? null : _tabItemKeys[id]?.currentContext;
    final render = box?.findRenderObject();
    if (press == null ||
        render is! RenderBox ||
        !render.attached ||
        !render.hasSize) {
      return;
    }
    final grab = press - render.localToGlobal(Offset.zero);
    _grabOffset = Offset(
      grab.dx.clamp(0.0, render.size.width).toDouble(),
      grab.dy.clamp(0.0, render.size.height).toDouble(),
    );
  }

  void _resetDrag({bool keepProxyHidden = false}) {
    _draggingTabId = null;
    if (_hoverPane != null) {
      _hoverPane = null;
      widget.onDragOverPane?.call(null);
    }
    if (_tornOut) {
      _tornOut = false;
      _tornOutGhost.value = null;
      _tornOutPortal.hide();
    }
    if (!keepProxyHidden) _dragProxyHidden.value = false;
  }

  void _finishDrag(BrowserTabs actions) {
    final id = _draggingTabId;
    final target = _hoverPane;
    final tearOff = _tornOut;
    _resetDrag(keepProxyHidden: tearOff);
    if (id == null) return;
    if (tearOff) {
      // After the list has settled its drop: the tab leaves this strip.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tearOffTab(id);
        _dragProxyHidden.value = false;
      });
      return;
    }
    if (target == null) return;
    // After the list has settled its drop: moving the tab changes both strips.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      actions.moveToPane(id, target);
    });
  }

  /// Moves the tab [id] into a window of its own: the window opens on the tab's
  /// location (see [FileManagerEnvironment.openTabWindow]) and the tab closes
  /// here. If the window cannot be opened the tab stays where it is.
  void _tearOffTab(TabId id) {
    final tab = _tearOffCandidate(id);
    if (tab == null) return;
    String? path;
    if (!tab.isDashboard && !tab.isCategory) {
      final nav = ref.read(fileBrowserNavigationProvider(tab.tabId));
      final current = browserTabDuplicatePath(nav);
      path = current.isEmpty ? null : current;
    }
    // The new window is as large as this one, so it reads as the same window.
    final view = View.of(context);
    final opened = FileManagerEnvironment.instance.openTabWindow(
      tab,
      initialPath: path,
      windowSize: view.physicalSize / view.devicePixelRatio,
    );
    if (!opened) return;
    ref.read(browserTabsProvider(widget.workspaceConfig).notifier).closeTab(id);
  }

  /// Closes the tab [id]. On desktop a window's last tab goes with the window,
  /// like in a browser; elsewhere the last tab cannot be closed (no control
  /// offers it).
  void _closeTab(TabId id) {
    final state = ref.read(browserTabsProvider(widget.workspaceConfig));
    if (PlatformFeatures.isDesktop && state.tabs.length < 2) {
      closeWindowOf(context);
      return;
    }
    ref.read(browserTabsProvider(widget.workspaceConfig).notifier).closeTab(id);
  }

  /// The tab pulled out of the strip, floating where the pointer is. It is
  /// drawn in the overlay because it leaves the strip's own bounds.
  Widget _buildTearOffGhost(BuildContext overlayContext) {
    final tab = _tornOutTab;
    if (tab == null) return const SizedBox.shrink();
    final cs = Theme.of(overlayContext).colorScheme;
    final color = PlatformFeatures.isDesktop ? cs.surfaceContainer : cs.surface;
    return TabTearOffGhost(
      topLeft: _tornOutGhost,
      size: Size(kBrowserTabItemWidth, widget.height - 4),
      child: Material(
        elevation: 8,
        color: color,
        shadowColor: cs.shadow.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
        child: _TabItem(
          tab: tab,
          active: true,
          activeBackground: color,
          closeVisible: false,
          onTap: () {},
        ),
      ),
    );
  }

  /// The tab this strip treats as current: the pane's shown tab, or the active
  /// tab for the single strip.
  TabId? _shownTabId(BrowserTabsState state) {
    final pane = widget.pane;
    return pane == null ? state.activeTabId : state.activeTabIdOfPane(pane);
  }

  List<BrowserTabState> _stripTabs(BrowserTabsState state) {
    final pane = widget.pane;
    return pane == null ? state.tabs : state.tabsInPane(pane);
  }

  void _scrollActiveIntoView({bool force = false}) {
    final state = ref.read(browserTabsProvider(widget.workspaceConfig));
    final active = _shownTabId(state);
    final activeIndex = active == null
        ? -1
        : _stripTabs(state).indexWhere((tab) => tab.tabId == active);
    if (!force &&
        active == _lastActiveTabId &&
        activeIndex == _lastActiveIndex) {
      return;
    }
    _lastActiveTabId = active;
    _lastActiveIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          _shownTabId(ref.read(browserTabsProvider(widget.workspaceConfig))) !=
              active) {
        return;
      }
      if (active == null) return;
      if (activeIndex == 0) {
        final position = _scrollController.position;
        if ((position.pixels - position.minScrollExtent).abs() > 0.5) {
          _scrollController.jumpTo(position.minScrollExtent);
        }
        return;
      }
      // Tabs have a fixed width, so where the active one sits is known without
      // asking its widget. (`Scrollable.ensureVisible` with
      // `keepVisibleAtEnd` never scrolls backwards, so a tab hidden on the
      // left stayed hidden; and a tab outside the built range has no widget to
      // ask at all.)
      final position = _scrollController.position;
      final viewport = position.viewportDimension;
      final itemStart = _stripPadding + activeIndex * kBrowserTabItemWidth;
      final itemEnd = itemStart + kBrowserTabItemWidth;
      double? target;
      if (itemStart - _stripPadding < position.pixels) {
        // Hidden (or clipped) on the left: bring its leading edge into view.
        target = itemStart - _stripPadding;
      } else if (itemEnd + _stripPadding > position.pixels + viewport) {
        // Hidden (or clipped) on the right: bring its trailing edge into view.
        target = itemEnd + _stripPadding - viewport;
      }
      if (target == null) return;
      final clamped = target
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if ((clamped - position.pixels).abs() < 0.5) return;
      unawaited(
        _scrollController.animateTo(
          clamped,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
        ),
      );
    });
  }

  /// Horizontal padding of the tab list (see the list's `padding`).
  /// Room at both ends for the flared foot of the selected tab.
  double get _stripPadding => _kTabFlare;

  void _onTabTapped(BrowserTabState tab, BuildContext tabContext) {
    final state = ref.read(browserTabsProvider(widget.workspaceConfig));
    if (PlatformFeatures.isDesktop) {
      ref
          .read(browserTabsProvider(widget.workspaceConfig).notifier)
          .activate(tab.tabId);
      return;
    }
    if (state.activeTabId == tab.tabId) {
      unawaited(_showTabMenu(tab, tabContext));
      return;
    }
    ref
        .read(browserTabsProvider(widget.workspaceConfig).notifier)
        .activate(tab.tabId);
  }

  Future<void> _showTabMenu(
    BrowserTabState tab,
    BuildContext tabContext,
  ) async {
    if (!tabContext.mounted) return;
    final tabBox = tabContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(tabContext).context.findRenderObject() as RenderBox?;
    if (tabBox == null ||
        overlayBox == null ||
        !tabBox.attached ||
        !tabBox.hasSize) {
      return;
    }

    final topLeft = tabBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final bottomRight = tabBox.localToGlobal(
      tabBox.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    );
    final anchor = Rect.fromLTRB(
      topLeft.dx,
      bottomRight.dy,
      bottomRight.dx,
      bottomRight.dy,
    );

    PopupMenuItem<_TabMenuAction> item(
      _TabMenuAction value,
      IconData icon,
      String label, {
      bool enabled = true,
    }) {
      return PopupMenuItem<_TabMenuAction>(
        value: value,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      );
    }

    final state = ref.read(browserTabsProvider(widget.workspaceConfig));
    final actions = ref.read(
      browserTabsProvider(widget.workspaceConfig).notifier,
    );
    final l10n = tabContext.l10n;
    final stripTabs = _stripTabs(state);
    final tabIndex = stripTabs.indexWhere((entry) => entry.tabId == tab.tabId);
    final choice = await showMenu<_TabMenuAction>(
      context: tabContext,
      position: RelativeRect.fromRect(anchor, Offset.zero & overlayBox.size),
      items: [
        item(
          _TabMenuAction.close,
          Icons.close_rounded,
          l10n.browserTabClose,
          // The last tab closes its window on desktop (see _closeTab).
          enabled: PlatformFeatures.isDesktop || state.tabs.length > 1,
        ),
        item(
          _TabMenuAction.closeOthers,
          Icons.tab_unselected_rounded,
          l10n.browserTabCloseOthers,
          enabled: stripTabs.length > 1,
        ),
        item(
          _TabMenuAction.closeToLeft,
          Icons.arrow_back_rounded,
          l10n.browserTabCloseToLeft,
          enabled: tabIndex > 0,
        ),
        item(
          _TabMenuAction.closeToRight,
          Icons.arrow_forward_rounded,
          l10n.browserTabCloseToRight,
          enabled: tabIndex >= 0 && tabIndex < stripTabs.length - 1,
        ),
        const PopupMenuDivider(),
        if (state.splitAvailable)
          item(
            _TabMenuAction.moveToOtherPane,
            Icons.swap_horiz_rounded,
            l10n.browserTabMoveToOtherPane,
            enabled: state.tabs.length > 1,
          ),
        item(
          _TabMenuAction.duplicate,
          Icons.copy_all_rounded,
          l10n.browserTabDuplicate,
          enabled: !state.atLimit,
        ),
      ],
    );
    if (!mounted ||
        choice == null ||
        !ref
            .read(browserTabsProvider(widget.workspaceConfig))
            .tabs
            .any((entry) => entry.tabId == tab.tabId)) {
      return;
    }

    switch (choice) {
      case _TabMenuAction.close:
        _closeTab(tab.tabId);
      case _TabMenuAction.closeOthers:
        actions.closeOthers(tab.tabId);
      case _TabMenuAction.closeToLeft:
        actions.closeToLeft(tab.tabId);
      case _TabMenuAction.closeToRight:
        actions.closeToRight(tab.tabId);
      case _TabMenuAction.duplicate:
        widget.onDuplicate(tab);
      case _TabMenuAction.moveToOtherPane:
        actions.moveToPane(tab.tabId, tab.pane.other);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabsEnabled = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.useBrowserTabs),
    );
    if (!tabsEnabled) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final state = ref.watch(browserTabsProvider(widget.workspaceConfig));
    final pane = widget.pane;
    final tabs = _stripTabs(state);
    final shownTabId = _shownTabId(state);
    // Side by side, only one pane is the active one (the pane of the active
    // tab). The single strip always is.
    final paneFocused = pane == null || state.focusedPane == pane;
    final actions = ref.read(
      browserTabsProvider(widget.workspaceConfig).notifier,
    );
    final liveTabIds = tabs.map((tab) => tab.tabId).toSet();
    _tabItemKeys.removeWhere((id, _) => !liveTabIds.contains(id));
    _scrollActiveIntoView();
    final windowTitleBar = DesktopWindowTitleBarScope.maybeOf(context);

    // The strip is a shade darker than the bar under it, and the selected tab
    // is drawn in that bar's colour, flowing into it. Under the strip sit the
    // navigation row (desktop, `surfaceContainer`) or breadcrumb bar / page
    // (phones and tablets, `surface`).
    const connected = true;
    final barColor = PlatformFeatures.isDesktop
        ? cs.surfaceContainer
        : cs.surface;
    final stripBackground = tabStripColorOver(cs, barColor);
    final activeBackground = barColor;
    final shownBackground = barColor;

    // On desktop a tab starts dragging as soon as the mouse moves a few pixels
    // with it pressed, like in a browser. Elsewhere it takes a press and hold,
    // which keeps a swipe along the strip from picking a tab up.
    Widget dragStart({
      required Key key,
      required int index,
      required Widget child,
    }) => PlatformFeatures.isDesktop
        ? BrowserTabDragStartListener(key: key, index: index, child: child)
        : ReorderableDelayedDragStartListener(
            key: key,
            index: index,
            child: child,
          );

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: stripBackground,
        // Marks the active pane (the one the keyboard, the toolbar and the
        // close buttons belong to).
        border: pane == null || connected
            ? null
            : Border(
                bottom: BorderSide(
                  color: paneFocused ? cs.primary : Colors.transparent,
                  width: 2,
                ),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // On desktop the + sits right after the last tab while they
                // fit; once they overflow the list stops short of it and the +
                // stays fixed at the right edge, always visible.
                final tabsWidth =
                    _stripPadding * 2 + tabs.length * kBrowserTabItemWidth;
                final listWidth = PlatformFeatures.isDesktop
                    ? tabsWidth
                          .clamp(
                            0.0,
                            (constraints.maxWidth - 48).clamp(
                              0.0,
                              double.infinity,
                            ),
                          )
                          .toDouble()
                    : constraints.maxWidth;
                final trailingBlankStart = listWidth + 48;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: listWidth,
                      child: MouseRegion(
                        onEnter: (_) => _stripHovered.value = true,
                        onExit: (_) => _stripHovered.value = false,
                        child: Listener(
                          behavior: HitTestBehavior.translucent,
                          onPointerDown: (event) =>
                              _lastPressPosition = event.position,
                          onPointerMove: _trackDrag,
                          onPointerUp: _onPointerUp,
                          onPointerCancel: (_) => _resetDrag(),
                          onPointerSignal: _onPointerSignal,
                          // A slim scrollbar along the top edge, shown while
                          // the pointer is over the strip (only when the tabs
                          // overflow). The platform's default scrollbar is
                          // switched off below so there is only this one.
                          child: ValueListenableBuilder<bool>(
                            valueListenable: _stripHovered,
                            builder: (context, hovered, list) => RawScrollbar(
                              controller: _scrollController,
                              thumbVisibility:
                                  PlatformFeatures.isDesktop && hovered,
                              interactive: PlatformFeatures.isDesktop,
                              scrollbarOrientation: ScrollbarOrientation.top,
                              thickness: 3,
                              radius: const Radius.circular(2),
                              crossAxisMargin: 0,
                              minThumbLength: 24,
                              thumbColor: cs.onSurface.withValues(alpha: 0.32),
                              child: list!,
                            ),
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(
                                context,
                              ).copyWith(scrollbars: false),
                              child: ReorderableListView.builder(
                                key: PageStorageKey<String>(
                                  '${widget.storageKey}-${pane?.name ?? 'all'}',
                                ),
                                scrollController: _scrollController,
                                scrollDirection: Axis.horizontal,
                                clipBehavior: Clip.hardEdge,
                                buildDefaultDragHandles: false,
                                padding: connected
                                    ? EdgeInsets.fromLTRB(
                                        _stripPadding,
                                        4,
                                        _stripPadding,
                                        0,
                                      )
                                    : EdgeInsets.symmetric(
                                        horizontal: _stripPadding,
                                        vertical: 3,
                                      ),
                                // The + button is not a list item: see below.
                                itemCount: tabs.length,
                                onReorderStart: (index) {
                                  HapticFeedback.mediumImpact();
                                  _draggingTabId =
                                      index >= 0 && index < tabs.length
                                      ? tabs[index].tabId
                                      : null;
                                  _noteGrab(_draggingTabId);
                                },
                                onReorderEnd: (_) => _finishDrag(actions),
                                onReorderItem: pane == null
                                    ? actions.reorderTabs
                                    : (oldIndex, newIndex) =>
                                          actions.reorderTabsInPane(
                                            pane,
                                            oldIndex,
                                            newIndex,
                                          ),
                                proxyDecorator: (child, index, animation) {
                                  // Gives way to the floating copy once the
                                  // tab is pulled out of the strip.
                                  return ValueListenableBuilder<bool>(
                                    valueListenable: _dragProxyHidden,
                                    builder: (context, hidden, proxy) =>
                                        Opacity(
                                          opacity: hidden ? 0 : 1,
                                          child: proxy,
                                        ),
                                    child: AnimatedBuilder(
                                      animation: animation,
                                      builder: (context, child) {
                                        final t = Curves.easeInOut.transform(
                                          animation.value,
                                        );
                                        return Material(
                                          elevation: 6 * t,
                                          color: activeBackground,
                                          shadowColor: cs.shadow.withValues(
                                            alpha: 0.35,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          child: child,
                                        );
                                      },
                                      child: child,
                                    ),
                                  );
                                },
                                itemBuilder: (context, index) {
                                  final tab = tabs[index];
                                  final itemKey = _tabItemKeys.putIfAbsent(
                                    tab.tabId,
                                    GlobalKey.new,
                                  );
                                  final isShown = tab.tabId == shownTabId;
                                  // Every pane's shown tab is highlighted the same way; no
                                  // pane is singled out as the focused one.
                                  final isActive = isShown;
                                  return dragStart(
                                    key: ValueKey<TabId>(tab.tabId),
                                    index: index,
                                    child: Builder(
                                      builder: (tabContext) => SizedBox(
                                        key: itemKey,
                                        width: kBrowserTabItemWidth,
                                        child: DragTarget<BrowserItemDragData>(
                                          onWillAcceptWithDetails: (details) {
                                            final destination = tab.container;
                                            if (destination == null ||
                                                tab.isDashboard ||
                                                tab.isCategory) {
                                              return false;
                                            }
                                            final navigation = ref.read(
                                              fileBrowserNavigationProvider(
                                                tab.tabId,
                                              ),
                                            );
                                            if (navigation.archiveContext !=
                                                null) {
                                              return false;
                                            }
                                            final path =
                                                navigation.currentDirPath;
                                            if (!details.data.canDropInto(
                                              destination,
                                              path,
                                            )) {
                                              return false;
                                            }
                                            _scheduleFileDropTabActivation(
                                              tab,
                                              actions,
                                            );
                                            return true;
                                          },
                                          onMove: (_) =>
                                              _scheduleFileDropTabActivation(
                                                tab,
                                                actions,
                                              ),
                                          onLeave: (_) =>
                                              _cancelFileDropTabActivation(
                                                tab.tabId,
                                              ),
                                          onAcceptWithDetails: (details) {
                                            _cancelFileDropTabActivation(
                                              tab.tabId,
                                            );
                                            final destination = tab.container;
                                            if (destination == null ||
                                                tab.isDashboard ||
                                                tab.isCategory) {
                                              return;
                                            }
                                            actions.activate(tab.tabId);
                                            final navigation = ref.read(
                                              fileBrowserNavigationProvider(
                                                tab.tabId,
                                              ),
                                            );
                                            if (navigation.archiveContext !=
                                                null)
                                              return;
                                            // Same Copy / Move / Cancel menu as dropping in a
                                            // folder view (Move is left out when the items
                                            // already live in that tab's folder).
                                            unawaited(
                                              handleBrowserItemDrop(
                                                tabContext,
                                                details,
                                                destination,
                                                navigation.currentDirPath,
                                              ),
                                            );
                                          },
                                          builder: (context, candidates, rejected) => DecoratedBox(
                                            decoration: candidates.isEmpty
                                                ? const BoxDecoration()
                                                : BoxDecoration(
                                                    border: Border.all(
                                                      color: cs.primary,
                                                      width: 2,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                            child: _TabItem(
                                              tab: tab,
                                              active: isActive,
                                              activeBackground: shownBackground,
                                              connected: connected,
                                              // Side by side, the focused pane's
                                              // selected tab carries an accent line.
                                              accent:
                                                  pane != null && paneFocused,
                                              onTap: () =>
                                                  _onTabTapped(tab, tabContext),
                                              onSecondaryTap:
                                                  PlatformFeatures.isDesktop
                                                  ? () => unawaited(
                                                      _showTabMenu(
                                                        tab,
                                                        tabContext,
                                                      ),
                                                    )
                                                  : null,
                                              // A window's last tab closes
                                              // the window (see _closeTab).
                                              onClose: PlatformFeatures.isDesktop
                                                  ? () => _closeTab(tab.tabId)
                                                  : null,
                                              // Selected on press, as in a
                                              // browser, so a tab is the
                                              // current one as soon as it is
                                              // picked up.
                                              onPressDown:
                                                  PlatformFeatures.isDesktop
                                                  ? () => actions.activate(
                                                      tab.tabId,
                                                    )
                                                  : null,
                                              // Only the active pane draws the
                                              // buttons; the other pane's tabs
                                              // still close with a middle click
                                              // or from their menu.
                                              closeVisible: paneFocused,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (PlatformFeatures.isDesktop)
                      Positioned(
                        left: listWidth,
                        top: 0,
                        bottom: 0,
                        width: 48,
                        child: IconButton(
                          icon: const Icon(Icons.add_rounded, size: 20),
                          style: IconButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: Size(
                              widget.height - 6,
                              widget.height - 6,
                            ),
                            maximumSize: Size(
                              widget.height - 6,
                              widget.height - 6,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          tooltip: context.l10n.browserTabNew,
                          onPressed: () {
                            // The new tab joins the pane whose + was pressed.
                            if (pane != null) actions.focusPane(pane);
                            widget.onNewTab();
                          },
                        ),
                      ),
                    if (windowTitleBar != null &&
                        trailingBlankStart < constraints.maxWidth)
                      Positioned(
                        left: trailingBlankStart,
                        top: 0,
                        right: 0,
                        bottom: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onPanStart: (_) => windowTitleBar.onDragStart(),
                          onDoubleTap: windowTitleBar.onDoubleTap,
                          child: const SizedBox.expand(),
                        ),
                      ),
                    // Where a tab pulled out of the strip floats (see
                    // _buildTearOffGhost). Takes no room itself.
                    Positioned(
                      key: const ValueKey<String>('tab-tear-off-ghost'),
                      left: 0,
                      top: 0,
                      width: 0,
                      height: 0,
                      child: OverlayPortal(
                        controller: _tornOutPortal,
                        overlayChildBuilder: _buildTearOffGhost,
                        child: const SizedBox.shrink(),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // Fixed at the right edge, so it does not move as tabs come and go.
          if (!PlatformFeatures.isDesktop)
            SizedBox(
              width: 48,
              child: IconButton(
                icon: const Icon(Icons.add_rounded, size: 20),
                visualDensity: VisualDensity.compact,
                tooltip: context.l10n.browserTabNew,
                onPressed: () {
                  // The new tab joins the pane whose + was pressed.
                  if (pane != null) actions.focusPane(pane);
                  widget.onNewTab();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _TabItem extends ConsumerStatefulWidget {
  final BrowserTabState tab;
  final bool active;
  final Color activeBackground;

  /// Desktop style: the selected tab is a rounded-top tab that continues into
  /// the toolbar below it (flared feet, no gap underneath).
  final bool connected;

  /// Draws a primary-coloured line on top of the selected tab.
  final bool accent;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;

  /// Null where tabs have no close button (phones and tablets close a tab from
  /// its menu).
  final VoidCallback? onClose;

  /// Called when the primary button (or a finger) goes down on the tab, but
  /// not on its close button. Desktop selects the tab here instead of waiting
  /// for the release.
  final VoidCallback? onPressDown;

  /// Whether the active tab draws its close button (false in the pane that is
  /// not focused). Any tab also draws it while the pointer is over it. The
  /// button's slot at the tab's right edge is kept either way, so the label
  /// does not shift as it comes and goes.
  final bool closeVisible;

  const _TabItem({
    required this.tab,
    required this.active,
    required this.activeBackground,
    this.connected = false,
    this.accent = false,
    required this.onTap,
    this.onSecondaryTap,
    this.onClose,
    this.onPressDown,
    this.closeVisible = true,
  });

  @override
  ConsumerState<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends ConsumerState<_TabItem> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value || !mounted) return;
    setState(() => _hovered = value);
  }

  /// Whether [local] (relative to the tab) is on the close button's slot at its
  /// right edge. Pressing the button must not select the tab on its way to
  /// closing it.
  bool _onCloseButton(Offset local) {
    if (widget.onClose == null) return false;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return local.dx >= box.size.width - _kTabCloseSlotWidth;
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    final active = widget.active;
    final onClose = widget.onClose;
    final cs = Theme.of(context).colorScheme;
    // The close button shows on the active tab and on the hovered one.
    final showClose = _hovered || (active && widget.closeVisible);
    final shape = widget.connected
        ? const BorderRadius.vertical(top: Radius.circular(8))
        : BorderRadius.circular(8);

    // Folder name once the tab has navigated into a directory, otherwise the
    // vault / storage name. Watching only this derived string keeps the tab
    // from rebuilding on every directory-listing or selection change.
    final folderLabel = tab.isDashboard
        ? null
        : tab.isCategory
        ? tab.category!.label(context.l10n)
        : ref.watch(
            fileBrowserNavigationProvider(tab.tabId).select(
              (s) => s.pathStack.length <= 1 ? null : s.pathStack.last.label,
            ),
          );
    final name = tab.isCategory
        ? tab.category!.label(context.l10n)
        : tab.container?.displayName ?? context.l10n.vaultsSectionTitle;
    final label = folderLabel ?? name;
    // Background tabs are dimmed so the selected one stands out clearly.
    final fg = active
        ? cs.onSurface
        : cs.onSurfaceVariant.withValues(alpha: 0.7);

    return Tooltip(
      message: tab.isCategory
          ? tab.category!.label(context.l10n)
          : (folderLabel == null ? name : '$name / $folderLabel'),
      // Long-press belongs to the drag start listener above this tab (phones
      // and tablets pick a tab up that way). Letting Tooltip use its default
      // long-press trigger consumes the gesture and shows the label instead of
      // starting a drag.
      triggerMode: TooltipTriggerMode.manual,
      child: MouseRegion(
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            Material(
              color: active ? widget.activeBackground : Colors.transparent,
              borderRadius: shape,
              child: Listener(
                // A middle click closes the tab, as in a browser.
                onPointerDown: (event) {
                  if (event.buttons == kMiddleMouseButton) {
                    onClose?.call();
                  } else if (event.buttons == kPrimaryMouseButton &&
                      widget.onPressDown != null &&
                      !_onCloseButton(event.localPosition)) {
                    widget.onPressDown!();
                  }
                },
                child: InkWell(
                  borderRadius: shape,
                  // No sparkle/pulse or pressed highlight when a tab is
                  // selected; the active tab's background already shows it.
                  splashFactory: NoSplash.splashFactory,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  onTap: widget.onTap,
                  onSecondaryTap: widget.onSecondaryTap,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 200),
                    padding: EdgeInsets.only(
                      left: 8,
                      right: onClose != null ? 4 : 8,
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      children: [
                        if (tab.isCategory) ...[
                          Icon(
                            tab.category!.icon,
                            size: 15,
                            color: active ? cs.primary : fg,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: active
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: fg,
                            ),
                          ),
                        ),
                        // Pinned to the tab's right edge.
                        if (onClose != null)
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: showClose
                                ? IconButton(
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    iconSize: 14,
                                    tooltip: context.l10n.browserTabClose,
                                    onPressed: onClose,
                                    icon: const Icon(Icons.close_rounded),
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Concave feet that blend the selected tab into the toolbar.
            if (widget.connected && active) ...[
              Positioned(
                left: -_kTabFlare,
                bottom: 0,
                width: _kTabFlare,
                height: _kTabFlare,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _TabFootPainter(
                      widget.activeBackground,
                      left: true,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: -_kTabFlare,
                bottom: 0,
                width: _kTabFlare,
                height: _kTabFlare,
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _TabFootPainter(
                      widget.activeBackground,
                      left: false,
                    ),
                  ),
                ),
              ),
            ],
            if (widget.accent && active)
              Positioned(
                left: 8,
                right: 8,
                top: 0,
                height: 2,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Radius of the concave feet of the selected desktop tab.
const double _kTabFlare = 8;

/// The stretch at a tab's right edge that belongs to its close button (the
/// 20 px button and the padding after it, plus a little to be safe).
const double _kTabCloseSlotWidth = 28;

/// One concave foot: the square between the tab's side and a quarter circle,
/// so the tab's colour sweeps outwards into the toolbar below it.
class _TabFootPainter extends CustomPainter {
  final Color color;
  final bool left;

  const _TabFootPainter(this.color, {required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width;
    final path = Path();
    if (left) {
      path
        ..moveTo(r, 0)
        ..lineTo(r, r)
        ..lineTo(0, r)
        ..arcToPoint(Offset(r, 0), radius: Radius.circular(r), clockwise: false)
        ..close();
    } else {
      path
        ..moveTo(0, 0)
        ..lineTo(0, r)
        ..lineTo(r, r)
        ..arcToPoint(Offset(0, 0), radius: Radius.circular(r))
        ..close();
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TabFootPainter old) =>
      old.color != color || old.left != left;
}
