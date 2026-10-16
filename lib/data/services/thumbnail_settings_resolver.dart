import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/thumbnail_settings.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';

/// The one place that decides which thumbnail settings apply to a file
/// browser. Precedence, highest first:
///
///  1. an explicit override passed to the screen ([overrideCacheMode] /
///     [overrideQuality], each independently);
///  2. the browser's own scope:
///     * Local Storage and the decoy file manager ([isLocalStorage]) share
///       one slot, [FileManagerToolbarConfig.localStorageThumbnails];
///     * a vault uses its own override when its [ContainerRecord] has one,
///       and otherwise follows the app-wide default;
///  3. the app-wide default, [FileManagerToolbarConfig.defaultThumbnails].
///
/// Local Storage never inherits the vault default on purpose: "inside
/// container" means something different there (a plain hidden folder, not an
/// encrypted vault), and the decoy must not depend on, or hint at, settings
/// that belong to vaults.
ThumbnailSettings resolveThumbnailSettings({
  required FileManagerToolbarConfig config,
  required bool isLocalStorage,
  ContainerRecord? record,
  ThumbnailCacheMode? overrideCacheMode,
  ThumbnailQuality? overrideQuality,
}) {
  final global = config.defaultThumbnails;
  final ThumbnailSettings scoped = isLocalStorage
      ? config.localStorageThumbnails
      : (record?.ownThumbnailSettings(global: global) ?? global);
  return ThumbnailSettings(
    cacheMode: overrideCacheMode ?? scoped.cacheMode,
    quality: overrideQuality ?? scoped.quality,
  );
}
