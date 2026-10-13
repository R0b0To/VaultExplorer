import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/core/utils/image_dimensions.dart';
import 'package:vaultexplorer/core/utils/image_preview_exception.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'native_avif_widget.dart';

class EncryptedImageWidget extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String fileName;
  final Uint8List? prefetchedBytes;
  final BoxFit fit;
  final VoidCallback? onError;
  final ThumbnailQuality thumbnailQuality;
  final ThumbnailCacheMode thumbnailCacheMode;
  final void Function(int width, int height)? onSizeKnown;

  const EncryptedImageWidget({
    super.key,
    required this.container,
    required this.fileName,
    this.prefetchedBytes,
    required this.fit,
    this.onError,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    this.thumbnailCacheMode = ThumbnailCacheMode.appCache,
    this.onSizeKnown,
  });

  @override
  ConsumerState<EncryptedImageWidget> createState() =>
      _EncryptedImageWidgetState();
}

class _EncryptedImageWidgetState extends ConsumerState<EncryptedImageWidget> {
  Uint8List? _bytes;
  Uint8List? _thumbnailBytes;
  String? _error;
  // Set when native code refused to decode this image (too large / not
  // enough memory) -- see FullResImageCache.fetch. Distinct from [_error]:
  // it is expected, explainable, and must not be retried automatically.
  ImagePreviewUnavailableReason? _previewFailure;
  bool _isFullResLoaded = false;
  bool _isLargeImagePreview = false;
  String? _currentlyLoadingFile;
  Completer<void>? _limiterCompleter;
  late final ThumbnailCacheService _thumbnailCache;

  void _sniffAndNotifySize(Uint8List bytes) {
    final dims = extractImageDimensionsFromBytes(bytes);
    if (dims != null && dims.$1 > 0 && dims.$2 > 0) {
      MediaAspectRatioCache.put(widget.container, widget.fileName, dims.$1, dims.$2);
      widget.onSizeKnown?.call(dims.$1, dims.$2);
    }
  }

  bool _isWebpImage(Uint8List bytes) =>
      bytes.length >= 12 &&
      String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';

  @override
  void initState() {
    super.initState();
    _thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    _thumbnailBytes =
        widget.prefetchedBytes ??
        _thumbnailCache.peekMemory(
          widget.container,
          widget.fileName,
          widget.thumbnailQuality,
        );
    if (_thumbnailBytes != null) {
      _sniffAndNotifySize(_thumbnailBytes!);
    }
    final cachedFullRes = FullResImageCache.get(
      widget.container,
      widget.fileName,
    );
    if (cachedFullRes != null) {
      _bytes = cachedFullRes;
      _isFullResLoaded = true;
      _isLargeImagePreview = false;
      _sniffAndNotifySize(cachedFullRes);
    } else {
      _loadImage();
    }
  }

  @override
  void didUpdateWidget(covariant EncryptedImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fileName != oldWidget.fileName) {
      _cancelPendingLoad();
      _error = null;
      _previewFailure = null;
      _thumbnailBytes =
          widget.prefetchedBytes ??
          _thumbnailCache.peekMemory(
            widget.container,
            widget.fileName,
            widget.thumbnailQuality,
          );
      final cachedFullRes = FullResImageCache.get(
        widget.container,
        widget.fileName,
      );
      _isLargeImagePreview = false;
      if (cachedFullRes != null) {
        _bytes = cachedFullRes;
        _isFullResLoaded = true;
      } else {
        _isFullResLoaded = false;
        _bytes = null;
        _loadImage();
      }
    } else if (!_isFullResLoaded &&
        _currentlyLoadingFile == null &&
        _previewFailure == null) {
      _loadImage();
     } else if (!_isFullResLoaded &&
        widget.prefetchedBytes != null &&
        _thumbnailBytes == null) {
      setState(() {
        _thumbnailBytes = widget.prefetchedBytes;
      });
      _sniffAndNotifySize(widget.prefetchedBytes!);
    }
  }

  void _cancelPendingLoad() {
    _currentlyLoadingFile = null;
    if (_limiterCompleter != null) {
      FullResImageCache.limiter.cancel(_limiterCompleter!);
      _limiterCompleter = null;
    }
  }

  Future<void> _loadImage() async {
    final targetFile = widget.fileName;
    if (_isFullResLoaded && _currentlyLoadingFile == targetFile) return;
    if (_currentlyLoadingFile == targetFile) return;

    if (_thumbnailBytes == null) {
      final memThumb = _thumbnailCache.peekMemory(
        widget.container,
        targetFile,
        widget.thumbnailQuality,
      );
      if (memThumb != null) {
        _thumbnailBytes = memThumb;
      }
    }

    final cachedFullRes = FullResImageCache.get(widget.container, targetFile);
    if (cachedFullRes != null) {
      if (mounted) {
        setState(() {
          _error = null;
          _bytes = cachedFullRes;
          _isFullResLoaded = true;
          _isLargeImagePreview = false;
        });
      }
      return;
    }

    _currentlyLoadingFile = targetFile;
    final completer = Completer<void>();
    _limiterCompleter = completer;

    if (_thumbnailBytes == null) {
      unawaited(_loadThumbnailFromCache(targetFile));
    }

    try {
      final data = await FullResImageCache.fetch(
        fileIoApi: ref.read(vaultFileIoApiProvider),
        container: widget.container,
        filePath: targetFile,
        completer: completer,
        isStillWanted: () => mounted && _currentlyLoadingFile == targetFile,
      );
      if (_limiterCompleter == completer) _limiterCompleter = null;
      if (!mounted || _currentlyLoadingFile != targetFile) return;
      if (data == null) {
        if (_bytes == null && _thumbnailBytes == null) {
          setState(() => _error = context.l10n.encryptedImageLoadFailedMessage);
        }
        return;
      }
       setState(() {
        _error = null;
        _bytes = data;
        _isFullResLoaded = true;
        _isLargeImagePreview =
            FullResImageCache.isLargeImagePreview(
              widget.container,
              targetFile,
            ) ||
            (widget.fileName.toLowerCase().endsWith('.avif') &&
                _isWebpImage(data));
      });
      _sniffAndNotifySize(data);
    } on ImagePreviewUnavailableException catch (e) {
      if (_limiterCompleter == completer) _limiterCompleter = null;
      if (mounted && _currentlyLoadingFile == targetFile) {
        _onPreviewUnavailable(e.reason);
      }
    } catch (e) {
      if (_limiterCompleter == completer) _limiterCompleter = null;
      if (mounted &&
          _currentlyLoadingFile == targetFile &&
          _bytes == null &&
          _thumbnailBytes == null) {
        setState(
          () => _error = context.l10n.encryptedImageLoadFailedWithReasonMessage(
            '$e',
          ),
        );
      }
    } finally {
      if (!_isFullResLoaded && _currentlyLoadingFile == targetFile) {
        _currentlyLoadingFile = null;
      }
    }
  }

  String _previewFailureMessage(ImagePreviewUnavailableReason reason) =>
      reason == ImagePreviewUnavailableReason.tooLarge
      ? context.l10n.imagePreviewTooLargeMessage
      : context.l10n.imagePreviewOutOfMemoryMessage;

  void _onPreviewUnavailable(ImagePreviewUnavailableReason reason) {
    setState(() => _previewFailure = reason);
    // With a thumbnail already on screen build() has nowhere to put an
    // error, so say why the picture is staying soft instead.
    if (_thumbnailBytes != null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(_previewFailureMessage(reason))),
      );
    }
  }

  Future<void> _loadThumbnailFromCache(String targetFile) async {
    try {
      final thumb = await _thumbnailCache.fetch(
        container: widget.container,
        filePath: targetFile,
        mode: widget.thumbnailCacheMode,
        quality: widget.thumbnailQuality,
      );
        if (thumb != null &&
          mounted &&
          _currentlyLoadingFile == targetFile &&
          !_isFullResLoaded) {
        setState(() {
          _thumbnailBytes = thumb;
        });
        _sniffAndNotifySize(thumb);
      }
    } catch (_) {
      // The thumbnail is only a placeholder shown while the full-res image
      // loads; a failure here just means no preview, not a failure to load
      // the actual image (handled separately, above).
    }
  }

  @override
  void dispose() {
    _cancelPendingLoad();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  style: TextStyle(color: cs.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                    });
                    _loadImage();
                  },
                  icon: const Icon(Icons.refresh, size: 16),
                  label: Text(context.l10n.retryButton),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.errorContainer,
                    foregroundColor: cs.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final previewFailure = _previewFailure;
    if (previewFailure != null && _bytes == null && _thumbnailBytes == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.image_not_supported_outlined, color: cs.onSurface),
              const SizedBox(height: 12),
              Text(
                _previewFailureMessage(previewFailure),
                style: TextStyle(color: cs.onSurface, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              // "Too large" is permanent for this file; "out of memory" may
              // well work after other apps have been closed.
              if (previewFailure == ImagePreviewUnavailableReason.outOfMemory)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _previewFailure = null);
                      _loadImage();
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(context.l10n.retryButton),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    if (_bytes == null && _thumbnailBytes == null) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
      );
    }

    final isAvif = widget.fileName.toLowerCase().endsWith('.avif');
    if (isAvif && !_isLargeImagePreview) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_thumbnailBytes != null)
            Image.memory(
              _thumbnailBytes!,
              fit: widget.fit,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          if (_isFullResLoaded && _bytes != null)
            NativeAvifWidget(avifBytes: _bytes!, fit: widget.fit),
        ],
      );
    }

    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    final headroom = MediaViewerConstants.fullResDecodeZoomHeadroom;
    final capWidth = (mq.size.width * dpr * headroom).round().clamp(1, 1 << 20);
    final capHeight = (mq.size.height * dpr * headroom).round().clamp(
      1,
      1 << 20,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_thumbnailBytes != null)
          Image.memory(
            _thumbnailBytes!,
            fit: widget.fit,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        if (_isFullResLoaded && _bytes != null)
          Image(
            image: ResizeImage(
              MemoryImage(_bytes!),
              width: capWidth,
              height: capHeight,
              policy: ResizeImagePolicy.fit,
            ),
            fit: widget.fit,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) => Center(
              child: Text(
                context.l10n.invalidOrCorruptedImageMessage,
                style: TextStyle(color: cs.error),
              ),
            ),
          ),
      ],
    );
  }
}
