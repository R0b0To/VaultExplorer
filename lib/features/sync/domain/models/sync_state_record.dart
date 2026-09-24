import 'package:flutter/foundation.dart';

/// What one side of a sync pair looked like for a single file: size,
/// modified time (Unix seconds, 0 = the storage didn't report one) and,
/// only when it was cheap or necessary to compute, a content hash.
///
/// Hashes are lazy on purpose ("fast hash rejection"): reading every byte
/// of every file on every sync would be far too slow through the encrypted
/// engine, so a hash is only filled in when size/mtime alone can't settle
/// a question (see `ThreeWayReconciler`).
@immutable
class SyncSideState {
  final int size;
  final int mtimeSecs;
  final String? hash;

  const SyncSideState({required this.size, required this.mtimeSecs, this.hash});

  SyncSideState withHash(String? newHash) =>
      SyncSideState(size: size, mtimeSecs: mtimeSecs, hash: newHash);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncSideState &&
          other.size == size &&
          other.mtimeSecs == mtimeSecs &&
          other.hash == hash;

  @override
  int get hashCode => Object.hash(size, mtimeSecs, hash);

  @override
  String toString() =>
      'SyncSideState(${size}B, mtime=$mtimeSecs${hash == null ? '' : ', hash=$hash'})';
}

/// One row of the 3-way sync ledger: the state both sides were in right
/// after the last successful sync of [relPath] under [ruleId].
///
/// Each side is later compared against *its own* baseline here, never
/// against the other side's timestamps. That is what makes the engine
/// robust on storage that rewrites modified times on write (SAF providers,
/// cryptor-based vaults): after every transfer the destination's real
/// post-write state is what gets recorded.
///
/// A path with no row has never been synced. A deletion that has been
/// propagated to both sides simply removes the row (there is nothing left
/// to be a baseline for); a deletion that was *not* propagated (deleting
/// disabled, or blocked by a safety guard) keeps its row, so it is seen
/// again on the next run instead of being forgotten.
@immutable
class SyncStateRecord {
  final String ruleId;
  final String relPath;
  final SyncSideState vault;
  final SyncSideState target;
  final int lastSyncedAtMs;
  final bool isDir;

  const SyncStateRecord({
    required this.ruleId,
    required this.relPath,
    required this.vault,
    required this.target,
    required this.lastSyncedAtMs,
    this.isDir = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncStateRecord &&
          other.ruleId == ruleId &&
          other.relPath == relPath &&
          other.vault == vault &&
          other.target == target &&
          other.lastSyncedAtMs == lastSyncedAtMs &&
          other.isDir == isDir;

  @override
  int get hashCode =>
      Object.hash(ruleId, relPath, vault, target, lastSyncedAtMs, isDir);
}

/// A scan of one side of a sync pair.
@immutable
class SyncSnapshot {
  /// Files only, keyed by path relative to the sync root (`/`-separated).
  final Map<String, SyncSideState> files;

  /// Every directory seen (relative paths, root excluded). Used to spot a
  /// path that is a file on one side and a folder on the other.
  final Set<String> dirs;

  /// Directories that could not be listed. Anything beneath one of these
  /// is *unknown*, not *deleted* -- treating a failed listing as "empty"
  /// would turn a transient I/O error into mass deletion on the other side.
  final Set<String> unreadableDirs;

  /// Directories whose listing hit the engine's "too many entries" cap
  /// (`System:TRUNCATED`). What *was* listed is real, but a file missing
  /// from such a folder may simply not have been listed, so absence there
  /// must never be read as a deletion. `''` stands for the root.
  final Set<String> truncatedDirs;

  /// Root could be listed at all.
  final bool rootReadable;

  /// Files left behind by an interrupted run (`*.vexp_tmp`, `*.vexp_old`),
  /// relative paths. Never part of [files].
  final List<String> leftovers;

  const SyncSnapshot({
    required this.files,
    this.dirs = const {},
    this.unreadableDirs = const {},
    this.truncatedDirs = const {},
    this.rootReadable = true,
    this.leftovers = const [],
  });

  const SyncSnapshot.empty()
    : files = const {},
      dirs = const {},
      unreadableDirs = const {},
      truncatedDirs = const {},
      rootReadable = true,
      leftovers = const [];

  bool get isComplete => rootReadable && unreadableDirs.isEmpty;

  /// True when [path] lies inside a directory that failed to list.
  bool isUnderUnreadable(String path) {
    if (!rootReadable) return true;
    for (final dir in unreadableDirs) {
      if (path == dir || path.startsWith('$dir/')) return true;
    }
    return false;
  }

  /// True when [path] lies inside a folder whose listing was cut short, so
  /// its *absence* from [files] proves nothing.
  bool isUnderTruncated(String path) {
    for (final dir in truncatedDirs) {
      if (dir.isEmpty || path == dir || path.startsWith('$dir/')) return true;
    }
    return false;
  }
}
