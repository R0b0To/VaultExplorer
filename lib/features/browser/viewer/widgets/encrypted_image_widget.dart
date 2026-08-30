import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/full_res_image_cache.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'native_avif_widget.dart';

class EncryptedImageWidget extends StatefulWidget {
  final MountedContainer container;
  final String fileName;
  final Uint8List? prefetchedBytes;
  final BoxFit fit;
  final VoidCallback? onError;
  final ThumbnailQuality thumbnailQuality;
  final ThumbnailCacheMode thumbnailCacheMode;

  const EncryptedImageWidget({
    super.key,
    required this.container,
    required this.fileName,
    this.prefetchedBytes,
    required this.fit,
    this.onError,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    this.thumbnailCacheMode = ThumbnailCacheMode.appCache,
  });

  @override
  State<EncryptedImageWidget> createState() => _EncryptedImageWidgetState();
}

class _EncryptedImageWidgetState extends State<EncryptedImageWidget> {
  Uint8List? _bytes;
  Uint8List? _thumbnailBytes;
  String? _error;
  bool _isFullResLoaded = false;
  String? _currentlyLoadingFile;
  Completer<void>? _limiterCompleter;

  @override
  void initState() {
    super.initState();
    _thumbnailBytes = widget.prefetchedBytes ??
        ThumbnailCacheService.getFromMemory(
            widget.container, widget.fileName, widget.thumbnailQuality);
    final cachedFullRes =
        FullResImageCache.get(widget.container, widget.fileName);
    if (cachedFullRes != null) {
      _bytes = cachedFullRes;
      _isFullResLoaded = true;
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
      _thumbnailBytes = widget.prefetchedBytes ??
          ThumbnailCacheService.getFromMemory(
              widget.container, widget.fileName, widget.thumbnailQuality);
      final cachedFullRes =
          FullResImageCache.get(widget.container, widget.fileName);
      if (cachedFullRes != null) {
        _bytes = cachedFullRes;
        _isFullResLoaded = true;
      } else {
        _isFullResLoaded = false;
        _bytes = null;
        _loadImage();
      }
    } else if (!_isFullResLoaded && _currentlyLoadingFile == null) {
      _loadImage();
    } else if (!_isFullResLoaded &&
        widget.prefetchedBytes != null &&
        _thumbnailBytes == null) {
      setState(() {
        _thumbnailBytes = widget.prefetchedBytes;
      });
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
      final memThumb = ThumbnailCacheService.getFromMemory(
          widget.container, targetFile, widget.thumbnailQuality);
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
        });
      }
      return;
    }

    _currentlyLoadingFile = targetFile;
    final completer = Completer<void>();
    _limiterCompleter = completer;

    if (_thumbnailBytes == null) {
      _loadThumbnailFromCache(targetFile);
    }

    try {
      final data = await FullResImageCache.fetch(
        widget.container,
        targetFile,
        completer,
        isStillWanted: () => mounted && _currentlyLoadingFile == targetFile,
      );
      if (_limiterCompleter == completer) _limiterCompleter = null;
      if (!mounted || _currentlyLoadingFile != targetFile) return;
      if (data == null) {
        if (_bytes == null && _thumbnailBytes == null) {
          setState(
              () => _error = context.l10n.encryptedImageLoadFailedMessage);
        }
        return;
      }
      setState(() {
        _error = null;
        _bytes = data;
        _isFullResLoaded = true;
      });
    } catch (e) {
      if (_limiterCompleter == completer) _limiterCompleter = null;
      if (mounted &&
          _currentlyLoadingFile == targetFile &&
          _bytes == null &&
          _thumbnailBytes == null) {
        setState(() => _error =
            context.l10n.encryptedImageLoadFailedWithReasonMessage('$e'));
      }
    } finally {
      if (!_isFullResLoaded && _currentlyLoadingFile == targetFile) {
        _currentlyLoadingFile = null;
      }
    }
  }

  Future<void> _loadThumbnailFromCache(String targetFile) async {
    try {
      final thumb = await ThumbnailCacheService.get(
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
    if (isAvif) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_thumbnailBytes != null)
            Image.memory(
              _thumbnailBytes!,
              fit: widget.fit,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          if (_isFullResLoaded && _bytes != null)
            NativeAvifWidget(
              avifBytes: _bytes!,
              fit: widget.fit,
            ),
        ],
      );
    }

    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    final headroom = MediaViewerConstants.fullResDecodeZoomHeadroom;
    final capWidth =
        (mq.size.width * dpr * headroom).round().clamp(1, 1 << 20);
    final capHeight =
        (mq.size.height * dpr * headroom).round().clamp(1, 1 << 20);

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
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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