/// The concrete, wire-level container/vault format for an already-mounted
/// or saved container — the same strings carried by
/// [MountedContainer.containerFormat] / [ContainerRecord.containerFormat] /
/// `UnlockProgress.containerFormat` ('veracrypt', 'luks1', 'luks2',
/// 'bitlocker', 'cryptomator', 'gocryptfs', 'cryfs', 'directory_vault').
enum ContainerFormat {
  veracrypt('veracrypt', 'VeraCrypt'),
  luks1('luks1', 'LUKS1'),
  luks2('luks2', 'LUKS2'),
  bitlocker('bitlocker', 'BitLocker'),
  cryptomator('cryptomator', 'Cryptomator'),
  gocryptfs('gocryptfs', 'gocryptfs'),
  cryfs('cryfs', 'CryFS'),
  directoryVault('directory_vault', 'Folder Vault'),

  /// Not a real wire value — returned by [fromWire] for any unrecognized
  /// string, including transient UI sentinels like unlock_sheet.dart's
  /// `'container'` (used while a file has been picked but its concrete
  /// format hasn't come back from auto-detect yet). Deliberately does NOT
  /// fall back to [veracrypt]: guessing a specific format for an
  /// unresolved container would misrepresent it (e.g. showing "VC" before
  /// detection has actually confirmed VeraCrypt).
  other('', 'Unknown');

  /// The exact string sent/received over the platform channel and stored
  /// in [ContainerRecord] JSON. Do not change these values.
  final String wire;
  final String label;

  const ContainerFormat(this.wire, this.label);

  /// Parses a wire string into a [ContainerFormat], falling back to
  /// [other] for anything unrecognized.
  static ContainerFormat fromWire(String wire) => values.firstWhere(
        (f) => f.wire == wire,
        orElse: () => ContainerFormat.other,
      );

  bool get isLuks => this == luks1 || this == luks2;
  bool get isBitlocker => this == bitlocker;
  bool get isCryptomator => this == cryptomator;
  bool get isGocryptfs => this == gocryptfs;
  bool get isCryfs => this == cryfs;

  /// True for directory-based vaults (a mounted folder) rather than a
  /// single encrypted container file.
  bool get isFolderVault =>
      this == directoryVault || isCryptomator || isGocryptfs || isCryfs;

  // ── Wire-string convenience ──────────────────────────────────────────
  // For call sites holding only the raw wire string (e.g. a screen's
  // in-progress `String _containerFormat` selection state) rather than a
  // full model instance. Prefer the instance getters above when possible.
  static bool isLuksWire(String wire) => fromWire(wire).isLuks;
  static bool isBitlockerWire(String wire) => fromWire(wire).isBitlocker;
  static bool isCryptomatorWire(String wire) => fromWire(wire).isCryptomator;
  static bool isGocryptfsWire(String wire) => fromWire(wire).isGocryptfs;
  static bool isCryfsWire(String wire) => fromWire(wire).isCryfs;
  static bool isFolderVaultWire(String wire) => fromWire(wire).isFolderVault;
}
