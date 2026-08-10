// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get search => 'Search';

  @override
  String get goBack => 'Go back';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => 'Go to page';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return 'Page number (1 - $pageCount)';
  }

  @override
  String get pdfViewerPageLabel => 'Page';

  @override
  String get pdfViewerGoButton => 'Go';

  @override
  String get pdfViewerSearchHint => 'Search in document';

  @override
  String get pdfViewerNoMatches => 'No matches';

  @override
  String get pdfViewerPreviousMatch => 'Previous match';

  @override
  String get pdfViewerNextMatch => 'Next match';

  @override
  String get pdfViewerCloseSearch => 'Close search';

  @override
  String get pdfViewerPrintTooltip => 'Print document';

  @override
  String get pdfViewerLoadingDocument => 'Loading document…';

  @override
  String get pdfViewerCannotOpenTitle => 'Cannot open PDF';

  @override
  String get pdfViewerFailedToLoad => 'Failed to load PDF';

  @override
  String get paste => 'Paste';

  @override
  String get clear => 'Clear';

  @override
  String get clipboardVerbMove => 'Move';

  @override
  String get clipboardVerbCopy => 'Copy';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb ($count) — Tap details, long press to paste';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb ($count) — Clipboard details';
  }

  @override
  String clipboardSourceLabel(String source) {
    return 'Source: $source';
  }

  @override
  String get clipboardDefaultSourceName => 'Vault';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count more items',
      one: '+1 more item',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => 'Advanced Parameters';

  @override
  String get pimFieldLabel => 'PIM  (leave blank for default)';

  @override
  String get encryptionAlgorithmLabel => 'Encryption Algorithm';

  @override
  String get hashAlgorithmLabel => 'Hash Algorithm';

  @override
  String get clipboardVerbMoving => 'Moving';

  @override
  String get clipboardVerbCopying => 'Copying';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return ' from \"$source\"';
  }

  @override
  String get clipboardOpenContainerToPaste => 'Open a container to paste';

  @override
  String get keyfilesOptionalLabel => 'Keyfiles (optional)';

  @override
  String get addFile => 'Add File';

  @override
  String get noKeyfilesAttached => 'No keyfiles attached';

  @override
  String get completed => 'Completed';

  @override
  String get dismiss => 'Dismiss';

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
      other: '$count transfers',
      one: '1 transfer',
    );
    return '$_temp0';
  }

  @override
  String multiOpSublabel(String summary) {
    return '$summary · tap to view all';
  }

  @override
  String get thumbnailSizeResolutionLabel => 'Thumbnail Size (Resolution)';

  @override
  String get jpegCompressionQualityLabel => 'JPEG Compression Quality';

  @override
  String get done => 'Done';

  @override
  String get confirm => 'Confirm';

  @override
  String get couldNotPickKeyfiles => 'Could not pick keyfiles';

  @override
  String get filesystemLabelEncryptedVault => 'this encrypted vault';

  @override
  String get filesystemLabelThisContainer => 'this container';

  @override
  String get nounFile => 'file';

  @override
  String get nounFolder => 'folder';

  @override
  String get nounFileCapitalized => 'File';

  @override
  String get nounFolderCapitalized => 'Folder';

  @override
  String get unitBytes => 'bytes';

  @override
  String get unitCharacters => 'characters';

  @override
  String get validationEmptyName => 'The name cannot be empty.';

  @override
  String validationReservedNavName(String name, String noun) {
    return '\"$name\" is a reserved navigation name and can\'t be used as a $noun name.';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return '\"$char\" at position $position is not allowed in a name on $fsLabel.';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return 'Position $position contains a non-printable control character (code $code), which is not allowed on $fsLabel.';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '\"$name\" is a reserved device name on $fsLabel (matches CON, PRN, AUX, NUL, COM0–9, or LPT0–9) and can\'t be used, with or without a file extension.';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return '$noun names can\'t end with a space on $fsLabel';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return '$noun names can\'t end with a \".\" on $fsLabel';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return 'This name is $length $unit long; $fsLabel allows at most $maxLength $unit per $noun name.';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return 'The full path is $length characters long; $fsLabel allows at most $maxLength.';
  }

  @override
  String conflictSameType(String noun, String name) {
    return 'A $noun named \"$name\" already exists here.';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return 'A $existingNoun named \"$name\" already exists here — it can\'t share a name with a $candidateNoun.';
  }

  @override
  String get readOnlyContainerWarning => 'This container is mounted read-only.';

  @override
  String get hiddenVolumeProtectionTriggeredWarning =>
      'A write to this outer volume would have damaged the hidden volume, so it was blocked. This container has been switched to read-only for the rest of this session.';

  @override
  String get protectHiddenVolumeToggleTitle => 'Protect hidden volume';

  @override
  String get protectHiddenVolumeToggleSubtitle =>
      'Prevent damage caused by writing to the outer volume';

  @override
  String get protectHiddenVolumeCredentialsRequired =>
      'A hidden volume password or keyfile is required to protect it';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count items?',
      one: 'Delete 1 item?',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning =>
      'These items will be permanently deleted, including all contents of any selected folders.';

  @override
  String get deleteFilesWarning =>
      'These items will be permanently erased from your encrypted volume.';

  @override
  String get delete => 'Delete';

  @override
  String get create => 'Create';

  @override
  String get rename => 'Rename';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Rename $count items',
      one: 'Rename 1 item',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => 'New Folder';

  @override
  String get newTextFileTitle => 'New Text File';

  @override
  String get folderNameHint => 'Folder name';

  @override
  String get filenameHint => 'filename.txt';

  @override
  String get newNameHint => 'New name';

  @override
  String get baseNameHint => 'Base name';

  @override
  String couldntCreateItem(String name) {
    return 'Couldn\'t create \"$name\" — check the container is still mounted';
  }

  @override
  String couldntRenameSingle(String name) {
    return 'Couldn\'t rename \"$name\" — an item with that name may already exist';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Couldn\'t rename # items: $reason',
      one: 'Couldn\'t rename 1 item: $reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Couldn\'t rename # items',
      one: 'Couldn\'t rename 1 item',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize =>
      'Enter a valid hidden size greater than 0';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter =>
      'Hidden volume size must be less than the outer volume size';

  @override
  String get hiddenVolumeErrorTooLargeForContainer =>
      'Hidden volume size is too large for this container size';

  @override
  String get hiddenVolumeErrorCredentialsRequired =>
      'A hidden password or keyfile is required when creating a hidden volume';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      'Hidden volume credentials (password, PIM, and keyfiles) cannot be identical to the outer volume credentials.';

  @override
  String get vaultItemTypePassword => 'Password';

  @override
  String get vaultItemTypePaymentCard => 'Payment Card';

  @override
  String get vaultItemTypeIdentity => 'Identity';

  @override
  String get vaultItemTypeSecureNote => 'Secure Note';

  @override
  String get vaultItemTypeBankAccount => 'Bank Account';

  @override
  String get vaultItemTypeSoftwareLicense => 'Software License';

  @override
  String get fieldUsernameEmail => 'Username / Email';

  @override
  String get fieldPassword => 'Password';

  @override
  String get fieldWebsiteUrl => 'Website URL';

  @override
  String get fieldTotpSecret => 'TOTP Secret (2FA)';

  @override
  String get fieldNotes => 'Notes';

  @override
  String get fieldCardholderName => 'Cardholder Name';

  @override
  String get fieldCardNumber => 'Card Number';

  @override
  String get fieldExpiryMMYY => 'Expiry (MM/YY)';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldIssuingBank => 'Issuing Bank';

  @override
  String get fieldFullName => 'Full Name';

  @override
  String get fieldDateOfBirth => 'Date of Birth';

  @override
  String get fieldNationality => 'Nationality';

  @override
  String get fieldPassportNumber => 'Passport Number';

  @override
  String get fieldPassportExpiry => 'Passport Expiry';

  @override
  String get fieldNationalIdSsn => 'National ID / SSN';

  @override
  String get fieldDriversLicense => 'Driver\'s License';

  @override
  String get fieldAddress => 'Address';

  @override
  String get fieldPhone => 'Phone';

  @override
  String get fieldEmail => 'Email';

  @override
  String get fieldNote => 'Note';

  @override
  String get fieldBankName => 'Bank Name';

  @override
  String get fieldAccountHolder => 'Account Holder';

  @override
  String get fieldAccountNumber => 'Account Number';

  @override
  String get fieldRoutingSortCode => 'Routing / Sort Code';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => 'Account Type';

  @override
  String get fieldProductName => 'Product Name';

  @override
  String get fieldLicenseKey => 'License Key';

  @override
  String get fieldRegisteredTo => 'Registered To';

  @override
  String get fieldPurchaseDate => 'Purchase Date';

  @override
  String get fieldExpiryRenewalDate => 'Expiry / Renewal Date';

  @override
  String get fieldDownloadUrl => 'Download URL';

  @override
  String get fieldRegistrationEmail => 'Registration Email';

  @override
  String get titleRequired => 'Title is required';

  @override
  String newTypeTitle(String typeLabel) {
    return 'New $typeLabel';
  }

  @override
  String editItemTitle(String title) {
    return 'Edit $title';
  }

  @override
  String get save => 'Save';

  @override
  String typeNameHint(String typeLabel) {
    return '$typeLabel name';
  }

  @override
  String get titleSectionLabel => 'Title';

  @override
  String get fieldsSectionLabel => 'Fields';

  @override
  String get encryptedStorageHint =>
      'All fields are stored encrypted inside the container.';

  @override
  String copiedSuffix(String fieldLabel) {
    return '$fieldLabel copied';
  }

  @override
  String get copy => 'Copy';

  @override
  String get failedToSaveCheckMounted =>
      'Failed to save — check container is still mounted';

  @override
  String get discardChangesTitle => 'Discard changes?';

  @override
  String get discardChangesMessage => 'Your unsaved changes will be lost.';

  @override
  String get discard => 'Discard';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get deleteItemTitle => 'Delete item?';

  @override
  String deleteItemMessage(String title) {
    return '\"$title\" will be permanently deleted from the vault.';
  }

  @override
  String get removeFromFavourites => 'Remove from favourites';

  @override
  String get addToFavourites => 'Add to favourites';

  @override
  String get edit => 'Edit';

  @override
  String labelCopiedToClipboard(String label) {
    return '$label copied to clipboard';
  }

  @override
  String get noFieldsFilledIn =>
      'No fields filled in.\nTap Edit to add details.';

  @override
  String get sectionLabelDetails => 'Details';

  @override
  String get sectionLabelInfo => 'Info';

  @override
  String get metaLabelType => 'Type';

  @override
  String get metaLabelCreated => 'Created';

  @override
  String get metaLabelModified => 'Modified';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return 'Copy $fieldLabel';
  }

  @override
  String get readOnlyCantAddItemsTooltip => 'Read-only — can\'t add items';

  @override
  String get extractArchive => 'Extract Archive';

  @override
  String get newItemTooltip => 'New item';

  @override
  String get camera => 'Camera';

  @override
  String get importFiles => 'Import Files';

  @override
  String get importFolder => 'Import Folder';

  @override
  String get secureItem => 'Secure Item';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archive Explorer';

  @override
  String get archiveExplorerPermissionTitle => 'Storage access needed';

  @override
  String get archiveExplorerPermissionMessage =>
      'Allow access to your files to browse and extract .zip archives from Downloads.';

  @override
  String get archiveExplorerGrantAccess => 'Grant Access';

  @override
  String get archiveExplorerEmptyTitle => 'No archives found';

  @override
  String get archiveExplorerEmptyMessage =>
      'Zip files you download will show up here.';

  @override
  String get archiveExplorerRefreshTooltip => 'Refresh';

  @override
  String archiveExplorerEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get archiveExplorerExtractAll => 'Extract All';

  @override
  String get archiveExplorerExtracting => 'Extracting…';

  @override
  String archiveExplorerExtractSuccess(int count, String name) {
    return 'Extracted $count files to Download/Extracted/$name';
  }

  @override
  String get archiveExplorerExtractFailed => 'Couldn\'t extract that archive.';

  @override
  String get archiveExplorerOpenFailed => 'Couldn\'t open that archive.';

  @override
  String get archiveExplorerOpenArchive => 'Open archive…';

  @override
  String get archiveExplorerUnresolvedPath =>
      'Couldn\'t access that file directly. Try picking one from Downloads instead.';

  @override
  String get archiveExplorerExtractTo => 'Extract to…';

  @override
  String get archiveExplorerPreview => 'Preview';

  @override
  String get archiveExplorerChoosingDestination => 'Choosing destination…';

  @override
  String get archiveExplorerNoDestinationChosen => 'No destination chosen.';

  @override
  String archiveExplorerExtractSuccessTo(int count, String path) {
    return 'Extracted $count files to $path';
  }

  @override
  String get archiveBrowserEmptyTitle => 'Empty folder';

  @override
  String get archiveBrowserEmptyMessage =>
      'This folder doesn\'t contain any files.';

  @override
  String get archiveBrowserRoot => 'Archive';

  @override
  String get archiveBrowserOpenFileFailed => 'Couldn\'t open that file.';

  @override
  String get fileAssocInAppTextEditor => 'In-app Text Editor';

  @override
  String get fileAssocInAppMediaViewer => 'In-app Media Viewer';

  @override
  String fileAssocAppPrefix(String name) {
    return 'App: $name';
  }

  @override
  String get fileAssocExternalApp => 'External App';

  @override
  String get appSettingsTitle => 'App Settings';

  @override
  String get sectionSecurityPrivacy => 'Security & Privacy';

  @override
  String get sectionAppearanceInterface => 'Appearance & Interface';

  @override
  String get sectionVaultFileHandling => 'Vault & File Handling';

  @override
  String get masterPasswordTitle => 'Master Password';

  @override
  String get masterPasswordActiveSubtitle => 'Active — tap toggle to remove';

  @override
  String get masterPasswordInactiveSubtitle =>
      'Require a password to open the app';

  @override
  String get newPasswordLabel => 'New Password';

  @override
  String get masterPasswordFieldLabel => 'Master password';

  @override
  String get confirmPasswordLabel => 'Confirm password';

  @override
  String get update => 'Update';

  @override
  String get setPassword => 'Set Password';

  @override
  String get biometricUnlockTitle => 'Biometric Unlock';

  @override
  String get biometricUnlockSubtitle =>
      'Authenticate to securely mount the container';

  @override
  String get changeMasterPasswordTitle => 'Change Master Password';

  @override
  String get changeMasterPasswordSubtitle =>
      'Update master password credentials';

  @override
  String get autoLockContainersTitle => 'Auto-Lock Containers';

  @override
  String get autoLockContainersSubtitle =>
      'Automatically lock open vaults after inactivity';

  @override
  String get autoLockTimeoutLabel => 'Auto-Lock Timeout';

  @override
  String get immediately => 'Immediately';

  @override
  String nMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get blockScreenshotsTitle => 'Block Screenshots';

  @override
  String get blockScreenshotsSubtitle =>
      'Prevent screenshots and hide recent apps preview';

  @override
  String get discreteModeTitle => 'Mask Mode';

  @override
  String get discreteModeActiveSubtitle =>
      'Active — the app currently appears as \"Archive Explorer\"';

  @override
  String get discreteModeInactiveSubtitle =>
      'Disguise this app as a zip archive browser on the home screen';

  @override
  String get enableDiscreteModeTitle => 'Enable Mask Mode?';

  @override
  String get disableDiscreteModeTitle => 'Disable Mask Mode?';

  @override
  String get enableDiscreteModeMessage =>
      'The app icon and name on your home screen will change to \"Archive Explorer\". It will function as a zip archive browser and extractor.\n\nTo access your vault, open Archive Explorer and hold your finger on the title for 3 seconds.';

  @override
  String get disableDiscreteModeMessage =>
      'The app icon and name on your home screen will change back to \"Vault Explorer\".';

  @override
  String get enable => 'Enable';

  @override
  String get disable => 'Disable';

  @override
  String get discreteModeEnabledSnack =>
      'Mask Mode enabled. The app will close — reopen from the new launcher icon.';

  @override
  String get discreteModeDisabledSnack =>
      'Mask Mode disabled. The app will close — reopen from the new launcher icon.';

  @override
  String get failedToChangeDiscreteMode => 'Failed to change Mask Mode';

  @override
  String get cacheDerivedKeysTitle => 'Cache Derived Keys by Default';

  @override
  String get cacheDerivedKeysSubtitle =>
      'Store derived key material in Keystore for faster unlocks';

  @override
  String get appThemeLabel => 'App Theme';

  @override
  String get systemDefault => 'System Default';

  @override
  String get lightTheme => 'Light Theme';

  @override
  String get darkTheme => 'Dark Theme';

  @override
  String get sortContainersByLabel => 'Sort Containers By';

  @override
  String get swapCardSwipeActionsTitle => 'Swap Card Swipe Actions';

  @override
  String get swapCardSwipeActionsSubtitle =>
      'Reveal Edit on left and Delete on right when swiping cards';

  @override
  String get swipeGestureHintTitle => 'Swipe Gesture Hint';

  @override
  String get swipeGestureHintSubtitle =>
      'Show card peek animation on first container';

  @override
  String get autoOpenOnUnlockTitle => 'Auto-Open on Unlock';

  @override
  String get autoOpenOnUnlockActiveSubtitle =>
      'Automatically open after unlocking a vault';

  @override
  String get autoOpenOnUnlockInactiveSubtitle =>
      'Only unlock vault and stay on dashboard';

  @override
  String get enableJsHtmlTitle => 'Enable JavaScript in HTML Viewer';

  @override
  String get jsEnabledSubtitle => 'JavaScript enabled for local HTML files';

  @override
  String get jsDisabledSubtitle => 'JavaScript disabled for local HTML files';

  @override
  String get fastStorageAccessTitle => 'Fast Storage Access';

  @override
  String get fastStorageAccessGrantedSubtitle =>
      'All Files Access granted (maximum speed)';

  @override
  String get fastStorageAccessNotGrantedSubtitle =>
      'Grant All Files Access in System Settings for optimal speed';

  @override
  String get enableFastStorageAccessTitle => 'Enable Fast Storage Access';

  @override
  String get enableFastStorageAccessMessage =>
      'Granting \"All Files Access\" allows Vault Explorer to perform direct POSIX file operations, speeding up folder vault performance by up to 1000x.';

  @override
  String get disableStorageAccessTitle => 'Disable Storage Access';

  @override
  String get disableStorageAccessMessage =>
      'Android requires \"All Files Access\" to be turned off inside System Settings. Would you like to open Settings to turn it off?';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get androidFileProviderTitle => 'Android File Provider';

  @override
  String get androidFileProviderSubtitle =>
      'Expose new containers to Android File Picker by default';

  @override
  String get thumbnailCachingDefaultLabel => 'Thumbnail Caching (default)';

  @override
  String get thumbnailQualityDefaultLabel => 'Thumbnail Quality (default)';

  @override
  String get fileAssociationsHeader => 'File Associations';

  @override
  String get noFileAssociationsYet =>
      'No remembered file associations yet. You will be prompted when opening files.';

  @override
  String get defaultActionsHeader =>
      'Default actions when opening non-standard files:';

  @override
  String get removeAssociationTooltip => 'Remove association';

  @override
  String get aboutAppTitle => 'About VaultExplorer';

  @override
  String versionInfoSubtitle(String version) {
    return 'Version $version · Open source licenses & details';
  }

  @override
  String get failedToSaveSettings => 'Failed to save settings';

  @override
  String get masterPasswordSetSnack => 'Master password set';

  @override
  String get passwordCannotBeEmpty => 'Password cannot be empty';

  @override
  String get atLeast4CharsRequired => 'At least 4 characters required';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get failedToHashPassword =>
      'Failed to hash password — please try again';

  @override
  String get languageLabel => 'Language';

  @override
  String get biometricNotAvailable => 'Biometric not available on this device';

  @override
  String get unlockVaultExplorerReason => 'Unlock VaultExplorer';

  @override
  String biometricErrorWithCode(String code) {
    return 'Biometric error: $code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconds',
      one: '1 second',
    );
    return 'Too many failed attempts. Try again in $_temp0.';
  }

  @override
  String get enterMasterPasswordPrompt => 'Enter your master password';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts failed attempts',
      one: '1 failed attempt',
    );
    return 'Incorrect password. Locked for ${seconds}s due to $_temp0.';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts failed attempts',
      one: '1 failed attempt',
    );
    return 'Incorrect password ($_temp0).';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle => 'Enter your master password to continue';

  @override
  String get masterPasswordFieldLabelTitleCase => 'Master Password';

  @override
  String get unlock => 'Unlock';

  @override
  String get useBiometric => 'Use Biometric';

  @override
  String get connectAtLeast4Dots => 'Connect at least 4 dots';

  @override
  String get patternsDontMatch => 'Patterns don\'t match — try again';

  @override
  String get drawUnlockPatternTitle => 'Draw Unlock Pattern';

  @override
  String get confirmPatternTitle => 'Confirm your pattern';

  @override
  String get drawSamePatternAgain => 'Draw the same pattern again';

  @override
  String removedFromListSnack(String name) {
    return 'Removed \"$name\" from list';
  }

  @override
  String get clearRecentHistoryTitle => 'Clear Recent History?';

  @override
  String get clearRecentHistoryMessage =>
      'This will remove all recent documents from your list. The actual files on your device will not be affected.';

  @override
  String get clearAll => 'Clear All';

  @override
  String get recentHistoryClearedSnack => 'Recent history cleared';

  @override
  String get moreOptionsTooltip => 'More options';

  @override
  String get clearHistoryMenuItem => 'Clear history';

  @override
  String get openPdfFile => 'Open PDF File';

  @override
  String get noDocumentsYetTitle => 'No documents yet';

  @override
  String get openPdfToStartMessage =>
      'Open a PDF from your device to start reading.';

  @override
  String get removeFromListMenuItem => 'Remove from list';

  @override
  String get justNow => 'Just now';

  @override
  String minutesAgo(int count) {
    return '${count}m ago';
  }

  @override
  String hoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String daysAgo(int count) {
    return '${count}d ago';
  }

  @override
  String get usbDriveDisconnectedLocked =>
      'USB drive disconnected — container locked';

  @override
  String get containerAlreadyMounted => 'This container is already mounted.';

  @override
  String get noVaultFolderFormatDetected =>
      'No masterkey.cryptomator, gocryptfs.conf, or cryfs.config found in that folder.';

  @override
  String get savedContainerSettingsNotFound =>
      'Saved settings for this container could not be found.';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return 'Could not update the container location: $error';
  }

  @override
  String filePickerFailed(String error) {
    return 'File picker failed: $error';
  }

  @override
  String get selectContainerFirst => 'Select a container first';

  @override
  String get passwordOrKeyfilesRequired => 'Password or keyfiles required';

  @override
  String get slowPerformanceWarningTitle => 'Slow Performance Warning';

  @override
  String get slowPerformanceWarningMessage =>
      'Direct Storage Access is currently disabled.\n\nCryFS stores files across thousands of small blocks. Opening non-empty CryFS vaults via Android SAF will be very slow.\n\nWould you like to open Settings to grant \"All Files Access\" for fast speed?';

  @override
  String get unlockAnyway => 'Unlock Anyway';

  @override
  String get defaultVaultName => 'Vault';

  @override
  String get defaultContainerName => 'Container';

  @override
  String get incorrectPasswordOrInvalidVault =>
      'Incorrect password or invalid vault';

  @override
  String get incorrectPasswordOrInvalidContainer =>
      'Incorrect password or invalid container';

  @override
  String get genericUnknownError => 'Unknown error';

  @override
  String get decryptingLabel => 'Decrypting…';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return 'Trying keyslot $attempted of $total…';
  }

  @override
  String get luksKeyslotProgressUnknown => 'Trying keyslot…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return 'Verifying credential $attempted of $total…';
  }

  @override
  String get bitlockerCredentialProgressUnknown => 'Verifying credential…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return 'Trying $algo ($slotName)…';
  }

  @override
  String get unlockContainerLabel => 'Unlock Container';

  @override
  String get mountContainerTitle => 'Mount Container';

  @override
  String get containerFileSegmentLabel => 'Container File';

  @override
  String get folderVaultSegmentLabel => 'Folder Vault';

  @override
  String formatContainerLabel(String format) {
    return '$format Container';
  }

  @override
  String formatVaultLabel(String format) {
    return '$format Vault';
  }

  @override
  String formatDriveLabel(String format) {
    return '$format Drive';
  }

  @override
  String get encryptedContainerLabel => 'Encrypted Container';

  @override
  String get tapToSelectVaultFolder => 'Tap to select vault folder…';

  @override
  String get tapToSelectContainerFile => 'Tap to select container file…';

  @override
  String get containerMissingTitle => 'Container Missing';

  @override
  String get filePathCouldNotBeResolved => 'File path could not be resolved';

  @override
  String get containerMissingExplanation =>
      'The container file may have been moved, deleted, or its host storage is currently disconnected.';

  @override
  String get retryButtonLabel => 'Retry';

  @override
  String get locateFileButtonLabel => 'Locate File';

  @override
  String get authenticateToMountSubtitle =>
      'Authenticate to securely mount the container';

  @override
  String get usePasswordButtonLabel => 'Use Password';

  @override
  String get authenticateButtonLabel => 'Authenticate';

  @override
  String get drawUnlockPatternCardTitle => 'Draw Unlock Pattern';

  @override
  String get wrongPatternTryAgain => 'Wrong pattern — try again';

  @override
  String get connectYourPatternSequence => 'Connect your pattern sequence';

  @override
  String get usePasswordInsteadButtonLabel => 'Use Password instead';

  @override
  String get passwordHintFolderVault => 'Enter vault password';

  @override
  String get passwordHintBitlocker => 'Enter password or recovery key';

  @override
  String get passwordHintContainer => 'Enter container password';

  @override
  String get usingSavedPasswordTooltip => 'Using saved password';

  @override
  String get luksKeyfileReplacesPasswordNote =>
      'For LUKS containers the keyfile replaces the password.';

  @override
  String get readOnlyModeUsbSubtitle =>
      'Mount without allowing changes to this drive';

  @override
  String get readOnlyModeContainerSubtitle =>
      'Mount without allowing changes to this container';

  @override
  String get rememberContainerLabel => 'Remember container';

  @override
  String get rememberContainerSubtitle =>
      'Pin container on dashboard for quick access';

  @override
  String get cancelUnlockButtonLabel => 'Cancel Unlock';

  @override
  String get biometricSubjectContainer => 'container';

  @override
  String get biometricSubjectUsbDrive => 'USB drive';

  @override
  String get usbNoSavedCredentialsMessage =>
      'No saved password found. Please enter it manually.';

  @override
  String get decryptingDriveLabel => 'Decrypting drive…';

  @override
  String get usbDeviceAlreadyActiveMounted =>
      'This USB device is already active and mounted.';

  @override
  String reconnectUsbDriveTitle(String label) {
    return 'Reconnect \"$label\"';
  }

  @override
  String get unlockUsbDriveTitle => 'Unlock USB Drive';

  @override
  String get noUsbStorageDetectedTitle => 'No USB Storage Detected';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return 'Authenticate to unlock $subject';
  }

  @override
  String get noPatternConfiguredMessage =>
      'No pattern configured. Please enter password manually.';

  @override
  String patternLockedForSeconds(int seconds) {
    return 'Too many failed attempts. Locked for ${seconds}s.';
  }

  @override
  String get initSecureCredsBiometricMessage =>
      'Initializing secure credentials. Please unlock manually once to authorize biometric access.';

  @override
  String get initSecureCredsPatternMessage =>
      'Initializing secure credentials. Please unlock manually once to authorize pattern access.';

  @override
  String get mountExistingContainerTitle => 'Mount existing container';

  @override
  String get mountExistingContainerSubtitle =>
      'Unlock a file container you already have';

  @override
  String get mountSplitContainerTitle => 'Mount split container';

  @override
  String get mountSplitContainerSubtitle =>
      'Unlock a split container directly, without joining it first';

  @override
  String get mountUsbDriveTitle => 'Mount USB Drive';

  @override
  String get mountUsbDriveSubtitle =>
      'Unlock a container on an OTG flash drive';

  @override
  String get formatUsbDriveTitle => 'Format USB drive';

  @override
  String get formatUsbDriveSubtitle =>
      'Erase a drive and create a new encrypted container on it';

  @override
  String get createNewContainerTitle => 'Create new container';

  @override
  String get createNewContainerSubtitle => 'Format a brand-new encrypted vault';

  @override
  String get lockBeforeRemovingWarning =>
      'Lock the container before removing it.';

  @override
  String get settingsTooltip => 'Settings';

  @override
  String get addVaultFabLabel => 'Add vault';

  @override
  String removedLabelUndo(String label) {
    return 'Removed \"$label\"';
  }

  @override
  String get undo => 'Undo';

  @override
  String get pdfViewerNoSourceProvided => 'No PDF source provided.';

  @override
  String get pdfViewerFileEmpty => 'PDF file is empty or unreadable.';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return 'Failed to inspect PDF file size: $error';
  }

  @override
  String get pdfViewerErrorLoadingTitle => 'Error loading PDF';

  @override
  String get pdfViewerNoDocumentLoaded => 'No PDF document loaded.';

  @override
  String get add => 'Add';

  @override
  String get reset => 'Reset';

  @override
  String couldNotExpose(String name) {
    return 'Could not expose \"$name\".';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return '\"$name\" is now available to other apps.';
  }

  @override
  String couldNotUnmount(String name) {
    return 'Could not unmount \"$name\".';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pinned # items',
      one: 'Pinned 1 item',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Unpinned # items',
      one: 'Unpinned 1 item',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning =>
      'Read-only mount — thumbnails will show but won\'t be saved inside the container this session.';

  @override
  String failedLoadingFolder(String type) {
    return 'Failed loading folder: $type';
  }

  @override
  String failedToReadArchive(String type) {
    return 'Failed to read archive: $type';
  }

  @override
  String archiveFormatNotSupported(String ext) {
    return 'Archive format .$ext is not yet supported';
  }

  @override
  String get failedToReadFileFromArchive => 'Failed to read file from archive';

  @override
  String failedToExtractFile(String type) {
    return 'Failed to extract file: $type';
  }

  @override
  String get failedToReadSecureItem => 'Failed to read secure item';

  @override
  String get openFileDialogTitle => 'Open File';

  @override
  String chooseHowToOpen(String name) {
    return 'Choose how to open \"$name\":';
  }

  @override
  String get playVideoAudioViewImageInApp =>
      'Play video/audio or view image in-app';

  @override
  String get viewEditTextMarkdownCode => 'View/edit text, markdown, code';

  @override
  String get sendFileToThirdPartyApp => 'Send file to third-party app';

  @override
  String get openAsEllipsis => 'Open As…';

  @override
  String get chooseFileTypeToOpenAs => 'Choose file type to open as';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return 'Always remember choice for .$ext files';
  }

  @override
  String get alwaysRememberChoiceNoExt =>
      'Always remember choice for files without extension';

  @override
  String get openAsDialogTitle => 'Open As';

  @override
  String get mimeTypeText => 'Text';

  @override
  String get mimeTypeImage => 'Image';

  @override
  String get mimeTypeVideo => 'Video';

  @override
  String get mimeTypeAudio => 'Audio';

  @override
  String get mimeTypeArchive => 'Archive';

  @override
  String get mimeTypeOther => 'Other';

  @override
  String get scanningSubfoldersForMedia => 'Scanning subfolders for media…';

  @override
  String get noMediaFilesFoundRecursive =>
      'No media files found in this folder or its subfolders';

  @override
  String failedToScanSubfolders(String error) {
    return 'Failed to scan subfolders: $error';
  }

  @override
  String get noAppFoundForFileType => 'No app found for this file type';

  @override
  String couldNotOpenFile(String name) {
    return 'Could not open \"$name\"';
  }

  @override
  String get readOnlyCantMove =>
      'This container is mounted read-only — items can\'t be moved from here.';

  @override
  String get readOnlyCantPaste =>
      'This container is mounted read-only — items can\'t be pasted here.';

  @override
  String get clipboardSourceInvalid => 'Clipboard source is invalid';

  @override
  String get crossContainerPasteNotConfigured =>
      'Cross-container paste is not configured.';

  @override
  String get crossContainerPasteRequiresBothMounted =>
      'Cross-container paste requires both containers to remain mounted.';

  @override
  String get readOnlyCantDelete =>
      'This container is mounted read-only — items can\'t be deleted.';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deleted $count items',
      one: 'Deleted 1 item',
    );
    return '$_temp0';
  }

  @override
  String deletedWithFailures(int deleted, int failed) {
    return '$deleted deleted · $failed failed';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Exported $count files',
      one: 'Exported 1 file',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed => 'Export cancelled or failed';

  @override
  String exportError(String type) {
    return 'Export error: $type';
  }

  @override
  String get deleteOriginalTitle => 'Delete original?';

  @override
  String get deleteOriginalFolderMessage =>
      'Delete the original folder from your device now that it has been imported?';

  @override
  String get deleteOriginalFilesMessage =>
      'Delete the original file(s) from your device now that they have been imported?';

  @override
  String get keepOriginal => 'Keep original';

  @override
  String get deleteOriginalButton => 'Delete original';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deleted $count original items',
      one: 'Deleted 1 original item',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals => 'Could not delete original(s)';

  @override
  String get videoCapturedEncrypted => 'Video captured and encrypted';

  @override
  String get photoCapturedEncrypted => 'Photo captured and encrypted';

  @override
  String cameraCaptureFailed(String type) {
    return 'Camera capture failed: $type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return 'Extract all files to the folder \"$folder\"?';
  }

  @override
  String get extract => 'Extract';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Extracted $count files',
      one: 'Extracted 1 file',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return 'Failed to extract: $type';
  }

  @override
  String get closeSearchTooltip => 'Close search';

  @override
  String get searchInThisFolderTooltip => 'Search in this folder';

  @override
  String get playMediaHereTooltip => 'Play media here';

  @override
  String get rootFolderLabel => 'Root';

  @override
  String folderPickerFailed(String error) {
    return 'Folder picker failed: $error';
  }

  @override
  String get addAVaultTitle => 'Add a vault';

  @override
  String get selectEmptyDestinationFolderFirst =>
      'Select an empty destination folder first';

  @override
  String get passwordRequired => 'A password is required';

  @override
  String get vaultCreatedSuccessfully => 'Vault created successfully.';

  @override
  String get vaultCreationFailedEmptyFolder =>
      'Vault creation failed — make sure the selected folder is empty.';

  @override
  String get unknownErrorOccurred => 'Unknown error occurred';

  @override
  String get containerNameRequired => 'Container name is required';

  @override
  String get enterValidSizeGreaterThanZero =>
      'Enter a valid size greater than 0';

  @override
  String get passwordOrKeyfileRequired =>
      'A password or at least one keyfile is required';

  @override
  String get standardVolumePasswordsDoNotMatch =>
      'Standard volume passwords do not match';

  @override
  String get hiddenVolumePasswordsDoNotMatch =>
      'Hidden volume passwords do not match';

  @override
  String get containerFileCreatedSuccessfully =>
      'Container file created successfully.';

  @override
  String get containerCreationCancelledOrFailed =>
      'Container creation cancelled or failed.';

  @override
  String get vaultKindContainerFile => 'Container File';

  @override
  String get vaultKindFolderVault => 'Folder Vault';

  @override
  String get formatFileSystemLabel => 'Format File System';

  @override
  String get standardVolumeHeader => 'Standard Volume';

  @override
  String get containerFormatLabel => 'Container Format';

  @override
  String get fileNameLabel => 'File Name';

  @override
  String get containerSizeLabel => 'Container Size';

  @override
  String get unitLabel => 'Unit';

  @override
  String get passwordFieldLabel => 'Password';

  @override
  String get confirmPasswordFieldLabelTitleCase => 'Confirm Password';

  @override
  String get hiddenVolumeHeader => 'Hidden Volume';

  @override
  String get createHiddenVolumeToggleTitle => 'Create Hidden Volume';

  @override
  String get createInvisibleSecondaryVolume =>
      'Create an invisible secondary volume';

  @override
  String get setOuterPasswordFirstToEnable =>
      'Set outer password or keyfiles first to enable';

  @override
  String get hiddenPasswordLabel => 'Hidden Password';

  @override
  String get confirmHiddenPasswordLabel => 'Confirm Hidden Password';

  @override
  String get hiddenSizeLabel => 'Hidden Size';

  @override
  String get unitMbMegabytes => 'MB (Megabytes)';

  @override
  String get unitGbGigabytes => 'GB (Gigabytes)';

  @override
  String get hiddenFileSystemLabel => 'Hidden File System';

  @override
  String get vaultFormatLabel => 'Vault Format';

  @override
  String get gocryptfsCipherLabel => 'Content Cipher';

  @override
  String get cryfsCipherLabel => 'Content Cipher';

  @override
  String get destinationFolderLabel => 'Destination Folder';

  @override
  String get selectEmptyFolderLabel => 'Select an empty folder';

  @override
  String get tapToChooseVaultLocation =>
      'Tap to choose where vault will be created…';

  @override
  String get folderVaultLimitationsNote =>
      'Folder vaults don\'t support keyfiles, PIM, hidden volumes, or VeraCrypt/LUKS cipher choices.';

  @override
  String get createVaultButton => 'Create Vault';

  @override
  String get createContainerButton => 'Create Container';

  @override
  String get vaultCreationInProgressWait =>
      'Vault creation in progress. Please wait.';

  @override
  String get containerCreationInProgressWait =>
      'Container creation in progress. Please wait.';

  @override
  String get createEncryptedVaultTitle => 'Create Encrypted Vault';

  @override
  String get createEncryptedContainerTitle => 'Create Encrypted Container';

  @override
  String get unitMbShort => 'MB';

  @override
  String get unitGbShort => 'GB';

  @override
  String failedToListUsbDevices(String error) {
    return 'Failed to list USB devices: $error';
  }

  @override
  String get usbPermissionDenied => 'USB permission denied';

  @override
  String get couldNotReadDriveCapacity =>
      'Could not read drive capacity — enter size manually.';

  @override
  String get selectUsbDriveFirst => 'Select a USB drive first';

  @override
  String eraseDeviceTitle(String name) {
    return 'Erase \"$name\"?';
  }

  @override
  String get eraseDeviceMessage =>
      'This will permanently erase everything currently on this USB drive and replace it with a new encrypted container. This cannot be undone.';

  @override
  String get eraseAndCreateButton => 'Erase & Create';

  @override
  String get usbPermissionRequiredToContinue =>
      'USB permission is required to continue';

  @override
  String get usbContainerCreatedSnack =>
      'USB container created. Use \"Mount USB drive\" to unlock it.';

  @override
  String get usbContainerCreationFailed => 'USB container creation failed.';

  @override
  String get usbStandardVolumeSectionHeader => 'USB Drive & Standard Volume';

  @override
  String get formattingErasesEverythingWarning =>
      'Formatting erases everything currently on the selected drive.';

  @override
  String get selectUsbDriveLabel => 'Select USB Drive';

  @override
  String get noUsbStorageDetected => 'No USB storage detected';

  @override
  String get connectOtgDriveToFormat => 'Connect an OTG drive to format';

  @override
  String get refreshListButton => 'Refresh list';

  @override
  String get readyToFormat => 'Ready to format';

  @override
  String get permissionRequired => 'Permission required';

  @override
  String get readingDriveCapacity => 'Reading drive capacity…';

  @override
  String get mustNotExceedDriveCapacity =>
      'Must not exceed the drive\'s actual capacity.';

  @override
  String get quickFormatTitle => 'Quick Format';

  @override
  String get quickFormatDescription =>
      'Skips zero-filling the drive. Faster, but does not securely erase old data.';

  @override
  String get eraseAndCreateContainerButton => 'Erase & Create Container';

  @override
  String get usbContainerCreationInProgressWait =>
      'Container creation in progress. Please wait.';

  @override
  String get formatUsbDriveScreenTitle => 'Format USB Drive';

  @override
  String get playlistTransitionAnimationLabel =>
      'Playlist Transition Animation';

  @override
  String get playlistTransitionSlideLabel => 'Slide (Default)';

  @override
  String get playlistTransitionFadeLabel => 'Fade';

  @override
  String get playlistTransitionZoomLabel => 'Zoom & Scale';

  @override
  String get playlistTransitionDepthLabel => 'Depth Stack';

  @override
  String get playlistTransitionCubeLabel => '3D Cube';

  @override
  String get playlistTransitionFlipLabel => '3D Flip';

  @override
  String get unlockVaultTitle => 'Unlock Vault';

  @override
  String get openContainerTitle => 'Open Container';

  @override
  String get selectContainerFileOrFolder => 'Select File or Folder';

  @override
  String get readOnlyModeLabel => 'Read-only mode';

  @override
  String get readOnlyModeSubtitle =>
      'Prevents any write or modify operations on the vault';

  @override
  String get selectUsbDeviceLabel => 'Select USB Device';

  @override
  String get noUsbDevicesFound => 'No compatible USB storage devices found';

  @override
  String get containerConfigTitle => 'Vault Configuration';

  @override
  String get changePasswordTitle => 'Change Password';

  @override
  String get confirmNewPasswordLabel => 'Confirm New Password';

  @override
  String get cameraCaptureTitle => 'Vault Camera';

  @override
  String get takingPhoto => 'Capturing photo…';

  @override
  String get savingToVault => 'Saving to vault…';

  @override
  String get noVaultSelected => 'No vault selected';

  @override
  String get mediaDiagnosticsTitle => 'Media Diagnostics';

  @override
  String get advancedViewerSettingsTitle => 'Viewer Settings';

  @override
  String get textEditorSaveConfirmTitle => 'Unsaved Changes';

  @override
  String get textEditorSaveConfirmMessage =>
      'Do you want to save your changes before closing?';

  @override
  String get saveAndClose => 'Save & Close';

  @override
  String get discardChanges => 'Discard Changes';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items selected',
      one: '1 item selected',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'Select All';

  @override
  String get deselectAll => 'Deselect All';

  @override
  String get sortOptionsTitle => 'Sort Files';

  @override
  String get layoutModeList => 'List View';

  @override
  String get layoutModeGrid => 'Grid View';

  @override
  String get layoutModeMasonry => 'Masonry';

  @override
  String get fileOperationsTitle => 'File Operations';

  @override
  String get conflictResolutionTitle => 'File Conflict';

  @override
  String get replaceExistingFile => 'Replace existing file';

  @override
  String get keepBothFiles => 'Keep both (rename new file)';

  @override
  String get skipFile => 'Skip this file';

  @override
  String get noVaultsFoundTitle => 'No Vaults Found';

  @override
  String get noVaultsFoundSubtitle =>
      'Create a new encrypted container or add an existing vault to get started.';

  @override
  String get addExistingVaultButton => 'Add Existing Vault';

  @override
  String get sortContainersModeManual => 'Manual (drag to reorder)';

  @override
  String get sortContainersModeUnlockStatus => 'Unlock status (unlocked first)';

  @override
  String get sortContainersModeNameAZ => 'Name (A–Z)';

  @override
  String get sortContainersModeNewest => 'Newest first';

  @override
  String get sortContainersModeOldest => 'Oldest first';

  @override
  String get thumbnailCacheAppCacheLabel => 'App cache';

  @override
  String get thumbnailCacheAppCacheDesc =>
      'Stored encrypted in the App cache. Fast; cleared automatically under storage pressure.';

  @override
  String get thumbnailCacheInContainerLabel => 'Inside container';

  @override
  String get thumbnailCacheInContainerDesc =>
      'Stored inside the encrypted container. Protected by the container itself, but writes are slower.';

  @override
  String get thumbnailCacheDisabledLabel => 'Disabled';

  @override
  String get thumbnailCacheDisabledDesc =>
      'No disk cache. Thumbnails are re-generated on every load.';

  @override
  String get unlockContainerTitle => 'Unlock Container';

  @override
  String get containerFileSegment => 'Container File';

  @override
  String get folderVaultSegment => 'Folder Vault';

  @override
  String get enableButtonLabel => 'Enable';

  @override
  String get retryButtonLabelShort => 'Retry';

  @override
  String get locateFileButton => 'Locate File';

  @override
  String get authenticateButton => 'Authenticate';

  @override
  String get cancelUnlockButton => 'Cancel Unlock';

  @override
  String tryingKeyslotProgress(int attempted, int total) {
    return 'Trying keyslot $attempted of $total…';
  }

  @override
  String get tryingKeyslotSingle => 'Trying keyslot…';

  @override
  String verifyingCredentialProgress(int attempted, int total) {
    return 'Verifying credential $attempted of $total…';
  }

  @override
  String get verifyingCredentialSingle => 'Verifying credential…';

  @override
  String tryingAlgoSlot(String algo, String slotName) {
    return 'Trying $algo ($slotName)…';
  }

  @override
  String get hiddenVolumeSlotName => 'Hidden Volume';

  @override
  String get standardVolumeSlotName => 'Standard Volume';

  @override
  String get containerMissingSubtitle => 'File path could not be resolved';

  @override
  String get containerMissingBody =>
      'The container file may have been moved, deleted, or its host storage is currently disconnected.';

  @override
  String get connectPatternSequence => 'Connect your pattern sequence';

  @override
  String get passwordLabel => 'Password';

  @override
  String get enterVaultPasswordHint => 'Enter vault password';

  @override
  String get enterBitlockerPasswordHint => 'Enter password or recovery key';

  @override
  String get enterContainerPasswordHint => 'Enter container password';

  @override
  String get readOnlyModeUsbSubtitleDrive =>
      'Mount without allowing changes to this drive';

  @override
  String get rememberDriveLabel => 'Remember drive';

  @override
  String get rememberDriveSubtitle => 'Pin drive on dashboard for quick access';

  @override
  String get unlockVaultButtonLabel => 'Unlock Vault';

  @override
  String get cryfsStorageAccessWarning =>
      'CryFS vaults use thousands of small block files. Without Direct Storage Access, performance will be significantly slower.';

  @override
  String get folderVaultStorageAccessWarning =>
      'Direct Storage Access is disabled. Opening and reading files in folder vaults may be slower.';

  @override
  String get requestingPermission => 'Requesting permission…';

  @override
  String get unlockAndMountButton => 'Unlock & Mount';

  @override
  String get unlockDriveButton => 'Unlock Drive';

  @override
  String couldntFindDevice(String deviceName) {
    return 'Couldn\'t find \"$deviceName\"';
  }

  @override
  String get plugDriveBackInRetry =>
      'Plug the drive back in and tap Retry, or select it below if it shows up under a different name.';

  @override
  String get retryConnectionButton => 'Retry Connection';

  @override
  String get refreshDevicesButton => 'Refresh Devices';

  @override
  String get connectOtgDriveToMount => 'Connect an OTG flash drive to mount';

  @override
  String get alreadyActive => 'Already active';

  @override
  String get active => 'Active';

  @override
  String get readyToUnlock => 'Ready to unlock';

  @override
  String get enterUsbPartitionPassword => 'Enter USB partition password';

  @override
  String get biometricAuthenticationTitle => 'Biometric Authentication';

  @override
  String get biometricAuthUsbSubtitle =>
      'Authenticate to unlock and mount this USB device';

  @override
  String get connectPatternSequenceToMount =>
      'Connect your pattern sequence to mount';

  @override
  String get selectAllAction => 'Select All';

  @override
  String get clearSelectionAction => 'Clear Selection';

  @override
  String get clearSelectionTooltip => 'Clear selection';

  @override
  String get selectionOptionsTooltip => 'Selection options';

  @override
  String get readOnlyContainerTooltip => 'Read-only container';

  @override
  String get copyAction => 'Copy';

  @override
  String get moveAction => 'Move';

  @override
  String get renameAction => 'Rename';

  @override
  String get exportToDeviceAction => 'Export to device';

  @override
  String get openWithAppAction => 'Open with App';

  @override
  String get pinAction => 'Pin';

  @override
  String get pinSelectedAction => 'Pin selected';

  @override
  String get unpinAction => 'Unpin';

  @override
  String get unpinSelectedAction => 'Unpin selected';

  @override
  String get documentProviderSettingsMenu => 'Document Provider Settings';

  @override
  String get exposeAsDocumentProviderMenu => 'Expose as Document Provider';

  @override
  String get moreOptionsTooltipShort => 'More options';

  @override
  String get copyTooltip => 'Copy';

  @override
  String get searchInThisFolderHint => 'Search in this folder…';

  @override
  String get clearTooltip => 'Clear';

  @override
  String get backToDashboardTooltip => 'Back to dashboard';

  @override
  String get cancelPasteButton => 'Cancel paste';

  @override
  String get continueButton => 'Continue';

  @override
  String get skipButton => 'Skip';

  @override
  String get keepBothButton => 'Keep both';

  @override
  String get clearAllButton => 'Clear all';

  @override
  String get autoMountWhenUnlocksTitle => 'Auto-mount when container unlocks';

  @override
  String get autoMountWhenUnlocksSubtitle =>
      'Expose this folder again automatically next time';

  @override
  String get unmountButton => 'Unmount';

  @override
  String get filtersMenuItem => 'Filters';

  @override
  String get settingsMenuItem => 'Settings';

  @override
  String get sortOptionsTooltip => 'Sort options';

  @override
  String get layoutOptionsTooltip => 'Layout options';

  @override
  String get lockContainerTooltip => 'Lock container';

  @override
  String get renameTooltip => 'Rename';

  @override
  String get cancelUpdatingPasswordTooltip => 'Cancel updating password';

  @override
  String get unlockSettingsButton => 'Unlock Settings';

  @override
  String get updateSavedCredentialsButton => 'Update Saved Credentials';

  @override
  String get verifyCredentialsTitle => 'Verify Credentials';

  @override
  String get verifyButton => 'Verify';

  @override
  String get displayNameTitle => 'Display Name';

  @override
  String get containerNameHint => 'Container name';

  @override
  String get deleteFileDialogTitle => 'Delete file?';

  @override
  String get deleteFilePermanentWarning =>
      'This action is permanent and cannot be undone.';

  @override
  String get unsavedChangesTitle => 'Unsaved Changes';

  @override
  String get unsavedChangesMessage =>
      'You have unsaved changes. Would you like to save before closing?';

  @override
  String get discardButton => 'Discard';

  @override
  String get decryptingFileContent => 'Decrypting file content...';

  @override
  String get cannotOpenFile => 'Cannot open file';

  @override
  String get changesSavedSuccessfully => 'Changes saved successfully';

  @override
  String saveFailedWithError(String error) {
    return 'Save failed: $error';
  }

  @override
  String linesCount(int count) {
    return 'Lines: $count';
  }

  @override
  String charsCount(int count) {
    return 'Chars: $count';
  }

  @override
  String get unsavedChangesLabel => 'Unsaved Changes';

  @override
  String get savedToVault => 'Saved to vault';

  @override
  String get saveChangesTooltip => 'Save changes';

  @override
  String get textEditorDecryptFailedMessage =>
      'Failed to decrypt file from vault.';

  @override
  String get textEditorInvalidTextFileMessage =>
      'The file does not appear to be a valid text file.';

  @override
  String get textEditorWriteBackFailedMessage =>
      'Failed to write file back to vault.';

  @override
  String get backTooltip => 'Back';

  @override
  String get forwardTooltip => 'Forward';

  @override
  String get reloadTooltip => 'Reload';

  @override
  String get optionsTooltip => 'Options';

  @override
  String get htmlViewerErrorTitle => 'Cannot display this page';

  @override
  String get htmlViewerLoadFailedMessage => 'Failed to load file';

  @override
  String get enableJavaScriptDialogTitle => 'Enable JavaScript?';

  @override
  String get enableJavaScriptDialogMessage =>
      'The page will be allowed to run its own local scripts. It still has no network access — nothing in this vault can be sent or received over the internet.';

  @override
  String get disableJavaScriptMenu => 'Disable JavaScript';

  @override
  String get enableJavaScriptMenu => 'Enable JavaScript';

  @override
  String get enterFullscreenMenu => 'Enter Fullscreen';

  @override
  String failedToOpenExternalApp(String error) {
    return 'Failed to open in external app: $error';
  }

  @override
  String get thisFolderMenu => 'This Folder';

  @override
  String get allInclSubfoldersMenu => 'All (Incl. Subfolders)';

  @override
  String get disableShuffleMenu => 'Disable Shuffle';

  @override
  String get shufflePlaylistMenu => 'Shuffle Playlist';

  @override
  String get playlistOptionsTooltip => 'Playlist Options';

  @override
  String get enablePlaylistTooltip => 'Enable Playlist';

  @override
  String get moreActionsTooltip => 'More Actions';

  @override
  String get forcePortraitMenu => 'Force Portrait';

  @override
  String get forceLandscapeMenu => 'Force Landscape';

  @override
  String get autoRotateSensorMenu => 'Auto-Rotate (Sensor)';

  @override
  String get screenOrientationMenu => 'Screen Orientation';

  @override
  String get playlistTransitionMenu => 'Playlist Transition';

  @override
  String get deleteFileMenu => 'Delete File';

  @override
  String get thumbnailCarouselTooltip => 'Thumbnail Carousel';

  @override
  String get advancedSettingsTooltip => 'Advanced Settings';

  @override
  String get previousTooltip => 'Previous';

  @override
  String get nextTooltip => 'Next';

  @override
  String get diagnosticsCopiedToClipboard => 'Diagnostics copied to clipboard';

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get copyDiagnosticsTooltip => 'Copy diagnostics';

  @override
  String get closeTooltip => 'Close';

  @override
  String get diagnosticsPlaybackSection => 'Playback';

  @override
  String get diagnosticsEngineSection => 'Engine';

  @override
  String get diagnosticsStateLabel => 'State';

  @override
  String get diagnosticsResolutionLabel => 'Resolution';

  @override
  String get diagnosticsAspectRatioLabel => 'Aspect Ratio';

  @override
  String get diagnosticsPositionLabel => 'Position';

  @override
  String get diagnosticsDurationLabel => 'Duration';

  @override
  String get diagnosticsErrorLabel => 'Error';

  @override
  String get diagnosticsPlayerLabel => 'Player';

  @override
  String get diagnosticsDecodingLabel => 'Decoding';

  @override
  String get diagnosticsExoPlayerValue => 'ExoPlayer (Android)';

  @override
  String get diagnosticsHardwareAcceleratedValue => 'Hardware-accelerated';

  @override
  String get diagnosticsUnknownValue => 'Unknown';

  @override
  String get diagnosticsStateBuffering => 'Buffering';

  @override
  String get diagnosticsStatePlaying => 'Playing';

  @override
  String get diagnosticsStatePaused => 'Paused';

  @override
  String get diagnosticsDurationUnavailable => '--:--';

  @override
  String get rotate90Label => 'Rotate 90°';

  @override
  String get imageFitModeLabel => 'Image Fit Mode';

  @override
  String get slideshowDelayLabel => 'Slideshow Delay';

  @override
  String get playbackSpeedLabel => 'Playback Speed';

  @override
  String get subtitlesLabel => 'Subtitles';

  @override
  String get imageSettingsTitle => 'Image Settings';

  @override
  String get playbackSettingsTitle => 'Playback Settings';

  @override
  String get imageFitContain => 'Contain';

  @override
  String get imageFitWidth => 'Fit Width';

  @override
  String get imageFitHeight => 'Fit Height';

  @override
  String nSecondsDelay(int n) {
    return '$n seconds';
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
  String get settingsTooltipShort => 'Settings';

  @override
  String get sourceCodeTooltip => 'Source Code';

  @override
  String get donateTooltip => 'Donate';

  @override
  String get shareAppTooltip => 'Share App';

  @override
  String get resetToDefaultsTooltip => 'Reset to defaults';

  @override
  String get usbUnlockContainerTitle => 'Unlock USB Container';

  @override
  String get usbMountContainerTitle => 'Mount USB Drive';

  @override
  String get staticLabel => 'Static';

  @override
  String get unmuteTooltip => 'Unmute';

  @override
  String get muteTooltip => 'Mute';

  @override
  String get playOnceDisabledTooltip => 'Play Once (Auto-Advance Disabled)';

  @override
  String get playAndAdvanceTooltip => 'Play & Advance to Next';

  @override
  String get loopCurrentVideoTooltip => 'Loop Current Video';

  @override
  String get clearThumbnailCacheDialogTitle => 'Clear Thumbnail Cache?';

  @override
  String get clearThumbnailCacheDialogMessage =>
      'This will delete cached thumbnails for this vault. They will be regenerated the next time you browse media.';

  @override
  String get clearCacheButton => 'Clear Cache';

  @override
  String get appCacheClearedUnlockMessage =>
      'App cache cleared. Unlock container to clear inside cache.';

  @override
  String get allThumbnailCachesClearedMessage =>
      'All thumbnail caches cleared successfully.';

  @override
  String get appCacheClearedContainerFailedMessage =>
      'App cache cleared, but failed to clear inside container.';

  @override
  String get failedToClearThumbnailCachesMessage =>
      'Failed to clear thumbnail caches.';

  @override
  String get authenticateToModifySettingsPrompt =>
      'Authenticate to modify settings';

  @override
  String get usbVaultSettingsTitle => 'USB Vault Settings';

  @override
  String get vaultSettingsTitle => 'Vault Settings';

  @override
  String get generalSectionHeader => 'General';

  @override
  String get securityCredentialsSectionHeader => 'Security & Credentials';

  @override
  String get securityOptionsLockedTitle => 'Security Options Locked';

  @override
  String get authenticateOriginalCredentialsMessage =>
      'Authenticate with original container credentials to modify security settings.';

  @override
  String get unlockCredentialsLabel => 'Unlock Credentials';

  @override
  String get unavailableSuffixLabel => '(Unavailable)';

  @override
  String get patternSetupRequiredBeforeSaving =>
      'Set up a pattern before saving.';

  @override
  String get passwordKeystoreEncryptedHelperText =>
      'Password is encrypted using Android Keystore. Leave blank if using keyfiles only.';

  @override
  String get changePatternButton => 'Change Pattern';

  @override
  String get setPatternButton => 'Set Pattern';

  @override
  String get cacheDerivedKeyLabel => 'Cache Derived Key';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      'Skip CryFS\'s scrypt KDF next time (key kept in Android Keystore)';

  @override
  String get reuseKeyMaterialKeystoreSubtitle =>
      'Reuse key material in Android Keystore';

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle =>
      'Pin algorithm to skip auto-detection on unlock.';

  @override
  String get changeContainerPasswordTitle => 'Change Container Password';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      'BitLocker credentials cannot be changed in-app. Use \"Manage BitLocker\" on Windows.';

  @override
  String get systemIntegrationSectionHeader => 'System & Integration';

  @override
  String get autoLockDurationLabel => 'Auto-Lock Duration';

  @override
  String get neverAutoLockOption => 'Never';

  @override
  String get exposeContentToFilePickerSubtitle =>
      'Expose content to System File Picker when unlocked';

  @override
  String get thumbnailStorageSectionHeader => 'Thumbnail Storage';

  @override
  String get cacheModeLabel => 'Cache Mode';

  @override
  String get useGlobalDefaultSubtitle => 'Use global default';

  @override
  String get thumbnailQualityLabel => 'Thumbnail Quality';

  @override
  String get clearThumbnailCacheTitle => 'Clear Thumbnail Cache';

  @override
  String get removeCachedThumbnailsSubtitle =>
      'Remove cached image and video thumbnails';

  @override
  String get patternSetupRequiredAboveBeforeSaving =>
      'Set up a pattern above before saving.';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      'A password or \"Cache Derived Key\" with keyfiles is required for this unlock method.';

  @override
  String get saveConfigurationButton => 'Save Configuration';

  @override
  String get incorrectPatternError => 'Incorrect pattern';

  @override
  String get verifyPatternTitle => 'Verify Pattern';

  @override
  String get incorrectPasswordError => 'Incorrect password';

  @override
  String get verificationFailedError => 'Verification failed';

  @override
  String get incorrectCredentialsError => 'Incorrect credentials';

  @override
  String get containerPasswordOptionalLabel =>
      'Container password (optional for keyfile-only)';

  @override
  String get pimOptionalLabel => 'PIM (optional)';

  @override
  String get usbDriveLockedLabel => 'USB Drive · Locked';

  @override
  String get lockedContainerLabel => 'Locked container';

  @override
  String get operationInProgressWaitMessage =>
      'An operation is in progress. Please wait before locking.';

  @override
  String get reconnectUsbTooltip => 'Reconnect USB';

  @override
  String get unlockContainerTooltip => 'Unlock container';

  @override
  String lockFailedMessage(String errorType) {
    return 'Lock failed: $errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired =>
      'New password or keyfiles are required.';

  @override
  String get newPasswordsDoNotMatch => 'New passwords do not match.';

  @override
  String get passwordChangedSuccessfullyMessage =>
      'Password changed successfully.';

  @override
  String get failedToChangePasswordMessage =>
      'Failed to change password. Check old credentials.';

  @override
  String get currentCredentialsSectionHeader => 'Current Credentials';

  @override
  String get oldPasswordLabel => 'Old Password';

  @override
  String get oldPimOptionalLabel => 'Old PIM (Optional)';

  @override
  String get newCredentialsSectionHeader => 'New Credentials';

  @override
  String get newPimOptionalLabel => 'New PIM (Optional)';

  @override
  String get noContainersYetTitle => 'No containers yet';

  @override
  String get dashboardEmptyStateMessage =>
      'Mount a VeraCrypt container, connect a USB drive, or create a brand-new encrypted vault to get started.';

  @override
  String get sortFieldName => 'Name';

  @override
  String get sortFieldSize => 'Size';

  @override
  String get sortFieldType => 'Type';

  @override
  String get sortFieldDate => 'Date';

  @override
  String get layoutModeDetailedList => 'Detailed List';

  @override
  String get layoutModeCompactList => 'Compact List';

  @override
  String get layoutModeGalleryGrid => 'Gallery Grid';

  @override
  String get readOnlyCantDeleteTooltip => 'Read-only — can\'t delete';

  @override
  String get readOnlyCantMoveTooltip => 'Read-only — can\'t move';

  @override
  String get readOnlyCantRenameTooltip => 'Read-only — can\'t rename';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes (calculating…)';
  }

  @override
  String get sizeCalculatingLabel => 'calculating…';

  @override
  String get editSecureItemsToRenameMessage =>
      'Edit secure items to rename them';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage =>
      'Vault items cannot be opened in external apps';

  @override
  String get mountedReadOnlyTooltip => 'Mounted read-only';

  @override
  String get readOnlyBadgeAbbreviation => 'RO';

  @override
  String freeSpaceLabel(String bytes) {
    return '$bytes free';
  }

  @override
  String get filteredLabel => 'filtered';

  @override
  String get statsStorageSectionHeader => 'STORAGE';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders',
      one: '1 folder',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => 'All Files';

  @override
  String get filterImagesOption => 'Images';

  @override
  String get filterVideosOption => 'Videos';

  @override
  String get filterAudioOption => 'Audio';

  @override
  String get filterDocumentsOption => 'Documents';

  @override
  String get folderExposedAsStorageExplanation =>
      'This folder is exposed as its own storage location, so other apps can browse and open its files directly.';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items already exist',
      one: '1 item already exists',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle =>
      'Choose what happens to each item, or apply one choice to all.';

  @override
  String get skipAllChipLabel => 'Skip all';

  @override
  String get overwriteAllChipLabel => 'Overwrite all';

  @override
  String get overwriteItemDropdownLabel => 'Overwrite';

  @override
  String get overwriteFolderDropdownLabel => 'Overwrite folder';

  @override
  String get fileOpsTransfersInProgressTitle => 'Transfers in progress';

  @override
  String get fileOpsRecentTransfersTitle => 'Recent transfers';

  @override
  String get fileOpsNoRecentTransfersMessage => 'No recent transfers';

  @override
  String get fileOpsCancelTooltip => 'Cancel';

  @override
  String get fileOpsRootDestinationLabel => 'Root';

  @override
  String get fileOpsCancelledStatusLabel => 'Cancelled';

  @override
  String fileOpsItemsFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items failed:',
      one: '1 item failed:',
    );
    return '$_temp0';
  }

  @override
  String fileOpsMoreItemsLabel(num count) {
    return '+ $count more';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return 'Error reading file: $error';
  }

  @override
  String get archivePreviewNotAvailableMessage =>
      'Preview not available for this file type.';

  @override
  String get avifFailedToRenderMessage => 'Failed to render AVIF';

  @override
  String get encryptedImageLoadFailedMessage =>
      'Failed to load encrypted image';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return 'Failed to load encrypted image: $error';
  }

  @override
  String get retryButton => 'Retry';

  @override
  String get invalidOrCorruptedImageMessage =>
      'Invalid or corrupted image format.';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '$current of $total';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '$current of $total  ·  scanning…';
  }

  @override
  String get mediaViewerScanningLabel => 'Scanning…';

  @override
  String get mediaFileDeletedMessage => 'File deleted successfully';

  @override
  String get mediaFileDeleteFailedMessage => 'Failed to delete file';

  @override
  String get aboutScreenTitle => 'About';

  @override
  String get couldNotOpenLinkMessage => 'Could not open link';

  @override
  String get fileManagerSettingsTitle => 'File Manager Settings';

  @override
  String get showMediaThumbnailsLabel => 'Show Media Thumbnails';

  @override
  String get showMediaThumbnailsDesc =>
      'Display thumbnail previews for images and videos in list view';

  @override
  String get showFileNamesLabel => 'Show File Names';

  @override
  String get showFileNamesDesc =>
      'Display text labels under items in grid layout';

  @override
  String get showBreadcrumbBarLabel => 'Show Breadcrumb Bar';

  @override
  String get showBreadcrumbBarDesc => 'Path navigation bar at top of browser';

  @override
  String get showStatsBarLabel => 'Show Stats Bar';

  @override
  String get showStatsBarDesc => 'File count and free space info banner';

  @override
  String get autoStartPlaylistModeLabel => 'Auto-start Playlist Mode';

  @override
  String get autoStartPlaylistModeDesc =>
      'Automatically start in playlist mode when opening a media item';

  @override
  String get showPlaylistCarouselLabel => 'Show Playlist Carousel';

  @override
  String get showPlaylistCarouselDesc =>
      'Show thumbnail carousel button when viewing media playlists';

  @override
  String get videoPlaybackSliderLabel => 'Video playback position slider';

  @override
  String get longPressPlaybackDiagnosticsHint =>
      'Long press for playback diagnostics';

  @override
  String get staticImageModeLabel => 'Static image mode';

  @override
  String slideshowModeActiveLabel(int seconds) {
    return 'Slideshow mode active with $seconds seconds delay';
  }

  @override
  String videoPlaybackModeLabel(String mode) {
    return 'Video playback mode: $mode';
  }

  @override
  String get pauseLabel => 'Pause';

  @override
  String get playLabel => 'Play';

  @override
  String get emptyFolderTitle => 'Empty Folder';

  @override
  String get emptyFolderMessage =>
      'Use the Add action to create files or import from device.';

  @override
  String get noResultsTitle => 'No results';

  @override
  String noResultsForQueryMessage(String query) {
    return 'Nothing in this folder matches \"$query\".';
  }

  @override
  String get closeCarouselTooltip => 'Close Carousel';

  @override
  String get playlistScrollModeMenu => 'Playlist Scroll Mode';

  @override
  String get playlistScrollHorizontalLabel => 'Horizontal';

  @override
  String get playlistScrollVerticalPageLabel => 'Vertical Paged';

  @override
  String get playlistScrollVerticalContinuousLabel => 'Vertical Continuous';

  @override
  String get undoTooltip => 'Undo';

  @override
  String get redoTooltip => 'Redo';

  @override
  String get autosavingLabel => 'Autosaving…';

  @override
  String get savingLabel => 'Saving…';

  @override
  String autosavedAtLabel(String time) {
    return 'Autosaved at $time';
  }

  @override
  String cameraDisconnectedError(String message) {
    return 'Camera disconnected: $message';
  }

  @override
  String get unknownErrorFallback => 'unknown error';

  @override
  String get cameraPermissionsRequiredMessage =>
      'Camera and microphone permissions are required to use the camera.';

  @override
  String cameraErrorMessage(String error) {
    return 'Camera error: $error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage => 'Photo capture failed';

  @override
  String get cameraRecordingFailedMessage => 'Recording failed';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return 'Recording failed: $error';
  }

  @override
  String get cameraRecordingTooShortMessage =>
      'Recording was too short to save';

  @override
  String get cameraCouldNotSaveRecordingMessage => 'Could not save recording';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return 'Could not save recording: $error';
  }

  @override
  String get cameraCouldNotSwitchLensMessage => 'Could not switch lens';

  @override
  String get cameraEncryptingPhotoLabel => 'Encrypting photo…';

  @override
  String get cameraEncryptingVideoLabel => 'Encrypting video…';

  @override
  String get aboutApplicationSectionHeader => 'Application';

  @override
  String get aboutTagline => 'Free · Open Source · Offline Encrypted Vault';

  @override
  String get aboutVersionTitle => 'Version';

  @override
  String aboutVersionSubtitle(String version) {
    return 'v$version · Tap to copy version info for bug reports';
  }

  @override
  String get aboutWhatsNewTitle => 'What\'s New';

  @override
  String get aboutWhatsNewSubtitle => 'See recent changes and release notes';

  @override
  String get aboutPrivacySecurityTitle => 'Privacy & Security';

  @override
  String get aboutPrivacySecuritySubtitle =>
      'Zero-trust, 100% offline, local memory security design';

  @override
  String get aboutSupportedFormatsSectionHeader => 'Supported Formats';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt & LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      'Standard & hidden volumes, custom PIM, keyfiles, xts-plain64, Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker & BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle =>
      'User passphrases and 48-digit numerical recovery key support';

  @override
  String get aboutDirectoryVaultsTitle => 'Directory Vaults';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator (v7/v8 SIV_GCM & SIV_CTRMAC), gocryptfs (v2 AES-GCM & XChaCha20), CryFS (v0.10+ XChaCha20 & AES)';

  @override
  String get aboutVhdTitle => 'Virtual Hard Disks (VHD / VHDX)';

  @override
  String get aboutVhdSubtitle =>
      'BAT translation for fixed and dynamic expandable disk images';

  @override
  String get aboutNativeCoreEngineSectionHeader => 'Native Core Engine';

  @override
  String get aboutCompiledLibrariesTitle => 'Compiled C++ Libraries';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.0 (ARMv8 Hardware Crypto & SHA-2)\n• libavif & libgav1 (Native AVIF Image Decoder)\n• ChaN FatFs v4.0.4 (FAT12/16/32 & exFAT)\n• Tuxera NTFS-3G & embedded mkntfs\n• e2fsprogs v1.47.4 libext2fs (ext2/ext3/ext4)\n• Dislocker Virtual I/O (BitLocker FVE / To Go)\n• VeraCrypt 1.26.29 (Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id/i)\n• cJSON v1.7.18 (LUKS2 & Cryptomator metadata)';

  @override
  String get aboutCommunitySectionHeader => 'Community & Open Source';

  @override
  String get aboutReportIssueTitle => 'Report an Issue';

  @override
  String get aboutReportIssueSubtitle =>
      'Found a bug? Submit an issue on GitHub';

  @override
  String get aboutContributorsTitle => 'Contributors';

  @override
  String get aboutContributorsSubtitle =>
      'People who helped build VaultExplorer';

  @override
  String get aboutLicensesTitle => 'Open Source Licenses';

  @override
  String get aboutLicensesSubtitle => 'Third-party libraries used in this app';

  @override
  String get aboutFooterMadeWithLove => 'Made with ❤ for privacy.';

  @override
  String get aboutVersionCopiedMessage =>
      'Version info copied — handy for bug reports';

  @override
  String aboutVersionClipboardText(String version) {
    return 'VaultExplorer v$version (Android)';
  }

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer — a free, open-source, offline vault for Android.\n\nStore passwords, notes, and files inside an encrypted container (VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs, CryFS).\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage =>
      'Copied a shareable link to your clipboard';

  @override
  String get aboutPrivacySheetTitle => 'Privacy & Data Security';

  @override
  String get aboutPrivacySheetSubtitle =>
      '100% offline, local memory security design';

  @override
  String get privacyPointNoNetworkTitle => 'No network access required';

  @override
  String get privacyPointNoNetworkBody =>
      'VaultExplorer does not request the android.permission.INTERNET permission on Android. It cannot communicate over any network.';

  @override
  String get privacyPointNoDiskLeaksTitle => 'Zero unencrypted disk leaks';

  @override
  String get privacyPointNoDiskLeaksBody =>
      'Decryption and re-encryption happen entirely in system memory. Temporary unencrypted files are never saved to device storage.';

  @override
  String get privacyPointNoAnalyticsTitle => 'No analytics or telemetry';

  @override
  String get privacyPointNoAnalyticsBody =>
      'There is zero crash reporting, usage tracking, or third-party SDK collecting data about you or your device.';

  @override
  String get privacyPointKeystoreTitle => 'Secrets stay in Android Keystore';

  @override
  String get privacyPointKeystoreBody =>
      'Remembered passwords, patterns, and cached derived keys are sealed using AES-256-GCM in the hardware-backed Android Keystore.';

  @override
  String get privacyPointPosixTitle => 'POSIX Acceleration & Storage Access';

  @override
  String get privacyPointPosixBody =>
      'Files inside container volumes are read and written locally. Bypasses SAF when direct path access is available for up to 1000x faster I/O.';

  @override
  String get privacyPointScreenClipboardTitle =>
      'Screen & Clipboard Protection';

  @override
  String get privacyPointScreenClipboardBody =>
      'Screenshot/task-switcher preview blocking (FLAG_SECURE) and automatic corrupt clipboard sanitization upon window focus.';

  @override
  String get privacyPointExternalLinksTitle => 'External links open in browser';

  @override
  String get privacyPointExternalLinksBody =>
      'Tapping links hands off to your default browser app, which handles the request.';

  @override
  String get truncatedListingWarning =>
      'Showing first 50,000 items — this folder has more files.';

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '$size px · $quality% quality';
  }

  @override
  String holdToSpeedIndicatorLabel(String speed) {
    return '$speed× Speed';
  }

  @override
  String get toolbarLayoutSectionHeader => 'Toolbar Layout';

  @override
  String get listViewOptionsSectionHeader => 'List View Options';

  @override
  String get detailedListViewColumnsSectionHeader =>
      'Detailed List View Columns';

  @override
  String get galleryGridViewSectionHeader => 'Gallery Grid View';

  @override
  String get browserLayoutSectionHeader => 'Browser Layout';

  @override
  String get mediaViewerSectionHeader => 'Media Viewer';

  @override
  String get viewModeAction => 'View mode';

  @override
  String get sortAction => 'Sort';

  @override
  String get playMediaAction => 'Play media';

  @override
  String containerSpaceSummary(String free, String total) {
    return '$free free · $total total';
  }

  @override
  String volMountedSummary(int volId) {
    return 'Vol $volId · Mounted';
  }

  @override
  String get incorrectPasswordOrKeyfilesDriveError =>
      'Incorrect password/keyfiles or unsupported drive';

  @override
  String driveUsableCapacity(int mb) {
    return 'Drive usable capacity: $mb MB. Must not exceed this.';
  }

  @override
  String get unlockMethodManualPassword => 'Manual Password';

  @override
  String get unlockMethodRememberPassword => 'Remember Password';

  @override
  String get unlockMethodBiometrics => 'Biometric Unlock';

  @override
  String get unlockMethodPattern => 'Pattern Unlock';

  @override
  String get unlockMethodSubtitlePassword => 'Type the password every time';

  @override
  String get unlockMethodSubtitleRememberPassword =>
      'Stored securely in Android Keystore';

  @override
  String get unlockMethodSubtitleBiometrics =>
      'Use fingerprint or face to unlock';

  @override
  String get unlockMethodSubtitlePattern => 'Draw a pattern to unlock';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError =>
      'Video decoder unavailable — hardware codec contention';

  @override
  String get mediaStreamInitFailedError => 'Media stream initialization failed';

  @override
  String get invalidAvifImage => 'Invalid AVIF image';

  @override
  String get verbImport => 'Import';

  @override
  String get verbMove => 'Move';

  @override
  String get verbCopy => 'Copy';

  @override
  String get verbImported => 'Imported';

  @override
  String get verbMoved => 'Moved';

  @override
  String get verbCopied => 'Copied';

  @override
  String get verbImporting => 'Importing';

  @override
  String get verbMoving => 'Moving';

  @override
  String get verbCopying => 'Copying';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items $verb',
      one: '1 item $verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return '$count skipped';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return '$count failed';
  }

  @override
  String get statusCancelled => 'Cancelled';

  @override
  String get statusFailed => 'Failed';

  @override
  String get statusCompleted => 'Completed';

  @override
  String get fileOpCheckingSpace => 'Checking available space…';

  @override
  String get fileOpResolvingConflicts => 'Resolving conflicts…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return 'Not enough space — need $required, only $free free';
  }

  @override
  String get fileOpDiskFullPartialRemoved =>
      'Disk full — partial files removed';

  @override
  String get fileOpMoveFailed => 'Move failed';

  @override
  String get fileOpCopyFailed => 'Copy failed';

  @override
  String get fileOpDiskFull => 'Disk full';

  @override
  String get fileOpImporting => 'Importing…';

  @override
  String fileOpImportingName(String name) {
    return 'Importing $name…';
  }

  @override
  String fileOpMovingName(String name) {
    return 'Moving $name…';
  }

  @override
  String fileOpCopyingName(String name) {
    return 'Copying $name…';
  }

  @override
  String get searchInSubfoldersHint => 'Search all subfolders…';

  @override
  String get deepSearchEnabledTooltip =>
      'Searching subfolders — tap for current folder only';

  @override
  String get deepSearchDisabledTooltip =>
      'Searching current folder — tap to search subfolders';

  @override
  String get filterAction => 'Filter';

  @override
  String get favouriteAction => 'Favourite';

  @override
  String get unfavouriteAction => 'Unfavourite';

  @override
  String get favouriteSelectedAction => 'Favourite selected';

  @override
  String get unfavouriteSelectedAction => 'Unfavourite selected';

  @override
  String favouritedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Favourited $count items',
      one: 'Favourited 1 item',
    );
    return '$_temp0';
  }

  @override
  String unfavouritedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Unfavourited $count items',
      one: 'Unfavourited 1 item',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => 'Show Bookmark Bar';

  @override
  String get showBookmarkBarDesc =>
      'Display favourite items in a bookmark bar or sidebar';

  @override
  String get bookmarkBarSectionHeader => 'Bookmark Bar & Favourites';

  @override
  String get noBookmarksYet => 'No favourite items bookmarked yet';

  @override
  String get reorderBookmarksTitle => 'Rearrange Bookmarks';

  @override
  String get reorderBookmarksDesc =>
      'Drag items to reorder them in the bookmark bar';

  @override
  String get navBarVaultsLabel => 'Vaults';

  @override
  String get navBarToolsLabel => 'Tools';

  @override
  String get toolsScreenTitle => 'Tools';

  @override
  String get toolsSectionContainerUtilities => 'Container Utilities';

  @override
  String get toolsSectionFileCryptography => 'File Cryptography';

  @override
  String get toolsSectionStorageDiagnostics => 'Storage & Diagnostics';

  @override
  String get toolContainerSplitterTitle => 'Split & Join';

  @override
  String get toolContainerSplitterSubtitle =>
      'Split a container into chunks, or rejoin them';

  @override
  String get toolContainerRepairTitle => 'Check & Repair';

  @override
  String get toolContainerRepairSubtitle =>
      'Diagnose header or filesystem issues';

  @override
  String get toolSingleFileCryptoTitle => 'Encrypt / Decrypt Files';

  @override
  String get toolSingleFileCryptoSubtitle =>
      'Protect one or more files without a full container';

  @override
  String get toolStorageAnalyzerTitle => 'Storage Analyzer';

  @override
  String get toolStorageAnalyzerSubtitle =>
      'See what\'s taking up space in a mounted vault';

  @override
  String get toolNotImplementedYetMessage =>
      'This tool isn\'t wired up to the native engine yet — check back in a future update.';

  @override
  String get splitJoinModeSplit => 'Split';

  @override
  String get splitJoinModeJoin => 'Join';

  @override
  String get splitSourceFileLabel => 'Source File';

  @override
  String get splitDestinationFolderLabel => 'Destination Folder';

  @override
  String get splitChunkSizeLabel => 'Chunk Size';

  @override
  String get splitChunkSizeCustomLabel => 'Custom size (MB)';

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
  String get splitChunkSizeCustom => 'Custom';

  @override
  String get splitContainerButton => 'Split Container';

  @override
  String get joinFirstPartLabel => 'First Part';

  @override
  String get joinOutputFileNameLabel => 'Output File Name';

  @override
  String get joinContainerButton => 'Join Files';

  @override
  String get chooseFileButton => 'Choose File';

  @override
  String get chooseFolderButton => 'Choose Folder';

  @override
  String get noFileSelectedLabel => 'No file selected';

  @override
  String get noFolderSelectedLabel => 'No folder selected';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage => 'Container split successfully';

  @override
  String get joinContainerSuccessMessage => 'Files joined successfully';

  @override
  String get cryptoDirectionEncrypt => 'Encrypt';

  @override
  String get cryptoDirectionDecrypt => 'Decrypt';

  @override
  String get singleFileCryptoInputFileLabel => 'Input Files';

  @override
  String get singleFileCryptoCipherLabel => 'Cipher';

  @override
  String get singleFileCryptoDeleteOriginalLabel =>
      'Delete original files after encryption';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Encrypt $count Files',
      one: 'Encrypt File',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Decrypt $count Files',
      one: 'Decrypt File',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Done — $count files processed',
      one: 'Done',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return '$succeeded of $total files processed — $failed failed';
  }

  @override
  String get singleFileCryptoAddFilesButton => 'Add Files';

  @override
  String get singleFileCryptoClearFilesButton => 'Clear';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files selected',
      one: '1 file selected',
      zero: 'No files selected',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return 'File $current of $total';
  }

  @override
  String get repairTargetStepTitle => 'Choose a Target';

  @override
  String get repairTargetUnmountedFileOption => 'Unmounted File';

  @override
  String get repairTargetUnmountedFileSubtitle =>
      'Restore a backup header on a container you haven\'t opened';

  @override
  String get repairTargetMountedVolumeSubtitle =>
      'Run a filesystem check on an already-open vault';

  @override
  String get repairNoMountedVolumes => 'No vaults are currently mounted';

  @override
  String get repairScanButton => 'Run Diagnostic Scan';

  @override
  String get repairChangeTargetButton => 'Change Target';

  @override
  String get repairDiagnosisHealthy => 'No issues found';

  @override
  String get repairDiagnosisHeaderCorrupted => 'Header Corrupted';

  @override
  String get repairDiagnosisFilesystemDirty =>
      'Filesystem Dirty / Unclean Unmount';

  @override
  String get repairRestoreBackupHeaderButton => 'Restore Backup Header';

  @override
  String get repairRunFilesystemCheckButton => 'Run Filesystem Check & Fix';

  @override
  String get repairActionSucceededMessage => 'Repair completed successfully';

  @override
  String get repairActionFailedMessage => 'Repair action did not succeed';

  @override
  String get storageAnalyzerTargetLabel => 'Volume';

  @override
  String get storageAnalyzerNoTargetsTitle => 'Nothing to Analyze';

  @override
  String get storageAnalyzerNoTargetsMessage =>
      'Mount a vault first, then come back here to see its storage breakdown.';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return '$used of $total used';
  }

  @override
  String get storageAnalyzerHeaviestFilesHeader => 'Heaviest Files';

  @override
  String get storageAnalyzerBreakdownHeader => 'By File Type';

  @override
  String get storageAnalyzerScanningMessage => 'Scanning volume…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return 'Scan stopped early after $count files — results may be incomplete.';
  }

  @override
  String get storageAnalyzerNoFilesFound => 'No files found';

  @override
  String get storageCategoryImages => 'Images';

  @override
  String get storageCategoryVideos => 'Videos';

  @override
  String get storageCategoryAudio => 'Audio';

  @override
  String get storageCategoryDocuments => 'Documents';

  @override
  String get storageCategoryArchives => 'Archives';

  @override
  String get storageCategoryOther => 'Other';
}
