import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/audio_equalizer_settings.dart';

void main() {
  group('band layout', () {
    test('has one frequency per band, an octave apart', () {
      expect(kEqualizerBandFrequenciesHz, hasLength(kEqualizerBandCount));
      for (var i = 1; i < kEqualizerBandCount; i++) {
        expect(
          kEqualizerBandFrequenciesHz[i] / kEqualizerBandFrequenciesHz[i - 1],
          2,
        );
      }
    });

    test('every preset has a gain for every band, within range', () {
      for (final preset in EqualizerPreset.values) {
        expect(preset.bandGainsDb, hasLength(kEqualizerBandCount), reason: '$preset');
        for (final g in preset.bandGainsDb) {
          expect(g.abs(), lessThanOrEqualTo(kEqualizerMaxGainDb), reason: '$preset');
        }
      }
      expect(
        EqualizerPreset.flat.bandGainsDb.every((g) => g == 0),
        isTrue,
      );
    });

    test('matches the native player (EqualizerDsp.kt)', () {
      // The band layout lives in two languages; this fails if one side is
      // edited without the other.
      final kotlin = File(
        'android/app/src/main/kotlin/com/aeidolon/vaultexplorer/engine/EqualizerDsp.kt',
      ).readAsStringSync();

      final freqs = RegExp(r'BAND_FREQUENCIES_HZ\s*=\s*doubleArrayOf\(([^)]*)\)')
          .firstMatch(kotlin)!
          .group(1)!
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .map(double.parse)
          .toList();
      expect(freqs, kEqualizerBandFrequenciesHz);

      final count = RegExp(r'const val BAND_COUNT\s*=\s*(\d+)')
          .firstMatch(kotlin)!
          .group(1)!;
      expect(int.parse(count), kEqualizerBandCount);

      final maxGain = RegExp(r'const val MAX_GAIN_DB\s*=\s*([\d.]+)f')
          .firstMatch(kotlin)!
          .group(1)!;
      expect(double.parse(maxGain), kEqualizerMaxGainDb);
    });
  });

  group('AudioEqualizerSettings', () {
    test('defaults are off, flat, and guard against clipping', () {
      final d = AudioEqualizerSettings.defaults;
      expect(d.enabled, isFalse);
      expect(d.preampDb, 0);
      expect(d.bandGainsDb, everyElement(0));
      expect(d.bandGainsDb, hasLength(kEqualizerBandCount));
      expect(d.preventClipping, isTrue);
      expect(d.isFlat, isTrue);
      expect(d.matchingPreset, EqualizerPreset.flat);
    });

    test('normalises what it is given', () {
      final s = AudioEqualizerSettings(
        enabled: true,
        preampDb: 50,
        bandGainsDb: [double.nan, 20, -20, 3.04, 2.96],
      );
      expect(s.preampDb, kEqualizerMaxGainDb);
      expect(s.bandGainsDb, hasLength(kEqualizerBandCount));
      expect(s.bandGainsDb[0], 0); // NaN
      expect(s.bandGainsDb[1], kEqualizerMaxGainDb); // clamped
      expect(s.bandGainsDb[2], -kEqualizerMaxGainDb);
      expect(s.bandGainsDb[3], 3.0); // rounded to 0.1 dB
      expect(s.bandGainsDb[4], 3.0);
      expect(s.bandGainsDb[9], 0); // padded
    });

    test('ignores surplus gains', () {
      final s = AudioEqualizerSettings(bandGainsDb: List.filled(25, 5));
      expect(s.bandGainsDb, hasLength(kEqualizerBandCount));
    });

    test('gains cannot be modified in place', () {
      final s = AudioEqualizerSettings(bandGainsDb: [1, 2, 3]);
      expect(() => s.bandGainsDb[0] = 9, throwsUnsupportedError);
      expect(() => AudioEqualizerSettings.defaults.bandGainsDb[0] = 9,
          throwsUnsupportedError);
    });

    test('withBandGain changes only that band', () {
      final s = AudioEqualizerSettings.defaults.withBandGain(4, 6.5);
      expect(s.bandGainsDb[4], 6.5);
      expect(
        [for (var i = 0; i < kEqualizerBandCount; i++) if (i != 4) s.bandGainsDb[i]],
        everyElement(0),
      );
      expect(AudioEqualizerSettings.defaults.withBandGain(-1, 5),
          AudioEqualizerSettings.defaults);
      expect(AudioEqualizerSettings.defaults.withBandGain(kEqualizerBandCount, 5),
          AudioEqualizerSettings.defaults);
    });

    test('withPreset takes the preset gains and keeps everything else', () {
      final s = AudioEqualizerSettings(
        enabled: true,
        preampDb: -3,
        preventClipping: false,
      ).withPreset(EqualizerPreset.rock);
      expect(s.bandGainsDb, EqualizerPreset.rock.bandGainsDb);
      expect(s.enabled, isTrue);
      expect(s.preampDb, -3);
      expect(s.preventClipping, isFalse);
    });

    test('recognises a preset, and "custom" once it is tweaked', () {
      for (final preset in EqualizerPreset.values) {
        expect(
          AudioEqualizerSettings.defaults.withPreset(preset).matchingPreset,
          preset,
        );
      }
      final tweaked = AudioEqualizerSettings.defaults
          .withPreset(EqualizerPreset.rock)
          .withBandGain(0, 1);
      expect(tweaked.matchingPreset, isNull);
    });

    test('the preamp does not affect which preset matches', () {
      final s = AudioEqualizerSettings.defaults
          .withPreset(EqualizerPreset.jazz)
          .copyWith(preampDb: -4);
      expect(s.matchingPreset, EqualizerPreset.jazz);
    });

    test('isFlat needs flat bands and no preamp', () {
      expect(AudioEqualizerSettings.defaults.isFlat, isTrue);
      expect(AudioEqualizerSettings.defaults.copyWith(preampDb: 2).isFlat, isFalse);
      expect(AudioEqualizerSettings.defaults.withBandGain(3, -1).isFlat, isFalse);
      expect(AudioEqualizerSettings.defaults.copyWith(enabled: true).isFlat, isTrue);
    });
  });

  group('serialisation', () {
    test('channel payload has the shape the native side parses', () {
      final map = AudioEqualizerSettings(
        enabled: true,
        preampDb: -2.5,
        bandGainsDb: EqualizerPreset.bassBoost.bandGainsDb,
        preventClipping: false,
      ).toChannelMap();
      expect(map.keys.toSet(), {
        'enabled',
        'preampDb',
        'bandGainsDb',
        'preventClipping',
      });
      expect(map['enabled'], true);
      expect(map['preampDb'], -2.5);
      expect(map['preventClipping'], false);
      expect(map['bandGainsDb'], EqualizerPreset.bassBoost.bandGainsDb);
    });

    test('survives a JSON round trip', () {
      final original = AudioEqualizerSettings(
        enabled: true,
        preampDb: 1.5,
        bandGainsDb: EqualizerPreset.pop.bandGainsDb,
        preventClipping: false,
      );
      expect(AudioEqualizerSettings.fromJson(original.toJson()), original);
    });

    test('fromJson falls back to defaults for anything unusable', () {
      expect(AudioEqualizerSettings.fromJson(null), AudioEqualizerSettings.defaults);
      expect(AudioEqualizerSettings.fromJson('nope'), AudioEqualizerSettings.defaults);
      final s = AudioEqualizerSettings.fromJson({
        'enabled': 'yes',
        'preampDb': 'loud',
        'bandGainsDb': ['x', 4],
        'preventClipping': 3,
      });
      expect(s.enabled, isFalse);
      expect(s.preampDb, 0);
      expect(s.bandGainsDb[0], 0);
      expect(s.bandGainsDb[1], 4);
      expect(s.preventClipping, isTrue);
    });

    test('fromJson clamps out-of-range values from a hand-edited file', () {
      final s = AudioEqualizerSettings.fromJson({
        'enabled': true,
        'preampDb': 99,
        'bandGainsDb': [-99, 99],
      });
      expect(s.preampDb, kEqualizerMaxGainDb);
      expect(s.bandGainsDb[0], -kEqualizerMaxGainDb);
      expect(s.bandGainsDb[1], kEqualizerMaxGainDb);
    });
  });

  group('equality', () {
    test('compares by value', () {
      final a = AudioEqualizerSettings(enabled: true, bandGainsDb: [1, 2, 3]);
      final b = AudioEqualizerSettings(enabled: true, bandGainsDb: [1, 2, 3]);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(enabled: false)));
      expect(a, isNot(a.withBandGain(0, 5)));
      expect(a, isNot(a.copyWith(preampDb: 1)));
      expect(a, isNot(a.copyWith(preventClipping: false)));
    });
  });
}
