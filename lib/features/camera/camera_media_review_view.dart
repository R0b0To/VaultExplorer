import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_screen.dart';

enum CapturedMediaType { photo, video }

class CapturedMediaItem {
  final CapturedMediaType type;
  Uint8List? fullPhotoBytes;
  String? videoPath;
  int videoDurationMs;
  int trimStartMs;
  int trimEndMs;
  Uint8List thumbnailBytes;

  CapturedMediaItem.photo({
    required Uint8List photoBytes,
    required this.thumbnailBytes,
  })  : type = CapturedMediaType.photo,
        fullPhotoBytes = photoBytes,
        videoDurationMs = 0,
        trimStartMs = 0,
        trimEndMs = 0;

  CapturedMediaItem.video({
    required this.videoPath,
    required this.videoDurationMs,
    required this.thumbnailBytes,
  })  : type = CapturedMediaType.video,
        trimStartMs = 0,
        trimEndMs = videoDurationMs;

  bool get isVideo => type == CapturedMediaType.video;
  bool get isPhoto => type == CapturedMediaType.photo;
}

class CameraMediaReviewView extends StatefulWidget {
  final List<CapturedMediaItem> initialMedia;
  final int initialIndex;
  final double iconTurns;
  final VoidCallback onDiscard;
  final VoidCallback onTakeMoreMedia;
  final ValueChanged<List<CapturedMediaItem>>? onMediaChanged;
  final Future<void> Function(List<CapturedMediaItem> media)? onSaveMedia;

  const CameraMediaReviewView({
    super.key,
    this.initialMedia = const [],
    this.initialIndex = 0,
    required this.iconTurns,
    required this.onDiscard,
    required this.onTakeMoreMedia,
    this.onMediaChanged,
    this.onSaveMedia,
  });

  @override
  State<CameraMediaReviewView> createState() => _CameraMediaReviewViewState();
}

class _CameraMediaReviewViewState extends State<CameraMediaReviewView> {
  late List<CapturedMediaItem> _media;
  late int _selectedIndex;
  NativeVideoController? _videoController;
  bool _isPlaying = true;
  bool _isDraggingTrim = false;

  CapturedMediaItem? get _currentMedia =>
      _media.isNotEmpty ? _media[_selectedIndex] : null;

  @override
  void initState() {
    super.initState();
    _media = List<CapturedMediaItem>.from(widget.initialMedia);
    _selectedIndex = widget.initialIndex.clamp(0, math.max(0, _media.length - 1));
    if (_currentMedia?.isVideo == true) {
      _initVideoPlayer(_currentMedia!.videoPath!);
    }
  }

  Future<void> _initVideoPlayer(String path) async {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    final controller = NativeVideoController(
      volId: -1,
      filePath: path,
      isLocalStorage: true,
      autoPlay: true,
      initialSpeed: 1.0,
    );
    _videoController = controller;
    controller.addListener(_onVideoTick);
    await controller.initialize();
    await controller.setLooping(false);
    await controller.play();
    if (mounted) setState(() {});
  }

  void _onVideoTick() {
    final controller = _videoController;
    final media = _currentMedia;
    if (controller == null || !controller.value.isInitialized || media == null || !media.isVideo) return;
    final posMs = controller.value.position.inMilliseconds;
    if (!_isDraggingTrim) {
      if (posMs >= media.trimEndMs || posMs < media.trimStartMs) {
        controller.seekTo(Duration(milliseconds: media.trimStartMs));
        if (!controller.value.isPlaying) controller.play();
      }
    }
    if (_isPlaying != controller.value.isPlaying) {
      setState(() => _isPlaying = controller.value.isPlaying);
    }
  }

  @override
  void dispose() {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _onEditPhoto() async {
    final media = _currentMedia;
    if (media == null || !media.isPhoto || media.fullPhotoBytes == null) return;
    HapticFeedback.lightImpact();
    final result = await Navigator.push<ImageEditorResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(
          imageBytes: media.fullPhotoBytes,
          batchIndex: _selectedIndex + 1,
        ),
      ),
    );
    if (!mounted || result == null) return;

    final Uint8List editedBytes = switch (result) {
      ImageEditorSaveResult(:final bytes) => bytes,
      ImageEditorAddAnotherResult(:final bytes) => bytes,
    };

    setState(() {
      media.fullPhotoBytes = editedBytes;
    });
    widget.onMediaChanged?.call(List<CapturedMediaItem>.from(_media));
  }

  void _deleteCurrentMedia() {
    if (_media.isEmpty) return;
    HapticFeedback.lightImpact();
    final item = _media.removeAt(_selectedIndex);
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _videoController = null;

    setState(() {
      if (_selectedIndex >= _media.length) {
        _selectedIndex = math.max(0, _media.length - 1);
      }
    });

    widget.onMediaChanged?.call(List<CapturedMediaItem>.from(_media));

    if (_media.isEmpty) {
      widget.onDiscard();
    } else if (_currentMedia?.isVideo == true) {
      _initVideoPlayer(_currentMedia!.videoPath!);
    }
  }

  void _onSwitchMedia(int idx) {
    if (idx == _selectedIndex || idx < 0 || idx >= _media.length) return;
    HapticFeedback.selectionClick();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _videoController = null;
    setState(() {
      _selectedIndex = idx;
    });
    if (_currentMedia?.isVideo == true) {
      _initVideoPlayer(_currentMedia!.videoPath!);
    }
  }

  void _togglePlayPause() {
    final controller = _videoController;
    if (controller == null) return;
    HapticFeedback.selectionClick();
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
  }

  String _formatMs(int ms) {
    final sec = (ms / 1000).floor();
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

 @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        HapticFeedback.lightImpact();
          widget.onMediaChanged?.call(List<CapturedMediaItem>.from(_media));
        widget.onTakeMoreMedia();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Media Preview Content with Pinch-to-Zoom
          if (_currentMedia != null) ...[
            if (_currentMedia!.isPhoto && _currentMedia!.fullPhotoBytes != null)
              InteractiveViewer(
                key: ValueKey('photo_zoom_$_selectedIndex'),
                minScale: 1.0,
                maxScale: 5.0,
                clipBehavior: Clip.none,
                child: Center(
                  child: Image.memory(
                    _currentMedia!.fullPhotoBytes!,
                    fit: BoxFit.contain,
                  ),
                ),
              )
            else if (_currentMedia!.isVideo && _videoController != null)
              InteractiveViewer(
                key: ValueKey('video_zoom_$_selectedIndex'),
                minScale: 1.0,
                maxScale: 4.0,
                clipBehavior: Clip.none,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _togglePlayPause,
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          NativeVideoPlayerView(controller: _videoController!),
                          if (!_isPlaying)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: const BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
            else
              const Center(child: CircularProgressIndicator(color: Colors.white)),
          ] else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

             // Top Bar (Single clean exit to return to live camera without losing batch)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
                    tooltip: context.l10n.goBack,
                  onPressed: () {
                      HapticFeedback.lightImpact();
                      widget.onMediaChanged?.call(List<CapturedMediaItem>.from(_media));
                      widget.onTakeMoreMedia();
                    },
                  ),
                ),
              ),
            ),
          ),

          // Bottom Controls, Trimmer & Actions (Optimized for thumb reachability)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black87, Colors.black54, Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                children: [
                    // Video Trimmer (for current selected item if video)
                    if (_currentMedia?.isVideo == true && _currentMedia!.videoDurationMs > 500) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatMs(_currentMedia!.trimStartMs),
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Duration: ${_formatMs(_currentMedia!.trimEndMs - _currentMedia!.trimStartMs)}',
                            style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _formatMs(_currentMedia!.trimEndMs),
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 28,
                          activeTrackColor: Colors.amber.withValues(alpha: 0.6),
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.amber,
                          rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10),
                          rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
                        ),
                        child: RangeSlider(
                          values: RangeValues(
                            _currentMedia!.trimStartMs.toDouble().clamp(0.0, _currentMedia!.videoDurationMs.toDouble()),
                            _currentMedia!.trimEndMs.toDouble().clamp(0.0, _currentMedia!.videoDurationMs.toDouble()),
                          ),
                          min: 0.0,
                          max: _currentMedia!.videoDurationMs.toDouble(),
                          onChangeStart: (_) {
                            _isDraggingTrim = true;
                            _videoController?.pause();
                          },
                          onChanged: (values) {
                            final media = _currentMedia!;
                            final total = media.videoDurationMs;
                            var s = values.start.toInt();
                            var e = values.end.toInt();
                            if (e - s < 500) {
                              if (e + 500 <= total) {
                                e = s + 500;
                              } else {
                                s = (e - 500).clamp(0, total);
                              }
                            }
                            setState(() {
                              media.trimStartMs = s;
                              media.trimEndMs = e;
                            });
                            _videoController?.seekTo(Duration(milliseconds: s));
                          },
                          onChangeEnd: (_) {
                            _isDraggingTrim = false;
                            final media = _currentMedia!;
                            _videoController?.seekTo(Duration(milliseconds: media.trimStartMs));
                            _videoController?.play();
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Unified Filmstrip (Photos & Videos)
                    if (_media.length > 1) ...[
                      SizedBox(
                        height: 54,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          itemCount: _media.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, idx) {
                            final isSel = idx == _selectedIndex;
                            final item = _media[idx];
                            return GestureDetector(
                              onTap: () => _onSwitchMedia(idx),
                              child: Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: isSel ? Colors.amber : Colors.white24,
                                    width: isSel ? 2.5 : 1.0,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: item.thumbnailBytes.isNotEmpty
                                          ? Image.memory(item.thumbnailBytes, fit: BoxFit.cover)
                                          : Container(color: Colors.grey.shade900),
                                    ),
                                    if (item.isVideo)
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
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Reachable Bottom Action Row
                    Row(
                      children: [
                        // Delete current item
                        Material(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 22),
                            tooltip: context.l10n.delete,
                            onPressed: _deleteCurrentMedia,
                          ),
                        ),
                        if (_currentMedia?.isPhoto == true) ...[
                          const SizedBox(width: 10),
                          // Edit current photo
                          Material(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: _onEditPhoto,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.crop_rotate_rounded, color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      context.l10n.edit,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (_media.length > 1) ...[
                          Text(
                            '${_selectedIndex + 1} / ${_media.length}',
                            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          const SizedBox(width: 14),
                        ],
                        // Confirm Save FAB
                        FloatingActionButton(
                          backgroundColor: Colors.amber,
                          foregroundColor: Colors.black,
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            if (_media.isNotEmpty) {
                              widget.onSaveMedia?.call(_media);
                            }
                          },
                          child: const Icon(Icons.check_rounded, size: 30),
                        ),
                      ],
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