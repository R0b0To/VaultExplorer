import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'logcat_service.g.dart';

@Riverpod(keepAlive: true)
LogcatService logcatService(Ref ref) => const LogcatService();

/// Wraps the Android `logcat` command for in-app log viewing and saving.
///
/// All methods are no-ops / return graceful failures on non-Android platforms
/// or when the process cannot be started (e.g. permission denied).
class LogcatService {
  const LogcatService();

  /// Instance-method forwarders so a migrated (Consumer) logcat_screen.dart
  /// can resolve this via [logcatServiceProvider] instead of the statics.
  DateTime? get lastClearedAtValue => lastClearedAt;
  Future<bool> clearLog() => clear();
  Stream<String> get logStream => stream;
  Future<String?> captureLogSnapshot() => captureSnapshot();
  Future<({bool success, String displayName})?> saveLogToFile(String content) =>
      saveToFile(content);

  // Same platform channel every VaultXxxApi class talks over (see
  // vault_engine_providers.dart) -- declared directly here rather than
  // injected through Riverpod so this stays a plain static-method wrapper
  // like the rest of the class. Mirrors ThumbnailCacheService/
  // AppSecureStorage, which do the same for the same reason.
  static const MethodChannel _channel = MethodChannel(
    'com.aeidolon.vaultexplorer/engine',
  );

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

  /// Builds a timestamped default filename offered as the suggested name in
  /// the system "Save As" picker (see [saveToFile]).
  static String buildExportFileName() {
    final now = DateTime.now();
    final stamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}'
        '_${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    return 'vaultexplorer_logcat_$stamp.txt';
  }

  /// Lets the user pick where to save [content] via the system document
  /// picker (`ACTION_CREATE_DOCUMENT`), rather than writing directly into
  /// this app's external-files directory (`Android/data/<package>/files/`)
  /// -- which many file managers can no longer browse on Android 11+ due to
  /// scoped storage.
  ///
  /// Returns `null` if the user cancelled the picker, or if the platform
  /// channel has no handler for it (non-Android platform, tests, ...) --
  /// neither is treated as an error. A genuine write failure surfaces as a
  /// [PlatformException] instead, for the caller to handle explicitly rather
  /// than have it look identical to a deliberate cancel.
  static Future<({bool success, String displayName})?> saveToFile(
    String content,
  ) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'exportLogFile',
        {'contents': content, 'fileName': buildExportFileName()},
      );
      if (raw == null) return null; // user cancelled the picker
      return (
        success: raw['success'] as bool? ?? false,
        displayName: (raw['displayName'] as String?) ?? 'log.txt',
      );
    } on MissingPluginException {
      return null; // no native handler -- non-Android platform, tests, ...
    }
  }
}