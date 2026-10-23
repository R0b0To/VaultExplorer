import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';

class BookmarkBar extends StatelessWidget {
  final List<VaultBookmark> bookmarks;
  final Axis axis;
  final ValueChanged<VaultBookmark> onTapItem;
  final ValueChanged<VaultBookmark> onRemoveBookmark;

  const BookmarkBar({
    super.key,
    required this.bookmarks,
    this.axis = Axis.horizontal,
    required this.onTapItem,
    required this.onRemoveBookmark,
  });

  @override
  Widget build(BuildContext context) {
    if (bookmarks.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final skin = FileManagerSkinScope.of(context);

    if (axis == Axis.horizontal) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          itemCount: bookmarks.length,
          itemBuilder: (context, index) {
            final bookmark = bookmarks[index];
            final name = bookmark.name;
            final isDir = bookmark.isDir;
            final icon = isDir ? skin.folderIcon : skin.fileIcon(name);
            final iconColor = isDir
                ? skin.folderIconColor(cs)
                : skin.fileIconColor(cs, name);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Material(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.full),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onTapItem(bookmark),
                  onLongPress: () => _showItemMenu(context, bookmark),
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              itemCount: bookmarks.length,
              itemBuilder: (context, index) {
                final bookmark = bookmarks[index];
                final name = bookmark.name;
                final isDir = bookmark.isDir;
                final icon = isDir ? skin.folderIcon : skin.fileIcon(name);
                final iconColor = isDir
                    ? skin.folderIconColor(cs)
                    : skin.fileIconColor(cs, name);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Tooltip(
                    message: bookmark.path,
                    child: Material(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => onTapItem(bookmark),
                        onLongPress: () => _showItemMenu(context, bookmark),
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

  void _showItemMenu(BuildContext context, VaultBookmark bookmark) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(
          bookmark.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        content: Text(
          bookmark.path,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              onRemoveBookmark(bookmark);
            },
            child: Text(context.l10n.removeFromBookmarks),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              onTapItem(bookmark);
            },
            child: Text(context.l10n.openAction),
          ),
        ],
      ),
    );
  }
}