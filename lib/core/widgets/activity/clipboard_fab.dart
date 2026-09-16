import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';

class ClipboardFab extends ConsumerWidget {
  final VoidCallback? onPaste;
  final Object? heroTag;

  const ClipboardFab({
    super.key,
    this.onPaste,
    this.heroTag = 'clipboard_floating_action_button',
  });

  IconData _getActionIcon(ClipboardAction action) {
    switch (action) {
      case ClipboardAction.copy:
        return Icons.content_paste_rounded;
      case ClipboardAction.move:
        return Icons.content_cut_rounded;
      case ClipboardAction.archiveCreate:
        return Icons.archive_rounded;
      case ClipboardAction.archiveExtract:
        return Icons.unarchive_rounded;
    }
  }

  IconData _getHeaderIcon(ClipboardAction action) {
    switch (action) {
      case ClipboardAction.copy:
        return Icons.copy_rounded;
      case ClipboardAction.move:
        return Icons.cut_rounded;
      case ClipboardAction.archiveCreate:
        return Icons.archive_rounded;
      case ClipboardAction.archiveExtract:
        return Icons.unarchive_rounded;
    }
  }

  String _getVerb(BuildContext context, ClipboardAction action) {
    switch (action) {
      case ClipboardAction.copy:
        return context.l10n.clipboardVerbCopy;
      case ClipboardAction.move:
        return context.l10n.clipboardVerbMove;
      case ClipboardAction.archiveCreate:
        return context.l10n.verbArchive;
      case ClipboardAction.archiveExtract:
        return context.l10n.verbExtract;
    }
  }

  void _showDetailsSheet(BuildContext context, WidgetRef ref) {
    HapticFeedback.selectionClick();
    final clip = ref.read(crossContainerClipboardProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final verb = _getVerb(context, clip.action);
    final count = clip.items.length;
    final source = clip.sourceDisplayName ?? context.l10n.clipboardDefaultSourceName;

    final pasteButtonLabel = clip.isArchiveExtract
        ? context.l10n.extract
        : clip.isArchiveCreate
            ? context.l10n.create
            : context.l10n.paste;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => AppBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getHeaderIcon(clip.action),
                    size: AppIconSize.standard,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.clipboardHeaderCount(verb, count),
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        context.l10n.clipboardSourceLabel(source),
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (clip.archiveName != null) ...[
              const SizedBox(height: 8),
              Text(
                clip.archiveName!,
                style: textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const Divider(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: clip.items.length > 5 ? 5 : clip.items.length,
                itemBuilder: (context, index) {
                  final item = clip.items[index];
                  final parts = item.path.split('/');
                  final name = parts.isNotEmpty ? parts.last : item.path;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Icon(
                          item.isDir
                              ? Icons.folder_rounded
                              : (clip.isArchiveExtract
                                  ? Icons.archive_rounded
                                  : Icons.insert_drive_file_rounded),
                          size: AppIconSize.inline,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            name,
                            style: textTheme.bodyMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (clip.items.length > 5) ...[
              const SizedBox(height: 6),
              Text(
                context.l10n.clipboardMoreItems(clip.items.length - 5),
                style: textTheme.labelSmall?.copyWith(color: cs.outline),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    ref.read(crossContainerClipboardProvider.notifier).clear();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: cs.error,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(context.l10n.clear),
                ),
                if (onPaste != null) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      onPaste!();
                    },
                    icon: Icon(_getActionIcon(clip.action), size: 18),
                    label: Text(pasteButtonLabel),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clip = ref.watch(crossContainerClipboardProvider);
    if (!clip.hasItems) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final count = clip.items.length;
    final verb = _getVerb(context, clip.action);

    final isMove = clip.action == ClipboardAction.move;
    final backgroundColor = isMove ? cs.tertiaryContainer : cs.primaryContainer;
    final foregroundColor = isMove ? cs.onTertiaryContainer : cs.onPrimaryContainer;

    final tooltipMessage = onPaste != null
        ? '$verb ($count) — ${context.l10n.clipboardFabTapToPaste}'
        : context.l10n.clipboardTooltipViewOnly(verb, count);

    return Tooltip(
      message: tooltipMessage,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onLongPress: () => _showDetailsSheet(context, ref),
          customBorder: const CircleBorder(),
          child: FloatingActionButton(
            heroTag: heroTag,
            elevation: 4,
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            onPressed: () {
              if (onPaste != null) {
                HapticFeedback.mediumImpact();
                onPaste!();
              } else {
                _showDetailsSheet(context, ref);
              }
            },
            child: Badge(
              label: Text(
                '$count',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              backgroundColor: isMove ? cs.tertiary : cs.primary,
              textColor: isMove ? cs.onTertiary : cs.onPrimary,
              child: Icon(
                _getActionIcon(clip.action),
                size: 24,
              ),
            ),
          ),
        ),
      ),
    );
  }
}