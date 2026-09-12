/// Fraction of a destination's reported free space held back as a safety
/// cushion when checking whether a transfer will fit, to absorb real
/// per-transfer overhead -- filesystem cluster/directory-entry rounding, or
/// per-file header plus per-block MAC/IV overhead in the directory-based
/// vault formats (Cryptomator/gocryptfs/CryFS) -- that isn't reflected in a
/// raw source byte count.
///
/// Deliberately small: real overhead for a modest number of reasonably
/// sized files is nowhere near 5%, and reserving that much rejected
/// transfers that would genuinely have fit (an 8-file/138MB import into a
/// vault with 142MB free, for example). Used by `file_operation_service.dart`
/// (intra-vault copy/move) and `vault_sync_controller.dart`. Mirrored by
/// `SPACE_SAFETY_MARGIN` in ImportExportHandlers.kt on the Kotlin side --
/// keep both in sync if this changes.
const double kFreeSpaceSafetyMargin = 0.01;

/// True if [requiredBytes] fits within [freeBytes] once
/// [kFreeSpaceSafetyMargin] is held back. The predicate behind the
/// insufficient-space checks in `file_operation_service.dart` (intra-vault
/// copy/move) and `vault_sync_controller.dart`, pulled out as a pure
/// function so it's directly testable without a live container/session --
/// see file_size_test.dart. Mirrored by
/// `ImportExportHandlers.fitsWithinSafetyMargin` on the Kotlin side.
bool fitsWithinSpaceSafetyMargin(int requiredBytes, int freeBytes) =>
    requiredBytes <= (freeBytes * (1 - kFreeSpaceSafetyMargin)).floor();

/// A file (or recursive folder) size as an explicit value type, instead of
/// a bare `int` that every call site has to remember is "bytes, right?".
///
/// This exists specifically to keep size decoupled from name/path (see
/// docs/architecture.md ADR-002, ownership rule #6): a [FileSize] never
/// carries a name, and nothing in name/path validation ever reads one.
/// `RawEntry.sizeBytes` (the existing field used throughout the app) stays
/// a plain `int` for compatibility — [FileSize.formatted] is implemented in
/// terms of the same table `format_utils.dart`'s `formatBytes` already
/// uses, so both stay in sync; new code that needs a size to carry its
/// unit with it (validation messages, size-limit checks, anything crossing
/// a boundary where "bytes" isn't obvious from context) should prefer this.
class FileSize {
  /// Always non-negative, always bytes — the one canonical representation.
  final int bytes;

  const FileSize.bytes(this.bytes) : assert(bytes >= 0);

  // ── Binary (IEC / 1024-based) Constructors ─────────────────────────────────
  // Primary constructors for vault containers, cluster sizes, and file buffers.
  factory FileSize.kibibytes(num kib) => FileSize.bytes((kib * 1024).round());
  factory FileSize.mebibytes(num mib) =>
      FileSize.bytes((mib * 1024 * 1024).round());
  factory FileSize.gibibytes(num gib) =>
      FileSize.bytes((gib * 1024 * 1024 * 1024).round());

  // ── Decimal (SI / 1000-based) Constructors ────────────────────────────────
  // For networking/hardware-rated decimal definitions if explicitly needed.
  factory FileSize.kilobytes(num kb) => FileSize.bytes((kb * 1000).round());
  factory FileSize.megabytes(num mb) =>
      FileSize.bytes((mb * 1000 * 1000).round());
  factory FileSize.gigabytes(num gb) =>
      FileSize.bytes((gb * 1000 * 1000 * 1000).round());

  static const zero = FileSize.bytes(0);

  bool operator >(FileSize other) => bytes > other.bytes;
  bool operator <(FileSize other) => bytes < other.bytes;
  bool operator >=(FileSize other) => bytes >= other.bytes;
  bool operator <=(FileSize other) => bytes <= other.bytes;

  @override
  bool operator ==(Object other) => other is FileSize && other.bytes == bytes;

  @override
  int get hashCode => bytes.hashCode;

  /// Binary (1024-based) human-readable form, e.g. "4.2 MB", "512 B".
  /// Matches `format_utils.dart`'s `formatBytes` exactly — see that file
  /// for the precision/threshold table this defers to.
  String get formatted => formatByteCount(bytes);

  @override
  String toString() => '$bytes bytes';
}

/// Shared formatting table used by both [FileSize.formatted] and the
/// pre-existing `formatBytes` free function in `format_utils.dart`
/// (`formatBytes` now just calls this), so there is exactly one place that
/// decides what "4.2 MB" means. Behavior is unchanged from the original
/// `formatBytes` implementation this replaces — same suffix table, same
/// "one decimal only when the value is under 10 and not in raw bytes" rule.
String formatByteCount(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final decimals = (value < 10 && unitIndex > 0) ? 1 : 0;
  var formatted = value.toStringAsFixed(decimals);
  if (formatted.endsWith('.0')) {
    formatted = formatted.substring(0, formatted.length - 2);
  }
  return '$formatted ${units[unitIndex]}';
}