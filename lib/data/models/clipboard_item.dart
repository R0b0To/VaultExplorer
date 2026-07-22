import 'package:flutter/foundation.dart';

/// A single item staged for copy or move.
///
/// Replaces the stringly-typed `Map<String, dynamic>` that was previously
/// passed through [CrossContainerClipboard] and [FileBrowserScreen._paste].
///
/// [path]         — full FAT path relative to the container root, e.g. `"docs/report.pdf"`.
/// [isDir]        — true when the item is a directory.
/// [sizeBytes]    — byte size for files; 0 for directories (resolved lazily
///                  by [FileOperationService] during the space pre-flight).
/// [modifiedSecs] — last-modified time in Unix seconds (UTC).
@immutable
class ClipboardItem {
  final String path;
  final bool isDir;
  final int sizeBytes;
  final int modifiedSecs;

  const ClipboardItem({
    required this.path,
    required this.isDir,
    this.sizeBytes = 0,
    this.modifiedSecs = 0,
  });

  /// The leaf name of this item (last path segment).
  String get name => path.split('/').last;

  // ── Serialisation ─────────────────────────────────────────────────────────
  //
  // CrossContainerClipboard is in-memory only, so these exist mainly for
  // debugging / future persistence.

  Map<String, dynamic> toJson() => {
    'path': path,
    'isDir': isDir,
    'sizeBytes': sizeBytes,
    'modifiedSecs': modifiedSecs,
  };

  factory ClipboardItem.fromJson(Map<String, dynamic> j) => ClipboardItem(
    path: j['path'] as String,
    isDir: j['isDir'] as bool? ?? false,
    sizeBytes: j['sizeBytes'] as int? ?? 0,
    modifiedSecs: j['modifiedSecs'] as int? ?? 0,
  );

  ClipboardItem copyWith({
    String? path,
    bool? isDir,
    int? sizeBytes,
    int? modifiedSecs,
  }) =>
      ClipboardItem(
        path: path ?? this.path,
        isDir: isDir ?? this.isDir,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        modifiedSecs: modifiedSecs ?? this.modifiedSecs,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClipboardItem &&
          other.path == path &&
          other.isDir == isDir &&
          other.sizeBytes == sizeBytes &&
          other.modifiedSecs == modifiedSecs;

  @override
  int get hashCode => Object.hash(path, isDir, sizeBytes, modifiedSecs);

  @override
  String toString() =>
      'ClipboardItem(${isDir ? "DIR" : "FILE"} $path, ${sizeBytes}B, ts=$modifiedSecs)';
}
