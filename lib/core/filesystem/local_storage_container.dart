import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

const int kDecoyLocalVolId = -1;
const int kExternalStorageBaseVolId = -100;

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
    containerFormat: ContainerFormat.localStorage.wire,
    readOnly: false,
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
}