import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';
import 'package:vaultexplorer/features/library/widgets/library_cover.dart';

/// Where every cover in the music views comes from, across all containers.
///
/// A cover is, in order of preference: one the person chose by hand for that
/// album or artist (the app has no internet, so there is no way to fetch one),
/// then the picture embedded in the track's own file. Hand-chosen covers are
/// shrunk to a small PNG and saved with the container they were chosen in: inside
/// a writable vault, in the app's encrypted storage otherwise. Embedded covers
/// are only ever read on demand into a memory-only cache.
class MusicCovers {
  final VaultFileIoApi _fileIo;
  final LibraryIndexStore _store;
  final MountedContainer? Function(String uri) _containerOf;

  MusicCovers({
    required VaultFileIoApi fileIo,
    required LibraryIndexStore store,
    required MountedContainer? Function(String uri) containerOf,
  })  : _fileIo = fileIo,
        _store = store,
        _containerOf = containerOf;

  /// Bumped whenever a hand-chosen cover is added, changed or removed, so
  /// covers already on screen redraw.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<String, LibraryCoverSource> _sources = {};

  /// Container uri -> (album/artist key -> PNG bytes).
  final Map<String, Map<String, Uint8List>> _custom = {};

  /// The reader for [uri]'s files, created on first use; null once the
  /// container's library has been dropped.
  LibraryCoverSource? sourceFor(String uri) {
    final existing = _sources[uri];
    if (existing != null) return existing;
    final container = _containerOf(uri);
    if (container == null) return null;
    return _sources[uri] = LibraryCoverSource(container: container, fileIo: _fileIo);
  }

  /// Loads the hand-chosen covers saved for [container].
  Future<void> loadCustom(MountedContainer container) async {
    final saved = await _store.loadCovers(container);
    _custom[container.uri] = saved;
    if (saved.isNotEmpty) revision.value++;
  }

  /// The hand-chosen cover for [groupKey] from any container, or null.
  Uint8List? customFor(String? groupKey) {
    if (groupKey == null) return null;
    for (final m in _custom.values) {
      final b = m[groupKey];
      if (b != null) return b;
    }
    return null;
  }

  bool hasCustom(String groupKey) => customFor(groupKey) != null;

  /// The picture embedded in [track]'s file, read on demand.
  Future<Uint8List?> embeddedFor(LibraryTrack track) async =>
      sourceFor(track.source)?.coverFor(track);

  /// Sets [rawImage] (any format Flutter can decode) as the cover for
  /// [groupKey], saved with [home]. Returns false if the image could not be
  /// decoded or saved.
  Future<bool> setCustom(MountedContainer home, String groupKey, Uint8List rawImage) async {
    final png = await shrinkToPng(rawImage);
    if (png == null) return false;
    final map = _custom.putIfAbsent(home.uri, () => {});
    map[groupKey] = png;
    revision.value++;
    return _store.saveCovers(home, Map<String, Uint8List>.of(map));
  }

  /// Removes the hand-chosen cover for [groupKey] wherever it was saved.
  Future<void> removeCustom(String groupKey) async {
    for (final entry in _custom.entries.toList()) {
      if (!entry.value.containsKey(groupKey)) continue;
      entry.value.remove(groupKey);
      final container = _containerOf(entry.key);
      if (container != null) {
        await _store.saveCovers(container, Map<String, Uint8List>.of(entry.value));
      }
    }
    revision.value++;
  }

  /// Decodes [source] and re-encodes it at most [maxSide] pixels wide, as PNG.
  /// Never enlarges. Null when it is not a decodable image.
  static Future<Uint8List?> shrinkToPng(Uint8List source, {int maxSide = 512}) async {
    try {
      final codec = await ui.instantiateImageCodec(
        source,
        targetWidth: maxSide,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Drops everything held for a container whose library was closed.
  void release(String uri) {
    _sources.remove(uri)?.dispose();
    _custom.remove(uri);
  }

  void dispose() {
    for (final s in _sources.values) {
      s.dispose();
    }
    _sources.clear();
    _custom.clear();
    revision.dispose();
  }
}
