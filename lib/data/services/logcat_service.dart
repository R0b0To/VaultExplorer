import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Wraps the Android `logcat` command for in-app log viewing and saving.
///
/// All methods are no-ops / return graceful failures on non-Android platforms
/// or when the process cannot be started (e.g. permission denied).
class LogcatService {
  const LogcatService();

  static DateTime? _lastClearedAt;

  /// Returns when the log buffer was last cleared.
  static DateTime? get lastClearedAt => _lastClearedAt;

  /// Parses a logcat timestamp formatted with `-v time` (e.g. `08-19 21:15:30.123`).
  static DateTime? parseLogcatTimestamp(String line) {
    if (line.length < 18) return null;
    try {
      final match = RegExp(r'^(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\.(\d{3})').firstMatch(line);
      if (match == null) return null;
      final now = DateTime.now();
      final month = int.parse(match.group(1)!);
      final day = int.parse(match.group(2)!);
      final hour = int.parse(match.group(3)!);
      final minute = int.parse(match.group(4)!);
      final second = int.parse(match.group(5)!);
      final millisecond = int.parse(match.group(6)!);
      return DateTime(now.year, month, day, hour, minute, second, millisecond);
    } catch (_) {
      return null;
    }
  }

  /// Clears the OS logcat buffer using `logcat -c` and records the timestamp so
  /// previous lines are discarded even if the process restarts.
  static Future<bool> clear() async {
    _lastClearedAt = DateTime.now();
    try {
      final result = await Process.run('logcat', ['-c']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ── Stream ──────────────────────────────────────────────────────────────────

  /// Opens a `logcat -v time` process filtered to the current PID and returns
  /// its stdout as a broadcast [Stream] of individual log lines.
  static Stream<String> get stream {
    return _buildStream();
  }

  static Stream<String> _buildStream() {
    final controller = StreamController<String>();
    Process? proc;

    controller.onListen = () async {
      try {
        proc = await Process.start('logcat', [
          '-v', 'time',
          '--pid=$pid',
        ]);
        proc!.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .listen(
              (String line) {
                if (_lastClearedAt != null) {
                  final t = parseLogcatTimestamp(line);
                  if (t != null && t.isBefore(_lastClearedAt!)) {
                    return;
                  }
                }
                controller.add(line);
              },
              onError: (Object e) => controller.addError(e),
              onDone: controller.close,
            );
        unawaited(proc!.stderr.drain<void>());
      } catch (e) {
        controller.addError(e);
        await controller.close();
      }
    };

    controller.onCancel = () {
      proc?.kill();
      proc = null;
    };

    return controller.stream;
  }

  // ── Snapshot ────────────────────────────────────────────────────────────────

  /// Runs `logcat -d -v time` once (dump mode) filtered to the current PID
  /// and returns the full output as a [String].
  ///
  /// Returns `null` on any error (process not available, permission denied, …).
  static Future<String?> captureSnapshot() async {
    try {
      final result = await Process.run('logcat', [
        '-d', '-v', 'time',
        '--pid=$pid',
      ]);
      if (result.exitCode != 0) return null;
      final raw = result.stdout as String;
      if (_lastClearedAt == null) return raw;

      final lines = raw.split('\n');
      final filtered = lines.where((line) {
        final t = parseLogcatTimestamp(line);
        if (t != null && t.isBefore(_lastClearedAt!)) return false;
        return true;
      });
      return filtered.join('\n');
    } catch (_) {
      return null;
    }
  }

  // ── Save ────────────────────────────────────────────────────────────────────

  /// Writes [content] to a timestamped `.txt` file in the app's external
  /// storage directory (`Android/data/<package>/files/`) and returns the path
  /// on success, or `null` on failure.
  static Future<String?> saveToFile(String content) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return null;

      final now = DateTime.now();
      final stamp =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}';

      final file = File('${dir.path}/vaultexplorer_logcat_$stamp.txt');
      await file.writeAsString(content, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }
}
