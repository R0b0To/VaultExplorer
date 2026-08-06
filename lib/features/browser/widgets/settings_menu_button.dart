import 'package:flutter/material.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_screen.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

/// App-bar settings button: a "Filters" submenu plus a link to the toolbar
/// settings screen.
///
/// Extracted verbatim from `FileBrowserScreen`'s private
/// `_buildSettingsMenuButton` (and the `_buildFilterMenuButton` helper it
/// exclusively called, five times, for the five filter options) -- third
/// slice of the `file_browser_screen.dart` decomposition
/// (docs/tech-debt.md TD-8). No behavior change, only a location change.
///
/// Unlike [SortMenuButton]/[LayoutModeMenuButton], this is a
/// [StatelessWidget]: the original `_buildSettingsMenuButton`'s `MenuAnchor`
/// had no `onOpen`/`onClose` handling at all, so there's no local
/// `_menuIsOpen`-style state to carry over.
class SettingsMenuButton extends StatelessWidget {
  final String? currentFilter;
  final ValueChanged<String?> onFilterChanged;

  /// Called after returning from [FileManagerToolbarSettingsScreen] --
  /// forwards to the parent's `_loadToolbarConfig()`, exactly as the
  /// original inline `onPressed` did.
  final Future<void> Function() onSettingsClosed;

  const SettingsMenuButton({
    super.key,
    required this.currentFilter,
    required this.onFilterChanged,
    required this.onSettingsClosed,
  });

  Widget _buildFilterMenuButton(
    String? value,
    String label,
    IconData icon,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final isActive = currentFilter == value;
    return MenuItemButton(
      onPressed: () => onFilterChanged(value),
      leadingIcon: Icon(
        icon,
        size: 16,
        color: isActive ? cs.primary : cs.onSurfaceVariant,
      ),
      trailingIcon: isActive
          ? Icon(Icons.check_rounded, size: 16, color: cs.primary)
          : null,
      child: Text(
        label,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return MenuAnchor(
      builder: (ctx, controller, child) => IconButton(
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
        icon: const Icon(Icons.settings_outlined),
        tooltip: context.l10n.settingsTooltipShort,
      ),
      menuChildren: [
        SubmenuButton(
          leadingIcon: Icon(Icons.filter_alt_outlined, color: cs.onSurfaceVariant),
          menuChildren: [
            _buildFilterMenuButton(null, context.l10n.filterAllFilesOption, Icons.all_inclusive_rounded, cs, textTheme),
            _buildFilterMenuButton('image', context.l10n.filterImagesOption, Icons.image_outlined, cs, textTheme),
            _buildFilterMenuButton('video', context.l10n.filterVideosOption, Icons.videocam_outlined, cs, textTheme),
            _buildFilterMenuButton('audio', context.l10n.filterAudioOption, Icons.audiotrack_rounded, cs, textTheme),
            _buildFilterMenuButton('document', context.l10n.filterDocumentsOption, Icons.description_outlined, cs, textTheme),
          ],
          child: Text(context.l10n.filtersMenuItem),
        ),
        const PopupMenuDivider(),
        MenuItemButton(
          leadingIcon: Icon(Icons.tune_rounded, color: cs.onSurfaceVariant),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FileManagerToolbarSettingsScreen()),
            );
            await onSettingsClosed();
          },
          child: Text(context.l10n.settingsMenuItem),
        ),
      ],
    );
  }
}