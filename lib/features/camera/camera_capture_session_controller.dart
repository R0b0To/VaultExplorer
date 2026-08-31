import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/features/camera/vault_camera_controller.dart';

part 'camera_capture_session_controller.g.dart';

/// User-facing camera session status, recording state, zoom/exposure bounds,
/// and countdown tracking for one camera-capture screen instance.
///
/// Native camera hardware lifecycle, preview textures, and streaming listeners
/// stay widget-owned because they must be destroyed with the platform view.
class CameraCaptureSessionState {
  const CameraCaptureSessionState({
    this.isInitialized = false,
    this.selectedCameraId = '',
    this.lenses = const [],
    this.permissionError,
    this.isRecording = false,
    this.isEncrypting = false,
    this.isStartingVideo = false,
    this.busyLabel = '',
    this.timerText = '00:00',
    this.isCountingDown = false,
    this.countdownValue = 0,
    this.minZoom = 1.0,
    this.maxZoom = 1.0,
    this.currentZoom = 1.0,
    this.minExposureEv = 0.0,
    this.maxExposureEv = 0.0,
    this.currentExposureEv = 0.0,
    this.showExposureSlider = false,
  });

  final bool isInitialized;
  final String selectedCameraId;
  final List<NativeCameraLens> lenses;
  final String? permissionError;
  final bool isRecording;
  final bool isEncrypting;
  final bool isStartingVideo;
  final String busyLabel;
  final String timerText;
  final bool isCountingDown;
  final int countdownValue;
  final double minZoom;
  final double maxZoom;
  final double currentZoom;
  final double minExposureEv;
  final double maxExposureEv;
  final double currentExposureEv;
  final bool showExposureSlider;

  CameraCaptureSessionState copyWith({
    bool? isInitialized,
    String? selectedCameraId,
    List<NativeCameraLens>? lenses,
    String? permissionError,
    bool clearPermissionError = false,
    bool? isRecording,
    bool? isEncrypting,
    bool? isStartingVideo,
    String? busyLabel,
    String? timerText,
    bool? isCountingDown,
    int? countdownValue,
    double? minZoom,
    double? maxZoom,
    double? currentZoom,
    double? minExposureEv,
    double? maxExposureEv,
    double? currentExposureEv,
    bool? showExposureSlider,
  }) => CameraCaptureSessionState(
    isInitialized: isInitialized ?? this.isInitialized,
    selectedCameraId: selectedCameraId ?? this.selectedCameraId,
    lenses: lenses ?? this.lenses,
    permissionError:
        clearPermissionError ? null : permissionError ?? this.permissionError,
    isRecording: isRecording ?? this.isRecording,
    isEncrypting: isEncrypting ?? this.isEncrypting,
    isStartingVideo: isStartingVideo ?? this.isStartingVideo,
    busyLabel: busyLabel ?? this.busyLabel,
    timerText: timerText ?? this.timerText,
    isCountingDown: isCountingDown ?? this.isCountingDown,
    countdownValue: countdownValue ?? this.countdownValue,
    minZoom: minZoom ?? this.minZoom,
    maxZoom: maxZoom ?? this.maxZoom,
    currentZoom: currentZoom ?? this.currentZoom,
    minExposureEv: minExposureEv ?? this.minExposureEv,
    maxExposureEv: maxExposureEv ?? this.maxExposureEv,
    currentExposureEv: currentExposureEv ?? this.currentExposureEv,
    showExposureSlider: showExposureSlider ?? this.showExposureSlider,
  );
}

@riverpod
class CameraCaptureSession extends _$CameraCaptureSession {
  @override
  CameraCaptureSessionState build(String sessionKey) =>
      const CameraCaptureSessionState();

  void setUninitialized({bool cancelCountdown = true}) {
    state = state.copyWith(
      isInitialized: false,
      isCountingDown: cancelCountdown ? false : state.isCountingDown,
    );
  }

  void setPermissionError(String error) {
    state = state.copyWith(
      isInitialized: false,
      permissionError: error,
    );
  }

  void setCameraOpened(VaultCameraSessionInfo info) {
    state = state.copyWith(
      isInitialized: true,
      clearPermissionError: true,
      selectedCameraId: info.cameraId,
      lenses: info.lenses,
      minZoom: info.zoomMin,
      maxZoom: info.zoomMax,
      currentZoom: 1.0.clamp(info.zoomMin, info.zoomMax),
      minExposureEv: info.minExposureEv,
      maxExposureEv: info.maxExposureEv,
      currentExposureEv: 0.0,
    );
  }

  void setZoom(double zoom) {
    final clamped = zoom.clamp(state.minZoom, state.maxZoom);
    if (state.currentZoom == clamped) return;
    state = state.copyWith(currentZoom: clamped);
  }

  void setExposureEv(double ev) {
    final clamped = ev.clamp(state.minExposureEv, state.maxExposureEv);
    if (state.currentExposureEv == clamped) return;
    state = state.copyWith(currentExposureEv: clamped);
  }

  void setShowExposureSlider(bool show) {
    if (state.showExposureSlider == show) return;
    state = state.copyWith(showExposureSlider: show);
  }

  void startCountdown(int delaySeconds) {
    state = state.copyWith(
      isCountingDown: true,
      countdownValue: delaySeconds,
    );
  }

  void updateCountdown(int remaining) {
    state = state.copyWith(countdownValue: remaining);
  }

  void stopCountdown() {
    state = state.copyWith(isCountingDown: false);
  }

  void setStartingVideo(bool starting) {
    state = state.copyWith(isStartingVideo: starting);
  }

  void startRecording() {
    state = state.copyWith(
      isRecording: true,
      timerText: '00:00',
    );
  }

  void updateTimerText(String text) {
    state = state.copyWith(timerText: text);
  }

  void setEncrypting(bool encrypting, {String label = ''}) {
    state = state.copyWith(
      isEncrypting: encrypting,
      busyLabel: label,
      isRecording: encrypting ? false : state.isRecording,
    );
  }
}
