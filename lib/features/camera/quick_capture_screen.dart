import 'dart:async';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/api/quick_capture_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
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
import '../image_editor/image_editor_screen.dart';

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

  _Phase _phase = _Phase.camera;

  ScratchpadSession? _pendingScratchpad;

  String? _saveError;

  @override
  bool get captureIsCountingDown => captureSession.countdownValue > 0 && captureSession.isCountingDown;

  @override
  void initState() {
    super.initState();
    captureFileIoApi = ref.read(vaultFileIoApiProvider);
    captureLifecycleApi = ref.read(vaultLifecycleApiProvider);
    engineEvents = ref.read(vaultEngineEventsProvider);
    _quickCaptureApi = ref.read(quickCaptureApiProvider);
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
      _discardAllMedia();
    }
  }

  @override
  void dispose() {
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

    try {
      String? firstName;
      bool hasVideo = false;

      for (int i = 0; i < mediaToSave.length; i++) {
        final item = mediaToSave[i];
        if (item.isPhoto && item.fullPhotoBytes != null) {
          final name = await vaultService.nextAvailableName(isPhoto: true);
          firstName ??= name;
          final virtualPath = vaultService.buildVirtualPath(name);
          final ok = await cameraController.savePhotoToVault(
            bytes: item.fullPhotoBytes!,
            volId: container.volId,
            virtualPath: virtualPath,
          );
          if (ok) await vaultService.finalizeVaultWrite(virtualPath);
        } else if (item.isVideo && item.videoPath != null) {
          hasVideo = true;
          var finalVideoPath = item.videoPath!;
          if (item.trimStartMs > 0 || (item.trimEndMs > 0 && item.trimEndMs < item.videoDurationMs)) {
            final trimmed = await cameraController.trimVideo(
              videoPath: item.videoPath!,
              startMs: item.trimStartMs,
              endMs: item.trimEndMs,
            );
            if (trimmed != null) finalVideoPath = trimmed;
          }
          final name = await vaultService.nextAvailableName(isPhoto: false);
          firstName ??= name;
          final virtualPath = vaultService.buildVirtualPath(name);
          final ok = await cameraController.saveVideoToVault(
            videoPath: finalVideoPath,
            volId: container.volId,
            virtualPath: virtualPath,
          );
          if (ok) await vaultService.finalizeVaultWrite(virtualPath);
        }
      }

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
          context.l10n.quickCaptureSavedToast(firstName ?? 'media', destination.displayName),
        );
        Navigator.pop(context, (savedName: firstName ?? 'media', isVideo: hasVideo));
      }
    } catch (_) {
      if (mounted) {
        showErrorToast(context.l10n.cameraCouldNotSaveRecordingMessage);
        setState(() => _phase = _Phase.camera);
      }
    }
  }

  @override
  Future<void> startVideoRecording() async {
    if (!cameraController.isInitialized ||
        isEncrypting ||
        captureIsRecording ||
        isStartingVideo) {
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
        computeDeviceRotationDegrees(),
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

    try {
      final isFirstMedia = capturedMedia.isEmpty;
      final result = await cameraController.stopVideoRecordingForReview();
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
        if (isFirstMedia) {
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
      unawaited(captureFileIoApi.setKeepScreenOn(false));
    }
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
          _discardAllMedia();
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
                              frameAspectRatio: isLandscapeFrame
                                  ? captureControls.aspectRatio
                                  : 1 / captureControls.aspectRatio,
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
                        iconTurns: captureIconTurns,
                        onClose: () {
                          if (_phase == _Phase.saving) return;
                          Navigator.pop(context);
                        },
                        onVideoQualityChanged: changeQuality,
                        onPhotoResolutionChanged: changePhotoResolution,
                        onCycleTimerDelay: captureControlsController.cycleTimerDelay,
                        onCycleFlashMode: () {
                          final nextMode = captureControlsController.cyclePhotoFlashMode();
                          unawaited(applyFlash(cameraController, nextMode, logTag: 'QuickCaptureScreen'));
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