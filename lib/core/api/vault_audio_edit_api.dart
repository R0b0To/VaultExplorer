import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

/// What the native side learned about an audio file: its length, codec and
/// whether it can be cut without re-encoding. See `LosslessAudioCutter.probe`
/// in Kotlin.
class AudioProbe {
  final int durationUs;
  final String? mime;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;

  /// Extension (no dot) the lossless cut will be written with.
  final String outputExtension;

  /// False when the file can't be edited at all on this device (no decoder for
  /// it, or a sample rate the AAC fallback can't take). It can still be played
  /// in the editor, but not exported.
  final bool cutSupported;

  /// True when the cut can't be a plain copy (FLAC, WMA, AMR, ...) and is
  /// decoded and re-encoded to AAC instead, so the output is not bit-identical
  /// to the source. Audio is cheap to re-encode, so this is allowed; the editor
  /// says so before exporting.
  final bool reencode;

  /// Native, English explanation for [cutSupported] being false. For logs and
  /// diagnostics; the UI shows its own localized message.
  final String? unsupportedReason;

  /// True when this device can decode the file and encode AAC, so the export
  /// sheet can offer a lower-bitrate ("reduce file size") export even for a
  /// format that would otherwise be copied losslessly.
  final bool canCompress;

  const AudioProbe({
    required this.durationUs,
    required this.mime,
    required this.outputExtension,
    required this.cutSupported,
    this.reencode = false,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.unsupportedReason,
    this.canCompress = false,
  });

  factory AudioProbe.fromMap(Map<Object?, Object?> m) => AudioProbe(
    durationUs: (m['durationUs'] as num?)?.toInt() ?? 0,
    mime: m['mime'] as String?,
    bitrate: (m['bitrate'] as num?)?.toInt(),
    sampleRate: (m['sampleRate'] as num?)?.toInt(),
    channels: (m['channels'] as num?)?.toInt(),
    outputExtension: m['outputExtension'] as String? ?? 'm4a',
    cutSupported: m['cutSupported'] as bool? ?? false,
    reencode: m['reencode'] as bool? ?? false,
    unsupportedReason: m['unsupportedReason'] as String?,
    canCompress: m['canCompress'] as bool? ?? false,
  );
}

/// The loudness envelope of an audio file, as the native side computed it:
/// one 0..255 level per slice of time. See `AudioWaveformExtractor`.
class AudioWaveformResult {
  final Uint8List peaks;
  final double peaksPerSecond;

  /// False when the decoder stalled before the end of the file; the rest of
  /// the timeline is then drawn flat. (There is no time limit any more: a long
  /// file is decoded to the end, however many minutes that takes.)
  final bool complete;

  const AudioWaveformResult({
    required this.peaks,
    required this.peaksPerSecond,
    required this.complete,
  });
}

class AudioExportResult {
  final List<String> outputPaths;
  const AudioExportResult({required this.outputPaths});
}

/// A failed audio probe/waveform/export. [cancelled] is true when the work
/// was cancelled.
class AudioEditException implements Exception {
  final String code;
  final String message;
  const AudioEditException(this.code, this.message);

  bool get cancelled => code == 'CANCELLED';

  @override
  String toString() => 'AudioEditException($code): $message';
}

/// Lossless audio trimming/cutting on the native side (stream copy -- no
/// re-encode) plus the waveform the editor draws. Paths follow the player's
/// rule: container-relative for a vault, absolute for local storage.
class VaultAudioEditApi {
  final MethodChannel _channel;
  const VaultAudioEditApi(this._channel);

  Future<AudioProbe> probe({
    required int volId,
    required String filePath,
    required bool isLocalStorage,
  }) async {
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>(ChannelMethods.audioEditProbe, {
            'volId': volId,
            'filePath': filePath,
            'isLocalStorage': isLocalStorage,
          });
      if (raw == null) {
        throw const AudioEditException('PROBE_FAILED', 'No response');
      }
      return AudioProbe.fromMap(raw);
    } on PlatformException catch (e) {
      throw AudioEditException(
        e.code,
        e.message ?? 'Could not read this audio file',
      );
    }
  }

  /// Decodes the file to a peak envelope. Progress arrives as
  /// `AudioEditProgress` events (phase `waveform`) tagged with [opId], and
  /// [cancel] with the same id stops the decode early.
  Future<AudioWaveformResult> waveform({
    required int volId,
    required String filePath,
    required bool isLocalStorage,
    required int opId,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        ChannelMethods.audioEditWaveform,
        {
          'volId': volId,
          'filePath': filePath,
          'isLocalStorage': isLocalStorage,
          'opId': opId,
        },
      );
      final peaks = raw?['peaks'];
      if (raw == null || peaks is! Uint8List) {
        throw const AudioEditException('WAVEFORM_FAILED', 'No response');
      }
      return AudioWaveformResult(
        peaks: peaks,
        peaksPerSecond: (raw['peaksPerSecond'] as num?)?.toDouble() ?? 100.0,
        complete: raw['complete'] as bool? ?? false,
      );
    } on PlatformException catch (e) {
      throw AudioEditException(
        e.code,
        e.message ?? 'Could not read the waveform',
      );
    }
  }

  /// Cuts [segmentsUs] (`[startUs, endUs]` pairs) out of the source. With
  /// [merge] they are joined into the single file [outputPaths] names;
  /// otherwise each becomes its own file, in order.
  ///
  /// With [compressBitratePerChannel] set, the audio is decoded and re-encoded
  /// to AAC at that bitrate per channel instead of being copied, so the
  /// outputs are much smaller (and always `.m4a`).
  Future<AudioExportResult> export({
    required int volId,
    required String filePath,
    required bool isLocalStorage,
    required List<({int startUs, int endUs})> segmentsUs,
    required bool merge,
    required List<String> outputPaths,
    required int opId,
    int? compressBitratePerChannel,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        ChannelMethods.audioEditExport,
        {
          'volId': volId,
          'filePath': filePath,
          'isLocalStorage': isLocalStorage,
          'segments': [
            for (final s in segmentsUs) [s.startUs, s.endUs],
          ],
          'merge': merge,
          'outputPaths': outputPaths,
          'opId': opId,
          if (compressBitratePerChannel != null)
            'compressBitratePerChannel': compressBitratePerChannel,
        },
      );
      return AudioExportResult(
        outputPaths: [
          for (final p
              in (raw?['outputPaths'] as List<Object?>? ?? outputPaths))
            p as String,
        ],
      );
    } on PlatformException catch (e) {
      throw AudioEditException(e.code, e.message ?? 'Export failed');
    }
  }

  Future<void> cancel(int opId) async {
    try {
      await _channel.invokeMethod<void>(ChannelMethods.cancelAudioEdit, {
        'opId': opId,
      });
    } on PlatformException {
      // Best effort: if the call fails the work simply runs to completion.
    }
  }
}
