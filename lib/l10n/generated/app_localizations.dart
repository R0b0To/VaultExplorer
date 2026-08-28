import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_uk.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('pt'),
    Locale('uk'),
    Locale('zh'),
  ];

  /// Generic Cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Generic Close action label
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Generic Search action/tooltip label
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Generic back navigation button label
  ///
  /// In en, this message translates to:
  /// **'Go back'**
  String get goBack;

  /// Generic X of Y counter, e.g. page 2 of 10 or search match 1 of 3
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String xOfYCounter(int current, int total);

  /// Dialog title for jumping to a specific PDF page
  ///
  /// In en, this message translates to:
  /// **'Go to page'**
  String get pdfViewerGoToPageTitle;

  /// Hint text showing the valid page range
  ///
  /// In en, this message translates to:
  /// **'Page number (1 - {pageCount})'**
  String pdfViewerPageNumberHint(int pageCount);

  /// Text field label for page number input
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get pdfViewerPageLabel;

  /// Confirm button label for the go-to-page dialog
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get pdfViewerGoButton;

  /// Hint text for the PDF in-document search field
  ///
  /// In en, this message translates to:
  /// **'Search in document'**
  String get pdfViewerSearchHint;

  /// Shown when a PDF text search finds no results
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get pdfViewerNoMatches;

  /// Tooltip for the previous search match button
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get pdfViewerPreviousMatch;

  /// Tooltip for the next search match button
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get pdfViewerNextMatch;

  /// Tooltip for closing the PDF search bar
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get pdfViewerCloseSearch;

  /// Tooltip for the print action
  ///
  /// In en, this message translates to:
  /// **'Print document'**
  String get pdfViewerPrintTooltip;

  /// Loading state message while a PDF loads
  ///
  /// In en, this message translates to:
  /// **'Loading document…'**
  String get pdfViewerLoadingDocument;

  /// Error title shown when a PDF fails to load
  ///
  /// In en, this message translates to:
  /// **'Cannot open PDF'**
  String get pdfViewerCannotOpenTitle;

  /// Fallback error message when the platform view reports an error without a message
  ///
  /// In en, this message translates to:
  /// **'Failed to load PDF'**
  String get pdfViewerFailedToLoad;

  /// Tooltip for the button that switches the PDF viewer into edit mode
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get pdfViewerEditTooltip;

  /// Tooltip for the button that saves and exits PDF edit mode
  ///
  /// In en, this message translates to:
  /// **'Done editing'**
  String get pdfViewerDoneEditingTooltip;

  /// Snackbar message when re-encrypting an edited PDF back into the vault fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save changes to this PDF'**
  String get pdfViewerSaveFailed;

  /// Snackbar message when the native PDF viewer's own edit button is tapped for a document that doesn't support in-app editing (e.g. a local/SAF file, not a vault-backed one)
  ///
  /// In en, this message translates to:
  /// **'Editing isn\'t available for this document'**
  String get pdfViewerEditUnavailable;

  /// Generic Paste action label
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// Generic Clear action label
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Verb shown when the clipboard holds a cut (move) operation
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get clipboardVerbMove;

  /// Verb shown when the clipboard holds a copy operation
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get clipboardVerbCopy;

  /// Tooltip for the AppBar clipboard chip when a paste target is available
  ///
  /// In en, this message translates to:
  /// **'{verb} ({count}) — Tap details, long press to paste'**
  String clipboardTooltipInteractive(String verb, int count);

  /// Tooltip for the AppBar clipboard chip when no paste target is available
  ///
  /// In en, this message translates to:
  /// **'{verb} ({count}) — Clipboard details'**
  String clipboardTooltipViewOnly(String verb, int count);

  /// Shows which vault/container the clipboard contents came from
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String clipboardSourceLabel(String source);

  /// Fallback source name shown when the clipboard source container has no display name
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get clipboardDefaultSourceName;

  /// Header showing the clipboard verb and item count
  ///
  /// In en, this message translates to:
  /// **'{verb} {count, plural, =1{1 item} other{{count} items}}'**
  String clipboardHeaderCount(String verb, num count);

  /// Overflow indicator when more clipboard items exist than shown in the preview
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{+1 more item} other{+{count} more items}}'**
  String clipboardMoreItems(num count);

  /// Expansion tile title for PIM/cipher/hash advanced options
  ///
  /// In en, this message translates to:
  /// **'Advanced Parameters'**
  String get advancedParametersTitle;

  /// Label for the optional PIM (Personal Iterations Multiplier) field
  ///
  /// In en, this message translates to:
  /// **'PIM  (leave blank for default)'**
  String get pimFieldLabel;

  /// Label for the cipher/encryption algorithm picker
  ///
  /// In en, this message translates to:
  /// **'Encryption Algorithm'**
  String get encryptionAlgorithmLabel;

  /// Label for the hash algorithm picker
  ///
  /// In en, this message translates to:
  /// **'Hash Algorithm'**
  String get hashAlgorithmLabel;

  /// Progress verb shown while a cut/move clipboard operation is pending
  ///
  /// In en, this message translates to:
  /// **'Moving'**
  String get clipboardVerbMoving;

  /// Progress verb shown while a copy clipboard operation is pending
  ///
  /// In en, this message translates to:
  /// **'Copying'**
  String get clipboardVerbCopying;

  /// Title of the floating clipboard activity pill
  ///
  /// In en, this message translates to:
  /// **'{verb} {count, plural, =1{1 item} other{{count} items}}'**
  String clipboardPillTitle(String verb, num count);

  /// Appended to the clipboard pill title to show the source container
  ///
  /// In en, this message translates to:
  /// **' from \"{source}\"'**
  String clipboardFromSourceSuffix(String source);

  /// Hint shown on the clipboard pill when no paste target is currently open
  ///
  /// In en, this message translates to:
  /// **'Open a container to paste'**
  String get clipboardOpenContainerToPaste;

  /// Header for the optional keyfiles section on unlock/creation forms
  ///
  /// In en, this message translates to:
  /// **'Keyfiles (optional)'**
  String get keyfilesOptionalLabel;

  /// Button label to add a keyfile
  ///
  /// In en, this message translates to:
  /// **'Add File'**
  String get addFile;

  /// Empty state text when no keyfiles have been selected
  ///
  /// In en, this message translates to:
  /// **'No keyfiles attached'**
  String get noKeyfilesAttached;

  /// Generic completed status label
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// Generic dismiss action tooltip
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// Byte transfer progress, e.g. '1.2 MB / 4.0 MB (30%)'
  ///
  /// In en, this message translates to:
  /// **'{transferred} / {total}  ({pct}%)'**
  String byteProgressText(String transferred, String total, int pct);

  /// Item count transfer progress, e.g. '3 / 10 (30%)'
  ///
  /// In en, this message translates to:
  /// **'{done} / {total}  ({pct}%)'**
  String countProgressText(int done, int total, int pct);

  /// Label shown when multiple file operations are running at once
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 transfer} other{{count} transfers}}'**
  String multiOpLabel(num count);

  /// Sublabel under the multi-operation activity pill
  ///
  /// In en, this message translates to:
  /// **'{summary} · tap to view all'**
  String multiOpSublabel(String summary);

  /// Section header for the thumbnail resolution slider
  ///
  /// In en, this message translates to:
  /// **'Thumbnail Size (Resolution)'**
  String get thumbnailSizeResolutionLabel;

  /// Section header for the JPEG compression quality slider
  ///
  /// In en, this message translates to:
  /// **'JPEG Compression Quality'**
  String get jpegCompressionQualityLabel;

  /// Generic Done button label
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Generic Confirm button label
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Fallback error message when picking keyfiles fails without a platform-provided message
  ///
  /// In en, this message translates to:
  /// **'Could not pick keyfiles'**
  String get couldNotPickKeyfiles;

  /// Generic filesystem label used in validation messages for encrypted-vault formats (Cryptomator/gocryptfs/CryFS)
  ///
  /// In en, this message translates to:
  /// **'this encrypted vault'**
  String get filesystemLabelEncryptedVault;

  /// Generic filesystem label used in validation messages when the concrete filesystem type is unknown
  ///
  /// In en, this message translates to:
  /// **'this container'**
  String get filesystemLabelThisContainer;

  /// Lowercase noun for a file, used inside validation sentences
  ///
  /// In en, this message translates to:
  /// **'file'**
  String get nounFile;

  /// Lowercase noun for a folder, used inside validation sentences
  ///
  /// In en, this message translates to:
  /// **'folder'**
  String get nounFolder;

  /// Capitalized noun for a file, used at the start of a validation sentence
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get nounFileCapitalized;

  /// Capitalized noun for a folder, used at the start of a validation sentence
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get nounFolderCapitalized;

  /// Unit label for byte-based length limits
  ///
  /// In en, this message translates to:
  /// **'bytes'**
  String get unitBytes;

  /// Unit label for character-based length limits
  ///
  /// In en, this message translates to:
  /// **'characters'**
  String get unitCharacters;

  /// Validation error when a file/folder name field is empty
  ///
  /// In en, this message translates to:
  /// **'The name cannot be empty.'**
  String get validationEmptyName;

  /// Validation error for names that are exactly "." or ".."
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is a reserved navigation name and can\'t be used as a {noun} name.'**
  String validationReservedNavName(String name, String noun);

  /// Validation error for a specific illegal character in a name
  ///
  /// In en, this message translates to:
  /// **'\"{char}\" at position {position} is not allowed in a name on {fsLabel}.'**
  String validationIllegalChar(String char, int position, String fsLabel);

  /// Validation error for a non-printable control character in a name
  ///
  /// In en, this message translates to:
  /// **'Position {position} contains a non-printable control character (code {code}), which is not allowed on {fsLabel}.'**
  String validationControlChar(int position, String code, String fsLabel);

  /// Validation error for Windows-family reserved device names
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is a reserved device name on {fsLabel} (matches CON, PRN, AUX, NUL, COM0–9, or LPT0–9) and can\'t be used, with or without a file extension.'**
  String validationReservedDeviceName(String name, String fsLabel);

  /// Validation error for a trailing space in a name
  ///
  /// In en, this message translates to:
  /// **'{noun} names can\'t end with a space on {fsLabel}'**
  String validationTrailingSpace(String noun, String fsLabel);

  /// Validation error for a trailing dot in a name
  ///
  /// In en, this message translates to:
  /// **'{noun} names can\'t end with a \".\" on {fsLabel}'**
  String validationTrailingDot(String noun, String fsLabel);

  /// Validation error when a name exceeds the filesystem's length limit
  ///
  /// In en, this message translates to:
  /// **'This name is {length} {unit} long; {fsLabel} allows at most {maxLength} {unit} per {noun} name.'**
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  );

  /// Validation error when the full joined path exceeds the filesystem's path length limit
  ///
  /// In en, this message translates to:
  /// **'The full path is {length} characters long; {fsLabel} allows at most {maxLength}.'**
  String validationPathTooLong(int length, String fsLabel, int maxLength);

  /// Error shown when creating/renaming to a name that collides with an existing entry of the same type
  ///
  /// In en, this message translates to:
  /// **'A {noun} named \"{name}\" already exists here.'**
  String conflictSameType(String noun, String name);

  /// Error shown when creating/renaming to a name that collides with an existing entry of the opposite type
  ///
  /// In en, this message translates to:
  /// **'A {existingNoun} named \"{name}\" already exists here — it can\'t share a name with a {candidateNoun}.'**
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  );

  /// Snackbar shown when trying to modify a read-only mounted container
  ///
  /// In en, this message translates to:
  /// **'This container is mounted read-only.'**
  String get readOnlyContainerWarning;

  /// Snackbar/warning shown when hidden volume protection blocks a write and switches the outer volume to read-only for the rest of the session
  ///
  /// In en, this message translates to:
  /// **'A write to this outer volume would have damaged the hidden volume, so it was blocked. This container has been switched to read-only for the rest of this session.'**
  String get hiddenVolumeProtectionTriggeredWarning;

  /// Title for the "protect hidden volume" toggle in the unlock advanced options
  ///
  /// In en, this message translates to:
  /// **'Protect hidden volume'**
  String get protectHiddenVolumeToggleTitle;

  /// Subtitle explaining the "protect hidden volume" toggle
  ///
  /// In en, this message translates to:
  /// **'Prevent damage caused by writing to the outer volume'**
  String get protectHiddenVolumeToggleSubtitle;

  /// Validation error shown when "protect hidden volume" is enabled but no hidden password/keyfiles were entered
  ///
  /// In en, this message translates to:
  /// **'A hidden volume password or keyfile is required to protect it'**
  String get protectHiddenVolumeCredentialsRequired;

  /// Confirmation dialog title for deleting one or more items
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete 1 item?} other{Delete {count} items?}}'**
  String deleteItemsTitle(num count);

  /// Delete confirmation body when the selection includes at least one folder
  ///
  /// In en, this message translates to:
  /// **'These items will be permanently deleted, including all contents of any selected folders.'**
  String get deleteFoldersWarning;

  /// Delete confirmation body when the selection is files only
  ///
  /// In en, this message translates to:
  /// **'These items will be permanently erased from your encrypted volume.'**
  String get deleteFilesWarning;

  /// Generic Delete action label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Generic Remove action label for removing cards/items from a list without deleting data
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// Generic Create action label
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// Generic Rename action label / single-item rename dialog title
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// Dialog title when renaming multiple items at once
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Rename 1 item} other{Rename {count} items}}'**
  String renameMultipleTitle(num count);

  /// Create-folder dialog title
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get newFolderTitle;

  /// Create-file dialog title
  ///
  /// In en, this message translates to:
  /// **'New Text File'**
  String get newTextFileTitle;

  /// Hint text for the new folder name field
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folderNameHint;

  /// Example hint text for the new file name field
  ///
  /// In en, this message translates to:
  /// **'filename.txt'**
  String get filenameHint;

  /// Hint text for a single-item rename field
  ///
  /// In en, this message translates to:
  /// **'New name'**
  String get newNameHint;

  /// Hint text for a multi-item rename base name field
  ///
  /// In en, this message translates to:
  /// **'Base name'**
  String get baseNameHint;

  /// Error shown when creating a folder or file fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create \"{name}\" — check the container is still mounted'**
  String couldntCreateItem(String name);

  /// Error shown when a single-item rename fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t rename \"{name}\" — an item with that name may already exist'**
  String couldntRenameSingle(String name);

  /// Error shown when one or more items fail to rename in a batch, with a specific reason
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Couldn\'t rename 1 item: {reason}} other{Couldn\'t rename {count} items: {reason}}}'**
  String couldntRenameMultiWithReason(num count, String reason);

  /// Error shown when one or more items fail to rename in a batch, without a specific reason
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Couldn\'t rename 1 item} other{Couldn\'t rename {count} items}}'**
  String couldntRenameMultiNoReason(num count);

  /// Validation error when the hidden volume size field is empty or non-positive
  ///
  /// In en, this message translates to:
  /// **'Enter a valid hidden size greater than 0'**
  String get hiddenVolumeErrorInvalidSize;

  /// Validation error when the hidden volume size is not smaller than the outer volume
  ///
  /// In en, this message translates to:
  /// **'Hidden volume size must be less than the outer volume size'**
  String get hiddenVolumeErrorTooLargeVsOuter;

  /// Validation error when the hidden volume plus header reservation exceeds the outer container size
  ///
  /// In en, this message translates to:
  /// **'Hidden volume size is too large for this container size'**
  String get hiddenVolumeErrorTooLargeForContainer;

  /// Validation error when neither a hidden password nor keyfiles were supplied
  ///
  /// In en, this message translates to:
  /// **'A hidden password or keyfile is required when creating a hidden volume'**
  String get hiddenVolumeErrorCredentialsRequired;

  /// Validation error when the hidden volume credentials exactly match the outer volume credentials
  ///
  /// In en, this message translates to:
  /// **'Hidden volume credentials (password, PIM, and keyfiles) cannot be identical to the outer volume credentials.'**
  String get hiddenVolumeErrorCredentialsMustDiffer;

  /// Vault item type name: a saved password/login
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get vaultItemTypePassword;

  /// Vault item type name: a saved payment card
  ///
  /// In en, this message translates to:
  /// **'Payment Card'**
  String get vaultItemTypePaymentCard;

  /// Vault item type name: a saved identity document
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get vaultItemTypeIdentity;

  /// Vault item type name: a free-text secure note
  ///
  /// In en, this message translates to:
  /// **'Secure Note'**
  String get vaultItemTypeSecureNote;

  /// Vault item type name: a saved bank account
  ///
  /// In en, this message translates to:
  /// **'Bank Account'**
  String get vaultItemTypeBankAccount;

  /// Vault item type name: a saved software license
  ///
  /// In en, this message translates to:
  /// **'Software License'**
  String get vaultItemTypeSoftwareLicense;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Username / Email'**
  String get fieldUsernameEmail;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get fieldPassword;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Website URL'**
  String get fieldWebsiteUrl;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'TOTP Secret (2FA)'**
  String get fieldTotpSecret;

  /// Form field label, shared across several vault item templates
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get fieldNotes;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Cardholder Name'**
  String get fieldCardholderName;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Card Number'**
  String get fieldCardNumber;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Expiry (MM/YY)'**
  String get fieldExpiryMMYY;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'CVV / CVC'**
  String get fieldCvvCvc;

  /// Form field label, shared across several vault item templates
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get fieldPin;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Issuing Bank'**
  String get fieldIssuingBank;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fieldFullName;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Date of Birth'**
  String get fieldDateOfBirth;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Nationality'**
  String get fieldNationality;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Passport Number'**
  String get fieldPassportNumber;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Passport Expiry'**
  String get fieldPassportExpiry;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'National ID / SSN'**
  String get fieldNationalIdSsn;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Driver\'s License'**
  String get fieldDriversLicense;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get fieldAddress;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get fieldPhone;

  /// Form field label, shared across several vault item templates
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get fieldEmail;

  /// Form field label for a secure note's free-text content
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get fieldNote;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Bank Name'**
  String get fieldBankName;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Account Holder'**
  String get fieldAccountHolder;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Account Number'**
  String get fieldAccountNumber;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Routing / Sort Code'**
  String get fieldRoutingSortCode;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'IBAN'**
  String get fieldIban;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'SWIFT / BIC'**
  String get fieldSwiftBic;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Account Type'**
  String get fieldAccountType;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Product Name'**
  String get fieldProductName;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'License Key'**
  String get fieldLicenseKey;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Registered To'**
  String get fieldRegisteredTo;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Purchase Date'**
  String get fieldPurchaseDate;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Expiry / Renewal Date'**
  String get fieldExpiryRenewalDate;

  /// Form field label
  ///
  /// In en, this message translates to:
  /// **'Download URL'**
  String get fieldDownloadUrl;

  /// Form field label for the email associated with a software license registration
  ///
  /// In en, this message translates to:
  /// **'Registration Email'**
  String get fieldRegistrationEmail;

  /// Validation error when saving a vault item without a title
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get titleRequired;

  /// AppBar title when creating a new vault item
  ///
  /// In en, this message translates to:
  /// **'New {typeLabel}'**
  String newTypeTitle(String typeLabel);

  /// AppBar title when editing an existing vault item
  ///
  /// In en, this message translates to:
  /// **'Edit {title}'**
  String editItemTitle(String title);

  /// Generic Save action label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Hint text for the vault item title field, e.g. 'Password name'
  ///
  /// In en, this message translates to:
  /// **'{typeLabel} name'**
  String typeNameHint(String typeLabel);

  /// Section header above the vault item title field
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleSectionLabel;

  /// Section header above the vault item's dynamic fields
  ///
  /// In en, this message translates to:
  /// **'Fields'**
  String get fieldsSectionLabel;

  /// Reassurance footer text on the vault item edit screen
  ///
  /// In en, this message translates to:
  /// **'All fields are stored encrypted inside the container.'**
  String get encryptedStorageHint;

  /// Snackbar confirming a field's value was copied to the clipboard
  ///
  /// In en, this message translates to:
  /// **'{fieldLabel} copied'**
  String copiedSuffix(String fieldLabel);

  /// Generic Copy action tooltip/label
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Error shown when saving a vault item fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save — check container is still mounted'**
  String get failedToSaveCheckMounted;

  /// Confirmation dialog title when leaving a screen with unsaved edits
  ///
  /// In en, this message translates to:
  /// **'Discard changes?'**
  String get discardChangesTitle;

  /// Confirmation dialog body when leaving a screen with unsaved edits
  ///
  /// In en, this message translates to:
  /// **'Your unsaved changes will be lost.'**
  String get discardChangesMessage;

  /// Button label to confirm discarding unsaved changes
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// Button label to cancel discarding unsaved changes and continue editing
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get keepEditing;

  /// Confirmation dialog title when deleting a single vault item
  ///
  /// In en, this message translates to:
  /// **'Delete item?'**
  String get deleteItemTitle;

  /// Confirmation dialog body when deleting a single vault item
  ///
  /// In en, this message translates to:
  /// **'\"{title}\" will be permanently deleted from the vault.'**
  String deleteItemMessage(String title);

  /// Tooltip for the star/bookmark toggle when the item is currently bookmarked
  ///
  /// In en, this message translates to:
  /// **'Remove from bookmarks'**
  String get removeFromBookmarks;

  /// Tooltip for the star/bookmark toggle when the item is not currently bookmarked
  ///
  /// In en, this message translates to:
  /// **'Add to bookmarks'**
  String get addToBookmarks;

  /// Generic Edit action label
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Snackbar confirming a value was copied to the clipboard
  ///
  /// In en, this message translates to:
  /// **'{label} copied to clipboard'**
  String labelCopiedToClipboard(String label);

  /// Empty state shown on the vault item detail screen when no fields have values
  ///
  /// In en, this message translates to:
  /// **'No fields filled in.\nTap Edit to add details.'**
  String get noFieldsFilledIn;

  /// Section header above a vault item's field details
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get sectionLabelDetails;

  /// Section header above a vault item's metadata (type, created, modified)
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get sectionLabelInfo;

  /// Metadata row label for the vault item's type
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get metaLabelType;

  /// Metadata row label for the vault item's creation date
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get metaLabelCreated;

  /// Metadata row label for the vault item's last-modified date
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get metaLabelModified;

  /// Tooltip for the per-field copy button
  ///
  /// In en, this message translates to:
  /// **'Copy {fieldLabel}'**
  String copyFieldTooltip(String fieldLabel);

  /// Tooltip on the add-item button when the container is mounted read-only
  ///
  /// In en, this message translates to:
  /// **'Read-only — can\'t add items'**
  String get readOnlyCantAddItemsTooltip;

  /// Tooltip/menu label to extract the currently open archive
  ///
  /// In en, this message translates to:
  /// **'Extract Archive'**
  String get extractArchive;

  /// Tooltip for the add-item button in the file browser app bar
  ///
  /// In en, this message translates to:
  /// **'New item'**
  String get newItemTooltip;

  /// Menu item label to capture a photo with the camera
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get camera;

  /// Menu item label to import files from outside the vault
  ///
  /// In en, this message translates to:
  /// **'Import Files'**
  String get importFiles;

  /// Menu item label to import a whole folder from outside the vault
  ///
  /// In en, this message translates to:
  /// **'Import Folder'**
  String get importFolder;

  /// Submenu label listing the vault item types (password, note, card, etc.) that can be created
  ///
  /// In en, this message translates to:
  /// **'Secure Item'**
  String get secureItem;

  /// The app's real (non-disguised) name, shown as the app title and Android task-switcher label
  ///
  /// In en, this message translates to:
  /// **'Vault Explorer'**
  String get appNameVaultExplorer;

  /// The decoy/disguise app name shown as the app title and Android task-switcher label when Mask Mode is active
  ///
  /// In en, this message translates to:
  /// **'Archive Explorer'**
  String get appNameZipExplorer;

  /// Title shown on the decoy Archive Explorer screen when file access hasn't been granted yet
  ///
  /// In en, this message translates to:
  /// **'Storage access needed'**
  String get archiveExplorerPermissionTitle;

  /// Explanatory message shown alongside the grant-access button on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Allow access to your files to browse and extract .zip archives from Downloads.'**
  String get archiveExplorerPermissionMessage;

  /// Button label to request all-files storage access from the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Grant Access'**
  String get archiveExplorerGrantAccess;

  /// Empty state title on the decoy Archive Explorer screen when no .zip files exist in Downloads
  ///
  /// In en, this message translates to:
  /// **'No archives found'**
  String get archiveExplorerEmptyTitle;

  /// Empty state message on the decoy Archive Explorer screen when no .zip files exist in Downloads
  ///
  /// In en, this message translates to:
  /// **'Zip files you download will show up here.'**
  String get archiveExplorerEmptyMessage;

  /// Tooltip for the refresh button on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get archiveExplorerRefreshTooltip;

  /// Number of entries inside a zip archive shown on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 item} other{{count} items}}'**
  String archiveExplorerEntryCount(int count);

  /// Button label to extract every entry from a zip archive on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Extract All'**
  String get archiveExplorerExtractAll;

  /// Progress label shown while a zip archive is being extracted on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Extracting…'**
  String get archiveExplorerExtracting;

  /// Confirmation snackbar after successfully extracting a zip archive on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Extracted {count} files to Download/Extracted/{name}'**
  String archiveExplorerExtractSuccess(int count, String name);

  /// Error snackbar shown when extracting a zip archive fails on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t extract that archive.'**
  String get archiveExplorerExtractFailed;

  /// Error snackbar shown when a zip archive can't be parsed on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open that archive.'**
  String get archiveExplorerOpenFailed;

  /// App-bar action on the decoy Archive Explorer screen to pick any .zip file via the system file picker, not just ones in Downloads
  ///
  /// In en, this message translates to:
  /// **'Open archive…'**
  String get archiveExplorerOpenArchive;

  /// Error snackbar on the decoy Archive Explorer screen when a picked document can't be resolved to a real filesystem path
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t access that file directly. Try picking one from Downloads instead.'**
  String get archiveExplorerUnresolvedPath;

  /// Menu item on the decoy Archive Explorer screen to extract a zip archive to a user-chosen folder instead of the default location
  ///
  /// In en, this message translates to:
  /// **'Extract to…'**
  String get archiveExplorerExtractTo;

  /// Menu item / action on the decoy Archive Explorer screen to browse a zip archive's contents without extracting it
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get archiveExplorerPreview;

  /// Transient status shown on the decoy Archive Explorer screen while the folder picker for a custom extraction destination is open
  ///
  /// In en, this message translates to:
  /// **'Choosing destination…'**
  String get archiveExplorerChoosingDestination;

  /// Snackbar shown on the decoy Archive Explorer screen when the user cancels the extraction-destination folder picker
  ///
  /// In en, this message translates to:
  /// **'No destination chosen.'**
  String get archiveExplorerNoDestinationChosen;

  /// Confirmation snackbar after extracting a zip archive to a user-chosen destination on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Extracted {count} files to {path}'**
  String archiveExplorerExtractSuccessTo(int count, String path);

  /// Empty state title shown when browsing into an empty folder inside an archive on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Empty folder'**
  String get archiveBrowserEmptyTitle;

  /// Empty state message shown when browsing into an empty folder inside an archive on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'This folder doesn\'t contain any files.'**
  String get archiveBrowserEmptyMessage;

  /// Breadcrumb label for the root of an archive being browsed on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archiveBrowserRoot;

  /// Error snackbar shown when extracting a single entry for preview fails while browsing an archive on the decoy Archive Explorer screen
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open that file.'**
  String get archiveBrowserOpenFileFailed;

  /// File association label: files open in the built-in text editor
  ///
  /// In en, this message translates to:
  /// **'In-app Text Editor'**
  String get fileAssocInAppTextEditor;

  /// File association label: files open in the built-in media viewer
  ///
  /// In en, this message translates to:
  /// **'In-app Media Viewer'**
  String get fileAssocInAppMediaViewer;

  /// File association label naming a specific external app
  ///
  /// In en, this message translates to:
  /// **'App: {name}'**
  String fileAssocAppPrefix(String name);

  /// File association label for an unspecified external app
  ///
  /// In en, this message translates to:
  /// **'External App'**
  String get fileAssocExternalApp;

  /// App Settings screen AppBar title
  ///
  /// In en, this message translates to:
  /// **'App Settings'**
  String get appSettingsTitle;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Security & Privacy'**
  String get sectionSecurityPrivacy;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Appearance & Interface'**
  String get sectionAppearanceInterface;

  /// Settings section header
  ///
  /// In en, this message translates to:
  /// **'Vault & File Handling'**
  String get sectionVaultFileHandling;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Master Password'**
  String get masterPasswordTitle;

  /// Settings toggle subtitle when a master password is set
  ///
  /// In en, this message translates to:
  /// **'Active — tap toggle to remove'**
  String get masterPasswordActiveSubtitle;

  /// Settings toggle subtitle when no master password is set
  ///
  /// In en, this message translates to:
  /// **'Require a password to open the app'**
  String get masterPasswordInactiveSubtitle;

  /// Label for new password input field
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPasswordLabel;

  /// Text field label when setting a master password for the first time
  ///
  /// In en, this message translates to:
  /// **'Master password'**
  String get masterPasswordFieldLabel;

  /// Text field label for the password confirmation field
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPasswordLabel;

  /// Generic Update button label
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// Button label to confirm setting a new master password
  ///
  /// In en, this message translates to:
  /// **'Set Password'**
  String get setPassword;

  /// Title of the biometric unlock card
  ///
  /// In en, this message translates to:
  /// **'Biometric Unlock'**
  String get biometricUnlockTitle;

  /// Subtitle of the biometric unlock card
  ///
  /// In en, this message translates to:
  /// **'Authenticate to securely mount the container'**
  String get biometricUnlockSubtitle;

  /// Settings row title to open the change-password form
  ///
  /// In en, this message translates to:
  /// **'Change Master Password'**
  String get changeMasterPasswordTitle;

  /// Settings row subtitle
  ///
  /// In en, this message translates to:
  /// **'Update master password credentials'**
  String get changeMasterPasswordSubtitle;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Auto-Lock Containers'**
  String get autoLockContainersTitle;

  /// Settings toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Automatically lock open vaults after inactivity'**
  String get autoLockContainersSubtitle;

  /// Settings picker label
  ///
  /// In en, this message translates to:
  /// **'Auto-Lock Timeout'**
  String get autoLockTimeoutLabel;

  /// Auto-lock timeout option meaning zero delay
  ///
  /// In en, this message translates to:
  /// **'Immediately'**
  String get immediately;

  /// Duration in minutes, used for auto-lock timeout options
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 minute} other{{count} minutes}}'**
  String nMinutes(num count);

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Block Screenshots'**
  String get blockScreenshotsTitle;

  /// Settings toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Prevent screenshots and hide recent apps preview'**
  String get blockScreenshotsSubtitle;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Keep Vaults Running in Background'**
  String get keepVaultsRunningInBackgroundTitle;

  /// Settings toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Show a notification and keep open vaults available after you leave the app. Vault keys stay in memory until locked.'**
  String get keepVaultsRunningInBackgroundSubtitle;

  /// Warning shown when the user denies the POST_NOTIFICATIONS prompt after enabling the keep-vaults-running-in-background setting
  ///
  /// In en, this message translates to:
  /// **'Notification permission denied. Vaults will still stay open, but the ongoing notification won\'t be shown.'**
  String get notificationPermissionDeniedMessage;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Mask Mode'**
  String get discreteModeTitle;

  /// Settings toggle subtitle when Discrete Mode is on
  ///
  /// In en, this message translates to:
  /// **'Active — the app currently appears as \"Archive Explorer\"'**
  String get discreteModeActiveSubtitle;

  /// Settings toggle subtitle when Discrete Mode is off
  ///
  /// In en, this message translates to:
  /// **'Disguise this app as a zip archive browser on the home screen'**
  String get discreteModeInactiveSubtitle;

  /// Confirmation dialog title when turning Discrete Mode on
  ///
  /// In en, this message translates to:
  /// **'Enable Mask Mode?'**
  String get enableDiscreteModeTitle;

  /// Confirmation dialog title when turning Discrete Mode off
  ///
  /// In en, this message translates to:
  /// **'Disable Mask Mode?'**
  String get disableDiscreteModeTitle;

  /// Confirmation dialog body when turning Discrete Mode on
  ///
  /// In en, this message translates to:
  /// **'The app icon and name on your home screen will change to \"Archive Explorer\". It will function as a zip archive browser and extractor.\n\nTo access your vault, open Archive Explorer and hold your finger on the title for 2 seconds.'**
  String get enableDiscreteModeMessage;

  /// Confirmation dialog body when turning Discrete Mode off
  ///
  /// In en, this message translates to:
  /// **'The app icon and name on your home screen will change back to \"Vault Explorer\".'**
  String get disableDiscreteModeMessage;

  /// Generic Enable action label
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// Generic Disable action label
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get disable;

  /// Snackbar shown after turning Discrete Mode on
  ///
  /// In en, this message translates to:
  /// **'Mask Mode enabled. The app will close — reopen from the new launcher icon.'**
  String get discreteModeEnabledSnack;

  /// Snackbar shown after turning Discrete Mode off
  ///
  /// In en, this message translates to:
  /// **'Mask Mode disabled. The app will close — reopen from the new launcher icon.'**
  String get discreteModeDisabledSnack;

  /// Error snackbar when toggling Discrete Mode fails
  ///
  /// In en, this message translates to:
  /// **'Failed to change Mask Mode'**
  String get failedToChangeDiscreteMode;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Cache Derived Keys by Default'**
  String get cacheDerivedKeysTitle;

  /// Settings toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Store derived key material in Keystore for faster unlocks'**
  String get cacheDerivedKeysSubtitle;

  /// Settings picker label
  ///
  /// In en, this message translates to:
  /// **'App Theme'**
  String get appThemeLabel;

  /// Option meaning: follow the OS-level setting rather than an explicit override
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// Theme option
  ///
  /// In en, this message translates to:
  /// **'Light Theme'**
  String get lightTheme;

  /// Theme option
  ///
  /// In en, this message translates to:
  /// **'Dark Theme'**
  String get darkTheme;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Use Material You'**
  String get useMaterialYouTitle;

  /// Settings toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Match app colors to your wallpaper (Android 12+)'**
  String get useMaterialYouSubtitle;

  /// Settings picker label
  ///
  /// In en, this message translates to:
  /// **'Sort Containers By'**
  String get sortContainersByLabel;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Swap Card Swipe Actions'**
  String get swapCardSwipeActionsTitle;

  /// Settings toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Reveal Edit on left and Remove on right when swiping cards'**
  String get swapCardSwipeActionsSubtitle;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Swipe Gesture Hint'**
  String get swipeGestureHintTitle;

  /// Settings toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Show card peek animation on first container'**
  String get swipeGestureHintSubtitle;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Auto-Open on Unlock'**
  String get autoOpenOnUnlockTitle;

  /// Settings toggle subtitle when enabled
  ///
  /// In en, this message translates to:
  /// **'Automatically open after unlocking a vault'**
  String get autoOpenOnUnlockActiveSubtitle;

  /// Settings toggle subtitle when disabled
  ///
  /// In en, this message translates to:
  /// **'Only unlock vault and stay on dashboard'**
  String get autoOpenOnUnlockInactiveSubtitle;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Enable JavaScript in HTML Viewer'**
  String get enableJsHtmlTitle;

  /// Settings toggle subtitle when enabled
  ///
  /// In en, this message translates to:
  /// **'JavaScript enabled for local HTML files'**
  String get jsEnabledSubtitle;

  /// Settings toggle subtitle when disabled
  ///
  /// In en, this message translates to:
  /// **'JavaScript disabled for local HTML files'**
  String get jsDisabledSubtitle;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Fast Storage Access'**
  String get fastStorageAccessTitle;

  /// Settings toggle subtitle when permission is granted
  ///
  /// In en, this message translates to:
  /// **'All Files Access granted (maximum speed)'**
  String get fastStorageAccessGrantedSubtitle;

  /// Settings toggle subtitle when permission is not granted
  ///
  /// In en, this message translates to:
  /// **'Grant All Files Access in System Settings for optimal speed'**
  String get fastStorageAccessNotGrantedSubtitle;

  /// Confirmation dialog title when granting All Files Access
  ///
  /// In en, this message translates to:
  /// **'Enable Fast Storage Access'**
  String get enableFastStorageAccessTitle;

  /// Confirmation dialog body when granting All Files Access
  ///
  /// In en, this message translates to:
  /// **'Granting \"All Files Access\" allows Vault Explorer to perform direct POSIX file operations, speeding up folder vault performance by up to 1000x.'**
  String get enableFastStorageAccessMessage;

  /// Confirmation dialog title when revoking All Files Access
  ///
  /// In en, this message translates to:
  /// **'Disable Storage Access'**
  String get disableStorageAccessTitle;

  /// Confirmation dialog body when revoking All Files Access
  ///
  /// In en, this message translates to:
  /// **'Android requires \"All Files Access\" to be turned off inside System Settings. Would you like to open Settings to turn it off?'**
  String get disableStorageAccessMessage;

  /// Confirmation dialog title when granting storage permission on Android 8-10 (API 26-29), before All Files Access existed
  ///
  /// In en, this message translates to:
  /// **'Allow Storage Access'**
  String get enableStoragePermissionLegacyTitle;

  /// Confirmation dialog body when granting storage permission on Android 8-10 (API 26-29), before All Files Access existed
  ///
  /// In en, this message translates to:
  /// **'Vault Explorer needs storage permission to perform direct file operations, speeding up folder vault performance. Android will now ask you to confirm.'**
  String get enableStoragePermissionLegacyMessage;

  /// Confirmation dialog body when revoking storage permission on Android 8-10 (API 26-29) -- apps can't revoke their own runtime grants, so this must go through Settings
  ///
  /// In en, this message translates to:
  /// **'Android requires storage permission to be turned off inside System Settings. Would you like to open Settings to turn it off?'**
  String get disableStoragePermissionLegacyMessage;

  /// Button label to open the system settings app
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// Switch title for exposing container content via the Android document provider
  ///
  /// In en, this message translates to:
  /// **'Android File Provider'**
  String get androidFileProviderTitle;

  /// Settings toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Expose new containers to Android File Picker by default'**
  String get androidFileProviderSubtitle;

  /// Settings picker label
  ///
  /// In en, this message translates to:
  /// **'Thumbnail Caching (default)'**
  String get thumbnailCachingDefaultLabel;

  /// Settings picker label
  ///
  /// In en, this message translates to:
  /// **'Thumbnail Quality (default)'**
  String get thumbnailQualityDefaultLabel;

  /// Settings subsection header
  ///
  /// In en, this message translates to:
  /// **'File Associations'**
  String get fileAssociationsHeader;

  /// Empty state text for the file associations list
  ///
  /// In en, this message translates to:
  /// **'No remembered file associations yet. You will be prompted when opening files.'**
  String get noFileAssociationsYet;

  /// Header above the list of remembered file associations
  ///
  /// In en, this message translates to:
  /// **'Default actions when opening non-standard files:'**
  String get defaultActionsHeader;

  /// Tooltip for the button that deletes a remembered file association
  ///
  /// In en, this message translates to:
  /// **'Remove association'**
  String get removeAssociationTooltip;

  /// Settings section header for export/import of app settings
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get sectionBackupRestore;

  /// Settings row title for exporting app settings to a file
  ///
  /// In en, this message translates to:
  /// **'Export settings'**
  String get exportSettingsTitle;

  /// Settings row subtitle for exporting app settings to a file
  ///
  /// In en, this message translates to:
  /// **'Save app settings and file manager layout to a file'**
  String get exportSettingsSubtitle;

  /// Settings row title for importing app settings from a file
  ///
  /// In en, this message translates to:
  /// **'Import settings'**
  String get importSettingsTitle;

  /// Settings row subtitle for importing app settings from a file
  ///
  /// In en, this message translates to:
  /// **'Restore app settings and file manager layout from a file'**
  String get importSettingsSubtitle;

  /// Confirmation dialog title before overwriting settings with an imported file
  ///
  /// In en, this message translates to:
  /// **'Import settings?'**
  String get importSettingsConfirmTitle;

  /// Confirmation dialog message before overwriting settings with an imported file
  ///
  /// In en, this message translates to:
  /// **'This replaces your current app settings and file manager layout. This can\'t be undone.'**
  String get importSettingsConfirmMessage;

  /// Snackbar shown after successfully exporting settings
  ///
  /// In en, this message translates to:
  /// **'Settings exported'**
  String get exportSettingsSuccessMessage;

  /// Snackbar shown after successfully importing settings
  ///
  /// In en, this message translates to:
  /// **'Settings imported'**
  String get importSettingsSuccessMessage;

  /// Snackbar shown when exporting settings fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export settings'**
  String get exportSettingsErrorMessage;

  /// Snackbar shown when the picked import file isn't a recognizable settings bundle
  ///
  /// In en, this message translates to:
  /// **'That file isn\'t a valid settings export'**
  String get importSettingsInvalidFileMessage;

  /// Settings section header for developer/debug tools
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get sectionDebug;

  /// Settings switch title for enabling verbose debug logs
  ///
  /// In en, this message translates to:
  /// **'Debug logging'**
  String get debugLoggingTitle;

  /// Settings switch subtitle explaining that debug logs help diagnose issues
  ///
  /// In en, this message translates to:
  /// **'Record detailed diagnostic logs for container operations'**
  String get debugLoggingSubtitle;

  /// Settings row title and screen title for the logcat viewer
  ///
  /// In en, this message translates to:
  /// **'Logcat'**
  String get logcatTitle;

  /// Settings row subtitle for the logcat viewer
  ///
  /// In en, this message translates to:
  /// **'View and save device logs'**
  String get logcatSubtitle;

  /// Snackbar shown after successfully saving the logcat output to a file
  ///
  /// In en, this message translates to:
  /// **'Log saved to {path}'**
  String logcatSavedMessage(String path);

  /// Snackbar shown when saving the logcat output fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save log'**
  String get logcatSaveErrorMessage;

  /// Snackbar shown after copying logcat lines to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Log copied to clipboard'**
  String get logcatCopiedMessage;

  /// Message shown when logcat cannot be started (e.g. permission denied or non-Android platform)
  ///
  /// In en, this message translates to:
  /// **'Logcat is not available on this device'**
  String get logcatUnavailableMessage;

  /// Placeholder shown in the logcat view while no lines have been received yet
  ///
  /// In en, this message translates to:
  /// **'Waiting for log lines…'**
  String get logcatEmptyMessage;

  /// Tooltip for the clear-log button in the logcat screen AppBar
  ///
  /// In en, this message translates to:
  /// **'Clear log'**
  String get logcatClearTooltip;

  /// Tooltip for the save-log button in the logcat screen AppBar
  ///
  /// In en, this message translates to:
  /// **'Save log'**
  String get logcatSaveTooltip;

  /// Filter tab for displaying only VaultExplorer app logs
  ///
  /// In en, this message translates to:
  /// **'App Only'**
  String get logcatFilterAppOnly;

  /// Filter tab for displaying all device/framework logs
  ///
  /// In en, this message translates to:
  /// **'All Logs'**
  String get logcatFilterAll;

  /// Placeholder hint in the logcat search bar
  ///
  /// In en, this message translates to:
  /// **'Search logs…'**
  String get logcatSearchHint;

  /// Snackbar shown after clearing the logcat buffer
  ///
  /// In en, this message translates to:
  /// **'Logs cleared'**
  String get logcatClearedMessage;

  /// Tooltip for the copy-log button in the logcat screen AppBar
  ///
  /// In en, this message translates to:
  /// **'Copy log'**
  String get logcatCopyTooltip;

  /// Button to retry a failed operation
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// Settings row title linking to the About screen
  ///
  /// In en, this message translates to:
  /// **'About VaultExplorer'**
  String get aboutAppTitle;

  /// Settings row subtitle showing the app version
  ///
  /// In en, this message translates to:
  /// **'Version {version} · Open source licenses & details'**
  String versionInfoSubtitle(String version);

  /// Error snackbar when persisting settings fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save settings'**
  String get failedToSaveSettings;

  /// Success snackbar after setting the master password
  ///
  /// In en, this message translates to:
  /// **'Master password set'**
  String get masterPasswordSetSnack;

  /// Validation error for an empty password field
  ///
  /// In en, this message translates to:
  /// **'Password cannot be empty'**
  String get passwordCannotBeEmpty;

  /// Validation error for a too-short password
  ///
  /// In en, this message translates to:
  /// **'At least 4 characters required'**
  String get atLeast4CharsRequired;

  /// Validation error when password and confirmation don't match
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// Error shown when password hashing fails
  ///
  /// In en, this message translates to:
  /// **'Failed to hash password — please try again'**
  String get failedToHashPassword;

  /// Settings picker label for the app display language
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// Error shown when biometric auth is requested but unsupported
  ///
  /// In en, this message translates to:
  /// **'Biometric not available on this device'**
  String get biometricNotAvailable;

  /// Reason string shown by the OS biometric prompt
  ///
  /// In en, this message translates to:
  /// **'Unlock VaultExplorer'**
  String get unlockVaultExplorerReason;

  /// Error message including the platform's biometric error code
  ///
  /// In en, this message translates to:
  /// **'Biometric error: {code}'**
  String biometricErrorWithCode(String code);

  /// Error shown when the lock screen is in a lockout cooldown
  ///
  /// In en, this message translates to:
  /// **'Too many failed attempts. Try again in {seconds, plural, =1{1 second} other{{seconds} seconds}}.'**
  String tooManyFailedAttempts(num seconds);

  /// Validation error when submitting the lock screen with an empty password field
  ///
  /// In en, this message translates to:
  /// **'Enter your master password'**
  String get enterMasterPasswordPrompt;

  /// Error shown when a failed attempt triggers a new lockout
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Locked for {seconds}s due to {attempts, plural, =1{1 failed attempt} other{{attempts} failed attempts}}.'**
  String incorrectPasswordLockedFor(int seconds, num attempts);

  /// Error shown after a failed attempt that doesn't (yet) trigger a lockout
  ///
  /// In en, this message translates to:
  /// **'Incorrect password ({attempts, plural, =1{1 failed attempt} other{{attempts} failed attempts}}).'**
  String incorrectPasswordAttempts(num attempts);

  /// The app's wordmark as displayed on the lock screen (intentionally spaceless stylization, distinct from the 'Vault Explorer' task-switcher/about-screen name)
  ///
  /// In en, this message translates to:
  /// **'VaultExplorer'**
  String get brandNameNoSpace;

  /// Subtitle shown under the app logo on the lock screen
  ///
  /// In en, this message translates to:
  /// **'Enter your master password to continue'**
  String get enterPasswordSubtitle;

  /// Title-case text field label on the lock screen (distinct from the settings screen's sentence-case 'Master password')
  ///
  /// In en, this message translates to:
  /// **'Master Password'**
  String get masterPasswordFieldLabelTitleCase;

  /// Button label to submit the master password and unlock the app
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// Button label to trigger biometric authentication
  ///
  /// In en, this message translates to:
  /// **'Use Biometric'**
  String get useBiometric;

  /// Instruction/error for the pattern lock setup, shown as both a hint and a validation error
  ///
  /// In en, this message translates to:
  /// **'Connect at least 4 dots'**
  String get connectAtLeast4Dots;

  /// Error shown when the confirmation pattern doesn't match the first one drawn
  ///
  /// In en, this message translates to:
  /// **'Patterns don\'t match — try again'**
  String get patternsDontMatch;

  /// Title of the pattern unlock card
  ///
  /// In en, this message translates to:
  /// **'Draw Unlock Pattern'**
  String get drawUnlockPatternTitle;

  /// Title shown during the confirmation step of pattern lock setup
  ///
  /// In en, this message translates to:
  /// **'Confirm your pattern'**
  String get confirmPatternTitle;

  /// Subtitle instructing the user to redraw their pattern to confirm it
  ///
  /// In en, this message translates to:
  /// **'Draw the same pattern again'**
  String get drawSamePatternAgain;

  /// Instruction/error for the PIN lock setup, shown as both a hint and a validation error
  ///
  /// In en, this message translates to:
  /// **'Enter at least 4 digits'**
  String get enterAtLeast4Digits;

  /// Error shown when the confirmation PIN doesn't match the first one entered
  ///
  /// In en, this message translates to:
  /// **'PINs don\'t match — try again'**
  String get pinsDontMatch;

  /// Title shown during the first step of PIN lock setup
  ///
  /// In en, this message translates to:
  /// **'Create your unlock PIN'**
  String get createUnlockPinTitle;

  /// Title shown during the confirmation step of PIN lock setup
  ///
  /// In en, this message translates to:
  /// **'Confirm your PIN'**
  String get confirmPinTitle;

  /// Subtitle instructing the user to re-enter their PIN to confirm it
  ///
  /// In en, this message translates to:
  /// **'Enter the same PIN again'**
  String get enterSamePinAgain;

  /// Card title shown above the PIN keypad when unlocking a container, both from local storage and from a USB drive
  ///
  /// In en, this message translates to:
  /// **'Enter Unlock PIN'**
  String get enterUnlockPinTitle;

  /// Error subtitle shown after a failed PIN unlock attempt
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN — try again'**
  String get wrongPinTryAgain;

  /// Non-error subtitle shown above the PIN keypad on the local-file unlock sheet
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN'**
  String get enterYourPinSequence;

  /// Non-error subtitle shown above the PIN keypad on the USB unlock sheet
  ///
  /// In en, this message translates to:
  /// **'Enter your PIN to mount'**
  String get enterPinToMount;

  /// Shown when a container is set to PIN unlock but no PIN hash is stored
  ///
  /// In en, this message translates to:
  /// **'No PIN configured. Please enter password manually.'**
  String get noPinConfiguredMessage;

  /// Shown when PIN-unlock lockout is triggered by a failed attempt
  ///
  /// In en, this message translates to:
  /// **'Too many failed attempts. Locked for {seconds}s.'**
  String pinLockedForSeconds(int seconds);

  /// Shown when a correct PIN was entered but no cached password/keyfile exists yet to complete the unlock
  ///
  /// In en, this message translates to:
  /// **'Initializing secure credentials. Please unlock manually once to authorize PIN access.'**
  String get initSecureCredsPinMessage;

  /// Button label to configure a PIN unlock when none is set yet
  ///
  /// In en, this message translates to:
  /// **'Set PIN'**
  String get setPinButton;

  /// Button label to replace an already-configured PIN unlock
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get changePinButton;

  /// Snackbar warning shown when trying to save container settings with PIN unlock selected but no PIN configured
  ///
  /// In en, this message translates to:
  /// **'Set up a PIN before saving.'**
  String get pinSetupRequiredBeforeSaving;

  /// Inline validation message shown above the save button when PIN unlock is selected but no PIN configured
  ///
  /// In en, this message translates to:
  /// **'Set up a PIN above before saving.'**
  String get pinSetupRequiredAboveBeforeSaving;

  /// Title of the sheet shown to re-authenticate into locked container settings via PIN
  ///
  /// In en, this message translates to:
  /// **'Verify PIN'**
  String get verifyPinTitle;

  /// Error shown when the entered PIN doesn't match while re-authenticating into locked container settings
  ///
  /// In en, this message translates to:
  /// **'Incorrect PIN'**
  String get incorrectPinError;

  /// Snackbar confirming a recent document was removed from the decoy reader's history
  ///
  /// In en, this message translates to:
  /// **'Removed \"{name}\" from list'**
  String removedFromListSnack(String name);

  /// Confirmation dialog title for clearing the decoy reader's recent documents list
  ///
  /// In en, this message translates to:
  /// **'Clear Recent History?'**
  String get clearRecentHistoryTitle;

  /// Confirmation dialog body for clearing the decoy reader's recent documents list
  ///
  /// In en, this message translates to:
  /// **'This will remove all recent documents from your list. The actual files on your device will not be affected.'**
  String get clearRecentHistoryMessage;

  /// Button label to confirm clearing the entire recent documents list
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clearAll;

  /// Snackbar confirming the recent documents list was cleared
  ///
  /// In en, this message translates to:
  /// **'Recent history cleared'**
  String get recentHistoryClearedSnack;

  /// Tooltip for an overflow/more-options menu button
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptionsTooltip;

  /// Menu item label to clear the recent documents list
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistoryMenuItem;

  /// Button label to open a PDF file from local storage
  ///
  /// In en, this message translates to:
  /// **'Open PDF File'**
  String get openPdfFile;

  /// Empty state title on the decoy PDF reader home screen
  ///
  /// In en, this message translates to:
  /// **'No documents yet'**
  String get noDocumentsYetTitle;

  /// Empty state message on the decoy PDF reader home screen
  ///
  /// In en, this message translates to:
  /// **'Open a PDF from your device to start reading.'**
  String get openPdfToStartMessage;

  /// Menu item label to remove a single document from the recent list
  ///
  /// In en, this message translates to:
  /// **'Remove from list'**
  String get removeFromListMenuItem;

  /// Relative time label for an event that happened less than a minute ago
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get justNow;

  /// Abbreviated relative time label, e.g. '5m ago'
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String minutesAgo(int count);

  /// Abbreviated relative time label, e.g. '3h ago'
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String hoursAgo(int count);

  /// Abbreviated relative time label, e.g. '2d ago'
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String daysAgo(int count);

  /// Warning snackbar when a USB container auto-locks because the drive was unplugged
  ///
  /// In en, this message translates to:
  /// **'USB drive disconnected — container locked'**
  String get usbDriveDisconnectedLocked;

  /// Snackbar shown when trying to unlock a container that's already open
  ///
  /// In en, this message translates to:
  /// **'This container is already mounted.'**
  String get containerAlreadyMounted;

  /// Error when a picked folder doesn't match any supported folder-vault format
  ///
  /// In en, this message translates to:
  /// **'No masterkey.cryptomator, gocryptfs.conf, or cryfs.config found in that folder.'**
  String get noVaultFolderFormatDetected;

  /// Error when relocating a container whose saved record has gone missing
  ///
  /// In en, this message translates to:
  /// **'Saved settings for this container could not be found.'**
  String get savedContainerSettingsNotFound;

  /// Error when relocating a container to a new file/folder fails
  ///
  /// In en, this message translates to:
  /// **'Could not update the container location: {error}'**
  String couldNotUpdateContainerLocation(String error);

  /// Error when the system file/folder picker fails
  ///
  /// In en, this message translates to:
  /// **'File picker failed: {error}'**
  String filePickerFailed(String error);

  /// Error when trying to unlock without having picked a container
  ///
  /// In en, this message translates to:
  /// **'Select a container first'**
  String get selectContainerFirst;

  /// Error when neither a password nor keyfiles were provided to unlock
  ///
  /// In en, this message translates to:
  /// **'Password or keyfiles required'**
  String get passwordOrKeyfilesRequired;

  /// Title of the dialog warning about slow CryFS performance without Direct Storage Access
  ///
  /// In en, this message translates to:
  /// **'Slow Performance Warning'**
  String get slowPerformanceWarningTitle;

  /// Message explaining the slow-performance tradeoff for CryFS without Direct Storage Access
  ///
  /// In en, this message translates to:
  /// **'Direct Storage Access is currently disabled.\n\nCryFS stores files across thousands of small blocks. Opening non-empty CryFS vaults via Android SAF will be very slow.\n\nWould you like to open Settings to grant \"All Files Access\" for fast speed?'**
  String get slowPerformanceWarningMessage;

  /// Button to dismiss the slow-performance warning and proceed with unlocking regardless
  ///
  /// In en, this message translates to:
  /// **'Unlock Anyway'**
  String get unlockAnyway;

  /// Fallback display name for a folder vault when none was resolved
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get defaultVaultName;

  /// Fallback display name for a container when none was resolved
  ///
  /// In en, this message translates to:
  /// **'Container'**
  String get defaultContainerName;

  /// Error message when folder-vault unlock fails
  ///
  /// In en, this message translates to:
  /// **'Incorrect password or invalid vault'**
  String get incorrectPasswordOrInvalidVault;

  /// Error message when container unlock fails
  ///
  /// In en, this message translates to:
  /// **'Incorrect password or invalid container'**
  String get incorrectPasswordOrInvalidContainer;

  /// Fallback error text when no specific error message is available
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get genericUnknownError;

  /// Generic progress label while decrypting
  ///
  /// In en, this message translates to:
  /// **'Decrypting…'**
  String get decryptingLabel;

  /// Progress label while trying successive LUKS keyslots
  ///
  /// In en, this message translates to:
  /// **'Trying keyslot {attempted} of {total}…'**
  String luksKeyslotProgress(int attempted, int total);

  /// Progress label while trying a LUKS keyslot when the total count isn't known yet
  ///
  /// In en, this message translates to:
  /// **'Trying keyslot…'**
  String get luksKeyslotProgressUnknown;

  /// Progress label while trying successive BitLocker credentials
  ///
  /// In en, this message translates to:
  /// **'Verifying credential {attempted} of {total}…'**
  String bitlockerCredentialProgress(int attempted, int total);

  /// Progress label while verifying a BitLocker credential when the total count isn't known yet
  ///
  /// In en, this message translates to:
  /// **'Verifying credential…'**
  String get bitlockerCredentialProgressUnknown;

  /// Progress label showing the hash/cipher algorithm combination currently being tried for a VeraCrypt volume
  ///
  /// In en, this message translates to:
  /// **'Trying {algo} ({slotName})…'**
  String veracryptAlgoProgress(String algo, String slotName);

  /// Title/button label for unlocking an existing (non-folder-vault) container
  ///
  /// In en, this message translates to:
  /// **'Unlock Container'**
  String get unlockContainerLabel;

  /// Title of the sheet when mounting a brand-new container (none picked yet)
  ///
  /// In en, this message translates to:
  /// **'Mount Container'**
  String get mountContainerTitle;

  /// Segmented control option for choosing a single-file container
  ///
  /// In en, this message translates to:
  /// **'Container File'**
  String get containerFileSegmentLabel;

  /// Segmented control option for choosing a folder-based vault
  ///
  /// In en, this message translates to:
  /// **'Folder Vault'**
  String get folderVaultSegmentLabel;

  /// Detected container-type label combining an untranslated format/brand name with 'Container', e.g. 'LUKS Container'
  ///
  /// In en, this message translates to:
  /// **'{format} Container'**
  String formatContainerLabel(String format);

  /// Detected container-type label combining an untranslated format/brand name with 'Vault', e.g. 'Cryptomator Vault'
  ///
  /// In en, this message translates to:
  /// **'{format} Vault'**
  String formatVaultLabel(String format);

  /// Detected container-type label combining an untranslated format/brand name with 'Drive', e.g. 'BitLocker Drive'
  ///
  /// In en, this message translates to:
  /// **'{format} Drive'**
  String formatDriveLabel(String format);

  /// Generic label for an unidentified encrypted container
  ///
  /// In en, this message translates to:
  /// **'Encrypted Container'**
  String get encryptedContainerLabel;

  /// Placeholder hint prompting the user to pick a folder vault
  ///
  /// In en, this message translates to:
  /// **'Tap to select vault folder…'**
  String get tapToSelectVaultFolder;

  /// Placeholder hint prompting the user to pick a container file
  ///
  /// In en, this message translates to:
  /// **'Tap to select container file…'**
  String get tapToSelectContainerFile;

  /// Error card title when the container file cannot be found
  ///
  /// In en, this message translates to:
  /// **'Container Missing'**
  String get containerMissingTitle;

  /// Subtitle shown alongside the container-missing title
  ///
  /// In en, this message translates to:
  /// **'File path could not be resolved'**
  String get filePathCouldNotBeResolved;

  /// Longer explanation shown when a saved container's file can't be found
  ///
  /// In en, this message translates to:
  /// **'The container file may have been moved, deleted, or its host storage is currently disconnected.'**
  String get containerMissingExplanation;

  /// Generic retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButtonLabel;

  /// Button to re-pick the location of a missing container's file
  ///
  /// In en, this message translates to:
  /// **'Locate File'**
  String get locateFileButtonLabel;

  /// Subtitle under the biometric-unlock title, explaining what authenticating will do
  ///
  /// In en, this message translates to:
  /// **'Authenticate to securely mount the container'**
  String get authenticateToMountSubtitle;

  /// Button to switch from biometric prompt to manual password entry
  ///
  /// In en, this message translates to:
  /// **'Use Password'**
  String get usePasswordButtonLabel;

  /// Button to trigger the biometric authentication prompt
  ///
  /// In en, this message translates to:
  /// **'Authenticate'**
  String get authenticateButtonLabel;

  /// Title of the pattern-unlock card shown on the unlock sheet
  ///
  /// In en, this message translates to:
  /// **'Draw Unlock Pattern'**
  String get drawUnlockPatternCardTitle;

  /// Message shown under the pattern title after an incorrect pattern attempt
  ///
  /// In en, this message translates to:
  /// **'Wrong pattern — try again'**
  String get wrongPatternTryAgain;

  /// Message shown under the pattern title prompting the user to draw their pattern
  ///
  /// In en, this message translates to:
  /// **'Connect your pattern sequence'**
  String get connectYourPatternSequence;

  /// Button to switch from pattern entry to manual password entry
  ///
  /// In en, this message translates to:
  /// **'Use Password instead'**
  String get usePasswordInsteadButtonLabel;

  /// Password field hint text when unlocking a folder vault
  ///
  /// In en, this message translates to:
  /// **'Enter vault password'**
  String get passwordHintFolderVault;

  /// Password field hint text when unlocking a BitLocker drive
  ///
  /// In en, this message translates to:
  /// **'Enter password or recovery key'**
  String get passwordHintBitlocker;

  /// Password field hint text when unlocking a regular container
  ///
  /// In en, this message translates to:
  /// **'Enter container password'**
  String get passwordHintContainer;

  /// Tooltip on the bookmark icon shown when the password field was prefilled from a saved credential
  ///
  /// In en, this message translates to:
  /// **'Using saved password'**
  String get usingSavedPasswordTooltip;

  /// Helper note shown under the keyfile picker for LUKS containers
  ///
  /// In en, this message translates to:
  /// **'For LUKS containers the keyfile replaces the password.'**
  String get luksKeyfileReplacesPasswordNote;

  /// Subtitle explaining read-only mode for a USB drive
  ///
  /// In en, this message translates to:
  /// **'Mount without allowing changes to this drive'**
  String get readOnlyModeUsbSubtitle;

  /// Subtitle explaining read-only mode for a container
  ///
  /// In en, this message translates to:
  /// **'Mount without allowing changes to this container'**
  String get readOnlyModeContainerSubtitle;

  /// Toggle label to remember/pin a newly mounted container
  ///
  /// In en, this message translates to:
  /// **'Remember container'**
  String get rememberContainerLabel;

  /// Subtitle explaining the remember-container toggle
  ///
  /// In en, this message translates to:
  /// **'Pin container on dashboard for quick access'**
  String get rememberContainerSubtitle;

  /// Button to cancel an in-progress unlock operation
  ///
  /// In en, this message translates to:
  /// **'Cancel Unlock'**
  String get cancelUnlockButtonLabel;

  /// Noun substituted into the biometric prompt reason when unlocking a local container, e.g. 'Authenticate to unlock container'
  ///
  /// In en, this message translates to:
  /// **'container'**
  String get biometricSubjectContainer;

  /// Noun substituted into the biometric prompt reason when unlocking a USB drive, e.g. 'Authenticate to unlock USB drive'
  ///
  /// In en, this message translates to:
  /// **'USB drive'**
  String get biometricSubjectUsbDrive;

  /// Fallback message when no saved password exists for biometric/pattern unlock of a USB drive
  ///
  /// In en, this message translates to:
  /// **'No saved password found. Please enter it manually.'**
  String get usbNoSavedCredentialsMessage;

  /// Progress label shown while a USB drive is being decrypted
  ///
  /// In en, this message translates to:
  /// **'Decrypting drive…'**
  String get decryptingDriveLabel;

  /// Error shown when trying to unlock a USB device that is already mounted
  ///
  /// In en, this message translates to:
  /// **'This USB device is already active and mounted.'**
  String get usbDeviceAlreadyActiveMounted;

  /// AppBar title when reconnecting a previously saved USB drive
  ///
  /// In en, this message translates to:
  /// **'Reconnect \"{label}\"'**
  String reconnectUsbDriveTitle(String label);

  /// AppBar title when unlocking a new USB drive
  ///
  /// In en, this message translates to:
  /// **'Unlock USB Drive'**
  String get unlockUsbDriveTitle;

  /// Title shown when no USB storage devices are found
  ///
  /// In en, this message translates to:
  /// **'No USB Storage Detected'**
  String get noUsbStorageDetectedTitle;

  /// Reason shown by the OS biometric prompt, combined with a source-specific subject noun
  ///
  /// In en, this message translates to:
  /// **'Authenticate to unlock {subject}'**
  String authenticateToUnlockPrompt(String subject);

  /// Error shown when a pattern is submitted but none is on record
  ///
  /// In en, this message translates to:
  /// **'No pattern configured. Please enter password manually.'**
  String get noPatternConfiguredMessage;

  /// Error shown when a new pattern-unlock lockout is triggered
  ///
  /// In en, this message translates to:
  /// **'Too many failed attempts. Locked for {seconds}s.'**
  String patternLockedForSeconds(int seconds);

  /// Message shown when biometric unlock has no saved credentials to use yet, for a local container
  ///
  /// In en, this message translates to:
  /// **'Initializing secure credentials. Please unlock manually once to authorize biometric access.'**
  String get initSecureCredsBiometricMessage;

  /// Message shown when pattern unlock has no saved credentials to use yet, for a local container
  ///
  /// In en, this message translates to:
  /// **'Initializing secure credentials. Please unlock manually once to authorize pattern access.'**
  String get initSecureCredsPatternMessage;

  /// Add-vault option title
  ///
  /// In en, this message translates to:
  /// **'Mount existing container'**
  String get mountExistingContainerTitle;

  /// Add-vault option subtitle
  ///
  /// In en, this message translates to:
  /// **'Unlock a file container you already have'**
  String get mountExistingContainerSubtitle;

  /// Add-vault option title
  ///
  /// In en, this message translates to:
  /// **'Mount split container'**
  String get mountSplitContainerTitle;

  /// Add-vault option subtitle
  ///
  /// In en, this message translates to:
  /// **'Unlock a split container directly, without joining it first'**
  String get mountSplitContainerSubtitle;

  /// Title for the USB drive mount sheet
  ///
  /// In en, this message translates to:
  /// **'Mount USB Drive'**
  String get mountUsbDriveTitle;

  /// Add-vault option subtitle
  ///
  /// In en, this message translates to:
  /// **'Unlock a container on an OTG flash drive'**
  String get mountUsbDriveSubtitle;

  /// Add-vault option title
  ///
  /// In en, this message translates to:
  /// **'Format USB drive'**
  String get formatUsbDriveTitle;

  /// Add-vault option subtitle
  ///
  /// In en, this message translates to:
  /// **'Erase a drive and create a new encrypted container on it'**
  String get formatUsbDriveSubtitle;

  /// Add-vault option title
  ///
  /// In en, this message translates to:
  /// **'Create new container'**
  String get createNewContainerTitle;

  /// Add-vault option subtitle
  ///
  /// In en, this message translates to:
  /// **'Format a brand-new encrypted vault'**
  String get createNewContainerSubtitle;

  /// Warning snackbar when trying to remove a currently mounted container
  ///
  /// In en, this message translates to:
  /// **'Lock the container before removing it.'**
  String get lockBeforeRemovingWarning;

  /// Tooltip for the settings icon button
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltip;

  /// Floating action button label to add a new vault
  ///
  /// In en, this message translates to:
  /// **'Add vault'**
  String get addVaultFabLabel;

  /// Undo bar text after removing a container from the dashboard list
  ///
  /// In en, this message translates to:
  /// **'Removed \"{label}\"'**
  String removedLabelUndo(String label);

  /// Button label to undo the last removal
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// Error shown when the PDF viewer is opened without a file, container path, or local URI
  ///
  /// In en, this message translates to:
  /// **'No PDF source provided.'**
  String get pdfViewerNoSourceProvided;

  /// Error shown when a PDF file inside a vault container has zero or unreadable size
  ///
  /// In en, this message translates to:
  /// **'PDF file is empty or unreadable.'**
  String get pdfViewerFileEmpty;

  /// Error shown when reading a PDF file's size from the vault container fails
  ///
  /// In en, this message translates to:
  /// **'Failed to inspect PDF file size: {error}'**
  String pdfViewerFailedToInspectSize(String error);

  /// Error banner title shown by the PDF rendering engine when a document fails to parse
  ///
  /// In en, this message translates to:
  /// **'Error loading PDF'**
  String get pdfViewerErrorLoadingTitle;

  /// Fallback text shown when the PDF viewer has no error, isn't loading, but has no document to display
  ///
  /// In en, this message translates to:
  /// **'No PDF document loaded.'**
  String get pdfViewerNoDocumentLoaded;

  /// Generic Add action button label
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Generic Reset action button label
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// Error when exposing a folder to the Android Document Provider fails
  ///
  /// In en, this message translates to:
  /// **'Could not expose \"{name}\".'**
  String couldNotExpose(String name);

  /// Confirmation after exposing a folder to the Android Document Provider
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is now available to other apps.'**
  String nowAvailableToOtherApps(String name);

  /// Error when unmounting a folder from the Android Document Provider fails
  ///
  /// In en, this message translates to:
  /// **'Could not unmount \"{name}\".'**
  String couldNotUnmount(String name);

  /// Status message after pinning items
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Pinned 1 item} other{Pinned {count} items}}'**
  String pinnedCount(num count);

  /// Status message after unpinning items
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Unpinned 1 item} other{Unpinned {count} items}}'**
  String unpinnedCount(num count);

  /// Warning shown when browsing a read-only container with in-container thumbnail caching selected
  ///
  /// In en, this message translates to:
  /// **'Read-only mount — thumbnails will show but won\'t be saved inside the container this session.'**
  String get readOnlyThumbnailWarning;

  /// Error status when listing a directory fails
  ///
  /// In en, this message translates to:
  /// **'Failed loading folder: {type}'**
  String failedLoadingFolder(String type);

  /// Error status when opening an archive fails
  ///
  /// In en, this message translates to:
  /// **'Failed to read archive: {type}'**
  String failedToReadArchive(String type);

  /// Error status when tapping an archive file whose format isn't supported
  ///
  /// In en, this message translates to:
  /// **'Archive format .{ext} is not yet supported'**
  String archiveFormatNotSupported(String ext);

  /// Error status when extracting a single file from an open archive fails
  ///
  /// In en, this message translates to:
  /// **'Failed to read file from archive'**
  String get failedToReadFileFromArchive;

  /// Error status when extracting a single file from an open archive throws
  ///
  /// In en, this message translates to:
  /// **'Failed to extract file: {type}'**
  String failedToExtractFile(String type);

  /// Error status when opening a vault item (password, note, etc.) fails
  ///
  /// In en, this message translates to:
  /// **'Failed to read secure item'**
  String get failedToReadSecureItem;

  /// Dialog title for choosing how to open a file with no remembered association
  ///
  /// In en, this message translates to:
  /// **'Open File'**
  String get openFileDialogTitle;

  /// Dialog subtitle asking how to open a specific file
  ///
  /// In en, this message translates to:
  /// **'Choose how to open \"{name}\":'**
  String chooseHowToOpen(String name);

  /// Description of the in-app media viewer option
  ///
  /// In en, this message translates to:
  /// **'Play video/audio or view image in-app'**
  String get playVideoAudioViewImageInApp;

  /// Description of the in-app text editor option
  ///
  /// In en, this message translates to:
  /// **'View/edit text, markdown, code'**
  String get viewEditTextMarkdownCode;

  /// Description of the external-app open option
  ///
  /// In en, this message translates to:
  /// **'Send file to third-party app'**
  String get sendFileToThirdPartyApp;

  /// Option label to choose a specific MIME type to open the file as
  ///
  /// In en, this message translates to:
  /// **'Open As…'**
  String get openAsEllipsis;

  /// Description of the open-as option
  ///
  /// In en, this message translates to:
  /// **'Choose file type to open as'**
  String get chooseFileTypeToOpenAs;

  /// Checkbox label to remember the open-with choice for a given extension
  ///
  /// In en, this message translates to:
  /// **'Always remember choice for .{ext} files'**
  String alwaysRememberChoiceExt(String ext);

  /// Checkbox label to remember the open-with choice for extensionless files
  ///
  /// In en, this message translates to:
  /// **'Always remember choice for files without extension'**
  String get alwaysRememberChoiceNoExt;

  /// Dialog title for picking a MIME type to force-open a file as
  ///
  /// In en, this message translates to:
  /// **'Open As'**
  String get openAsDialogTitle;

  /// MIME type option: plain text
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get mimeTypeText;

  /// MIME type option: image
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get mimeTypeImage;

  /// MIME type option: video
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get mimeTypeVideo;

  /// MIME type option: audio
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get mimeTypeAudio;

  /// MIME type option: archive/zip
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get mimeTypeArchive;

  /// MIME type option: any other/unknown type
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get mimeTypeOther;

  /// Status message while recursively scanning for playable media
  ///
  /// In en, this message translates to:
  /// **'Scanning subfolders for media…'**
  String get scanningSubfoldersForMedia;

  /// Error status when a recursive media scan finds nothing
  ///
  /// In en, this message translates to:
  /// **'No media files found in this folder or its subfolders'**
  String get noMediaFilesFoundRecursive;

  /// Error status when a recursive media scan throws
  ///
  /// In en, this message translates to:
  /// **'Failed to scan subfolders: {error}'**
  String failedToScanSubfolders(String error);

  /// Error status when no external app can handle a file
  ///
  /// In en, this message translates to:
  /// **'No app found for this file type'**
  String get noAppFoundForFileType;

  /// Error status when opening a file with an external app fails
  ///
  /// In en, this message translates to:
  /// **'Could not open \"{name}\"'**
  String couldNotOpenFile(String name);

  /// Error when starting a cut operation on a read-only container
  ///
  /// In en, this message translates to:
  /// **'This container is mounted read-only — items can\'t be moved from here.'**
  String get readOnlyCantMove;

  /// Error when pasting into a read-only container
  ///
  /// In en, this message translates to:
  /// **'This container is mounted read-only — items can\'t be pasted here.'**
  String get readOnlyCantPaste;

  /// Error when the clipboard's source container can't be identified
  ///
  /// In en, this message translates to:
  /// **'Clipboard source is invalid'**
  String get clipboardSourceInvalid;

  /// Error when a cross-container paste is attempted but not supported by the current screen
  ///
  /// In en, this message translates to:
  /// **'Cross-container paste is not configured.'**
  String get crossContainerPasteNotConfigured;

  /// Error when the clipboard's source container is no longer mounted
  ///
  /// In en, this message translates to:
  /// **'Cross-container paste requires both containers to remain mounted.'**
  String get crossContainerPasteRequiresBothMounted;

  /// Error when attempting to delete items from a read-only container
  ///
  /// In en, this message translates to:
  /// **'This container is mounted read-only — items can\'t be deleted.'**
  String get readOnlyCantDelete;

  /// Status message after a successful batch delete
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Deleted 1 item} other{Deleted {count} items}}'**
  String deletedCount(num count);

  /// Status message after a batch delete with some failures
  ///
  /// In en, this message translates to:
  /// **'{deleted} deleted · {failed} failed'**
  String deletedWithFailures(int deleted, int failed);

  /// Status message after exporting files to device storage
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Exported 1 file} other{Exported {count} files}}'**
  String exportedCount(num count);

  /// Status message when an export operation returns zero files
  ///
  /// In en, this message translates to:
  /// **'Export cancelled or failed'**
  String get exportCancelledOrFailed;

  /// Error status when exporting files throws
  ///
  /// In en, this message translates to:
  /// **'Export error: {type}'**
  String exportError(String type);

  /// Confirmation dialog title after an import, asking whether to delete the source
  ///
  /// In en, this message translates to:
  /// **'Delete original?'**
  String get deleteOriginalTitle;

  /// Confirmation dialog body for deleting the original imported folder
  ///
  /// In en, this message translates to:
  /// **'Delete the original folder from your device now that it has been imported?'**
  String get deleteOriginalFolderMessage;

  /// Confirmation dialog body for deleting the original imported files
  ///
  /// In en, this message translates to:
  /// **'Delete the original file(s) from your device now that they have been imported?'**
  String get deleteOriginalFilesMessage;

  /// Button label to keep the original imported files/folder on-device
  ///
  /// In en, this message translates to:
  /// **'Keep original'**
  String get keepOriginal;

  /// Button label to delete the original imported files/folder from-device
  ///
  /// In en, this message translates to:
  /// **'Delete original'**
  String get deleteOriginalButton;

  /// Status message after deleting import source files
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Deleted 1 original item} other{Deleted {count} original items}}'**
  String deletedOriginalCount(num count);

  /// Error status when deleting import source files fails
  ///
  /// In en, this message translates to:
  /// **'Could not delete original(s)'**
  String get couldNotDeleteOriginals;

  /// Status message after successfully capturing a video with the in-app camera
  ///
  /// In en, this message translates to:
  /// **'Video captured and encrypted'**
  String get videoCapturedEncrypted;

  /// Status message after successfully capturing a photo with the in-app camera
  ///
  /// In en, this message translates to:
  /// **'Photo captured and encrypted'**
  String get photoCapturedEncrypted;

  /// Error status when in-app camera capture throws
  ///
  /// In en, this message translates to:
  /// **'Camera capture failed: {type}'**
  String cameraCaptureFailed(String type);

  /// Confirmation dialog body before extracting an archive
  ///
  /// In en, this message translates to:
  /// **'Extract all files to the folder \"{folder}\"?'**
  String extractAllFilesToFolder(String folder);

  /// Button label to confirm extracting an archive
  ///
  /// In en, this message translates to:
  /// **'Extract'**
  String get extract;

  /// Status message after successfully extracting an archive
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Extracted 1 file} other{Extracted {count} files}}'**
  String extractedCount(num count);

  /// Error status when extracting an archive throws
  ///
  /// In en, this message translates to:
  /// **'Failed to extract: {type}'**
  String failedToExtractGeneric(String type);

  /// Tooltip for closing the in-folder search bar
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearchTooltip;

  /// Tooltip for opening the in-folder search bar
  ///
  /// In en, this message translates to:
  /// **'Search in this folder'**
  String get searchInThisFolderTooltip;

  /// Tooltip for the action bar button that plays all media in the current folder
  ///
  /// In en, this message translates to:
  /// **'Play media here'**
  String get playMediaHereTooltip;

  /// Display label for a container's top-level root folder
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get rootFolderLabel;

  /// Error when the folder-vault destination picker throws
  ///
  /// In en, this message translates to:
  /// **'Folder picker failed: {error}'**
  String folderPickerFailed(String error);

  /// Bottom sheet title for the add-vault options
  ///
  /// In en, this message translates to:
  /// **'Add a vault'**
  String get addAVaultTitle;

  /// Validation error when creating a folder vault without picking a destination
  ///
  /// In en, this message translates to:
  /// **'Select an empty destination folder first'**
  String get selectEmptyDestinationFolderFirst;

  /// Validation error when a required password field is empty
  ///
  /// In en, this message translates to:
  /// **'A password is required'**
  String get passwordRequired;

  /// Success snackbar after creating a folder vault
  ///
  /// In en, this message translates to:
  /// **'Vault created successfully.'**
  String get vaultCreatedSuccessfully;

  /// Error shown when folder vault creation returns failure
  ///
  /// In en, this message translates to:
  /// **'Vault creation failed — make sure the selected folder is empty.'**
  String get vaultCreationFailedEmptyFolder;

  /// Fallback error message when a platform exception has no message
  ///
  /// In en, this message translates to:
  /// **'Unknown error occurred'**
  String get unknownErrorOccurred;

  /// Validation error when the container file name field is empty
  ///
  /// In en, this message translates to:
  /// **'Container name is required'**
  String get containerNameRequired;

  /// Validation error for the container size field
  ///
  /// In en, this message translates to:
  /// **'Enter a valid size greater than 0'**
  String get enterValidSizeGreaterThanZero;

  /// Validation error when creating a container with neither a password nor keyfiles
  ///
  /// In en, this message translates to:
  /// **'A password or at least one keyfile is required'**
  String get passwordOrKeyfileRequired;

  /// Validation error when the outer volume password confirmation doesn't match
  ///
  /// In en, this message translates to:
  /// **'Standard volume passwords do not match'**
  String get standardVolumePasswordsDoNotMatch;

  /// Validation error when the hidden volume password confirmation doesn't match
  ///
  /// In en, this message translates to:
  /// **'Hidden volume passwords do not match'**
  String get hiddenVolumePasswordsDoNotMatch;

  /// Success snackbar after creating a container file
  ///
  /// In en, this message translates to:
  /// **'Container file created successfully.'**
  String get containerFileCreatedSuccessfully;

  /// Error shown when container creation returns failure
  ///
  /// In en, this message translates to:
  /// **'Container creation cancelled or failed.'**
  String get containerCreationCancelledOrFailed;

  /// Error shown when the chosen destination can't fit the requested container size
  ///
  /// In en, this message translates to:
  /// **'Not enough free space at the destination. Need {needed}, only {available} available.'**
  String insufficientSpaceForContainer(String needed, String available);

  /// Segmented button option: create a single encrypted container file
  ///
  /// In en, this message translates to:
  /// **'Container File'**
  String get vaultKindContainerFile;

  /// Segmented button option / section header: create a folder-based encrypted vault (Cryptomator/Gocryptfs/CryFS)
  ///
  /// In en, this message translates to:
  /// **'Folder Vault'**
  String get vaultKindFolderVault;

  /// Label for the inner filesystem picker when creating a container
  ///
  /// In en, this message translates to:
  /// **'Format File System'**
  String get formatFileSystemLabel;

  /// Section header for the main/outer volume creation form
  ///
  /// In en, this message translates to:
  /// **'Standard Volume'**
  String get standardVolumeHeader;

  /// Label above the VeraCrypt/LUKS1/LUKS2 format selector
  ///
  /// In en, this message translates to:
  /// **'Container Format'**
  String get containerFormatLabel;

  /// Text field label for the new container's file name
  ///
  /// In en, this message translates to:
  /// **'File Name'**
  String get fileNameLabel;

  /// Text field label for the new container's size
  ///
  /// In en, this message translates to:
  /// **'Container Size'**
  String get containerSizeLabel;

  /// Label for the MB/GB size unit picker
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unitLabel;

  /// Generic title-case Password text field label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordFieldLabel;

  /// Title-case Confirm Password text field label
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPasswordFieldLabelTitleCase;

  /// Section header for the hidden volume creation form
  ///
  /// In en, this message translates to:
  /// **'Hidden Volume'**
  String get hiddenVolumeHeader;

  /// Switch title to enable creating a hidden volume
  ///
  /// In en, this message translates to:
  /// **'Create Hidden Volume'**
  String get createHiddenVolumeToggleTitle;

  /// Switch subtitle explaining the hidden volume feature when enabled
  ///
  /// In en, this message translates to:
  /// **'Create an invisible secondary volume'**
  String get createInvisibleSecondaryVolume;

  /// Switch subtitle explaining why the hidden volume toggle is disabled
  ///
  /// In en, this message translates to:
  /// **'Set outer password or keyfiles first to enable'**
  String get setOuterPasswordFirstToEnable;

  /// Text field label for the hidden volume's password
  ///
  /// In en, this message translates to:
  /// **'Hidden Password'**
  String get hiddenPasswordLabel;

  /// Text field label for confirming the hidden volume's password
  ///
  /// In en, this message translates to:
  /// **'Confirm Hidden Password'**
  String get confirmHiddenPasswordLabel;

  /// Text field label for the hidden volume's size
  ///
  /// In en, this message translates to:
  /// **'Hidden Size'**
  String get hiddenSizeLabel;

  /// Size unit option with expanded unit name
  ///
  /// In en, this message translates to:
  /// **'MB (Megabytes)'**
  String get unitMbMegabytes;

  /// Size unit option with expanded unit name
  ///
  /// In en, this message translates to:
  /// **'GB (Gigabytes)'**
  String get unitGbGigabytes;

  /// Label for the hidden volume's inner filesystem picker
  ///
  /// In en, this message translates to:
  /// **'Hidden File System'**
  String get hiddenFileSystemLabel;

  /// Label above the Cryptomator/Gocryptfs/CryFS format selector
  ///
  /// In en, this message translates to:
  /// **'Vault Format'**
  String get vaultFormatLabel;

  /// Label above the AES-256-GCM/XChaCha20-Poly1305 cipher picker shown when creating a new gocryptfs vault
  ///
  /// In en, this message translates to:
  /// **'Content Cipher'**
  String get gocryptfsCipherLabel;

  /// Label above the XChaCha20-Poly1305/AES-256-GCM cipher picker shown when creating a new CryFS vault
  ///
  /// In en, this message translates to:
  /// **'Content Cipher'**
  String get cryfsCipherLabel;

  /// Label above the on-disk block size picker shown when creating a new CryFS vault
  ///
  /// In en, this message translates to:
  /// **'Block Size'**
  String get cryfsBlockSizeLabel;

  /// Label shown once a folder vault destination has been picked
  ///
  /// In en, this message translates to:
  /// **'Destination Folder'**
  String get destinationFolderLabel;

  /// Label shown before a folder vault destination has been picked
  ///
  /// In en, this message translates to:
  /// **'Select an empty folder'**
  String get selectEmptyFolderLabel;

  /// Placeholder hint for the folder vault destination picker card
  ///
  /// In en, this message translates to:
  /// **'Tap to choose where vault will be created…'**
  String get tapToChooseVaultLocation;

  /// Informational note below the folder vault creation form
  ///
  /// In en, this message translates to:
  /// **'Folder vaults don\'t support keyfiles, PIM, hidden volumes, or VeraCrypt/LUKS cipher choices.'**
  String get folderVaultLimitationsNote;

  /// Button label to create a new vault
  ///
  /// In en, this message translates to:
  /// **'Create Vault'**
  String get createVaultButton;

  /// Submit button label when creating a container file
  ///
  /// In en, this message translates to:
  /// **'Create Container'**
  String get createContainerButton;

  /// Warning shown when trying to leave the screen while a folder vault is being created
  ///
  /// In en, this message translates to:
  /// **'Vault creation in progress. Please wait.'**
  String get vaultCreationInProgressWait;

  /// Warning shown when trying to leave the screen while a container file is being created
  ///
  /// In en, this message translates to:
  /// **'Container creation in progress. Please wait.'**
  String get containerCreationInProgressWait;

  /// AppBar title when creating a folder vault
  ///
  /// In en, this message translates to:
  /// **'Create Encrypted Vault'**
  String get createEncryptedVaultTitle;

  /// AppBar title when creating a container file
  ///
  /// In en, this message translates to:
  /// **'Create Encrypted Container'**
  String get createEncryptedContainerTitle;

  /// Short abbreviation for megabytes
  ///
  /// In en, this message translates to:
  /// **'MB'**
  String get unitMbShort;

  /// Short abbreviation for gigabytes
  ///
  /// In en, this message translates to:
  /// **'GB'**
  String get unitGbShort;

  /// Error when enumerating connected USB storage devices fails
  ///
  /// In en, this message translates to:
  /// **'Failed to list USB devices: {error}'**
  String failedToListUsbDevices(String error);

  /// Error when the user denies the USB device access permission prompt
  ///
  /// In en, this message translates to:
  /// **'USB permission denied'**
  String get usbPermissionDenied;

  /// Error when the USB drive's capacity can't be auto-detected
  ///
  /// In en, this message translates to:
  /// **'Could not read drive capacity — enter size manually.'**
  String get couldNotReadDriveCapacity;

  /// Validation error when creating a USB container without selecting a device
  ///
  /// In en, this message translates to:
  /// **'Select a USB drive first'**
  String get selectUsbDriveFirst;

  /// Confirmation dialog title before formatting a USB drive
  ///
  /// In en, this message translates to:
  /// **'Erase \"{name}\"?'**
  String eraseDeviceTitle(String name);

  /// Confirmation dialog body before formatting a USB drive
  ///
  /// In en, this message translates to:
  /// **'This will permanently erase everything currently on this USB drive and replace it with a new encrypted container. This cannot be undone.'**
  String get eraseDeviceMessage;

  /// Confirmation dialog button to proceed with erasing and formatting a USB drive
  ///
  /// In en, this message translates to:
  /// **'Erase & Create'**
  String get eraseAndCreateButton;

  /// Error shown when USB device access permission is missing at creation time
  ///
  /// In en, this message translates to:
  /// **'USB permission is required to continue'**
  String get usbPermissionRequiredToContinue;

  /// Success snackbar after formatting a USB drive with a new encrypted container
  ///
  /// In en, this message translates to:
  /// **'USB container created. Use \"Mount USB drive\" to unlock it.'**
  String get usbContainerCreatedSnack;

  /// Error shown when USB container creation returns failure
  ///
  /// In en, this message translates to:
  /// **'USB container creation failed.'**
  String get usbContainerCreationFailed;

  /// Section header for the USB drive selection and outer volume form
  ///
  /// In en, this message translates to:
  /// **'USB Drive & Standard Volume'**
  String get usbStandardVolumeSectionHeader;

  /// Warning banner shown on the USB container creation screen
  ///
  /// In en, this message translates to:
  /// **'Formatting erases everything currently on the selected drive.'**
  String get formattingErasesEverythingWarning;

  /// Label above the USB device picker list
  ///
  /// In en, this message translates to:
  /// **'Select USB Drive'**
  String get selectUsbDriveLabel;

  /// Empty state title when no USB devices are connected
  ///
  /// In en, this message translates to:
  /// **'No USB storage detected'**
  String get noUsbStorageDetected;

  /// Empty state message when no USB devices are connected
  ///
  /// In en, this message translates to:
  /// **'Connect an OTG drive to format'**
  String get connectOtgDriveToFormat;

  /// Button label to re-scan for connected USB devices
  ///
  /// In en, this message translates to:
  /// **'Refresh list'**
  String get refreshListButton;

  /// Status label for a USB device with permission already granted
  ///
  /// In en, this message translates to:
  /// **'Ready to format'**
  String get readyToFormat;

  /// Status label for a USB device that needs an access permission grant
  ///
  /// In en, this message translates to:
  /// **'Permission required'**
  String get permissionRequired;

  /// Status message while auto-detecting a USB drive's capacity
  ///
  /// In en, this message translates to:
  /// **'Reading drive capacity…'**
  String get readingDriveCapacity;

  /// Helper text under the USB container size field
  ///
  /// In en, this message translates to:
  /// **'Must not exceed the drive\'s actual capacity.'**
  String get mustNotExceedDriveCapacity;

  /// Switch title for skipping a full zero-fill when formatting a USB drive
  ///
  /// In en, this message translates to:
  /// **'Quick Format'**
  String get quickFormatTitle;

  /// Switch subtitle explaining Quick Format's tradeoff
  ///
  /// In en, this message translates to:
  /// **'Skips zero-filling the drive. Faster, but does not securely erase old data.'**
  String get quickFormatDescription;

  /// Submit button label to format the USB drive and create the container
  ///
  /// In en, this message translates to:
  /// **'Erase & Create Container'**
  String get eraseAndCreateContainerButton;

  /// Warning shown when trying to leave the screen while a USB container is being created
  ///
  /// In en, this message translates to:
  /// **'Container creation in progress. Please wait.'**
  String get usbContainerCreationInProgressWait;

  /// AppBar title for the USB drive formatting screen
  ///
  /// In en, this message translates to:
  /// **'Format USB Drive'**
  String get formatUsbDriveScreenTitle;

  /// Label for the playlist transition effect settings option
  ///
  /// In en, this message translates to:
  /// **'Playlist Transition Animation'**
  String get playlistTransitionAnimationLabel;

  /// Playlist transition effect: default horizontal slide
  ///
  /// In en, this message translates to:
  /// **'Slide (Default)'**
  String get playlistTransitionSlideLabel;

  /// Playlist transition effect: cross-fade
  ///
  /// In en, this message translates to:
  /// **'Fade'**
  String get playlistTransitionFadeLabel;

  /// Playlist transition effect: zoom and scale
  ///
  /// In en, this message translates to:
  /// **'Zoom & Scale'**
  String get playlistTransitionZoomLabel;

  /// Playlist transition effect: 3D depth stack
  ///
  /// In en, this message translates to:
  /// **'Depth Stack'**
  String get playlistTransitionDepthLabel;

  /// Playlist transition effect: 3D cube rotation
  ///
  /// In en, this message translates to:
  /// **'3D Cube'**
  String get playlistTransitionCubeLabel;

  /// Playlist transition effect: 3D card flip
  ///
  /// In en, this message translates to:
  /// **'3D Flip'**
  String get playlistTransitionFlipLabel;

  /// Title for the vault unlock bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Unlock Vault'**
  String get unlockVaultTitle;

  /// Title when opening an unmounted container
  ///
  /// In en, this message translates to:
  /// **'Open Container'**
  String get openContainerTitle;

  /// Label for picking a container file or folder
  ///
  /// In en, this message translates to:
  /// **'Select File or Folder'**
  String get selectContainerFileOrFolder;

  /// Checkbox label for mounting in read-only mode
  ///
  /// In en, this message translates to:
  /// **'Read-only mode'**
  String get readOnlyModeLabel;

  /// Subtitle explaining read-only mode
  ///
  /// In en, this message translates to:
  /// **'Prevents any write or modify operations on the vault'**
  String get readOnlyModeSubtitle;

  /// Label for USB device selector
  ///
  /// In en, this message translates to:
  /// **'Select USB Device'**
  String get selectUsbDeviceLabel;

  /// Message when no USB devices are detected
  ///
  /// In en, this message translates to:
  /// **'No compatible USB storage devices found'**
  String get noUsbDevicesFound;

  /// Title for container configuration sheet
  ///
  /// In en, this message translates to:
  /// **'Vault Configuration'**
  String get containerConfigTitle;

  /// Title for the change password screen/button
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePasswordTitle;

  /// Label for confirm new password input field
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPasswordLabel;

  /// Title for in-app secure camera screen
  ///
  /// In en, this message translates to:
  /// **'Vault Camera'**
  String get cameraCaptureTitle;

  /// Status text while taking a photo
  ///
  /// In en, this message translates to:
  /// **'Capturing photo…'**
  String get takingPhoto;

  /// Status text while saving captured media directly to vault
  ///
  /// In en, this message translates to:
  /// **'Saving to vault…'**
  String get savingToVault;

  /// Message when camera is launched without a target vault
  ///
  /// In en, this message translates to:
  /// **'No vault selected'**
  String get noVaultSelected;

  /// Title for media viewer diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Media Diagnostics'**
  String get mediaDiagnosticsTitle;

  /// Title for advanced media viewer settings sheet
  ///
  /// In en, this message translates to:
  /// **'Viewer Settings'**
  String get advancedViewerSettingsTitle;

  /// Title for unsaved changes confirm dialog in text editor
  ///
  /// In en, this message translates to:
  /// **'Unsaved Changes'**
  String get textEditorSaveConfirmTitle;

  /// Message for unsaved changes confirm dialog in text editor
  ///
  /// In en, this message translates to:
  /// **'Do you want to save your changes before closing?'**
  String get textEditorSaveConfirmMessage;

  /// Button label to save changes and close editor
  ///
  /// In en, this message translates to:
  /// **'Save & Close'**
  String get saveAndClose;

  /// Button label to discard changes and close editor
  ///
  /// In en, this message translates to:
  /// **'Discard Changes'**
  String get discardChanges;

  /// Plural label for selection app bar
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item selected} other{{count} items selected}}'**
  String selectionBarSelectedCount(int count);

  /// Action label to select all items in file browser
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// Action label to clear item selection
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get deselectAll;

  /// Title for file browser sort options sheet
  ///
  /// In en, this message translates to:
  /// **'Sort Files'**
  String get sortOptionsTitle;

  /// Menu option for list layout mode
  ///
  /// In en, this message translates to:
  /// **'List View'**
  String get layoutModeList;

  /// Menu option for grid layout mode
  ///
  /// In en, this message translates to:
  /// **'Grid View'**
  String get layoutModeGrid;

  /// Menu option for masonry layout mode
  ///
  /// In en, this message translates to:
  /// **'Masonry View'**
  String get layoutModeMasonry;

  /// Title for file operations action sheet
  ///
  /// In en, this message translates to:
  /// **'File Operations'**
  String get fileOperationsTitle;

  /// Title for conflict resolution sheet when copying/moving files
  ///
  /// In en, this message translates to:
  /// **'File Conflict'**
  String get conflictResolutionTitle;

  /// Option to overwrite existing file in conflict resolution
  ///
  /// In en, this message translates to:
  /// **'Replace existing file'**
  String get replaceExistingFile;

  /// Option to keep both files in conflict resolution
  ///
  /// In en, this message translates to:
  /// **'Keep both (rename new file)'**
  String get keepBothFiles;

  /// Option to skip file in conflict resolution
  ///
  /// In en, this message translates to:
  /// **'Skip this file'**
  String get skipFile;

  /// Title for dashboard empty state
  ///
  /// In en, this message translates to:
  /// **'No Vaults Found'**
  String get noVaultsFoundTitle;

  /// Subtitle for dashboard empty state
  ///
  /// In en, this message translates to:
  /// **'Create a new encrypted container or add an existing vault to get started.'**
  String get noVaultsFoundSubtitle;

  /// Button label to add an existing vault
  ///
  /// In en, this message translates to:
  /// **'Add Existing Vault'**
  String get addExistingVaultButton;

  /// Sort option for manual ordering
  ///
  /// In en, this message translates to:
  /// **'Manual (drag to reorder)'**
  String get sortContainersModeManual;

  /// Sort option by unlock status
  ///
  /// In en, this message translates to:
  /// **'Unlock status (unlocked first)'**
  String get sortContainersModeUnlockStatus;

  /// Sort option A to Z
  ///
  /// In en, this message translates to:
  /// **'Name (A–Z)'**
  String get sortContainersModeNameAZ;

  /// Sort option Z to A
  ///
  /// In en, this message translates to:
  /// **'Name (Z–A)'**
  String get sortContainersModeNameZA;

  /// Sort option newest first
  ///
  /// In en, this message translates to:
  /// **'Newest first'**
  String get sortContainersModeNewest;

  /// Sort option oldest first
  ///
  /// In en, this message translates to:
  /// **'Oldest first'**
  String get sortContainersModeOldest;

  /// Label for app cache thumbnail mode
  ///
  /// In en, this message translates to:
  /// **'App cache'**
  String get thumbnailCacheAppCacheLabel;

  /// Description for app cache thumbnail mode
  ///
  /// In en, this message translates to:
  /// **'Stored encrypted in the App cache. Fast; cleared automatically under storage pressure.'**
  String get thumbnailCacheAppCacheDesc;

  /// Label for in-container thumbnail mode
  ///
  /// In en, this message translates to:
  /// **'Inside container'**
  String get thumbnailCacheInContainerLabel;

  /// Description for in-container thumbnail mode
  ///
  /// In en, this message translates to:
  /// **'Stored inside the encrypted container. Protected by the container itself, but writes are slower.'**
  String get thumbnailCacheInContainerDesc;

  /// Label for disabled thumbnail mode
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get thumbnailCacheDisabledLabel;

  /// Description for disabled thumbnail mode
  ///
  /// In en, this message translates to:
  /// **'No disk cache. Thumbnails are re-generated on every load.'**
  String get thumbnailCacheDisabledDesc;

  /// AppBar title when unlocking a known container
  ///
  /// In en, this message translates to:
  /// **'Unlock Container'**
  String get unlockContainerTitle;

  /// Segmented button label for container-file unlock mode
  ///
  /// In en, this message translates to:
  /// **'Container File'**
  String get containerFileSegment;

  /// Segmented button label for folder-vault unlock mode
  ///
  /// In en, this message translates to:
  /// **'Folder Vault'**
  String get folderVaultSegment;

  /// Button label to enable a feature (e.g. storage access)
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enableButtonLabel;

  /// Short retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButtonLabelShort;

  /// Button to relocate a missing container file
  ///
  /// In en, this message translates to:
  /// **'Locate File'**
  String get locateFileButton;

  /// Button label to trigger biometric authentication
  ///
  /// In en, this message translates to:
  /// **'Authenticate'**
  String get authenticateButton;

  /// Button to cancel an in-progress unlock operation
  ///
  /// In en, this message translates to:
  /// **'Cancel Unlock'**
  String get cancelUnlockButton;

  /// LUKS unlock progress with multiple keyslots
  ///
  /// In en, this message translates to:
  /// **'Trying keyslot {attempted} of {total}…'**
  String tryingKeyslotProgress(int attempted, int total);

  /// LUKS unlock progress with a single keyslot
  ///
  /// In en, this message translates to:
  /// **'Trying keyslot…'**
  String get tryingKeyslotSingle;

  /// BitLocker unlock progress with multiple credentials
  ///
  /// In en, this message translates to:
  /// **'Verifying credential {attempted} of {total}…'**
  String verifyingCredentialProgress(int attempted, int total);

  /// BitLocker unlock progress with a single credential
  ///
  /// In en, this message translates to:
  /// **'Verifying credential…'**
  String get verifyingCredentialSingle;

  /// VeraCrypt unlock progress showing algorithm and slot
  ///
  /// In en, this message translates to:
  /// **'Trying {algo} ({slotName})…'**
  String tryingAlgoSlot(String algo, String slotName);

  /// Slot name for VeraCrypt hidden volume during unlock
  ///
  /// In en, this message translates to:
  /// **'Hidden Volume'**
  String get hiddenVolumeSlotName;

  /// Slot name for VeraCrypt standard volume during unlock
  ///
  /// In en, this message translates to:
  /// **'Standard Volume'**
  String get standardVolumeSlotName;

  /// Error card subtitle when the container file cannot be found
  ///
  /// In en, this message translates to:
  /// **'File path could not be resolved'**
  String get containerMissingSubtitle;

  /// Explanation text when a container is missing
  ///
  /// In en, this message translates to:
  /// **'The container file may have been moved, deleted, or its host storage is currently disconnected.'**
  String get containerMissingBody;

  /// Subtitle prompting the user to draw their pattern
  ///
  /// In en, this message translates to:
  /// **'Connect your pattern sequence'**
  String get connectPatternSequence;

  /// Label for password text field
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get passwordLabel;

  /// Hint text for folder-vault password field
  ///
  /// In en, this message translates to:
  /// **'Enter vault password'**
  String get enterVaultPasswordHint;

  /// Hint text for BitLocker password field
  ///
  /// In en, this message translates to:
  /// **'Enter password or recovery key'**
  String get enterBitlockerPasswordHint;

  /// Hint text for container password field
  ///
  /// In en, this message translates to:
  /// **'Enter container password'**
  String get enterContainerPasswordHint;

  /// Read-only toggle subtitle specific to USB drives
  ///
  /// In en, this message translates to:
  /// **'Mount without allowing changes to this drive'**
  String get readOnlyModeUsbSubtitleDrive;

  /// Toggle label to pin a USB drive on the dashboard
  ///
  /// In en, this message translates to:
  /// **'Remember drive'**
  String get rememberDriveLabel;

  /// Subtitle for remember-drive toggle
  ///
  /// In en, this message translates to:
  /// **'Pin drive on dashboard for quick access'**
  String get rememberDriveSubtitle;

  /// Button label to unlock a folder vault
  ///
  /// In en, this message translates to:
  /// **'Unlock Vault'**
  String get unlockVaultButtonLabel;

  /// Warning message about CryFS performance without direct storage access
  ///
  /// In en, this message translates to:
  /// **'CryFS vaults use thousands of small block files. Without Direct Storage Access, performance will be significantly slower.'**
  String get cryfsStorageAccessWarning;

  /// Warning message about folder vault performance without direct storage access
  ///
  /// In en, this message translates to:
  /// **'Direct Storage Access is disabled. Opening and reading files in folder vaults may be slower.'**
  String get folderVaultStorageAccessWarning;

  /// Progress label while requesting USB permission
  ///
  /// In en, this message translates to:
  /// **'Requesting permission…'**
  String get requestingPermission;

  /// Button label for USB reconnect unlock
  ///
  /// In en, this message translates to:
  /// **'Unlock & Mount'**
  String get unlockAndMountButton;

  /// Button label to unlock a USB drive
  ///
  /// In en, this message translates to:
  /// **'Unlock Drive'**
  String get unlockDriveButton;

  /// Error title when a saved USB device is not found
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t find \"{deviceName}\"'**
  String couldntFindDevice(String deviceName);

  /// Instruction when a saved USB device is not found
  ///
  /// In en, this message translates to:
  /// **'Plug the drive back in and tap Retry, or select it below if it shows up under a different name.'**
  String get plugDriveBackInRetry;

  /// Button to retry USB device connection
  ///
  /// In en, this message translates to:
  /// **'Retry Connection'**
  String get retryConnectionButton;

  /// Button to refresh USB device list
  ///
  /// In en, this message translates to:
  /// **'Refresh Devices'**
  String get refreshDevicesButton;

  /// Empty state subtitle when no USB devices are detected
  ///
  /// In en, this message translates to:
  /// **'Connect an OTG flash drive to mount'**
  String get connectOtgDriveToMount;

  /// Status label for an already-mounted USB device
  ///
  /// In en, this message translates to:
  /// **'Already active'**
  String get alreadyActive;

  /// Short badge label for an already-active USB device
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// Status label for a USB device with permission granted
  ///
  /// In en, this message translates to:
  /// **'Ready to unlock'**
  String get readyToUnlock;

  /// Hint text for USB partition password field
  ///
  /// In en, this message translates to:
  /// **'Enter USB partition password'**
  String get enterUsbPartitionPassword;

  /// Title of the biometric auth card on USB unlock
  ///
  /// In en, this message translates to:
  /// **'Biometric Authentication'**
  String get biometricAuthenticationTitle;

  /// Subtitle of the biometric auth card on USB unlock
  ///
  /// In en, this message translates to:
  /// **'Authenticate to unlock and mount this USB device'**
  String get biometricAuthUsbSubtitle;

  /// Subtitle prompting the user to draw their pattern to mount USB
  ///
  /// In en, this message translates to:
  /// **'Connect your pattern sequence to mount'**
  String get connectPatternSequenceToMount;

  /// Menu item to select all items
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAllAction;

  /// Menu item to clear the selection
  ///
  /// In en, this message translates to:
  /// **'Clear Selection'**
  String get clearSelectionAction;

  /// Tooltip for close/clear selection button
  ///
  /// In en, this message translates to:
  /// **'Clear selection'**
  String get clearSelectionTooltip;

  /// Tooltip for the selection dropdown menu
  ///
  /// In en, this message translates to:
  /// **'Selection options'**
  String get selectionOptionsTooltip;

  /// Tooltip shown when an action is disabled due to read-only
  ///
  /// In en, this message translates to:
  /// **'Read-only container'**
  String get readOnlyContainerTooltip;

  /// Action label to copy items
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyAction;

  /// Action label to move/cut items
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get moveAction;

  /// Action label to rename items
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameAction;

  /// Menu item to export items to the device
  ///
  /// In en, this message translates to:
  /// **'Export to device'**
  String get exportToDeviceAction;

  /// Menu item to open a file with an external app
  ///
  /// In en, this message translates to:
  /// **'Open with App'**
  String get openWithAppAction;

  /// Menu item to pin item
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pinAction;

  /// Menu item to pin multiple items
  ///
  /// In en, this message translates to:
  /// **'Pin selected'**
  String get pinSelectedAction;

  /// Menu item to unpin item
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpinAction;

  /// Menu item to unpin multiple items
  ///
  /// In en, this message translates to:
  /// **'Unpin selected'**
  String get unpinSelectedAction;

  /// Menu item for document provider settings on a folder
  ///
  /// In en, this message translates to:
  /// **'Document Provider Settings'**
  String get documentProviderSettingsMenu;

  /// Menu item to expose a folder as a document provider
  ///
  /// In en, this message translates to:
  /// **'Expose as Document Provider'**
  String get exposeAsDocumentProviderMenu;

  /// Tooltip for the more-options overflow menu
  ///
  /// In en, this message translates to:
  /// **'More options'**
  String get moreOptionsTooltipShort;

  /// Tooltip for copy icon button
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copyTooltip;

  /// Hint text for the bottom search bar
  ///
  /// In en, this message translates to:
  /// **'Search in this folder…'**
  String get searchInThisFolderHint;

  /// Tooltip for clear text button
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearTooltip;

  /// Tooltip for the back button in browser app bar
  ///
  /// In en, this message translates to:
  /// **'Back to dashboard'**
  String get backToDashboardTooltip;

  /// Button to cancel a paste operation
  ///
  /// In en, this message translates to:
  /// **'Cancel paste'**
  String get cancelPasteButton;

  /// Button to cancel an import operation, shown on the same conflict-resolution sheet as cancelPasteButton when it's resolving conflicts for an import instead of a paste
  ///
  /// In en, this message translates to:
  /// **'Cancel import'**
  String get cancelImportButton;

  /// Button to continue a conflict resolution
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// Button to skip a conflicting file
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skipButton;

  /// Button to keep both files in conflict resolution
  ///
  /// In en, this message translates to:
  /// **'Keep both'**
  String get keepBothButton;

  /// Button to clear all file operations
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAllButton;

  /// Toggle title for auto-mounting a document provider folder
  ///
  /// In en, this message translates to:
  /// **'Auto-mount when container unlocks'**
  String get autoMountWhenUnlocksTitle;

  /// Toggle subtitle for auto-mounting a document provider folder
  ///
  /// In en, this message translates to:
  /// **'Expose this folder again automatically next time'**
  String get autoMountWhenUnlocksSubtitle;

  /// Button to unmount a document provider folder
  ///
  /// In en, this message translates to:
  /// **'Unmount'**
  String get unmountButton;

  /// Menu item for filters
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filtersMenuItem;

  /// Menu item for settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsMenuItem;

  /// Tooltip for sort options menu button
  ///
  /// In en, this message translates to:
  /// **'Sort options'**
  String get sortOptionsTooltip;

  /// Tooltip for layout mode menu button
  ///
  /// In en, this message translates to:
  /// **'Layout options'**
  String get layoutOptionsTooltip;

  /// Tooltip for the lock container action button
  ///
  /// In en, this message translates to:
  /// **'Lock container'**
  String get lockContainerTooltip;

  /// Tooltip for the rename action button
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get renameTooltip;

  /// Tooltip for cancelling password update
  ///
  /// In en, this message translates to:
  /// **'Cancel updating password'**
  String get cancelUpdatingPasswordTooltip;

  /// Button to open unlock method settings
  ///
  /// In en, this message translates to:
  /// **'Unlock Settings'**
  String get unlockSettingsButton;

  /// Button to update saved credentials for a container
  ///
  /// In en, this message translates to:
  /// **'Update Saved Credentials'**
  String get updateSavedCredentialsButton;

  /// Dialog title for verifying credentials before update
  ///
  /// In en, this message translates to:
  /// **'Verify Credentials'**
  String get verifyCredentialsTitle;

  /// Button label to verify credentials
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verifyButton;

  /// Dialog title for editing a container display name
  ///
  /// In en, this message translates to:
  /// **'Display Name'**
  String get displayNameTitle;

  /// Hint text for the container name input field
  ///
  /// In en, this message translates to:
  /// **'Container name'**
  String get containerNameHint;

  /// Confirmation dialog title for deleting a single file
  ///
  /// In en, this message translates to:
  /// **'Delete file?'**
  String get deleteFileDialogTitle;

  /// Warning text in the delete file confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This action is permanent and cannot be undone.'**
  String get deleteFilePermanentWarning;

  /// Dialog title when closing text editor with unsaved changes
  ///
  /// In en, this message translates to:
  /// **'Unsaved Changes'**
  String get unsavedChangesTitle;

  /// Dialog message when closing text editor with unsaved changes
  ///
  /// In en, this message translates to:
  /// **'You have unsaved changes. Would you like to save before closing?'**
  String get unsavedChangesMessage;

  /// Button label to discard changes
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardButton;

  /// Loading message while decrypting a file for the text editor
  ///
  /// In en, this message translates to:
  /// **'Decrypting file content...'**
  String get decryptingFileContent;

  /// Error title when a file cannot be opened in the text editor
  ///
  /// In en, this message translates to:
  /// **'Cannot open file'**
  String get cannotOpenFile;

  /// Snackbar message after successfully saving a text file
  ///
  /// In en, this message translates to:
  /// **'Changes saved successfully'**
  String get changesSavedSuccessfully;

  /// Snackbar message when saving a text file fails
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveFailedWithError(String error);

  /// Bottom bar line count in text editor
  ///
  /// In en, this message translates to:
  /// **'Lines: {count}'**
  String linesCount(int count);

  /// Bottom bar character count in text editor
  ///
  /// In en, this message translates to:
  /// **'Chars: {count}'**
  String charsCount(int count);

  /// Bottom bar status when text editor has unsaved changes
  ///
  /// In en, this message translates to:
  /// **'Unsaved Changes'**
  String get unsavedChangesLabel;

  /// Bottom bar status when text file is saved
  ///
  /// In en, this message translates to:
  /// **'Saved to vault'**
  String get savedToVault;

  /// Tooltip for save icon button in text editor
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChangesTooltip;

  /// Exception message when the text editor fails to decrypt a file from the vault for editing
  ///
  /// In en, this message translates to:
  /// **'Failed to decrypt file from vault.'**
  String get textEditorDecryptFailedMessage;

  /// Exception message when a file's bytes cannot be decoded as UTF-8 text in the text editor
  ///
  /// In en, this message translates to:
  /// **'The file does not appear to be a valid text file.'**
  String get textEditorInvalidTextFileMessage;

  /// Exception message when the text editor fails to write edited content back into the vault
  ///
  /// In en, this message translates to:
  /// **'Failed to write file back to vault.'**
  String get textEditorWriteBackFailedMessage;

  /// Generic back navigation tooltip
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backTooltip;

  /// Forward navigation tooltip for HTML viewer
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get forwardTooltip;

  /// Reload tooltip for HTML viewer
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reloadTooltip;

  /// Options menu tooltip
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get optionsTooltip;

  /// Error state title shown when the HTML viewer fails to render a page
  ///
  /// In en, this message translates to:
  /// **'Cannot display this page'**
  String get htmlViewerErrorTitle;

  /// Fallback error message shown in the HTML viewer when a page fails to load and the platform side did not supply a more specific message
  ///
  /// In en, this message translates to:
  /// **'Failed to load file'**
  String get htmlViewerLoadFailedMessage;

  /// Confirmation dialog title shown before enabling JavaScript in the HTML viewer
  ///
  /// In en, this message translates to:
  /// **'Enable JavaScript?'**
  String get enableJavaScriptDialogTitle;

  /// Confirmation dialog message explaining the effect of enabling JavaScript in the HTML viewer
  ///
  /// In en, this message translates to:
  /// **'The page will be allowed to run its own local scripts. It still has no network access — nothing in this vault can be sent or received over the internet.'**
  String get enableJavaScriptDialogMessage;

  /// Menu item to disable JavaScript in HTML viewer
  ///
  /// In en, this message translates to:
  /// **'Disable JavaScript'**
  String get disableJavaScriptMenu;

  /// Menu item to enable JavaScript in HTML viewer
  ///
  /// In en, this message translates to:
  /// **'Enable JavaScript'**
  String get enableJavaScriptMenu;

  /// Menu item to enter fullscreen mode
  ///
  /// In en, this message translates to:
  /// **'Enter Fullscreen'**
  String get enterFullscreenMenu;

  /// Snackbar error when opening a file in external app fails
  ///
  /// In en, this message translates to:
  /// **'Failed to open in external app: {error}'**
  String failedToOpenExternalApp(String error);

  /// Menu item for current-folder-only playlist scope
  ///
  /// In en, this message translates to:
  /// **'This Folder'**
  String get thisFolderMenu;

  /// Menu item for all-including-subfolders playlist scope
  ///
  /// In en, this message translates to:
  /// **'All (Incl. Subfolders)'**
  String get allInclSubfoldersMenu;

  /// Menu item to disable playlist shuffle
  ///
  /// In en, this message translates to:
  /// **'Disable Shuffle'**
  String get disableShuffleMenu;

  /// Menu item to enable playlist shuffle
  ///
  /// In en, this message translates to:
  /// **'Shuffle Playlist'**
  String get shufflePlaylistMenu;

  /// Tooltip when playlist is active
  ///
  /// In en, this message translates to:
  /// **'Playlist Options'**
  String get playlistOptionsTooltip;

  /// Tooltip when playlist is not active
  ///
  /// In en, this message translates to:
  /// **'Enable Playlist'**
  String get enablePlaylistTooltip;

  /// Tooltip for the more-actions menu
  ///
  /// In en, this message translates to:
  /// **'More Actions'**
  String get moreActionsTooltip;

  /// Menu item to force portrait orientation
  ///
  /// In en, this message translates to:
  /// **'Force Portrait'**
  String get forcePortraitMenu;

  /// Menu item to force landscape orientation
  ///
  /// In en, this message translates to:
  /// **'Force Landscape'**
  String get forceLandscapeMenu;

  /// Menu item to follow sensor orientation
  ///
  /// In en, this message translates to:
  /// **'Auto-Rotate (Sensor)'**
  String get autoRotateSensorMenu;

  /// Submenu title for screen orientation options
  ///
  /// In en, this message translates to:
  /// **'Screen Orientation'**
  String get screenOrientationMenu;

  /// Submenu title for playlist transition effect options
  ///
  /// In en, this message translates to:
  /// **'Playlist Transition'**
  String get playlistTransitionMenu;

  /// Menu item to rename the current file
  ///
  /// In en, this message translates to:
  /// **'Rename File'**
  String get renameFileMenu;

  /// Menu item to delete the current file
  ///
  /// In en, this message translates to:
  /// **'Delete File'**
  String get deleteFileMenu;

  /// Tooltip for toggle thumbnail carousel button
  ///
  /// In en, this message translates to:
  /// **'Thumbnail Carousel'**
  String get thumbnailCarouselTooltip;

  /// Tooltip for advanced settings button
  ///
  /// In en, this message translates to:
  /// **'Advanced Settings'**
  String get advancedSettingsTooltip;

  /// Tooltip for previous media button
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get previousTooltip;

  /// Tooltip for next media button
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get nextTooltip;

  /// Snackbar message when diagnostics are copied
  ///
  /// In en, this message translates to:
  /// **'Diagnostics copied to clipboard'**
  String get diagnosticsCopiedToClipboard;

  /// Title of the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// Tooltip for copy diagnostics button
  ///
  /// In en, this message translates to:
  /// **'Copy diagnostics'**
  String get copyDiagnosticsTooltip;

  /// Tooltip for close button
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeTooltip;

  /// Section header for playback stats in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get diagnosticsPlaybackSection;

  /// Section header for engine stats in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get diagnosticsEngineSection;

  /// Stat row label for playback state in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'State'**
  String get diagnosticsStateLabel;

  /// Stat row label for video resolution in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get diagnosticsResolutionLabel;

  /// Stat row label for aspect ratio in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Aspect Ratio'**
  String get diagnosticsAspectRatioLabel;

  /// Stat row label for playback position in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get diagnosticsPositionLabel;

  /// Stat row label for media duration in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get diagnosticsDurationLabel;

  /// Stat row label and playback state value for an error condition in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get diagnosticsErrorLabel;

  /// Stat row label for the playback engine name in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get diagnosticsPlayerLabel;

  /// Stat row label for the decoding method in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Decoding'**
  String get diagnosticsDecodingLabel;

  /// Stat row value naming the playback engine in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'ExoPlayer (Android)'**
  String get diagnosticsExoPlayerValue;

  /// Stat row value describing the decoding method in the diagnostics sheet
  ///
  /// In en, this message translates to:
  /// **'Hardware-accelerated'**
  String get diagnosticsHardwareAcceleratedValue;

  /// Fallback stat value in the diagnostics sheet when resolution or aspect ratio is unavailable
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get diagnosticsUnknownValue;

  /// Playback state value shown in the diagnostics sheet while the player is buffering
  ///
  /// In en, this message translates to:
  /// **'Buffering'**
  String get diagnosticsStateBuffering;

  /// Playback state value shown in the diagnostics sheet while media is playing
  ///
  /// In en, this message translates to:
  /// **'Playing'**
  String get diagnosticsStatePlaying;

  /// Playback state value shown in the diagnostics sheet while media is paused
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get diagnosticsStatePaused;

  /// Fallback duration/position value in the diagnostics sheet when the time is negative or unavailable
  ///
  /// In en, this message translates to:
  /// **'--:--'**
  String get diagnosticsDurationUnavailable;

  /// Label for rotate 90 degrees action
  ///
  /// In en, this message translates to:
  /// **'Rotate 90°'**
  String get rotate90Label;

  /// Label for image fit mode option
  ///
  /// In en, this message translates to:
  /// **'Image Fit Mode'**
  String get imageFitModeLabel;

  /// Label for slideshow delay option
  ///
  /// In en, this message translates to:
  /// **'Slideshow Delay'**
  String get slideshowDelayLabel;

  /// Label for playback speed option
  ///
  /// In en, this message translates to:
  /// **'Playback Speed'**
  String get playbackSpeedLabel;

  /// Label for subtitles toggle
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get subtitlesLabel;

  /// Sheet title for image settings
  ///
  /// In en, this message translates to:
  /// **'Image Settings'**
  String get imageSettingsTitle;

  /// Sheet title for playback/video settings
  ///
  /// In en, this message translates to:
  /// **'Playback Settings'**
  String get playbackSettingsTitle;

  /// Image fit mode: contain
  ///
  /// In en, this message translates to:
  /// **'Contain'**
  String get imageFitContain;

  /// Image fit mode: fit width
  ///
  /// In en, this message translates to:
  /// **'Fit Width'**
  String get imageFitWidth;

  /// Image fit mode: fit height
  ///
  /// In en, this message translates to:
  /// **'Fit Height'**
  String get imageFitHeight;

  /// Slideshow delay option label
  ///
  /// In en, this message translates to:
  /// **'{n} seconds'**
  String nSecondsDelay(int n);

  /// Playback speed label with Normal tag
  ///
  /// In en, this message translates to:
  /// **'{speed}x (Normal)'**
  String playbackSpeedNormal(String speed);

  /// Plain playback speed multiplier trailing badge (non-default speeds)
  ///
  /// In en, this message translates to:
  /// **'{speed}x'**
  String playbackSpeedValue(String speed);

  /// Compact trailing badge showing the current slideshow delay in seconds
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String slideshowDelaySecondsValue(int seconds);

  /// Trailing badge showing the current rotation in degrees
  ///
  /// In en, this message translates to:
  /// **'{degrees}°'**
  String rotationDegreesValue(int degrees);

  /// Tooltip for settings menu button
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTooltipShort;

  /// Tooltip for source code link on about screen
  ///
  /// In en, this message translates to:
  /// **'Source Code'**
  String get sourceCodeTooltip;

  /// Tooltip for donate link on about screen
  ///
  /// In en, this message translates to:
  /// **'Donate'**
  String get donateTooltip;

  /// Tooltip for share app button on about screen
  ///
  /// In en, this message translates to:
  /// **'Share App'**
  String get shareAppTooltip;

  /// Tooltip for reset to defaults button on toolbar settings
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get resetToDefaultsTooltip;

  /// AppBar title when unlocking a USB container
  ///
  /// In en, this message translates to:
  /// **'Unlock USB Container'**
  String get usbUnlockContainerTitle;

  /// AppBar title when mounting a new USB drive
  ///
  /// In en, this message translates to:
  /// **'Mount USB Drive'**
  String get usbMountContainerTitle;

  /// Label when slideshow auto-advance is off
  ///
  /// In en, this message translates to:
  /// **'Static'**
  String get staticLabel;

  /// Tooltip for unmute button
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmuteTooltip;

  /// Tooltip for mute button
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get muteTooltip;

  /// Tooltip for play once mode
  ///
  /// In en, this message translates to:
  /// **'Play Once (Auto-Advance Disabled)'**
  String get playOnceDisabledTooltip;

  /// Tooltip for play and advance mode
  ///
  /// In en, this message translates to:
  /// **'Play & Advance to Next'**
  String get playAndAdvanceTooltip;

  /// Tooltip for loop video mode
  ///
  /// In en, this message translates to:
  /// **'Loop Current Video'**
  String get loopCurrentVideoTooltip;

  /// Confirmation dialog title for clearing a vault's thumbnail cache
  ///
  /// In en, this message translates to:
  /// **'Clear Thumbnail Cache?'**
  String get clearThumbnailCacheDialogTitle;

  /// Confirmation dialog message for clearing a vault's thumbnail cache
  ///
  /// In en, this message translates to:
  /// **'This will delete cached thumbnails for this vault. They will be regenerated the next time you browse media.'**
  String get clearThumbnailCacheDialogMessage;

  /// Confirm button label for clearing thumbnail cache
  ///
  /// In en, this message translates to:
  /// **'Clear Cache'**
  String get clearCacheButton;

  /// Snackbar shown when app-level cache is cleared but the container is locked
  ///
  /// In en, this message translates to:
  /// **'App cache cleared. Unlock container to clear inside cache.'**
  String get appCacheClearedUnlockMessage;

  /// Snackbar shown when both app and in-container thumbnail caches are cleared
  ///
  /// In en, this message translates to:
  /// **'All thumbnail caches cleared successfully.'**
  String get allThumbnailCachesClearedMessage;

  /// Snackbar shown when app cache clears but the in-container cache fails to clear
  ///
  /// In en, this message translates to:
  /// **'App cache cleared, but failed to clear inside container.'**
  String get appCacheClearedContainerFailedMessage;

  /// Snackbar shown when clearing thumbnail caches fails entirely
  ///
  /// In en, this message translates to:
  /// **'Failed to clear thumbnail caches.'**
  String get failedToClearThumbnailCachesMessage;

  /// Biometric prompt reason shown when unlocking container settings for editing
  ///
  /// In en, this message translates to:
  /// **'Authenticate to modify settings'**
  String get authenticateToModifySettingsPrompt;

  /// AppBar title for the settings screen of a USB-backed vault
  ///
  /// In en, this message translates to:
  /// **'USB Vault Settings'**
  String get usbVaultSettingsTitle;

  /// AppBar title for the settings screen of a regular container vault
  ///
  /// In en, this message translates to:
  /// **'Vault Settings'**
  String get vaultSettingsTitle;

  /// Section header for general container settings
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get generalSectionHeader;

  /// Section header for security and credential settings
  ///
  /// In en, this message translates to:
  /// **'Security & Credentials'**
  String get securityCredentialsSectionHeader;

  /// Title shown when security settings are locked pending authentication
  ///
  /// In en, this message translates to:
  /// **'Security Options Locked'**
  String get securityOptionsLockedTitle;

  /// Explanation shown while security settings are locked
  ///
  /// In en, this message translates to:
  /// **'Authenticate with original container credentials to modify security settings.'**
  String get authenticateOriginalCredentialsMessage;

  /// Label for the option picker choosing the container's unlock method
  ///
  /// In en, this message translates to:
  /// **'Unlock Credentials'**
  String get unlockCredentialsLabel;

  /// Suffix appended to an unlock method label when it is currently unavailable, e.g. 'Biometric Unlock (Unavailable)'
  ///
  /// In en, this message translates to:
  /// **'(Unavailable)'**
  String get unavailableSuffixLabel;

  /// Warning shown when trying to save container settings without setting up a pattern
  ///
  /// In en, this message translates to:
  /// **'Set up a pattern before saving.'**
  String get patternSetupRequiredBeforeSaving;

  /// Helper text under the password field when updating saved container credentials
  ///
  /// In en, this message translates to:
  /// **'Password is encrypted using Android Keystore. Leave blank if using keyfiles only.'**
  String get passwordKeystoreEncryptedHelperText;

  /// Button label to change an already-configured unlock pattern
  ///
  /// In en, this message translates to:
  /// **'Change Pattern'**
  String get changePatternButton;

  /// Button label to configure an unlock pattern for the first time
  ///
  /// In en, this message translates to:
  /// **'Set Pattern'**
  String get setPatternButton;

  /// Switch title for caching the derived encryption key for this container
  ///
  /// In en, this message translates to:
  /// **'Cache Derived Key'**
  String get cacheDerivedKeyLabel;

  /// Subtitle for the cache-derived-key switch when the container is a CryFS vault
  ///
  /// In en, this message translates to:
  /// **'Skip CryFS\'s scrypt KDF next time (key kept in Android Keystore)'**
  String get cryfsSkipScryptKdfSubtitle;

  /// Subtitle for the cache-derived-key switch for non-CryFS containers
  ///
  /// In en, this message translates to:
  /// **'Reuse key material in Android Keystore'**
  String get reuseKeyMaterialKeystoreSubtitle;

  /// Subtitle explaining the advanced cipher/hash pinning option
  ///
  /// In en, this message translates to:
  /// **'Pin algorithm to skip auto-detection on unlock.'**
  String get pinAlgorithmSkipAutoDetectSubtitle;

  /// List tile title to change a container's password
  ///
  /// In en, this message translates to:
  /// **'Change Container Password'**
  String get changeContainerPasswordTitle;

  /// Warning shown when attempting to change the credentials of a BitLocker drive
  ///
  /// In en, this message translates to:
  /// **'BitLocker credentials cannot be changed in-app. Use \"Manage BitLocker\" on Windows.'**
  String get bitlockerCredentialsChangeNotSupportedMessage;

  /// Section header for system/OS integration settings
  ///
  /// In en, this message translates to:
  /// **'System & Integration'**
  String get systemIntegrationSectionHeader;

  /// Label for the per-container auto-lock duration option picker
  ///
  /// In en, this message translates to:
  /// **'Auto-Lock Duration'**
  String get autoLockDurationLabel;

  /// Option meaning the container will never auto-lock
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get neverAutoLockOption;

  /// Subtitle explaining the Android File Provider switch
  ///
  /// In en, this message translates to:
  /// **'Expose content to System File Picker when unlocked'**
  String get exposeContentToFilePickerSubtitle;

  /// Section header for per-container thumbnail cache settings
  ///
  /// In en, this message translates to:
  /// **'Thumbnail Storage'**
  String get thumbnailStorageSectionHeader;

  /// Label for the thumbnail cache mode option picker
  ///
  /// In en, this message translates to:
  /// **'Cache Mode'**
  String get cacheModeLabel;

  /// Subtitle shown when a container uses the app's global default thumbnail cache mode
  ///
  /// In en, this message translates to:
  /// **'Use global default'**
  String get useGlobalDefaultSubtitle;

  /// Label for the thumbnail quality tile
  ///
  /// In en, this message translates to:
  /// **'Thumbnail Quality'**
  String get thumbnailQualityLabel;

  /// List tile title for the clear-thumbnail-cache action
  ///
  /// In en, this message translates to:
  /// **'Clear Thumbnail Cache'**
  String get clearThumbnailCacheTitle;

  /// Subtitle for the clear-thumbnail-cache list tile
  ///
  /// In en, this message translates to:
  /// **'Remove cached image and video thumbnails'**
  String get removeCachedThumbnailsSubtitle;

  /// Section header in Vault Settings for the new read-only vault-info section
  ///
  /// In en, this message translates to:
  /// **'Vault Information'**
  String get vaultInformationSectionHeader;

  /// List tile title that opens the Vault Information screen
  ///
  /// In en, this message translates to:
  /// **'View Vault Details'**
  String get vaultInformationTileTitle;

  /// List tile subtitle under vaultInformationTileTitle
  ///
  /// In en, this message translates to:
  /// **'Cipher, format, and other technical details'**
  String get vaultInformationTileSubtitle;

  /// Row label on the Vault Information screen for the vault's file/folder location (its URI, decoded for readability)
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get vaultInfoLocationLabel;

  /// Empty-state title on the Vault Information screen when the vault isn't currently unlocked
  ///
  /// In en, this message translates to:
  /// **'Unlock Required'**
  String get vaultInfoRequiresUnlockTitle;

  /// Empty-state message on the Vault Information screen when the vault isn't currently unlocked
  ///
  /// In en, this message translates to:
  /// **'Unlock this vault to view its technical details.'**
  String get vaultInfoRequiresUnlockMessage;

  /// Empty-state title on the Vault Information screen when fetching details failed unexpectedly
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t Load Vault Information'**
  String get vaultInfoLoadFailedTitle;

  /// Empty-state message on the Vault Information screen when fetching details failed unexpectedly
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while reading this vault\'s details.'**
  String get vaultInfoLoadFailedMessage;

  /// Row label on the Vault Information screen for the container's total size
  ///
  /// In en, this message translates to:
  /// **'Volume Size'**
  String get vaultInfoVolumeSizeLabel;

  /// Row label on the Vault Information screen (VeraCrypt/LUKS/BitLocker) for the container's inner filesystem, e.g. FAT32, exFAT, NTFS, ext4
  ///
  /// In en, this message translates to:
  /// **'File System'**
  String get vaultInfoFileSystemLabel;

  /// Row label on the Vault Information screen (VeraCrypt) for whether a hidden volume is present
  ///
  /// In en, this message translates to:
  /// **'Hidden Volume'**
  String get vaultInfoHiddenVolumeLabel;

  /// Row label on the Vault Information screen for whether the current session is read-only
  ///
  /// In en, this message translates to:
  /// **'Read-Only'**
  String get vaultInfoReadOnlyLabel;

  /// Row label on the Vault Information screen (LUKS) for the on-disk header version
  ///
  /// In en, this message translates to:
  /// **'LUKS Version'**
  String get vaultInfoLuksVersionLabel;

  /// Row label on the Vault Information screen (LUKS) for the volume's sector size
  ///
  /// In en, this message translates to:
  /// **'Sector Size'**
  String get vaultInfoSectorSizeLabel;

  /// Row label on the Vault Information screen (Cryptomator) for the vault.cryptomator format number
  ///
  /// In en, this message translates to:
  /// **'Vault Format'**
  String get vaultInfoVaultFormatLabel;

  /// Row label on the Vault Information screen (Cryptomator) for the content/filename cipher combo
  ///
  /// In en, this message translates to:
  /// **'Cipher Combination'**
  String get vaultInfoCipherComboLabel;

  /// Row label on the Vault Information screen (Cryptomator) for the shortening threshold
  ///
  /// In en, this message translates to:
  /// **'Filename Shortening Threshold'**
  String get vaultInfoShorteningThresholdLabel;

  /// Row label on the Vault Information screen (gocryptfs/CryFS) for the on-disk config format version
  ///
  /// In en, this message translates to:
  /// **'Format Version'**
  String get vaultInfoFormatVersionLabel;

  /// Row label on the Vault Information screen (gocryptfs) for the file-content cipher
  ///
  /// In en, this message translates to:
  /// **'Content Cipher'**
  String get vaultInfoContentCipherLabel;

  /// Row label on the Vault Information screen (gocryptfs) for whether filenames are encrypted
  ///
  /// In en, this message translates to:
  /// **'Filenames'**
  String get vaultInfoFilenameEncryptionLabel;

  /// Value shown next to vaultInfoFilenameEncryptionLabel when filenames aren't encrypted
  ///
  /// In en, this message translates to:
  /// **'Plaintext'**
  String get vaultInfoPlaintextNamesValue;

  /// Value shown next to vaultInfoFilenameEncryptionLabel when filenames are encrypted
  ///
  /// In en, this message translates to:
  /// **'Encrypted'**
  String get vaultInfoEncryptedNamesValue;

  /// Row label on the Vault Information screen (CryFS) for the block cipher
  ///
  /// In en, this message translates to:
  /// **'Block Cipher'**
  String get vaultInfoBlockCipherLabel;

  /// Row label on the Vault Information screen (CryFS) for the block size
  ///
  /// In en, this message translates to:
  /// **'Block Size'**
  String get vaultInfoBlockSizeLabel;

  /// Row label on the Vault Information screen (CryFS) for the CryFS version that created the vault
  ///
  /// In en, this message translates to:
  /// **'Created With'**
  String get vaultInfoCreatedWithVersionLabel;

  /// Row label on the Vault Information screen (CryFS) for the CryFS version that last opened the vault
  ///
  /// In en, this message translates to:
  /// **'Last Opened With'**
  String get vaultInfoLastOpenedWithVersionLabel;

  /// Generic boolean value shown on the Vault Information screen
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get vaultInfoYesValue;

  /// Generic boolean value shown on the Vault Information screen
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get vaultInfoNoValue;

  /// Explanatory note on the Vault Information screen (BitLocker) about limited field availability
  ///
  /// In en, this message translates to:
  /// **'This app doesn\'t parse BitLocker\'s own header metadata, so cipher and version details aren\'t available here.'**
  String get vaultInfoBitlockerNote;

  /// Inline validation error shown near the save button when a pattern hasn't been set up
  ///
  /// In en, this message translates to:
  /// **'Set up a pattern above before saving.'**
  String get patternSetupRequiredAboveBeforeSaving;

  /// Inline validation error shown near the save button when neither a password nor cached derived key with keyfiles is provided
  ///
  /// In en, this message translates to:
  /// **'A password or \"Cache Derived Key\" with keyfiles is required for this unlock method.'**
  String get passwordOrCacheDerivedKeyRequiredMessage;

  /// Primary button label to save container configuration changes
  ///
  /// In en, this message translates to:
  /// **'Save Configuration'**
  String get saveConfigurationButton;

  /// Error shown when a pattern verification attempt fails
  ///
  /// In en, this message translates to:
  /// **'Incorrect pattern'**
  String get incorrectPatternError;

  /// Title for the pattern verification bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Verify Pattern'**
  String get verifyPatternTitle;

  /// Error shown when a folder-vault password verification attempt fails
  ///
  /// In en, this message translates to:
  /// **'Incorrect password'**
  String get incorrectPasswordError;

  /// Generic error shown when credential verification fails unexpectedly
  ///
  /// In en, this message translates to:
  /// **'Verification failed'**
  String get verificationFailedError;

  /// Error shown when a container password/keyfile verification attempt fails
  ///
  /// In en, this message translates to:
  /// **'Incorrect credentials'**
  String get incorrectCredentialsError;

  /// Label for the password field when keyfiles alone may be sufficient
  ///
  /// In en, this message translates to:
  /// **'Container password (optional for keyfile-only)'**
  String get containerPasswordOptionalLabel;

  /// Label for the optional VeraCrypt PIM field
  ///
  /// In en, this message translates to:
  /// **'PIM (optional)'**
  String get pimOptionalLabel;

  /// Subtitle shown on a dashboard card for a locked USB drive
  ///
  /// In en, this message translates to:
  /// **'USB Drive · Locked'**
  String get usbDriveLockedLabel;

  /// Subtitle shown on a dashboard card for a locked container
  ///
  /// In en, this message translates to:
  /// **'Locked container'**
  String get lockedContainerLabel;

  /// Message shown when trying to lock a container while another operation is running
  ///
  /// In en, this message translates to:
  /// **'An operation is in progress. Please wait before locking.'**
  String get operationInProgressWaitMessage;

  /// Tooltip for reconnecting a saved but disconnected USB drive
  ///
  /// In en, this message translates to:
  /// **'Reconnect USB'**
  String get reconnectUsbTooltip;

  /// Tooltip for unlocking a container from the dashboard
  ///
  /// In en, this message translates to:
  /// **'Unlock container'**
  String get unlockContainerTooltip;

  /// Snackbar shown when locking a container throws an unexpected error
  ///
  /// In en, this message translates to:
  /// **'Lock failed: {errorType}'**
  String lockFailedMessage(String errorType);

  /// Validation error when changing a container password without a new password or keyfiles
  ///
  /// In en, this message translates to:
  /// **'New password or keyfiles are required.'**
  String get newPasswordOrKeyfilesRequired;

  /// Validation error when the new password and confirmation don't match
  ///
  /// In en, this message translates to:
  /// **'New passwords do not match.'**
  String get newPasswordsDoNotMatch;

  /// Snackbar shown after a container password change succeeds
  ///
  /// In en, this message translates to:
  /// **'Password changed successfully.'**
  String get passwordChangedSuccessfullyMessage;

  /// Error shown when a container password change fails
  ///
  /// In en, this message translates to:
  /// **'Failed to change password. Check old credentials.'**
  String get failedToChangePasswordMessage;

  /// Section header for the current/old credentials on the change password screen
  ///
  /// In en, this message translates to:
  /// **'Current Credentials'**
  String get currentCredentialsSectionHeader;

  /// Label for the old/current password field
  ///
  /// In en, this message translates to:
  /// **'Old Password'**
  String get oldPasswordLabel;

  /// Label for the old/current VeraCrypt PIM field
  ///
  /// In en, this message translates to:
  /// **'Old PIM (Optional)'**
  String get oldPimOptionalLabel;

  /// Section header for the new credentials on the change password screen
  ///
  /// In en, this message translates to:
  /// **'New Credentials'**
  String get newCredentialsSectionHeader;

  /// Label for the new VeraCrypt PIM field
  ///
  /// In en, this message translates to:
  /// **'New PIM (Optional)'**
  String get newPimOptionalLabel;

  /// Title for the dashboard's empty state when no vaults exist
  ///
  /// In en, this message translates to:
  /// **'No containers yet'**
  String get noContainersYetTitle;

  /// Message for the dashboard's empty state when no vaults exist
  ///
  /// In en, this message translates to:
  /// **'Mount a VeraCrypt container, connect a USB drive, or create a brand-new encrypted vault to get started.'**
  String get dashboardEmptyStateMessage;

  /// Sort menu option: sort by file/folder name
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortFieldName;

  /// Sort menu option: sort by file size
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sortFieldSize;

  /// Sort menu option: sort by file type/extension
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get sortFieldType;

  /// Sort menu option: sort by modification date
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get sortFieldDate;

  /// Layout mode option: detailed list view
  ///
  /// In en, this message translates to:
  /// **'Detailed List'**
  String get layoutModeDetailedList;

  /// Layout mode option: compact list view
  ///
  /// In en, this message translates to:
  /// **'Compact List'**
  String get layoutModeCompactList;

  /// Layout mode option: gallery grid view
  ///
  /// In en, this message translates to:
  /// **'Gallery Grid'**
  String get layoutModeGalleryGrid;

  /// Tooltip for the delete action when the container is read-only
  ///
  /// In en, this message translates to:
  /// **'Read-only — can\'t delete'**
  String get readOnlyCantDeleteTooltip;

  /// Tooltip for the move action when the container is read-only
  ///
  /// In en, this message translates to:
  /// **'Read-only — can\'t move'**
  String get readOnlyCantMoveTooltip;

  /// Tooltip for the rename action when the container is read-only
  ///
  /// In en, this message translates to:
  /// **'Read-only — can\'t rename'**
  String get readOnlyCantRenameTooltip;

  /// Selected-items size label while a folder size total is still being calculated, showing a running partial total
  ///
  /// In en, this message translates to:
  /// **'{bytes} (calculating…)'**
  String sizeCalculatingWithBytesLabel(String bytes);

  /// Selected-items size label while a folder size total is still being calculated and no partial total is available yet
  ///
  /// In en, this message translates to:
  /// **'calculating…'**
  String get sizeCalculatingLabel;

  /// Status message shown when trying to rename a vault item directly instead of editing it
  ///
  /// In en, this message translates to:
  /// **'Edit secure items to rename them'**
  String get editSecureItemsToRenameMessage;

  /// Status message shown when trying to open a vault item with an external app
  ///
  /// In en, this message translates to:
  /// **'Vault items cannot be opened in external apps'**
  String get vaultItemsCannotBeOpenedExternallyMessage;

  /// Tooltip/badge shown next to the container name when it's mounted read-only
  ///
  /// In en, this message translates to:
  /// **'Mounted read-only'**
  String get mountedReadOnlyTooltip;

  /// Short abbreviation shown inside the read-only badge next to the container name (paired with mountedReadOnlyTooltip)
  ///
  /// In en, this message translates to:
  /// **'RO'**
  String get readOnlyBadgeAbbreviation;

  /// Label showing free storage space remaining
  ///
  /// In en, this message translates to:
  /// **'{bytes} free'**
  String freeSpaceLabel(String bytes);

  /// Label indicating the current file list is filtered
  ///
  /// In en, this message translates to:
  /// **'filtered'**
  String get filteredLabel;

  /// Section header label above the storage stats in the vertical (landscape sidebar) stats bar layout
  ///
  /// In en, this message translates to:
  /// **'STORAGE'**
  String get statsStorageSectionHeader;

  /// Count of folders shown in the stats bar
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 folder} other{{count} folders}}'**
  String statsFolderCount(num count);

  /// Count of files shown in the stats bar
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String statsFileCount(num count);

  /// Browser file-type filter menu option: show all files
  ///
  /// In en, this message translates to:
  /// **'All Files'**
  String get filterAllFilesOption;

  /// Browser file-type filter menu option: images only
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get filterImagesOption;

  /// Browser file-type filter menu option: videos only
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get filterVideosOption;

  /// Browser file-type filter menu option: audio only
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get filterAudioOption;

  /// Browser file-type filter menu option: documents only
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get filterDocumentsOption;

  /// Explanation body text in the folder document provider sheet
  ///
  /// In en, this message translates to:
  /// **'This folder is exposed as its own storage location, so other apps can browse and open its files directly.'**
  String get folderExposedAsStorageExplanation;

  /// Header title in the conflict resolution sheet showing how many items collided
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item already exists} other{{count} items already exist}}'**
  String conflictItemsAlreadyExistTitle(num count);

  /// Subtitle in the conflict resolution sheet
  ///
  /// In en, this message translates to:
  /// **'Choose what happens to each item, or apply one choice to all.'**
  String get conflictResolutionSubtitle;

  /// Apply-to-all chip: skip every conflicting item
  ///
  /// In en, this message translates to:
  /// **'Skip all'**
  String get skipAllChipLabel;

  /// Apply-to-all chip: overwrite every conflicting item
  ///
  /// In en, this message translates to:
  /// **'Overwrite all'**
  String get overwriteAllChipLabel;

  /// Per-item conflict resolution dropdown option: overwrite a file
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get overwriteItemDropdownLabel;

  /// Per-item conflict resolution dropdown option: overwrite a folder
  ///
  /// In en, this message translates to:
  /// **'Overwrite folder'**
  String get overwriteFolderDropdownLabel;

  /// File operations sheet header title while at least one transfer is active
  ///
  /// In en, this message translates to:
  /// **'Transfers in progress'**
  String get fileOpsTransfersInProgressTitle;

  /// File operations sheet header title when no transfer is currently active
  ///
  /// In en, this message translates to:
  /// **'Recent transfers'**
  String get fileOpsRecentTransfersTitle;

  /// Empty state message in the file operations sheet
  ///
  /// In en, this message translates to:
  /// **'No recent transfers'**
  String get fileOpsNoRecentTransfersMessage;

  /// Empty state subtitle/body in the file operations sheet, shown under fileOpsNoRecentTransfersMessage
  ///
  /// In en, this message translates to:
  /// **'Copies, moves, and deletes will show up here while they run.'**
  String get fileOpsNoRecentTransfersSubtitle;

  /// Collapsed summary label for the expandable per-item detail list in a file operation row, shown when every item succeeded. Kept generic (no count) because the row's title above it already states how many items were affected.
  ///
  /// In en, this message translates to:
  /// **'Show details'**
  String fileOpsShowDetailsLabel(num count);

  /// Tooltip for the cancel button on an active file operation row
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get fileOpsCancelTooltip;

  /// Tooltip for the button that removes a single finished operation from the file operations history
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get fileOpsDismissTooltip;

  /// Destination label for a file operation targeting the root directory
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get fileOpsRootDestinationLabel;

  /// Status label for a cancelled file operation
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get fileOpsCancelledStatusLabel;

  /// Label introducing the list of failed items in a batch file operation
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item failed:} other{{count} items failed:}}'**
  String fileOpsItemsFailedLabel(num count);

  /// Label indicating additional items beyond the displayed limit in a batch file operation
  ///
  /// In en, this message translates to:
  /// **'+ {count} more'**
  String fileOpsMoreItemsLabel(num count);

  /// Tooltip for the top app bar transfer activity button
  ///
  /// In en, this message translates to:
  /// **'Transfers'**
  String get transferActivityTooltip;

  /// Label showing file transfer speed
  ///
  /// In en, this message translates to:
  /// **'{speed}/s'**
  String fileOpsSpeedLabel(String speed);

  /// Label showing estimated time remaining for a file operation
  ///
  /// In en, this message translates to:
  /// **'~{time} remaining'**
  String fileOpsEtaLabel(String time);

  /// Error message shown when reading a text file inside the archive viewer fails
  ///
  /// In en, this message translates to:
  /// **'Error reading file: {error}'**
  String archiveErrorReadingFile(String error);

  /// Fallback message in the archive file viewer when no preview can be shown
  ///
  /// In en, this message translates to:
  /// **'Preview not available for this file type.'**
  String get archivePreviewNotAvailableMessage;

  /// Fallback error message when an AVIF image fails to decode/render
  ///
  /// In en, this message translates to:
  /// **'Failed to render AVIF'**
  String get avifFailedToRenderMessage;

  /// Error message when decrypting/loading an image fails with no further detail
  ///
  /// In en, this message translates to:
  /// **'Failed to load encrypted image'**
  String get encryptedImageLoadFailedMessage;

  /// Error message when decrypting/loading an image fails with an underlying error
  ///
  /// In en, this message translates to:
  /// **'Failed to load encrypted image: {error}'**
  String encryptedImageLoadFailedWithReasonMessage(String error);

  /// Error message shown when an image fails to decode/render
  ///
  /// In en, this message translates to:
  /// **'Invalid or corrupted image format.'**
  String get invalidOrCorruptedImageMessage;

  /// Current position within the media viewer playlist
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String mediaViewerPlaylistPositionLabel(num current, num total);

  /// Current position within the media viewer playlist while subfolders are still being scanned
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}  ·  scanning…'**
  String mediaViewerPlaylistPositionScanningLabel(num current, num total);

  /// Subtitle shown in the media viewer top bar while subfolders are being scanned and no playlist is active yet
  ///
  /// In en, this message translates to:
  /// **'Scanning…'**
  String get mediaViewerScanningLabel;

  /// Snackbar message after successfully deleting the currently viewed file in the media viewer
  ///
  /// In en, this message translates to:
  /// **'File deleted successfully'**
  String get mediaFileDeletedMessage;

  /// Snackbar message when deleting the currently viewed file in the media viewer fails
  ///
  /// In en, this message translates to:
  /// **'Failed to delete file'**
  String get mediaFileDeleteFailedMessage;

  /// Snackbar message after successfully renaming the currently viewed file in the media viewer
  ///
  /// In en, this message translates to:
  /// **'File renamed successfully'**
  String get mediaFileRenamedMessage;

  /// AppBar title for the About screen
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutScreenTitle;

  /// Snackbar error shown when an external link fails to open from the About screen
  ///
  /// In en, this message translates to:
  /// **'Could not open link'**
  String get couldNotOpenLinkMessage;

  /// AppBar title for the file manager toolbar settings screen
  ///
  /// In en, this message translates to:
  /// **'File Manager Settings'**
  String get fileManagerSettingsTitle;

  /// Toggle label for showing media thumbnails in list view
  ///
  /// In en, this message translates to:
  /// **'Show Media Thumbnails'**
  String get showMediaThumbnailsLabel;

  /// Toggle description for showing media thumbnails in list view
  ///
  /// In en, this message translates to:
  /// **'Display thumbnail previews for images and videos in list view'**
  String get showMediaThumbnailsDesc;

  /// Toggle label for showing file names in grid view
  ///
  /// In en, this message translates to:
  /// **'Show File Names'**
  String get showFileNamesLabel;

  /// Toggle description for showing file names in grid view
  ///
  /// In en, this message translates to:
  /// **'Display text labels under items in grid layout'**
  String get showFileNamesDesc;

  /// Toggle label for showing the breadcrumb navigation bar
  ///
  /// In en, this message translates to:
  /// **'Show Breadcrumb Bar'**
  String get showBreadcrumbBarLabel;

  /// Toggle description for showing the breadcrumb navigation bar
  ///
  /// In en, this message translates to:
  /// **'Path navigation bar at top of browser'**
  String get showBreadcrumbBarDesc;

  /// Toggle label for showing the file stats bar
  ///
  /// In en, this message translates to:
  /// **'Show Stats Bar'**
  String get showStatsBarLabel;

  /// Toggle description for showing the file stats bar
  ///
  /// In en, this message translates to:
  /// **'File count and free space info banner'**
  String get showStatsBarDesc;

  /// Toggle label for automatically starting playlist mode
  ///
  /// In en, this message translates to:
  /// **'Auto-start Playlist Mode'**
  String get autoStartPlaylistModeLabel;

  /// Toggle description for automatically starting playlist mode
  ///
  /// In en, this message translates to:
  /// **'Automatically start in playlist mode when opening a media item'**
  String get autoStartPlaylistModeDesc;

  /// Toggle label for showing the playlist thumbnail carousel
  ///
  /// In en, this message translates to:
  /// **'Show Playlist Carousel'**
  String get showPlaylistCarouselLabel;

  /// Toggle description for showing the playlist thumbnail carousel
  ///
  /// In en, this message translates to:
  /// **'Show thumbnail carousel button when viewing media playlists'**
  String get showPlaylistCarouselDesc;

  /// Accessibility label for the video playback position slider
  ///
  /// In en, this message translates to:
  /// **'Video playback position slider'**
  String get videoPlaybackSliderLabel;

  /// Accessibility hint on the advanced settings button explaining the long-press action
  ///
  /// In en, this message translates to:
  /// **'Long press for playback diagnostics'**
  String get longPressPlaybackDiagnosticsHint;

  /// Accessibility label shown for an image in the playlist when slideshow auto-advance is off
  ///
  /// In en, this message translates to:
  /// **'Static image mode'**
  String get staticImageModeLabel;

  /// Accessibility label shown for an image in the playlist when slideshow auto-advance is on
  ///
  /// In en, this message translates to:
  /// **'Slideshow mode active with {seconds} seconds delay'**
  String slideshowModeActiveLabel(int seconds);

  /// Accessibility label describing the current video playback mode button
  ///
  /// In en, this message translates to:
  /// **'Video playback mode: {mode}'**
  String videoPlaybackModeLabel(String mode);

  /// Accessibility label for the pause playback button in the media viewer
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseLabel;

  /// Accessibility label for the play playback button in the media viewer
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playLabel;

  /// Empty state title shown when the current folder has no items
  ///
  /// In en, this message translates to:
  /// **'Empty Folder'**
  String get emptyFolderTitle;

  /// Empty state message shown when the current folder has no items
  ///
  /// In en, this message translates to:
  /// **'Use the Add action to create files or import from device.'**
  String get emptyFolderMessage;

  /// Empty state title shown when a search finds no matches
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get noResultsTitle;

  /// Empty state message shown when a search finds no matches
  ///
  /// In en, this message translates to:
  /// **'Nothing in this folder matches \"{query}\".'**
  String noResultsForQueryMessage(String query);

  /// Tooltip for the button that closes the playlist thumbnail carousel overlay
  ///
  /// In en, this message translates to:
  /// **'Close Carousel'**
  String get closeCarouselTooltip;

  /// Submenu title for playlist scroll mode options in media viewer
  ///
  /// In en, this message translates to:
  /// **'Playlist Scroll Mode'**
  String get playlistScrollModeMenu;

  /// Playlist scroll mode: horizontal pagination
  ///
  /// In en, this message translates to:
  /// **'Horizontal'**
  String get playlistScrollHorizontalLabel;

  /// Playlist scroll mode: vertical pagination
  ///
  /// In en, this message translates to:
  /// **'Vertical Paged'**
  String get playlistScrollVerticalPageLabel;

  /// Playlist scroll mode: continuous vertical scrolling
  ///
  /// In en, this message translates to:
  /// **'Vertical Continuous'**
  String get playlistScrollVerticalContinuousLabel;

  /// Tooltip for the undo button in the text editor
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undoTooltip;

  /// Tooltip for the redo button in the text editor
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redoTooltip;

  /// Status label shown while the text editor is autosaving
  ///
  /// In en, this message translates to:
  /// **'Autosaving…'**
  String get autosavingLabel;

  /// Status label shown while the text editor is saving
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get savingLabel;

  /// Status label showing the time of the last autosave in the text editor
  ///
  /// In en, this message translates to:
  /// **'Autosaved at {time}'**
  String autosavedAtLabel(String time);

  /// Error message shown when the camera device drops out unexpectedly
  ///
  /// In en, this message translates to:
  /// **'Camera disconnected: {message}'**
  String cameraDisconnectedError(String message);

  /// Generic fallback text used when no specific error detail is available
  ///
  /// In en, this message translates to:
  /// **'unknown error'**
  String get unknownErrorFallback;

  /// Error message shown when camera/microphone permissions are denied
  ///
  /// In en, this message translates to:
  /// **'Camera and microphone permissions are required to use the camera.'**
  String get cameraPermissionsRequiredMessage;

  /// Generic camera initialization error message
  ///
  /// In en, this message translates to:
  /// **'Camera error: {error}'**
  String cameraErrorMessage(String error);

  /// Error toast when taking a photo fails with no further detail
  ///
  /// In en, this message translates to:
  /// **'Photo capture failed'**
  String get cameraPhotoCaptureFailedMessage;

  /// Error toast when starting a video recording fails with no further detail
  ///
  /// In en, this message translates to:
  /// **'Recording failed'**
  String get cameraRecordingFailedMessage;

  /// Error toast when starting a video recording throws an exception
  ///
  /// In en, this message translates to:
  /// **'Recording failed: {error}'**
  String cameraRecordingFailedWithReasonMessage(String error);

  /// Error toast when a video recording is discarded for being too short
  ///
  /// In en, this message translates to:
  /// **'Recording was too short to save'**
  String get cameraRecordingTooShortMessage;

  /// Error toast when saving a finished video recording fails with no further detail
  ///
  /// In en, this message translates to:
  /// **'Could not save recording'**
  String get cameraCouldNotSaveRecordingMessage;

  /// Error toast when saving a finished video recording throws an exception
  ///
  /// In en, this message translates to:
  /// **'Could not save recording: {error}'**
  String cameraCouldNotSaveRecordingWithReasonMessage(String error);

  /// Error toast when switching to a different camera lens fails
  ///
  /// In en, this message translates to:
  /// **'Could not switch lens'**
  String get cameraCouldNotSwitchLensMessage;

  /// Busy overlay label shown while a captured photo is being encrypted into the vault
  ///
  /// In en, this message translates to:
  /// **'Encrypting photo…'**
  String get cameraEncryptingPhotoLabel;

  /// Busy overlay label shown while a recorded video is being encrypted into the vault
  ///
  /// In en, this message translates to:
  /// **'Encrypting video…'**
  String get cameraEncryptingVideoLabel;

  /// Section header on the about screen for the application info section
  ///
  /// In en, this message translates to:
  /// **'Application'**
  String get aboutApplicationSectionHeader;

  /// Tagline shown under the app name on the about screen
  ///
  /// In en, this message translates to:
  /// **'Free · Open Source · Offline Encrypted Vault'**
  String get aboutTagline;

  /// List tile title on the about screen for the app version entry
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get aboutVersionTitle;

  /// List tile subtitle on the about screen showing the app version
  ///
  /// In en, this message translates to:
  /// **'v{version} · Tap to copy version info for bug reports'**
  String aboutVersionSubtitle(String version);

  /// List tile title on the about screen linking to release notes
  ///
  /// In en, this message translates to:
  /// **'What\'s New'**
  String get aboutWhatsNewTitle;

  /// List tile subtitle on the about screen for the release notes entry
  ///
  /// In en, this message translates to:
  /// **'See recent changes and release notes'**
  String get aboutWhatsNewSubtitle;

  /// List tile title on the about screen opening the privacy details sheet
  ///
  /// In en, this message translates to:
  /// **'Privacy & Security'**
  String get aboutPrivacySecurityTitle;

  /// List tile subtitle on the about screen for the privacy & security entry
  ///
  /// In en, this message translates to:
  /// **'No network access, nothing unencrypted ever written to disk'**
  String get aboutPrivacySecuritySubtitle;

  /// Section header on the about screen listing supported container formats
  ///
  /// In en, this message translates to:
  /// **'Supported Formats'**
  String get aboutSupportedFormatsSectionHeader;

  /// List tile title on the about screen for the VeraCrypt/LUKS format entry
  ///
  /// In en, this message translates to:
  /// **'VeraCrypt & LUKS1/2'**
  String get aboutVeraCryptLuksTitle;

  /// List tile subtitle on the about screen describing VeraCrypt/LUKS capabilities
  ///
  /// In en, this message translates to:
  /// **'Standard & hidden volumes, custom PIM, keyfiles, xts-plain64, Argon2id/i'**
  String get aboutVeraCryptLuksSubtitle;

  /// List tile title on the about screen for the BitLocker format entry
  ///
  /// In en, this message translates to:
  /// **'BitLocker & BitLocker To Go'**
  String get aboutBitLockerTitle;

  /// List tile subtitle on the about screen describing BitLocker capabilities
  ///
  /// In en, this message translates to:
  /// **'User passphrases and 48-digit numerical recovery key support'**
  String get aboutBitLockerSubtitle;

  /// List tile title on the about screen for the directory vault formats entry
  ///
  /// In en, this message translates to:
  /// **'Directory Vaults'**
  String get aboutDirectoryVaultsTitle;

  /// List tile subtitle on the about screen describing directory vault format support
  ///
  /// In en, this message translates to:
  /// **'Cryptomator (v7/v8 SIV_GCM & SIV_CTRMAC), gocryptfs (v2 AES-GCM & XChaCha20), CryFS (v0.10+ XChaCha20 & AES)'**
  String get aboutDirectoryVaultsSubtitle;

  /// List tile title on the about screen for the VHD/VHDX format entry
  ///
  /// In en, this message translates to:
  /// **'Virtual Hard Disks (VHD / VHDX)'**
  String get aboutVhdTitle;

  /// List tile subtitle on the about screen describing VHD/VHDX format support
  ///
  /// In en, this message translates to:
  /// **'BAT translation for fixed and dynamic expandable disk images'**
  String get aboutVhdSubtitle;

  /// Section header on the about screen for the native engine details
  ///
  /// In en, this message translates to:
  /// **'Native Core Engine'**
  String get aboutNativeCoreEngineSectionHeader;

  /// Title above the list of compiled native libraries on the about screen
  ///
  /// In en, this message translates to:
  /// **'Compiled C++ Libraries'**
  String get aboutCompiledLibrariesTitle;

  /// Bulleted list of compiled native libraries and versions used by the app
  ///
  /// In en, this message translates to:
  /// **'• mbedTLS v3.6.0 (ARMv8 Hardware Crypto & SHA-2)\n• libavif & libgav1 (Native AVIF Image Decoder)\n• ChaN FatFs v4.0.4 (FAT12/16/32 & exFAT)\n• Tuxera NTFS-3G & embedded mkntfs\n• e2fsprogs v1.47.4 libext2fs (ext2/ext3/ext4)\n• Dislocker Virtual I/O (BitLocker FVE / To Go)\n• VeraCrypt 1.26.29 (Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id/i)\n• cJSON v1.7.18 (LUKS2 & Cryptomator metadata)'**
  String get aboutCompiledLibrariesBody;

  /// Section header on the about screen for community/legal links
  ///
  /// In en, this message translates to:
  /// **'Community & Open Source'**
  String get aboutCommunitySectionHeader;

  /// List tile title on the about screen linking to the GitHub issue tracker
  ///
  /// In en, this message translates to:
  /// **'Report an Issue'**
  String get aboutReportIssueTitle;

  /// List tile subtitle on the about screen for the report-an-issue entry
  ///
  /// In en, this message translates to:
  /// **'Found a bug? Submit an issue on GitHub'**
  String get aboutReportIssueSubtitle;

  /// Title of the bottom sheet shown when tapping Report an Issue on the about screen
  ///
  /// In en, this message translates to:
  /// **'Report an Issue'**
  String get reportIssueSheetTitle;

  /// Subtitle of the report-an-issue bottom sheet
  ///
  /// In en, this message translates to:
  /// **'Pick the option that best matches your issue — it opens a pre-filled GitHub form'**
  String get reportIssueSheetSubtitle;

  /// Option in the report-an-issue sheet for a general app bug
  ///
  /// In en, this message translates to:
  /// **'Bug Report'**
  String get reportIssueBugTitle;

  /// Subtitle for the bug report option in the report-an-issue sheet
  ///
  /// In en, this message translates to:
  /// **'Something crashed or isn\'t working right'**
  String get reportIssueBugSubtitle;

  /// Option in the report-an-issue sheet for a container/vault-specific problem
  ///
  /// In en, this message translates to:
  /// **'Container / Vault Problem'**
  String get reportIssueContainerTitle;

  /// Subtitle for the container/vault problem option in the report-an-issue sheet
  ///
  /// In en, this message translates to:
  /// **'Unlock, mount, or format-specific issue'**
  String get reportIssueContainerSubtitle;

  /// Option in the report-an-issue sheet for suggesting a feature
  ///
  /// In en, this message translates to:
  /// **'Feature Request'**
  String get reportIssueFeatureTitle;

  /// Subtitle for the feature request option in the report-an-issue sheet
  ///
  /// In en, this message translates to:
  /// **'Suggest an idea or improvement'**
  String get reportIssueFeatureSubtitle;

  /// Option in the report-an-issue sheet linking to the full GitHub issue template chooser
  ///
  /// In en, this message translates to:
  /// **'Something Else'**
  String get reportIssueOtherTitle;

  /// Subtitle for the 'something else' option in the report-an-issue sheet
  ///
  /// In en, this message translates to:
  /// **'Browse all templates on GitHub'**
  String get reportIssueOtherSubtitle;

  /// List tile title on the about screen linking to the contributors list
  ///
  /// In en, this message translates to:
  /// **'Contributors'**
  String get aboutContributorsTitle;

  /// List tile subtitle on the about screen for the contributors entry
  ///
  /// In en, this message translates to:
  /// **'People who helped build VaultExplorer'**
  String get aboutContributorsSubtitle;

  /// List tile title on the about screen opening the OSS license page
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get aboutLicensesTitle;

  /// List tile subtitle on the about screen for the licenses entry
  ///
  /// In en, this message translates to:
  /// **'Third-party libraries used in this app'**
  String get aboutLicensesSubtitle;

  /// Footer text at the bottom of the about screen
  ///
  /// In en, this message translates to:
  /// **'Made with ❤ for privacy.'**
  String get aboutFooterMadeWithLove;

  /// Snackbar message shown after copying version info to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Version info copied — handy for bug reports'**
  String get aboutVersionCopiedMessage;

  /// Text copied to the clipboard when the user taps the version entry
  ///
  /// In en, this message translates to:
  /// **'VaultExplorer v{version} (Android)'**
  String aboutVersionClipboardText(String version);

  /// Shareable promotional text copied to the clipboard when the user taps share
  ///
  /// In en, this message translates to:
  /// **'VaultExplorer — a free, open-source, offline vault for Android.\n\nStore passwords, notes, and files inside an encrypted container (VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs, CryFS).\n\n{url}'**
  String aboutShareText(String url);

  /// Snackbar message shown after copying the shareable app link to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied a shareable link to your clipboard'**
  String get aboutShareLinkCopiedMessage;

  /// Title of the privacy details bottom sheet on the about screen
  ///
  /// In en, this message translates to:
  /// **'Privacy & Data Security'**
  String get aboutPrivacySheetTitle;

  /// Subtitle of the privacy details bottom sheet on the about screen
  ///
  /// In en, this message translates to:
  /// **'100% offline, local memory security design'**
  String get aboutPrivacySheetSubtitle;

  /// Privacy sheet point title: no network access
  ///
  /// In en, this message translates to:
  /// **'No network access required'**
  String get privacyPointNoNetworkTitle;

  /// Privacy sheet point body: no network access
  ///
  /// In en, this message translates to:
  /// **'VaultExplorer does not request the android.permission.INTERNET permission on Android. It cannot communicate over any network.'**
  String get privacyPointNoNetworkBody;

  /// Privacy sheet point title: no unencrypted disk leaks
  ///
  /// In en, this message translates to:
  /// **'Zero unencrypted disk leaks'**
  String get privacyPointNoDiskLeaksTitle;

  /// Privacy sheet point body: no unencrypted disk leaks
  ///
  /// In en, this message translates to:
  /// **'Decryption and re-encryption happen entirely in system memory. Temporary unencrypted files are never saved to device storage.'**
  String get privacyPointNoDiskLeaksBody;

  /// Privacy sheet point title: no analytics or telemetry
  ///
  /// In en, this message translates to:
  /// **'No analytics or telemetry'**
  String get privacyPointNoAnalyticsTitle;

  /// Privacy sheet point body: no analytics or telemetry
  ///
  /// In en, this message translates to:
  /// **'There is zero crash reporting, usage tracking, or third-party SDK collecting data about you or your device.'**
  String get privacyPointNoAnalyticsBody;

  /// Privacy sheet point title: secrets stay in Android Keystore
  ///
  /// In en, this message translates to:
  /// **'Secrets stay in Android Keystore'**
  String get privacyPointKeystoreTitle;

  /// Privacy sheet point body: secrets stay in Android Keystore
  ///
  /// In en, this message translates to:
  /// **'Remembered passwords, patterns, and cached derived keys are sealed using AES-256-GCM in the hardware-backed Android Keystore.'**
  String get privacyPointKeystoreBody;

  /// Privacy sheet point title: POSIX acceleration and storage access
  ///
  /// In en, this message translates to:
  /// **'POSIX Acceleration & Storage Access'**
  String get privacyPointPosixTitle;

  /// Privacy sheet point body: POSIX acceleration and storage access
  ///
  /// In en, this message translates to:
  /// **'Files inside directory vaults are read and written directly when possible, bypassing Android\'s slower SAF layer for large folders.'**
  String get privacyPointPosixBody;

  /// Privacy sheet point title: screen and clipboard protection
  ///
  /// In en, this message translates to:
  /// **'Screen & Clipboard Protection'**
  String get privacyPointScreenClipboardTitle;

  /// Privacy sheet point body: screen and clipboard protection
  ///
  /// In en, this message translates to:
  /// **'Screenshot/task-switcher preview blocking (FLAG_SECURE), plus automatic corrupt clipboard sanitization upon window focus. Passwords copied from the Item Vault are marked sensitive on Android 13+ and auto-cleared 30 seconds later if untouched.'**
  String get privacyPointScreenClipboardBody;

  /// Privacy sheet point title: Mask Mode disguise
  ///
  /// In en, this message translates to:
  /// **'Mask Mode'**
  String get privacyPointMaskModeTitle;

  /// Privacy sheet point body: Mask Mode disguise
  ///
  /// In en, this message translates to:
  /// **'Optionally disguises the app as a working zip archive browser, with a different icon and name. Hold the title for 2 seconds to reach your real vault.'**
  String get privacyPointMaskModeBody;

  /// Privacy sheet point title: external links open in browser
  ///
  /// In en, this message translates to:
  /// **'External links open in browser'**
  String get privacyPointExternalLinksTitle;

  /// Privacy sheet point body: external links open in browser
  ///
  /// In en, this message translates to:
  /// **'Tapping links hands off to your default browser app, which handles the request.'**
  String get privacyPointExternalLinksBody;

  /// Warning banner shown above the file list when a folder's listing was capped at the max item count
  ///
  /// In en, this message translates to:
  /// **'Showing first 50,000 items — this folder has more files.'**
  String get truncatedListingWarning;

  /// Summary line showing the configured thumbnail size and JPEG compression quality
  ///
  /// In en, this message translates to:
  /// **'{size} px · {quality}% quality'**
  String thumbnailQualitySummary(int size, int quality);

  /// On-screen indicator shown while holding down to fast-forward playback at a multiplier
  ///
  /// In en, this message translates to:
  /// **'{speed}× Speed'**
  String holdToSpeedIndicatorLabel(String speed);

  /// Section header on toolbar settings screen
  ///
  /// In en, this message translates to:
  /// **'Toolbar Layout'**
  String get toolbarLayoutSectionHeader;

  /// Section header on toolbar settings screen
  ///
  /// In en, this message translates to:
  /// **'List View Options'**
  String get listViewOptionsSectionHeader;

  /// Section header on toolbar settings screen
  ///
  /// In en, this message translates to:
  /// **'Detailed List View Columns'**
  String get detailedListViewColumnsSectionHeader;

  /// Section header on toolbar settings screen
  ///
  /// In en, this message translates to:
  /// **'Gallery Grid View'**
  String get galleryGridViewSectionHeader;

  /// Section header on toolbar settings screen
  ///
  /// In en, this message translates to:
  /// **'Browser Layout'**
  String get browserLayoutSectionHeader;

  /// Section header on toolbar settings screen
  ///
  /// In en, this message translates to:
  /// **'Media Viewer'**
  String get mediaViewerSectionHeader;

  /// Label for view mode toolbar action
  ///
  /// In en, this message translates to:
  /// **'View mode'**
  String get viewModeAction;

  /// Label for sort toolbar action
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortAction;

  /// Label for play media toolbar action
  ///
  /// In en, this message translates to:
  /// **'Play media'**
  String get playMediaAction;

  /// Storage space summary shown on mounted container card
  ///
  /// In en, this message translates to:
  /// **'{free} free · {total} total'**
  String containerSpaceSummary(String free, String total);

  /// Fallback summary shown on mounted container card when total space is unknown
  ///
  /// In en, this message translates to:
  /// **'Vol {volId} · Mounted'**
  String volMountedSummary(int volId);

  /// Occupied space summary shown on mounted folder vault card (Cryptomator/gocryptfs/CryFS), which have no fixed total size
  ///
  /// In en, this message translates to:
  /// **'{used} used'**
  String vaultOccupiedSpaceSummary(String used);

  /// Error message when unlocking/verifying container fails due to wrong password or keyfiles
  ///
  /// In en, this message translates to:
  /// **'Incorrect password/keyfiles or unsupported drive'**
  String get incorrectPasswordOrKeyfilesDriveError;

  /// Helper text showing detected USB drive usable capacity
  ///
  /// In en, this message translates to:
  /// **'Drive usable capacity: {mb} MB. Must not exceed this.'**
  String driveUsableCapacity(int mb);

  /// Container unlock method label
  ///
  /// In en, this message translates to:
  /// **'Manual Password'**
  String get unlockMethodManualPassword;

  /// Container unlock method label
  ///
  /// In en, this message translates to:
  /// **'Remember Password'**
  String get unlockMethodRememberPassword;

  /// Container unlock method label
  ///
  /// In en, this message translates to:
  /// **'Biometric Unlock'**
  String get unlockMethodBiometrics;

  /// Container unlock method label
  ///
  /// In en, this message translates to:
  /// **'Pattern Unlock'**
  String get unlockMethodPattern;

  /// Container unlock method label
  ///
  /// In en, this message translates to:
  /// **'PIN Unlock'**
  String get unlockMethodPin;

  /// Subtitle explaining manual password unlock method
  ///
  /// In en, this message translates to:
  /// **'Type the password every time'**
  String get unlockMethodSubtitlePassword;

  /// Subtitle explaining stored password unlock method
  ///
  /// In en, this message translates to:
  /// **'Stored securely in Android Keystore'**
  String get unlockMethodSubtitleRememberPassword;

  /// Subtitle explaining biometric unlock method
  ///
  /// In en, this message translates to:
  /// **'Use fingerprint or face to unlock'**
  String get unlockMethodSubtitleBiometrics;

  /// Subtitle explaining pattern unlock method
  ///
  /// In en, this message translates to:
  /// **'Draw a pattern to unlock'**
  String get unlockMethodSubtitlePattern;

  /// Subtitle explaining PIN unlock method
  ///
  /// In en, this message translates to:
  /// **'Enter a PIN to unlock'**
  String get unlockMethodSubtitlePin;

  /// Combines file selection and folder selection summaries
  ///
  /// In en, this message translates to:
  /// **'{filePart} + {folderPart}'**
  String selectionSummaryCombined(String filePart, String folderPart);

  /// Error description when video player initialization fails
  ///
  /// In en, this message translates to:
  /// **'Video decoder unavailable — hardware codec contention'**
  String get videoDecoderUnavailableError;

  /// Fallback error description for video playback failure
  ///
  /// In en, this message translates to:
  /// **'Media stream initialization failed'**
  String get mediaStreamInitFailedError;

  /// Error message when an AVIF image is corrupt or invalid
  ///
  /// In en, this message translates to:
  /// **'Invalid AVIF image'**
  String get invalidAvifImage;

  /// Verb: Import
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get verbImport;

  /// Verb: Export
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get verbExport;

  /// Verb: Move
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get verbMove;

  /// Verb: Copy
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get verbCopy;

  /// Verb: Delete
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get verbDelete;

  /// Past-tense verb: Imported
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get verbImported;

  /// Past-tense verb: Exported
  ///
  /// In en, this message translates to:
  /// **'Exported'**
  String get verbExported;

  /// Past-tense verb: Moved
  ///
  /// In en, this message translates to:
  /// **'Moved'**
  String get verbMoved;

  /// Past-tense verb: Copied
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get verbCopied;

  /// Past-tense verb: Deleted
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get verbDeleted;

  /// Present-continuous verb: Importing
  ///
  /// In en, this message translates to:
  /// **'Importing'**
  String get verbImporting;

  /// Present-continuous verb: Exporting
  ///
  /// In en, this message translates to:
  /// **'Exporting'**
  String get verbExporting;

  /// Present-continuous verb: Moving
  ///
  /// In en, this message translates to:
  /// **'Moving'**
  String get verbMoving;

  /// Present-continuous verb: Copying
  ///
  /// In en, this message translates to:
  /// **'Copying'**
  String get verbCopying;

  /// Present-continuous verb: Deleting
  ///
  /// In en, this message translates to:
  /// **'Deleting'**
  String get verbDeleting;

  /// Pluralized count of items in a file operation
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String fileOpItemsCount(num count);

  /// Completion summary count of items processed
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item {verb}} other{{count} items {verb}}}'**
  String fileOpSummaryCount(num count, String verb);

  /// Completion summary count of skipped items
  ///
  /// In en, this message translates to:
  /// **'{count} skipped'**
  String fileOpSummarySkipped(num count);

  /// Completion summary count of failed items
  ///
  /// In en, this message translates to:
  /// **'{count} failed'**
  String fileOpSummaryFailed(num count);

  /// Status label for cancelled operations
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// Status label for failed operations
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// Status label for completed operations
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusCompleted;

  /// Status message while checking available space before a file operation
  ///
  /// In en, this message translates to:
  /// **'Checking available space…'**
  String get fileOpCheckingSpace;

  /// Status message while resolving file name conflicts before a file operation
  ///
  /// In en, this message translates to:
  /// **'Resolving conflicts…'**
  String get fileOpResolvingConflicts;

  /// Error message when storage space is insufficient for a file operation
  ///
  /// In en, this message translates to:
  /// **'Not enough space — need {required}, only {free} free'**
  String fileOpNotEnoughSpace(String required, String free);

  /// Error message when disk becomes full during a file operation and partial files are cleaned up
  ///
  /// In en, this message translates to:
  /// **'Disk full — partial files removed'**
  String get fileOpDiskFullPartialRemoved;

  /// Error message when moving a file fails
  ///
  /// In en, this message translates to:
  /// **'Move failed'**
  String get fileOpMoveFailed;

  /// Error message when copying a file fails
  ///
  /// In en, this message translates to:
  /// **'Copy failed'**
  String get fileOpCopyFailed;

  /// Error message when deleting a file or folder fails
  ///
  /// In en, this message translates to:
  /// **'Delete failed'**
  String get fileOpDeleteFailed;

  /// Error message when disk becomes full
  ///
  /// In en, this message translates to:
  /// **'Disk full'**
  String get fileOpDiskFull;

  /// Status message while importing
  ///
  /// In en, this message translates to:
  /// **'Importing…'**
  String get fileOpImporting;

  /// Status message while exporting
  ///
  /// In en, this message translates to:
  /// **'Exporting…'**
  String get fileOpExporting;

  /// Status message while importing a specific item
  ///
  /// In en, this message translates to:
  /// **'Importing {name}…'**
  String fileOpImportingName(String name);

  /// Status message while exporting a specific item
  ///
  /// In en, this message translates to:
  /// **'Exporting {name}…'**
  String fileOpExportingName(String name);

  /// Status message while moving a specific item
  ///
  /// In en, this message translates to:
  /// **'Moving {name}…'**
  String fileOpMovingName(String name);

  /// Status message while copying a specific item
  ///
  /// In en, this message translates to:
  /// **'Copying {name}…'**
  String fileOpCopyingName(String name);

  /// Status message while a delete operation is starting, before the first item has been processed
  ///
  /// In en, this message translates to:
  /// **'Deleting…'**
  String get fileOpDeleting;

  /// Status message showing the specific file or folder currently being removed during a delete operation
  ///
  /// In en, this message translates to:
  /// **'Deleting {name}…'**
  String fileOpDeletingName(String name);

  /// Live running count of files/folders removed so far, shown while a delete operation is in progress — especially useful for slow backends (e.g. cryFS) where the operation can otherwise look stalled
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item removed} other{{count} items removed}}'**
  String fileOpDeletedSoFar(num count);

  /// Hint text for searching recursively across subfolders
  ///
  /// In en, this message translates to:
  /// **'Search all subfolders…'**
  String get searchInSubfoldersHint;

  /// Tooltip when recursive subfolder search is active
  ///
  /// In en, this message translates to:
  /// **'Searching subfolders — tap for current folder only'**
  String get deepSearchEnabledTooltip;

  /// Tooltip when local folder search is active
  ///
  /// In en, this message translates to:
  /// **'Searching current folder — tap to search subfolders'**
  String get deepSearchDisabledTooltip;

  /// Label for filter toolbar action
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filterAction;

  /// No description provided for @bookmarkAction.
  ///
  /// In en, this message translates to:
  /// **'Bookmark'**
  String get bookmarkAction;

  /// No description provided for @unbookmarkAction.
  ///
  /// In en, this message translates to:
  /// **'Unbookmark'**
  String get unbookmarkAction;

  /// No description provided for @bookmarkSelectedAction.
  ///
  /// In en, this message translates to:
  /// **'Bookmark selected'**
  String get bookmarkSelectedAction;

  /// No description provided for @unbookmarkSelectedAction.
  ///
  /// In en, this message translates to:
  /// **'Unbookmark selected'**
  String get unbookmarkSelectedAction;

  /// No description provided for @bookmarkedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Bookmarked 1 item} other{Bookmarked {count} items}}'**
  String bookmarkedCount(num count);

  /// No description provided for @unbookmarkedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Unbookmarked 1 item} other{Unbookmarked {count} items}}'**
  String unbookmarkedCount(num count);

  /// No description provided for @showBookmarkBarLabel.
  ///
  /// In en, this message translates to:
  /// **'Show Bookmark Bar'**
  String get showBookmarkBarLabel;

  /// No description provided for @showBookmarkBarDesc.
  ///
  /// In en, this message translates to:
  /// **'Display bookmarked items in a bookmark bar or sidebar'**
  String get showBookmarkBarDesc;

  /// No description provided for @bookmarkBarSectionHeader.
  ///
  /// In en, this message translates to:
  /// **'Bookmark Bar'**
  String get bookmarkBarSectionHeader;

  /// No description provided for @noBookmarksYet.
  ///
  /// In en, this message translates to:
  /// **'No items bookmarked yet'**
  String get noBookmarksYet;

  /// No description provided for @reorderBookmarksTitle.
  ///
  /// In en, this message translates to:
  /// **'Rearrange Bookmarks'**
  String get reorderBookmarksTitle;

  /// No description provided for @reorderBookmarksDesc.
  ///
  /// In en, this message translates to:
  /// **'Drag items to reorder them in the bookmark bar'**
  String get reorderBookmarksDesc;

  /// Bottom navigation bar label for the Vaults dashboard tab
  ///
  /// In en, this message translates to:
  /// **'Vaults'**
  String get navBarVaultsLabel;

  /// Bottom navigation bar label for the Tools tab
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get navBarToolsLabel;

  /// AppBar title for the Tools tab
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get toolsScreenTitle;

  /// Section header on the Tools tab, above Split/Repair
  ///
  /// In en, this message translates to:
  /// **'Container Utilities'**
  String get toolsSectionContainerUtilities;

  /// Section header on the Tools tab, above Single-File Encrypt/Decrypt
  ///
  /// In en, this message translates to:
  /// **'File Cryptography'**
  String get toolsSectionFileCryptography;

  /// Section header on the Tools tab, above Storage Analyzer
  ///
  /// In en, this message translates to:
  /// **'Storage & Diagnostics'**
  String get toolsSectionStorageDiagnostics;

  /// Tool card title for the Container Splitter/Joiner
  ///
  /// In en, this message translates to:
  /// **'Split & Join'**
  String get toolContainerSplitterTitle;

  /// Tool card subtitle for the Container Splitter/Joiner
  ///
  /// In en, this message translates to:
  /// **'Split a container into chunks, or rejoin them'**
  String get toolContainerSplitterSubtitle;

  /// Tool card title for Container Check & Repair
  ///
  /// In en, this message translates to:
  /// **'Check & Repair'**
  String get toolContainerRepairTitle;

  /// Tool card subtitle for Container Check & Repair
  ///
  /// In en, this message translates to:
  /// **'Diagnose header or filesystem issues'**
  String get toolContainerRepairSubtitle;

  /// Tool card title for Single-File Encrypt/Decrypt
  ///
  /// In en, this message translates to:
  /// **'Encrypt / Decrypt Files'**
  String get toolSingleFileCryptoTitle;

  /// Tool card subtitle for Single-File Encrypt/Decrypt
  ///
  /// In en, this message translates to:
  /// **'Protect one or more files without a full container'**
  String get toolSingleFileCryptoSubtitle;

  /// Tool card title for the Storage Analyzer
  ///
  /// In en, this message translates to:
  /// **'Storage Analyzer'**
  String get toolStorageAnalyzerTitle;

  /// Tool card subtitle for the Storage Analyzer
  ///
  /// In en, this message translates to:
  /// **'See what\'s taking up space in a mounted vault'**
  String get toolStorageAnalyzerSubtitle;

  /// Tool card title for Duplicate File Finder
  ///
  /// In en, this message translates to:
  /// **'Duplicate File Finder'**
  String get toolDuplicateFinderTitle;

  /// Tool card subtitle for Duplicate File Finder
  ///
  /// In en, this message translates to:
  /// **'Find & remove byte-identical duplicate files to reclaim space'**
  String get toolDuplicateFinderSubtitle;

  /// Tool card title for the File Checksum & Hash Verifier
  ///
  /// In en, this message translates to:
  /// **'File Checksum & Hash Verifier'**
  String get toolHashVerifierTitle;

  /// Tool card subtitle for the File Checksum & Hash Verifier
  ///
  /// In en, this message translates to:
  /// **'Verify large files weren\'t corrupted using MD5/SHA checksums'**
  String get toolHashVerifierSubtitle;

  /// Segmented-button label for the Hash Verifier's compute-a-hash mode
  ///
  /// In en, this message translates to:
  /// **'Compute'**
  String get hashVerifierModeCompute;

  /// Segmented-button label for the Hash Verifier's verify-against-manifest mode
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get hashVerifierModeVerify;

  /// Bottom sheet title when picking device vs. vault as a file source in the Hash Verifier
  ///
  /// In en, this message translates to:
  /// **'Select File Source'**
  String get hashVerifierSelectSourceTitle;

  /// Label above the hash-algorithm selector chips on the Hash Verifier's Compute tab
  ///
  /// In en, this message translates to:
  /// **'Algorithms'**
  String get hashVerifierAlgorithmsLabel;

  /// Error shown when Compute is pressed with no algorithm chip selected
  ///
  /// In en, this message translates to:
  /// **'Select at least one algorithm'**
  String get hashVerifierNoAlgorithmSelected;

  /// Label above the file list on the Hash Verifier's Compute tab
  ///
  /// In en, this message translates to:
  /// **'Files to Hash'**
  String get hashVerifierFilesLabel;

  /// Count readout under the Compute tab's file list
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No files selected} =1{1 file selected} other{{count} files selected}}'**
  String hashVerifierFilesQueuedCount(num count);

  /// Primary button on the Hash Verifier's Compute tab
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Compute Hash} other{Compute {count} Hashes}}'**
  String hashVerifierComputeButton(num count);

  /// Button shown in place of the primary action while a hash computation or verification run is in flight
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get hashVerifierCancelButton;

  /// Progress readout while a multi-file Compute run is in flight
  ///
  /// In en, this message translates to:
  /// **'File {current} of {total}'**
  String hashVerifierBatchProgressLabel(Object current, Object total);

  /// Shown after the user cancels an in-flight hash computation or verification run
  ///
  /// In en, this message translates to:
  /// **'Cancelled.'**
  String get hashVerifierCancelledMessage;

  /// Error banner shown when one or more files failed to hash during a Compute run
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file failed to hash} other{{count} files failed to hash}}'**
  String hashVerifierComputeErrorsMessage(num count);

  /// Snackbar shown after copying a hex digest to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get hashVerifierCopiedMessage;

  /// Button to write computed hashes out as a checksum manifest file
  ///
  /// In en, this message translates to:
  /// **'Export as Manifest'**
  String get hashVerifierExportManifestButton;

  /// Label next to the algorithm dropdown used when exporting a checksum manifest
  ///
  /// In en, this message translates to:
  /// **'Manifest algorithm'**
  String get hashVerifierExportAlgorithmLabel;

  /// Snackbar shown after a checksum manifest is exported
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String hashVerifierExportSuccessMessage(Object path);

  /// Snackbar shown when exporting a checksum manifest fails
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String hashVerifierExportFailedMessage(Object error);

  /// Button to pick a checksum manifest file on the Hash Verifier's Verify tab
  ///
  /// In en, this message translates to:
  /// **'Load Manifest'**
  String get hashVerifierLoadManifestButton;

  /// Button to swap out the currently-loaded checksum manifest for a different one
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get hashVerifierChangeManifestButton;

  /// Label above the loaded manifest's filename on the Verify tab
  ///
  /// In en, this message translates to:
  /// **'Manifest File'**
  String get hashVerifierManifestLabel;

  /// Entry-count readout under the loaded manifest's filename
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No entries} =1{1 entry} other{{count} entries}}'**
  String hashVerifierManifestEntryCount(num count);

  /// Button that auto-adds every file in the vault folder containing the loaded manifest as verify candidates
  ///
  /// In en, this message translates to:
  /// **'Add All Files From This Folder'**
  String get hashVerifierAutoAddFolderButton;

  /// Button to manually add candidate files to match against manifest entries
  ///
  /// In en, this message translates to:
  /// **'Add Files to Verify'**
  String get hashVerifierAddFilesToVerifyButton;

  /// Primary button on the Hash Verifier's Verify tab
  ///
  /// In en, this message translates to:
  /// **'Verify All'**
  String get hashVerifierVerifyAllButton;

  /// Progress readout while a multi-file Verify run is in flight
  ///
  /// In en, this message translates to:
  /// **'Verifying file {current} of {total}'**
  String hashVerifierVerifyProgressLabel(Object current, Object total);

  /// Summary banner above the Verify tab's results list
  ///
  /// In en, this message translates to:
  /// **'{ok} matched, {mismatch} mismatched, {missing} missing'**
  String hashVerifierSummaryMessage(Object ok, Object mismatch, Object missing);

  /// Status label for a verify row whose computed hash matches the manifest
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get hashVerifierStatusMatch;

  /// Status label for a verify row whose computed hash doesn't match the manifest
  ///
  /// In en, this message translates to:
  /// **'Mismatch'**
  String get hashVerifierStatusMismatch;

  /// Status label for a manifest entry with no matching candidate file added yet
  ///
  /// In en, this message translates to:
  /// **'File not added'**
  String get hashVerifierStatusMissing;

  /// Status label for a matched verify row that hasn't been hashed yet
  ///
  /// In en, this message translates to:
  /// **'Not yet verified'**
  String get hashVerifierStatusPending;

  /// Label before the manifest's expected hex digest on a mismatched verify row
  ///
  /// In en, this message translates to:
  /// **'Expected'**
  String get hashVerifierExpectedLabel;

  /// Label before the freshly-computed hex digest on a mismatched verify row
  ///
  /// In en, this message translates to:
  /// **'Actual'**
  String get hashVerifierActualLabel;

  /// Note listing candidate files that were added but aren't referenced by any manifest entry
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 extra file not listed in the manifest} other{{count} extra files not listed in the manifest}}'**
  String hashVerifierExtraFilesLabel(num count);

  /// Placeholder banner on the Verify tab before any manifest has been loaded
  ///
  /// In en, this message translates to:
  /// **'Load a manifest file to begin'**
  String get hashVerifierNoManifestLoadedMessage;

  /// Error shown when a loaded manifest file contains no recognizable checksum lines
  ///
  /// In en, this message translates to:
  /// **'No checksum entries found in this file'**
  String get hashVerifierManifestParseEmptyMessage;

  /// Error shown when reading the picked manifest file fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read manifest: {error}'**
  String hashVerifierLoadManifestFailedMessage(Object error);

  /// Snackbar shown after auto-adding every file from the manifest's vault folder
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No new files found} =1{Added 1 file from the vault folder} other{Added {count} files from the vault folder}}'**
  String hashVerifierAutoAddedCount(num count);

  /// Segmented-button label for the 'Check entire vault' tab
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get hashVerifierModeVault;

  /// Label on the picker tile used to choose which mounted vault to check
  ///
  /// In en, this message translates to:
  /// **'Vault'**
  String get hashVerifierVaultPickerLabel;

  /// Placeholder shown on the Vault tab when there are no mounted vaults to check
  ///
  /// In en, this message translates to:
  /// **'No vaults are currently mounted'**
  String get hashVerifierVaultNoVaultsMessage;

  /// Button that starts scanning the selected vault
  ///
  /// In en, this message translates to:
  /// **'Check Entire Vault'**
  String get hashVerifierCheckEntireVaultButton;

  /// Status label shown while the vault scanner is discovering files
  ///
  /// In en, this message translates to:
  /// **'Scanning vault…'**
  String get hashVerifierVaultScanningLabel;

  /// Live count shown under the scanning progress indicator
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No files discovered yet} =1{1 file discovered} other{{count} files discovered}}'**
  String hashVerifierVaultFilesDiscoveredLabel(num count);

  /// Heading on the confirmation step shown after a vault scan completes
  ///
  /// In en, this message translates to:
  /// **'Check entire vault?'**
  String get hashVerifierVaultConfirmTitle;

  /// File count line on the vault confirmation step
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String hashVerifierVaultConfirmFilesLabel(num count);

  /// Warning shown on the vault confirmation step before starting an expensive full-vault check
  ///
  /// In en, this message translates to:
  /// **'Every file in this vault will be read.'**
  String get hashVerifierVaultConfirmWarning;

  /// Message shown on the confirmation step when the scan discovered zero files
  ///
  /// In en, this message translates to:
  /// **'This vault has no files to check'**
  String get hashVerifierVaultEmptyMessage;

  /// Button on the vault confirmation step that begins hashing every discovered file
  ///
  /// In en, this message translates to:
  /// **'Start Check'**
  String get hashVerifierVaultStartButton;

  /// Progress label shown while hashing discovered vault files
  ///
  /// In en, this message translates to:
  /// **'Checking {current} / {total}'**
  String hashVerifierVaultHashingProgressLabel(Object current, Object total);

  /// Heading on the aggregate summary shown after a vault check finishes
  ///
  /// In en, this message translates to:
  /// **'Vault Check Complete'**
  String get hashVerifierVaultCompleteTitle;

  /// Total files checked line in the vault completion summary
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file checked} other{{count} files checked}}'**
  String hashVerifierVaultCompleteFilesLabel(num count);

  /// Total bytes processed line in the vault completion summary
  ///
  /// In en, this message translates to:
  /// **'{size} processed'**
  String hashVerifierVaultCompleteBytesLabel(Object size);

  /// Successful-files line in the vault completion summary
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 successful} other{{count} successful}}'**
  String hashVerifierVaultCompleteSucceededLabel(num count);

  /// Failed-files line in the vault completion summary
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{0 failed} =1{1 failed} other{{count} failed}}'**
  String hashVerifierVaultCompleteFailedLabel(num count);

  /// Elapsed-time line in the vault completion summary
  ///
  /// In en, this message translates to:
  /// **'Elapsed: {time}'**
  String hashVerifierVaultElapsedLabel(Object time);

  /// Message shown when a vault scan or check is cancelled
  ///
  /// In en, this message translates to:
  /// **'Vault check cancelled.'**
  String get hashVerifierVaultCancelledMessage;

  /// Error banner shown when a vault operation fails at the operation level (not a single file)
  ///
  /// In en, this message translates to:
  /// **'Vault check failed: {error}'**
  String hashVerifierVaultFailedMessage(Object error);

  /// Button that resets the Vault tab after a check completes, to start another one
  ///
  /// In en, this message translates to:
  /// **'New Check'**
  String get hashVerifierVaultNewCheckButton;

  /// Title of the 'hash every file in a vault' option on the Vault tab's action chooser
  ///
  /// In en, this message translates to:
  /// **'Compute Entire Vault'**
  String get hashVerifierVaultActionComputeTitle;

  /// Subtitle of the 'hash every file in a vault' option on the Vault tab's action chooser
  ///
  /// In en, this message translates to:
  /// **'Hash every file in a vault'**
  String get hashVerifierVaultActionComputeSubtitle;

  /// Title of the 'check every file in a vault against a manifest' option on the Vault tab's action chooser
  ///
  /// In en, this message translates to:
  /// **'Verify Entire Vault'**
  String get hashVerifierVaultActionVerifyTitle;

  /// Subtitle of the 'check every file in a vault against a manifest' option on the Vault tab's action chooser
  ///
  /// In en, this message translates to:
  /// **'Check every file in a vault against a loaded manifest'**
  String get hashVerifierVaultActionVerifySubtitle;

  /// Button that returns the Vault tab from a chosen action back to the compute/verify chooser
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get hashVerifierVaultChangeActionButton;

  /// Button that scans the loaded manifest's vault and verifies every file it finds against it
  ///
  /// In en, this message translates to:
  /// **'Verify Entire Vault'**
  String get hashVerifierVaultVerifyButton;

  /// Warning shown on Vault > Verify Entire Vault when the loaded manifest is an external/on-device file rather than a vault file
  ///
  /// In en, this message translates to:
  /// **'Verifying an entire vault requires a manifest loaded from inside a vault.'**
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage;

  /// Label for target vault selector in Duplicate File Finder
  ///
  /// In en, this message translates to:
  /// **'Target Vault'**
  String get duplicateFinderTargetLabel;

  /// Option for scanning all open vaults in Duplicate File Finder
  ///
  /// In en, this message translates to:
  /// **'All Open Vaults'**
  String get duplicateFinderTargetAllVaults;

  /// Button label to start duplicate scan
  ///
  /// In en, this message translates to:
  /// **'Start Scan'**
  String get duplicateFinderStartScan;

  /// Button label to cancel duplicate scan
  ///
  /// In en, this message translates to:
  /// **'Cancel Scan'**
  String get duplicateFinderCancelScan;

  /// Button label to rescan for duplicates
  ///
  /// In en, this message translates to:
  /// **'Rescan'**
  String get duplicateFinderRescan;

  /// Stage 1 scanning status
  ///
  /// In en, this message translates to:
  /// **'Stage 1: Indexing & size grouping...'**
  String get duplicateFinderScanningStage1;

  /// Stage 2 scanning status
  ///
  /// In en, this message translates to:
  /// **'Stage 2: Checking partial file headers...'**
  String get duplicateFinderScanningStage2;

  /// Stage 3 scanning status
  ///
  /// In en, this message translates to:
  /// **'Stage 3: Verifying full byte hashes...'**
  String get duplicateFinderScanningStage3;

  /// Scan complete status
  ///
  /// In en, this message translates to:
  /// **'Scan Complete'**
  String get duplicateFinderScanComplete;

  /// Title when no duplicate files are found
  ///
  /// In en, this message translates to:
  /// **'No Duplicate Files Found'**
  String get duplicateFinderNoDuplicatesTitle;

  /// Message when no duplicate files are found
  ///
  /// In en, this message translates to:
  /// **'All files in the scanned vault(s) contain unique byte contents.'**
  String get duplicateFinderNoDuplicatesMessage;

  /// Action to select redundant copies
  ///
  /// In en, this message translates to:
  /// **'Select Redundant'**
  String get duplicateFinderSelectRedundant;

  /// Action to select all files
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get duplicateFinderSelectAll;

  /// Action to deselect all files
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get duplicateFinderDeselectAll;

  /// Badge for original/keep copy
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get duplicateFinderOriginalLabel;

  /// Badge for redundant duplicate copy
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicateFinderDuplicateLabel;

  /// Dialog title for deleting duplicates
  ///
  /// In en, this message translates to:
  /// **'Delete Duplicate Files?'**
  String get duplicateFinderConfirmDeleteTitle;

  /// Search field hint text in Duplicate Finder
  ///
  /// In en, this message translates to:
  /// **'Search duplicates by filename or path...'**
  String get duplicateFinderSearchHint;

  /// Shown when a Tools-tab action calls into a ContainerToolService method that still throws UnimplementedError
  ///
  /// In en, this message translates to:
  /// **'This tool isn\'t wired up to the native engine yet — check back in a future update.'**
  String get toolNotImplementedYetMessage;

  /// Segmented button option: split mode
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get splitJoinModeSplit;

  /// Segmented button option: join mode
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get splitJoinModeJoin;

  /// Label for the container file being split
  ///
  /// In en, this message translates to:
  /// **'Source File'**
  String get splitSourceFileLabel;

  /// Label for where split chunks are written
  ///
  /// In en, this message translates to:
  /// **'Destination Folder'**
  String get splitDestinationFolderLabel;

  /// Label for the chunk-size preset selector
  ///
  /// In en, this message translates to:
  /// **'Chunk Size'**
  String get splitChunkSizeLabel;

  /// Text field label for a custom chunk size in megabytes
  ///
  /// In en, this message translates to:
  /// **'Custom size (MB)'**
  String get splitChunkSizeCustomLabel;

  /// Chunk size preset label: 4 MB
  ///
  /// In en, this message translates to:
  /// **'4 MB'**
  String get splitChunkSizeFourMb;

  /// Chunk size preset label: 8 MB
  ///
  /// In en, this message translates to:
  /// **'8 MB'**
  String get splitChunkSizeCloud8mb;

  /// Chunk size preset label: 32 MB
  ///
  /// In en, this message translates to:
  /// **'32 MB'**
  String get splitChunkSizeCloud32mb;

  /// Chunk size preset label: 100 MB
  ///
  /// In en, this message translates to:
  /// **'100 MB'**
  String get splitChunkSizeCloud;

  /// Chunk size preset label: 2 GB
  ///
  /// In en, this message translates to:
  /// **'2 GB'**
  String get splitChunkSizeFat32;

  /// Chunk size preset label: 4 GB
  ///
  /// In en, this message translates to:
  /// **'4 GB'**
  String get splitChunkSizeFourGb;

  /// Chunk size preset label: user-entered custom size
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get splitChunkSizeCustom;

  /// Primary action button label for the Split flow
  ///
  /// In en, this message translates to:
  /// **'Split Container'**
  String get splitContainerButton;

  /// Label for the first chunk file (e.g. .001) when joining
  ///
  /// In en, this message translates to:
  /// **'First Part'**
  String get joinFirstPartLabel;

  /// Text field label for the joined output file's name
  ///
  /// In en, this message translates to:
  /// **'Output File Name'**
  String get joinOutputFileNameLabel;

  /// Primary action button label for the Join flow
  ///
  /// In en, this message translates to:
  /// **'Join Files'**
  String get joinContainerButton;

  /// Generic button label to open a file picker
  ///
  /// In en, this message translates to:
  /// **'Choose File'**
  String get chooseFileButton;

  /// Generic button label to open a folder picker
  ///
  /// In en, this message translates to:
  /// **'Choose Folder'**
  String get chooseFolderButton;

  /// Placeholder shown before a file has been picked
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get noFileSelectedLabel;

  /// Placeholder shown before a destination folder has been picked
  ///
  /// In en, this message translates to:
  /// **'No folder selected'**
  String get noFolderSelectedLabel;

  /// Byte progress readout for split/join/encrypt/decrypt operations
  ///
  /// In en, this message translates to:
  /// **'{done} / {total}'**
  String splitJoinOperationProgress(String done, String total);

  /// Snackbar shown after a successful split
  ///
  /// In en, this message translates to:
  /// **'Container split successfully'**
  String get splitContainerSuccessMessage;

  /// Snackbar shown after a successful join
  ///
  /// In en, this message translates to:
  /// **'Files joined successfully'**
  String get joinContainerSuccessMessage;

  /// Segmented button option: encrypt mode
  ///
  /// In en, this message translates to:
  /// **'Encrypt'**
  String get cryptoDirectionEncrypt;

  /// Segmented button option: decrypt mode
  ///
  /// In en, this message translates to:
  /// **'Decrypt'**
  String get cryptoDirectionDecrypt;

  /// Label for the file(s) being encrypted/decrypted
  ///
  /// In en, this message translates to:
  /// **'Input Files'**
  String get singleFileCryptoInputFileLabel;

  /// Label for the standalone AEAD cipher selector
  ///
  /// In en, this message translates to:
  /// **'Cipher'**
  String get singleFileCryptoCipherLabel;

  /// Switch label to delete the plaintext source(s) after encrypting
  ///
  /// In en, this message translates to:
  /// **'Delete original files after encryption'**
  String get singleFileCryptoDeleteOriginalLabel;

  /// Primary action button label when encrypting, given how many files are queued
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Encrypt File} other{Encrypt {count} Files}}'**
  String singleFileCryptoEncryptButton(num count);

  /// Primary action button label when decrypting, given how many files are queued
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Decrypt File} other{Decrypt {count} Files}}'**
  String singleFileCryptoDecryptButton(num count);

  /// Snackbar shown after a fully successful encrypt/decrypt run
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Done} other{Done — {count} files processed}}'**
  String singleFileCryptoSuccessMessage(num count);

  /// Snackbar shown when a batch encrypt/decrypt run finishes with some files failing
  ///
  /// In en, this message translates to:
  /// **'{succeeded} of {total} files processed — {failed} failed'**
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  );

  /// Button to open the multi-select file picker, adding to the current batch
  ///
  /// In en, this message translates to:
  /// **'Add Files'**
  String get singleFileCryptoAddFilesButton;

  /// Button to clear every file currently queued for encrypt/decrypt
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get singleFileCryptoClearFilesButton;

  /// Count readout under the input-files picker row
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No files selected} =1{1 file selected} other{{count} files selected}}'**
  String singleFileCryptoFilesQueuedCount(num count);

  /// Progress readout while a batch encrypt/decrypt run is in flight
  ///
  /// In en, this message translates to:
  /// **'File {current} of {total}'**
  String singleFileCryptoBatchProgressLabel(Object current, Object total);

  /// Step title: pick an unmounted file or mounted volume to repair
  ///
  /// In en, this message translates to:
  /// **'Choose a Target'**
  String get repairTargetStepTitle;

  /// Repair wizard option: pick a container file that isn't currently mounted
  ///
  /// In en, this message translates to:
  /// **'Unmounted File'**
  String get repairTargetUnmountedFileOption;

  /// Subtitle for the unmounted-file repair target option
  ///
  /// In en, this message translates to:
  /// **'Restore a backup header on a container you haven\'t opened'**
  String get repairTargetUnmountedFileSubtitle;

  /// Subtitle shown above the list of currently mounted volumes in the repair wizard
  ///
  /// In en, this message translates to:
  /// **'Run a filesystem check on an already-open vault'**
  String get repairTargetMountedVolumeSubtitle;

  /// Empty state when no mounted volume is available to repair
  ///
  /// In en, this message translates to:
  /// **'No vaults are currently mounted'**
  String get repairNoMountedVolumes;

  /// Button label to start the repair wizard's diagnostic step
  ///
  /// In en, this message translates to:
  /// **'Run Diagnostic Scan'**
  String get repairScanButton;

  /// Button to go back and pick a different repair target
  ///
  /// In en, this message translates to:
  /// **'Change Target'**
  String get repairChangeTargetButton;

  /// Repair diagnosis result: everything looks fine
  ///
  /// In en, this message translates to:
  /// **'No issues found'**
  String get repairDiagnosisHealthy;

  /// Repair diagnosis result: container header signature/backup mismatch
  ///
  /// In en, this message translates to:
  /// **'Header Corrupted'**
  String get repairDiagnosisHeaderCorrupted;

  /// Repair diagnosis result: filesystem wasn't cleanly unmounted
  ///
  /// In en, this message translates to:
  /// **'Filesystem Dirty / Unclean Unmount'**
  String get repairDiagnosisFilesystemDirty;

  /// Action button for a header-corrupted diagnosis
  ///
  /// In en, this message translates to:
  /// **'Restore Backup Header'**
  String get repairRestoreBackupHeaderButton;

  /// Action button for a filesystem-dirty diagnosis
  ///
  /// In en, this message translates to:
  /// **'Run Filesystem Check & Fix'**
  String get repairRunFilesystemCheckButton;

  /// Shown after a repair action reports success
  ///
  /// In en, this message translates to:
  /// **'Repair completed successfully'**
  String get repairActionSucceededMessage;

  /// Shown after a repair action reports failure
  ///
  /// In en, this message translates to:
  /// **'Repair action did not succeed'**
  String get repairActionFailedMessage;

  /// Label for the mounted-volume picker in Storage Analyzer
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get storageAnalyzerTargetLabel;

  /// Empty state title when no volumes are mounted
  ///
  /// In en, this message translates to:
  /// **'Nothing to Analyze'**
  String get storageAnalyzerNoTargetsTitle;

  /// Empty state message when no volumes are mounted
  ///
  /// In en, this message translates to:
  /// **'Mount a vault first, then come back here to see its storage breakdown.'**
  String get storageAnalyzerNoTargetsMessage;

  /// Capacity gauge caption
  ///
  /// In en, this message translates to:
  /// **'{used} of {total} used'**
  String storageAnalyzerUsedOfTotal(String used, String total);

  /// Section header for the largest-files list
  ///
  /// In en, this message translates to:
  /// **'Heaviest Files'**
  String get storageAnalyzerHeaviestFilesHeader;

  /// Section header for the file-type breakdown bar
  ///
  /// In en, this message translates to:
  /// **'By File Type'**
  String get storageAnalyzerBreakdownHeader;

  /// Shown while the recursive directory walk is in progress
  ///
  /// In en, this message translates to:
  /// **'Scanning volume…'**
  String get storageAnalyzerScanningMessage;

  /// Notice shown when the directory walk hit its entry cap
  ///
  /// In en, this message translates to:
  /// **'Scan stopped early after {count} files — results may be incomplete.'**
  String storageAnalyzerScanTruncatedNotice(String count);

  /// Shown when a mounted volume's directory walk found no files
  ///
  /// In en, this message translates to:
  /// **'No files found'**
  String get storageAnalyzerNoFilesFound;

  /// Storage Analyzer file-type category
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get storageCategoryImages;

  /// Storage Analyzer file-type category
  ///
  /// In en, this message translates to:
  /// **'Videos'**
  String get storageCategoryVideos;

  /// Storage Analyzer file-type category
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get storageCategoryAudio;

  /// Storage Analyzer file-type category
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get storageCategoryDocuments;

  /// Storage Analyzer file-type category
  ///
  /// In en, this message translates to:
  /// **'Archives'**
  String get storageCategoryArchives;

  /// Storage Analyzer file-type category: everything not otherwise classified
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get storageCategoryOther;

  /// Title for Keyfile & Passphrase Generator tool
  ///
  /// In en, this message translates to:
  /// **'Keyfile & Passphrase Generator'**
  String get keyfilePassphraseGeneratorTitle;

  /// Subtitle for Keyfile & Passphrase Generator tool
  ///
  /// In en, this message translates to:
  /// **'Generate Diceware passphrases, custom passwords, and high-entropy keyfiles'**
  String get keyfilePassphraseGeneratorSubtitle;

  /// Tab title for Passphrase Generator
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get tabPassphrase;

  /// Tab title for Keyfile Generator
  ///
  /// In en, this message translates to:
  /// **'Keyfile'**
  String get tabKeyfile;

  /// Generator mode for Diceware word-based passphrases
  ///
  /// In en, this message translates to:
  /// **'Diceware Passphrase'**
  String get modeDiceware;

  /// Generator mode for custom character passwords
  ///
  /// In en, this message translates to:
  /// **'Custom Password'**
  String get modeCustomPassword;

  /// Keyfile format option for binary random bytes
  ///
  /// In en, this message translates to:
  /// **'Binary Keyfile (.key)'**
  String get keyfileTypeBinary;

  /// Keyfile format option for high-entropy PNG image noise
  ///
  /// In en, this message translates to:
  /// **'Noise Image Keyfile (.png)'**
  String get keyfileTypeImage;

  /// Snackbar message when passphrase is copied
  ///
  /// In en, this message translates to:
  /// **'Passphrase copied to sensitive clipboard'**
  String get copyPassphraseSuccess;

  /// Snackbar message when keyfile fingerprint is copied
  ///
  /// In en, this message translates to:
  /// **'SHA-256 fingerprint copied to clipboard'**
  String get copyFingerprintSuccess;

  /// Button to save keyfile into a mounted vault
  ///
  /// In en, this message translates to:
  /// **'Save to Mounted Vault'**
  String get saveKeyfileToVault;

  /// Button to export keyfile to external device storage
  ///
  /// In en, this message translates to:
  /// **'Export to Device Storage'**
  String get exportKeyfileToStorage;

  /// Warning shown when trying to save a keyfile to a vault but none are mounted
  ///
  /// In en, this message translates to:
  /// **'No open vaults available. Please mount a vault first.'**
  String get keyfileNoOpenVaultsMessage;

  /// Bottom sheet title for choosing which mounted vault to save a keyfile into
  ///
  /// In en, this message translates to:
  /// **'Select Destination Vault'**
  String get keyfileSelectDestinationVaultTitle;

  /// Subtitle showing a mounted vault's volume id in the destination picker
  ///
  /// In en, this message translates to:
  /// **'Volume ID: {volId}'**
  String keyfileVolumeIdLabel(Object volId);

  /// Snackbar shown after a keyfile is exported to device storage
  ///
  /// In en, this message translates to:
  /// **'Keyfile exported to {path}'**
  String keyfileExportSuccessMessage(Object path);

  /// Snackbar shown when exporting a keyfile to device storage fails
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String keyfileExportFailedMessage(Object error);

  /// Snackbar shown after a keyfile is written into a mounted vault
  ///
  /// In en, this message translates to:
  /// **'Keyfile saved to {vaultName}: {path}'**
  String keyfileSavedToVaultMessage(Object vaultName, Object path);

  /// Snackbar shown when writing a keyfile into a mounted vault fails
  ///
  /// In en, this message translates to:
  /// **'Failed to write keyfile to vault'**
  String get keyfileWriteFailedMessage;

  /// Snackbar shown when an exception is thrown while saving a keyfile to a vault
  ///
  /// In en, this message translates to:
  /// **'Error saving to vault: {error}'**
  String keyfileSaveErrorMessage(Object error);

  /// Label above the generated passphrase/password output
  ///
  /// In en, this message translates to:
  /// **'Generated Secret'**
  String get passphraseGeneratedSecretLabel;

  /// Tooltip for the icon button that copies the generated secret to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get copyToClipboardTooltip;

  /// Tooltip for the icon button that regenerates the passphrase/password
  ///
  /// In en, this message translates to:
  /// **'Generate New'**
  String get generateNewTooltip;

  /// Weakest qualitative password/passphrase strength rating
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get passphraseStrengthWeak;

  /// Second-lowest qualitative password/passphrase strength rating
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get passphraseStrengthGood;

  /// Second-highest qualitative password/passphrase strength rating
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get passphraseStrengthStrong;

  /// Highest qualitative password/passphrase strength rating
  ///
  /// In en, this message translates to:
  /// **'Unbreakable'**
  String get passphraseStrengthUnbreakable;

  /// Estimated brute-force crack time for a weak password/passphrase
  ///
  /// In en, this message translates to:
  /// **'< 1 second'**
  String get passphraseCrackTimeInstant;

  /// Estimated brute-force crack time for a good password/passphrase
  ///
  /// In en, this message translates to:
  /// **'A few days / months'**
  String get passphraseCrackTimeShort;

  /// Estimated brute-force crack time for a strong password/passphrase
  ///
  /// In en, this message translates to:
  /// **'Several centuries'**
  String get passphraseCrackTimeCenturies;

  /// Estimated brute-force crack time for an unbreakable password/passphrase
  ///
  /// In en, this message translates to:
  /// **'Millions of years'**
  String get passphraseCrackTimeMillionsOfYears;

  /// Label showing the qualitative strength rating of the generated passphrase
  ///
  /// In en, this message translates to:
  /// **'Strength: {label}'**
  String passphraseStrengthLabel(Object label);

  /// Label showing the entropy in bits of the generated passphrase
  ///
  /// In en, this message translates to:
  /// **'{bits} bits entropy'**
  String passphraseEntropyBitsLabel(Object bits);

  /// Label showing the estimated brute-force crack time of the generated passphrase
  ///
  /// In en, this message translates to:
  /// **'Estimated crack time: {crackTime}'**
  String passphraseCrackTimeLabel(Object crackTime);

  /// Section title for the EFF Diceware passphrase configuration card
  ///
  /// In en, this message translates to:
  /// **'EFF Diceware Options'**
  String get dicewareOptionsTitle;

  /// Label showing how many diceware words are currently configured
  ///
  /// In en, this message translates to:
  /// **'Word Count: {count} words'**
  String dicewareWordCountLabel(Object count);

  /// Label showing the approximate entropy in bits contributed by the diceware word count
  ///
  /// In en, this message translates to:
  /// **'{bits} bits'**
  String dicewareWordCountBitsLabel(Object bits);

  /// Compact slider thumb label for the diceware word count
  ///
  /// In en, this message translates to:
  /// **'{count} words'**
  String dicewareWordCountSliderLabel(Object count);

  /// Label for the diceware word separator dropdown
  ///
  /// In en, this message translates to:
  /// **'Word Separator'**
  String get dicewareWordSeparatorLabel;

  /// Diceware word separator option: a hyphen character
  ///
  /// In en, this message translates to:
  /// **'Hyphen ( - )'**
  String get dicewareSeparatorHyphen;

  /// Diceware word separator option: a space character
  ///
  /// In en, this message translates to:
  /// **'Space (   )'**
  String get dicewareSeparatorSpace;

  /// Diceware word separator option: an underscore character
  ///
  /// In en, this message translates to:
  /// **'Underscore ( _ )'**
  String get dicewareSeparatorUnderscore;

  /// Diceware word separator option: a dot character
  ///
  /// In en, this message translates to:
  /// **'Dot ( . )'**
  String get dicewareSeparatorDot;

  /// Diceware word separator option: a slash character
  ///
  /// In en, this message translates to:
  /// **'Slash ( / )'**
  String get dicewareSeparatorSlash;

  /// Label for the diceware word casing dropdown
  ///
  /// In en, this message translates to:
  /// **'Word Casing'**
  String get dicewareWordCasingLabel;

  /// Diceware word casing option: all lowercase
  ///
  /// In en, this message translates to:
  /// **'lowercase'**
  String get dicewareCasingLowercase;

  /// Diceware word casing option: Title Case
  ///
  /// In en, this message translates to:
  /// **'Title Case'**
  String get dicewareCasingTitleCase;

  /// Diceware word casing option: ALL UPPERCASE
  ///
  /// In en, this message translates to:
  /// **'UPPERCASE'**
  String get dicewareCasingUppercase;

  /// Switch label to append a random digit to the diceware passphrase
  ///
  /// In en, this message translates to:
  /// **'Append Random Digit (0-9)'**
  String get dicewareAppendDigitLabel;

  /// Switch label to append a random symbol to the diceware passphrase
  ///
  /// In en, this message translates to:
  /// **'Append Random Symbol (!@#\$%)'**
  String get dicewareAppendSymbolLabel;

  /// Section title for the custom random password configuration card
  ///
  /// In en, this message translates to:
  /// **'Custom Password Options'**
  String get customPasswordOptionsTitle;

  /// Label showing the configured length of the custom password
  ///
  /// In en, this message translates to:
  /// **'Length: {length} characters'**
  String customPasswordLengthLabel(Object length);

  /// Compact slider thumb label for the custom password length
  ///
  /// In en, this message translates to:
  /// **'{length} chars'**
  String customPasswordLengthSliderLabel(Object length);

  /// Switch label to include uppercase letters in the custom password
  ///
  /// In en, this message translates to:
  /// **'Uppercase Letters (A-Z)'**
  String get customPasswordUppercaseLabel;

  /// Switch label to include lowercase letters in the custom password
  ///
  /// In en, this message translates to:
  /// **'Lowercase Letters (a-z)'**
  String get customPasswordLowercaseLabel;

  /// Switch label to include numbers in the custom password
  ///
  /// In en, this message translates to:
  /// **'Numbers (0-9)'**
  String get customPasswordNumbersLabel;

  /// Switch label to include symbols in the custom password
  ///
  /// In en, this message translates to:
  /// **'Symbols (!@#\$%^&*)'**
  String get customPasswordSymbolsLabel;

  /// Switch label to exclude visually ambiguous characters from the custom password
  ///
  /// In en, this message translates to:
  /// **'Exclude Ambiguous (1, l, I, 0, O)'**
  String get customPasswordExcludeAmbiguousLabel;

  /// Section title for the binary keyfile size preset picker
  ///
  /// In en, this message translates to:
  /// **'Binary Keyfile Size'**
  String get keyfileBinarySizeTitle;

  /// Section title for the noise image keyfile resolution preset picker
  ///
  /// In en, this message translates to:
  /// **'Noise Image Resolution'**
  String get keyfileImageResolutionTitle;

  /// Binary keyfile size preset choice chip label
  ///
  /// In en, this message translates to:
  /// **'64 Bytes (VeraCrypt Standard)'**
  String get keyfilePresetBytes64;

  /// Binary keyfile size preset choice chip label
  ///
  /// In en, this message translates to:
  /// **'256 Bytes'**
  String get keyfilePresetBytes256;

  /// Binary keyfile size preset choice chip label
  ///
  /// In en, this message translates to:
  /// **'2 KB'**
  String get keyfilePresetBytes2048;

  /// Binary keyfile size preset choice chip label
  ///
  /// In en, this message translates to:
  /// **'64 KB'**
  String get keyfilePresetBytes64kb;

  /// Binary keyfile size preset choice chip label
  ///
  /// In en, this message translates to:
  /// **'1 MB (Max Boundary)'**
  String get keyfilePresetBytes1mb;

  /// Noise image keyfile resolution preset choice chip label
  ///
  /// In en, this message translates to:
  /// **'64 x 64 pixels (~16 KB)'**
  String get keyfilePresetRes64;

  /// Noise image keyfile resolution preset choice chip label
  ///
  /// In en, this message translates to:
  /// **'256 x 256 pixels (~256 KB)'**
  String get keyfilePresetRes256;

  /// Noise image keyfile resolution preset choice chip label
  ///
  /// In en, this message translates to:
  /// **'512 x 512 pixels (~1 MB)'**
  String get keyfilePresetRes512;

  /// Tooltip for the icon button that regenerates the keyfile
  ///
  /// In en, this message translates to:
  /// **'Generate New Keyfile'**
  String get keyfileGenerateNewTooltip;

  /// Label showing the size of the generated keyfile
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String keyfileSizeLabel(Object size);

  /// Label above the generated keyfile's SHA-256 fingerprint
  ///
  /// In en, this message translates to:
  /// **'SHA-256 Fingerprint'**
  String get keyfileFingerprintLabel;

  /// Tooltip for the icon button that copies the keyfile fingerprint to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy Fingerprint'**
  String get keyfileCopyFingerprintTooltip;

  /// Empty-state title when no vaults are mounted, shown on the Duplicate Finder screen
  ///
  /// In en, this message translates to:
  /// **'No Mounted Vaults'**
  String get duplicateFinderNoVaultsTitle;

  /// Empty-state message when no vaults are mounted, shown on the Duplicate Finder screen
  ///
  /// In en, this message translates to:
  /// **'Unlock and mount at least one vault container to scan for duplicate files.'**
  String get duplicateFinderNoVaultsMessage;

  /// Confirmation dialog body before permanently deleting selected duplicate files
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete {count} duplicate file(s) ({size}) from your vault(s)? This action cannot be undone.'**
  String duplicateFinderConfirmDeleteMessage(Object count, Object size);

  /// Destructive confirm button label in the delete-duplicates dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Permanently'**
  String get duplicateFinderDeletePermanentlyButton;

  /// Snackbar shown after duplicate files are successfully deleted
  ///
  /// In en, this message translates to:
  /// **'Successfully deleted {count} duplicate file(s).'**
  String duplicateFinderDeleteSuccessMessage(Object count);

  /// Title of the idle-state intro card explaining how the duplicate finder works
  ///
  /// In en, this message translates to:
  /// **'3-Stage Byte-Equal Finder'**
  String get duplicateFinderIntroTitle;

  /// Subtitle of the idle-state intro card explaining how the duplicate finder works
  ///
  /// In en, this message translates to:
  /// **'Detect exact identical content regardless of filenames.'**
  String get duplicateFinderIntroSubtitle;

  /// Bulleted description of the 3 scan stages shown on the idle card
  ///
  /// In en, this message translates to:
  /// **'• Stage 1: Size Grouping (Instant metadata walk)\n• Stage 2: Partial Header Check (16 KB SHA-256 header)\n• Stage 3: Full Hash Verification (Exact SHA-256 byte match)'**
  String get duplicateFinderStagesDescription;

  /// Fallback stage label shown while scanning if no more specific stage label applies
  ///
  /// In en, this message translates to:
  /// **'Scanning vault...'**
  String get duplicateFinderScanningVaultFallback;

  /// Label showing the name of the file currently being processed during a scan
  ///
  /// In en, this message translates to:
  /// **'Processing: {fileName}'**
  String duplicateFinderProcessingFileLabel(Object fileName);

  /// Label showing running scan statistics: files scanned, duplicate groups found, and space that could be saved
  ///
  /// In en, this message translates to:
  /// **'Files scanned: {scanned} | Duplicates found: {groups} groups ({saved})'**
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  );

  /// Summary card title showing how many duplicate groups were found
  ///
  /// In en, this message translates to:
  /// **'{count} Duplicate Groups Found'**
  String duplicateFinderGroupsFoundLabel(Object count);

  /// Summary card subtitle showing total duplicate copies and space that could be saved
  ///
  /// In en, this message translates to:
  /// **'{copies} copies found • Save {saved} storage space'**
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved);

  /// Subtitle on the target picker showing how many vaults are currently selected
  ///
  /// In en, this message translates to:
  /// **'{count} vaults selected'**
  String duplicateFinderVaultsSelectedLabel(Object count);

  /// Title of a single duplicate group's expansion tile: group number, size, and copy count
  ///
  /// In en, this message translates to:
  /// **'Group {groupIndex}: {size} ({count} copies found)'**
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  );

  /// Subtitle of a duplicate group's expansion tile showing recoverable disk space
  ///
  /// In en, this message translates to:
  /// **'Recoverable space: {size}'**
  String duplicateFinderRecoverableSpaceLabel(Object size);

  /// Tooltip for the icon button that opens a file preview from a duplicate group listing
  ///
  /// In en, this message translates to:
  /// **'Preview File'**
  String get duplicateFinderPreviewFileTooltip;

  /// Snackbar shown when no viewer is available to preview the selected duplicate file
  ///
  /// In en, this message translates to:
  /// **'Could not open file preview for {fileName}'**
  String duplicateFinderPreviewFailedMessage(Object fileName);

  /// Snackbar shown when an exception is thrown while opening a duplicate file preview
  ///
  /// In en, this message translates to:
  /// **'Error previewing file: {error}'**
  String duplicateFinderPreviewErrorMessage(Object error);

  /// Bottom action bar label showing how many duplicate files are currently selected for deletion
  ///
  /// In en, this message translates to:
  /// **'{count} files selected'**
  String duplicateFinderFilesSelectedLabel(Object count);

  /// Bottom action bar label showing how much space will be freed by the current selection
  ///
  /// In en, this message translates to:
  /// **'{size} to be freed'**
  String duplicateFinderBytesToBeFreedLabel(Object size);

  /// Bottom action bar button to delete the currently selected duplicate files, with a count
  ///
  /// In en, this message translates to:
  /// **'Delete Selected ({count})'**
  String duplicateFinderDeleteSelectedButton(Object count);

  /// Tooltip for the icon button that switches which mounted vault is being browsed
  ///
  /// In en, this message translates to:
  /// **'Switch Vault'**
  String get vaultBrowserSwitchVaultTooltip;

  /// Breadcrumb label shown when browsing a vault's root folder
  ///
  /// In en, this message translates to:
  /// **'Root Folder'**
  String get vaultBrowserRootFolderLabel;

  /// App bar title for the vault file picker, showing which vault is being browsed
  ///
  /// In en, this message translates to:
  /// **'Select Files ({vaultName})'**
  String vaultFilePickerTitle(Object vaultName);

  /// Message shown when the current vault folder has no files or subfolders
  ///
  /// In en, this message translates to:
  /// **'Folder is empty'**
  String get vaultFilePickerEmptyMessage;

  /// Confirm button label showing how many files are currently selected in the vault file picker
  ///
  /// In en, this message translates to:
  /// **'Select {count} File(s)'**
  String vaultFilePickerConfirmButton(Object count);

  /// App bar title for the vault folder picker, showing which vault is being browsed
  ///
  /// In en, this message translates to:
  /// **'Select Folder ({vaultName})'**
  String vaultFolderPickerTitle(Object vaultName);

  /// Message shown when the current vault folder has no subfolders
  ///
  /// In en, this message translates to:
  /// **'No subfolders here'**
  String get vaultFolderPickerEmptyMessage;

  /// Folder name used to represent a vault's root folder in the destination display name
  ///
  /// In en, this message translates to:
  /// **'Root'**
  String get vaultFolderPickerRootLabel;

  /// Confirm button label when the vault's root folder is the selected destination
  ///
  /// In en, this message translates to:
  /// **'Select Root Folder'**
  String get vaultFolderPickerConfirmRootButton;

  /// Confirm button label showing the name of the selected destination subfolder
  ///
  /// In en, this message translates to:
  /// **'Select \"{folderName}\"'**
  String vaultFolderPickerConfirmNamedButton(Object folderName);

  /// Bottom sheet title for choosing where to add Single File Crypto input files from
  ///
  /// In en, this message translates to:
  /// **'Select Input Files'**
  String get singleFileCryptoSelectInputTitle;

  /// Option to add Single File Crypto input files from device storage
  ///
  /// In en, this message translates to:
  /// **'From Device Storage'**
  String get singleFileCryptoFromDeviceTitle;

  /// Subtitle explaining the device-storage input option
  ///
  /// In en, this message translates to:
  /// **'Pick files from device using system file picker'**
  String get singleFileCryptoFromDeviceSubtitle;

  /// Option to add Single File Crypto input files from a mounted vault
  ///
  /// In en, this message translates to:
  /// **'From Mounted Vault'**
  String get singleFileCryptoFromVaultTitle;

  /// Subtitle explaining the mounted-vault input option
  ///
  /// In en, this message translates to:
  /// **'Pick files from an open encrypted container'**
  String get singleFileCryptoFromVaultSubtitle;

  /// Bottom sheet title for choosing the Single File Crypto output destination
  ///
  /// In en, this message translates to:
  /// **'Select Destination Folder'**
  String get singleFileCryptoSelectDestinationTitle;

  /// Option to save Single File Crypto output to device storage
  ///
  /// In en, this message translates to:
  /// **'Device Storage Folder'**
  String get singleFileCryptoDeviceFolderTitle;

  /// Subtitle explaining the device-storage destination option
  ///
  /// In en, this message translates to:
  /// **'Save output to a folder on device storage'**
  String get singleFileCryptoDeviceFolderSubtitle;

  /// Option to save Single File Crypto output inside a mounted vault
  ///
  /// In en, this message translates to:
  /// **'Mounted Vault Folder'**
  String get singleFileCryptoVaultFolderTitle;

  /// Subtitle explaining the mounted-vault destination option
  ///
  /// In en, this message translates to:
  /// **'Save output inside an open encrypted container'**
  String get singleFileCryptoVaultFolderSubtitle;

  /// Section header on the Tools screen grouping backup/sync tools
  ///
  /// In en, this message translates to:
  /// **'Backup & Sync'**
  String get toolsSectionBackupSync;

  /// Tool card title for the Vault-to-Vault Synchronizer / Diff tool
  ///
  /// In en, this message translates to:
  /// **'Vault Sync'**
  String get toolVaultSyncTitle;

  /// Tool card subtitle for the Vault-to-Vault Synchronizer / Diff tool
  ///
  /// In en, this message translates to:
  /// **'Compare two vaults and copy over what\'s missing or newer'**
  String get toolVaultSyncSubtitle;

  /// Empty state title shown in Vault Sync when no vaults are mounted
  ///
  /// In en, this message translates to:
  /// **'No Vaults Mounted'**
  String get vaultSyncNoVaultsTitle;

  /// Empty state message shown in Vault Sync when no vaults are mounted
  ///
  /// In en, this message translates to:
  /// **'Mount at least one vault to compare and sync its files.'**
  String get vaultSyncNoVaultsMessage;

  /// Label for the left side of a Vault Sync comparison
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get vaultSyncLeftLabel;

  /// Label for the right side of a Vault Sync comparison
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get vaultSyncRightLabel;

  /// Placeholder subtitle shown on a Vault Sync side picker before a location is chosen
  ///
  /// In en, this message translates to:
  /// **'Tap to select a vault & folder'**
  String get vaultSyncTapToSelect;

  /// Tooltip for the button that swaps the Left and Right sides in Vault Sync
  ///
  /// In en, this message translates to:
  /// **'Swap Left and Right'**
  String get vaultSyncSwapTooltip;

  /// Warning shown when Left and Right are set to the exact same vault and folder
  ///
  /// In en, this message translates to:
  /// **'Left and Right must be different folders.'**
  String get vaultSyncSameLocationWarning;

  /// Title of the idle-state intro card in Vault Sync before a comparison has run
  ///
  /// In en, this message translates to:
  /// **'Compare Two Vaults'**
  String get vaultSyncIntroTitle;

  /// Subtitle of the idle-state intro card in Vault Sync before a comparison has run
  ///
  /// In en, this message translates to:
  /// **'Pick a Left and Right vault (or two folders in the same vault) to see what\'s missing, modified, or newer on each side.'**
  String get vaultSyncIntroSubtitle;

  /// Button label to start comparing the two selected vault locations
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get vaultSyncCompareButton;

  /// Progress label shown while Vault Sync is walking both sides
  ///
  /// In en, this message translates to:
  /// **'Comparing vaults…'**
  String get vaultSyncComparingLabel;

  /// Live stats shown under the progress bar while comparing
  ///
  /// In en, this message translates to:
  /// **'Folders scanned: {dirs} | Differences found: {entries}'**
  String vaultSyncCompareStatsLabel(Object dirs, Object entries);

  /// Button to cancel an in-progress Vault Sync comparison
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get vaultSyncCancelCompareButton;

  /// Empty state title shown when a comparison finds no differences
  ///
  /// In en, this message translates to:
  /// **'Already in Sync'**
  String get vaultSyncInSyncTitle;

  /// Empty state message shown when a comparison finds no differences
  ///
  /// In en, this message translates to:
  /// **'All {count} matching files are identical on both sides.'**
  String vaultSyncInSyncMessage(num count);

  /// Button to re-run a Vault Sync comparison
  ///
  /// In en, this message translates to:
  /// **'Compare Again'**
  String get vaultSyncRecompareButton;

  /// Summary card title showing how many differing paths were found
  ///
  /// In en, this message translates to:
  /// **'{count} Differences Found'**
  String vaultSyncDifferencesFoundLabel(num count);

  /// Summary card subtitle showing how many files were already identical
  ///
  /// In en, this message translates to:
  /// **'{count} files already match on both sides'**
  String vaultSyncInSyncCountLabel(num count);

  /// Summary badge counting entries that exist only on the Left side
  ///
  /// In en, this message translates to:
  /// **'{count} only on Left'**
  String vaultSyncBadgeOnlyLeft(Object count);

  /// Summary badge counting entries that exist only on the Right side
  ///
  /// In en, this message translates to:
  /// **'{count} only on Right'**
  String vaultSyncBadgeOnlyRight(Object count);

  /// Summary badge counting entries where the Left copy is newer
  ///
  /// In en, this message translates to:
  /// **'{count} newer on Left'**
  String vaultSyncBadgeLeftNewer(Object count);

  /// Summary badge counting entries where the Right copy is newer
  ///
  /// In en, this message translates to:
  /// **'{count} newer on Right'**
  String vaultSyncBadgeRightNewer(Object count);

  /// Summary badge counting entries that can't be resolved automatically
  ///
  /// In en, this message translates to:
  /// **'{count} need review'**
  String vaultSyncBadgeConflicts(num count);

  /// Label for the sync direction option picker
  ///
  /// In en, this message translates to:
  /// **'Sync Direction'**
  String get vaultSyncDirectionLabel;

  /// Sync direction option: copy newer/missing files in both directions
  ///
  /// In en, this message translates to:
  /// **'Two-way (recommended)'**
  String get vaultSyncDirectionTwoWay;

  /// Explanation of the two-way sync direction option
  ///
  /// In en, this message translates to:
  /// **'Copies each file to whichever side is missing it or has an older copy'**
  String get vaultSyncDirectionTwoWaySubtitle;

  /// Sync direction option: only push Left's changes to Right
  ///
  /// In en, this message translates to:
  /// **'Left → Right (one-way)'**
  String get vaultSyncDirectionLeftToRight;

  /// Explanation of the Left-to-Right one-way sync direction option
  ///
  /// In en, this message translates to:
  /// **'Pushes new and updated files from Left to Right; never changes Left'**
  String get vaultSyncDirectionLeftToRightSubtitle;

  /// Sync direction option: only push Right's changes to Left
  ///
  /// In en, this message translates to:
  /// **'Right → Left (one-way)'**
  String get vaultSyncDirectionRightToLeft;

  /// Explanation of the Right-to-Left one-way sync direction option
  ///
  /// In en, this message translates to:
  /// **'Pushes new and updated files from Right to Left; never changes Right'**
  String get vaultSyncDirectionRightToLeftSubtitle;

  /// Hint text for the search field filtering the Vault Sync diff list
  ///
  /// In en, this message translates to:
  /// **'Search differences'**
  String get vaultSyncSearchHint;

  /// Status badge for an entry that exists only on the Left side
  ///
  /// In en, this message translates to:
  /// **'Only Left'**
  String get vaultSyncStatusOnlyLeft;

  /// Status badge for an entry that exists only on the Right side
  ///
  /// In en, this message translates to:
  /// **'Only Right'**
  String get vaultSyncStatusOnlyRight;

  /// Status badge for an entry where the Left copy is newer
  ///
  /// In en, this message translates to:
  /// **'Left Newer'**
  String get vaultSyncStatusLeftNewer;

  /// Status badge for an entry where the Right copy is newer
  ///
  /// In en, this message translates to:
  /// **'Right Newer'**
  String get vaultSyncStatusRightNewer;

  /// Status badge for an entry with ambiguous same-time, different-size copies
  ///
  /// In en, this message translates to:
  /// **'Needs Review'**
  String get vaultSyncStatusConflict;

  /// Status badge for an entry that's a file on one side and a folder on the other
  ///
  /// In en, this message translates to:
  /// **'Type Mismatch'**
  String get vaultSyncStatusTypeMismatch;

  /// Detail line for a whole folder that exists only on the Left side
  ///
  /// In en, this message translates to:
  /// **'Folder — only on Left'**
  String get vaultSyncFolderOnlyLeftDetail;

  /// Detail line for a whole folder that exists only on the Right side
  ///
  /// In en, this message translates to:
  /// **'Folder — only on Right'**
  String get vaultSyncFolderOnlyRightDetail;

  /// Detail line comparing size and modified date on both sides for a modified/conflicted file
  ///
  /// In en, this message translates to:
  /// **'L: {leftSize} · {leftDate}  →  R: {rightSize} · {rightDate}'**
  String vaultSyncBothSidesDetail(
    Object leftSize,
    Object leftDate,
    Object rightSize,
    Object rightDate,
  );

  /// Tooltip explaining why a type-mismatch entry can't be synced automatically
  ///
  /// In en, this message translates to:
  /// **'A file on one side and a folder on the other — resolve manually in the file browser'**
  String get vaultSyncTypeMismatchTooltip;

  /// Tooltip on the per-entry action button in the Vault Sync diff list
  ///
  /// In en, this message translates to:
  /// **'Change sync action'**
  String get vaultSyncChangeActionTooltip;

  /// Per-entry action: copy this entry from Left to Right
  ///
  /// In en, this message translates to:
  /// **'Copy → Right'**
  String get vaultSyncActionCopyToRight;

  /// Per-entry action: copy this entry from Right to Left
  ///
  /// In en, this message translates to:
  /// **'Copy → Left'**
  String get vaultSyncActionCopyToLeft;

  /// Per-entry action: leave this entry untouched
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get vaultSyncActionSkip;

  /// Bottom action bar label showing how many changes are queued to sync
  ///
  /// In en, this message translates to:
  /// **'{count} changes queued'**
  String vaultSyncChangesQueuedLabel(num count);

  /// Button to start applying the current Vault Sync plan
  ///
  /// In en, this message translates to:
  /// **'Sync Now'**
  String get vaultSyncSyncNowButton;

  /// Confirmation dialog title before starting a Vault Sync run
  ///
  /// In en, this message translates to:
  /// **'Start Sync?'**
  String get vaultSyncConfirmTitle;

  /// Confirmation dialog message before starting a Vault Sync run
  ///
  /// In en, this message translates to:
  /// **'This will copy {count} items ({bytes} total) between the two sides. Existing files with the same name will be overwritten.'**
  String vaultSyncConfirmMessage(num count, Object bytes);

  /// Snackbar shown after enqueueing Vault Sync copy operations
  ///
  /// In en, this message translates to:
  /// **'Sync started — {count} items queued'**
  String vaultSyncStartedMessage(num count);

  /// App bar title on the Vault Sync location picker sheet, naming which side is being picked
  ///
  /// In en, this message translates to:
  /// **'Select {side} Vault & Folder'**
  String vaultSyncPickLocationTitle(Object side);

  /// Short badge shown next to a Vault Sync side that's mounted read-only
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get vaultSyncReadOnlyBadge;

  /// Tooltip explaining the read-only badge on a Vault Sync side
  ///
  /// In en, this message translates to:
  /// **'This vault is mounted read-only — files can\'t be copied into it'**
  String get vaultSyncReadOnlyTooltip;

  /// Sync Now button label while a sync run is in progress
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get vaultSyncSyncingButton;

  /// Title of the blocking dialog shown when a Vault Sync destination doesn't have enough free space
  ///
  /// In en, this message translates to:
  /// **'Not Enough Space'**
  String get vaultSyncNotEnoughSpaceTitle;

  /// Message shown per side when a Vault Sync destination doesn't have enough free space
  ///
  /// In en, this message translates to:
  /// **'Not enough space on {side} — needs {required}, only {free} free.'**
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  );

  /// Title of the dialog shown when removing the master password
  ///
  /// In en, this message translates to:
  /// **'Remove Master Password'**
  String get removeMasterPasswordTitle;

  /// Prompt message when removing master password
  ///
  /// In en, this message translates to:
  /// **'Enter your current Master Password to confirm removal:'**
  String get confirmRemoveMasterPasswordMessage;

  /// Biometric prompt reason when removing master password
  ///
  /// In en, this message translates to:
  /// **'Authenticate to remove Master Password'**
  String get authenticateToRemoveMasterPassword;

  /// Error message when entering an incorrect password
  ///
  /// In en, this message translates to:
  /// **'Incorrect password'**
  String get incorrectPassword;

  /// Toggle label for remembering layout mode per folder
  ///
  /// In en, this message translates to:
  /// **'Remember Per-Folder Layout'**
  String get rememberPerFolderLayoutLabel;

  /// Toggle description for remembering layout mode per folder
  ///
  /// In en, this message translates to:
  /// **'Save separate view layout (list, grid, masonry) for each folder'**
  String get rememberPerFolderLayoutDesc;

  /// Menu item label to view metadata, EXIF, and details of the selected file
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get fileInfoAction;

  /// App bar title for the per-vault automation settings screen
  ///
  /// In en, this message translates to:
  /// **'Automation (Tasker / MacroDroid)'**
  String get automationScreenTitle;

  /// Shown instead of automation settings when the vault is USB-attached
  ///
  /// In en, this message translates to:
  /// **'Automation isn\'t available yet for USB-attached vaults.'**
  String get automationUsbUnsupportedMessage;

  /// Section header above the automation access picker for the current vault
  ///
  /// In en, this message translates to:
  /// **'This vault'**
  String get automationThisVaultSectionHeader;

  /// Label for the picker choosing this vault's automation tier (none/lifecycle/full)
  ///
  /// In en, this message translates to:
  /// **'Automation access'**
  String get automationAccessLabel;

  /// Section header above the stored automation password field
  ///
  /// In en, this message translates to:
  /// **'Automation password'**
  String get automationPasswordSectionHeader;

  /// Explanation shown when a stored automation password already exists
  ///
  /// In en, this message translates to:
  /// **'A password is stored for unattended UNLOCK_VAULT calls. Save a new one to replace it, or save an empty field to clear it — automation can also supply a password directly in the broadcast instead of relying on this.'**
  String get automationPasswordStoredHint;

  /// Explanation shown when no automation password is stored yet
  ///
  /// In en, this message translates to:
  /// **'Optional. Without a stored password, automation must supply one with every UNLOCK_VAULT broadcast.'**
  String get automationPasswordNotStoredHint;

  /// Text field label when replacing an already-stored automation password
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get automationNewPasswordFieldLabel;

  /// Text field label when no automation password is stored yet
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get automationPasswordFieldLabel;

  /// Button that clears the stored automation password by saving an empty value
  ///
  /// In en, this message translates to:
  /// **'Clear stored password'**
  String get automationClearPasswordButton;

  /// Button that saves the entered automation password
  ///
  /// In en, this message translates to:
  /// **'Save password'**
  String get automationSavePasswordButton;

  /// Section header above the shared automation API token
  ///
  /// In en, this message translates to:
  /// **'API token'**
  String get automationTokenSectionHeader;

  /// Explanation of how the shared automation API token is used
  ///
  /// In en, this message translates to:
  /// **'Shared by every vault with automation access enabled. Automation sends this back on every broadcast; a wrong or missing token gets silently ignored, not an error.'**
  String get automationTokenDescription;

  /// Button that regenerates the automation API token
  ///
  /// In en, this message translates to:
  /// **'Regenerate token'**
  String get automationRegenerateTokenButton;

  /// Confirmation dialog title before regenerating the automation API token
  ///
  /// In en, this message translates to:
  /// **'Regenerate token?'**
  String get automationRegenerateTokenDialogTitle;

  /// Confirmation dialog message before regenerating the automation API token
  ///
  /// In en, this message translates to:
  /// **'Any Tasker profile or MacroDroid macro using the current token will stop working silently until you update it with the new one.'**
  String get automationRegenerateTokenDialogMessage;

  /// Confirm button label on the regenerate-token dialog
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get automationRegenerateConfirmLabel;

  /// Snackbar shown after the automation API token is regenerated
  ///
  /// In en, this message translates to:
  /// **'Token regenerated.'**
  String get automationTokenRegeneratedMessage;

  /// Snackbar shown when regenerating the automation API token fails
  ///
  /// In en, this message translates to:
  /// **'Could not regenerate the token.'**
  String get automationRegenerateTokenFailedMessage;

  /// Snackbar shown when changing this vault's automation tier fails
  ///
  /// In en, this message translates to:
  /// **'Could not update automation settings.'**
  String get automationUpdateSettingsFailedMessage;

  /// Snackbar shown when saving the automation password fails
  ///
  /// In en, this message translates to:
  /// **'Could not save the automation password.'**
  String get automationSavePasswordFailedMessage;

  /// Snackbar shown after clearing the stored automation password
  ///
  /// In en, this message translates to:
  /// **'Automation password cleared.'**
  String get automationPasswordClearedMessage;

  /// Snackbar shown after saving a new automation password
  ///
  /// In en, this message translates to:
  /// **'Automation password saved.'**
  String get automationPasswordSavedMessage;

  /// Section header above the copyable Tasker/MacroDroid configuration values
  ///
  /// In en, this message translates to:
  /// **'Configuration strings'**
  String get automationConfigSectionHeader;

  /// Explanatory note above the copyable automation configuration strings, including the Broadcast-vs-Activity troubleshooting tip
  ///
  /// In en, this message translates to:
  /// **'Tap any value below to copy it. In Tasker, use a \"Send Intent\" action; in MacroDroid, use an \"Intent\" action with Intent Type set to Broadcast — not Activity or Service, which fails with \"unable to find explicit activity class\".'**
  String get automationConfigIntro;

  /// Row label for the copyable app package name
  ///
  /// In en, this message translates to:
  /// **'Package name'**
  String get automationConfigPackageLabel;

  /// Row label for the copyable fully-qualified receiver class name
  ///
  /// In en, this message translates to:
  /// **'Receiver class'**
  String get automationConfigClassLabel;

  /// Row label for the copyable vault_uri extra value for this specific vault
  ///
  /// In en, this message translates to:
  /// **'This vault\'s URI'**
  String get automationConfigVaultUriLabel;

  /// Section header above the list of copyable automation broadcast action strings
  ///
  /// In en, this message translates to:
  /// **'Broadcast actions'**
  String get automationConfigActionsSectionHeader;

  /// Row label for the copyable UNLOCK_VAULT action string
  ///
  /// In en, this message translates to:
  /// **'Unlock vault'**
  String get automationActionUnlockLabel;

  /// Row label for the copyable LOCK_VAULT action string
  ///
  /// In en, this message translates to:
  /// **'Lock vault'**
  String get automationActionLockLabel;

  /// Row label for the copyable IMPORT_FILE action string
  ///
  /// In en, this message translates to:
  /// **'Import file'**
  String get automationActionImportLabel;

  /// Row label for the copyable EXPORT_FILE action string
  ///
  /// In en, this message translates to:
  /// **'Export file'**
  String get automationActionExportLabel;

  /// Row label for the copyable WIPE_FILE action string
  ///
  /// In en, this message translates to:
  /// **'Wipe file'**
  String get automationActionWipeLabel;

  /// Closing footnote pointing to the source doc comment for the full extras contract
  ///
  /// In en, this message translates to:
  /// **'Full extras and the result-broadcast contract are documented in VaultAutomationReceiver.kt.'**
  String get automationDocCommentFootnote;

  /// Automation tier picker option: automation disabled for this vault
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get automationTierOffLabel;

  /// Subtitle for the Off automation tier option
  ///
  /// In en, this message translates to:
  /// **'Automation cannot touch this vault'**
  String get automationTierOffSubtitle;

  /// Automation tier picker option: unlock/lock only
  ///
  /// In en, this message translates to:
  /// **'Unlock / lock only'**
  String get automationTierLifecycleLabel;

  /// Subtitle for the lifecycle-only automation tier option
  ///
  /// In en, this message translates to:
  /// **'Automation may unlock and lock this vault, nothing else'**
  String get automationTierLifecycleSubtitle;

  /// Automation tier picker option: unlock/lock plus file import-export
  ///
  /// In en, this message translates to:
  /// **'Unlock / lock + file import-export'**
  String get automationTierFullLabel;

  /// Subtitle for the full automation tier option
  ///
  /// In en, this message translates to:
  /// **'Automation may also import and export files while this vault is unlocked'**
  String get automationTierFullSubtitle;

  /// Tappable link on the Automation settings screen that opens the in-app automation tutorial
  ///
  /// In en, this message translates to:
  /// **'Read the full step-by-step tutorial'**
  String get automationTutorialLinkLabel;

  /// Toggle label for showing hidden files and folders
  ///
  /// In en, this message translates to:
  /// **'Show Hidden Files'**
  String get showHiddenFilesLabel;

  /// Toggle description for showing hidden files and folders
  ///
  /// In en, this message translates to:
  /// **'Display dotfiles and system folders'**
  String get showHiddenFilesDesc;

  /// Checkbox label to remember choice and not prompt again
  ///
  /// In en, this message translates to:
  /// **'Don\'t ask again'**
  String get dontAskAgain;

  /// Settings picker label for deleting original files after import
  ///
  /// In en, this message translates to:
  /// **'Delete files after import'**
  String get deleteAfterImportLabel;

  /// Delete after import mode: prompt the user each time
  ///
  /// In en, this message translates to:
  /// **'Ask every time'**
  String get deleteAfterImportModeAsk;

  /// Subtitle for the 'Ask every time' delete after import mode
  ///
  /// In en, this message translates to:
  /// **'Prompt whether to delete original files after importing'**
  String get deleteAfterImportModeAskSubtitle;

  /// Delete after import mode: always keep original files and never delete
  ///
  /// In en, this message translates to:
  /// **'Keep originals (do not delete)'**
  String get deleteAfterImportModeKeep;

  /// Subtitle for the 'Keep originals' delete after import mode
  ///
  /// In en, this message translates to:
  /// **'Never delete original files and do not ask'**
  String get deleteAfterImportModeKeepSubtitle;

  /// Delete after import mode: automatically delete original files without asking
  ///
  /// In en, this message translates to:
  /// **'Delete originals automatically'**
  String get deleteAfterImportModeDelete;

  /// Subtitle for the 'Delete originals automatically' delete after import mode
  ///
  /// In en, this message translates to:
  /// **'Automatically delete original files from device after import'**
  String get deleteAfterImportModeDeleteSubtitle;

  /// Bottom navigation bar button in a creation wizard: step back to the previous step
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get wizardBackButton;

  /// Bottom navigation bar button in a creation wizard: advance to the next step
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get wizardNextButton;

  /// Short step title/progress-indicator label for a creation wizard's Category/Type Selection step
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get wizardStepTypeTitle;

  /// Short step title/progress-indicator label for a creation wizard's Basic Configuration step
  ///
  /// In en, this message translates to:
  /// **'Basic Info'**
  String get wizardStepBasicInfoTitle;

  /// Short step title/progress-indicator label for a creation wizard's Advanced/Optional Features step
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get wizardStepAdvancedTitle;

  /// Short step title/progress-indicator label for a creation wizard's Review & Confirm step
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get wizardStepReviewTitle;

  /// Prompt above the visual selection cards on the container/vault creation wizard's first step
  ///
  /// In en, this message translates to:
  /// **'What would you like to create?'**
  String get wizardCreateTypePrompt;

  /// Prompt above the visual format selection cards on the USB formatting wizard's first step
  ///
  /// In en, this message translates to:
  /// **'Choose a container format'**
  String get wizardChooseFormatPrompt;

  /// Row title for the tile that opens the Advanced Parameters / cipher settings modal bottom sheet on a creation wizard's Advanced step
  ///
  /// In en, this message translates to:
  /// **'Encryption Details'**
  String get wizardEncryptionDetailsRowTitle;

  /// Subtitle shown under the hidden-volume details row once the toggle is on and its modal sheet has been opened
  ///
  /// In en, this message translates to:
  /// **'Configured — tap to review'**
  String get wizardHiddenVolumeRowSubtitleConfigured;

  /// Subtitle shown under the hidden-volume details row once the toggle is on but its modal sheet hasn't been opened yet
  ///
  /// In en, this message translates to:
  /// **'Tap to set up'**
  String get wizardHiddenVolumeRowSubtitleNeedsSetup;

  /// Heading above the summary card on a creation wizard's Review & Confirm step
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get wizardSummaryTitle;

  /// Row label for the password row in a creation wizard's Review & Confirm summary card
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get wizardSummaryPasswordLabel;

  /// Value shown in the Review summary card's password row when a password was entered
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get wizardPasswordSetValue;

  /// Value shown in the Review summary card's password row when no password was entered (keyfiles only)
  ///
  /// In en, this message translates to:
  /// **'Not set (using keyfiles)'**
  String get wizardPasswordNotSetValue;

  /// Row label for the keyfiles row in a creation wizard's Review & Confirm summary card
  ///
  /// In en, this message translates to:
  /// **'Keyfiles'**
  String get wizardSummaryKeyfilesLabel;

  /// Value shown in the Review summary card's PIM row when the field was left blank
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get wizardSummaryPimDefaultValue;

  /// Row label for the PIM row in a creation wizard's Review & Confirm summary card
  ///
  /// In en, this message translates to:
  /// **'PIM'**
  String get wizardSummaryPimLabel;

  /// Row label for the selected USB drive in the USB formatting wizard's Review & Confirm summary card
  ///
  /// In en, this message translates to:
  /// **'USB Drive'**
  String get wizardSummaryDriveLabel;

  /// Settings section header for background services, keystore caching, fast storage, and file provider
  ///
  /// In en, this message translates to:
  /// **'Key Storage & System Access'**
  String get sectionKeyStorageIntegration;

  /// Settings section header for decoy disguise mode
  ///
  /// In en, this message translates to:
  /// **'Mask Mode'**
  String get sectionMaskMode;

  /// Title for the collapsible advanced options card in the unlock sheet
  ///
  /// In en, this message translates to:
  /// **'Advanced Options'**
  String get advancedOptionsTitle;

  /// Title for audio track settings and headers
  ///
  /// In en, this message translates to:
  /// **'Audio Track'**
  String get audioTrackTitle;

  /// Message displayed when no audio tracks are found
  ///
  /// In en, this message translates to:
  /// **'No audio tracks available'**
  String get noAudioTracksAvailable;

  /// Fallback label for audio track with track number
  ///
  /// In en, this message translates to:
  /// **'Track {number}'**
  String trackNumberLabel(int number);

  /// Fallback label for subtitle track with track number
  ///
  /// In en, this message translates to:
  /// **'Subtitle {number}'**
  String subtitleTrackNumberLabel(int number);

  /// Label indicating a feature or track is turned off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get offLabel;

  /// Label for external subtitle files
  ///
  /// In en, this message translates to:
  /// **'External Subtitles (.srt/.vtt)'**
  String get externalSubtitlesLabel;

  /// Short label indicating external subtitles are active
  ///
  /// In en, this message translates to:
  /// **'External'**
  String get externalLabel;

  /// Label for subtitle font size selector
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get subtitleSizeLabel;

  /// Small subtitle size label
  ///
  /// In en, this message translates to:
  /// **'S'**
  String get subtitleSizeSmall;

  /// Medium subtitle size label
  ///
  /// In en, this message translates to:
  /// **'M'**
  String get subtitleSizeMedium;

  /// Large subtitle size label
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get subtitleSizeLarge;

  /// Extra large subtitle size label
  ///
  /// In en, this message translates to:
  /// **'XL'**
  String get subtitleSizeExtraLarge;

  /// Label for subtitle vertical position selector
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get subtitlePositionLabel;

  /// Bottom position preset for subtitles
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get subtitlePositionBottom;

  /// Lower-third position preset for subtitles
  ///
  /// In en, this message translates to:
  /// **'Lower'**
  String get subtitlePositionLower;

  /// Center position preset for subtitles
  ///
  /// In en, this message translates to:
  /// **'Center'**
  String get subtitlePositionCenter;

  /// Top position preset for subtitles
  ///
  /// In en, this message translates to:
  /// **'Top'**
  String get subtitlePositionTop;

  /// Menu action to open the in-app image editor for the selected image
  ///
  /// In en, this message translates to:
  /// **'Edit Image'**
  String get editImageAction;

  /// Shown in the image editor when the source image can't be decoded for editing
  ///
  /// In en, this message translates to:
  /// **'This image format isn\'t supported for editing.'**
  String get imageEditorUnsupportedFormatMessage;

  /// Image editor toolbar button: crop tool
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get cropToolLabel;

  /// Image editor toolbar button: freehand drawing tool
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get drawToolLabel;

  /// Image editor toolbar button: add text annotation tool
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textToolLabel;

  /// Image editor toolbar button: blackout/redaction box tool, for hiding sensitive info
  ///
  /// In en, this message translates to:
  /// **'Redact'**
  String get redactToolLabel;

  /// Image editor tooltip: rotate the working image 90 degrees counter-clockwise
  ///
  /// In en, this message translates to:
  /// **'Rotate left'**
  String get rotateLeftTooltip;

  /// Image editor tooltip: rotate the working image 90 degrees clockwise
  ///
  /// In en, this message translates to:
  /// **'Rotate right'**
  String get rotateRightTooltip;

  /// Crop aspect-ratio preset: unconstrained/free-form crop
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get cropAspectFreeLabel;

  /// Crop aspect-ratio preset: 1:1 square crop
  ///
  /// In en, this message translates to:
  /// **'Square'**
  String get cropAspectSquareLabel;

  /// Crop aspect-ratio preset: matches the current working image's own aspect ratio
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get cropAspectOriginalLabel;

  /// Image editor tooltip: commit the current crop rectangle into the working image
  ///
  /// In en, this message translates to:
  /// **'Apply crop'**
  String get applyCropTooltip;

  /// Image editor tooltip: choose the color for the current drawing/redaction tool
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get annotationColorTooltip;

  /// Image editor tooltip: choose the pen/redaction stroke width
  ///
  /// In en, this message translates to:
  /// **'Stroke width'**
  String get annotationStrokeWidthTooltip;

  /// Image editor tooltip: remove every pen stroke, text label, and redaction box added this session
  ///
  /// In en, this message translates to:
  /// **'Clear all annotations'**
  String get clearAnnotationsTooltip;

  /// Image editor tooltip: discard every edit and reload the original image
  ///
  /// In en, this message translates to:
  /// **'Reset to original'**
  String get resetImageTooltip;

  /// Confirmation dialog title before discarding all image editor changes
  ///
  /// In en, this message translates to:
  /// **'Reset image?'**
  String get resetImageConfirmTitle;

  /// Confirmation dialog message before discarding all image editor changes
  ///
  /// In en, this message translates to:
  /// **'This discards every crop and drawing change made in this session.'**
  String get resetImageConfirmMessage;

  /// Dialog title when placing a text annotation on the image
  ///
  /// In en, this message translates to:
  /// **'Add text'**
  String get addTextAnnotationTitle;

  /// Placeholder hint text in the add-text-annotation input field
  ///
  /// In en, this message translates to:
  /// **'Type something…'**
  String get addTextAnnotationHint;

  /// Hint shown above the toolbar in the image editor while the text tool is active
  ///
  /// In en, this message translates to:
  /// **'Tap the image to add text'**
  String get textToolHint;

  /// Title of the bottom sheet offering how to save image editor changes
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveImageSheetTitle;

  /// Save-sheet option: write the edited image to a new file, keeping the original
  ///
  /// In en, this message translates to:
  /// **'Save as new file'**
  String get saveAsNewFileOption;

  /// Subtitle explaining the save-as-new-file option
  ///
  /// In en, this message translates to:
  /// **'Keeps the original untouched'**
  String get saveAsNewFileDescription;

  /// Save-sheet option: replace the original file's bytes with the edited image
  ///
  /// In en, this message translates to:
  /// **'Overwrite original'**
  String get overwriteOriginalOption;

  /// Subtitle explaining the overwrite-original option
  ///
  /// In en, this message translates to:
  /// **'Replaces the original file'**
  String get overwriteOriginalDescription;

  /// Text field label for the new file name when saving an edited image as a copy
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get newFileNameLabel;

  /// Note shown in the save sheet explaining the output format, since there's no in-app JPEG encoder
  ///
  /// In en, this message translates to:
  /// **'Edited images are saved as PNG.'**
  String get imageEditorPngNoteMessage;

  /// Snackbar message after successfully saving an edited image
  ///
  /// In en, this message translates to:
  /// **'Image saved'**
  String get imageSavedMessage;

  /// Snackbar message when saving an edited image fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save image: {error}'**
  String imageSaveFailedMessage(String error);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'de',
    'en',
    'es',
    'fr',
    'it',
    'ja',
    'ko',
    'pt',
    'uk',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'pt':
      return AppLocalizationsPt();
    case 'uk':
      return AppLocalizationsUk();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
