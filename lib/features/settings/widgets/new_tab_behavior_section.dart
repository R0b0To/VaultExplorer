import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/external_storage_locations_provider.dart';
import 'package:vaultexplorer/core/utils/local_storage_name.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/inputs/option_picker_tile.dart';
import 'package:vaultexplorer/data/models/new_tab_behavior.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

/// What opening a new tab does: duplicate the tab in front (default), ask
/// where to open it, or always open one chosen storage. The storage picker is
/// only shown for the last choice.
class NewTabBehaviorSection extends ConsumerWidget {
  const NewTabBehaviorSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.useBrowserTabs),
    );
    final behavior = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.newTabBehavior),
    );
    final storageId = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.newTabStorageId),
    );
    final externals = ref.watch(externalStorageLocationsProvider);

    // The Vaults page first, then this device's storage and every added
    // external storage. A saved
    // storage that no longer exists stays visible (so the row never claims
    // another storage) and makes new tabs ask instead.
    final storageOptions = <SelectOption<String>>[
      SelectOption(
        value: kNewTabVaultsPageId,
        label: l10n.vaultsSectionTitle,
      ),
      SelectOption(
        value: kNewTabLocalStorageId,
        label: localStorageDisplayName(l10n.localStorageCardTitle),
        subtitle: l10n.internalStorageSubtitle,
      ),
      for (final loc in externals)
        SelectOption(value: loc.id, label: loc.displayName),
    ];
    if (!storageOptions.any((o) => o.value == storageId)) {
      storageOptions.insert(
        0,
        SelectOption(value: storageId, label: l10n.newTabStorageUnavailable),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.browserTabNew),
        SectionCard(
          children: [
            OptionPickerTile<NewTabBehavior>(
              label: l10n.newTabBehaviorLabel,
              value: behavior,
              enabled: enabled,
              prefixIcon: Icons.add_box_outlined,
              options: [
                for (final mode in NewTabBehavior.values)
                  SelectOption(
                    value: mode,
                    label: mode.getLocalizedLabel(l10n),
                    subtitle: mode.getLocalizedDescription(l10n),
                  ),
              ],
              onChanged: (mode) => ref
                  .read(appSettingsControllerProvider.notifier)
                  .updateSettings((s) => s.copyWith(newTabBehavior: mode)),
            ),
            if (behavior == NewTabBehavior.specificStorage)
              OptionPickerTile<String>(
                label: l10n.newTabStorageLabel,
                value: storageId,
                enabled: enabled,
                prefixIcon: Icons.sd_storage_outlined,
                options: storageOptions,
                onChanged: (id) => ref
                    .read(appSettingsControllerProvider.notifier)
                    .updateSettings((s) => s.copyWith(newTabStorageId: id)),
              ),
          ],
        ),
      ],
    );
  }
}
