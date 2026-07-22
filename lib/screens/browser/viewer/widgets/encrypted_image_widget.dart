// lib/screens/browser/viewer/widgets/encrypted_image_widget.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '/../../models/mounted_container.dart';
import '/../../services/full_res_image_cache.dart';
import '/../../services/thumbnail_cache_service.dart';

class EncryptedImageWidget extends StatefulWidget {
  final MountedContainer container;
  final String fileName;
  final Uint8List? prefetchedBytes;
  final BoxFit fit;
  final VoidCallback? onError;

  const EncryptedImageWidget({
    super.key,
    required this.container,
    required this.fileName,
    this.prefetchedBytes,
    required this.fit,
    this.onError,
  });

  @override
  State<EncryptedImageWidget> createState() => _EncryptedImageWidgetState();
}

class _EncryptedImageWidgetState extends State<EncryptedImageWidget> {
  Uint8List? _bytes;
  String? _error;
  bool _isFullResLoaded = false;
  String? _currentlyLoadingFile;
  Completer<void>? _limiterCompleter;

  @override
  void initState() {
    super.initState();
    final cachedFullRes =
        FullResImageCache.get(widget.container, widget.fileName);
    if (cachedFullRes != null) {
      _bytes = cachedFullRes;
      _isFullResLoaded = true;
    } else {
      _bytes = widget.prefetchedBytes ??
          ThumbnailCacheService.getFromMemory(
              widget.container, widget.fileName);
      _loadImage();
    }
  }

  @override
  void didUpdateWidget(covariant EncryptedImageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.fileName != oldWidget.fileName) {
      _cancelPendingLoad();
      _error = null;
      final cachedFullRes =
          FullResImageCache.get(widget.container, widget.fileName);
      if (cachedFullRes != null) {
        _bytes = cachedFullRes;
        _isFullResLoaded = true;
      } else {
        _isFullResLoaded = false;
        _bytes = widget.prefetchedBytes ??
            ThumbnailCacheService.getFromMemory(
                widget.container, widget.fileName);
        _loadImage();
      }
    } else if (!_isFullResLoaded && _currentlyLoadingFile == null) {
      _loadImage();
    } else if (!_isFullResLoaded &&
        widget.prefetchedBytes != null &&
        _bytes == null) {
      setState(() => _bytes = widget.prefetchedBytes);
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

    try {
      // Gated through FullResImageCache's shared LIFO limiter + in-flight
      // de-dup (see full_res_image_cache.dart) instead of calling
      // vaultExplorerApi directly: this caps how many full-resolution
      // reads can ever be in native flight at once from the media viewer,
      // and lets this specific request drop out of the queue entirely
      // (via the completer above) if the user swipes past this page
      // before it's granted a turn.
      final data = await FullResImageCache.fetch(
        widget.container,
        targetFile,
        completer,
        isStillWanted: () => mounted && _currentlyLoadingFile == targetFile,
      );

      if (_limiterCompleter == completer) _limiterCompleter = null;
      if (!mounted || _currentlyLoadingFile != targetFile) return;

      if (data == null) {
        if (_bytes == null) {
          setState(() => _error = 'Failed to load encrypted image');
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
      if (mounted && _currentlyLoadingFile == targetFile && _bytes == null) {
        setState(() => _error = 'Failed to load encrypted image: $e');
      }
    } finally {
      if (!_isFullResLoaded && _currentlyLoadingFile == targetFile) {
        _currentlyLoadingFile = null;
      }
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
                label: const Text('Retry'),
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

    if (_bytes == null) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
      );
    }

    return Image.memory(
      _bytes!,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      gaplessPlayback: true, // <--- KEEPS THE THUMBNAIL VISIBLE WHILE DECODING HIGH-RES
      errorBuilder: (context, error, stackTrace) => Center(
        child: Text(
          'Invalid or corrupted image format.',
          style: TextStyle(color: cs.error),
        ),
      ),
    );
  }
}