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
}
