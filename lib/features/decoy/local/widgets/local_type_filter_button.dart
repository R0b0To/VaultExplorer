import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

enum LocalTypeFilter { all, image, video, audio, document }

/// App-bar popup button for filtering the current folder's contents by
/// type. Deliberately its own (small) widget rather than a reuse of the
/// vault file manager's `FilterMenuButton`: that one also offers a
/// "secure" category for the single-file-crypto tool, which has no
/// business appearing in a decoy that must never surface vault vocabulary.
class LocalTypeFilterButton extends StatelessWidget {
  final LocalTypeFilter value;
  final ValueChanged<LocalTypeFilter> onChanged;

  const LocalTypeFilterButton({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final options = <(LocalTypeFilter, String, IconData)>[
      (LocalTypeFilter.all, l10n.filesFilterAll, Icons.apps_rounded),
      (LocalTypeFilter.image, l10n.filesFilterImages, Icons.image_outlined),
      (LocalTypeFilter.video, l10n.filesFilterVideos, Icons.movie_outlined),
      (LocalTypeFilter.audio, l10n.filesFilterAudio, Icons.audiotrack_outlined),
      (LocalTypeFilter.document, l10n.filesFilterDocuments, Icons.description_outlined),
    ];
    return MenuAnchor(
      builder: (context, controller, child) => IconButton(
        icon: Icon(
          value == LocalTypeFilter.all ? Icons.filter_list_rounded : Icons.filter_alt_rounded,
          color: value == LocalTypeFilter.all ? null : cs.primary,
        ),
        tooltip: l10n.filesFilterTooltip,
        onPressed: () => controller.isOpen ? controller.close() : controller.open(),
      ),
      menuChildren: [
        for (final (mode, label, icon) in options)
          MenuItemButton(
            leadingIcon: Icon(icon, color: value == mode ? cs.primary : cs.onSurfaceVariant),
            trailingIcon: value == mode ? Icon(Icons.check_rounded, size: 16, color: cs.primary) : null,
            onPressed: () => onChanged(mode),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: value == mode ? FontWeight.bold : FontWeight.normal,
                color: value == mode ? cs.primary : null,
              ),
            ),
          ),
      ],
    );
  }
}
