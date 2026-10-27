import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/audio_recording_quality.dart';
import 'package:vaultexplorer/features/camera/vault_audio_recorder_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('normalizeAudioAmplitude', () {
    test('silence and invalid input read as zero', () {
      expect(normalizeAudioAmplitude(0), 0.0);
      expect(normalizeAudioAmplitude(-5), 0.0);
    });

    test('full scale reads as one, and anything above is clamped', () {
      expect(normalizeAudioAmplitude(32767), closeTo(1.0, 1e-9));
      expect(normalizeAudioAmplitude(40000), closeTo(1.0, 1e-9));
    });

    test('is monotonic and lifts quiet speech well above a linear scale', () {
      final quiet = normalizeAudioAmplitude(300);
      final mid = normalizeAudioAmplitude(3000);
      final loud = normalizeAudioAmplitude(20000);
      expect(quiet, lessThan(mid));
      expect(mid, lessThan(loud));
      // 3000/32767 is ~9% linear; on the dB scale it must read much higher.
      expect(mid, greaterThan(0.5));
    });

    test('falls to zero at the -50 dB floor', () {
      // 32767 * 10^(-50/20) ~= 104
      expect(normalizeAudioAmplitude(100), lessThan(0.02));
      expect(normalizeAudioAmplitude(1), 0.0);
    });
  });

  group('formatAudioDuration', () {
    test('formats minutes and seconds', () {
      expect(formatAudioDuration(0), '0:00');
      expect(formatAudioDuration(999), '0:00');
      expect(formatAudioDuration(59999), '0:59');
      expect(formatAudioDuration(65000), '1:05');
    });

    test('adds hours past one hour', () {
      expect(formatAudioDuration(3600000), '1:00:00');
      expect(formatAudioDuration(3723000), '1:02:03');
    });

    test('clamps negative input', () {
      expect(formatAudioDuration(-1000), '0:00');
    });
  });

  group('VaultAudioRecorderController', () {
    const channel = MethodChannel('test/audio-capture');
    late VaultAudioRecorderController controller;
    late List<MethodCall> calls;
    late Future<Object?> Function(MethodCall call) handler;

    setUp(() {
      calls = [];
      handler = (_) async => null;
      controller = VaultAudioRecorderController(channel: channel);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            calls.add(call);
            return handler(call);
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('start reports success and surfaces the native error', () async {
      handler = (_) async => {'success': true};
      expect((await controller.start()).success, isTrue);

      handler = (_) async => {'success': false, 'error': 'permission_denied'};
      final denied = await controller.start();
      expect(denied.success, isFalse);
      expect(denied.error, 'permission_denied');
    });

    test('start sends the chosen quality as bitrate and sample rate', () async {
      handler = (_) async => {'success': true};

      await controller.start(quality: AudioRecordingQuality.voice);
      expect(calls.last.method, 'start');
      expect(calls.last.arguments, {
        'bitrate': 32000,
        'sampleRate': 22050,
        'segmentSeconds': 0,
      });

      await controller.start(quality: AudioRecordingQuality.high);
      expect(calls.last.arguments, {
        'bitrate': 128000,
        'sampleRate': 44100,
        'segmentSeconds': 0,
      });

      // No quality given: the default preset, not an unset value.
      await controller.start();
      expect(calls.last.arguments, {
        'bitrate': AudioRecordingQuality.defaultQuality.bitrate,
        'sampleRate': AudioRecordingQuality.defaultQuality.sampleRate,
        'segmentSeconds': 0,
      });
    });

    test('stop maps a finished take', () async {
      handler = (_) async => {
        'success': true,
        'path': '/cache/vx_aud_1.m4a',
        'durationMs': 4200,
      };
      final res = await controller.stop();
      expect(res.success, isTrue);
      expect(res.path, '/cache/vx_aud_1.m4a');
      expect(res.durationMs, 4200);
    });

    test('stop never exposes a path for a failed take', () async {
      handler = (_) async => {
        'success': false,
        'path': '/cache/vx_aud_1.m4a',
        'error': 'no audio was captured',
      };
      final res = await controller.stop();
      expect(res.success, isFalse);
      expect(res.path, isNull);
      expect(res.error, 'no audio was captured');
    });

    test('trim returns the new path, and null when the native trim failed',
        () async {
      handler = (_) async => {'path': '/cache/vx_vid_trim_9.mp4'};
      expect(
        await controller.trim(path: '/cache/vx_aud_1.m4a', startMs: 1000, endMs: 3000),
        '/cache/vx_vid_trim_9.mp4',
      );
      expect(calls.last.method, 'trim');
      expect(calls.last.arguments, {
        'path': '/cache/vx_aud_1.m4a',
        'startMs': 1000,
        'endMs': 3000,
      });

      // The native side hands back the source path when it could not trim.
      handler = (_) async => {'path': '/cache/vx_aud_1.m4a'};
      expect(
        await controller.trim(path: '/cache/vx_aud_1.m4a', startMs: 1000, endMs: 3000),
        isNull,
      );
    });

    test('saveToVault sends the target and reports failure as false', () async {
      handler = (_) async => {'success': true};
      expect(
        await controller.saveToVault(path: '/cache/vx_aud_1.m4a', volId: 7, virtualPath: 'Rec/AUD.m4a'),
        isTrue,
      );
      expect(calls.last.arguments, {
        'path': '/cache/vx_aud_1.m4a',
        'volId': 7,
        'virtualPath': 'Rec/AUD.m4a',
      });

      handler = (_) async => throw PlatformException(code: 'audio_capture_error');
      expect(
        await controller.saveToVault(path: '/cache/vx_aud_1.m4a', volId: 7, virtualPath: 'Rec/AUD.m4a'),
        isFalse,
      );
    });

    test('level normalizes the raw amplitude and reads silence on error', () async {
      handler = (_) async => 32767;
      expect(await controller.level(), closeTo(1.0, 1e-9));

      handler = (_) async => throw PlatformException(code: 'audio_capture_error');
      expect(await controller.level(), 0.0);
    });

    test('discard and cancel swallow platform errors', () async {
      handler = (_) async => throw PlatformException(code: 'audio_capture_error');
      await controller.discard('/cache/vx_aud_1.m4a');
      await controller.cancel();
      expect(calls.map((c) => c.method), ['discard', 'cancel']);
    });
  });
}
