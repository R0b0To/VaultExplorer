import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Wording for the direction choice in the auto-sync settings.
extension SyncDirectionLabels on SyncDirection {
  String label(AppLocalizations l10n) => switch (this) {
    SyncDirection.twoWay => l10n.autoSyncDirectionTwoWay,
    SyncDirection.vaultToTarget => l10n.autoSyncDirectionVaultToTarget,
    SyncDirection.targetToVault => l10n.autoSyncDirectionTargetToVault,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    SyncDirection.twoWay => l10n.autoSyncDirectionTwoWayHint,
    SyncDirection.vaultToTarget => l10n.autoSyncDirectionVaultToTargetHint,
    SyncDirection.targetToVault => l10n.autoSyncDirectionTargetToVaultHint,
  };
}

/// Wording for the conflict choice in the auto-sync settings.
extension ConflictStrategyLabels on ConflictStrategy {
  String label(AppLocalizations l10n) => switch (this) {
    ConflictStrategy.renameConflict => l10n.autoSyncConflictKeepBoth,
    ConflictStrategy.keepNewer => l10n.autoSyncConflictKeepNewer,
    ConflictStrategy.vaultWins => l10n.autoSyncConflictVaultWins,
    ConflictStrategy.targetWins => l10n.autoSyncConflictTargetWins,
  };

  String hint(AppLocalizations l10n) => switch (this) {
    ConflictStrategy.renameConflict => l10n.autoSyncConflictKeepBothHint,
    ConflictStrategy.keepNewer => l10n.autoSyncConflictKeepNewerHint,
    ConflictStrategy.vaultWins => l10n.autoSyncConflictVaultWinsHint,
    ConflictStrategy.targetWins => l10n.autoSyncConflictTargetWinsHint,
  };
}
