import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/audio_editor/models/audio_waveform.dart';
import 'package:vaultexplorer/features/camera/audio_waveform_trimmer.dart';

void main() {
  group('AudioWaveformTrimmer', () {
    testWidgets('renders time badges and duration', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioWaveformTrimmer(
              durationMs: 10000,
              trimStartMs: 2000,
              trimEndMs: 8000,
              currentPositionMs: 3000,
              onTrimChanged: (start, end) {},
            ),
          ),
        ),
      );

      // Start: 0:02, End: 0:08, Trimmed: 0:06
      expect(find.text('0:02'), findsOneWidget);
      expect(find.text('0:08'), findsOneWidget);
      expect(find.text('Trimmed: 0:06'), findsOneWidget);
    });

    testWidgets('renders when not trimmed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioWaveformTrimmer(
              durationMs: 15000,
              trimStartMs: 0,
              trimEndMs: 15000,
              currentPositionMs: 0,
              onTrimChanged: (start, end) {},
            ),
          ),
        ),
      );

      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0:15'), findsOneWidget);
      expect(find.text('Duration: 0:15'), findsOneWidget);
    });

    testWidgets('renders with AudioWaveform and recordedLevels', (tester) async {
      final peaks = Uint8List.fromList([10, 50, 100, 200, 255, 128, 64]);
      final waveform = AudioWaveform(peaks: peaks, peaksPerSecond: 10);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AudioWaveformTrimmer(
              durationMs: 5000,
              trimStartMs: 1000,
              trimEndMs: 4000,
              currentPositionMs: 2000,
              waveform: waveform,
              recordedLevels: const [0.1, 0.4, 0.8, 0.5, 0.2],
              onTrimChanged: (start, end) {},
            ),
          ),
        ),
      );

      expect(find.byType(AudioWaveformTrimmer), findsOneWidget);
    });

    testWidgets('tapping inside active region calls onSeek', (tester) async {
      int? soughtMs;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: AudioWaveformTrimmer(
                  durationMs: 10000,
                  trimStartMs: 0,
                  trimEndMs: 10000,
                  currentPositionMs: 0,
                  onTrimChanged: (start, end) {},
                  onSeek: (ms) => soughtMs = ms,
                ),
              ),
            ),
          ),
        ),
      );

      // Tap roughly in the middle of the track
      await tester.tap(find.byType(GestureDetector).last);
      expect(soughtMs, isNotNull);
      expect(soughtMs!, inInclusiveRange(4000, 6000));
    });

    testWidgets('drag on handle calls onTrimChanged and onTrimChangeStart/End', (tester) async {
      int? changedStart;
      int? changedEnd;
      var startCalled = false;
      var endCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 300,
                child: AudioWaveformTrimmer(
                  durationMs: 10000,
                  trimStartMs: 2000,
                  trimEndMs: 8000,
                  currentPositionMs: 2000,
                  onTrimChangeStart: () => startCalled = true,
                  onTrimChangeEnd: () => endCalled = true,
                  onTrimChanged: (start, end) {
                    changedStart = start;
                    changedEnd = end;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final trackFinder = find.byType(GestureDetector).last;
      final trackTopLeft = tester.getTopLeft(trackFinder);
      // Start handle is around x = 14 + 0.2 * 272 ≈ 68 px
      final handleOffset = trackTopLeft + const Offset(68, 40);
      await tester.dragFrom(handleOffset, const Offset(40, 0));
      await tester.pumpAndSettle();

      expect(startCalled, isTrue);
      expect(endCalled, isTrue);
      expect(changedStart, isNotNull);
    });
  });
}
