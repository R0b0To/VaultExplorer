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
import 'camera_capture_controls_controller.dart';
import 'camera_capture_session_controller.dart';
import 'camera_ui_components.dart';
import 'camera_media_review_view.dart';
import 'vault_camera_controller.dart';

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

  // Document scanning is optional. Screens that offer it override these; the
  // defaults keep every other screen (QuickCapture) exactly as it was.
  /// Whether the mode toggle includes "scan document".
  bool get supportsDocumentScan => false;
  /// True while in document-scan mode, where the shutter captures a page.
  bool get captureIsScanMode => false;
  Future<void> setDocumentScanMode(bool enable) async {}
  /// Captures, straightens and filters one page; [takePhoto] hands over to it
  /// in scan mode.
  Future<void> takeScanPage() async {}
  /// Live outline from the native document detector.
  void onDocumentQuadEvent(Map<String, dynamic> event) {}

  /// A part of a segmented video recording has been closed natively and is
  /// waiting to be picked up. Only the screen that records segmented video
  /// overrides this.
  void onVideoSegmentEvent() {}

  /// Whether a capture should open the review screen. With "keep shooting"
  /// on, the first capture stays on the camera and the tray collects
  /// everything until the user opens it.
  bool get captureOpensReviewOnFirstMedia => !captureControls.continuousCapture;

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

  // --- Pause and snapshots while recording ----------------------------------

  /// True while the recording in progress is paused.
  bool captureIsPaused = false;

  /// Photos can be taken while the recording in progress runs. Decided by the
  /// camera when the recording starts: not every device can set up a photo
  /// stream next to the video at the chosen size.
  bool captureSnapshotAvailable = false;

  /// Photos taken during the recording in progress. They wait in the tray like
  /// any other capture; the count is shown on the snapshot button.
  int recordingSnapshotCount = 0;

  bool _isTogglingPause = false;
  Duration _pausedBefore = Duration.zero;
  DateTime? _pausedSince;

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

  List<NativeCameraLens> get captureLensStops => captureSession.lensStops;

  bool get captureHasFlash => captureSession.hasFlash;

  double get captureIntrinsicZoom => captureSession.intrinsicZoomRatio;

  /// Facing of the camera that is open right now ('back' / 'front').
  String get captureActiveFacing {
    for (final l in [...captureLensStops, ...lenses]) {
      if (l.cameraId == selectedCameraId) return l.facing;
    }
    return 'back';
  }

  /// Lens stops of the active facing, ascending by field of view.
  List<NativeCameraLens> get captureFacingStops {
    final facing = captureActiveFacing;
    final stops = captureLensStops.where((l) => l.facing == facing).toList()
      ..sort((a, b) => a.relativeZoom.compareTo(b.relativeZoom));
    return stops;
  }

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

  // --- Recording clock, pause and snapshots -----------------------------------

  /// How long has been recorded: wall time since the start minus every pause.
  Duration get recordingElapsed {
    final start = recordingStart;
    if (start == null) return Duration.zero;
    final now = DateTime.now();
    final pausedNow = _pausedSince == null
        ? Duration.zero
        : now.difference(_pausedSince!);
    final elapsed = now.difference(start) - _pausedBefore - pausedNow;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// Starts the on-screen recording timer. Call once the recording has really
  /// started, after setting [recordingStart]. [snapshotAvailable] is what the
  /// camera reported for this recording.
  void startRecordingClock({required bool snapshotAvailable}) {
    _pausedBefore = Duration.zero;
    _pausedSince = null;
    captureIsPaused = false;
    captureSnapshotAvailable = snapshotAvailable;
    recordingSnapshotCount = 0;
    timer?.cancel();
    timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted || recordingStart == null) return;
      final elapsed = recordingElapsed.inSeconds;
      final text =
          '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}';
      // Frozen while paused: nothing to redraw.
      if (text != captureTimerText) {
        captureSessionController.updateTimerText(text);
      }
    });
  }

  /// Stops the recording timer and clears the pause/snapshot state. Returns
  /// how many milliseconds were recorded, pauses not counted (9999 when the
  /// start is unknown, so a recording is never thrown away as too short by
  /// mistake). Read [recordingStart] only after this.
  int stopRecordingClock() {
    timer?.cancel();
    final recordedMs = recordingStart == null
        ? 9999
        : recordingElapsed.inMilliseconds;
    _pausedBefore = Duration.zero;
    _pausedSince = null;
    captureIsPaused = false;
    captureSnapshotAvailable = false;
    return recordedMs;
  }

  /// True when nothing but photos taken during the recording that just ended
  /// is waiting in the tray, so the video is the first thing the user leaves
  /// the camera with (and the review opens for it, unless "keep shooting" is on).
  bool get trayHoldsOnlyRecordingSnapshots =>
      capturedMedia.length == recordingSnapshotCount;

  /// Pauses the recording in progress, or continues it when paused. The
  /// preview stays live and photos can still be taken meanwhile.
  Future<void> toggleRecordingPause() async {
    if (!captureIsRecording || isStartingVideo || _isTogglingPause) return;
    _isTogglingPause = true;
    final pausing = !captureIsPaused;
    HapticFeedback.mediumImpact();
    try {
      final result = pausing
          ? await cameraController.pauseVideoRecording()
          : await cameraController.resumeVideoRecording();
      // The recording may have been stopped while the call was in flight.
      if (!mounted || !captureIsRecording) return;
      if (!result.success) {
        showErrorToast(context.l10n.cameraPauseFailedMessage);
        return;
      }
      final now = DateTime.now();
      setState(() {
        if (pausing) {
          _pausedSince = now;
        } else {
          _pausedBefore += now.difference(_pausedSince ?? now);
          _pausedSince = null;
        }
        captureIsPaused = pausing;
      });
    } catch (_) {
      if (mounted && captureIsRecording) {
        showErrorToast(context.l10n.cameraPauseFailedMessage);
      }
    } finally {
      _isTogglingPause = false;
    }
  }

  /// Takes a photo without interrupting the recording. It goes to the tray
  /// like any capture; the review never opens until the recording is over.
  Future<void> takeRecordingSnapshot() async {
    if (!captureIsRecording ||
        !captureSnapshotAvailable ||
        isTakingPhoto ||
        isEncrypting) {
      return;
    }
    isTakingPhoto = true;
    HapticFeedback.mediumImpact();
    triggerShutterFlash();
    setState(() => pendingPhotoCount++);
    try {
      final orientationDegrees = await computePreviewRotationDegrees();
      // No aspect crop: the camera's photo stream already has the video's frame.
      final result = await cameraController.capturePhoto(
        orientationDegrees: orientationDegrees,
      );
      if (result.success && result.bytes != null && mounted) {
        HapticFeedback.lightImpact();
        setState(() {
          capturedMedia.add(
            CapturedMediaItem.photo(
              photoBytes: result.bytes!,
              thumbnailBytes: result.thumbnail ?? result.bytes!,
            ),
          );
          recordingSnapshotCount++;
        });
      } else if (mounted && captureIsRecording) {
        showErrorToast(
          result.error ?? context.l10n.cameraPhotoCaptureFailedMessage,
        );
      }
    } catch (_) {
      // A photo still in flight when the recording is stopped fails on its own.
      if (mounted && captureIsRecording) {
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

  /// One of the round buttons beside the shutter while recording.
  Widget buildRecordingSideButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool highlighted = false,
    int badgeCount = 0,
  }) {
    return buildRotatedWidget(
      iconTurns: captureIconTurns,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: highlighted ? Colors.amber : Colors.black45,
                    border: Border.all(
                      color: highlighted ? Colors.amber : Colors.white70,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: highlighted ? Colors.black : Colors.white,
                    size: 26,
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 18),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.amber,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- Shared behaviour ---------------------------------------------------------
  void handleCameraEvent(Map<String, dynamic> event) {
    if (event['event'] == 'document_quad') {
      onDocumentQuadEvent(event);
      return;
    }
    if (event['event'] == 'video_segment') {
      onVideoSegmentEvent();
      return;
    }
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

  /// Rotation of the preview in the app's current display orientation.
  /// Photos and videos use this so their orientation matches the visible frame,
  /// including when Android's auto-rotate setting leaves the UI locked.
  Future<int> computePreviewRotationDegrees() async {
    final rotation = await VaultCameraController.getDisplayRotation();
    if (mounted && rotation != captureDisplayRotation) {
      setState(() => captureDisplayRotation = rotation);
    }
    return (rotation % 4) * 90;
  }

  Future<void> refreshDisplayRotation() async {
    final rotation = await VaultCameraController.getDisplayRotation();
    if (!mounted || rotation == captureDisplayRotation) return;
    setState(() => captureDisplayRotation = rotation);
  }

  double get captureVideoAspectRatio {
    final fallbackResolution = switch (captureControls.videoQuality) {
      'uhd' => '3840x2160',
      'hd' => '1280x720',
      'sd' => '720x480',
      _ => '1920x1080',
    };
    final resolution = captureSession.currentVideoResolution ??
        captureSession.videoQualities[captureControls.videoQuality] ??
        fallbackResolution;
    final dimensions = resolution.toLowerCase().split('x');
    if (dimensions.length != 2) return 16 / 9;
    final width = int.tryParse(dimensions[0].trim());
    final height = int.tryParse(dimensions[1].trim());
    if (width == null || height == null || width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return math.max(width, height) / math.min(width, height);
  }

  /// Uses the recorder aspect in video mode and the chosen crop in photo mode.
  double cameraPreviewFrameAspectRatio({required bool isLandscape}) {
    final landscapeAspectRatio = captureControls.isVideoMode
        ? captureVideoAspectRatio
        : captureControls.aspectRatio;
    return isLandscape ? landscapeAspectRatio : 1 / landscapeAspectRatio;
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

    // Photo and video stay stacked; scan sits beside them, centred on the pair.
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            modeButton(
              selected: !captureControls.isVideoMode && !captureIsScanMode,
              icon: Icons.photo_camera_rounded,
              onTap: () async {
                if (captureIsScanMode) {
                  await setDocumentScanMode(false);
                } else {
                  await setVideoMode(false);
                }
              },
            ),
            const SizedBox(height: 10),
            modeButton(
              selected: captureControls.isVideoMode,
              icon: Icons.videocam_rounded,
              onTap: () async {
                if (captureIsScanMode) await setDocumentScanMode(false);
                await setVideoMode(true);
              },
            ),
          ],
        ),
        if (supportsDocumentScan) ...[
          const SizedBox(width: 10),
          modeButton(
            selected: captureIsScanMode,
            icon: Icons.document_scanner_rounded,
            onTap: () => setDocumentScanMode(true),
          ),
        ],
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
      orElse: () => lenses.firstWhere(
        (l) => l.facing == captureActiveFacing,
        orElse: () => lenses.first,
      ),
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

  /// Switches to one lens stop (0.5x / 1x / 3x). A stop of the camera that is
  /// already open is only a zoom change (the logical camera switches lens by
  /// itself); a standalone camera id reopens the session on that camera.
  Future<void> selectLensStop(NativeCameraLens stop) async {
    if (captureIsRecording ||
        isEncrypting ||
        captureIsCountingDown ||
        isStartingVideo) {
      return;
    }
    HapticFeedback.selectionClick();

    if (stop.cameraId == selectedCameraId) {
      final zoom = stop.zoomRatio.clamp(captureMinZoom, captureMaxZoom).toDouble();
      captureSessionController.setZoom(zoom);
      await applyZoomLogged(cameraController, zoom, logTag: captureLogTag);
      return;
    }

    captureSessionController.setUninitialized(cancelCountdown: false);
    await initCamera(cameraId: stop.cameraId);
    if (!mounted || !cameraController.isInitialized) return;
    if (stop.cameraId == selectedCameraId && (stop.zoomRatio - 1.0).abs() > 0.01) {
      final zoom = stop.zoomRatio.clamp(captureMinZoom, captureMaxZoom).toDouble();
      captureSessionController.setZoom(zoom);
      await applyZoomLogged(cameraController, zoom, logTag: captureLogTag);
    }
  }

  Future<void> takePhoto() async {
    if (captureIsScanMode) return takeScanPage();
    if (!cameraController.isInitialized || isEncrypting || isTakingPhoto) return;
    isTakingPhoto = true;

    triggerShutterFlash();

    setState(() {
      pendingPhotoCount++;
    });
    scrollToEndOfTray();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final frameAspectRatio = isLandscape
        ? captureControls.aspectRatio
        : 1 / captureControls.aspectRatio;

    try {
      final orientationDegrees = await computePreviewRotationDegrees();
      final isFirstMedia = capturedMedia.isEmpty;
      final result = await cameraController.capturePhoto(
        aspectRatio: frameAspectRatio,
        orientationDegrees: orientationDegrees,
      );

      if (result.success && result.bytes != null && mounted) {
        HapticFeedback.lightImpact();
        setState(() {
          capturedMedia.add(
            CapturedMediaItem.photo(
              photoBytes: result.bytes!,
              thumbnailBytes: result.thumbnail ?? result.bytes!,
            ),
          );
          if (isFirstMedia && captureOpensReviewOnFirstMedia) {
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
              if (captureFacingStops.length > 1)
                CameraLensSelector(
                  stops: captureFacingStops,
                  selectedCameraId: selectedCameraId,
                  displayZoom: captureCurrentZoom * captureIntrinsicZoom,
                  iconTurns: captureIconTurns,
                  onSelect: selectLensStop,
                )
              else
                CameraZoomIndicator(
                  currentZoom: captureCurrentZoom * captureIntrinsicZoom,
                  minZoom: captureMinZoom * captureIntrinsicZoom,
                  maxZoom: captureMaxZoom * captureIntrinsicZoom,
                  iconTurns: captureIconTurns,
                  onSetZoom: (shown) async {
                    final zoom = (shown / captureIntrinsicZoom)
                        .clamp(captureMinZoom, captureMaxZoom)
                        .toDouble();
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
                // While recording the lens cannot be switched (the recording is
                // tied to the camera it started on), so this slot holds the
                // pause button instead of the flip button.
                if (captureIsRecording)
                  SizedBox(
                    width: 48,
                    child: buildRecordingSideButton(
                      icon: captureIsPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      tooltip: captureIsPaused
                          ? context.l10n.cameraResumeRecordingTooltip
                          : context.l10n.cameraPauseRecordingTooltip,
                      highlighted: captureIsPaused,
                      onPressed: isStartingVideo ? null : toggleRecordingPause,
                    ),
                  )
                else
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
                if (captureIsRecording)
                  // Same width the mode toggle's slot had, so the shutter
                  // does not move when the recording starts.
                  SizedBox(
                    width: supportsDocumentScan ? 94 : 48,
                    child: captureSnapshotAvailable
                        ? Center(
                            child: buildRecordingSideButton(
                              icon: Icons.photo_camera_rounded,
                              tooltip: context.l10n.cameraSnapshotTooltip,
                              badgeCount: recordingSnapshotCount,
                              onPressed: isTakingPhoto || isEncrypting
                                  ? null
                                  : takeRecordingSnapshot,
                            ),
                          )
                        : null,
                  )
                else if (!captureIsCountingDown)
                  buildModeToggle()
                else
                  SizedBox(width: supportsDocumentScan ? 94 : 48),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
