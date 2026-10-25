import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart'
    show logSwallowed;
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/audio_recording_quality.dart';

const String _tag = 'VaultAudioRecorder';

/// One finished part of a segmented recording: a complete, playable
/// plaintext temp file that the caller must save into the vault and wipe (or
/// [VaultAudioRecorderController.discard]).
class AudioSegment {
  final String path;
  final int durationMs;

  const AudioSegment({required this.path, required this.durationMs});
}

/// Outcome of [VaultAudioRecorderController.stop].
class AudioRecordingResult {
  final bool success;

  /// Plaintext temp file holding the finished take -- the last part, for a
  /// segmented recording. Only set on success, and `null` on success when a
  /// segmented recording ended without a usable last part (the earlier parts
  /// are in [segments]). It lives until it is saved into a vault or discarded
  /// -- both of which wipe it natively.
  final String? path;
  final int durationMs;
  final String? error;

  /// Parts of a segmented recording that closed since the last
  /// [VaultAudioRecorderController.takeSegments], oldest first. They come
  /// before [path]. Empty for an ordinary recording.
  final List<AudioSegment> segments;

  const AudioRecordingResult({
    required this.success,
    this.path,
    this.durationMs = 0,
    this.error,
    this.segments = const [],
  });
}

/// Maps the recorder's raw peak amplitude (0..32767) to a 0..1 meter level.
///
/// Amplitude is perceived roughly logarithmically, so a linear mapping
/// leaves normal speech looking like a flat line. This uses a dB scale with
/// a -50 dB floor: silence reads 0, full scale reads 1.
double normalizeAudioAmplitude(int raw) {
  if (raw <= 0) return 0.0;
  final clamped = raw > 32767 ? 32767 : raw;
  final db = 20 * math.log(clamped / 32767) / math.ln10;
  const floorDb = -50.0;
  final level = (db - floorDb) / -floorDb;
  if (level < 0.0) return 0.0;
  if (level > 1.0) return 1.0;
  return level;
}

/// `m:ss`, or `h:mm:ss` once a recording passes an hour.
String formatAudioDuration(int ms) {
  final totalSeconds = (ms < 0 ? 0 : ms) ~/ 1000;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$ss';
  }
  return '$minutes:$ss';
}

/// Dart side of the audio-only capture flow -- the counterpart of
/// [VaultCameraController] for the video path, minus any camera session.
///
/// A thin, stateless wrapper over the `audio_capture` method channel; the
/// recording state itself lives natively (see `VaultAudioRecorder`). Only
/// one recording can exist at a time.
class VaultAudioRecorderController {
  final MethodChannel _channel;

  VaultAudioRecorderController({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('com.aeidolon.vaultexplorer/audio_capture');

  Future<bool> hasPermission() async {
    final res = await _channel.invokeMethod<bool>('hasPermission');
    return res ?? false;
  }

  /// Shows the system microphone prompt if needed and completes with the
  /// outcome. Completes immediately with `true` if already granted.
  Future<bool> requestPermission() async {
    final res = await _channel.invokeMethod<bool>('requestPermission');
    return res ?? false;
  }

  /// Starts a recording at [quality] (bitrate + sample rate, mono AAC). The
  /// native side clamps anything it can't use, so a bad value degrades to
  /// its default rather than failing the start.
  ///
  /// With [segmentSeconds] above zero the recording is cut into parts of about
  /// that length. Each part is closed as a complete file while recording
  /// continues; collect them with [takeSegments].
  Future<({bool success, String? error})> start({
    AudioRecordingQuality quality = AudioRecordingQuality.defaultQuality,
    int segmentSeconds = 0,
  }) async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('start', {
      'bitrate': quality.bitrate,
      'sampleRate': quality.sampleRate,
      'segmentSeconds': segmentSeconds,
    });
    return (success: res?['success'] == true, error: res?['error'] as String?);
  }

  Future<bool> pause() async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('pause');
    return res?['success'] == true;
  }

  Future<bool> resume() async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('resume');
    return res?['success'] == true;
  }

  /// Current input level, 0..1 (see [normalizeAudioAmplitude]). Never
  /// throws: a failed poll just reads as silence.
  Future<double> level() async {
    try {
      final raw = await _channel.invokeMethod<int>('amplitude');
      return normalizeAudioAmplitude(raw ?? 0);
    } catch (e) {
      logSwallowed('audioAmplitude', e, expected: true);
      return 0.0;
    }
  }

  Future<AudioRecordingResult> stop() async {
    final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('stop');
    final success = res?['success'] == true;
    final rawPath = res?['path'];
    return AudioRecordingResult(
      success: success,
      path: (success && rawPath is String) ? rawPath : null,
      durationMs: (res?['durationMs'] as num?)?.toInt() ?? 0,
      error: res?['error'] as String?,
      segments: success ? _parseSegments(res?['segments']) : const [],
    );
  }

  /// Parts of a segmented recording that are complete and have not been
  /// collected yet, oldest first. Never throws: a failed call reads as "none
  /// yet" and the parts stay queued natively for the next call.
  Future<List<AudioSegment>> takeSegments() async {
    try {
      final res = await _channel.invokeMethod<List<dynamic>>('takeSegments');
      return _parseSegments(res);
    } catch (e) {
      logSwallowed('audioTakeSegments', e, expected: true);
      return const [];
    }
  }

  static List<AudioSegment> _parseSegments(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map && item['path'] is String)
          AudioSegment(
            path: item['path'] as String,
            durationMs: (item['durationMs'] as num?)?.toInt() ?? 0,
          ),
    ];
  }

  /// Cuts [path] down to [startMs]..[endMs] without re-encoding. Returns the
  /// path of the trimmed file (the original is wiped), or `null` if the
  /// trim failed -- in which case the original is untouched.
  Future<String?> trim({
    required String path,
    required int startMs,
    required int endMs,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('trim', {
        'path': path,
        'startMs': startMs,
        'endMs': endMs,
      });
      final trimmed = res?['path'] as String?;
      // The native trim hands back the source path on failure.
      if (trimmed == null || trimmed == path) return null;
      return trimmed;
    } catch (e) {
      VeLog.w(_tag, 'trim failed', e);
      return null;
    }
  }

  /// Streams the temp file at [path] into the vault. The caller must wipe it
  /// only after the vault write has been finalized successfully. On failure
  /// the temp file remains available for retry.
  Future<bool> saveToVault({
    required String path,
    required int volId,
    required String virtualPath,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('save', {
        'path': path,
        'volId': volId,
        'virtualPath': virtualPath,
      });
      return res?['success'] == true;
    } catch (e) {
      VeLog.w(_tag, 'saveToVault failed', e);
      return false;
    }
  }

  /// Securely wipes a finished take that will not be saved.
  Future<void> discard(String path) async {
    try {
      await _channel.invokeMethod<void>('discard', {'path': path});
    } catch (e) {
      logSwallowed('audioDiscard', e, expected: true);
    }
  }

  /// Aborts any in-progress recording and wipes its temp file. Safe to call
  /// when nothing is recording.
  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } catch (e) {
      logSwallowed('audioCancel', e, expected: true);
    }
  }
}
