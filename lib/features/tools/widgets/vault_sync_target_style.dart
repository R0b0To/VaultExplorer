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
