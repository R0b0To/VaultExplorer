import 'package:flutter/foundation.dart';

/// Canonical parser for the wire format produced by [buildDirectoryListing] in C++.
///
/// Wire layout — three pipe-separated fields:
///
///   file:       "name|sizeBytes|unixSecs"
///   directory:  "[DIR] name|0|unixSecs"
///
/// [unixSecs] is 0 when the FAT entry carries no real-time-clock data
/// (files created on-device with FF_FS_NORTC=1 in ffconf.h will have 0).
///
/// All Dart code that previously parsed raw strings manually should call
/// [RawEntry.parse] instead.  This keeps format changes in one place.
@immutable
class RawEntry {
  final String name;
  final bool isDir;

  /// Byte size of the file.  Always 0 for directories; call [getFolderSize]
  /// for the real recursive total.
  final int sizeBytes;

  /// Last-modified time in Unix seconds (UTC).  0 = unknown / not recorded.
  final int modifiedSecs;

  const RawEntry({
    required this.name,
    required this.isDir,
    required this.sizeBytes,
    required this.modifiedSecs,
  });

  /// Parses one entry from [buildDirectoryListing] output.
  factory RawEntry.parse(String raw) {
    final isDir = raw.startsWith('[DIR] ');
    // Strip the six-character prefix so both branches share the same
    // "name|size|ts" splitting logic.
    final body = isDir ? raw.substring(6) : raw;
    final parts = body.split('|');
    return RawEntry(
      name: parts[0],
      isDir: isDir,
      sizeBytes: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      modifiedSecs: parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0,
    );
  }

  /// Reconstructs the canonical wire string.
  ///
  /// Use when the raw form is required — e.g. a stable [ValueKey] for a
  /// list row, or passing an entry back through a platform channel call
  /// that still expects the wire format. Most in-app state (like
  /// [SelectionMixin.selectedItems]) holds [RawEntry] values directly and
  /// has no need to round-trip through this.
  String get raw => isDir
      ? '[DIR] $name|$sizeBytes|$modifiedSecs'
      : '$name|$sizeBytes|$modifiedSecs';

  /// Modification date/time, or null when the FAT timestamp is absent.
  DateTime? get modifiedAt => modifiedSecs > 0
      ? DateTime.fromMillisecondsSinceEpoch(modifiedSecs * 1000)
      : null;

  /// Value equality on the same fields the wire string encodes, so a
  /// [RawEntry] can be used as a `Set`/`Map` key exactly like the raw
  /// string it replaces (e.g. [SelectionMixin.selectedItems]). Two entries
  /// from the *same* directory listing can never legitimately share
  /// name+isDir+size+timestamp, so this is a safe identity proxy within one
  /// listing — the same guarantee the original string-based `Set<String>`
  /// relied on.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RawEntry &&
          other.name == name &&
          other.isDir == isDir &&
          other.sizeBytes == sizeBytes &&
          other.modifiedSecs == modifiedSecs;

  @override
  int get hashCode => Object.hash(name, isDir, sizeBytes, modifiedSecs);

  @override
  String toString() =>
      'RawEntry(${isDir ? "DIR" : "FILE"} $name, '
      '${sizeBytes}B, ts=$modifiedSecs)';
}
