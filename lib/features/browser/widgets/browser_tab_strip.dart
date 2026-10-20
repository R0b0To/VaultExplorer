import 'dart:async';

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

enum _TabMenuAction { close, closeOthers, closeToLeft, closeToRight, duplicate }

/// Height of the strip; matches the text editor's tab strip.
const double kBrowserTabStripHeight = 40;
const double kBrowserTabItemWidth = 148;

/// File-manager tab strip with a horizontally scrollable reorderable row of
/// tabs and a fixed new-tab button. Tapping switches tabs; tapping the active
/// tab opens its operation menu; long-press and drag reorder tabs. The tab
/// controller retains its horizontal offset while the strip moves between
/// screens.
class BrowserTabStrip extends ConsumerStatefulWidget {
  final BrowserTabsConfig workspaceConfig;
  final VoidCallback onNewTab;
  final ValueChanged<BrowserTabState> onDuplicate;
  final TabId? secondaryTabId;
  final String storageKey;

  const BrowserTabStrip({
    super.key,
    required this.workspaceConfig,
    required this.onNewTab,
    required this.onDuplicate,
    this.secondaryTabId,
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

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: ref
          .read(browserTabsProvider(widget.workspaceConfig))
          .tabStripScrollOffset,
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
    _scrollController.removeListener(_rememberScrollOffset);
    _scrollController.dispose();
    super.dispose();
  }

  void _rememberScrollOffset() {
    if (!_scrollController.hasClients) return;
    ref
        .read(browserTabsProvider(widget.workspaceConfig).notifier)
        .setTabStripScrollOffset(_scrollController.position.pixels);
  }

  void _scrollActiveIntoView({bool force = false}) {
    final state = ref.read(browserTabsProvider(widget.workspaceConfig));
    final active = state.activeTabId;
    final activeIndex = state.activeIndex;
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
          ref.read(browserTabsProvider(widget.workspaceConfig)).activeTabId !=
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
    final tabIndex = state.tabs.indexWhere((entry) => entry.tabId == tab.tabId);
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
          enabled: state.tabs.length > 1,
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
          enabled: tabIndex >= 0 && tabIndex < state.tabs.length - 1,
        ),
        const PopupMenuDivider(),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabsEnabled = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.useBrowserTabs),
    );
    if (!tabsEnabled) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final tabs = ref.watch(browserTabsListProvider(widget.workspaceConfig));
    final activeTab = ref.watch(
      activeBrowserTabProvider(widget.workspaceConfig),
    );
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
      decoration: BoxDecoration(
        color: stripBackground,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              key: PageStorageKey<String>(widget.storageKey),
              scrollController: _scrollController,
              itemExtent: kBrowserTabItemWidth,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.hardEdge,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
              itemCount: tabs.length,
              onReorderStart: (_) => HapticFeedback.mediumImpact(),
              onReorderItem: actions.reorderTabs,
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
                final isActive = tab.tabId == activeTab?.tabId;
                final isSecondary =
                    !isActive && tab.tabId == widget.secondaryTabId;
                return ReorderableDelayedDragStartListener(
                  key: ValueKey<TabId>(tab.tabId),
                  index: index,
                  child: Builder(
                    builder: (tabContext) => SizedBox(
                      key: itemKey,
                      width: kBrowserTabItemWidth,
                      child: _TabItem(
                        tab: tab,
                        active: isActive,
                        secondary: isSecondary,
                        activeBackground: activeBackground,
                        onTap: () => _onTabTapped(tab, tabContext),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 20),
            visualDensity: VisualDensity.compact,
            tooltip: context.l10n.browserTabNew,
            onPressed: widget.onNewTab,
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
  final bool secondary;
  final Color activeBackground;
  final VoidCallback onTap;

  const _TabItem({
    required this.tab,
    required this.active,
    required this.secondary,
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
    final secondaryBackground = cs.primary.withValues(alpha: 0.08);
    final fg = active
        ? cs.onSurface
        : secondary
        ? cs.primary
        : cs.onSurfaceVariant;

    return Tooltip(
      message: folderLabel == null ? name : '$name / $folderLabel',
      // Long-press belongs to ReorderableDelayedDragStartListener above this
      // tab. Letting Tooltip use its default long-press trigger consumes the
      // gesture and shows the label instead of starting a drag.
      triggerMode: TooltipTriggerMode.manual,
      child: Material(
        color: active
            ? activeBackground
            : secondary
            ? secondaryBackground
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? cs.primary.withValues(alpha: 0.5)
                    : secondary
                    ? cs.primary.withValues(alpha: 0.25)
                    : Colors.transparent,
                width: 1,
              ),
            ),
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
                      fontWeight: active
                          ? FontWeight.bold
                          : secondary
                          ? FontWeight.w600
                          : FontWeight.normal,
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
