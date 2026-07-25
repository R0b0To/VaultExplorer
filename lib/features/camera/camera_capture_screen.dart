import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

import 'camera_vault_service.dart';

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
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _selectedCameraIndex = 0;

  bool _isInitialized = false;
  bool _isVideoMode = false;
  bool _isRecording = false;
  bool _isEncrypting = false;

  // Guards the async window between tapping "record" and the native side
  // actually confirming the recording has started, so a rapid second tap
  // can't fire a duplicate startVideoRecording() call or get silently lost.
  bool _isStartingVideo = false;
  bool _pendingStopAfterStart = false;

  bool _showShutterFlash = false;

  // Extra back-facing lenses (e.g. ultra-wide/telephoto) reported by the
  // device, and each one's own native zoom range, used to build the lens
  // selector pills below.
  List<int> _backCameraIndices = [];
  final Map<int, ({double min, double max})> _lensZoomRanges = {};
  bool _lensRangesProbed = false;

  FlashMode _flashMode = FlashMode.auto;
  ResolutionPreset _resolutionPreset = ResolutionPreset.max;
  
  double _minZoom = 1.0, _maxZoom = 1.0, _currentZoom = 1.0, _baseZoom = 1.0;
  double _minExposure = 0.0, _maxExposure = 0.0, _currentExposure = 0.0;
  
  bool _showExposureSlider = false;
  Timer? _exposureHideTimer;
  Offset? _focusPoint;

  int _timerDelaySeconds = 0;
  bool _isCountingDown = false;
  int _countdownValue = 0;

  String _busyLabel = 'Encrypting…';
  String _timerText = '00:00';
  DateTime? _recordingStart;
  Timer? _timer;
  String? _permissionError;

  // --- SENSOR STATE ---
  StreamSubscription<AccelerometerEvent>? _sensorSubscription;
  double _iconTurns = 0.0; 
  int _eventCount = 0;

  @override
  void initState() {
    super.initState();
    
    // Lock app system UI strictly to portrait
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _vaultService = CameraVaultService(container: widget.container, targetDirPath: widget.targetDirPath);
    WidgetsBinding.instance.addObserver(this);
    
    _initCamera();
    _startSensorListener();
  }

  void _startSensorListener() {
    _sensorSubscription = accelerometerEventStream().listen((event) {
      _eventCount++;
      double magnitude = math.sqrt(event.x * event.x + event.y * event.y);
      if (magnitude < 2.0) return; 

      double angle = math.atan2(event.x, event.y); 
      double turns = angle / (2 * math.pi);
      double snappedTurns = (turns * 4).round() / 4.0;
      if (snappedTurns == -0.5) snappedTurns = 0.5;

      if (_iconTurns != snappedTurns && mounted) {
        setState(() => _iconTurns = snappedTurns);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _exposureHideTimer?.cancel();
    _controller?.dispose();
    _sensorSubscription?.cancel();

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      if (_isRecording) _stopVideoRecording();
      _controller!.dispose();
      setState(() { _isInitialized = false; _isCountingDown = false; });
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(cameraIndex: _selectedCameraIndex);
    }
  }

  // CameraController.dispose() resolves as soon as the teardown request is
  // sent to the platform side - it does NOT wait for the native camera
  // device to actually finish releasing hardware (Android's
  // CameraDevice.close() is asynchronous and can take 1-2s under HAL/driver
  // contention). Opening another camera immediately after dispose() can
  // race that teardown and fail with "Unsupported set of inputs/outputs
  // provided" - especially between a logical multi-camera and one of its
  // physical constituents. Give it a short buffer before proceeding.
  Future<void> _disposeControllerAndWait(CameraController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {
      // CameraX may throw IllegalStateException if the preview surface was
      // never fully initialized (e.g. rapid lens switching).  The controller
      // is being discarded anyway, so swallow the error.
    }
    await Future.delayed(const Duration(milliseconds: 350));
  }

  Future<void> _initCamera({int cameraIndex = 0}) async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) return setState(() => _permissionError = 'No cameras available');

      _selectedCameraIndex = cameraIndex.clamp(0, _cameras.length - 1);
      final camera = _cameras[_selectedCameraIndex];

      CameraController controller;
      try {
        controller = CameraController(camera, _resolutionPreset, enableAudio: true);
        await controller.initialize();
      } catch (e) {
        controller = CameraController(camera, _resolutionPreset, enableAudio: false);
        await controller.initialize();
      }

      _controller = controller;
      if (!mounted) return;

      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = await controller.getMaxZoomLevel();
      
      // Default to 1.0x or min zoom if 1.0x is not available
      _currentZoom = 1.0.clamp(_minZoom, _maxZoom);
      await controller.setZoomLevel(_currentZoom);

      _minExposure = await controller.getMinExposureOffset();
      _maxExposure = await controller.getMaxExposureOffset();
      
      try { await controller.setFlashMode(_flashMode); } catch (_) {}

      // NOTE: We intentionally do NOT lockCaptureOrientation here.
      // The app UI is already locked to portrait via SystemChrome, which is
      // sufficient for the preview.  Locking the *capture* orientation to
      // portraitUp at init time causes CameraX to write incorrect rotation
      // metadata into recorded videos (portrait video saved as landscape).

      setState(() { _isInitialized = true; _permissionError = null; });

      // Kick off in the background: doesn't block the preview from showing.
      unawaited(_probeLensZoomRanges());
      if (_isVideoMode) {
        unawaited(_controller?.prepareForVideoRecording());
      }
    } catch (e) {
      if (mounted) setState(() { _isInitialized = false; _permissionError = 'Camera error: $e'; });
    }
  }

  // Some devices expose ultra-wide/telephoto lenses as entirely separate
  // CameraDescriptions rather than as an extension of the main lens's zoom
  // range, so getMinZoomLevel()/getMaxZoomLevel() on the active controller
  // alone can't reveal them. We briefly open each additional back-facing
  // camera to read its native zoom range, then close it again, so the lens
  // selector can offer it as a proper "0.5x" style pill.
  Future<void> _probeLensZoomRanges() async {
    if (_lensRangesProbed) return;
    _lensRangesProbed = true;

    // Filter out auxiliary sensors (infrared, depth, ToF) that Android
    // exposes as separate CameraDescriptions but can't produce a usable
    // preview.  They typically share the same zoom range as the main lens
    // and just clutter the pill selector.
    final infraredPattern = RegExp(r'infrared|depth|tof|mono', caseSensitive: false);
    _backCameraIndices = [
      for (int i = 0; i < _cameras.length; i++)
        if (_cameras[i].lensDirection == CameraLensDirection.back &&
            !infraredPattern.hasMatch(_cameras[i].name)) i
    ];

    if (_backCameraIndices.length <= 1) return;

    for (final idx in _backCameraIndices) {
      if (idx == _selectedCameraIndex) {
        _lensZoomRanges[idx] = (min: _minZoom, max: _maxZoom);
        continue;
      }
      try {
        final probe = CameraController(_cameras[idx], ResolutionPreset.low, enableAudio: false);
        await probe.initialize();
        final mn = await probe.getMinZoomLevel();
        final mx = await probe.getMaxZoomLevel();
        _lensZoomRanges[idx] = (min: mn, max: mx);
        await _disposeControllerAndWait(probe);
      } catch (_) {
        // Device wouldn't let us open a second camera handle - skip it,
        // the digital zoom pills for the active lens still work fine.
      }
    }
    if (mounted) setState(() {});
  }

  DeviceOrientation _getPhysicalCaptureOrientation() {
    if (_iconTurns == 0.25) return DeviceOrientation.landscapeLeft;
    if (_iconTurns == -0.25) return DeviceOrientation.landscapeRight;
    if (_iconTurns == 0.5) return DeviceOrientation.portraitDown;
    return DeviceOrientation.portraitUp;
  }

  Future<void> _flipCamera() async {
    if (_isRecording || _isEncrypting || _isCountingDown || _isStartingVideo || _cameras.length <= 1) return;
    HapticFeedback.lightImpact();

    final currentLens = _cameras[_selectedCameraIndex].lensDirection;
    final targetLens = currentLens == CameraLensDirection.back 
        ? CameraLensDirection.front 
        : CameraLensDirection.back;

    final targetIndex = _cameras.indexWhere((c) => c.lensDirection == targetLens);

    if (targetIndex != -1) {
      setState(() => _isInitialized = false);
      await _disposeControllerAndWait(_controller);
      await _initCamera(cameraIndex: targetIndex);
    }
  }

  Future<void> _changeResolution(ResolutionPreset preset) async {
    if (_isRecording || _isEncrypting || _isCountingDown || _isStartingVideo || _resolutionPreset == preset) return;
    setState(() { _resolutionPreset = preset; _isInitialized = false; });
    await _disposeControllerAndWait(_controller);
    await _initCamera(cameraIndex: _selectedCameraIndex);
  }

  void _onTapToFocus(TapDownDetails details, BoxConstraints constraints) async {
    if (_controller == null || !_isInitialized) return;
    
    final offset = Offset(details.localPosition.dx / constraints.maxWidth, details.localPosition.dy / constraints.maxHeight);
    setState(() { _focusPoint = details.localPosition; _showExposureSlider = true; });

    try {
      await _controller!.setFocusPoint(offset);
      await _controller!.setExposurePoint(offset);
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
        // A start request is still being confirmed by the camera - remember
        // that the user wants to stop, and honor it the instant recording
        // actually begins, instead of firing a second start call now.
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
      _flashMode = videoMode ? FlashMode.off : FlashMode.auto;
    });
    try {
      await _controller?.setFlashMode(_flashMode);
    } catch (_) {}

    if (videoMode) {
      // This is the expensive step (reconfiguring the capture session to add
      // a video output) - doing it now, while the user is looking at the
      // mode toggle, matches how the stock camera app behaves. Without this,
      // the same delay happens later, right after pressing record.
      try {
        await _controller?.prepareForVideoRecording();
      } catch (_) {}
    }
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
    if (_controller == null || _isEncrypting) return;

    _triggerShutterFlash();
    setState(() { _isEncrypting = true; _busyLabel = 'Encrypting photo…'; });
    await Future.delayed(const Duration(milliseconds: 50)); 

    try {
      try {
        await _controller!.lockCaptureOrientation(_getPhysicalCaptureOrientation());
      } catch (_) {}

      final image = await _controller!.takePicture();
      final result = await _vaultService.saveToVault(image, true);
      if (mounted) {
        result.error == null 
            ? Navigator.pop(context, (savedName: result.savedName, isVideo: false)) 
            : _showErrorToast(result.error!);
      }
    } finally {
      if (mounted) setState(() => _isEncrypting = false);
    }
  }

  Future<void> _startVideoRecording() async {
    if (_controller == null || _isEncrypting || _isRecording || _isStartingVideo) return;

    _isStartingVideo = true;
    try {
      try {
        await _controller!.lockCaptureOrientation(_getPhysicalCaptureOrientation());
      } catch (_) {}

      // If this hasn't already happened at mode-switch time (e.g. the very
      // first recording after opening the screen), make sure the session is
      // ready before asking the native side to start writing frames.
      try {
        await _controller!.prepareForVideoRecording();
      } catch (_) {}

      await _controller!.startVideoRecording();
      _recordingStart = DateTime.now();
      if (!mounted) return;
      setState(() { _isRecording = true; _timerText = '00:00'; });

      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted || _recordingStart == null) return;
        final elapsed = DateTime.now().difference(_recordingStart!).inSeconds;
        setState(() => _timerText = '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}');
      });
    } catch (e) {
      _showErrorToast('Recording failed: $e');
    } finally {
      _isStartingVideo = false;
      // Honor a stop that was tapped while we were still starting up.
      if (_pendingStopAfterStart) {
        _pendingStopAfterStart = false;
        if (_isRecording) _stopVideoRecording();
      }
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_controller == null || !_isRecording) return;
    _timer?.cancel();

    final startedAt = _recordingStart;
    _recordingStart = null;
    setState(() { _isRecording = false; _isEncrypting = true; _busyLabel = 'Encrypting video…'; });
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final video = await _controller!.stopVideoRecording();

      // Reset so the next recording picks up the then-current orientation.
      try { await _controller!.unlockCaptureOrientation(); } catch (_) {}

      // A start/stop fired back-to-back can hand us a file the encoder
      // never actually got frames into. Discard it instead of trying (and
      // failing) to save something that was never really recorded.
      final elapsedMs = startedAt == null ? 9999 : DateTime.now().difference(startedAt).inMilliseconds;
      if (elapsedMs < 500) {
        try {
          final cleanPath = video.path.startsWith('file://') ? Uri.parse(video.path).path : video.path;
          await File(cleanPath).delete();
        } catch (_) {}
        if (mounted) _showErrorToast('Recording was too short to save');
        return;
      }

      final result = await _vaultService.saveToVault(video, false);
      if (mounted) {
        result.error == null 
            ? Navigator.pop(context, (savedName: result.savedName, isVideo: true)) 
            : _showErrorToast(result.error!);
      }
    } catch (e) {
      if (mounted) _showErrorToast('Could not save recording: $e');
    } finally {
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
    return PopScope(
      canPop: !_isRecording && !_isEncrypting && !_isCountingDown,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Camera Viewfinder
            if (_isInitialized && _controller != null)
              LayoutBuilder(
                builder: (context, constraints) {
                  return GestureDetector(
                    onScaleStart: (_) => _baseZoom = _currentZoom,
                    onScaleUpdate: (d) async {
                      double target = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);
                      if (target != _currentZoom) {
                        setState(() => _currentZoom = target);
                        try { await _controller!.setZoomLevel(target); } catch (_) {}
                      }
                    },
                    onTapDown: (details) => _onTapToFocus(details, constraints),
                    child: Center(child: CameraPreview(_controller!)),
                  );
                },
              )
            else if (_permissionError != null)
              Center(child: Text(_permissionError!, style: const TextStyle(color: Colors.white)))
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),

            // 2. Focus & Exposure UI
            if (_showExposureSlider && _focusPoint != null) ...[
              Positioned(
                left: _focusPoint!.dx - 30, top: _focusPoint!.dy - 30,
                child: Container(width: 60, height: 60, decoration: BoxDecoration(border: Border.all(color: Colors.amber, width: 1.5))),
              ),
              Positioned(
                right: 16, top: MediaQuery.of(context).size.height * 0.3,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.height * 0.4,
                    child: Slider(
                      value: _currentExposure, min: _minExposure, max: _maxExposure, activeColor: Colors.amber,
                      onChanged: (val) async {
                        setState(() => _currentExposure = val);
                        try { await _controller?.setExposureOffset(val); } catch (_) {}
                      },
                    ),
                  ),
                ),
              ),
            ],

            // 3. Stable Single-Layout UI (Top/Bottom anchored)
            Positioned(top: 0, left: 0, right: 0, child: _buildTopControls()),
            Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomControls()),

            // 3b. Shutter flash - brief black flicker mimicking a physical shutter
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showShutterFlash ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 60),
                child: Container(color: Colors.black),
              ),
            ),

            // 4. Overlays
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
                  PopupMenuButton<ResolutionPreset>(
                    initialValue: _resolutionPreset,
                    color: Colors.black87,
                    onSelected: _changeResolution,
                    itemBuilder: (context) => ResolutionPreset.values.reversed.map((res) {
                      return PopupMenuItem(value: res, child: Text(res.name.toUpperCase(), style: const TextStyle(color: Colors.white)));
                    }).toList(),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: _rotated(
                        child: Text(_resolutionPreset.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                          _flashMode == FlashMode.auto ? Icons.flash_auto_rounded : (_flashMode == FlashMode.always || _flashMode == FlashMode.torch) ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          color: _flashMode == FlashMode.off ? Colors.white : Colors.amber,
                        ),
                        onPressed: () => setState(() {
                          _flashMode = _flashMode == FlashMode.auto ? FlashMode.always : _flashMode == FlashMode.always ? FlashMode.off : FlashMode.auto;
                          _controller?.setFlashMode(_flashMode);
                        }),
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

  // --- CAMERA LENS / ZOOM SELECTOR PILLS ---
  Widget _buildZoomSelector() {
    final isBackCamera = _cameras.isNotEmpty && _cameras[_selectedCameraIndex].lensDirection == CameraLensDirection.back;

    // Each option is either a plain digital-zoom step on the active lens
    // (cameraIndex == null), or a switch to a genuinely separate physical
    // lens (e.g. an ultra-wide camera the device exposes as its own
    // CameraDescription rather than as part of the main lens's zoom range).
    final List<({double zoom, int? cameraIndex})> options = [];

    if (isBackCamera && _backCameraIndices.length > 1 && _lensZoomRanges.isNotEmpty) {
      final sortedLenses = _backCameraIndices.where((i) => _lensZoomRanges.containsKey(i)).toList()
        ..sort((a, b) => _lensZoomRanges[a]!.min.compareTo(_lensZoomRanges[b]!.min));

      // Deduplicate lenses that report the same min-zoom (e.g. main + depth
      // sensor both at 1.0x).  Prefer the currently active camera, otherwise
      // the first (lowest-index) one.
      final seenZooms = <double>{};
      for (final idx in sortedLenses) {
        final z = _lensZoomRanges[idx]!.min;
        if (seenZooms.contains(z)) {
          // Only replace the existing entry if *this* index is the active one.
          if (idx == _selectedCameraIndex) {
            options.removeWhere((o) => o.zoom == z && o.cameraIndex != null);
          } else {
            continue;
          }
        }
        seenZooms.add(z);
        options.add((zoom: z, cameraIndex: idx));
      }
      // Extra digital reach on top of whichever lens is active, if it has it.
      if (_maxZoom >= 2.0 && !options.any((o) => o.zoom == 2.0)) {
        options.add((zoom: 2.0, cameraIndex: null));
      }
      if (_maxZoom >= 5.0) options.add((zoom: 5.0, cameraIndex: null));
    } else {
      // Single-lens device (or front camera): fall back to plain digital zoom.
      if (_minZoom <= 0.6) options.add((zoom: _minZoom, cameraIndex: null));
      if (_minZoom <= 1.0 && _maxZoom >= 1.0) options.add((zoom: 1.0, cameraIndex: null));
      if (_maxZoom >= 2.0) options.add((zoom: 2.0, cameraIndex: null));
      if (_maxZoom >= 5.0) options.add((zoom: 5.0, cameraIndex: null));
    }

    // If there's nothing to switch between, don't show the selector
    if (options.length <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: options.map((option) {
        final zoom = option.zoom;
        // Highlight logic matching current zoom level
        bool isSelected = false;
        if (zoom <= 0.8 && _currentZoom < 0.8) isSelected = true;
        else if (zoom > 0.8 && zoom < 1.5 && _currentZoom >= 0.8 && _currentZoom < 1.5) isSelected = true;
        else if (zoom >= 1.5 && zoom < 3.5 && _currentZoom >= 1.5 && _currentZoom < 3.5) isSelected = true;
        else if (zoom >= 3.5 && _currentZoom >= 3.5) isSelected = true;

        String label = zoom == 1.0 ? '1x' : zoom < 1.0 ? '${zoom.toStringAsFixed(1)}x' : '${zoom.toInt()}x';

        return GestureDetector(
          onTap: () async {
            if (_isRecording || _isEncrypting || _isCountingDown || _isStartingVideo) return;
            HapticFeedback.selectionClick();

            if (option.cameraIndex != null && option.cameraIndex != _selectedCameraIndex) {
              // Switching to a different physical lens - re-init the controller.
              setState(() => _isInitialized = false);
              await _disposeControllerAndWait(_controller);
              await _initCamera(cameraIndex: option.cameraIndex!);
              if (mounted) setState(() => _currentZoom = _minZoom);
              return;
            }

            setState(() => _currentZoom = zoom);
            try {
              await _controller?.setZoomLevel(zoom);
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
            // 1. Lens / Zoom Selector Pills (0.5x, 1x, 2x, 5x)
            if (!_isRecording && !_isCountingDown) ...[
              _buildZoomSelector(),
              const SizedBox(height: 16),
            ],

            // 2. Mode Selectors (PHOTO / VIDEO - Unrotated as requested)
            if (!_isRecording && !_isCountingDown)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => _setVideoMode(false),
                    child: Text('PHOTO', style: TextStyle(color: !_isVideoMode ? Colors.amber : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(width: 32),
                  GestureDetector(
                    onTap: () => _setVideoMode(true),
                    child: Text('VIDEO', style: TextStyle(color: _isVideoMode ? Colors.amber : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ],
              ),
            
            const SizedBox(height: 24),
            
            // 3. Shutter Area
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
                const SizedBox(width: 48), // Spacer offsets flip icon to center shutter
              ],
            ),
          ],
        ),
      ),
    );
  }
}