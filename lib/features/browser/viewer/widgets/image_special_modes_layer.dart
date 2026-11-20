import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/metadata/image_metadata_reader.dart';
import 'package:vaultexplorer/features/browser/metadata/metadata_edit_service.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/panorama/device_orientation_sensor.dart';
import 'package:vaultexplorer/features/browser/viewer/panorama/panorama_camera.dart';
import 'package:vaultexplorer/features/browser/viewer/video_playback_manager.dart';

class ImageSpecialModesLayer extends ConsumerStatefulWidget {
  const ImageSpecialModesLayer({
    super.key,
    required this.container,
    required this.fileName,
    required this.showUI,
    required this.motionPhotoActive,
    required this.motionPhotoAutoplay,
    required this.onMotionPhotoChanged,
    required this.onMotionPhotoAutoplayChanged,
    required this.onPanoramaModeChanged,
    required this.playbackManager,
    required this.onToggleUI,
  });

  final MountedContainer container;
  final String fileName;
  final bool showUI;
  final bool motionPhotoActive;
  final bool motionPhotoAutoplay;
  final Future<void> Function(bool active) onMotionPhotoChanged;
  final ValueChanged<bool> onMotionPhotoAutoplayChanged;
  final ValueChanged<bool> onPanoramaModeChanged;
  final VideoPlaybackManager playbackManager;
  final ValueChanged<bool> onToggleUI;

  @override
  ConsumerState<ImageSpecialModesLayer> createState() =>
      _ImageSpecialModesLayerState();
}

class _ImageSpecialModesLayerState
    extends ConsumerState<ImageSpecialModesLayer> {
  static const int _maxPanoramaFileBytes = 128 * 1024 * 1024;
  static const int _panoramaDecodeWidth = 4096;
  static const String _shaderAsset = 'shaders/panorama_viewer.frag';

  static Future<ui.FragmentProgram>? _programLoad;

  /// Gyro mode is remembered for the rest of the session, so flicking through
  /// several 360° photos does not need the toggle every time.
  static bool _lastSensorChoice = false;

  _SpecialImageMetadata _metadata = const _SpecialImageMetadata();
  bool _panoramaActive = false;
  bool _autoPlayRequested = false;
  bool _panoramaLoading = false;
  bool _sensorAvailable = false;
  bool _sensorOn = false;
  String? _panoramaError;
  ui.Image? _panoramaImage;
  ui.FragmentShader? _panoramaShader;
  int _requestToken = 0;
  int _fileSize = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_readMetadata());
    unawaited(_probeSensor());
  }

  Future<void> _probeSensor() async {
    final available = await DeviceOrientationSensor.isAvailable();
    if (!mounted) return;
    setState(() {
      _sensorAvailable = available;
      if (!available) _sensorOn = false;
    });
  }

  void _toggleSensor() {
    setState(() {
      _sensorOn = !_sensorOn;
      _lastSensorChoice = _sensorOn;
    });
  }

  @override
  void didUpdateWidget(covariant ImageSpecialModesLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.container.uri != widget.container.uri ||
        oldWidget.fileName != widget.fileName) {
      _requestToken++;
      _disposePanoramaResources();
      _metadata = const _SpecialImageMetadata();
      _panoramaActive = false;
      _autoPlayRequested = false;
      _panoramaLoading = false;
      _panoramaError = null;
      unawaited(_readMetadata());
    }
    if (oldWidget.motionPhotoAutoplay != widget.motionPhotoAutoplay ||
        oldWidget.fileName != widget.fileName) {
      _maybeAutoPlayMotionPhoto();
    }
  }

  Future<void> _readMetadata() async {
    final token = ++_requestToken;
    try {
      final source = await MetadataEditService(
        ref.read(vaultFileIoApiProvider),
      ).openSource(widget.container, widget.fileName);
      if (source == null) return;
      final directories = await ImageMetadataReader.read(source);
      final parsed = _SpecialImageMetadata.fromDirectories(directories);
      if (!mounted || token != _requestToken) return;
      setState(() {
        _fileSize = source.length;
        _metadata = parsed;
      });
      _maybeAutoPlayMotionPhoto();
    } catch (_) {
      if (!mounted || token != _requestToken) return;
    }
  }

  Future<void> _toggleMotionPhoto() async {
    final shouldPlay = !widget.motionPhotoActive;
    _autoPlayRequested = shouldPlay;
    widget.onMotionPhotoAutoplayChanged(shouldPlay);
    if (_panoramaActive) _leavePanorama();
    await widget.onMotionPhotoChanged(shouldPlay);
  }

  void _maybeAutoPlayMotionPhoto() {
    if (!mounted ||
        !widget.motionPhotoAutoplay ||
        !_metadata.motionPhoto ||
        widget.motionPhotoActive ||
        _autoPlayRequested) {
      return;
    }
    _autoPlayRequested = true;
    unawaited(widget.onMotionPhotoChanged(true));
  }

  Future<void> _togglePanorama() async {
    if (_panoramaActive) {
      _leavePanorama();
      return;
    }
    if (widget.motionPhotoActive) {
      await widget.onMotionPhotoChanged(false);
    }
    await _enterPanorama();
  }

  Future<void> _enterPanorama() async {
    if (_panoramaImage != null && _panoramaShader != null) {
      setState(() {
        _panoramaActive = true;
        _panoramaError = null;
        _sensorOn = _sensorAvailable && _lastSensorChoice;
      });
      widget.onPanoramaModeChanged(true);
      return;
    }

    final token = ++_requestToken;
    setState(() {
      _panoramaActive = true;
      _panoramaLoading = true;
      _panoramaError = null;
      _sensorOn = _sensorAvailable && _lastSensorChoice;
    });
    widget.onPanoramaModeChanged(true);
    ui.Image? decodedImage;
    ui.FragmentShader? shader;
    try {
      final api = ref.read(vaultFileIoApiProvider);
      final size = _fileSize > 0
          ? _fileSize
          : await api.getFileSize(widget.container, widget.fileName);
      if (size <= 0 || size > _maxPanoramaFileBytes) {
        throw StateError('This panorama is too large to open here.');
      }
      final bytes = await api.readMediaFileChunk(
        widget.container,
        widget.fileName,
        0,
        size,
      );
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Could not read this panorama.');
      }

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _panoramaDecodeWidth,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      decodedImage = frame.image;
      final program = await (_programLoad ??= ui.FragmentProgram.fromAsset(
        _shaderAsset,
      ));
      shader = program.fragmentShader();
      if (!mounted || token != _requestToken) {
        decodedImage.dispose();
        shader.dispose();
        return;
      }
      _disposePanoramaResources();
      setState(() {
        _panoramaImage = decodedImage;
        _panoramaShader = shader;
        _panoramaLoading = false;
        _panoramaError = null;
      });
      decodedImage = null;
      shader = null;
    } catch (error) {
      decodedImage?.dispose();
      shader?.dispose();
      if (!mounted || token != _requestToken) return;
      setState(() {
        _panoramaLoading = false;
        _panoramaError = error is StateError
            ? error.message.toString()
            : 'Could not open this panorama.';
      });
    }
  }

  void _leavePanorama() {
    setState(() {
      _panoramaActive = false;
      _panoramaLoading = false;
      _panoramaError = null;
      _sensorOn = false;
    });
    widget.onPanoramaModeChanged(false);
  }

  void _disposePanoramaResources() {
    _panoramaImage?.dispose();
    _panoramaImage = null;
    _panoramaShader?.dispose();
    _panoramaShader = null;
  }

  @override
  void dispose() {
    _requestToken++;
    _disposePanoramaResources();
    super.dispose();
  }

  Widget _buildMotionPhoto() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onToggleUI(!widget.showUI),
        child: ColoredBox(
          color: Colors.black,
          child: ValueListenableBuilder<NativeVideoController?>(
            valueListenable: widget.playbackManager.activeControllerNotifier,
            builder: (context, active, _) {
              final controller = widget.playbackManager.getControllerFor(
                widget.fileName,
              );
              if (controller == null || !identical(active, controller)) {
                return const Center(child: CircularProgressIndicator());
              }
              return ValueListenableBuilder<NativeVideoValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  if (value.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          value.errorDescription.isEmpty
                              ? 'Could not play this motion photo.'
                              : value.errorDescription,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  if (!value.isInitialized || !value.hasRenderedFirstFrame) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final width = value.size.width;
                  final height = value.size.height;
                  if (width <= 0 || height <= 0) {
                    return NativeVideoPlayerView(controller: controller);
                  }
                  return Center(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(
                        width: width,
                        height: height,
                        child: NativeVideoPlayerView(controller: controller),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPanorama() {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onToggleUI(!widget.showUI),
        child: ColoredBox(
          color: Colors.black,
          child: _panoramaLoading
              ? const Center(child: CircularProgressIndicator())
              : _panoramaError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_panoramaError!, textAlign: TextAlign.center),
                  ),
                )
              : _panoramaImage != null && _panoramaShader != null
              ? _PanoramaScene(
                  image: _panoramaImage!,
                  shader: _panoramaShader!,
                  spec: _metadata.panorama!,
                  sensorEnabled: _sensorOn,
                  onTap: () => widget.onToggleUI(!widget.showUI),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _modePill({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? const Color(0xCC38658D) : const Color(0xCC25282B),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showMotionPill = _metadata.motionPhoto && widget.showUI;
    final showPanoramaPill = _metadata.panorama != null && widget.showUI;
    if (!showMotionPill &&
        !showPanoramaPill &&
        !widget.motionPhotoActive &&
        !_panoramaActive) {
      return const SizedBox.shrink();
    }

    final topInset = MediaQuery.paddingOf(context).top;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.motionPhotoActive) _buildMotionPhoto(),
        if (_panoramaActive) _buildPanorama(),
        if (showMotionPill || showPanoramaPill)
          Positioned(
            top: topInset + 72,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showMotionPill)
                    _modePill(
                      label: 'Motion',
                      icon: widget.motionPhotoActive
                          ? Icons.pause
                          : Icons.play_arrow,
                      selected: widget.motionPhotoActive,
                      onTap: _toggleMotionPhoto,
                    ),
                  if (showMotionPill && showPanoramaPill)
                    const SizedBox(width: 8),
                  if (showPanoramaPill)
                    _modePill(
                      label: _panoramaActive ? 'Exit 360°' : '360°',
                      icon: Icons.explore_outlined,
                      selected: _panoramaActive,
                      onTap: _togglePanorama,
                    ),
                  if (showPanoramaPill && _panoramaActive && _sensorAvailable)
                    const SizedBox(width: 8),
                  if (showPanoramaPill && _panoramaActive && _sensorAvailable)
                    _modePill(
                      label: 'Gyro',
                      icon: Icons.screen_rotation_alt_outlined,
                      selected: _sensorOn,
                      onTap: _toggleSensor,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _SpecialImageMetadata {
  const _SpecialImageMetadata({this.motionPhoto = false, this.panorama});

  final bool motionPhoto;
  final _PanoramaSpec? panorama;

  factory _SpecialImageMetadata.fromDirectories(
    List<MetadataDirectory> directories,
  ) {
    final tags = <String, String>{};
    for (final directory in directories) {
      if (directory.name.toLowerCase() != 'xmp') continue;
      for (final tag in directory.tags) {
        final key = tag.name.toLowerCase().split(':').last;
        tags[key] = tag.value.trim();
      }
    }

    String? tag(String name) => tags[name.toLowerCase()];
    bool yes(String? value) =>
        value != null &&
        const {'1', 'true', 'yes'}.contains(value.toLowerCase());
    double? number(String name) => double.tryParse(tag(name) ?? '');

    final isMotionPhoto = ImageMetadataReader.isMotionPhoto(directories);

    final projection = tag('ProjectionType')?.toLowerCase();
    final useViewer = yes(tag('UsePanoramaViewer'));
    if (projection != 'equirectangular' && !useViewer) {
      // Many 360° exports carry no GPano XMP at all. A 2:1 image that says
      // nothing else about its projection is treated as a full equirectangular
      // sphere; the spec's zeros mean "the whole image".
      if (projection == null && _looksEquirectangular(directories)) {
        return _SpecialImageMetadata(
          motionPhoto: isMotionPhoto,
          panorama: const _PanoramaSpec(
            fullWidth: 0,
            fullHeight: 0,
            cropLeft: 0,
            cropTop: 0,
            cropWidth: 0,
            cropHeight: 0,
            initialHeading: 0,
            initialPitch: 0,
            initialFov: 90,
          ),
        );
      }
      return _SpecialImageMetadata(motionPhoto: isMotionPhoto);
    }

    return _SpecialImageMetadata(
      motionPhoto: isMotionPhoto,
      panorama: _PanoramaSpec(
        fullWidth: number('FullPanoWidthPixels') ?? 0,
        fullHeight: number('FullPanoHeightPixels') ?? 0,
        cropLeft: number('CroppedAreaLeftPixels') ?? 0,
        cropTop: number('CroppedAreaTopPixels') ?? 0,
        cropWidth: number('CroppedAreaImageWidthPixels') ?? 0,
        cropHeight: number('CroppedAreaImageHeightPixels') ?? 0,
        initialHeading: number('InitialViewHeadingDegrees') ?? 0,
        initialPitch: number('InitialViewPitchDegrees') ?? 0,
        initialFov: number('InitialHorizontalFOVDegrees') ?? 90,
      ),
    );
  }
}

bool _looksEquirectangular(List<MetadataDirectory> directories) {
  double? dimension(String name) {
    for (final directory in directories) {
      for (final tag in directory.tags) {
        if (tag.name.toLowerCase() == name) {
          final value = double.tryParse(tag.value.trim());
          if (value != null) return value;
        }
      }
    }
    return null;
  }

  final width = dimension('image width');
  final height = dimension('image height');
  if (width == null || height == null || height <= 0) return false;
  return width >= 2048 && (width / height - 2).abs() < 0.02;
}

class _PanoramaSpec {
  const _PanoramaSpec({
    required this.fullWidth,
    required this.fullHeight,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
    required this.initialHeading,
    required this.initialPitch,
    required this.initialFov,
  });

  final double fullWidth;
  final double fullHeight;
  final double cropLeft;
  final double cropTop;
  final double cropWidth;
  final double cropHeight;
  final double initialHeading;
  final double initialPitch;
  final double initialFov;
}

class _PanoramaScene extends StatefulWidget {
  const _PanoramaScene({
    required this.image,
    required this.shader,
    required this.spec,
    required this.sensorEnabled,
    required this.onTap,
  });

  final ui.Image image;
  final ui.FragmentShader shader;
  final _PanoramaSpec spec;
  final bool sensorEnabled;
  final VoidCallback onTap;

  @override
  State<_PanoramaScene> createState() => _PanoramaSceneState();
}

class _PanoramaSceneState extends State<_PanoramaScene>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final PanoramaCamera _camera = PanoramaCamera(
    yaw: widget.spec.initialHeading * math.pi / 180,
    pitch: widget.spec.initialPitch * math.pi / 180,
    fov: widget.spec.initialFov * math.pi / 180,
  );
  late final Ticker _flingTicker = createTicker(_onFlingTick);

  StreamSubscription<List<double>>? _sensorSub;
  bool _resumed = true;

  double _startFov = math.pi / 2;
  bool _multiTouch = false;
  double _viewportHeight = 1;
  double _flingYaw = 0; // rad/s
  double _flingPitch = 0; // rad/s
  Duration _lastTick = Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncSensor();
  }

  @override
  void didUpdateWidget(covariant _PanoramaScene oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sensorEnabled != widget.sensorEnabled) _syncSensor();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _resumed) return;
    _resumed = resumed;
    _syncSensor();
  }

  void _syncSensor() {
    final shouldRun = widget.sensorEnabled && _resumed;
    if (shouldRun && _sensorSub == null) {
      _stopFling();
      if (_camera.sensorActive) {
        // Resuming after a pause: keep looking where the user was looking.
        _camera.beginSensor(_camera.forward().heading);
      } else {
        _camera.beginSensor(widget.spec.initialHeading * math.pi / 180);
      }
      _sensorSub = DeviceOrientationSensor.matrices().listen(
        _camera.onDeviceMatrix,
        onError: (_) {},
      );
    } else if (!shouldRun && _sensorSub != null) {
      _sensorSub?.cancel();
      _sensorSub = null;
      if (widget.sensorEnabled) {
        _camera.suspendSensor(); // paused in background; resume re-anchors
      } else {
        _camera.endSensor();
      }
    } else if (!widget.sensorEnabled && _camera.sensorActive) {
      _camera.endSensor();
    }
  }

  void _stopFling() {
    if (_flingTicker.isActive) _flingTicker.stop();
    _flingYaw = 0;
    _flingPitch = 0;
  }

  void _onFlingTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    _camera.rotateBy(_flingYaw * dt, _flingPitch * dt);
    final decay = math.exp(-3.5 * dt);
    _flingYaw *= decay;
    _flingPitch *= decay;
    if (_flingYaw.abs() < 0.02 && _flingPitch.abs() < 0.02) _stopFling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sensorSub?.cancel();
    _flingTicker.dispose();
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportHeight = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onScaleStart: (details) {
            _stopFling();
            _startFov = _camera.fov;
            _multiTouch = details.pointerCount > 1;
          },
          onScaleUpdate: (details) {
            if (_viewportHeight <= 0) return;
            if (details.pointerCount > 1) _multiTouch = true;
            _camera.panBy(details.focalPointDelta, _viewportHeight);
            if (details.scale != 1.0) {
              _camera.setFov(_startFov / details.scale);
            }
          },
          onScaleEnd: (details) {
            if (_multiTouch || _viewportHeight <= 0) return;
            final rpp = _camera.radiansPerPixel(_viewportHeight);
            final v = details.velocity.pixelsPerSecond;
            _flingYaw = -v.dx * rpp;
            _flingPitch = v.dy * rpp;
            if (_flingYaw.abs() < 0.2 && _flingPitch.abs() < 0.2) return;
            _lastTick = Duration.zero;
            _flingTicker.start();
          },
          child: CustomPaint(
            painter: _PanoramaPainter(
              image: widget.image,
              shader: widget.shader,
              spec: widget.spec,
              camera: _camera,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _PanoramaPainter extends CustomPainter {
  _PanoramaPainter({
    required this.image,
    required this.shader,
    required this.spec,
    required this.camera,
  }) : super(repaint: camera);

  final ui.Image image;
  final ui.FragmentShader shader;
  final _PanoramaSpec spec;
  final PanoramaCamera camera;

  @override
  void paint(Canvas canvas, Size size) {
    final fullWidth = spec.fullWidth > 0
        ? spec.fullWidth
        : image.width.toDouble();
    final fullHeight = spec.fullHeight > 0
        ? spec.fullHeight
        : image.height.toDouble();
    final cropWidth = spec.cropWidth > 0
        ? spec.cropWidth
        : image.width.toDouble();
    final cropHeight = spec.cropHeight > 0
        ? spec.cropHeight
        : image.height.toDouble();
    final sensor = camera.sensorActive && camera.hasSensorSample;
    final rows = camera.rows;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, camera.yaw)
      ..setFloat(3, camera.pitch)
      ..setFloat(4, camera.fov)
      ..setFloat(5, fullWidth)
      ..setFloat(6, fullHeight)
      ..setFloat(7, spec.cropLeft)
      ..setFloat(8, spec.cropTop)
      ..setFloat(9, cropWidth)
      ..setFloat(10, cropHeight)
      ..setFloat(11, sensor ? 1 : 0);
    for (var i = 0; i < 9; i++) {
      shader.setFloat(12 + i, rows[i]);
    }
    shader.setImageSampler(0, image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _PanoramaPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.shader != shader ||
      oldDelegate.camera != camera ||
      oldDelegate.spec != spec;
}
