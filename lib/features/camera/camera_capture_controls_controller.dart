import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'camera_capture_controls_controller.g.dart';

class CameraCaptureControlsState {
  const CameraCaptureControlsState({
    this.isVideoMode = false,
    this.flashMode = 'auto',
    this.videoQuality = 'fhd',
    this.photoResolution = 'max',
    this.timerDelaySeconds = 0,
  });

  final bool isVideoMode;
  final String flashMode;
  final String videoQuality;
  final String photoResolution;
  final int timerDelaySeconds;

  CameraCaptureControlsState copyWith({
    bool? isVideoMode,
    String? flashMode,
    String? videoQuality,
    String? photoResolution,
    int? timerDelaySeconds,
  }) => CameraCaptureControlsState(
    isVideoMode: isVideoMode ?? this.isVideoMode,
    flashMode: flashMode ?? this.flashMode,
    videoQuality: videoQuality ?? this.videoQuality,
    photoResolution: photoResolution ?? this.photoResolution,
    timerDelaySeconds: timerDelaySeconds ?? this.timerDelaySeconds,
  );
}

@riverpod
class CameraCaptureControls extends _$CameraCaptureControls {
  @override
  CameraCaptureControlsState build(String sessionKey) =>
      const CameraCaptureControlsState();

  void selectVideoQuality(String value) {
    if (state.videoQuality == value) return;
    state = state.copyWith(videoQuality: value);
  }

  void selectPhotoResolution(String value) {
    if (state.photoResolution == value) return;
    state = state.copyWith(photoResolution: value);
  }

  void setVideoMode(bool value) {
    if (state.isVideoMode == value) return;
    state = state.copyWith(
      isVideoMode: value,
      flashMode: value ? 'off' : 'auto',
    );
  }

  void cycleTimerDelay() {
    final next = switch (state.timerDelaySeconds) {
      0 => 3,
      3 => 10,
      _ => 0,
    };
    state = state.copyWith(timerDelaySeconds: next);
  }

  String cyclePhotoFlashMode() {
    final next = switch (state.flashMode) {
      'auto' => 'on',
      'on' => 'off',
      _ => 'auto',
    };
    state = state.copyWith(flashMode: next);
    return next;
  }
}