import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Presentation helpers for [VaultSyncTargetKind], shared by the Vault Sync
/// screen and its location picker so both describe a target the same way.
extension VaultSyncTargetKindUi on VaultSyncTargetKind {
  IconData get icon => switch (this) {
    VaultSyncTargetKind.vault => Icons.lock_rounded,
    VaultSyncTargetKind.deviceStorage => Icons.smartphone_rounded,
    VaultSyncTargetKind.documentProvider => Icons.folder_shared_rounded,
  };

  /// Short description that also makes clear whether files are encrypted.
  String label(AppLocalizations l10n) => switch (this) {
    VaultSyncTargetKind.vault => l10n.vaultSyncTargetKindVault,
    VaultSyncTargetKind.deviceStorage => l10n.vaultSyncTargetKindDevice,
    VaultSyncTargetKind.documentProvider => l10n.vaultSyncTargetKindProvider,
  };
}

/// Presentation of a diff entry's status, shared by the results list and the
/// folder explorer so a status always looks and reads the same.
extension VaultDiffEntryUi on VaultDiffEntry {
  Color statusColor(ColorScheme cs) => switch (status) {
    VaultDiffStatus.onlyLeft => cs.primary,
    VaultDiffStatus.onlyRight => cs.secondary,
    VaultDiffStatus.leftNewer => cs.tertiary,
    VaultDiffStatus.rightNewer => cs.tertiary,
    VaultDiffStatus.conflicted => cs.error,
    VaultDiffStatus.identical => cs.onSurfaceVariant,
    VaultDiffStatus.bothFolders => cs.onSurfaceVariant,
  };

  /// The badge text for this entry's status, naming the storages involved
  /// (e.g. "Only in Backup", "Newer in My Vault").
  String statusLabel(AppLocalizations l10n, VaultSyncNames names) =>
      switch (status) {
    VaultDiffStatus.onlyLeft => l10n.vaultSyncStatusOnlyIn(names.left),
    VaultDiffStatus.onlyRight => l10n.vaultSyncStatusOnlyIn(names.right),
    VaultDiffStatus.leftNewer => l10n.vaultSyncStatusNewerIn(names.left),
    VaultDiffStatus.rightNewer => l10n.vaultSyncStatusNewerIn(names.right),
    VaultDiffStatus.conflicted =>
      typeMismatch
          ? l10n.vaultSyncStatusTypeMismatch
          : l10n.vaultSyncStatusConflict,
    VaultDiffStatus.identical => l10n.vaultSyncStatusInSync,
    VaultDiffStatus.bothFolders => l10n.vaultSyncStatusFolder,
  };
}

/// The display names for the two sides, with the localized "choose a storage"
/// text standing in for a side that hasn't been picked yet.
VaultSyncNames vaultSyncNamesOf(
  VaultSyncSide? left,
  VaultSyncSide? right,
  AppLocalizations l10n,
) => vaultSyncNamesFor(
  left,
  right,
  leftFallback: l10n.vaultSyncChooseFirstStorage,
  rightFallback: l10n.vaultSyncChooseSecondStorage,
);
