import 'package:meta/meta.dart';

/// Canonical parser for the directory-entry wire format produced by every
/// backend (`fat_backend.cpp`, `ntfs_backend.cpp`, `ext_backend.cpp`,
/// `foldervault_bridge.cpp` (gocryptfs / Cryptomator / CryFS),
/// `archive_context.dart`) — see docs/architecture.md §5.3 and ADR-003.
///
/// Wire layout — an explicit type tag, then three more fields, joined by
/// `|`, with the name always last:
///
///   "F|sizeBytes|unixSecs|name"   (file)
///   "D|0|unixSecs|name"           (directory)
///   "L|targetBytes|unixSecs|name" (symbolic link to a file / broken link)
///   "LD|0|unixSecs|name"          (symbolic link to a directory)
///
/// The type is a real field (`F`, `D`, `L` or `LD`), never inferred from the name — and
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

  /// True when this entry is a symbolic link. The entry keeps
  /// its link path for rename/delete, while content access follows its target.
  final bool isSymlink;

  /// Byte size of the file.  Always 0 for directories; call [getFolderSize]
  /// for the real recursive total.
  final int sizeBytes;

  /// Last-modified time in Unix seconds (UTC).  0 = unknown / not recorded.
  final int modifiedSecs;

  /// True when this entry is a temporary visual placeholder for an item
  /// currently being transferred/imported into this directory.
  final bool isPlaceholder;
  final String? _lowercaseName;
  final String? _extension;

  const RawEntry({
    required this.name,
    required this.isDir,
    this.isSymlink = false,
    required this.sizeBytes,
    required this.modifiedSecs,
    this.isPlaceholder = false,
    String? lowercaseName,
    String? extension,
  })  : _lowercaseName = lowercaseName,
        _extension = extension;

  String get lowercaseName => _lowercaseName ?? name.toLowerCase();
  String get extension => _extension ?? _extensionOf(name, lowerCase: true);

  /// The part of [name] after its last `.` (empty when there is no dot).
  ///
  /// Same result as `name.contains('.') ? name.split('.').last : ''`, without
  /// building a list of every dot-separated piece for each entry: a listing
  /// of a few thousand files used to allocate that list once per file.
  static String _extensionOf(String name, {required bool lowerCase}) {
    final dot = name.lastIndexOf('.');
    if (dot < 0) return '';
    final ext = name.substring(dot + 1);
    return lowerCase ? ext.toLowerCase() : ext;
  }

  /// Parses `raw[start, end)` as a non-negative decimal, or returns -1 when it
  /// is empty, too long to be sure of, or holds anything but digits (the
  /// caller then falls back to `int.tryParse`, so odd input behaves exactly as
  /// before). Avoids allocating a substring per numeric field.
  static int _parseDigits(String raw, int start, int end) {
    final len = end - start;
    if (len <= 0 || len > 18) return -1;
    var value = 0;
    for (var i = start; i < end; i++) {
      final digit = raw.codeUnitAt(i) - 0x30;
      if (digit < 0 || digit > 9) return -1;
      value = value * 10 + digit;
    }
    return value;
  }

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

    // Type tag: "F", "D", "L" or "LD". Read from the code units rather than
    // slicing a one/two character substring out of every line.
    var isDir = false;
    var isSymlink = false;
    if (firstSep == 1) {
      final tag = raw.codeUnitAt(0);
      isDir = tag == 0x44; // D
      isSymlink = tag == 0x4C; // L
    } else if (firstSep == 2 &&
        raw.codeUnitAt(0) == 0x4C && // L
        raw.codeUnitAt(1) == 0x44) {
      // D
      isDir = true;
      isSymlink = true;
    }

    var size = _parseDigits(raw, firstSep + 1, secondSep);
    if (size < 0) {
      size = int.tryParse(raw.substring(firstSep + 1, secondSep)) ?? 0;
    }
    var mtime = _parseDigits(raw, secondSep + 1, thirdSep);
    if (mtime < 0) {
      mtime = int.tryParse(raw.substring(secondSep + 1, thirdSep)) ?? 0;
    }

    final name = raw.substring(thirdSep + 1);
    final lower = name.toLowerCase();

    return RawEntry(
      name: name,
      isDir: isDir,
      isSymlink: isSymlink,
      sizeBytes: size,
      modifiedSecs: mtime,
      lowercaseName: lower,
      extension: _extensionOf(lower, lowerCase: false),
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
  static List<RawEntry> parseAll(Iterable<String> rawList) {
    final out = <RawEntry>[];
    for (final raw in rawList) {
      if (raw.startsWith('System:')) continue;
      out.add(RawEntry.parse(raw));
    }
    return out;
  }

  /// True when [a] and [b] hold equal entries in the same order.
  ///
  /// A listing that is refreshed in the background usually comes back
  /// unchanged; callers use this to keep the list instance they already have,
  /// so everything keyed on that instance (sorted/filtered views, layout)
  /// stays valid instead of being rebuilt for identical content.
  static bool sameEntries(List<RawEntry> a, List<RawEntry> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Reconstructs the canonical wire string.
  ///
  /// Use when the raw form is required — e.g. a stable [ValueKey] for a
  /// list row, or passing an entry back through a platform channel call
  /// that still expects the wire format. Most in-app state (like
  /// [FileBrowserSelectionState.items]) holds [RawEntry] values directly and
  /// has no need to round-trip through this.
  String get raw =>
      '${isSymlink ? (isDir ? 'LD' : 'L') : isDir ? 'D' : 'F'}|$sizeBytes|$modifiedSecs|$name';

  /// This entry under a different [newName] (deep-search results, whose name
  /// is the path relative to the folder searched from).
  ///
  /// The lowercase name and extension are worked out once here. An entry
  /// built through the plain constructor recomputes both on every
  /// [lowercaseName]/[extension] read, and a sort reads them twice per
  /// comparison, so a few thousand results meant tens of thousands of
  /// throwaway strings per rebuild. The formulas are the same ones the
  /// getters fall back to, so the values are identical.
  RawEntry withName(String newName) => RawEntry(
    name: newName,
    isDir: isDir,
    isSymlink: isSymlink,
    sizeBytes: sizeBytes,
    modifiedSecs: modifiedSecs,
    isPlaceholder: isPlaceholder,
    lowercaseName: newName.toLowerCase(),
    extension: _extensionOf(newName, lowerCase: true),
  );

  /// Modification date/time, or null when the FAT timestamp is absent.
  DateTime? get modifiedAt => modifiedSecs > 0
      ? DateTime.fromMillisecondsSinceEpoch(modifiedSecs * 1000)
      : null;

  /// Value equality on the same fields the wire string encodes, so a
  /// [RawEntry] can be used as a `Set`/`Map` key exactly like the raw
  /// string it replaces (e.g. [FileBrowserSelectionState.items]). Two entries
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
          other.isSymlink == isSymlink &&
          other.sizeBytes == sizeBytes &&
          other.modifiedSecs == modifiedSecs &&
          other.isPlaceholder == isPlaceholder;

  @override
  int get hashCode => Object.hash(name, isDir, isSymlink, sizeBytes, modifiedSecs, isPlaceholder);

  @override
  String toString() =>
      'RawEntry(${isDir ? "DIR" : "FILE"} $name, '
      '${sizeBytes}B, ts=$modifiedSecs${isPlaceholder ? ", placeholder" : ""})';
}

/// A directory listing already parsed into [RawEntry] values, plus whether
/// native had to cut it short.
///
/// What the interactive browser actually wants from a listing. Producing this
/// directly lets sources that already hold [RawEntry] values (plain device
/// storage) skip formatting every entry into a wire string just so it can be
/// parsed straight back, and parses the wire form and looks for the
/// `System:TRUNCATED` marker in a single pass for the sources that don't.
class ParsedDirectoryListing {
  const ParsedDirectoryListing(
    this.entries, {
    this.truncated = false,
    this.preSortedByNameAsc = false,
  });

  /// Parses wire-format lines (see [RawEntry.parse]); `System:*` sentinel
  /// lines are dropped, and `System:TRUNCATED` sets [truncated].
  factory ParsedDirectoryListing.fromWire(Iterable<String> rawList) {
    final out = <RawEntry>[];
    var truncated = false;
    for (final raw in rawList) {
      if (raw.startsWith('System:')) {
        if (raw == 'System:TRUNCATED') truncated = true;
        continue;
      }
      out.add(RawEntry.parse(raw));
    }
    return ParsedDirectoryListing(out, truncated: truncated);
  }

  final List<RawEntry> entries;

  /// True when the folder has more children than native was willing to list.
  final bool truncated;

  /// True when [entries] are already partitioned (dirs first) and sorted by
  /// [naturalCompare] on `lowercaseName` ascending.
  final bool preSortedByNameAsc;
}
