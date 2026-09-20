import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/scrub_preview_style.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_scrub_preview_controller.dart';

/// Stands in for the native player: records how big/what quality each scrub
/// frame was asked for. Only the three scrub methods are ever called by
/// [VideoScrubPreviewController]; anything else would throw, which is the
/// point of [Fake].
class _RecordingNativeController extends Fake implements NativeVideoController {
  final List<int> requestedMaxSizes = [];
  final List<int> requestedQualities = [];
  int endCalls = 0;

  @override
  Future<bool> startScrubPreview() async => true;

  @override
  Future<Uint8List?> getScrubPreviewFrame(
    Duration position, {
    int maxSize = 200,
    int quality = 55,
  }) async {
    requestedMaxSizes.add(maxSize);
    requestedQualities.add(quality);
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> endScrubPreview() async => endCalls++;
}

/// Returns a frame of a fixed size for every request, so cache behaviour
/// (which is bounded by bytes) can be exercised without real decoding.
class _SizedNativeController extends Fake implements NativeVideoController {
  _SizedNativeController(this.frameBytes);

  final int frameBytes;

  @override
  Future<bool> startScrubPreview() async => true;

  @override
  Future<Uint8List?> getScrubPreviewFrame(
    Duration position, {
    int maxSize = 200,
    int quality = 55,
  }) async =>
      Uint8List(frameBytes);

  @override
  Future<void> endScrubPreview() async {}
}

void main() {
  Future<_RecordingNativeController> scrubOnce(ScrubPreviewStyle style) async {
    final native = _RecordingNativeController();
    final preview = VideoScrubPreviewController.forStyle(native, style);
    await preview.begin();
    preview.requestFrame(const Duration(seconds: 5));
    await pumpEventQueue();
    preview.dispose();
    return native;
  }

  test('mini box keeps asking for small frames', () async {
    final native = await scrubOnce(ScrubPreviewStyle.miniBox);

    expect(native.requestedMaxSizes, [200]);
    expect(native.requestedQualities, [55]);
  });

  test('fullscreen asks for much larger, higher-quality frames', () async {
    final mini = await scrubOnce(ScrubPreviewStyle.miniBox);
    final full = await scrubOnce(ScrubPreviewStyle.fullscreen);

    expect(full.requestedMaxSizes.single,
        greaterThan(mini.requestedMaxSizes.single * 4));
    expect(full.requestedQualities.single,
        greaterThan(mini.requestedQualities.single));
  });

  test('a decoded frame is published on frameNotifier', () async {
    final native = _RecordingNativeController();
    final preview =
        VideoScrubPreviewController.forStyle(native, ScrubPreviewStyle.fullscreen);
    addTearDown(preview.dispose);

    await preview.begin();
    expect(preview.available, isTrue);
    expect(preview.frameNotifier.value, isNull);

    preview.requestFrame(const Duration(seconds: 5));
    await pumpEventQueue();

    expect(preview.frameNotifier.value, Uint8List.fromList([1, 2, 3]));
  });

  test('isDisposed flips on dispose, which also closes the native session', () async {
    final native = _RecordingNativeController();
    final preview = VideoScrubPreviewController(native);

    await preview.begin();
    expect(preview.isDisposed, isFalse);

    preview.dispose();
    await pumpEventQueue();

    expect(preview.isDisposed, isTrue);
    expect(native.endCalls, 1);
  });

  group('position buckets and cache', () {
    Future<VideoScrubPreviewController> scrubbed({
      required int frameBytes,
      required Iterable<Duration> positions,
      Duration videoDuration = Duration.zero,
    }) async {
      final preview = VideoScrubPreviewController.forStyle(
        _SizedNativeController(frameBytes),
        ScrubPreviewStyle.miniBox,
        videoDuration: videoDuration,
      );
      addTearDown(preview.dispose);
      await preview.begin();
      for (final position in positions) {
        preview.requestFrame(position);
        await pumpEventQueue();
      }
      return preview;
    }

    test('bucket width follows the video: fine for short clips, 750 ms cap for long ones', () {
      expect(VideoScrubPreviewController.bucketMsFor(Duration.zero), 750);
      expect(VideoScrubPreviewController.bucketMsFor(const Duration(seconds: -1)), 750);
      // ~1/240 of the video, floored at about one frame.
      expect(VideoScrubPreviewController.bucketMsFor(const Duration(seconds: 5)), 33);
      expect(VideoScrubPreviewController.bucketMsFor(const Duration(seconds: 30)), 125);
      // The old fixed width is still the ceiling.
      expect(VideoScrubPreviewController.bucketMsFor(const Duration(minutes: 3)), 750);
      expect(VideoScrubPreviewController.bucketMsFor(const Duration(hours: 2)), 750);
    });

    test('bucket width never leaves the [one frame, 750 ms] range', () {
      for (final seconds in [1, 2, 5, 10, 20, 60, 120, 180, 600, 7200]) {
        final ms = VideoScrubPreviewController.bucketMsFor(Duration(seconds: seconds));
        expect(ms, inInclusiveRange(33, 750), reason: '${seconds}s');
      }
    });

    test('on a short clip, positions 100 ms apart each get their own cache slot', () async {
      // Regression: with the fixed 750 ms buckets these ten positions fell in
      // two slots, so a 5 s clip could only ever show a handful of frames.
      final positions = [for (var i = 0; i < 10; i++) Duration(milliseconds: i * 100)];

      final fine = await scrubbed(
        frameBytes: 16,
        positions: positions,
        videoDuration: const Duration(seconds: 5),
      );
      final coarse = await scrubbed(frameBytes: 16, positions: positions);

      expect(fine.cachedFrameCount, 10);
      expect(coarse.cachedFrameCount, 2);
    });

    test('small frames are all retained', () async {
      final preview = await scrubbed(
        frameBytes: 10 * 1024,
        positions: [for (var i = 0; i < 100; i++) Duration(seconds: i)],
      );

      expect(preview.cachedFrameCount, 100);
    });

    test('the cache is capped by size, evicting the oldest frames', () async {
      // 20 distinct 1 MiB frames: far more than the byte budget holds.
      final preview = await scrubbed(
        frameBytes: 1024 * 1024,
        positions: [for (var i = 0; i < 20; i++) Duration(seconds: i)],
      );

      expect(preview.cachedFrameCount, inInclusiveRange(1, 6));
    });

    test('a frame larger than the whole budget is still kept', () async {
      final preview = await scrubbed(
        frameBytes: 8 * 1024 * 1024,
        positions: const [Duration(seconds: 1)],
      );

      expect(preview.cachedFrameCount, 1);
    });

    test('re-fetching the same bucket replaces its frame rather than adding one', () async {
      final preview = await scrubbed(
        frameBytes: 1024,
        positions: const [Duration(seconds: 1), Duration(seconds: 1), Duration(seconds: 1)],
      );

      expect(preview.cachedFrameCount, 1);
    });
  });
}
