import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/core/utils/listing_job.dart';
import 'package:vaultexplorer/core/utils/natural_sort.dart';
import 'package:vaultexplorer/core/utils/perf_trace.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';

/// Real, on-disk file operations for the decoy's local storage explorer.
///
/// This intentionally never touches the vault engine APIs, vault containers,
/// or any encryption code -- everything here operates on plain phone
/// storage through `dart:io`, the same way the existing decoy archive
/// screen already reads Downloads for zip files. It exists so the decoy
/// can offer a genuine, fully-functional file manager for real device
/// storage, reusing [RawEntry] -- the same directory-entry value type the
/// vault file manager's list/sort/selection widgets already work with --
/// without pulling any of the vault machinery into the decoy.
class DecoyLocalRepository {
  const DecoyLocalRepository();

  // Recently listed folders, least recently used first. This used to be a
  // single slot, so going from folder A to B and back to A listed A again
  // from scratch (a new isolate plus a stat per file). Entries are only
  // reused while the folder's own modification time is unchanged -- adding,
  // removing or renaming a child updates it -- and for at most [_cacheTtl],
  // which bounds how long an in-place change to a file's size can go unseen.
  static final LinkedHashMap<String, _CachedListing> _cache =
      LinkedHashMap<String, _CachedListing>();
  static const int _cacheMaxFolders = 32;
  static const _cacheTtl = Duration(seconds: 60);
  static const _largeFolderCacheTtl = Duration(minutes: 15);
  static const int _largeFolderThreshold = 2000;

  /// Clears the in-memory cache of directory listings.
  static void clearCache() {
    _cache.clear();
  }

  /// Drops only [dirPath] from the listing cache so mutations in one folder
  /// do not evict cached 40,000-entry folders elsewhere.
  static void invalidateDirectory(String dirPath) {
    _cache.remove(dirPath);
  }

  /// Drops the parent folder of [entryPath] (and [entryPath] itself if it was
  /// a cached directory).
  static void invalidatePathAndParent(String entryPath) {
    _cache.remove(entryPath);
    _cache.remove(p.dirname(entryPath));
  }
  /// Resolves the true public storage root (e.g. `/storage/emulated/0`),
  /// independent of Android version/OEM quirks -- same approach the decoy
  /// archive screen already uses to find Downloads, generalized to return
  /// the root itself rather than joining `Download` onto it.
  Future<Directory> primaryRoot() async {
    // There is no shared-storage root on desktop; "Local storage" is the home
    // folder, and the drives are listed beside it (see DesktopStorage).
    if (PlatformFeatures.isDesktop) return _desktopHome();
    try {
      final appExternal = await getExternalStorageDirectory();
      if (appExternal == null) {
        return Directory('/storage/emulated/0');
      }
      var dir = appExternal;
      while (dir.path.isNotEmpty && p.basename(dir.path) != 'Android') {
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      return p.basename(dir.path) == 'Android' ? dir.parent : appExternal;
    } catch (_) {
      return Directory('/storage/emulated/0');
    }
  }

  /// The user's home folder, falling back to the working directory.
  Directory _desktopHome() {
    final env = Platform.environment;
    final home = (Platform.isWindows ? env['USERPROFILE'] : env['HOME']) ?? '';
    if (home.isNotEmpty && Directory(home).existsSync()) return Directory(home);
    return Directory.current;
  }

  /// Lists the immediate children of [path] as [RawEntry] values, sourced
  /// straight from `dart:io` stats -- no wire-format parsing needed since
  /// there's no native backend in between for plain local files.
  ///
  /// Entries that can't be stat'd (permission-denied system folders,
  /// broken symlinks, races with a concurrent delete elsewhere) are
  /// skipped rather than failing the whole listing, mirroring how the
  /// decoy archive screen already tolerates a failed Downloads scan.
  Future<List<RawEntry>> listDirectory(String path, {bool refresh = false}) async {
    final perfT0 = PerfTrace.begin();
    final lookup = await _lookupCached(path, refresh);
    final hit = lookup.hit;
    if (hit != null) {
      PerfTrace.count('local.list.cache_hit');
      PerfTrace.end('local.list.cached', perfT0);
      return hit;
    }
    final missReason = lookup.missReason;
    PerfTrace.count('local.list.cache_miss');

    // Stat the folder *before* listing it: a change that lands while the
    // listing runs then leaves a newer mtime on disk than the one remembered,
    // so the next lookup re-lists instead of trusting a half-old result.
    final folderModified = await _folderModified(path);
    final out = await Isolate.run(() => _listDirectorySync(path));
    PerfTrace.end('local.list.isolate', perfT0, slowMs: 150);
    PerfTrace.record('local.list.readdir', out.listUs);
    PerfTrace.record('local.list.stat', out.statUs);
    if (perfT0 != 0) {
      PerfTrace.sink(
        'local.list.detail key=${path.hashCode} miss=$missReason count=${out.entries.length} '
        'readdirMs=${out.listUs ~/ 1000} statMs=${out.statUs ~/ 1000} sortMs=${out.sortUs ~/ 1000}',
      );
    }

    final result = UnmodifiableListView<RawEntry>(out.entries);
    _remember(path, folderModified, result);
    return result;
  }

  /// Like [listDirectory], but for folders too big to wait for: while the
  /// folder is still being read it hands [onPartial] a few growing,
  /// name-sorted snapshots (see [ProgressiveListingConfig]) so the first
  /// screenful can be shown long before the last entry is read. The returned
  /// job's result is the complete listing, exactly what [listDirectory]
  /// would give, and only that complete listing is remembered.
  ///
  /// A cached folder, or one that is read quickly, never produces a partial:
  /// the result just arrives. Cancelling the job stops the worker reading.
  ListingJob<List<RawEntry>> listDirectoryProgressive(
    String path, {
    bool refresh = false,
    void Function(List<RawEntry> partial)? onPartial,
    ProgressiveListingConfig config = const ProgressiveListingConfig(),
  }) {
    final run = _ProgressiveListing(path, refresh, onPartial, config);
    unawaited(run.start());
    return ListingJob<List<RawEntry>>(run.result, run.cancel);
  }

  /// The cached listing of [path] if it is still good, otherwise null and why
  /// not. A cached entry is reused only while the folder's own modification
  /// time is unchanged and it has not outlived its TTL.
  static Future<({List<RawEntry>? hit, String missReason})> _lookupCached(
    String path,
    bool refresh,
  ) async {
    final cached = _cache.remove(path);
    var missReason = refresh
        ? 'refresh(hadCache=${cached != null})'
        : (cached == null ? 'cold_or_evicted(n=${_cache.length})' : '');
    if (!refresh && cached != null) {
      // One stat of the folder itself decides whether the cached listing is
      // still good; far cheaper than listing and stat'ing every child again.
      final ttl = cached.entries.length >= _largeFolderThreshold
          ? _largeFolderCacheTtl
          : _cacheTtl;
      final age = DateTime.now().difference(cached.cachedAt);
      if (age < ttl) {
        final modified = await _folderModified(path);
        if (modified != null && modified == cached.folderModified) {
          _cache[path] = cached; // re-insert: most recently used
          return (hit: cached.entries, missReason: '');
        }
        missReason = modified == null
            ? 'mtime_null'
            : 'mtime_changed(${cached.folderModified.millisecondsSinceEpoch}->${modified.millisecondsSinceEpoch})';
      } else {
        missReason = 'ttl(${age.inSeconds}s>=${ttl.inSeconds}s,n=${cached.entries.length})';
      }
    }
    return (hit: null, missReason: missReason);
  }

  static void _remember(
    String path,
    DateTime? folderModified,
    List<RawEntry> result,
  ) {
    if (folderModified == null) return;
    _cache[path] = _CachedListing(result, folderModified, DateTime.now());
    while (_cache.length > _cacheMaxFolders) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// The folder's own last-modified time, or null when it cannot be read.
  static Future<DateTime?> _folderModified(String path) async {
    try {
      final stat = await FileStat.stat(path);
      return stat.type == FileSystemEntityType.notFound ? null : stat.modified;
    } catch (_) {
      return null;
    }
  }

  /// Recursive byte total for a folder -- used for the selection summary
  /// only when the user is looking at a small enough selection that this
  /// is worth computing. Read on a worker isolate (see [folderSizeJob]). A
  /// stream error from the tree ends the count where it stands, and what was
  /// counted so far is returned.
  Future<int> folderSize(String path) async {
    try {
      return await folderSizeJob(path).result ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// [folderSize] as a job that can be abandoned. The walk runs on a worker
  /// isolate, so a big tree no longer costs the UI isolate a round trip per
  /// file, and cancelling stops the walk at its next entry instead of leaving
  /// it to read the rest of the tree for nobody. [ListingJob.result] is null
  /// when the job was cancelled.
  ListingJob<int> folderSizeJob(String path) {
    final run = _FolderSizeRun(path);
    unawaited(run.start());
    return ListingJob<int>(run.result, run.cancel);
  }

 Future<String> rename(String path, String newName) async {
    invalidatePathAndParent(path);
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Name cannot be empty');
    }
    final parent = p.dirname(path);
    final target = p.join(parent, trimmed);
    if (await FileSystemEntity.type(target) != FileSystemEntityType.notFound) {
      throw StateError('"$trimmed" already exists here');
    }
    final isDir = await FileSystemEntity.isDirectory(path);
    final entity = isDir ? Directory(path) : File(path);
    final renamed = await entity.rename(target);
    return renamed.path;
  }

  Future<void> delete(String path) async {
    invalidatePathAndParent(path);
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else if (type != FileSystemEntityType.notFound) {
      await File(path).delete();
    }
  }

  Future<String> copyInto(String sourcePath, String destDirPath) async {
    invalidateDirectory(destDirPath);;
    final name = await _uniqueName(destDirPath, p.basename(sourcePath));
    final destPath = p.join(destDirPath, name);
    final type = await FileSystemEntity.type(sourcePath);
    if (type == FileSystemEntityType.directory) {
      await _copyDirRecursive(Directory(sourcePath), Directory(destPath));
    } else {
      await File(sourcePath).copy(destPath);
    }
    return destPath;
  }

 Future<String> moveInto(String sourcePath, String destDirPath) async {
    invalidatePathAndParent(sourcePath);
    invalidateDirectory(destDirPath);
    final name = await _uniqueName(destDirPath, p.basename(sourcePath));
    final destPath = p.join(destDirPath, name);
    try {
      final type = await FileSystemEntity.type(sourcePath);
      final entity = type == FileSystemEntityType.directory ? Directory(sourcePath) : File(sourcePath);
      final moved = await entity.rename(destPath);
      return moved.path;
    } on FileSystemException {
      final copiedPath = await copyInto(sourcePath, destDirPath);
      await delete(sourcePath);
      return copiedPath;
    }
  }

  Future<void> _copyDirRecursive(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list(followLinks: false)) {
      final newPath = p.join(dst.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirRecursive(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  Future<String> _uniqueName(String destDir, String name) async {
    if (await FileSystemEntity.type(p.join(destDir, name)) == FileSystemEntityType.notFound) {
      return name;
    }
    final ext = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    var i = 1;
    while (true) {
      final candidate = '$base ($i)$ext';
      if (await FileSystemEntity.type(p.join(destDir, candidate)) == FileSystemEntityType.notFound) {
        return candidate;
      }
      i++;
    }
  }
}

({List<RawEntry> entries, int listUs, int statUs, int sortUs}) _listDirectorySync(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    return (entries: <RawEntry>[], listUs: 0, statUs: 0, sortUs: 0);
  }
  final dirs = <RawEntry>[];
  final files = <RawEntry>[];
  var listUs = 0;
  var statUs = 0;
  var sortUs = 0;
  try {
    final sw = Stopwatch()..start();
    final items = dir.listSync(followLinks: false);
    listUs = sw.elapsedMicroseconds;
    sw.reset();
    for (final item in items) {
      final entry = _entryFor(item);
      if (entry == null) continue;
      (entry.isDir ? dirs : files).add(entry);
    }
    statUs = sw.elapsedMicroseconds;
    sw.reset();
    // Pre-sort on this worker isolate in natural-name order so the UI thread
    // can skip the 600k-comparison sort on large folders opened by name.
    if (dirs.length > 1) {
      dirs.sort((a, b) => naturalCompare(a.lowercaseName, b.lowercaseName));
    }
    if (files.length > 1) {
      files.sort((a, b) => naturalCompare(a.lowercaseName, b.lowercaseName));
    }
    sortUs = sw.elapsedMicroseconds;
  } catch (_) {
    // Unreadable directory or stream error mid-listing
  }
  final entries = dirs.isEmpty
      ? files
      : (files.isEmpty ? dirs : <RawEntry>[...dirs, ...files]);
  return (entries: entries, listUs: listUs, statUs: statUs, sortUs: sortUs);
}

/// Last path segment of an entry returned by `Directory.listSync`.
///
/// Those paths are always `<directory>/<name>` with `/` separators on Android,
/// so cutting after the last `/` is exact and avoids `package:path`'s full
/// parse of every entry (a listing of thousands of files called it once each).
String _baseName(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = path.lastIndexOf(r'\');
  final idx = slash > backslash ? slash : backslash;
  return idx >= 0 ? path.substring(idx + 1) : path;
}

class _CachedListing {
  _CachedListing(this.entries, this.folderModified, this.cachedAt);

  final List<RawEntry> entries;
  final DateTime folderModified;
  final DateTime cachedAt;
}

/// One directory child as a [RawEntry], or null if it is neither a file nor a
/// folder or cannot be read (permission-denied system folders, broken
/// symlinks, a concurrent delete). Shared by the one-shot and the progressive
/// listing so both produce identical entries.
RawEntry? _entryFor(FileSystemEntity item) {
  try {
    if (item is Directory) {
      int modifiedSecs = 0;
      try {
        final stat = item.statSync();
        modifiedSecs = stat.modified.millisecondsSinceEpoch ~/ 1000;
      } catch (_) {
        // Folder metadata is optional; keep the entry with modifiedSecs 0
        // if stat fails because of permissions or a concurrent filesystem change.
      }
      final name = _baseName(item.path);
      return RawEntry(
        name: name,
        isDir: true,
        sizeBytes: 0,
        modifiedSecs: modifiedSecs,
        lowercaseName: name.toLowerCase(),
        extension: '',
      );
    }
    if (item is File) {
      final stat = item.statSync();
      final name = _baseName(item.path);
      final lower = name.toLowerCase();
      final dot = lower.lastIndexOf('.');
      return RawEntry(
        name: name,
        isDir: false,
        sizeBytes: stat.size,
        modifiedSecs: stat.modified.millisecondsSinceEpoch ~/ 1000,
        lowercaseName: lower,
        extension: dot < 0 ? '' : lower.substring(dot + 1),
      );
    }
  } catch (_) {
    return null;
  }
  return null;
}

/// When a folder that is still being read is shown in part.
///
/// A snapshot is sent once the listing has been running for the next time in
/// [schedule] *and* holds at least [minPartialEntries] entries and half again
/// as many as the previous snapshot. A folder that finishes before the first
/// time (anything on fast storage, and every ordinary-sized folder) is never
/// shown in part; the finished listing simply arrives.
class ProgressiveListingConfig {
  const ProgressiveListingConfig({
    this.schedule = const <Duration>[
      Duration(milliseconds: 250),
      Duration(seconds: 1),
      Duration(milliseconds: 2500),
    ],
    this.minPartialEntries = 200,
  });

  final List<Duration> schedule;
  final int minPartialEntries;
}

typedef _ProgressiveOutcome = ({
  List<RawEntry> entries,
  int listUs,
  int statUs,
  int sortUs,
  int partials,
  int firstPartialUs,
});

/// Reads one folder on a worker isolate and reports growing snapshots.
class _ProgressiveListing {
  _ProgressiveListing(this.path, this.refresh, this.onPartial, this.config);

  final String path;
  final bool refresh;
  final void Function(List<RawEntry> partial)? onPartial;
  final ProgressiveListingConfig config;

  final Completer<List<RawEntry>?> _done = Completer<List<RawEntry>?>();
  bool _cancelled = false;
  SendPort? _control;

  Future<List<RawEntry>?> get result => _done.future;

  Future<void> start() async {
    final perfT0 = PerfTrace.begin();
    ReceivePort? partials;
    try {
      final lookup = await DecoyLocalRepository._lookupCached(path, refresh);
      if (_cancelled) return;
      final hit = lookup.hit;
      if (hit != null) {
        PerfTrace.count('local.list.cache_hit');
        PerfTrace.end('local.list.cached', perfT0);
        _finish(hit);
        return;
      }
      PerfTrace.count('local.list.cache_miss');

      // As in the one-shot listing: stat the folder before reading it.
      final folderModified = await DecoyLocalRepository._folderModified(path);
      if (_cancelled) return;

      partials = ReceivePort()..listen(_onWorkerMessage);
      final out = await _spawnWorker(path, partials.sendPort, config);
      // A cancelled run may have been cut short, so it is neither reported
      // nor remembered.
      if (_cancelled) return;

      PerfTrace.end('local.list.isolate', perfT0, slowMs: 150);
      PerfTrace.record('local.list.readdir', out.listUs);
      PerfTrace.record('local.list.stat', out.statUs);
      if (out.partials > 0) {
        PerfTrace.record('local.list.first_partial', out.firstPartialUs);
      }
      if (perfT0 != 0) {
        PerfTrace.sink(
          'local.list.detail key=${path.hashCode} miss=${lookup.missReason} count=${out.entries.length} '
          'readdirMs=${out.listUs ~/ 1000} statMs=${out.statUs ~/ 1000} sortMs=${out.sortUs ~/ 1000} '
          'progressive partials=${out.partials} firstPartialMs=${out.firstPartialUs ~/ 1000}',
        );
      }

      final listing = UnmodifiableListView<RawEntry>(out.entries);
      DecoyLocalRepository._remember(path, folderModified, listing);
      _finish(listing);
    } catch (error, stack) {
      if (!_done.isCompleted) _done.completeError(error, stack);
    } finally {
      partials?.close();
    }
  }

  /// Kept out of the instance so the closure sent to the isolate captures only
  /// the path, the port and the config, never this object.
  static Future<_ProgressiveOutcome> _spawnWorker(
    String path,
    SendPort partials,
    ProgressiveListingConfig config,
  ) {
    return Isolate.run(() => _listDirectoryProgressive(path, partials, config));
  }

  void _onWorkerMessage(Object? message) {
    if (message is SendPort) {
      // The worker's control port. If cancelled before it arrived, say so now.
      _control = message;
      if (_cancelled) message.send('cancel');
      return;
    }
    if (_cancelled || message is! List) return;
    PerfTrace.count('local.list.partial');
    onPartial?.call(UnmodifiableListView<RawEntry>(message.cast<RawEntry>()));
  }

  /// Stops reading. The result completes with null at once; the worker notices
  /// at its next entry, ends, and its (possibly incomplete) outcome is dropped.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _control?.send('cancel');
    _finish(null);
  }

  void _finish(List<RawEntry>? value) {
    if (!_done.isCompleted) _done.complete(value);
  }
}

/// Runs on a worker isolate: streams the folder, sending name-sorted snapshots
/// to [partials] on the schedule in [config], and returns the full, sorted
/// listing. Sends its own control port first so the caller can cancel it.
Future<_ProgressiveOutcome> _listDirectoryProgressive(
  String path,
  SendPort partials,
  ProgressiveListingConfig config,
) async {
  final control = ReceivePort();
  var cancelled = false;
  control.listen((message) {
    if (message == 'cancel') cancelled = true;
  });
  partials.send(control.sendPort);

  final dirs = <RawEntry>[];
  final files = <RawEntry>[];
  var statUs = 0;
  var sortUs = 0;
  var partialCount = 0;
  var firstPartialUs = 0;
  final total = Stopwatch()..start();
  try {
    if (!await Directory(path).exists()) {
      return _emptyOutcome;
    }
    final stat = Stopwatch();
    var next = 0;
    var lastCount = 0;
    await for (final item in Directory(path).list(followLinks: false)) {
      if (cancelled) break;
      stat.start();
      final entry = _entryFor(item);
      stat.stop();
      if (entry == null) continue;
      (entry.isDir ? dirs : files).add(entry);

      if (next < config.schedule.length) {
        final count = dirs.length + files.length;
        if (count >= config.minPartialEntries &&
            count >= lastCount + (lastCount >> 1) &&
            total.elapsed >= config.schedule[next]) {
          final sortWatch = Stopwatch()..start();
          partials.send(_sortedSnapshot(dirs, files));
          sortUs += sortWatch.elapsedMicroseconds;
          lastCount = count;
          next++;
          partialCount++;
          if (partialCount == 1) firstPartialUs = total.elapsedMicroseconds;
        }
      }
    }
    statUs = stat.elapsedMicroseconds;
    if (cancelled) return _emptyOutcome;

    final sortWatch = Stopwatch()..start();
    // Pre-sort here, off the UI thread, in natural-name order.
    if (dirs.length > 1) {
      dirs.sort((a, b) => naturalCompare(a.lowercaseName, b.lowercaseName));
    }
    if (files.length > 1) {
      files.sort((a, b) => naturalCompare(a.lowercaseName, b.lowercaseName));
    }
    sortUs += sortWatch.elapsedMicroseconds;
  } catch (_) {
    // Unreadable directory or stream error mid-listing: keep what was read,
    // as the one-shot listing does.
  } finally {
    control.close();
  }
  final entries = dirs.isEmpty
      ? files
      : (files.isEmpty ? dirs : <RawEntry>[...dirs, ...files]);
  return (
    entries: entries,
    listUs: total.elapsedMicroseconds - statUs - sortUs,
    statUs: statUs,
    sortUs: sortUs,
    partials: partialCount,
    firstPartialUs: firstPartialUs,
  );
}

const _ProgressiveOutcome _emptyOutcome = (
  entries: <RawEntry>[],
  listUs: 0,
  statUs: 0,
  sortUs: 0,
  partials: 0,
  firstPartialUs: 0,
);

/// Adds up the size of every file under one folder on a worker isolate.
class _FolderSizeRun {
  _FolderSizeRun(this.path);

  final String path;

  final Completer<int?> _done = Completer<int?>();
  bool _cancelled = false;
  SendPort? _control;

  Future<int?> get result => _done.future;

  Future<void> start() async {
    final fromWorker = ReceivePort()..listen(_onWorkerMessage);
    try {
      final total = await _spawnWorker(path, fromWorker.sendPort);
      // A cancelled walk may have been cut short, so its total is not reported.
      _finish(_cancelled ? null : total);
    } catch (error, stack) {
      if (!_done.isCompleted) _done.completeError(error, stack);
    } finally {
      fromWorker.close();
    }
  }

  /// Kept out of the instance so the closure sent to the isolate captures only
  /// the path and the port, never this object.
  static Future<int> _spawnWorker(String path, SendPort fromWorker) {
    return Isolate.run(() => _sumFolderSize(path, fromWorker));
  }

  void _onWorkerMessage(Object? message) {
    if (message is SendPort) {
      // The worker's control port. If cancelled before it arrived, say so now.
      _control = message;
      if (_cancelled) message.send('cancel');
    }
  }

  /// Stops the walk. The result completes with null at once; the worker
  /// notices at its next entry and ends.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _control?.send('cancel');
    _finish(null);
  }

  void _finish(int? value) {
    if (!_done.isCompleted) _done.complete(value);
  }
}

/// Runs on a worker isolate: walks [path] and returns the total size of the
/// files under it. Sends its own control port first so the caller can cancel
/// the walk. Like the listing worker it only hears that message between
/// entries, which the asynchronous directory stream makes frequent.
Future<int> _sumFolderSize(String path, SendPort fromWorker) async {
  final control = ReceivePort();
  var cancelled = false;
  control.listen((message) {
    if (message == 'cancel') cancelled = true;
  });
  fromWorker.send(control.sendPort);

  var total = 0;
  try {
    await for (final entity in Directory(path).list(
      recursive: true,
      followLinks: false,
    )) {
      if (cancelled) break;
      if (entity is File) {
        try {
          total += entity.lengthSync();
        } catch (_) {
          // Unreadable file mid-tree -- keep counting the rest.
        }
      }
    }
  } catch (_) {
    // Stream error from the tree -- return whatever was counted so far.
  } finally {
    control.close();
  }
  return total;
}

/// Folders first, each group in natural-name order: the same order the final
/// listing has, so a snapshot can be shown as it is.
List<RawEntry> _sortedSnapshot(List<RawEntry> dirs, List<RawEntry> files) {
  int byName(RawEntry a, RawEntry b) =>
      naturalCompare(a.lowercaseName, b.lowercaseName);
  final sortedDirs = List<RawEntry>.of(dirs)..sort(byName);
  final sortedFiles = List<RawEntry>.of(files)..sort(byName);
  return <RawEntry>[...sortedDirs, ...sortedFiles];
}
