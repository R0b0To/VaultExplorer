import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// The concrete filesystem (or vault-format equivalent) that a name is
/// being validated against. See docs/architecture.md, ADR-002 and §5.4/§1.
///
/// This is the one piece of context [validateEntryName] (name_validation.dart)
/// needs in order to give a *precise* answer instead of a generic one — the
/// same string ("CON.txt", or a name with a trailing space) is illegal on
/// one of these and perfectly legal on another, so validation must never be
/// done against an assumed/one-size-fits-all rule set.
enum FilesystemType {
  /// FAT32, as mounted by the native FatFs backend (`fat_backend.cpp`).
  fat32,

  /// exFAT, as mounted by the same FatFs backend (FatFs handles both under
  /// one `FS_FATFS` volume kind; see ADR-005 for distinguishing them at
  /// runtime instead of applying the union of both rule sets).
  exfat,

  /// NTFS, as mounted by NTFS-3G (`ntfs_backend.cpp`).
  ntfs,

  /// ext2/3/4, as mounted by libext2fs (`ext_backend.cpp`). The three ext
  /// generations share an identical naming grammar, so one entry covers all
  /// three.
  ext,

  /// CryFS / Cryptomator / gocryptfs: names are encrypted before they ever
  /// touch a host filesystem, so almost no host-filesystem character rule
  /// applies to the plaintext name the user types. See
  /// [FilesystemRules.encryptedVault] for the (app-level, not fs-level)
  /// restrictions that still apply.
  encryptedVault,

  /// Used when the real target filesystem isn't known at the call site
  /// (see ADR-005) — a plain SAF-backed folder vault, or a native
  /// disk-image container whose exact FAT/exFAT/NTFS/ext kind hasn't been
  /// threaded through yet. Applies the union of every restriction below, so
  /// a name accepted here is guaranteed valid on any of the concrete types.
  /// This can reject some names that would actually be fine on the real
  /// target — that's the intended, conservative trade-off: never
  /// under-restrict just because the concrete type is unknown.
  unknownConservative;

  /// Short label for error messages, e.g. "NTFS", "ext2/3/4". Filesystem
  /// format names are technical terms and are intentionally left
  /// untranslated across every locale (see implementation_plan.md's open
  /// question on VeraCrypt/LUKS-style jargon) — only the two generic,
  /// natural-language fallbacks are localized.
  String label(AppLocalizations l10n) => switch (this) {
        FilesystemType.fat32 => 'FAT32',
        FilesystemType.exfat => 'exFAT',
        FilesystemType.ntfs => 'NTFS',
        FilesystemType.ext => 'ext2/3/4',
        FilesystemType.encryptedVault => l10n.filesystemLabelEncryptedVault,
        FilesystemType.unknownConservative => l10n.filesystemLabelThisContainer,
      };
}

/// Immutable per-[FilesystemType] rule table. Every rule here is a fact
/// about the real filesystem (or, for [FilesystemType.encryptedVault], a
/// documented app-level choice) — nothing here is a stylistic preference.
class FilesystemRules {
  /// Characters illegal anywhere in a single path component (not the whole
  /// path — `/` is always illegal in a component because it's the
  /// component separator, regardless of filesystem).
  final Set<int> illegalCharCodes;

  /// Whether ASCII control characters (0x00–0x1F) and DEL (0x7F) are
  /// illegal. True for every filesystem this app mounts natively; ext2/3/4
  /// technically permits them (only NUL and `/` are truly illegal at the
  /// ext level) but they are rejected here too since they are either
  /// unrepresentable or invisible/unmanageable in the app's own UI —
  /// this is the one place [FilesystemType.ext] is intentionally stricter
  /// than the bare filesystem, and it is called out explicitly rather than
  /// silently folded into "illegal characters" so the distinction stays
  /// visible to anyone auditing the rule table.
  final bool disallowControlChars;

  /// Windows-family reserved device names (case-insensitive, matched
  /// against the name up to the first `.`): CON, PRN, AUX, NUL, COM0–COM9,
  /// LPT0–LPT9.
  final bool disallowReservedDeviceNames;

  /// A trailing space or `.` is silently stripped by the filesystem itself,
  /// so allowing it in would mean "the name you see is not the name that
  /// gets saved" — exactly what this change exists to prevent.
  final bool disallowTrailingSpaceOrDot;

  /// Maximum length of a single path component, measured the way the real
  /// filesystem measures it: UTF-16 code units for FAT32/exFAT/NTFS
  /// (matching FatFs's `FF_MAX_LFN` / NTFS's on-disk UTF-16 names), UTF-8
  /// bytes for ext2/3/4 (matching `EXT2_NAME_LEN`).
  final int maxComponentLength;

  /// Whether [maxComponentLength] counts UTF-8 bytes (true, for ext) rather
  /// than UTF-16 code units (false, for everything else this app mounts).
  final bool maxComponentLengthIsUtf8Bytes;

  /// Maximum total path length (all components, joined by `/`, from the
  /// container root). See ADR-005 for tightening these once the concrete
  /// on-disk kind is known at every call site instead of only where the
  /// creation-time choice happens to be threaded through.
  final int maxPathLength;

  /// Whether the filesystem treats "Notes" and "notes" as different names.
  /// FAT32/exFAT/NTFS are case-insensitive (but case-preserving); ext2/3/4
  /// is case-sensitive. Used by [checkEntryConflict] (entry_conflict.dart)
  /// so a same-name collision check matches what the real filesystem would
  /// actually consider a collision.
  final bool caseSensitive;

  const FilesystemRules({
    required this.illegalCharCodes,
    required this.disallowControlChars,
    required this.disallowReservedDeviceNames,
    required this.disallowTrailingSpaceOrDot,
    required this.maxComponentLength,
    required this.maxComponentLengthIsUtf8Bytes,
    required this.maxPathLength,
    required this.caseSensitive,
  });

  static const _windowsFamilyIllegal = <int>{
    0x22, // "
    0x2A, // *
    0x2F, // /
    0x3A, // :
    0x3C, // <
    0x3E, // >
    0x3F, // ?
    0x5C, // backslash
    0x7C, // |
  };

  /// FAT32 via FatFs. Component length matches `FF_MAX_LFN` (255) in
  /// `cpp/filesystems/ffconf.h`. Path length is a conservative,
  /// documented bound (FatFs's own long-path handling is generous, but
  /// 260 keeps every name interoperable with tooling that still assumes
  /// classic `MAX_PATH`); see ADR-005.
  static const fat32 = FilesystemRules(
    illegalCharCodes: _windowsFamilyIllegal,
    disallowControlChars: true,
    disallowReservedDeviceNames: true,
    disallowTrailingSpaceOrDot: true,
    maxComponentLength: 255,
    maxComponentLengthIsUtf8Bytes: false,
    maxPathLength: 260,
    caseSensitive: false,
  );

  /// exFAT, same FatFs backend. exFAT's on-disk name length limit is the
  /// same 255 UTF-16 units; its path-length ceiling is far larger than
  /// classic FAT, but this app keeps the same conservative bound as FAT32
  /// since both are mounted through the same FatFs volume type and the
  /// same practical interoperability argument applies.
  static const exfat = FilesystemRules(
    illegalCharCodes: _windowsFamilyIllegal,
    disallowControlChars: true,
    disallowReservedDeviceNames: true,
    disallowTrailingSpaceOrDot: true,
    maxComponentLength: 255,
    maxComponentLengthIsUtf8Bytes: false,
    maxPathLength: 260,
    caseSensitive: false,
  );

  /// NTFS via NTFS-3G. NTFS's own extended-length-path ceiling is far
  /// higher than Win32's classic `MAX_PATH`; NTFS-3G does not apply the
  /// legacy 260-character limit, so this uses NTFS's real on-disk path
  /// ceiling instead of the FAT/exFAT conservative bound above.
  static const ntfs = FilesystemRules(
    illegalCharCodes: _windowsFamilyIllegal,
    disallowControlChars: true,
    disallowReservedDeviceNames: true,
    disallowTrailingSpaceOrDot: true,
    maxComponentLength: 255,
    maxComponentLengthIsUtf8Bytes: false,
    maxPathLength: 32760,
    caseSensitive: false,
  );

  /// ext2/3/4 via libext2fs. Only NUL and `/` are illegal at the real
  /// filesystem level — `/` is covered by [illegalCharCodes] as a
  /// component separator; NUL is covered by [disallowControlChars].
  /// `EXT2_NAME_LEN` is 255 bytes; `PATH_MAX` on Linux is 4096 bytes.
  /// Trailing dots/spaces and reserved device names are real, legal ext
  /// filenames and are deliberately *not* rejected here — rejecting a
  /// name that is genuinely legal on the target filesystem would itself be
  /// a validation bug.
  static const ext = FilesystemRules(
    illegalCharCodes: {0x2F},
    disallowControlChars: true,
    disallowReservedDeviceNames: false,
    disallowTrailingSpaceOrDot: false,
    maxComponentLength: 255,
    maxComponentLengthIsUtf8Bytes: true,
    maxPathLength: 4096,
    caseSensitive: true,
  );

  /// CryFS / Cryptomator / gocryptfs. The plaintext name is encrypted
  /// before it becomes a host filename, so real filesystem character
  /// rules don't apply to it. `/` is still rejected — not because the
  /// vault format requires it, but because this app's own virtual-path
  /// model joins components with `/`, and a component containing `/`
  /// would be indistinguishable from two nested components in that model.
  /// The length bound is a generous, documented app-level choice (not a
  /// hard format limit) to keep the encrypted on-disk name reasonable.
  static const encryptedVault = FilesystemRules(
    illegalCharCodes: {0x2F},
    disallowControlChars: false,
    disallowReservedDeviceNames: false,
    disallowTrailingSpaceOrDot: false,
    maxComponentLength: 1024,
    maxComponentLengthIsUtf8Bytes: true,
    maxPathLength: 4096,
    caseSensitive: true,
  );

  /// The union (most restrictive choice per field) of fat32/exfat/ntfs/ext,
  /// used whenever the concrete on-disk type for a native disk-image
  /// container, or the real host filesystem behind a SAF folder vault,
  /// isn't known at the call site. See ADR-005.
  static const unknownConservative = FilesystemRules(
    illegalCharCodes: _windowsFamilyIllegal, // superset of ext's {'/'}
    disallowControlChars: true,
    disallowReservedDeviceNames: true,
    disallowTrailingSpaceOrDot: true,
    maxComponentLength: 255, // ext's 255 *bytes* is the tightest in practice
    maxComponentLengthIsUtf8Bytes: true,
    maxPathLength: 260, // fat32/exfat's bound is the tightest
    caseSensitive: false, // conservative: don't under-flag a real collision
  );

  static FilesystemRules of(FilesystemType type) => switch (type) {
        FilesystemType.fat32 => fat32,
        FilesystemType.exfat => exfat,
        FilesystemType.ntfs => ntfs,
        FilesystemType.ext => ext,
        FilesystemType.encryptedVault => encryptedVault,
        FilesystemType.unknownConservative => unknownConservative,
      };
}

const List<String> _reservedDeviceBaseNames = [
  'CON', 'PRN', 'AUX', 'NUL',
  'COM0', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT0', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
];

/// Whether [name]'s portion before the first `.` (or the whole name, if it
/// has no `.`) case-insensitively matches a Windows-family reserved device
/// name. Matches the real-world rule: "CON.txt" is just as reserved as
/// "CON".
bool isReservedDeviceName(String name) {
  final base = name.contains('.') ? name.substring(0, name.indexOf('.')) : name;
  final upper = base.toUpperCase();
  return _reservedDeviceBaseNames.contains(upper);
}
