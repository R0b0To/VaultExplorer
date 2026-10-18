import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

const int kDecoyLocalVolId = -1;
const int kExternalStorageBaseVolId = -100;

MountedContainer buildLocalStorageContainer({
  required String rootPath,
  required String displayName,
  bool readOnly = false,
}) {
  return MountedContainer(
    uri: rootPath,
    displayName: displayName,
    volId: kDecoyLocalVolId,
    rootFiles: const [],
    mountedAt: DateTime.now(),
    totalSpace: 0,
    freeSpace: 0,
    containerFormat: ContainerFormat.localStorage.wire,
    readOnly: readOnly,
  );
}

MountedContainer buildExternalStorageContainer({
  required String rootPath,
  required String displayName,
  required int volId,
}) {
  return MountedContainer(
    uri: rootPath,
    displayName: displayName,
    volId: volId,
    rootFiles: const [],
    mountedAt: DateTime.now(),
    totalSpace: 0,
    freeSpace: 0,
    containerFormat: ContainerFormat.localStorage.wire,
    readOnly: false,
  );
}

/// Any negative volId is local/external phone storage rather than a native vault
extension LocalStorageContainerX on MountedContainer {
  bool get isLocalStorage => volId < 0;
  bool get isPrimaryLocalStorage => volId == kDecoyLocalVolId;
  bool get isExternalStorage => volId <= kExternalStorageBaseVolId;
  bool get isSafStorage => volId < 0 && uri.startsWith('content://');
  bool get isRawLocal => volId < 0 && !uri.startsWith('content://');

  /// Whether a folder in this container can be handed to the system share
  /// sheet (as a zip streamed out of the vault -- see
  /// `ContainerShareProvider`). Only real vault containers can: device
  /// storage and SAF trees expose files, not a provider that can archive a
  /// subtree on the fly.
  bool get canShareFolders => !isLocalStorage && !isSafStorage;
}
