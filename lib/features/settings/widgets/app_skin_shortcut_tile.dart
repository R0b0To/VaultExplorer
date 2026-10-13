import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/features/settings/app_skin_settings_screen.dart';
import 'package:vaultexplorer/features/settings/custom_app_skin_screen.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';

/// A contextual link from a component appearance page to app-wide skins.
/// Custom skins open directly in their preview/editor; built-in skins open
/// the preset page so the user can choose or create a custom skin.
class AppSkinShortcutTile extends StatelessWidget {
  final AppSkinPreset preset;

  const AppSkinShortcutTile({super.key, required this.preset});

  @override
  Widget build(BuildContext context) {
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
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SkinAreaScope(area: SkinArea.settings, child: isCustom
              ? const CustomAppSkinScreen()
              : const AppSkinSettingsScreen()),
        ),
      ),
    );
  }
}
