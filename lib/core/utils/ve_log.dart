import 'dart:developer' as developer;

/// Lightweight debug logger for VaultExplorer.
///
/// All methods are zero-cost no-ops when [enabled] is `false` — no string
/// interpolation, no allocation, no I/O.  Flip [enabled] from the Debug
/// settings toggle and it immediately starts routing through
/// `dart:developer`'s `log()`, which feeds into the Android logcat stream
/// under the tag `VaultExplorer`.
///
/// Usage:
/// ```dart
/// VeLog.d('UnlockSheet', 'Container selected: uri=$uri');
/// VeLog.e('UnlockSheet', 'PlatformException', e);
/// ```
abstract final class VeLog {
  /// Master switch — set this from the "Debug logging" settings toggle.
  static bool enabled = false;

  /// Sanitizes a URI (SAF content URI, tree URI, or file path) by stripping sensitive path
  /// segments, emails, usernames, and document tokens, while retaining authority,
  /// structure type, and file extension for diagnostic purposes.
  static String censorUri(String? rawUri) {
    if (rawUri == null || rawUri.isEmpty) return '<null>';

    if (rawUri.startsWith('content://')) {
      try {
        final uri = Uri.parse(rawUri);
        final authority = uri.authority;
        final segments = uri.pathSegments;
        final isTree = segments.contains('tree') || rawUri.contains('/tree/');
        final isDocument = segments.contains('document') || rawUri.contains('/document/');

        final lastSeg = Uri.decodeComponent(segments.isNotEmpty ? segments.last : '');
        final extMatch = RegExp(r'(\.[a-zA-Z0-9_-]{1,10})$').firstMatch(lastSeg);
        final ext = extMatch?.group(1) ?? '';

        final kind = isTree && isDocument
            ? 'tree+doc'
            : isTree
                ? 'tree'
                : 'doc';

        return 'content://$authority/[$kind${ext.isNotEmpty ? "*$ext" : ""}]';
      } catch (_) {
        return 'content://[REDACTED_URI]';
      }
    }

    final decoded = Uri.decodeComponent(rawUri);
    final extMatch = RegExp(r'(\.[a-zA-Z0-9_-]{1,10})$').firstMatch(decoded);
    final ext = extMatch?.group(1) ?? '';
    return 'file://[path]/***$ext';
  }

  /// Sanitizes display names by masking the stem and preserving the file extension.
  static String censorName(String? name) {
    if (name == null || name.isEmpty) return '<null>';
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex > 0 && dotIndex < name.length - 1) {
      final ext = name.substring(dotIndex);
      return '***$ext';
    }
    return '***';
  }

  // ── Levels (mirrors android.util.Log constants) ──────────────────────────

  /// Verbose (level 2).
  static void v(String tag, String msg) {
    if (!enabled) return;
    developer.log(msg, name: tag, level: 200);
  }

  /// Debug (level 3).
  static void d(String tag, String msg) {
    if (!enabled) return;
    developer.log(msg, name: tag, level: 500);
  }

  /// Info (level 4).
  static void i(String tag, String msg) {
    if (!enabled) return;
    developer.log(msg, name: tag, level: 800);
  }

  /// Warning (level 5).
  static void w(String tag, String msg) {
    if (!enabled) return;
    developer.log(msg, name: tag, level: 900);
  }

  /// Error (level 6).  Attach the caught [error] object for extra context.
  static void e(String tag, String msg, [Object? error]) {
    if (!enabled) return;
    developer.log(
      error != null ? '$msg — $error' : msg,
      name: tag,
      level: 1000,
      error: error,
    );
  }
}
