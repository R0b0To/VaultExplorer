import 'dart:convert';

import 'package:vaultexplorer/features/sync/domain/endpoints/sync_endpoint.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_state_record.dart';
import 'package:vaultexplorer/features/sync/domain/sync_cancellation.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

/// Monotonic fake clock so every write gets a distinct modified time.
class FakeClock {
  int _now;
  FakeClock([this._now = 1000]);
  int tick() => _now += 10;
}

class FakeFile {
  String content;
  int mtime;
  FakeFile(this.content, this.mtime);
  int get size => utf8.encode(content).length;
}

/// A [SyncEndpoint] over an in-memory map.
///
/// Behaves like the real storage layer where it matters to the engine:
/// * `rename` **fails when the destination exists** (the app's rule --
///   the engine must never rely on replace-on-rename);
/// * every write stamps a fresh modified time, and [supportsSetModified]
///   can be turned off to mimic SAF, where the engine can't restore the
///   source's timestamp -- so destination mtimes differ from the source's,
///   exactly the situation the ledger's post-write baselines exist for.
class FakeSyncEndpoint implements SyncEndpoint {
  FakeSyncEndpoint(
    this.label,
    this.clock, {
    this.encrypted = false,
    this.supportsSetModified = true,
  });

  @override
  final String label;
  final FakeClock clock;
  final bool encrypted;
  final bool supportsSetModified;

  final Map<String, FakeFile> files = {};

  /// Final paths (not temp names) whose copy should fail.
  final Set<String> failCopyTo = {};

  /// The next rename *to* each of these paths fails once (to exercise the
  /// swap's rollback), then the entry is consumed.
  final Set<String> failRenameTo = {};

  /// Folders whose listing "fails".
  final Set<String> unreadable = {};

  final List<String> hashCalls = [];

  /// Called mid-copy, after a partial temp file exists and before the copy
  /// completes. Tests cancel the token from here.
  Future<void> Function(String finalRel)? duringCopy;

  @override
  bool get isEncrypted => encrypted;

  void put(String rel, String content, {int? mtime}) {
    files[rel] = FakeFile(content, mtime ?? clock.tick());
  }

  String? read(String rel) => files[rel]?.content;

  bool has(String rel) => files.containsKey(rel);

  static String _finalName(String rel) => rel.endsWith(kSyncTempSuffix)
      ? rel.substring(0, rel.length - kSyncTempSuffix.length)
      : rel;

  @override
  Future<SyncSnapshot> scan({
    required SyncIgnoreMatcher ignore,
    required SyncCancellationToken token,
  }) async {
    if (token.isCancelled) throw const SyncCancelledException();
    final out = <String, SyncSideState>{};
    final dirs = <String>{};
    final leftovers = <String>[];
    for (final entry in files.entries) {
      final rel = entry.key;
      if (unreadable.any((d) => rel == d || rel.startsWith('$d/'))) continue;
      final parts = rel.split('/');
      for (var i = 1; i < parts.length; i++) {
        dirs.add(parts.sublist(0, i).join('/'));
      }
      if (isSyncArtifact(rel)) {
        leftovers.add(rel);
      } else if (!ignore.isIgnored(rel)) {
        out[rel] = SyncSideState(size: entry.value.size, mtimeSecs: entry.value.mtime);
      }
    }
    return SyncSnapshot(
      files: out,
      dirs: dirs,
      unreadableDirs: Set.of(unreadable),
      leftovers: leftovers,
    );
  }

  @override
  Future<Map<String, SyncSideState>> stat(Iterable<String> relPaths) async => {
    for (final rel in relPaths)
      if (files[rel] != null)
        rel: SyncSideState(size: files[rel]!.size, mtimeSecs: files[rel]!.mtime),
  };

  @override
  Future<String?> hash(String relPath, SyncCancellationToken token) async {
    hashCalls.add(relPath);
    final f = files[relPath];
    return f == null ? null : 'h:${f.content}';
  }

  @override
  Future<bool> ensureDirectory(String relDir) async => true;

  @override
  Future<bool> copyFrom(
    SyncEndpoint source,
    String sourceRel,
    String destRel, {
    required int opId,
    required SyncCancellationToken token,
  }) async {
    final src = source as FakeSyncEndpoint;
    final f = src.files[sourceRel];
    if (f == null) return false;
    final finalRel = _finalName(destRel);
    if (failCopyTo.contains(finalRel)) return false;

    // A partial file first, like a real interrupted transfer.
    files[destRel] = FakeFile(f.content.substring(0, f.content.length ~/ 2), clock.tick());
    await duringCopy?.call(finalRel);
    if (token.isCancelled) throw const SyncCancelledException();
    files[destRel] = FakeFile(f.content, clock.tick());
    return true;
  }

  @override
  Future<bool> rename(String fromRel, String toRel) async {
    if (!files.containsKey(fromRel)) return false;
    if (files.containsKey(toRel)) return false; // never replaces
    if (failRenameTo.remove(toRel)) return false;
    files[toRel] = files.remove(fromRel)!;
    return true;
  }

  @override
  Future<bool> delete(String relPath) async => files.remove(relPath) != null;

  @override
  Future<bool> setModified(String relPath, int mtimeSecs) async {
    final f = files[relPath];
    if (!supportsSetModified || f == null) return false;
    f.mtime = mtimeSecs;
    return true;
  }
}
