import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/inputs/thumbnail_settings_tiles.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_settings.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/vault_gallery_meta_storage.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_config_controller.dart';
import 'package:vaultexplorer/features/library/controllers/library_providers.dart';

class ContainerIndexesThumbnailsScreen extends ConsumerStatefulWidget {
  const ContainerIndexesThumbnailsScreen({
    super.key,
    required this.params,
    this.mountedContainer,
    required this.isModified,
    required this.canSave,
    required this.onSave,
  });

  final ContainerConfigParams params;
  final MountedContainer? mountedContainer;
  final bool Function(ContainerConfigState state) isModified;
  final bool Function(ContainerConfigState state) canSave;
  final Future<void> Function() onSave;

  @override
  ConsumerState<ContainerIndexesThumbnailsScreen> createState() =>
      _ContainerIndexesThumbnailsScreenState();
}

class _ContainerIndexesThumbnailsScreenState
    extends ConsumerState<ContainerIndexesThumbnailsScreen> {
  bool _clearingGalleryMetadataIndex = false;
  bool _clearingMusicIndex = false;

  MountedContainer? get _effectiveMounted {
    if (widget.mountedContainer != null) return widget.mountedContainer;
    return ref
        .read(vaultDashboardControllerProvider)
        .mounted
        .where((container) => container.uri == widget.params.uri)
        .firstOrNull;
  }

  Future<void> _clearThumbnailCache() async {
    final confirm = await showAppConfirmDialog(
      context,
      title: context.l10n.clearThumbnailCacheDialogTitle,
      message: context.l10n.clearThumbnailCacheDialogMessage,
      confirmLabel: context.l10n.clearCacheButton,
      isDestructive: true,
    );
    if (!confirm || !mounted) return;

    final result = await ref
        .read(containerConfigControllerProvider(widget.params).notifier)
        .clearThumbnailCache();

    if (!mounted) return;
    if (result.isLocked) {
      showAppSnackBar(
        context,
        message: context.l10n.appCacheClearedUnlockMessage,
        tone: AppBannerTone.warning,
      );
    } else if (result.appCacheCleared && result.containerCacheCleared) {
      showAppSnackBar(
        context,
        message: context.l10n.allThumbnailCachesClearedMessage,
        tone: AppBannerTone.success,
      );
    } else if (result.appCacheCleared) {
      showAppSnackBar(
        context,
        message: context.l10n.appCacheClearedContainerFailedMessage,
        tone: AppBannerTone.warning,
      );
    } else {
      showAppSnackBar(
        context,
        message: context.l10n.failedToClearThumbnailCachesMessage,
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _clearGalleryMetadataIndex() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.galleryMetadataClearConfirmTitle,
      message: context.l10n.galleryMetadataClearConfirmMessage,
      confirmLabel: context.l10n.clearSavedIndexButton,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearingGalleryMetadataIndex = true);
    final container = _effectiveMounted;
    try {
      final result = await VaultGalleryMetaStorage.clearPersistedIndexCopies(
        uri: widget.params.uri,
        crypto: ref.read(vaultCryptoApiProvider),
        io: ref.read(vaultFileIoApiProvider),
        container: container,
      );
      if (!mounted) return;
      if (result.appStorageCleared && result.containerStorageCleared) {
        showAppSnackBar(
          context,
          message: context.l10n.galleryMetadataIndexClearedMessage,
          tone: AppBannerTone.success,
        );
      } else if (result.appStorageCleared &&
          (container == null || container.readOnly)) {
        showAppSnackBar(
          context,
          message: context.l10n.appIndexClearedUnlockMessage,
          tone: AppBannerTone.warning,
        );
      } else {
        showAppSnackBar(
          context,
          message: context.l10n.savedIndexClearFailedMessage,
          tone: AppBannerTone.error,
        );
      }
    } catch (e) {
      VeLog.e(
        'ContainerIndexesThumbnailsScreen',
        'Gallery metadata index clear failed',
        e,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.savedIndexClearFailedMessage,
          tone: AppBannerTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _clearingGalleryMetadataIndex = false);
    }
  }

  Future<void> _clearMusicIndex() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.musicIndexClearConfirmTitle,
      message: context.l10n.musicIndexClearConfirmMessage,
      confirmLabel: context.l10n.clearSavedIndexButton,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _clearingMusicIndex = true);
    final container = _effectiveMounted;
    try {
      final result = await ref
          .read(libraryIndexStoreProvider)
          .deleteIndexCopies(widget.params.uri, container: container);
      if (!mounted) return;
      if (result.appStorageCleared && result.containerStorageCleared) {
        showAppSnackBar(
          context,
          message: context.l10n.musicIndexClearedMessage,
          tone: AppBannerTone.success,
        );
      } else if (result.appStorageCleared &&
          (container == null || container.readOnly)) {
        showAppSnackBar(
          context,
          message: context.l10n.appIndexClearedUnlockMessage,
          tone: AppBannerTone.warning,
        );
      } else {
        showAppSnackBar(
          context,
          message: context.l10n.savedIndexClearFailedMessage,
          tone: AppBannerTone.error,
        );
      }
    } catch (e) {
      VeLog.e(
        'ContainerIndexesThumbnailsScreen',
        'Music index clear failed',
        e,
      );
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.savedIndexClearFailedMessage,
          tone: AppBannerTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _clearingMusicIndex = false);
    }
  }

  Widget _loadingCard() => const Center(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    ),
  );

  Widget _buildThumbnailSection(
    BuildContext context,
    ContainerConfigState state,
    TextTheme textTheme,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.thumbnailStorageSectionHeader),
        SectionCard(
          children: [
            if (state.loadingPassword)
              _loadingCard()
            else ...[
              ThumbnailSettingsTiles(
                useGlobalDefault: state.useGlobalThumbnails,
                onUseGlobalDefaultChanged: (value) => ref
                    .read(
                      containerConfigControllerProvider(widget.params).notifier,
                    )
                    .setUseGlobalThumbnails(value),
                cacheMode:
                    state.thumbnailCacheMode ??
                    ThumbnailSettings.defaults.cacheMode,
                quality:
                    state.thumbnailQuality ??
                    ThumbnailSettings.defaults.quality,
                cacheModeLabel: context.l10n.cacheModeLabel,
                qualityLabel: context.l10n.thumbnailQualityLabel,
                onCacheModeChanged: (value) => ref
                    .read(
                      containerConfigControllerProvider(widget.params).notifier,
                    )
                    .setThumbnailCacheMode(value),
                onQualityChanged: (value) => ref
                    .read(
                      containerConfigControllerProvider(widget.params).notifier,
                    )
                    .setThumbnailQuality(value),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                title: Text(
                  context.l10n.clearThumbnailCacheTitle,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  context.l10n.removeCachedThumbnailsSubtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                trailing: state.clearingCache
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                onTap: state.clearingCache ? null : _clearThumbnailCache,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildGalleryMetadataSection(
    BuildContext context,
    ContainerConfigState state,
    TextTheme textTheme,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.galleryMetadataSectionHeader),
        SectionCard(
          children: [
            if (state.loadingPassword)
              _loadingCard()
            else ...[
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: state.useGlobalGalleryMetadata,
                onChanged: (value) => ref
                    .read(
                      containerConfigControllerProvider(widget.params).notifier,
                    )
                    .setUseGlobalGalleryMetadata(value),
                title: Text(
                  context.l10n.galleryMetadataUseGlobalDefaultTitle,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  context.l10n.galleryMetadataUseGlobalDefaultDesc,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (!state.useGlobalGalleryMetadata)
                OptionPickerTile<ThumbnailCacheMode>(
                  label: context.l10n.galleryMetadataIndexStorageLabel,
                  value:
                      state.galleryMetadataCacheMode ??
                      ThumbnailCacheMode.inContainer,
                  options: ThumbnailCacheMode.values
                      .map(
                        (mode) => SelectOption<ThumbnailCacheMode>(
                          value: mode,
                          label: switch (mode) {
                            ThumbnailCacheMode.appCache =>
                              context.l10n.galleryMetadataAppStorageOption,
                            ThumbnailCacheMode.inContainer =>
                              context.l10n.galleryMetadataInVaultOption,
                            ThumbnailCacheMode.disabled =>
                              mode.getLocalizedLabel(context.l10n),
                          },
                        ),
                      )
                      .toList(),
                  onChanged: ref
                      .read(
                        containerConfigControllerProvider(
                          widget.params,
                        ).notifier,
                      )
                      .setGalleryMetadataCacheMode,
                ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                title: Text(
                  context.l10n.galleryMetadataClearAction,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  context.l10n.galleryMetadataClearConfirmMessage,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                trailing: _clearingGalleryMetadataIndex
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                onTap: _clearingGalleryMetadataIndex
                    ? null
                    : _clearGalleryMetadataIndex,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildMusicIndexSection(
    BuildContext context,
    ContainerConfigState state,
    TextTheme textTheme,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.musicIndexSectionHeader),
        SectionCard(
          children: [
            if (state.loadingPassword)
              _loadingCard()
            else ...[
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: state.useGlobalMusicIndex,
                onChanged: (value) => ref
                    .read(
                      containerConfigControllerProvider(widget.params).notifier,
                    )
                    .setUseGlobalMusicIndex(value),
                title: Text(
                  context.l10n.musicIndexUseGlobalDefaultTitle,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  context.l10n.musicIndexUseGlobalDefaultDesc,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (!state.useGlobalMusicIndex)
                OptionPickerTile<ThumbnailCacheMode>(
                  label: context.l10n.musicIndexStorageLabel,
                  value:
                      state.musicIndexCacheMode ??
                      ThumbnailCacheMode.inContainer,
                  options: ThumbnailCacheMode.values
                      .map(
                        (mode) => SelectOption<ThumbnailCacheMode>(
                          value: mode,
                          label: switch (mode) {
                            ThumbnailCacheMode.appCache =>
                              context.l10n.musicIndexAppStorageOption,
                            ThumbnailCacheMode.inContainer =>
                              context.l10n.musicIndexInVaultOption,
                            ThumbnailCacheMode.disabled =>
                              mode.getLocalizedLabel(context.l10n),
                          },
                        ),
                      )
                      .toList(),
                  onChanged: ref
                      .read(
                        containerConfigControllerProvider(
                          widget.params,
                        ).notifier,
                      )
                      .setMusicIndexCacheMode,
                ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                title: Text(
                  context.l10n.musicIndexClearAction,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  context.l10n.musicIndexClearConfirmMessage,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                trailing: _clearingMusicIndex
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                onTap: _clearingMusicIndex ? null : _clearMusicIndex,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget? _buildBottomSaveBar(
    ContainerConfigState state, {
    required bool isModified,
    required bool canSave,
  }) {
    if (!isModified) return null;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!canSave) ...[
                  InlineBanner(
                    state.needsPatternSetup
                        ? context.l10n.patternSetupRequiredAboveBeforeSaving
                        : state.needsPinSetup
                        ? context.l10n.pinSetupRequiredAboveBeforeSaving
                        : context.l10n.passwordOrCacheDerivedKeyRequiredMessage,
                    tone: AppBannerTone.error,
                    icon: Icons.info_outline_rounded,
                  ),
                  const SizedBox(height: 10),
                ],
                FilledButton(
                  onPressed: (state.saving || !canSave) ? null : widget.onSave,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                  ),
                  child: state.saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          context.l10n.saveConfigurationButton,
                          style: textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(containerConfigControllerProvider(widget.params));
    final isModified = widget.isModified(state);
    final canSave = widget.canSave(state);
    final wideLayout = context.screen.useWideLayout;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.indexesAndThumbnailsTitle),
        actions: [
          if (wideLayout && isModified)
            IconButton(
              icon: state.saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_rounded),
              tooltip: context.l10n.saveConfigurationButton,
              onPressed: (state.saving || !canSave) ? null : widget.onSave,
            ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _buildThumbnailSection(context, state, textTheme, cs),
                const SizedBox(height: 16),
                _buildGalleryMetadataSection(context, state, textTheme, cs),
                const SizedBox(height: 16),
                _buildMusicIndexSection(context, state, textTheme, cs),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: wideLayout
          ? null
          : _buildBottomSaveBar(
              state,
              isModified: isModified,
              canSave: canSave,
            ),
    );
  }
}
