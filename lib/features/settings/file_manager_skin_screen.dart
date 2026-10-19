import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/core/theme/app_skin_tokens.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/file_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/grid_card_shell.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/features/settings/widgets/app_skin_shortcut_tile.dart';
import 'package:vaultexplorer/features/settings/widgets/skin_color_picker_sheet.dart';

/// Where the person chooses how the file manager looks: a built-in skin, or
/// individual icon, background and text-color options.
///
/// Reads and writes the skin through the same
/// [FileManagerToolbarSettings] controller as the rest of File Manager
/// Settings, so an open file manager behind this screen updates as choices are
/// made.
class FileManagerSkinScreen extends ConsumerWidget {
  final String? containerUri;
  final bool showAppSkinShortcut;

  const FileManagerSkinScreen({
    super.key,
    this.containerUri,
    this.showAppSkinShortcut = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(fileManagerToolbarSettingsProvider(containerUri));
    final notifier = ref.read(
      fileManagerToolbarSettingsProvider(containerUri).notifier,
    );
    final appSkinSettings = ref.watch(appSkinSettingsProvider);
    final followsAppSkin = appSkinSettings.fileManagerFollowsAppSkin;
    final activeSkinTokens = Theme.of(context).extension<AppSkinTokens>();
    final skin = followsAppSkin
        ? activeSkinTokens?.fileManagerSkin ?? state.config.skin
        : state.config.skin;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.fileSkinScreenTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: l10n.resetToDefaultsTooltip,
            onPressed: state.config.skin == FileManagerSkin.classic
                ? null
                : () => notifier.setSkin(FileManagerSkin.classic),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    children: [
                      SectionHeader(l10n.fileSkinComponentStyling),
                      SectionCard(
                        children: [
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            value: appSkinSettings.fileManagerFollowsAppSkin,
                            onChanged: (value) => ref
                                .read(appSkinSettingsProvider.notifier)
                                .setFileManagerFollowsAppSkin(value),
                            title: Text(
                              l10n.skinFollowAppSkin,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              appSkinSettings.fileManagerFollowsAppSkin
                                  ? l10n.fileSkinFollowAppSkinDescription
                                  : l10n.fileSkinUseIndependentStylesDescription,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            secondary: Icon(
                              Icons.folder_special_outlined,
                              color: cs.primary,
                            ),
                          ),
                          if (showAppSkinShortcut)
                            AppSkinShortcutTile(
                              preset: appSkinSettings.preset,
                              showFileManagerSkinShortcut: false,
                            ),
                        ],
                      ),
                      SectionHeader(l10n.fileSkinPreviewHeader),
                      _SkinPreview(skin: skin),
                      if (followsAppSkin) ...[
                        SectionCard(
                          children: [
                            ListTile(
                              leading: Icon(
                                Icons.info_outline_rounded,
                                color: cs.primary,
                              ),
                              title: Text(
                                l10n.fileSkinManagedByAppSkinTitle,
                                style: textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                l10n.fileSkinManagedByAppSkinDescription,
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      SectionHeader(l10n.fileSkinPresetsHeader),
                      _PresetPicker(
                        skin: skin,
                        onSelected: (preset) => notifier.setSkin(preset.skin),
                      ),
                      SectionHeader(l10n.fileSkinFoldersHeader),
                      SectionCard(
                        children: _itemStyleTiles(
                          context,
                          style: skin.folders,
                          onChanged: (s) =>
                              notifier.setSkin(skin.copyWith(folders: s)),
                        ),
                      ),
                      SectionHeader(l10n.fileSkinFilesHeader),
                      SectionCard(
                        children: _itemStyleTiles(
                          context,
                          style: skin.files,
                          onChanged: (s) =>
                              notifier.setSkin(skin.copyWith(files: s)),
                        ),
                      ),
                      SectionHeader(l10n.fileSkinTextHeader),
                      SectionCard(
                        children: [
                          _ColorTile(
                            title: l10n.fileSkinDetailsColorLabel,
                            icon: Icons.format_color_text_rounded,
                            color: skin.detailsColor,
                            allowDefault: true,
                            onChanged: (c) => notifier.setSkin(
                              c == null
                                  ? skin.copyWith(clearDetailsColor: true)
                                  : skin.copyWith(detailsColor: c),
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                            ),
                            value: skin.monospaceNames,
                            onChanged: (v) => notifier.setSkin(
                              skin.copyWith(monospaceNames: v),
                            ),
                            title: Text(
                              l10n.fileSkinMonospaceLabel,
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              l10n.fileSkinMonospaceDesc,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            secondary: Icon(
                              Icons.text_fields_rounded,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

/// The color a person starts from when they switch an icon color to Custom
/// before having picked one.
const Color _kDefaultCustomIconColor = Color(0xFF42A5F5);

/// The controls shared by the Folders and Files sections: icon style,
/// background, icon color (plus its custom color when chosen), name color.
List<Widget> _itemStyleTiles(
  BuildContext context, {
  required SkinItemStyle style,
  required ValueChanged<SkinItemStyle> onChanged,
}) {
  final l10n = context.l10n;
  return [
    OptionPickerTile<SkinIconFamily>(
      label: l10n.fileSkinIconStyleLabel,
      prefixIcon: Icons.category_outlined,
      value: style.iconFamily,
      options: [
        for (final family in SkinIconFamily.values)
          SelectOption(value: family, label: family.getLocalizedLabel(l10n)),
      ],
      onChanged: (v) => onChanged(style.copyWith(iconFamily: v)),
    ),
    OptionPickerTile<SkinContainerStyle>(
      label: l10n.fileSkinContainerLabel,
      prefixIcon: Icons.crop_square_rounded,
      value: style.container,
      options: [
        for (final container in SkinContainerStyle.values)
          SelectOption(
            value: container,
            label: container.getLocalizedLabel(l10n),
          ),
      ],
      onChanged: (v) => onChanged(style.copyWith(container: v)),
    ),
    OptionPickerTile<SkinIconColorMode>(
      label: l10n.fileSkinIconColorLabel,
      prefixIcon: Icons.format_color_fill_rounded,
      value: style.iconColorMode,
      options: [
        for (final mode in SkinIconColorMode.values)
          SelectOption(value: mode, label: mode.getLocalizedLabel(l10n)),
      ],
      onChanged: (v) => onChanged(
        v == SkinIconColorMode.custom && style.customIconColor == null
            ? style.copyWith(
                iconColorMode: v,
                customIconColor: _kDefaultCustomIconColor,
              )
            : style.copyWith(iconColorMode: v),
      ),
    ),
    if (style.iconColorMode == SkinIconColorMode.custom)
      _ColorTile(
        title: l10n.fileSkinCustomIconColorLabel,
        icon: Icons.palette_outlined,
        color: style.customIconColor,
        allowDefault: false,
        onChanged: (c) => onChanged(
          c == null
              ? style.copyWith(clearCustomIconColor: true)
              : style.copyWith(customIconColor: c),
        ),
      ),
    _ColorTile(
      title: l10n.fileSkinNameColorLabel,
      icon: Icons.format_color_text_rounded,
      color: style.nameColor,
      allowDefault: true,
      onChanged: (c) => onChanged(
        c == null
            ? style.copyWith(clearNameColor: true)
            : style.copyWith(nameColor: c),
      ),
    ),
  ];
}

/// A settings row showing a color (or "Default") that opens the picker.
class _ColorTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color? color;

  /// Whether the picker offers "Default" (i.e. null) as a choice.
  final bool allowDefault;
  final ValueChanged<Color?> onChanged;

  const _ColorTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.allowDefault,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final current = color;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(icon, color: cs.primary),
      title: Text(
        title,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        current == null
            ? context.l10n.fileSkinColorDefault
            : '#${skinColorToHex(current)}',
        style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
      ),
      trailing: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: current ?? Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: cs.outlineVariant),
        ),
      ),
      onTap: () async {
        final pick = await showSkinColorPicker(
          context,
          title: title,
          initial: current,
          allowDefault: allowDefault,
        );
        if (pick != null) onChanged(pick.color);
      },
    );
  }
}

void _noop() {}

/// A live sample of the file manager -- real list rows and grid cards, drawn
/// by the same widgets the browser uses -- under the skin being edited.
class _SkinPreview extends StatelessWidget {
  final FileManagerSkin skin;

  const _SkinPreview({required this.skin});

  static const String _folderName = 'Documents';
  static const List<(String, int)> _files = [
    ('report.pdf', 482113),
    ('holiday.jpg', 3120455),
    ('clip.mp4', 48213004),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final modified = DateTime(2026, 9, 12).millisecondsSinceEpoch ~/ 1000;

    Widget gridCard({required bool isFolder, required String name}) {
      final icon = isFolder ? skin.folderIcon : skin.fileIcon(name);
      final color = isFolder
          ? skin.folderIconColor(cs)
          : skin.fileIconColor(cs, name);
      return GridCardShell(
        isFolder: isFolder,
        preview: Center(child: Icon(icon, size: 40, color: color)),
        label: name,
        isSelected: false,
        isSelectionMode: false,
        onTap: _noop,
        onLongPress: _noop,
      );
    }

    return FileManagerSkinScope(
      skin: skin,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DirectoryTile(
                entry: RawEntry(
                  name: _folderName,
                  isDir: true,
                  sizeBytes: 0,
                  modifiedSecs: modified,
                ),
                isSelectionMode: false,
                isSelected: false,
                showItemActionsMenu: false,
                onTap: _noop,
                onLongPress: _noop,
              ),
              for (final (name, size) in _files)
                FileTile(
                  entry: RawEntry(
                    name: name,
                    isDir: false,
                    sizeBytes: size,
                    modifiedSecs: modified,
                  ),
                  isSelectionMode: false,
                  isSelected: false,
                  showItemActionsMenu: false,
                  onTap: _noop,
                  onLongPress: _noop,
                ),
              const SizedBox(height: 10),
              SizedBox(
                height: 108,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: gridCard(isFolder: true, name: _folderName),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: gridCard(isFolder: false, name: _files[0].$1),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: gridCard(isFolder: false, name: _files[2].$1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal strip of the built-in skins. When the current skin matches none
/// of them (individual options were changed) a "Custom" card is appended and
/// marked as the selection.
class _PresetPicker extends StatefulWidget {
  final FileManagerSkin skin;
  final ValueChanged<SkinPreset> onSelected;

  const _PresetPicker({required this.skin, required this.onSelected});

  @override
  State<_PresetPicker> createState() => _PresetPickerState();
}

class _PresetPickerState extends State<_PresetPicker> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _PresetPicker oldWidget) {
    super.didUpdateWidget(oldWidget);

    final wasPreset = oldWidget.skin.matchingPreset != null;
    final isCustom = widget.skin.matchingPreset == null;
    if (wasPreset && isCustom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = widget.skin.matchingPreset;

    return SizedBox(
      height: 120,
      child: Scrollbar(
        controller: _scrollController,
        thumbVisibility: true,

        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.only(bottom: 16),
          scrollDirection: Axis.horizontal,
          children: [
            for (final preset in SkinPreset.values)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _PresetCard(
                  label: preset.getLocalizedLabel(l10n),
                  skin: preset.skin,
                  selected: current == preset,
                  onTap: () => widget.onSelected(preset),
                ),
              ),
            if (current == null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: _PresetCard(
                  label: l10n.fileSkinPresetCustom,
                  skin: widget.skin,
                  selected: true,
                  onTap: null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final String label;
  final FileManagerSkin skin;
  final bool selected;
  final VoidCallback? onTap;

  const _PresetCard({
    required this.label,
    required this.skin,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.35)
          : cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: selected
            ? BorderSide(color: cs.primary, width: 2)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 108,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _MiniTile(skin: skin, isDir: true),
                  const SizedBox(width: 8),
                  _MiniTile(skin: skin, isDir: false),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small sample tile showing how [skin] draws a folder or a file icon and
/// its background.
class _MiniTile extends StatelessWidget {
  final FileManagerSkin skin;
  final bool isDir;

  const _MiniTile({required this.skin, required this.isDir});

  static const String _sampleFile = 'sample.pdf';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final icon = isDir ? skin.folderIcon : skin.fileIcon(_sampleFile);
    final color = isDir
        ? skin.folderIconColor(cs)
        : skin.fileIconColor(cs, _sampleFile);

    Color? fill;
    BoxBorder? border;
    switch (skin.styleFor(isDir: isDir).container) {
      case SkinContainerStyle.filled:
        fill = isDir
            ? cs.secondaryContainer.withValues(alpha: 0.4)
            : cs.surfaceContainerHighest;
      case SkinContainerStyle.outlined:
        border = Border.all(color: cs.outlineVariant, width: 1.2);
      case SkinContainerStyle.none:
        break;
    }

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        border: border,
      ),
      child: Icon(icon, size: 22, color: color),
    );
  }
}
