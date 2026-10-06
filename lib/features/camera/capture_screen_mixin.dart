// Shared by QuickCaptureScreen and CameraCaptureScreen.
//
// Everything here used to exist twice, line for line, in both screens' State
// classes. It moved only where the two copies were identical (checked
// mechanically at the time); the places they genuinely differ stay in the
// screens and reach this code through the hooks declared first below.
//
// Members are public because Dart privacy is per-library and the screens are
// separate files. Treat them as internal to lib/features/camera/.

import 'dart:async';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'camera_vault_service.dart';
import 'camera_capture_controls_controller.dart';
import 'camera_capture_session_controller.dart';
import 'camera_ui_components.dart';
import 'camera_media_review_view.dart';
import 'vault_camera_controller.dart';
import '../image_editor/image_editor_screen.dart';

mixin CaptureScreenStateMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  // --- Hooks: where the two screens differ -------------------------------
  /// Key for [cameraCaptureControlsProvider] (the two screens share one key today).
  String get captureControlsKey;
  /// Key for [cameraCaptureSessionProvider]; one session per capture destination.
  String get captureSessionKey;
  /// Tag passed to the native-call logging helpers.
  String get captureLogTag;
  /// Moves the screen into its review state (QuickCapture: `_Phase.reviewing`;
  /// CameraCapture: `_isReviewingMedia = true`).
  void enterReviewing();
  // Behaviour the screens implement differently and the shared code calls:
  Future<void> initCamera({String? cameraId});
  bool get captureIsCountingDown;
  Future<void> setVideoMode(bool videoMode);
  Future<void> startVideoRecording();
  Future<void> stopVideoRecording();

  // --- Shared state ---------------------------------------------------------
  late final VaultFileIoApi captureFileIoApi;

  late final VaultLifecycleApi captureLifecycleApi;

  late final VaultEngineEvents engineEvents;

  late final VaultCameraController cameraController;

  AppLifecycleState lastLifecycleState = AppLifecycleState.resumed;

  Future<void>? backgroundingFuture;

  bool isOpeningCamera = false;

  bool captureIsRecording = false;

  bool pendingStopAfterStart = false;

  bool captureShowShutterFlash = false;

  double baseZoom = 1.0;

  Timer? exposureHideTimer;

  Offset? captureFocusPoint;

  DateTime? recordingStart;

  Timer? timer;

  final List<CapturedMediaItem> capturedMedia = [];

  final ScrollController trayScrollController = ScrollController();

  int pendingPhotoCount = 0;

  bool isTakingPhoto = false;

  StreamSubscription<Map<String, dynamic>>? cameraEventSubscription;

  StreamSubscription<({double x, double y, double z})>? sensorSubscription;

  double captureDeviceTurns = 0.0;

  int captureDisplayRotation = 0;

  // --- Session / controls accessors ------------------------------------------
  double get captureIconTurns => cameraIconTurns(
    deviceTurns: captureDeviceTurns,
    displayRotation: captureDisplayRotation,
  );

  CameraCaptureControlsState get captureControls =>
      ref.read(cameraCaptureControlsProvider(captureControlsKey));

  CameraCaptureControls get captureControlsController =>
      ref.read(cameraCaptureControlsProvider(captureControlsKey).notifier);

  CameraCaptureSessionState get captureSession =>
      ref.read(cameraCaptureSessionProvider(captureSessionKey));

  CameraCaptureSession get captureSessionController =>
      ref.read(cameraCaptureSessionProvider(captureSessionKey).notifier);

  bool get isInitialized => captureSession.isInitialized;

  String get selectedCameraId => captureSession.selectedCameraId;

  List<NativeCameraLens> get lenses => captureSession.lenses;

  bool get isEncrypting => captureSession.isEncrypting;

  bool get isStartingVideo => captureSession.isStartingVideo;

  String? get permissionError => captureSession.permissionError;

  int get countdownValue => captureSession.countdownValue;

  String get busyLabel => captureSession.busyLabel;

  String get captureTimerText => captureSession.timerText;

  double get captureCurrentZoom => captureSession.currentZoom;

  double get captureMinZoom => captureSession.minZoom;

  double get captureMaxZoom => captureSession.maxZoom;

  double get captureCurrentExposureEv => captureSession.currentExposureEv;

  double get captureMinExposureEv => captureSession.minExposureEv;

  double get captureMaxExposureEv => captureSession.maxExposureEv;

  bool get captureShowExposureSlider => captureSession.showExposureSlider;

  // --- Shared behaviour ---------------------------------------------------------
  void handleCameraEvent(Map<String, dynamic> event) {
    if (event['event'] != 'error' || !mounted) return;
    captureSessionController.setPermissionError(
      context.l10n.cameraDisconnectedError(
        event['message'] ?? context.l10n.unknownErrorFallback,
      ),
    );
  }

  void startSensorListener() {
    sensorSubscription = VaultCameraController.accelerometerEventStream()
        .listen((event) {
          double magnitude = math.sqrt(event.x * event.x + event.y * event.y);
          if (magnitude < 2.0) return;

          double angle = math.atan2(event.x, event.y);
          double turns = angle / (2 * math.pi);
          double snappedTurns = (turns * 4).round() / 4.0;
          if (snappedTurns == -0.5) snappedTurns = 0.5;

          if (captureDeviceTurns != snappedTurns && mounted) {
            setState(() => captureDeviceTurns = snappedTurns);
            unawaited(applyOrientationSilent(cameraController, computeDeviceRotationDegrees()));
          }
        });
  }

  int computeDeviceRotationDegrees() {
    return ((captureDeviceTurns * 360).round() % 360 + 360) % 360;
  }

  Future<void> refreshDisplayRotation() async {
    final rotation = await VaultCameraController.getDisplayRotation();
    if (!mounted || rotation == captureDisplayRotation) return;
    setState(() => captureDisplayRotation = rotation);
  }

  void scrollToEndOfTray() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (trayScrollController.hasClients) {
        trayScrollController.animateTo(
          trayScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> changeQuality(String quality) async {
    if (captureIsRecording ||
        isEncrypting ||
        captureIsCountingDown ||
        isStartingVideo ||
        captureControls.videoQuality == quality) {
      return;
    }
    captureControlsController.selectVideoQuality(quality);
    captureSessionController.setUninitialized(cancelCountdown: false);
    await initCamera(cameraId: selectedCameraId);
  }

  Future<void> changePhotoResolution(String resolution) async {
    if (captureIsRecording ||
        isEncrypting ||
        captureIsCountingDown ||
        isStartingVideo ||
        captureControls.photoResolution == resolution) {
      return;
    }
    captureControlsController.selectPhotoResolution(resolution);
    captureSessionController.setUninitialized(cancelCountdown: false);
    await initCamera(cameraId: selectedCameraId);
  }

  void onCaptureClicked() {
    if (isEncrypting) return;
    HapticFeedback.mediumImpact();

    if (captureIsCountingDown) {
      captureSessionController.stopCountdown();
      return;
    }

    if (captureControls.isVideoMode) {
      if (captureIsRecording) {
        stopVideoRecording();
      } else if (isStartingVideo) {
        pendingStopAfterStart = true;
      } else {
        startVideoRecording();
      }
    } else {
      captureControls.timerDelaySeconds > 0
          ? startPhotoCountdownAndCapture()
          : takePhoto();
    }
  }

  Future<void> startPhotoCountdownAndCapture() async {
    final delay = captureControls.timerDelaySeconds;
    captureSessionController.startCountdown(delay);

    for (int i = delay; i > 0; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !captureIsCountingDown) return;
      HapticFeedback.lightImpact();
      captureSessionController.updateCountdown(i - 1);
    }

    captureSessionController.stopCountdown();
    await takePhoto();
  }

  void triggerShutterFlash() {
    setState(() => captureShowShutterFlash = true);
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) setState(() => captureShowShutterFlash = false);
    });
  }

  void showErrorToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  Widget buildModeToggle() {
    Widget modeButton({
      required bool selected,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: buildRotatedWidget(
          iconTurns: captureIconTurns,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? Colors.amber : Colors.black45,
            ),
            child: Icon(
              icon,
              color: selected ? Colors.black : Colors.white,
              size: 20,
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        modeButton(
          selected: !captureControls.isVideoMode,
          icon: Icons.photo_camera_rounded,
          onTap: () => setVideoMode(false),
        ),
        const SizedBox(height: 10),
        modeButton(
          selected: captureControls.isVideoMode,
          icon: Icons.videocam_rounded,
          onTap: () => setVideoMode(true),
        ),
      ],
    );
  }

  Future<void> flipCamera() async {
    if (captureIsRecording ||
        isEncrypting ||
        captureIsCountingDown ||
        isStartingVideo ||
        lenses.length <= 1) {
      return;
    }

    HapticFeedback.lightImpact();

    final currentLens = lenses.firstWhere(
      (l) => l.cameraId == selectedCameraId,
      orElse: () => lenses.first,
    );

    final targetFacing = currentLens.facing == 'back' ? 'front' : 'back';
    final targetLens = lenses.firstWhere(
      (l) => l.facing == targetFacing,
      orElse: () => lenses.firstWhere(
        (l) => l.cameraId != selectedCameraId,
        orElse: () => currentLens,
      ),
    );

    if (targetLens.cameraId != selectedCameraId) {
      captureControlsController.setPreferredFacing(targetFacing);
      captureSessionController.setUninitialized(cancelCountdown: false);
      await initCamera(cameraId: targetLens.cameraId);
    }
  }

  Future<void> takePhoto() async {
    if (!cameraController.isInitialized || isEncrypting || isTakingPhoto) return;
    isTakingPhoto = true;

    triggerShutterFlash();

    setState(() {
      pendingPhotoCount++;
    });
    scrollToEndOfTray();

    try {
      await cameraController.setOrientationDegrees(
        computeDeviceRotationDegrees(),
      );

      final isFirstMedia = capturedMedia.isEmpty;
      final result = await cameraController.capturePhoto();

      if (result.success && result.bytes != null && mounted) {
        HapticFeedback.lightImpact();
        setState(() {
          capturedMedia.add(
            CapturedMediaItem.photo(
              photoBytes: result.bytes!,
              thumbnailBytes: result.thumbnail ?? result.bytes!,
            ),
          );
          if (isFirstMedia) {
            enterReviewing();
          }
        });
        scrollToEndOfTray();
      } else {
        if (mounted) {
          showErrorToast(
            result.error ?? context.l10n.cameraPhotoCaptureFailedMessage,
          );
        }
      }
    } catch (_) {
      if (mounted) {
        showErrorToast(context.l10n.cameraPhotoCaptureFailedMessage);
      }
    } finally {
      isTakingPhoto = false;
      if (mounted) {
        setState(() {
          pendingPhotoCount = math.max(0, pendingPhotoCount - 1);
        });
      }
    }
  }

  Widget buildCapturedMediaTray() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final totalCount = capturedMedia.length + pendingPhotoCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isLandscape ? 160 : 180),
            child: SingleChildScrollView(
              controller: trayScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < capturedMedia.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2, right: 8, left: 4),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setState(enterReviewing);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 44,
                                height: 44,
                              
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    capturedMedia[i].thumbnailBytes.isNotEmpty
                                        ? Image.memory(
                                            capturedMedia[i].thumbnailBytes,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(color: Colors.grey.shade900),
                                    if (capturedMedia[i].isVideo)
                                      Center(
                                        child: Container(
                                          padding: const EdgeInsets.all(3),
                                          decoration: const BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 14),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: -10,
                            right: -10,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                final removed = capturedMedia.removeAt(i);
                                if (removed.isVideo && removed.videoPath != null) {
                                  cameraController.discardVideo(removed.videoPath!);
                                }
                                setState(() {});
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.9),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.2),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.close_rounded, color: Colors.white, size: 13),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (int p = 0; p < pendingPhotoCount; p++)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2, right: 8, left: 4),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.withValues(alpha: 0.8), width: 1.5),
                        ),
                        child: const Center(
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: capturedMedia.isNotEmpty
                ? () {
                    setState(enterReviewing);
                  }
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$totalCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget buildBottomControls() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.black54, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        bottom: isLandscape ? 12 : 32,
        top: isLandscape ? 8 : 16,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isLandscape && (capturedMedia.isNotEmpty || pendingPhotoCount > 0) && !captureIsRecording && !captureIsCountingDown)
              buildCapturedMediaTray(),

            if (!captureIsRecording && !captureIsCountingDown) ...[
              CameraZoomIndicator(
                currentZoom: captureCurrentZoom,
                minZoom: captureMinZoom,
                maxZoom: captureMaxZoom,
                iconTurns: captureIconTurns,
                onSetZoom: (zoom) async {
                  captureSessionController.setZoom(zoom);
                  await applyZoomLogged(cameraController, zoom, logTag: captureLogTag);
                },
              ),
              SizedBox(height: isLandscape ? 6 : 16),
            ],
            SizedBox(height: isLandscape ? 8 : 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                buildRotatedWidget(
                  iconTurns: captureIconTurns,
                  child: IconButton(
                    icon: const Icon(
                      Icons.flip_camera_ios_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: flipCamera,
                  ),
                ),
                GestureDetector(
                  onTap: onCaptureClicked,
                  child: Container(
                    width: 76,
                    height: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      width: captureControls.isVideoMode && captureIsRecording ? 30 : 60,
                      height: captureControls.isVideoMode && captureIsRecording ? 30 : 60,
                      decoration: BoxDecoration(
                        color: captureControls.isVideoMode ? Colors.red : Colors.white,
                        borderRadius: BorderRadius.circular(
                          captureControls.isVideoMode && captureIsRecording ? 8 : 30,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!captureIsRecording && !captureIsCountingDown)
                  buildModeToggle()
                else
                  const SizedBox(width: 48),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
