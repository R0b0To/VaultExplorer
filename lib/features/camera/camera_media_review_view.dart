import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/editor_swipe_to_seek_area.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_screen.dart';
import 'package:vaultexplorer/features/video_editor/models/edit_segment.dart';
import 'package:vaultexplorer/features/video_editor/models/video_edit_math.dart';
import 'package:vaultexplorer/features/video_editor/widgets/video_timeline.dart';

enum CapturedMediaType { photo, video }

class CapturedMediaItem {
  final CapturedMediaType type;
  Uint8List? fullPhotoBytes;
  String? videoPath;
  int videoDurationMs;
  int trimStartMs;
  int trimEndMs;
  Uint8List thumbnailBytes;

  /// True for a page from the document scanner (already cropped, flattened and
  /// filtered). It is a photo in every other respect; the flag only decides
  /// whether it may be combined into a PDF when saving.
  final bool isScan;

  CapturedMediaItem.photo({
    required Uint8List photoBytes,
    required this.thumbnailBytes,
  }) : type = CapturedMediaType.photo,
       fullPhotoBytes = photoBytes,
       isScan = false,
       videoDurationMs = 0,
       trimStartMs = 0,
       trimEndMs = 0;

  CapturedMediaItem.scanPage({
    required Uint8List pageBytes,
    required this.thumbnailBytes,
  }) : type = CapturedMediaType.photo,
       fullPhotoBytes = pageBytes,
       isScan = true,
       videoDurationMs = 0,
       trimStartMs = 0,
       trimEndMs = 0;

  CapturedMediaItem.video({
    required this.videoPath,
    required this.videoDurationMs,
    required this.thumbnailBytes,
  }) : type = CapturedMediaType.video,
       isScan = false,
       trimStartMs = 0,
       trimEndMs = videoDurationMs;

  bool get isVideo => type == CapturedMediaType.video;
  bool get isPhoto => type == CapturedMediaType.photo;
}

class CameraMediaReviewView extends ConsumerStatefulWidget {
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
  ConsumerState<CameraMediaReviewView> createState() =>
      _CameraMediaReviewViewState();
}

class _CameraMediaReviewViewState extends ConsumerState<CameraMediaReviewView> {
  static const String _trimSegmentId = 'camera-review-trim';

  late List<CapturedMediaItem> _media;
  late int _selectedIndex;
  NativeVideoController? _videoController;
  bool _isPlaying = true;
  bool _isDraggingTrim = false;
  bool _isScrubbing = false;
  bool _resumeAfterScrub = false;
  bool _isSaving = false;
  int? _pendingSeekUs;
  bool _seeking = false;
  Completer<void>? _seekIdle;
  int _filmstripLoadId = 0;
  List<FilmstripEntry>? _filmstripFrames;
  final ValueNotifier<int> _playheadUs = ValueNotifier<int>(0);
  final GlobalKey<VideoTimelineState> _timelineKey =
      GlobalKey<VideoTimelineState>();

  CapturedMediaItem? get _currentMedia =>
      _media.isNotEmpty ? _media[_selectedIndex] : null;

  @override
  void initState() {
    super.initState();
    _media = List<CapturedMediaItem>.from(widget.initialMedia);
    _selectedIndex = widget.initialIndex.clamp(
      0,
      math.max(0, _media.length - 1),
    );
    if (_currentMedia?.isVideo == true) {
      _initVideoPlayer(_currentMedia!.videoPath!);
      unawaited(_loadFilmstrip(_currentMedia!));
    }
  }

  Future<void> _initVideoPlayer(String path) async {
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    // The app has a single native player; background audio lets go of it first.
    if (BackgroundPlaybackHost.instance.needsRelease) {
      await BackgroundPlaybackHost.instance.closeAndWait();
      if (!mounted) return;
    }
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
    if (!mounted || !identical(_videoController, controller)) return;
    await controller.setLooping(false);
    if (!mounted || !identical(_videoController, controller)) return;
    final media = _currentMedia;
    if (media != null && media.isVideo && media.trimStartMs > 0) {
      _playheadUs.value = media.trimStartMs * 1000;
      await controller.seekTo(Duration(milliseconds: media.trimStartMs));
      if (!mounted || !identical(_videoController, controller)) return;
    }
    await controller.play();
    if (mounted) setState(() {});
  }

  void _onVideoTick() {
    final controller = _videoController;
    final media = _currentMedia;
    if (controller == null ||
        !controller.value.isInitialized ||
        media == null ||
        !media.isVideo)
      return;
    final posMs = controller.value.position.inMilliseconds;
    if (!_isDraggingTrim && !_isScrubbing && !_seeking) {
      final posUs = (posMs * 1000)
          .clamp(0, media.videoDurationMs * 1000)
          .toInt();
      if (_playheadUs.value != posUs) _playheadUs.value = posUs;
    }
    if (controller.value.isPlaying && !_isDraggingTrim && !_isScrubbing) {
      if (posMs >= media.trimEndMs || posMs < media.trimStartMs) {
        unawaited(_seekToUs(media.trimStartMs * 1000));
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
    _playheadUs.dispose();
    _disposeFilmstrip();
    super.dispose();
  }

  void _disposeFilmstrip() {
    _filmstripLoadId++;
    final frames = _filmstripFrames;
    _filmstripFrames = null;
    if (frames != null) {
      for (final frame in frames) {
        frame.image.dispose();
      }
    }
  }

  Future<void> _loadFilmstrip(CapturedMediaItem media) async {
    final path = media.videoPath;
    if (path == null || media.videoDurationMs <= 0) return;
    _disposeFilmstrip();
    final loadId = _filmstripLoadId;
    final fileIo = ref.read(vaultFileIoApiProvider);
    const frameCount = 10;
    final durationUs = media.videoDurationMs * 1000;
    final frames = <FilmstripEntry>[];

    if (media.thumbnailBytes.isNotEmpty) {
      try {
        final codec = await ui.instantiateImageCodec(media.thumbnailBytes);
        try {
          final frame = await codec.getNextFrame();
          final placeholder = (timeUs: 0, image: frame.image);
          if (mounted &&
              loadId == _filmstripLoadId &&
              identical(_currentMedia, media)) {
            setState(() => _filmstripFrames = [placeholder]);
          } else {
            frame.image.dispose();
            return;
          }
        } finally {
          codec.dispose();
        }
      } catch (_) {
        // Fall back to the extracted frames below.
      }
    }

    for (var i = 0; i < frameCount; i++) {
      if (!mounted ||
          loadId != _filmstripLoadId ||
          !identical(_currentMedia, media)) {
        _disposeFrames(frames);
        return;
      }
      final timeUs = i * durationUs ~/ frameCount;
      try {
        final bytes = await fileIo.getVideoThumbnailFromLocalPath(
          path,
          targetSize: 100,
          quality: 45,
          timeUs: timeUs,
        );
        if (bytes == null) continue;
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          final frame = await codec.getNextFrame();
          frames.add((timeUs: timeUs, image: frame.image));
        } finally {
          codec.dispose();
        }
      } catch (_) {
        // A missing frame should not prevent the captured video from opening.
      }
    }

    if (!mounted ||
        loadId != _filmstripLoadId ||
        !identical(_currentMedia, media)) {
      _disposeFrames(frames);
      return;
    }
    if (frames.isNotEmpty) {
      final oldFrames = _filmstripFrames;
      setState(() => _filmstripFrames = frames);
      if (oldFrames != null) _disposeFrames(oldFrames);
    }
  }

  void _disposeFrames(List<FilmstripEntry> frames) {
    for (final frame in frames) {
      frame.image.dispose();
    }
  }

  Future<void> _seekToUs(int requestedUs) {
    final media = _currentMedia;
    final controller = _videoController;
    if (media == null || controller == null || controller.isDisposed) {
      return Future<void>.value();
    }
    final durationUs = media.videoDurationMs * 1000;
    final us = requestedUs.clamp(0, durationUs).toInt();
    _playheadUs.value = us;
    _pendingSeekUs = us;
    if (_seeking) return _seekIdle!.future;
    _seeking = true;
    _seekIdle = Completer<void>();
    unawaited(_runSeekLoop());
    return _seekIdle!.future;
  }

  Future<void> _runSeekLoop() async {
    try {
      while (_pendingSeekUs != null) {
        final us = _pendingSeekUs!;
        _pendingSeekUs = null;
        final controller = _videoController;
        if (controller == null || controller.isDisposed) break;
        await controller.seekTo(Duration(milliseconds: (us + 999) ~/ 1000));
      }
    } catch (_) {
      // Seeking is best-effort while the native recording player initializes.
    } finally {
      _seeking = false;
      _seekIdle?.complete();
    }
  }

  void _onScrubStart() {
    _isScrubbing = true;
    _resumeAfterScrub = _videoController?.value.isPlaying ?? false;
    if (_resumeAfterScrub) unawaited(_videoController?.pause());
  }

  void _onScrub(int us) => unawaited(_seekToUs(us));

  void _onScrubEnd() {
    _isScrubbing = false;
    if (_resumeAfterScrub) unawaited(_videoController?.play());
    _resumeAfterScrub = false;
  }

  void _onTrimHandleDragStart() {
    _isDraggingTrim = true;
    _resumeAfterScrub = _videoController?.value.isPlaying ?? false;
    if (_resumeAfterScrub) unawaited(_videoController?.pause());
  }

  void _onTrimHandleDragUpdate(bool isStart, int us) {
    final media = _currentMedia;
    if (media == null) return;
    final total = media.videoDurationMs;
    var start = media.trimStartMs;
    var end = media.trimEndMs;
    final valueMs = (us / 1000).round();
    if (isStart) {
      start = valueMs.clamp(0, math.max(0, end - 500)).toInt();
    } else {
      end = valueMs.clamp(math.min(total, start + 500), total).toInt();
    }
    if (start == media.trimStartMs && end == media.trimEndMs) return;
    setState(() {
      media.trimStartMs = start;
      media.trimEndMs = end;
    });
  }

  void _onTrimHandleDragEnd() {
    _isDraggingTrim = false;
    final media = _currentMedia;
    if (media != null) unawaited(_seekToUs(media.trimStartMs * 1000));
    if (_resumeAfterScrub) unawaited(_videoController?.play());
    _resumeAfterScrub = false;
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
    _disposeFilmstrip();
    _timelineKey.currentState?.resetZoom();

    setState(() {
      if (_selectedIndex >= _media.length) {
        _selectedIndex = math.max(0, _media.length - 1);
      }
      _isScrubbing = false;
      _isDraggingTrim = false;
      _resumeAfterScrub = false;
    });
    final selected = _currentMedia;
    _playheadUs.value = selected?.isVideo == true
        ? selected!.trimStartMs * 1000
        : 0;
    _isPlaying = selected?.isVideo == true;

    widget.onMediaChanged?.call(List<CapturedMediaItem>.from(_media));

    if (_media.isEmpty) {
      widget.onDiscard();
    } else if (_currentMedia?.isVideo == true) {
      _initVideoPlayer(_currentMedia!.videoPath!);
      unawaited(_loadFilmstrip(_currentMedia!));
    }
  }

  void _onSwitchMedia(int idx) {
    if (idx == _selectedIndex || idx < 0 || idx >= _media.length) return;
    HapticFeedback.selectionClick();
    _videoController?.removeListener(_onVideoTick);
    _videoController?.dispose();
    _videoController = null;
    _disposeFilmstrip();
    _timelineKey.currentState?.resetZoom();
    setState(() {
      _selectedIndex = idx;
      _isScrubbing = false;
      _isDraggingTrim = false;
      _resumeAfterScrub = false;
    });
    final selected = _currentMedia;
    _playheadUs.value = selected?.isVideo == true
        ? selected!.trimStartMs * 1000
        : 0;
    _isPlaying = selected?.isVideo == true;
    if (_currentMedia?.isVideo == true) {
      _initVideoPlayer(_currentMedia!.videoPath!);
      unawaited(_loadFilmstrip(_currentMedia!));
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

  Future<void> _saveMedia() async {
    final onSaveMedia = widget.onSaveMedia;
    if (_isSaving || _media.isEmpty || onSaveMedia == null) return;

    final selectedBeforeSave = _currentMedia;
    final selectedVideoPathBeforeSave = selectedBeforeSave?.videoPath;
    setState(() => _isSaving = true);
    try {
      await _videoController?.pause();
      await onSaveMedia(_media);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.cameraCouldNotSaveCaptureMessage),
          ),
        );
      }
    } finally {
      if (mounted) {
        final selectedStillExists =
            selectedBeforeSave != null && _media.contains(selectedBeforeSave);
        final selectedVideoPathChanged =
            selectedStillExists &&
            selectedBeforeSave.isVideo &&
            selectedBeforeSave.videoPath != selectedVideoPathBeforeSave;
        if (!selectedStillExists || selectedVideoPathChanged) {
          _videoController?.removeListener(_onVideoTick);
          await _videoController?.dispose();
          _videoController = null;
          if (selectedVideoPathChanged) _disposeFilmstrip();
        }
        setState(() {
          if (_media.isNotEmpty) {
            _selectedIndex = _selectedIndex.clamp(0, _media.length - 1);
          } else {
            _selectedIndex = 0;
          }
          _isSaving = false;
        });
        if ((!selectedStillExists || selectedVideoPathChanged) &&
            _currentMedia?.isVideo == true) {
          await _initVideoPlayer(_currentMedia!.videoPath!);
          unawaited(_loadFilmstrip(_currentMedia!));
        } else if (selectedStillExists && selectedBeforeSave.isVideo) {
          try {
            await _videoController?.play();
          } catch (_) {
            // Resuming the preview is best-effort after a successful save;
            // the saved media is intact and the user can still tap Play.
          }
        }
      }
    }
  }

  Widget _buildVideoPreview(
    CapturedMediaItem media,
    NativeVideoController controller,
  ) {
    final duration = Duration(milliseconds: media.videoDurationMs);
    return InteractiveViewer(
      key: ValueKey('video_zoom_$_selectedIndex'),
      minScale: 1.0,
      maxScale: 4.0,
      clipBehavior: Clip.none,
      child: EditorSwipeToSeekArea(
        totalDuration: duration,
        currentPosition: () => Duration(microseconds: _playheadUs.value),
        visibleDuration: () => _timelineKey.currentState?.visibleDuration,
        enabled: controller.value.isInitialized && duration > Duration.zero,
        onTap: _togglePlayPause,
        onSeekStart: _onScrubStart,
        onSeekUpdate: (position) => _onScrub(position.inMicroseconds),
        onSeekEnd: (_) => _onScrubEnd(),
        onSeekCancel: (position) {
          unawaited(_seekToUs(position.inMicroseconds));
          _onScrubEnd();
        },
        child: Center(
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: Stack(
              alignment: Alignment.center,
              children: [
                NativeVideoPlayerView(controller: controller),
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
    );
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
              if (_currentMedia!.isPhoto &&
                  _currentMedia!.fullPhotoBytes != null)
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
                _buildVideoPreview(_currentMedia!, _videoController!)
              else
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
            ] else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Top Bar (Single clean exit to return to live camera without losing batch)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(
                        Icons.arrow_back_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      tooltip: context.l10n.goBack,
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        widget.onMediaChanged?.call(
                          List<CapturedMediaItem>.from(_media),
                        );
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
                      colors: [
                        Colors.black87,
                        Colors.black54,
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The same filmstrip timeline and trim handles used by the
                      // video editor, connected to this capture's trim range.
                      if (_currentMedia?.isVideo == true &&
                          _currentMedia!.videoDurationMs > 500) ...[
                        Row(
                          children: [
                            ValueListenableBuilder<int>(
                              valueListenable: _playheadUs,
                              builder: (context, us, _) => Text(
                                '${formatTimecode(us)} / ${formatTimecode(_currentMedia!.videoDurationMs * 1000)}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              tooltip: context.l10n.videoEditorZoomOut,
                              visualDensity: VisualDensity.compact,
                              color: Colors.white,
                              icon: const Icon(Icons.zoom_out_rounded),
                              onPressed: () =>
                                  _timelineKey.currentState?.zoomBy(0.5),
                            ),
                            IconButton(
                              tooltip: context.l10n.videoEditorZoomIn,
                              visualDensity: VisualDensity.compact,
                              color: Colors.white,
                              icon: const Icon(Icons.zoom_in_rounded),
                              onPressed: () =>
                                  _timelineKey.currentState?.zoomBy(2),
                            ),
                            IconButton(
                              tooltip: context.l10n.videoEditorZoomFit,
                              visualDensity: VisualDensity.compact,
                              color: Colors.white,
                              icon: const Icon(Icons.fit_screen_rounded),
                              onPressed: () =>
                                  _timelineKey.currentState?.resetZoom(),
                            ),
                          ],
                        ),
                        VideoTimeline(
                          key: _timelineKey,
                          durationUs: _currentMedia!.videoDurationMs * 1000,
                          segments: [
                            EditSegment(
                              id: _trimSegmentId,
                              startUs: _currentMedia!.trimStartMs * 1000,
                              endUs: _currentMedia!.trimEndMs * 1000,
                            ),
                          ],
                          selectedId: _trimSegmentId,
                          mode: VideoEditMode.keep,
                          keyframes: const [],
                          snappedExportRanges: const [],
                          filmstripFrames: _filmstripFrames,
                          playheadUs: _playheadUs,
                          onScrubStart: _onScrubStart,
                          onScrub: _onScrub,
                          onScrubEnd: _onScrubEnd,
                          onTapAt: _onScrub,
                          onHandleDragStart: _onTrimHandleDragStart,
                          onHandleDragUpdate: _onTrimHandleDragUpdate,
                          onHandleDragEnd: _onTrimHandleDragEnd,
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
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
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
                                      color: isSel
                                          ? Colors.amber
                                          : Colors.white24,
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
                                            ? Image.memory(
                                                item.thumbnailBytes,
                                                fit: BoxFit.cover,
                                              )
                                            : Container(
                                                color: Colors.grey.shade900,
                                              ),
                                      ),
                                      if (item.isVideo)
                                        Center(
                                          child: Container(
                                            padding: const EdgeInsets.all(3),
                                            decoration: const BoxDecoration(
                                              color: Colors.black54,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.play_arrow_rounded,
                                              color: Colors.white,
                                              size: 14,
                                            ),
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
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.crop_rotate_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
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
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 14),
                          ],
                          // Confirm Save FAB
                          FloatingActionButton(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            onPressed: _isSaving
                                ? null
                                : () {
                                    HapticFeedback.mediumImpact();
                                    unawaited(_saveMedia());
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
