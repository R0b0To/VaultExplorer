import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/inputs/thumbnail_settings_tiles.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
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
/// One widget for every place that edits the default (App settings and File
/// manager settings), so the two can never diverge: they were already
/// editing the same stored value through two separate copies of these tiles.
class GlobalThumbnailDefaultsTiles extends ConsumerWidget {
  const GlobalThumbnailDefaultsTiles({super.key});

  Future<void> _changeCacheMode(
    BuildContext context,
    WidgetRef ref,
    ThumbnailCacheMode mode,
  ) async {
    final provider = fileManagerToolbarSettingsProvider(null);
    final current = ref.read(provider).config.defaultThumbnailCacheMode;
    if (mode == current) return;

    // Unlike every other default, this one is live: it changes what every
    // vault that follows it does, right now. Storing thumbnails inside a
    // vault starts writing to all of them (and is not possible on read-only
    // ones), so say how many are affected before doing it.
    if (mode == ThumbnailCacheMode.inContainer) {
      final following = await ref
          .read(containerRepositoryProvider)
          .countFollowingGlobalThumbnails();
      if (!context.mounted) return;
      if (following > 0) {
        final confirmed = await showAppConfirmDialog(
          context,
          title: context.l10n.thumbnailCachingDefaultLabel,
          message: context.l10n.thumbnailGlobalInContainerConfirmMessage(
            following,
          ),
          confirmLabel: context.l10n.continueButton,
        );
        if (!confirmed || !context.mounted) return;
      }
    }
    await ref.read(provider.notifier).setDefaultThumbnailCacheMode(mode);
  }

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
          onCacheModeChanged: (mode) => _changeCacheMode(context, ref, mode),
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
