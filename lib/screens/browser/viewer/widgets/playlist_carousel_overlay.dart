import 'dart:typed_data';
import 'package:flutter/material.dart';
import '/../../models/mounted_container.dart';
import '/../../models/thumbnail_quality.dart';
import '/../../services/vaultexplorer_api.dart';
import '../media_viewer_constants.dart';

/// A bottom-anchored strip of thumbnails for the active playlist. Lets the
/// user scroll through every item at a glance and tap one to jump straight
/// to it, instead of stepping through with next/previous.
class PlaylistCarouselOverlay extends StatefulWidget {
  final MountedContainer container;
  final List<String> playlist;
  final int currentIndex;
  final ThumbnailQuality thumbnailQuality;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  const PlaylistCarouselOverlay({
    Key? key,
    required this.container,
    required this.playlist,
    required this.currentIndex,
    required this.thumbnailQuality,
    required this.onSelect,
    required this.onClose,
  }) : super(key: key);

  // Height adjusted to comfortably fit the thumbnails + the seekbar
  static const double height = 230;

  @override
  State<PlaylistCarouselOverlay> createState() =>
      _PlaylistCarouselOverlayState();
}

class _PlaylistCarouselOverlayState extends State<PlaylistCarouselOverlay> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _sliderProportion = ValueNotifier<double>(0.0);

  bool _isDraggingSlider = false;

  static const double _tileWidth = 108;
  static const double _tileSpacing = 10;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerOnCurrent(animate: false));
  }

  @override
  void didUpdateWidget(covariant PlaylistCarouselOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _centerOnCurrent(animate: true);
    }
  }

  void _onScroll() {
    if (_isDraggingSlider || !_scrollController.hasClients) return;
    final maxExt = _scrollController.position.maxScrollExtent;
    if (maxExt > 0) {
      _sliderProportion.value = (_scrollController.offset / maxExt).clamp(0.0, 1.0);
    } else {
      _sliderProportion.value = 0.0;
    }
  }

  void _centerOnCurrent({required bool animate}) {
    if (!_scrollController.hasClients || widget.playlist.isEmpty) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final target = (widget.currentIndex * (_tileWidth + _tileSpacing)) -
        (screenWidth / 2) +
        (_tileWidth / 2);
    final clamped = target.clamp(0.0, _scrollController.position.maxScrollExtent);
    if (animate) {
      _scrollController.animateTo(
        clamped,
        duration: MediaViewerConstants.animationDuration,
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(clamped);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _sliderProportion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: PlaylistCarouselOverlay.height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withOpacity(0.95),
            Colors.black.withOpacity(0.95),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  iconSize: 22,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: Colors.white70,
                  ),
                  tooltip: 'Close carousel',
                  onPressed: widget.onClose,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                itemCount: widget.playlist.length,
                itemBuilder: (context, index) {
                  final fileName = widget.playlist[index];
                  final isSelected = index == widget.currentIndex;
                  return GestureDetector(
                    onTap: () => widget.onSelect(index),
                    child: Container(
                      width: _tileWidth,
                      margin: const EdgeInsets.only(right: _tileSpacing),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? cs.primary : Colors.white24,
                          width: isSelected ? 2.5 : 1,
                        ),
                      ),
                      // Wrap child in a ClipRRect with radius calculated to sit exactly 
                      // inside the outer border (outer radius - border width)
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(isSelected ? 7.5 : 9.0),
                        child: _CarouselThumb(
                          key: ValueKey(fileName),
                          container: widget.container,
                          fileName: fileName,
                          thumbnailQuality: widget.thumbnailQuality,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Seekbar with current and total numbers on the extremities
            if (widget.playlist.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 4),
                child: Row(
                  children: [
                    Text(
                      '${widget.currentIndex + 1}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 24, // Compact height for slider footprint
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.0,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                            activeTrackColor: cs.primary,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: cs.primary,
                            overlayColor: cs.primary.withOpacity(0.2),
                          ),
                          child: ValueListenableBuilder<double>(
                            valueListenable: _sliderProportion,
                            builder: (context, proportion, child) {
                              return Slider(
                                value: proportion,
                                min: 0.0,
                                max: 1.0,
                                onChanged: (val) {
                                  if (!_scrollController.hasClients) return;
                                  final maxExt = _scrollController.position.maxScrollExtent;
                                  if (maxExt <= 0) return;

                                  _isDraggingSlider = true;
                                  _sliderProportion.value = val;
                                  _scrollController.jumpTo(val * maxExt);
                                },
                                onChangeEnd: (val) {
                                  _isDraggingSlider = false;
                                  // Ensure the slider is reset visually if items don't stretch enough to scroll
                                  if (_scrollController.hasClients && _scrollController.position.maxScrollExtent <= 0) {
                                    _sliderProportion.value = 0.0;
                                  }
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${widget.playlist.length}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CarouselThumb extends StatefulWidget {
  final MountedContainer container;
  final String fileName;
  final ThumbnailQuality thumbnailQuality;

  const _CarouselThumb({
    Key? key,
    required this.container,
    required this.fileName,
    required this.thumbnailQuality,
  }) : super(key: key);

  @override
  State<_CarouselThumb> createState() => _CarouselThumbState();
}

class _CarouselThumbState extends State<_CarouselThumb> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final target = widget.fileName;
    if (MediaViewerConstants.isAudio(target)) return;

    try {
      Uint8List? data;
      if (MediaViewerConstants.isImage(target)) {
        data = await vaultExplorerApi.getImageThumbnail(
          widget.container,
          target,
          targetSize: MediaViewerConstants.carouselThumbnailTargetSize,
          quality: widget.thumbnailQuality.jpegQuality,
        );
      } else if (MediaViewerConstants.isVideo(target)) {
        data = await vaultExplorerApi.getVideoThumbnail(
          widget.container,
          target,
          quality: widget.thumbnailQuality.jpegQuality,
        );
      }
      if (!mounted) return;
      if (data != null && data.isNotEmpty) {
        setState(() => _bytes = data);
      } else {
        setState(() => _failed = true);
      }
    } catch (e) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaViewerConstants.isAudio(widget.fileName)) {
      return Container(
        color: const Color(0xFF161B22),
        child: const Center(
          child: Icon(Icons.music_note_rounded, color: Colors.white54, size: 26),
        ),
      );
    }

    if (_bytes != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(_bytes!, fit: BoxFit.cover),
          if (MediaViewerConstants.isVideo(widget.fileName))
            const Positioned(
              right: 4,
              bottom: 4,
              child: Icon(
                Icons.play_circle_fill_rounded,
                color: Colors.white70,
                size: 18,
              ),
            ),
        ],
      );
    }

    if (_failed) {
      return Container(
        color: const Color(0xFF161B22),
        child: Center(
          child: Icon(
            MediaViewerConstants.isVideo(widget.fileName)
                ? Icons.videocam_off_rounded
                : Icons.broken_image_rounded,
            color: Colors.white38,
            size: 20,
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF161B22),
      child: const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
        ),
      ),
    );
  }
}