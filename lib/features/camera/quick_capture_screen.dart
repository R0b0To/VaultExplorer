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
import 'package:vaultexplorer/features/share_import/share_destination_sheet.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'camera_vault_service.dart';
import 'camera_capture_controls_controller.dart';
import 'camera_capture_session_controller.dart';
import 'camera_ui_components.dart';
import 'vault_camera_controller.dart';

const _quickCaptureControlsKey = 'quick_capture';

class QuickCaptureScreen extends ConsumerStatefulWidget {
  const QuickCaptureScreen({super.key});

  @override
  ConsumerState<QuickCaptureScreen> createState() =>
      _QuickCaptureScreenState();
}

enum _Phase { camera, reviewing, saving }

class _QuickCaptureScreenState extends ConsumerState<QuickCaptureScreen>
    with WidgetsBindingObserver {
  late final VaultFileIoApi _fileIoApi;
  late final VaultLifecycleApi _lifecycleApi;
  late final VaultEngineEvents _engineEvents;
  late final QuickCaptureApi _quickCaptureApi;
  late final VaultCameraController _cameraController;

  _Phase _phase = _Phase.camera;
  ScratchpadSession? _pendingScratchpad;
  bool? _pendingIsVideo;
  String? _saveError;

  bool _isRecording = false;
  bool _pendingStopAfterStart = false;
  bool _showShutterFlash = false;
  double _selectedAspectRatio = 4 / 3; // 4:3 (1.333), 16:9 (1.777), 1:1 (1.0)
  double _baseZoom = 1.0;
  Timer? _exposureHideTimer;
  Offset? _focusPoint;

  DateTime? _recordingStart;
  Timer? _timer;

  StreamSubscription<({double x, double y, double z})>? _sensorSubscription;
  StreamSubscription<Map<String, dynamic>>? _cameraEventSubscription;
  double _iconTurns = 0.0;

  CameraCaptureControlsState get _captureControls =>
      ref.read(cameraCaptureControlsProvider(_quickCaptureControlsKey));

  CameraCaptureControls get _captureControlsController =>
      ref.read(cameraCaptureControlsProvider(_quickCaptureControlsKey).notifier);

  CameraCaptureSessionState get _captureSession =>
      ref.read(cameraCaptureSessionProvider(_quickCaptureControlsKey));

  CameraCaptureSession get _captureSessionController =>
      ref.read(cameraCaptureSessionProvider(_quickCaptureControlsKey).notifier);

  bool get _isInitialized => _captureSession.isInitialized;
  String get _selectedCameraId => _captureSession.selectedCameraId;
  List<NativeCameraLens> get _lenses => _captureSession.lenses;
  bool get _isEncrypting => _captureSession.isEncrypting;
  bool get _isStartingVideo => _captureSession.isStartingVideo;
  String? get _permissionError => _captureSession.permissionError;
  bool get _isCountingDown => _captureSession.countdownValue > 0 && _captureSession.isCountingDown;
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

  @override
  void initState() {
    super.initState();
    _fileIoApi = ref.read(vaultFileIoApiProvider);
    _lifecycleApi = ref.read(vaultLifecycleApiProvider);
    _engineEvents = ref.read(vaultEngineEventsProvider);
    _quickCaptureApi = ref.read(quickCaptureApiProvider);
    _cameraController = VaultCameraController(_engineEvents);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

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
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _exposureHideTimer?.cancel();
    _sensorSubscription?.cancel();
    _cameraEventSubscription?.cancel();
    unawaited(_cameraController.dispose());

    if (_isRecording) {
      unawaited(_fileIoApi.setKeepScreenOn(false));
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
    if (!_cameraController.isInitialized) return;
    if (_phase != _Phase.camera) return;

    if (state == AppLifecycleState.inactive) {
      unawaited(_handleGoingInactive());
    } else if (state == AppLifecycleState.resumed && _phase == _Phase.camera) {
      _initCamera(
        cameraId: _selectedCameraId.isNotEmpty ? _selectedCameraId : null,
      );
    }
  }

  Future<void> _handleGoingInactive() async {
    if (_isRecording) {
      await _stopVideoRecording();
    }
    await _cameraController.close();
    if (mounted && _phase == _Phase.camera) {
      _captureSessionController.setUninitialized();
    }
  }

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

    setState(() => _focusPoint = details.localPosition);
    _captureSessionController.setShowExposureSlider(true);

    try {
      await _cameraController.setFocusAndExposurePoint(nx, ny);
    } catch (_) {}

    _exposureHideTimer?.cancel();
    _exposureHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _captureSessionController.setShowExposureSlider(false);
        setState(() => _focusPoint = null);
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
      final session = await _quickCaptureApi.openSession();
      if (session == null) {
        _showErrorToast(context.l10n.cameraPhotoCaptureFailedMessage);
        return;
      }

      await _cameraController.setOrientationDegrees(
        _computeDeviceRotationDegrees(),
      );

      final result = await _cameraController.takePhotoToScratchpad(
        sessionToken: session.sessionToken,
        scratchpadPath: session.scratchpadPath,
      );

      if (result.success) {
        setState(() {
          _pendingScratchpad = session;
          _pendingIsVideo = false;
          _phase = _Phase.reviewing;
        });
      } else {
        await _quickCaptureApi.discardSession(session.sessionToken);
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
      final session = await _quickCaptureApi.openSession();
      if (session == null) {
        _showErrorToast(context.l10n.cameraRecordingFailedMessage);
        return;
      }
      _pendingScratchpad = session;
      _pendingIsVideo = true;

      await _cameraController.setOrientationDegrees(
        _computeDeviceRotationDegrees(),
      );

      final result = await _cameraController.startVideoRecordingToScratchpad(
        sessionToken: session.sessionToken,
        scratchpadPath: session.scratchpadPath,
      );

      if (!result.success) {
        await _quickCaptureApi.discardSession(session.sessionToken);
        _pendingScratchpad = null;
        _pendingIsVideo = null;
        _showErrorToast(
          result.error ?? context.l10n.cameraRecordingFailedMessage,
        );
        return;
      }

      _recordingStart = DateTime.now();
      _isRecording = true;
      if (!mounted) return;
      _captureSessionController.startRecording();
      unawaited(_fileIoApi.setKeepScreenOn(true));

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
    _isRecording = false;

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

      final session = _pendingScratchpad;
      if (elapsedMs < 500 || !result.success || session == null) {
        if (session != null) {
          await _quickCaptureApi.discardSession(session.sessionToken);
        }
        _pendingScratchpad = null;
        _pendingIsVideo = null;
        if (mounted) {
          _showErrorToast(
            elapsedMs < 500
                ? context.l10n.cameraRecordingTooShortMessage
                : (result.error ??
                      context.l10n.cameraCouldNotSaveRecordingMessage),
          );
        }
        return;
      }

      setState(() => _phase = _Phase.reviewing);
    } catch (e) {
      final session = _pendingScratchpad;
      if (session != null) {
        await _quickCaptureApi.discardSession(session.sessionToken);
      }
      _pendingScratchpad = null;
      _pendingIsVideo = null;
      if (mounted) {
        _showErrorToast(
          context.l10n.cameraCouldNotSaveRecordingWithReasonMessage('$e'),
        );
      }
    } finally {
      unawaited(_fileIoApi.setKeepScreenOn(false));
      if (mounted) _captureSessionController.setEncrypting(false);
    }
  }

  Future<void> _onSaveTapped() async {
    final session = _pendingScratchpad;
    final isVideo = _pendingIsVideo;
    if (session == null || isVideo == null) return;

    final destination = await Navigator.push<CryptoDestination>(
      context,
      MaterialPageRoute(builder: (_) => const ShareDestinationSheet()),
    );
    if (destination == null || !mounted) return;
    if (!destination.isVault ||
        destination.container == null ||
        destination.relativePath == null) {
      setState(() => _saveError = context.l10n.cameraCouldNotSaveRecordingMessage);
      return;
    }

    setState(() {
      _phase = _Phase.saving;
      _saveError = null;
    });

    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    final container = destination.container!;
    final vaultService = CameraVaultService(
      container: container,
      targetDirPath: destination.relativePath!,
      fileIoApi: _fileIoApi,
      lifecycleApi: _lifecycleApi,
    );

    try {
      final name = await vaultService.nextAvailableName(isPhoto: !isVideo);
      final virtualPath = vaultService.buildVirtualPath(name);

      final result = await _quickCaptureApi.finalizeSession(
        sessionToken: session.sessionToken,
        volId: container.volId,
        virtualPath: virtualPath,
      );

      if (!result.success) {
        if (mounted) {
          setState(() {
            _phase = _Phase.reviewing;
            _saveError =
                result.error ?? context.l10n.cameraCouldNotSaveRecordingMessage;
          });
        }
        return;
      }

      await vaultService.finalizeVaultWrite(virtualPath);
      _pendingScratchpad = null;
      _pendingIsVideo = null;
      if (mounted) {
        await _quickCaptureApi.showToast(
          context.l10n.quickCaptureSavedToast(name, destination.displayName),
        );
        Navigator.pop(context, (savedName: name, isVideo: isVideo));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.reviewing;
          _saveError = '$e';
        });
      }
    }
  }

  Future<void> _onDiscardTapped() async {
    final session = _pendingScratchpad;
    _pendingScratchpad = null;
    _pendingIsVideo = null;
    if (session != null) {
      await _quickCaptureApi.discardSession(session.sessionToken);
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.camera;
      _saveError = null;
    });
  }

  void _showErrorToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cameraCaptureControlsProvider(_quickCaptureControlsKey));
    ref.watch(cameraCaptureSessionProvider(_quickCaptureControlsKey));

    return PopScope(
      canPop: !_isRecording && !_isEncrypting && !_isCountingDown && _phase != _Phase.saving,
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

            // Exposure focus reticle and slider
            if (_phase == _Phase.camera)
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

            if (_phase == _Phase.camera) ...[
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
                  onClose: () {
                    if (_phase == _Phase.saving) return;
                    Navigator.pop(context);
                  },
                  onVideoQualityChanged: _changeQuality,
                  onPhotoResolutionChanged: _changePhotoResolution,
                  onCycleTimerDelay: _captureControlsController.cycleTimerDelay,
                  onCycleFlashMode: () {
                    final nextMode = _captureControlsController.cyclePhotoFlashMode();
                    unawaited(_cameraController.setFlash(nextMode));
                  },
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildBottomControls(),
              ),
            ] else
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildReviewPanel(),
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

            if (_isEncrypting || _phase == _Phase.saving)
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
                          _phase == _Phase.saving
                              ? (_pendingIsVideo == true
                                  ? context.l10n.cameraEncryptingVideoLabel
                                  : context.l10n.cameraEncryptingPhotoLabel)
                              : _busyLabel,
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
                        color: _captureControls.isVideoMode
                            ? Colors.red
                            : Colors.white,
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

  Widget _buildReviewPanel() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.black54, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _pendingIsVideo == true
                  ? context.l10n.videoCapturedEncrypted
                  : context.l10n.photoCapturedEncrypted,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (_saveError != null) ...[
              const SizedBox(height: 8),
              Text(
                _saveError!,
                style: TextStyle(color: Colors.red.shade300, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _phase == _Phase.saving ? null : _onDiscardTapped,
                    child: Text(context.l10n.discardButton),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _phase == _Phase.saving ? null : _onSaveTapped,
                    child: Text(context.l10n.saveToVaultTitle),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}