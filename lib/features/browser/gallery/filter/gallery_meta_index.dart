import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'gallery_meta.dart';
import 'gallery_meta_parser.dart';
import 'gallery_meta_worker.dart';

/// Reads the first [length] bytes of [path] in the source [volId].
typedef GalleryHeaderReader =
    Future<Uint8List?> Function(int volId, String path, int length);

/// Parses one photo header (see [GalleryMetaWorker.parse]).
typedef GalleryHeaderParser = Future<GalleryMeta> Function(Uint8List bytes);

/// Where the index of one source is kept between sessions.
///
/// The index is stored as an append-only log of *segments*, each one the JSON
/// of a batch of photos (`{"v": 1, "e": {path: [size, mtime, ...meta]}}`), the
/// later segment winning for a path. Saving a batch therefore costs the size of
/// the batch, not of the whole library, and a legacy single-file index is just
/// a log of one segment.
abstract interface class GalleryMetaStorage {
  /// Whether anything of [volId] can be stored at all right now. False for a
  /// source that never is (the phone's own storage, a read-only vault, one
  /// whose owner turned persistent caching off): the index then does not
  /// build batches that would only be refused.
  bool persists(int volId);

  /// Every stored segment of [volId], oldest first. Empty when nothing is
  /// stored (or it cannot be read).
  Future<List<String>> loadSegments(int volId);

  /// Stores [json] as a new, newest segment. Whether it was stored.
  Future<bool> appendSegment(int volId, String json);

  /// Replaces every stored segment by the single [json] (compaction). The old
  /// segments are only dropped once [json] is safely stored. Whether it was.
  Future<bool> replaceSegments(int volId, String json);
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

class _Stored {
  const _Stored(this.size, this.mtime, this.meta);
  final int size;
  final int mtime;
  final GalleryMeta meta;
}

/// Results kept in memory for the whole app session and shared by every
/// [GalleryMetaIndex] given it, so that leaving the gallery (or toggling gallery
/// mode, or anything else that rebuilds the view) does not throw away what was
/// read from sources that are never saved to disk, like the phone's own
/// storage. Nothing here is written anywhere; it is gone with the process.
class GalleryMetaMemory {
  GalleryMetaMemory();

  /// The one the app uses.
  static final GalleryMetaMemory app = GalleryMetaMemory();

  final Map<int, LinkedHashMap<String, _Stored>> _maps = {};

  LinkedHashMap<String, _Stored> _mapFor(int volId) =>
      _maps.putIfAbsent(volId, LinkedHashMap.new);

  /// How many photos are remembered for [volId].
  int entryCount(int volId) => _maps[volId]?.length ?? 0;

  /// Forgets [volId], or everything.
  void clear([int? volId]) {
    if (volId == null) {
      _maps.clear();
    } else {
      _maps.remove(volId);
    }
  }
}

class _MergeJob {
  const _MergeJob(this.texts, this.limit);
  final List<String> texts;
  final int limit;
}

// Top-level so `compute` can run them in another isolate without dragging the
// index (a ChangeNotifier with timers) along in a closure.

String _encodeIndex(Map<String, List<Object?>> snapshot) =>
    jsonEncode({'v': GalleryMetaIndex.storageVersion, 'e': snapshot});

/// The entries of one decoded segment, or null when it is not one of ours.
Map<Object?, Object?>? _entriesOf(Object? decoded) {
  if (decoded is! Map || decoded['v'] != GalleryMetaIndex.storageVersion) {
    return null;
  }
  final entries = decoded['e'];
  return entries is Map ? entries.cast<Object?, Object?>() : null;
}

/// Decodes and merges stored segments (oldest first, the newer one winning),
/// entirely on the worker isolate so that a large library does not stall the
/// UI isolate while it is parsed and its objects are built.
LinkedHashMap<String, _Stored> _decodeSegments(List<String> texts) {
  final merged = LinkedHashMap<String, _Stored>();
  for (final text in texts) {
    try {
      final entries = _entriesOf(jsonDecode(text));
      if (entries == null) continue;
      for (final e in entries.entries) {
        final path = e.key;
        final v = e.value;
        if (path is! String || v is! List || v.length != 11) continue;
        final size = v[0];
        final mtime = v[1];
        if (size is! int || mtime is! int) continue;
        final meta = GalleryMeta.tryFromJson(v.sublist(2));
        if (meta == null) continue;
        merged.remove(path); // a newer entry moves to the newest end
        merged[path] = _Stored(size, mtime, meta);
      }
    } catch (_) {
      // A damaged segment counts as none; the next compaction drops it.
    }
  }
  return merged;
}

/// Merges stored segments into the text of one, without building objects.
/// Null when nothing valid was found (so a damaged store is never "replaced"
/// by an empty one).
String? _mergeSegments(_MergeJob job) {
  final merged = LinkedHashMap<String, List<Object?>>();
  for (final text in job.texts) {
    try {
      final entries = _entriesOf(jsonDecode(text));
      if (entries == null) continue;
      for (final e in entries.entries) {
        final path = e.key;
        final v = e.value;
        if (path is! String || v is! List || v.length != 11) continue;
        if (v[0] is! int || v[1] is! int) continue;
        merged.remove(path);
        merged[path] = v.cast<Object?>();
      }
    } catch (_) {
      // A damaged segment counts as none; the next compaction drops it.
    }
  }
  if (merged.isEmpty) return null;
  while (merged.length > job.limit) {
    merged.remove(merged.keys.first);
  }
  return jsonEncode({'v': GalleryMetaIndex.storageVersion, 'e': merged});
}

/// The date, place, camera, keywords and rating of every photo the gallery has
/// looked at, which the filter, the sections and the search need and which no
/// directory listing carries.
///
/// Photos are read lazily and in the background: [ensure] queues the ones not
/// known yet (or changed since: an entry is valid only for the size and date
/// it was read at), a few at a time. Only the start of each file is read
/// ([GalleryMetaParser.headerBytes]), and it is *parsed on a worker isolate*
/// ([GalleryMetaWorker]), so a scan of a large library does not take frames
/// from the UI.
///
/// Two signals come out of it, because they cost very different amounts to act
/// on:
///  * [notifyListeners] at most every [notifyEvery] while photos are read: the
///    progress ([done], [total], [isIndexing]). Cheap to show.
///  * [publishedRevision], which advances (together with a notification) only
///    when [notifyBatch] new results are in, or [maxPublishDelay] has passed,
///    or the run ended, and never while [paused]. A view that refilters,
///    re-sorts and regroups its photos should key on this one, not on
///    [revision], which moves with every single photo.
///
/// With a [storage] the index is loaded at the first request for a source and
/// each batch of [saveEvery] photos is appended to it in the background, so the
/// next session starts with everything already known and no save ever costs
/// more than one batch. Without one it lives for the session only, which is
/// what the phone's own storage gets: nothing is written to it.
class GalleryMetaIndex extends ChangeNotifier {
  GalleryMetaIndex({
    required this.readHeader,
    this.storage,
    this.memory,
    this.retain,
    this.parse,
    this.concurrency = 3,
    this.notifyEvery = const Duration(milliseconds: 500),
    this.notifyBatch = 500,
    this.maxPublishDelay = const Duration(seconds: 4),
    this.saveEvery = 500,
    this.compactAfter = 8,
    this.maxSegments = 48,
  });

  /// Upper bound of entries kept per source; the oldest are dropped first and
  /// simply read again if they are needed.
  static const int maxEntriesPerSource = 200000;

  static const int storageVersion = 1;

  final GalleryHeaderReader readHeader;
  final GalleryMetaStorage? storage;

  /// Where the results of the sources [retain] selects are kept between
  /// indexes (see [GalleryMetaMemory]).
  final GalleryMetaMemory? memory;

  /// Whether the results of [volId] go to [memory]. Meant for sources that are
  /// never saved to [storage]: a vault's results stay private to the index and
  /// are dropped with it (they are on disk, inside the vault, anyway).
  final bool Function(int volId)? retain;

  /// How a header is parsed. Null: on a [GalleryMetaWorker] owned by the index.
  final GalleryHeaderParser? parse;
  final int concurrency;

  /// Minimum time between two progress notifications.
  final Duration notifyEvery;

  /// New results after which [publishedRevision] advances.
  final int notifyBatch;

  /// The longest results are held back from [publishedRevision] while the run
  /// goes on.
  final Duration maxPublishDelay;

  /// Photos read between two appends to [storage].
  final int saveEvery;

  /// Stored segments of a source above which they are merged into one when the
  /// run ends, and the count above which they are merged during a run.
  final int compactAfter;
  final int maxSegments;

  final Map<int, LinkedHashMap<String, _Stored>> _stored = {};

  /// Sources whose map is the one in [memory].
  final Set<int> _shared = {};
  final Map<int, Future<void>> _loading = {};

  /// Paths read since the last append, per source: what the next segment holds.
  final Map<int, Set<String>> _dirty = {};
  final Map<int, Future<void>> _writing = {};

  /// Stored segments per source, as far as this session knows.
  final Map<int, int> _segments = {};

  // A queue, not a list: taking the first element of a 40,000-long list moves
  // the other 39,999 on every single photo.
  final Queue<GalleryIndexRequest> _queue = Queue();
  final Set<String> _queued = {};

  GalleryMetaWorker? _ownedWorker;

  int _inFlight = 0;
  int _revision = 0;
  int _published = 0;
  int _enqueued = 0;
  int _done = 0;
  int _sinceSave = 0;
  bool _disposed = false;
  bool _paused = false;
  Timer? _notifyTimer;
  bool _notifyDue = false;
  final Stopwatch _sincePublish = Stopwatch()..start();

  /// Bumped whenever the answer of [lookup] may have changed (every photo).
  int get revision => _revision;

  /// [revision] as of the last time the results were published to views: it
  /// moves in batches (see the class comment).
  int get publishedRevision => _published;

  /// Whether starting new reads is held back (the list is being scrolled).
  /// Reads in progress finish; publishing resumes when this is cleared.
  bool get paused => _paused;
  set paused(bool value) {
    if (_paused == value) return;
    _paused = value;
    if (!value && !_disposed) {
      _pump();
      _maybePublish();
    }
  }

  /// Photos waiting to be read or being read.
  int get pending => _queue.length + _inFlight;

  /// Photos read since the queue was last empty, and how many were queued in
  /// that time: the progress of the current indexing run.
  int get done => _done;
  int get total => _enqueued;
  bool get isIndexing => pending > 0;

  String _key(int volId, String path) => '$volId|$path';

  /// The results held for [volId]: the session-wide map for a retained source,
  /// else one of the index's own.
  LinkedHashMap<String, _Stored> _mapFor(int volId) {
    final existing = _stored[volId];
    if (existing != null) return existing;
    final mem = memory;
    if (mem != null && (retain?.call(volId) ?? false)) {
      _shared.add(volId);
      return _stored[volId] = mem._mapFor(volId);
    }
    return _stored[volId] = LinkedHashMap<String, _Stored>();
  }

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
      if (r.size <= 0) continue;
      if (lookup(r.volId, r.path, r.size, r.mtime) != null) continue;
      if (!GalleryMetaParser.canParse(_extensionOf(r.path))) continue;
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

  /// Writes everything not saved yet, and completes once every write started
  /// so far has finished. Call before a source is locked.
  ///
  /// What is to be written is captured synchronously, so it is safe to call
  /// right before [dispose].
  Future<void> flush() =>
      Future.wait([
        for (final v in {..._dirty.keys, ..._writing.keys}) _save(v),
      ]).then((_) {});

  /// Forgets what is known about one file, because its metadata was edited.
  ///
  /// [lookup] trusts an entry while the file's size and modified time match,
  /// and a metadata edit can keep both (a date rewritten in place, the time
  /// put back so the photo does not look newly changed). Without this the
  /// gallery would go on showing the old tags and date.
  void invalidate(int volId, String path) {
    final removed = _stored[volId]?.remove(path);
    if (removed == null) return;
    (_dirty[volId] ??= <String>{}).add(path);
    _revision++;
    if (!_maybePublish(force: true)) _scheduleNotify();
  }

  /// Drops what is held (not what is stored) for [volId]; its container was
  /// locked.
  void forget(int volId) {
    _stored.remove(volId);
    if (_shared.remove(volId)) memory?.clear(volId);
    _loading.remove(volId);
    _dirty.remove(volId);
    _segments.remove(volId);
    _queue.removeWhere((r) {
      final hit = r.volId == volId;
      if (hit) _queued.remove(_key(r.volId, r.path));
      return hit;
    });
    _revision++;
    if (!_maybePublish(force: true)) _scheduleNotify();
  }

  // ── Reading ──────────────────────────────────────────────────────────────

  void _pump() {
    while (!_disposed &&
        !_paused &&
        _inFlight < concurrency &&
        _queue.isNotEmpty) {
      final r = _queue.removeFirst();
      _inFlight++;
      unawaited(_process(r));
    }
  }

  Future<GalleryMeta> _parse(Uint8List bytes) {
    final custom = parse;
    if (custom != null) return custom(bytes);
    return (_ownedWorker ??= GalleryMetaWorker()).parse(bytes);
  }

  Future<void> _process(GalleryIndexRequest r) async {
    GalleryMeta? meta;
    try {
      final length = math.min(r.size, GalleryMetaParser.headerBytes);
      final bytes = await readHeader(r.volId, r.path, length);
      if (bytes != null) meta = await _parse(bytes);
    } catch (_) {
      // Unreadable now (locked, removed): left unknown, asked again later.
    }
    _inFlight--;
    _done++;
    _queued.remove(_key(r.volId, r.path));
    if (_disposed) return;
    if (meta != null) {
      final map = _mapFor(r.volId);
      map.remove(r.path); // a re-read entry moves to the newest end
      map[r.path] = _Stored(r.size, r.mtime, meta);
      if (map.length > maxEntriesPerSource) map.remove(map.keys.first);
      _revision++;
      (_dirty[r.volId] ??= <String>{}).add(r.path);
      _sinceSave++;
      if (_sinceSave >= saveEvery) {
        _sinceSave = 0;
        unawaited(flush());
      }
    }
    final idle = _queue.isEmpty && _inFlight == 0;
    if (idle) {
      _sinceSave = 0;
      unawaited(_finishRun());
    }
    if (!_maybePublish()) _scheduleNotify(force: idle);
    _pump();
  }

  Future<void> _finishRun() async {
    await flush();
    if (_disposed) return;
    for (final v in _stored.keys.toList()) {
      _maybeCompact(v, idle: true);
    }
  }

  /// Advances [publishedRevision] to [revision] (and notifies) when enough has
  /// accumulated. Returns whether it did.
  bool _maybePublish({bool force = false}) {
    if (_disposed || _revision == _published) return false;
    if (!force) {
      if (_paused) return false;
      final idle = _queue.isEmpty && _inFlight == 0;
      final due =
          idle ||
          _revision - _published >= notifyBatch ||
          _sincePublish.elapsed >= maxPublishDelay;
      if (!due) return false;
    }
    _published = _revision;
    _sincePublish
      ..reset()
      ..start();
    _scheduleNotify(force: true);
    return true;
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
      // Long enough since the last batch: publish it with the tick.
      if (!_maybePublish()) notifyListeners();
    });
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Future<void> _load(int volId) {
    return _loading[volId] ??= _doLoad(volId);
  }

  Future<void> _doLoad(int volId) async {
    final seeded = _mapFor(volId);
    if (seeded.isNotEmpty) {
      // Already known from an earlier index of this session.
      _revision++;
      _maybePublish(force: true);
    }
    final st = storage;
    if (st == null) return;
    try {
      final texts = await st.loadSegments(volId);
      _segments[volId] = texts.length;
      if (texts.isEmpty) return;
      // Parsed, validated and turned into objects off the UI isolate.
      final decoded = await compute(_decodeSegments, texts);
      if (_disposed) return;
      final map = _stored[volId];
      if (map == null) return; // forgotten while loading
      if (map.isEmpty && !_shared.contains(volId)) {
        _stored[volId] = decoded;
      } else {
        // Anything read this session is newer than what was stored.
        for (final e in decoded.entries) {
          map.putIfAbsent(e.key, () => e.value);
        }
      }
      _revision++;
      _maybePublish(force: true);
      if (texts.length > compactAfter) _maybeCompact(volId, idle: true);
    } catch (_) {
      // A damaged index counts as none; the next run replaces it.
    }
  }

  /// Appends the photos read since the last append as one new segment: work
  /// proportional to the batch, whatever the size of the library.
  Future<void> _save(int volId) {
    final st = storage;
    final paths = _dirty.remove(volId);
    final running = _writing[volId] ?? Future<void>.value();
    // A source that cannot be saved (the phone's own storage) must not cost a
    // snapshot, an encode and a refused write for every batch.
    if (st == null || !st.persists(volId)) return running;
    if (paths == null || paths.isEmpty) return running;
    final map = _stored[volId];
    if (map == null) return running;
    // Captured now (O(batch)), written later.
    final snapshot = <String, List<Object?>>{
      for (final p in paths)
        if (map[p] case final s?) p: [s.size, s.mtime, ...s.meta.toJson()],
    };
    if (snapshot.isEmpty) return running;
    // One write at a time per source, in order.
    final next = running.then((_) async {
      try {
        final text = await compute(_encodeIndex, snapshot);
        if (await st.appendSegment(volId, text)) {
          final count = (_segments[volId] ?? 0) + 1;
          _segments[volId] = count;
          if (count > maxSegments) _maybeCompact(volId, idle: false);
        } else {
          (_dirty[volId] ??= <String>{}).addAll(snapshot.keys);
        }
      } catch (_) {
        (_dirty[volId] ??= <String>{}).addAll(snapshot.keys);
      }
    });
    _writing[volId] = next;
    return next;
  }

  /// Merges the stored segments of [volId] into one when there are more than
  /// the limit. The merge reads the stored text and works on a worker isolate,
  /// queued behind the appends so none can be lost to it.
  void _maybeCompact(int volId, {required bool idle}) {
    final st = storage;
    if (st == null || _disposed) return;
    final limit = idle ? compactAfter : maxSegments;
    if ((_segments[volId] ?? 0) <= limit) return;
    final running = _writing[volId] ?? Future<void>.value();
    _writing[volId] = running.then((_) async {
      try {
        final texts = await st.loadSegments(volId);
        if (texts.length <= 1) {
          _segments[volId] = texts.length;
          return;
        }
        final merged = await compute(
          _mergeSegments,
          _MergeJob(texts, maxEntriesPerSource),
        );
        if (merged != null && await st.replaceSegments(volId, merged)) {
          _segments[volId] = 1;
        }
      } catch (_) {
        // Compaction is an optimisation: the log stays valid without it.
      }
    });
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
    _ownedWorker?.dispose();
    _ownedWorker = null;
    super.dispose();
  }
}
