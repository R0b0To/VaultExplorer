import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vaultexplorer/core/api/quick_capture_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart' show logSwallowed;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';
import 'package:vaultexplorer/features/share_import/share_destination_sheet.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'camera_vault_service.dart';
import 'camera_capture_controls_controller.dart';
import 'camera_capture_session_controller.dart';
import 'camera_ui_components.dart';
import 'capture_screen_mixin.dart';
import 'camera_media_review_view.dart';
import 'vault_camera_controller.dart';

const _quickCaptureControlsKey = 'camera_capture';
const _quickCaptureSessionKey = 'quick_capture';

class QuickCaptureScreen extends ConsumerStatefulWidget {
  const QuickCaptureScreen({super.key});

  @override
  ConsumerState<QuickCaptureScreen> createState() =>
      _QuickCaptureScreenState();
}

enum _Phase { camera, reviewing, saving }

class _QuickCaptureScreenState extends ConsumerState<QuickCaptureScreen>
    with WidgetsBindingObserver, CaptureScreenStateMixin<QuickCaptureScreen> {
  @override
  String get captureControlsKey => _quickCaptureControlsKey;

  @override
  String get captureSessionKey => _quickCaptureSessionKey;

  @override
  String get captureLogTag => 'QuickCaptureScreen';

  @override
  void enterReviewing() {
    _phase = _Phase.reviewing;
  }

  late final QuickCaptureApi _quickCaptureApi;
  late final SessionLockController _sessionLockController;
  late final VaultDashboardController _dashboardController;
  bool _autoLockPausedForRecording = false;

  _Phase _phase = _Phase.camera;

  ScratchpadSession? _pendingScratchpad;

  String? _saveError;

  // --- Segmented video recording ---------------------------------------------
  // Quick capture normally lets the person pick the vault after shooting. A
  // segmented recording saves each part as soon as it closes, so it needs the
  // vault up front: it is asked for (and unlocked if needed) when recording
  // starts, every part goes straight into it, and there is no review.

  /// True while the recording in progress is segmented.
  bool _segmentedRecording = false;

  /// Where the parts of the segmented recording are saved.
  CryptoDestination? _segmentDestination;
  CameraVaultService? _segmentVaultService;

  /// Timestamp shared by the names of every part of this recording.
  DateTime? _segmentGroupStart;

  /// Number of parts saved into the vault so far.
  int _segmentIndex = 0;

  /// Name of the first saved part, shown in the "saved" toast.
  String? _firstSegmentName;

  /// Shows the "vault full" message once per recording, not once per part.
  bool _segmentSpaceWarned = false;

  /// Runs part collection one at a time, so event nudges and the final stop
  /// never overlap and parts are always numbered in order.
  Future<void> _segmentChain = Future<void>.value();

  @override
  bool get captureIsCountingDown => captureSession.countdownValue > 0 && captureSession.isCountingDown;

  @override
  void initState() {
    super.initState();
    captureFileIoApi = ref.read(vaultFileIoApiProvider);
    captureLifecycleApi = ref.read(vaultLifecycleApiProvider);
    engineEvents = ref.read(vaultEngineEventsProvider);
    _quickCaptureApi = ref.read(quickCaptureApiProvider);
    _sessionLockController = ref.read(sessionLockControllerProvider);
    _dashboardController = ref.read(vaultDashboardControllerProvider.notifier);
    cameraController = VaultCameraController(engineEvents);

    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    WidgetsBinding.instance.addObserver(this);
    cameraEventSubscription = cameraController.events.listen(
      handleCameraEvent,
    );
    initCamera();
    startSensorListener();
    unawaited(refreshDisplayRotation());
  }

  @override
  void didChangeMetrics() {
    unawaited(refreshDisplayRotation());
  }

  bool get _isOwnRouteCurrent => ModalRoute.of(context)?.isCurrent ?? false;

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!_isOwnRouteCurrent) return false;
    if (_phase == _Phase.reviewing && capturedMedia.isNotEmpty) {
      return true;
    }
    if (captureIsRecording ||
        isEncrypting ||
        captureIsCountingDown ||
        _phase == _Phase.saving ||
        pendingPhotoCount > 0) {
      return true;
    }
    if (capturedMedia.isNotEmpty) {
      return true;
    }
    return false;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {}

  @override
  void handleCancelBackGesture() {}

  @override
  void handleCommitBackGesture() {
    if (!_isOwnRouteCurrent) return;
    if (_phase == _Phase.reviewing && capturedMedia.isNotEmpty) {
      setState(() => _phase = _Phase.camera);
    } else if (capturedMedia.isNotEmpty) {
      HapticFeedback.lightImpact();
      _backWithCapturedMedia();
    }
  }

  /// Back from the camera while captures wait in the tray: discards them, or,
  /// with "keep shooting" on (the user may never have seen the review
  /// screen), opens the review so the discard stays an explicit choice.
  void _backWithCapturedMedia() {
    if (captureControls.continuousCapture) {
      setState(() => _phase = _Phase.reviewing);
    } else {
      _discardAllMedia();
    }
  }

  @override
  void dispose() {
    _resumeAutoLockAfterRecording();
    WidgetsBinding.instance.removeObserver(this);
    trayScrollController.dispose();
    timer?.cancel();
    exposureHideTimer?.cancel();
    sensorSubscription?.cancel();
    cameraEventSubscription?.cancel();
    unawaited(cameraController.dispose());

    if (captureIsRecording) {
      unawaited(captureFileIoApi.setKeepScreenOn(false));
    }

    final pending = _pendingScratchpad;
    if (pending != null) {
      unawaited(_quickCaptureApi.discardSession(pending.sessionToken));
    }

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

 @override

  void didChangeAppLifecycleState(AppLifecycleState state) {
    lastLifecycleState = state;
    if (_phase != _Phase.camera) return;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      backgroundingFuture = _handleGoingBackground();
    } else if (state == AppLifecycleState.resumed && backgroundingFuture != null) {
      unawaited(_handleResumed());
    }
  }

  void _pauseAutoLockForRecording() {
    if (_autoLockPausedForRecording) return;
    _autoLockPausedForRecording = true;
    _sessionLockController.pauseVaultAutoLock();
    _dashboardController.pauseAutoCloseTimersForActivity();
  }

  void _resumeAutoLockAfterRecording() {
    if (!_autoLockPausedForRecording) return;
    _autoLockPausedForRecording = false;
    _dashboardController.resumeAutoCloseTimersAfterActivity();
    _sessionLockController.resumeVaultAutoLock();
  }

  Future<void> _handleGoingBackground() async {
    if (captureIsRecording) {
      await stopVideoRecording();
    }
    await cameraController.close();
    if (mounted && _phase == _Phase.camera) {
      captureSessionController.setUninitialized();
    }
  }

  Future<void> _handleResumed() async {
    final bgFuture = backgroundingFuture;
    backgroundingFuture = null;
    unawaited(refreshDisplayRotation());
    if (bgFuture != null) {
      await bgFuture;
    }
    if (!mounted || _phase != _Phase.camera) return;
    if (!cameraController.isInitialized) {
      await initCamera(
        cameraId: selectedCameraId.isNotEmpty ? selectedCameraId : null,
      );
    }
  }

  @override
  Future<void> initCamera({String? cameraId}) async {
    if (isOpeningCamera) return;
    isOpeningCamera = true;
    try {
      await captureControlsController.loadPersisted();

      final hasPerms = await VaultCameraController.hasPermissions();
      if (!hasPerms) {
        final granted = await cameraController.requestPermissions();
        if (!granted) {
          if (mounted) {
            captureSessionController.setPermissionError(
              context.l10n.cameraPermissionsRequiredMessage,
            );
          }
          return;
        }
      }

      final info = await cameraController.open(
        cameraId: cameraId,
        facing: captureControls.preferredFacing,
        quality: captureControls.videoQuality,
        photoResolution: captureControls.photoResolution,
      );

      if (!mounted) return;

      if (_phase != _Phase.camera ||
          lastLifecycleState == AppLifecycleState.paused ||
          lastLifecycleState == AppLifecycleState.hidden) {
        await cameraController.close();
        return;
      }

      captureSessionController.setCameraOpened(info);
      await cameraController.setFlash(captureControls.flashMode);
      await cameraController.setZoom(captureCurrentZoom);
    } catch (e) {
      if (mounted) {
        captureSessionController.setPermissionError(
          context.l10n.cameraErrorMessage('$e'),
        );
      }
    } finally {
      isOpeningCamera = false;
    }
  }

  void _onTapToFocus(TapDownDetails details, BoxConstraints constraints) async {
    if (!cameraController.isInitialized) return;

    final natural = cameraDisplayPointToNatural(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
      captureDisplayRotation,
    );
    final nx = natural.x;
    final ny = natural.y;

    setState(() => captureFocusPoint = details.localPosition);
    captureSessionController.setShowExposureSlider(true);

    await applyFocusAndExposurePoint(cameraController, nx, ny, logTag: 'QuickCaptureScreen');

    exposureHideTimer?.cancel();
    exposureHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        captureSessionController.setShowExposureSlider(false);
        setState(() => captureFocusPoint = null);
        unawaited(cameraController.resetFocusAndExposure());
      }
    });
  }

  @override
  Future<void> setVideoMode(bool videoMode) async {
    if (captureIsRecording ||
        isEncrypting ||
        captureIsCountingDown ||
        isStartingVideo ||
        captureControls.isVideoMode == videoMode) {
      return;
    }
    captureControlsController.setVideoMode(videoMode);
    await applyFlash(cameraController, captureControls.flashMode, logTag: 'QuickCaptureScreen');
  }

  /// Quick Capture opens without the app lock gate. If this launch skipped
  /// it, the person has to pass it before choosing a destination or writing
  /// anything; once passed it isn't asked again for this capture session.
  Future<bool> _ensureAppUnlockedForSave() async {
    final launch = ref.read(pendingQuickCaptureLaunchProvider);
    if (!launch.appUnlockRequired) return true;
    final unlocked = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const LockGateScreen(popOnSuccess: true),
      ),
    );
    if (unlocked != true) return false;
    launch.markAppUnlocked();
    return true;
  }

  Future<void> _commitAllMediaToVault(List<CapturedMediaItem> mediaToSave) async {
    if (mediaToSave.isEmpty) return;

    if (!await _ensureAppUnlockedForSave() || !mounted) return;

    final destination = await Navigator.push<CryptoDestination>(
      context,
      MaterialPageRoute(builder: (_) => const ShareDestinationSheet()),
    );
    if (destination == null || !mounted) return;
    if (!destination.isVault ||
        destination.container == null ||
        destination.relativePath == null) {
      return;
    }

    setState(() => _phase = _Phase.saving);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    final container = destination.container!;
    final vaultService = CameraVaultService(
      container: container,
      targetDirPath: destination.relativePath!,
      fileIoApi: captureFileIoApi,
      lifecycleApi: captureLifecycleApi,
    );

    final successfullySaved = <CapturedMediaItem>[];
    try {
      String? firstName;
      bool hasVideo = false;

      for (final item in List<CapturedMediaItem>.from(mediaToSave)) {
        if (item.isPhoto && item.fullPhotoBytes != null) {
          final bytes = item.fullPhotoBytes!;
          if (!await vaultService.hasEnoughSpaceFor(bytes.length)) {
            if (mounted) {
              _returnToReviewWithError(
                context.l10n.cameraNotEnoughVaultSpaceMessage,
                mediaToSave,
                successfullySaved,
              );
            }
            return;
          }
          final name = await vaultService.nextAvailableName(isPhoto: true);
          final virtualPath = vaultService.buildVirtualPath(name);
          final ok = await cameraController.savePhotoToVault(
            bytes: bytes,
            volId: container.volId,
            virtualPath: virtualPath,
          );
          if (!ok || !await vaultService.finalizeVaultWrite(virtualPath)) {
            await vaultService.deleteFile(virtualPath);
            if (mounted) {
              _returnToReviewWithError(
                context.l10n.cameraCouldNotSaveCaptureMessage,
                mediaToSave,
                successfullySaved,
              );
            }
            return;
          }
          firstName ??= name;
          successfullySaved.add(item);
        } else if (item.isVideo && item.videoPath != null) {
          var finalVideoPath = item.videoPath!;
          if (item.trimStartMs > 0 || (item.trimEndMs > 0 && item.trimEndMs < item.videoDurationMs)) {
            final trimmed = await cameraController.trimVideo(
              videoPath: item.videoPath!,
              startMs: item.trimStartMs,
              endMs: item.trimEndMs,
            );
            if (trimmed != null) {
              finalVideoPath = trimmed;
              item.videoPath = trimmed;
              item.trimStartMs = 0;
              item.trimEndMs = item.videoDurationMs;
            }
          }
          final videoBytes = await vaultService.localFileSize(finalVideoPath);
          if (videoBytes != null &&
              !await vaultService.hasEnoughSpaceFor(videoBytes)) {
            if (mounted) {
              _returnToReviewWithError(
                context.l10n.cameraNotEnoughVaultSpaceMessage,
                mediaToSave,
                successfullySaved,
              );
            }
            return;
          }
          final name = await vaultService.nextAvailableName(isPhoto: false);
          final virtualPath = vaultService.buildVirtualPath(name);
          final ok = await cameraController.saveVideoToVault(
            videoPath: finalVideoPath,
            volId: container.volId,
            virtualPath: virtualPath,
          );
          if (!ok || !await vaultService.finalizeVaultWrite(virtualPath)) {
            await vaultService.deleteFile(virtualPath);
            if (mounted) {
              _returnToReviewWithError(
                context.l10n.cameraCouldNotSaveCaptureMessage,
                mediaToSave,
                successfullySaved,
              );
            }
            return;
          }
          await cameraController.discardVideo(finalVideoPath);
          firstName ??= name;
          hasVideo = true;
          successfullySaved.add(item);
        }
      }

      await _relockAndFinish(
        destination: destination,
        savedName: firstName ?? 'media',
        isVideo: hasVideo,
      );
    } catch (_) {
      if (mounted) {
        _returnToReviewWithError(
          context.l10n.cameraCouldNotSaveCaptureMessage,
          mediaToSave,
          successfullySaved,
        );
      }
    }
  }

  void _returnToReviewWithError(
    String message,
    List<CapturedMediaItem> mediaToSave,
    List<CapturedMediaItem> successfullySaved,
  ) {
    for (final item in successfullySaved) {
      mediaToSave.remove(item);
      capturedMedia.remove(item);
    }
    if (!mounted) return;
    showErrorToast(message);
    setState(() => _phase = _Phase.reviewing);
  }

  @override
  /// Applies the "after saving" lock policy to the vault the capture was
  /// saved into, tells the person, and closes the screen.
  Future<void> _relockAndFinish({
    required CryptoDestination destination,
    required String savedName,
    required bool isVideo,
  }) async {
    final container = destination.container!;
    final settings = await ref.read(appSettingsServiceProvider).loadSettings();
    final shouldRelock = switch (settings.quickActionLockMode) {
      QuickActionLockMode.alwaysLock => true,
      QuickActionLockMode.leaveAsFound => destination.wasInitiallyLocked,
      QuickActionLockMode.leaveOpen => false,
    };

    if (shouldRelock) {
      await captureLifecycleApi.lockContainer(container.uri);
    }

    if (mounted) {
      await _quickCaptureApi.showToast(
        context.l10n.quickCaptureSavedToast(savedName, destination.displayName),
      );
      Navigator.pop(context, (savedName: savedName, isVideo: isVideo));
    }
  }

  /// Asks for the vault a segmented recording saves into, unlocking the app
  /// and the vault if needed. Null when the person backs out.
  Future<CryptoDestination?> _pickSegmentDestination() async {
    if (!await _ensureAppUnlockedForSave() || !mounted) return null;
    final destination = await Navigator.push<CryptoDestination>(
      context,
      MaterialPageRoute(builder: (_) => const ShareDestinationSheet()),
    );
    if (destination == null || !mounted) return null;
    if (!destination.isVault ||
        destination.container == null ||
        destination.relativePath == null) {
      return null;
    }
    return destination;
  }

  Future<void> startVideoRecording() async {
    if (!cameraController.isInitialized ||
        isEncrypting ||
        captureIsRecording ||
        isStartingVideo) {
      return;
    }

    if (captureControls.segmentMinutes > 0) {
      await _startSegmentedRecording();
      return;
    }

    captureSessionController.setStartingVideo(true);
    try {
      final session = await _quickCaptureApi.openSession();
      if (session == null) {
        showErrorToast(context.l10n.cameraRecordingFailedMessage);
        return;
      }
      _pendingScratchpad = session;

      await cameraController.setOrientationDegrees(
        await computePreviewRotationDegrees(),
      );

      final result = await cameraController.startVideoRecordingToScratchpad(
        sessionToken: session.sessionToken,
        scratchpadPath: session.scratchpadPath,
      );

      if (!result.success) {
        await _quickCaptureApi.discardSession(session.sessionToken);
        _pendingScratchpad = null;
        showErrorToast(
          result.error ?? context.l10n.cameraRecordingFailedMessage,
        );
        return;
      }

      recordingStart = DateTime.now();
      captureIsRecording = true;
      if (!mounted) return;
      _pauseAutoLockForRecording();
      captureSessionController.startRecording();
      unawaited(captureFileIoApi.setKeepScreenOn(true));

      timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted || recordingStart == null) return;
        final elapsed = DateTime.now().difference(recordingStart!).inSeconds;
        captureSessionController.updateTimerText(
          '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}',
        );
      });
    } catch (e) {
      showErrorToast(
        context.l10n.cameraRecordingFailedWithReasonMessage('$e'),
      );
    } finally {
      captureSessionController.setStartingVideo(false);
      if (pendingStopAfterStart) {
        pendingStopAfterStart = false;
        if (captureIsRecording) stopVideoRecording();
      }
    }
  }

  @override
  Future<void> stopVideoRecording() async {
    if (!cameraController.isInitialized || !captureIsRecording) return;

    timer?.cancel();
    final startedAt = recordingStart;
    recordingStart = null;
    captureIsRecording = false;
    _resumeAutoLockAfterRecording();

    try {
      final isFirstMedia = capturedMedia.isEmpty;
      final result = await cameraController.stopVideoRecordingForReview();

      if (_segmentedRecording) {
        await _finishSegmentedRecording(
          success: result.success,
          videoPath: result.videoPath,
          durationMs: result.durationMs,
        );
        return;
      }

      final elapsedMs = startedAt == null
          ? 9999
          : DateTime.now().difference(startedAt).inMilliseconds;

      final session = _pendingScratchpad;
      if (elapsedMs < 500 || !result.success || result.videoPath == null) {
        if (session != null) {
          await _quickCaptureApi.discardSession(session.sessionToken);
        }
        if (result.videoPath != null) {
          await cameraController.discardVideo(result.videoPath!);
        }
        _pendingScratchpad = null;
        if (mounted) {
          showErrorToast(context.l10n.cameraRecordingTooShortMessage);
        }
        return;
      }

      setState(() {
        capturedMedia.add(
          CapturedMediaItem.video(
            videoPath: result.videoPath!,
            videoDurationMs: result.durationMs,
            thumbnailBytes: result.thumbnail ?? Uint8List(0),
          ),
        );
        if (isFirstMedia && captureOpensReviewOnFirstMedia) {
          _phase = _Phase.reviewing;
        }
      });
    } catch (e) {
      final session = _pendingScratchpad;
      if (session != null) {
        await _quickCaptureApi.discardSession(session.sessionToken);
      }
      _pendingScratchpad = null;
      if (mounted) {
        showErrorToast(
          context.l10n.cameraCouldNotSaveRecordingWithReasonMessage('$e'),
        );
      }
    } finally {
      _segmentedRecording = false;
      unawaited(captureFileIoApi.setKeepScreenOn(false));
    }
  }

  // --- Segmented recording: destination, collecting and saving parts ----------

  Future<void> _startSegmentedRecording() async {
    final segmentSeconds = captureControls.segmentMinutes * 60;
    captureSessionController.setStartingVideo(true);
    try {
      final destination = await _pickSegmentDestination();
      // Unlocking the vault can take the app to the background, which closes
      // the camera; a new tap on record starts over once it has reopened.
      if (destination == null || !mounted || !cameraController.isInitialized) {
        return;
      }
      final container = destination.container!;
      final vaultService = CameraVaultService(
        container: container,
        targetDirPath: destination.relativePath!,
        fileIoApi: captureFileIoApi,
        lifecycleApi: captureLifecycleApi,
      );
      final groupStart = await vaultService.segmentGroupStart(
        prefix: 'VID_',
        ext: '.mp4',
        at: DateTime.now(),
      );
      if (!mounted) return;

      await cameraController.setOrientationDegrees(
        await computePreviewRotationDegrees(),
      );
      final result = await cameraController.startVideoRecording(
        volId: container.volId,
        virtualPath: vaultService.buildVirtualPath(
          vaultService.segmentName(
            prefix: 'VID_',
            ext: '.mp4',
            groupStart: groupStart,
            index: 1,
          ),
        ),
        segmentSeconds: segmentSeconds,
      );
      if (!result.success) {
        showErrorToast(
          result.error ?? context.l10n.cameraRecordingFailedMessage,
        );
        return;
      }

      _segmentedRecording = true;
      _segmentDestination = destination;
      _segmentVaultService = vaultService;
      _segmentGroupStart = groupStart;
      _segmentIndex = 0;
      _firstSegmentName = null;
      _segmentSpaceWarned = false;
      _segmentChain = Future<void>.value();

      recordingStart = DateTime.now();
      captureIsRecording = true;
      if (!mounted) return;
      _pauseAutoLockForRecording();
      captureSessionController.startRecording();
      unawaited(captureFileIoApi.setKeepScreenOn(true));

      timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted || recordingStart == null) return;
        final elapsed = DateTime.now().difference(recordingStart!).inSeconds;
        captureSessionController.updateTimerText(
          '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}',
        );
      });
    } catch (e) {
      _segmentedRecording = false;
      if (mounted) {
        showErrorToast(
          context.l10n.cameraRecordingFailedWithReasonMessage('$e'),
        );
      }
    } finally {
      captureSessionController.setStartingVideo(false);
      if (pendingStopAfterStart) {
        pendingStopAfterStart = false;
        if (captureIsRecording) unawaited(stopVideoRecording());
      }
    }
  }

  @override
  void onVideoSegmentEvent() {
    if (!_segmentedRecording) return;
    unawaited(_collectVideoSegments());
  }

  /// Picks up every part the recorder has closed and saves each into the
  /// chosen vault. Safe to call at any time; calls queue up and run in turn.
  Future<void> _collectVideoSegments() {
    final next = _segmentChain.then((_) async {
      final parts = await cameraController.takeVideoSegments();
      for (final part in parts) {
        await _saveVideoSegment(path: part.path, durationMs: part.durationMs);
      }
    }).catchError((Object e) {
      logSwallowed('quickCollectVideoSegments', e);
    });
    _segmentChain = next;
    return next;
  }

  /// Saves one finished part into the vault under the next part name and
  /// wipes its temp file. Returns false when it could not be saved; the part
  /// then waits in the tray (nothing is lost) and the recording stops, since
  /// every further part would most likely fail the same way. The review
  /// screen lets the person free up space and save it, or discard it.
  Future<bool> _saveVideoSegment({
    required String path,
    required int durationMs,
  }) async {
    final service = _segmentVaultService;
    final container = _segmentDestination?.container;
    if (service == null || container == null || !mounted) {
      unawaited(cameraController.discardVideo(path));
      return false;
    }

    final bytes = await service.localFileSize(path);
    final enoughSpace =
        bytes == null || await service.hasEnoughSpaceFor(bytes);
    var saved = false;
    String? name;
    if (enoughSpace) {
      final index = _segmentIndex + 1;
      name = service.segmentName(
        prefix: 'VID_',
        ext: '.mp4',
        groupStart: _segmentGroupStart ?? DateTime.now(),
        index: index,
      );
      final virtualPath = service.buildVirtualPath(name);
      saved = await cameraController.saveVideoToVault(
            videoPath: path,
            volId: container.volId,
            virtualPath: virtualPath,
          ) &&
          await service.finalizeVaultWrite(virtualPath);
      if (!saved) await service.deleteFile(virtualPath);
    }

    if (saved && name != null) {
      await cameraController.discardVideo(path);
      _segmentIndex++;
      _firstSegmentName ??= name;
      return true;
    }

    if (!mounted) {
      unawaited(cameraController.discardVideo(path));
      return false;
    }
    setState(() {
      capturedMedia.add(
        CapturedMediaItem.video(
          videoPath: path,
          videoDurationMs: durationMs,
          thumbnailBytes: Uint8List(0),
        ),
      );
    });
    if (!_segmentSpaceWarned) {
      _segmentSpaceWarned = true;
      showErrorToast(
        enoughSpace
            ? context.l10n.cameraCouldNotSaveCaptureMessage
            : context.l10n.cameraSegmentSpaceMessage,
      );
    }
    if (captureIsRecording) unawaited(stopVideoRecording());
    return false;
  }

  /// Ends a segmented recording: every part closed since the last pickup,
  /// then the last one, is saved into the vault chosen at the start, with no
  /// review. Then the vault gets the usual after-quick-capture lock policy
  /// and the screen closes. A part that could not be saved goes to the review
  /// screen instead.
  Future<void> _finishSegmentedRecording({
    required bool success,
    required String? videoPath,
    required int durationMs,
  }) async {
    if (mounted) setState(() => _phase = _Phase.saving);
    await _collectVideoSegments();
    if (success && videoPath != null) {
      // A short last part is still real footage, so it is kept.
      await _saveVideoSegment(path: videoPath, durationMs: durationMs);
    } else if (videoPath != null) {
      await cameraController.discardVideo(videoPath);
    }
    final destination = _segmentDestination;
    final savedName = _firstSegmentName;
    if (!mounted) return;

    if (capturedMedia.isNotEmpty) {
      setState(() => _phase = _Phase.reviewing);
      return;
    }
    if (savedName == null || destination == null) {
      setState(() => _phase = _Phase.camera);
      showErrorToast(context.l10n.cameraRecordingTooShortMessage);
      return;
    }
    await _relockAndFinish(
      destination: destination,
      savedName: savedName,
      isVideo: true,
    );
  }

  void _discardAllMedia() {
    for (final item in capturedMedia) {
      if (item.isVideo && item.videoPath != null) {
        cameraController.discardVideo(item.videoPath!);
      }
    }
    final session = _pendingScratchpad;
    _pendingScratchpad = null;
    if (session != null) {
      unawaited(_quickCaptureApi.discardSession(session.sessionToken));
    }
    setState(() {
      capturedMedia.clear();
      _phase = _Phase.camera;
      _saveError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    ref.watch(cameraCaptureControlsProvider(_quickCaptureControlsKey));
    ref.watch(cameraCaptureSessionProvider(_quickCaptureSessionKey));

    final isReviewing = _phase == _Phase.reviewing && capturedMedia.isNotEmpty;
    final canPop = !isReviewing &&
        !captureIsRecording &&
        !isEncrypting &&
        !captureIsCountingDown &&
        _phase != _Phase.saving &&
        capturedMedia.isEmpty &&
        pendingPhotoCount == 0;

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isReviewing) {
          setState(() => _phase = _Phase.camera);
        } else if (capturedMedia.isNotEmpty) {
          HapticFeedback.lightImpact();
          _backWithCapturedMedia();
        }
      },
      child: isReviewing
          ? CameraMediaReviewView(
              initialMedia: capturedMedia,
              iconTurns: captureIconTurns,
              onMediaChanged: (updated) {
                setState(() {
                  capturedMedia
                    ..clear()
                    ..addAll(updated);
                  if (capturedMedia.isEmpty) {
                    _phase = _Phase.camera;
                  }
                });
              },
              onDiscard: _discardAllMedia,
              onTakeMoreMedia: () {
                setState(() => _phase = _Phase.camera);
              },
              onSaveMedia: _commitAllMediaToVault,
            )
          : Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  if (isInitialized && cameraController.textureId != null)
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final bool isLandscapeFrame =
                            constraints.maxWidth > constraints.maxHeight;

                        return GestureDetector(
                          onScaleStart: (_) => baseZoom = captureCurrentZoom,
                          onScaleUpdate: (d) async {
                            double target = (baseZoom * d.scale).clamp(
                              captureMinZoom,
                              captureMaxZoom,
                            );
                            if (target != captureCurrentZoom) {
                              captureSessionController.setZoom(target);
                              await applyZoomSilent(cameraController, target);
                            }
                          },
                          onTapDown: (details) => _onTapToFocus(details, constraints),
                          child: Center(
                            child: CameraPreviewView(
                              textureId: cameraController.textureId!,
                              previewWidth: cameraController.previewWidth,
                              previewHeight: cameraController.previewHeight,
                              sensorOrientation: cameraController.sensorOrientation,
                              displayRotation: captureDisplayRotation,
                              frameAspectRatio: cameraPreviewFrameAspectRatio(
                                isLandscape: isLandscapeFrame,
                              ),
                              showShutterFlash: captureShowShutterFlash,
                            ),
                          ),
                        );
                      },
                    )
                  else if (permissionError != null)
                    Center(
                      child: Text(
                        permissionError!,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  else
                    const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),

                  if (_phase == _Phase.camera)
                    CameraFocusExposureOverlay(
                      focusPoint: captureFocusPoint,
                      showExposureSlider: captureShowExposureSlider,
                      currentExposureEv: captureCurrentExposureEv,
                      minExposureEv: captureMinExposureEv,
                      maxExposureEv: captureMaxExposureEv,
                      onExposureChanged: (val) async {
                        captureSessionController.setExposureEv(val);
                        await applyExposureOffsetSilent(cameraController, val);
                      },
                    ),

                  if (_phase == _Phase.camera) ...[
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: CameraTopControlsBar(
                        isVideoMode: captureControls.isVideoMode,
                        isRecording: captureIsRecording,
                        isCountingDown: captureIsCountingDown,
                        timerText: captureTimerText,
                        videoQuality: captureControls.videoQuality,
                        photoResolution: captureControls.photoResolution,
                        photoResolutions: captureSession.photoResolutions,
                        videoQualities: captureSession.videoQualities,
                        selectedAspectRatio: captureControls.aspectRatio,
                        onAspectRatioChanged: captureControlsController.selectAspectRatio,
                        timerDelaySeconds: captureControls.timerDelaySeconds,
                        flashMode: captureControls.flashMode,
                        hasFlash: captureHasFlash,
                        iconTurns: captureIconTurns,
                        onClose: () {
                          if (_phase == _Phase.saving) return;
                          Navigator.pop(context);
                        },
                        onVideoQualityChanged: changeQuality,
                        onPhotoResolutionChanged: changePhotoResolution,
                        onCycleTimerDelay: captureControlsController.cycleTimerDelay,
                        continuousCapture: captureControls.continuousCapture,
                        onToggleContinuousCapture:
                            captureControlsController.toggleContinuousCapture,
                        segmentMinutes: captureControls.segmentMinutes,
                        onSegmentMinutesChanged:
                            captureControlsController.selectSegmentMinutes,
                        onCycleFlashMode: () {
                          final nextMode = captureControlsController.cyclePhotoFlashMode();
                          unawaited(applyFlash(cameraController, nextMode, logTag: 'QuickCaptureScreen'));
                        },
                        onPhotoTorchActivated: () {
                          final mode = captureControlsController.activatePhotoTorch();
                          if (mode != null) {
                            unawaited(applyFlash(cameraController, mode, logTag: 'QuickCaptureScreen'));
                          }
                        },
                      ),
                    ),

                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: buildBottomControls(),
                    ),

                    if (isLandscape && (capturedMedia.isNotEmpty || pendingPhotoCount > 0) && !captureIsRecording && !captureIsCountingDown)
                      Positioned(
                        left: 16.0 + MediaQuery.paddingOf(context).left,
                        bottom: 76.0 + MediaQuery.paddingOf(context).bottom,
                        child: buildCapturedMediaTray(),
                      ),
                  ],

                  if (captureIsCountingDown)
                    Center(
                      child: buildRotatedWidget(
                        iconTurns: captureIconTurns,
                        child: Text(
                          '$countdownValue',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 120,
                            shadows: [Shadow(blurRadius: 20)],
                          ),
                        ),
                      ),
                    ),

                  if (isEncrypting || _phase == _Phase.saving)
                    Container(
                      color: Colors.black54,
                      child: Center(
                        child: buildRotatedWidget(
                          iconTurns: captureIconTurns,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(color: Colors.white),
                              const SizedBox(height: 20),
                              Text(
                                _phase == _Phase.saving
                                    ? context.l10n.savingToVault
                                    : busyLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
