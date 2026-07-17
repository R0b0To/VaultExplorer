import 'package:flutter/material.dart';
import '../../../theme.dart';

/// Warning strip shown above the file list/grid when a folder's listing was
/// capped (see [FileBrowserScreen._isListingTruncated]).
class TruncatedBanner extends StatelessWidget {
  const TruncatedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: cs.tertiaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, size: AppIconSize.small, color: cs.onTertiaryContainer),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Showing first 50,000 items — this folder has more files.',
            style: textTheme.bodySmall?.copyWith(
              color: cs.onTertiaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ]),
    );
  }
}