import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';

/// The folder/file count + free-space summary shown above the file
/// list/grid (horizontal strip in portrait, a vertical sidebar panel in
/// landscape via [isVertical]).
class StatsBar extends StatelessWidget {
  final int dirCount;
  final int fileCount;
  final int freeSpaceBytes;
  final bool isFiltered;
  final bool isVertical;

  const StatsBar({
    super.key,
    required this.dirCount,
    required this.fileCount,
    required this.freeSpaceBytes,
    this.isFiltered = false,
    this.isVertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (isVertical) {
      return Container(
        color: cs.surfaceContainerLow,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'STORAGE',
              style: textTheme.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            _stat(context, Icons.folder_rounded, '$dirCount folders'),
            const SizedBox(height: 8),
            _stat(context, Icons.description_rounded, '$fileCount files'),
            const SizedBox(height: 8),
            _stat(context, Icons.storage_rounded, '${formatBytes(freeSpaceBytes)} free'),
            if (isFiltered) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  'filtered',
                  style: textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      color: cs.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          _stat(context, Icons.folder_rounded, '$dirCount folders'),
          const SizedBox(width: 12),
          _stat(context, Icons.description_rounded, '$fileCount files'),
          const Spacer(),
          if (isFiltered) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Text(
                'filtered',
                style: textTheme.labelSmall?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          _stat(context, Icons.storage_rounded, '${formatBytes(freeSpaceBytes)} free'),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppIconSize.inline, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(text, style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}
