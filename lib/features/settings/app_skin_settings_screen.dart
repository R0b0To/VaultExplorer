import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/data/services/skin_backup_service.dart';
import 'package:vaultexplorer/features/settings/settings_live_refresh.dart';
import 'package:vaultexplorer/features/settings/custom_app_skin_screen.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';

class AppSkinSettingsScreen extends ConsumerWidget {
  const AppSkinSettingsScreen({super.key});

  Future<void> _importSkins(BuildContext context, WidgetRef ref) async {
    try {
      final parsed = await ref
          .read(sessionLockControllerProvider)
          .withLockSuppression(
            () => ref
                .read(appSkinSettingsProvider.notifier)
                .pickAndParseSkinFile(),
          );
      if (!context.mounted || parsed == null) return;
      // Skins are always added first, so that the active skin recorded in the
      // interface settings can resolve to one of them.
      final added = parsed.skins.isEmpty
          ? <CustomAppSkin>[]
          : await ref
                .read(appSkinSettingsProvider.notifier)
                .addImportedSkins(parsed.skins);
      var interfaceApplied = false;
      final interfaceSettings = parsed.interfaceSettings;
      if (interfaceSettings != null && context.mounted) {
        final apply = await showAppConfirmDialog(
          context,
          title: context.l10n.skinImportInterfaceTitle,
          message: context.l10n.skinImportInterfaceMessage,
          confirmLabel: context.l10n.skinImportInterfaceApply,
          cancelLabel: context.l10n.skinImportInterfaceSkip,
        );
        if (apply && context.mounted) {
          final applied = await ref
              .read(skinBackupServiceProvider)
              .applyInterface(interfaceSettings);
          if (!context.mounted) return;
          await refreshLiveSettings(
            ref,
            applied.settings,
            applied.toolbarConfig,
          );
          interfaceApplied = true;
        }
      }
      if (!context.mounted) return;
      final message = [
        if (added.isNotEmpty || !interfaceApplied)
          context.l10n.skinImportSucceeded(added.length),
        if (interfaceApplied) context.l10n.skinInterfaceApplied,
      ].join(' ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.skinImportFailed(error.toString())),
        ),
      );
    }
  }

  /// The toolbar button: asks what to export, because a file that also carries
  /// the interface settings is a personal backup rather than something to
  /// share (single-skin export from a skin's menu never includes them).
  Future<void> _chooseExport(
    BuildContext context,
    WidgetRef ref,
    List<CustomAppSkin> skins,
  ) async {
    final includeInterface = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.l10n.skinExportSkins),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              enabled: skins.isNotEmpty,
              leading: const Icon(Icons.palette_outlined),
              title: Text(dialogContext.l10n.skinExportSkinsOnly),
              subtitle: Text(dialogContext.l10n.skinExportSkinsOnlySubtitle),
              onTap: skins.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, false),
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: Text(dialogContext.l10n.skinExportSkinsAndInterface),
              subtitle: Text(
                dialogContext.l10n.skinExportSkinsAndInterfaceSubtitle,
              ),
              onTap: () => Navigator.pop(dialogContext, true),
            ),
          ],
        ),
      ),
    );
    if (includeInterface == null || !context.mounted) return;
    await _exportSkins(
      context,
      ref,
      skins,
      includeInterface: includeInterface,
    );
  }

  Future<void> _exportSkins(
    BuildContext context,
    WidgetRef ref,
    List<CustomAppSkin> skins, {
    bool includeInterface = false,
  }) async {
    try {
      final exported = await ref
          .read(sessionLockControllerProvider)
          .withLockSuppression(
            () => ref
                .read(appSkinSettingsProvider.notifier)
                .exportSkins(skins, includeInterface: includeInterface),
          );
      if (!context.mounted || !exported) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            includeInterface
                ? context.l10n.skinAppearanceExported
                : skins.length == 1
                ? context.l10n.skinExportedSingle
                : context.l10n.skinExportedMultiple,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.skinExportFailed(error.toString())),
        ),
      );
    }
  }

  Future<void> _editSkin(
    BuildContext context,
    WidgetRef ref,
    CustomAppSkin skin,
  ) async {
    final notifier = ref.read(appSkinSettingsProvider.notifier);
    await notifier.activateCustomSkin(skin);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const CustomAppSkinScreen())),
    );
  }

  Future<void> _removeSkin(
    BuildContext context,
    WidgetRef ref,
    CustomAppSkin skin,
  ) async {
    final shouldRemove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.skinRemoveSkin),
        content: Text(context.l10n.skinRemoveConfirmation(skin.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.remove),
          ),
        ],
      ),
    );
    if (shouldRemove != true || !context.mounted) return;
    await ref.read(appSkinSettingsProvider.notifier).removeCustomSkin(skin.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appSkin = ref.watch(appSkinSettingsProvider);
    final selected = appSkin.preset;
    final cs = Theme.of(context).colorScheme;
    final exportableSkins = [...appSkin.customAppSkins];
    if (selected == AppSkinPreset.custom &&
        !exportableSkins.any((skin) => skin.id == appSkin.customAppSkin.id)) {
      exportableSkins.add(appSkin.customAppSkin);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.skinAppSkin),
        actions: [
          IconButton(
            tooltip: context.l10n.skinImportSkins,
            onPressed: () => _importSkins(context, ref),
            icon: const Icon(Icons.file_open_outlined),
          ),
          IconButton(
            tooltip: context.l10n.skinExportSkins,
            onPressed: () => _chooseExport(context, ref, exportableSkins),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  context
                          .l10n
                          .skinChooseACoordinatedLookForTheAppFileManagerAndEditor +
                      context
                          .l10n
                          .skinLightAndDarkSystemThemesUseMatchingPaletteVariants,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: Icon(
                    selected == AppSkinPreset.custom
                        ? Icons.tune_rounded
                        : Icons.palette_outlined,
                  ),
                  label: Text(
                    selected == AppSkinPreset.custom
                        ? context.l10n.skinEditCurrentSkin
                        : context.l10n.skinCreateASkinFromThisLook,
                  ),
                  onPressed: () async {
                    final notifier = ref.read(appSkinSettingsProvider.notifier);
                    final current = ref.read(appSkinSettingsProvider);
                    final skin =
                        current.preset == AppSkinPreset.custom &&
                            current.customAppSkin.lightColors.isNotEmpty
                        ? current.customAppSkin
                        : createCustomAppSkinFromCurrent(
                            current,
                          ).copyWith(id: createCustomAppSkinId());
                    await notifier.saveCustomSkin(skin);
                    if (!context.mounted) return;
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SkinAreaScope(area: SkinArea.settings, child: const CustomAppSkinScreen()),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                for (final preset in AppSkinPreset.values.where(
                  (preset) => preset != AppSkinPreset.custom,
                ))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AppSkinCard(
                      preset: preset,
                      displayName: appSkinPresetLabel(context, preset),
                      selected: selected == preset,
                      onTap: () async {
                        final notifier = ref.read(
                          appSkinSettingsProvider.notifier,
                        );
                        final current = ref.read(appSkinSettingsProvider);
                        if (preset == AppSkinPreset.custom &&
                            current.customAppSkin.lightColors.isEmpty) {
                          await notifier.setCustomAppSkin(
                            createCustomAppSkinFromCurrent(current),
                          );
                        }
                        await notifier.setPreset(preset);
                      },
                    ),
                  ),
                if (appSkin.customAppSkins.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.l10n.skinYourSkins,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final skin in appSkin.customAppSkins)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AppSkinCard(
                        preset: AppSkinPreset.custom,
                        customSkin: skin,
                        displayName: skin.name,
                        selected:
                            selected == AppSkinPreset.custom &&
                            appSkin.customAppSkin.id == skin.id,
                        onTap: () => ref
                            .read(appSkinSettingsProvider.notifier)
                            .activateCustomSkin(skin),
                        onEdit: () => _editSkin(context, ref, skin),
                        onExport: () => _exportSkins(context, ref, [skin]),
                        onRemove: () => _removeSkin(context, ref, skin),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppSkinCard extends StatelessWidget {
  final AppSkinPreset preset;
  final String displayName;
  final bool selected;
  final VoidCallback onTap;
  final CustomAppSkin? customSkin;
  final VoidCallback? onEdit;
  final VoidCallback? onExport;
  final VoidCallback? onRemove;

  const _AppSkinCard({
    required this.preset,
    required this.displayName,
    required this.selected,
    required this.onTap,
    this.customSkin,
    this.onEdit,
    this.onExport,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final custom = customSkin;
    final (surface, accent, foreground, icon) = custom != null
        ? (
            Color(
              custom.lightColors['surfaceContainerHigh'] ??
                  cs.surfaceContainerHigh.toARGB32(),
            ),
            Color(custom.lightColors['primary'] ?? cs.primary.toARGB32()),
            Color(custom.lightColors['onSurface'] ?? cs.onSurface.toARGB32()),
            Icons.palette_outlined,
          )
        : switch (preset) {
            AppSkinPreset.defaultSkin => (
              cs.surfaceContainerHigh,
              cs.primary,
              cs.onSurface,
              Icons.folder_rounded,
            ),
            AppSkinPreset.oledPureBlack => (
              Colors.black,
              const Color(0xFFA8C7FA),
              const Color(0xFFE2E2E9),
              Icons.folder_rounded,
            ),
            AppSkinPreset.custom => (
              cs.surfaceContainerHigh,
              cs.primary,
              cs.onSurface,
              Icons.palette_outlined,
            ),
          };
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _PreviewSwatch(
                surface: surface,
                accent: accent,
                foreground: foreground,
                icon: icon,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      custom != null
                          ? context.l10n.skinCustomAppFileManagerAndEditorColors
                          : switch (preset) {
                              AppSkinPreset.defaultSkin =>
                                context
                                    .l10n
                                    .skinMaterialColorsWithLightAndDarkVariants,
                              AppSkinPreset.oledPureBlack =>
                                context.l10n.skinTrueBlackEditorAndDarkf97e8f,
                              AppSkinPreset.custom =>
                                context
                                    .l10n
                                    .skinYourEditableAppFileManagerAndEditorColors,
                            },
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (custom != null)
                PopupMenuButton<_CustomSkinAction>(
                  tooltip: context.l10n.skinSkinActions,
                  onSelected: (action) {
                    switch (action) {
                      case _CustomSkinAction.edit:
                        onEdit?.call();
                      case _CustomSkinAction.export:
                        onExport?.call();
                      case _CustomSkinAction.remove:
                        onRemove?.call();
                    }
                  },
                  itemBuilder: (context) => [
                    if (onEdit != null)
                      PopupMenuItem(
                        value: _CustomSkinAction.edit,
                        child: Text(context.l10n.skinEditSkin),
                      ),
                    if (onExport != null)
                      PopupMenuItem(
                        value: _CustomSkinAction.export,
                        child: Text(context.l10n.skinExportSkin),
                      ),
                    if (onRemove != null)
                      PopupMenuItem(
                        value: _CustomSkinAction.remove,
                        child: Text(context.l10n.skinRemoveSkinf09101),
                      ),
                  ],
                ),
              if (selected) Icon(Icons.check_circle_rounded, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CustomSkinAction { edit, export, remove }

class _PreviewSwatch extends StatelessWidget {
  final Color surface;
  final Color accent;
  final Color foreground;
  final IconData icon;

  const _PreviewSwatch({
    required this.surface,
    required this.accent,
    required this.foreground,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    width: 88,
    height: 72,
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: foreground.withValues(alpha: 0.2)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: accent),
            const SizedBox(width: 4),
            Icon(Icons.description_outlined, size: 16, color: foreground),
          ],
        ),
        const Spacer(),
        Container(
          height: 4,
          width: 58,
          color: foreground.withValues(alpha: 0.8),
        ),
        const SizedBox(height: 4),
        Container(height: 3, width: 40, color: accent),
      ],
    ),
  );
}

String appSkinPresetLabel(BuildContext context, AppSkinPreset preset) =>
    switch (preset) {
      AppSkinPreset.defaultSkin => context.l10n.skinDefaultLightDark,
      AppSkinPreset.oledPureBlack => context.l10n.skinOLEDPureBlack,
      AppSkinPreset.custom => context.l10n.skinCustomSkin,
    };
