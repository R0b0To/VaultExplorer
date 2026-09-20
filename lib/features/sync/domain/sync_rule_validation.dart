import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';

/// Why a rule can't be saved as it stands.
enum SyncRuleProblem {
  /// No target folder has been chosen.
  noTarget,

  /// The target is inside the same vault and overlaps the synced folder:
  /// syncing would copy a folder into itself.
  overlapsTarget,

  /// Another rule already covers this folder, or a folder inside/above it.
  overlapsOtherRule,
}

/// True when [a] and [b] are the same folder or one is inside the other.
/// An empty path is a root, which contains everything.
bool syncPathsOverlap(String a, String b) {
  final x = normalizeSyncPath(a);
  final y = normalizeSyncPath(b);
  if (x.isEmpty || y.isEmpty || x == y) return true;
  return x.startsWith('$y/') || y.startsWith('$x/');
}

/// Checks [candidate] before it is saved. [vaultUri] is the vault the rule
/// lives in; [others] are the vault's other rules.
SyncRuleProblem? validateSyncRule({
  required SyncRule candidate,
  required String vaultUri,
  required Iterable<SyncRule> others,
}) {
  if (candidate.targetEndpointUri.isEmpty) return SyncRuleProblem.noTarget;

  if (candidate.targetEndpointUri == vaultUri &&
      syncPathsOverlap(candidate.vaultRelativePath, candidate.targetRelativePath)) {
    return SyncRuleProblem.overlapsTarget;
  }

  for (final other in others) {
    if (other.id == candidate.id) continue;
    if (syncPathsOverlap(other.vaultRelativePath, candidate.vaultRelativePath)) {
      return SyncRuleProblem.overlapsOtherRule;
    }
  }
  return null;
}
