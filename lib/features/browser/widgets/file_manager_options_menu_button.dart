import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';

/// The quick options menu items, shared between [FileManagerOptionsMenuButton]'s
/// own MenuAnchor and any other cascade (e.g. the FAB toolbar's "More" menu)
/// that wants to embed the same choices as a [SubmenuButton]'s `menuChildren`.
List<Widget> buildOptionsMenuItems({
  required BuildContext context,
  required ColorScheme cs,
  required FileManagerToolbarConfig toolbarConfig,
  required ValueChanged<bool> onToggleShowHiddenFiles,
  required ValueChanged<bool> onToggleShowGridFileNames,
  required ValueChanged<bool> onToggleShowFileExtensions,
  required ValueChanged<bool> onToggleShowListThumbnails,
  required VoidCallback onOpenSettings,
}) {
  final l10n = context.l10n;

  Widget toggleItem({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return MenuItemButton(
      leadingIcon: Icon(
        icon,
        size: 20,
        color: value ? cs.primary : cs.onSurfaceVariant,
      ),
      trailingIcon: Icon(
        value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
        size: 20,
        color: value ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.6),
      ),
      closeOnActivate: false,
      onPressed: () => onChanged(!value),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: value ? FontWeight.w600 : FontWeight.normal,
          color: value ? cs.primary : null,
        ),
      ),
    );
  }

  return [
    toggleItem(
      icon: toolbarConfig.showHiddenFiles
          ? Icons.visibility_rounded
          : Icons.visibility_off_outlined,
      label: l10n.showHiddenFilesLabel,
      value: toolbarConfig.showHiddenFiles,
      onChanged: onToggleShowHiddenFiles,
    ),
    toggleItem(
      icon: Icons.title_rounded,
      label: l10n.showFileNamesLabel,
      value: toolbarConfig.showGridFileNames,
      onChanged: onToggleShowGridFileNames,
    ),
    toggleItem(
      icon: Icons.extension_outlined,
      label: l10n.showFileExtensionsLabel,
      value: toolbarConfig.showFileExtensions,
      onChanged: onToggleShowFileExtensions,
    ),
    toggleItem(
      icon: Icons.photo_outlined,
      label: l10n.showMediaThumbnailsLabel,
      value: toolbarConfig.showListThumbnails,
      onChanged: onToggleShowListThumbnails,
    ),
    const Divider(height: 1),
    MenuItemButton(
      leadingIcon: Icon(
        Icons.settings_outlined,
        size: 20,
        color: cs.onSurfaceVariant,
      ),
      trailingIcon: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: cs.onSurfaceVariant,
      ),
      onPressed: onOpenSettings,
      child: Text(l10n.fileManagerSettingsTitle),
    ),
  ];
}

/// App-bar / toolbar popup button for quick file manager options.
class FileManagerOptionsMenuButton extends StatefulWidget {
  final FileManagerToolbarConfig toolbarConfig;
  final ValueChanged<bool> onToggleShowHiddenFiles;
  final ValueChanged<bool> onToggleShowGridFileNames;
  final ValueChanged<bool> onToggleShowFileExtensions;
  final ValueChanged<bool> onToggleShowListThumbnails;
  final VoidCallback onOpenSettings;

  const FileManagerOptionsMenuButton({
    super.key,
    required this.toolbarConfig,
    required this.onToggleShowHiddenFiles,
    required this.onToggleShowGridFileNames,
    required this.onToggleShowFileExtensions,
    required this.onToggleShowListThumbnails,
    required this.onOpenSettings,
  });

  @override
  State<FileManagerOptionsMenuButton> createState() =>
      _FileManagerOptionsMenuButtonState();
}

class _FileManagerOptionsMenuButtonState
    extends State<FileManagerOptionsMenuButton> {
  final MenuController _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 4),
      menuChildren: buildOptionsMenuItems(
        context: context,
        cs: cs,
        toolbarConfig: widget.toolbarConfig,
        onToggleShowHiddenFiles: widget.onToggleShowHiddenFiles,
        onToggleShowGridFileNames: widget.onToggleShowGridFileNames,
        onToggleShowFileExtensions: widget.onToggleShowFileExtensions,
        onToggleShowListThumbnails: widget.onToggleShowListThumbnails,
        onOpenSettings: widget.onOpenSettings,
      ),
      builder: (context, controller, child) {
        return IconButton(
          icon: const Icon(Icons.more_vert_rounded),
          tooltip: l10n.optionsActionTooltip,
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
        );
      },
    );
  }
}
