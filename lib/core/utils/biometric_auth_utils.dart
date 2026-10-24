/// Whether a local-auth exception represents a dismissal rather than a failed
/// authentication attempt.
bool isBiometricCancellation(String code, [String? details]) {
  final normalized = '$code ${details ?? ''}'
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z]'), '');
  return normalized.contains('usercanceled') ||
      normalized.contains('usercancelled') ||
      normalized.contains('systemcanceled') ||
      normalized.contains('systemcancelled');
}
