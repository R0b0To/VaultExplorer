import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/models/file_item_action.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/grid_aspect_ratio.dart';
import 'package:vaultexplorer/data/models/grid_corner_style.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';
import 'package:vaultexplorer/data/models/resume_playback_mode.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
import 'package:vaultexplorer/data/models/media_decoder_mode.dart';
import 'package:vaultexplorer/data/models/audio_equalizer_settings.dart';
import 'package:vaultexplorer/data/models/thumbnail_generation_strategy.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/scrub_preview_style.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/video_aspect_ratio_mode.dart';
import 'package:vaultexplorer/core/theme/app_skin_settings_provider.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

part 'file_manager_toolbar_settings_controller.g.dart';

class FileManagerToolbarSettingsState {
  final FileManagerToolbarConfig config;
  final ContainerRecord? record;
  final bool loading;

  /// Bumped whenever a bulk action rewrites vault records behind the
  /// browsers' backs (see [FileManagerToolbarSettings.resetVaultThumbnailOverrides]).
  /// A vault's own thumbnail settings live in its record, not in [config],
  /// so a live file browser can't notice that change from the config alone.
  final int thumbnailOverridesRevision;

  FileManagerToolbarSettingsState({
    FileManagerToolbarConfig? config,
    this.record,
    this.loading = true,
    this.thumbnailOverridesRevision = 0,
  }) : config = config ?? FileManagerToolbarConfig.defaults();

  FileManagerToolbarSettingsState _copy({
    FileManagerToolbarConfig? config,
    ContainerRecord? record,
    bool setRecord = false,
    bool? loading,
    int? thumbnailOverridesRevision,
  }) => FileManagerToolbarSettingsState(
    config: config ?? this.config,
    record: setRecord ? record : (record ?? this.record),
    loading: loading ?? this.loading,
    thumbnailOverridesRevision:
        thumbnailOverridesRevision ?? this.thumbnailOverridesRevision,
  );
}

@riverpod
class FileManagerToolbarSettings extends _$FileManagerToolbarSettings {
  static final Set<FileManagerToolbarSettings> _activeInstances = {};
  Future<void>? _loadFuture;

  @override
  FileManagerToolbarSettingsState build(String? containerUri) {
    ref.onDispose(() {
      _activeInstances.remove(this);
    });
    _activeInstances.add(this);

    final state = FileManagerToolbarSettingsState(loading: true);
    Future.microtask(() => load(containerUri));
    return state;
  }

  Future<void> load(String? containerUri) {
    return _loadFuture ??= _performLoad(containerUri).whenComplete(() {
      _loadFuture = null;
    });
  }

  Future<void> _performLoad(String? containerUri) async {
    final config = await ref.read(fileManagerToolbarServiceProvider).load();
    ContainerRecord? record;
    if (containerUri != null) {
      final records = await ref.read(containerRepositoryProvider).loadAll();
      record = records[containerUri];
    }
    if (!ref.mounted) return;
    final viewerConfig = config.mediaViewerToolbarConfig;
    ThumbnailCacheService.setVideoThumbnailSettings(
      viewerConfig.thumbnailGenerationStrategy,
      viewerConfig.thumbnailFramePosition,
    );
    state = state._copy(
      config: config,
      record: record,
      setRecord: true,
      loading: false,
    );
  }

  /// Id of the most recent [_updateConfig] call, shared across every family
  /// instance (they all write to the same underlying service).
  static int _latestUpdateId = 0;

  /// Serializes disk writes so rapid successive updates are persisted in the
  /// order they were made.
  static Future<void> _persistQueue = Future.value();

  /// Publishes [config] to every live family instance so any screen listening
  /// to toolbar settings updates in real-time.
  static void _publishConfig(FileManagerToolbarConfig config) {
    for (final instance in _activeInstances) {
      if (instance.ref.mounted) {
        instance.state = instance.state._copy(config: config);
      }
    }
  }

  /// Applies [newConfig] to in-memory state immediately (optimistically), then
  /// persists it in the background.
  ///
  /// The state must NOT wait for the encrypted-storage write: UIs such as the
  /// reorderable toolbar list rebuild as soon as a drag is dropped, and if the
  /// provider still holds the old order at that moment the list visibly snaps
  /// back before jumping to the new order once the write finishes.
  Future<void> _updateConfig(FileManagerToolbarConfig newConfig) {
    final updateId = ++_latestUpdateId;
    final service = ref.read(fileManagerToolbarServiceProvider);

    _publishConfig(newConfig);

    final persisted = _persistQueue.then((_) async {
      final currentServiceConfig = await service.load();
      final preservedConfig = newConfig.copyWith(
        listZoomLevel: currentServiceConfig.listZoomLevel,
        gridColumnsPortrait: currentServiceConfig.gridColumnsPortrait,
        gridColumnsLandscape: currentServiceConfig.gridColumnsLandscape,
        masonryColumnsPortrait: currentServiceConfig.masonryColumnsPortrait,
        masonryColumnsLandscape: currentServiceConfig.masonryColumnsLandscape,
        folderLayoutModes: currentServiceConfig.folderLayoutModes,
        folderGridAspectRatios: currentServiceConfig.folderGridAspectRatios,
        folderSortModes: currentServiceConfig.folderSortModes,
      );
      await service.save(preservedConfig);

      // Only the newest update re-syncs state (to pick up the preserved
      // fields); an older one doing so would briefly revert a newer change.
      if (updateId == _latestUpdateId) {
        _publishConfig(preservedConfig);
      }
    });
    _persistQueue = persisted.catchError((_) {});
    return persisted;
  }

  Future<void> setBottomSelectionBar(bool val) =>
      _updateConfig(state.config.copyWith(bottomSelectionBar: val));

  Future<void> setRememberPerFolderLayout(bool val) =>
      _updateConfig(state.config.copyWith(rememberPerFolderLayout: val));

  Future<void> setResetSizeOnLayoutChange(bool val) =>
      _updateConfig(state.config.copyWith(resetSizeOnLayoutChange: val));

  Future<void> setAutoHideAppBar(bool val) =>
      _updateConfig(state.config.copyWith(autoHideAppBar: val));

  Future<void> setUseFabForToolbar(bool val) =>
      _updateConfig(state.config.copyWith(useFabForToolbar: val));

  Future<void> setShowHiddenFiles(bool val) =>
      _updateConfig(state.config.copyWith(showHiddenFiles: val));

  Future<void> setShowBreadcrumbBar(bool val) =>
      _updateConfig(state.config.copyWith(showBreadcrumbBar: val));

  Future<void> setShowStatsBar(bool val) =>
      _updateConfig(state.config.copyWith(showStatsBar: val));

  Future<void> setShowBookmarkBar(bool val) =>
      _updateConfig(state.config.copyWith(showBookmarkBar: val));

  Future<void> setShowListThumbnails(bool val) =>
      _updateConfig(state.config.copyWith(showListThumbnails: val));

  Future<void> setShowItemActionsMenu(bool val) =>
      _updateConfig(state.config.copyWith(showItemActionsMenu: val));

  Future<void> setSelectByIcon(bool val) =>
      _updateConfig(state.config.copyWith(selectByIcon: val));

  Future<void> setShowFileExtensions(bool val) =>
      _updateConfig(state.config.copyWith(showFileExtensions: val));

  Future<void> setShowGridFileNames(bool val) =>
      _updateConfig(state.config.copyWith(showGridFileNames: val));

  Future<void> setGridAspectRatio(GridAspectRatio ratio) =>
      _updateConfig(state.config.copyWith(gridAspectRatio: ratio));

  Future<void> setGridCornerStyle(GridCornerStyle style) =>
      _updateConfig(state.config.copyWith(gridCornerStyle: style));

  Future<void> setGridSpacing(int spacing) =>
      _updateConfig(state.config.copyWith(gridSpacing: spacing));

  Future<void> setLongFileNameDisplayMode(LongFileNameDisplayMode mode) =>
      _updateConfig(state.config.copyWith(longFileNameDisplayMode: mode));

  /// Applies [skin] as the independent file-manager override. It is retained
  /// in the toolbar config for compatibility and mirrored through
  /// AppSettingsService for app-skin persistence/export; open browsers receive
  /// the effective skin through the app ThemeExtension.
  Future<void> setSkin(FileManagerSkin skin) async {
    await ref
        .read(appSkinSettingsProvider.notifier)
        .setFileManagerFollowsAppSkin(false);
    await ref.read(appSkinSettingsProvider.notifier).setFileManagerSkin(skin);
    await _updateConfig(state.config.copyWith(skin: skin));
  }

  Future<void> setAutoStartPlaylistMode(bool val) =>
      _updateConfig(state.config.copyWith(autoStartPlaylistMode: val));

  Future<void> setShowMediaCarousel(bool val) =>
      _updateConfig(state.config.copyWith(showMediaCarousel: val));

  Future<void> setPlaylistTransitionEffect(PlaylistTransitionEffect effect) =>
      _updateConfig(state.config.copyWith(playlistTransitionEffect: effect));

  Future<void> setDefaultThumbnailCacheMode(ThumbnailCacheMode mode) =>
      _updateConfig(state.config.copyWith(defaultThumbnailCacheMode: mode));

  Future<void> setDefaultThumbnailQuality(ThumbnailQuality quality) =>
      _updateConfig(state.config.copyWith(defaultThumbnailQuality: quality));

  /// The thumbnail slot shared by Local Storage and the decoy file manager.
  Future<void> setLocalStorageThumbnailCacheMode(ThumbnailCacheMode mode) =>
      _updateConfig(
        state.config.copyWith(localStorageThumbnailCacheMode: mode),
      );

  Future<void> setLocalStorageThumbnailQuality(ThumbnailQuality quality) =>
      _updateConfig(
        state.config.copyWith(localStorageThumbnailQuality: quality),
      );

  /// Makes every saved vault follow the app-wide thumbnail default again,
  /// then tells every live file browser to re-read its vault record (see
  /// [FileManagerToolbarSettingsState.thumbnailOverridesRevision]). Returns
  /// how many vaults changed.
  Future<int> resetVaultThumbnailOverrides() async {
    final changed = await ref
        .read(containerRepositoryProvider)
        .resetThumbnailOverrides();
    if (changed > 0) {
      for (final instance in _activeInstances.toList()) {
        if (!instance.ref.mounted) continue;
        instance.state = instance.state._copy(
          thumbnailOverridesRevision:
              instance.state.thumbnailOverridesRevision + 1,
        );
      }
    }
    return changed;
  }

  Future<void> reorderActions(int oldIndex, int newIndex) async {
    final order = List<FileManagerAction>.from(state.config.order);
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex, moved);
    final newConfig = state.config.copyWith(order: order);
    await _updateConfig(newConfig);
  }

  Future<void> toggleActionVisible(
    FileManagerAction action,
    bool visible,
  ) async {
    final hidden = Set<FileManagerAction>.from(state.config.hidden);
    if (visible) {
      hidden.remove(action);
    } else {
      hidden.add(action);
    }
    final newConfig = state.config.copyWith(hidden: hidden);
    await _updateConfig(newConfig);
  }

  Future<void> reorderDetailColumns(int oldIndex, int newIndex) async {
    final order = List<FileDetailColumn>.from(state.config.detailColumnsOrder);
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex, moved);
    final newConfig = state.config.copyWith(detailColumnsOrder: order);
    await _updateConfig(newConfig);
  }

  Future<void> toggleDetailColumnVisible(
    FileDetailColumn col,
    bool visible,
  ) async {
    final hidden = Set<FileDetailColumn>.from(state.config.hiddenDetailColumns);
    if (visible) {
      hidden.remove(col);
    } else {
      hidden.add(col);
    }
    final newConfig = state.config.copyWith(hiddenDetailColumns: hidden);
    await _updateConfig(newConfig);
  }

  /// Moves an item action within its own section of the settings list: the
  /// quick-action row ([quickRow] true) or the menu list. [oldIndex] and
  /// [newIndex] are positions among that section's actions only; the other
  /// section's actions keep their places in [FileManagerToolbarConfig.itemActionsOrder].
  Future<void> reorderItemActions(
    bool quickRow,
    int oldIndex,
    int newIndex,
  ) async {
    final order = List<FileItemAction>.from(state.config.itemActionsOrder);
    final section = order.where((a) => a.isQuickAction == quickRow).toList();
    final moved = section.removeAt(oldIndex);
    section.insert(newIndex, moved);
    var next = 0;
    final reordered = [
      for (final a in order) a.isQuickAction == quickRow ? section[next++] : a,
    ];
    await _updateConfig(state.config.copyWith(itemActionsOrder: reordered));
  }

  Future<void> toggleItemActionVisible(
    FileItemAction action,
    bool visible,
  ) async {
    final hidden = Set<FileItemAction>.from(state.config.hiddenItemActions);
    if (visible) {
      hidden.remove(action);
    } else {
      hidden.add(action);
    }
    await _updateConfig(state.config.copyWith(hiddenItemActions: hidden));
  }

  /// Puts the item actions back in their default order with none hidden,
  /// leaving every other setting alone.
  Future<void> resetItemActions() => _updateConfig(
    state.config.copyWith(
      itemActionsOrder: FileItemAction.values,
      hiddenItemActions: const {},
    ),
  );

  Future<void> reorderBookmarks(int oldIndex, int newIndex) async {
    final record = state.record;
    if (record == null) return;

    final paths = List<String>.from(record.bookmarkPaths);
    final moved = paths.removeAt(oldIndex);
    paths.insert(newIndex, moved);

    final newRecord = record.copyWith(bookmarkPaths: paths);
    state = state._copy(record: newRecord, setRecord: true);
    await ref.read(containerRepositoryProvider).save(newRecord);
  }

  Future<void> removeBookmark(String path) async {
    final record = state.record;
    if (record == null) return;
    final paths = List<String>.from(record.bookmarkPaths)..remove(path);
    final newRecord = record.copyWith(bookmarkPaths: paths);
    state = state._copy(record: newRecord, setRecord: true);
    await ref.read(containerRepositoryProvider).save(newRecord);
  }

  Future<void> resetToDefaults() async {
    final def = FileManagerToolbarConfig.defaults();
    await _updateConfig(def);
  }

void applyImportedConfig(FileManagerToolbarConfig newConfig) {
    ThumbnailCacheService.setVideoThumbnailSettings(
      newConfig.mediaViewerToolbarConfig.thumbnailGenerationStrategy,
      newConfig.mediaViewerToolbarConfig.thumbnailFramePosition,
    );
    Future.microtask(() {
      if (ref.mounted) {
        state = state._copy(config: newConfig);
      }
    });
  }

  // Media Viewer Controls Customization
  Future<void> updateMediaViewerConfig(MediaViewerToolbarConfig mediaConfig) {
    ThumbnailCacheService.setVideoThumbnailSettings(
      mediaConfig.thumbnailGenerationStrategy,
      mediaConfig.thumbnailFramePosition,
    );
    return _updateConfig(
      state.config.copyWith(mediaViewerToolbarConfig: mediaConfig),
    );
  }

  Future<void> setThumbnailGenerationStrategy(
    ThumbnailGenerationStrategy strategy,
  ) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      thumbnailGenerationStrategy: strategy,
    );
    ThumbnailCacheService.setVideoThumbnailSettings(
      strategy,
      updated.thumbnailFramePosition,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setThumbnailFramePosition(double position) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      thumbnailFramePosition: position.clamp(0.05, 0.90).toDouble(),
    );
    ThumbnailCacheService.setVideoThumbnailSettings(
      updated.thumbnailGenerationStrategy,
      updated.thumbnailFramePosition,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerSeekSensitivity(double sensitivity) =>
      updateMediaViewerConfig(
        state.config.mediaViewerToolbarConfig.copyWith(
          seekSensitivity: sensitivity.clamp(0.25, 2.0).toDouble(),
        ),
      );

  Future<void> setMediaViewerVolumeGestureSensitivity(double sensitivity) =>
      updateMediaViewerConfig(
        state.config.mediaViewerToolbarConfig.copyWith(
          volumeGestureSensitivity: sensitivity.clamp(0.25, 2.0).toDouble(),
        ),
      );

  Future<void> setMediaViewerBrightnessGestureSensitivity(double sensitivity) =>
      updateMediaViewerConfig(
        state.config.mediaViewerToolbarConfig.copyWith(
          brightnessGestureSensitivity: sensitivity.clamp(0.25, 2.0).toDouble(),
        ),
      );

  Future<void> setMediaViewerVolumeBoostEnabled(bool enabled) =>
      updateMediaViewerConfig(
        state.config.mediaViewerToolbarConfig.copyWith(
          volumeBoostEnabled: enabled,
        ),
      );

  Future<void> setMediaViewerVolumeBoostGain(int gainMb) =>
      updateMediaViewerConfig(
        state.config.mediaViewerToolbarConfig.copyWith(
          volumeBoostGainMb: gainMb.clamp(0, 2000).toInt(),
        ),
      );

  /// Persists the media player's equalizer. Callers that stream many changes
  /// (a slider drag) should call this once at the end, not per tick.
  Future<void> setMediaViewerEqualizer(AudioEqualizerSettings equalizer) =>
      updateMediaViewerConfig(
        state.config.mediaViewerToolbarConfig.copyWith(equalizer: equalizer),
      );

  Future<void> setMediaViewerVideoDecoderMode(MediaDecoderMode mode) =>
      updateMediaViewerConfig(
        state.config.mediaViewerToolbarConfig.copyWith(videoDecoderMode: mode),
      );

  Future<void> setMediaViewerAudioDecoderMode(MediaDecoderMode mode) =>
      updateMediaViewerConfig(
        state.config.mediaViewerToolbarConfig.copyWith(audioDecoderMode: mode),
      );

  Future<void> setMediaViewerTopBarActions(List<MediaViewerAction> actions) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      topBarActions: actions,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerBottomBarActions(List<MediaViewerAction> actions) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      bottomBarActions: actions,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerHiddenActions(Set<MediaViewerAction> hidden) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      hiddenActions: hidden,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerShowProgressBar(bool show) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      showProgressBar: show,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerShowCenterTransport(bool show) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      showCenterTransport: show,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerShowPreviousNext(bool show) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      showPreviousNext: show,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerShowStatusBadge(bool show) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      showStatusBadge: show,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerShowFileNamesInNotification(bool show) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      showFileNamesInMediaNotification: show,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerScrubPreviewStyle(ScrubPreviewStyle style) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      scrubPreviewStyle: style,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerEdgeSwipeBrightnessEnabled(bool enabled) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      edgeSwipeBrightnessEnabled: enabled,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerEdgeSwipeVolumeEnabled(bool enabled) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      edgeSwipeVolumeEnabled: enabled,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerEdgeSwipeHudEnabled(bool enabled) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      edgeSwipeHudEnabled: enabled,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerEdgeSwipeWidthFraction(double fraction) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      edgeSwipeWidthFraction: fraction,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerPinchZoomOutEnabled(bool enabled) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      pinchZoomOutEnabled: enabled,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerMinVideoZoomScale(double scale) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      minVideoZoomScale: scale,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerDefaultAspectRatioMode(VideoAspectRatioMode mode) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      defaultAspectRatioMode: mode,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerHoldToSpeedMultiplier(double multiplier) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      holdToSpeedMultiplier: multiplier,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerSwipeToSeekEnabled(bool enabled) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      swipeToSeekEnabled: enabled,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerTapEdgesToNavigate(bool enabled) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      tapEdgesToNavigate: enabled,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerDoubleTapPlayPause(bool enabled) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      doubleTapPlayPause: enabled,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerLoopPlaylist(bool enabled) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      loopPlaylist: enabled,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> setMediaViewerResumePlaybackMode(ResumePlaybackMode mode) {
    final updated = state.config.mediaViewerToolbarConfig.copyWith(
      resumePlaybackMode: mode,
    );
    return updateMediaViewerConfig(updated);
  }

  Future<void> resetMediaViewerConfigToDefaults() {
    final defaultMediaConfig = MediaViewerToolbarConfig.defaults();
    ThumbnailCacheService.setVideoThumbnailSettings(
      defaultMediaConfig.thumbnailGenerationStrategy,
      defaultMediaConfig.thumbnailFramePosition,
    );
    final updated = state.config.copyWith(
      mediaViewerToolbarConfig: defaultMediaConfig,
      showMediaCarousel: true,
    );
    return _updateConfig(updated);
  }
}
