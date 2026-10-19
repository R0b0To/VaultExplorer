import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_tabs_controller.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';

/// Leading icon for a tab / location row: the vault's format initials, or a
/// phone / SD-card glyph for on-device storage.
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

/// Horizontal strip of file-manager tabs shown above the browser toolbar when
/// more than one tab is open. Tapping a tab activates it, the trailing buttons
/// flip to the previously used tab and open a new one, and a long-press opens
/// a small menu (duplicate / close / close others).
class BrowserTabStrip extends ConsumerStatefulWidget {
  final BrowserTabsController controller;
  final VoidCallback onNewTab;
  final ValueChanged<BrowserTab> onDuplicate;

  /// Shorter strip for landscape, where vertical space is scarce.
  final bool compact;

  const BrowserTabStrip({
    super.key,
    required this.controller,
    required this.onNewTab,
    required this.onDuplicate,
    this.compact = false,
  });

  @override
  ConsumerState<BrowserTabStrip> createState() => _BrowserTabStripState();
}

class _BrowserTabStripState extends ConsumerState<BrowserTabStrip> {
  final Map<int, GlobalKey> _chipKeys = {};
  int? _lastActiveKey;

  GlobalKey _keyFor(int tabKey) =>
      _chipKeys.putIfAbsent(tabKey, () => GlobalKey());

  @override
  void didUpdateWidget(covariant BrowserTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scrollActiveIntoView();
  }

  @override
  void initState() {
    super.initState();
    _scrollActiveIntoView();
  }

  void _scrollActiveIntoView() {
    final active = widget.controller.activeKey;
    if (active == _lastActiveKey) return;
    _lastActiveKey = active;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[active]?.currentContext;
      if (ctx == null || !ctx.mounted) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 180),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  Future<void> _showTabMenu(BuildContext chipContext, BrowserTab tab) async {
    final box = chipContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(chipContext).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );
    final l10n = chipContext.l10n;
    final c = widget.controller;
    final choice = await showMenu<String>(
      context: chipContext,
      position: position,
      items: [
        if (!c.atLimit)
          PopupMenuItem<String>(
            value: 'duplicate',
            child: Text(l10n.browserTabDuplicate),
          ),
        PopupMenuItem<String>(
          value: 'close',
          child: Text(l10n.browserTabClose),
        ),
        if (c.hasMultiple)
          PopupMenuItem<String>(
            value: 'others',
            child: Text(l10n.browserTabCloseOthers),
          ),
      ],
    );
    switch (choice) {
      case 'duplicate':
        widget.onDuplicate(tab);
      case 'close':
        c.closeTab(tab.key);
      case 'others':
        c.closeOthers(tab.key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = widget.controller;
    final tabs = c.tabs;
    _chipKeys.removeWhere((k, _) => !tabs.any((t) => t.key == k));

    return Material(
      color: cs.surfaceContainerLow,
      child: SizedBox(
        height: widget.compact ? 38 : 44,
        child: Row(
          children: [
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: widget.compact ? 3 : 6,
                ),
                itemCount: tabs.length,
                separatorBuilder: (context, index) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final tab = tabs[i];
                  return _TabChip(
                    key: _keyFor(tab.key),
                    tab: tab,
                    active: tab.key == c.activeKey,
                    onTap: () => c.activate(tab.key),
                    onClose: () => c.closeTab(tab.key),
                    onLongPress: (chipContext) => _showTabMenu(chipContext, tab),
                  );
                },
              ),
            ),
            IconButton(
              tooltip: context.l10n.browserTabSwitchPrevious,
              icon: const Icon(Icons.swap_horiz_rounded),
              visualDensity: VisualDensity.compact,
              onPressed: c.hasMultiple ? c.swapToPrevious : null,
            ),
            IconButton(
              tooltip: context.l10n.browserTabNew,
              icon: const Icon(Icons.add_rounded),
              visualDensity: VisualDensity.compact,
              onPressed: widget.onNewTab,
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends ConsumerWidget {
  final BrowserTab tab;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final void Function(BuildContext chipContext) onLongPress;

  const _TabChip({
    super.key,
    required this.tab,
    required this.active,
    required this.onTap,
    required this.onClose,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Folder name once the tab has navigated into a directory, otherwise the
    // vault / storage name. Watching only this derived string keeps the chip
    // from rebuilding on every directory-listing or selection change.
    final folderLabel = ref.watch(
      fileBrowserNavigationProvider(tab.key).select(
        (s) => s.pathStack.length <= 1 ? null : s.pathStack.last.label,
      ),
    );
    final name = tab.container.displayName;
    final label = folderLabel ?? name;

    final fg = active ? cs.onSecondaryContainer : cs.onSurfaceVariant;

    return Tooltip(
      message: folderLabel == null ? name : '$name / $folderLabel',
      child: Material(
        color: active ? cs.secondaryContainer : Colors.transparent,
        shape: StadiumBorder(
          side: active
              ? BorderSide.none
              : BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Builder(
          builder: (chipContext) => InkWell(
            onTap: onTap,
            onLongPress: () => onLongPress(chipContext),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200, minWidth: 72),
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    BrowserLocationIcon(container: tab.container, color: fg),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelLarge?.copyWith(
                          color: fg,
                          fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    InkResponse(
                      onTap: onClose,
                      radius: 16,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(Icons.close_rounded, size: 16, color: fg),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
