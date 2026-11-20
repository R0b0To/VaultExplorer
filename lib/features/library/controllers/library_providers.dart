import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/library/controllers/library_controller.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/controllers/music_mode.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';
import 'package:vaultexplorer/features/library/data/library_store_platform.dart';
import 'package:vaultexplorer/features/library/index/library_scanner.dart';
import 'package:vaultexplorer/features/library/widgets/music_covers.dart';

/// Saves and loads music mode config, indexes and custom covers. The saved
/// index follows its independent storage setting; configs and covers keep the
/// existing vault-or-encrypted-app-storage behavior.
final libraryIndexStoreProvider = Provider<LibraryIndexStore>((ref) {
  return LibraryIndexStore(
    VaultLibraryStorePlatform(
      fileIo: ref.watch(vaultFileIoApiProvider),
      crypto: ref.watch(vaultCryptoApiProvider),
      hash: ref.watch(vaultHashApiProvider),
    ),
    musicIndexCacheModeFor: (container) async {
      final provider = fileManagerToolbarSettingsProvider(null);
      var settings = ref.read(provider);
      if (settings.loading) {
        await ref.read(provider.notifier).load(null);
        settings = ref.read(provider);
      }
      if (container.isLocalStorage) {
        return settings.config.localStorageMusicIndexCacheMode;
      }
      final record = (await ref
          .read(containerRepositoryProvider)
          .loadAll())[container.uri];
      return record?.musicIndexCacheMode ??
          settings.config.defaultMusicIndexCacheMode;
    },
  );
});

/// The per-container music mode switches. Holds only the small config, never an
/// index; entries are dropped when the last file manager view of a container
/// goes away.
final musicModeRegistryProvider = Provider<MusicModeRegistry>((ref) {
  return MusicModeRegistry(ref.watch(libraryIndexStoreProvider));
});

/// All containers' music libraries, merged, with the covers for them.
class MusicLibrary {
  final MusicHub hub;
  final MusicCovers covers;

  const MusicLibrary(this.hub, this.covers);
}

final musicLibraryProvider = Provider<MusicLibrary>((ref) {
  final fileIo = ref.watch(vaultFileIoApiProvider);
  final store = ref.watch(libraryIndexStoreProvider);

  late final MusicHub hub;
  final covers = MusicCovers(
    fileIo: fileIo,
    store: store,
    containerOf: (uri) => hub.containerOf(uri),
  );
  hub = MusicHub(
    createController: (container) => LibraryController(
      access: (c) => libraryFileAccess(fileIo, c),
      store: store,
      isAudioFile: MediaViewerConstants.isAudio,
    ),
    onSourceRemoved: covers.release,
  );
  ref.onDispose(() {
    hub.dispose();
    covers.dispose();
  });
  return MusicLibrary(hub, covers);
});

/// Adapts the engine's directory listing and chunked reads to what the
/// scanner expects. Works for vaults, phone and external storage and SAF
/// folders alike: the engine API hides which one a container is.
LibraryFileAccess libraryFileAccess(
  VaultFileIoApi fileIo,
  MountedContainer container,
) {
  return LibraryFileAccess(
    list: (dirPath) async {
      // refresh: a rescan exists to notice changes, so never accept a cached listing.
      final raw = await fileIo.listDirectory(container, dirPath, refresh: true);
      if (raw == null) return null;
      final entries = <LibraryFsEntry>[];
      for (final item in raw) {
        if (item.startsWith('System:')) continue;
        final e = RawEntry.parse(item);
        if (e.isPlaceholder) continue;
        entries.add(
          LibraryFsEntry(
            name: e.name,
            isDir: e.isDir,
            sizeBytes: e.sizeBytes,
            modifiedSecs: e.modifiedSecs,
          ),
        );
      }
      return entries;
    },
    read: (path, offset, length) =>
        fileIo.readFileChunk(container, path, offset, length),
  );
}
