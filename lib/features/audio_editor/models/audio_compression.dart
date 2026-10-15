import 'package:vaultexplorer/core/api/vault_audio_edit_api.dart'
    show AudioProbe;

/// The "reduce file size" choice in the audio editor's export sheet: either
/// export as before (lossless copy where the format allows it), or decode and
/// re-encode to AAC at a lower bitrate for a much smaller file.
///
/// Bitrates are per channel, because the native encoder keeps the source's
/// channel layout (mono stays mono, anything wider becomes a stereo pair);
/// [totalBitrate] gives what the file will actually carry. The sample rate is
/// not changed, so the saving comes from the bitrate alone.
enum AudioCompression {
  /// No re-encode: the existing behavior.
  off(null),

  /// 64 kbps per channel -- clean for most audio.
  balanced(64000),

  /// 32 kbps per channel -- speech.
  small(32000);

  /// Bits per second per channel the AAC encoder is asked for; `null` means
  /// "don't re-encode".
  final int? bitratePerChannel;

  const AudioCompression(this.bitratePerChannel);

  bool get isOn => bitratePerChannel != null;

  /// A compressed export is always AAC in an `.m4a`.
  static const String outputExtension = 'm4a';

  /// Channels of the AAC output: mono stays mono, wider audio is cut down to
  /// the front pair (see `AudioEditMath.reencodeChannels` natively).
  static int outputChannels(int? sourceChannels) =>
      (sourceChannels ?? 2) <= 1 ? 1 : 2;

  /// The total bitrate the exported file will carry, or `null` for [off].
  int? totalBitrate(int? sourceChannels) {
    final perChannel = bitratePerChannel;
    if (perChannel == null) return null;
    return perChannel * outputChannels(sourceChannels);
  }

  /// Rough size in bytes of [durationUs] of audio at this setting, or `null`
  /// for [off] (the source's own size isn't known from here).
  int? estimatedBytes({required int durationUs, required int? sourceChannels}) {
    final bitrate = totalBitrate(sourceChannels);
    if (bitrate == null || durationUs <= 0) return null;
    return (bitrate * (durationUs / 1000000) / 8).round();
  }

  /// The choices worth offering for [probe]: always [off] first, then each
  /// compression that is meaningfully lower than the source's own bitrate (at
  /// most 80% of it -- re-encoding to roughly the same bitrate would only cost
  /// quality). Just `[off]` when the file can't be re-encoded on this device
  /// or is already that small, in which case the sheet hides the section.
  static List<AudioCompression> optionsFor(AudioProbe probe) {
    if (!probe.canCompress) return const [AudioCompression.off];
    final sourceBitrate = probe.bitrate;
    bool worthOffering(AudioCompression c) {
      if (sourceBitrate == null || sourceBitrate <= 0) return true;
      return c.totalBitrate(probe.channels)! * 5 <= sourceBitrate * 4;
    }

    return [
      AudioCompression.off,
      for (final c in const [AudioCompression.balanced, AudioCompression.small])
        if (worthOffering(c)) c,
    ];
  }
}
