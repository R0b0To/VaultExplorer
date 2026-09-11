import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

List<CipherAlgo> cipherChoicesForFormat(CreateFormat format) => switch (format) {
      CreateFormat.veracrypt => CipherAlgo.concrete,
      CreateFormat.luks1 => CipherAlgo.luks1Choices,
      CreateFormat.luks2 => CipherAlgo.luks2Choices,
    };

List<HashAlgo> hashChoicesForFormat(CreateFormat format) => switch (format) {
      CreateFormat.veracrypt => HashAlgo.concrete,
      CreateFormat.luks1 => HashAlgo.luks1Choices,
      CreateFormat.luks2 => HashAlgo.luks2Choices,
    };

/// Resolves the (cipherId, hashId) pair to use after switching to [format],
/// preserving the current selection if it's still a valid choice for the
/// new format, otherwise falling back to that format's first choice.
///
/// Identical logic previously hand-duplicated in both
/// CreateContainerController.setFormat and
/// UsbCreateContainerController.setFormat -- extracted here so a future
/// change to the fallback rule (or a new format's choice list) only needs
/// to happen once.
({int cipherId, int hashId}) resolveCipherHashForFormat(
  CreateFormat format, {
  required int currentCipherId,
  required int currentHashId,
}) {
  final cipherChoices = cipherChoicesForFormat(format);
  final hashChoices = hashChoicesForFormat(format);
  return (
    cipherId: cipherChoices.any((c) => c.id == currentCipherId)
        ? currentCipherId
        : cipherChoices.first.id,
    hashId: hashChoices.any((h) => h.id == currentHashId)
        ? currentHashId
        : hashChoices.first.id,
  );
}

/// Merges [picked] into [existing], skipping any entry whose [KeyfileRef.uri]
/// is already present. Used by every "pick keyfiles/carriers" flow across
/// the three container-creation controllers (outer keyfiles, hidden-volume
/// keyfiles, composite keyfiles, composite carriers) -- the merge-by-uri
/// semantics are identical regardless of what the picked files represent.
List<KeyfileRef> mergeKeyfilesByUri(
  List<KeyfileRef> existing,
  List<KeyfileRef> picked,
) {
  final seenUris = existing.map((k) => k.uri).toSet();
  final merged = List<KeyfileRef>.from(existing);
  for (final k in picked) {
    if (seenUris.add(k.uri)) merged.add(k);
  }
  return merged;
}

/// Removes a single entry by value equality. Used by every "remove
/// keyfile" action across the three controllers. (Composite's carrier
/// removal is index-based instead, since carrier order is meaningful, and
/// is intentionally left as its own implementation rather than forced
/// through this helper.)
List<KeyfileRef> removeKeyfileByValue(
  List<KeyfileRef> keyfiles,
  KeyfileRef toRemove,
) =>
    keyfiles.where((k) => k != toRemove).toList();

// Identical today, but kept as two separate lists (rather than one shared
// constant) since VeraCrypt and LUKS filesystem support already diverges
// at the native layer and may again -- see the two wizards' original
// _veraCryptFileSystems/_luksFileSystems fields this replaces.
const List<String> veraCryptContainerFileSystems = [
  'FAT',
  'exFAT',
  'NTFS',
  'ext2',
  'ext3',
  'ext4',
];
const List<String> luksContainerFileSystems = [
  'FAT',
  'exFAT',
  'NTFS',
  'ext2',
  'ext3',
  'ext4',
];

List<String> availableFileSystemsForFormat(CreateFormat format) =>
    format == CreateFormat.veracrypt ? veraCryptContainerFileSystems : luksContainerFileSystems;

/// Computes the outer-volume side of a hidden-volume request (parsed size,
/// clamped PIMs) from the wizard's raw text-field values, then delegates to
/// [validateHiddenVolume] for the actual size/credential checks. Both
/// wizards call this identically for a VeraCrypt outer volume -- only the
/// state object each reads its inputs from differs, so callers pass the
/// raw scalars rather than their (different) state types.
///
/// Returns null if [sizeText] isn't a valid positive number yet (nothing to
/// validate against until the outer size is known) -- callers should treat
/// that the same as "no hidden-volume problem to report yet", exactly as
/// the pre-extraction code on both wizards did.
HiddenVolumeValidation? computeHiddenVolumeValidation({
  required String sizeText,
  required String sizeUnit,
  required String pimText,
  required String hiddenPimText,
  required String hiddenSizeText,
  required String hiddenSizeUnit,
  required String outerPassword,
  required String hiddenPassword,
  required bool hasHiddenKeyfiles,
  required Set<String> outerKeyfileUris,
  required Set<String> hiddenKeyfileUris,
  required AppLocalizations l10n,
}) {
  final sizeVal = double.tryParse(sizeText);
  if (sizeVal == null || sizeVal <= 0) return null;
  final multiplier = sizeUnit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
  final outerSizeBytes = (sizeVal * multiplier).round();
  final outerPim = clampPim(pimText.isEmpty ? 0 : int.tryParse(pimText) ?? 0);
  final hiddenPim = clampPim(hiddenPimText.isEmpty ? 0 : int.tryParse(hiddenPimText) ?? 0);

  return validateHiddenVolume(
    hiddenSizeText: hiddenSizeText,
    hiddenSizeUnit: hiddenSizeUnit,
    outerSizeBytes: outerSizeBytes,
    outerPimClamped: outerPim,
    hiddenPimClamped: hiddenPim,
    outerPassword: outerPassword,
    hiddenPassword: hiddenPassword,
    hasHiddenKeyfiles: hasHiddenKeyfiles,
    outerKeyfileUris: outerKeyfileUris,
    hiddenKeyfileUris: hiddenKeyfileUris,
    l10n: l10n,
  );
}