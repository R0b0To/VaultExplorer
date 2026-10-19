import 'dart:math' as math;

import 'package:vaultexplorer/features/sync/domain/models/sync_plan.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_state_record.dart';

/// Content hash of [relPath] on [side], or null if it can't be computed.
typedef SyncHashResolver =
    Future<String?> Function(SyncSide side, String relPath);

/// Decides, for every path in `vault ∪ target ∪ baseline`, what a sync
/// run should do. Pure decision logic: no I/O except the injected
/// [SyncHashResolver], which is only consulted when size and modified time
/// can't settle a question.
///
/// Each side is compared with **its own** ledger baseline, never with the
/// other side's timestamps:
///
/// | vault vs B | target vs B | action |
/// |---|---|---|
/// | changed   | unchanged | copy vault -> target |
/// | unchanged | changed   | copy target -> vault |
/// | changed   | changed   | identical content -> adopt, else resolve conflict |
/// | unchanged | missing   | target deleted it -> delete on vault (if enabled) |
/// | missing   | unchanged | vault deleted it -> delete on target (if enabled) |
/// | changed   | missing   | modification beats deletion -> copy vault -> target |
/// | missing   | changed   | modification beats deletion -> copy target -> vault |
/// | missing   | missing   | forget |
///
/// With no baseline row (first sight): present on one side -> copy it
/// across; present on both -> adopt if they look identical, else conflict.
///
/// One-way rules use the same table, but any action that would *write to
/// the source side* is turned into a [SyncSkipReason.directionBlocked]
/// skip: a one-way rule only ever writes to its destination, and only for
/// changes made on its source. (A conflict on a one-way rule is won by the
/// source.)
///
/// Safety guards, because a listing that silently fails looks exactly like
/// "everything was deleted":
/// * paths under a folder that couldn't be listed are skipped, not deleted;
/// * deletions are held back when the side that "lost" the files came back
///   completely empty while the ledger says it held at least
///   [emptySideMinBaseline] files, or when they exceed
///   [massDeleteFraction] of the ledger (minimum [massDeleteMinCount]).
class ThreeWayReconciler {
  /// Modified times closer than this are "the same" (FAT stores 2 s).
  final int mtimeToleranceSecs;

  /// Largest file [SyncHashResolver] is asked to hash automatically.
  final int hashLimitBytes;

  final int massDeleteMinCount;
  final double massDeleteFraction;

  /// A side that lists as completely empty is only treated as suspicious
  /// (deletions held back) if the ledger says it held at least this many
  /// files. Below that, "the user deleted the last file or two" is far
  /// likelier than "the listing failed", and little is at stake.
  final int emptySideMinBaseline;

  const ThreeWayReconciler({
    this.mtimeToleranceSecs = 2,
    this.hashLimitBytes = 32 * 1024 * 1024,
    this.massDeleteMinCount = 10,
    this.massDeleteFraction = 0.5,
    this.emptySideMinBaseline = 3,
  });

  Future<SyncPlan> reconcile({
    required SyncRule rule,
    required SyncSnapshot vault,
    required SyncSnapshot target,
    required Map<String, SyncStateRecord> baseline,
    required SyncHashResolver hashOf,
    DateTime? now,
  }) async {
    final run = _Run(
      reconciler: this,
      rule: rule,
      vault: vault,
      target: target,
      baseline: baseline,
      hashOf: hashOf,
      stamp: _stamp(now ?? DateTime.now()),
    );
    await run.detectFolderRenames();

    final paths = <String>{
      ...vault.files.keys,
      ...target.files.keys,
      ...baseline.keys.where((k) => !(baseline[k]?.isDir ?? false)),
    }.toList()..sort();

    for (final path in paths) {
      await run.decide(path);
    }
    run.reconcileDirectories();
    run.addSourceCleanupActions();
    return run.finish();
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
        '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}

class _Equality {
  final bool same;
  final SyncSideState vault;
  final SyncSideState target;
  const _Equality(this.same, this.vault, this.target);
}

class _Run {
  final ThreeWayReconciler reconciler;
  final SyncRule rule;
  final SyncSnapshot vault;
  final SyncSnapshot target;
  final Map<String, SyncStateRecord> baseline;
  final SyncHashResolver hashOf;
  final String stamp;
  final List<SyncAction> actions = [];
  final Set<String> _handledPaths = {};
  final Set<String> _renamedOldDirsOnVault = {};
  final Set<String> _renamedOldDirsOnTarget = {};
  final Set<String> _renamedNewDirsOnVault = {};
  final Set<String> _renamedNewDirsOnTarget = {};

  _Run({
    required this.reconciler,
    required this.rule,
    required this.vault,
    required this.target,
    required this.baseline,
    required this.hashOf,
    required this.stamp,
  });

  bool get _canWriteTarget => rule.direction != SyncDirection.targetToVault;
  bool get _canWriteVault => rule.direction != SyncDirection.vaultToTarget;

  /// A missing path is only safe to treat as deleted when that side's scan
  /// could see the whole tree. A rename into an unreadable or truncated
  /// subtree otherwise looks like a set of deletions at the old paths.
  bool _mayHideMissingPaths(SyncSnapshot snapshot) =>
      !snapshot.rootReadable ||
      snapshot.unreadableDirs.isNotEmpty ||
      snapshot.truncatedDirs.isNotEmpty;

  Set<String> _baselineDirs() {
    final dirs = <String>{};
    for (final record in baseline.values) {
      if (record.isDir) {
        dirs.add(record.relPath);
      } else {
        var path = record.relPath;
        while (path.contains('/')) {
          path = path.substring(0, path.lastIndexOf('/'));
          dirs.add(path);
        }
      }
    }
    return dirs;
  }

  bool _looksUnexpectedlyEmpty(SyncSnapshot snapshot) {
    if (snapshot.files.isNotEmpty) return false;
    if (baseline.length >= reconciler.emptySideMinBaseline) return true;

    // Even a small baseline is suspicious when tracked directories vanished
    // and new directory paths appeared together: an unreadable renamed
    // folder would otherwise look like an intentional one-file deletion.
    if (!baseline.values.any((record) => !record.isDir)) return false;
    final oldDirs = _baselineDirs();
    final removedOldDir = oldDirs.any((d) => !snapshot.dirs.contains(d));
    final addedNewDir = snapshot.dirs.any((d) => !oldDirs.contains(d));
    return removedOldDir && addedNewDir;
  }

  bool _hasIncompleteSubtree(SyncSnapshot snapshot, String path) {
    if (_looksUnexpectedlyEmpty(snapshot) ||
        snapshot.isUnderUnreadable(path) ||
        snapshot.isUnderTruncated(path)) {
      return true;
    }
    final prefix = '$path/';
    return snapshot.unreadableDirs.any((d) => d.startsWith(prefix)) ||
        snapshot.truncatedDirs.any((d) => d.isEmpty || d.startsWith(prefix));
  }

  static String _parentPath(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  static Set<String> _relativePathsUnder(
    Iterable<String> paths,
    String directory,
  ) {
    final prefix = '$directory/';
    return paths
        .where((path) => path.startsWith(prefix))
        .map((path) => path.substring(prefix.length))
        .toSet();
  }

  static List<String> _topLevelDirectories(Iterable<String> paths) {
    final candidates = paths.toSet();
    return candidates.where((path) {
      var slash = path.lastIndexOf('/');
      while (slash > 0) {
        if (candidates.contains(path.substring(0, slash))) return false;
        slash = path.lastIndexOf('/', slash - 1);
      }
      return true;
    }).toList()..sort();
  }

  Future<void> detectFolderRenames() async {
    // Rename inference is only safe with complete snapshots. Partial trees
    // are handled by the deletion and empty-directory guards below.
    if (!vault.isComplete || !target.isComplete) return;

    if (rule.direction != SyncDirection.vaultToTarget) {
      await _detectFolderRenamesOnSource(SyncSide.target);
    }
    if (rule.direction != SyncDirection.targetToVault) {
      await _detectFolderRenamesOnSource(SyncSide.vault);
    }
  }

  Future<void> _detectFolderRenamesOnSource(SyncSide sourceSide) async {
    final source = sourceSide == SyncSide.vault ? vault : target;
    final destinationSide = sourceSide.other;
    final destination = destinationSide == SyncSide.vault ? vault : target;
    final baselineDirs = _baselineDirs();

    final oldRoots = _topLevelDirectories(
      baselineDirs.where(
        (d) => destination.dirs.contains(d) && !source.dirs.contains(d),
      ),
    );
    final newRoots = _topLevelDirectories(
      source.dirs
          .where(
            (d) => !baselineDirs.contains(d) && !destination.dirs.contains(d),
          )
          .where((d) {
            final oldParent = _parentPath(d);
            return oldParent.isEmpty ||
                (source.dirs.contains(oldParent) &&
                    destination.dirs.contains(oldParent));
          }),
    );
    if (oldRoots.isEmpty || newRoots.isEmpty) return;

    final matchesByOld = <String, List<String>>{};
    final matchesByNew = <String, int>{};
    for (final oldRoot in oldRoots) {
      for (final newRoot in newRoots) {
        if (_parentPath(oldRoot) != _parentPath(newRoot)) continue;
        if (destination.files.containsKey(newRoot) ||
            _ancestorIsFile(newRoot, destination)) {
          continue;
        }
        if (await _sameUnchangedSubtree(
          oldRoot: oldRoot,
          newRoot: newRoot,
          sourceSide: sourceSide,
          source: source,
          destination: destination,
          baselineDirs: baselineDirs,
        )) {
          matchesByOld.putIfAbsent(oldRoot, () => []).add(newRoot);
          matchesByNew[newRoot] = (matchesByNew[newRoot] ?? 0) + 1;
        }
      }
    }

    for (final entry in matchesByOld.entries) {
      if (entry.value.length != 1) continue;
      final oldRoot = entry.key;
      final newRoot = entry.value.single;
      if (matchesByNew[newRoot] != 1) continue;

      actions.add(
        SyncAction(
          kind: destinationSide == SyncSide.vault
              ? SyncActionKind.moveOnVault
              : SyncActionKind.moveOnTarget,
          relPath: newRoot,
          renameFromPath: oldRoot,
          isDir: true,
        ),
      );
      for (final suffix in _relativePathsUnder(
        baseline.values.where((r) => !r.isDir).map((r) => r.relPath),
        oldRoot,
      )) {
        _handledPaths
          ..add('$oldRoot/$suffix')
          ..add('$newRoot/$suffix');
      }

      final oldDirs = baselineDirs.where(
        (d) => d == oldRoot || d.startsWith('$oldRoot/'),
      );
      final newDirs = source.dirs.where(
        (d) => d == newRoot || d.startsWith('$newRoot/'),
      );
      if (destinationSide == SyncSide.vault) {
        _renamedOldDirsOnVault.addAll(oldDirs);
        _renamedNewDirsOnVault.addAll(newDirs);
      } else {
        _renamedOldDirsOnTarget.addAll(oldDirs);
        _renamedNewDirsOnTarget.addAll(newDirs);
      }
    }
  }

  Future<bool> _sameUnchangedSubtree({
    required String oldRoot,
    required String newRoot,
    required SyncSide sourceSide,
    required SyncSnapshot source,
    required SyncSnapshot destination,
    required Set<String> baselineDirs,
  }) async {
    final oldPrefix = '$oldRoot/';
    final oldRecords = baseline.values
        .where((r) => !r.isDir && r.relPath.startsWith(oldPrefix))
        .toList();

    final expectedFiles = {
      for (final r in oldRecords) r.relPath.substring(oldPrefix.length),
    };
    final destinationFiles = _relativePathsUnder(
      destination.files.keys,
      oldRoot,
    );
    final sourceFiles = _relativePathsUnder(source.files.keys, newRoot);
    if (destinationFiles.length != expectedFiles.length ||
        !destinationFiles.containsAll(expectedFiles) ||
        sourceFiles.length != expectedFiles.length ||
        !sourceFiles.containsAll(expectedFiles)) {
      return false;
    }

    final expectedDirs = _relativePathsUnder(
      baselineDirs.where((d) => d.startsWith(oldPrefix)),
      oldRoot,
    );
    final destinationDirs = _relativePathsUnder(destination.dirs, oldRoot);
    final sourceDirs = _relativePathsUnder(source.dirs, newRoot);
    if (destinationDirs.length != expectedDirs.length ||
        !destinationDirs.containsAll(expectedDirs) ||
        sourceDirs.length != expectedDirs.length ||
        !sourceDirs.containsAll(expectedDirs)) {
      return false;
    }

    for (final record in oldRecords) {
      final suffix = record.relPath.substring(oldPrefix.length);
      final oldPath = '$oldRoot/$suffix';
      final newPath = '$newRoot/$suffix';
      final destinationState = destination.files[oldPath];
      final sourceState = source.files[newPath];
      if (destinationState == null || sourceState == null) return false;

      final destinationBase = _baselineSideState(record, sourceSide.other);
      final sourceBase = _baselineSideState(record, sourceSide);
      if (await _changed(
            sourceSide.other,
            oldPath,
            destinationState,
            destinationBase,
          ) ||
          await _changed(sourceSide, newPath, sourceState, sourceBase)) {
        return false;
      }
    }
    return true;
  }

  static SyncSideState _baselineSideState(
    SyncStateRecord record,
    SyncSide side,
  ) => side == SyncSide.vault ? record.vault : record.target;

  // ── per-path decision ────────────────────────────────────────────────

  Future<void> decide(String path) async {
    if (_handledPaths.contains(path)) return;

    final v = vault.files[path];
    final t = target.files[path];
    final b = baseline[path];

    // Unknown is not deleted: a folder that failed to list, or whose
    // listing was truncated and simply doesn't show this path, says
    // nothing about whether the file still exists there.
    if (vault.isUnderUnreadable(path) ||
        target.isUnderUnreadable(path) ||
        (v == null && vault.isUnderTruncated(path)) ||
        (t == null && target.isUnderTruncated(path))) {
      _skip(path, SyncSkipReason.unreadableSubtree, v, t);
      return;
    }
    // A file on one side where the other side has a folder -- including a
    // file that would have to live *inside* something that is a plain file
    // on the other side. Copying can't safely replace one with the other.
    if ((v != null &&
            (target.dirs.contains(path) || _ancestorIsFile(path, target))) ||
        (t != null &&
            (vault.dirs.contains(path) || _ancestorIsFile(path, vault)))) {
      _skip(path, SyncSkipReason.typeMismatch, v, t);
      return;
    }

    if (v == null && t == null) {
      if (b != null) {
        actions.add(SyncAction(kind: SyncActionKind.forget, relPath: path));
      }
      return;
    }

    if (b == null) {
      await _firstSight(path, v, t);
      return;
    }

    if (v != null && t != null) {
      final vc = await _changed(SyncSide.vault, path, v, b.vault);
      final tc = await _changed(SyncSide.target, path, t, b.target);
      if (vc && tc) {
        await _bothChanged(path, v, t);
      } else if (vc) {
        actions.add(_toTarget(path, v, t));
      } else if (tc) {
        actions.add(_toVault(path, v, t));
      }
      return;
    }

    if (v != null) {
      // Missing on the target.
      final vc = await _changed(SyncSide.vault, path, v, b.vault);
      if (vc) {
        actions.add(_toTarget(path, v, null)); // modification beats deletion
      } else if (_mayHideMissingPaths(target)) {
        _skip(path, SyncSkipReason.unreadableSubtree, v, null);
      } else {
        actions.add(_delete(path, SyncSide.vault, v, null));
      }
      return;
    }

    // Missing on the vault (t != null).
    final tc = await _changed(SyncSide.target, path, t!, b.target);
    if (tc) {
      actions.add(_toVault(path, null, t));
    } else if (_mayHideMissingPaths(vault)) {
      _skip(path, SyncSkipReason.unreadableSubtree, null, t);
    } else {
      actions.add(_delete(path, SyncSide.target, null, t));
    }
  }

  static bool _ancestorIsFile(String path, SyncSnapshot snapshot) {
    var slash = path.indexOf('/');
    while (slash > 0) {
      if (snapshot.files.containsKey(path.substring(0, slash))) return true;
      slash = path.indexOf('/', slash + 1);
    }
    return false;
  }

  Future<void> _firstSight(
    String path,
    SyncSideState? v,
    SyncSideState? t,
  ) async {
    if (v != null && t == null) {
      actions.add(_toTarget(path, v, null));
      return;
    }
    if (v == null && t != null) {
      actions.add(_toVault(path, null, t));
      return;
    }
    final cmp = await _compare(path, v!, t!, trustSameSize: true);
    if (cmp.same) {
      actions.add(
        SyncAction(
          kind: SyncActionKind.adopt,
          relPath: path,
          vaultState: cmp.vault,
          targetState: cmp.target,
        ),
      );
    } else {
      actions.add(_conflict(path, v, t));
    }
  }

  Future<void> _bothChanged(
    String path,
    SyncSideState v,
    SyncSideState t,
  ) async {
    final cmp = await _compare(path, v, t, trustSameSize: false);
    if (cmp.same) {
      actions.add(
        SyncAction(
          kind: SyncActionKind.adopt,
          relPath: path,
          vaultState: cmp.vault,
          targetState: cmp.target,
        ),
      );
    } else {
      actions.add(_conflict(path, v, t));
    }
  }

  // ── comparisons ──────────────────────────────────────────────────────

  Future<bool> _changed(
    SyncSide side,
    String path,
    SyncSideState cur,
    SyncSideState base,
  ) async {
    if (cur.size != base.size) return true;
    // No usable timestamp on either end: size is all there is to go on.
    if (cur.mtimeSecs <= 0 || base.mtimeSecs <= 0) return false;
    if ((cur.mtimeSecs - base.mtimeSecs).abs() <=
        reconciler.mtimeToleranceSecs) {
      return false;
    }
    // Same size but the timestamp moved: a "touch" or a same-size edit.
    // Settle it by hash when we recorded one and the file is small enough.
    final baseHash = base.hash;
    if (baseHash != null && cur.size <= reconciler.hashLimitBytes) {
      final h = await hashOf(side, path);
      if (h != null) return h != baseHash;
    }
    return true;
  }

  /// Are the vault and target copies the same content?
  ///
  /// [trustSameSize] is for first sight, where the two copies typically
  /// come from an earlier manual copy: equal size with agreeing (or
  /// missing) timestamps counts as identical -- the same heuristic the
  /// manual Vault Sync tool uses -- and large files with equal size are
  /// assumed identical rather than read end to end. Once both sides are
  /// known to have *changed*, timestamps say nothing, so only a hash can
  /// prove equality, and a file too large to hash counts as different.
  Future<_Equality> _compare(
    String path,
    SyncSideState v,
    SyncSideState t, {
    required bool trustSameSize,
  }) async {
    if (v.size != t.size) return _Equality(false, v, t);

    if (trustSameSize) {
      final agree =
          v.mtimeSecs <= 0 ||
          t.mtimeSecs <= 0 ||
          (v.mtimeSecs - t.mtimeSecs).abs() <= reconciler.mtimeToleranceSecs;
      if (agree || v.size > reconciler.hashLimitBytes) {
        return _Equality(true, v, t);
      }
    } else if (v.size > reconciler.hashLimitBytes) {
      return _Equality(false, v, t);
    }

    final hv = await hashOf(SyncSide.vault, path);
    final ht = await hashOf(SyncSide.target, path);
    if (hv != null && ht != null && hv == ht) {
      return _Equality(true, v.withHash(hv), t.withHash(ht));
    }
    return _Equality(false, v, t);
  }

  // ── action builders ──────────────────────────────────────────────────

  SyncAction _toTarget(String path, SyncSideState? v, SyncSideState? t) {
    if (!_canWriteTarget)
      return _skipAction(path, SyncSkipReason.directionBlocked, v, t);
    return SyncAction(
      kind: SyncActionKind.copyToTarget,
      relPath: path,
      vaultState: v,
      targetState: t,
      replacesExisting: t != null,
    );
  }

  SyncAction _toVault(String path, SyncSideState? v, SyncSideState? t) {
    if (!_canWriteVault)
      return _skipAction(path, SyncSkipReason.directionBlocked, v, t);
    return SyncAction(
      kind: SyncActionKind.copyToVault,
      relPath: path,
      vaultState: v,
      targetState: t,
      replacesExisting: v != null,
    );
  }

  /// A deletion that must be mirrored: the file vanished from one side, so
  /// it is removed from [side] -- the side that still has it. (Deleting on
  /// the vault therefore means the *target* lost the file.)
  SyncAction _delete(
    String path,
    SyncSide side,
    SyncSideState? v,
    SyncSideState? t,
  ) {
    final canWrite = side == SyncSide.vault ? _canWriteVault : _canWriteTarget;
    if (!canWrite)
      return _skipAction(path, SyncSkipReason.directionBlocked, v, t);
    if (!rule.deleteOrphans)
      return _skipAction(path, SyncSkipReason.deletionsDisabled, v, t);
    return SyncAction(
      kind: side == SyncSide.vault
          ? SyncActionKind.deleteOnVault
          : SyncActionKind.deleteOnTarget,
      relPath: path,
      vaultState: v,
      targetState: t,
    );
  }

  SyncAction _conflict(String path, SyncSideState v, SyncSideState t) {
    final strategy = rule.conflictStrategy;

    if (rule.direction != SyncDirection.twoWay) {
      final winner = rule.direction == SyncDirection.vaultToTarget
          ? SyncSide.vault
          : SyncSide.target;
      if (strategy == ConflictStrategy.renameConflict) {
        return _keepBoth(path, v, t, winner: winner, propagate: false);
      }
      return winner == SyncSide.vault
          ? _toTarget(path, v, t)
          : _toVault(path, v, t);
    }

    switch (strategy) {
      case ConflictStrategy.renameConflict:
        return _keepBoth(path, v, t, winner: SyncSide.target, propagate: true);
      case ConflictStrategy.vaultWins:
        return _toTarget(path, v, t);
      case ConflictStrategy.targetWins:
        return _toVault(path, v, t);
      case ConflictStrategy.keepNewer:
        if (v.mtimeSecs > 0 && t.mtimeSecs > 0) {
          final tol = reconciler.mtimeToleranceSecs;
          if (v.mtimeSecs > t.mtimeSecs + tol) return _toTarget(path, v, t);
          if (t.mtimeSecs > v.mtimeSecs + tol) return _toVault(path, v, t);
        }
        // Can't tell which is newer: never guess, keep both.
        return _keepBoth(path, v, t, winner: SyncSide.target, propagate: true);
    }
  }

  SyncAction _keepBoth(
    String path,
    SyncSideState v,
    SyncSideState t, {
    required SyncSide winner,
    required bool propagate,
  }) {
    final loser = winner.other;
    final label = loser == SyncSide.vault ? 'Vault' : 'Target';
    return SyncAction(
      kind: SyncActionKind.keepBoth,
      relPath: path,
      vaultState: v,
      targetState: t,
      replacesExisting: true,
      winner: winner,
      conflictCopyPath: _conflictName(path, label),
      propagateConflictCopy: propagate,
    );
  }

  String _conflictName(String relPath, String label) {
    final slash = relPath.lastIndexOf('/');
    final dir = slash < 0 ? '' : relPath.substring(0, slash + 1);
    final name = slash < 0 ? relPath : relPath.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    return '$dir$stem ($label Conflict $stamp)$ext';
  }

  void _skip(
    String path,
    SyncSkipReason reason,
    SyncSideState? v,
    SyncSideState? t, {
    bool isDir = false,
  }) => actions.add(_skipAction(path, reason, v, t, isDir: isDir));

  SyncAction _skipAction(
    String path,
    SyncSkipReason reason,
    SyncSideState? v,
    SyncSideState? t, {
    bool isDir = false,
  }) => SyncAction(
    kind: SyncActionKind.skip,
    relPath: path,
    vaultState: v,
    targetState: t,
    skipReason: reason,
    isDir: isDir,
  );

  // ── directory reconciliation ──────────────────────────────────────

  void reconcileDirectories() {
    final vaultSurvivingFiles = {...vault.files.keys}
      ..removeAll(
        actions
            .where((a) => a.kind == SyncActionKind.deleteOnVault)
            .map((a) => a.relPath),
      );
    vaultSurvivingFiles.addAll(
      actions
          .where((a) => a.kind == SyncActionKind.copyToVault)
          .map((a) => a.relPath),
    );
    for (final action in actions.where(
      (a) => a.kind == SyncActionKind.moveOnVault,
    )) {
      final from = action.renameFromPath!;
      if (action.isDir) {
        final prefix = '$from/';
        final moved = vault.files.keys
            .where((path) => path.startsWith(prefix))
            .map((path) => '${action.relPath}/${path.substring(prefix.length)}')
            .toList();
        vaultSurvivingFiles.removeWhere((path) => path.startsWith(prefix));
        vaultSurvivingFiles.addAll(moved);
      } else {
        vaultSurvivingFiles
          ..remove(from)
          ..add(action.relPath);
      }
    }

    final targetSurvivingFiles = {...target.files.keys}
      ..removeAll(
        actions
            .where((a) => a.kind == SyncActionKind.deleteOnTarget)
            .map((a) => a.relPath),
      );
    targetSurvivingFiles.addAll(
      actions
          .where((a) => a.kind == SyncActionKind.copyToTarget)
          .map((a) => a.relPath),
    );
    for (final action in actions.where(
      (a) => a.kind == SyncActionKind.moveOnTarget,
    )) {
      final from = action.renameFromPath!;
      if (action.isDir) {
        final prefix = '$from/';
        final moved = target.files.keys
            .where((path) => path.startsWith(prefix))
            .map((path) => '${action.relPath}/${path.substring(prefix.length)}')
            .toList();
        targetSurvivingFiles.removeWhere((path) => path.startsWith(prefix));
        targetSurvivingFiles.addAll(moved);
      } else {
        targetSurvivingFiles
          ..remove(from)
          ..add(action.relPath);
      }
    }

    bool clashingWithFile(String d, SyncSnapshot snap) {
      return snap.files.containsKey(d) || _ancestorIsFile(d, snap);
    }

    final existingActionPaths = {for (final a in actions) a.relPath}
      ..addAll(_renamedOldDirsOnVault)
      ..addAll(_renamedOldDirsOnTarget)
      ..addAll(_renamedNewDirsOnVault)
      ..addAll(_renamedNewDirsOnTarget);

    final baselineDirs = _baselineDirs();

    if (rule.direction == SyncDirection.vaultToTarget) {
      final toCreate =
          vault.dirs.where((d) => !target.dirs.contains(d)).toList()
            ..sort((a, b) => a.length.compareTo(b.length));
      for (final d in toCreate) {
        // The directory itself may be visible even when its contents could
        // not be listed. Don't mirror it as an empty folder until the source
        // subtree is readable; a later complete scan will create it with its
        // files.
        if (_hasIncompleteSubtree(vault, d)) continue;
        if (existingActionPaths.contains(d) || clashingWithFile(d, target))
          continue;
        actions.add(
          SyncAction(
            kind: SyncActionKind.createDirOnTarget,
            relPath: d,
            isDir: true,
          ),
        );
        existingActionPaths.add(d);
      }

      if (rule.deleteOrphans) {
        if (_mayHideMissingPaths(vault)) return;
        final toDelete =
            target.dirs.where((d) => !vault.dirs.contains(d)).toList()
              ..sort((a, b) => b.length.compareTo(a.length));
        final deletedDirs = <String>{};
        for (final d in toDelete) {
          if (existingActionPaths.contains(d)) continue;
          if (target.isUnderUnreadable(d) || target.isUnderTruncated(d))
            continue;
          final prefix = '$d/';
          final hasFiles = targetSurvivingFiles.any(
            (f) => f.startsWith(prefix),
          );
          final hasSubdirs = target.dirs.any(
            (other) =>
                other != d &&
                other.startsWith(prefix) &&
                !deletedDirs.contains(other),
          );
          if (!hasFiles && !hasSubdirs) {
            actions.add(
              SyncAction(
                kind: SyncActionKind.deleteDirOnTarget,
                relPath: d,
                isDir: true,
              ),
            );
            deletedDirs.add(d);
            existingActionPaths.add(d);
          }
        }
      }
    } else if (rule.direction == SyncDirection.targetToVault) {
      final toCreate =
          target.dirs.where((d) => !vault.dirs.contains(d)).toList()
            ..sort((a, b) => a.length.compareTo(b.length));
      for (final d in toCreate) {
        // The directory itself may be visible even when its contents could
        // not be listed. Don't mirror it as an empty folder until the source
        // subtree is readable; a later complete scan will create it with its
        // files.
        if (_hasIncompleteSubtree(target, d)) continue;
        if (existingActionPaths.contains(d) || clashingWithFile(d, vault))
          continue;
        actions.add(
          SyncAction(
            kind: SyncActionKind.createDirOnVault,
            relPath: d,
            isDir: true,
          ),
        );
        existingActionPaths.add(d);
      }

      if (rule.deleteOrphans) {
        if (_mayHideMissingPaths(target)) return;
        final toDelete =
            vault.dirs.where((d) => !target.dirs.contains(d)).toList()
              ..sort((a, b) => b.length.compareTo(a.length));
        final deletedDirs = <String>{};
        for (final d in toDelete) {
          if (existingActionPaths.contains(d)) continue;
          if (vault.isUnderUnreadable(d) || vault.isUnderTruncated(d)) continue;
          final prefix = '$d/';
          final hasFiles = vaultSurvivingFiles.any((f) => f.startsWith(prefix));
          final hasSubdirs = vault.dirs.any(
            (other) =>
                other != d &&
                other.startsWith(prefix) &&
                !deletedDirs.contains(other),
          );
          if (!hasFiles && !hasSubdirs) {
            actions.add(
              SyncAction(
                kind: SyncActionKind.deleteDirOnVault,
                relPath: d,
                isDir: true,
              ),
            );
            deletedDirs.add(d);
            existingActionPaths.add(d);
          }
        }
      }
    } else {
      // Two-way sync
      final allDirs = {...vault.dirs, ...target.dirs, ...baselineDirs}.toList()
        ..sort((a, b) => a.length.compareTo(b.length));

      for (final d in allDirs) {
        if (existingActionPaths.contains(d)) continue;
        final inV = vault.dirs.contains(d);
        final inT = target.dirs.contains(d);
        final inB = baselineDirs.contains(d);

        if (inV && !inT && !inB) {
          if (!_hasIncompleteSubtree(vault, d) &&
              !clashingWithFile(d, target)) {
            actions.add(
              SyncAction(
                kind: SyncActionKind.createDirOnTarget,
                relPath: d,
                isDir: true,
              ),
            );
            existingActionPaths.add(d);
          }
        } else if (!inV && inT && !inB) {
          if (!_hasIncompleteSubtree(target, d) &&
              !clashingWithFile(d, vault)) {
            actions.add(
              SyncAction(
                kind: SyncActionKind.createDirOnVault,
                relPath: d,
                isDir: true,
              ),
            );
            existingActionPaths.add(d);
          }
        }
      }

      final allDirsReversed = allDirs.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      final deletedVaultDirs = <String>{};
      final deletedTargetDirs = <String>{};

      for (final d in allDirsReversed) {
        if (existingActionPaths.contains(d)) continue;
        final inV = vault.dirs.contains(d);
        final inT = target.dirs.contains(d);
        final inB = baselineDirs.contains(d);

        if (inV && !inT && inB) {
          if (target.isUnderUnreadable(d) || target.isUnderTruncated(d))
            continue;
          if (rule.deleteOrphans) {
            if (_mayHideMissingPaths(target)) continue;
            final prefix = '$d/';
            final hasFiles = vaultSurvivingFiles.any(
              (f) => f.startsWith(prefix),
            );
            final hasSubdirs = vault.dirs.any(
              (other) =>
                  other != d &&
                  other.startsWith(prefix) &&
                  !deletedVaultDirs.contains(other),
            );
            if (!hasFiles && !hasSubdirs) {
              actions.add(
                SyncAction(
                  kind: SyncActionKind.deleteDirOnVault,
                  relPath: d,
                  isDir: true,
                ),
              );
              deletedVaultDirs.add(d);
              existingActionPaths.add(d);
            }
          } else {
            if (!clashingWithFile(d, target)) {
              actions.add(
                SyncAction(
                  kind: SyncActionKind.createDirOnTarget,
                  relPath: d,
                  isDir: true,
                ),
              );
              existingActionPaths.add(d);
            }
          }
        } else if (!inV && inT && inB) {
          if (vault.isUnderUnreadable(d) || vault.isUnderTruncated(d)) continue;
          if (rule.deleteOrphans) {
            if (_mayHideMissingPaths(vault)) continue;
            final prefix = '$d/';
            final hasFiles = targetSurvivingFiles.any(
              (f) => f.startsWith(prefix),
            );
            final hasSubdirs = target.dirs.any(
              (other) =>
                  other != d &&
                  other.startsWith(prefix) &&
                  !deletedTargetDirs.contains(other),
            );
            if (!hasFiles && !hasSubdirs) {
              actions.add(
                SyncAction(
                  kind: SyncActionKind.deleteDirOnTarget,
                  relPath: d,
                  isDir: true,
                ),
              );
              deletedTargetDirs.add(d);
              existingActionPaths.add(d);
            }
          } else {
            if (!clashingWithFile(d, vault)) {
              actions.add(
                SyncAction(
                  kind: SyncActionKind.createDirOnVault,
                  relPath: d,
                  isDir: true,
                ),
              );
              existingActionPaths.add(d);
            }
          }
        } else if (!inV && !inT && inB) {
          if (baseline[d]?.isDir ?? false) {
            actions.add(
              SyncAction(kind: SyncActionKind.forget, relPath: d, isDir: true),
            );
            existingActionPaths.add(d);
          }
        }
      }
    }
  }

  /// Adds cleanup candidates for visible source files. The executor removes
  /// each source only after the vault copy is committed and both SHA-256
  /// digests match.
  void addSourceCleanupActions() {
    if (rule.direction != SyncDirection.targetToVault ||
        !rule.deleteSourceAfterImport) {
      return;
    }

    final paths = target.files.keys.toList()..sort();
    for (final path in paths) {
      actions.add(
        SyncAction(
          kind: SyncActionKind.deleteSourceAfterImport,
          relPath: path,
          vaultState: vault.files[path],
          targetState: target.files[path],
        ),
      );
    }
  }

  // ── mass-deletion guard ─────────────────────────────────────────────

  SyncPlan finish() {
    final baselineCount = baseline.length;
    final limit = math.max(
      reconciler.massDeleteMinCount,
      (baselineCount * reconciler.massDeleteFraction).floor(),
    );

    final delFileOnVault = actions
        .where((a) => !a.isDir && a.kind == SyncActionKind.deleteOnVault)
        .toList();
    final delFileOnTarget = actions
        .where((a) => !a.isDir && a.kind == SyncActionKind.deleteOnTarget)
        .toList();

    // Check for renames/moves so moving/renaming files is not falsely counted as mass deletion:
    final copyToTargetFiles = actions
        .where((a) => !a.isDir && a.kind == SyncActionKind.copyToTarget)
        .toList();
    final copyToVaultFiles = actions
        .where((a) => !a.isDir && a.kind == SyncActionKind.copyToVault)
        .toList();

    int renamedOnTarget = 0;
    final availableTargetCopies = List<SyncAction>.of(copyToTargetFiles);
    for (final del in delFileOnTarget) {
      final delName = del.relPath.split('/').last;
      final delSize = del.targetState?.size ?? 0;
      final matchIdx = availableTargetCopies.indexWhere(
        (c) =>
            c.relPath.split('/').last == delName &&
            (c.vaultState?.size ?? 0) == delSize,
      );
      if (matchIdx >= 0) {
        renamedOnTarget++;
        availableTargetCopies.removeAt(matchIdx);
      }
    }

    int renamedOnVault = 0;
    final availableVaultCopies = List<SyncAction>.of(copyToVaultFiles);
    for (final del in delFileOnVault) {
      final delName = del.relPath.split('/').last;
      final delSize = del.vaultState?.size ?? 0;
      final matchIdx = availableVaultCopies.indexWhere(
        (c) =>
            c.relPath.split('/').last == delName &&
            (c.targetState?.size ?? 0) == delSize,
      );
      if (matchIdx >= 0) {
        renamedOnVault++;
        availableVaultCopies.removeAt(matchIdx);
      }
    }

    final netDelOnVault = delFileOnVault.length - renamedOnVault;
    final netDelOnTarget = delFileOnTarget.length - renamedOnTarget;

    // Deleting on the vault is driven by what the target *lost*, so an
    // empty target listing is the suspicious case there (and vice versa).
    final targetLooksUnexpectedlyEmpty = _looksUnexpectedlyEmpty(target);
    final vaultLooksUnexpectedlyEmpty = _looksUnexpectedlyEmpty(vault);
    final blockVault =
        delFileOnVault.isNotEmpty &&
        (targetLooksUnexpectedlyEmpty || netDelOnVault > limit);
    final blockTarget =
        delFileOnTarget.isNotEmpty &&
        (vaultLooksUnexpectedlyEmpty || netDelOnTarget > limit);

    if (!blockVault && !blockTarget) {
      return SyncPlan(ruleId: rule.id, actions: List.unmodifiable(actions));
    }

    final guarded = <SyncAction>[
      for (final a in actions)
        if ((blockVault &&
                (a.kind == SyncActionKind.deleteOnVault ||
                    a.kind == SyncActionKind.deleteDirOnVault)) ||
            (blockTarget &&
                (a.kind == SyncActionKind.deleteOnTarget ||
                    a.kind == SyncActionKind.deleteDirOnTarget)))
          _skipAction(
            a.relPath,
            SyncSkipReason.massDeleteGuard,
            a.vaultState,
            a.targetState,
            isDir: a.isDir,
          )
        else
          a,
    ];
    return SyncPlan(
      ruleId: rule.id,
      actions: List.unmodifiable(guarded),
      deletionsBlocked: true,
    );
  }
}
