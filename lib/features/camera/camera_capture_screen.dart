import 'dart:async';
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'active_recording_registry.dart';
import 'camera_vault_service.dart';
import 'camera_capture_controls_controller.dart';
import 'camera_capture_lock_controller.dart';
import 'camera_capture_session_controller.dart';
import 'camera_ui_components.dart';
import 'capture_screen_mixin.dart';
import 'camera_media_review_view.dart';
import 'vault_camera_controller.dart';
import '../image_editor/image_editor_screen.dart';

class CameraCaptureScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String targetDirPath;

  const CameraCaptureScreen({
    super.key,
    required this.container,
    required this.targetDirPath,
  });

  @override
  ConsumerState<CameraCaptureScreen> createState() =>
      _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends ConsumerState<CameraCaptureScreen>
    with WidgetsBindingObserver, CaptureScreenStateMixin<CameraCaptureScreen> {
  @override
  String get captureControlsKey => _captureControlsKey;

  @override
  String get captureLogTag => 'CameraCaptureScreen';

  @override
  void enterReviewing() {
    _isReviewingMedia = true;
  }

  late CameraVaultService _vaultService;

  late final ActiveRecordingRegistry _activeRecordingRegistry;

  bool _backgroundRecordingActive = false;

  String? _currentRecordingName;

  String? _currentRecordingPath;

  bool _isReviewingMedia = false;

  static const String _captureControlsKey = 'camera_capture';

  @override
  String get captureSessionKey =>
      '${widget.container.uri}\u0000${widget.targetDirPath}';

  @override
  bool get captureIsCountingDown => captureSession.isCountingDown;

  void _onBackgroundRecordingStopRequestedEvent(int volId) {
    if (volId == widget.container.volId && captureIsRecording) {
      unawaited(stopVideoRecording());
    }
  }

  @override
  void initState() {
    super.initState();
    captureFileIoApi = ref.read(vaultFileIoApiProvider);
    captureLifecycleApi = ref.read(vaultLifecycleApiProvider);
    engineEvents = ref.read(vaultEngineEventsProvider);
    _activeRecordingRegistry = ref.read(activeRecordingRegistryProvider);
    cameraController = VaultCameraController(engineEvents);

    engineEvents.addBackgroundRecordingStopRequestedListener(
      _onBackgroundRecordingStopRequestedEvent,
    );
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _vaultService = CameraVaultService(
      container: widget.container,
      targetDirPath: widget.targetDirPath,
      fileIoApi: captureFileIoApi,
      lifecycleApi: captureLifecycleApi,
    );
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
    if (_isReviewingMedia && capturedMedia.isNotEmpty) {
      return true;
    }
    if (captureIsRecording ||
        isEncrypting ||
        captureIsCountingDown ||
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
    if (_isReviewingMedia && capturedMedia.isNotEmpty) {
      setState(() => _isReviewingMedia = false);
    } else if (capturedMedia.isNotEmpty) {
      HapticFeedback.lightImpact();
      _discardAllMedia();
    }
  }

  @override
  void dispose() {
    engineEvents.removeBackgroundRecordingStopRequestedListener(
      _onBackgroundRecordingStopRequestedEvent,
    );
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
    _activeRecordingRegistry.unregister(widget.container.uri);
    if (_backgroundRecordingActive) {
      unawaited(captureFileIoApi.stopBackgroundRecording());
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

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      backgroundingFuture = _handleGoingBackground();
    } else if (state == AppLifecycleState.resumed && backgroundingFuture != null) {
      unawaited(_handleResumed());
    }
  }

  Future<void> _handleGoingBackground() async {
    if (captureIsRecording) return;
    await cameraController.close();
    if (mounted) {
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
    if (!mounted) return;
    if (_backgroundRecordingActive) {
      unawaited(_resumeFromBackgroundRecording());
    } else if (!cameraController.isInitialized) {
      await initCamera(
        cameraId: selectedCameraId.isNotEmpty ? selectedCameraId : null,
      );
    }
  }

  Future<void> _resumeFromBackgroundRecording() async {}

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

      if (lastLifecycleState == AppLifecycleState.paused ||
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

    setState(() {
      captureFocusPoint = details.localPosition;
    });
    captureSessionController.setShowExposureSlider(true);

    await applyFocusAndExposurePoint(cameraController, nx, ny, logTag: 'CameraCaptureScreen');

    exposureHideTimer?.cancel();
    exposureHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        captureSessionController.setShowExposureSlider(false);
        setState(() {
          captureFocusPoint = null;
        });
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
    await applyFlash(cameraController, captureControls.flashMode, logTag: 'CameraCaptureScreen');
  }

  Future<void> _commitAllMediaToVault(List<CapturedMediaItem> mediaToSave) async {
    if (mediaToSave.isEmpty) return;

    captureSessionController.setEncrypting(
      true,
      label: context.l10n.savingToVault,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      String? firstName;
      bool hasVideo = false;

      for (int i = 0; i < mediaToSave.length; i++) {
        final item = mediaToSave[i];
        if (item.isPhoto && item.fullPhotoBytes != null) {
          final name = await _vaultService.nextAvailableName(isPhoto: true);
          firstName ??= name;
          final virtualPath = _vaultService.buildVirtualPath(name);
          final ok = await cameraController.savePhotoToVault(
            bytes: item.fullPhotoBytes!,
            volId: widget.container.volId,
            virtualPath: virtualPath,
          );
          if (ok) await _vaultService.finalizeVaultWrite(virtualPath);
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
          final name = await _vaultService.nextAvailableName(isPhoto: false);
          firstName ??= name;
          final virtualPath = _vaultService.buildVirtualPath(name);
          final ok = await cameraController.saveVideoToVault(
            videoPath: finalVideoPath,
            volId: widget.container.volId,
            virtualPath: virtualPath,
          );
          if (ok) await _vaultService.finalizeVaultWrite(virtualPath);
        }
      }

      if (mounted) {
        Navigator.pop(context, (savedName: firstName ?? 'media', isVideo: hasVideo));
      }
    } finally {
      if (mounted) captureSessionController.setEncrypting(false);
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
      final name = await _vaultService.nextAvailableName(isPhoto: false);
      final virtualPath = _vaultService.buildVirtualPath(name);

      _currentRecordingName = name;
      _currentRecordingPath = virtualPath;

      await cameraController.setOrientationDegrees(
        computeDeviceRotationDegrees(),
      );

      final result = await cameraController.startVideoRecording(
        volId: widget.container.volId,
        virtualPath: virtualPath,
      );

      if (!result.success) {
        showErrorToast(
          result.error ?? context.l10n.cameraRecordingFailedMessage,
        );
        return;
      }

      recordingStart = DateTime.now();
      setState(() => captureIsRecording = true);

      if (!mounted) return;
      captureSessionController.startRecording();
      unawaited(captureFileIoApi.setKeepScreenOn(true));
      _activeRecordingRegistry.register(
        widget.container.uri,
        stopVideoRecording,
      );

      _backgroundRecordingActive = true;
      unawaited(
        captureFileIoApi.startBackgroundRecording(
          volId: widget.container.volId,
          containerName: widget.container.displayName,
        ),
      );

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
    setState(() => captureIsRecording = false);

    try {
      final isFirstMedia = capturedMedia.isEmpty;
      final result = await cameraController.stopVideoRecordingForReview();

      final elapsedMs = startedAt == null
          ? 9999
          : DateTime.now().difference(startedAt).inMilliseconds;
      if (elapsedMs < 500 || !result.success || result.videoPath == null) {
        if (result.videoPath != null) {
          await cameraController.discardVideo(result.videoPath!);
        }
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
          _isReviewingMedia = true;
        }
      });
    } catch (e) {
      if (mounted) {
        showErrorToast(
          context.l10n.cameraCouldNotSaveRecordingWithReasonMessage('$e'),
        );
      }
    } finally {
      unawaited(captureFileIoApi.setKeepScreenOn(false));
      _activeRecordingRegistry.unregister(widget.container.uri);
      if (_backgroundRecordingActive) {
        _backgroundRecordingActive = false;
        unawaited(captureFileIoApi.stopBackgroundRecording());
      }
    }
  }

  void _discardAllMedia() {
    for (final item in capturedMedia) {
      if (item.isVideo && item.videoPath != null) {
        cameraController.discardVideo(item.videoPath!);
      }
    }
    setState(() {
      capturedMedia.clear();
      _isReviewingMedia = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    ref.watch(cameraCaptureControlsProvider(_captureControlsKey));
    ref.watch(cameraCaptureSessionProvider(captureSessionKey));
    final isContainerLocked = ref.watch(
      cameraCaptureLockProvider(widget.container.volId),
    );
    if (isContainerLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    if (_isReviewingMedia && capturedMedia.isNotEmpty) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          setState(() => _isReviewingMedia = false);
        },
        child: CameraMediaReviewView(
          initialMedia: capturedMedia,
          iconTurns: captureIconTurns,
          onMediaChanged: (updated) {
            setState(() {
              capturedMedia
                ..clear()
                ..addAll(updated);
            });
          },
          onDiscard: _discardAllMedia,
          onTakeMoreMedia: () {
            setState(() => _isReviewingMedia = false);
          },
          onSaveMedia: _commitAllMediaToVault,
        ),
      );
    }

    return PopScope(
      canPop: !captureIsRecording && !isEncrypting && !captureIsCountingDown && capturedMedia.isEmpty && pendingPhotoCount == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (capturedMedia.isNotEmpty) {
          HapticFeedback.lightImpact();
          _discardAllMedia();
        }
      },
      child: Scaffold(
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
                currentPhotoResolution: captureSession.currentPhotoResolution,
                currentVideoResolution: captureSession.currentVideoResolution,
                selectedAspectRatio: captureControls.aspectRatio,
                onAspectRatioChanged: captureControlsController.selectAspectRatio,
                timerDelaySeconds: captureControls.timerDelaySeconds,
                flashMode: captureControls.flashMode,
                iconTurns: captureIconTurns,
                onClose: () => Navigator.pop(context),
                onVideoQualityChanged: changeQuality,
                onPhotoResolutionChanged: changePhotoResolution,
                onCycleTimerDelay: captureControlsController.cycleTimerDelay,
                onCycleFlashMode: () {
                  final nextMode = captureControlsController.cyclePhotoFlashMode();
                  unawaited(applyFlash(cameraController, nextMode, logTag: 'CameraCaptureScreen'));
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

            if (isEncrypting)
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
                          busyLabel,
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