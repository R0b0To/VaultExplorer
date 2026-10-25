import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/features/settings/app_skin_settings_screen.dart';
import 'package:vaultexplorer/features/skin_editor/skin_edit_session.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';

/// A contextual link from a component appearance page to app-wide skins.
/// For a custom skin it starts the floating skin editor right here (the
/// person can then tap any element, on any page, to recolor it); built-in
/// skins open the preset page so the user can choose or create a custom skin.
class AppSkinShortcutTile extends ConsumerWidget {
  final AppSkinPreset preset;
  final bool showFileManagerSkinShortcut;

  const AppSkinShortcutTile({
    super.key,
    required this.preset,
    this.showFileManagerSkinShortcut = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCustom = preset == AppSkinPreset.custom;
    final l10n = context.l10n;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(
        isCustom ? Icons.tune_rounded : Icons.palette_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        isCustom ? l10n.skinEditCurrentSkin : l10n.skinChooseOrCreateSkin,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        isCustom
            ? l10n.skinSkinShortcutCustomDescription
            : l10n.skinSkinShortcutPresetDescription,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () {
        if (isCustom) {
          beginSkinEditing(
            context,
            ref,
            ref.read(appSkinSettingsProvider).customAppSkin,
          );
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SkinAreaScope(
              area: SkinArea.settings,
              child: AppSkinSettingsScreen(
                showFileManagerSkinShortcut: showFileManagerSkinShortcut,
              ),
            ),
          ),
        );
      },
    );
  }
}
