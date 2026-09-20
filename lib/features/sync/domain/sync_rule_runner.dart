import 'package:vaultexplorer/features/sync/data/ledger/sync_ledger_repository.dart';
import 'package:vaultexplorer/features/sync/domain/endpoints/sync_endpoint.dart';
import 'package:vaultexplorer/features/sync/domain/executor/sync_executor.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_plan.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_state_record.dart';
import 'package:vaultexplorer/features/sync/domain/reconciler/three_way_reconciler.dart';
import 'package:vaultexplorer/features/sync/domain/sync_cancellation.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

/// Runs one [SyncRule] end to end: scan both sides (repairing anything an
/// interrupted run left behind), reconcile against the ledger, execute.
///
/// Knows nothing about vaults, Android or the UI -- it works on
/// [SyncEndpoint]s -- so it can be driven from a unit test with in-memory
/// endpoints.
class SyncRuleRunner {
  final ThreeWayReconciler reconciler;
  final SyncExecutor executor;

  SyncRuleRunner({ThreeWayReconciler? reconciler, SyncExecutor? executor})
    : reconciler = reconciler ?? const ThreeWayReconciler(),
      executor = executor ?? SyncExecutor();

  Future<SyncRunReport> run({
    required SyncRule rule,
    required SyncEndpoint vault,
    required SyncEndpoint target,
    required SyncLedgerRepository ledger,
    required SyncCancellationToken token,
    void Function(SyncProgress progress)? onProgress,
    String? ledgerKey,
    DateTime? now,
  }) async {
    final key = ledgerKey ?? rule.id;
    final ignore = SyncIgnoreMatcher(rule.ignorePatterns);

    try {
      final scans = await Future.wait([
        _scanAndRecover(vault, ignore, token),
        _scanAndRecover(target, ignore, token),
      ]);
      final vaultSnap = scans[0];
      final targetSnap = scans[1];
      if (token.isCancelled) return SyncRunReport(ruleId: rule.id, cancelled: true);

      final plan = await reconciler.reconcile(
        rule: rule,
        vault: vaultSnap,
        target: targetSnap,
        baseline: ledger.baselineFor(key),
        hashOf: (side, rel) =>
            (side == SyncSide.vault ? vault : target).hash(rel, token),
        now: now,
      );
      if (token.isCancelled) return SyncRunReport(ruleId: rule.id, cancelled: true);

      return await executor.execute(
        rule: rule,
        plan: plan,
        vault: vault,
        target: target,
        ledger: ledger,
        token: token,
        onProgress: onProgress,
        incompleteScan: !vaultSnap.isComplete || !targetSnap.isComplete,
        ledgerKey: key,
      );
    } on SyncCancelledException {
      return SyncRunReport(ruleId: rule.id, cancelled: true);
    }
  }

  /// Scans [endpoint]; if a previous run left `.vexp_tmp` / `.vexp_old`
  /// files behind, repairs them and scans again.
  ///
  /// The re-scan matters: restoring a `.vexp_old` brings a file back that
  /// the first scan didn't see, and reconciling against the *first* scan
  /// would read that file as "deleted on this side" and could propagate the
  /// deletion.
  Future<SyncSnapshot> _scanAndRecover(
    SyncEndpoint endpoint,
    SyncIgnoreMatcher ignore,
    SyncCancellationToken token,
  ) async {
    var snapshot = await endpoint.scan(ignore: ignore, token: token);
    if (snapshot.rootReadable && snapshot.leftovers.isNotEmpty) {
      final handled = await executor.cleanupLeftovers(endpoint, snapshot);
      if (handled > 0) {
        snapshot = await endpoint.scan(ignore: ignore, token: token);
      }
    }
    return snapshot;
  }
}
