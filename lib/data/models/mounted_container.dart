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
  });

  MountedContainer copyWith({
    String? displayName,
    List<String>? rootFiles,
    int? totalSpace,
    int? freeSpace,
    String? containerFormat,
    bool? readOnly,   
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
    );
  }
}

extension MountedContainerFormatX on MountedContainer {
  /// Typed classification of [containerFormat]. See [ContainerFormat].
  ContainerFormat get format => ContainerFormat.fromWire(containerFormat);
}
