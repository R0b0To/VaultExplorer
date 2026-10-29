import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

typedef MarkdownImageReadAll = Future<Uint8List?> Function(String path);
typedef MarkdownImageReadHead =
    Future<Uint8List?> Function(String path, int length);

enum MarkdownImageFailure { unreadable, invalid }

/// Remembers, per markdown viewer, which images exist, how big they are and
/// (within a memory budget) their encoded bytes.
///
/// The markdown preview is a lazy list, so an image's widget is created and
/// destroyed over and over while the user scrolls. Without this cache every
/// re-creation re-read the image from the vault, showed a 160px spinner, then
/// a 0px box while decoding, and finally the real height. All of those height
/// changes happen above/below the viewport and shove the content around, which
/// is the "jitter" when scrolling.
///
/// With this cache:
///  * the size of an image is known (and never forgotten) after the first
///    time it is looked at, so the layout box is always the final size;
///  * [prefetchSizes] learns the sizes of every image in the document in the
///    background (reading only the file header when possible), so even the
///    first scroll through the document does not shift anything;
///  * encoded bytes are kept in a bounded LRU so scrolling back is instant and
///    does not hit the vault again.
class MarkdownImageCache {
  MarkdownImageCache({
    required this.readAll,
    required this.readHead,
    this.maxBytes = 48 * 1024 * 1024,
    this.prefetchConcurrency = 2,
  });

  /// Builds a cache that reads through [api] from [container].
  factory MarkdownImageCache.forVault({
    required VaultFileIoApi api,
    required MountedContainer container,
  }) {
    return MarkdownImageCache(
      readAll: (path) => api.readWholeFile(container, path),
      readHead: (path, length) async {
        final size = await api.getFileSize(container, path);
        if (size <= 0) return null;
        return api.readFileChunk(
          container,
          path,
          0,
          size < length ? size : length,
        );
      },
    );
  }

  /// How much of a file is read to learn its dimensions before falling back
  /// to reading the whole file.
  static const int headBytes = 64 * 1024;

  final MarkdownImageReadAll readAll;
  final MarkdownImageReadHead readHead;
  final int maxBytes;
  final int prefetchConcurrency;

  final Map<String, ui.Size> _sizes = {};
  final Map<String, MarkdownImageFailure> _failures = {};
  final LinkedHashMap<String, Uint8List> _bytes =
      LinkedHashMap<String, Uint8List>();
  int _bytesTotal = 0;

  final Map<String, Future<Uint8List?>> _loading = {};
  final Map<String, Future<ui.Size?>> _sizing = {};

  final Queue<String> _prefetchQueue = Queue<String>();
  final Set<String> _prefetchQueued = {};
  int _prefetchActive = 0;
  bool _disposed = false;

  ui.Size? knownSize(String path) => _sizes[path];

  MarkdownImageFailure? failureOf(String path) => _failures[path];

  /// Returns the cached bytes (marking them most recently used) or null.
  Uint8List? cachedBytes(String path) {
    final bytes = _bytes.remove(path);
    if (bytes == null) return null;
    _bytes[path] = bytes;
    return bytes;
  }

  /// Forgets failures so unreadable images are retried (e.g. when the
  /// markdown source changed and the file may exist now).
  void clearFailures() => _failures.clear();

  /// Reads (or returns the cached) encoded image. Completes with null when
  /// the file cannot be read or is not a decodable image; [failureOf] then
  /// says why.
  Future<Uint8List?> loadBytes(String path) {
    if (_disposed) return SynchronousFuture<Uint8List?>(null);
    final cached = cachedBytes(path);
    if (cached != null) return SynchronousFuture<Uint8List?>(cached);
    if (_failures.containsKey(path)) {
      return SynchronousFuture<Uint8List?>(null);
    }
    // Block body on purpose: an arrow body would return the very future
    // being removed, and whenComplete would then wait on itself forever.
    return _loading[path] ??= _loadBytes(path).whenComplete(() {
      _loading.remove(path);
    });
  }

  /// Learns the pixel size of an image, preferring to read only its header.
  Future<ui.Size?> resolveSize(String path) {
    if (_disposed) return SynchronousFuture<ui.Size?>(null);
    final known = _sizes[path];
    if (known != null) return SynchronousFuture<ui.Size?>(known);
    if (_failures.containsKey(path)) return SynchronousFuture<ui.Size?>(null);
    return _sizing[path] ??= _resolveSize(path).whenComplete(() {
      _sizing.remove(path);
    });
  }

  /// Queues [paths] (in order) so their sizes are known before the user
  /// scrolls to them. Cheap: runs in the background with limited concurrency.
  void prefetchSizes(Iterable<String> paths) {
    if (_disposed) return;
    for (final path in paths) {
      if (_sizes.containsKey(path) || _failures.containsKey(path)) continue;
      if (!_prefetchQueued.add(path)) continue;
      _prefetchQueue.add(path);
    }
    _pumpPrefetch();
  }

  void _pumpPrefetch() {
    while (!_disposed &&
        _prefetchActive < prefetchConcurrency &&
        _prefetchQueue.isNotEmpty) {
      final path = _prefetchQueue.removeFirst();
      _prefetchActive++;
      resolveSize(path)
          .catchError((Object _) => null)
          .whenComplete(() {
            _prefetchActive--;
            _prefetchQueued.remove(path);
            _pumpPrefetch();
          });
    }
  }

  Future<ui.Size?> _resolveSize(String path) async {
    // Header-only first: a 64 KB read instead of a multi-megabyte decrypt.
    try {
      final head = await readHead(path, headBytes);
      if (_disposed) return null;
      if (head != null && head.isNotEmpty) {
        final size = await _decodeSize(head);
        if (_disposed) return null;
        if (size != null) {
          _sizes.putIfAbsent(path, () => size);
          return _sizes[path];
        }
      }
    } catch (e) {
      debugPrint('MarkdownImageCache: header read failed for $path: $e');
    }

    // The header was not enough (or unreadable): read the whole file. This
    // also fills the bytes cache, so it is not wasted work.
    final bytes = await loadBytes(path);
    if (bytes == null) return null;
    return _sizes[path];
  }

  Future<Uint8List?> _loadBytes(String path) async {
    Uint8List? bytes;
    try {
      bytes = await readAll(path);
    } catch (e) {
      debugPrint('MarkdownImageCache: read failed for $path: $e');
    }
    if (_disposed) return null;
    if (bytes == null || bytes.isEmpty) {
      _failures[path] = MarkdownImageFailure.unreadable;
      return null;
    }

    final size = _sizes[path] ?? await _decodeSize(bytes);
    if (_disposed) return null;
    if (size == null) {
      _failures[path] = MarkdownImageFailure.invalid;
      return null;
    }

    _sizes.putIfAbsent(path, () => size);
    _putBytes(path, bytes);
    return bytes;
  }

  void _putBytes(String path, Uint8List bytes) {
    final previous = _bytes.remove(path);
    if (previous != null) _bytesTotal -= previous.length;
    _bytes[path] = bytes;
    _bytesTotal += bytes.length;
    // Evict least-recently-used entries, but always keep the newest one even
    // if it alone is over budget. Sizes are tiny and are never evicted.
    while (_bytesTotal > maxBytes && _bytes.length > 1) {
      final oldest = _bytes.keys.first;
      final removed = _bytes.remove(oldest);
      if (removed != null) _bytesTotal -= removed.length;
    }
  }

  /// Reads the pixel size from the image header without decoding pixels.
  /// Returns null when [data] is not (or not enough of) a decodable image.
  static Future<ui.Size?> _decodeSize(Uint8List data) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(data);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final width = descriptor.width;
      final height = descriptor.height;
      if (width <= 0 || height <= 0) return null;
      return ui.Size(width.toDouble(), height.toDouble());
    } catch (_) {
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  void dispose() {
    _disposed = true;
    _bytes.clear();
    _bytesTotal = 0;
    _sizes.clear();
    _failures.clear();
    _loading.clear();
    _sizing.clear();
    _prefetchQueue.clear();
    _prefetchQueued.clear();
  }
}
