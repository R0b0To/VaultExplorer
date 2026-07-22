import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '/../../models/mounted_container.dart';
import '/../../models/thumbnail_cache_mode.dart';
import '/../../models/thumbnail_quality.dart';
import '/../../services/thumbnail_cache_service.dart';
import '/../../services/vaultexplorer_api.dart';
import '/../../widgets/async_thumbnail.dart';
import '../media_viewer_constants.dart';

class PlaylistCarouselOverlay extends StatefulWidget {
  final MountedContainer container;
  final List<String> playlist;
  final int currentIndex;
  final ThumbnailQuality thumbnailQuality;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;

  const PlaylistCarouselOverlay({
    super.key,
    required this.container,
    required this.playlist,
    required this.currentIndex,
    required this.thumbnailQuality,
    required this.thumbnailCacheMode,
    required this.onSelect,
    required this.onClose,
  });

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
    if (oldWidget.currentIndex != widget.currentIndex || oldWidget.playlist.length != widget.playlist.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerOnCurrent(animate: true);
      });
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
    final maxExt = _scrollController.position.maxScrollExtent;
    final clamped = target.clamp(0.0, maxExt > 0 ? maxExt : 0.0);

    if (animate && maxExt > 0) {
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
            Colors.black.withValues(alpha: 0.95),
            Colors.black.withValues(alpha: 0.95),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close Carousel Top Action
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Tooltip(
                  message: 'Close Carousel',
                  child: Material(
                    color: Colors.white.withValues(alpha: 0.14),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: widget.onClose,
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Horizontal Expressive Thumbnail List
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
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? cs.primary : Colors.white24,
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(isSelected ? 13 : 15),
                        child: _CarouselThumb(
                          key: ValueKey(fileName),
                          container: widget.container,
                          fileName: fileName,
                          thumbnailQuality: widget.thumbnailQuality,
                          thumbnailCacheMode: widget.thumbnailCacheMode,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // Position Scrubber Row
            if (widget.playlist.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12, top: 4),
                child: Row(
                  children: [
                    Text(
                      '${widget.currentIndex + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 24,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.0,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                            activeTrackColor: cs.primary,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: cs.primary,
                            overlayColor: cs.primary.withValues(alpha: 0.2),
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
                                  if (_scrollController.hasClients &&
                                      _scrollController.position.maxScrollExtent <= 0) {
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
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
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

class _CarouselThumb extends StatelessWidget {
  final MountedContainer container;
  final String fileName;
  final ThumbnailQuality thumbnailQuality;
  final ThumbnailCacheMode thumbnailCacheMode;

  const _CarouselThumb({
    super.key,
    required this.container,
    required this.fileName,
    required this.thumbnailQuality,
    required this.thumbnailCacheMode,
  });

  static Future<Uint8List> _fetchImage(
    MountedContainer container,
    String path,
    ThumbnailQuality quality,
    ThumbnailCacheMode mode,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await ThumbnailCacheService.get(
        container: container,
        filePath: path,
        mode: mode,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final scaledTargetSize = quality.scaledSize(
      MediaViewerConstants.carouselThumbnailTargetSize,
    );
    final data = await vaultExplorerApi.getImageThumbnail(
      container,
      path,
      targetSize: scaledTargetSize,
      quality: quality.jpegQuality,
    );
    if (data == null || data.isEmpty) {
      throw Exception('Empty image thumbnail: $path');
    }

    ThumbnailCacheService.putInMemory(container, path, data);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        ThumbnailCacheService.put(
          container: container,
          filePath: path,
          data: data,
          mode: mode,
        ),
      );
    }
    return data;
  }

  static Future<Uint8List> _fetchVideo(
    MountedContainer container,
    String path,
    ThumbnailQuality quality,
    ThumbnailCacheMode mode,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await ThumbnailCacheService.get(
        container: container,
        filePath: path,
        mode: mode,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final scaledTargetSize = quality.scaledSize(
      MediaViewerConstants.carouselThumbnailTargetSize,
    );
    final data = await vaultExplorerApi.getVideoThumbnail(
      container,
      path,
      quality: quality.jpegQuality,
      targetSize: scaledTargetSize,
    );
    if (data == null || data.isEmpty) {
      throw Exception('Empty video thumbnail: $path');
    }

    ThumbnailCacheService.putInMemory(container, path, data);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        ThumbnailCacheService.put(
          container: container,
          filePath: path,
          data: data,
          mode: mode,
        ),
      );
    }
    return data;
  }

  @override
  Widget build(BuildContext context) {
    if (MediaViewerConstants.isAudio(fileName)) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Icon(Icons.music_note_rounded, color: Colors.white70, size: 28),
        ),
      );
    }

    final isVideo = MediaViewerConstants.isVideo(fileName);
    final scaledSize = thumbnailQuality.scaledSize(
      MediaViewerConstants.carouselThumbnailTargetSize,
    );

    return AsyncThumbnail(
      key: ValueKey('carousel:$fileName'),
      container: container,
      filePath: fileName,
      cache: isVideo ? ThumbnailConcurrency.videoCache : ThumbnailConcurrency.imageCache,
      limiter: isVideo ? ThumbnailConcurrency.videoLimiter : ThumbnailConcurrency.imageLimiter,
      fetchFn: (c, p) => isVideo
          ? _fetchVideo(c, p, thumbnailQuality, thumbnailCacheMode)
          : _fetchImage(c, p, thumbnailQuality, thumbnailCacheMode),
      debounce: isVideo
          ? const Duration(milliseconds: 150)
          : const Duration(milliseconds: 100),
      syncLookup: () => ThumbnailCacheService.getFromMemory(container, fileName),
      cacheHeight: scaledSize,
      imageBuilder: (context, bytes, cacheHeight) => Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(bytes, fit: BoxFit.cover, cacheHeight: cacheHeight),
          if (isVideo)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
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
      loadingBuilder: (context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54),
          ),
        ),
      ),
      errorBuilder: (context) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            isVideo ? Icons.videocam_off_rounded : Icons.broken_image_rounded,
            color: Colors.white54,
            size: 22,
          ),
        ),
      ),
    );
  }
}