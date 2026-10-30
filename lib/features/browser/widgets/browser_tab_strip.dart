import 'dart:async';

import 'package:flutter/gestures.dart' show PointerMoveEvent;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_provider.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drag.dart';
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
      return Icon(Icons.sd_card_rounded, size: size, color: color);
    }
    if (container.isLocalStorage) {
      return Icon(Icons.phone_android_rounded, size: size, color: color);
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
/// tabs and a fixed new-tab button. Tapping switches tabs; tapping the active
/// tab opens its operation menu; long-press and drag reorder tabs. The tab
/// controller retains its horizontal offset while the strip moves between
/// screens.
///
/// With a [pane] the strip belongs to that pane in the dual-pane layout: it
/// lists only the pane's own tabs, switching a tab changes only that pane, the
/// new-tab button opens a tab in it, and its bottom edge marks whether the pane
/// has focus. Without one it is the single strip over all tabs.
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

  const BrowserTabStrip({
    super.key,
    required this.workspaceConfig,
    required this.onNewTab,
    required this.onDuplicate,
    this.pane,
    this.paneBounds,
    this.onDragOverPane,
    this.storageKey = 'browser-tab-strip-scroll-position',
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
  Timer? _fileDropHoverTimer;
  TabId? _fileDropHoverTabId;

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

  /// Follows the finger of a tab drag. The reorder list only moves the tab
  /// within this strip; the finger itself may be over the other pane, which is
  /// what a drop there is decided by.
  void _trackDrag(PointerMoveEvent event) {
    final pane = widget.pane;
    if (_draggingTabId == null || pane == null) return;
    final other = pane.other;
    final bounds = widget.paneBounds?.call(other);
    final over = bounds != null && bounds.contains(event.position)
        ? other
        : null;
    if (over == _hoverPane) return;
    _hoverPane = over;
    widget.onDragOverPane?.call(over);
  }

  void _finishDrag(BrowserTabs actions) {
    final id = _draggingTabId;
    final target = _hoverPane;
    _draggingTabId = null;
    if (target != null) {
      _hoverPane = null;
      widget.onDragOverPane?.call(null);
    }
    if (id == null || target == null) return;
    // After the list has settled its drop: moving the tab changes both strips.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      actions.moveToPane(id, target);
    });
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
      final itemContext = _tabItemKeys[active]?.currentContext;
      if (itemContext == null) return;
      Scrollable.ensureVisible(
        itemContext,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
      );
    });
  }

  void _onTabTapped(BrowserTabState tab, BuildContext tabContext) {
    final state = ref.read(browserTabsProvider(widget.workspaceConfig));
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
          enabled: state.tabs.length > 1,
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
          enabled: !tab.isDashboard && !state.atLimit,
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
        actions.closeTab(tab.tabId);
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
    final actions = ref.read(
      browserTabsProvider(widget.workspaceConfig).notifier,
    );
    final liveTabIds = tabs.map((tab) => tab.tabId).toSet();
    _tabItemKeys.removeWhere((id, _) => !liveTabIds.contains(id));
    _scrollActiveIntoView();

    final stripBackground = cs.surfaceContainer;
    final activeBackground = cs.surfaceContainerHighest;

    return Container(
      height: kBrowserTabStripHeight,
      color: stripBackground,
      child: Row(
        children: [
          Expanded(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerMove: _trackDrag,
              child: ReorderableListView.builder(
                key: PageStorageKey<String>(
                  '${widget.storageKey}-${pane?.name ?? 'all'}',
                ),
                scrollController: _scrollController,
                itemExtent: kBrowserTabItemWidth,
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.hardEdge,
                buildDefaultDragHandles: false,
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
                itemCount: tabs.length,
                onReorderStart: (index) {
                  HapticFeedback.mediumImpact();
                  _draggingTabId = index >= 0 && index < tabs.length
                      ? tabs[index].tabId
                      : null;
                },
                onReorderEnd: (_) => _finishDrag(actions),
                onReorderItem: pane == null
                    ? actions.reorderTabs
                    : (oldIndex, newIndex) =>
                          actions.reorderTabsInPane(pane, oldIndex, newIndex),
                proxyDecorator: (child, index, animation) {
                  return AnimatedBuilder(
                    animation: animation,
                    builder: (context, child) {
                      final t = Curves.easeInOut.transform(animation.value);
                      return Material(
                        elevation: 6 * t,
                        color: activeBackground,
                        shadowColor: cs.shadow.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        child: child,
                      );
                    },
                    child: child,
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
                  return ReorderableDelayedDragStartListener(
                    key: ValueKey<TabId>(tab.tabId),
                    index: index,
                    child: Builder(
                      builder: (tabContext) => SizedBox(
                        key: itemKey,
                        width: kBrowserTabItemWidth,
                        child: DragTarget<BrowserItemDragData>(
                          onWillAcceptWithDetails: (details) {
                            final destination = tab.container;
                            if (destination == null || tab.isDashboard) {
                              return false;
                            }
                            final navigation = ref.read(
                              fileBrowserNavigationProvider(tab.tabId),
                            );
                            if (navigation.archiveContext != null) {
                              return false;
                            }
                            final path = navigation.currentDirPath;
                            if (!details.data.canDropInto(destination, path)) {
                              return false;
                            }
                            _scheduleFileDropTabActivation(tab, actions);
                            return true;
                          },
                          onMove: (_) =>
                              _scheduleFileDropTabActivation(tab, actions),
                          onLeave: (_) =>
                              _cancelFileDropTabActivation(tab.tabId),
                          onAcceptWithDetails: (details) {
                            _cancelFileDropTabActivation(tab.tabId);
                            final destination = tab.container;
                            if (destination == null || tab.isDashboard) return;
                            actions.activate(tab.tabId);
                            final navigation = ref.read(
                              fileBrowserNavigationProvider(tab.tabId),
                            );
                            if (navigation.archiveContext != null) return;
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
                          builder: (context, candidates, rejected) =>
                              DecoratedBox(
                                decoration: candidates.isEmpty
                                    ? const BoxDecoration()
                                    : BoxDecoration(
                                        border: Border.all(
                                          color: cs.primary,
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                child: _TabItem(
                                  tab: tab,
                                  active: isActive,
                                  activeBackground: activeBackground,
                                  onTap: () => _onTabTapped(tab, tabContext),
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
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 20),
            visualDensity: VisualDensity.compact,
            tooltip: context.l10n.browserTabNew,
            onPressed: () {
              // The new tab joins the pane whose + was pressed.
              if (pane != null) actions.focusPane(pane);
              widget.onNewTab();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _TabItem extends ConsumerWidget {
  final BrowserTabState tab;
  final bool active;
  final Color activeBackground;
  final VoidCallback onTap;

  const _TabItem({
    required this.tab,
    required this.active,
    required this.activeBackground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    // Folder name once the tab has navigated into a directory, otherwise the
    // vault / storage name. Watching only this derived string keeps the tab
    // from rebuilding on every directory-listing or selection change.
    final folderLabel = tab.isDashboard
        ? null
        : ref.watch(
            fileBrowserNavigationProvider(tab.tabId).select(
              (s) => s.pathStack.length <= 1 ? null : s.pathStack.last.label,
            ),
          );
    // Items selected in this tab. Selections in different tabs add up when
    // the user copies / cuts, so each tab shows what it is contributing.
    final selectedCount = tab.isDashboard
        ? 0
        : ref.watch(
            fileBrowserSelectionProvider(
              tab.tabId,
            ).select((s) => s.items.length),
          );
    final name = tab.container?.displayName ?? context.l10n.dashboardNavLabel;
    final label = folderLabel ?? name;
    final fg = active ? cs.onSurface : cs.onSurfaceVariant;

    return Tooltip(
      message: folderLabel == null ? name : '$name / $folderLabel',
      // Long-press belongs to ReorderableDelayedDragStartListener above this
      // tab. Letting Tooltip use its default long-press trigger consumes the
      // gesture and shows the label instead of starting a drag.
      triggerMode: TooltipTriggerMode.manual,
      child: Material(
        color: active ? activeBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectedCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: cs.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$selectedCount',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimary,
                      ),
                    ),
                  ),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
