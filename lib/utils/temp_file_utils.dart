import 'dart:io';
import 'dart:math';

/// Generates collision-safe temporary file paths.
///
/// Uses microsecond timestamp + 6-char random suffix to handle concurrent
/// operations on files with identical names (e.g. clipboard copy + import).
abstract class TempFileUtils {
  static final _rng = Random.secure();

  static String _randomSuffix() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(6, (_) => chars[_rng.nextInt(chars.length)]).join();
  }

  /// Returns a path inside [dir] that is guaranteed not to exist.
  /// [prefix] is optional; defaults to `'tmp'`.
  static String uniquePath(Directory dir, {String prefix = 'tmp'}) {
    while (true) {
      final name =
          '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_randomSuffix()}';
      final candidate = '${dir.path}/$name';
      if (!File(candidate).existsSync()) return candidate;
      // Collision (extraordinarily unlikely) — retry.
    }
  }
}