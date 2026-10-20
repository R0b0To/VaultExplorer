import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_selection_controller.dart';
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
  final BrowserTabsController controller;
  final VoidCallback onNewTab;
  final ValueChanged<BrowserTab> onDuplicate;
  final ValueChanged<BrowserTab>? onActivateTab;
  final String storageKey;

  const BrowserTabStrip({
    super.key,
    required this.controller,
    required this.onNewTab,
    required this.onDuplicate,
    this.onActivateTab,
    this.storageKey = 'browser-tab-strip-scroll-position',
  });

  @override
  ConsumerState<BrowserTabStrip> createState() => _BrowserTabStripState();
}

class _BrowserTabStripState extends ConsumerState<BrowserTabStrip> {
  late final ScrollController _scrollController;
  final Map<int, GlobalKey> _tabItemKeys = {};
  int? _lastActiveKey;
  int? _lastActiveIndex;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController(
      initialScrollOffset: widget.controller.tabStripScrollOffset,
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
    widget.controller.setTabStripScrollOffset(
      _scrollController.position.pixels,
    );
  }

  void _scrollActiveIntoView({bool force = false}) {
    final active = widget.controller.activeKey;
    final activeIndex = widget.controller.activeIndex;
    if (!force && active == _lastActiveKey && activeIndex == _lastActiveIndex) {
      return;
    }
    _lastActiveKey = active;
    _lastActiveIndex = activeIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_scrollController.hasClients ||
          widget.controller.activeKey != active) {
        return;
      }
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

  void _onTabTapped(BrowserTab tab, BuildContext tabContext) {
    final c = widget.controller;
    if (c.activeKey == tab.key) {
      unawaited(_showTabMenu(tab, tabContext));
      return;
    }
    final onActivateTab = widget.onActivateTab;
    if (onActivateTab != null) {
      onActivateTab(tab);
    } else {
      c.activate(tab.key);
    }
  }

  Future<void> _showTabMenu(BrowserTab tab, BuildContext tabContext) async {
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

    final c = widget.controller;
    final l10n = tabContext.l10n;
    final tabIndex = c.tabs.indexWhere((entry) => entry.key == tab.key);
    final choice = await showMenu<_TabMenuAction>(
      context: tabContext,
      position: RelativeRect.fromRect(anchor, Offset.zero & overlayBox.size),
      items: [
        item(
          _TabMenuAction.close,
          Icons.close_rounded,
          l10n.browserTabClose,
          enabled: c.length > 1,
        ),
        item(
          _TabMenuAction.closeOthers,
          Icons.tab_unselected_rounded,
          l10n.browserTabCloseOthers,
          enabled: c.length > 1,
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
          enabled: tabIndex >= 0 && tabIndex < c.length - 1,
        ),
        const PopupMenuDivider(),
        item(
          _TabMenuAction.duplicate,
          Icons.copy_all_rounded,
          l10n.browserTabDuplicate,
          enabled: tab.isDashboard || !c.atLimit,
        ),
      ],
    );
    if (!mounted || choice == null || c.tabForKey(tab.key) == null) return;

    switch (choice) {
      case _TabMenuAction.close:
        c.closeTab(tab.key);
      case _TabMenuAction.closeOthers:
        c.closeOthers(tab.key);
      case _TabMenuAction.closeToLeft:
        c.closeToLeft(tab.key);
      case _TabMenuAction.closeToRight:
        c.closeToRight(tab.key);
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
    final c = widget.controller;

    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final tabs = c.tabs;
        final liveTabKeys = tabs.map((tab) => tab.key).toSet();
        _tabItemKeys.removeWhere((key, _) => !liveTabKeys.contains(key));
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 3,
                  ),
                  itemCount: tabs.length,
                  onReorderStart: (_) => HapticFeedback.mediumImpact(),
                  onReorderItem: c.moveTab,
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
                      tab.key,
                      GlobalKey.new,
                    );
                    final isActive = tab.key == c.activeKey;
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey<int>(tab.key),
                      index: index,
                      child: Builder(
                        builder: (tabContext) => SizedBox(
                          key: itemKey,
                          width: kBrowserTabItemWidth,
                          child: _TabItem(
                            tab: tab,
                            active: isActive,
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
      },
    );
  }
}

class _TabItem extends ConsumerWidget {
  final BrowserTab tab;
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
            fileBrowserNavigationProvider(tab.key).select(
              (s) => s.pathStack.length <= 1 ? null : s.pathStack.last.label,
            ),
          );
    // Items selected in this tab. Selections in different tabs add up when
    // the user copies / cuts, so each tab shows what it is contributing.
    final selectedCount = tab.isDashboard
        ? 0
        : ref.watch(
            fileBrowserSelectionProvider(tab.key).select((s) => s.items.length),
          );
    final name = tab.container?.displayName ?? context.l10n.dashboardNavLabel;
    final label = folderLabel ?? name;
    final fg = active ? cs.onSurface : cs.onSurfaceVariant;

    return Tooltip(
      message: folderLabel == null ? name : '$name / $folderLabel',
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
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? cs.primary.withValues(alpha: 0.5)
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
