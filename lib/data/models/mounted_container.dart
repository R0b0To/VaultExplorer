import 'package:vaultexplorer/data/models/container_format.dart';

class MountedContainer {
  final String uri;
  final String displayName;
  final int volId;
  final List<String> rootFiles;
  final DateTime mountedAt;
  final int totalSpace;
  final int freeSpace;
  final String containerFormat;
  final bool readOnly;   
  final int? occupiedSpace;

  const MountedContainer({
    required this.uri,
    required this.displayName,
    required this.volId,
    required this.rootFiles,
    required this.mountedAt,
    required this.totalSpace,
    required this.freeSpace,
    this.containerFormat = 'veracrypt',
    this.readOnly = false,   
    this.occupiedSpace,
  });

  MountedContainer copyWith({
    String? displayName,
    List<String>? rootFiles,
    int? totalSpace,
    int? freeSpace,
    String? containerFormat,
    bool? readOnly,   
    int? occupiedSpace,
  }) {
    return MountedContainer(
      uri: uri,
      displayName: displayName ?? this.displayName,
      volId: volId,
      rootFiles: rootFiles ?? this.rootFiles,
      mountedAt: mountedAt,
      totalSpace: totalSpace ?? this.totalSpace,
      freeSpace: freeSpace ?? this.freeSpace,
      containerFormat: containerFormat ?? this.containerFormat,
      readOnly: readOnly ?? this.readOnly,   
      occupiedSpace: occupiedSpace ?? this.occupiedSpace,
    );
  }
}

extension MountedContainerFormatX on MountedContainer {
  /// Typed classification of [containerFormat]. See [ContainerFormat].
  ContainerFormat get format => ContainerFormat.fromWire(containerFormat);
}
