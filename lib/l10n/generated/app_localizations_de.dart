// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get cancel => 'Abbrechen';

  @override
  String get close => 'Schließen';

  @override
  String get search => 'Suchen';

  @override
  String get goBack => 'Zurück';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => 'Zu Seite gehen';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return 'Seitenzahl (1 - $pageCount)';
  }

  @override
  String get pdfViewerPageLabel => 'Seite';

  @override
  String get pdfViewerGoButton => 'Los';

  @override
  String get pdfViewerSearchHint => 'Im Dokument suchen';

  @override
  String get pdfViewerNoMatches => 'Keine Treffer';

  @override
  String get pdfViewerPreviousMatch => 'Vorheriger Treffer';

  @override
  String get pdfViewerNextMatch => 'Nächster Treffer';

  @override
  String get pdfViewerCloseSearch => 'Suche schließen';

  @override
  String get pdfViewerPrintTooltip => 'Dokument drucken';

  @override
  String get pdfViewerLoadingDocument => 'Dokument wird geladen…';

  @override
  String get pdfViewerCannotOpenTitle => 'PDF kann nicht geöffnet werden';

  @override
  String get pdfViewerFailedToLoad => 'PDF konnte nicht geladen werden';

  @override
  String get pdfViewerEditTooltip => 'Bearbeiten';

  @override
  String get pdfViewerDoneEditingTooltip => 'Bearbeitung abschließen';

  @override
  String get pdfViewerSaveFailed =>
      'Änderungen an dieser PDF konnten nicht gespeichert werden';

  @override
  String get pdfViewerEditUnavailable =>
      'Bearbeitung ist für dieses Dokument nicht verfügbar';

  @override
  String get paste => 'Einfügen';

  @override
  String get clear => 'Leeren';

  @override
  String get clipboardVerbMove => 'Verschieben';

  @override
  String get clipboardVerbCopy => 'Kopieren';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb ($count) — Tippen für Details, lange drücken zum Einfügen';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb ($count) — Zwischenablage-Details';
  }

  @override
  String clipboardSourceLabel(String source) {
    return 'Quelle: $source';
  }

  @override
  String get clipboardDefaultSourceName => 'Tresor';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente',
      one: '1 Element',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count weitere Elemente',
      one: '+1 weiteres Element',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => 'Erweiterte Parameter';

  @override
  String get pimFieldLabel => 'PIM  (leer lassen für Standard)';

  @override
  String get encryptionAlgorithmLabel => 'Verschlüsselungsalgorithmus';

  @override
  String get hashAlgorithmLabel => 'Hash-Algorithmus';

  @override
  String get clipboardVerbMoving => 'Wird verschoben';

  @override
  String get clipboardVerbCopying => 'Wird kopiert';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente',
      one: '1 Element',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return ' aus \"$source\"';
  }

  @override
  String get clipboardOpenContainerToPaste => 'Container zum Einfügen öffnen';

  @override
  String get keyfilesOptionalLabel => 'Schlüsseldateien (optional)';

  @override
  String get addFile => 'Datei hinzufügen';

  @override
  String get noKeyfilesAttached => 'Keine Schlüsseldateien angehängt';

  @override
  String get completed => 'Abgeschlossen';

  @override
  String get dismiss => 'Verwerfen';

  @override
  String byteProgressText(String transferred, String total, int pct) {
    return '$transferred / $total  ($pct%)';
  }

  @override
  String countProgressText(int done, int total, int pct) {
    return '$done / $total  ($pct%)';
  }

  @override
  String multiOpLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Übertragungen',
      one: '1 Übertragung',
    );
    return '$_temp0';
  }

  @override
  String multiOpSublabel(String summary) {
    return '$summary · zum Anzeigen aller tippen';
  }

  @override
  String get thumbnailSizeResolutionLabel =>
      'Miniaturansicht-Größe (Auflösung)';

  @override
  String get jpegCompressionQualityLabel => 'JPEG-Kompressionsqualität';

  @override
  String get done => 'Fertig';

  @override
  String get confirm => 'Bestätigen';

  @override
  String get couldNotPickKeyfiles =>
      'Schlüsseldateien konnten nicht ausgewählt werden';

  @override
  String get filesystemLabelEncryptedVault => 'diesem verschlüsselten Tresor';

  @override
  String get filesystemLabelThisContainer => 'diesem Container';

  @override
  String get nounFile => 'Datei';

  @override
  String get nounFolder => 'Ordner';

  @override
  String get nounFileCapitalized => 'Datei';

  @override
  String get nounFolderCapitalized => 'Ordner';

  @override
  String get unitBytes => 'Bytes';

  @override
  String get unitCharacters => 'Zeichen';

  @override
  String get validationEmptyName => 'Der Name darf nicht leer sein.';

  @override
  String validationReservedNavName(String name, String noun) {
    return '\"$name\" ist ein reservierter Navigationsname und kann nicht als $noun-Name verwendet werden.';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return '\"$char\" an Position $position ist in einem Namen auf $fsLabel nicht erlaubt.';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return 'Position $position enthält ein nicht druckbares Steuerzeichen (Code $code), das auf $fsLabel nicht erlaubt ist.';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '\"$name\" ist ein reservierter Gerätename auf $fsLabel (entspricht CON, PRN, AUX, NUL, COM0–9 oder LPT0–9) und kann nicht verwendet werden, mit oder ohne Dateiendung.';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return '$noun-Namen dürfen auf $fsLabel nicht mit einem Leerzeichen enden';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return '$noun-Namen dürfen auf $fsLabel nicht mit einem \".\" enden';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return 'Dieser Name ist $length $unit lang; $fsLabel erlaubt maximal $maxLength $unit pro $noun-Name.';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return 'Der vollständige Pfad ist $length Zeichen lang; $fsLabel erlaubt maximal $maxLength.';
  }

  @override
  String conflictSameType(String noun, String name) {
    return 'Ein $noun mit dem Namen \"$name\" existiert hier bereits.';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return 'Ein $existingNoun mit dem Namen \"$name\" existiert hier bereits — er kann sich den Namen nicht mit einem $candidateNoun teilen.';
  }

  @override
  String get readOnlyContainerWarning =>
      'Dieser Container ist schreibgeschützt eingebunden.';

  @override
  String get hiddenVolumeProtectionTriggeredWarning =>
      'Ein Schreibvorgang auf dieses äußere Volume hätte das versteckte Volume beschädigt und wurde daher blockiert. Dieser Container wurde für den Rest dieser Sitzung auf schreibgeschützt umgestellt.';

  @override
  String get protectHiddenVolumeToggleTitle => 'Verstecktes Volume schützen';

  @override
  String get protectHiddenVolumeToggleSubtitle =>
      'Schäden durch Schreibvorgänge auf das äußere Volume verhindern';

  @override
  String get protectHiddenVolumeCredentialsRequired =>
      'Zum Schutz ist ein Passwort oder eine Schlüsseldatei für das versteckte Volume erforderlich';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente löschen?',
      one: '1 Element löschen?',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning =>
      'Diese Elemente werden dauerhaft gelöscht, einschließlich aller Inhalte ausgewählter Ordner.';

  @override
  String get deleteFilesWarning =>
      'Diese Elemente werden dauerhaft aus Ihrem verschlüsselten Volume gelöscht.';

  @override
  String get delete => 'Löschen';

  @override
  String get remove => 'Entfernen';

  @override
  String get create => 'Erstellen';

  @override
  String get rename => 'Umbenennen';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente umbenennen',
      one: '1 Element umbenennen',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => 'Neuer Ordner';

  @override
  String get newTextFileTitle => 'Neue Textdatei';

  @override
  String get folderNameHint => 'Ordnername';

  @override
  String get filenameHint => 'dateiname.txt';

  @override
  String get newNameHint => 'Neuer Name';

  @override
  String get baseNameHint => 'Basisname';

  @override
  String couldntCreateItem(String name) {
    return '\"$name\" konnte nicht erstellt werden — prüfen Sie, ob der Container noch eingebunden ist';
  }

  @override
  String couldntRenameSingle(String name) {
    return '\"$name\" konnte nicht umbenannt werden — möglicherweise existiert bereits ein Element mit diesem Namen';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente konnten nicht umbenannt werden: $reason',
      one: '1 Element konnte nicht umbenannt werden: $reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente konnten nicht umbenannt werden',
      one: '1 Element konnte nicht umbenannt werden',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize =>
      'Geben Sie eine gültige versteckte Größe größer als 0 ein';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter =>
      'Die Größe des versteckten Volumes muss kleiner als die des äußeren Volumes sein';

  @override
  String get hiddenVolumeErrorTooLargeForContainer =>
      'Die Größe des versteckten Volumes ist für diese Containergröße zu groß';

  @override
  String get hiddenVolumeErrorCredentialsRequired =>
      'Beim Erstellen eines versteckten Volumes ist ein verstecktes Passwort oder eine Schlüsseldatei erforderlich';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      'Die Anmeldedaten des versteckten Volumes (Passwort, PIM und Schlüsseldateien) dürfen nicht mit denen des äußeren Volumes identisch sein.';

  @override
  String get vaultItemTypePassword => 'Passwort';

  @override
  String get vaultItemTypePaymentCard => 'Zahlungskarte';

  @override
  String get vaultItemTypeIdentity => 'Identität';

  @override
  String get vaultItemTypeSecureNote => 'Sichere Notiz';

  @override
  String get vaultItemTypeBankAccount => 'Bankkonto';

  @override
  String get vaultItemTypeSoftwareLicense => 'Softwarelizenz';

  @override
  String get fieldUsernameEmail => 'Benutzername / E-Mail';

  @override
  String get fieldPassword => 'Passwort';

  @override
  String get fieldWebsiteUrl => 'Website-URL';

  @override
  String get fieldTotpSecret => 'TOTP-Geheimnis (2FA)';

  @override
  String get fieldNotes => 'Notizen';

  @override
  String get fieldCardholderName => 'Name des Karteninhabers';

  @override
  String get fieldCardNumber => 'Kartennummer';

  @override
  String get fieldExpiryMMYY => 'Ablaufdatum (MM/JJ)';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldIssuingBank => 'Ausstellende Bank';

  @override
  String get fieldFullName => 'Vollständiger Name';

  @override
  String get fieldDateOfBirth => 'Geburtsdatum';

  @override
  String get fieldNationality => 'Staatsangehörigkeit';

  @override
  String get fieldPassportNumber => 'Reisepassnummer';

  @override
  String get fieldPassportExpiry => 'Reisepass-Ablaufdatum';

  @override
  String get fieldNationalIdSsn =>
      'Personalausweis / Sozialversicherungsnummer';

  @override
  String get fieldDriversLicense => 'Führerschein';

  @override
  String get fieldAddress => 'Adresse';

  @override
  String get fieldPhone => 'Telefon';

  @override
  String get fieldEmail => 'E-Mail';

  @override
  String get fieldNote => 'Notiz';

  @override
  String get fieldBankName => 'Bankname';

  @override
  String get fieldAccountHolder => 'Kontoinhaber';

  @override
  String get fieldAccountNumber => 'Kontonummer';

  @override
  String get fieldRoutingSortCode => 'Bankleitzahl';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => 'Kontotyp';

  @override
  String get fieldProductName => 'Produktname';

  @override
  String get fieldLicenseKey => 'Lizenzschlüssel';

  @override
  String get fieldRegisteredTo => 'Registriert auf';

  @override
  String get fieldPurchaseDate => 'Kaufdatum';

  @override
  String get fieldExpiryRenewalDate => 'Ablauf-/Verlängerungsdatum';

  @override
  String get fieldDownloadUrl => 'Download-URL';

  @override
  String get fieldRegistrationEmail => 'Registrierungs-E-Mail';

  @override
  String get titleRequired => 'Titel ist erforderlich';

  @override
  String newTypeTitle(String typeLabel) {
    return 'Neu: $typeLabel';
  }

  @override
  String editItemTitle(String title) {
    return '$title bearbeiten';
  }

  @override
  String get save => 'Speichern';

  @override
  String typeNameHint(String typeLabel) {
    return '$typeLabel-Name';
  }

  @override
  String get titleSectionLabel => 'Titel';

  @override
  String get fieldsSectionLabel => 'Felder';

  @override
  String get encryptedStorageHint =>
      'Alle Felder werden verschlüsselt im Container gespeichert.';

  @override
  String copiedSuffix(String fieldLabel) {
    return '$fieldLabel kopiert';
  }

  @override
  String get copy => 'Kopieren';

  @override
  String get failedToSaveCheckMounted =>
      'Speichern fehlgeschlagen — prüfen Sie, ob der Container noch eingebunden ist';

  @override
  String get discardChangesTitle => 'Änderungen verwerfen?';

  @override
  String get discardChangesMessage =>
      'Ihre nicht gespeicherten Änderungen gehen verloren.';

  @override
  String get discard => 'Verwerfen';

  @override
  String get keepEditing => 'Weiter bearbeiten';

  @override
  String get deleteItemTitle => 'Element löschen?';

  @override
  String deleteItemMessage(String title) {
    return '\"$title\" wird dauerhaft aus dem Tresor gelöscht.';
  }

  @override
  String get removeFromBookmarks => 'Aus Lesezeichen entfernen';

  @override
  String get addToBookmarks => 'Zu Lesezeichen hinzufügen';

  @override
  String get edit => 'Bearbeiten';

  @override
  String labelCopiedToClipboard(String label) {
    return '$label in die Zwischenablage kopiert';
  }

  @override
  String get noFieldsFilledIn =>
      'Keine Felder ausgefüllt.\nTippen Sie auf Bearbeiten, um Details hinzuzufügen.';

  @override
  String get sectionLabelDetails => 'Details';

  @override
  String get sectionLabelInfo => 'Info';

  @override
  String get metaLabelType => 'Typ';

  @override
  String get metaLabelCreated => 'Erstellt';

  @override
  String get metaLabelModified => 'Geändert';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return '$fieldLabel kopieren';
  }

  @override
  String get readOnlyCantAddItemsTooltip =>
      'Schreibgeschützt — Elemente können nicht hinzugefügt werden';

  @override
  String get extractArchive => 'Archiv extrahieren';

  @override
  String get newItemTooltip => 'Neues Element';

  @override
  String get camera => 'Kamera';

  @override
  String get importFiles => 'Dateien importieren';

  @override
  String get importFolder => 'Ordner importieren';

  @override
  String get secureItem => 'Sicheres Element';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archiv-Explorer';

  @override
  String get archiveExplorerPermissionTitle => 'Speicherzugriff erforderlich';

  @override
  String get archiveExplorerPermissionMessage =>
      'Erlauben Sie den Zugriff auf Ihre Dateien, um .zip-Archive aus Downloads zu durchsuchen und zu extrahieren.';

  @override
  String get archiveExplorerGrantAccess => 'Zugriff gewähren';

  @override
  String get archiveExplorerEmptyTitle => 'Keine Archive gefunden';

  @override
  String get archiveExplorerEmptyMessage =>
      'Heruntergeladene Zip-Dateien werden hier angezeigt.';

  @override
  String get archiveExplorerRefreshTooltip => 'Aktualisieren';

  @override
  String archiveExplorerEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente',
      one: '1 Element',
    );
    return '$_temp0';
  }

  @override
  String get archiveExplorerExtractAll => 'Alle extrahieren';

  @override
  String get archiveExplorerExtracting => 'Wird extrahiert…';

  @override
  String archiveExplorerExtractSuccess(int count, String name) {
    return '$count Dateien nach Download/Extracted/$name extrahiert';
  }

  @override
  String get archiveExplorerExtractFailed =>
      'Dieses Archiv konnte nicht extrahiert werden.';

  @override
  String get archiveExplorerOpenFailed =>
      'Dieses Archiv konnte nicht geöffnet werden.';

  @override
  String get archiveExplorerOpenArchive => 'Archiv öffnen…';

  @override
  String get archiveExplorerUnresolvedPath =>
      'Auf diese Datei konnte nicht direkt zugegriffen werden. Wählen Sie stattdessen eine aus den Downloads aus.';

  @override
  String get archiveExplorerExtractTo => 'Extrahieren nach…';

  @override
  String get archiveExplorerPreview => 'Vorschau';

  @override
  String get archiveExplorerChoosingDestination => 'Ziel wird ausgewählt…';

  @override
  String get archiveExplorerNoDestinationChosen => 'Kein Ziel ausgewählt.';

  @override
  String archiveExplorerExtractSuccessTo(int count, String path) {
    return '$count Dateien nach $path extrahiert';
  }

  @override
  String get archiveBrowserEmptyTitle => 'Leerer Ordner';

  @override
  String get archiveBrowserEmptyMessage =>
      'Dieser Ordner enthält keine Dateien.';

  @override
  String get archiveBrowserRoot => 'Archiv';

  @override
  String get archiveBrowserOpenFileFailed =>
      'Diese Datei konnte nicht geöffnet werden.';

  @override
  String get fileAssocInAppTextEditor => 'Interner Text-Editor';

  @override
  String get fileAssocInAppMediaViewer => 'Interner Medienbetrachter';

  @override
  String fileAssocAppPrefix(String name) {
    return 'App: $name';
  }

  @override
  String get fileAssocExternalApp => 'Externe App';

  @override
  String get appSettingsTitle => 'App-Einstellungen';

  @override
  String get sectionSecurityPrivacy => 'Sicherheit & Datenschutz';

  @override
  String get sectionAppearanceInterface => 'Erscheinungsbild & Oberfläche';

  @override
  String get sectionVaultFileHandling => 'Tresor- & Dateiverwaltung';

  @override
  String get masterPasswordTitle => 'Master-Passwort';

  @override
  String get masterPasswordActiveSubtitle => 'Aktiv — zum Entfernen umschalten';

  @override
  String get masterPasswordInactiveSubtitle =>
      'Ein Passwort zum Öffnen der App verlangen';

  @override
  String get newPasswordLabel => 'Neues Passwort';

  @override
  String get masterPasswordFieldLabel => 'Master-Passwort';

  @override
  String get confirmPasswordLabel => 'Passwort bestätigen';

  @override
  String get update => 'Aktualisieren';

  @override
  String get setPassword => 'Passwort festlegen';

  @override
  String get biometricUnlockTitle => 'Biometrische Entsperrung';

  @override
  String get biometricUnlockSubtitle =>
      'Authentifizieren, um den Container sicher einzubinden';

  @override
  String get changeMasterPasswordTitle => 'Master-Passwort ändern';

  @override
  String get changeMasterPasswordSubtitle =>
      'Anmeldedaten des Master-Passworts aktualisieren';

  @override
  String get autoLockContainersTitle => 'Container automatisch sperren';

  @override
  String get autoLockContainersSubtitle =>
      'Geöffnete Tresore nach Inaktivität automatisch sperren';

  @override
  String get autoLockTimeoutLabel => 'Zeitlimit für automatische Sperre';

  @override
  String get immediately => 'Sofort';

  @override
  String nMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Minuten',
      one: '1 Minute',
    );
    return '$_temp0';
  }

  @override
  String get blockScreenshotsTitle => 'Screenshots blockieren';

  @override
  String get blockScreenshotsSubtitle =>
      'Screenshots verhindern und Vorschau in letzten Apps ausblenden';

  @override
  String get keepVaultsRunningInBackgroundTitle =>
      'Container im Hintergrund geöffnet halten';

  @override
  String get keepVaultsRunningInBackgroundSubtitle =>
      'Zeigt eine Benachrichtigung an und hält geöffnete Tresore auch nach Verlassen der App verfügbar. Tresorschlüssel bleiben bis zum Sperren im Speicher.';

  @override
  String get notificationPermissionDeniedMessage =>
      'Benachrichtigungsberechtigung verweigert. Tresore bleiben weiterhin geöffnet, aber die dauerhafte Benachrichtigung wird nicht angezeigt.';

  @override
  String get discreteModeTitle => 'Tarnmodus';

  @override
  String get discreteModeActiveSubtitle =>
      'Aktiv — die App erscheint derzeit als \"Archiv-Explorer\"';

  @override
  String get discreteModeInactiveSubtitle =>
      'Diese App auf dem Startbildschirm als Zip-Archiv-Browser tarnen';

  @override
  String get enableDiscreteModeTitle => 'Tarnmodus aktivieren?';

  @override
  String get disableDiscreteModeTitle => 'Tarnmodus deaktivieren?';

  @override
  String get enableDiscreteModeMessage =>
      'Das App-Symbol und der Name auf Ihrem Startbildschirm ändern sich zu \"Archiv-Explorer\". Die App funktioniert dann als Zip-Archiv-Browser und -Extraktor.\n\nUm auf Ihren Tresor zuzugreifen, öffnen Sie den Archiv-Explorer und halten Sie den Titel 3 Sekunden lang gedrückt.';

  @override
  String get disableDiscreteModeMessage =>
      'Das App-Symbol und der Name auf Ihrem Startbildschirm ändern sich zurück zu \"Vault Explorer\".';

  @override
  String get enable => 'Aktivieren';

  @override
  String get disable => 'Deaktivieren';

  @override
  String get discreteModeEnabledSnack =>
      'Tarnmodus aktiviert. Die App wird geschlossen — öffnen Sie sie über das neue Launcher-Symbol erneut.';

  @override
  String get discreteModeDisabledSnack =>
      'Tarnmodus deaktiviert. Die App wird geschlossen — öffnen Sie sie über das neue Launcher-Symbol erneut.';

  @override
  String get failedToChangeDiscreteMode =>
      'Tarnmodus konnte nicht geändert werden';

  @override
  String get cacheDerivedKeysTitle =>
      'Abgeleitete Schlüssel standardmäßig zwischenspeichern';

  @override
  String get cacheDerivedKeysSubtitle =>
      'Abgeleitetes Schlüsselmaterial im Keystore speichern für schnellere Entsperrung';

  @override
  String get appThemeLabel => 'App-Design';

  @override
  String get systemDefault => 'Systemstandard';

  @override
  String get lightTheme => 'Helles Design';

  @override
  String get darkTheme => 'Dunkles Design';

  @override
  String get useMaterialYouTitle => 'Material You verwenden';

  @override
  String get useMaterialYouSubtitle =>
      'App-Farben an Ihr Hintergrundbild anpassen (Android 12+)';

  @override
  String get pureBlackThemeTitle => 'Reines Schwarz (OLED)';

  @override
  String get pureBlackThemeSubtitle =>
      'Reine schwarze Hintergründe zum Sparen von Akku und Reduzieren von Blendung auf OLED-Bildschirmen (nur im dunklen Design)';

  @override
  String get sortContainersByLabel => 'Container sortieren nach';

  @override
  String get swapCardSwipeActionsTitle =>
      'Wischaktionen der Karten vertauschen';

  @override
  String get swapCardSwipeActionsSubtitle =>
      'Bearbeiten links und Entfernen rechts beim Wischen der Karten anzeigen';

  @override
  String get swipeGestureHintTitle => 'Wischgesten-Hinweis';

  @override
  String get swipeGestureHintSubtitle =>
      'Karten-Vorschau-Animation beim ersten Container anzeigen';

  @override
  String get autoOpenOnUnlockTitle => 'Automatisch öffnen nach Entsperrung';

  @override
  String get autoOpenOnUnlockActiveSubtitle =>
      'Nach dem Entsperren eines Tresors automatisch öffnen';

  @override
  String get autoOpenOnUnlockInactiveSubtitle =>
      'Nur Tresor entsperren und auf dem Dashboard bleiben';

  @override
  String get enableJsHtmlTitle => 'JavaScript im HTML-Betrachter aktivieren';

  @override
  String get jsEnabledSubtitle =>
      'JavaScript für lokale HTML-Dateien aktiviert';

  @override
  String get jsDisabledSubtitle =>
      'JavaScript für lokale HTML-Dateien deaktiviert';

  @override
  String get fastStorageAccessTitle => 'Schneller Speicherzugriff';

  @override
  String get fastStorageAccessGrantedSubtitle =>
      'Zugriff auf alle Dateien gewährt (maximale Geschwindigkeit)';

  @override
  String get fastStorageAccessNotGrantedSubtitle =>
      'Gewähren Sie in den Systemeinstellungen Zugriff auf alle Dateien für optimale Geschwindigkeit';

  @override
  String get enableFastStorageAccessTitle =>
      'Schnellen Speicherzugriff aktivieren';

  @override
  String get enableFastStorageAccessMessage =>
      'Die Gewährung von \"Zugriff auf alle Dateien\" ermöglicht es Vault Explorer, direkte POSIX-Dateioperationen auszuführen und die Leistung von Ordner-Tresoren um bis zu das 1000-fache zu beschleunigen.';

  @override
  String get disableStorageAccessTitle => 'Speicherzugriff deaktivieren';

  @override
  String get disableStorageAccessMessage =>
      'Android erfordert, dass \"Zugriff auf alle Dateien\" in den Systemeinstellungen deaktiviert wird. Möchten Sie die Einstellungen öffnen, um ihn zu deaktivieren?';

  @override
  String get enableStoragePermissionLegacyTitle => 'Speicherzugriff erlauben';

  @override
  String get enableStoragePermissionLegacyMessage =>
      'Vault Explorer benötigt Speicherberechtigung, um direkte Dateioperationen auszuführen und die Leistung von Ordner-Tresoren zu beschleunigen. Android wird Sie nun um Bestätigung bitten.';

  @override
  String get disableStoragePermissionLegacyMessage =>
      'Android erfordert, dass die Speicherberechtigung in den Systemeinstellungen deaktiviert wird. Möchten Sie die Einstellungen öffnen, um sie zu deaktivieren?';

  @override
  String get openSettings => 'Einstellungen öffnen';

  @override
  String get useThisPasswordButton => 'Use This Password';

  @override
  String get quickPasswordGeneratorSheetTitle => 'Password Generator';

  @override
  String get androidFileProviderTitle => 'Android-Dateianbieter';

  @override
  String get androidFileProviderSubtitle =>
      'Neue Container standardmäßig für die Android-Dateiauswahl freigeben';

  @override
  String get thumbnailCachingDefaultLabel =>
      'Miniaturansicht-Zwischenspeicherung (Standard)';

  @override
  String get thumbnailQualityDefaultLabel =>
      'Miniaturansicht-Qualität (Standard)';

  @override
  String get fileAssociationsHeader => 'Dateizuordnungen';

  @override
  String get noFileAssociationsYet =>
      'Noch keine gespeicherten Dateizuordnungen. Sie werden beim Öffnen von Dateien gefragt.';

  @override
  String get defaultActionsHeader =>
      'Standardaktionen beim Öffnen nicht standardmäßiger Dateien:';

  @override
  String get removeAssociationTooltip => 'Zuordnung entfernen';

  @override
  String get sectionBackupRestore => 'Sicherung';

  @override
  String get exportSettingsTitle => 'Einstellungen exportieren';

  @override
  String get exportSettingsSubtitle =>
      'App-Einstellungen und Dateimanager-Layout in einer Datei speichern';

  @override
  String get importSettingsTitle => 'Einstellungen importieren';

  @override
  String get importSettingsSubtitle =>
      'App-Einstellungen und Dateimanager-Layout aus einer Datei wiederherstellen';

  @override
  String get importSettingsConfirmTitle => 'Einstellungen importieren?';

  @override
  String get importSettingsConfirmMessage =>
      'Dadurch werden Ihre aktuellen App-Einstellungen und das Dateimanager-Layout ersetzt. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get exportSettingsSuccessMessage => 'Einstellungen exportiert';

  @override
  String get importSettingsSuccessMessage => 'Einstellungen importiert';

  @override
  String get exportSettingsErrorMessage =>
      'Einstellungen konnten nicht exportiert werden';

  @override
  String get importSettingsInvalidFileMessage =>
      'Diese Datei ist kein gültiger Einstellungsexport';

  @override
  String get sectionDebug => 'Debug';

  @override
  String get debugLoggingTitle => 'Debug-Protokollierung';

  @override
  String get debugLoggingSubtitle =>
      'Detaillierte Diagnoseprotokolle für Containervorgänge aufzeichnen';

  @override
  String get logcatTitle => 'Logcat';

  @override
  String get logcatSubtitle => 'Geräteprotokolle anzeigen und speichern';

  @override
  String logcatSavedMessage(String path) {
    return 'Protokoll gespeichert unter $path';
  }

  @override
  String get logcatSaveErrorMessage =>
      'Protokoll konnte nicht gespeichert werden';

  @override
  String get logcatCopiedMessage => 'Protokoll in die Zwischenablage kopiert';

  @override
  String get logcatUnavailableMessage =>
      'Logcat ist auf diesem Gerät nicht verfügbar';

  @override
  String get logcatEmptyMessage => 'Warten auf Protokollzeilen…';

  @override
  String get logcatClearTooltip => 'Protokoll leeren';

  @override
  String get logcatSaveTooltip => 'Protokoll speichern';

  @override
  String get logcatFilterAppOnly => 'Nur App';

  @override
  String get logcatFilterAll => 'Alle Protokolle';

  @override
  String get logcatSearchHint => 'Protokolle durchsuchen…';

  @override
  String get logcatClearedMessage => 'Protokolle gelöscht';

  @override
  String get logcatCopyTooltip => 'Protokoll kopieren';

  @override
  String get retryButton => 'Wiederholen';

  @override
  String get aboutAppTitle => 'Über VaultExplorer';

  @override
  String versionInfoSubtitle(String version) {
    return 'Version $version · Open-Source-Lizenzen & Details';
  }

  @override
  String get failedToSaveSettings =>
      'Einstellungen konnten nicht gespeichert werden';

  @override
  String get masterPasswordSetSnack => 'Master-Passwort festgelegt';

  @override
  String get passwordCannotBeEmpty => 'Passwort darf nicht leer sein';

  @override
  String get atLeast4CharsRequired => 'Mindestens 4 Zeichen erforderlich';

  @override
  String get passwordsDoNotMatch => 'Passwörter stimmen nicht überein';

  @override
  String get failedToHashPassword =>
      'Passwort-Hash konnte nicht erstellt werden — bitte erneut versuchen';

  @override
  String get languageLabel => 'Sprache';

  @override
  String get biometricNotAvailable =>
      'Biometrie auf diesem Gerät nicht verfügbar';

  @override
  String get unlockVaultExplorerReason => 'VaultExplorer entsperren';

  @override
  String biometricErrorWithCode(String code) {
    return 'Biometrie-Fehler: $code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds Sekunden',
      one: '1 Sekunde',
    );
    return 'Zu viele fehlgeschlagene Versuche. Erneut versuchen in $_temp0.';
  }

  @override
  String get enterMasterPasswordPrompt => 'Geben Sie Ihr Master-Passwort ein';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts fehlgeschlagenen Versuchen',
      one: '1 fehlgeschlagenem Versuch',
    );
    return 'Falsches Passwort. Gesperrt für ${seconds}s nach $_temp0.';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts fehlgeschlagene Versuche',
      one: '1 fehlgeschlagener Versuch',
    );
    return 'Falsches Passwort ($_temp0).';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle =>
      'Geben Sie Ihr Master-Passwort ein, um fortzufahren';

  @override
  String get masterPasswordFieldLabelTitleCase => 'Master-Passwort';

  @override
  String get unlock => 'Entsperren';

  @override
  String get useBiometric => 'Biometrie verwenden';

  @override
  String get connectAtLeast4Dots => 'Mindestens 4 Punkte verbinden';

  @override
  String get patternsDontMatch =>
      'Muster stimmen nicht überein — bitte erneut versuchen';

  @override
  String get drawUnlockPatternTitle => 'Entsperrmuster zeichnen';

  @override
  String get confirmPatternTitle => 'Bestätigen Sie Ihr Muster';

  @override
  String get drawSamePatternAgain => 'Zeichnen Sie das gleiche Muster erneut';

  @override
  String get enterAtLeast4Digits => 'Mindestens 4 Ziffern eingeben';

  @override
  String get pinsDontMatch => 'PINs stimmen nicht überein — erneut versuchen';

  @override
  String get createUnlockPinTitle => 'Entsperr-PIN erstellen';

  @override
  String get confirmPinTitle => 'PIN bestätigen';

  @override
  String get enterSamePinAgain => 'Denselben PIN erneut eingeben';

  @override
  String get enterUnlockPinTitle => 'Entsperr-PIN eingeben';

  @override
  String get wrongPinTryAgain => 'Falscher PIN — erneut versuchen';

  @override
  String get enterYourPinSequence => 'PIN eingeben';

  @override
  String get enterPinToMount => 'PIN eingeben, um einzubinden';

  @override
  String get noPinConfiguredMessage =>
      'Kein PIN konfiguriert. Bitte Passwort manuell eingeben.';

  @override
  String pinLockedForSeconds(int seconds) {
    return 'Zu viele Fehlversuche. Gesperrt für ${seconds}s.';
  }

  @override
  String get initSecureCredsPinMessage =>
      'Sichere Anmeldedaten werden initialisiert. Bitte einmal manuell entsperren, um den PIN-Zugriff zu autorisieren.';

  @override
  String get setPinButton => 'PIN festlegen';

  @override
  String get changePinButton => 'PIN ändern';

  @override
  String get pinSetupRequiredBeforeSaving =>
      'Richten Sie vor dem Speichern einen PIN ein.';

  @override
  String get pinSetupRequiredAboveBeforeSaving =>
      'Richten Sie oben vor dem Speichern einen PIN ein.';

  @override
  String get verifyPinTitle => 'PIN überprüfen';

  @override
  String get incorrectPinError => 'Falscher PIN';

  @override
  String removedFromListSnack(String name) {
    return '\"$name\" aus der Liste entfernt';
  }

  @override
  String get clearRecentHistoryTitle => 'Letzten Verlauf löschen?';

  @override
  String get clearRecentHistoryMessage =>
      'Dadurch werden alle zuletzt verwendeten Dokumente aus Ihrer Liste entfernt. Die tatsächlichen Dateien auf Ihrem Gerät sind davon nicht betroffen.';

  @override
  String get clearAll => 'Alle löschen';

  @override
  String get recentHistoryClearedSnack => 'Letzter Verlauf gelöscht';

  @override
  String get moreOptionsTooltip => 'Weitere Optionen';

  @override
  String get clearHistoryMenuItem => 'Verlauf löschen';

  @override
  String get openPdfFile => 'PDF-Datei öffnen';

  @override
  String get noDocumentsYetTitle => 'Noch keine Dokumente';

  @override
  String get openPdfToStartMessage =>
      'Öffnen Sie eine PDF-Datei von Ihrem Gerät, um mit dem Lesen zu beginnen.';

  @override
  String get removeFromListMenuItem => 'Aus Liste entfernen';

  @override
  String get justNow => 'Gerade eben';

  @override
  String minutesAgo(int count) {
    return 'vor $count Min.';
  }

  @override
  String hoursAgo(int count) {
    return 'vor $count Std.';
  }

  @override
  String daysAgo(int count) {
    return 'vor $count T.';
  }

  @override
  String get usbDriveDisconnectedLocked =>
      'USB-Laufwerk getrennt — Container gesperrt';

  @override
  String get containerAlreadyMounted =>
      'Dieser Container ist bereits eingebunden.';

  @override
  String get noVaultFolderFormatDetected =>
      'In diesem Ordner wurde keine masterkey.cryptomator-, gocryptfs.conf- oder cryfs.config-Datei gefunden.';

  @override
  String get savedContainerSettingsNotFound =>
      'Gespeicherte Einstellungen für diesen Container konnten nicht gefunden werden.';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return 'Der Containerspeicherort konnte nicht aktualisiert werden: $error';
  }

  @override
  String filePickerFailed(String error) {
    return 'Dateiauswahl fehlgeschlagen: $error';
  }

  @override
  String get selectContainerFirst => 'Wählen Sie zuerst einen Container aus';

  @override
  String get passwordOrKeyfilesRequired =>
      'Passwort oder Schlüsseldateien erforderlich';

  @override
  String get slowPerformanceWarningTitle => 'Warnung: Langsame Leistung';

  @override
  String get slowPerformanceWarningMessage =>
      'Der direkte Speicherzugriff ist derzeit deaktiviert.\n\nCryFS speichert Dateien in Tausenden kleiner Blöcke. Das Öffnen nicht leerer CryFS-Tresore über Android SAF wird sehr langsam sein.\n\nMöchten Sie die Einstellungen öffnen, um für hohe Geschwindigkeit \"Zugriff auf alle Dateien\" zu gewähren?';

  @override
  String get unlockAnyway => 'Trotzdem entsperren';

  @override
  String get defaultVaultName => 'Tresor';

  @override
  String get defaultContainerName => 'Container';

  @override
  String get incorrectPasswordOrInvalidVault =>
      'Falsches Passwort oder ungültiger Tresor';

  @override
  String get incorrectPasswordOrInvalidContainer =>
      'Falsches Passwort oder ungültiger Container';

  @override
  String get genericUnknownError => 'Unbekannter Fehler';

  @override
  String get decryptingLabel => 'Wird entschlüsselt…';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return 'Keyslot $attempted von $total wird versucht…';
  }

  @override
  String get luksKeyslotProgressUnknown => 'Keyslot wird versucht…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return 'Anmeldedaten $attempted von $total werden überprüft…';
  }

  @override
  String get bitlockerCredentialProgressUnknown =>
      'Anmeldedaten werden überprüft…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return '$algo wird versucht ($slotName)…';
  }

  @override
  String get unlockContainerLabel => 'Container entsperren';

  @override
  String get mountContainerTitle => 'Container einbinden';

  @override
  String get containerFileSegmentLabel => 'Container-Datei';

  @override
  String get folderVaultSegmentLabel => 'Ordner-Tresor';

  @override
  String formatContainerLabel(String format) {
    return '$format-Container';
  }

  @override
  String formatVaultLabel(String format) {
    return '$format-Tresor';
  }

  @override
  String formatDriveLabel(String format) {
    return '$format-Laufwerk';
  }

  @override
  String get encryptedContainerLabel => 'Verschlüsselter Container';

  @override
  String get tapToSelectVaultFolder => 'Tippen, um Tresorordner auszuwählen…';

  @override
  String get tapToSelectContainerFile =>
      'Tippen, um Container-Datei auszuwählen…';

  @override
  String get containerMissingTitle => 'Container fehlt';

  @override
  String get filePathCouldNotBeResolved =>
      'Dateipfad konnte nicht aufgelöst werden';

  @override
  String get containerMissingExplanation =>
      'Die Container-Datei wurde möglicherweise verschoben oder gelöscht, oder ihr Host-Speicher ist derzeit nicht verbunden.';

  @override
  String get retryButtonLabel => 'Erneut versuchen';

  @override
  String get locateFileButtonLabel => 'Datei suchen';

  @override
  String get authenticateToMountSubtitle =>
      'Authentifizieren, um den Container sicher einzubinden';

  @override
  String get usePasswordButtonLabel => 'Passwort verwenden';

  @override
  String get authenticateButtonLabel => 'Authentifizieren';

  @override
  String get drawUnlockPatternCardTitle => 'Entsperrmuster zeichnen';

  @override
  String get wrongPatternTryAgain => 'Falsches Muster — bitte erneut versuchen';

  @override
  String get connectYourPatternSequence => 'Verbinden Sie Ihre Mustersequenz';

  @override
  String get usePasswordInsteadButtonLabel => 'Stattdessen Passwort verwenden';

  @override
  String get passwordHintFolderVault => 'Tresor-Passwort eingeben';

  @override
  String get passwordHintBitlocker =>
      'Passwort oder Wiederherstellungsschlüssel eingeben';

  @override
  String get passwordHintContainer => 'Container-Passwort eingeben';

  @override
  String get usingSavedPasswordTooltip =>
      'Gespeichertes Passwort wird verwendet';

  @override
  String get luksKeyfileReplacesPasswordNote =>
      'Bei LUKS-Containern ersetzt die Schlüsseldatei das Passwort.';

  @override
  String get readOnlyModeUsbSubtitle =>
      'Einbinden, ohne Änderungen an diesem Laufwerk zuzulassen';

  @override
  String get readOnlyModeContainerSubtitle =>
      'Einbinden, ohne Änderungen an diesem Container zuzulassen';

  @override
  String get rememberContainerLabel => 'Container merken';

  @override
  String get rememberContainerSubtitle =>
      'Container für schnellen Zugriff auf dem Dashboard anheften';

  @override
  String get cancelUnlockButtonLabel => 'Entsperren abbrechen';

  @override
  String get biometricSubjectContainer => 'Container';

  @override
  String get biometricSubjectUsbDrive => 'USB-Laufwerk';

  @override
  String get usbNoSavedCredentialsMessage =>
      'Kein gespeichertes Passwort gefunden. Bitte manuell eingeben.';

  @override
  String get decryptingDriveLabel => 'Laufwerk wird entschlüsselt…';

  @override
  String get usbDeviceAlreadyActiveMounted =>
      'Dieses USB-Gerät ist bereits aktiv und eingebunden.';

  @override
  String reconnectUsbDriveTitle(String label) {
    return '\"$label\" erneut verbinden';
  }

  @override
  String get unlockUsbDriveTitle => 'USB-Laufwerk entsperren';

  @override
  String get noUsbStorageDetectedTitle => 'Kein USB-Speicher erkannt';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return 'Authentifizieren, um $subject zu entsperren';
  }

  @override
  String get noPatternConfiguredMessage =>
      'Kein Muster konfiguriert. Bitte Passwort manuell eingeben.';

  @override
  String patternLockedForSeconds(int seconds) {
    return 'Zu viele fehlgeschlagene Versuche. Gesperrt für ${seconds}s.';
  }

  @override
  String get initSecureCredsBiometricMessage =>
      'Sichere Anmeldedaten werden initialisiert. Bitte einmal manuell entsperren, um den biometrischen Zugriff zu autorisieren.';

  @override
  String get initSecureCredsPatternMessage =>
      'Sichere Anmeldedaten werden initialisiert. Bitte einmal manuell entsperren, um den Musterzugriff zu autorisieren.';

  @override
  String get mountExistingContainerTitle => 'Vorhandenen Container einbinden';

  @override
  String get mountExistingContainerSubtitle =>
      'Einen bereits vorhandenen Datei-Container entsperren';

  @override
  String get mountSplitContainerTitle => 'Geteilten Container einbinden';

  @override
  String get mountSplitContainerSubtitle =>
      'Einen geteilten Container direkt entsperren, ohne ihn vorher zusammenzuführen';

  @override
  String get mountUsbDriveTitle => 'USB-Laufwerk einbinden';

  @override
  String get mountUsbDriveSubtitle =>
      'Einen Container auf einem OTG-USB-Stick entsperren';

  @override
  String get formatUsbDriveTitle => 'USB-Laufwerk formatieren';

  @override
  String get formatUsbDriveSubtitle =>
      'Ein Laufwerk löschen und einen neuen verschlüsselten Container darauf erstellen';

  @override
  String get createNewContainerTitle => 'Neuen Container erstellen';

  @override
  String get createNewContainerSubtitle =>
      'Einen brandneuen verschlüsselten Tresor formatieren';

  @override
  String get lockBeforeRemovingWarning =>
      'Sperren Sie den Container, bevor Sie ihn entfernen.';

  @override
  String get settingsTooltip => 'Einstellungen';

  @override
  String get addVaultFabLabel => 'Tresor hinzufügen';

  @override
  String removedLabelUndo(String label) {
    return '\"$label\" entfernt';
  }

  @override
  String get undo => 'Rückgängig';

  @override
  String get pdfViewerNoSourceProvided => 'Keine PDF-Quelle angegeben.';

  @override
  String get pdfViewerFileEmpty => 'PDF-Datei ist leer oder nicht lesbar.';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return 'Größe der PDF-Datei konnte nicht ermittelt werden: $error';
  }

  @override
  String get pdfViewerErrorLoadingTitle => 'Fehler beim Laden der PDF';

  @override
  String get pdfViewerNoDocumentLoaded => 'Kein PDF-Dokument geladen.';

  @override
  String get add => 'Hinzufügen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String couldNotExpose(String name) {
    return '\"$name\" konnte nicht freigegeben werden.';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return '\"$name\" ist jetzt für andere Apps verfügbar.';
  }

  @override
  String couldNotUnmount(String name) {
    return '\"$name\" konnte nicht ausgehängt werden.';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente angeheftet',
      one: '1 Element angeheftet',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente gelöst',
      one: '1 Element gelöst',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning =>
      'Schreibgeschützt eingebunden — Miniaturansichten werden angezeigt, aber in dieser Sitzung nicht im Container gespeichert.';

  @override
  String failedLoadingFolder(String type) {
    return 'Ordner konnte nicht geladen werden: $type';
  }

  @override
  String failedToReadArchive(String type) {
    return 'Archiv konnte nicht gelesen werden: $type';
  }

  @override
  String archiveFormatNotSupported(String ext) {
    return 'Archivformat .$ext wird noch nicht unterstützt';
  }

  @override
  String get failedToReadFileFromArchive =>
      'Datei konnte nicht aus dem Archiv gelesen werden';

  @override
  String failedToExtractFile(String type) {
    return 'Datei konnte nicht extrahiert werden: $type';
  }

  @override
  String get failedToReadSecureItem =>
      'Sicheres Element konnte nicht gelesen werden';

  @override
  String get openFileDialogTitle => 'Datei öffnen';

  @override
  String chooseHowToOpen(String name) {
    return 'Wählen Sie, wie \"$name\" geöffnet werden soll:';
  }

  @override
  String get playVideoAudioViewImageInApp =>
      'Video/Audio abspielen oder Bild in der App anzeigen';

  @override
  String get viewEditTextMarkdownCode =>
      'Text, Markdown, Code anzeigen/bearbeiten';

  @override
  String get sendFileToThirdPartyApp => 'Datei an Drittanbieter-App senden';

  @override
  String get openAsEllipsis => 'Öffnen als…';

  @override
  String get chooseFileTypeToOpenAs =>
      'Wählen Sie den Dateityp, als der geöffnet werden soll';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return 'Auswahl für .$ext-Dateien immer merken';
  }

  @override
  String get alwaysRememberChoiceNoExt =>
      'Auswahl für Dateien ohne Erweiterung immer merken';

  @override
  String get openAsDialogTitle => 'Öffnen als';

  @override
  String get mimeTypeText => 'Text';

  @override
  String get mimeTypeImage => 'Bild';

  @override
  String get mimeTypeVideo => 'Video';

  @override
  String get mimeTypeAudio => 'Audio';

  @override
  String get mimeTypeArchive => 'Archiv';

  @override
  String get mimeTypeOther => 'Sonstiges';

  @override
  String get scanningSubfoldersForMedia =>
      'Unterordner werden nach Medien durchsucht…';

  @override
  String get noMediaFilesFoundRecursive =>
      'Keine Mediendateien in diesem Ordner oder seinen Unterordnern gefunden';

  @override
  String failedToScanSubfolders(String error) {
    return 'Unterordner konnten nicht durchsucht werden: $error';
  }

  @override
  String scanningSubfoldersForMediaProgress(int count) {
    return 'Unterordner werden nach Medien durchsucht… $count geprüft';
  }

  @override
  String get mediaScanCancelled => 'Medienscan abgebrochen';

  @override
  String get mediaScanLimitReached =>
      'Suche nach vielen geprüften Ordnern gestoppt. Keine Medien gefunden.';

  @override
  String get noAppFoundForFileType => 'Keine App für diesen Dateityp gefunden';

  @override
  String couldNotOpenFile(String name) {
    return '\"$name\" konnte nicht geöffnet werden';
  }

  @override
  String get readOnlyCantMove =>
      'Dieser Container ist schreibgeschützt eingebunden — Elemente können von hier nicht verschoben werden.';

  @override
  String get readOnlyCantPaste =>
      'Dieser Container ist schreibgeschützt eingebunden — Elemente können hier nicht eingefügt werden.';

  @override
  String get clipboardSourceInvalid => 'Quelle der Zwischenablage ist ungültig';

  @override
  String get crossContainerPasteNotConfigured =>
      'Containerübergreifendes Einfügen ist nicht konfiguriert.';

  @override
  String get crossContainerPasteRequiresBothMounted =>
      'Containerübergreifendes Einfügen erfordert, dass beide Container eingebunden bleiben.';

  @override
  String get readOnlyCantDelete =>
      'Dieser Container ist schreibgeschützt eingebunden — Elemente können nicht gelöscht werden.';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente gelöscht',
      one: '1 Element gelöscht',
    );
    return '$_temp0';
  }

  @override
  String deletedWithFailures(int deleted, int failed) {
    return '$deleted gelöscht · $failed fehlgeschlagen';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien exportiert',
      one: '1 Datei exportiert',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed =>
      'Export abgebrochen oder fehlgeschlagen';

  @override
  String exportError(String type) {
    return 'Exportfehler: $type';
  }

  @override
  String get deleteOriginalTitle => 'Original löschen?';

  @override
  String get deleteOriginalFolderMessage =>
      'Original-Ordner von Ihrem Gerät löschen, nachdem er importiert wurde?';

  @override
  String get deleteOriginalFilesMessage =>
      'Original-Datei(en) von Ihrem Gerät löschen, nachdem sie importiert wurden?';

  @override
  String get keepOriginal => 'Original behalten';

  @override
  String get deleteOriginalButton => 'Original löschen';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Originalelemente gelöscht',
      one: '1 Originalelement gelöscht',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals =>
      'Original(e) konnte(n) nicht gelöscht werden';

  @override
  String get videoCapturedEncrypted => 'Video aufgenommen und verschlüsselt';

  @override
  String get photoCapturedEncrypted => 'Foto aufgenommen und verschlüsselt';

  @override
  String cameraCaptureFailed(String type) {
    return 'Kameraaufnahme fehlgeschlagen: $type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return 'Alle Dateien in den Ordner \"$folder\" extrahieren?';
  }

  @override
  String get extract => 'Extrahieren';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien extrahiert',
      one: '1 Datei extrahiert',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return 'Extraktion fehlgeschlagen: $type';
  }

  @override
  String get archiveSelectionAction => 'Archivieren';

  @override
  String get createArchiveTitle => 'Archiv erstellen';

  @override
  String get archiveNameHint => 'archiv.zip';

  @override
  String archivedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien archiviert',
      one: '1 Datei archiviert',
    );
    return '$_temp0';
  }

  @override
  String failedToArchiveGeneric(String type) {
    return 'Archivierung fehlgeschlagen: $type';
  }

  @override
  String get closeSearchTooltip => 'Suche schließen';

  @override
  String get searchInThisFolderTooltip => 'In diesem Ordner suchen';

  @override
  String get playMediaHereTooltip => 'Medien hier abspielen';

  @override
  String get rootFolderLabel => 'Stammverzeichnis';

  @override
  String folderPickerFailed(String error) {
    return 'Ordnerauswahl fehlgeschlagen: $error';
  }

  @override
  String get addAVaultTitle => 'Tresor hinzufügen';

  @override
  String get selectEmptyDestinationFolderFirst =>
      'Wählen Sie zuerst einen leeren Zielordner aus';

  @override
  String get passwordRequired => 'Ein Passwort ist erforderlich';

  @override
  String get vaultCreatedSuccessfully => 'Tresor erfolgreich erstellt.';

  @override
  String get vaultCreationFailedEmptyFolder =>
      'Tresor-Erstellung fehlgeschlagen — stellen Sie sicher, dass der ausgewählte Ordner leer ist.';

  @override
  String get unknownErrorOccurred => 'Unbekannter Fehler aufgetreten';

  @override
  String get containerNameRequired => 'Containername ist erforderlich';

  @override
  String get enterValidSizeGreaterThanZero =>
      'Geben Sie eine gültige Größe größer als 0 ein';

  @override
  String get passwordOrKeyfileRequired =>
      'Ein Passwort oder mindestens eine Schlüsseldatei ist erforderlich';

  @override
  String get standardVolumePasswordsDoNotMatch =>
      'Passwörter des Standard-Volumes stimmen nicht überein';

  @override
  String get hiddenVolumePasswordsDoNotMatch =>
      'Passwörter des versteckten Volumes stimmen nicht überein';

  @override
  String get containerFileCreatedSuccessfully =>
      'Container-Datei erfolgreich erstellt.';

  @override
  String get containerCreationCancelledOrFailed =>
      'Container-Erstellung abgebrochen oder fehlgeschlagen.';

  @override
  String insufficientSpaceForContainer(String needed, String available) {
    return 'Nicht genügend freier Speicherplatz am Zielort. Benötigt: $needed, verfügbar: nur $available.';
  }

  @override
  String get vaultKindContainerFile => 'Container-Datei';

  @override
  String get vaultKindFolderVault => 'Ordner-Tresor';

  @override
  String get formatFileSystemLabel => 'Dateisystem formatieren';

  @override
  String get standardVolumeHeader => 'Standard-Volume';

  @override
  String get containerFormatLabel => 'Container-Format';

  @override
  String get fileNameLabel => 'Dateiname';

  @override
  String get containerSizeLabel => 'Containergröße';

  @override
  String get unitLabel => 'Einheit';

  @override
  String get passwordFieldLabel => 'Passwort';

  @override
  String get confirmPasswordFieldLabelTitleCase => 'Passwort bestätigen';

  @override
  String get hiddenVolumeHeader => 'Verstecktes Volume';

  @override
  String get createHiddenVolumeToggleTitle => 'Verstecktes Volume erstellen';

  @override
  String get createInvisibleSecondaryVolume =>
      'Ein unsichtbares sekundäres Volume erstellen';

  @override
  String get setOuterPasswordFirstToEnable =>
      'Zum Aktivieren zuerst äußeres Passwort oder Schlüsseldateien festlegen';

  @override
  String get hiddenPasswordLabel => 'Verstecktes Passwort';

  @override
  String get confirmHiddenPasswordLabel => 'Verstecktes Passwort bestätigen';

  @override
  String get hiddenSizeLabel => 'Versteckte Größe';

  @override
  String get unitMbMegabytes => 'MB (Megabyte)';

  @override
  String get unitGbGigabytes => 'GB (Gigabyte)';

  @override
  String get hiddenFileSystemLabel => 'Verstecktes Dateisystem';

  @override
  String get vaultFormatLabel => 'Tresorformat';

  @override
  String get gocryptfsCipherLabel => 'Inhaltsverschlüsselung';

  @override
  String get cryfsCipherLabel => 'Inhaltsverschlüsselung';

  @override
  String get cryfsBlockSizeLabel => 'Blockgröße';

  @override
  String get destinationFolderLabel => 'Zielordner';

  @override
  String get selectEmptyFolderLabel => 'Einen leeren Ordner auswählen';

  @override
  String get tapToChooseVaultLocation =>
      'Tippen, um Speicherort des Tresors auszuwählen…';

  @override
  String get folderVaultLimitationsNote =>
      'Ordner-Tresore unterstützen keine Schlüsseldateien, PIM, versteckte Volumes oder VeraCrypt-/LUKS-Verschlüsselungswahl.';

  @override
  String get createVaultButton => 'Tresor erstellen';

  @override
  String get createContainerButton => 'Container erstellen';

  @override
  String get vaultCreationInProgressWait =>
      'Tresor-Erstellung läuft. Bitte warten.';

  @override
  String get containerCreationInProgressWait =>
      'Container-Erstellung läuft. Bitte warten.';

  @override
  String get createEncryptedVaultTitle => 'Verschlüsselten Tresor erstellen';

  @override
  String get createEncryptedContainerTitle =>
      'Verschlüsselten Container erstellen';

  @override
  String get unitMbShort => 'MB';

  @override
  String get unitGbShort => 'GB';

  @override
  String failedToListUsbDevices(String error) {
    return 'USB-Geräte konnten nicht aufgelistet werden: $error';
  }

  @override
  String get usbPermissionDenied => 'USB-Berechtigung verweigert';

  @override
  String get couldNotReadDriveCapacity =>
      'Laufwerkskapazität konnte nicht gelesen werden — Größe manuell eingeben.';

  @override
  String get selectUsbDriveFirst => 'Wählen Sie zuerst ein USB-Laufwerk aus';

  @override
  String eraseDeviceTitle(String name) {
    return '\"$name\" löschen?';
  }

  @override
  String get eraseDeviceMessage =>
      'Dadurch wird alles auf diesem USB-Laufwerk dauerhaft gelöscht und durch einen neuen verschlüsselten Container ersetzt. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get eraseAndCreateButton => 'Löschen & erstellen';

  @override
  String get usbPermissionRequiredToContinue =>
      'USB-Berechtigung ist zum Fortfahren erforderlich';

  @override
  String get usbContainerCreatedSnack =>
      'USB-Container erstellt. Verwenden Sie \"USB-Laufwerk einbinden\", um ihn zu entsperren.';

  @override
  String get usbContainerCreationFailed =>
      'USB-Container-Erstellung fehlgeschlagen.';

  @override
  String get usbStandardVolumeSectionHeader => 'USB-Laufwerk & Standard-Volume';

  @override
  String get formattingErasesEverythingWarning =>
      'Die Formatierung löscht alles auf dem ausgewählten Laufwerk.';

  @override
  String get selectUsbDriveLabel => 'USB-Laufwerk auswählen';

  @override
  String get noUsbStorageDetected => 'Kein USB-Speicher erkannt';

  @override
  String get connectOtgDriveToFormat =>
      'Ein OTG-Laufwerk zum Formatieren verbinden';

  @override
  String get refreshListButton => 'Liste aktualisieren';

  @override
  String get readyToFormat => 'Bereit zum Formatieren';

  @override
  String get permissionRequired => 'Berechtigung erforderlich';

  @override
  String get readingDriveCapacity => 'Laufwerkskapazität wird gelesen…';

  @override
  String get mustNotExceedDriveCapacity =>
      'Darf die tatsächliche Kapazität des Laufwerks nicht überschreiten.';

  @override
  String get quickFormatTitle => 'Schnellformatierung';

  @override
  String get quickFormatDescription =>
      'Überspringt das Nullen des Laufwerks. Schneller, löscht alte Daten aber nicht sicher.';

  @override
  String get eraseAndCreateContainerButton => 'Löschen & Container erstellen';

  @override
  String get usbContainerCreationInProgressWait =>
      'Container-Erstellung läuft. Bitte warten.';

  @override
  String get formatUsbDriveScreenTitle => 'USB-Laufwerk formatieren';

  @override
  String get playlistTransitionAnimationLabel => 'Playlist-Übergangsanimation';

  @override
  String get playlistTransitionSlideLabel => 'Schieben (Standard)';

  @override
  String get playlistTransitionFadeLabel => 'Überblenden';

  @override
  String get playlistTransitionZoomLabel => 'Zoom & Skalierung';

  @override
  String get playlistTransitionDepthLabel => 'Tiefenstapel';

  @override
  String get playlistTransitionCubeLabel => '3D-Würfel';

  @override
  String get playlistTransitionFlipLabel => '3D-Flip';

  @override
  String get unlockVaultTitle => 'Tresor entsperren';

  @override
  String get openContainerTitle => 'Container öffnen';

  @override
  String get selectContainerFileOrFolder => 'Datei oder Ordner auswählen';

  @override
  String get readOnlyModeLabel => 'Schreibgeschützter Modus';

  @override
  String get readOnlyModeSubtitle =>
      'Verhindert Schreib- oder Änderungsvorgänge im Tresor';

  @override
  String get selectUsbDeviceLabel => 'USB-Gerät auswählen';

  @override
  String get noUsbDevicesFound =>
      'Keine kompatiblen USB-Speichergeräte gefunden';

  @override
  String get containerConfigTitle => 'Tresor-Konfiguration';

  @override
  String get changePasswordTitle => 'Passwort ändern';

  @override
  String get confirmNewPasswordLabel => 'Neues Passwort bestätigen';

  @override
  String get cameraCaptureTitle => 'Tresor-Kamera';

  @override
  String get takingPhoto => 'Foto wird aufgenommen…';

  @override
  String get savingToVault => 'Wird im Tresor gespeichert…';

  @override
  String get noVaultSelected => 'Kein Tresor ausgewählt';

  @override
  String get mediaDiagnosticsTitle => 'Mediendiagnose';

  @override
  String get advancedViewerSettingsTitle => 'Betrachter-Einstellungen';

  @override
  String get textEditorSaveConfirmTitle => 'Nicht gespeicherte Änderungen';

  @override
  String get textEditorSaveConfirmMessage =>
      'Möchten Sie Ihre Änderungen vor dem Schließen speichern?';

  @override
  String get saveAndClose => 'Speichern & schließen';

  @override
  String get discardChanges => 'Änderungen verwerfen';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente ausgewählt',
      one: '1 Element ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'Alle auswählen';

  @override
  String get deselectAll => 'Auswahl aufheben';

  @override
  String get sortOptionsTitle => 'Dateien sortieren';

  @override
  String get layoutModeList => 'Listenansicht';

  @override
  String get layoutModeGrid => 'Rasteransicht';

  @override
  String get layoutModeMasonry => 'Mauerwerk-Ansicht';

  @override
  String get fileOperationsTitle => 'Dateioperationen';

  @override
  String get conflictResolutionTitle => 'Dateikonflikt';

  @override
  String get replaceExistingFile => 'Vorhandene Datei ersetzen';

  @override
  String get keepBothFiles => 'Beide behalten (neue Datei umbenennen)';

  @override
  String get skipFile => 'Diese Datei überspringen';

  @override
  String get noVaultsFoundTitle => 'Keine Tresore gefunden';

  @override
  String get noVaultsFoundSubtitle =>
      'Erstellen Sie einen neuen verschlüsselten Container oder fügen Sie einen vorhandenen Tresor hinzu, um zu beginnen.';

  @override
  String get addExistingVaultButton => 'Vorhandenen Tresor hinzufügen';

  @override
  String get sortContainersModeManual => 'Manuell (zum Umordnen ziehen)';

  @override
  String get sortContainersModeUnlockStatus =>
      'Entsperrstatus (zuerst entsperrt)';

  @override
  String get sortContainersModeNameAZ => 'Name (A–Z)';

  @override
  String get sortContainersModeNameZA => 'Name (Z–A)';

  @override
  String get sortContainersModeNewest => 'Neueste zuerst';

  @override
  String get sortContainersModeOldest => 'Älteste zuerst';

  @override
  String get thumbnailCacheAppCacheLabel => 'App-Cache';

  @override
  String get thumbnailCacheAppCacheDesc =>
      'Verschlüsselt im App-Cache gespeichert. Schnell; wird bei Speicherplatzknappheit automatisch geleert.';

  @override
  String get thumbnailCacheInContainerLabel => 'Im Container';

  @override
  String get thumbnailCacheInContainerDesc =>
      'Im verschlüsselten Container gespeichert. Durch den Container selbst geschützt, aber Schreibvorgänge sind langsamer.';

  @override
  String get thumbnailCacheHiddenFolderLabel => 'Versteckter Ordner';

  @override
  String get thumbnailCacheHiddenFolderDesc =>
      'Wird in einem versteckten .thumbcache-Ordner im Stammverzeichnis gespeichert. Im Gegensatz zum App-Cache wird er nicht automatisch geleert.';

  @override
  String get thumbnailCacheDisabledLabel => 'Deaktiviert';

  @override
  String get thumbnailCacheDisabledDesc =>
      'Kein Festplatten-Cache. Miniaturansichten werden bei jedem Laden neu erstellt.';

  @override
  String get unlockContainerTitle => 'Container entsperren';

  @override
  String get containerFileSegment => 'Container-Datei';

  @override
  String get folderVaultSegment => 'Ordner-Tresor';

  @override
  String get enableButtonLabel => 'Aktivieren';

  @override
  String get retryButtonLabelShort => 'Erneut';

  @override
  String get locateFileButton => 'Datei suchen';

  @override
  String get authenticateButton => 'Authentifizieren';

  @override
  String get cancelUnlockButton => 'Entsperren abbrechen';

  @override
  String tryingKeyslotProgress(int attempted, int total) {
    return 'Keyslot $attempted von $total wird versucht…';
  }

  @override
  String get tryingKeyslotSingle => 'Keyslot wird versucht…';

  @override
  String verifyingCredentialProgress(int attempted, int total) {
    return 'Anmeldedaten $attempted von $total werden überprüft…';
  }

  @override
  String get verifyingCredentialSingle => 'Anmeldedaten werden überprüft…';

  @override
  String tryingAlgoSlot(String algo, String slotName) {
    return '$algo wird versucht ($slotName)…';
  }

  @override
  String get hiddenVolumeSlotName => 'Verstecktes Volume';

  @override
  String get standardVolumeSlotName => 'Standard-Volume';

  @override
  String get containerMissingSubtitle =>
      'Dateipfad konnte nicht aufgelöst werden';

  @override
  String get containerMissingBody =>
      'Die Container-Datei wurde möglicherweise verschoben oder gelöscht, oder ihr Host-Speicher ist derzeit nicht verbunden.';

  @override
  String get connectPatternSequence => 'Verbinden Sie Ihre Mustersequenz';

  @override
  String get passwordLabel => 'Passwort';

  @override
  String get enterVaultPasswordHint => 'Tresor-Passwort eingeben';

  @override
  String get enterBitlockerPasswordHint =>
      'Passwort oder Wiederherstellungsschlüssel eingeben';

  @override
  String get enterContainerPasswordHint => 'Container-Passwort eingeben';

  @override
  String get readOnlyModeUsbSubtitleDrive =>
      'Einbinden, ohne Änderungen an diesem Laufwerk zuzulassen';

  @override
  String get rememberDriveLabel => 'Laufwerk merken';

  @override
  String get rememberDriveSubtitle =>
      'Laufwerk für schnellen Zugriff auf dem Dashboard anheften';

  @override
  String get unlockVaultButtonLabel => 'Tresor entsperren';

  @override
  String get cryfsStorageAccessWarning =>
      'CryFS-Tresore verwenden Tausende kleiner Blockdateien. Ohne direkten Speicherzugriff wird die Leistung deutlich langsamer sein.';

  @override
  String get folderVaultStorageAccessWarning =>
      'Der direkte Speicherzugriff ist deaktiviert. Das Öffnen und Lesen von Dateien in Ordner-Tresoren kann langsamer sein.';

  @override
  String get requestingPermission => 'Berechtigung wird angefordert…';

  @override
  String get unlockAndMountButton => 'Entsperren & einbinden';

  @override
  String get unlockDriveButton => 'Laufwerk entsperren';

  @override
  String couldntFindDevice(String deviceName) {
    return '\"$deviceName\" konnte nicht gefunden werden';
  }

  @override
  String get plugDriveBackInRetry =>
      'Schließen Sie das Laufwerk wieder an und tippen Sie auf Erneut versuchen, oder wählen Sie es unten aus, falls es unter einem anderen Namen erscheint.';

  @override
  String get retryConnectionButton => 'Verbindung erneut versuchen';

  @override
  String get refreshDevicesButton => 'Geräte aktualisieren';

  @override
  String get connectOtgDriveToMount =>
      'Ein OTG-USB-Stick zum Einbinden verbinden';

  @override
  String get alreadyActive => 'Bereits aktiv';

  @override
  String get active => 'Aktiv';

  @override
  String get readyToUnlock => 'Bereit zum Entsperren';

  @override
  String get enterUsbPartitionPassword => 'USB-Partitionspasswort eingeben';

  @override
  String get biometricAuthenticationTitle => 'Biometrische Authentifizierung';

  @override
  String get biometricAuthUsbSubtitle =>
      'Authentifizieren, um dieses USB-Gerät zu entsperren und einzubinden';

  @override
  String get connectPatternSequenceToMount =>
      'Verbinden Sie Ihre Mustersequenz zum Einbinden';

  @override
  String get selectAllAction => 'Alle auswählen';

  @override
  String get clearSelectionAction => 'Auswahl löschen';

  @override
  String get clearSelectionTooltip => 'Auswahl löschen';

  @override
  String get selectionOptionsTooltip => 'Auswahloptionen';

  @override
  String get readOnlyContainerTooltip => 'Schreibgeschützter Container';

  @override
  String get copyAction => 'Kopieren';

  @override
  String get moveAction => 'Verschieben';

  @override
  String get renameAction => 'Umbenennen';

  @override
  String get exportToDeviceAction => 'Auf Gerät exportieren';

  @override
  String get openWithAppAction => 'Mit App öffnen';

  @override
  String get pinAction => 'Anheften';

  @override
  String get pinSelectedAction => 'Ausgewählte anheften';

  @override
  String get unpinAction => 'Lösen';

  @override
  String get unpinSelectedAction => 'Ausgewählte lösen';

  @override
  String get documentProviderSettingsMenu => 'Dokumentanbieter-Einstellungen';

  @override
  String get exposeAsDocumentProviderMenu => 'Als Dokumentanbieter freigeben';

  @override
  String get moreOptionsTooltipShort => 'Weitere Optionen';

  @override
  String get copyTooltip => 'Kopieren';

  @override
  String get searchInThisFolderHint => 'In diesem Ordner suchen…';

  @override
  String get clearTooltip => 'Löschen';

  @override
  String get backToDashboardTooltip => 'Zurück zum Dashboard';

  @override
  String get cancelPasteButton => 'Einfügen abbrechen';

  @override
  String get cancelImportButton => 'Importieren abbrechen';

  @override
  String get continueButton => 'Weiter';

  @override
  String get skipButton => 'Überspringen';

  @override
  String get keepBothButton => 'Beide behalten';

  @override
  String get clearAllButton => 'Alle löschen';

  @override
  String get autoMountWhenUnlocksTitle =>
      'Automatisch einbinden, wenn Container entsperrt wird';

  @override
  String get autoMountWhenUnlocksSubtitle =>
      'Diesen Ordner beim nächsten Mal automatisch wieder freigeben';

  @override
  String get unmountButton => 'Aushängen';

  @override
  String get filtersMenuItem => 'Filter';

  @override
  String get settingsMenuItem => 'Einstellungen';

  @override
  String get sortOptionsTooltip => 'Sortieroptionen';

  @override
  String get layoutOptionsTooltip => 'Layoutoptionen';

  @override
  String get lockContainerTooltip => 'Container sperren';

  @override
  String get renameTooltip => 'Umbenennen';

  @override
  String get cancelUpdatingPasswordTooltip =>
      'Passwortaktualisierung abbrechen';

  @override
  String get unlockSettingsButton => 'Entsperreinstellungen';

  @override
  String get updateSavedCredentialsButton =>
      'Gespeicherte Anmeldedaten aktualisieren';

  @override
  String get verifyCredentialsTitle => 'Anmeldedaten überprüfen';

  @override
  String get verifyButton => 'Überprüfen';

  @override
  String get displayNameTitle => 'Anzeigename';

  @override
  String get containerNameHint => 'Containername';

  @override
  String get deleteFileDialogTitle => 'Datei löschen?';

  @override
  String get deleteFilePermanentWarning =>
      'Diese Aktion ist endgültig und kann nicht rückgängig gemacht werden.';

  @override
  String get unsavedChangesTitle => 'Nicht gespeicherte Änderungen';

  @override
  String get unsavedChangesMessage =>
      'Sie haben nicht gespeicherte Änderungen. Möchten Sie vor dem Schließen speichern?';

  @override
  String get discardButton => 'Verwerfen';

  @override
  String get decryptingFileContent => 'Dateiinhalt wird entschlüsselt...';

  @override
  String get cannotOpenFile => 'Datei kann nicht geöffnet werden';

  @override
  String get changesSavedSuccessfully => 'Änderungen erfolgreich gespeichert';

  @override
  String saveFailedWithError(String error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String linesCount(int count) {
    return 'Zeilen: $count';
  }

  @override
  String charsCount(int count) {
    return 'Zeichen: $count';
  }

  @override
  String get unsavedChangesLabel => 'Nicht gespeicherte Änderungen';

  @override
  String get savedToVault => 'Im Tresor gespeichert';

  @override
  String get saveChangesTooltip => 'Änderungen speichern';

  @override
  String get textEditorDecryptFailedMessage =>
      'Datei konnte nicht aus dem Tresor entschlüsselt werden.';

  @override
  String get textEditorInvalidTextFileMessage =>
      'Die Datei scheint keine gültige Textdatei zu sein.';

  @override
  String get textEditorWriteBackFailedMessage =>
      'Datei konnte nicht in den Tresor zurückgeschrieben werden.';

  @override
  String get backTooltip => 'Zurück';

  @override
  String get forwardTooltip => 'Vor';

  @override
  String get reloadTooltip => 'Neu laden';

  @override
  String get optionsTooltip => 'Optionen';

  @override
  String get htmlViewerErrorTitle => 'Diese Seite kann nicht angezeigt werden';

  @override
  String get htmlViewerLoadFailedMessage => 'Datei konnte nicht geladen werden';

  @override
  String get enableJavaScriptDialogTitle => 'JavaScript aktivieren?';

  @override
  String get enableJavaScriptDialogMessage =>
      'Der Seite wird erlaubt, ihre eigenen lokalen Skripte auszuführen. Sie hat weiterhin keinen Netzwerkzugriff — nichts in diesem Tresor kann über das Internet gesendet oder empfangen werden.';

  @override
  String get disableJavaScriptMenu => 'JavaScript deaktivieren';

  @override
  String get enableJavaScriptMenu => 'JavaScript aktivieren';

  @override
  String get enterFullscreenMenu => 'Vollbild aktivieren';

  @override
  String failedToOpenExternalApp(String error) {
    return 'Öffnen in externer App fehlgeschlagen: $error';
  }

  @override
  String get thisFolderMenu => 'Dieser Ordner';

  @override
  String get allInclSubfoldersMenu => 'Alle (inkl. Unterordner)';

  @override
  String get disableShuffleMenu => 'Zufallswiedergabe deaktivieren';

  @override
  String get shufflePlaylistMenu => 'Playlist mischen';

  @override
  String get playlistOptionsTooltip => 'Playlist-Optionen';

  @override
  String get enablePlaylistTooltip => 'Playlist aktivieren';

  @override
  String get moreActionsTooltip => 'Weitere Aktionen';

  @override
  String get forcePortraitMenu => 'Hochformat erzwingen';

  @override
  String get forceLandscapeMenu => 'Querformat erzwingen';

  @override
  String get autoRotateSensorMenu => 'Automatisch drehen (Sensor)';

  @override
  String get screenOrientationMenu => 'Bildschirmausrichtung';

  @override
  String get playlistTransitionMenu => 'Playlist-Übergang';

  @override
  String get renameFileMenu => 'Datei umbenennen';

  @override
  String get deleteFileMenu => 'Datei löschen';

  @override
  String get thumbnailCarouselTooltip => 'Miniaturansicht-Karussell';

  @override
  String get advancedSettingsTooltip => 'Erweiterte Einstellungen';

  @override
  String get previousTooltip => 'Vorherige';

  @override
  String get nextTooltip => 'Nächste';

  @override
  String get diagnosticsCopiedToClipboard =>
      'Diagnose in die Zwischenablage kopiert';

  @override
  String get diagnosticsTitle => 'Diagnose';

  @override
  String get copyDiagnosticsTooltip => 'Diagnose kopieren';

  @override
  String get closeTooltip => 'Schließen';

  @override
  String get diagnosticsPlaybackSection => 'Wiedergabe';

  @override
  String get diagnosticsEngineSection => 'Engine';

  @override
  String get diagnosticsStateLabel => 'Status';

  @override
  String get diagnosticsResolutionLabel => 'Auflösung';

  @override
  String get diagnosticsAspectRatioLabel => 'Seitenverhältnis';

  @override
  String get diagnosticsPositionLabel => 'Position';

  @override
  String get diagnosticsDurationLabel => 'Dauer';

  @override
  String get diagnosticsErrorLabel => 'Fehler';

  @override
  String get diagnosticsPlayerLabel => 'Player';

  @override
  String get diagnosticsDecodingLabel => 'Decodierung';

  @override
  String get diagnosticsExoPlayerValue => 'ExoPlayer (Android)';

  @override
  String get diagnosticsHardwareAcceleratedValue => 'Hardwarebeschleunigt';

  @override
  String get diagnosticsUnknownValue => 'Unbekannt';

  @override
  String get diagnosticsStateBuffering => 'Puffern';

  @override
  String get diagnosticsStatePlaying => 'Wiedergabe';

  @override
  String get diagnosticsStatePaused => 'Pausiert';

  @override
  String get diagnosticsDurationUnavailable => '--:--';

  @override
  String get rotate90Label => 'Um 90° drehen';

  @override
  String get imageFitModeLabel => 'Bildanpassungsmodus';

  @override
  String get slideshowDelayLabel => 'Diashow-Verzögerung';

  @override
  String get playbackSpeedLabel => 'Wiedergabegeschwindigkeit';

  @override
  String get subtitlesLabel => 'Untertitel';

  @override
  String get imageSettingsTitle => 'Bildeinstellungen';

  @override
  String get playbackSettingsTitle => 'Wiedergabeeinstellungen';

  @override
  String get imageFitContain => 'Einpassen';

  @override
  String get imageFitWidth => 'Breite anpassen';

  @override
  String get imageFitHeight => 'Höhe anpassen';

  @override
  String nSecondsDelay(int n) {
    return '$n Sekunden';
  }

  @override
  String playbackSpeedNormal(String speed) {
    return '${speed}x (Normal)';
  }

  @override
  String playbackSpeedValue(String speed) {
    return '${speed}x';
  }

  @override
  String slideshowDelaySecondsValue(int seconds) {
    return '${seconds}s';
  }

  @override
  String rotationDegreesValue(int degrees) {
    return '$degrees°';
  }

  @override
  String get settingsTooltipShort => 'Einstellungen';

  @override
  String get sourceCodeTooltip => 'Quellcode';

  @override
  String get donateTooltip => 'Spenden';

  @override
  String get shareAppTooltip => 'App teilen';

  @override
  String get resetToDefaultsTooltip => 'Auf Standard zurücksetzen';

  @override
  String get usbUnlockContainerTitle => 'USB-Container entsperren';

  @override
  String get usbMountContainerTitle => 'USB-Laufwerk einbinden';

  @override
  String get staticLabel => 'Statisch';

  @override
  String get unmuteTooltip => 'Ton ein';

  @override
  String get muteTooltip => 'Ton aus';

  @override
  String get playOnceDisabledTooltip =>
      'Einmal abspielen (Automatischer Weiterlauf deaktiviert)';

  @override
  String get playAndAdvanceTooltip => 'Abspielen & zum Nächsten wechseln';

  @override
  String get loopCurrentVideoTooltip => 'Aktuelles Video wiederholen';

  @override
  String get clearThumbnailCacheDialogTitle => 'Miniaturansicht-Cache leeren?';

  @override
  String get clearThumbnailCacheDialogMessage =>
      'Dadurch werden zwischengespeicherte Miniaturansichten für diesen Tresor gelöscht. Sie werden beim nächsten Durchsuchen von Medien neu erstellt.';

  @override
  String get clearCacheButton => 'Cache leeren';

  @override
  String get appCacheClearedUnlockMessage =>
      'App-Cache geleert. Container entsperren, um den internen Cache zu leeren.';

  @override
  String get allThumbnailCachesClearedMessage =>
      'Alle Miniaturansicht-Caches erfolgreich geleert.';

  @override
  String get appCacheClearedContainerFailedMessage =>
      'App-Cache geleert, aber der interne Cache des Containers konnte nicht geleert werden.';

  @override
  String get failedToClearThumbnailCachesMessage =>
      'Miniaturansicht-Caches konnten nicht geleert werden.';

  @override
  String get authenticateToModifySettingsPrompt =>
      'Authentifizieren, um Einstellungen zu ändern';

  @override
  String get usbVaultSettingsTitle => 'USB-Tresor-Einstellungen';

  @override
  String get vaultSettingsTitle => 'Tresor-Einstellungen';

  @override
  String get generalSectionHeader => 'Allgemein';

  @override
  String get securityCredentialsSectionHeader => 'Sicherheit & Anmeldedaten';

  @override
  String get securityOptionsLockedTitle => 'Sicherheitsoptionen gesperrt';

  @override
  String get authenticateOriginalCredentialsMessage =>
      'Authentifizieren Sie sich mit den ursprünglichen Container-Anmeldedaten, um die Sicherheitseinstellungen zu ändern.';

  @override
  String get unlockCredentialsLabel => 'Entsperr-Anmeldedaten';

  @override
  String get unavailableSuffixLabel => '(Nicht verfügbar)';

  @override
  String get patternSetupRequiredBeforeSaving =>
      'Richten Sie ein Muster ein, bevor Sie speichern.';

  @override
  String get passwordKeystoreEncryptedHelperText =>
      'Das Passwort wird mit dem Android Keystore verschlüsselt. Leer lassen, wenn nur Schlüsseldateien verwendet werden.';

  @override
  String get changePatternButton => 'Muster ändern';

  @override
  String get setPatternButton => 'Muster festlegen';

  @override
  String get cacheDerivedKeyLabel => 'Abgeleiteten Schlüssel zwischenspeichern';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      'CryFS-scrypt-KDF beim nächsten Mal überspringen (Schlüssel im Android Keystore gespeichert)';

  @override
  String get reuseKeyMaterialKeystoreSubtitle =>
      'Schlüsselmaterial im Android Keystore wiederverwenden';

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle =>
      'Algorithmus fixieren, um die automatische Erkennung beim Entsperren zu überspringen.';

  @override
  String get changeContainerPasswordTitle => 'Container-Passwort ändern';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      'BitLocker-Anmeldedaten können nicht in der App geändert werden. Verwenden Sie \"BitLocker verwalten\" unter Windows.';

  @override
  String get systemIntegrationSectionHeader => 'System & Integration';

  @override
  String get autoLockDurationLabel => 'Dauer bis automatische Sperre';

  @override
  String get neverAutoLockOption => 'Nie';

  @override
  String get exposeContentToFilePickerSubtitle =>
      'Inhalt bei Entsperrung für die Systemdateiauswahl freigeben';

  @override
  String get thumbnailStorageSectionHeader => 'Miniaturansicht-Speicherung';

  @override
  String get cacheModeLabel => 'Cache-Modus';

  @override
  String get useGlobalDefaultSubtitle => 'Globalen Standard verwenden';

  @override
  String get thumbnailQualityLabel => 'Miniaturansicht-Qualität';

  @override
  String get clearThumbnailCacheTitle => 'Miniaturansicht-Cache leeren';

  @override
  String get removeCachedThumbnailsSubtitle =>
      'Zwischengespeicherte Bild- und Video-Miniaturansichten entfernen';

  @override
  String get vaultInformationSectionHeader => 'Tresorinformationen';

  @override
  String get vaultInformationTileTitle => 'Tresordetails anzeigen';

  @override
  String get vaultInformationTileSubtitle =>
      'Verschlüsselung, Format und weitere technische Details';

  @override
  String get vaultInfoLocationLabel => 'Speicherort';

  @override
  String get vaultInfoRequiresUnlockTitle => 'Entsperren erforderlich';

  @override
  String get vaultInfoRequiresUnlockMessage =>
      'Entsperren Sie diesen Tresor, um die technischen Details anzuzeigen.';

  @override
  String get vaultInfoLoadFailedTitle =>
      'Tresorinformationen konnten nicht geladen werden';

  @override
  String get vaultInfoLoadFailedMessage =>
      'Beim Lesen der Tresordetails ist ein Fehler aufgetreten.';

  @override
  String get vaultInfoVolumeSizeLabel => 'Datenträgergröße';

  @override
  String get vaultInfoFileSystemLabel => 'Dateisystem';

  @override
  String get vaultInfoHiddenVolumeLabel => 'Verstecktes Volume';

  @override
  String get vaultInfoReadOnlyLabel => 'Schreibgeschützt';

  @override
  String get vaultInfoLuksVersionLabel => 'LUKS-Version';

  @override
  String get vaultInfoSectorSizeLabel => 'Sektorgröße';

  @override
  String get vaultInfoVaultFormatLabel => 'Tresorformat';

  @override
  String get vaultInfoCipherComboLabel => 'Verschlüsselungskombination';

  @override
  String get vaultInfoShorteningThresholdLabel =>
      'Schwellenwert für Dateinamenkürzung';

  @override
  String get vaultInfoFormatVersionLabel => 'Formatversion';

  @override
  String get vaultInfoContentCipherLabel => 'Inhaltsverschlüsselung';

  @override
  String get vaultInfoFilenameEncryptionLabel => 'Dateinamen';

  @override
  String get vaultInfoPlaintextNamesValue => 'Klartext';

  @override
  String get vaultInfoEncryptedNamesValue => 'Verschlüsselt';

  @override
  String get vaultInfoBlockCipherLabel => 'Blockverschlüsselung';

  @override
  String get vaultInfoBlockSizeLabel => 'Blockgröße';

  @override
  String get vaultInfoCreatedWithVersionLabel => 'Erstellt mit';

  @override
  String get vaultInfoLastOpenedWithVersionLabel => 'Zuletzt geöffnet mit';

  @override
  String get vaultInfoYesValue => 'Ja';

  @override
  String get vaultInfoNoValue => 'Nein';

  @override
  String get vaultInfoBitlockerNote =>
      'Diese App liest BitLockers eigene Header-Metadaten nicht aus, daher sind Verschlüsselungs- und Versionsdetails hier nicht verfügbar.';

  @override
  String get patternSetupRequiredAboveBeforeSaving =>
      'Richten Sie oben ein Muster ein, bevor Sie speichern.';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      'Für diese Entsperrmethode ist ein Passwort oder \"Abgeleiteten Schlüssel zwischenspeichern\" mit Schlüsseldateien erforderlich.';

  @override
  String get saveConfigurationButton => 'Konfiguration speichern';

  @override
  String get incorrectPatternError => 'Falsches Muster';

  @override
  String get verifyPatternTitle => 'Muster überprüfen';

  @override
  String get incorrectPasswordError => 'Falsches Passwort';

  @override
  String get verificationFailedError => 'Überprüfung fehlgeschlagen';

  @override
  String get incorrectCredentialsError => 'Falsche Anmeldedaten';

  @override
  String get containerPasswordOptionalLabel =>
      'Container-Passwort (optional bei reiner Schlüsseldatei)';

  @override
  String get pimOptionalLabel => 'PIM (optional)';

  @override
  String get usbDriveLockedLabel => 'USB-Laufwerk · Gesperrt';

  @override
  String get lockedContainerLabel => 'Gesperrter Container';

  @override
  String get operationInProgressWaitMessage =>
      'Ein Vorgang läuft. Bitte warten Sie vor dem Sperren.';

  @override
  String get reconnectUsbTooltip => 'USB erneut verbinden';

  @override
  String get unlockContainerTooltip => 'Container entsperren';

  @override
  String lockFailedMessage(String errorType) {
    return 'Sperren fehlgeschlagen: $errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired =>
      'Neues Passwort oder Schlüsseldateien sind erforderlich.';

  @override
  String get newPasswordsDoNotMatch => 'Neue Passwörter stimmen nicht überein.';

  @override
  String get passwordChangedSuccessfullyMessage =>
      'Passwort erfolgreich geändert.';

  @override
  String get failedToChangePasswordMessage =>
      'Passwort konnte nicht geändert werden. Überprüfen Sie die alten Anmeldedaten.';

  @override
  String get currentCredentialsSectionHeader => 'Aktuelle Anmeldedaten';

  @override
  String get oldPasswordLabel => 'Altes Passwort';

  @override
  String get oldPimOptionalLabel => 'Alte PIM (optional)';

  @override
  String get newCredentialsSectionHeader => 'Neue Anmeldedaten';

  @override
  String get newPimOptionalLabel => 'Neue PIM (optional)';

  @override
  String get noContainersYetTitle => 'Noch keine Container';

  @override
  String get dashboardEmptyStateMessage =>
      'Binden Sie einen VeraCrypt-Container ein, verbinden Sie ein USB-Laufwerk oder erstellen Sie einen brandneuen verschlüsselten Tresor, um zu beginnen.';

  @override
  String get sortFieldName => 'Name';

  @override
  String get sortFieldSize => 'Größe';

  @override
  String get sortFieldType => 'Typ';

  @override
  String get sortFieldDate => 'Datum';

  @override
  String get layoutModeDetailedList => 'Detaillierte Liste';

  @override
  String get layoutModeCompactList => 'Kompakte Liste';

  @override
  String get layoutModeGalleryGrid => 'Galerie-Raster';

  @override
  String get readOnlyCantDeleteTooltip =>
      'Schreibgeschützt — Löschen nicht möglich';

  @override
  String get readOnlyCantMoveTooltip =>
      'Schreibgeschützt — Verschieben nicht möglich';

  @override
  String get readOnlyCantRenameTooltip =>
      'Schreibgeschützt — Umbenennen nicht möglich';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes (wird berechnet…)';
  }

  @override
  String get sizeCalculatingLabel => 'wird berechnet…';

  @override
  String get editSecureItemsToRenameMessage =>
      'Sichere Elemente zum Umbenennen bearbeiten';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage =>
      'Tresor-Elemente können nicht in externen Apps geöffnet werden';

  @override
  String get mountedReadOnlyTooltip => 'Schreibgeschützt eingebunden';

  @override
  String get readOnlyBadgeAbbreviation => 'SG';

  @override
  String freeSpaceLabel(String bytes) {
    return '$bytes frei';
  }

  @override
  String get filteredLabel => 'gefiltert';

  @override
  String get statsStorageSectionHeader => 'SPEICHER';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ordner',
      one: '1 Ordner',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien',
      one: '1 Datei',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => 'Alle Dateien';

  @override
  String get filterImagesOption => 'Bilder';

  @override
  String get filterVideosOption => 'Videos';

  @override
  String get filterAudioOption => 'Audio';

  @override
  String get filterDocumentsOption => 'Dokumente';

  @override
  String get folderExposedAsStorageExplanation =>
      'Dieser Ordner wird als eigener Speicherort freigegeben, sodass andere Apps seine Dateien direkt durchsuchen und öffnen können.';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente existieren bereits',
      one: '1 Element existiert bereits',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle =>
      'Wählen Sie, was mit jedem Element geschieht, oder wenden Sie eine Auswahl auf alle an.';

  @override
  String get skipAllChipLabel => 'Alle überspringen';

  @override
  String get overwriteAllChipLabel => 'Alle überschreiben';

  @override
  String get overwriteItemDropdownLabel => 'Überschreiben';

  @override
  String get overwriteFolderDropdownLabel => 'Ordner überschreiben';

  @override
  String get fileOpsTransfersInProgressTitle => 'Übertragungen laufen';

  @override
  String get fileOpsRecentTransfersTitle => 'Letzte Übertragungen';

  @override
  String get fileOpsNoRecentTransfersMessage =>
      'Keine kürzlichen Übertragungen';

  @override
  String get fileOpsNoRecentTransfersSubtitle =>
      'Kopien, Verschiebungen und Löschungen werden hier angezeigt, während sie laufen.';

  @override
  String fileOpsShowDetailsLabel(num count) {
    return 'Details anzeigen';
  }

  @override
  String get fileOpsCancelTooltip => 'Abbrechen';

  @override
  String get fileOpsDismissTooltip => 'Verwerfen';

  @override
  String get fileOpsRootDestinationLabel => 'Stammverzeichnis';

  @override
  String get fileOpsCancelledStatusLabel => 'Abgebrochen';

  @override
  String fileOpsItemsFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente fehlgeschlagen:',
      one: '1 Element fehlgeschlagen:',
    );
    return '$_temp0';
  }

  @override
  String fileOpsMoreItemsLabel(num count) {
    return '+ $count weitere';
  }

  @override
  String get transferActivityTooltip => 'Übertragungen';

  @override
  String fileOpsSpeedLabel(String speed) {
    return '$speed/s';
  }

  @override
  String fileOpsEtaLabel(String time) {
    return '~$time verbleibend';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return 'Fehler beim Lesen der Datei: $error';
  }

  @override
  String get archivePreviewNotAvailableMessage =>
      'Für diesen Dateityp ist keine Vorschau verfügbar.';

  @override
  String get avifFailedToRenderMessage => 'AVIF konnte nicht gerendert werden';

  @override
  String get encryptedImageLoadFailedMessage =>
      'Verschlüsseltes Bild konnte nicht geladen werden';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return 'Verschlüsseltes Bild konnte nicht geladen werden: $error';
  }

  @override
  String get invalidOrCorruptedImageMessage =>
      'Ungültiges oder beschädigtes Bildformat.';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '$current von $total';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '$current von $total  ·  wird gescannt…';
  }

  @override
  String get mediaViewerScanningLabel => 'Wird gescannt…';

  @override
  String get mediaFileDeletedMessage => 'Datei erfolgreich gelöscht';

  @override
  String get mediaFileDeleteFailedMessage =>
      'Datei konnte nicht gelöscht werden';

  @override
  String get mediaFileRenamedMessage => 'Datei erfolgreich umbenannt';

  @override
  String get aboutScreenTitle => 'Über';

  @override
  String get couldNotOpenLinkMessage => 'Link konnte nicht geöffnet werden';

  @override
  String get fileManagerSettingsTitle => 'Dateimanager-Einstellungen';

  @override
  String get showMediaThumbnailsLabel => 'Medienminiaturen anzeigen';

  @override
  String get showMediaThumbnailsDesc =>
      'Vorschaubilder für Bilder und Videos in der Listenansicht anzeigen';

  @override
  String get showFileNamesLabel => 'Dateinamen anzeigen';

  @override
  String get showFileNamesDesc =>
      'Textbeschriftungen unter Elementen im Rasterlayout anzeigen';

  @override
  String get showBreadcrumbBarLabel => 'Pfadleiste anzeigen';

  @override
  String get showBreadcrumbBarDesc => 'Pfad-Navigationsleiste oben im Browser';

  @override
  String get showStatsBarLabel => 'Statusleiste anzeigen';

  @override
  String get showStatsBarDesc =>
      'Infobanner mit Dateianzahl und freiem Speicherplatz';

  @override
  String get autoStartPlaylistModeLabel =>
      'Wiedergabelistenmodus automatisch starten';

  @override
  String get autoStartPlaylistModeDesc =>
      'Beim Öffnen eines Medienelements automatisch im Wiedergabelistenmodus starten';

  @override
  String get showPlaylistCarouselLabel => 'Wiedergabelisten-Karussell anzeigen';

  @override
  String get showPlaylistCarouselDesc =>
      'Miniaturkarussell-Schaltfläche beim Anzeigen von Medienwiedergabelisten anzeigen';

  @override
  String get videoPlaybackSliderLabel =>
      'Schieberegler für Videowiedergabeposition';

  @override
  String get longPressPlaybackDiagnosticsHint =>
      'Für Wiedergabediagnose lange drücken';

  @override
  String get staticImageModeLabel => 'Standbild-Modus';

  @override
  String slideshowModeActiveLabel(int seconds) {
    return 'Diashow-Modus aktiv mit $seconds Sekunden Verzögerung';
  }

  @override
  String videoPlaybackModeLabel(String mode) {
    return 'Videowiedergabemodus: $mode';
  }

  @override
  String get pauseLabel => 'Pause';

  @override
  String get playLabel => 'Wiedergabe';

  @override
  String get emptyFolderTitle => 'Leerer Ordner';

  @override
  String get emptyFolderMessage =>
      'Verwenden Sie die Aktion „Hinzufügen“, um Dateien zu erstellen oder vom Gerät zu importieren.';

  @override
  String get noResultsTitle => 'Keine Ergebnisse';

  @override
  String noResultsForQueryMessage(String query) {
    return 'Nichts in diesem Ordner entspricht „$query“.';
  }

  @override
  String get closeCarouselTooltip => 'Karussell schließen';

  @override
  String get playlistScrollModeMenu => 'Wiedergabelisten-Scrollmodus';

  @override
  String get playlistScrollHorizontalLabel => 'Horizontal';

  @override
  String get playlistScrollVerticalPageLabel => 'Vertikal seitenweise';

  @override
  String get playlistScrollVerticalContinuousLabel => 'Vertikal fortlaufend';

  @override
  String get undoTooltip => 'Rückgängig';

  @override
  String get redoTooltip => 'Wiederholen';

  @override
  String get autosavingLabel => 'Automatisches Speichern…';

  @override
  String get savingLabel => 'Wird gespeichert…';

  @override
  String autosavedAtLabel(String time) {
    return 'Automatisch gespeichert um $time';
  }

  @override
  String cameraDisconnectedError(String message) {
    return 'Kamera getrennt: $message';
  }

  @override
  String get unknownErrorFallback => 'unbekannter Fehler';

  @override
  String get cameraPermissionsRequiredMessage =>
      'Kamera- und Mikrofonberechtigungen sind erforderlich, um die Kamera zu verwenden.';

  @override
  String cameraErrorMessage(String error) {
    return 'Kamerafehler: $error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage => 'Fotoaufnahme fehlgeschlagen';

  @override
  String get cameraRecordingFailedMessage => 'Aufnahme fehlgeschlagen';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return 'Aufnahme fehlgeschlagen: $error';
  }

  @override
  String get cameraRecordingTooShortMessage =>
      'Aufnahme war zu kurz zum Speichern';

  @override
  String get cameraCouldNotSaveRecordingMessage =>
      'Aufnahme konnte nicht gespeichert werden';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return 'Aufnahme konnte nicht gespeichert werden: $error';
  }

  @override
  String get cameraCouldNotSwitchLensMessage =>
      'Objektiv konnte nicht gewechselt werden';

  @override
  String get cameraEncryptingPhotoLabel => 'Foto wird verschlüsselt…';

  @override
  String get cameraEncryptingVideoLabel => 'Video wird verschlüsselt…';

  @override
  String get aboutApplicationSectionHeader => 'Anwendung';

  @override
  String get aboutTagline =>
      'Kostenlos · Open Source · Offline verschlüsselter Tresor';

  @override
  String get aboutVersionTitle => 'Version';

  @override
  String aboutVersionSubtitle(String version) {
    return 'v$version';
  }

  @override
  String get aboutWhatsNewTitle => 'Neuigkeiten';

  @override
  String get aboutWhatsNewSubtitle =>
      'Aktuelle Änderungen und Versionshinweise ansehen';

  @override
  String get aboutPrivacySecurityTitle => 'Datenschutz & Sicherheit';

  @override
  String get aboutPrivacySecuritySubtitle =>
      'Kein Netzwerkzugriff, nie unverschlüsselte Daten auf die Festplatte geschrieben';

  @override
  String get aboutSupportedFormatsSectionHeader => 'Unterstützte Formate';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt & LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      'Standard- und versteckte Volumes, benutzerdefinierter PIM, Schlüsseldateien, xts-plain64, Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker & BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle =>
      'Benutzerkennwörter und Unterstützung für 48-stellige numerische Wiederherstellungsschlüssel';

  @override
  String get aboutDirectoryVaultsTitle => 'Ordner-Tresore';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator (v7/v8 SIV_GCM & SIV_CTRMAC), gocryptfs (v2 AES-GCM & XChaCha20), CryFS (v0.10+ XChaCha20 & AES)';

  @override
  String get aboutVhdTitle => 'Virtuelle Festplatten (VHD / VHDX)';

  @override
  String get aboutVhdSubtitle =>
      'BAT-Übersetzung für feste und dynamisch erweiterbare Datenträgerabbilder';

  @override
  String get aboutNativeCoreEngineSectionHeader => 'Native Kern-Engine';

  @override
  String get aboutCompiledLibrariesTitle => 'Kompilierte C++-Bibliotheken';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.0 (ARMv8-Hardwarekryptografie & SHA-2)\n• libavif & libgav1 (nativer AVIF-Bilddecoder)\n• ChaN FatFs v4.0.4 (FAT12/16/32 & exFAT)\n• Tuxera NTFS-3G & eingebettetes mkntfs\n• e2fsprogs v1.47.4 libext2fs (ext2/ext3/ext4)\n• Dislocker Virtual I/O (BitLocker FVE / To Go)\n• VeraCrypt 1.26.29 (Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id/i)\n• cJSON v1.7.18 (LUKS2- & Cryptomator-Metadaten)';

  @override
  String get aboutCommunitySectionHeader => 'Community & Open Source';

  @override
  String get aboutReportIssueTitle => 'Problem melden';

  @override
  String get aboutReportIssueSubtitle =>
      'Einen Fehler gefunden? Ein Issue auf GitHub einreichen';

  @override
  String get reportIssueSheetTitle => 'Problem melden';

  @override
  String get reportIssueSheetSubtitle =>
      'Wählen Sie die Option, die am besten zu Ihrem Problem passt – es öffnet ein vorausgefülltes GitHub-Formular';

  @override
  String get reportIssueBugTitle => 'Fehlerbericht';

  @override
  String get reportIssueBugSubtitle =>
      'Etwas ist abgestürzt oder funktioniert nicht richtig';

  @override
  String get reportIssueContainerTitle => 'Container-/Tresor-Problem';

  @override
  String get reportIssueContainerSubtitle =>
      'Problem beim Entsperren, Einbinden oder formatspezifisches Problem';

  @override
  String get reportIssueFeatureTitle => 'Funktionswunsch';

  @override
  String get reportIssueFeatureSubtitle =>
      'Eine Idee oder Verbesserung vorschlagen';

  @override
  String get reportIssueOtherTitle => 'Etwas anderes';

  @override
  String get reportIssueOtherSubtitle => 'Alle Vorlagen auf GitHub durchsuchen';

  @override
  String get aboutContributorsTitle => 'Mitwirkende';

  @override
  String get aboutContributorsSubtitle =>
      'Menschen, die beim Erstellen von VaultExplorer geholfen haben';

  @override
  String get aboutLicensesTitle => 'Open-Source-Lizenzen';

  @override
  String get aboutLicensesSubtitle =>
      'In dieser App verwendete Bibliotheken von Drittanbietern';

  @override
  String get aboutFooterMadeWithLove => 'Mit ❤ für den Datenschutz gemacht.';

  @override
  String get aboutVersionCopiedMessage =>
      'Versionsinfo kopiert — praktisch für Fehlerberichte';

  @override
  String aboutVersionClipboardText(String version) {
    return 'VaultExplorer v$version (Android)';
  }

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer — ein kostenloser, quelloffener, Offline-Tresor für Android.\n\nSpeichern Sie Passwörter, Notizen und Dateien in einem verschlüsselten Container (VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs, CryFS).\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage =>
      'Teilbaren Link in die Zwischenablage kopiert';

  @override
  String get aboutPrivacySheetTitle => 'Datenschutz & Datensicherheit';

  @override
  String get aboutPrivacySheetSubtitle =>
      '100 % offline, lokal gespeichertes Sicherheitskonzept';

  @override
  String get privacyPointNoNetworkTitle => 'Kein Netzwerkzugriff erforderlich';

  @override
  String get privacyPointNoNetworkBody =>
      'VaultExplorer fordert unter Android nicht die Berechtigung android.permission.INTERNET an. Es kann über kein Netzwerk kommunizieren.';

  @override
  String get privacyPointNoDiskLeaksTitle =>
      'Keine unverschlüsselten Datenlecks auf dem Datenträger';

  @override
  String get privacyPointNoDiskLeaksBody =>
      'Entschlüsselung und erneute Verschlüsselung erfolgen ausschließlich im Systemspeicher. Temporäre unverschlüsselte Dateien werden niemals auf dem Gerätespeicher gespeichert.';

  @override
  String get privacyPointNoAnalyticsTitle => 'Keine Analyse oder Telemetrie';

  @override
  String get privacyPointNoAnalyticsBody =>
      'Es gibt keinerlei Absturzberichte, Nutzungsverfolgung oder Drittanbieter-SDKs, die Daten über Sie oder Ihr Gerät sammeln.';

  @override
  String get privacyPointKeystoreTitle =>
      'Geheimnisse bleiben im Android Keystore';

  @override
  String get privacyPointKeystoreBody =>
      'Gespeicherte Passwörter, Muster und zwischengespeicherte abgeleitete Schlüssel werden mit AES-256-GCM im hardwaregestützten Android Keystore versiegelt.';

  @override
  String get privacyPointPosixTitle => 'POSIX-Beschleunigung & Speicherzugriff';

  @override
  String get privacyPointPosixBody =>
      'Dateien in Ordner-Tresoren werden nach Möglichkeit direkt gelesen und geschrieben, wodurch Androids langsamere SAF-Schicht bei großen Ordnern umgangen wird.';

  @override
  String get privacyPointScreenClipboardTitle =>
      'Bildschirm- & Zwischenablageschutz';

  @override
  String get privacyPointScreenClipboardBody =>
      'Screenshot/task-switcher preview blocking (FLAG_SECURE) and automatic corrupt clipboard sanitization upon window focus.';

  @override
  String get privacyPointMaskModeTitle => 'Maskenmodus';

  @override
  String get privacyPointMaskModeBody =>
      'Optionally disguises the app as a working zip archive browser, with a different icon and name. Hold the title for 3 seconds to reach your real vault.';

  @override
  String get privacyPointExternalLinksTitle =>
      'Externe Links öffnen im Browser';

  @override
  String get privacyPointExternalLinksBody =>
      'Das Tippen auf Links übergibt die Anfrage an Ihre Standard-Browser-App.';

  @override
  String get truncatedListingWarning =>
      'Die ersten 50.000 Elemente werden angezeigt — dieser Ordner enthält weitere Dateien.';

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '$size px · $quality% Qualität';
  }

  @override
  String holdToSpeedIndicatorLabel(String speed) {
    return '$speed× Geschwindigkeit';
  }

  @override
  String get toolbarLayoutSectionHeader => 'Symbolleisten-Layout';

  @override
  String get listViewOptionsSectionHeader => 'Listenansicht-Optionen';

  @override
  String get detailedListViewColumnsSectionHeader =>
      'Spalten der detaillierten Listenansicht';

  @override
  String get galleryGridViewSectionHeader => 'Galerie-Rasteransicht';

  @override
  String get browserLayoutSectionHeader => 'Browser-Layout';

  @override
  String get mediaViewerSectionHeader => 'Medienbetrachter';

  @override
  String get viewModeAction => 'Ansichtsmodus';

  @override
  String get sortAction => 'Sortieren';

  @override
  String get playMediaAction => 'Medien abspielen';

  @override
  String containerSpaceSummary(String free, String total) {
    return '$free frei · $total gesamt';
  }

  @override
  String volMountedSummary(int volId) {
    return 'Vol $volId · Eingebunden';
  }

  @override
  String vaultOccupiedSpaceSummary(String used) {
    return '$used belegt';
  }

  @override
  String get incorrectPasswordOrKeyfilesDriveError =>
      'Falsches Passwort/Schlüsseldateien oder nicht unterstütztes Laufwerk';

  @override
  String driveUsableCapacity(int mb) {
    return 'Nutzbare Laufwerkskapazität: $mb MB. Darf nicht überschritten werden.';
  }

  @override
  String get unlockMethodManualPassword => 'Manuelles Passwort';

  @override
  String get unlockMethodRememberPassword => 'Passwort merken';

  @override
  String get unlockMethodBiometrics => 'Biometrische Entsperrung';

  @override
  String get unlockMethodPattern => 'Muster-Entsperrung';

  @override
  String get unlockMethodPin => 'PIN-Entsperrung';

  @override
  String get unlockMethodSubtitlePassword => 'Das Passwort jedes Mal eingeben';

  @override
  String get unlockMethodSubtitleRememberPassword =>
      'Sicher im Android Keystore gespeichert';

  @override
  String get unlockMethodSubtitleBiometrics =>
      'Fingerabdruck oder Gesicht zum Entsperren verwenden';

  @override
  String get unlockMethodSubtitlePattern =>
      'Zum Entsperren ein Muster zeichnen';

  @override
  String get unlockMethodSubtitlePin => 'PIN zum Entsperren eingeben';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError =>
      'Video-Decoder nicht verfügbar — Hardware-Codec-Konflikt';

  @override
  String get mediaStreamInitFailedError =>
      'Initialisierung des Medienstreams fehlgeschlagen';

  @override
  String get invalidAvifImage => 'Ungültiges AVIF-Bild';

  @override
  String get verbImport => 'Importieren';

  @override
  String get verbExport => 'Exportieren';

  @override
  String get verbMove => 'Verschieben';

  @override
  String get verbCopy => 'Kopieren';

  @override
  String get verbDelete => 'Löschen';

  @override
  String get verbImported => 'Importiert';

  @override
  String get verbExported => 'Exportiert';

  @override
  String get verbMoved => 'Verschoben';

  @override
  String get verbCopied => 'Kopiert';

  @override
  String get verbDeleted => 'Gelöscht';

  @override
  String get verbImporting => 'Wird importiert';

  @override
  String get verbExporting => 'Wird exportiert';

  @override
  String get verbMoving => 'Wird verschoben';

  @override
  String get verbCopying => 'Wird kopiert';

  @override
  String get verbDeleting => 'Wird gelöscht';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente',
      one: '1 Element',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente $verb',
      one: '1 Element $verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return '$count übersprungen';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return '$count fehlgeschlagen';
  }

  @override
  String get statusCancelled => 'Abgebrochen';

  @override
  String get statusFailed => 'Fehlgeschlagen';

  @override
  String get statusCompleted => 'Abgeschlossen';

  @override
  String get fileOpCheckingSpace => 'Verfügbarer Speicherplatz wird geprüft…';

  @override
  String get fileOpResolvingConflicts => 'Konflikte werden gelöst…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return 'Nicht genug Speicherplatz — benötigt $required, nur $free frei';
  }

  @override
  String get fileOpDiskFullPartialRemoved =>
      'Speicher voll — teilweise Dateien entfernt';

  @override
  String get fileOpMoveFailed => 'Verschieben fehlgeschlagen';

  @override
  String get fileOpCopyFailed => 'Kopieren fehlgeschlagen';

  @override
  String get fileOpDeleteFailed => 'Löschen fehlgeschlagen';

  @override
  String get fileOpDiskFull => 'Speicher voll';

  @override
  String get fileOpImporting => 'Wird importiert…';

  @override
  String get fileOpExporting => 'Wird exportiert…';

  @override
  String fileOpImportingName(String name) {
    return '$name wird importiert…';
  }

  @override
  String fileOpExportingName(String name) {
    return '$name wird exportiert…';
  }

  @override
  String fileOpMovingName(String name) {
    return '$name wird verschoben…';
  }

  @override
  String fileOpCopyingName(String name) {
    return '$name wird kopiert…';
  }

  @override
  String get fileOpDeleting => 'Wird gelöscht…';

  @override
  String fileOpDeletingName(String name) {
    return '$name wird gelöscht…';
  }

  @override
  String fileOpDeletedSoFar(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente entfernt',
      one: '1 Element entfernt',
    );
    return '$_temp0';
  }

  @override
  String get searchInSubfoldersHint => 'Alle Unterordner durchsuchen…';

  @override
  String get deepSearchEnabledTooltip =>
      'Unterordner werden durchsucht — tippen für nur aktuellen Ordner';

  @override
  String get deepSearchDisabledTooltip =>
      'Aktueller Ordner wird durchsucht — tippen, um Unterordner zu durchsuchen';

  @override
  String get filterAction => 'Filtern';

  @override
  String get bookmarkAction => 'Lesezeichen hinzufügen';

  @override
  String get unbookmarkAction => 'Lesezeichen entfernen';

  @override
  String get bookmarkSelectedAction => 'Lesezeichen für Ausgewählte hinzufügen';

  @override
  String get unbookmarkSelectedAction =>
      'Lesezeichen bei Ausgewählten entfernen';

  @override
  String bookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente als Lesezeichen gespeichert',
      one: '1 Element als Lesezeichen gespeichert',
    );
    return '$_temp0';
  }

  @override
  String unbookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente aus Lesezeichen entfernt',
      one: '1 Element aus Lesezeichen entfernt',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => 'Lesezeichenleiste anzeigen';

  @override
  String get showBookmarkBarDesc =>
      'Als Lesezeichen gespeicherte Elemente in einer Lesezeichenleiste oder Seitenleiste anzeigen';

  @override
  String get bookmarkBarSectionHeader => 'Lesezeichenleiste';

  @override
  String get noBookmarksYet => 'Noch keine Lesezeichen gespeichert';

  @override
  String get reorderBookmarksTitle => 'Lesezeichen neu anordnen';

  @override
  String get reorderBookmarksDesc =>
      'Ziehen Sie Elemente, um sie in der Lesezeichenleiste neu anzuordnen';

  @override
  String get navBarVaultsLabel => 'Tresore';

  @override
  String get navBarToolsLabel => 'Werkzeuge';

  @override
  String get toolsScreenTitle => 'Werkzeuge';

  @override
  String get toolsSectionContainerUtilities => 'Container-Dienstprogramme';

  @override
  String get toolsSectionFileCryptography => 'Dateiverschlüsselung';

  @override
  String get toolsSectionStorageDiagnostics => 'Speicher & Diagnose';

  @override
  String get toolContainerSplitterTitle => 'Teilen & Zusammenführen';

  @override
  String get toolContainerSplitterSubtitle =>
      'Einen Container in Teile aufteilen oder wieder zusammenführen';

  @override
  String get toolContainerRepairTitle => 'Prüfen & Reparieren';

  @override
  String get toolContainerRepairSubtitle =>
      'Header- oder Dateisystemprobleme diagnostizieren';

  @override
  String get toolSingleFileCryptoTitle => 'Dateien ver-/entschlüsseln';

  @override
  String get toolSingleFileCryptoSubtitle =>
      'Eine oder mehrere Dateien ohne vollständigen Container schützen';

  @override
  String get toolStorageAnalyzerTitle => 'Speicheranalyse';

  @override
  String get toolStorageAnalyzerSubtitle =>
      'Sehen Sie, was in einem eingebundenen Tresor Speicherplatz belegt';

  @override
  String get toolDuplicateFinderTitle => 'Duplikat-Dateisuche';

  @override
  String get toolDuplicateFinderSubtitle =>
      'Byte-identische Duplikate finden und entfernen, um Speicherplatz freizugeben';

  @override
  String get toolHashVerifierTitle => 'Datei-Prüfsumme & Hash-Verifizierung';

  @override
  String get toolHashVerifierSubtitle =>
      'Überprüfen Sie mit MD5/SHA-Prüfsummen, dass große Dateien nicht beschädigt wurden';

  @override
  String get hashVerifierModeCompute => 'Berechnen';

  @override
  String get hashVerifierModeVerify => 'Überprüfen';

  @override
  String get hashVerifierSelectSourceTitle => 'Dateiquelle auswählen';

  @override
  String get hashVerifierAlgorithmsLabel => 'Algorithmen';

  @override
  String get hashVerifierNoAlgorithmSelected =>
      'Wählen Sie mindestens einen Algorithmus aus';

  @override
  String get hashVerifierFilesLabel => 'Zu hashende Dateien';

  @override
  String hashVerifierFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien ausgewählt',
      one: '1 Datei ausgewählt',
      zero: 'Keine Dateien ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierComputeButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Hashes berechnen',
      one: 'Hash berechnen',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCancelButton => 'Abbrechen';

  @override
  String hashVerifierBatchProgressLabel(Object current, Object total) {
    return 'Datei $current von $total';
  }

  @override
  String get hashVerifierCancelledMessage => 'Abgebrochen.';

  @override
  String hashVerifierComputeErrorsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien konnten nicht gehasht werden',
      one: '1 Datei konnte nicht gehasht werden',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCopiedMessage => 'In die Zwischenablage kopiert';

  @override
  String get hashVerifierExportManifestButton => 'Als Manifest exportieren';

  @override
  String get hashVerifierExportAlgorithmLabel => 'Manifest-Algorithmus';

  @override
  String hashVerifierExportSuccessMessage(Object path) {
    return 'Gespeichert unter $path';
  }

  @override
  String hashVerifierExportFailedMessage(Object error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String get hashVerifierLoadManifestButton => 'Manifest laden';

  @override
  String get hashVerifierChangeManifestButton => 'Ändern';

  @override
  String get hashVerifierManifestLabel => 'Manifest-Datei';

  @override
  String hashVerifierManifestEntryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
      zero: 'Keine Einträge',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierAutoAddFolderButton =>
      'Alle Dateien aus diesem Ordner hinzufügen';

  @override
  String get hashVerifierAddFilesToVerifyButton =>
      'Dateien zur Überprüfung hinzufügen';

  @override
  String get hashVerifierVerifyAllButton => 'Alle überprüfen';

  @override
  String hashVerifierVerifyProgressLabel(Object current, Object total) {
    return 'Datei $current von $total wird überprüft';
  }

  @override
  String hashVerifierSummaryMessage(
    Object ok,
    Object mismatch,
    Object missing,
  ) {
    return '$ok übereinstimmend, $mismatch nicht übereinstimmend, $missing fehlend';
  }

  @override
  String get hashVerifierStatusMatch => 'Übereinstimmung';

  @override
  String get hashVerifierStatusMismatch => 'Abweichung';

  @override
  String get hashVerifierStatusMissing => 'Datei nicht hinzugefügt';

  @override
  String get hashVerifierStatusPending => 'Noch nicht überprüft';

  @override
  String get hashVerifierExpectedLabel => 'Erwartet';

  @override
  String get hashVerifierActualLabel => 'Tatsächlich';

  @override
  String hashVerifierExtraFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zusätzliche Dateien nicht im Manifest aufgeführt',
      one: '1 zusätzliche Datei nicht im Manifest aufgeführt',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierNoManifestLoadedMessage =>
      'Laden Sie eine Manifest-Datei, um zu beginnen';

  @override
  String get hashVerifierManifestParseEmptyMessage =>
      'Keine Prüfsummeneinträge in dieser Datei gefunden';

  @override
  String hashVerifierLoadManifestFailedMessage(Object error) {
    return 'Manifest konnte nicht gelesen werden: $error';
  }

  @override
  String hashVerifierAutoAddedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien aus dem Tresorordner hinzugefügt',
      one: '1 Datei aus dem Tresorordner hinzugefügt',
      zero: 'Keine neuen Dateien gefunden',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierModeVault => 'Tresor';

  @override
  String get hashVerifierVaultPickerLabel => 'Tresor';

  @override
  String get hashVerifierVaultNoVaultsMessage =>
      'Derzeit sind keine Tresore eingebunden';

  @override
  String get hashVerifierCheckEntireVaultButton => 'Gesamten Tresor prüfen';

  @override
  String get hashVerifierVaultScanningLabel => 'Tresor wird durchsucht…';

  @override
  String hashVerifierVaultFilesDiscoveredLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien gefunden',
      one: '1 Datei gefunden',
      zero: 'Noch keine Dateien gefunden',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmTitle => 'Gesamten Tresor prüfen?';

  @override
  String hashVerifierVaultConfirmFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien',
      one: '1 Datei',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmWarning =>
      'Jede Datei in diesem Tresor wird gelesen.';

  @override
  String get hashVerifierVaultEmptyMessage =>
      'Dieser Tresor enthält keine zu prüfenden Dateien';

  @override
  String get hashVerifierVaultStartButton => 'Prüfung starten';

  @override
  String hashVerifierVaultHashingProgressLabel(Object current, Object total) {
    return 'Prüfe $current / $total';
  }

  @override
  String get hashVerifierVaultCompleteTitle => 'Tresorprüfung abgeschlossen';

  @override
  String hashVerifierVaultCompleteFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien geprüft',
      one: '1 Datei geprüft',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteBytesLabel(Object size) {
    return '$size verarbeitet';
  }

  @override
  String hashVerifierVaultCompleteSucceededLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count erfolgreich',
      one: '1 erfolgreich',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fehlgeschlagen',
      one: '1 fehlgeschlagen',
      zero: '0 fehlgeschlagen',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultElapsedLabel(Object time) {
    return 'Verstrichen: $time';
  }

  @override
  String get hashVerifierVaultCancelledMessage => 'Tresorprüfung abgebrochen.';

  @override
  String hashVerifierVaultFailedMessage(Object error) {
    return 'Tresorprüfung fehlgeschlagen: $error';
  }

  @override
  String get hashVerifierVaultNewCheckButton => 'Neue Prüfung';

  @override
  String get hashVerifierVaultActionComputeTitle => 'Gesamten Tresor berechnen';

  @override
  String get hashVerifierVaultActionComputeSubtitle =>
      'Jede Datei in einem Tresor hashen';

  @override
  String get hashVerifierVaultActionVerifyTitle => 'Gesamten Tresor überprüfen';

  @override
  String get hashVerifierVaultActionVerifySubtitle =>
      'Jede Datei in einem Tresor gegen ein geladenes Manifest prüfen';

  @override
  String get hashVerifierVaultChangeActionButton => 'Ändern';

  @override
  String get hashVerifierVaultVerifyButton => 'Gesamten Tresor überprüfen';

  @override
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage =>
      'Die Überprüfung eines gesamten Tresors erfordert ein aus einem Tresor geladenes Manifest.';

  @override
  String get duplicateFinderTargetLabel => 'Ziel-Tresor';

  @override
  String get duplicateFinderTargetAllVaults => 'Alle geöffneten Tresore';

  @override
  String get duplicateFinderStartScan => 'Scan starten';

  @override
  String get duplicateFinderCancelScan => 'Scan abbrechen';

  @override
  String get duplicateFinderRescan => 'Erneut scannen';

  @override
  String get duplicateFinderScanningStage1 =>
      'Stufe 1: Indizierung & Größengruppierung...';

  @override
  String get duplicateFinderScanningStage2 =>
      'Stufe 2: Teilweise Datei-Header werden geprüft...';

  @override
  String get duplicateFinderScanningStage3 =>
      'Stufe 3: Vollständige Byte-Hashes werden überprüft...';

  @override
  String get duplicateFinderScanComplete => 'Scan abgeschlossen';

  @override
  String get duplicateFinderNoDuplicatesTitle => 'Keine Duplikate gefunden';

  @override
  String get duplicateFinderNoDuplicatesMessage =>
      'Alle Dateien im/in den durchsuchten Tresor(en) enthalten eindeutige Byte-Inhalte.';

  @override
  String get duplicateFinderSelectRedundant => 'Überflüssige auswählen';

  @override
  String get duplicateFinderSelectAll => 'Alle auswählen';

  @override
  String get duplicateFinderDeselectAll => 'Auswahl aufheben';

  @override
  String get duplicateFinderOriginalLabel => 'Original';

  @override
  String get duplicateFinderDuplicateLabel => 'Duplikat';

  @override
  String get duplicateFinderConfirmDeleteTitle => 'Duplikat-Dateien löschen?';

  @override
  String get duplicateFinderSearchHint =>
      'Duplikate nach Dateiname oder Pfad suchen...';

  @override
  String get toolNotImplementedYetMessage =>
      'Dieses Werkzeug ist noch nicht mit der nativen Engine verbunden — schauen Sie in einem zukünftigen Update wieder vorbei.';

  @override
  String get splitJoinModeSplit => 'Teilen';

  @override
  String get splitJoinModeJoin => 'Zusammenführen';

  @override
  String get splitSourceFileLabel => 'Quelldatei';

  @override
  String get splitDestinationFolderLabel => 'Zielordner';

  @override
  String get splitChunkSizeLabel => 'Teilgröße';

  @override
  String get splitChunkSizeCustomLabel => 'Benutzerdefinierte Größe (MB)';

  @override
  String get splitChunkSizeFourMb => '4 MB';

  @override
  String get splitChunkSizeCloud8mb => '8 MB';

  @override
  String get splitChunkSizeCloud32mb => '32 MB';

  @override
  String get splitChunkSizeCloud => '100 MB';

  @override
  String get splitChunkSizeFat32 => '2 GB';

  @override
  String get splitChunkSizeFourGb => '4 GB';

  @override
  String get splitChunkSizeCustom => 'Benutzerdefiniert';

  @override
  String get splitContainerButton => 'Container teilen';

  @override
  String get joinFirstPartLabel => 'Erster Teil';

  @override
  String get joinOutputFileNameLabel => 'Ausgabe-Dateiname';

  @override
  String get joinContainerButton => 'Dateien zusammenführen';

  @override
  String get chooseFileButton => 'Datei auswählen';

  @override
  String get chooseFolderButton => 'Ordner auswählen';

  @override
  String get noFileSelectedLabel => 'Keine Datei ausgewählt';

  @override
  String get noFolderSelectedLabel => 'Kein Ordner ausgewählt';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage => 'Container erfolgreich geteilt';

  @override
  String get joinContainerSuccessMessage =>
      'Dateien erfolgreich zusammengeführt';

  @override
  String get cryptoDirectionEncrypt => 'Verschlüsseln';

  @override
  String get cryptoDirectionDecrypt => 'Entschlüsseln';

  @override
  String get singleFileCryptoInputFileLabel => 'Eingabedateien';

  @override
  String get singleFileCryptoCipherLabel => 'Verschlüsselung';

  @override
  String get singleFileCryptoDeleteOriginalLabel =>
      'Originaldateien nach der Verschlüsselung löschen';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien verschlüsseln',
      one: 'Datei verschlüsseln',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien entschlüsseln',
      one: 'Datei entschlüsseln',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Fertig — $count Dateien verarbeitet',
      one: 'Fertig',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return '$succeeded von $total Dateien verarbeitet — $failed fehlgeschlagen';
  }

  @override
  String get singleFileCryptoAddFilesButton => 'Dateien hinzufügen';

  @override
  String get singleFileCryptoClearFilesButton => 'Löschen';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Dateien ausgewählt',
      one: '1 Datei ausgewählt',
      zero: 'Keine Dateien ausgewählt',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return 'Datei $current von $total';
  }

  @override
  String get repairTargetStepTitle => 'Ziel auswählen';

  @override
  String get repairTargetUnmountedFileOption => 'Nicht eingebundene Datei';

  @override
  String get repairTargetUnmountedFileSubtitle =>
      'Einen Backup-Header auf einem noch nicht geöffneten Container wiederherstellen';

  @override
  String get repairTargetMountedVolumeSubtitle =>
      'Eine Dateisystemprüfung auf einem bereits geöffneten Tresor ausführen';

  @override
  String get repairNoMountedVolumes => 'Derzeit sind keine Tresore eingebunden';

  @override
  String get repairScanButton => 'Diagnosescan ausführen';

  @override
  String get repairChangeTargetButton => 'Ziel ändern';

  @override
  String get repairDiagnosisHealthy => 'Keine Probleme gefunden';

  @override
  String get repairDiagnosisHeaderCorrupted => 'Header beschädigt';

  @override
  String get repairDiagnosisFilesystemDirty =>
      'Dateisystem unsauber / unsauber ausgehängt';

  @override
  String get repairRestoreBackupHeaderButton =>
      'Backup-Header wiederherstellen';

  @override
  String get repairRunFilesystemCheckButton =>
      'Dateisystemprüfung & Reparatur ausführen';

  @override
  String get repairActionSucceededMessage =>
      'Reparatur erfolgreich abgeschlossen';

  @override
  String get repairActionFailedMessage =>
      'Reparaturaktion war nicht erfolgreich';

  @override
  String get storageAnalyzerTargetLabel => 'Volume';

  @override
  String get storageAnalyzerNoTargetsTitle => 'Nichts zu analysieren';

  @override
  String get storageAnalyzerNoTargetsMessage =>
      'Binden Sie zuerst einen Tresor ein und kommen Sie dann hierher zurück, um dessen Speicherbelegung zu sehen.';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return '$used von $total verwendet';
  }

  @override
  String get storageAnalyzerHeaviestFilesHeader => 'Größte Dateien';

  @override
  String get storageAnalyzerBreakdownHeader => 'Nach Dateityp';

  @override
  String get storageAnalyzerScanningMessage => 'Volume wird durchsucht…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return 'Scan nach $count Dateien vorzeitig gestoppt — Ergebnisse könnten unvollständig sein.';
  }

  @override
  String get storageAnalyzerNoFilesFound => 'Keine Dateien gefunden';

  @override
  String get storageCategoryImages => 'Bilder';

  @override
  String get storageCategoryVideos => 'Videos';

  @override
  String get storageCategoryAudio => 'Audio';

  @override
  String get storageCategoryDocuments => 'Dokumente';

  @override
  String get storageCategoryArchives => 'Archive';

  @override
  String get storageCategoryOther => 'Sonstiges';

  @override
  String get keyfilePassphraseGeneratorTitle =>
      'Schlüsseldatei- & Passphrasen-Generator';

  @override
  String get keyfilePassphraseGeneratorSubtitle =>
      'Diceware-Passphrasen, benutzerdefinierte Passwörter und Schlüsseldateien mit hoher Entropie erzeugen';

  @override
  String get tabPassphrase => 'Passphrase';

  @override
  String get tabKeyfile => 'Schlüsseldatei';

  @override
  String get modeDiceware => 'Diceware-Passphrase';

  @override
  String get modeCustomPassword => 'Benutzerdefiniertes Passwort';

  @override
  String get keyfileTypeBinary => 'Binäre Schlüsseldatei (.key)';

  @override
  String get keyfileTypeImage => 'Rauschbild-Schlüsseldatei (.png)';

  @override
  String get copyPassphraseSuccess =>
      'Passphrase in die sichere Zwischenablage kopiert';

  @override
  String get copyFingerprintSuccess =>
      'SHA-256-Fingerabdruck in die Zwischenablage kopiert';

  @override
  String get saveKeyfileToVault => 'In eingebundenem Tresor speichern';

  @override
  String get exportKeyfileToStorage => 'Auf Gerätespeicher exportieren';

  @override
  String get keyfileNoOpenVaultsMessage =>
      'Keine geöffneten Tresore verfügbar. Bitte binden Sie zuerst einen Tresor ein.';

  @override
  String get keyfileSelectDestinationVaultTitle => 'Zieltresor auswählen';

  @override
  String keyfileVolumeIdLabel(Object volId) {
    return 'Volume-ID: $volId';
  }

  @override
  String keyfileExportSuccessMessage(Object path) {
    return 'Schlüsseldatei nach $path exportiert';
  }

  @override
  String keyfileExportFailedMessage(Object error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String keyfileSavedToVaultMessage(Object vaultName, Object path) {
    return 'Schlüsseldatei in $vaultName gespeichert: $path';
  }

  @override
  String get keyfileWriteFailedMessage =>
      'Schlüsseldatei konnte nicht in den Tresor geschrieben werden';

  @override
  String keyfileSaveErrorMessage(Object error) {
    return 'Fehler beim Speichern im Tresor: $error';
  }

  @override
  String get passphraseGeneratedSecretLabel => 'Generiertes Geheimnis';

  @override
  String get copyToClipboardTooltip => 'In die Zwischenablage kopieren';

  @override
  String get generateNewTooltip => 'Neu generieren';

  @override
  String get passphraseStrengthWeak => 'Schwach';

  @override
  String get passphraseStrengthGood => 'Gut';

  @override
  String get passphraseStrengthStrong => 'Stark';

  @override
  String get passphraseStrengthUnbreakable => 'Unknackbar';

  @override
  String get passphraseCrackTimeInstant => '< 1 Sekunde';

  @override
  String get passphraseCrackTimeShort => 'Einige Tage / Monate';

  @override
  String get passphraseCrackTimeCenturies => 'Mehrere Jahrhunderte';

  @override
  String get passphraseCrackTimeMillionsOfYears => 'Millionen Jahre';

  @override
  String passphraseStrengthLabel(Object label) {
    return 'Stärke: $label';
  }

  @override
  String passphraseEntropyBitsLabel(Object bits) {
    return '$bits Bit Entropie';
  }

  @override
  String passphraseCrackTimeLabel(Object crackTime) {
    return 'Geschätzte Knackzeit: $crackTime';
  }

  @override
  String get dicewareOptionsTitle => 'EFF-Diceware-Optionen';

  @override
  String dicewareWordCountLabel(Object count) {
    return 'Wortanzahl: $count Wörter';
  }

  @override
  String dicewareWordCountBitsLabel(Object bits) {
    return '$bits Bit';
  }

  @override
  String dicewareWordCountSliderLabel(Object count) {
    return '$count Wörter';
  }

  @override
  String get dicewareWordSeparatorLabel => 'Worttrennzeichen';

  @override
  String get dicewareSeparatorHyphen => 'Bindestrich ( - )';

  @override
  String get dicewareSeparatorSpace => 'Leerzeichen (   )';

  @override
  String get dicewareSeparatorUnderscore => 'Unterstrich ( _ )';

  @override
  String get dicewareSeparatorDot => 'Punkt ( . )';

  @override
  String get dicewareSeparatorSlash => 'Schrägstrich ( / )';

  @override
  String get dicewareWordCasingLabel => 'Wort-Groß-/Kleinschreibung';

  @override
  String get dicewareCasingLowercase => 'kleinbuchstaben';

  @override
  String get dicewareCasingTitleCase => 'Titelform';

  @override
  String get dicewareCasingUppercase => 'GROSSBUCHSTABEN';

  @override
  String get dicewareAppendDigitLabel => 'Zufällige Ziffer anhängen (0-9)';

  @override
  String get dicewareAppendSymbolLabel => 'Zufälliges Symbol anhängen (!@#\$%)';

  @override
  String get customPasswordOptionsTitle =>
      'Optionen für benutzerdefiniertes Passwort';

  @override
  String customPasswordLengthLabel(Object length) {
    return 'Länge: $length Zeichen';
  }

  @override
  String customPasswordLengthSliderLabel(Object length) {
    return '$length Zeichen';
  }

  @override
  String get customPasswordUppercaseLabel => 'Großbuchstaben (A-Z)';

  @override
  String get customPasswordLowercaseLabel => 'Kleinbuchstaben (a-z)';

  @override
  String get customPasswordNumbersLabel => 'Zahlen (0-9)';

  @override
  String get customPasswordSymbolsLabel => 'Symbole (!@#\$%^&*)';

  @override
  String get customPasswordExcludeAmbiguousLabel =>
      'Mehrdeutige ausschließen (1, l, I, 0, O)';

  @override
  String get keyfileBinarySizeTitle => 'Binäre Schlüsseldateigröße';

  @override
  String get keyfileImageResolutionTitle => 'Rauschbild-Auflösung';

  @override
  String get keyfilePresetBytes64 => '64 Byte (VeraCrypt-Standard)';

  @override
  String get keyfilePresetBytes256 => '256 Byte';

  @override
  String get keyfilePresetBytes2048 => '2 KB';

  @override
  String get keyfilePresetBytes64kb => '64 KB';

  @override
  String get keyfilePresetBytes1mb => '1 MB (Maximale Grenze)';

  @override
  String get keyfilePresetRes64 => '64 x 64 Pixel (~16 KB)';

  @override
  String get keyfilePresetRes256 => '256 x 256 Pixel (~256 KB)';

  @override
  String get keyfilePresetRes512 => '512 x 512 Pixel (~1 MB)';

  @override
  String get keyfileGenerateNewTooltip => 'Neue Schlüsseldatei generieren';

  @override
  String keyfileSizeLabel(Object size) {
    return 'Größe: $size';
  }

  @override
  String get keyfileFingerprintLabel => 'SHA-256-Fingerabdruck';

  @override
  String get keyfileCopyFingerprintTooltip => 'Fingerabdruck kopieren';

  @override
  String get duplicateFinderNoVaultsTitle => 'Keine eingebundenen Tresore';

  @override
  String get duplicateFinderNoVaultsMessage =>
      'Binden Sie mindestens einen Tresor-Container ein, um nach Duplikaten zu suchen.';

  @override
  String duplicateFinderConfirmDeleteMessage(Object count, Object size) {
    return 'Sind Sie sicher, dass Sie $count Duplikat-Datei(en) ($size) dauerhaft aus Ihrem/Ihren Tresor(en) löschen möchten? Diese Aktion kann nicht rückgängig gemacht werden.';
  }

  @override
  String get duplicateFinderDeletePermanentlyButton => 'Dauerhaft löschen';

  @override
  String duplicateFinderDeleteSuccessMessage(Object count) {
    return '$count Duplikat-Datei(en) erfolgreich gelöscht.';
  }

  @override
  String get duplicateFinderIntroTitle => '3-Stufen-Byte-Gleichheitssuche';

  @override
  String get duplicateFinderIntroSubtitle =>
      'Exakt identische Inhalte unabhängig von Dateinamen erkennen.';

  @override
  String get duplicateFinderStagesDescription =>
      '• Stufe 1: Größengruppierung (sofortiger Metadaten-Durchlauf)\n• Stufe 2: Teilweise Header-Prüfung (16-KB-SHA-256-Header)\n• Stufe 3: Vollständige Hash-Verifizierung (exakte SHA-256-Byte-Übereinstimmung)';

  @override
  String get duplicateFinderScanningVaultFallback =>
      'Tresor wird durchsucht...';

  @override
  String duplicateFinderProcessingFileLabel(Object fileName) {
    return 'Verarbeitung: $fileName';
  }

  @override
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  ) {
    return 'Durchsuchte Dateien: $scanned | Duplikate gefunden: $groups Gruppen ($saved)';
  }

  @override
  String duplicateFinderGroupsFoundLabel(Object count) {
    return '$count Duplikatgruppen gefunden';
  }

  @override
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved) {
    return '$copies Kopien gefunden • $saved Speicherplatz sparen';
  }

  @override
  String duplicateFinderVaultsSelectedLabel(Object count) {
    return '$count Tresore ausgewählt';
  }

  @override
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  ) {
    return 'Gruppe $groupIndex: $size ($count Kopien gefunden)';
  }

  @override
  String duplicateFinderRecoverableSpaceLabel(Object size) {
    return 'Wiederherstellbarer Speicherplatz: $size';
  }

  @override
  String get duplicateFinderPreviewFileTooltip => 'Datei-Vorschau';

  @override
  String duplicateFinderPreviewFailedMessage(Object fileName) {
    return 'Dateivorschau für $fileName konnte nicht geöffnet werden';
  }

  @override
  String duplicateFinderPreviewErrorMessage(Object error) {
    return 'Fehler bei der Dateivorschau: $error';
  }

  @override
  String duplicateFinderFilesSelectedLabel(Object count) {
    return '$count Dateien ausgewählt';
  }

  @override
  String duplicateFinderBytesToBeFreedLabel(Object size) {
    return '$size werden freigegeben';
  }

  @override
  String duplicateFinderDeleteSelectedButton(Object count) {
    return 'Ausgewählte löschen ($count)';
  }

  @override
  String get vaultBrowserSwitchVaultTooltip => 'Tresor wechseln';

  @override
  String get vaultBrowserRootFolderLabel => 'Stammordner';

  @override
  String vaultFilePickerTitle(Object vaultName) {
    return 'Dateien auswählen ($vaultName)';
  }

  @override
  String get vaultFilePickerEmptyMessage => 'Ordner ist leer';

  @override
  String vaultFilePickerConfirmButton(Object count) {
    return '$count Datei(en) auswählen';
  }

  @override
  String vaultFolderPickerTitle(Object vaultName) {
    return 'Ordner auswählen ($vaultName)';
  }

  @override
  String get vaultFolderPickerEmptyMessage => 'Keine Unterordner vorhanden';

  @override
  String get vaultFolderPickerRootLabel => 'Stammverzeichnis';

  @override
  String get vaultFolderPickerConfirmRootButton => 'Stammordner auswählen';

  @override
  String vaultFolderPickerConfirmNamedButton(Object folderName) {
    return '\"$folderName\" auswählen';
  }

  @override
  String get singleFileCryptoSelectInputTitle => 'Eingabedateien auswählen';

  @override
  String get singleFileCryptoFromDeviceTitle => 'Vom Gerätespeicher';

  @override
  String get singleFileCryptoFromDeviceSubtitle =>
      'Dateien über die Systemdateiauswahl vom Gerät auswählen';

  @override
  String get singleFileCryptoFromVaultTitle => 'Aus eingebundenem Tresor';

  @override
  String get singleFileCryptoFromVaultSubtitle =>
      'Dateien aus einem geöffneten verschlüsselten Container auswählen';

  @override
  String get singleFileCryptoSelectDestinationTitle => 'Zielordner auswählen';

  @override
  String get singleFileCryptoDeviceFolderTitle => 'Ordner im Gerätespeicher';

  @override
  String get singleFileCryptoDeviceFolderSubtitle =>
      'Ausgabe in einem Ordner auf dem Gerätespeicher speichern';

  @override
  String get singleFileCryptoVaultFolderTitle =>
      'Ordner im eingebundenen Tresor';

  @override
  String get singleFileCryptoVaultFolderSubtitle =>
      'Ausgabe innerhalb eines geöffneten verschlüsselten Containers speichern';

  @override
  String get toolsSectionBackupSync => 'Sicherung & Synchronisierung';

  @override
  String get toolVaultSyncTitle => 'Tresor-Synchronisierung';

  @override
  String get toolVaultSyncSubtitle =>
      'Zwei Tresore vergleichen und fehlende oder neuere Dateien übertragen';

  @override
  String get vaultSyncNoVaultsTitle => 'Keine Tresore eingebunden';

  @override
  String get vaultSyncNoVaultsMessage =>
      'Binden Sie mindestens einen Tresor ein, um dessen Dateien zu vergleichen und zu synchronisieren.';

  @override
  String get vaultSyncLeftLabel => 'Links';

  @override
  String get vaultSyncRightLabel => 'Rechts';

  @override
  String get vaultSyncTapToSelect => 'Tippen, um Tresor & Ordner auszuwählen';

  @override
  String get vaultSyncSwapTooltip => 'Links und Rechts vertauschen';

  @override
  String get vaultSyncSameLocationWarning =>
      'Links und Rechts müssen unterschiedliche Ordner sein.';

  @override
  String get vaultSyncIntroTitle => 'Zwei Tresore vergleichen';

  @override
  String get vaultSyncIntroSubtitle =>
      'Wählen Sie einen linken und rechten Tresor (oder zwei Ordner im selben Tresor), um zu sehen, was auf jeder Seite fehlt, geändert oder neuer ist.';

  @override
  String get vaultSyncCompareButton => 'Vergleichen';

  @override
  String get vaultSyncComparingLabel => 'Tresore werden verglichen…';

  @override
  String vaultSyncCompareStatsLabel(Object dirs, Object entries) {
    return 'Durchsuchte Ordner: $dirs | Unterschiede gefunden: $entries';
  }

  @override
  String get vaultSyncCancelCompareButton => 'Abbrechen';

  @override
  String get vaultSyncInSyncTitle => 'Bereits synchron';

  @override
  String vaultSyncInSyncMessage(Object count) {
    return 'Alle $count übereinstimmenden Dateien sind auf beiden Seiten identisch.';
  }

  @override
  String get vaultSyncRecompareButton => 'Erneut vergleichen';

  @override
  String vaultSyncDifferencesFoundLabel(Object count) {
    return '$count Unterschiede gefunden';
  }

  @override
  String vaultSyncInSyncCountLabel(Object count) {
    return '$count Dateien stimmen bereits auf beiden Seiten überein';
  }

  @override
  String vaultSyncBadgeOnlyLeft(Object count) {
    return '$count nur links';
  }

  @override
  String vaultSyncBadgeOnlyRight(Object count) {
    return '$count nur rechts';
  }

  @override
  String vaultSyncBadgeLeftNewer(Object count) {
    return '$count neuer links';
  }

  @override
  String vaultSyncBadgeRightNewer(Object count) {
    return '$count neuer rechts';
  }

  @override
  String vaultSyncBadgeConflicts(Object count) {
    return '$count müssen überprüft werden';
  }

  @override
  String get vaultSyncDirectionLabel => 'Synchronisierungsrichtung';

  @override
  String get vaultSyncDirectionTwoWay => 'Beidseitig (empfohlen)';

  @override
  String get vaultSyncDirectionTwoWaySubtitle =>
      'Kopiert jede Datei auf die Seite, wo sie fehlt oder eine ältere Kopie vorhanden ist';

  @override
  String get vaultSyncDirectionLeftToRight => 'Links → Rechts (einseitig)';

  @override
  String get vaultSyncDirectionLeftToRightSubtitle =>
      'Überträgt neue und aktualisierte Dateien von Links nach Rechts; ändert Links nie';

  @override
  String get vaultSyncDirectionRightToLeft => 'Rechts → Links (einseitig)';

  @override
  String get vaultSyncDirectionRightToLeftSubtitle =>
      'Überträgt neue und aktualisierte Dateien von Rechts nach Links; ändert Rechts nie';

  @override
  String get vaultSyncSearchHint => 'Unterschiede durchsuchen';

  @override
  String get vaultSyncStatusOnlyLeft => 'Nur links';

  @override
  String get vaultSyncStatusOnlyRight => 'Nur rechts';

  @override
  String get vaultSyncStatusLeftNewer => 'Links neuer';

  @override
  String get vaultSyncStatusRightNewer => 'Rechts neuer';

  @override
  String get vaultSyncStatusConflict => 'Überprüfung nötig';

  @override
  String get vaultSyncStatusTypeMismatch => 'Typ-Konflikt';

  @override
  String get vaultSyncFolderOnlyLeftDetail => 'Ordner — nur links';

  @override
  String get vaultSyncFolderOnlyRightDetail => 'Ordner — nur rechts';

  @override
  String vaultSyncBothSidesDetail(
    Object leftSize,
    Object leftDate,
    Object rightSize,
    Object rightDate,
  ) {
    return 'L: $leftSize · $leftDate  →  R: $rightSize · $rightDate';
  }

  @override
  String get vaultSyncTypeMismatchTooltip =>
      'Eine Datei auf der einen Seite und ein Ordner auf der anderen — manuell im Dateibrowser lösen';

  @override
  String get vaultSyncChangeActionTooltip => 'Synchronisierungsaktion ändern';

  @override
  String get vaultSyncActionCopyToRight => 'Kopieren → Rechts';

  @override
  String get vaultSyncActionCopyToLeft => 'Kopieren → Links';

  @override
  String get vaultSyncActionSkip => 'Überspringen';

  @override
  String vaultSyncChangesQueuedLabel(Object count) {
    return '$count Änderungen in Warteschlange';
  }

  @override
  String get vaultSyncSyncNowButton => 'Jetzt synchronisieren';

  @override
  String get vaultSyncConfirmTitle => 'Synchronisierung starten?';

  @override
  String vaultSyncConfirmMessage(Object count, Object bytes) {
    return 'Dadurch werden $count Elemente ($bytes insgesamt) zwischen den beiden Seiten kopiert. Vorhandene Dateien mit demselben Namen werden überschrieben.';
  }

  @override
  String vaultSyncStartedMessage(Object count) {
    return 'Synchronisierung gestartet — $count Elemente in Warteschlange';
  }

  @override
  String vaultSyncPickLocationTitle(Object side) {
    return '$side-Tresor & Ordner auswählen';
  }

  @override
  String get vaultSyncReadOnlyBadge => 'Schreibgeschützt';

  @override
  String get vaultSyncReadOnlyTooltip =>
      'Dieser Tresor ist schreibgeschützt eingebunden — Dateien können nicht hineinkopiert werden';

  @override
  String get vaultSyncSyncingButton => 'Wird synchronisiert…';

  @override
  String get vaultSyncNotEnoughSpaceTitle => 'Nicht genug Speicherplatz';

  @override
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  ) {
    return 'Nicht genug Speicherplatz auf $side — benötigt $required, nur $free frei.';
  }

  @override
  String get removeMasterPasswordTitle => 'Master-Passwort entfernen';

  @override
  String get confirmRemoveMasterPasswordMessage =>
      'Geben Sie Ihr aktuelles Master-Passwort ein, um das Entfernen zu bestätigen:';

  @override
  String get authenticateToRemoveMasterPassword =>
      'Authentifizieren, um das Master-Passwort zu entfernen';

  @override
  String get incorrectPassword => 'Falsches Passwort';

  @override
  String get rememberPerFolderLayoutLabel => 'Layout pro Ordner merken';

  @override
  String get rememberPerFolderLayoutDesc =>
      'Separates Ansichtslayout (Liste, Raster, Mauerwerk) für jeden Ordner speichern';

  @override
  String get fileInfoAction => 'Info';

  @override
  String get automationSectionHeader => 'Automatisierung';

  @override
  String get automationTileTitle => 'Automatisierung';

  @override
  String get automationTileSubtitle =>
      'Automatisierung darf diesen Tresor entsperren, sperren, Dateien importieren oder exportieren';

  @override
  String get automationScreenTitle => 'Automatisierung (Tasker / MacroDroid)';

  @override
  String get automationUsbUnsupportedMessage =>
      'Automatisierung ist für USB-angeschlossene Tresore noch nicht verfügbar.';

  @override
  String get automationThisVaultSectionHeader => 'Dieser Tresor';

  @override
  String get automationAccessLabel => 'Automatisierungszugriff';

  @override
  String get automationPasswordSectionHeader => 'Automatisierungspasswort';

  @override
  String get automationPasswordStoredHint =>
      'Für unbeaufsichtigte UNLOCK_VAULT-Aufrufe ist ein Passwort gespeichert. Speichern Sie ein neues, um es zu ersetzen, oder speichern Sie ein leeres Feld, um es zu löschen — die Automatisierung kann stattdessen auch direkt ein Passwort im Broadcast übergeben.';

  @override
  String get automationPasswordNotStoredHint =>
      'Optional. Ohne gespeichertes Passwort muss die Automatisierung bei jedem UNLOCK_VAULT-Broadcast eines angeben.';

  @override
  String get automationNewPasswordFieldLabel => 'Neues Passwort';

  @override
  String get automationPasswordFieldLabel => 'Passwort';

  @override
  String get automationClearPasswordButton => 'Gespeichertes Passwort löschen';

  @override
  String get automationSavePasswordButton => 'Passwort speichern';

  @override
  String get automationTokenSectionHeader => 'API-Token';

  @override
  String get automationTokenDescription =>
      'Wird von jedem Tresor mit aktiviertem Automatisierungszugriff gemeinsam genutzt. Die Automatisierung sendet dieses Token bei jedem Broadcast zurück; ein falsches oder fehlendes Token wird stillschweigend ignoriert, nicht als Fehler behandelt.';

  @override
  String get automationRegenerateTokenButton => 'Token neu generieren';

  @override
  String get automationRegenerateTokenDialogTitle => 'Token neu generieren?';

  @override
  String get automationRegenerateTokenDialogMessage =>
      'Jedes Tasker-Profil oder MacroDroid-Makro, das das aktuelle Token verwendet, funktioniert stillschweigend nicht mehr, bis Sie es mit dem neuen aktualisieren.';

  @override
  String get automationRegenerateConfirmLabel => 'Neu generieren';

  @override
  String get automationTokenRegeneratedMessage => 'Token neu generiert.';

  @override
  String get automationRegenerateTokenFailedMessage =>
      'Das Token konnte nicht neu generiert werden.';

  @override
  String get automationUpdateSettingsFailedMessage =>
      'Automatisierungseinstellungen konnten nicht aktualisiert werden.';

  @override
  String get automationSavePasswordFailedMessage =>
      'Das Automatisierungspasswort konnte nicht gespeichert werden.';

  @override
  String get automationPasswordClearedMessage =>
      'Automatisierungspasswort gelöscht.';

  @override
  String get automationPasswordSavedMessage =>
      'Automatisierungspasswort gespeichert.';

  @override
  String get automationConfigSectionHeader => 'Konfigurationszeichenfolgen';

  @override
  String get automationConfigIntro =>
      'Tippen Sie auf einen Wert unten, um ihn zu kopieren. Verwenden Sie in Tasker eine Aktion „Send Intent“; in MacroDroid eine Aktion „Intent“ mit Intent-Typ auf Broadcast — nicht Activity oder Service, was mit „unable to find explicit activity class“ fehlschlägt.';

  @override
  String get automationConfigPackageLabel => 'Paketname';

  @override
  String get automationConfigClassLabel => 'Receiver-Klasse';

  @override
  String get automationConfigVaultUriLabel => 'URI dieses Tresors';

  @override
  String get automationConfigActionsSectionHeader => 'Broadcast-Aktionen';

  @override
  String get automationActionUnlockLabel => 'Tresor entsperren';

  @override
  String get automationActionLockLabel => 'Tresor sperren';

  @override
  String get automationActionImportLabel => 'Datei importieren';

  @override
  String get automationActionExportLabel => 'Datei exportieren';

  @override
  String get automationActionWipeLabel => 'Datei löschen (Wipe)';

  @override
  String get automationDocCommentFootnote =>
      'Alle Extras und der Ergebnis-Broadcast-Vertrag sind in VaultAutomationReceiver.kt dokumentiert.';

  @override
  String get automationTierOffLabel => 'Aus';

  @override
  String get automationTierOffSubtitle =>
      'Automatisierung kann diesen Tresor nicht berühren';

  @override
  String get automationTierLifecycleLabel => 'Nur entsperren/sperren';

  @override
  String get automationTierLifecycleSubtitle =>
      'Automatisierung darf diesen Tresor nur entsperren und sperren, sonst nichts';

  @override
  String get automationTierFullLabel =>
      'Entsperren/Sperren + Datei-Import/-Export';

  @override
  String get automationTierFullSubtitle =>
      'Automatisierung darf zusätzlich Dateien importieren und exportieren, solange dieser Tresor entsperrt ist';

  @override
  String get automationTutorialLinkLabel =>
      'Vollständiges Schritt-für-Schritt-Tutorial lesen';

  @override
  String get showHiddenFilesLabel => 'Versteckte Dateien anzeigen';

  @override
  String get showHiddenFilesDesc =>
      'Versteckte Dateien und Systemordner anzeigen';

  @override
  String get dontAskAgain => 'Nicht erneut fragen';

  @override
  String get deleteAfterImportLabel => 'Dateien nach dem Import löschen';

  @override
  String get deleteAfterImportModeAsk => 'Jedes Mal fragen';

  @override
  String get deleteAfterImportModeAskSubtitle =>
      'Nach dem Import fragen, ob die Originaldateien gelöscht werden sollen';

  @override
  String get deleteAfterImportModeKeep => 'Originale behalten (nicht löschen)';

  @override
  String get deleteAfterImportModeKeepSubtitle =>
      'Originaldateien nie löschen und nicht nachfragen';

  @override
  String get deleteAfterImportModeDelete => 'Originale automatisch löschen';

  @override
  String get deleteAfterImportModeDeleteSubtitle =>
      'Originaldateien nach dem Import automatisch vom Gerät löschen';

  @override
  String get wizardBackButton => 'Zurück';

  @override
  String get wizardNextButton => 'Weiter';

  @override
  String get wizardStepTypeTitle => 'Typ';

  @override
  String get wizardStepBasicInfoTitle => 'Grundlagen';

  @override
  String get wizardStepAdvancedTitle => 'Erweitert';

  @override
  String get wizardStepReviewTitle => 'Überprüfung';

  @override
  String get wizardCreateTypePrompt => 'Was möchten Sie erstellen?';

  @override
  String get wizardChooseFormatPrompt => 'Container-Format wählen';

  @override
  String get wizardEncryptionDetailsRowTitle => 'Verschlüsselungsdetails';

  @override
  String get wizardHiddenVolumeRowSubtitleConfigured =>
      'Konfiguriert — zum Überprüfen tippen';

  @override
  String get wizardHiddenVolumeRowSubtitleNeedsSetup => 'Zum Einrichten tippen';

  @override
  String get wizardSummaryTitle => 'Zusammenfassung';

  @override
  String get wizardSummaryPasswordLabel => 'Passwort';

  @override
  String get wizardPasswordSetValue => 'Festgelegt';

  @override
  String get wizardPasswordNotSetValue =>
      'Nicht festgelegt (Schlüsseldateien werden verwendet)';

  @override
  String get wizardSummaryKeyfilesLabel => 'Schlüsseldateien';

  @override
  String get wizardSummaryPimDefaultValue => 'Standard';

  @override
  String get wizardSummaryPimLabel => 'PIM';

  @override
  String get wizardSummaryDriveLabel => 'USB-Laufwerk';

  @override
  String get sectionKeyStorageIntegration =>
      'Schlüsselspeicher & Systemzugriff';

  @override
  String get sectionMaskMode => 'Maskenmodus';

  @override
  String get advancedOptionsTitle => 'Erweiterte Optionen';

  @override
  String get audioTrackTitle => 'Audiospur';

  @override
  String get noAudioTracksAvailable => 'Keine Audiospuren verfügbar';

  @override
  String trackNumberLabel(int number) {
    return 'Spur $number';
  }

  @override
  String subtitleTrackNumberLabel(int number) {
    return 'Untertitel $number';
  }

  @override
  String get offLabel => 'Aus';

  @override
  String get externalSubtitlesLabel => 'Externe Untertitel (.srt/.vtt)';

  @override
  String get externalLabel => 'Extern';

  @override
  String get subtitleSizeLabel => 'Größe';

  @override
  String get subtitleSizeSmall => 'S';

  @override
  String get subtitleSizeMedium => 'M';

  @override
  String get subtitleSizeLarge => 'L';

  @override
  String get subtitleSizeExtraLarge => 'XL';

  @override
  String get subtitlePositionLabel => 'Position';

  @override
  String get subtitlePositionBottom => 'Unten';

  @override
  String get subtitlePositionLower => 'Unteres Drittel';

  @override
  String get subtitlePositionCenter => 'Mitte';

  @override
  String get subtitlePositionTop => 'Oben';

  @override
  String get editImageAction => 'Bild bearbeiten';

  @override
  String get imageEditorUnsupportedFormatMessage =>
      'Dieses Bildformat wird für die Bearbeitung nicht unterstützt.';

  @override
  String get cropToolLabel => 'Zuschneiden';

  @override
  String get drawToolLabel => 'Zeichnen';

  @override
  String get textToolLabel => 'Text';

  @override
  String get redactToolLabel => 'Schwärzen';

  @override
  String get rotateLeftTooltip => 'Nach links drehen';

  @override
  String get rotateRightTooltip => 'Nach rechts drehen';

  @override
  String get cropAspectFreeLabel => 'Frei';

  @override
  String get cropAspectSquareLabel => 'Quadratisch';

  @override
  String get cropAspectOriginalLabel => 'Original';

  @override
  String get applyCropTooltip => 'Zuschnitt anwenden';

  @override
  String get annotationColorTooltip => 'Farbe';

  @override
  String get annotationStrokeWidthTooltip => 'Strichstärke';

  @override
  String get clearAnnotationsTooltip => 'Alle Anmerkungen entfernen';

  @override
  String get resetImageTooltip => 'Auf Original zurücksetzen';

  @override
  String get resetImageConfirmTitle => 'Bild zurücksetzen?';

  @override
  String get resetImageConfirmMessage =>
      'Dadurch werden alle in dieser Sitzung vorgenommenen Zuschnitte und Zeichnungen verworfen.';

  @override
  String get addTextAnnotationTitle => 'Text hinzufügen';

  @override
  String get addTextAnnotationHint => 'Etwas eingeben…';

  @override
  String get textToolHint => 'Zum Hinzufügen von Text auf das Bild tippen';

  @override
  String get saveImageSheetTitle => 'Änderungen speichern';

  @override
  String get saveAsNewFileOption => 'Als neue Datei speichern';

  @override
  String get saveAsNewFileDescription => 'Original bleibt unverändert';

  @override
  String get overwriteOriginalOption => 'Original überschreiben';

  @override
  String get overwriteOriginalDescription => 'Ersetzt die Originaldatei';

  @override
  String get newFileNameLabel => 'Dateiname';

  @override
  String get imageEditorPngNoteMessage =>
      'Bearbeitete Bilder werden als PNG gespeichert.';

  @override
  String get imageSavedMessage => 'Bild gespeichert';

  @override
  String imageSaveFailedMessage(String error) {
    return 'Bild konnte nicht gespeichert werden: $error';
  }

  @override
  String get advancedRenameButton => 'Erweitert';

  @override
  String get advancedRenameBatchTitle => 'Stapel-Umbenennung';

  @override
  String get advancedRenameRulesTab => 'Regeln';

  @override
  String advancedRenamePreviewTab(int count) {
    return 'Vorschau ($count)';
  }

  @override
  String get advancedRenameSearchReplaceTitle => 'Suchen & Ersetzen';

  @override
  String get advancedRenameFindTextLabel => 'Text suchen';

  @override
  String get advancedRenameFindTextHint =>
      'Text oder Muster zum Abgleichen eingeben...';

  @override
  String get advancedRenameReplaceWithLabel => 'Ersetzen durch';

  @override
  String get advancedRenameReplaceWithHint => 'Neuer Text oder Variablen...';

  @override
  String get advancedRenameInsertVariableTooltip =>
      'Dynamisches Variablen-Token einfügen';

  @override
  String get advancedRenameDateTimeTokens => 'DATUMS- & ZEITTOKEN';

  @override
  String advancedRenameStandardDate(String token) {
    return 'Standarddatum ($token)';
  }

  @override
  String advancedRenameYearFourDigit(String token) {
    return 'Jahr 4-stellig ($token)';
  }

  @override
  String advancedRenameMonth(String token) {
    return 'Monat ($token)';
  }

  @override
  String advancedRenameDayOfMonth(String token) {
    return 'Tag des Monats ($token)';
  }

  @override
  String advancedRenameTime(String token) {
    return 'Zeit ($token)';
  }

  @override
  String get advancedRenameDynamicIdentifiers => 'DYNAMISCHE KENNUNGEN';

  @override
  String advancedRenameUniqueUuid(String token) {
    return 'Eindeutige UUID v4 ($token)';
  }

  @override
  String get advancedRenameRandomAlphanumeric =>
      'Zufällig alphanumerisch (8 Zeichen)';

  @override
  String get advancedRenameRandomDigits => 'Zufällige Ziffern (6 Ziffern)';

  @override
  String get advancedRenameEmbeddedCounter => 'EINGEBETTETER ZÄHLER';

  @override
  String advancedRenamePaddedCounter(String token) {
    return 'Aufgefüllter Zähler ($token)';
  }

  @override
  String get advancedRenameRegex => 'Regex';

  @override
  String get advancedRenameMatchCase => 'Groß-/Kleinschreibung beachten';

  @override
  String get advancedRenameAllOccurrences => 'Alle Vorkommen';

  @override
  String get advancedRenameScopeFormatting => 'Bereich & Formatierung';

  @override
  String get advancedRenameApplyChangesTo => 'Änderungen anwenden auf';

  @override
  String get advancedRenameFilename => 'Dateiname';

  @override
  String get advancedRenameExtension => 'Erweiterung';

  @override
  String get advancedRenameBoth => 'Beides';

  @override
  String get advancedRenameCaseTransformation => 'Groß-/Kleinschreibung';

  @override
  String get advancedRenameNoChange => 'Keine Änderung';

  @override
  String get advancedRenameLowercase => 'kleinbuchstaben';

  @override
  String get advancedRenameUppercase => 'GROSSBUCHSTABEN';

  @override
  String get advancedRenameTitleCase => 'Wortbeginn Groß';

  @override
  String get advancedRenameCapitalize => 'Großschreiben';

  @override
  String get advancedRenameSequentialCounter => 'Fortlaufender Zähler';

  @override
  String get advancedRenameCounterDescription =>
      'Fortlaufende Nummern anhängen oder voranstellen';

  @override
  String get advancedRenameSuffix => 'Suffix (Ende)';

  @override
  String get advancedRenamePrefix => 'Präfix (Anfang)';

  @override
  String get advancedRenameStartAt => 'Beginnen bei';

  @override
  String get advancedRenameDigits => 'Ziffern';

  @override
  String get advancedRenameDigitsHint => 'z. B. 2 (01)';

  @override
  String get advancedRenameSeparator => 'Trennzeichen';

  @override
  String get advancedRenameSeparatorHint => '_ or -';

  @override
  String get advancedRenameLivePreview => 'Live-Vorschau';

  @override
  String get advancedRenameDeselect => 'Auswahl aufheben';

  @override
  String get advancedRenameSelectAll => 'Alle auswählen';

  @override
  String get advancedRenameNoFilesSelected => 'Keine Dateien ausgewählt';

  @override
  String get advancedRenameNameConflictDetected => 'Namenskonflikt erkannt';

  @override
  String get advancedRenameCheckPreviewToFix =>
      'Prüfen Sie den Vorschau-Tab zur Behebung';

  @override
  String get advancedRenameReadyToRename => 'Bereit zum Umbenennen';

  @override
  String get advancedRenameErrorsDetected => 'Fehler erkannt';

  @override
  String advancedRenameApply(int count) {
    return 'Anwenden ($count)';
  }

  @override
  String get advancedRenameNameCollisionWithinBatch =>
      'Namenskonflikt innerhalb des Stapels.';

  @override
  String get advancedRenameCollidesWithUnselectedFile =>
      'Kollidiert mit einer nicht ausgewählten Datei.';

  @override
  String advancedRenameReadyCount(int valid, int total) {
    return '$valid bereit zum Umbenennen (von $total)';
  }

  @override
  String advancedRenameReadyOfTotal(int valid, int total) {
    return '$valid von $total bereit';
  }

  @override
  String advancedRenameRenamedItems(int succeeded, int failed) {
    return '$succeeded Elemente umbenannt ($failed fehlgeschlagen).';
  }

  @override
  String advancedRenameSuccessfullyRenamed(int count) {
    return '$count Elemente erfolgreich umbenannt.';
  }

  @override
  String get advancedRenameMonthsFull =>
      'Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember';

  @override
  String get advancedRenameMonthsAbbr =>
      'Jan|Feb|Mär|Apr|Mai|Jun|Jul|Aug|Sep|Okt|Nov|Dez';

  @override
  String get advancedRenameDaysFull =>
      'Montag|Dienstag|Mittwoch|Donnerstag|Freitag|Samstag|Sonntag';

  @override
  String get advancedRenameDaysAbbr => 'Mo|Di|Mi|Do|Fr|Sa|So';

  @override
  String get advancedRenameResolveConflicts =>
      'Namenskonflikte vor dem Anwenden lösen';

  @override
  String advancedRenameChangedCount(int changed, int total) {
    return '$changed von $total';
  }

  @override
  String get automationKeyfilesPimSectionHeader => 'Schlüsseldateien & PIM';

  @override
  String get automationKeyfilesPimDescription =>
      'Wird zusammen mit dem oben genannten Automatisierungspasswort gespeichert und für UNLOCK_VAULT genauso verwendet – für einen VeraCrypt-/LUKS-Tresor, der normalerweise mit einer Schlüsseldatei und/oder einem nicht standardmäßigen PIM statt nur mit einem Passwort entsperrt wird.';

  @override
  String get automationSavePimButton => 'PIM speichern';

  @override
  String get automationCameraSectionHeader => 'Kamera-Automatisierung';

  @override
  String get automationCameraDescription =>
      'Ermöglicht der Automatisierung, TAKE_PHOTO / START_RECORDING / STOP_RECORDING für diesen Tresor auszulösen. Standardmäßig auch bei vollem Zugriff deaktiviert – anders als Datei-Import/-Export benötigt ein Foto überhaupt keine Anzeige auf dem Bildschirm, daher ist dies eine separate, ausdrückliche Freigabe.';

  @override
  String get automationAllowCameraCapture => 'Kameraaufnahme zulassen';

  @override
  String get automationPimSavedMessage => 'PIM gespeichert';

  @override
  String get automationActionImportFolderLabel => 'Ordner importieren';

  @override
  String get automationActionExportFolderLabel => 'Ordner exportieren';

  @override
  String get automationActionTakePhotoLabel => 'Foto aufnehmen';

  @override
  String get automationActionStartRecordingLabel => 'Aufnahme starten';

  @override
  String get automationActionStopRecordingLabel => 'Aufnahme stoppen';

  @override
  String get filePropertiesSectionHeader => 'DATEIEIGENSCHAFTEN';

  @override
  String get fullPathLabel => 'Vollständiger Pfad';

  @override
  String get sizeLabel => 'Größe';

  @override
  String get modifiedLabel => 'Geändert';

  @override
  String get vaultLabel => 'Tresor';

  @override
  String get mediaDimensionsSectionHeader => 'MEDIEN & ABMESSUNGEN';

  @override
  String get resolutionLabel => 'Auflösung';

  @override
  String get aspectRatioLabel => 'Seitenverhältnis';

  @override
  String get formatLabel => 'Format';

  @override
  String get exifCameraDataSectionHeader => 'EXIF- & KAMERADATEN';

  @override
  String get cameraLabel => 'Kamera';

  @override
  String get lensLabel => 'Objektiv';

  @override
  String get dateTakenLabel => 'Aufnahmedatum';

  @override
  String get shutterSpeedLabel => 'Verschlusszeit';

  @override
  String get apertureLabel => 'Blende';

  @override
  String get isoLabel => 'ISO';

  @override
  String get focalLengthLabel => 'Brennweite';

  @override
  String get flashLabel => 'Blitz';

  @override
  String get softwareLabel => 'Software';

  @override
  String get gpsLocationLabel => 'GPS-Standort';

  @override
  String get integrityChecksumSectionHeader => 'INTEGRITÄT & PRÜFSUMME';

  @override
  String get computingHashMessage => 'Hash wird berechnet…';

  @override
  String get tapCalculateToVerifyMessage =>
      'Zum Überprüfen auf „Berechnen“ tippen';

  @override
  String get calculateButton => 'Berechnen';

  @override
  String get copyDiagnosticsButton => 'Diagnose kopieren';

  @override
  String get closeButton => 'Schließen';

  @override
  String get hwAcceleratedBadge => 'HW-BESCHLEUNIGT';

  @override
  String get swDecoderBadge => 'SW-DECODER';

  @override
  String get videoDecoderHardwareSection => 'VIDEODECODER & HARDWARE';

  @override
  String get decoderNameLabel => 'Decoder-Name';

  @override
  String get accelerationLabel => 'Beschleunigung';

  @override
  String get hardwareGpuDirect => 'Hardware (GPU Direct)';

  @override
  String get softwareCpuFallback => 'Software (CPU-Fallback)';

  @override
  String get unknownValue => 'Unbekannt';

  @override
  String get framerateLabel => 'Bildrate';

  @override
  String get variableOrUnknown => 'Variabel / Unbekannt';

  @override
  String get videoCodecLabel => 'Videocodec';

  @override
  String get autoDetected => 'Automatisch erkannt';

  @override
  String get colorFormatLabel => 'Farbformat';

  @override
  String get initLatencyLabel => 'Initialisierungslatenz';

  @override
  String get audioEngineSection => 'AUDIO-ENGINE';

  @override
  String get audioDecoderLabel => 'Audiodecoder';

  @override
  String get audioCodecLabel => 'Audiocodec';

  @override
  String get pipelineHealthSection => 'PIPELINE & STATUS';

  @override
  String get playbackStateLabel => 'Wiedergabestatus';

  @override
  String get decryptedBufferLabel => 'Entschlüsselter Puffer';

  @override
  String secondsCached(String seconds) {
    return '$seconds s zwischengespeichert';
  }

  @override
  String get droppedFramesLabel => 'Verworfene Bilder';

  @override
  String nFrames(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bilder',
      one: '1 Bild',
    );
    return '$_temp0';
  }

  @override
  String get sourceStorageLabel => 'Quellspeicher';

  @override
  String directJniStreamSource(int volId) {
    return 'Direkter C++-JNI-Stream (volId=$volId)';
  }

  @override
  String get archivesTabLabel => 'Archives';

  @override
  String get filesTabLabel => 'Files';

  @override
  String get filesPermissionMessage =>
      'Allow access to browse files on your device.';

  @override
  String get filesEmptyTitle => 'No files here';

  @override
  String get filesEmptyMessage => 'This folder is empty.';

  @override
  String get filesNewFolderTooltip => 'New folder';

  @override
  String get filesNewFolderDialogTitle => 'New folder';

  @override
  String get filesNameHint => 'Name';

  @override
  String get filesCreate => 'Create';

  @override
  String get filesRename => 'Rename';

  @override
  String get filesDelete => 'Delete';

  @override
  String get filesShare => 'Share';

  @override
  String get filesCopy => 'Copy';

  @override
  String get filesMove => 'Move';

  @override
  String get filesDeleteConfirmTitle => 'Delete permanently?';

  @override
  String get filesChooseDestinationTitle => 'Choose a folder';

  @override
  String get filesMoveHere => 'Move here';

  @override
  String get filesCopyHere => 'Copy here';

  @override
  String get filesSelectAllTooltip => 'Select all';

  @override
  String get filesCloseSelectionTooltip => 'Close';

  @override
  String get filesFolderCreated => 'Folder created';

  @override
  String get filesCreateFolderFailed => 'Couldn\'t create folder';

  @override
  String get filesRenamed => 'Renamed';

  @override
  String get filesRenameFailed => 'Couldn\'t rename';

  @override
  String get filesNameAlreadyExists => 'That name is already taken';

  @override
  String get filesDeleted => 'Deleted';

  @override
  String get filesDeleteFailed => 'Couldn\'t delete';

  @override
  String get filesMoved => 'Moved';

  @override
  String get filesMoveFailed => 'Couldn\'t move';

  @override
  String get filesCopied => 'Copied';

  @override
  String get filesCopyFailed => 'Couldn\'t copy';

  @override
  String get filesOpenFailed => 'Couldn\'t open this file';

  @override
  String get filesShareFailed => 'Couldn\'t share this file';

  @override
  String get filesFilterTooltip => 'Filter';

  @override
  String get filesFilterAll => 'All files';

  @override
  String get filesFilterImages => 'Images';

  @override
  String get filesFilterVideos => 'Videos';

  @override
  String get filesFilterAudio => 'Audio';

  @override
  String get filesFilterDocuments => 'Documents';

  @override
  String get filesTextTooLarge => 'This file is too large to preview here.';

  @override
  String get filesTextSaved => 'Saved';

  @override
  String get filesTextSaveFailed => 'Couldn\'t save';
}
