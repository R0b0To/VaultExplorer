import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/android_manifest_icon_parser.dart';
import 'package:vaultexplorer/core/utils/android_resource_table_parser.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';

/// Thrown when an APK's launcher icon can't be resolved or extracted by
/// either the native or the manual-parsing route -- see
/// [fetchApkIconForThumbnail]'s doc comment.
///
/// Same handling contract as [ArchiveThumbnailUnavailable]: callers don't
/// need to catch this specifically -- [AsyncThumbnail] already falls back
/// to the plain file-type icon on any thrown error from a `fetchFn`.
class ApkIconUnavailable implements Exception {
  final String reason;
  const ApkIconUnavailable(this.reason);
  @override
  String toString() => 'APK icon unavailable: $reason';
}

/// Extracts an APK's launcher icon for use as a file-manager thumbnail --
/// the same icon Android itself would show for the app once installed.
///
/// Tries the real thing first: [VaultFileIoApi.getApkIcon] calls
/// `PackageManager.getPackageArchiveInfo` + `ApplicationInfo.loadIcon` on
/// the native side, which resolves resources (including full
/// adaptive-icon compositing) exactly the way Android itself does --
/// see `ThumbnailHandlers.handleGetApkIcon`'s doc comment for how that
/// works even for vault content, which has no on-disk file for
/// `PackageManager` to open directly.
///
/// Falls back to manual parsing only if that fails -- a defensive second
/// layer, not the primary path, kept around for whatever the native route
/// doesn't cover (older/unusual OS behavior, a future regression there):
///
///  1. Open the APK as a plain archive -- it's a ZIP file, and the native
///     engine detects format by content, not extension, so no different
///     from opening any other archive ([ArchiveService.open]/[openLocal]).
///  2. Extract `AndroidManifest.xml` and binary-XML-parse it to find the
///     resource id `android:icon` points at
///     ([findApplicationIconResourceId]).
///  3. Extract `resources.arsc` and resolve that id to an actual raster
///     icon file path inside the APK ([resolveIconResourcePath] -- see its
///     doc comment for what's *not* handled: full adaptive-icon
///     compositing, resource-reference chains, "compact" resource-table
///     entries -- exactly the gaps the native route above doesn't have).
///  4. Extract that one entry's bytes, exactly like
///     [fetchArchiveEntryForThumbnail] does for an image inside an
///     ordinary archive.
///
/// Neither route is attempted from inside an already-open archive (i.e.
/// browsing a `.zip` that happens to contain a `.apk`) -- same reasoning
/// and restriction as video thumbnails in `file_tile.dart`: there's no
/// real container/local path for a nested entry, which both
/// `VaultFileIoApi.getApkIcon` and [ArchiveService.open]/[openLocal] need.
/// Callers should only reach this when `archiveContext == null`.
///
/// Throws [ApkIconUnavailable] if both routes fail; callers should let
/// [AsyncThumbnail]'s existing error handling fall back to the plain
/// file-type icon, same as [fetchArchiveEntryForThumbnail].
Future<Uint8List> fetchApkIconForThumbnail({
  required MountedContainer container,
  required String filePath,
  required VaultFileIoApi fileIoApi,
}) async {
  final nativeIcon = await fileIoApi.getApkIcon(container, filePath);
  if (nativeIcon != null && nativeIcon.isNotEmpty) return nativeIcon;

  return _fetchApkIconByManualParse(container: container, filePath: filePath);
}

/// The manual-parsing fallback described in [fetchApkIconForThumbnail]'s
/// doc comment. Split out into its own function purely so that doc
/// comment can describe the two routes in one place.
Future<Uint8List> _fetchApkIconByManualParse({
  required MountedContainer container,
  required String filePath,
}) async {
  final ArchiveContext archive;
  try {
    archive = container.isLocalStorage
        ? await ArchiveService.openLocal(
            pathOrUri: p.join(container.uri, filePath),
            archiveName: p.basename(filePath),
          )
        : await ArchiveService.open(
            container: container,
            archivePathInContainer: filePath,
            // No real archive-browsing UI session backs this call -- see
            // this function's doc comment -- so there's no path-stack
            // position to record. 0 is never read for anything other
            // callers of ArchiveContext use it for.
            pathStackEntryIndex: 0,
          );
  } catch (e) {
    throw ApkIconUnavailable('Failed to open APK as archive: $e');
  }
  if (archive.status != ArchiveOpenStatus.ok) {
    throw ApkIconUnavailable('Failed to scan APK (status: ${archive.status})');
  }

  final manifestBytes = await archive.extractEntry('AndroidManifest.xml');
  if (manifestBytes == null || manifestBytes.isEmpty) {
    throw const ApkIconUnavailable('No AndroidManifest.xml in APK');
  }
  final iconResId = findApplicationIconResourceId(manifestBytes);
  if (iconResId == null) {
    throw const ApkIconUnavailable('No android:icon on <application>');
  }

  final arscBytes = await archive.extractEntry('resources.arsc');
  if (arscBytes == null || arscBytes.isEmpty) {
    throw const ApkIconUnavailable('No resources.arsc in APK');
  }
  // resources.arsc can run into the tens of MB on a large app -- offload
  // the scan to a background isolate rather than blocking the isolate
  // driving the file browser's scroll, mirroring the >500KB threshold
  // ThumbnailCacheService already uses for its own encrypt/decrypt work.
  final iconPath = arscBytes.length > 500 * 1024
      ? await compute(_resolveIconPath, _ResolveIconArgs(arscBytes, iconResId))
      : resolveIconResourcePath(arscBytes, iconResId);
  if (iconPath == null) {
    throw const ApkIconUnavailable(
      'Icon resource has no raster (PNG/WebP/JPEG) variant -- likely an '
      'adaptive icon with no legacy fallback',
    );
  }

  final iconBytes = await archive.extractEntry(iconPath);
  if (iconBytes == null || iconBytes.isEmpty) {
    throw ApkIconUnavailable('Failed to extract icon entry "$iconPath"');
  }
  return iconBytes;
}

class _ResolveIconArgs {
  final Uint8List arscBytes;
  final int resourceId;
  const _ResolveIconArgs(this.arscBytes, this.resourceId);
}

String? _resolveIconPath(_ResolveIconArgs args) =>
    resolveIconResourcePath(args.arscBytes, args.resourceId);