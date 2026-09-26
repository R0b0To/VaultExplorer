import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/external_storage_repository.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

/// Thrown by [ExternalStorageLocationsNotifier.promptAndAddLocation] when
/// the user picked a SAF tree that is this app's own exposed vault (or an
/// exposed subfolder of one) -- see [ExternalStorageLocationsNotifier]'s
/// `_isOwnDocumentsProviderUri` doc comment for why that's refused.
class SelfReferentialStorageException implements Exception {
  const SelfReferentialStorageException();
}

class ExternalStorageLocationsNotifier extends Notifier<List<ExternalStorageLocation>> {
  static const ExternalStorageRepository _repo = ExternalStorageRepository();

  /// SAF authority of this app's own `ContainerDocumentsProvider` (see the
  /// Kotlin class of that name, and `FolderDocumentProviderHandlers`, which
  /// mounts a single subfolder as its own root under the same provider).
  /// Both "expose the whole unlocked vault" and "expose one subfolder of
  /// it" publish their SAF roots through this one authority, so comparing
  /// against it alone is enough to catch either case -- content already
  /// reachable directly inside the app must not also be pickable back in
  /// as an "external storage" location, which would just be a confusing,
  /// redundant alias for the same data. Must be kept in sync with the
  /// `<provider android:authorities=...>` entry in AndroidManifest.xml.
  static const _kOwnDocumentsProviderAuthority = 'com.aeidolon.vaultexplorer.documents';

  /// True if [treeUri] is (or lives under) this app's own SAF document
  /// provider. Compares the URI's authority component only -- not a
  /// string prefix -- so it can't be fooled or missed by query-string or
  /// path differences between roots.
  static bool _isOwnDocumentsProviderUri(String? treeUri) {
    if (treeUri == null || treeUri.isEmpty) return false;
    try {
      return Uri.parse(treeUri).authority == _kOwnDocumentsProviderAuthority;
    } catch (_) {
      return false;
    }
  }

  @override
  List<ExternalStorageLocation> build() {
    _init();
    return const [];
  }

  Future<void> _init() async {
    state = await _repo.loadAll();
  }

  Future<ExternalStorageLocation?> promptAndAddLocation() async {
    final channel = ref.read(vaultEngineChannelProvider);
    final result = await channel.invokeMapMethod<String, dynamic>(
      ChannelMethods.pickExtractFolder,
    );
    if (result == null) return null;

    // Fast path: the native picker already recognized this as one of our
    // own exposed SAF roots (see `VaultPickerHandlers.pickExtractFolder`)
    // and skipped taking a persistable permission grant for it.
    if (result['selfReference'] == true) {
      VeLog.w(
        'ExternalStorage',
        'promptAndAddLocation: rejected self-referential pick (native flagged it)',''
      );
      throw const SelfReferentialStorageException();
    }

    final rawPath = result['path'] as String?;
    final treeUri = result['treeUri'] as String?;
    var displayName = result['displayName'] as String? ?? '';

    // Defense in depth: refuse it here too, purely from the returned
    // treeUri, in case some other caller ever reaches this point without
    // going through that native check.
    if (_isOwnDocumentsProviderUri(treeUri)) {
      VeLog.w(
        'ExternalStorage',
        'promptAndAddLocation: rejected self-referential pick (treeUri=$treeUri)',''
      );
      throw const SelfReferentialStorageException();
    }

    // NOTE: this only decides what gets stored in `.path` for display/legacy
    // purposes (e.g. showing a real folder path instead of a content:// URI
    // where we have one). It must NOT be used to decide whether raw file
    // access is safe -- `/storage/emulated/0` covers all of shared storage,
    // not just app-private space, so raw POSIX access to an arbitrary
    // folder under it still needs MANAGE_EXTERNAL_STORAGE. Actual access
    // always goes through `ExternalStorageLocation.resolvedUri`, which
    // prefers `treeUri` (a persisted SAF grant) regardless of this flag.
    final isInternalStorage = rawPath != null &&
        (rawPath.startsWith('/storage/emulated/0') || rawPath.startsWith('/data/user/0'));
    final effectivePath = (isInternalStorage ? rawPath : treeUri) ?? treeUri ?? rawPath;

    VeLog.d(
      'ExternalStorage',
      'promptAndAddLocation: rawPath=$rawPath, treeUri=$treeUri, isInternal=$isInternalStorage -> effectivePath=$effectivePath',
    );

    if (effectivePath == null || effectivePath.isEmpty) {
      VeLog.w('ExternalStorage', 'effectivePath is null or empty, aborting', 'empty path');
      return null;
    }

    // Sanitize display names for cloud providers
    if (displayName.isEmpty ||
        displayName == 'Storage' ||
        displayName == 'primary' ||
        displayName.contains('acc=')) {
      if (treeUri != null && treeUri.contains('com.google.android.apps.docs')) {
        displayName = 'Google Drive';
      } else {
        final segments = effectivePath.split('/').where((s) => s.isNotEmpty).toList();
        final last = segments.isNotEmpty ? Uri.decodeComponent(segments.last) : 'Storage';
        displayName = last.contains('acc=') ? 'Cloud Storage' : last;
      }
    } else if (treeUri != null && treeUri.contains('com.google.android.apps.docs')) {
      // e.g. "Google Drive (data)"
      displayName = 'Google Drive ($displayName)';
    }

    var nextVolId = kExternalStorageBaseVolId;
    for (final loc in state) {
      if (loc.volId <= nextVolId) {
        nextVolId = loc.volId - 1;
      }
    }

    final newLocation = ExternalStorageLocation(
      id: 'ext_${DateTime.now().millisecondsSinceEpoch}',
      path: effectivePath,
      treeUri: treeUri,
      displayName: displayName,
      volId: nextVolId,
    );

    state = [...state, newLocation];
    await _repo.saveAll(state);
    VeLog.d('ExternalStorage', 'Successfully saved storage location: ${newLocation.displayName} (volId=${newLocation.volId})');
    return newLocation;
  }

  Future<void> removeLocation(String id) async {
    state = state.where((loc) => loc.id != id).toList();
    await _repo.saveAll(state);
  }

   /// True if [loc] can actually be opened right now.
  ///
  /// For SAF-backed locations (content:// URIs), asks the native SAF engine
  /// to probe whether the persisted grant exists and the storage volume is
  /// currently connected and reachable (e.g. USB drive or SD card is inserted).
  /// For raw filesystem paths, verifies that the directory exists on disk.
  Future<bool> isAccessible(ExternalStorageLocation loc) async {
    final uri = loc.resolvedUri;
    if (uri.isEmpty) return false;
    if (uri.startsWith('content://')) {
      final channel = ref.read(vaultEngineChannelProvider);
      try {
        final accessible = await channel.invokeMethod<bool>(
          ChannelMethods.safCheckTreeAccess,
          {'treeUri': uri},
        );
        return accessible ?? false;
      } catch (e) {
        VeLog.w('ExternalStorage', 'isAccessible check failed for ${loc.displayName}', e);
        return false;
      }
    } else {
      try {
        return Directory(uri).existsSync();
      } catch (e) {
        VeLog.w('ExternalStorage', 'Directory exists check failed for ${loc.displayName}', e);
        return false;
      }
    }
  }

  Future<void> renameLocation(String id, String newName) async {
    state = state.map((loc) {
      if (loc.id == id) {
        return loc.copyWith(displayName: newName);
      }
      return loc;
    }).toList();
    await _repo.saveAll(state);
  }

  MountedContainer? resolveContainer(int volId) {
    for (final loc in state) {
      if (loc.volId == volId) {
        return buildExternalStorageContainer(
          rootPath: loc.resolvedUri,
          displayName: loc.displayName,
          volId: loc.volId,
        );
      }
    }
    return null;
  }
}

final externalStorageLocationsProvider =
    NotifierProvider<ExternalStorageLocationsNotifier, List<ExternalStorageLocation>>(
  ExternalStorageLocationsNotifier.new,
);