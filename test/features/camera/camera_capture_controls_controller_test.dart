import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/camera/camera_capture_controls_controller.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('CameraCaptureControls controller', () {
    test('starts with the photo defaults', () {
      final state = container.read(cameraCaptureControlsProvider('session-a'));

      expect(state.isVideoMode, isFalse);
      expect(state.flashMode, 'auto');
      expect(state.videoQuality, 'fhd');
      expect(state.timerDelaySeconds, 0);
    });

    test('owns the video mode and corresponding flash default', () {
      final controller = container.read(
        cameraCaptureControlsProvider('session-a').notifier,
      );

      controller.setVideoMode(true);
      var state = container.read(cameraCaptureControlsProvider('session-a'));
      expect(state.isVideoMode, isTrue);
      expect(state.flashMode, 'off');

      controller.setVideoMode(false);
      state = container.read(cameraCaptureControlsProvider('session-a'));
      expect(state.isVideoMode, isFalse);
      expect(state.flashMode, 'auto');
    });

    test('cycles timer and photo flash settings', () {
      final controller = container.read(
        cameraCaptureControlsProvider('session-a').notifier,
      );

      controller.cycleTimerDelay();
      expect(
        container.read(cameraCaptureControlsProvider('session-a')).timerDelaySeconds,
        3,
      );
      controller.cycleTimerDelay();
      expect(
        container.read(cameraCaptureControlsProvider('session-a')).timerDelaySeconds,
        10,
      );
      controller.cycleTimerDelay();
      expect(
        container.read(cameraCaptureControlsProvider('session-a')).timerDelaySeconds,
        0,
      );

      expect(controller.cyclePhotoFlashMode(), 'on');
      expect(controller.cyclePhotoFlashMode(), 'off');
      expect(controller.cyclePhotoFlashMode(), 'auto');
    });

    test('keeps controls isolated by camera screen session', () {
      container
          .read(cameraCaptureControlsProvider('session-a').notifier)
          .selectVideoQuality('uhd');
      container
          .read(cameraCaptureControlsProvider('session-b').notifier)
          .setVideoMode(true);

      expect(
        container.read(cameraCaptureControlsProvider('session-a')).videoQuality,
        'uhd',
      );
      expect(
        container.read(cameraCaptureControlsProvider('session-a')).isVideoMode,
        isFalse,
      );
      expect(
        container.read(cameraCaptureControlsProvider('session-b')).videoQuality,
        'fhd',
      );
      expect(
        container.read(cameraCaptureControlsProvider('session-b')).isVideoMode,
        isTrue,
      );
    });
  });
}
