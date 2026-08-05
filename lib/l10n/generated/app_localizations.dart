import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

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
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

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
  /// **'{verb} {count, plural, =1{1 item} other{# items}}'**
  String clipboardHeaderCount(String verb, num count);

  /// Overflow indicator when more clipboard items exist than shown in the preview
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{+1 more item} other{+# more items}}'**
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
  /// **'{verb} {count, plural, =1{1 item} other{# items}}'**
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
  /// **'{count, plural, =1{1 transfer} other{# transfers}}'**
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

  /// Confirmation dialog title for deleting one or more items
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete 1 item?} other{Delete # items?}}'**
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
  /// **'{count, plural, =1{Rename 1 item} other{Rename # items}}'**
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
  /// **'{count, plural, =1{Couldn\'t rename 1 item: {reason}} other{Couldn\'t rename # items: {reason}}}'**
  String couldntRenameMultiWithReason(num count, String reason);

  /// Error shown when one or more items fail to rename in a batch, without a specific reason
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Couldn\'t rename 1 item} other{Couldn\'t rename # items}}'**
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

  /// Tooltip for the star/favourite toggle when the item is currently a favourite
  ///
  /// In en, this message translates to:
  /// **'Remove from favourites'**
  String get removeFromFavourites;

  /// Tooltip for the star/favourite toggle when the item is not currently a favourite
  ///
  /// In en, this message translates to:
  /// **'Add to favourites'**
  String get addToFavourites;

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
  /// **'Hydro Tracker'**
  String get appNameHydroTracker;

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

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Biometric Unlock'**
  String get biometricUnlockTitle;

  /// Settings toggle subtitle
  ///
  /// In en, this message translates to:
  /// **'Use fingerprint or face recognition'**
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
  /// **'{count, plural, =1{1 minute} other{# minutes}}'**
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
  /// **'Mask Mode'**
  String get discreteModeTitle;

  /// Settings toggle subtitle when Discrete Mode is on
  ///
  /// In en, this message translates to:
  /// **'Active — the app currently appears as \"Hydro Tracker\"'**
  String get discreteModeActiveSubtitle;

  /// Settings toggle subtitle when Discrete Mode is off
  ///
  /// In en, this message translates to:
  /// **'Disguise this app as a daily water tracker on the home screen'**
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
  /// **'The app icon and name on your home screen will change to \"Hydro Tracker\". It will function as a daily water intake tracker.\n\nTo access your vault, open Hydro Tracker and hold your finger on the title or water gauge for 3 seconds.'**
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
  /// **'Reveal Edit on left and Delete on right when swiping cards'**
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

  /// Button label to open the system settings app
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// Settings toggle title
  ///
  /// In en, this message translates to:
  /// **'Android File Provider (default)'**
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
  /// **'Too many failed attempts. Try again in {seconds, plural, =1{1 second} other{# seconds}}.'**
  String tooManyFailedAttempts(num seconds);

  /// Validation error when submitting the lock screen with an empty password field
  ///
  /// In en, this message translates to:
  /// **'Enter your master password'**
  String get enterMasterPasswordPrompt;

  /// Error shown when a failed attempt triggers a new lockout
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Locked for {seconds}s due to {attempts, plural, =1{1 failed attempt} other{# failed attempts}}.'**
  String incorrectPasswordLockedFor(int seconds, num attempts);

  /// Error shown after a failed attempt that doesn't (yet) trigger a lockout
  ///
  /// In en, this message translates to:
  /// **'Incorrect password ({attempts, plural, =1{1 failed attempt} other{# failed attempts}}).'**
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

  /// Title shown during the first step of pattern lock setup
  ///
  /// In en, this message translates to:
  /// **'Draw your unlock pattern'**
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

  /// Bottom sheet title for the add-vault options
  ///
  /// In en, this message translates to:
  /// **'Add a vault'**
  String get addAVaultTitle;

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

  /// Snackbar shown when the user's water intake crosses the daily goal
  ///
  /// In en, this message translates to:
  /// **'🎉 Daily hydration goal reached! Streak increased!'**
  String get goalReachedSnack;

  /// Dialog title for manually logging a custom water amount
  ///
  /// In en, this message translates to:
  /// **'Add Water'**
  String get addWaterDialogTitle;

  /// Text field label showing the active unit, e.g. 'Amount (ml)'
  ///
  /// In en, this message translates to:
  /// **'Amount ({unit})'**
  String amountWithUnitLabel(String unit);

  /// Generic Add action button label
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// Confirmation dialog title for resetting today's logged water intake
  ///
  /// In en, this message translates to:
  /// **'Reset Today\'s Water Log?'**
  String get resetTodayTitle;

  /// Confirmation dialog body for resetting today's logged water intake
  ///
  /// In en, this message translates to:
  /// **'This will reset your logged water intake for today to 0.'**
  String get resetTodayMessage;

  /// Generic Reset action button label
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// AppBar icon button tooltip to reset today's water log
  ///
  /// In en, this message translates to:
  /// **'Reset Today'**
  String get resetTodayTooltip;

  /// AppBar icon button tooltip to switch between metric and imperial units
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get unitsTooltip;

  /// Menu item label for the metric unit option
  ///
  /// In en, this message translates to:
  /// **'Metric (ml)'**
  String get metricUnitLabel;

  /// Menu item label for the imperial unit option
  ///
  /// In en, this message translates to:
  /// **'Imperial (fl oz)'**
  String get imperialUnitLabel;

  /// Compact badge label showing the current daily-goal streak, e.g. '5 Day Streak'
  ///
  /// In en, this message translates to:
  /// **'{count} Day Streak'**
  String streakBadge(int count);

  /// Label showing the daily goal amount and current progress percentage
  ///
  /// In en, this message translates to:
  /// **'Goal: {goal} ({percent}%)'**
  String goalProgressLabel(String goal, int percent);

  /// Small all-caps section header above the quick-add water buttons
  ///
  /// In en, this message translates to:
  /// **'QUICK LOG'**
  String get quickLogHeader;

  /// Quick-add button label for a small glass of water
  ///
  /// In en, this message translates to:
  /// **'Glass'**
  String get quickAddGlass;

  /// Quick-add button label for a bottle of water
  ///
  /// In en, this message translates to:
  /// **'Bottle'**
  String get quickAddBottle;

  /// Quick-add button label for a large water serving
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get quickAddLarge;

  /// Quick-add button label to open the custom-amount dialog
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get quickAddCustom;

  /// Quick-add button amount text, e.g. '+250 ml'
  ///
  /// In en, this message translates to:
  /// **'+{amount} {unit}'**
  String quickAddDisplay(int amount, String unit);

  /// Abbreviation for millilitres (metric volume unit)
  ///
  /// In en, this message translates to:
  /// **'ml'**
  String get unitMl;

  /// Abbreviation for fluid ounces (imperial volume unit)
  ///
  /// In en, this message translates to:
  /// **'fl oz'**
  String get unitFlOz;

  /// Title of the hydration tip info card
  ///
  /// In en, this message translates to:
  /// **'Daily Hydration Tip'**
  String get dailyHydrationTipTitle;

  /// Body text of the hydration tip info card
  ///
  /// In en, this message translates to:
  /// **'Drink a glass of water right after waking up to kickstart your metabolism.'**
  String get hydrationTipBody;

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
  /// **'{count, plural, =1{Pinned 1 item} other{Pinned # items}}'**
  String pinnedCount(num count);

  /// Status message after unpinning items
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Unpinned 1 item} other{Unpinned # items}}'**
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
  /// **'{count, plural, =1{Deleted 1 item} other{Deleted # items}}'**
  String deletedCount(num count);

  /// Status message after a batch delete with some failures
  ///
  /// In en, this message translates to:
  /// **'{deleted} deleted · {failed} failed'**
  String deletedWithFailures(int deleted, int failed);

  /// Status message after exporting files to device storage
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Exported 1 file} other{Exported # files}}'**
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
  /// **'{count, plural, =1{Deleted 1 original item} other{Deleted # original items}}'**
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
  /// **'{count, plural, =1{Extracted 1 file} other{Extracted # files}}'**
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

  /// Title for change vault password screen
  ///
  /// In en, this message translates to:
  /// **'Change Vault Password'**
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
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
