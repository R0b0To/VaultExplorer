import 'dart:math' as math;

import 'package:vaultexplorer/features/sync/domain/models/sync_plan.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_state_record.dart';

/// Content hash of [relPath] on [side], or null if it can't be computed.
typedef SyncHashResolver = Future<String?> Function(SyncSide side, String relPath);

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

    final paths = <String>{
      ...vault.files.keys,
      ...target.files.keys,
      ...baseline.keys,
    }.toList()..sort();

    for (final path in paths) {
      await run.decide(path);
    }
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

  // ── per-path decision ────────────────────────────────────────────────

  Future<void> decide(String path) async {
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
      } else {
        actions.add(_delete(path, SyncSide.vault, v, null));
      }
      return;
    }

    // Missing on the vault (t != null).
    final tc = await _changed(SyncSide.target, path, t!, b.target);
    if (tc) {
      actions.add(_toVault(path, null, t));
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

  Future<void> _firstSight(String path, SyncSideState? v, SyncSideState? t) async {
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

  Future<void> _bothChanged(String path, SyncSideState v, SyncSideState t) async {
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
    if ((cur.mtimeSecs - base.mtimeSecs).abs() <= reconciler.mtimeToleranceSecs) {
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
    if (!_canWriteTarget) return _skipAction(path, SyncSkipReason.directionBlocked, v, t);
    return SyncAction(
      kind: SyncActionKind.copyToTarget,
      relPath: path,
      vaultState: v,
      targetState: t,
      replacesExisting: t != null,
    );
  }

  SyncAction _toVault(String path, SyncSideState? v, SyncSideState? t) {
    if (!_canWriteVault) return _skipAction(path, SyncSkipReason.directionBlocked, v, t);
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
  SyncAction _delete(String path, SyncSide side, SyncSideState? v, SyncSideState? t) {
    final canWrite = side == SyncSide.vault ? _canWriteVault : _canWriteTarget;
    if (!canWrite) return _skipAction(path, SyncSkipReason.directionBlocked, v, t);
    if (!rule.deleteOrphans) return _skipAction(path, SyncSkipReason.deletionsDisabled, v, t);
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
      return winner == SyncSide.vault ? _toTarget(path, v, t) : _toVault(path, v, t);
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

  void _skip(String path, SyncSkipReason reason, SyncSideState? v, SyncSideState? t) =>
      actions.add(_skipAction(path, reason, v, t));

  SyncAction _skipAction(
    String path,
    SyncSkipReason reason,
    SyncSideState? v,
    SyncSideState? t,
  ) => SyncAction(
    kind: SyncActionKind.skip,
    relPath: path,
    vaultState: v,
    targetState: t,
    skipReason: reason,
  );

  // ── mass-deletion guard ─────────────────────────────────────────────

  SyncPlan finish() {
    final baselineCount = baseline.length;
    final limit = math.max(
      reconciler.massDeleteMinCount,
      (baselineCount * reconciler.massDeleteFraction).floor(),
    );

    final delOnVault = actions.where((a) => a.kind == SyncActionKind.deleteOnVault).length;
    final delOnTarget = actions.where((a) => a.kind == SyncActionKind.deleteOnTarget).length;

    // Deleting on the vault is driven by what the target *lost*, so an
    // empty target listing is the suspicious case there (and vice versa).
    final emptyIsSuspicious = baselineCount >= reconciler.emptySideMinBaseline;
    final blockVault =
        delOnVault > 0 &&
        ((target.files.isEmpty && emptyIsSuspicious) || delOnVault > limit);
    final blockTarget =
        delOnTarget > 0 &&
        ((vault.files.isEmpty && emptyIsSuspicious) || delOnTarget > limit);

    if (!blockVault && !blockTarget) {
      return SyncPlan(ruleId: rule.id, actions: List.unmodifiable(actions));
    }

    final guarded = <SyncAction>[
      for (final a in actions)
        if ((blockVault && a.kind == SyncActionKind.deleteOnVault) ||
            (blockTarget && a.kind == SyncActionKind.deleteOnTarget))
          _skipAction(a.relPath, SyncSkipReason.massDeleteGuard, a.vaultState, a.targetState)
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
