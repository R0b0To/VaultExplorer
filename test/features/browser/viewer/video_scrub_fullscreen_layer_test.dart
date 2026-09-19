import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/video_scrub_preview_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/media_player_widget.dart'
    show VideoPlaybackProgress;
import 'package:vaultexplorer/features/browser/viewer/widgets/video_scrub_fullscreen_layer.dart';

class _AvailableNativeController extends Fake implements NativeVideoController {
  @override
  Future<bool> startScrubPreview() async => true;

  @override
  Future<void> endScrubPreview() async {}
}

// A valid 1x1 PNG, so the frame is something Image.memory can really decode.
final Uint8List _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const _dragging = VideoPlaybackProgress(
  position: Duration(seconds: 5),
  duration: Duration(minutes: 1),
  sliderValue: 5 / 60,
  isDragging: true,
);

void main() {
  late VideoScrubPreviewHost host;
  late ValueNotifier<VideoPlaybackProgress> progress;

  setUp(() {
    host = VideoScrubPreviewHost(null);
    progress = ValueNotifier(const VideoPlaybackProgress());
  });

  tearDown(() {
    host.dispose();
    progress.dispose();
  });

  Future<void> pumpLayer(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned.fill(
                  child: VideoScrubFullscreenLayer(
                    previewHost: host,
                    progress: progress,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  // Long enough for the layer's fade in/out to finish.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<VideoScrubPreviewController> liveSessionWithFrame() async {
    final preview = VideoScrubPreviewController(_AvailableNativeController());
    addTearDown(preview.dispose);
    await preview.begin();
    preview.frameNotifier.value = _pixel;
    return preview;
  }

  testWidgets('draws nothing before a drag starts', (tester) async {
    await pumpLayer(tester);

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('shows the frame and timestamp while dragging a live session',
      (tester) async {
    await pumpLayer(tester);
    final preview = await liveSessionWithFrame();

    host.value = preview;
    progress.value = _dragging;
    await settle(tester);

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('00:05 / 01:00'), findsOneWidget);
  });

  testWidgets('goes away when the drag ends', (tester) async {
    await pumpLayer(tester);
    final preview = await liveSessionWithFrame();
    host.value = preview;
    progress.value = _dragging;
    await settle(tester);

    progress.value = _dragging.copyWith(isDragging: false);
    await settle(tester);

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('stays hidden until a session has been published', (tester) async {
    await pumpLayer(tester);

    // Dragging, but the native session hasn't been confirmed available yet
    // (or never will be, e.g. an unsupported codec): nothing to draw.
    progress.value = _dragging;
    await settle(tester);

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining(' / '), findsNothing);
  });

  testWidgets('ignores a stale, already-disposed session', (tester) async {
    await pumpLayer(tester);
    final preview = VideoScrubPreviewController(_AvailableNativeController());
    await preview.begin();
    preview.frameNotifier.value = _pixel;
    host.value = preview;
    // The seekbar was unmounted mid-drag: it disposes its session but cannot
    // clear the host from dispose().
    preview.dispose();

    progress.value = _dragging;
    await settle(tester);

    expect(find.byType(Image), findsNothing);
  });

  testWidgets('never intercepts pointer events', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              // Stands in for the media page underneath.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => taps++,
                ),
              ),
              Positioned.fill(
                child: VideoScrubFullscreenLayer(
                  previewHost: host,
                  progress: progress,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final preview = await liveSessionWithFrame();
    host.value = preview;
    progress.value = _dragging;
    await settle(tester);
    // The layer really is covering the screen right now...
    expect(find.text('00:05 / 01:00'), findsOneWidget);

    // ...yet a touch still reaches what's underneath it.
    await tester.tapAt(tester.getCenter(find.byType(Scaffold)));

    expect(taps, 1);
  });
}
