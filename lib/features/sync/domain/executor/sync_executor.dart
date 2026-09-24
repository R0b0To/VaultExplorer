import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/sync/data/ledger/sync_ledger_repository.dart';
import 'package:vaultexplorer/features/sync/domain/endpoints/sync_endpoint.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_plan.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_state_record.dart';
import 'package:vaultexplorer/features/sync/domain/sync_cancellation.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

class _StepFailed implements Exception {
  final String reason;
  const _StepFailed(this.reason);

  @override
  String toString() => '_StepFailed($reason)';
}

/// A ledger row still to be written once the destination's real
/// post-write state is known. A side left null is looked up with
/// [SyncEndpoint.stat] at the end.
class _PendingBaseline {
  final String path;
  final SyncSideState? vault;
  final SyncSideState? target;
  const _PendingBaseline(this.path, {this.vault, this.target});
}

/// Carries out a [SyncPlan].
///
/// **Atomic replace.** A file is never written in place. It is copied to
/// `<name>.vexp_tmp`, and only once that copy is complete is it swapped
/// into place. The storage layer refuses to rename onto an existing name
/// (a standing rule of the app), so replacing an existing file is a
/// three-step swap that never leaves a moment without a complete copy:
///
/// 1. copy source -> `name.vexp_tmp`
/// 2. rename `name` -> `name.vexp_old`, then `name.vexp_tmp` -> `name`
/// 3. delete `name.vexp_old`
///
/// If the process dies part-way, the next run's [cleanupLeftovers] deletes
/// stray temp files and restores a `.vexp_old` whose original went
/// missing -- the file is either the old version or the new one, never a
/// torn write.
///
/// **Cancellation.** [SyncCancellationToken] is polled between actions and
/// inside each transfer; a cancelled transfer deletes its temp file and
/// stops the run. Baselines for everything that *did* complete are still
/// recorded, so a cancelled run loses no progress.
///
/// **Loop prevention.** After a write the ledger holds the destination's
/// real post-write size/mtime, so the next scan sees "unchanged" and
/// nothing bounces back. [inFlightPaths] / [wasRecentlyWritten] are the
/// second layer, for a live watcher that needs to ignore events caused by
/// the engine's own writes.
class SyncExecutor {
  /// Sync copy-operation ids live in their own range so they can't collide
  /// with `FileOperationService`'s (which counts up from 1) in the native
  /// cancellation table.
  static int _opSeq = 1500000000;

  static const String _tag = 'SyncExecutor';

  final DateTime Function() _now;
  final Duration recentWriteWindow;

  SyncExecutor({
    DateTime Function()? now,
    this.recentWriteWindow = const Duration(seconds: 10),
  }) : _now = now ?? DateTime.now;

  /// `"<side>:<relPath>"` of files being written right now.
  final Set<String> inFlightPaths = {};
  final Map<String, DateTime> _recentWrites = {};

  static String _key(SyncSide side, String rel) => '${side.name}:$rel';

  bool isInFlight(SyncSide side, String rel) =>
      inFlightPaths.contains(_key(side, rel));

  /// True if the engine itself wrote [rel] on [side] within
  /// [recentWriteWindow] (or is writing it now).
  bool wasRecentlyWritten(SyncSide side, String rel) {
    final key = _key(side, rel);
    if (inFlightPaths.contains(key)) return true;
    final at = _recentWrites[key];
    if (at == null) return false;
    if (_now().difference(at) <= recentWriteWindow) return true;
    _recentWrites.remove(key);
    return false;
  }

  // ── leftovers from an interrupted run ────────────────────────────────

  /// Deletes stray `*.vexp_tmp` files and resolves `*.vexp_old` ones (see
  /// the class comment). Returns how many entries were dealt with.
  Future<int> cleanupLeftovers(SyncEndpoint endpoint, SyncSnapshot snapshot) async {
    var handled = 0;
    for (final rel in snapshot.leftovers) {
      if (rel.endsWith(kSyncTempSuffix)) {
        if (await endpoint.delete(rel)) handled++;
      } else if (rel.endsWith(kSyncBackupSuffix)) {
        final original = rel.substring(0, rel.length - kSyncBackupSuffix.length);
        final ok = snapshot.files.containsKey(original)
            ? await endpoint.delete(rel)
            : await endpoint.rename(rel, original);
        if (ok) handled++;
      }
    }
    return handled;
  }

  // ── execution ────────────────────────────────────────────────────────

  Future<SyncRunReport> execute({
    required SyncRule rule,
    required SyncPlan plan,
    required SyncEndpoint vault,
    required SyncEndpoint target,
    required SyncLedgerRepository ledger,
    required SyncCancellationToken token,
    void Function(SyncProgress progress)? onProgress,
    bool incompleteScan = false,

    /// Key the ledger rows are filed under; defaults to `rule.id`.
    String? ledgerKey,
  }) async {
    final key = ledgerKey ?? rule.id;

    // Directory creates first (shallowest first), then bookkeeping,
    // then transfers, then file deletions, then directory deletions (deepest first).
    final dirCreates = <SyncAction>[];
    final cheap = <SyncAction>[];
    final transfers = <SyncAction>[];
    final fileDeletions = <SyncAction>[];
    final dirDeletions = <SyncAction>[];
    for (final a in plan.actions) {
      switch (a.kind) {
        case SyncActionKind.createDirOnTarget:
        case SyncActionKind.createDirOnVault:
          dirCreates.add(a);
        case SyncActionKind.adopt:
        case SyncActionKind.forget:
          cheap.add(a);
        case SyncActionKind.copyToTarget:
        case SyncActionKind.copyToVault:
        case SyncActionKind.keepBoth:
          transfers.add(a);
        case SyncActionKind.deleteOnTarget:
        case SyncActionKind.deleteOnVault:
          fileDeletions.add(a);
        case SyncActionKind.deleteDirOnTarget:
        case SyncActionKind.deleteDirOnVault:
          dirDeletions.add(a);
        case SyncActionKind.skip:
          break;
      }
    }
    dirCreates.sort((a, b) => a.relPath.length.compareTo(b.relPath.length));
    dirDeletions.sort((a, b) => b.relPath.length.compareTo(a.relPath.length));

    final work = [
      ...dirCreates,
      ...cheap,
      ...transfers,
      ...fileDeletions,
      ...dirDeletions,
    ];

    var done = 0;
    var failed = 0;
    var copied = 0;
    var deleted = 0;
    var kept = 0;
    var adopted = 0;
    var cancelled = false;
    final pending = <_PendingBaseline>[];

    void report(String? current) => onProgress?.call(
      SyncProgress(
        ruleId: rule.id,
        totalActions: work.length,
        doneActions: done,
        failedActions: failed,
        currentPath: current,
      ),
    );

    try {
      for (final action in work) {
        if (token.isCancelled) {
          cancelled = true;
          break;
        }
        report(action.relPath);
        try {
          switch (action.kind) {
            case SyncActionKind.createDirOnTarget:
              final ok = await target.ensureDirectory(action.relPath);
              if (!ok) throw const _StepFailed('mkdir');
              _put(
                ledger,
                key,
                action.relPath,
                const SyncSideState(size: 0, mtimeSecs: 0),
                const SyncSideState(size: 0, mtimeSecs: 0),
                isDir: true,
              );
              copied++;
            case SyncActionKind.createDirOnVault:
              final ok = await vault.ensureDirectory(action.relPath);
              if (!ok) throw const _StepFailed('mkdir');
              _put(
                ledger,
                key,
                action.relPath,
                const SyncSideState(size: 0, mtimeSecs: 0),
                const SyncSideState(size: 0, mtimeSecs: 0),
                isDir: true,
              );
              copied++;
            case SyncActionKind.adopt:
              final v = action.vaultState;
              final t = action.targetState;
              if (v != null && t != null) {
                _put(ledger, key, action.relPath, v, t, isDir: action.isDir);
              }
              adopted++;
            case SyncActionKind.forget:
              ledger.remove(key, action.relPath);
            case SyncActionKind.copyToTarget:
              await _copyAtomic(
                source: vault,
                dest: target,
                destSide: SyncSide.target,
                rel: action.relPath,
                destExists: action.replacesExisting,
                sourceMtime: action.vaultState?.mtimeSecs ?? 0,
                token: token,
              );
              pending.add(_PendingBaseline(action.relPath, vault: action.vaultState));
              copied++;
            case SyncActionKind.copyToVault:
              await _copyAtomic(
                source: target,
                dest: vault,
                destSide: SyncSide.vault,
                rel: action.relPath,
                destExists: action.replacesExisting,
                sourceMtime: action.targetState?.mtimeSecs ?? 0,
                token: token,
              );
              pending.add(_PendingBaseline(action.relPath, target: action.targetState));
              copied++;
            case SyncActionKind.keepBoth:
              await _keepBoth(
                action: action,
                vault: vault,
                target: target,
                token: token,
                pending: pending,
              );
              kept++;
            case SyncActionKind.deleteOnTarget:
              await _delete(target, action.relPath);
              ledger.remove(key, action.relPath);
              deleted++;
            case SyncActionKind.deleteOnVault:
              await _delete(vault, action.relPath);
              ledger.remove(key, action.relPath);
              deleted++;
            case SyncActionKind.deleteDirOnTarget:
              await _delete(target, action.relPath);
              ledger.remove(key, action.relPath);
              deleted++;
            case SyncActionKind.deleteDirOnVault:
              await _delete(vault, action.relPath);
              ledger.remove(key, action.relPath);
              deleted++;
            case SyncActionKind.skip:
              break;
          }
          done++;
        } on SyncCancelledException {
          cancelled = true;
          break;
        } catch (e) {
          // One bad file must not stop the rest. No path in the log:
          // file names are private.
          failed++;
          VeLog.d(_tag, 'action ${action.kind.name} failed: $e');
        }
      }
    } finally {
      await _recordBaselines(key, vault, target, ledger, pending);
      report(null);
    }

    return SyncRunReport(
      ruleId: rule.id,
      copied: copied,
      deleted: deleted,
      conflictsKeptBoth: kept,
      adopted: adopted,
      skipped: plan.skippedCount,
      failed: failed,
      cancelled: cancelled,
      deletionsBlocked: plan.deletionsBlocked,
      incompleteScan: incompleteScan,
    );
  }

  void _put(
    SyncLedgerRepository ledger,
    String ruleId,
    String rel,
    SyncSideState vault,
    SyncSideState target, {
    bool isDir = false,
  }) {
    ledger.put(
      SyncStateRecord(
        ruleId: ruleId,
        relPath: rel,
        vault: vault,
        target: target,
        lastSyncedAtMs: _now().millisecondsSinceEpoch,
        isDir: isDir,
      ),
    );
  }

  /// Turns the pending baselines into ledger rows, looking up whichever
  /// side's state isn't already known.
  Future<void> _recordBaselines(
    String ruleId,
    SyncEndpoint vault,
    SyncEndpoint target,
    SyncLedgerRepository ledger,
    List<_PendingBaseline> pending,
  ) async {
    if (pending.isEmpty) return;

    final needVault = <String>{
      for (final p in pending)
        if (p.vault == null) p.path,
    };
    final needTarget = <String>{
      for (final p in pending)
        if (p.target == null) p.path,
    };
    final Map<String, SyncSideState> vaultNow = needVault.isEmpty
        ? const {}
        : await vault.stat(needVault);
    final Map<String, SyncSideState> targetNow = needTarget.isEmpty
        ? const {}
        : await target.stat(needTarget);

    for (final p in pending) {
      final v = p.vault ?? vaultNow[p.path];
      final t = p.target ?? targetNow[p.path];
      // Can't establish both sides -> leave it unrecorded. The next run
      // treats it as first sight, which never deletes anything.
      if (v == null || t == null) continue;
      _put(ledger, ruleId, p.path, v, t);
    }
  }

  // ── primitives ───────────────────────────────────────────────────────

  Future<void> _delete(SyncEndpoint endpoint, String rel) async {
    if (await endpoint.delete(rel)) return;
    // "Couldn't delete" is fine if it is simply gone already.
    final still = await endpoint.stat([rel]);
    if (still.containsKey(rel)) throw const _StepFailed('delete');
  }

  /// Copies [rel] from [source] to [dest] via a temp file and a swap. See
  /// the class comment for why it's shaped this way.
  Future<void> _copyAtomic({
    required SyncEndpoint source,
    required SyncEndpoint dest,
    required SyncSide destSide,
    required String rel,
    required bool destExists,
    required int sourceMtime,
    required SyncCancellationToken token,
  }) async {
    final tmp = '$rel$kSyncTempSuffix';
    final old = '$rel$kSyncBackupSuffix';
    final key = _key(destSide, rel);

    inFlightPaths.add(key);
    try {
      final slash = rel.lastIndexOf('/');
      if (slash > 0 && !await dest.ensureDirectory(rel.substring(0, slash))) {
        throw const _StepFailed('mkdir');
      }

      await dest.delete(tmp); // stale leftover from an earlier attempt

      var copied = false;
      try {
        copied = await dest.copyFrom(
          source,
          rel,
          tmp,
          opId: ++_opSeq,
          token: token,
        );
      } on SyncCancelledException {
        await dest.delete(tmp);
        rethrow;
      } catch (_) {
        copied = false;
      }
      if (token.isCancelled) {
        await dest.delete(tmp);
        throw const SyncCancelledException();
      }
      if (!copied) {
        await dest.delete(tmp);
        throw const _StepFailed('copy');
      }

      // The temp copy is complete. From here the swap runs to the end even
      // if a cancel arrives: it is a few quick renames, and stopping in the
      // middle would be the one way to leave a mess.
      if (destExists) {
        await dest.delete(old);
        final movedAside = await dest.rename(rel, old);
        if (!movedAside) {
          final stillThere = await dest.stat([rel]);
          if (stillThere.containsKey(rel)) {
            await dest.delete(tmp);
            throw const _StepFailed('swap-aside');
          }
        }
        if (!await dest.rename(tmp, rel)) {
          if (movedAside) await dest.rename(old, rel); // put the old one back
          await dest.delete(tmp);
          throw const _StepFailed('swap-in');
        }
        if (movedAside) await dest.delete(old);
      } else if (!await dest.rename(tmp, rel)) {
        await dest.delete(tmp);
        throw const _StepFailed('rename');
      }

      if (sourceMtime > 0) await dest.setModified(rel, sourceMtime);
    } finally {
      inFlightPaths.remove(key);
      _recentWrites[key] = _now();
    }
  }

  /// Both sides changed the file and neither may win silently.
  ///
  /// 1. the loser's version is renamed to the conflict-copy name,
  /// 2. the winner's version is copied over to the loser's side under the
  ///    original name,
  /// 3. (two-way rules) the conflict copy is copied to the winner's side,
  ///    so both sides end up holding both versions.
  ///
  /// Nothing is ever overwritten before a complete copy of it exists
  /// elsewhere, so no version is lost at any point.
  Future<void> _keepBoth({
    required SyncAction action,
    required SyncEndpoint vault,
    required SyncEndpoint target,
    required SyncCancellationToken token,
    required List<_PendingBaseline> pending,
  }) async {
    final winnerSide = action.winner;
    final wantedCopy = action.conflictCopyPath;
    if (winnerSide == null || wantedCopy == null) {
      throw const _StepFailed('keepBoth-incomplete');
    }
    final rel = action.relPath;
    final winner = winnerSide == SyncSide.vault ? vault : target;
    final loser = winnerSide == SyncSide.vault ? target : vault;
    final loserSide = winnerSide.other;
    final winnerState = winnerSide == SyncSide.vault
        ? action.vaultState
        : action.targetState;

    final copyPath = await _freeConflictName(winner, loser, wantedCopy);
    if (copyPath == null) throw const _StepFailed('conflict-name');

    if (!await loser.rename(rel, copyPath)) {
      throw const _StepFailed('conflict-rename');
    }

    try {
      await _copyAtomic(
        source: winner,
        dest: loser,
        destSide: loserSide,
        rel: rel,
        destExists: false, // just moved aside
        sourceMtime: winnerState?.mtimeSecs ?? 0,
        token: token,
      );
    } catch (_) {
      // Put the loser's file back under its own name, then report.
      await loser.rename(copyPath, rel);
      rethrow;
    }

    // Canonical name is settled: winner keeps its state, loser's side is
    // whatever the copy produced.
    if (winnerSide == SyncSide.vault) {
      pending.add(_PendingBaseline(rel, vault: winnerState));
    } else {
      pending.add(_PendingBaseline(rel, target: winnerState));
    }

    if (action.propagateConflictCopy) {
      // If this fails the loser's version still exists under copyPath on
      // its own side; the next run sees it as a new file and copies it.
      await _copyAtomic(
        source: loser,
        dest: winner,
        destSide: winnerSide,
        rel: copyPath,
        destExists: false,
        sourceMtime: 0,
        token: token,
      );
      pending.add(_PendingBaseline(copyPath));
    }
  }

  /// [wanted], or a numbered variant of it, that exists on neither side.
  Future<String?> _freeConflictName(
    SyncEndpoint a,
    SyncEndpoint b,
    String wanted,
  ) async {
    for (var n = 1; n <= 9; n++) {
      final candidate = n == 1 ? wanted : _numbered(wanted, n);
      final inA = await a.stat([candidate]);
      final inB = await b.stat([candidate]);
      if (inA.isEmpty && inB.isEmpty) return candidate;
    }
    return null;
  }

  String _numbered(String path, int n) {
    final slash = path.lastIndexOf('/');
    final dir = slash < 0 ? '' : path.substring(0, slash + 1);
    final name = slash < 0 ? path : path.substring(slash + 1);
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return '$dir$name-$n';
    return '$dir${name.substring(0, dot)}-$n${name.substring(dot)}';
  }
}
