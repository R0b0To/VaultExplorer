import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart'
    show AppBannerTone;
import 'package:vaultexplorer/features/browser/models/file_category.dart';
import 'package:vaultexplorer/features/browser/models/file_category_presentation.dart';
import 'package:vaultexplorer/features/browser/services/device_category_index_provider.dart';
import 'package:vaultexplorer/features/browser/services/vault_category_index_io.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';

/// Chooses which category shortcuts the drawer shows and in what order.
///
/// Used in Settings and in the drawer's "Manage categories" sheet. Everything
/// here only changes the drawer: a hidden category still exists, and its files
/// are untouched.
class CategoryShortcutsEditor extends ConsumerWidget {
  const CategoryShortcutsEditor({super.key, this.showVaultOptions = true});

  /// Whether to show the options that concern vaults (the category index kept
  /// inside them). The decoy file manager passes false: nothing it shows may
  /// mention vaults.
  final bool showVaultOptions;

  /// Removes the category index from every unlocked vault, and what the
  /// category views remembered of phone storage. A vault that is locked keeps
  /// its index until it is next unlocked and this runs again; a read-only
  /// vault cannot be changed and is skipped.
  Future<void> _clearIndexes(BuildContext context, WidgetRef ref) async {
    final io = ref.read(vaultFileIoApiProvider);
    await ref.read(deviceCategoryIndexProvider).clear();
    for (final vault in ref.read(vaultDashboardControllerProvider).mounted) {
      try {
        await categoryIndexStoreFor(io, vault)?.delete();
      } catch (_) {
        // Nothing to do about one vault that cannot be reached.
      }
    }
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.categoryIndexCleared,
        tone: AppBannerTone.info,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings),
    );
    final notifier = ref.read(appSettingsControllerProvider.notifier);
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final order = FileCategory.orderedFrom(settings.categoryShortcutOrder);
    final hidden = settings.hiddenCategoryShortcuts.toSet();
    final enabled = settings.categoryShortcutsEnabled;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(
            l10n.categoryShortcutsEnable,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            l10n.categoryShortcutsEnableSubtitle,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          value: enabled,
          onChanged: (value) => notifier.updateSettings(
            (s) => s.copyWith(categoryShortcutsEnabled: value),
          ),
        ),
        if (enabled) ...[
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              final moved = [...order];
              if (newIndex > oldIndex) newIndex -= 1;
              moved.insert(newIndex, moved.removeAt(oldIndex));
              notifier.updateSettings(
                (s) => s.copyWith(
                  categoryShortcutOrder: [for (final c in moved) c.storageKey],
                ),
              );
            },
            children: [
              for (var i = 0; i < order.length; i++)
                SwitchListTile(
                  key: ValueKey(order[i].storageKey),
                  contentPadding: const EdgeInsets.only(left: 8, right: 16),
                  secondary: ReorderableDragStartListener(
                    index: i,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Icon(order[i].icon, size: 20, color: scheme.primary),
                      const SizedBox(width: 12),
                      Text(order[i].label(l10n)),
                    ],
                  ),
                  value: !hidden.contains(order[i].storageKey),
                  onChanged: (visible) {
                    final next = {...hidden};
                    visible
                        ? next.remove(order[i].storageKey)
                        : next.add(order[i].storageKey);
                    notifier.updateSettings(
                      (s) => s.copyWith(hiddenCategoryShortcuts: next.toList()),
                    );
                  },
                ),
            ],
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(Icons.restart_alt_rounded, color: scheme.primary),
            title: Text(l10n.categoryShortcutsRestore),
            onTap: () => notifier.updateSettings(
              (s) => s.copyWith(
                categoryShortcutsEnabled: true,
                categoryShortcutOrder: FileCategory.defaultOrderKeys,
                hiddenCategoryShortcuts: const [],
              ),
            ),
          ),
        ],
        if (showVaultOptions) ...[
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(
              l10n.categoryIndexInVaultsTitle,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              l10n.categoryIndexInVaultsSubtitle,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            value: settings.categoryIndexInVaults,
            onChanged: (value) => notifier.updateSettings(
              (s) => s.copyWith(categoryIndexInVaults: value),
            ),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Icon(Icons.delete_sweep_outlined, color: scheme.primary),
            title: Text(l10n.categoryIndexClear),
            subtitle: Text(
              l10n.categoryIndexClearSubtitle,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            onTap: () => _clearIndexes(context, ref),
          ),
        ],
      ],
    );
  }
}
