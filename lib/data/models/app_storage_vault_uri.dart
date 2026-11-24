/// Tells whether a vault's URI points into *app storage*: the app's private
/// `<filesDir>/vaults` folder on Android, where a vault lives inside the app's
/// own sandbox instead of at a location the user picked.
///
/// This only drives the UI (a badge, which actions to offer). Every
/// destructive operation is re-checked natively against the real directory, so a
/// URI that merely looks like this can never get something deleted.
abstract final class AppStorageVaultUri {
  /// `file:///data/user/<n>/<package>/files/vaults/<name>` (or the legacy
  /// `/data/data/<package>/...`), with at least one name segment after `vaults/`.
  static final RegExp _path = RegExp(r'^/data/(?:user/\d+|data)/[^/]+/files/vaults/[^/]+');

  static bool isAppStorage(String uri) {
    if (!uri.startsWith('file:///')) return false;
    final path = _decodedPath(uri);
    if (path == null) return false;
    if (path.split('/').any((s) => s == '..' || s == '.')) return false;
    return _path.hasMatch(path);
  }

  /// The vault's file or folder name, e.g. `My vault.hc` -- what the user gave
  /// it when it was created or moved in. Null if [uri] is not a local file URI.
  static String? fileName(String uri) {
    final path = _decodedPath(uri);
    if (path == null) return null;
    final trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final name = trimmed.substring(trimmed.lastIndexOf('/') + 1);
    return name.isEmpty ? null : name;
  }

  static String? _decodedPath(String uri) {
    if (!uri.startsWith('file://')) return null;
    var rest = uri.substring('file://'.length);
    final cut = rest.indexOf(RegExp('[?#]'));
    if (cut >= 0) rest = rest.substring(0, cut);
    if (!rest.startsWith('/')) return null;
    try {
      return Uri.decodeFull(rest);
    } on FormatException {
      return null; // invalid UTF-8 in a percent-encoded sequence
    } on ArgumentError {
      return null; // truncated sequence such as a trailing "%E0%A4"
    }
  }
}
