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

  Future<void> _init() => refreshSystemVolumes();

  /// Prefix of auto-discovered physical-volume entries (SD card, USB OTG).
  /// These are NOT persisted: they're recomputed from [StorageManager] on
  /// every init/refresh, so a volume that's unplugged simply disappears.
  /// See [ExternalStorageLocation.systemVolumeIdPrefix].
  static const _kSystemVolumeIdPrefix = ExternalStorageLocation.systemVolumeIdPrefix;

  /// Auto-discovers storage volumes (SD cards, USB OTG drives) through
  /// the native `getStorageVolumes` channel method and returns them as
  /// raw-path [ExternalStorageLocation]s.
  ///
  /// Requires "All files access" ([MANAGE_EXTERNAL_STORAGE]): the raw
  /// `/storage/<uuid>` paths only list correctly with it granted. They are
  /// deliberately NOT SAF-backed.
  Future<List<ExternalStorageLocation>> _fetchSystemVolumes(
    List<ExternalStorageLocation> persisted, {
    required Map<String, int> previousSystemVolIds,
  }) async {
    final channel = ref.read(vaultEngineChannelProvider);
    try {
      final volumes =
          await channel.invokeListMethod<Map<dynamic, dynamic>>(ChannelMethods.getStorageVolumes);
      if (volumes == null) return const [];

      // System volumes get volIds strictly below every persisted location,
      // keeping the existing "persisted first, newer below" ordering intact
      // (promptAndAddLocation decrements from the lowest it sees, which now
      // includes these). Previously handed-out IDs are preserved by native
      // volume id so a refresh can't renumber a volume still being shown in
      // an open tab.
      var nextVolId = kExternalStorageBaseVolId;
      for (final loc in persisted) {
        if (loc.volId <= nextVolId) nextVolId = loc.volId - 1;
      }
      for (final volId in previousSystemVolIds.values) {
        if (volId <= nextVolId) nextVolId = volId - 1;
      }
      final usedVolIds = {
        ...persisted.map((loc) => loc.volId),
        ...previousSystemVolIds.values,
      };

      final result = <ExternalStorageLocation>[];
      final existingKeys = persisted
          .expand((loc) => [loc.path, if (loc.treeUri != null) loc.treeUri!])
          .toSet();
      for (final vol in volumes) {
        final id = vol['id'] as String? ?? '';
        final isPrimary = vol['isPrimary'] == true;
        final isRemovable = vol['isRemovable'] == true;
        final state = vol['state'] as String? ?? '';
        final path = vol['path'] as String? ?? '';
        final desc = vol['description'] as String? ?? '';

        // Only removable, actually-mounted, non-primary volumes. The
        // primary internal volume is already covered by the built-in
        // "Local Storage" container (kDecoyLocalVolId).
        if (isPrimary || !isRemovable || state != 'mounted' || path.isEmpty) {
          continue;
        }
        // Skip if the user already added this exact root (or the volume's
        // path matches an existing entry's resolved location).
        if (existingKeys.contains(path) || existingKeys.contains(id)) continue;

        int? volId = previousSystemVolIds[id];
        if (volId != null && !usedVolIds.add(volId)) {
          volId = null;
        }
        volId ??= nextVolId--;
        usedVolIds.add(volId);

        result.add(ExternalStorageLocation(
          id: '$_kSystemVolumeIdPrefix$id',
          path: path,
          displayName: desc.isEmpty ? id : desc,
          volId: volId,
        ));
        existingKeys.add(path);
      }
      return result;
    } catch (e) {
      VeLog.w('ExternalStorage', 'Failed to discover system storage volumes', e);
      return const [];
    }
  }

  /// Re-runs system-volume discovery (SD card / USB hot-plug, e.g. after
  /// the app resumes with a new volume attached) and rebuilds the state
  /// from disk + volumes. User-added SAF locations are reloaded from disk,
  /// so an in-flight rename/add that wasn't saved yet is lost -- call this
  /// only at idle points (init, app resume).
  Future<void> refreshSystemVolumes() async {
    final persisted = (await _repo.loadAll())
        .where((loc) => !loc.id.startsWith(_kSystemVolumeIdPrefix))
        .toList();
    // Snapshot the volIds already handed out, keyed by native volume id, so
    // unplugging a *different* volume (or adding a persisted location) can't
    // renumber the volumes this session has already opened in tabs.
    //
    // This deliberately happens after the await above: `_init()` is called
    // from `build()` before the notifier's initial state is published, so
    // reading `state` synchronously there can throw.
    final previousSystemVolIds = {
      for (final loc in state)
        if (loc.isSystemVolume)
          loc.id.substring(_kSystemVolumeIdPrefix.length): loc.volId,
    };
    final system = await _fetchSystemVolumes(
      persisted,
      previousSystemVolIds: previousSystemVolIds,
    );
    state = [...persisted, ...system];
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
    await _savePersisted();
    VeLog.d('ExternalStorage', 'Successfully saved storage location: ${newLocation.displayName} (volId=${newLocation.volId})');
    return newLocation;
  }

  Future<void> removeLocation(String id) async {
    // System-discovered volumes (SD cards, USB) cannot be removed: they
    // are re-derived from StorageManager on every refresh anyway, and a
    // "removed" device would silently come back -- which must not happen.
    if (id.startsWith(_kSystemVolumeIdPrefix)) return;
    state = state.where((loc) => loc.id != id).toList();
    await _savePersisted();
  }

  /// Writes only user-added locations to disk; ephemeral system-volume
  /// entries never reach the JSON file.
  Future<void> _savePersisted() async {
    await _repo.saveAll(
      state.where((loc) => !loc.id.startsWith(_kSystemVolumeIdPrefix)).toList(),
    );
  }

   /// True if [loc] can actually be opened right now.
  ///
  /// For SAF-backed locations (content:// URIs), asks the native SAF engine
  /// to probe whether the persisted grant exists and the storage volume is
  /// currently connected and reachable (e.g. USB drive or SD card is inserted).
  /// For raw filesystem paths, verifies that the directory exists on disk.
  Future<bool> isAccessible(ExternalStorageLocation loc) async {
    final uri = loc.resolvedUri;
    if (uri.isEmpty) {
      VeLog.w('ExternalStorage', 'isAccessible failed: resolved URI is empty');
      return false;
    }
    if (uri.startsWith('content://')) {
      final channel = ref.read(vaultEngineChannelProvider);
      try {
        final accessible = await channel.invokeMethod<bool>(
          ChannelMethods.safCheckTreeAccess,
          {'treeUri': uri},
        );
        final result = accessible ?? false;
        VeLog.d(
          'ExternalStorage',
          'SAF access probe ${VeLog.censorUri(uri)} returned $result',
        );
        return result;
      } catch (e) {
        VeLog.w(
          'ExternalStorage',
          'SAF access probe failed for ${VeLog.censorUri(uri)} (${e.runtimeType})',
        );
        return false;
      }
    } else {
      try {
        final exists = Directory(uri).existsSync();
        VeLog.d('ExternalStorage', 'Raw path access probe returned $exists');
        return exists;
      } catch (e) {
        VeLog.w(
          'ExternalStorage',
          'Raw path access probe failed (${e.runtimeType})',
        );
        return false;
      }
    }
  }

  Future<void> renameLocation(String id, String newName) async {
    // System-discovered volumes keep their StorageManager-provided name.
    if (id.startsWith(_kSystemVolumeIdPrefix)) return;
    state = state.map((loc) {
      if (loc.id == id) {
        return loc.copyWith(displayName: newName);
      }
      return loc;
    }).toList();
    await _savePersisted();
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
