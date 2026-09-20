import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

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
import 'vault_camera_controller.dart';

/// A single, fixed key for the capture-controls/session providers this
/// screen uses. CameraCaptureScreen keys these per (container, folder) so
/// separate vault folders remember separate flash/zoom/quality choices;
/// Quick Capture has no folder (or vault) yet when it opens, and there is
/// only ever one Quick Capture task alive at a time (see
/// VaultQuickCaptureActivity's isolated task window), so a single shared
/// key is enough here.
const _quickCaptureControlsKey = 'quick_capture';

/// Camera screen for the Quick Capture entry point (Quick Settings tile /
/// pinned shortcut -- see VaultQuickCaptureActivity). Deliberately takes
/// no MountedContainer: capture starts before any vault has been chosen,
/// straight into an ephemeral-key-encrypted scratchpad file (see
/// docs/architecture.md, "Capture-First + Encrypted Scratchpad"), and
/// only after the shot is taken does the person pick where it goes --
/// reusing ShareDestinationSheet exactly as the Share Sheet import flow
/// does, rather than a second destination-picker UI.
///
/// Shares its camera-open/permission/tap-to-focus/zoom/lens-switch logic
/// with CameraCaptureScreen almost verbatim; the two things that
/// genuinely differ are (1) where captured bytes are written -- a
/// scratchpad instead of a mounted vault -- and (2) what happens after a
/// successful capture -- a save/discard step instead of an immediate
/// pop. Kept as its own screen rather than a `container == null` branch
/// on CameraCaptureScreen so neither screen risks a regression in the
/// other's already-shipped behavior.
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

  bool _showShutterFlash = false;
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
  bool get _isRecording => _captureSession.isRecording;
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
    int degrees = ((_iconTurns * 360).round() % 360 + 360) % 360;
    return degrees;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _exposureHideTimer?.cancel();
    _sensorSubscription?.cancel();
    _cameraEventSubscription?.cancel();
    unawaited(_cameraController.dispose());
    if (_isRecording) unawaited(_fileIoApi.setKeepScreenOn(false));
    // A scratchpad still pending when this screen goes away (back
    // gesture, task swipe-away) is exactly the "cancel/app backgrounded"
    // case from the design notes: wipe it rather than leave it as an
    // orphan for the next launch's sweep to find.
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

  /// Unlike CameraCaptureScreen, Quick Capture never hands a recording
  /// off to VaultCameraRecordingService to keep running with the screen
  /// off -- there's no vault/container to attribute a background
  /// notification to yet, and this entry point is meant for a single
  /// quick grab rather than a long unattended recording. Backgrounding
  /// mid-recording always stops and moves to the save/discard step
  /// instead.
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

  void _onTapToFocus(TapDownDetails details, BoxConstraints constraints) async {
    if (!_cameraController.isInitialized) return;

    final nx = details.localPosition.dx / constraints.maxWidth;
    final ny = details.localPosition.dy / constraints.maxHeight;

    setState(() => _focusPoint = details.localPosition);
    _captureSessionController.setShowExposureSlider(true);

    try {
      await _cameraController.setFocusAndExposurePoint(nx, ny);
    } catch (_) {
      // Reticle/slider already updated above; a failed native call just
      // means this particular tap doesn't take effect on the sensor.
    }

    _exposureHideTimer?.cancel();
    _exposureHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _captureSessionController.setShowExposureSlider(false);
        setState(() => _focusPoint = null);
      }
    });
  }

  void _onCaptureClicked() {
    if (_isEncrypting) return;
    HapticFeedback.mediumImpact();

    if (_captureControls.isVideoMode) {
      if (_isRecording) {
        _stopVideoRecording();
      } else if (!_isStartingVideo) {
        _startVideoRecording();
      }
    } else {
      _takePhoto();
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
    }
  }

  Future<void> _stopVideoRecording() async {
    if (!_cameraController.isInitialized || !_isRecording) return;

    _timer?.cancel();
    final startedAt = _recordingStart;
    _recordingStart = null;

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

  /// Pushes the same destination picker the Share Sheet import flow
  /// uses -- see share_import_flow.dart's presentIncomingShareImport,
  /// which this mirrors -- rather than a second, purpose-built picker.
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
      // Only vault destinations are meaningful here -- unlike a generic
      // share-import, there's no "export a plaintext copy" option for a
      // capture that's never touched plaintext disk in the first place.
      setState(() => _saveError = context.l10n.cameraCouldNotSaveRecordingMessage);
      return;
    }

    setState(() {
      _phase = _Phase.saving;
      _saveError = null;
    });

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
    // The camera session/encoder was left open throughout capture+review
    // (see _stopVideoRecording/_takePhoto -- neither one closes it), so
    // there's nothing to reinitialize here; the preview just keeps
    // rendering, ready for another shot.
  }

  void _showErrorToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
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
    ref.watch(cameraCaptureControlsProvider(_quickCaptureControlsKey));
    ref.watch(cameraCaptureSessionProvider(_quickCaptureControlsKey));

    return PopScope(
      canPop: !_isRecording && !_isEncrypting && _phase != _Phase.saving,
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

            if (_showExposureSlider && _focusPoint != null && _phase == _Phase.camera) ...[
              Positioned(
                left: _focusPoint!.dx - 30,
                top: _focusPoint!.dy - 30,
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.amber, width: 1.5),
                  ),
                ),
              ),
              if (_minExposureEv < _maxExposureEv)
                Positioned(
                  right: 16,
                  top: MediaQuery.of(context).size.height * 0.3,
                  child: RotatedBox(
                    quarterTurns: 3,
                    child: SizedBox(
                      width: MediaQuery.of(context).size.height * 0.4,
                      child: Slider(
                        value: _currentExposureEv,
                        min: _minExposureEv,
                        max: _maxExposureEv,
                        activeColor: Colors.amber,
                        onChanged: (val) async {
                          _captureSessionController.setExposureEv(val);
                          try {
                            await _cameraController.setExposureOffset(val);
                          } catch (_) {}
                        },
                      ),
                    ),
                  ),
                ),
            ],

            if (_phase == _Phase.camera) ...[
              Positioned(top: 0, left: 0, right: 0, child: _buildTopControls()),
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

            if (_isEncrypting || _phase == _Phase.saving)
              Container(
                color: Colors.black54,
                child: Center(
                  child: _rotated(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 20),
                        Text(
                          _phase == _Phase.saving
                              ? context.l10n.cameraEncryptingPhotoLabel
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

  Widget _buildTopControls() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _rotated(
              child: IconButton(
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            if (_isRecording)
              _rotated(
                child: Text(
                  _timerText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Row(
                children: [
                  _rotated(
                    child: IconButton(
                      icon: Icon(
                        _captureControls.flashMode == 'auto'
                            ? Icons.flash_auto_rounded
                            : (_captureControls.flashMode == 'on' ||
                                  _captureControls.flashMode == 'torch')
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        color: _captureControls.flashMode == 'off'
                            ? Colors.white
                            : Colors.amber,
                      ),
                      onPressed: () {
                        final nextMode = _captureControlsController
                            .cyclePhotoFlashMode();
                        unawaited(_cameraController.setFlash(nextMode));
                      },
                    ),
                  ),
                ],
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _rotated(
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
            if (!_isRecording) _buildModeToggle() else const SizedBox(width: 48),
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
        child: _rotated(
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

  /// The "Review & Route" step from the design notes: the captured
  /// photo/video is already complete ciphertext in the scratchpad file
  /// (see ScratchpadChunkWriter.finish) -- there's no plaintext to
  /// preview here any more than the existing in-vault camera flow shows
  /// a preview before saving, so this is a save/discard decision rather
  /// than a played-back review.
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
              _pendingIsVideo == true ? 'Video captured' : 'Photo captured',
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
                    child: const Text('Discard'),
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
                    child: const Text('Save to vault'),
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
