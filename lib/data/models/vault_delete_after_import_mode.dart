import 'package:vaultexplorer/data/models/delete_after_import_mode.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Per-vault behavior for removing device files after import.
///
/// [inherit] follows the app-wide [DeleteAfterImportMode] default.
enum VaultDeleteAfterImportMode {
  inherit,
  ask,
  keep,
  delete;

  DeleteAfterImportMode resolve(DeleteAfterImportMode globalDefault) =>
      switch (this) {
        VaultDeleteAfterImportMode.inherit => globalDefault,
        VaultDeleteAfterImportMode.ask => DeleteAfterImportMode.ask,
        VaultDeleteAfterImportMode.keep => DeleteAfterImportMode.keep,
        VaultDeleteAfterImportMode.delete => DeleteAfterImportMode.delete,
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
    VaultDeleteAfterImportMode.inherit => l10n.deleteAfterImportInheritGlobal,
    VaultDeleteAfterImportMode.ask => l10n.deleteAfterImportVaultAsk,
    VaultDeleteAfterImportMode.keep => l10n.deleteAfterImportVaultKeep,
    VaultDeleteAfterImportMode.delete => l10n.deleteAfterImportVaultDelete,
  };

  String getLocalizedSubtitle(
    AppLocalizations l10n,
    DeleteAfterImportMode globalDefault,
  ) => switch (this) {
    VaultDeleteAfterImportMode.inherit =>
      l10n.deleteAfterImportInheritGlobalSubtitle(
        globalDefault.getLocalizedLabel(l10n),
      ),
    VaultDeleteAfterImportMode.ask => l10n.deleteAfterImportModeAskSubtitle,
    VaultDeleteAfterImportMode.keep => l10n.deleteAfterImportModeKeepSubtitle,
    VaultDeleteAfterImportMode.delete =>
      l10n.deleteAfterImportModeDeleteSubtitle,
  };

  String toJson() => name;

  static VaultDeleteAfterImportMode fromJson(String? value) => switch (value) {
    'ask' => VaultDeleteAfterImportMode.ask,
    'keep' => VaultDeleteAfterImportMode.keep,
    'delete' => VaultDeleteAfterImportMode.delete,
    _ => VaultDeleteAfterImportMode.inherit,
  };
}
