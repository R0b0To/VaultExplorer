import 'dart:async';
import 'dart:typed_data';

import 'package:vaultexplorer/data/models/mounted_container.dart';

import 'media_index.dart';
import 'media_index_codec.dart';

/// Where a container's media index is kept between sessions.
abstract interface class MediaIndexStorage {
  /// The stored bytes, or null when nothing is stored. Throws when something
  /// is stored but could not be read, so the caller never saves over an index
  /// it failed to look at.
  Future<Uint8List?> read(MountedContainer container);

  /// Whether the bytes were stored.
  Future<bool> write(MountedContainer container, Uint8List bytes);
}

/// What the service may do with a container's persisted index.
enum MediaIndexAccess {
  /// Nothing is read or written; sizes only live for this session (phone and
  /// external storage, which must not get a hidden folder dropped into them).
  memoryOnly,

  /// An existing stored index is used but never changed (a read-only vault, or
  /// thumbnail caching switched off).
  readOnly,

  /// Read at open, saved as it grows.
  readWrite,
}

class _ContainerState {
  _ContainerState(this.container);

  MountedContainer container;
  MediaIndexAccess access = MediaIndexAccess.memoryOnly;
  MediaIndex index = MediaIndex();
  Future<void>? loading;
  bool ready = false;

  /// Set when an index exists that could not be read: saving would replace
  /// something never looked at.
  bool writeBlocked = false;
  int failures = 0;

  Timer? timer;
  DateTime? dirtySince;
  Future<void> writing = Future.value();

  bool get canWrite =>
      access == MediaIndexAccess.readWrite && !writeBlocked && failures < 3;
}

/// Width/height of every media file seen in a container, kept in memory for
/// the session and, for a writable vault, saved inside it.
///
/// It lives in `/.vaultexplorer/media_index.bin`, next to the other per-vault
/// files (marks, sync rules): encrypted with the vault, carried with it to
/// another device, readable only while it is unlocked. See [MediaIndex] for
/// what an entry is and when it counts as stale, and [MediaIndexCodec] for the
/// file format.
///
/// Saving is batched (a few seconds after the last new measurement, never
/// later than [maxFlushWait] after the first) and runs in the background; it
/// never blocks scrolling. `VaultLifecycleApi.lockContainer` flushes before it
/// locks ([flushForUri]); [forgetForUri] runs once the container is locked.
class MediaIndexService {
  MediaIndexService({
    required this.storage,
    this.flushDelay = const Duration(seconds: 4),
    this.maxFlushWait = const Duration(seconds: 20),
    this.onWarning,
  });

  /// The app's service, for the lock hooks that have no `ref`.
  static MediaIndexService? current;

  final MediaIndexStorage storage;
  final Duration flushDelay;
  final Duration maxFlushWait;
  final void Function(String message, Object? error)? onWarning;

  final Map<String, _ContainerState> _states = {};

  /// Whether [attach] has finished for [container] ([lookup] and [record] only
  /// work once it has).
  bool isReady(MountedContainer container) =>
      _states[container.uri]?.ready ?? false;

  /// Loads the container's stored index (once per mount) and applies
  /// [access]. Safe to call again; calls that overlap share one read.
  Future<void> attach(MountedContainer container, MediaIndexAccess access) {
    final state = _states.putIfAbsent(
      container.uri,
      () => _ContainerState(container),
    );
    state.container = container;
    state.access = access;
    return state.loading ??= _load(state);
  }

  Future<void> _load(_ContainerState state) async {
    try {
      if (state.access != MediaIndexAccess.memoryOnly) {
        Uint8List? bytes;
        try {
          bytes = await storage.read(state.container);
        } catch (e) {
          // Never save over an index that exists but could not be read.
          state.writeBlocked = true;
          onWarning?.call('media index could not be read', e);
        }
        if (bytes != null && bytes.isNotEmpty) {
          final snapshot = await MediaIndexCodec.decodeAsync(bytes);
          if (snapshot != null) {
            state.index = MediaIndex(snapshot);
          } else {
            onWarning?.call('media index is unreadable; starting empty', null);
          }
        }
      }
    } finally {
      state.ready = true;
    }
  }

  /// Packed size of the file with `pathHash` (see `MediaPathHash`) if it is
  /// known and still valid for a file of [size] bytes modified at [mtimeSecs];
  /// 0 otherwise. Read it with [MediaIndex.widthOf] / [MediaIndex.heightOf].
  int lookup(
    MountedContainer container,
    int pathHash,
    int size,
    int mtimeSecs,
  ) {
    final state = _states[container.uri];
    if (state == null || !state.ready) return 0;
    return state.index.lookup(pathHash, size, mtimeSecs);
  }

  /// Remembers a measured size; saved in the background when the container
  /// allows it.
  void record(
    MountedContainer container,
    int pathHash,
    int size,
    int mtimeSecs,
    int width,
    int height,
  ) {
    final state = _states[container.uri];
    if (state == null || !state.ready) return;
    state.index.record(pathHash, size, mtimeSecs, width, height);
    if (state.index.hasUnsavedChanges && state.canWrite) _schedule(state);
  }

  void _schedule(_ContainerState state) {
    final now = DateTime.now();
    state.dirtySince ??= now;
    final waited = now.difference(state.dirtySince!);
    var delay = state.failures > 0 ? flushDelay * 6 : flushDelay;
    final remaining = maxFlushWait - waited;
    if (remaining < delay) delay = remaining.isNegative ? Duration.zero : remaining;
    state.timer?.cancel();
    state.timer = Timer(delay, () => unawaited(_flushState(state)));
  }

  /// Saves what has not been saved yet and completes when it is stored (or
  /// could not be). Never throws.
  Future<void> flush(MountedContainer container) =>
      _flushState(_states[container.uri]);

  Future<void> _flushState(_ContainerState? state) {
    if (state == null) return Future.value();
    state.timer?.cancel();
    state.timer = null;
    return state.writing = state.writing.then((_) => _writeOnce(state));
  }

  Future<void> _writeOnce(_ContainerState state) async {
    if (!state.ready || !state.canWrite || !state.index.hasUnsavedChanges) {
      state.dirtySince = null;
      return;
    }
    final revision = state.index.revision;
    try {
      final snapshot = state.index.compact();
      final bytes = await MediaIndexCodec.encodeAsync(snapshot);
      if (await storage.write(state.container, bytes)) {
        state.index.markSaved(revision);
        state.failures = 0;
        state.dirtySince = null;
      } else {
        state.failures++;
      }
    } catch (e) {
      state.failures++;
      onWarning?.call('media index save failed', e);
    }
    // More arrived while writing, or the write failed: try again later.
    if (state.index.hasUnsavedChanges && state.canWrite) _schedule(state);
  }

  /// Saves everything pending for every container.
  Future<void> flushAll() =>
      Future.wait([for (final s in _states.values.toList()) _flushState(s)]);

  /// Drops the in-memory index of [uri] (the container was locked).
  void forget(String uri) {
    final state = _states.remove(uri);
    state?.timer?.cancel();
  }

  void dispose() {
    for (final s in _states.values) {
      s.timer?.cancel();
    }
    _states.clear();
  }

  /// [flush] by container URI, for the code that locks a container (while it
  /// is still mounted).
  static Future<void> flushForUri(String uri) async {
    final service = current;
    if (service == null) return;
    await service._flushState(service._states[uri]);
  }

  /// [forget] by container URI, once the container is locked.
  static void forgetForUri(String uri) => current?.forget(uri);
}
