import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/inputs/thumbnail_settings_tiles.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

/// How many saved vaults carry their own thumbnail settings. Drives whether
/// the "Reset all vaults" action is shown; auto-disposed so it is re-read
/// each time a settings screen opens.
final vaultThumbnailOverrideCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.read(containerRepositoryProvider).countThumbnailOverrides(),
);

/// The app-wide thumbnail default -- the value every vault set to "Use global
/// default" follows -- plus the action that puts every vault back on it.
///
/// Only App settings shows this. Local Storage and the decoy file manager
/// never read the default: they have their own slot, edited in File manager
/// settings.
class GlobalThumbnailDefaultsTiles extends ConsumerWidget {
  const GlobalThumbnailDefaultsTiles({super.key});

  Future<void> _resetVaults(
    BuildContext context,
    WidgetRef ref,
    int count,
  ) async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.resetVaultThumbnailsTitle,
      message: context.l10n.resetVaultThumbnailsConfirmMessage(count),
      confirmLabel: context.l10n.reset,
    );
    if (!confirmed || !context.mounted) return;

    final changed = await ref
        .read(fileManagerToolbarSettingsProvider(null).notifier)
        .resetVaultThumbnailOverrides();
    if (!context.mounted) return;
    ref.invalidate(vaultThumbnailOverrideCountProvider);
    showAppSnackBar(
      context,
      message: context.l10n.resetVaultThumbnailsDone(changed),
      tone: AppBannerTone.success,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.colors;
    final textTheme = context.typography;
    final provider = fileManagerToolbarSettingsProvider(null);
    final config = ref.watch(provider).config;
    final notifier = ref.read(provider.notifier);
    final overrides = ref.watch(vaultThumbnailOverrideCountProvider).value ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ThumbnailSettingsTiles(
          cacheMode: config.defaultThumbnailCacheMode,
          quality: config.defaultThumbnailQuality,
          cacheModeLabel: context.l10n.thumbnailCachingDefaultLabel,
          qualityLabel: context.l10n.thumbnailQualityDefaultLabel,
          onCacheModeChanged: notifier.setDefaultThumbnailCacheMode,
          onQualityChanged: notifier.setDefaultThumbnailQuality,
        ),
        if (overrides > 0)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: Icon(Icons.restart_alt_rounded, color: cs.primary),
            title: Text(
              context.l10n.resetVaultThumbnailsTitle,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              context.l10n.resetVaultThumbnailsSubtitle,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            onTap: () => _resetVaults(context, ref, overrides),
          ),
      ],
    );
  }
}
