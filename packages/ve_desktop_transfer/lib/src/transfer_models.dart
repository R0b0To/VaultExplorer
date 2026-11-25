import 'dart:typed_data';
import 'dart:ui' show Offset;

/// A single file or directory included in an outbound drag-and-drop or OS
/// clipboard manifest.
class TransferManifestItem {
  const TransferManifestItem({
    required this.vaultPath,
    required this.name,
    required this.isDir,
    required this.sizeBytes,
    required this.modifiedSecs,
    this.localPath,
  });

  /// Path relative to the volume root (or relative to LocalStorage root).
  final String vaultPath;

  /// Display/export leaf name.
  final String name;
  final bool isDir;
  final int sizeBytes;
  final int modifiedSecs;

  /// Non-null only for plain LocalStorage items that already live on the host
  /// filesystem and need no decryption or staging.
  final String? localPath;

  Map<String, Object?> toMap() => <String, Object?>{
    'vaultPath': vaultPath,
    'name': name,
    'isDir': isDir,
    'sizeBytes': sizeBytes,
    'modifiedSecs': modifiedSecs,
    'localPath': localPath,
  };
}

/// Lightweight metadata describing an outbound drag or OS file clipboard
/// operation. Zero bytes are decrypted until the OS target commits a drop or
/// paste.
class TransferManifest {
  const TransferManifest({
    required this.batchId,
    required this.volId,
    required this.stagingDir,
    required this.items,
    this.preferVirtualStream = false,
    this.isSensitive = true,
  });

  final String batchId;

  /// Engine volume slot (>= 0) or -1 for plain LocalStorage.
  final int volId;

  /// Pre-created private staging directory for lazy decryption (empty when
  /// [volId] < 0).
  final String stagingDir;

  final List<TransferManifestItem> items;

  /// On Windows drag-and-drop, when true, expose CFSTR_FILEDESCRIPTORW +
  /// CFSTR_FILECONTENTS (`IStream`) without `CF_HDROP` so Windows Shell/Explorer
  /// streams directly with zero temp files on disk.
  final bool preferVirtualStream;

  /// Whether to attach Windows clipboard-history/cloud-sync exclusion formats.
  final bool isSensitive;

  Map<String, Object?> toMap() => <String, Object?>{
    'batchId': batchId,
    'volId': volId,
    'stagingDir': stagingDir,
    'preferVirtualStream': preferVirtualStream,
    'isSensitive': isSensitive,
    'items': [for (final item in items) item.toMap()],
  };
}

/// Result of inspecting the current OS clipboard contents.
class ClipboardInspectResult {
  const ClipboardInspectResult({
    required this.hasFiles,
    required this.isOwnFiles,
    required this.ownBatchId,
    required this.filePaths,
    required this.hasImage,
    this.isMove = false,
  });

  final bool hasFiles;
  final bool isOwnFiles;
  final String? ownBatchId;
  final List<String> filePaths;
  final bool hasImage;

  /// True on Linux when `x-special/gnome-copied-files` specifies `cut`.
  final bool isMove;

  factory ClipboardInspectResult.fromMap(Map<Object?, Object?>? map) {
    if (map == null) {
      return const ClipboardInspectResult(
        hasFiles: false,
        isOwnFiles: false,
        ownBatchId: null,
        filePaths: <String>[],
        hasImage: false,
      );
    }
    return ClipboardInspectResult(
      hasFiles: map['hasFiles'] == true,
      isOwnFiles: map['isOwnFiles'] == true,
      ownBatchId: map['ownBatchId'] as String?,
      filePaths: [
        for (final p in (map['filePaths'] as List<Object?>?) ?? const [])
          if (p is String && p.isNotEmpty) p,
      ],
      hasImage: map['hasImage'] == true,
      isMove: map['isMove'] == true,
    );
  }
}

enum DesktopDropEventKind { entered, updated, exited, dropped }

class DesktopDropEvent {
  const DesktopDropEvent({
    required this.kind,
    required this.viewId,
    required this.location,
    this.paths = const <String>[],
  });

  final DesktopDropEventKind kind;
  final int viewId;
  final Offset location;
  final List<String> paths;
}

class DesktopDropDetails {
  const DesktopDropDetails({
    required this.localPosition,
    required this.globalPosition,
    this.paths = const <String>[],
  });

  final Offset localPosition;
  final Offset globalPosition;
  final List<String> paths;
}

class ClipboardImagePayload {
  const ClipboardImagePayload({
    required this.pngBytes,
    required this.rgbaBytes,
    required this.width,
    required this.height,
    this.sensitive = true,
  });

  final Uint8List pngBytes;
  final Uint8List rgbaBytes;
  final int width;
  final int height;
  final bool sensitive;
}
