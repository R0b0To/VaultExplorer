import 'package:intl/intl.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// How audio recordings made inside a vault are encoded (mono AAC in an
/// `.m4a`). Lower presets trade fidelity for much smaller files, which
/// matters for recordings that run for hours.
///
/// The numbers here are the single source of truth: they are sent to the
/// native recorder with every `start` (see `VaultAudioRecorderController`),
/// which clamps anything out of range, and the technical description shown in
/// the pickers is built from the same values rather than typed in separately.
enum AudioRecordingQuality {
  /// Smallest files; fine for speech (meetings, lectures, interviews).
  voice(bitrate: 32000, sampleRate: 22050),

  /// Clear sound for most recordings at half the old size.
  standard(bitrate: 64000, sampleRate: 44100),

  /// The previous fixed setting; best for music and ambient sound.
  high(bitrate: 128000, sampleRate: 44100);

  final int bitrate;
  final int sampleRate;

  const AudioRecordingQuality({required this.bitrate, required this.sampleRate});

  static const AudioRecordingQuality defaultQuality = standard;

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
    AudioRecordingQuality.voice => l10n.audioRecordingQualityVoice,
    AudioRecordingQuality.standard => l10n.audioRecordingQualityStandard,
    AudioRecordingQuality.high => l10n.audioRecordingQualityHigh,
  };

  /// What the preset actually records with, e.g. "AAC · 32 kbps · 22.05 kHz ·
  /// mono": the real encoder values, not a description of them. The sample
  /// rate follows the locale's decimal separator.
  String getLocalizedSubtitle(AppLocalizations l10n) {
    final kilohertz = NumberFormat('0.##', l10n.localeName).format(
      sampleRate / 1000,
    );
    return l10n.audioRecordingQualityDetails(
      (bitrate / 1000).round().toString(),
      kilohertz,
    );
  }

  String toJson() => name;

  /// Unknown or missing values (older settings files) read as the default.
  static AudioRecordingQuality fromJson(String? value) => switch (value) {
    'voice' => AudioRecordingQuality.voice,
    'standard' => AudioRecordingQuality.standard,
    'high' => AudioRecordingQuality.high,
    _ => AudioRecordingQuality.defaultQuality,
  };
}
