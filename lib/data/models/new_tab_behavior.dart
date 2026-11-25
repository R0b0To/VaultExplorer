import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// What opening a new browser tab does (the tab strip's "+", Ctrl/Cmd+T and a
/// left swipe past the last tab).
///
/// Opening a tab from a menu on purpose ("Open in new tab" on a folder or a
/// vault) is not affected: that always opens what was asked for.
enum NewTabBehavior {
  /// Opens a copy of the tab in front, in the same place (default).
  duplicate,

  /// Asks where the new tab should open: the Vaults page, an unlocked vault
  /// or one of the storages.
  prompt,

  /// Opens the place picked in settings ([AppSettings.newTabStorageId]): the
  /// Vaults page, this device's storage or an added external storage.
  /// When that storage cannot be opened right now, the prompt is shown.
  specificStorage;

  String toJson() => name;

  /// Unknown or missing values fall back to [duplicate].
  static NewTabBehavior fromJson(Object? value) => switch (value) {
    'prompt' => NewTabBehavior.prompt,
    'specificStorage' => NewTabBehavior.specificStorage,
    _ => NewTabBehavior.duplicate,
  };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
    NewTabBehavior.duplicate => l10n.newTabBehaviorDuplicate,
    NewTabBehavior.prompt => l10n.newTabBehaviorPrompt,
    NewTabBehavior.specificStorage => l10n.newTabBehaviorSpecificStorage,
  };

  String getLocalizedDescription(AppLocalizations l10n) => switch (this) {
    NewTabBehavior.duplicate => l10n.newTabBehaviorDuplicateDesc,
    NewTabBehavior.prompt => l10n.newTabBehaviorPromptDesc,
    NewTabBehavior.specificStorage => l10n.newTabBehaviorSpecificStorageDesc,
  };
}

/// The value of [AppSettings.newTabStorageId] for this device's own storage.
const String kNewTabLocalStorageId = 'local';

/// The value of [AppSettings.newTabStorageId] for the Vaults page (the
/// dashboard). Any other value is the id of an added external storage
/// location.
const String kNewTabVaultsPageId = 'vaults';
