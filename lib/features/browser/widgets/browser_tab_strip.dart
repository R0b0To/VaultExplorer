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
import 'package:vaultexplorer/core/windowing/window_caption.dart';
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
import 'package:vaultexplorer/features/browser/widgets/tab_drag_platform.dart';
import 'package:vaultexplorer/features/browser/widgets/tab_drag_session.dart';
import 'package:vaultexplorer/features/browser/widgets/tab_tear_off_zone.dart';
import 'package:vaultexplorer/features/browser/widgets/tab_transfer.dart';
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
/// Where the platform allows it (Windows), the drag is live like in a browser:
/// the window made for a tab pulled out follows the pointer, a tab can be
/// dropped into the strip of another window (the strips of every window take
/// part, see [tabDropTargets]), and a window's only tab moves the whole window.
/// See [TabDragSession].
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

  /// The live drag of the tab being dragged, once it left the strip (or at
  /// once, for a window's only tab). See [TabDragSession].
  TabDragSession<TabTransfer>? _session;

  /// Whether the window made for the dragged tab has been drawn, so that the
  /// floating copy is not needed any more; and whether the tab is back over
  /// its own strip.
  bool _carrierShown = false;
  bool _returned = false;
  bool _ghostShown = false;

  /// This strip as a place for another window's tab to be dropped, and the tab
  /// that is held over it right now (shown at its slot).
  late final _StripDropTarget _dropTarget = _StripDropTarget(this);
  bool _dropTargetAdded = false;
  int? _viewId;
  ({BrowserTabState tab, int slot})? _incoming;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _viewId = View.maybeOf(context)?.viewId;
    if (!_dropTargetAdded && _viewId != null && PlatformFeatures.isDesktop) {
      _dropTargetAdded = true;
      tabDropTargets.register(_dropTarget);
    }
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
    tabDropTargets.unregister(_dropTarget);
    // A drag in progress is given up. Its end is not reported back here.
    final session = _session;
    _session = null;
    session?.abort();
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
    if (_session != null) {
      _updateTearOff(event.position, overOtherPane: false);
      return;
    }
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
    // say), nothing may be left floating. A live drag ends by itself: it reads
    // the mouse button from the system.
    scheduleMicrotask(() {
      if (mounted && _session == null && _draggingTabId != null) _resetDrag();
    });
  }

  /// The tab [id] if it can be torn off into a window of its own: there has to
  /// be somewhere to open one, and another tab to stay behind (a window's only
  /// tab moves the window instead, see [_beginLiveDrag]).
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

  /// Whether the platform can follow a drag live: where the cursor is, which
  /// window is under it, moving a window along. Only a window that the runner
  /// knows by its view id qualifies.
  bool get _liveDragAvailable =>
      WindowsTabDragPlatform.isSupported && windowChannelArgsFor(context) != null;

  void _updateTearOff(Offset pointer, {required bool overOtherPane}) {
    if (_session != null) {
      // The live drag decides from here on (see TabDragSession). The floating
      // copy only stands in until the new window has been drawn.
      if (_ghostShown) _tornOutGhost.value = pointer - _grabOffset;
      return;
    }
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
        if (_liveDragAvailable) _beginLiveDrag(candidate!, movesWindow: false);
        _syncGhost();
      }
    } else if (_tornOut) {
      _tornOut = false;
      _dragProxyHidden.value = false;
      _syncGhost();
    }
  }

  /// Whether the floating copy of the tab shows: while the tab is held out and
  /// no window of its own shows it yet (or never will, where there is no live
  /// drag and the window only opens when the tab is let go).
  void _syncGhost() {
    final want = _tornOut && !_carrierShown && !_returned;
    if (want == _ghostShown) return;
    _ghostShown = want;
    if (want) {
      _tornOutPortal.show();
    } else {
      _tornOutPortal.hide();
      _tornOutGhost.value = null;
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
    _tornOut = false;
    _syncGhost();
    if (!keepProxyHidden) _dragProxyHidden.value = false;
  }

  void _finishDrag(BrowserTabs actions) {
    final session = _session;
    if (session != null) {
      // A live drag settles itself on where the cursor is now (and has
      // usually noticed the release already).
      _draggingTabId = null;
      unawaited(session.finishNow());
      return;
    }
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

  /// Where in its container a folder tab is (null for the root, and for tabs
  /// that are not folders).
  String? _pathOf(BrowserTabState tab) {
    if (tab.isDashboard || tab.isCategory) return null;
    final current = browserTabDuplicatePath(
      ref.read(fileBrowserNavigationProvider(tab.tabId)),
    );
    return current.isEmpty ? null : current;
  }

  /// The size for a window made for a tab of this one: the same, so that it
  /// reads as the same window, but never larger than most of the screen (a
  /// maximized window is not one that size when it is restored).
  Size _newWindowSize() {
    final view = View.of(context);
    final size = view.physicalSize / view.devicePixelRatio;
    final display = view.display;
    final screen = display.size / display.devicePixelRatio;
    return Size(
      size.width < screen.width * 0.9 ? size.width : screen.width * 0.9,
      size.height < screen.height * 0.9 ? size.height : screen.height * 0.9,
    );
  }

  /// Moves the tab [id] into a window of its own once it is let go, for where
  /// there is no live drag: the window opens on the tab's location (see
  /// [FileManagerEnvironment.openTabWindow]), under the cursor where the
  /// platform allows, and the tab closes here. If the window cannot be opened
  /// the tab stays where it is.
  void _tearOffTab(TabId id) {
    final tab = _tearOffCandidate(id);
    if (tab == null) return;
    final opened = FileManagerEnvironment.instance.openTabWindow(
      TabWindowRequest(
        tab: tab,
        initialPath: _pathOf(tab),
        windowSize: _newWindowSize(),
        placeAtCursor: true,
      ),
    );
    if (opened == null) return;
    ref.read(browserTabsProvider(widget.workspaceConfig).notifier).closeTab(id);
  }

  // ---- the live drag: this strip as where a drag starts

  /// Starts the live drag of [tab]: from the moment it is pulled out of the
  /// strip, or, for a window's only tab, from the moment it is picked up
  /// (then it is the window that follows the cursor).
  void _beginLiveDrag(BrowserTabState tab, {required bool movesWindow}) {
    final viewId = _viewId;
    if (viewId == null || _session != null) return;
    final press = _lastPressPosition ?? Offset.zero;
    _carrierShown = false;
    _returned = false;
    // A tab pulled out gives way to the window that carries it. A window's only
    // tab stays in sight instead: the window moves with the cursor, so the
    // lifted tab simply stays where it is under it.
    if (!movesWindow) _dragProxyHidden.value = true;
    final session = TabDragSession<TabTransfer>(
      payload: TabTransfer(tab: tab, sourceViewId: viewId, path: _pathOf(tab)),
      sourceViewId: viewId,
      platform: const WindowsTabDragPlatform(),
      targets: tabDropTargets,
      host: _LiveDragHost(this),
      movesSourceWindow: movesWindow,
      // Where in this window the cursor stays when the window itself moves:
      // where it took hold of the tab.
      grabX: press.dx,
      grabY: press.dy,
    );
    _session = session;
    unawaited(session.start());
  }

  bool _inSourceStrip(double x, double y, {required bool wasInside}) {
    final strip = context.findRenderObject();
    if (strip is! RenderBox || !strip.attached || !strip.hasSize) return false;
    final top = strip.localToGlobal(Offset.zero).dy;
    final view = View.of(context);
    return !TabTearOffZone.isTornOut(
      pointerX: x,
      pointerY: y,
      stripTop: top,
      stripBottom: top + strip.size.height,
      windowWidth: view.physicalSize.width / view.devicePixelRatio,
      wasTornOut: !wasInside,
    );
  }

  TabDragCarrierWindow? _openCarrier(void Function() onShown) {
    final tab = _session?.payload.tab;
    if (tab == null) return null;
    final opened = FileManagerEnvironment.instance.openTabWindow(
      TabWindowRequest(
        tab: tab,
        initialPath: _pathOf(tab),
        windowSize: _newWindowSize(),
        onFirstFrame: onShown,
      ),
    );
    if (opened == null) return null;
    // The cursor stays on the new window's tab where it was on this one.
    final grab = _grabOffset;
    return TabDragCarrierWindow(
      viewId: opened.viewId,
      close: opened.close,
      grip: () => (x: opened.tabLeft + grab.dx, y: 4 + grab.dy),
    );
  }

  void _liveReturned(bool returned) {
    if (_session == null) return;
    _returned = returned;
    _dragProxyHidden.value = !returned;
    _syncGhost();
  }

  void _liveCarrierShown() {
    if (_session == null) return;
    _carrierShown = true;
    _syncGhost();
  }

  void _onLiveDragFinished(TabDragResult result) {
    final session = _session;
    if (session == null || !mounted) return;
    _session = null;
    final tab = session.payload.tab;
    _carrierShown = false;
    _returned = false;
    switch (result.outcome) {
      case TabDragOutcome.returned:
      case TabDragOutcome.cancelled:
        // Nothing left: the list settles its own drag, as if the tab had never
        // been pulled out.
        _tornOut = false;
        _syncGhost();
        _dragProxyHidden.value = false;
      case TabDragOutcome.movedWindow:
        _resetDrag();
      case TabDragOutcome.detached:
        // The tab lives in its own window now.
        _resetDrag(keepProxyHidden: true);
        ref
            .read(browserTabsProvider(widget.workspaceConfig).notifier)
            .closeTab(tab.tabId);
        _dragProxyHidden.value = false;
      case TabDragOutcome.dropped:
        _resetDrag(keepProxyHidden: true);
        if (session.movesSourceWindow) {
          // Its only tab went to another window, and this window with it.
          closeWindowOf(context);
        } else {
          ref
              .read(browserTabsProvider(widget.workspaceConfig).notifier)
              .closeTab(tab.tabId);
          _dragProxyHidden.value = false;
        }
    }
  }

  // ---- the live drag: this strip as where another window's tab is dropped

  /// Where the strip is on the screen of its own window, a little taller than
  /// it is so that a tab need not be aimed precisely. Null while it cannot take
  /// a drop: not drawn, or covered by another page of the window.
  DragRect? _dropZone() {
    if (!mounted) return null;
    if (ModalRoute.of(context)?.isCurrent == false) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize || box.size.isEmpty) {
      return null;
    }
    final origin = box.localToGlobal(Offset.zero);
    return (
      left: origin.dx,
      top: origin.dy - 6,
      right: origin.dx + box.size.width,
      bottom: origin.dy + box.size.height + 6,
    );
  }

  bool _accepts(TabTransfer payload) {
    if (!mounted || payload.sourceViewId == _viewId) return false;
    return !ref.read(browserTabsProvider(widget.workspaceConfig)).atLimit;
  }

  /// The slot (0 = before the first tab) that a tab held at window x [x] would
  /// take: after the tabs whose middle is to its left.
  int _slotAt(double x) {
    final box = context.findRenderObject();
    final left = box is RenderBox && box.attached
        ? box.localToGlobal(Offset.zero).dx
        : 0.0;
    final scrolled = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    final count = _stripTabs(
      ref.read(browserTabsProvider(widget.workspaceConfig)),
    ).length;
    final slot = ((x - left - _stripPadding + scrolled) / kBrowserTabItemWidth)
        .round();
    return slot.clamp(0, count);
  }

  void _showIncoming(TabTransfer payload, int slot) {
    if (!mounted) return;
    setState(() => _incoming = (tab: payload.tab, slot: slot));
  }

  void _clearIncoming() {
    if (!mounted || _incoming == null) return;
    setState(() => _incoming = null);
  }

  bool _takeIn(TabTransfer payload, int slot) {
    if (!mounted) return false;
    final id = ref
        .read(browserTabsProvider(widget.workspaceConfig).notifier)
        .adoptTab(
          payload.tab,
          initialPath: payload.path,
          pane: widget.pane,
          slot: slot,
        );
    return id != null;
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

  /// The tab of another window that is held over this strip: where it would
  /// land, in the strip's own colour, so it is plain that it is not here yet.
  Widget _buildIncomingTab(
    BrowserTabState tab, {
    required bool connected,
    required Color color,
  }) {
    return SizedBox(
      key: const ValueKey<String>('incoming-tab'),
      width: kBrowserTabItemWidth,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.7,
          child: _TabItem(
            tab: tab,
            active: true,
            connected: connected,
            activeBackground: color,
            closeVisible: false,
            onTap: () {},
          ),
        ),
      ),
    );
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
    // A tab held over this strip by a drag from another window shows at the
    // slot it would take, and the tabs after it make room.
    final incoming = _incoming;
    final slotted = incoming == null
        ? tabs
        : <BrowserTabState>[
            ...tabs.take(incoming.slot),
            incoming.tab,
            ...tabs.skip(incoming.slot),
          ];
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
                    _stripPadding * 2 + slotted.length * kBrowserTabItemWidth;
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
                          onPointerCancel: (_) {
                            if (_session == null) _resetDrag();
                          },
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
                                itemCount: slotted.length,
                                onReorderStart: (index) {
                                  HapticFeedback.mediumImpact();
                                  _draggingTabId =
                                      index >= 0 && index < tabs.length
                                      ? tabs[index].tabId
                                      : null;
                                  _noteGrab(_draggingTabId);
                                  // A window's only tab has nowhere to be
                                  // pulled out to: it moves the window.
                                  if (_draggingTabId != null &&
                                      tabs.length == 1 &&
                                      state.tabs.length == 1 &&
                                      _liveDragAvailable) {
                                    _beginLiveDrag(tabs[0], movesWindow: true);
                                  }
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
                                  final tab = slotted[index];
                                  if (incoming != null &&
                                      tab.tabId == incoming.tab.tabId) {
                                    return _buildIncomingTab(
                                      tab,
                                      connected: connected,
                                      color: activeBackground,
                                    );
                                  }
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

/// What a live drag (see [TabDragSession]) needs from the strip it started in.
class _LiveDragHost implements TabDragHost {
  _LiveDragHost(this._strip);

  final _BrowserTabStripState _strip;

  @override
  bool isInSourceStrip(double x, double y, {required bool wasInside}) =>
      _strip._inSourceStrip(x, y, wasInside: wasInside);

  @override
  TabDragCarrierWindow? openCarrier({required void Function() onShown}) =>
      _strip._openCarrier(onShown);

  @override
  void returned(bool returned) => _strip._liveReturned(returned);

  @override
  void carrierShown() => _strip._liveCarrierShown();

  @override
  void finished(TabDragResult result) => _strip._onLiveDragFinished(result);
}

/// A strip as a place that another window's tab can be dropped.
class _StripDropTarget implements TabDropTarget<TabTransfer> {
  _StripDropTarget(this._strip);

  final _BrowserTabStripState _strip;

  // No window has this id, so a strip that has not been given its window yet
  // is never found under a cursor.
  @override
  int get viewId => _strip._viewId ?? -1;

  @override
  DragRect? get dropZone => _strip._dropZone();

  @override
  bool accepts(TabTransfer payload) => _strip._accepts(payload);

  @override
  int slotAt(double x) => _strip._slotAt(x);

  @override
  void showDrop(TabTransfer payload, int slot) =>
      _strip._showIncoming(payload, slot);

  @override
  void clearDrop() => _strip._clearIncoming();

  @override
  bool drop(TabTransfer payload, int slot) => _strip._takeIn(payload, slot);
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
