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
import 'vault_camera_controller.dart';

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

  StreamSubscription<({double x, double y, double z})>? _sensorSubscription;
  StreamSubscription<Map<String, dynamic>>? _cameraEventSubscription;
  double _iconTurns = 0.0;

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
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
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

          if (_iconTurns != snappedTurns && mounted) {
            setState(() => _iconTurns = snappedTurns);
            _cameraController.setOrientationDegrees(
              _computeDeviceRotationDegrees(),
            );
          }
        });
  }

  int _computeDeviceRotationDegrees() {
    return ((_iconTurns * 360).round() % 360 + 360) % 360;
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
    if (!_cameraController.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      unawaited(_handleGoingInactive());
    } else if (state == AppLifecycleState.resumed) {
      if (_backgroundRecordingActive) {
        unawaited(_resumeFromBackgroundRecording());
      } else {
        _initCamera(
          cameraId: _selectedCameraId.isNotEmpty ? _selectedCameraId : null,
        );
      }
    }
  }

  Future<void> _handleGoingInactive() async {
    if (_isRecording) return;
    await _cameraController.close();
    if (mounted) {
      _captureSessionController.setUninitialized();
    }
  }

  Future<void> _resumeFromBackgroundRecording() async {}

  Future<void> _initCamera({String? cameraId}) async {
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

      _captureSessionController.setCameraOpened(info);
      await _cameraController.setFlash(_captureControls.flashMode);
      await _cameraController.setZoom(_currentZoom);
    } catch (e) {
      if (mounted) {
        _captureSessionController.setPermissionError(
          context.l10n.cameraErrorMessage('$e'),
        );
      }
    }
  }

  Future<void> _switchLens(String cameraId) async {
    if (_isRecording || _isEncrypting || _isCountingDown || _isStartingVideo) return;
    _captureSessionController.setUninitialized(cancelCountdown: false);
    try {
      await _cameraController.switchLens(cameraId);
      if (mounted) {
        _captureSessionController.setZoom(_cameraController.zoomMin);
        _captureSessionController.setCameraOpened(
          VaultCameraSessionInfo(
            sessionId: _cameraController.sessionId ?? 0,
            textureId: _cameraController.textureId ?? 0,
            cameraId: cameraId,
            zoomMin: _cameraController.zoomMin,
            zoomMax: _cameraController.zoomMax,
            minExposureEv: _cameraController.minExposureEv,
            maxExposureEv: _cameraController.maxExposureEv,
            previewWidth: _cameraController.previewWidth,
            previewHeight: _cameraController.previewHeight,
            sensorOrientation: _cameraController.sensorOrientation,
            lenses: _lenses,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showErrorToast(context.l10n.cameraCouldNotSwitchLensMessage);
      }
      await _initCamera(cameraId: _selectedCameraId);
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

    final nx = details.localPosition.dx / constraints.maxWidth;
    final ny = details.localPosition.dy / constraints.maxHeight;

    setState(() {
      _focusPoint = details.localPosition;
    });
    _captureSessionController.setShowExposureSlider(true);

    try {
      // Hardware locks focus and exposure metering onto the tapped point
      await _cameraController.setFocusAndExposurePoint(nx, ny);
    } catch (_) {}

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
    try {
      await _cameraController.setFlash(_captureControls.flashMode);
    } catch (_) {}
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
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) setState(() => _showShutterFlash = false);
    });
  }

  Future<void> _takePhoto() async {
    if (!_cameraController.isInitialized || _isEncrypting) return;

    _triggerShutterFlash();

    _captureSessionController.setEncrypting(
      true,
      label: context.l10n.cameraEncryptingPhotoLabel,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final name = await _vaultService.nextAvailableName(isPhoto: true);
      final virtualPath = _vaultService.buildVirtualPath(name);

      await _cameraController.setOrientationDegrees(
        _computeDeviceRotationDegrees(),
      );

      final result = await _cameraController.takePhoto(
        volId: widget.container.volId,
        virtualPath: virtualPath,
      );

      if (result.success) {
        await _vaultService.finalizeVaultWrite(virtualPath);
        if (mounted) {
          Navigator.pop(context, (savedName: name, isVideo: false));
        }
      } else {
        if (mounted) {
          _showErrorToast(
            result.error ?? context.l10n.cameraPhotoCaptureFailedMessage,
          );
        }
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

    _captureSessionController.setEncrypting(
      true,
      label: context.l10n.cameraEncryptingVideoLabel,
    );
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final result = await _cameraController.stopVideoRecording();

      final elapsedMs = startedAt == null
          ? 9999
          : DateTime.now().difference(startedAt).inMilliseconds;
      if (elapsedMs < 500) {
        if (mounted) {
          _showErrorToast(context.l10n.cameraRecordingTooShortMessage);
        }
        return;
      }

      if (result.success) {
        if (_currentRecordingPath != null) {
          await _vaultService.finalizeVaultWrite(_currentRecordingPath!);
        }
        if (mounted) {
          Navigator.pop(context, (
            savedName: _currentRecordingName,
            isVideo: true,
          ));
        }
      } else {
        if (mounted) {
          _showErrorToast(
            result.error ?? context.l10n.cameraCouldNotSaveRecordingMessage,
          );
        }
      }
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
      if (mounted) _captureSessionController.setEncrypting(false);
    }
  }

  void _showErrorToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  @override
  Widget build(BuildContext context) {
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
    return PopScope(
      canPop: !_isRecording && !_isEncrypting && !_isCountingDown,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_isInitialized && _cameraController.textureId != null)
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isRotated =
                      _cameraController.sensorOrientation % 180 != 0;

                  return GestureDetector(
                    onScaleStart: (_) => _baseZoom = _currentZoom,
                    onScaleUpdate: (d) async {
                      double target = (_baseZoom * d.scale).clamp(
                        _minZoom,
                        _maxZoom,
                      );
                      if (target != _currentZoom) {
                        _captureSessionController.setZoom(target);
                        try {
                          await _cameraController.setZoom(target);
                        } catch (_) {}
                      }
                    },
                    onTapDown: (details) => _onTapToFocus(details, constraints),
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1 / _selectedAspectRatio,
                        child: ClipRect(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: isRotated
                                  ? _cameraController.previewHeight.toDouble()
                                  : _cameraController.previewWidth.toDouble(),
                              height: isRotated
                                  ? _cameraController.previewWidth.toDouble()
                                  : _cameraController.previewHeight.toDouble(),
                              child: Texture(
                                textureId: _cameraController.textureId!,
                              ),
                            ),
                          ),
                        ),
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
                try {
                  await _cameraController.setExposureOffset(val);
                } catch (_) {}
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
                  unawaited(_cameraController.setFlash(nextMode));
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

            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showShutterFlash ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 60),
                child: Container(color: Colors.black),
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

  Widget _buildBottomControls() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.black54, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.only(bottom: 32, top: 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isRecording && !_isCountingDown) ...[
              CameraLensSelectorBar(
                lenses: _lenses,
                selectedCameraId: _selectedCameraId,
                currentZoom: _currentZoom,
                minZoom: _minZoom,
                maxZoom: _maxZoom,
                iconTurns: _iconTurns,
                onSwitchLens: _switchLens,
                onSetZoom: (zoom) async {
                  _captureSessionController.setZoom(zoom);
                  try {
                    await _cameraController.setZoom(zoom);
                  } catch (_) {}
                },
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 24),
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