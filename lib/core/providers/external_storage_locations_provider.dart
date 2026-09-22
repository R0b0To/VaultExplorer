import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/external_storage_repository.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

class ExternalStorageLocationsNotifier extends Notifier<List<ExternalStorageLocation>> {
  static const ExternalStorageRepository _repo = ExternalStorageRepository();

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

    final rawPath = result['path'] as String?;
    final treeUri = result['treeUri'] as String?;
    var displayName = result['displayName'] as String? ?? '';

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