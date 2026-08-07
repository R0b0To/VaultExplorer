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
  /// **'The app icon and name on your home screen will change to \"Archive Explorer\". It will function as a zip archive browser and extractor.\n\nTo access your vault, open Archive Explorer and hold your finger on the title for 3 seconds.'**
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

  /// Layout mode option: masonry grid view
  ///
  /// In en, this message translates to:
  /// **'Masonry'**
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

  /// Warning shown when attempting to change the password of a LUKS container
  ///
  /// In en, this message translates to:
  /// **'LUKS password changing is not supported in-app. Use cryptsetup on Linux.'**
  String get luksPasswordChangeNotSupportedMessage;

  /// Warning shown when attempting to change the password of a Cryptomator vault
  ///
  /// In en, this message translates to:
  /// **'Cryptomator vault passwords cannot be changed in-app.'**
  String get cryptomatorPasswordChangeNotSupportedMessage;

  /// Warning shown when attempting to change the password of a Gocryptfs vault
  ///
  /// In en, this message translates to:
  /// **'Gocryptfs vault passwords cannot be changed in-app.'**
  String get gocryptfsPasswordChangeNotSupportedMessage;

  /// Warning shown when attempting to change the password of a CryFS vault
  ///
  /// In en, this message translates to:
  /// **'CryFS vault passwords cannot be changed in-app.'**
  String get cryfsPasswordChangeNotSupportedMessage;

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
  /// **'{count, plural, =1{1 folder} other{# folders}}'**
  String statsFolderCount(num count);

  /// Count of files shown in the stats bar
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{# files}}'**
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
  /// **'{count, plural, =1{1 item already exists} other{# items already exist}}'**
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

  /// Tooltip for the cancel button on an active file operation row
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get fileOpsCancelTooltip;

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
  /// **'{count, plural, =1{1 item failed:} other{# items failed:}}'**
  String fileOpsItemsFailedLabel(num count);

  /// Label indicating additional items beyond the displayed limit in a batch file operation
  ///
  /// In en, this message translates to:
  /// **'+ {count} more'**
  String fileOpsMoreItemsLabel(num count);

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

  /// Button to retry a failed operation
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

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
  /// **'Zero-trust, 100% offline, local memory security design'**
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
  /// **'Cryptomator (v7/v8 SIV_GCM), gocryptfs (v2 EME), CryFS (0.10 Merkle)'**
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
  /// **'Files inside container volumes are read and written locally. Bypasses SAF when direct path access is available for up to 1000x faster I/O.'**
  String get privacyPointPosixBody;

  /// Privacy sheet point title: screen and clipboard protection
  ///
  /// In en, this message translates to:
  /// **'Screen & Clipboard Protection'**
  String get privacyPointScreenClipboardTitle;

  /// Privacy sheet point body: screen and clipboard protection
  ///
  /// In en, this message translates to:
  /// **'Screenshot/task-switcher preview blocking (FLAG_SECURE) and automatic corrupt clipboard sanitization upon window focus.'**
  String get privacyPointScreenClipboardBody;

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

  /// Past-tense verb: Imported
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get verbImported;

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

  /// Present-continuous verb: Importing
  ///
  /// In en, this message translates to:
  /// **'Importing'**
  String get verbImporting;

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

  /// Pluralized count of items in a file operation
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{# items}}'**
  String fileOpItemsCount(num count);

  /// Completion summary count of items processed
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item {verb}} other{# items {verb}}}'**
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

  /// Status message while importing a specific item
  ///
  /// In en, this message translates to:
  /// **'Importing {name}…'**
  String fileOpImportingName(String name);

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
