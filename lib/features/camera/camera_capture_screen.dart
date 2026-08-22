import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import '../../data/services/vault_engine/vault_explorer_api.dart';
import 'active_recording_registry.dart';
import 'camera_vault_service.dart';
import 'vault_camera_controller.dart';

class CameraCaptureScreen extends StatefulWidget {
  final MountedContainer container;
  final String targetDirPath;

  const CameraCaptureScreen({
    super.key,
    required this.container,
    required this.targetDirPath,
  });

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> with WidgetsBindingObserver {
  late CameraVaultService _vaultService;
  final VaultCameraController _cameraController = VaultCameraController();

  List<NativeCameraLens> _lenses = [];
  String _selectedCameraId = '';
  bool _isInitialized = false;
  bool _isContainerLocked = false;
  bool _isVideoMode = false;
  bool _isRecording = false;
  bool _isEncrypting = false;
  bool _isStartingVideo = false;
  bool _pendingStopAfterStart = false;

  /// Whether "lock vaults on screen lock" was OFF for this container when
  /// the current recording started -- if so, the screen turning off
  /// hands the recording to VaultCameraRecordingService instead of
  /// stopping it. Cached at record-start rather than re-read live so a
  /// mid-recording settings change can't change behavior unpredictably
  /// partway through.
  bool _allowBackgroundRecording = false;

  /// True while VaultCameraRecordingService owns keeping the recording
  /// alive (screen off / app backgrounded, background recording allowed).
  bool _backgroundRecordingActive = false;

  bool _showShutterFlash = false;
  String _flashMode = 'auto';
  String _videoQuality = 'fhd';

  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;

  double _minExposureEv = 0.0;
  double _maxExposureEv = 0.0;
  double _currentExposureEv = 0.0;
  bool _showExposureSlider = false;
  Timer? _exposureHideTimer;
  Offset? _focusPoint;

  int _timerDelaySeconds = 0;
  bool _isCountingDown = false;
  int _countdownValue = 0;

  String _busyLabel = '';
  String _timerText = '00:00';
  DateTime? _recordingStart;
  Timer? _timer;

  String? _permissionError;
  String? _currentRecordingName;
  String? _currentRecordingPath;

  StreamSubscription<({double x, double y, double z})>? _sensorSubscription;
  StreamSubscription<Map<String, dynamic>>? _cameraEventSubscription;
  double _iconTurns = 0.0;

    void _onContainerLockedEvent(int volId) {
    if (volId == widget.container.volId && mounted) {
      setState(() => _isContainerLocked = true);
    }
  }

  /// Fired when the user taps "Stop & save" on the background recording
  /// notification -- the only way to stop a recording that's continuing
  /// with the screen off, since there's no shutter button to tap.
  void _onBackgroundRecordingStopRequestedEvent(int volId) {
    if (volId == widget.container.volId && _isRecording) {
      unawaited(_stopVideoRecording());
    }
  }


  @override
  void initState() {
    VaultExplorerApi.addContainerLockedListener(_onContainerLockedEvent);
    VaultExplorerApi.addBackgroundRecordingStopRequestedListener(_onBackgroundRecordingStopRequestedEvent);
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _vaultService = CameraVaultService(container: widget.container, targetDirPath: widget.targetDirPath);
    WidgetsBinding.instance.addObserver(this);

    _cameraEventSubscription = _cameraController.events.listen(_handleCameraEvent);
    _initCamera();
    _startSensorListener();
  }

  void _handleCameraEvent(Map<String, dynamic> event) {
    if (event['event'] != 'error' || !mounted) return;
    // The camera device dropped out from under us (another app took it,
    // a HAL error, thermal shutdown, etc.) -- the preview would otherwise
    // just sit there frozen with no indication anything went wrong.
    setState(() {
      _isInitialized = false;
      _permissionError = context.l10n.cameraDisconnectedError(event['message'] ?? context.l10n.unknownErrorFallback);
    });
  }

  void _startSensorListener() {
    _sensorSubscription = VaultCameraController.accelerometerEventStream().listen((event) {
      double magnitude = math.sqrt(event.x * event.x + event.y * event.y);
      if (magnitude < 2.0) return;

      double angle = math.atan2(event.x, event.y);
      double turns = angle / (2 * math.pi);
      double snappedTurns = (turns * 4).round() / 4.0;
      if (snappedTurns == -0.5) snappedTurns = 0.5;

      if (_iconTurns != snappedTurns && mounted) {
        setState(() => _iconTurns = snappedTurns);
        _cameraController.setOrientationDegrees(_computeDeviceRotationDegrees());
      }
    });
  }

  int _computeDeviceRotationDegrees() {
    int degrees = ((_iconTurns * 360).round() % 360 + 360) % 360;
    return degrees;
  }

  @override
  void dispose() {
    VaultExplorerApi.removeContainerLockedListener(_onContainerLockedEvent);
    VaultExplorerApi.removeBackgroundRecordingStopRequestedListener(_onBackgroundRecordingStopRequestedEvent);
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _exposureHideTimer?.cancel();
    _sensorSubscription?.cancel();
    _cameraEventSubscription?.cancel();
    unawaited(_cameraController.dispose());
    if (_isRecording) unawaited(vaultExplorerApi.setKeepScreenOn(false));
    ActiveRecordingRegistry.instance.unregister(widget.container.uri);
    if (_backgroundRecordingActive) unawaited(vaultExplorerApi.stopBackgroundRecording());

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
        _initCamera(cameraId: _selectedCameraId.isNotEmpty ? _selectedCameraId : null);
      }
    }
  }

  Future<void> _handleGoingInactive() async {
    if (_isRecording) {
      if (_allowBackgroundRecording) {
        // "Lock vaults on screen lock" is off for this container, so
        // nothing is about to lock it out from under the recording.
        // Hand off to VaultCameraRecordingService -- a foreground service
        // is the only way the OS lets camera/mic access survive once
        // nothing is in the foreground -- and deliberately do NOT close
        // _cameraController here, so the native session and encoder keep
        // running untouched.
        _backgroundRecordingActive = true;
        await vaultExplorerApi.startBackgroundRecording(
          volId: widget.container.volId,
          containerName: widget.container.displayName,
        );
        return;
      }
      // Otherwise the screen turning off is about to lock this container
      // (see handleScreenOff/performAutoLock), so finish and save the
      // recording now rather than let that lock yank it out from under an
      // in-flight write.
      //
      // IMPORTANT: this must be fully awaited BEFORE close() runs below.
      // close() nulls out the session id synchronously and tears the
      // encoder down via releaseEncoder() (no finalize) on the native
      // side; racing it against a not-yet-awaited _stopVideoRecording()
      // was silently dropping the recording (stopVideoRecording() would
      // return "Camera not open" because close() had already run first).
      await _stopVideoRecording();
    }
    await _cameraController.close();
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _isCountingDown = false;
      });
    }
  }

  Future<void> _resumeFromBackgroundRecording() async {
    _backgroundRecordingActive = false;
    await vaultExplorerApi.stopBackgroundRecording();
    // The native session and recorder were never closed while backgrounded,
    // so there's nothing to reinitialize -- the existing preview texture
    // just keeps rendering.
  }

  Future<void> _initCamera({String? cameraId}) async {
    try {
      final hasPerms = await VaultCameraController.hasPermissions();
      if (!hasPerms) {
        final granted = await VaultCameraController.requestPermissions();
        if (!granted) {
          if (mounted) {
            setState(() {
              _isInitialized = false;
              _permissionError = context.l10n.cameraPermissionsRequiredMessage;
            });
          }
          return;
        }
      }

      final info = await _cameraController.open(
        cameraId: cameraId,
        facing: 'back',
        quality: _videoQuality,
      );

      if (!mounted) return;

      setState(() {
        _selectedCameraId = info.cameraId;
        _lenses = info.lenses;
        _minZoom = info.zoomMin;
        _maxZoom = info.zoomMax;
        _currentZoom = 1.0.clamp(_minZoom, _maxZoom);

        _minExposureEv = info.minExposureEv;
        _maxExposureEv = info.maxExposureEv;
        _currentExposureEv = 0.0;

        _isInitialized = true;
        _permissionError = null;
      });

      await _cameraController.setFlash(_flashMode);
      await _cameraController.setZoom(_currentZoom);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _permissionError = context.l10n.cameraErrorMessage('$e');
        });
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_isRecording || _isEncrypting || _isCountingDown || _isStartingVideo || _lenses.length <= 1) return;

    HapticFeedback.lightImpact();

    final currentLens = _lenses.firstWhere(
      (l) => l.cameraId == _selectedCameraId,
      orElse: () => _lenses.first,
    );

    final targetFacing = currentLens.facing == 'back' ? 'front' : 'back';
    final targetLens = _lenses.firstWhere(
      (l) => l.facing == targetFacing,
      orElse: () => _lenses.firstWhere((l) => l.cameraId != _selectedCameraId, orElse: () => currentLens),
    );

    if (targetLens.cameraId != _selectedCameraId) {
      setState(() => _isInitialized = false);
      await _initCamera(cameraId: targetLens.cameraId);
    }
  }

  Future<void> _changeQuality(String quality) async {
    if (_isRecording || _isEncrypting || _isCountingDown || _isStartingVideo || _videoQuality == quality) return;
    setState(() {
      _videoQuality = quality;
      _isInitialized = false;
    });
    await _initCamera(cameraId: _selectedCameraId);
  }

  void _onTapToFocus(TapDownDetails details, BoxConstraints constraints) async {
    if (!_cameraController.isInitialized) return;

    final nx = details.localPosition.dx / constraints.maxWidth;
    final ny = details.localPosition.dy / constraints.maxHeight;

    setState(() {
      _focusPoint = details.localPosition;
      _showExposureSlider = true;
    });

    try {
      await _cameraController.setFocusAndExposurePoint(nx, ny);
    } catch (_) {}

    _exposureHideTimer?.cancel();
    _exposureHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() { _showExposureSlider = false; _focusPoint = null; });
    });
  }

  void _onCaptureClicked() {
    if (_isEncrypting) return;
    HapticFeedback.mediumImpact();

    if (_isCountingDown) {
      setState(() => _isCountingDown = false);
      return;
    }

    if (_isVideoMode) {
      if (_isRecording) {
        _stopVideoRecording();
      } else if (_isStartingVideo) {
        _pendingStopAfterStart = true;
      } else {
        _startVideoRecording();
      }
    } else {
      _timerDelaySeconds > 0 ? _startPhotoCountdownAndCapture() : _takePhoto();
    }
  }

  Future<void> _setVideoMode(bool videoMode) async {
    if (_isRecording || _isEncrypting || _isCountingDown || _isStartingVideo || _isVideoMode == videoMode) return;

    setState(() {
      _isVideoMode = videoMode;
      _flashMode = videoMode ? 'off' : 'auto';
    });
    try {
      await _cameraController.setFlash(_flashMode);
    } catch (_) {}
  }

  Future<void> _startPhotoCountdownAndCapture() async {
    setState(() { _isCountingDown = true; _countdownValue = _timerDelaySeconds; });

    for (int i = _timerDelaySeconds; i > 0; i--) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_isCountingDown) return;
      HapticFeedback.lightImpact();
      setState(() => _countdownValue = i - 1);
    }

    setState(() => _isCountingDown = false);
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

    setState(() { _isEncrypting = true; _busyLabel = context.l10n.cameraEncryptingPhotoLabel; });
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final name = await _vaultService.nextAvailableName(isPhoto: true);
      final virtualPath = _vaultService.buildVirtualPath(name);

      await _cameraController.setOrientationDegrees(_computeDeviceRotationDegrees());

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
        if (mounted) _showErrorToast(result.error ?? context.l10n.cameraPhotoCaptureFailedMessage);
      }
    } finally {
      if (mounted) setState(() => _isEncrypting = false);
    }
  }

  Future<void> _startVideoRecording() async {
    if (!_cameraController.isInitialized || _isEncrypting || _isRecording || _isStartingVideo) return;

    _isStartingVideo = true;

    try {
      // Read this up front (not lazily when the screen actually turns
      // off) so the decision is ready instantly and can't add latency to
      // the screen-off handoff.
      final settings = await AppSettingsService.loadSettings();
      _allowBackgroundRecording = !settings.lockContainersOnScreenLock;

      final name = await _vaultService.nextAvailableName(isPhoto: false);
      final virtualPath = _vaultService.buildVirtualPath(name);

      _currentRecordingName = name;
      _currentRecordingPath = virtualPath;

      await _cameraController.setOrientationDegrees(_computeDeviceRotationDegrees());

      final result = await _cameraController.startVideoRecording(
        volId: widget.container.volId,
        virtualPath: virtualPath,
      );

      if (!result.success) {
        _showErrorToast(result.error ?? context.l10n.cameraRecordingFailedMessage);
        return;
      }

      _recordingStart = DateTime.now();

      if (!mounted) return;
      setState(() { _isRecording = true; _timerText = '00:00'; });
      unawaited(vaultExplorerApi.setKeepScreenOn(true));
      ActiveRecordingRegistry.instance.register(widget.container.uri, _stopVideoRecording);

      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted || _recordingStart == null) return;
        final elapsed = DateTime.now().difference(_recordingStart!).inSeconds;
        setState(() => _timerText = '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}');
      });
    } catch (e) {
      _showErrorToast(context.l10n.cameraRecordingFailedWithReasonMessage('$e'));
    } finally {
      _isStartingVideo = false;
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

    setState(() { _isRecording = false; _isEncrypting = true; _busyLabel = context.l10n.cameraEncryptingVideoLabel; });
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final result = await _cameraController.stopVideoRecording();

      final elapsedMs = startedAt == null ? 9999 : DateTime.now().difference(startedAt).inMilliseconds;
      if (elapsedMs < 500) {
        if (mounted) _showErrorToast(context.l10n.cameraRecordingTooShortMessage);
        return;
      }

      if (result.success) {
        if (_currentRecordingPath != null) {
          await _vaultService.finalizeVaultWrite(_currentRecordingPath!);
        }
        if (mounted) {
          Navigator.pop(context, (savedName: _currentRecordingName, isVideo: true));
        }
      } else {
        if (mounted) _showErrorToast(result.error ?? context.l10n.cameraCouldNotSaveRecordingMessage);
      }
    } catch (e) {
      if (mounted) _showErrorToast(context.l10n.cameraCouldNotSaveRecordingWithReasonMessage('$e'));
    } finally {
      unawaited(vaultExplorerApi.setKeepScreenOn(false));
      ActiveRecordingRegistry.instance.unregister(widget.container.uri);
      if (_backgroundRecordingActive) {
        _backgroundRecordingActive = false;
        unawaited(vaultExplorerApi.stopBackgroundRecording());
      }
      if (mounted) setState(() => _isEncrypting = false);
    }
  }

  void _showErrorToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800)
    );
  }

  Widget _rotated({required Widget child}) {
    return AnimatedRotation(
      turns: _iconTurns,
      alignment: Alignment.center,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutBack,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
        if (_isContainerLocked) {
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
                  final bool isRotated = _cameraController.sensorOrientation % 180 != 0;
                  
                  return GestureDetector(
                    onScaleStart: (_) => _baseZoom = _currentZoom,
                    onScaleUpdate: (d) async {
                      double target = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
                      if (target != _currentZoom) {
                        setState(() => _currentZoom = target);
                        try { await _cameraController.setZoom(target); } catch (_) {}
                      }
                    },
                    onTapDown: (details) => _onTapToFocus(details, constraints),
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
                          child: Texture(textureId: _cameraController.textureId!),
                        ),
                      ),
                    ),
                  );
                },
              )
            else if (_permissionError != null)
              Center(child: Text(_permissionError!, style: const TextStyle(color: Colors.white)))
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),

            if (_showExposureSlider && _focusPoint != null) ...[
              Positioned(
                left: _focusPoint!.dx - 30, top: _focusPoint!.dy - 30,
                child: Container(width: 60, height: 60, decoration: BoxDecoration(border: Border.all(color: Colors.amber, width: 1.5))),
              ),
              if (_minExposureEv < _maxExposureEv)
                Positioned(
                  right: 16, top: MediaQuery.of(context).size.height * 0.3,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.height * 0.4,
                      child: Slider(
                        value: _currentExposureEv, min: _minExposureEv, max: _maxExposureEv, activeColor: Colors.amber,
                        onChanged: (val) async {
                          setState(() => _currentExposureEv = val);
                          try { await _cameraController.setExposureOffset(val); } catch (_) {}
                        },
                      ),
                    ),
                  ),
                ),
            ],

            Positioned(top: 0, left: 0, right: 0, child: _buildTopControls()),
            Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomControls()),

            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showShutterFlash ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 60),
                child: Container(color: Colors.black),
              ),
            ),

            if (_isCountingDown)
              Center(
                child: _rotated(
                  child: Text('$_countdownValue', style: const TextStyle(color: Colors.white, fontSize: 120, shadows: [Shadow(blurRadius: 20)])),
                ),
              ),

            if (_isEncrypting)
              Container(
                color: Colors.black54,
                child: Center(
                  child: _rotated(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 20),
                        Text(_busyLabel, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
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

  Widget _buildTopControls() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black54, Colors.transparent]),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _rotated(
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            if (_isRecording || _isCountingDown)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(20)),
                child: _rotated(
                  child: Text(_timerText, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              )
            else
              Row(
                children: [
                  PopupMenuButton<String>(
                    initialValue: _videoQuality,
                    color: Colors.black87,
                    onSelected: _changeQuality,
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'hd', child: Text('720P (HD)', style: TextStyle(color: Colors.white))),
                      PopupMenuItem(value: 'fhd', child: Text('1080P (FHD)', style: TextStyle(color: Colors.white))),
                      PopupMenuItem(value: 'uhd', child: Text('4K (UHD)', style: TextStyle(color: Colors.white))),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: _rotated(
                        child: Text(_videoQuality.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                  if (!_isVideoMode) ...[
                    _rotated(
                      child: IconButton(
                        icon: Icon(
                          _timerDelaySeconds == 3 ? Icons.timer_3_rounded : _timerDelaySeconds == 10 ? Icons.timer_10_rounded : Icons.timer_off_rounded,
                          color: _timerDelaySeconds > 0 ? Colors.amber : Colors.white,
                        ),
                        onPressed: () => setState(() => _timerDelaySeconds = _timerDelaySeconds == 0 ? 3 : _timerDelaySeconds == 3 ? 10 : 0),
                      ),
                    ),
                    _rotated(
                      child: IconButton(
                        icon: Icon(
                          _flashMode == 'auto' ? Icons.flash_auto_rounded : (_flashMode == 'on' || _flashMode == 'torch') ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          color: _flashMode == 'off' ? Colors.white : Colors.amber,
                        ),
                        onPressed: () {
                          final nextMode = _flashMode == 'auto' ? 'on' : _flashMode == 'on' ? 'off' : 'auto';
                          setState(() => _flashMode = nextMode);
                          _cameraController.setFlash(nextMode);
                        },
                      ),
                    ),
                  ]
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomSelector() {
    final currentLens = _lenses.firstWhere((l) => l.cameraId == _selectedCameraId, orElse: () => _lenses.firstOrNull ?? const NativeCameraLens(cameraId: '', facing: 'back', isLogical: false, zoomMin: 1.0, zoomMax: 1.0));
    final isBackCamera = currentLens.facing == 'back';

    final List<({double zoom, String? switchCameraId})> options = [];

    if (isBackCamera) {
      final backLenses = _lenses.where((l) => l.facing == 'back').toList();
      if (backLenses.length > 1) {
        for (final lens in backLenses) {
          options.add((zoom: lens.relativeZoom, switchCameraId: lens.cameraId));
        }
      } else {
        if (_minZoom <= 0.6) options.add((zoom: _minZoom, switchCameraId: null));
        if (_minZoom <= 1.0 && _maxZoom >= 1.0) options.add((zoom: 1.0, switchCameraId: null));
        if (_maxZoom >= 2.0) options.add((zoom: 2.0, switchCameraId: null));
        if (_maxZoom >= 5.0) options.add((zoom: 5.0, switchCameraId: null));
      }
    } else {
      if (_minZoom <= 1.0 && _maxZoom >= 1.0) options.add((zoom: 1.0, switchCameraId: null));
      if (_maxZoom >= 2.0) options.add((zoom: 2.0, switchCameraId: null));
    }

    if (options.length <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: options.map((option) {
        final zoom = option.zoom;
        bool isSelected = false;
        if (option.switchCameraId != null) {
          isSelected = option.switchCameraId == _selectedCameraId;
        } else {
          if (zoom <= 0.8 && _currentZoom < 0.8) isSelected = true;
          else if (zoom > 0.8 && zoom < 1.5 && _currentZoom >= 0.8 && _currentZoom < 1.5) isSelected = true;
          else if (zoom >= 1.5 && zoom < 3.5 && _currentZoom >= 1.5 && _currentZoom < 3.5) isSelected = true;
          else if (zoom >= 3.5 && _currentZoom >= 3.5) isSelected = true;
        }

        String label;
        if ((zoom - 1.0).abs() < 0.05) {
          label = '1x';
        } else if (zoom < 1.0) {
          label = '${zoom.toStringAsFixed(1)}x';
        } else {
          label = '${zoom.round()}x';
        }

        return GestureDetector(
          onTap: () async {
            if (_isRecording || _isEncrypting || _isCountingDown || _isStartingVideo) return;
            HapticFeedback.selectionClick();

            if (option.switchCameraId != null && option.switchCameraId != _selectedCameraId) {
              setState(() => _isInitialized = false);
              try {
                await _cameraController.switchLens(option.switchCameraId!);
                if (mounted) {
                  setState(() {
                    _selectedCameraId = option.switchCameraId!;
                    _currentZoom = _cameraController.zoomMin;
                    _isInitialized = true;
                  });
                }
              } catch (e) {
                // Lens switch can fail if a lens can't be opened as a
                // standalone stream; fall back to re-opening the previously
                // selected lens instead of leaving the screen stuck on a
                // blank/uninitialized preview.
                if (mounted) _showErrorToast(context.l10n.cameraCouldNotSwitchLensMessage);
                await _initCamera(cameraId: _selectedCameraId);
              }
              return;
            }
            setState(() => _currentZoom = zoom);
            try {
              await _cameraController.setZoom(zoom);
            } catch (_) {}
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isSelected ? Colors.amber : Colors.black45,
            ),
            child: _rotated(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBottomControls() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.black54, Colors.transparent]),
      ),
      padding: const EdgeInsets.only(bottom: 32, top: 16),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isRecording && !_isCountingDown) ...[
              _buildZoomSelector(),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _rotated(
                  child: IconButton(
                    icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 32),
                    onPressed: _flipCamera,
                  ),
                ),
                GestureDetector(
                  onTap: _onCaptureClicked,
                  child: Container(
                    width: 76,
                    height: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      width: _isVideoMode && _isRecording ? 30 : 60,
                      height: _isVideoMode && _isRecording ? 30 : 60,
                      decoration: BoxDecoration(
                        color: _isVideoMode ? Colors.red : Colors.white,
                        borderRadius: BorderRadius.circular(_isVideoMode && _isRecording ? 8 : 30),
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
    Widget modeButton({required bool selected, required IconData icon, required VoidCallback onTap}) {
      return GestureDetector(
        onTap: onTap,
        child: _rotated(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? Colors.amber : Colors.black45,
            ),
            child: Icon(icon, color: selected ? Colors.black : Colors.white, size: 20),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        modeButton(
          selected: !_isVideoMode,
          icon: Icons.photo_camera_rounded,
          onTap: () => _setVideoMode(false),
        ),
        const SizedBox(height: 10),
        modeButton(
          selected: _isVideoMode,
          icon: Icons.videocam_rounded,
          onTap: () => _setVideoMode(true),
        ),
      ],
    );
  }
}