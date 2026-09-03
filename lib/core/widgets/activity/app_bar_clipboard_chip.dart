import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';

class AppBarClipboardButton extends ConsumerWidget {
  final VoidCallback? onPaste;

  const AppBarClipboardButton({super.key, this.onPaste});

  IconData _getActionIcon(ClipboardAction action) {
    switch (action) {
      case ClipboardAction.copy:
        return Icons.content_paste_rounded;
      case ClipboardAction.move:
        return Icons.cut_rounded;
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final clip = ref.watch(crossContainerClipboardProvider);

    if (!clip.hasItems) return const SizedBox.shrink();

    final verb = _getVerb(context, clip.action);
    final count = clip.items.length;
    final source = clip.sourceDisplayName ?? context.l10n.clipboardDefaultSourceName;

    final pasteButtonLabel = clip.isArchiveExtract
        ? context.l10n.extract
        : clip.isArchiveCreate
            ? context.l10n.create
            : context.l10n.paste;

    return Tooltip(
      message: onPaste != null
          ? context.l10n.clipboardTooltipInteractive(verb, count)
          : context.l10n.clipboardTooltipViewOnly(verb, count),
      triggerMode: TooltipTriggerMode.manual,
      child: PopupMenuButton<void>(
        offset: const Offset(0, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        color: cs.surfaceContainerHigh,
        elevation: 6,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: onPaste != null
              ? () {
                  Feedback.forLongPress(context);
                  onPaste!();
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Badge(
              label: Text(
                '$count',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
              ),
              backgroundColor: cs.primary,
              textColor: cs.onPrimary,
              child: Icon(
                _getActionIcon(clip.action),
                color: cs.primary,
              ),
            ),
          ),
        ),
        itemBuilder: (popupContext) => [
          PopupMenuItem<void>(
            enabled: false,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 280),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _getHeaderIcon(clip.action),
                        size: AppIconSize.standard,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.clipboardHeaderCount(verb, count),
                          style: textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    context.l10n.clipboardSourceLabel(source),
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (clip.archiveName != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      clip.archiveName!,
                      style: textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const Divider(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 120),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: clip.items.take(4).map((item) {
                          final parts = item.path.split('/');
                          final name = parts.isNotEmpty ? parts.last : item.path;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
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
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: textTheme.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  if (clip.items.length > 4) ...[
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.clipboardMoreItems(clip.items.length - 4),
                      style: textTheme.labelSmall?.copyWith(color: cs.outline),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(popupContext).pop();
                          ref.read(crossContainerClipboardProvider.notifier).clear();
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: cs.error,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(context.l10n.clear),
                      ),
                      if (onPaste != null) ...[
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            Navigator.of(popupContext).pop();
                            onPaste!();
                          },
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(pasteButtonLabel),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef AppBarClipboardChip = AppBarClipboardButton;