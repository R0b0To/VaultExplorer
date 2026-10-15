import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_audio_edit_api.dart';

void main() {
  group('AudioProbe.fromMap', () {
    test('reads a losslessly cuttable file', () {
      final probe = AudioProbe.fromMap({
        'durationUs': 215000000,
        'mime': 'audio/mpeg',
        'bitrate': 320000,
        'sampleRate': 44100,
        'channels': 2,
        'outputExtension': 'mp3',
        'cutSupported': true,
        'reencode': false,
        'unsupportedReason': null,
      });
      expect(probe.durationUs, 215000000);
      expect(probe.mime, 'audio/mpeg');
      expect(probe.sampleRate, 44100);
      expect(probe.channels, 2);
      expect(probe.outputExtension, 'mp3');
      expect(probe.cutSupported, isTrue);
      expect(probe.reencode, isFalse);
      expect(probe.unsupportedReason, isNull);
    });

    test('a file that has to be re-encoded is still editable', () {
      final probe = AudioProbe.fromMap({
        'durationUs': 1000000,
        'mime': 'audio/flac',
        'outputExtension': 'm4a',
        'cutSupported': true,
        'reencode': true,
      });
      expect(probe.cutSupported, isTrue);
      expect(probe.reencode, isTrue);
      expect(probe.outputExtension, 'm4a');
    });

    test('canCompress is read from the probe and defaults to false', () {
      final yes = AudioProbe.fromMap({
        'durationUs': 1000000,
        'outputExtension': 'mp3',
        'cutSupported': true,
        'canCompress': true,
      });
      expect(yes.canCompress, isTrue);

      final missing = AudioProbe.fromMap({
        'durationUs': 1000000,
        'outputExtension': 'mp3',
        'cutSupported': true,
      });
      expect(missing.canCompress, isFalse);
    });

    test('a file this device cannot decode is not editable', () {
      final probe = AudioProbe.fromMap({
        'durationUs': 1000000,
        'mime': 'audio/x-ms-wma',
        'outputExtension': 'm4a',
        'cutSupported': false,
        'reencode': true,
        'unsupportedReason': 'This device can\'t decode audio/x-ms-wma',
      });
      expect(probe.cutSupported, isFalse);
      expect(probe.unsupportedReason, contains('decode'));
    });

    test('accepts numbers of either kind and falls back safely when fields are missing', () {
      final probe = AudioProbe.fromMap({'durationUs': 5.0e6, 'bitrate': 128000.0});
      expect(probe.durationUs, 5000000);
      expect(probe.bitrate, 128000);
      expect(probe.outputExtension, 'm4a');
      expect(probe.cutSupported, isFalse);
      expect(probe.reencode, isFalse);
    });
  });
}
