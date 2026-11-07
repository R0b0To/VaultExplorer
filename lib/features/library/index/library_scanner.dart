import 'dart:async';
import 'dart:typed_data';

import 'package:vaultexplorer/core/utils/bounded_semaphore.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';
import 'package:vaultexplorer/features/library/tags/audio_tag_reader.dart';
import 'package:vaultexplorer/features/library/tags/byte_source.dart';

/// One directory entry as the scanner needs it. The adapter that talks to the
/// vault engine maps its own listing format to this.
class LibraryFsEntry {
  final String name;
  final bool isDir;
  final int sizeBytes;

  /// Unix seconds, 0 when the filesystem does not record one.
  final int modifiedSecs;

  const LibraryFsEntry({
    required this.name,
    required this.isDir,
    this.sizeBytes = 0,
    this.modifiedSecs = 0,
  });
}

/// Lists a container-relative folder; null when the listing failed.
typedef LibraryDirectoryLister = Future<List<LibraryFsEntry>?> Function(
  String dirPath,
);

/// Reads a byte range of a container-relative file.
typedef LibraryChunkReader = Future<Uint8List?> Function(
  String path,
  int offset,
  int length,
);

enum LibraryScanPhase { listing, reading }

class LibraryScanProgress {
  final LibraryScanPhase phase;
  final int foldersChecked;
  final int audioFilesFound;

  /// Files that need their tags read (new or changed).
  final int toRead;

  /// Of those, how many are done.
  final int read;

  const LibraryScanProgress({
    required this.phase,
    required this.foldersChecked,
    required this.audioFilesFound,
    this.toRead = 0,
    this.read = 0,
  });
}

class LibraryScanResult {
  /// Every audio file found, changed or not. Anything in the old index that is
  /// missing from here was deleted, but only trust that when [walkComplete].
  final Set<String> seenPaths;
  final int foldersChecked;
  final int listFailures;
  final int readFailures;
  final bool cancelled;
  final bool limitReached;

  const LibraryScanResult({
    required this.seenPaths,
    required this.foldersChecked,
    required this.listFailures,
    required this.readFailures,
    required this.cancelled,
    required this.limitReached,
  });

  /// True when the whole tree was listed without a hiccup. An index must not
  /// drop tracks on the strength of a scan that was cancelled, hit a limit, or
  /// could not list some folder: a missing listing is not a missing file.
  bool get walkComplete => !cancelled && !limitReached && listFailures == 0;
}

/// Finds audio files under a folder and reads the tags of the ones that are new
/// or changed since [scan]'s `existing` snapshot.
///
/// Two phases: a walk that only lists directories (cheap, bounded
/// concurrency), then tag reads for what changed (bounded concurrency, each a
/// few kilobytes thanks to the header-driven readers). New tracks are handed
/// to `onTracks` in batches while the scan runs, so a caller can show them
/// early.
class LibraryScanner {
  final LibraryDirectoryLister listDirectory;
  final LibraryChunkReader readChunk;
  final bool Function(String fileName) isAudioFile;

  final int listConcurrency;
  final int readConcurrency;
  final int maxDepth;
  final int maxFolders;
  final int batchSize;
  final Duration batchInterval;

  LibraryScanner({
    required this.listDirectory,
    required this.readChunk,
    required this.isAudioFile,
    this.listConcurrency = 4,
    this.readConcurrency = 4,
    this.maxDepth = 40,
    this.maxFolders = 50000,
    this.batchSize = 100,
    this.batchInterval = const Duration(milliseconds: 500),
  });

  /// Scans every folder in [startPaths] (use `['']` for the whole container).
  /// Roots that overlap are harmless: a file found twice is counted once.
  Future<LibraryScanResult> scan({
    required List<String> startPaths,
    required Map<String, LibraryTrack> existing,
    required CancellationToken token,
    required void Function(List<LibraryTrack> batch) onTracks,
    void Function(LibraryScanProgress progress)? onProgress,
  }) async {
    var foldersChecked = 0;
    var listFailures = 0;
    var limitReached = false;
    final foundByPath = <String, _Found>{};
    List<_Found> foundList() => foundByPath.values.toList();

    // ── Phase 1: walk ────────────────────────────────────────────────────────
    final semaphore = BoundedSemaphore(listConcurrency);

    Future<void> walk(String dir, int depth) async {
      if (token.isCancelled) return;
      if (depth > maxDepth || foldersChecked >= maxFolders) {
        limitReached = true;
        return;
      }
      final subdirs = <String>[];
      await semaphore.acquire();
      // Siblings queue up here long before they run; check again so a cancel
      // does not pay for a listing per queued folder.
      if (token.isCancelled) {
        semaphore.release();
        return;
      }
      try {
        final entries = await listDirectory(dir);
        if (entries == null) {
          listFailures++;
        } else {
          for (final e in entries) {
            if (e.name.isEmpty || e.name.startsWith('.')) continue;
            final path = dir.isEmpty ? e.name : '$dir/${e.name}';
            if (e.isDir) {
              subdirs.add(path);
            } else if (isAudioFile(e.name)) {
              foundByPath[path] = _Found(path, e.sizeBytes, e.modifiedSecs);
            }
          }
        }
      } catch (_) {
        listFailures++;
      } finally {
        semaphore.release();
        foldersChecked++;
        if (foldersChecked % 25 == 0) {
          onProgress?.call(LibraryScanProgress(
            phase: LibraryScanPhase.listing,
            foldersChecked: foldersChecked,
            audioFilesFound: foundByPath.length,
          ));
        }
      }
      if (token.isCancelled || subdirs.isEmpty) return;
      await Future.wait([for (final s in subdirs) walk(s, depth + 1)]);
    }

    await Future.wait([for (final root in startPaths) walk(root, 0)]);

    final found = foundList();
    final seen = <String>{for (final f in found) f.path};
    if (token.isCancelled) {
      return LibraryScanResult(
        seenPaths: seen,
        foldersChecked: foldersChecked,
        listFailures: listFailures,
        readFailures: 0,
        cancelled: true,
        limitReached: limitReached,
      );
    }

    // ── Phase 2: read what changed ───────────────────────────────────────────
    final todo = [
      for (final f in found)
        if (f.size > 0 &&
            !(existing[f.path]?.isCurrentFor(
                  size: f.size,
                  modifiedSecs: f.modifiedSecs,
                ) ??
                false))
          f,
    ]..sort((a, b) => a.path.compareTo(b.path));

    var readDone = 0;
    var readFailures = 0;
    var next = 0;
    final pending = <LibraryTrack>[];
    final clock = Stopwatch()..start();
    var lastFlush = Duration.zero;

    void flush() {
      if (pending.isNotEmpty) {
        onTracks(List<LibraryTrack>.of(pending));
        pending.clear();
      }
      lastFlush = clock.elapsed;
      onProgress?.call(LibraryScanProgress(
        phase: LibraryScanPhase.reading,
        foldersChecked: foldersChecked,
        audioFilesFound: found.length,
        toRead: todo.length,
        read: readDone,
      ));
    }

    onProgress?.call(LibraryScanProgress(
      phase: LibraryScanPhase.reading,
      foldersChecked: foldersChecked,
      audioFilesFound: found.length,
      toRead: todo.length,
    ));

    Future<void> worker() async {
      while (!token.isCancelled) {
        final i = next++;
        if (i >= todo.length) return;
        final f = todo[i];
        try {
          final tags = await AudioTagReader.read(
            _ChunkSource(f.path, f.size, readChunk),
            fileName: f.path.substring(f.path.lastIndexOf('/') + 1),
          );
          pending.add(LibraryTrack.fromTags(
            path: f.path,
            size: f.size,
            modifiedSecs: f.modifiedSecs,
            tags: tags,
          ));
        } catch (_) {
          readFailures++;
        }
        readDone++;
        if (pending.length >= batchSize ||
            clock.elapsed - lastFlush >= batchInterval) {
          flush();
        }
      }
    }

    await Future.wait([for (var i = 0; i < readConcurrency; i++) worker()]);
    flush();

    return LibraryScanResult(
      seenPaths: seen,
      foldersChecked: foldersChecked,
      listFailures: listFailures,
      readFailures: readFailures,
      cancelled: token.isCancelled,
      limitReached: limitReached,
    );
  }
}

class _Found {
  final String path;
  final int size;
  final int modifiedSecs;
  const _Found(this.path, this.size, this.modifiedSecs);
}

class _ChunkSource implements ByteSource {
  final String path;
  final int size;
  final LibraryChunkReader reader;

  _ChunkSource(this.path, this.size, this.reader);

  @override
  int get length => size;

  @override
  Future<Uint8List?> read(int offset, int count) => reader(path, offset, count);
}
