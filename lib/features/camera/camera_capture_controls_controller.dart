import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'camera_capture_controls_controller.g.dart';

/// The user-selected capture controls for one camera screen instance.
///
/// This deliberately does not own the native camera session, texture, or
/// recording lifecycle: those resources are tied to the widget's platform
/// view and must be torn down in lock-step with it. It owns the durable
/// capture choices that several controls read and update together.
class CameraCaptureControlsState {
  const CameraCaptureControlsState({
    this.isVideoMode = false,
    this.flashMode = 'auto',
    this.videoQuality = 'fhd',
    this.timerDelaySeconds = 0,
  });

  final bool isVideoMode;
  final String flashMode;
  final String videoQuality;
  final int timerDelaySeconds;

  CameraCaptureControlsState copyWith({
    bool? isVideoMode,
    String? flashMode,
    String? videoQuality,
    int? timerDelaySeconds,
  }) => CameraCaptureControlsState(
    isVideoMode: isVideoMode ?? this.isVideoMode,
    flashMode: flashMode ?? this.flashMode,
    videoQuality: videoQuality ?? this.videoQuality,
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

  /// Video capture always starts with flash off; photo capture returns to
  /// automatic flash, matching the former screen-local behavior.
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
