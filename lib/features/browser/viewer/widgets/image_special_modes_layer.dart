import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/metadata/image_metadata_reader.dart';
import 'package:vaultexplorer/features/browser/metadata/metadata_edit_service.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
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

  _SpecialImageMetadata _metadata = const _SpecialImageMetadata();
  bool _panoramaActive = false;
  bool _autoPlayRequested = false;
  bool _panoramaLoading = false;
  String? _panoramaError;
  ui.Image? _panoramaImage;
  ui.FragmentShader? _panoramaShader;
  int _requestToken = 0;
  int _fileSize = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_readMetadata());
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
      });
      widget.onPanoramaModeChanged(true);
      return;
    }

    final token = ++_requestToken;
    setState(() {
      _panoramaActive = true;
      _panoramaLoading = true;
      _panoramaError = null;
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
    required this.onTap,
  });

  final ui.Image image;
  final ui.FragmentShader shader;
  final _PanoramaSpec spec;
  final VoidCallback onTap;

  @override
  State<_PanoramaScene> createState() => _PanoramaSceneState();
}

class _PanoramaSceneState extends State<_PanoramaScene> {
  late double _yaw = widget.spec.initialHeading * math.pi / 180;
  late double _pitch = widget.spec.initialPitch * math.pi / 180;
  late double _fov =
      (widget.spec.initialFov.clamp(35, 110)).toDouble() * math.pi / 180;
  double _startYaw = 0;
  double _startPitch = 0;
  double _startFov = math.pi / 2;
  Offset _startFocalPoint = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onScaleStart: (details) {
            _startYaw = _yaw;
            _startPitch = _pitch;
            _startFov = _fov;
            _startFocalPoint = details.focalPoint;
          },
          onScaleUpdate: (details) {
            if (width <= 0 || height <= 0) return;
            final delta = details.focalPoint - _startFocalPoint;
            setState(() {
              _yaw = _startYaw - delta.dx / width * 2 * math.pi;
              _pitch = (_startPitch + delta.dy / height * math.pi).clamp(
                -math.pi / 2,
                math.pi / 2,
              );
              _fov = (_startFov / details.scale).clamp(
                35 * math.pi / 180,
                110 * math.pi / 180,
              );
            });
          },
          child: CustomPaint(
            painter: _PanoramaPainter(
              image: widget.image,
              shader: widget.shader,
              spec: widget.spec,
              yaw: _yaw,
              pitch: _pitch,
              fov: _fov,
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

class _PanoramaPainter extends CustomPainter {
  const _PanoramaPainter({
    required this.image,
    required this.shader,
    required this.spec,
    required this.yaw,
    required this.pitch,
    required this.fov,
  });

  final ui.Image image;
  final ui.FragmentShader shader;
  final _PanoramaSpec spec;
  final double yaw;
  final double pitch;
  final double fov;

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
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, yaw)
      ..setFloat(3, pitch)
      ..setFloat(4, fov)
      ..setFloat(5, fullWidth)
      ..setFloat(6, fullHeight)
      ..setFloat(7, spec.cropLeft)
      ..setFloat(8, spec.cropTop)
      ..setFloat(9, cropWidth)
      ..setFloat(10, cropHeight)
      ..setImageSampler(0, image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _PanoramaPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.shader != shader ||
      oldDelegate.yaw != yaw ||
      oldDelegate.pitch != pitch ||
      oldDelegate.fov != fov ||
      oldDelegate.spec != spec;
}
