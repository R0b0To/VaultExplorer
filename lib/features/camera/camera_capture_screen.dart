import 'dart:async';
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

      // Lock preview stream strictly to portrait to prevent native surface flashing
      try {
        await _controller!.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}

      setState(() { _isInitialized = true; _permissionError = null; });
    } catch (e) {
      if (mounted) setState(() { _isInitialized = false; _permissionError = 'Camera error: $e'; });
    }
  }

  DeviceOrientation _getPhysicalCaptureOrientation() {
    if (_iconTurns == 0.25) return DeviceOrientation.landscapeLeft;
    if (_iconTurns == -0.25) return DeviceOrientation.landscapeRight;
    if (_iconTurns == 0.5) return DeviceOrientation.portraitDown;
    return DeviceOrientation.portraitUp;
  }

  Future<void> _flipCamera() async {
    if (_isRecording || _isEncrypting || _isCountingDown || _cameras.length <= 1) return;
    HapticFeedback.lightImpact();

    final currentLens = _cameras[_selectedCameraIndex].lensDirection;
    final targetLens = currentLens == CameraLensDirection.back 
        ? CameraLensDirection.front 
        : CameraLensDirection.back;

    final targetIndex = _cameras.indexWhere((c) => c.lensDirection == targetLens);

    if (targetIndex != -1) {
      setState(() => _isInitialized = false);
      await _controller?.dispose();
      await _initCamera(cameraIndex: targetIndex);
    }
  }

  Future<void> _changeResolution(ResolutionPreset preset) async {
    if (_isRecording || _isEncrypting || _isCountingDown || _resolutionPreset == preset) return;
    setState(() { _resolutionPreset = preset; _isInitialized = false; });
    await _controller?.dispose();
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
      _isRecording ? _stopVideoRecording() : _startVideoRecording();
    } else {
      _timerDelaySeconds > 0 ? _startPhotoCountdownAndCapture() : _takePhoto();
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

  Future<void> _takePhoto() async {
    if (_controller == null || _isEncrypting) return;
    
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
    if (_controller == null || _isEncrypting) return;
    try {
      try {
        await _controller!.lockCaptureOrientation(_getPhysicalCaptureOrientation());
      } catch (_) {}

      await _controller!.startVideoRecording();
      _recordingStart = DateTime.now();
      setState(() { _isRecording = true; _timerText = '00:00'; });

      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (!mounted || _recordingStart == null) return;
        final elapsed = DateTime.now().difference(_recordingStart!).inSeconds;
        setState(() => _timerText = '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}');
      });
    } catch (e) {
      _showErrorToast('Recording failed: $e');
    }
  }

  Future<void> _stopVideoRecording() async {
    if (_controller == null || !_isRecording) return;
    _timer?.cancel();
    
    setState(() { _isRecording = false; _isEncrypting = true; _busyLabel = 'Encrypting video…'; });
    await Future.delayed(const Duration(milliseconds: 50));

    try {
      final video = await _controller!.stopVideoRecording();
      final result = await _vaultService.saveToVault(video, false);
      if (mounted) {
        result.error == null 
            ? Navigator.pop(context, (savedName: result.savedName, isVideo: true)) 
            : _showErrorToast(result.error!);
      }
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
    List<double> options = [];
    
    // Check if Ultra-Wide lens (0.5x or 0.6x) is supported by hardware
    if (_minZoom <= 0.6) options.add(_minZoom);
    
    // 1.0x Main Lens
    if (_minZoom <= 1.0 && _maxZoom >= 1.0) options.add(1.0);
    
    // Telephoto / Zoom Lenses
    if (_maxZoom >= 2.0) options.add(2.0);
    if (_maxZoom >= 5.0) options.add(5.0);

    // If no multi-zoom capability reported, don't show selector
    if (options.length <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: options.map((zoom) {
        // Highlight logic matching current zoom level
        bool isSelected = false;
        if (zoom <= 0.6 && _currentZoom < 0.8) isSelected = true;
        else if (zoom == 1.0 && _currentZoom >= 0.8 && _currentZoom < 1.5) isSelected = true;
        else if (zoom == 2.0 && _currentZoom >= 1.5 && _currentZoom < 3.5) isSelected = true;
        else if (zoom == 5.0 && _currentZoom >= 3.5) isSelected = true;

        String label = zoom == 1.0 ? '1x' : zoom < 1.0 ? '${zoom.toStringAsFixed(1)}x' : '${zoom.toInt()}x';

        return GestureDetector(
          onTap: () async {
            HapticFeedback.selectionClick();
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
                    onTap: () => setState(() { _isVideoMode = false; _flashMode = FlashMode.auto; }),
                    child: Text('PHOTO', style: TextStyle(color: !_isVideoMode ? Colors.amber : Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  const SizedBox(width: 32),
                  GestureDetector(
                    onTap: () => setState(() { _isVideoMode = true; _flashMode = FlashMode.off; }),
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
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
                    padding: const EdgeInsets.all(4),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      decoration: BoxDecoration(
                        color: _isVideoMode ? Colors.red : Colors.white,
                        borderRadius: BorderRadius.circular(_isVideoMode && _isRecording ? 12 : 40),
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