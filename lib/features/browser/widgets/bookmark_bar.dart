import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';

class BookmarkBar extends StatelessWidget {
  final List<String> favouritePaths;
  final Axis axis;
  final ValueChanged<String> onTapItem;
  final ValueChanged<String> onRemoveFavourite;
  final bool Function(String path)? isDirectory;

  const BookmarkBar({
    super.key,
    required this.favouritePaths,
    this.axis = Axis.horizontal,
    required this.onTapItem,
    required this.onRemoveFavourite,
    this.isDirectory,
  });

  bool _isFolder(String path) {
    if (isDirectory != null) {
      return isDirectory!(path);
    }
    final leaf = path.split('/').last;
    return !leaf.contains('.') || path.endsWith('/');
  }

  @override
  Widget build(BuildContext context) {
    if (favouritePaths.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (axis == Axis.horizontal) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: favouritePaths.length,
          itemBuilder: (context, index) {
            final path = favouritePaths[index];
            final name = path.split('/').last;
            final isDir = _isFolder(path);
            final ext = name.contains('.') ? name.split('.').last : '';
            final icon = isDir
                ? Icons.folder_rounded
                : (vaultIconForExt(ext) ?? iconForFile(name));
            final iconColor = isDir
                ? cs.secondary
                : (vaultColorForExt(ext) ?? colorForFile(name));

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.full),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onTapItem(path),
                  onLongPress: () => _showItemMenu(context, path, name),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 16, color: iconColor),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: Text(
                            name,
                            style: textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              itemCount: favouritePaths.length,
              itemBuilder: (context, index) {
                final path = favouritePaths[index];
                final name = path.split('/').last;
                final isDir = _isFolder(path);
                final ext = name.contains('.') ? name.split('.').last : '';
                final icon = isDir
                    ? Icons.folder_rounded
                    : (vaultIconForExt(ext) ?? iconForFile(name));
                final iconColor = isDir
                    ? cs.secondary
                    : (vaultColorForExt(ext) ?? colorForFile(name));

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Tooltip(
                    message: path,
                    child: Material(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onTapItem(path),
                        onLongPress: () => _showItemMenu(context, path, name),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Row(
                            children: [
                              Icon(icon, size: 18, color: iconColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  name,
                                  style: textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showItemMenu(BuildContext context, String path, String name) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: Text(path, style: Theme.of(context).textTheme.bodySmall),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              onRemoveFavourite(path);
            },
            child: Text(context.l10n.removeFromFavourites),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              onTapItem(path);
            },
            child: Text(context.l10n.openWithAppAction.split(' ').first),
          ),
        ],
      ),
    );
  }
}