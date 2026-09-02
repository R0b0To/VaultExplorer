import 'dart:async';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';

part 'file_manager_toolbar_settings_controller.g.dart';

class FileManagerToolbarSettingsState {
  final FileManagerToolbarConfig config;
  final ContainerRecord? record;
  final bool loading;

  FileManagerToolbarSettingsState({
    FileManagerToolbarConfig? config,
    this.record,
    this.loading = true,
  }) : config = config ?? FileManagerToolbarConfig.defaults();

  FileManagerToolbarSettingsState _copy({
    FileManagerToolbarConfig? config,
    ContainerRecord? record,
    bool setRecord = false,
    bool? loading,
  }) => FileManagerToolbarSettingsState(
    config: config ?? this.config,
    record: setRecord ? record : (record ?? this.record),
    loading: loading ?? this.loading,
  );
}

@riverpod
class FileManagerToolbarSettings extends _$FileManagerToolbarSettings {
  Future<void>? _loadFuture;

  @override
  FileManagerToolbarSettingsState build(String? containerUri) {
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
    state = state._copy(
      config: config,
      record: record,
      setRecord: true,
      loading: false,
    );
  }

  Future<void> _updateConfig(FileManagerToolbarConfig newConfig) async {
    state = state._copy(config: newConfig);
    await ref.read(fileManagerToolbarServiceProvider).save(newConfig);
  }

  Future<void> setRememberPerFolderLayout(bool val) =>
      _updateConfig(state.config.copyWith(rememberPerFolderLayout: val));

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

  Future<void> setShowGridFileNames(bool val) =>
      _updateConfig(state.config.copyWith(showGridFileNames: val));

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

  Future<void> reorderActions(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final order = List<FileManagerAction>.from(state.config.order);
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex, moved);
    final newConfig = state.config.copyWith(order: order);
    await _updateConfig(newConfig);
  }

  Future<void> toggleActionVisible(FileManagerAction action, bool visible) async {
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
    if (newIndex > oldIndex) newIndex -= 1;
    final order = List<FileDetailColumn>.from(state.config.detailColumnsOrder);
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex, moved);
    final newConfig = state.config.copyWith(detailColumnsOrder: order);
    await _updateConfig(newConfig);
  }

  Future<void> toggleDetailColumnVisible(FileDetailColumn col, bool visible) async {
    final hidden = Set<FileDetailColumn>.from(state.config.hiddenDetailColumns);
    if (visible) {
      hidden.remove(col);
    } else {
      hidden.add(col);
    }
    final newConfig = state.config.copyWith(hiddenDetailColumns: hidden);
    await _updateConfig(newConfig);
  }

  Future<void> reorderBookmarks(int oldIndex, int newIndex) async {
    final record = state.record;
    if (record == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
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
}