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
    with WidgetsBindingObserver {
  late CameraVaultService _vaultService;
  late final VaultFileIoApi _fileIoApi;
  late final VaultLifecycleApi _lifecycleApi;
  late final VaultEngineEvents _engineEvents;
  late final VaultCameraController _cameraController;
  late final ActiveRecordingRegistry _activeRecordingRegistry;

  AppLifecycleState _lastLifecycleState = AppLifecycleState.resumed;
  Future<void>? _backgroundingFuture;
  bool _isOpeningCamera = false;

  bool _isRecording = false;
  bool _pendingStopAfterStart = false;
  bool _backgroundRecordingActive = false;
  bool _showShutterFlash = false;
  double _selectedAspectRatio = 4 / 3; // 4:3 (1.333), 16:9 (1.777), 1:1 (1.0)

  double _baseZoom = 1.0;
  Timer? _exposureHideTimer;
  Offset? _focusPoint;

  DateTime? _recordingStart;
  Timer? _timer;

 String? _currentRecordingName;
  String? _currentRecordingPath;
  final List<CapturedMediaItem> _capturedMedia = [];
  bool _isReviewingMedia = false;

  StreamSubscription<({double x, double y, double z})>? _sensorSubscription;
  StreamSubscription<Map<String, dynamic>>? _cameraEventSubscription;
  // Physical device rotation from the accelerometer (0, 0.25, 0.5, -0.25).
  double _deviceTurns = 0.0;
  // Surface.ROTATION_* (0..3) of the display, i.e. how far the OS has rotated the UI.
  int _displayRotation = 0;

  /// Icon rotation that is still needed on top of what the OS already applied.
  double get _iconTurns => cameraIconTurns(
    deviceTurns: _deviceTurns,
    displayRotation: _displayRotation,
  );

  String get _captureControlsKey =>
      '${widget.container.uri}\u0000${widget.targetDirPath}';

  CameraCaptureControlsState get _captureControls =>
      ref.read(cameraCaptureControlsProvider(_captureControlsKey));

  CameraCaptureControls get _captureControlsController =>
      ref.read(cameraCaptureControlsProvider(_captureControlsKey).notifier);

  CameraCaptureSessionState get _captureSession =>
      ref.read(cameraCaptureSessionProvider(_captureControlsKey));

  CameraCaptureSession get _captureSessionController =>
      ref.read(cameraCaptureSessionProvider(_captureControlsKey).notifier);

  bool get _isInitialized => _captureSession.isInitialized;
  String get _selectedCameraId => _captureSession.selectedCameraId;
  List<NativeCameraLens> get _lenses => _captureSession.lenses;
  bool get _isEncrypting => _captureSession.isEncrypting;
  bool get _isStartingVideo => _captureSession.isStartingVideo;
  String? get _permissionError => _captureSession.permissionError;
  bool get _isCountingDown => _captureSession.isCountingDown;
  int get _countdownValue => _captureSession.countdownValue;
  String get _busyLabel => _captureSession.busyLabel;
  String get _timerText => _captureSession.timerText;
  double get _currentZoom => _captureSession.currentZoom;
  double get _minZoom => _captureSession.minZoom;
  double get _maxZoom => _captureSession.maxZoom;
  double get _currentExposureEv => _captureSession.currentExposureEv;
  double get _minExposureEv => _captureSession.minExposureEv;
  double get _maxExposureEv => _captureSession.maxExposureEv;
  bool get _showExposureSlider => _captureSession.showExposureSlider;

  void _onBackgroundRecordingStopRequestedEvent(int volId) {
    if (volId == widget.container.volId && _isRecording) {
      unawaited(_stopVideoRecording());
    }
  }

  @override
  void initState() {
    super.initState();
    _fileIoApi = ref.read(vaultFileIoApiProvider);
    _lifecycleApi = ref.read(vaultLifecycleApiProvider);
    _engineEvents = ref.read(vaultEngineEventsProvider);
    _activeRecordingRegistry = ref.read(activeRecordingRegistryProvider);
    _cameraController = VaultCameraController(_engineEvents);

    _engineEvents.addBackgroundRecordingStopRequestedListener(
      _onBackgroundRecordingStopRequestedEvent,
    );
    // Follow the device: the preview is counter-rotated by the display
    // rotation (see CameraPreviewView), so no portrait lock is needed.
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _vaultService = CameraVaultService(
      container: widget.container,
      targetDirPath: widget.targetDirPath,
      fileIoApi: _fileIoApi,
      lifecycleApi: _lifecycleApi,
    );
    WidgetsBinding.instance.addObserver(this);

    _cameraEventSubscription = _cameraController.events.listen(
      _handleCameraEvent,
    );
    _initCamera();
    _startSensorListener();
    unawaited(_refreshDisplayRotation());
  }

  void _handleCameraEvent(Map<String, dynamic> event) {
    if (event['event'] != 'error' || !mounted) return;
    _captureSessionController.setPermissionError(
      context.l10n.cameraDisconnectedError(
        event['message'] ?? context.l10n.unknownErrorFallback,
      ),
    );
  }

  void _startSensorListener() {
    _sensorSubscription = VaultCameraController.accelerometerEventStream()
        .listen((event) {
          double magnitude = math.sqrt(event.x * event.x + event.y * event.y);
          if (magnitude < 2.0) return;

          double angle = math.atan2(event.x, event.y);
          double turns = angle / (2 * math.pi);
          double snappedTurns = (turns * 4).round() / 4.0;
          if (snappedTurns == -0.5) snappedTurns = 0.5;

          if (_deviceTurns != snappedTurns && mounted) {
            setState(() => _deviceTurns = snappedTurns);
            unawaited(applyOrientationSilent(_cameraController, _computeDeviceRotationDegrees()));
          }
        });
  }

  int _computeDeviceRotationDegrees() {
    return ((_deviceTurns * 360).round() % 360 + 360) % 360;
  }

  @override
  void didChangeMetrics() {
    unawaited(_refreshDisplayRotation());
  }

  Future<void> _refreshDisplayRotation() async {
    final rotation = await VaultCameraController.getDisplayRotation();
    if (!mounted || rotation == _displayRotation) return;
    setState(() => _displayRotation = rotation);
  }

  @override
  void dispose() {
    _engineEvents.removeBackgroundRecordingStopRequestedListener(
      _onBackgroundRecordingStopRequestedEvent,
    );
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _exposureHideTimer?.cancel();
    _sensorSubscription?.cancel();
    _cameraEventSubscription?.cancel();
    unawaited(_cameraController.dispose());

    // Safe disposal using local fields without calling ref.read
    if (_isRecording) {
      unawaited(_fileIoApi.setKeepScreenOn(false));
    }
    _activeRecordingRegistry.unregister(widget.container.uri);
    if (_backgroundRecordingActive) {
      unawaited(_fileIoApi.stopBackgroundRecording());
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
    _lastLifecycleState = state;

    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundingFuture = _handleGoingBackground();
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_handleResumed());
    }
  }

  Future<void> _handleGoingBackground() async {
    if (_isRecording) return;
    await _cameraController.close();
    if (mounted) {
      _captureSessionController.setUninitialized();
    }
  }

  Future<void> _handleResumed() async {
    unawaited(_refreshDisplayRotation());
    if (_backgroundingFuture != null) {
      await _backgroundingFuture;
    }
    if (!mounted) return;
    if (_backgroundRecordingActive) {
      unawaited(_resumeFromBackgroundRecording());
    } else if (!_cameraController.isInitialized) {
      await _initCamera(
        cameraId: _selectedCameraId.isNotEmpty ? _selectedCameraId : null,
      );
    }
  }

  Future<void> _resumeFromBackgroundRecording() async {}

  Future<void> _initCamera({String? cameraId}) async {
    if (_isOpeningCamera) return;
    _isOpeningCamera = true;
    try {
      final hasPerms = await VaultCameraController.hasPermissions();
      if (!hasPerms) {
        final granted = await _cameraController.requestPermissions();
        if (!granted) {
          if (mounted) {
            _captureSessionController.setPermissionError(
              context.l10n.cameraPermissionsRequiredMessage,
            );
          }
          return;
        }
      }

      final info = await _cameraController.open(
        cameraId: cameraId,
        facing: 'back',
        quality: _captureControls.videoQuality,
        photoResolution: _captureControls.photoResolution,
      );

      if (!mounted) return;

      if (_lastLifecycleState == AppLifecycleState.paused ||
          _lastLifecycleState == AppLifecycleState.hidden) {
        await _cameraController.close();
        return;
      }

      _captureSessionController.setCameraOpened(info);
      await _cameraController.setFlash(_captureControls.flashMode);
      await _cameraController.setZoom(_currentZoom);
    } catch (e) {
      if (mounted) {
        _captureSessionController.setPermissionError(
          context.l10n.cameraErrorMessage('$e'),
        );
      }
    } finally {
      _isOpeningCamera = false;
    }
  }

  Future<void> _flipCamera() async {
    if (_isRecording ||
        _isEncrypting ||
        _isCountingDown ||
        _isStartingVideo ||
        _lenses.length <= 1) {
      return;
    }

    HapticFeedback.lightImpact();

    final currentLens = _lenses.firstWhere(
      (l) => l.cameraId == _selectedCameraId,
      orElse: () => _lenses.first,
    );

    final targetFacing = currentLens.facing == 'back' ? 'front' : 'back';
    final targetLens = _lenses.firstWhere(
      (l) => l.facing == targetFacing,
      orElse: () => _lenses.firstWhere(
        (l) => l.cameraId != _selectedCameraId,
        orElse: () => currentLens,
      ),
    );

    if (targetLens.cameraId != _selectedCameraId) {
      _captureSessionController.setUninitialized(cancelCountdown: false);
      await _initCamera(cameraId: targetLens.cameraId);
    }
  }

  Future<void> _changeQuality(String quality) async {
    if (_isRecording ||
        _isEncrypting ||
        _isCountingDown ||
        _isStartingVideo ||
        _captureControls.videoQuality == quality) {
      return;
    }
    _captureControlsController.selectVideoQuality(quality);
    _captureSessionController.setUninitialized(cancelCountdown: false);
    await _initCamera(cameraId: _selectedCameraId);
  }

  Future<void> _changePhotoResolution(String resolution) async {
    if (_isRecording ||
        _isEncrypting ||
        _isCountingDown ||
        _isStartingVideo ||
        _captureControls.photoResolution == resolution) {
      return;
    }
    _captureControlsController.selectPhotoResolution(resolution);
    _captureSessionController.setUninitialized(cancelCountdown: false);
    await _initCamera(cameraId: _selectedCameraId);
  }

  void _onTapToFocus(TapDownDetails details, BoxConstraints constraints) async {
    if (!_cameraController.isInitialized) return;

    // Normalized in the displayed frame -> natural-orientation frame, which
    // is what the native focus/metering mapping expects.
    final natural = cameraDisplayPointToNatural(
      details.localPosition.dx / constraints.maxWidth,
      details.localPosition.dy / constraints.maxHeight,
      _displayRotation,
    );
    final nx = natural.x;
    final ny = natural.y;

    setState(() {
      _focusPoint = details.localPosition;
    });
    _captureSessionController.setShowExposureSlider(true);

    // Hardware locks focus and exposure metering onto the tapped point
    await applyFocusAndExposurePoint(_cameraController, nx, ny, logTag: 'CameraCaptureScreen');

    _exposureHideTimer?.cancel();
    _exposureHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _captureSessionController.setShowExposureSlider(false);
        setState(() {
          _focusPoint = null;
        });
        // Returns sensor back to continuous autofocus once reticle disappears
        unawaited(_cameraController.resetFocusAndExposure());
      }
    });
  }

  void _onCaptureClicked() {
    if (_isEncrypting) return;
    HapticFeedback.mediumImpact();

    if (_isCountingDown) {
      _captureSessionController.stopCountdown();
      return;
    }

    if (_captureControls.isVideoMode) {
      if (_isRecording) {
        _stopVideoRecording();
      } else if (_isStartingVideo) {
        _pendingStopAfterStart = true;
      } else {
        _startVideoRecording();
      }
    } else {
      _captureControls.timerDelaySeconds > 0
          ? _startPhotoCountdownAndCapture()
          : _takePhoto();
    }
  }

  Future<void> _setVideoMode(bool videoMode) async {
    if (_isRecording ||
        _isEncrypting ||
        _isCountingDown ||
        _isStartingVideo ||
        _captureControls.isVideoMode == videoMode) {
      return;
    }

    _captureControlsController.setVideoMode(videoMode);
    await applyFlash(_cameraController, _captureControls.flashMode, logTag: 'CameraCaptureScreen');
  }

  Future<void> _startPhotoCountdownAndCapture() async {
    final delay = _captureControls.timerDelaySeconds;
    _captureSessionController.startCountdown(delay);

    for (int i = delay; i > 0; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_isCountingDown) return;
      HapticFeedback.lightImpact();
      _captureSessionController.updateCountdown(i - 1);
    }

    _captureSessionController.stopCountdown();
    await _takePhoto();
  }

   void _triggerShutterFlash() {
    setState(() => _showShutterFlash = true);
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) setState(() => _showShutterFlash = false);
    });
  }

   Future<void> _takePhoto() async {
    if (!_cameraController.isInitialized || _isEncrypting) return;

    _triggerShutterFlash();

    try {
      await _cameraController.setOrientationDegrees(
        _computeDeviceRotationDegrees(),
      );

      final isFirstMedia = _capturedMedia.isEmpty;
      final result = await _cameraController.capturePhoto();

      if (result.success && result.bytes != null && mounted) {
        HapticFeedback.lightImpact();
        setState(() {
          _capturedMedia.add(
            CapturedMediaItem.photo(
              photoBytes: result.bytes!,
              thumbnailBytes: result.thumbnail ?? result.bytes!,
            ),
          );
          if (isFirstMedia) {
            _isReviewingMedia = true;
          }
        });
      } else {
        if (mounted) {
          _showErrorToast(
            result.error ?? context.l10n.cameraPhotoCaptureFailedMessage,
          );
        }
      }
    } catch (_) {
      if (mounted) {
        _showErrorToast(context.l10n.cameraPhotoCaptureFailedMessage);
      }
    }
  }

  Future<void> _commitAllMediaToVault(List<CapturedMediaItem> mediaToSave) async {
    if (mediaToSave.isEmpty) return;

    _captureSessionController.setEncrypting(
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
          final ok = await _cameraController.savePhotoToVault(
            bytes: item.fullPhotoBytes!,
            volId: widget.container.volId,
            virtualPath: virtualPath,
          );
          if (ok) await _vaultService.finalizeVaultWrite(virtualPath);
        } else if (item.isVideo && item.videoPath != null) {
          hasVideo = true;
          var finalVideoPath = item.videoPath!;
          if (item.trimStartMs > 0 || (item.trimEndMs > 0 && item.trimEndMs < item.videoDurationMs)) {
            final trimmed = await _cameraController.trimVideo(
              videoPath: item.videoPath!,
              startMs: item.trimStartMs,
              endMs: item.trimEndMs,
            );
            if (trimmed != null) finalVideoPath = trimmed;
          }
          final name = await _vaultService.nextAvailableName(isPhoto: false);
          firstName ??= name;
          final virtualPath = _vaultService.buildVirtualPath(name);
          final ok = await _cameraController.saveVideoToVault(
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
      if (mounted) _captureSessionController.setEncrypting(false);
    }
  }

  Future<void> _startVideoRecording() async {
    if (!_cameraController.isInitialized ||
        _isEncrypting ||
        _isRecording ||
        _isStartingVideo) {
      return;
    }

    _captureSessionController.setStartingVideo(true);

    try {
      final name = await _vaultService.nextAvailableName(isPhoto: false);
      final virtualPath = _vaultService.buildVirtualPath(name);

      _currentRecordingName = name;
      _currentRecordingPath = virtualPath;

      await _cameraController.setOrientationDegrees(
        _computeDeviceRotationDegrees(),
      );

      final result = await _cameraController.startVideoRecording(
        volId: widget.container.volId,
        virtualPath: virtualPath,
      );

      if (!result.success) {
        _showErrorToast(
          result.error ?? context.l10n.cameraRecordingFailedMessage,
        );
        return;
      }

      _recordingStart = DateTime.now();
      setState(() => _isRecording = true);

      if (!mounted) return;
      _captureSessionController.startRecording();
      unawaited(_fileIoApi.setKeepScreenOn(true));
      _activeRecordingRegistry.register(
        widget.container.uri,
        _stopVideoRecording,
      );

      _backgroundRecordingActive = true;
      unawaited(
        _fileIoApi.startBackgroundRecording(
          volId: widget.container.volId,
          containerName: widget.container.displayName,
        ),
      );

      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted || _recordingStart == null) return;
        final elapsed = DateTime.now().difference(_recordingStart!).inSeconds;
        _captureSessionController.updateTimerText(
          '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}',
        );
      });
    } catch (e) {
      _showErrorToast(
        context.l10n.cameraRecordingFailedWithReasonMessage('$e'),
      );
    } finally {
      _captureSessionController.setStartingVideo(false);
      if (_pendingStopAfterStart) {
        _pendingStopAfterStart = false;
        if (_isRecording) _stopVideoRecording();
      }
    }
  }

  Future<void> _stopVideoRecording() async {
    if (!_cameraController.isInitialized || !_isRecording) return;

    _timer?.cancel();
    final startedAt = _recordingStart;
    _recordingStart = null;
    setState(() => _isRecording = false);

    try {
      final isFirstMedia = _capturedMedia.isEmpty;
      final result = await _cameraController.stopVideoRecordingForReview();

      final elapsedMs = startedAt == null
          ? 9999
          : DateTime.now().difference(startedAt).inMilliseconds;
      if (elapsedMs < 500 || !result.success || result.videoPath == null) {
        if (result.videoPath != null) {
          await _cameraController.discardVideo(result.videoPath!);
        }
        if (mounted) {
          _showErrorToast(context.l10n.cameraRecordingTooShortMessage);
        }
        return;
      }

      setState(() {
        _capturedMedia.add(
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
        _showErrorToast(
          context.l10n.cameraCouldNotSaveRecordingWithReasonMessage('$e'),
        );
      }
    } finally {
      unawaited(_fileIoApi.setKeepScreenOn(false));
      _activeRecordingRegistry.unregister(widget.container.uri);
      if (_backgroundRecordingActive) {
        _backgroundRecordingActive = false;
        unawaited(_fileIoApi.stopBackgroundRecording());
      }
    }
  }

  void _discardAllMedia() {
    for (final item in _capturedMedia) {
      if (item.isVideo && item.videoPath != null) {
        _cameraController.discardVideo(item.videoPath!);
      }
    }
    setState(() {
      _capturedMedia.clear();
      _isReviewingMedia = false;
    });
  }

  void _showErrorToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

   @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    ref.watch(cameraCaptureControlsProvider(_captureControlsKey));
    ref.watch(cameraCaptureSessionProvider(_captureControlsKey));
    final isContainerLocked = ref.watch(
      cameraCaptureLockProvider(widget.container.volId),
    );
    if (isContainerLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    if (_isReviewingMedia && _capturedMedia.isNotEmpty) {
      return CameraMediaReviewView(
        initialMedia: _capturedMedia,
        iconTurns: _iconTurns,
        onMediaChanged: (updated) {
          setState(() {
            _capturedMedia
              ..clear()
              ..addAll(updated);
          });
        },
        onDiscard: _discardAllMedia,
        onTakeMoreMedia: () {
          setState(() => _isReviewingMedia = false);
        },
        onSaveMedia: _commitAllMediaToVault,
      );
    }

    return PopScope(
      canPop: !_isRecording && !_isEncrypting && !_isCountingDown && _capturedMedia.isEmpty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_capturedMedia.isNotEmpty) {
          HapticFeedback.lightImpact();
          _discardAllMedia();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_isInitialized && _cameraController.textureId != null)
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isLandscapeFrame =
                      constraints.maxWidth > constraints.maxHeight;

                  return GestureDetector(
                    onScaleStart: (_) => _baseZoom = _currentZoom,
                    onScaleUpdate: (d) async {
                      double target = (_baseZoom * d.scale).clamp(
                        _minZoom,
                        _maxZoom,
                      );
                      if (target != _currentZoom) {
                        _captureSessionController.setZoom(target);
                        await applyZoomSilent(_cameraController, target);
                      }
                    },
                    onTapDown: (details) => _onTapToFocus(details, constraints),
                    child: Center(
                      child: CameraPreviewView(
                        textureId: _cameraController.textureId!,
                        previewWidth: _cameraController.previewWidth,
                        previewHeight: _cameraController.previewHeight,
                        sensorOrientation: _cameraController.sensorOrientation,
                        displayRotation: _displayRotation,
                        frameAspectRatio: isLandscapeFrame
                            ? _selectedAspectRatio
                            : 1 / _selectedAspectRatio,
                      ),
                    ),
                  );
                },
              )
            else if (_permissionError != null)
              Center(
                child: Text(
                  _permissionError!,
                  style: const TextStyle(color: Colors.white),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Exposure focus reticle and vertical slider
            CameraFocusExposureOverlay(
              focusPoint: _focusPoint,
              showExposureSlider: _showExposureSlider,
              currentExposureEv: _currentExposureEv,
              minExposureEv: _minExposureEv,
              maxExposureEv: _maxExposureEv,
              onExposureChanged: (val) async {
                _captureSessionController.setExposureEv(val);
                await applyExposureOffsetSilent(_cameraController, val);
              },
            ),

            // Top Bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: CameraTopControlsBar(
                isVideoMode: _captureControls.isVideoMode,
                isRecording: _isRecording,
                isCountingDown: _isCountingDown,
                timerText: _timerText,
                videoQuality: _captureControls.videoQuality,
                photoResolution: _captureControls.photoResolution,
                selectedAspectRatio: _selectedAspectRatio,
                onAspectRatioChanged: (ratio) => setState(() => _selectedAspectRatio = ratio),
                timerDelaySeconds: _captureControls.timerDelaySeconds,
                flashMode: _captureControls.flashMode,
                iconTurns: _iconTurns,
                onClose: () => Navigator.pop(context),
                onVideoQualityChanged: _changeQuality,
                onPhotoResolutionChanged: _changePhotoResolution,
                onCycleTimerDelay: _captureControlsController.cycleTimerDelay,
                onCycleFlashMode: () {
                  final nextMode = _captureControlsController.cyclePhotoFlashMode();
                  unawaited(applyFlash(_cameraController, nextMode, logTag: 'CameraCaptureScreen'));
                },
              ),
            ),

         // Bottom Bar
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildBottomControls(),
            ),

           // In LANDSCAPE, place the tray above the flip camera button on the left so they never overlap
            if (isLandscape && _capturedMedia.isNotEmpty && !_isRecording && !_isCountingDown)
              Positioned(
                left: 16.0 + MediaQuery.paddingOf(context).left,
                bottom: 76.0 + MediaQuery.paddingOf(context).bottom,
                child: _buildCapturedMediaTray(),
              ),

             IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showShutterFlash ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 50),
                child: Container(color: Colors.white.withValues(alpha: 0.65)),
              ),
            ),

            if (_isCountingDown)
              Center(
                child: buildRotatedWidget(
                  iconTurns: _iconTurns,
                  child: Text(
                    '$_countdownValue',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 120,
                      shadows: [Shadow(blurRadius: 20)],
                    ),
                  ),
                ),
              ),

            if (_isEncrypting)
              Container(
                color: Colors.black54,
                child: Center(
                  child: buildRotatedWidget(
                    iconTurns: _iconTurns,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 20),
                        Text(
                          _busyLabel,
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

  Widget _buildCapturedMediaTray() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

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
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < _capturedMedia.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 2, right: 8, left: 4),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              setState(() => _isReviewingMedia = true);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white54, width: 1.5),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    _capturedMedia[i].thumbnailBytes.isNotEmpty
                                        ? Image.memory(
                                            _capturedMedia[i].thumbnailBytes,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(color: Colors.grey.shade900),
                                    if (_capturedMedia[i].isVideo)
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
                                final removed = _capturedMedia.removeAt(i);
                                if (removed.isVideo && removed.videoPath != null) {
                                  _cameraController.discardVideo(removed.videoPath!);
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
            onPressed: () {
              setState(() => _isReviewingMedia = true);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${_capturedMedia.length}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_rounded, size: 14),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
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
            // Live captured media tray: stacked above controls ONLY in PORTRAIT
            if (!isLandscape && _capturedMedia.isNotEmpty && !_isRecording && !_isCountingDown)
              _buildCapturedMediaTray(),

            if (!_isRecording && !_isCountingDown) ...[
              CameraZoomIndicator(
                currentZoom: _currentZoom,
                minZoom: _minZoom,
                maxZoom: _maxZoom,
                iconTurns: _iconTurns,
                onSetZoom: (zoom) async {
                  _captureSessionController.setZoom(zoom);
                  await applyZoomLogged(_cameraController, zoom, logTag: 'CameraCaptureScreen');
                },
              ),
              SizedBox(height: isLandscape ? 6 : 16),
            ],
            SizedBox(height: isLandscape ? 8 : 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
               buildRotatedWidget(
                  iconTurns: _iconTurns,
                  child: IconButton(
                    icon: const Icon(
                      Icons.flip_camera_ios_rounded,
                      color: Colors.white,
                      size: 32,
                    ),
                    onPressed: _flipCamera,
                  ),
                ),
                GestureDetector(
                  onTap: _onCaptureClicked,
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
                      width: _captureControls.isVideoMode && _isRecording ? 30 : 60,
                      height: _captureControls.isVideoMode && _isRecording ? 30 : 60,
                      decoration: BoxDecoration(
                        color: _captureControls.isVideoMode ? Colors.red : Colors.white,
                        borderRadius: BorderRadius.circular(
                          _captureControls.isVideoMode && _isRecording ? 8 : 30,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_isRecording && !_isCountingDown)
                  _buildModeToggle()
                else
                  const SizedBox(width: 48),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle() {
    Widget modeButton({
      required bool selected,
      required IconData icon,
      required VoidCallback onTap,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: buildRotatedWidget(
          iconTurns: _iconTurns,
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
          selected: !_captureControls.isVideoMode,
          icon: Icons.photo_camera_rounded,
          onTap: () => _setVideoMode(false),
        ),
        const SizedBox(height: 10),
        modeButton(
          selected: _captureControls.isVideoMode,
          icon: Icons.videocam_rounded,
          onTap: () => _setVideoMode(true),
        ),
      ],
    );
  }
}