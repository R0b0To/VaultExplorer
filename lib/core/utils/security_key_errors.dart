import 'package:flutter/services.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// User-facing message for a failed FIDO2 security key operation, or null if
/// [e] isn't one (callers fall back to their normal error handling).
///
/// The `SECURITY_KEY_*` codes come from the native layer
/// (SecurityKeyError.wire). SECURITY_KEY_CANCELLED returns null on purpose:
/// the user backed out, so there is nothing to report.
String? localizedSecurityKeyError(PlatformException e, AppLocalizations l10n) {
  switch (e.code) {
    case 'SECURITY_KEY_TIMEOUT':
      return l10n.securityKeyErrorTimeout;
    case 'SECURITY_KEY_PIN_REQUIRED':
      return l10n.securityKeyErrorPinRequired;
    case 'SECURITY_KEY_PIN_INVALID':
      return l10n.securityKeyErrorPinInvalid;
    case 'SECURITY_KEY_PIN_BLOCKED':
      return l10n.securityKeyErrorPinBlocked;
    case 'SECURITY_KEY_PIN_NOT_SET':
      return l10n.securityKeyErrorPinNotSet;
    case 'SECURITY_KEY_NO_CREDENTIAL':
      return l10n.securityKeyErrorNoCredential;
    case 'SECURITY_KEY_UNSUPPORTED':
      return l10n.securityKeyErrorUnsupported;
    case 'SECURITY_KEY_USER_ACTION':
      return l10n.securityKeyErrorTouch;
    case 'SECURITY_KEY_FAILED':
      return e.message ?? l10n.securityKeyErrorGeneric;
    default:
      return null;
  }
}
