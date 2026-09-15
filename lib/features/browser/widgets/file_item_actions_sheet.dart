import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

class FileItemActionsSheet extends StatelessWidget {
  final RawEntry entry;
  final MountedContainer container;
  final String currentDirPath;
  final bool isReadOnly;
  final bool isPinned;
  final bool isBookmark;
  final bool isDocumentProviderMounted;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final VoidCallback onCut;
  final VoidCallback onTogglePin;
  final VoidCallback onToggleBookmark;
  final VoidCallback onInfo;
  final VoidCallback? onOpenWith;
  final VoidCallback? onShare;
  final VoidCallback? onEditImage;
  final VoidCallback? onToggleDocProvider;

  const FileItemActionsSheet({
    super.key,
    required this.entry,
    required this.container,
    required this.currentDirPath,
    required this.isReadOnly,
    required this.isPinned,
    required this.isBookmark,
    this.isDocumentProviderMounted = false,
    required this.onRename,
    required this.onDelete,
    required this.onCopy,
    required this.onCut,
    required this.onTogglePin,
    required this.onToggleBookmark,
    required this.onInfo,
    this.onOpenWith,
    this.onShare,
    this.onEditImage,
    this.onToggleDocProvider,
  });

  static Future<void> show(
    BuildContext context, {
    required RawEntry entry,
    required MountedContainer container,
    required String currentDirPath,
    required bool isReadOnly,
    required bool isPinned,
    required bool isBookmark,
    bool isDocumentProviderMounted = false,
    required VoidCallback onRename,
    required VoidCallback onDelete,
    required VoidCallback onCopy,
    required VoidCallback onCut,
    required VoidCallback onTogglePin,
    required VoidCallback onToggleBookmark,
    required VoidCallback onInfo,
    VoidCallback? onOpenWith,
    VoidCallback? onShare,
    VoidCallback? onEditImage,
    VoidCallback? onToggleDocProvider,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => FileItemActionsSheet(
        entry: entry,
        container: container,
        currentDirPath: currentDirPath,
        isReadOnly: isReadOnly,
        isPinned: isPinned,
        isBookmark: isBookmark,
        isDocumentProviderMounted: isDocumentProviderMounted,
        onRename: onRename,
        onDelete: onDelete,
        onCopy: onCopy,
        onCut: onCut,
        onTogglePin: onTogglePin,
        onToggleBookmark: onToggleBookmark,
        onInfo: onInfo,
        onOpenWith: onOpenWith,
        onShare: onShare,
        onEditImage: onEditImage,
        onToggleDocProvider: onToggleDocProvider,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final isDir = entry.isDir;
    final ext = isDir ? '' : (entry.name.contains('.') ? entry.name.split('.').last : '');
    final icon = isDir
        ? (isDocumentProviderMounted ? Icons.folder_shared_rounded : Icons.folder_rounded)
        : (vaultIconForExt(ext) ?? iconForFile(entry.name));
    final iconColor = isDir
        ? (isDocumentProviderMounted ? cs.tertiary : cs.secondary)
        : (vaultColorForExt(ext) ?? colorForFile(entry.name));

    final subtitleParts = <String>[
      if (!isDir) formatBytes(entry.sizeBytes),
      if (entry.modifiedSecs > 0) formatEntryDate(entry.modifiedSecs),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header: Icon + Filename + Meta
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (subtitleParts.isNotEmpty)
                          Text(
                            subtitleParts.join('    '),
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),

            // Actions list
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onOpenWith != null)
                      _ActionTile(
                        icon: Icons.open_in_new_rounded,
                        label: context.l10n.openWithAppAction,
                        onTap: () {
                          Navigator.pop(context);
                          onOpenWith!();
                        },
                      ),
                    if (onShare != null)
                      _ActionTile(
                        icon: Icons.share_rounded,
                        label: context.l10n.shareAction,
                        onTap: () {
                          Navigator.pop(context);
                          onShare!();
                        },
                      ),
                    if (onEditImage != null)
                      _ActionTile(
                        icon: Icons.edit_outlined,
                        label: context.l10n.editImageAction,
                        enabled: !isReadOnly,
                        onTap: () {
                          Navigator.pop(context);
                          onEditImage!();
                        },
                      ),
                    _ActionTile(
                      icon: Icons.drive_file_rename_outline_rounded,
                      label: context.l10n.renameAction,
                      enabled: !isReadOnly,
                      onTap: () {
                        Navigator.pop(context);
                        onRename();
                      },
                    ),
                    _ActionTile(
                      icon: Icons.copy_rounded,
                      label: context.l10n.copyAction,
                      onTap: () {
                        Navigator.pop(context);
                        onCopy();
                      },
                    ),
                    _ActionTile(
                      icon: Icons.cut_rounded,
                      label: context.l10n.moveAction,
                      enabled: !isReadOnly,
                      onTap: () {
                        Navigator.pop(context);
                        onCut();
                      },
                    ),
                    _ActionTile(
                      icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                      label: isPinned ? context.l10n.unpinAction : context.l10n.pinAction,
                      onTap: () {
                        Navigator.pop(context);
                        onTogglePin();
                      },
                    ),
                    _ActionTile(
                      icon: isBookmark ? Icons.star_outline_rounded : Icons.star_rounded,
                      label: isBookmark ? context.l10n.unbookmarkAction : context.l10n.bookmarkAction,
                      onTap: () {
                        Navigator.pop(context);
                        onToggleBookmark();
                      },
                    ),
                    if (onToggleDocProvider != null)
                      _ActionTile(
                        icon: isDocumentProviderMounted
                            ? Icons.folder_shared_rounded
                            : Icons.folder_shared_outlined,
                        label: isDocumentProviderMounted
                            ? context.l10n.documentProviderSettingsMenu
                            : context.l10n.exposeAsDocumentProviderMenu,
                        onTap: () {
                          Navigator.pop(context);
                          onToggleDocProvider!();
                        },
                      ),
                    _ActionTile(
                      icon: Icons.info_outline_rounded,
                      label: context.l10n.fileInfoAction,
                      onTap: () {
                        Navigator.pop(context);
                        onInfo();
                      },
                    ),
                    _ActionTile(
                      icon: Icons.delete_outline_rounded,
                      label: context.l10n.delete,
                      color: cs.error,
                      enabled: !isReadOnly,
                      onTap: () {
                        Navigator.pop(context);
                        onDelete();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool enabled;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = enabled
        ? (color ?? cs.onSurface)
        : cs.onSurfaceVariant.withValues(alpha: 0.38);

    return ListTile(
      dense: true,
      leading: Icon(icon, color: effectiveColor, size: 22),
      title: Text(
        label,
        style: TextStyle(
          color: effectiveColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      enabled: enabled,
      onTap: enabled ? onTap : null,
    );
  }
}