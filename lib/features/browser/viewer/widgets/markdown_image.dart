import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_image_cache.dart';

/// An image embedded in a markdown document, read from the vault.
///
/// Layout is deliberately independent of load state: once the image's pixel
/// size is known (see [MarkdownImageCache]) the widget always occupies exactly
/// the final box, whether it is still loading, decoding or already painted.
/// That keeps the surrounding lazy list from re-measuring while scrolling.
class MarkdownImage extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String resolvedPath;
  final String alt;

  /// Shared cache of the owning viewer. When null the widget keeps a private
  /// one (used by one-off previews such as the image dialog).
  final MarkdownImageCache? cache;

  const MarkdownImage({
    super.key,
    required this.container,
    required this.resolvedPath,
    required this.alt,
    this.cache,
  });

  static const _decodableExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
  };

  /// Whether [path] has an extension this widget can decode.
  static bool isDecodablePath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    final ext = path.substring(dot + 1).toLowerCase();
    return _decodableExtensions.contains(ext);
  }

  @override
  ConsumerState<MarkdownImage> createState() => _MarkdownImageState();
}

class _MarkdownImageState extends ConsumerState<MarkdownImage> {
  static const double _maxHeight = 420;
  static const double _placeholderHeight = 160;
  static const int _maxDecodeWidth = 4096;

  MarkdownImageCache? _ownCache;
  Uint8List? _bytes;
  ui.Size? _size;
  MarkdownImageFailure? _failure;
  int _generation = 0;

  MarkdownImageCache get _cache =>
      widget.cache ??
      (_ownCache ??= MarkdownImageCache.forVault(
        api: ref.read(vaultFileIoApiProvider),
        container: widget.container,
      ));

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant MarkdownImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final containerChanged =
        oldWidget.container.volId != widget.container.volId;
    final cacheChanged = oldWidget.cache != widget.cache;
    if (containerChanged || cacheChanged) {
      _ownCache?.dispose();
      _ownCache = null;
    }
    if (oldWidget.resolvedPath != widget.resolvedPath ||
        containerChanged ||
        cacheChanged) {
      _resolve();
    }
  }

  @override
  void dispose() {
    _generation++;
    _ownCache?.dispose();
    super.dispose();
  }

  void _resolve() {
    final token = ++_generation;
    _bytes = null;
    _size = null;
    _failure = null;
    if (!MarkdownImage.isDecodablePath(widget.resolvedPath)) return;

    final cache = _cache;
    final path = widget.resolvedPath;

    // Synchronous fast path: scrolling back to an image that was already
    // loaded renders it in the very first frame, with no spinner at all.
    _size = cache.knownSize(path);
    _bytes = cache.cachedBytes(path);
    _failure = cache.failureOf(path);
    if (_bytes != null || _failure != null) return;

    // The size usually arrives first (the owning viewer prefetches every
    // image header in the background); adopting it right away means the box
    // is already final while the pixels are still being read.
    if (_size == null) {
      _listen<ui.Size?>(cache.resolveSize(path), token, (size) {
        if (size != null) _size ??= size;
      });
    }

    _listen<Uint8List?>(cache.loadBytes(path), token, (bytes) {
      _bytes = bytes;
      _size = cache.knownSize(path) ?? _size;
      _failure = bytes == null
          ? (cache.failureOf(path) ?? MarkdownImageFailure.unreadable)
          : null;
    });
  }

  /// Applies [apply] when [future] completes, calling setState only when the
  /// completion is asynchronous (setState is not allowed during initState,
  /// and a SynchronousFuture runs its callback immediately).
  void _listen<T>(Future<T> future, int token, void Function(T value) apply) {
    var completedSynchronously = true;
    future.then((value) {
      if (!mounted || token != _generation) return;
      if (completedSynchronously) {
        apply(value);
      } else {
        setState(() => apply(value));
      }
    });
    completedSynchronously = false;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (!MarkdownImage.isDecodablePath(widget.resolvedPath)) {
      return _fallbackCard(cs, context.l10n.archivePreviewNotAvailableMessage);
    }

    final failure = _failure;
    if (failure != null) {
      return _fallbackCard(
        cs,
        failure == MarkdownImageFailure.invalid
            ? context.l10n.invalidOrCorruptedImageMessage
            : context.l10n.encryptedImageLoadFailedMessage,
      );
    }

    final size = _size;
    final bytes = _bytes;

    // Layout never depends on load state. Once the pixel size is known the
    // box is exactly the final one (full width, height from the aspect ratio,
    // capped) while loading, decoding and after painting, so the lazy list
    // around it never has to re-measure. Built from AspectRatio rather than
    // a LayoutBuilder so it still works under intrinsic-size parents such as
    // AlertDialog.
    if (size == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: double.infinity,
          height: _placeholderHeight,
          child: _loadingBox(cs),
        ),
      );
    }

    final Widget content;
    if (bytes == null) {
      content = _loadingBox(cs);
    } else {
      // Decode at (at most) screen resolution instead of full resolution:
      // far less memory and a much faster decode for big photos.
      final screenPx =
          MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context);
      final cacheWidth = screenPx.isFinite && screenPx > 0
          ? screenPx.round().clamp(1, _maxDecodeWidth)
          : null;
      content = Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        cacheWidth: cacheWidth,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return _loadingBox(cs);
        },
        errorBuilder: (context, error, stackTrace) => Align(
          alignment: Alignment.topCenter,
          child: _fallbackCard(cs, context.l10n.invalidOrCorruptedImageMessage),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _maxHeight),
        child: AspectRatio(
          aspectRatio: size.width / size.height,
          child: content,
        ),
      ),
    );
  }

  Widget _loadingBox(ColorScheme cs) {
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }

  Widget _fallbackCard(ColorScheme cs, String message) {
    final name = widget.resolvedPath.contains('/')
        ? widget.resolvedPath.substring(widget.resolvedPath.lastIndexOf('/') + 1)
        : widget.resolvedPath;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.alt.isNotEmpty ? widget.alt : name,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
