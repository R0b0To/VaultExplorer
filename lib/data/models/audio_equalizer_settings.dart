import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Number of bands in the media player's equalizer.
const int kEqualizerBandCount = 10;

/// Largest boost/cut, in dB, of a band or of the preamp.
const double kEqualizerMaxGainDb = 12;

/// Centre frequency (Hz) of each band, lowest first: one octave apart.
///
/// Mirrors `EqualizerDsp.BAND_FREQUENCIES_HZ` in the native player
/// (EqualizerDsp.kt) -- the two must stay in step.
const List<double> kEqualizerBandFrequenciesHz = [
  31.25,
  62.5,
  125,
  250,
  500,
  1000,
  2000,
  4000,
  8000,
  16000,
];

/// Built-in starting points. A preset only sets the band gains; the preamp and
/// the other options are left as they are.
enum EqualizerPreset {
  flat([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
  bassBoost([6, 5, 4, 2, 0, 0, 0, 0, 0, 0]),
  trebleBoost([0, 0, 0, 0, 0, 1, 2, 4, 5, 6]),
  voice([-3, -2, -1, 0, 2, 4, 4, 3, 1, 0]),
  rock([5, 4, 3, 1, -1, -1, 1, 3, 4, 5]),
  pop([-1, 1, 3, 4, 3, 0, -1, -1, 1, 2]),
  jazz([3, 2, 1, 2, -2, -2, 0, 1, 2, 3]),
  classical([4, 3, 2, 1, 0, 0, 0, 1, 2, 3]),
  electronic([6, 5, 2, 0, -2, 2, 1, 2, 5, 6]),
  loudness([6, 4, 1, 0, -1, 0, -1, 0, 3, 5]);

  const EqualizerPreset(this.bandGainsDb);

  /// Gain per band in dB, same order as [kEqualizerBandFrequenciesHz].
  final List<double> bandGainsDb;

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
    EqualizerPreset.flat => l10n.equalizerPresetFlat,
    EqualizerPreset.bassBoost => l10n.equalizerPresetBassBoost,
    EqualizerPreset.trebleBoost => l10n.equalizerPresetTrebleBoost,
    EqualizerPreset.voice => l10n.equalizerPresetVoice,
    EqualizerPreset.rock => l10n.equalizerPresetRock,
    EqualizerPreset.pop => l10n.equalizerPresetPop,
    EqualizerPreset.jazz => l10n.equalizerPresetJazz,
    EqualizerPreset.classical => l10n.equalizerPresetClassical,
    EqualizerPreset.electronic => l10n.equalizerPresetElectronic,
    EqualizerPreset.loudness => l10n.equalizerPresetLoudness,
  };
}

/// The media player's equalizer configuration. Global (not per file) and
/// persisted with the rest of the media viewer settings.
///
/// Immutable and always normalised: exactly [kEqualizerBandCount] gains, each
/// clamped to +-[kEqualizerMaxGainDb] and rounded to 0.1 dB, so a value read
/// from disk or built by hand can never put the native side out of range.
@immutable
class AudioEqualizerSettings {
  /// Master switch. While false the audio is untouched.
  final bool enabled;

  /// Broadband gain applied before the bands, in dB.
  final double preampDb;

  /// Gain of each band in dB (see [kEqualizerBandFrequenciesHz]).
  final List<double> bandGainsDb;

  /// Lower the overall level by exactly as much as the bands boost their
  /// loudest frequency, so a boost can't distort.
  final bool preventClipping;

  const AudioEqualizerSettings._({
    required this.enabled,
    required this.preampDb,
    required this.bandGainsDb,
    required this.preventClipping,
  });

  factory AudioEqualizerSettings({
    bool enabled = false,
    double preampDb = 0,
    List<double>? bandGainsDb,
    bool preventClipping = true,
  }) => AudioEqualizerSettings._(
    enabled: enabled,
    preampDb: _clampGain(preampDb),
    bandGainsDb: _normalizeGains(bandGainsDb),
    preventClipping: preventClipping,
  );

  /// Off, flat, no preamp. A true constant, so it can serve as a `const`
  /// default (e.g. in `MediaViewerToolbarConfig`).
  static const AudioEqualizerSettings defaults = AudioEqualizerSettings._(
    enabled: false,
    preampDb: 0,
    bandGainsDb: _flatGains,
    preventClipping: true,
  );

  static const List<double> _flatGains = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

  AudioEqualizerSettings copyWith({
    bool? enabled,
    double? preampDb,
    List<double>? bandGainsDb,
    bool? preventClipping,
  }) => AudioEqualizerSettings(
    enabled: enabled ?? this.enabled,
    preampDb: preampDb ?? this.preampDb,
    bandGainsDb: bandGainsDb ?? this.bandGainsDb,
    preventClipping: preventClipping ?? this.preventClipping,
  );

  /// A copy with band [index] set to [gainDb].
  AudioEqualizerSettings withBandGain(int index, double gainDb) {
    if (index < 0 || index >= kEqualizerBandCount) return this;
    final gains = List<double>.of(bandGainsDb);
    gains[index] = gainDb;
    return copyWith(bandGainsDb: gains);
  }

  /// A copy using [preset]'s band gains (everything else unchanged).
  AudioEqualizerSettings withPreset(EqualizerPreset preset) =>
      copyWith(bandGainsDb: preset.bandGainsDb);

  /// The preset whose gains the bands currently match exactly, or null when
  /// they have been tweaked into something custom.
  EqualizerPreset? get matchingPreset {
    for (final preset in EqualizerPreset.values) {
      var same = true;
      for (var i = 0; i < kEqualizerBandCount; i++) {
        if ((bandGainsDb[i] - preset.bandGainsDb[i]).abs() > 0.05) {
          same = false;
          break;
        }
      }
      if (same) return preset;
    }
    return null;
  }

  /// True when the bands and the preamp are all at 0 dB.
  bool get isFlat =>
      preampDb.abs() < 0.05 && bandGainsDb.every((g) => g.abs() < 0.05);

  /// The payload understood by the native player's `setEqualizer` /
  /// `initialize` (see EqualizerSettings.fromMap in EqualizerDsp.kt).
  Map<String, Object> toChannelMap() => {
    'enabled': enabled,
    'preampDb': preampDb,
    'bandGainsDb': bandGainsDb,
    'preventClipping': preventClipping,
  };

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'preampDb': preampDb,
    'bandGainsDb': bandGainsDb,
    'preventClipping': preventClipping,
  };

  /// Tolerant of missing / mistyped fields (older or hand-edited configs):
  /// anything unusable falls back to its default.
  factory AudioEqualizerSettings.fromJson(Object? json) {
    if (json is! Map) return defaults;
    final rawGains = json['bandGainsDb'];
    return AudioEqualizerSettings(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
      preampDb: json['preampDb'] is num
          ? (json['preampDb'] as num).toDouble()
          : 0,
      bandGainsDb: rawGains is List
          ? [for (final g in rawGains) g is num ? g.toDouble() : 0.0]
          : null,
      preventClipping: json['preventClipping'] is bool
          ? json['preventClipping'] as bool
          : true,
    );
  }

  static double _clampGain(double v) {
    if (v.isNaN) return 0;
    final clamped = v.clamp(-kEqualizerMaxGainDb, kEqualizerMaxGainDb);
    return (clamped * 10).round() / 10;
  }

  static List<double> _normalizeGains(List<double>? source) =>
      List<double>.unmodifiable([
        for (var i = 0; i < kEqualizerBandCount; i++)
          source != null && i < source.length ? _clampGain(source[i]) : 0.0,
      ]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AudioEqualizerSettings &&
          other.enabled == enabled &&
          other.preampDb == preampDb &&
          other.preventClipping == preventClipping &&
          listEquals(other.bandGainsDb, bandGainsDb);

  @override
  int get hashCode =>
      Object.hash(enabled, preampDb, preventClipping, Object.hashAll(bandGainsDb));
}
