import 'package:vaultexplorer/data/services/container_repository.dart';

/// Captures every point where the local-file and USB-device unlock flows'
/// shared biometric/pattern logic actually diverge -- derived directly from
/// a field-by-field comparison of `unlock_sheet.dart`'s and
/// `usb_unlock_sheet.dart`'s pre-extraction `_tryBiometric`/
/// `_onPatternComplete` methods (see docs/td7-unlock-flow-design.md).
///
/// Deliberately does *not* cover `_unlock()` itself or `_initUnlockMethod()`
/// -- both turned out, on closer reading, to have too much non-shared logic
/// (format branching for `_unlock()`; document-existence/relocation vs.
/// device-load/reconnect-gating for `_initUnlockMethod()`) to unify safely
/// in the same pass as this interface. See the design doc for why.
abstract class UnlockBiometricSource {
  /// Governs [UnlockBiometricMixin.tryBiometric]'s pre-authentication guard.
  /// Local always returns `(ready: true, blockMessage: null)` -- the
  /// original local `_tryBiometric` has *no* pre-authentication guard at
  /// all beyond the in-progress check, and goes straight to calling the
  /// platform biometric API every time. USB has two genuinely different
  /// original behaviors that must not be collapsed into one boolean:
  /// `widget.existingRecord == null` bails *silently* (`blockMessage:
  /// null`), while `_selected == null` (a record exists but no device is
  /// chosen yet) bails *and shows* `'Select a USB drive first'`
  /// (`blockMessage: 'Select a USB drive first'`).
  ({bool ready, String? blockMessage}) get preAuthReadiness;

  /// Governs [UnlockBiometricMixin.onPatternComplete]'s pre-check --
  /// simpler than [preAuthReadiness] because the original pattern-complete
  /// handlers only ever have zero or one guard, never the two-state
  /// silent-vs-message split above. Local: always true (no guard in the
  /// original). USB: `widget.existingRecord != null` (matches the
  /// original's `if (record == null) return;` -- note this does *not*
  /// additionally check device selection the way biometric does; the
  /// original pattern handler never checked `_selected`).
  bool get isReadyForPattern;

  /// Resolves the saved record for the current target. Local re-fetches via
  /// `ContainerRepository.instance.loadAll()` on every call, matching the
  /// original code's behavior exactly -- not "optimized" here, since a pure
  /// decomposition shouldn't also silently change this. USB returns
  /// `widget.existingRecord` synchronously, wrapped in a completed Future
  /// for a uniform signature.
  Future<ContainerRecord?> resolveRecord();

  /// Key for `loadDerivedKey`/`storeDerivedKey`/`clearDerivedKey`. Local:
  /// the container's URI. USB: a device-name-derived identifier that is
  /// genuinely different from [containerUri] on this side -- do not
  /// collapse these into one getter.
  String? get derivedKeyIdentifier;

  /// Key for `ContainerRepository.instance.getPassword(...)`. Local: the
  /// container's URI. USB: the resolved record's own `.uri`.
  String get containerUri;

  /// The one line of the biometric prompt that differs by source --
  /// "Authenticate to unlock $biometricPromptSubject".
  String get biometricPromptSubject;

  /// Shown when neither a cached derived key nor a saved password/keyfile
  /// exists, for the biometric path specifically. Local:
  /// "...authorize biometric access." USB: a source-agnostic message (USB
  /// doesn't distinguish by trigger the way local does -- this is a real
  /// asymmetry in the original code, not one introduced by extracting it).
  String get noSavedCredentialsForBiometricMessage;

  /// Same as above, for the pattern-unlock path. Local has a *different*
  /// string here than [noSavedCredentialsForBiometricMessage] ("...
  /// authorize pattern access."); USB returns the same string for both --
  /// preserve that asymmetry rather than collapsing it into one getter.
  String get noSavedCredentialsForPatternMessage;

  /// A short tag for the diagnostic debugPrint lines only (e.g. "unlock" vs
  /// "usb unlock") -- no functional effect, kept purely so the log output
  /// stays as identifiable as it was before this extraction.
  String get debugLogTag;
}
