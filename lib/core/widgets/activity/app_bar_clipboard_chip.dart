import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/services/cross_container_clipboard.dart';

/// MiXplorer-style clipboard action button designed for the top AppBar actions.
///
/// Features:
/// - Takes up minimal reserved space in the AppBar actions (title gets clipped cleanly).
/// - Displays a paste/cut icon with a badge indicating the item count.
/// - Tapping opens a popup dialog anchored directly beneath the icon.
/// - The popup displays detailed clipboard info (verb, source, item preview list)
///   along with immediate "Paste" and "Clear" action buttons close to finger reach.
class AppBarClipboardButton extends StatelessWidget {
  final VoidCallback? onPaste;

  const AppBarClipboardButton({super.key, this.onPaste});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ListenableBuilder(
      listenable: CrossContainerClipboard.instance,
      builder: (context, _) {
        final clip = CrossContainerClipboard.instance;
        if (!clip.hasItems) return const SizedBox.shrink();

        final verb = clip.isCutOperation
            ? context.l10n.clipboardVerbMove
            : context.l10n.clipboardVerbCopy;
        final count = clip.items.length;
        final source = clip.sourceDisplayName ?? context.l10n.clipboardDefaultSourceName;

        return Tooltip(
          message: onPaste != null
              ? context.l10n.clipboardTooltipInteractive(verb, count)
              : context.l10n.clipboardTooltipViewOnly(verb, count),
          triggerMode: TooltipTriggerMode.manual,
          child: PopupMenuButton<void>(
            offset: const Offset(0, 48), // Anchored directly beneath the AppBar action icon
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
                    clip.isCutOperation ? Icons.cut_rounded : Icons.content_paste_rounded,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
            itemBuilder: (popupContext) => [
            PopupMenuItem<void>(
              enabled: false, // Custom interactive layout inside menu
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: Verb + Icon
                    Row(
                      children: [
                        Icon(
                          clip.isCutOperation ? Icons.cut_rounded : Icons.copy_rounded,
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
                    const Divider(height: 16),
                    // Item list preview
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
                                    item.isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded,
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
                    // Action Buttons Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Navigator.of(popupContext).pop();
                            clip.clear();
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
                            child: Text(context.l10n.paste),
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
      },
    );
  }
}

/// Backwards compatibility alias for [AppBarClipboardButton].
typedef AppBarClipboardChip = AppBarClipboardButton;
