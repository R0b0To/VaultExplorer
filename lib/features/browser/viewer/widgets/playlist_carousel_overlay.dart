import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

class PlaylistCarouselOverlay extends StatefulWidget {
  final MountedContainer container;
  final List<String> playlist;
  final int currentIndex;
  final ThumbnailQuality thumbnailQuality;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ValueChanged<int> onSelect;
  final VoidCallback? onClose;

  const PlaylistCarouselOverlay({
    super.key,
    required this.container,
    required this.playlist,
    required this.currentIndex,
    required this.thumbnailQuality,
    required this.thumbnailCacheMode,
    required this.onSelect,
    this.onClose,
  });

  static const double heightCollapsed = 140;
  static const double heightWithScrubber = 182;
  static const double height = heightWithScrubber;

  @override
  State<PlaylistCarouselOverlay> createState() =>
      _PlaylistCarouselOverlayState();
}

class _PlaylistCarouselOverlayState extends State<PlaylistCarouselOverlay> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _sliderProportion = ValueNotifier<double>(0.0);

  bool _isDraggingSlider = false;
  bool _showScrubber = false;
  double _verticalDragDistance = 0.0;

  void _toggleScrubber(bool show) {
    if (_showScrubber == show || widget.playlist.length <= 1) return;
    HapticFeedback.selectionClick();
    setState(() {
      _showScrubber = show;
    });
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    _verticalDragDistance = 0.0;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    _verticalDragDistance += details.primaryDelta ?? 0;
    if (_verticalDragDistance < -12 && !_showScrubber) {
      _toggleScrubber(true);
      _verticalDragDistance = 0.0;
    } else if (_verticalDragDistance > 12 && _showScrubber) {
      _toggleScrubber(false);
      _verticalDragDistance = 0.0;
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final vy = details.primaryVelocity ?? 0;
    if (vy < -100 && !_showScrubber) {
      _toggleScrubber(true);
    } else if (vy > 100 && _showScrubber) {
      _toggleScrubber(false);
    }
    _verticalDragDistance = 0.0;
  }

  double? _viewportWidth;

  static const double _tileWidth = 108;
  static const double _tileSpacing = 10;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant PlaylistCarouselOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex ||
        oldWidget.playlist.length != widget.playlist.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerOnCurrent(animate: true);
      });
    }
  }

  void _onScroll() {
    if (_isDraggingSlider ||
        !_scrollController.hasClients ||
        _scrollController.positions.length != 1) {
      return;
    }
    final maxExt = _scrollController.position.maxScrollExtent;
    if (maxExt > 0) {
      _sliderProportion.value = (_scrollController.offset / maxExt).clamp(
        0.0,
        1.0,
      );
    } else {
      _sliderProportion.value = 0.0;
    }
  }

  void _onViewportWidthKnown(double width) {
    if (_viewportWidth == width) return;
    _viewportWidth = width;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _centerOnCurrent(animate: false);
    });
  }

  void _centerOnCurrent({required bool animate}) {
    if (!_scrollController.hasClients ||
        _scrollController.positions.length != 1 ||
        widget.playlist.isEmpty) {
      return;
    }
    final viewportWidth = _viewportWidth ?? MediaQuery.of(context).size.width;
    final target =
        (widget.currentIndex * (_tileWidth + _tileSpacing)) -
        (viewportWidth / 2) +
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
    final currentHeight = _showScrubber && widget.playlist.length > 1
        ? PlaylistCarouselOverlay.heightWithScrubber
        : PlaylistCarouselOverlay.heightCollapsed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: currentHeight,
      child: ClipRect(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: _handleVerticalDragStart,
          onVerticalDragUpdate: _handleVerticalDragUpdate,
          onVerticalDragEnd: _handleVerticalDragEnd,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                // Horizontal Expressive Thumbnail List
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _onViewportWidthKnown(constraints.maxWidth);
                      return ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        itemExtent: _tileWidth + _tileSpacing,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        itemCount: widget.playlist.length,
                        itemBuilder: (context, index) {
                          final fileName = widget.playlist[index];
                          final isSelected = index == widget.currentIndex;
                          return GestureDetector(
                            onTap: () => widget.onSelect(index),
                            child: Container(
                              width: _tileWidth,
                              margin:
                                  const EdgeInsets.only(right: _tileSpacing),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected
                                      ? cs.primary
                                      : Colors.white24,
                                  width: isSelected ? 3 : 1,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  isSelected ? 13 : 15,
                                ),
                                child: _CarouselThumb(
                                  key: ValueKey(fileName),
                                  container: widget.container,
                                  fileName: fileName,
                                  thumbnailQuality: widget.thumbnailQuality,
                                  thumbnailCacheMode:
                                      widget.thumbnailCacheMode,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                // Collapsible Position Scrubber Row
                if (_showScrubber && widget.playlist.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      bottom: 10,
                      top: 4,
                    ),
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
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6.0,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14.0,
                                ),
                                activeTrackColor: cs.primary,
                                inactiveTrackColor: Colors.white24,
                                thumbColor: cs.primary,
                                overlayColor:
                                    cs.primary.withValues(alpha: 0.2),
                              ),
                              child: ValueListenableBuilder<double>(
                                valueListenable: _sliderProportion,
                                builder: (context, proportion, child) {
                                  return Slider(
                                    value: proportion,
                                    min: 0.0,
                                    max: 1.0,
                                    onChanged: (val) {
                                      if (!_scrollController.hasClients) {
                                        return;
                                      }
                                      final maxExt = _scrollController
                                          .position
                                          .maxScrollExtent;
                                      if (maxExt <= 0) return;

                                      _isDraggingSlider = true;
                                      _sliderProportion.value = val;
                                      _scrollController
                                          .jumpTo(val * maxExt);
                                    },
                                    onChangeEnd: (val) {
                                      _isDraggingSlider = false;
                                      if (_scrollController.hasClients &&
                                          _scrollController
                                                  .position
                                                  .maxScrollExtent <=
                                              0) {
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
        ),
      ),
    );
  }
}

class _CarouselThumb extends ConsumerWidget {
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
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailQuality quality,
    ThumbnailCacheMode mode,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await thumbnailCache.fetch(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }

    final scaledTargetSize = quality.scaledSize(
      MediaViewerConstants.carouselThumbnailTargetSize,
    );
    final data = await fileIoApi.getImageThumbnail(
      container,
      path,
      targetSize: scaledTargetSize,
      quality: quality.jpegQuality,
    );
    if (data == null || data.isEmpty) {
      throw Exception('Empty image thumbnail');
    }

    thumbnailCache.cacheInMemory(container, path, data, quality);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        thumbnailCache.store(
          container: container,
          filePath: path,
          data: data,
          mode: mode,
          quality: quality,
        ),
      );
    }
    return data;
  }

  static Future<Uint8List> _fetchVideo(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailQuality quality,
    ThumbnailCacheMode mode,
  ) =>
      VideoThumbnailFetcher.fetch(
        thumbnailCache,
        fileIoApi,
        container,
        path,
        mode: mode,
        quality: quality,
        targetSize: quality.scaledSize(
          MediaViewerConstants.carouselThumbnailTargetSize,
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    if (MediaViewerConstants.isAudio(fileName)) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(
          child: Icon(
            Icons.music_note_rounded,
            color: Colors.white70,
            size: 28,
          ),
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
      quality: thumbnailQuality,
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: isVideo
          ? ThumbnailConcurrency.videoLimiter
          : ThumbnailConcurrency.imageLimiter,
      priority: TaskPriority.adjacent,
      fetchFn: (c, p) => isVideo
          ? _fetchVideo(
              thumbnailCache,
              fileIoApi,
              c,
              p,
              thumbnailQuality,
              thumbnailCacheMode,
            )
          : _fetchImage(
              thumbnailCache,
              fileIoApi,
              c,
              p,
              thumbnailQuality,
              thumbnailCacheMode,
            ),
      debounce: isVideo
          ? const Duration(milliseconds: 150)
          : const Duration(milliseconds: 100),
      syncLookup: () =>
          thumbnailCache.peekMemory(container, fileName, thumbnailQuality),
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
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white54,
            ),
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