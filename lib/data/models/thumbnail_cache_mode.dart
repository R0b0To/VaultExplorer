import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Where thumbnail data (decrypted image/video previews) is stored on disk.
///
/// The in-memory LRU cache in [FileGridView] is independent of this; it sits
/// above all three modes and is always active.
enum ThumbnailCacheMode {
  /// Store in the OS app-cache directory (default).
  ///
  /// Fast, disposable, and transparent to the container. The OS may purge
  /// this folder under storage pressure. Thumbnails are stored **encrypted**
  /// (AES-GCM, per-container key) in the app cache directory — see
  /// [ThumbnailCacheService]. Users who require the container itself to be
  /// the only thing holding the bytes (e.g. so nothing survives outside it
  /// even in encrypted form) should choose [inContainer] instead.
  appCache,

  /// Store inside the VeraCrypt container under a hidden `.thumbcache/` dir.
  ///
  /// Thumbnails are encrypted alongside the rest of the container data.
  /// Writing is slower (requires a temp-file round-trip through the FAT layer)
  /// but the thumbnails never exist unencrypted on device storage.
  inContainer,

  /// No persistent caching. Every grid-view load re-reads from the container.
  ///
  /// Maximally private (no decrypted data ever written to disk) at the cost
  /// of slower gallery loading.
  disabled;

  // ── Human-readable labels ─────────────────────────────────────────────────

  String get label {
    switch (this) {
      case ThumbnailCacheMode.appCache:
        return 'App cache';
      case ThumbnailCacheMode.inContainer:
        return 'Inside container';
      case ThumbnailCacheMode.disabled:
        return 'Disabled';
    }
  }

  String getLocalizedLabel(AppLocalizations l10n) {
    switch (this) {
      case ThumbnailCacheMode.appCache:
        return l10n.thumbnailCacheAppCacheLabel;
      case ThumbnailCacheMode.inContainer:
        return l10n.thumbnailCacheInContainerLabel;
      case ThumbnailCacheMode.disabled:
        return l10n.thumbnailCacheDisabledLabel;
    }
  }

  String get description {
    switch (this) {
      case ThumbnailCacheMode.appCache:
        return 'Stored encrypted in the App cache. '
            'Fast; cleared automatically under storage pressure.';
      case ThumbnailCacheMode.inContainer:
        return 'Stored inside the encrypted container. '
            'Protected by the container itself, but writes are slower.';
      case ThumbnailCacheMode.disabled:
        return 'No disk cache. Thumbnails are re-generated on every load.';
    }
  }

  String getLocalizedDescription(AppLocalizations l10n) {
    switch (this) {
      case ThumbnailCacheMode.appCache:
        return l10n.thumbnailCacheAppCacheDesc;
      case ThumbnailCacheMode.inContainer:
        return l10n.thumbnailCacheInContainerDesc;
      case ThumbnailCacheMode.disabled:
        return l10n.thumbnailCacheDisabledDesc;
    }
  }

  // ── JSON serialisation ────────────────────────────────────────────────────

  String toJson() {
    switch (this) {
      case ThumbnailCacheMode.appCache:
        return 'appCache';
      case ThumbnailCacheMode.inContainer:
        return 'inContainer';
      case ThumbnailCacheMode.disabled:
        return 'disabled';
    }
  }

  static ThumbnailCacheMode? fromJson(String? value) {
    switch (value) {
      case 'appCache':
        return ThumbnailCacheMode.appCache;
      case 'inContainer':
        return ThumbnailCacheMode.inContainer;
      case 'disabled':
        return ThumbnailCacheMode.disabled;
      default:
        return null; // Return null so we know it isn't configured
    }
  }
}