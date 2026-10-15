import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/audio_recording_quality.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  group('AudioRecordingQuality', () {
    test('the High preset is the old fixed 128 kbps / 44.1 kHz setting', () {
      expect(AudioRecordingQuality.high.bitrate, 128000);
      expect(AudioRecordingQuality.high.sampleRate, 44100);
    });

    test('presets get smaller as the quality drops', () {
      expect(
        AudioRecordingQuality.voice.bitrate,
        lessThan(AudioRecordingQuality.standard.bitrate),
      );
      expect(
        AudioRecordingQuality.standard.bitrate,
        lessThan(AudioRecordingQuality.high.bitrate),
      );
    });

    test('every preset uses a sample rate the native recorder accepts', () {
      // Mirrors AudioRecordingParams.SAMPLE_RATES on the Kotlin side.
      const accepted = {
        8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000,
      };
      for (final q in AudioRecordingQuality.values) {
        expect(accepted, contains(q.sampleRate), reason: q.name);
        expect(q.bitrate, inInclusiveRange(16000, 192000), reason: q.name);
      }
    });

    test('the picker description shows the real encoder values', () {
      final l10n = AppLocalizationsEn();
      expect(
        AudioRecordingQuality.voice.getLocalizedSubtitle(l10n),
        'AAC · 32 kbps · 22.05 kHz · mono',
      );
      expect(
        AudioRecordingQuality.standard.getLocalizedSubtitle(l10n),
        'AAC · 64 kbps · 44.1 kHz · mono',
      );
      expect(
        AudioRecordingQuality.high.getLocalizedSubtitle(l10n),
        'AAC · 128 kbps · 44.1 kHz · mono',
      );
    });

    test('json round-trips and unknown values fall back to the default', () {
      for (final q in AudioRecordingQuality.values) {
        expect(AudioRecordingQuality.fromJson(q.toJson()), q);
      }
      expect(AudioRecordingQuality.fromJson(null), AudioRecordingQuality.standard);
      expect(AudioRecordingQuality.fromJson('lossless'), AudioRecordingQuality.standard);
    });
  });
}
