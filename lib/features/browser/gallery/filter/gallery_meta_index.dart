import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

import 'gallery_meta.dart';
import 'gallery_meta_parser.dart';

/// Reads the first [length] bytes of [path] in the source [volId].
typedef GalleryHeaderReader =
    Future<Uint8List?> Function(int volId, String path, int length);

/// Where the index of one source is kept between sessions.
abstract interface class GalleryMetaStorage {
  /// The stored text, or null when nothing is stored (or it cannot be read).
  Future<String?> load(int volId);

  /// Whether [json] was stored.
  Future<bool> save(int volId, String json);
}

/// One file the index should know about.
class GalleryIndexRequest {
  const GalleryIndexRequest(this.volId, this.path, this.size, this.mtime);

  final int volId;

  /// Path inside the source.
  final String path;
  final int size;
  final int mtime;
}

// Top-level so `compute` can run them in another isolate without dragging the
// index (a ChangeNotifier with timers) along in a closure.
Object? _decodeIndex(String text) => jsonDecode(text);

String _encodeIndex(Map<String, List<Object?>> snapshot) =>
    jsonEncode({'v': GalleryMetaIndex.storageVersion, 'e': snapshot});

class _Stored {
  const _Stored(this.size, this.mtime, this.meta);
  final int size;
  final int mtime;
  final GalleryMeta meta;
}

/// The date, place, camera, keywords and rating of every photo the gallery has
/// looked at, which the filter, the sections and the search need and which no
/// directory listing carries.
///
/// Photos are read lazily and in the background: [ensure] queues the ones not
/// known yet (or changed since: an entry is valid only for the size and date
/// it was read at), a few at a time, and [notifyListeners] fires (at most every
/// [notifyEvery]) as results arrive, so a view can refilter as the index fills.
/// Only the start of each file is read ([GalleryMetaParser.headerBytes]).
///
/// With a [storage] the index is loaded at the first request for a source and
/// saved back (in the background, in batches) so the next session starts with
/// everything already known. Without one it lives for the session only, which
/// is what the phone's own storage gets: nothing is written to it.
class GalleryMetaIndex extends ChangeNotifier {
  GalleryMetaIndex({
    required this.readHeader,
    this.storage,
    this.concurrency = 3,
    this.notifyEvery = const Duration(milliseconds: 500),
    this.saveEvery = 200,
  });

  /// Upper bound of entries kept per source; the oldest are dropped first and
  /// simply read again if they are needed.
  static const int maxEntriesPerSource = 200000;

  static const int storageVersion = 1;

  final GalleryHeaderReader readHeader;
  final GalleryMetaStorage? storage;
  final int concurrency;
  final Duration notifyEvery;
  final int saveEvery;

  final Map<int, LinkedHashMap<String, _Stored>> _stored = {};
  final Map<int, Future<void>> _loading = {};
  final Set<int> _dirty = {};
  final Map<int, Future<void>> _writing = {};
  final List<GalleryIndexRequest> _queue = [];
  final Set<String> _queued = {};

  int _inFlight = 0;
  int _revision = 0;
  int _enqueued = 0;
  int _done = 0;
  int _sinceSave = 0;
  bool _disposed = false;
  Timer? _notifyTimer;
  bool _notifyDue = false;

  /// Bumped whenever the answer of [lookup] may have changed.
  int get revision => _revision;

  /// Photos waiting to be read or being read.
  int get pending => _queue.length + _inFlight;

  /// Photos read since the queue was last empty, and how many were queued in
  /// that time: the progress of the current indexing run.
  int get done => _done;
  int get total => _enqueued;
  bool get isIndexing => pending > 0;

  String _key(int volId, String path) => '$volId|$path';

  /// What is known about the file, or null when it is unknown or the file
  /// changed since it was read.
  GalleryMeta? lookup(int volId, String path, int size, int mtime) {
    final s = _stored[volId]?[path];
    if (s == null || s.size != size || s.mtime != mtime) return null;
    return s.meta;
  }

  /// Loads what was stored for [volIds] (nothing is read from the files).
  Future<void> loadStored(Iterable<int> volIds) =>
      Future.wait([for (final v in volIds.toSet()) _load(v)]);

  /// Queues every request not known yet. Returns once the stored indexes of
  /// the sources involved are loaded (not once the files are read).
  Future<void> ensure(Iterable<GalleryIndexRequest> requests) async {
    final list = requests.toList(growable: false);
    final vols = {for (final r in list) r.volId};
    await Future.wait([for (final v in vols) _load(v)]);
    if (_disposed) return;
    var added = 0;
    for (final r in list) {
      if (!GalleryMetaParser.canParse(_extensionOf(r.path))) continue;
      if (r.size <= 0) continue;
      if (lookup(r.volId, r.path, r.size, r.mtime) != null) continue;
      if (!_queued.add(_key(r.volId, r.path))) continue;
      _queue.add(r);
      added++;
    }
    if (added == 0) {
      _pump();
      return;
    }
    if (_inFlight == 0 && _done >= _enqueued) {
      // A fresh run: start the progress count over.
      _done = 0;
      _enqueued = 0;
    }
    _enqueued += added;
    _scheduleNotify();
    _pump();
  }

  /// Forgets what is queued (what is being read finishes and is kept).
  void cancel() {
    for (final r in _queue) {
      _queued.remove(_key(r.volId, r.path));
    }
    _enqueued -= _queue.length;
    _queue.clear();
    _scheduleNotify();
  }

  /// Writes everything not saved yet. Call before a source is locked.
  Future<void> flush() async {
    await Future.wait([for (final v in _dirty.toList()) _save(v)]);
  }

  /// Drops what is held (not what is stored) for [volId]; its container was
  /// locked.
  void forget(int volId) {
    _stored.remove(volId);
    _loading.remove(volId);
    _dirty.remove(volId);
    _queue.removeWhere((r) {
      final hit = r.volId == volId;
      if (hit) _queued.remove(_key(r.volId, r.path));
      return hit;
    });
    _revision++;
    _scheduleNotify();
  }

  // ── Reading ──────────────────────────────────────────────────────────────

  void _pump() {
    while (!_disposed && _inFlight < concurrency && _queue.isNotEmpty) {
      final r = _queue.removeAt(0);
      _inFlight++;
      unawaited(_process(r));
    }
  }

  Future<void> _process(GalleryIndexRequest r) async {
    GalleryMeta? meta;
    try {
      final length = math.min(r.size, GalleryMetaParser.headerBytes);
      final bytes = await readHeader(r.volId, r.path, length);
      if (bytes != null) meta = GalleryMetaParser.parse(bytes);
    } catch (_) {
      // Unreadable now (locked, removed): left unknown, asked again later.
    }
    _inFlight--;
    _done++;
    _queued.remove(_key(r.volId, r.path));
    if (_disposed) return;
    if (meta != null) {
      final map = _stored.putIfAbsent(r.volId, LinkedHashMap.new);
      map.remove(r.path); // a re-read entry moves to the newest end
      map[r.path] = _Stored(r.size, r.mtime, meta);
      _revision++;
      _dirty.add(r.volId);
      _sinceSave++;
      if (_sinceSave >= saveEvery) {
        _sinceSave = 0;
        unawaited(flush());
      }
    }
    if (_queue.isEmpty && _inFlight == 0) {
      _sinceSave = 0;
      unawaited(flush());
    }
    _scheduleNotify(force: _queue.isEmpty && _inFlight == 0);
    _pump();
  }

  void _scheduleNotify({bool force = false}) {
    if (_disposed) return;
    if (force) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      _notifyDue = false;
      notifyListeners();
      return;
    }
    _notifyDue = true;
    _notifyTimer ??= Timer(notifyEvery, () {
      _notifyTimer = null;
      if (_disposed || !_notifyDue) return;
      _notifyDue = false;
      notifyListeners();
    });
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _load(int volId) {
    return _loading[volId] ??= _doLoad(volId);
  }

  Future<void> _doLoad(int volId) async {
    final map = _stored.putIfAbsent(volId, LinkedHashMap.new);
    final st = storage;
    if (st == null) return;
    try {
      final text = await st.load(volId);
      if (text == null || text.isEmpty) return;
      final decoded = await compute(_decodeIndex, text);
      if (decoded is! Map || decoded['v'] != storageVersion) return;
      final entries = decoded['e'];
      if (entries is! Map) return;
      for (final e in entries.entries) {
        final path = e.key;
        final v = e.value;
        if (path is! String || v is! List || v.length != 11) continue;
        final size = v[0];
        final mtime = v[1];
        if (size is! int || mtime is! int) continue;
        final meta = GalleryMeta.tryFromJson(v.sublist(2));
        if (meta == null) continue;
        // Anything read this session is newer than what was stored.
        map.putIfAbsent(path, () => _Stored(size, mtime, meta));
      }
      _revision++;
      _scheduleNotify();
    } catch (_) {
      // A damaged index counts as none; the next run replaces it.
    }
  }

  Future<void> _save(int volId) {
    final st = storage;
    if (st == null) {
      _dirty.remove(volId);
      return Future.value();
    }
    // One write at a time per source; a later request waits for the running
    // one and then writes the newest state.
    final previous = _writing[volId] ?? Future<void>.value();
    final next = previous.then((_) async {
      if (!_dirty.remove(volId)) return;
      final map = _stored[volId];
      if (map == null || map.isEmpty) return;
      while (map.length > maxEntriesPerSource) {
        map.remove(map.keys.first);
      }
      final snapshot = <String, List<Object?>>{
        for (final e in map.entries)
          e.key: [e.value.size, e.value.mtime, ...e.value.meta.toJson()],
      };
      try {
        final text = await compute(_encodeIndex, snapshot);
        final ok = await st.save(volId, text);
        if (!ok) _dirty.add(volId);
      } catch (_) {
        _dirty.add(volId);
      }
    });
    _writing[volId] = next;
    return next;
  }

  static String _extensionOf(String path) {
    final slash = path.lastIndexOf('/');
    final name = slash < 0 ? path : path.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    _queue.clear();
    super.dispose();
  }
}

/// Keeps a vault's gallery index in `/.vaultexplorer/gallery_meta.json`, inside
/// the encrypted vault next to its other per-vault files (see
/// `VaultMediaIndexStorage`): encrypted with the vault, carried with it, and
/// readable only while it is unlocked. The phone's own storage and read-only
/// vaults get nothing written.
class VaultGalleryMetaStorage implements GalleryMetaStorage {
  VaultGalleryMetaStorage(this._io, this._containerOf, {this.allowWrite});

  static const String fileName = 'gallery_meta.json';
  static const String filePath = '$kVaultMetaDir/$fileName';

  final VaultFileIoApi _io;
  final MountedContainer? Function(int volId) _containerOf;

  /// Whether the source may be written to at all (false when its owner turned
  /// persistent caching off: nothing derived from the files is then kept).
  final bool Function(int volId)? allowWrite;

  MountedContainer? _writable(int volId) {
    final c = _containerOf(volId);
    if (c == null || c.isLocalStorage) return null;
    return c;
  }

  @override
  Future<String?> load(int volId) async {
    final c = _writable(volId);
    if (c == null) return null;
    final raw = await _io.listDirectory(c, kVaultMetaDir);
    if (raw == null) return null;
    final exists = RawEntry.parseAll(raw).any((e) => !e.isDir && e.name == fileName);
    if (!exists) return null;
    final bytes = await _io.readWholeFile(c, filePath);
    if (bytes == null || bytes.isEmpty) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  @override
  Future<bool> save(int volId, String json) async {
    final c = _writable(volId);
    if (c == null || c.readOnly) return false;
    if (allowWrite != null && !allowWrite!(volId)) return false;
    await _io.createDirectory(c, kVaultMetaDir);
    return _io.writeWholeFile(c, filePath, Uint8List.fromList(utf8.encode(json)));
  }
}
