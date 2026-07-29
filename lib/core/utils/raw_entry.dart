import 'package:flutter/foundation.dart';

/// Canonical parser for the directory-entry wire format produced by every
/// backend (`fat_backend.cpp`, `ntfs_backend.cpp`, `ext_backend.cpp`,
/// `CryfsSession.kt`, `CryptomatorSession.kt`, `GocryptfsSession.kt`,
/// `archive_context.dart`) — see docs/architecture.md §5.3 and ADR-003.
///
/// Wire layout — an explicit type tag, then three more fields, joined by
/// `|`, with the name always last:
///
///   "F|sizeBytes|unixSecs|name"   (file)
///   "D|0|unixSecs|name"           (directory)
///
/// The type is a real field (`F`/`D`), never inferred from the name — and
/// the name is *everything after the third `|`*, not "up to the next `|`",
/// so a name that itself contains `|` (legal on ext2/3/4) round-trips
/// exactly instead of corrupting the fields after it. Previously this used
/// a `"[DIR] "` prefix on the name to signal "this is a directory", which
/// both misclassified any real file legitimately named starting with
/// "[DIR] " and shifted every subsequent field for any name containing
/// `|`; ADR-002/ADR-003 removed both bugs at the source instead of working
/// around them by rewriting user-chosen names.
///
/// [unixSecs] is 0 when the entry carries no real-time-clock data (e.g.
/// FAT files created on-device with FF_FS_NORTC=1 in ffconf.h).
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

  /// Parses one entry from the directory-listing wire format described
  /// above. The type tag is read as an explicit field, and the name is
  /// captured as everything after the third `|` — never inferred from a
  /// prefix, never split further even if it contains `|` itself.
  ///
  /// Throws a [FormatException] if [raw] doesn't have the three separators
  /// this format requires. Every producer of this format ships in the same
  /// app build as this parser, so a malformed string here is a genuine bug
  /// in a producer, not something to guess around.
  factory RawEntry.parse(String raw) {
    final firstSep = raw.indexOf('|');
    final secondSep = firstSep < 0 ? -1 : raw.indexOf('|', firstSep + 1);
    final thirdSep = secondSep < 0 ? -1 : raw.indexOf('|', secondSep + 1);
    if (firstSep < 0 || secondSep < 0 || thirdSep < 0) {
      throw FormatException(
        'Malformed directory-entry wire string (expected '
        '"F|size|mtime|name" or "D|size|mtime|name"): "$raw"',
      );
    }

    final typeTag = raw.substring(0, firstSep);
    final sizeStr = raw.substring(firstSep + 1, secondSep);
    final mtimeStr = raw.substring(secondSep + 1, thirdSep);
    final name = raw.substring(thirdSep + 1);

    return RawEntry(
      name: name,
      isDir: typeTag == 'D',
      sizeBytes: int.tryParse(sizeStr) ?? 0,
      modifiedSecs: int.tryParse(mtimeStr) ?? 0,
    );
  }

  /// Parses every entry in [rawList], skipping the `"System:*"` sentinel
  /// lines (e.g. `"System:TRUNCATED"`) that native emits when a directory
  /// has too many children to list in full.
  ///
  /// Prefer this over manually filtering and calling [RawEntry.parse] in a
  /// loop: every hand-written `if (raw.startsWith('System:')) continue`
  /// guard is one omission away from [RawEntry.parse] throwing a
  /// [FormatException] on a sentinel line it was never meant to see.
  static List<RawEntry> parseAll(Iterable<String> rawList) => rawList
      .where((raw) => !raw.startsWith('System:'))
      .map(RawEntry.parse)
      .toList();

  /// Reconstructs the canonical wire string.
  ///
  /// Use when the raw form is required — e.g. a stable [ValueKey] for a
  /// list row, or passing an entry back through a platform channel call
  /// that still expects the wire format. Most in-app state (like
  /// [SelectionMixin.selectedItems]) holds [RawEntry] values directly and
  /// has no need to round-trip through this.
  String get raw => '${isDir ? 'D' : 'F'}|$sizeBytes|$modifiedSecs|$name';

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
