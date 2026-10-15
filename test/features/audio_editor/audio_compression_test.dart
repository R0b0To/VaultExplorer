import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_audio_edit_api.dart';
import 'package:vaultexplorer/features/audio_editor/models/audio_compression.dart';

AudioProbe _probe({int? bitrate, int? channels = 1, bool canCompress = true}) =>
    AudioProbe(
      durationUs: 3600 * 1000000,
      mime: 'audio/mp4a-latm',
      outputExtension: 'm4a',
      cutSupported: true,
      bitrate: bitrate,
      channels: channels,
      canCompress: canCompress,
    );

void main() {
  group('AudioCompression', () {
    test('off does not re-encode; the others carry a per-channel bitrate', () {
      expect(AudioCompression.off.isOn, isFalse);
      expect(AudioCompression.off.bitratePerChannel, isNull);
      expect(AudioCompression.balanced.bitratePerChannel, 64000);
      expect(AudioCompression.small.bitratePerChannel, 32000);
    });

    test('mono stays mono and wider audio becomes a stereo pair', () {
      expect(AudioCompression.outputChannels(1), 1);
      expect(AudioCompression.outputChannels(2), 2);
      expect(AudioCompression.outputChannels(6), 2);
      expect(AudioCompression.small.totalBitrate(1), 32000);
      expect(AudioCompression.small.totalBitrate(2), 64000);
      expect(AudioCompression.small.totalBitrate(6), 64000);
      expect(AudioCompression.off.totalBitrate(2), isNull);
    });

    test('estimatedBytes follows bitrate and duration', () {
      // One hour of mono at 32 kbps is 14.4 MB.
      expect(
        AudioCompression.small.estimatedBytes(
          durationUs: 3600 * 1000000,
          sourceChannels: 1,
        ),
        14400000,
      );
      expect(
        AudioCompression.off.estimatedBytes(
          durationUs: 3600 * 1000000,
          sourceChannels: 1,
        ),
        isNull,
      );
      expect(
        AudioCompression.small.estimatedBytes(durationUs: 0, sourceChannels: 1),
        isNull,
      );
    });

    test('a compressed export is always an m4a', () {
      expect(AudioCompression.outputExtension, 'm4a');
    });

    group('optionsFor', () {
      test('offers nothing when the device cannot re-encode the file', () {
        expect(
          AudioCompression.optionsFor(_probe(bitrate: 320000, canCompress: false)),
          [AudioCompression.off],
        );
      });

      test('offers both lower bitrates for a high-bitrate source', () {
        expect(
          AudioCompression.optionsFor(_probe(bitrate: 128000)),
          [AudioCompression.off, AudioCompression.balanced, AudioCompression.small],
        );
      });

      test('skips a target that is not meaningfully below the source', () {
        // 64 kbps mono is above 80% of a 64 kbps source: only 32 is worth it.
        expect(
          AudioCompression.optionsFor(_probe(bitrate: 64000)),
          [AudioCompression.off, AudioCompression.small],
        );
        // Already at or below the lowest option: nothing to offer.
        expect(
          AudioCompression.optionsFor(_probe(bitrate: 32000)),
          [AudioCompression.off],
        );
      });

      test('compares the total bitrate, so stereo targets double', () {
        // Stereo balanced is 128 kbps, which is not below a 128 kbps source.
        expect(
          AudioCompression.optionsFor(_probe(bitrate: 128000, channels: 2)),
          [AudioCompression.off, AudioCompression.small],
        );
      });

      test('offers everything when the source bitrate is unknown', () {
        expect(
          AudioCompression.optionsFor(_probe(bitrate: null)),
          [AudioCompression.off, AudioCompression.balanced, AudioCompression.small],
        );
      });
    });
  });
}
