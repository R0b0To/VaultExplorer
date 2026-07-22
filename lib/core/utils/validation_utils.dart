/// Clamps a user-supplied PIM value to a safe range.
///
/// The native PBKDF2 iteration formula is:
///   iter = (pim > 0) ? (15_000 + pim * 1_000) : 500_000
///
/// An unclamped pim of, say, 2_000_000 would produce ~2_000_015_000
/// iterations — effectively a denial-of-service against the user's own
/// device. Capping at 2_000 gives a generous maximum of ~2_015_000
/// iterations, which is still far above VeraCrypt's own recommended range.
int clampPim(int value) {
  if (value < 0) return 0;
  if (value > 2000) return 2000;
  return value;
}

/// VeraCrypt reserves this many bytes at the start of a volume for the
/// outer volume's header + data area before a hidden volume's data can
/// begin. Mirrors the native header layout; do not change without checking
/// the native side.
const int vcDataAreaOffset = 131072;

/// Outcome of [validateHiddenVolume]: either an accepted hidden-volume
/// size, or a user-facing error explaining why the configuration was
/// rejected.
class HiddenVolumeValidation {
  final int? hiddenSizeBytes;
  final String? error;

  const HiddenVolumeValidation.ok(int sizeBytes)
      : hiddenSizeBytes = sizeBytes,
        error = null;

  const HiddenVolumeValidation.error(String message)
      : hiddenSizeBytes = null,
        error = message;

  bool get isValid => error == null;
}

/// Validates a hidden-volume request against its outer volume: the size
/// relationship (including the on-disk header reservation via
/// [vcDataAreaOffset]), required credentials, and that the hidden
/// credentials aren't identical to the outer ones.
HiddenVolumeValidation validateHiddenVolume({
  required String hiddenSizeText,
  required String hiddenSizeUnit,
  required int outerSizeBytes,
  required int outerPimClamped,
  required int hiddenPimClamped,
  required String outerPassword,
  required String hiddenPassword,
  required bool hasHiddenKeyfiles,
  required Set<String> outerKeyfileUris,
  required Set<String> hiddenKeyfileUris,
}) {
  final hiddenSizeVal = double.tryParse(hiddenSizeText);
  if (hiddenSizeVal == null || hiddenSizeVal <= 0) {
    return const HiddenVolumeValidation.error(
      'Enter a valid hidden size greater than 0',
    );
  }
  final hiddenMultiplier =
      hiddenSizeUnit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
  final hiddenSizeBytes = (hiddenSizeVal * hiddenMultiplier).round();

  if (hiddenSizeBytes >= outerSizeBytes) {
    return const HiddenVolumeValidation.error(
      'Hidden volume size must be less than the outer volume size',
    );
  }
  if (outerSizeBytes <= vcDataAreaOffset + hiddenSizeBytes) {
    return const HiddenVolumeValidation.error(
      'Hidden volume size is too large for this container size',
    );
  }
  if (hiddenPassword.isEmpty && !hasHiddenKeyfiles) {
    return const HiddenVolumeValidation.error(
      'A hidden password or keyfile is required when creating a hidden volume',
    );
  }

  final samePassword = outerPassword == hiddenPassword;
  final samePim = outerPimClamped == hiddenPimClamped;
  final sameKeyfiles = outerKeyfileUris.length == hiddenKeyfileUris.length &&
      outerKeyfileUris.difference(hiddenKeyfileUris).isEmpty;

  if (samePassword && samePim && sameKeyfiles) {
    return const HiddenVolumeValidation.error(
      'Hidden volume credentials (password, PIM, and keyfiles) cannot be '
      'identical to the outer volume credentials.',
    );
  }

  return HiddenVolumeValidation.ok(hiddenSizeBytes);
}
