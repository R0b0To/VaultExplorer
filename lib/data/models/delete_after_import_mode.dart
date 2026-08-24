import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

enum DeleteAfterImportMode {
  ask,
  keep,
  delete;

  String get label => switch (this) {
        DeleteAfterImportMode.ask => 'Ask every time',
        DeleteAfterImportMode.keep => 'Keep originals (do not delete)',
        DeleteAfterImportMode.delete => 'Delete originals automatically',
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        DeleteAfterImportMode.ask => l10n.deleteAfterImportModeAsk,
        DeleteAfterImportMode.keep => l10n.deleteAfterImportModeKeep,
        DeleteAfterImportMode.delete => l10n.deleteAfterImportModeDelete,
      };

  String getLocalizedSubtitle(AppLocalizations l10n) => switch (this) {
        DeleteAfterImportMode.ask => l10n.deleteAfterImportModeAskSubtitle,
        DeleteAfterImportMode.keep => l10n.deleteAfterImportModeKeepSubtitle,
        DeleteAfterImportMode.delete => l10n.deleteAfterImportModeDeleteSubtitle,
      };

  String toJson() => name;

  static DeleteAfterImportMode fromJson(String? value) => switch (value) {
        'ask' => DeleteAfterImportMode.ask,
        'keep' => DeleteAfterImportMode.keep,
        'delete' => DeleteAfterImportMode.delete,
        _ => DeleteAfterImportMode.ask,
      };
}