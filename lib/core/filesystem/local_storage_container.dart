import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Sentinel [MountedContainer.volId] standing in for local phone storage.
///
/// Never a real native mount -- [FileOperationService.enqueueLocalTransfer]
/// and [resolveFilesystemType] special-case this volId to perform plain
/// dart:io I/O instead of a native container call. Chosen as a negative
/// number since real mounted containers' volIds are always non-negative.
const int kDecoyLocalVolId = -1;

/// Builds a [MountedContainer] standing in for local phone storage, so the
/// decoy's local explorer can reuse the same volId-keyed selection/sort
/// controllers, [CrossContainerClipboard], and rename dialog the vault
/// file manager uses, instead of a second, parallel implementation of
/// each. See [kDecoyLocalVolId].
MountedContainer buildLocalStorageContainer({
  required String rootPath,
  required String displayName,
}) {
  return MountedContainer(
    uri: rootPath,
    displayName: displayName,
    volId: kDecoyLocalVolId,
    rootFiles: const [],
    mountedAt: DateTime.now(),
    totalSpace: 0,
    freeSpace: 0,
    readOnly: false,
  );
}
