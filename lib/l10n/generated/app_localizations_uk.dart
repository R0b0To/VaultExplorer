// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get cancel => 'Скасувати';

  @override
  String get close => 'Закрити';

  @override
  String get search => 'Пошук';

  @override
  String get goBack => 'Назад';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => 'Перейти до сторінки';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return 'Номер сторінки (1 - $pageCount)';
  }

  @override
  String get pdfViewerPageLabel => 'Сторінка';

  @override
  String get pdfViewerGoButton => 'Перейти';

  @override
  String get pdfViewerSearchHint => 'Пошук у документі';

  @override
  String get pdfViewerNoMatches => 'Збігів не знайдено';

  @override
  String get pdfViewerPreviousMatch => 'Попередній збіг';

  @override
  String get pdfViewerNextMatch => 'Наступний збіг';

  @override
  String get pdfViewerCloseSearch => 'Закрити пошук';

  @override
  String get pdfViewerPrintTooltip => 'Друкувати документ';

  @override
  String get pdfViewerLoadingDocument => 'Завантаження документа…';

  @override
  String get pdfViewerCannotOpenTitle => 'Не вдалося відкрити PDF';

  @override
  String get pdfViewerFailedToLoad => 'Помилка завантаження PDF';

  @override
  String get pdfViewerEditTooltip => 'Редагувати';

  @override
  String get pdfViewerDoneEditingTooltip => 'Завершити редагування';

  @override
  String get pdfViewerSaveFailed => 'Не вдалося зберегти зміни до цього PDF';

  @override
  String get pdfViewerEditUnavailable =>
      'Редагування недоступне для цього документа';

  @override
  String get paste => 'Вставити';

  @override
  String get clear => 'Очистити';

  @override
  String get clipboardVerbMove => 'Перемістити';

  @override
  String get clipboardVerbCopy => 'Копіювати';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb ($count) — торкніться для деталей, затисніть для вставки';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb ($count) — деталі буфера обміну';
  }

  @override
  String clipboardSourceLabel(String source) {
    return 'Джерело: $source';
  }

  @override
  String get clipboardDefaultSourceName => 'Сховище';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count елементів',
      many: '$count елементів',
      few: '$count елементи',
      one: '1 елемент',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+ще $count елементів',
      many: '+ще $count елементів',
      few: '+ще $count елементи',
      one: '+1 елемент',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => 'Розширені параметри';

  @override
  String get pimFieldLabel => 'PIM (залиште порожнім за замовчуванням)';

  @override
  String get encryptionAlgorithmLabel => 'Алгоритм шифрування';

  @override
  String get hashAlgorithmLabel => 'Хеш-алгоритм';

  @override
  String get clipboardVerbMoving => 'Переміщення';

  @override
  String get clipboardVerbCopying => 'Копіювання';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count елементів',
      many: '$count елементів',
      few: '$count елементи',
      one: '1 елемент',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return ' із \"$source\"';
  }

  @override
  String get clipboardOpenContainerToPaste => 'Відкрийте сховище для вставки';

  @override
  String get keyfilesOptionalLabel => 'Ключ. файли (необов\'язково)';

  @override
  String get addFile => 'Додати';

  @override
  String get noKeyfilesAttached => 'Ключ. файли не прикріплено';

  @override
  String get completed => 'Завершено';

  @override
  String get dismiss => 'Закрити';

  @override
  String byteProgressText(String transferred, String total, int pct) {
    return '$transferred / $total ($pct%)';
  }

  @override
  String countProgressText(int done, int total, int pct) {
    return '$done / $total ($pct%)';
  }

  @override
  String multiOpLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count операцій',
      many: '$count операцій',
      few: '$count операції',
      one: '1 операція',
    );
    return '$_temp0';
  }

  @override
  String multiOpSublabel(String summary) {
    return '$summary · торкніться для перегляду';
  }

  @override
  String get thumbnailSizeResolutionLabel => 'Розмір мініатюри (Роздільність)';

  @override
  String get jpegCompressionQualityLabel => 'Якість стиснення JPEG';

  @override
  String get done => 'Готово';

  @override
  String get confirm => 'Підтвердити';

  @override
  String get couldNotPickKeyfiles => 'Не вдалося вибрати ключові файли';

  @override
  String get filesystemLabelEncryptedVault => 'цьому зашифрованому сховищі';

  @override
  String get filesystemLabelThisContainer => 'цьому контейнері';

  @override
  String get nounFile => 'файл';

  @override
  String get nounFolder => 'папку';

  @override
  String get nounFileCapitalized => 'Файл';

  @override
  String get nounFolderCapitalized => 'Папка';

  @override
  String get unitBytes => 'байт';

  @override
  String get unitCharacters => 'символів';

  @override
  String get validationEmptyName => 'Назва не може бути порожньою.';

  @override
  String validationReservedNavName(String name, String noun) {
    return '\"$name\" є зарезервованим системним ім\'ям і не може бути назвою $noun.';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return '\"$char\" на позиції $position є неприпустимим символом для $fsLabel.';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return 'Позиція $position містить недрукований символ керування (код $code), заборонений у $fsLabel.';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '\"$name\" є зарезервованим ім\'ям пристрою у $fsLabel (CON, PRN, AUX, NUL тощо) і не може використовуватися.';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return 'Назва $noun не може закінчуватися пробілом у $fsLabel';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return 'Назва $noun не може закінчуватися крапкою у $fsLabel';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return 'Довжина цієї назви $length $unit; $fsLabel дозволяє щонайбільше $maxLength $unit для назви $noun.';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return 'Повний шлях містить $length символів; $fsLabel дозволяє щонайбільше $maxLength.';
  }

  @override
  String conflictSameType(String noun, String name) {
    return '$noun з назвою \"$name\" вже існує тут.';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return '$existingNoun з назвою \"$name\" вже існує тут — не може мати однакову назву з $candidateNoun.';
  }

  @override
  String get readOnlyContainerWarning =>
      'Цей контейнер змонтовано лише для читання.';

  @override
  String get hiddenVolumeProtectionTriggeredWarning =>
      'Запис у цей том міг пошкодити прихований том і був заблокований. Сховище переведено в режим лише для читання.';

  @override
  String get protectHiddenVolumeToggleTitle => 'Захистити прихований том';

  @override
  String get protectHiddenVolumeToggleSubtitle =>
      'Запобігати пошкодженню при записі в зовнішній том';

  @override
  String get protectHiddenVolumeCredentialsRequired =>
      'Для захисту потрібен пароль або ключовий файл прихованого тома';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Видалити $count елементів?',
      many: 'Видалити $count елементів?',
      few: 'Видалити $count елементи?',
      one: 'Видалити 1 елемент?',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning =>
      'Ці елементи буде безповоротно видалено разом з усім вмістом вибраних папок.';

  @override
  String get deleteFilesWarning =>
      'Ці елементи буде безповоротно видалено з вашого зашифрованого тома.';

  @override
  String get delete => 'Видалити';

  @override
  String get remove => 'Вилучити';

  @override
  String get create => 'Створити';

  @override
  String get rename => 'Перейменувати';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Перейменувати $count елементів',
      many: 'Перейменувати $count елементів',
      few: 'Перейменувати $count елементи',
      one: 'Перейменувати 1 елемент',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => 'Нова папка';

  @override
  String get newTextFileTitle => 'Новий текстовий файл';

  @override
  String get folderNameHint => 'Назва папки';

  @override
  String get filenameHint => 'filename.txt';

  @override
  String get newNameHint => 'Нова назва';

  @override
  String get baseNameHint => 'Базова назва';

  @override
  String couldntCreateItem(String name) {
    return 'Не вдалося створити \"$name\" — перевірте, чи контейнер змонтовано';
  }

  @override
  String couldntRenameSingle(String name) {
    return 'Не вдалося перейменувати \"$name\" — можливо, елемент із такою назвою вже існує';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Не вдалося перейменувати $count елементів: $reason',
      many: 'Не вдалося перейменувати $count елементів: $reason',
      few: 'Не вдалося перейменувати $count елементи: $reason',
      one: 'Не вдалося перейменувати 1 елемент: $reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Не вдалося перейменувати $count елементів',
      many: 'Не вдалося перейменувати $count елементів',
      few: 'Не вдалося перейменувати $count елементи',
      one: 'Не вдалося перейменувати 1 елемент',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize =>
      'Введіть коректний розмір прихованого тома більше 0';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter =>
      'Розмір прихованого тома має бути меншим за розмір зовнішнього тома';

  @override
  String get hiddenVolumeErrorTooLargeForContainer =>
      'Розмір прихованого тома завеликий для цього контейнера';

  @override
  String get hiddenVolumeErrorCredentialsRequired =>
      'Для створення прихованого тома потрібен пароль або ключовий файл';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      'Облікові дані прихованого тома не можуть збігатися з обліковими даними зовнішнього тома.';

  @override
  String get vaultItemTypePassword => 'Пароль';

  @override
  String get vaultItemTypePaymentCard => 'Платіжна картка';

  @override
  String get vaultItemTypeIdentity => 'Особисті дані';

  @override
  String get vaultItemTypeSecureNote => 'Захищена нотатка';

  @override
  String get vaultItemTypeBankAccount => 'Банківський рахунок';

  @override
  String get vaultItemTypeSoftwareLicense => 'Ліцензія на ПЗ';

  @override
  String get fieldUsernameEmail => 'Ім\'я користувача / Email';

  @override
  String get fieldPassword => 'Пароль';

  @override
  String get fieldWebsiteUrl => 'Веб-сайт / URL';

  @override
  String get fieldTotpSecret => 'Секретний ключ TOTP';

  @override
  String get fieldNotes => 'Нотатки';

  @override
  String get fieldCardholderName => 'Власник картки';

  @override
  String get fieldCardNumber => 'Номер картки';

  @override
  String get fieldExpiryMMYY => 'Термін дії (ММ/РР)';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN-код';

  @override
  String get fieldIssuingBank => 'Банк-емітент';

  @override
  String get fieldFullName => 'Повне ім\'я';

  @override
  String get fieldDateOfBirth => 'Дата народження';

  @override
  String get fieldNationality => 'Громадянство';

  @override
  String get fieldPassportNumber => 'Номер паспорта';

  @override
  String get fieldPassportExpiry => 'Термін дії паспорта';

  @override
  String get fieldNationalIdSsn => 'ІПН / Номер посвідчення';

  @override
  String get fieldDriversLicense => 'Водійське посвідчення';

  @override
  String get fieldAddress => 'Адреса';

  @override
  String get fieldPhone => 'Телефон';

  @override
  String get fieldEmail => 'Електронна пошта';

  @override
  String get fieldNote => 'Нотатка';

  @override
  String get fieldBankName => 'Назва банку';

  @override
  String get fieldAccountHolder => 'Власник рахунку';

  @override
  String get fieldAccountNumber => 'Номер рахунку';

  @override
  String get fieldRoutingSortCode => 'МФО / Код банку';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => 'Тип рахунку';

  @override
  String get fieldProductName => 'Назва продукту';

  @override
  String get fieldLicenseKey => 'Ліцензійний ключ';

  @override
  String get fieldRegisteredTo => 'Зареєстровано на';

  @override
  String get fieldPurchaseDate => 'Дата придбання';

  @override
  String get fieldExpiryRenewalDate => 'Дата завершення / продовження';

  @override
  String get fieldDownloadUrl => 'Посилання для завантаження';

  @override
  String get fieldRegistrationEmail => 'Email реєстрації';

  @override
  String get titleRequired => 'Необхідно вказати заголовок';

  @override
  String newTypeTitle(String typeLabel) {
    return 'Новий $typeLabel';
  }

  @override
  String editItemTitle(String title) {
    return 'Редагувати $title';
  }

  @override
  String get save => 'Зберегти';

  @override
  String typeNameHint(String typeLabel) {
    return 'Назва $typeLabel';
  }

  @override
  String get titleSectionLabel => 'Заголовок';

  @override
  String get fieldsSectionLabel => 'Поля';

  @override
  String get encryptedStorageHint =>
      'Зберігається в зашифрованому вигляді всередині сховища';

  @override
  String copiedSuffix(String fieldLabel) {
    return '$fieldLabel скопійовано';
  }

  @override
  String get copy => 'Копіювати';

  @override
  String get failedToSaveCheckMounted =>
      'Не вдалося зберегти — перевірте, чи контейнер змонтовано';

  @override
  String get discardChangesTitle => 'Відкинути зміни?';

  @override
  String get discardChangesMessage => 'Усі незбережені зміни буде втрачено.';

  @override
  String get discard => 'Відкинути';

  @override
  String get keepEditing => 'Продовжити редагування';

  @override
  String get deleteItemTitle => 'Видалити запис?';

  @override
  String deleteItemMessage(String title) {
    return '\"$title\" буде безповоротно видалено зі сховища.';
  }

  @override
  String get removeFromBookmarks => 'Вилучити із закладок';

  @override
  String get addToBookmarks => 'Додати до закладок';

  @override
  String get edit => 'Редагувати';

  @override
  String labelCopiedToClipboard(String label) {
    return '$label скопійовано в буфер';
  }

  @override
  String get noFieldsFilledIn => 'Жодного поля не заповнено';

  @override
  String get sectionLabelDetails => 'Деталі';

  @override
  String get sectionLabelInfo => 'Інформація';

  @override
  String get metaLabelType => 'Тип';

  @override
  String get metaLabelCreated => 'Створено';

  @override
  String get metaLabelModified => 'Змінено';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return 'Скопіювати $fieldLabel';
  }

  @override
  String get readOnlyCantAddItemsTooltip =>
      'Лише читання — додавання неможливе';

  @override
  String get extractArchive => 'Видобути архів';

  @override
  String get newItemTooltip => 'Створити запис';

  @override
  String get camera => 'Камера';

  @override
  String get importFiles => 'Імпортувати файли';

  @override
  String get importFolder => 'Імпортувати папку';

  @override
  String get secureItem => 'Захищений запис';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archive Explorer';

  @override
  String get archiveExplorerPermissionTitle => 'Потрібен доступ до файлів';

  @override
  String get archiveExplorerPermissionMessage =>
      'Надайте доступ до пам\'яті для перегляду та видобування zip-архівів із папки Завантаження.';

  @override
  String get archiveExplorerGrantAccess => 'Надати доступ';

  @override
  String get archiveExplorerEmptyTitle => 'Архіви не знайдено';

  @override
  String get archiveExplorerEmptyMessage =>
      'Завантажені zip-файли з\'являтимуться тут.';

  @override
  String get archiveExplorerRefreshTooltip => 'Оновити';

  @override
  String archiveExplorerEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count елементів',
      many: '$count елементів',
      few: '$count елементи',
      one: '1 елемент',
    );
    return '$_temp0';
  }

  @override
  String get archiveExplorerExtractAll => 'Видобути все';

  @override
  String get archiveExplorerExtracting => 'Видобування...';

  @override
  String archiveExplorerExtractSuccess(int count, String name) {
    return 'Видобуто $count файлів до Download/Extracted/$name';
  }

  @override
  String get archiveExplorerExtractFailed => 'Не вдалося видобути цей архів.';

  @override
  String get archiveExplorerOpenFailed => 'Не вдалося відкрити цей архів.';

  @override
  String get archiveExplorerOpenArchive => 'Відкрити архів…';

  @override
  String get archiveExplorerUnresolvedPath =>
      'Не вдалося отримати прямий доступ до файлу. Виберіть файл із папки Завантаження.';

  @override
  String get archiveExplorerExtractTo => 'Видобути до…';

  @override
  String get archiveExplorerPreview => 'Попередній перегляд';

  @override
  String get archiveExplorerChoosingDestination => 'Вибір місця призначення…';

  @override
  String get archiveExplorerNoDestinationChosen =>
      'Місце призначення не вибрано.';

  @override
  String archiveExplorerExtractSuccessTo(int count, String path) {
    return 'Видобуто $count файлів до $path';
  }

  @override
  String get archiveBrowserEmptyTitle => 'Порожня папка';

  @override
  String get archiveBrowserEmptyMessage => 'Ця папка не містить файлів.';

  @override
  String get archiveBrowserRoot => 'Архів';

  @override
  String get archiveBrowserOpenFileFailed => 'Не вдалося відкрити цей файл.';

  @override
  String get fileAssocInAppTextEditor => 'Вбудований текстовий редактор';

  @override
  String get fileAssocInAppMediaViewer => 'Вбудований переглядач медіа';

  @override
  String fileAssocAppPrefix(String name) {
    return 'Програма: $name';
  }

  @override
  String get fileAssocExternalApp => 'Зовнішня програма';

  @override
  String get appSettingsTitle => 'Налаштування програми';

  @override
  String get sectionSecurityPrivacy => 'Безпека та конфіденційність';

  @override
  String get sectionAppearanceInterface => 'Вигляд та інтерфейс';

  @override
  String get sectionVaultFileHandling => 'Сховища та робота з файлами';

  @override
  String get masterPasswordTitle => 'Головний пароль';

  @override
  String get masterPasswordActiveSubtitle =>
      'Активний · торкніться перемикача для видалення';

  @override
  String get masterPasswordInactiveSubtitle =>
      'Вимагати пароль для відкриття програми';

  @override
  String get newPasswordLabel => 'Новий пароль';

  @override
  String get masterPasswordFieldLabel => 'Головний пароль';

  @override
  String get confirmPasswordLabel => 'Підтвердження пароля';

  @override
  String get update => 'Оновити';

  @override
  String get setPassword => 'Встановити пароль';

  @override
  String get biometricUnlockTitle => 'Біометричне розблокування';

  @override
  String get biometricUnlockSubtitle =>
      'Підтвердьте особу для безпечного відкриття контейнера';

  @override
  String get changeMasterPasswordTitle => 'Змінити головний пароль';

  @override
  String get changeMasterPasswordSubtitle =>
      'Оновити облікові дані головного пароля';

  @override
  String get autoLockContainersTitle => 'Автоматичне блокування сховища';

  @override
  String get autoLockContainersSubtitle =>
      'Автоматично блокувати відкриті сховища при бездіяльності';

  @override
  String get autoLockTimeoutLabel => 'Час автоблокування';

  @override
  String get immediately => 'Одразу';

  @override
  String nMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count хвилин',
      many: '$count хвилин',
      few: '$count хвилини',
      one: '1 хвилина',
    );
    return '$_temp0';
  }

  @override
  String get blockScreenshotsTitle => 'Блокувати знімки екрана';

  @override
  String get blockScreenshotsSubtitle =>
      'Забороняти створення скриншотів та приховувати програму в списку нещодавніх';

  @override
  String get keepVaultsRunningInBackgroundTitle =>
      'Тримати сховища відкритими у фоні';

  @override
  String get keepVaultsRunningInBackgroundSubtitle =>
      'Показувати сповіщення та залишати сховища відкритими після виходу з програми. Ключі сховищ залишаються в пам\'яті до блокування.';

  @override
  String get notificationPermissionDeniedMessage =>
      'Дозвіл на сповіщення відхилено. Сховища все одно залишатимуться відкритими, але постійне сповіщення не відображатиметься.';

  @override
  String get discreteModeTitle => 'Режим маскування';

  @override
  String get discreteModeActiveSubtitle =>
      'Активний · програма маскується під \"Archive Explorer\"';

  @override
  String get discreteModeInactiveSubtitle =>
      'Маскувати цю програму під провідник zip-архівів на домашньому екрані';

  @override
  String get enableDiscreteModeTitle => 'Увімкнути режим маскування?';

  @override
  String get disableDiscreteModeTitle => 'Вимкнути режим маскування?';

  @override
  String get enableDiscreteModeMessage =>
      'Іконка та назва програми зміняться на \"Archive Explorer\". Вона працюватиме як звичайний переглядач архівів.\n\nДля доступу до ваших сховищ відкрийте Archive Explorer і затисніть заголовок на 3 секунди.';

  @override
  String get disableDiscreteModeMessage =>
      'Іконка та назва програми зміняться назад на \"Vault Explorer\".';

  @override
  String get enable => 'Увімкнути';

  @override
  String get disable => 'Вимкнути';

  @override
  String get discreteModeEnabledSnack =>
      'Режим маскування увімкнено. Програма закриється — відкрийте її з нової іконки.';

  @override
  String get discreteModeDisabledSnack =>
      'Режим маскування вимкнено. Програма закриється — відкрийте її з нової іконки.';

  @override
  String get failedToChangeDiscreteMode =>
      'Не вдалося змінити режим маскування';

  @override
  String get cacheDerivedKeysTitle =>
      'Використовувати кеш ключа для швидшого розблокування';

  @override
  String get cacheDerivedKeysSubtitle =>
      'Зберігати ключ, отриманий із пароля, у Keystore для швидшого відкриття сховища';

  @override
  String get appThemeLabel => 'Тема програми';

  @override
  String get systemDefault => 'Системна';

  @override
  String get lightTheme => 'Світла';

  @override
  String get darkTheme => 'Темна';

  @override
  String get useMaterialYouTitle => 'Кольори Material You';

  @override
  String get useMaterialYouSubtitle =>
      'Адаптувати кольори програми до шпалер (Android 12+)';

  @override
  String get sortContainersByLabel => 'Сортувати сховища за';

  @override
  String get swapCardSwipeActionsTitle =>
      'Змінити порядок дій при проведенні по картках';

  @override
  String get swapCardSwipeActionsSubtitle =>
      'Під час свайпу карток: \"Редагувати\" ліворуч, \"Видалити\" праворуч';

  @override
  String get swipeGestureHintTitle => 'Показувати підказку свайпу';

  @override
  String get swipeGestureHintSubtitle =>
      'Показати анімацію-підказку свайпу для контейнера';

  @override
  String get autoOpenOnUnlockTitle => 'Автоматично переходити до файлів';

  @override
  String get autoOpenOnUnlockActiveSubtitle =>
      'Одразу відкривати файловий менеджер після розблокування сховища';

  @override
  String get autoOpenOnUnlockInactiveSubtitle =>
      'Лише розблокувати сховище і залишатися на головному екрані';

  @override
  String get enableJsHtmlTitle => 'Увімкнути JavaScript у переглядачі HTML';

  @override
  String get jsEnabledSubtitle =>
      'JavaScript увімкнено для локальних HTML-файлів';

  @override
  String get jsDisabledSubtitle =>
      'JavaScript вимкнено для локальних HTML-файлів';

  @override
  String get fastStorageAccessTitle => 'Швидкий доступ до сховища';

  @override
  String get fastStorageAccessGrantedSubtitle =>
      'Надано доступ до всіх файлів (максимальна швидкість)';

  @override
  String get fastStorageAccessNotGrantedSubtitle =>
      'Надайте доступ до всіх файлів у налаштуваннях для максимальної швидкості';

  @override
  String get enableFastStorageAccessTitle => 'Увімкнути швидкий доступ';

  @override
  String get enableFastStorageAccessMessage =>
      'Надання дозволу \"Доступ до всіх файлів\" дозволяє Vault Explorer виконувати прямі POSIX операції, прискорюючи роботу до 1000 разів.';

  @override
  String get disableStorageAccessTitle => 'Вимкнути доступ до сховища';

  @override
  String get disableStorageAccessMessage =>
      'Вимкніть дозвіл \"Доступ до всіх файлів\" у системних налаштуваннях Android. Відкрити налаштування зараз?';

  @override
  String get enableStoragePermissionLegacyTitle =>
      'Дозволити доступ до пам\'яті';

  @override
  String get enableStoragePermissionLegacyMessage =>
      'Vault Explorer потрібен доступ до пам\'яті для виконання прямих файлових операцій, що значно прискорює роботу захищених папок. Зараз Android запитає підтвердження.';

  @override
  String get disableStoragePermissionLegacyMessage =>
      'Вимкнути доступ до пам\'яті в Android можна лише в системних налаштуваннях. Відкрити налаштування зараз?';

  @override
  String get openSettings => 'Відкрити налаштування';

  @override
  String get androidFileProviderTitle => 'Провайдер файлів Android';

  @override
  String get androidFileProviderSubtitle =>
      'Відкривати доступ до нових сховищ через системний вибір файлів Android за замовчуванням';

  @override
  String get thumbnailCachingDefaultLabel =>
      'Кешування мініатюр (за замовчуванням)';

  @override
  String get thumbnailQualityDefaultLabel =>
      'Якість мініатюр (за замовчуванням)';

  @override
  String get fileAssociationsHeader => 'Асоціації файлів';

  @override
  String get noFileAssociationsYet =>
      'Немає збережених асоціацій файлів. Програма запитуватиме, чим відкривати файли.';

  @override
  String get defaultActionsHeader =>
      'Дії за замовчуванням для нестандартних файлів:';

  @override
  String get removeAssociationTooltip => 'Видалити асоціацію';

  @override
  String get sectionBackupRestore => 'Резервне копіювання';

  @override
  String get exportSettingsTitle => 'Експорт налаштувань';

  @override
  String get exportSettingsSubtitle =>
      'Зберегти налаштування програми та панелі інструментів у файл';

  @override
  String get importSettingsTitle => 'Імпорт налаштувань';

  @override
  String get importSettingsSubtitle =>
      'Відновити налаштування програми та панелі інструментів із файлу';

  @override
  String get importSettingsConfirmTitle => 'Імпортувати налаштування?';

  @override
  String get importSettingsConfirmMessage =>
      'Це замінить ваші поточні налаштування програми та панелі інструментів. Дію не можна скасувати.';

  @override
  String get exportSettingsSuccessMessage => 'Налаштування експортовано';

  @override
  String get importSettingsSuccessMessage => 'Налаштування імпортовано';

  @override
  String get exportSettingsErrorMessage =>
      'Не вдалося експортувати налаштування';

  @override
  String get importSettingsInvalidFileMessage =>
      'Цей файл не є коректним файлом налаштувань';

  @override
  String get sectionDebug => 'Налагодження';

  @override
  String get debugLoggingTitle => 'Журнал налагодження';

  @override
  String get debugLoggingSubtitle =>
      'Записувати детальні діагностичні логи операцій із контейнерами';

  @override
  String get logcatTitle => 'Системний журнал (Logcat)';

  @override
  String get logcatSubtitle =>
      'Перегляд та збереження системних логів пристрою';

  @override
  String logcatSavedMessage(String path) {
    return 'Журнал збережено до $path';
  }

  @override
  String get logcatSaveErrorMessage => 'Не вдалося зберегти журнал';

  @override
  String get logcatCopiedMessage => 'Журнал скопійовано в буфер обміну';

  @override
  String get logcatUnavailableMessage => 'Logcat недоступний на цьому пристрої';

  @override
  String get logcatEmptyMessage => 'Очікування записів журналу…';

  @override
  String get logcatClearTooltip => 'Очистити журнал';

  @override
  String get logcatSaveTooltip => 'Зберегти журнал';

  @override
  String get logcatFilterAppOnly => 'Лише програма';

  @override
  String get logcatFilterAll => 'Усі логи';

  @override
  String get logcatSearchHint => 'Пошук у журналі…';

  @override
  String get logcatClearedMessage => 'Журнал очищено';

  @override
  String get logcatCopyTooltip => 'Скопіювати журнал';

  @override
  String get retryButton => 'Повторити';

  @override
  String get aboutAppTitle => 'Про VaultExplorer';

  @override
  String versionInfoSubtitle(String version) {
    return 'Версія $version · Ліцензії відкритого коду та деталі';
  }

  @override
  String get failedToSaveSettings => 'Не вдалося зберегти налаштування';

  @override
  String get masterPasswordSetSnack => 'Головний пароль встановлено';

  @override
  String get passwordCannotBeEmpty => 'Пароль не може бути порожнім';

  @override
  String get atLeast4CharsRequired => 'Потрібно щонайменше 4 символи';

  @override
  String get passwordsDoNotMatch => 'Паролі не збігаються';

  @override
  String get failedToHashPassword =>
      'Не вдалося створити хеш пароля — спробуйте знову';

  @override
  String get languageLabel => 'Мова';

  @override
  String get biometricNotAvailable => 'Біометрія недоступна на цьому пристрої';

  @override
  String get unlockVaultExplorerReason => 'Розблокувати VaultExplorer';

  @override
  String biometricErrorWithCode(String code) {
    return 'Помилка біометрії: $code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds секунд',
      many: '$seconds секунд',
      few: '$seconds секунди',
      one: '1 секунду',
    );
    return 'Забагато невдалих спроб. Спробуйте знову через $_temp0.';
  }

  @override
  String get enterMasterPasswordPrompt => 'Введіть ваш головний пароль';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts невдалих спроб',
      many: '$attempts невдалих спроб',
      few: '$attempts невдалі спроби',
      one: '1 невдалу спробу',
    );
    return 'Невірний пароль. Заблоковано на $seconds с через $_temp0.';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts невдалих спроб',
      many: '$attempts невдалих спроб',
      few: '$attempts невдалі спроби',
      one: '1 невдала спроба',
    );
    return 'Невірний пароль ($_temp0).';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle =>
      'Введіть ваш головний пароль для продовження';

  @override
  String get masterPasswordFieldLabelTitleCase => 'Головний пароль';

  @override
  String get unlock => 'Розблокувати';

  @override
  String get useBiometric => 'Біометрія';

  @override
  String get connectAtLeast4Dots => 'З\'єднайте щонайменше 4 точки';

  @override
  String get patternsDontMatch =>
      'Графічні ключі не збігаються — спробуйте знову';

  @override
  String get drawUnlockPatternTitle => 'Намалюйте графічний ключ';

  @override
  String get confirmPatternTitle => 'Підтвердьте ваш ключ';

  @override
  String get drawSamePatternAgain => 'Намалюйте той самий ключ знову';

  @override
  String removedFromListSnack(String name) {
    return 'Вилучено \"$name\" зі списку';
  }

  @override
  String get clearRecentHistoryTitle => 'Очистити історію?';

  @override
  String get clearRecentHistoryMessage =>
      'Це очистить список нещодавніх документів. Файли на вашому пристрої залишаться без змін.';

  @override
  String get clearAll => 'Очистити все';

  @override
  String get recentHistoryClearedSnack => 'Історію очищено';

  @override
  String get moreOptionsTooltip => 'Інші параметри';

  @override
  String get clearHistoryMenuItem => 'Очистити історію';

  @override
  String get openPdfFile => 'Відкрити файл PDF';

  @override
  String get noDocumentsYetTitle => 'Документів ще немає';

  @override
  String get openPdfToStartMessage =>
      'Відкрийте PDF-документ із вашого пристрою, щоб почати читання.';

  @override
  String get removeFromListMenuItem => 'Видалити зі списку';

  @override
  String get justNow => 'Щойно';

  @override
  String minutesAgo(int count) {
    return '$count хв тому';
  }

  @override
  String hoursAgo(int count) {
    return '$count год тому';
  }

  @override
  String daysAgo(int count) {
    return '$count дн тому';
  }

  @override
  String get usbDriveDisconnectedLocked =>
      'USB-диск відключено — сховище заблоковано';

  @override
  String get containerAlreadyMounted => 'Цей контейнер уже змонтовано.';

  @override
  String get noVaultFolderFormatDetected =>
      'У вибраній папці не знайдено masterkey.cryptomator, gocryptfs.conf або cryfs.config.';

  @override
  String get savedContainerSettingsNotFound =>
      'Збережені налаштування для цього контейнера не знайдено.';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return 'Не вдалося оновити розташування контейнера: $error';
  }

  @override
  String filePickerFailed(String error) {
    return 'Помилка вибору файлу: $error';
  }

  @override
  String get selectContainerFirst => 'Спочатку виберіть контейнер';

  @override
  String get passwordOrKeyfilesRequired => 'Потрібен пароль або ключові файли';

  @override
  String get slowPerformanceWarningTitle => 'Попередження про низьку швидкість';

  @override
  String get slowPerformanceWarningMessage =>
      'Прямий доступ до сховища наразі вимкнено.\n\nCryFS зберігає файли у вигляді тисяч дрібних блоків. Відкриття таких сховищ через системний Android SAF буде повільним.\n\nБажаєте відкрити Налаштування та надати дозвіл \"Доступ до всіх файлів\" для максимальної швидкості?';

  @override
  String get unlockAnyway => 'Все одно розблокувати';

  @override
  String get defaultVaultName => 'Сховище';

  @override
  String get defaultContainerName => 'Контейнер';

  @override
  String get incorrectPasswordOrInvalidVault =>
      'Невірний пароль або пошкоджене сховище';

  @override
  String get incorrectPasswordOrInvalidContainer =>
      'Невірний пароль або пошкоджений контейнер';

  @override
  String get genericUnknownError => 'Невідома помилка';

  @override
  String get decryptingLabel => 'Розшифрування…';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return 'Перевірка ключового слота $attempted з $total…';
  }

  @override
  String get luksKeyslotProgressUnknown => 'Перевірка ключового слота…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return 'Перевірка облікових даних $attempted з $total…';
  }

  @override
  String get bitlockerCredentialProgressUnknown => 'Перевірка облікових даних…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return 'Спроба $algo ($slotName)…';
  }

  @override
  String get unlockContainerLabel => 'Розблокувати контейнер';

  @override
  String get mountContainerTitle => 'Змонтувати контейнер';

  @override
  String get containerFileSegmentLabel => 'Файл контейнера';

  @override
  String get folderVaultSegmentLabel => 'Захищена папка';

  @override
  String formatContainerLabel(String format) {
    return 'Контейнер $format';
  }

  @override
  String formatVaultLabel(String format) {
    return 'Сховище $format';
  }

  @override
  String formatDriveLabel(String format) {
    return 'Диск $format';
  }

  @override
  String get encryptedContainerLabel => 'Зашифрований контейнер';

  @override
  String get tapToSelectVaultFolder => 'Торкніться, щоб вибрати папку сховища…';

  @override
  String get tapToSelectContainerFile =>
      'Торкніться, щоб вибрати файл контейнера…';

  @override
  String get containerMissingTitle => 'Контейнер відсутній';

  @override
  String get filePathCouldNotBeResolved => 'Не вдалося знайти шлях до файлу';

  @override
  String get containerMissingExplanation =>
      'Файл контейнера міг бути переміщений, видалений, або носій наразі відключено.';

  @override
  String get retryButtonLabel => 'Повторити';

  @override
  String get locateFileButtonLabel => 'Знайти файл';

  @override
  String get authenticateToMountSubtitle =>
      'Підтвердьте особу для безпечного відкриття контейнера';

  @override
  String get usePasswordButtonLabel => 'Використати пароль';

  @override
  String get authenticateButtonLabel => 'Підтвердити';

  @override
  String get drawUnlockPatternCardTitle => 'Намалюйте ключ розблокування';

  @override
  String get wrongPatternTryAgain => 'Невірний ключ — спробуйте ще раз';

  @override
  String get connectYourPatternSequence => 'З\'єднайте точки графічного ключа';

  @override
  String get usePasswordInsteadButtonLabel => 'Використати пароль';

  @override
  String get passwordHintFolderVault => 'Введіть пароль до сховища';

  @override
  String get passwordHintBitlocker => 'Введіть пароль або ключ відновлення';

  @override
  String get passwordHintContainer => 'Введіть пароль до контейнера';

  @override
  String get usingSavedPasswordTooltip => 'Використовується збережений пароль';

  @override
  String get luksKeyfileReplacesPasswordNote =>
      'Для контейнерів LUKS ключовий файл замінює пароль.';

  @override
  String get readOnlyModeUsbSubtitle =>
      'Відкрити без можливості внесення змін до диска';

  @override
  String get readOnlyModeContainerSubtitle =>
      'Відкрити без можливості внесення змін до контейнера';

  @override
  String get rememberContainerLabel => 'Запам\'ятати контейнер';

  @override
  String get rememberContainerSubtitle =>
      'Закріпити на головному екрані для швидкого доступу';

  @override
  String get cancelUnlockButtonLabel => 'Скасувати відкриття';

  @override
  String get biometricSubjectContainer => 'контейнера';

  @override
  String get biometricSubjectUsbDrive => 'USB-накопичувача';

  @override
  String get usbNoSavedCredentialsMessage =>
      'Збережений пароль не знайдено. Введіть його вручну.';

  @override
  String get decryptingDriveLabel => 'Розшифрування диска…';

  @override
  String get usbDeviceAlreadyActiveMounted =>
      'Цей USB-пристрій уже підключено та змонтовано.';

  @override
  String reconnectUsbDriveTitle(String label) {
    return 'Перепідключити \"$label\"';
  }

  @override
  String get unlockUsbDriveTitle => 'Розблокувати USB-диск';

  @override
  String get noUsbStorageDetectedTitle => 'USB-накопичувачів не виявлено';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return 'Підтвердьте особу для розблокування ($subject)';
  }

  @override
  String get noPatternConfiguredMessage =>
      'Графічний ключ не налаштовано. Введіть пароль вручну.';

  @override
  String patternLockedForSeconds(int seconds) {
    return 'Забагато спроб. Заблоковано на $seconds с.';
  }

  @override
  String get initSecureCredsBiometricMessage =>
      'Ініціалізація захищених даних. Розблокуйте вручну для надання біометричного доступу.';

  @override
  String get initSecureCredsPatternMessage =>
      'Ініціалізація захищених даних. Розблокуйте вручну для налаштування графічного ключа.';

  @override
  String get mountExistingContainerTitle => 'Змонтувати наявний контейнер';

  @override
  String get mountExistingContainerSubtitle =>
      'Відкрити створений раніше файл контейнера';

  @override
  String get mountSplitContainerTitle => 'Змонтувати розділений контейнер';

  @override
  String get mountSplitContainerSubtitle =>
      'Відкрити контейнер, розділений на частини, без попереднього об\'єднання';

  @override
  String get mountUsbDriveTitle => 'Змонтувати USB-диск';

  @override
  String get mountUsbDriveSubtitle =>
      'Відкрити контейнер на флеш-накопичувачі OTG';

  @override
  String get formatUsbDriveTitle => 'Форматувати USB-диск';

  @override
  String get formatUsbDriveSubtitle =>
      'Стерти диск і створити на ньому новий зашифрований том';

  @override
  String get createNewContainerTitle => 'Створити новий контейнер';

  @override
  String get createNewContainerSubtitle =>
      'Створити абсолютно нове зашифроване сховище';

  @override
  String get lockBeforeRemovingWarning =>
      'Заблокуйте контейнер перед його видаленням.';

  @override
  String get settingsTooltip => 'Налаштування';

  @override
  String get addVaultFabLabel => 'Додати сховище';

  @override
  String removedLabelUndo(String label) {
    return 'Вилучено \"$label\"';
  }

  @override
  String get undo => 'Скасувати';

  @override
  String get pdfViewerNoSourceProvided => 'Джерело PDF не вказано.';

  @override
  String get pdfViewerFileEmpty => 'Файл PDF порожній або пошкоджений.';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return 'Не вдалося визначити розмір PDF: $error';
  }

  @override
  String get pdfViewerErrorLoadingTitle => 'Помилка завантаження PDF';

  @override
  String get pdfViewerNoDocumentLoaded => 'Документ PDF не завантажено.';

  @override
  String get add => 'Додати';

  @override
  String get reset => 'Скинути';

  @override
  String couldNotExpose(String name) {
    return 'Не вдалося надати доступ до \"$name\".';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return '\"$name\" тепер доступний іншим програмам.';
  }

  @override
  String couldNotUnmount(String name) {
    return 'Не вдалося розмонтувати \"$name\".';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Закріплено $count елементів',
      many: 'Закріплено $count елементів',
      few: 'Закріплено $count елементи',
      one: 'Закріплено 1 елемент',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Відкріплено $count елементів',
      many: 'Відкріплено $count елементів',
      few: 'Відкріплено $count елементи',
      one: 'Відкріплено 1 елемент',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning =>
      'Монтування лише для читання — мініатюри не зберігатимуться всередині сховища в цій сесії.';

  @override
  String failedLoadingFolder(String type) {
    return 'Не вдалося завантажити папку: $type';
  }

  @override
  String failedToReadArchive(String type) {
    return 'Не вдалося прочитати архів: $type';
  }

  @override
  String archiveFormatNotSupported(String ext) {
    return 'Формат архіву .$ext поки що не підтримується';
  }

  @override
  String get failedToReadFileFromArchive =>
      'Не вдалося прочитати файл з архіву';

  @override
  String failedToExtractFile(String type) {
    return 'Не вдалося видобути файл: $type';
  }

  @override
  String get failedToReadSecureItem => 'Не вдалося прочитати захищений запис';

  @override
  String get openFileDialogTitle => 'Відкрити файл';

  @override
  String chooseHowToOpen(String name) {
    return 'Виберіть спосіб відкриття \"$name\":';
  }

  @override
  String get playVideoAudioViewImageInApp =>
      'Переглянути медіа або зображення в програмі';

  @override
  String get viewEditTextMarkdownCode => 'Переглянути або редагувати текст/код';

  @override
  String get sendFileToThirdPartyApp => 'Надіслати файл в іншу програму';

  @override
  String get openAsEllipsis => 'Відкрити як…';

  @override
  String get chooseFileTypeToOpenAs => 'Виберіть тип файлу для відкриття';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return 'Завжди вибирати для файлів .$ext';
  }

  @override
  String get alwaysRememberChoiceNoExt =>
      'Завжди вибирати для файлів без розширення';

  @override
  String get openAsDialogTitle => 'Відкрити як';

  @override
  String get mimeTypeText => 'Текст';

  @override
  String get mimeTypeImage => 'Зображення';

  @override
  String get mimeTypeVideo => 'Відео';

  @override
  String get mimeTypeAudio => 'Аудіо';

  @override
  String get mimeTypeArchive => 'Архів';

  @override
  String get mimeTypeOther => 'Інше';

  @override
  String get scanningSubfoldersForMedia =>
      'Сканування папок на наявність медіа…';

  @override
  String get noMediaFilesFoundRecursive =>
      'Медіафайлів у цій папці та підпапках не знайдено';

  @override
  String failedToScanSubfolders(String error) {
    return 'Не вдалося просканувати підпапки: $error';
  }

  @override
  String get noAppFoundForFileType =>
      'Не знайдено програми для цього типу файлу';

  @override
  String couldNotOpenFile(String name) {
    return 'Не вдалося відкрити \"$name\"';
  }

  @override
  String get readOnlyCantMove =>
      'Контейнер змонтовано лише для читання — переміщення неможливе.';

  @override
  String get readOnlyCantPaste =>
      'Контейнер змонтовано лише для читання — вставка неможлива.';

  @override
  String get clipboardSourceInvalid => 'Джерело буфера обміну недійсне';

  @override
  String get crossContainerPasteNotConfigured =>
      'Вставка між різними сховищами не налаштована.';

  @override
  String get crossContainerPasteRequiresBothMounted =>
      'Вставка між сховищами вимагає, щоб обидва контейнери були відкриті.';

  @override
  String get readOnlyCantDelete =>
      'Контейнер змонтовано лише для читання — видалення неможливе.';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Видалено $count елементів',
      many: 'Видалено $count елементів',
      few: 'Видалено $count елементи',
      one: 'Видалено 1 елемент',
    );
    return '$_temp0';
  }

  @override
  String deletedWithFailures(int deleted, int failed) {
    return 'Видалено: $deleted · Помилок: $failed';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Експортовано $count файлів',
      many: 'Експортовано $count файлів',
      few: 'Експортовано $count файли',
      one: 'Експортовано 1 файл',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed =>
      'Експорт скасовано або завершено з помилкою';

  @override
  String exportError(String type) {
    return 'Помилка експорту: $type';
  }

  @override
  String get deleteOriginalTitle => 'Видалити оригінал?';

  @override
  String get deleteOriginalFolderMessage =>
      'Видалити оригінальну папку з пам\'яті пристрою після імпорту?';

  @override
  String get deleteOriginalFilesMessage =>
      'Видалити оригінальні файли з пам\'яті пристрою після імпорту?';

  @override
  String get keepOriginal => 'Залишити оригінал';

  @override
  String get deleteOriginalButton => 'Видалити оригінал';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Видалено $count оригінальних елементів',
      many: 'Видалено $count оригінальних елементів',
      few: 'Видалено $count оригінальні елементи',
      one: 'Видалено 1 оригінальний елемент',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals => 'Не вдалося видалити оригінал(и)';

  @override
  String get videoCapturedEncrypted => 'Відео записано та зашифровано';

  @override
  String get photoCapturedEncrypted => 'Фото зроблено та зашифровано';

  @override
  String cameraCaptureFailed(String type) {
    return 'Помилка камери: $type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return 'Видобути всі файли до папки \"$folder\"?';
  }

  @override
  String get extract => 'Видобути';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Видобуто $count файлів',
      many: 'Видобуто $count файлів',
      few: 'Видобуто $count файли',
      one: 'Видобуто 1 файл',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return 'Помилка видобування: $type';
  }

  @override
  String get closeSearchTooltip => 'Закрити пошук';

  @override
  String get searchInThisFolderTooltip => 'Шукати в цій папці';

  @override
  String get playMediaHereTooltip => 'Відтворити медіа тут';

  @override
  String get rootFolderLabel => 'Корінь';

  @override
  String folderPickerFailed(String error) {
    return 'Помилка вибору папки: $error';
  }

  @override
  String get addAVaultTitle => 'Додати сховище';

  @override
  String get selectEmptyDestinationFolderFirst =>
      'Спочатку виберіть порожню папку призначення';

  @override
  String get passwordRequired => 'Необхідно ввести пароль';

  @override
  String get vaultCreatedSuccessfully => 'Сховище успішно створено.';

  @override
  String get vaultCreationFailedEmptyFolder =>
      'Помилка створення сховища — переконайтеся, що вибрана папка порожня.';

  @override
  String get unknownErrorOccurred => 'Виникла невідома помилка';

  @override
  String get containerNameRequired => 'Необхідно вказати назву контейнера';

  @override
  String get enterValidSizeGreaterThanZero => 'Введіть розмір більше 0';

  @override
  String get passwordOrKeyfileRequired =>
      'Потрібен пароль або принаймні один ключовий файл';

  @override
  String get standardVolumePasswordsDoNotMatch =>
      'Паролі стандартного тома не збігаються';

  @override
  String get hiddenVolumePasswordsDoNotMatch =>
      'Паролі прихованого тома не збігаються';

  @override
  String get containerFileCreatedSuccessfully =>
      'Файл контейнера успішно створено.';

  @override
  String get containerCreationCancelledOrFailed =>
      'Створення контейнера скасовано або завершилося помилкою.';

  @override
  String get vaultKindContainerFile => 'Файл контейнера';

  @override
  String get vaultKindFolderVault => 'Захищена папка';

  @override
  String get formatFileSystemLabel => 'Файлова система тома';

  @override
  String get standardVolumeHeader => 'Стандартний том';

  @override
  String get containerFormatLabel => 'Формат контейнера';

  @override
  String get fileNameLabel => 'Ім\'я файлу';

  @override
  String get containerSizeLabel => 'Розмір контейнера';

  @override
  String get unitLabel => 'Одиниця';

  @override
  String get passwordFieldLabel => 'Пароль';

  @override
  String get confirmPasswordFieldLabelTitleCase => 'Підтвердження пароля';

  @override
  String get hiddenVolumeHeader => 'Прихований том';

  @override
  String get createHiddenVolumeToggleTitle => 'Створити прихований том';

  @override
  String get createInvisibleSecondaryVolume =>
      'Створити невидимий вторинний том';

  @override
  String get setOuterPasswordFirstToEnable =>
      'Спочатку вкажіть пароль зовнішнього тома';

  @override
  String get hiddenPasswordLabel => 'Пароль прихованого тома';

  @override
  String get confirmHiddenPasswordLabel =>
      'Підтвердження пароля прихованого тома';

  @override
  String get hiddenSizeLabel => 'Розмір прихованого тома';

  @override
  String get unitMbMegabytes => 'МБ (Мегабайти)';

  @override
  String get unitGbGigabytes => 'ГБ (Гігабайти)';

  @override
  String get hiddenFileSystemLabel => 'Файлова система прихованого тома';

  @override
  String get vaultFormatLabel => 'Формат сховища';

  @override
  String get gocryptfsCipherLabel => 'Шифр вмісту';

  @override
  String get cryfsCipherLabel => 'Шифр вмісту';

  @override
  String get cryfsBlockSizeLabel => 'Розмір блоку';

  @override
  String get destinationFolderLabel => 'Папка призначення';

  @override
  String get selectEmptyFolderLabel => 'Виберіть порожню папку';

  @override
  String get tapToChooseVaultLocation =>
      'Торкніться для вибору місця створення сховища…';

  @override
  String get folderVaultLimitationsNote =>
      'Сховища папок не підтримують ключові файли, PIM, приховані томи та вибір алгоритмів шифрування VeraCrypt/LUKS.';

  @override
  String get createVaultButton => 'Створити сховище';

  @override
  String get createContainerButton => 'Створити контейнер';

  @override
  String get vaultCreationInProgressWait =>
      'Триває створення сховища. Зачекайте, будь ласка.';

  @override
  String get containerCreationInProgressWait =>
      'Триває створення контейнера. Зачекайте, будь ласка.';

  @override
  String get createEncryptedVaultTitle => 'Створити зашифроване сховище';

  @override
  String get createEncryptedContainerTitle => 'Створити зашифрований контейнер';

  @override
  String get unitMbShort => 'МБ';

  @override
  String get unitGbShort => 'ГБ';

  @override
  String failedToListUsbDevices(String error) {
    return 'Не вдалося отримати список USB-пристроїв: $error';
  }

  @override
  String get usbPermissionDenied => 'Доступ до USB заборонено';

  @override
  String get couldNotReadDriveCapacity =>
      'Не вдалося визначити розмір накопичувача — введіть вручну.';

  @override
  String get selectUsbDriveFirst => 'Спочатку виберіть USB-накопичувач';

  @override
  String eraseDeviceTitle(String name) {
    return 'Стерти \"$name\"?';
  }

  @override
  String get eraseDeviceMessage =>
      'Це безповоротно видалить усі дані на цьому USB-накопичувачі та створить новий зашифрований контейнер. Дію не можна скасувати.';

  @override
  String get eraseAndCreateButton => 'Стерти та створити';

  @override
  String get usbPermissionRequiredToContinue =>
      'Для продовження потрібен дозвіл на доступ до USB';

  @override
  String get usbContainerCreatedSnack =>
      'USB-контейнер створено. Використовуйте \"Змонтувати USB-диск\" для відкриття.';

  @override
  String get usbContainerCreationFailed => 'Не вдалося створити USB-контейнер.';

  @override
  String get usbStandardVolumeSectionHeader => 'USB-диск і стандартний том';

  @override
  String get formattingErasesEverythingWarning =>
      'Форматування повністю видалить усі дані на вибраному диску.';

  @override
  String get selectUsbDriveLabel => 'Виберіть USB-диск';

  @override
  String get noUsbStorageDetected => 'USB-накопичувачів не виявлено';

  @override
  String get connectOtgDriveToFormat =>
      'Підключіть OTG-накопичувач для форматування';

  @override
  String get refreshListButton => 'Оновити список';

  @override
  String get readyToFormat => 'Готовий до форматування';

  @override
  String get permissionRequired => 'Потрібен дозвіл';

  @override
  String get readingDriveCapacity => 'Визначення місткості диска…';

  @override
  String get mustNotExceedDriveCapacity =>
      'Не повинен перевищувати реальну місткість накопичувача.';

  @override
  String get quickFormatTitle => 'Швидке форматування';

  @override
  String get quickFormatDescription =>
      'Пропускає заповнення нулями. Швидше, але не видаляє старі дані безповоротно.';

  @override
  String get eraseAndCreateContainerButton => 'Стерти та створити контейнер';

  @override
  String get usbContainerCreationInProgressWait =>
      'Створення контейнера триває. Зачекайте, будь ласка.';

  @override
  String get formatUsbDriveScreenTitle => 'Форматувати USB-диск';

  @override
  String get playlistTransitionAnimationLabel => 'Анімація переходів списку';

  @override
  String get playlistTransitionSlideLabel => 'Зсув (за замовчуванням)';

  @override
  String get playlistTransitionFadeLabel => 'Згасання';

  @override
  String get playlistTransitionZoomLabel => 'Масштабування';

  @override
  String get playlistTransitionDepthLabel => 'Глибина';

  @override
  String get playlistTransitionCubeLabel => '3D Куб';

  @override
  String get playlistTransitionFlipLabel => '3D Перегортання';

  @override
  String get unlockVaultTitle => 'Розблокувати сховище';

  @override
  String get openContainerTitle => 'Відкрити контейнер';

  @override
  String get selectContainerFileOrFolder => 'Виберіть файл або папку';

  @override
  String get readOnlyModeLabel => 'Режим лише для читання';

  @override
  String get readOnlyModeSubtitle =>
      'Забороняє будь-які операції запису або зміни у сховищі';

  @override
  String get selectUsbDeviceLabel => 'Виберіть USB-пристрій';

  @override
  String get noUsbDevicesFound => 'Сумісних USB-накопичувачів не знайдено';

  @override
  String get containerConfigTitle => 'Конфігурація сховища';

  @override
  String get changePasswordTitle => 'Змінити пароль';

  @override
  String get confirmNewPasswordLabel => 'Підтвердьте новий пароль';

  @override
  String get cameraCaptureTitle => 'Камера сховища';

  @override
  String get takingPhoto => 'Зйомка фото…';

  @override
  String get savingToVault => 'Збереження у сховище…';

  @override
  String get noVaultSelected => 'Сховище не вибрано';

  @override
  String get mediaDiagnosticsTitle => 'Діагностика медіа';

  @override
  String get advancedViewerSettingsTitle => 'Налаштування переглядача';

  @override
  String get textEditorSaveConfirmTitle => 'Незбережені зміни';

  @override
  String get textEditorSaveConfirmMessage =>
      'Бажаєте зберегти зміни перед закриттям?';

  @override
  String get saveAndClose => 'Зберегти і закрити';

  @override
  String get discardChanges => 'Відкинути зміни';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вибрано $count елементів',
      many: 'Вибрано $count елементів',
      few: 'Вибрано $count елементи',
      one: 'Вибрано 1 елемент',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'Вибрати все';

  @override
  String get deselectAll => 'Зняти виділення';

  @override
  String get sortOptionsTitle => 'Сортування файлів';

  @override
  String get layoutModeList => 'Список';

  @override
  String get layoutModeGrid => 'Сітка';

  @override
  String get layoutModeMasonry => 'Мозаїка';

  @override
  String get fileOperationsTitle => 'Операції з файлами';

  @override
  String get conflictResolutionTitle => 'Конфлікт імен файлів';

  @override
  String get replaceExistingFile => 'Замінити наявний файл';

  @override
  String get keepBothFiles => 'Зберегти обидва (перейменувати)';

  @override
  String get skipFile => 'Пропустити цей файл';

  @override
  String get noVaultsFoundTitle => 'Сховищ не знайдено';

  @override
  String get noVaultsFoundSubtitle =>
      'Створіть новий контейнер або додайте наявне сховище для початку роботи.';

  @override
  String get addExistingVaultButton => 'Додати наявне сховище';

  @override
  String get sortContainersModeManual => 'Вручну (перетягування)';

  @override
  String get sortContainersModeUnlockStatus => 'За станом розблокування';

  @override
  String get sortContainersModeNameAZ => 'За назвою (А–Я)';

  @override
  String get sortContainersModeNameZA => 'За назвою (Я–А)';

  @override
  String get sortContainersModeNewest => 'Спочатку нові';

  @override
  String get sortContainersModeOldest => 'Спочатку старі';

  @override
  String get thumbnailCacheAppCacheLabel => 'Кеш програми';

  @override
  String get thumbnailCacheAppCacheDesc =>
      'Зберігається в кеші програми. Швидко; очищається системою при нестачі пам\'яті.';

  @override
  String get thumbnailCacheInContainerLabel => 'Всередині контейнера';

  @override
  String get thumbnailCacheInContainerDesc =>
      'Зберігається всередині контейнера. Захищено шифруванням, але запис повільніший.';

  @override
  String get thumbnailCacheDisabledLabel => 'Вимкнено';

  @override
  String get thumbnailCacheDisabledDesc =>
      'Без дискового кешу. Мініатюри генеруються щоразу наново.';

  @override
  String get unlockContainerTitle => 'Розблокувати контейнер';

  @override
  String get containerFileSegment => 'Файл контейнера';

  @override
  String get folderVaultSegment => 'Захищена папка';

  @override
  String get enableButtonLabel => 'Увімкнути';

  @override
  String get retryButtonLabelShort => 'Повторити';

  @override
  String get locateFileButton => 'Знайти файл';

  @override
  String get authenticateButton => 'Підтвердити';

  @override
  String get cancelUnlockButton => 'Скасувати';

  @override
  String tryingKeyslotProgress(int attempted, int total) {
    return 'Перевірка ключового слота $attempted з $total…';
  }

  @override
  String get tryingKeyslotSingle => 'Перевірка ключового слота…';

  @override
  String verifyingCredentialProgress(int attempted, int total) {
    return 'Перевірка облікових даних $attempted з $total…';
  }

  @override
  String get verifyingCredentialSingle => 'Перевірка облікових даних…';

  @override
  String tryingAlgoSlot(String algo, String slotName) {
    return 'Спроба $algo ($slotName)…';
  }

  @override
  String get hiddenVolumeSlotName => 'Прихований том';

  @override
  String get standardVolumeSlotName => 'Стандартний том';

  @override
  String get containerMissingSubtitle => 'Не вдалося знайти шлях до файлу';

  @override
  String get containerMissingBody =>
      'Файл контейнера міг бути переміщений або видалений.';

  @override
  String get connectPatternSequence => 'З\'єднайте точки графічного ключа';

  @override
  String get passwordLabel => 'Пароль';

  @override
  String get enterVaultPasswordHint => 'Введіть пароль до сховища';

  @override
  String get enterBitlockerPasswordHint =>
      'Введіть пароль або ключ відновлення';

  @override
  String get enterContainerPasswordHint => 'Введіть пароль до контейнера';

  @override
  String get readOnlyModeUsbSubtitleDrive =>
      'Відкрити без можливості внесення змін до цього диска';

  @override
  String get rememberDriveLabel => 'Запам\'ятати диск';

  @override
  String get rememberDriveSubtitle => 'Закріпити диск на головному екрані';

  @override
  String get unlockVaultButtonLabel => 'Розблокувати сховище';

  @override
  String get cryfsStorageAccessWarning =>
      'Сховища CryFS використовують тисячі блокових файлів. Без прямого доступу швидкість буде значно нижчою.';

  @override
  String get folderVaultStorageAccessWarning =>
      'Прямий доступ до сховища вимкнено. Читання файлів у папкових сховищах може бути повільнішим.';

  @override
  String get requestingPermission => 'Запит дозволу…';

  @override
  String get unlockAndMountButton => 'Розблокувати та змонтувати';

  @override
  String get unlockDriveButton => 'Розблокувати диск';

  @override
  String couldntFindDevice(String deviceName) {
    return 'Не вдалося знайти \"$deviceName\"';
  }

  @override
  String get plugDriveBackInRetry =>
      'Підключіть накопичувач знову та натисніть \"Повторити\", або виберіть його нижче, якщо він відображається під іншою назвою.';

  @override
  String get retryConnectionButton => 'Повторити підключення';

  @override
  String get refreshDevicesButton => 'Оновити пристрої';

  @override
  String get connectOtgDriveToMount =>
      'Підключіть флеш-диск OTG для монтування';

  @override
  String get alreadyActive => 'Вже активний';

  @override
  String get active => 'Активний';

  @override
  String get readyToUnlock => 'Готовий до розблокування';

  @override
  String get enterUsbPartitionPassword => 'Введіть пароль розділу USB';

  @override
  String get biometricAuthenticationTitle => 'Біометрична автентифікація';

  @override
  String get biometricAuthUsbSubtitle =>
      'Підтвердьте особу для відкриття цього USB-пристрою';

  @override
  String get connectPatternSequenceToMount =>
      'Намалюйте графічний ключ для відкриття';

  @override
  String get selectAllAction => 'Вибрати все';

  @override
  String get clearSelectionAction => 'Зняти виділення';

  @override
  String get clearSelectionTooltip => 'Зняти виділення';

  @override
  String get selectionOptionsTooltip => 'Параметри виділення';

  @override
  String get readOnlyContainerTooltip => 'Сховище лише для читання';

  @override
  String get copyAction => 'Копіювати';

  @override
  String get moveAction => 'Перемістити';

  @override
  String get renameAction => 'Перейменувати';

  @override
  String get exportToDeviceAction => 'Експортувати на пристрій';

  @override
  String get openWithAppAction => 'Відкрити за допомогою програми';

  @override
  String get pinAction => 'Закріпити';

  @override
  String get pinSelectedAction => 'Закріпити вибране';

  @override
  String get unpinAction => 'Відкріпити';

  @override
  String get unpinSelectedAction => 'Відкріпити вибране';

  @override
  String get documentProviderSettingsMenu => 'Налаштування Document Provider';

  @override
  String get exposeAsDocumentProviderMenu => 'Надати доступ до папки';

  @override
  String get moreOptionsTooltipShort => 'Інші параметри';

  @override
  String get copyTooltip => 'Копіювати';

  @override
  String get searchInThisFolderHint => 'Пошук у цій папці…';

  @override
  String get clearTooltip => 'Очистити';

  @override
  String get backToDashboardTooltip => 'Повернутися до сховищ';

  @override
  String get cancelPasteButton => 'Скасувати вставку';

  @override
  String get continueButton => 'Продовжити';

  @override
  String get skipButton => 'Пропустити';

  @override
  String get keepBothButton => 'Зберегти обидва';

  @override
  String get clearAllButton => 'Очистити все';

  @override
  String get autoMountWhenUnlocksTitle =>
      'Автомонтування при відкритті сховища';

  @override
  String get autoMountWhenUnlocksSubtitle =>
      'Автоматично відкривати доступ до цієї папки наступного разу';

  @override
  String get unmountButton => 'Розмонтувати';

  @override
  String get filtersMenuItem => 'Фільтри';

  @override
  String get settingsMenuItem => 'Налаштування';

  @override
  String get sortOptionsTooltip => 'Параметри сортування';

  @override
  String get layoutOptionsTooltip => 'Параметри вигляду';

  @override
  String get lockContainerTooltip => 'Заблокувати сховище';

  @override
  String get renameTooltip => 'Перейменувати';

  @override
  String get cancelUpdatingPasswordTooltip => 'Скасувати зміну пароля';

  @override
  String get unlockSettingsButton => 'Розблокувати налаштування';

  @override
  String get updateSavedCredentialsButton => 'Оновити збережені дані';

  @override
  String get verifyCredentialsTitle => 'Перевірка облікових даних';

  @override
  String get verifyButton => 'Перевірити';

  @override
  String get displayNameTitle => 'Назва для відображення';

  @override
  String get containerNameHint => 'Назва контейнера';

  @override
  String get deleteFileDialogTitle => 'Видалити файл?';

  @override
  String get deleteFilePermanentWarning =>
      'Ця дія є остаточною і не може бути скасована.';

  @override
  String get unsavedChangesTitle => 'Незбережені зміни';

  @override
  String get unsavedChangesMessage =>
      'Ви маєте незбережені зміни. Бажаєте зберегти їх перед закриттям?';

  @override
  String get discardButton => 'Відкинути';

  @override
  String get decryptingFileContent => 'Розшифрування вмісту файлу...';

  @override
  String get cannotOpenFile => 'Не вдалося відкрити файл';

  @override
  String get changesSavedSuccessfully => 'Зміни успішно збережено';

  @override
  String saveFailedWithError(String error) {
    return 'Помилка збереження: $error';
  }

  @override
  String linesCount(int count) {
    return 'Рядків: $count';
  }

  @override
  String charsCount(int count) {
    return 'Символів: $count';
  }

  @override
  String get unsavedChangesLabel => 'Незбережені зміни';

  @override
  String get savedToVault => 'Збережено у сховище';

  @override
  String get saveChangesTooltip => 'Зберегти зміни';

  @override
  String get textEditorDecryptFailedMessage =>
      'Не вдалося розшифрувати файл зі сховища.';

  @override
  String get textEditorInvalidTextFileMessage =>
      'Цей файл не є коректним текстовим документом.';

  @override
  String get textEditorWriteBackFailedMessage =>
      'Не вдалося записати файл назад у сховище.';

  @override
  String get backTooltip => 'Назад';

  @override
  String get forwardTooltip => 'Вперед';

  @override
  String get reloadTooltip => 'Перезавантажити';

  @override
  String get optionsTooltip => 'Опції';

  @override
  String get htmlViewerErrorTitle => 'Неможливо відобразити сторінку';

  @override
  String get htmlViewerLoadFailedMessage => 'Не вдалося завантажити файл';

  @override
  String get enableJavaScriptDialogTitle => 'Увімкнути JavaScript?';

  @override
  String get enableJavaScriptDialogMessage =>
      'Сторінка зможе виконувати локальні скрипти. Вона все одно не матиме доступу до інтернету — жодні дані не можуть бути передані назовні.';

  @override
  String get disableJavaScriptMenu => 'Вимкнути JavaScript';

  @override
  String get enableJavaScriptMenu => 'Увімкнути JavaScript';

  @override
  String get enterFullscreenMenu => 'На весь екран';

  @override
  String failedToOpenExternalApp(String error) {
    return 'Не вдалося відкрити у зовнішній програмі: $error';
  }

  @override
  String get thisFolderMenu => 'Ця папка';

  @override
  String get allInclSubfoldersMenu => 'Усе (разом із підпапками)';

  @override
  String get disableShuffleMenu => 'Вимкнути перемішування';

  @override
  String get shufflePlaylistMenu => 'Перемішати список';

  @override
  String get playlistOptionsTooltip => 'Параметри списку';

  @override
  String get enablePlaylistTooltip => 'Увімкнути список відтворення';

  @override
  String get moreActionsTooltip => 'Додаткові дії';

  @override
  String get forcePortraitMenu => 'Портретна орієнтація';

  @override
  String get forceLandscapeMenu => 'Альбомна орієнтація';

  @override
  String get autoRotateSensorMenu => 'Автоповорот (за датчиком)';

  @override
  String get screenOrientationMenu => 'Орієнтація екрана';

  @override
  String get playlistTransitionMenu => 'Перехід списку';

  @override
  String get renameFileMenu => 'Перейменувати файл';

  @override
  String get deleteFileMenu => 'Видалити файл';

  @override
  String get thumbnailCarouselTooltip => 'Карусель мініатюр';

  @override
  String get advancedSettingsTooltip => 'Розширені налаштування';

  @override
  String get previousTooltip => 'Попередній';

  @override
  String get nextTooltip => 'Наступний';

  @override
  String get diagnosticsCopiedToClipboard => 'Діагностику скопійовано в буфер';

  @override
  String get diagnosticsTitle => 'Діагностика';

  @override
  String get copyDiagnosticsTooltip => 'Скопіювати діагностику';

  @override
  String get closeTooltip => 'Закрити';

  @override
  String get diagnosticsPlaybackSection => 'Відтворення';

  @override
  String get diagnosticsEngineSection => 'Рушій';

  @override
  String get diagnosticsStateLabel => 'Стан';

  @override
  String get diagnosticsResolutionLabel => 'Роздільність';

  @override
  String get diagnosticsAspectRatioLabel => 'Співвідношення сторін';

  @override
  String get diagnosticsPositionLabel => 'Позиція';

  @override
  String get diagnosticsDurationLabel => 'Тривалість';

  @override
  String get diagnosticsErrorLabel => 'Помилка';

  @override
  String get diagnosticsPlayerLabel => 'Програвач';

  @override
  String get diagnosticsDecodingLabel => 'Декодування';

  @override
  String get diagnosticsExoPlayerValue => 'ExoPlayer (Android)';

  @override
  String get diagnosticsHardwareAcceleratedValue => 'Апаратне прискорення';

  @override
  String get diagnosticsUnknownValue => 'Невідомо';

  @override
  String get diagnosticsStateBuffering => 'Буферизація';

  @override
  String get diagnosticsStatePlaying => 'Відтворення';

  @override
  String get diagnosticsStatePaused => 'Пауза';

  @override
  String get diagnosticsDurationUnavailable => '--:--';

  @override
  String get rotate90Label => 'Повернути на 90°';

  @override
  String get imageFitModeLabel => 'Режим масштабування';

  @override
  String get slideshowDelayLabel => 'Затримка слайд-шоу';

  @override
  String get playbackSpeedLabel => 'Швидкість відтворення';

  @override
  String get subtitlesLabel => 'Субтитри';

  @override
  String get imageSettingsTitle => 'Налаштування зображень';

  @override
  String get playbackSettingsTitle => 'Налаштування відтворення';

  @override
  String get imageFitContain => 'Вписати';

  @override
  String get imageFitWidth => 'За шириною';

  @override
  String get imageFitHeight => 'За висотою';

  @override
  String nSecondsDelay(int n) {
    return '$n секунд';
  }

  @override
  String playbackSpeedNormal(String speed) {
    return '${speed}x (Звичайна)';
  }

  @override
  String playbackSpeedValue(String speed) {
    return '${speed}x';
  }

  @override
  String slideshowDelaySecondsValue(int seconds) {
    return '$seconds с';
  }

  @override
  String rotationDegreesValue(int degrees) {
    return '$degrees°';
  }

  @override
  String get settingsTooltipShort => 'Налаштування';

  @override
  String get sourceCodeTooltip => 'Вихідний код';

  @override
  String get donateTooltip => 'Підтримати проект';

  @override
  String get shareAppTooltip => 'Поділитися програмою';

  @override
  String get resetToDefaultsTooltip => 'Скинути до початкових';

  @override
  String get usbUnlockContainerTitle => 'Розблокувати USB-контейнер';

  @override
  String get usbMountContainerTitle => 'Змонтувати USB-диск';

  @override
  String get staticLabel => 'Статично';

  @override
  String get unmuteTooltip => 'Увімкнути звук';

  @override
  String get muteTooltip => 'Вимкнути звук';

  @override
  String get playOnceDisabledTooltip => 'Один раз (автоперехід вимкнено)';

  @override
  String get playAndAdvanceTooltip => 'Грати і перейти далі';

  @override
  String get loopCurrentVideoTooltip => 'Повторювати це відео';

  @override
  String get clearThumbnailCacheDialogTitle => 'Очистити кеш мініатюр?';

  @override
  String get clearThumbnailCacheDialogMessage =>
      'Це видалить кешовані мініатюри для цього сховища. Вони створяться повторно під час перегляду медіа.';

  @override
  String get clearCacheButton => 'Очистити кеш';

  @override
  String get appCacheClearedUnlockMessage =>
      'Кеш програми очищено. Відкрийте контейнер для очищення внутрішнього кешу.';

  @override
  String get allThumbnailCachesClearedMessage =>
      'Усі кеші мініатюр успішно очищено.';

  @override
  String get appCacheClearedContainerFailedMessage =>
      'Кеш програми очищено, але не вдалося очистити кеш усередині контейнера.';

  @override
  String get failedToClearThumbnailCachesMessage =>
      'Не вдалося очистити кеші мініатюр.';

  @override
  String get authenticateToModifySettingsPrompt =>
      'Підтвердьте особу для зміни налаштувань';

  @override
  String get usbVaultSettingsTitle => 'Налаштування USB-сховища';

  @override
  String get vaultSettingsTitle => 'Налаштування сховища';

  @override
  String get generalSectionHeader => 'Загальні';

  @override
  String get securityCredentialsSectionHeader => 'Безпека та облікові дані';

  @override
  String get securityOptionsLockedTitle => 'Параметри безпеки заблоковано';

  @override
  String get authenticateOriginalCredentialsMessage =>
      'Підтвердьте початкові облікові дані контейнера для зміни параметрів безпеки.';

  @override
  String get unlockCredentialsLabel => 'Спосіб розблокування';

  @override
  String get unavailableSuffixLabel => '(Недоступно)';

  @override
  String get patternSetupRequiredBeforeSaving =>
      'Встановіть графічний ключ перед збереженням.';

  @override
  String get passwordKeystoreEncryptedHelperText =>
      'Пароль шифрується за допомогою Android Keystore. Залиште порожнім, якщо використовуються лише ключові файли.';

  @override
  String get changePatternButton => 'Змінити ключ';

  @override
  String get setPatternButton => 'Встановити ключ';

  @override
  String get cacheDerivedKeyLabel => 'Кешувати похідний ключ';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      'Пропускати scrypt KDF наступного разу (ключ у Keystore)';

  @override
  String get reuseKeyMaterialKeystoreSubtitle =>
      'Повторно використовувати ключ із Android Keystore';

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle =>
      'Закріпити алгоритм для пропуску автовизначення при відкритті.';

  @override
  String get changeContainerPasswordTitle => 'Змінити пароль контейнера';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      'Зміна пароля BitLocker не підтримується у програмі. Використовуйте засоби Windows.';

  @override
  String get systemIntegrationSectionHeader => 'Система та інтеграція';

  @override
  String get autoLockDurationLabel => 'Час автоблокування';

  @override
  String get neverAutoLockOption => 'Ніколи';

  @override
  String get exposeContentToFilePickerSubtitle =>
      'Надавати доступ системному провіднику при розблокуванні';

  @override
  String get thumbnailStorageSectionHeader => 'Зберігання мініатюр';

  @override
  String get cacheModeLabel => 'Режим кешування';

  @override
  String get useGlobalDefaultSubtitle =>
      'Використовувати загальне налаштування';

  @override
  String get thumbnailQualityLabel => 'Якість мініатюр';

  @override
  String get clearThumbnailCacheTitle => 'Очистити кеш мініатюр';

  @override
  String get removeCachedThumbnailsSubtitle =>
      'Видалити кешовані мініатюри зображень та відео';

  @override
  String get vaultInformationSectionHeader => 'Інформація про сховище';

  @override
  String get vaultInformationTileTitle => 'Відомості про сховище';

  @override
  String get vaultInformationTileSubtitle =>
      'Шифр, формат та інші технічні параметри';

  @override
  String get vaultInfoLocationLabel => 'Розташування';

  @override
  String get vaultInfoRequiresUnlockTitle => 'Потрібне розблокування';

  @override
  String get vaultInfoRequiresUnlockMessage =>
      'Розблокуйте це сховище, щоб переглянути технічні відомості.';

  @override
  String get vaultInfoLoadFailedTitle =>
      'Не вдалося завантажити інформацію про сховище';

  @override
  String get vaultInfoLoadFailedMessage =>
      'Сталася помилка під час зчитування відомостей сховища.';

  @override
  String get vaultInfoVolumeSizeLabel => 'Розмір тому';

  @override
  String get vaultInfoHiddenVolumeLabel => 'Прихований том';

  @override
  String get vaultInfoReadOnlyLabel => 'Лише для читання';

  @override
  String get vaultInfoLuksVersionLabel => 'Версія LUKS';

  @override
  String get vaultInfoSectorSizeLabel => 'Розмір сектора';

  @override
  String get vaultInfoVaultFormatLabel => 'Формат сховища';

  @override
  String get vaultInfoCipherComboLabel => 'Комбінація шифрів';

  @override
  String get vaultInfoShorteningThresholdLabel =>
      'Поріг скорочення імен файлів';

  @override
  String get vaultInfoFormatVersionLabel => 'Версія формату';

  @override
  String get vaultInfoContentCipherLabel => 'Шифр вмісту';

  @override
  String get vaultInfoFilenameEncryptionLabel => 'Імена файлів';

  @override
  String get vaultInfoPlaintextNamesValue => 'Відкритий текст';

  @override
  String get vaultInfoEncryptedNamesValue => 'Зашифровані';

  @override
  String get vaultInfoBlockCipherLabel => 'Блочний шифр';

  @override
  String get vaultInfoBlockSizeLabel => 'Розмір блоку';

  @override
  String get vaultInfoCreatedWithVersionLabel => 'Створено у версії';

  @override
  String get vaultInfoLastOpenedWithVersionLabel =>
      'Востаннє відкрито у версії';

  @override
  String get vaultInfoYesValue => 'Так';

  @override
  String get vaultInfoNoValue => 'Ні';

  @override
  String get vaultInfoBitlockerNote =>
      'Ця програма не зчитує метадані заголовка BitLocker, тому деталі шифрування та версії тут недоступні.';

  @override
  String get patternSetupRequiredAboveBeforeSaving =>
      'Налаштуйте графічний ключ вище перед збереженням.';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      'Для цього методу потрібен пароль або кешований ключ із ключовими файлами.';

  @override
  String get saveConfigurationButton => 'Зберегти конфігурацію';

  @override
  String get incorrectPatternError => 'Невірний графічний ключ';

  @override
  String get verifyPatternTitle => 'Перевірка графічного ключа';

  @override
  String get incorrectPasswordError => 'Невірний пароль';

  @override
  String get verificationFailedError => 'Помилка перевірки';

  @override
  String get incorrectCredentialsError => 'Невірні облікові дані';

  @override
  String get containerPasswordOptionalLabel =>
      'Пароль контейнера (необов\'язково при наявності keyfile)';

  @override
  String get pimOptionalLabel => 'PIM (необов\'язково)';

  @override
  String get usbDriveLockedLabel => 'USB-диск · Заблоковано';

  @override
  String get lockedContainerLabel => 'Заблокований контейнер';

  @override
  String get operationInProgressWaitMessage =>
      'Операція триває. Будь ласка, зачекайте перед блокуванням.';

  @override
  String get reconnectUsbTooltip => 'Перепідключити USB';

  @override
  String get unlockContainerTooltip => 'Розблокувати контейнер';

  @override
  String lockFailedMessage(String errorType) {
    return 'Помилка блокування: $errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired =>
      'Потрібен новий пароль або ключ. файли.';

  @override
  String get newPasswordsDoNotMatch => 'Нові паролі не збігаються.';

  @override
  String get passwordChangedSuccessfullyMessage => 'Пароль успішно змінено.';

  @override
  String get failedToChangePasswordMessage =>
      'Не вдалося змінити пароль. Перевірте старі дані.';

  @override
  String get currentCredentialsSectionHeader => 'Поточні облікові дані';

  @override
  String get oldPasswordLabel => 'Старий пароль';

  @override
  String get oldPimOptionalLabel => 'Старий PIM (необов\'язково)';

  @override
  String get newCredentialsSectionHeader => 'Нові облікові дані';

  @override
  String get newPimOptionalLabel => 'Новий PIM (необов\'язково)';

  @override
  String get noContainersYetTitle => 'Сховищ ще немає';

  @override
  String get dashboardEmptyStateMessage =>
      'Змонтуйте контейнер VeraCrypt, підключіть USB-диск або створіть нове зашифроване сховище.';

  @override
  String get sortFieldName => 'Назва';

  @override
  String get sortFieldSize => 'Розмір';

  @override
  String get sortFieldType => 'Тип';

  @override
  String get sortFieldDate => 'Дата';

  @override
  String get layoutModeDetailedList => 'Детальний список';

  @override
  String get layoutModeCompactList => 'Компактний список';

  @override
  String get layoutModeGalleryGrid => 'Галерея (сітка)';

  @override
  String get readOnlyCantDeleteTooltip => 'Лише читання — видалення неможливе';

  @override
  String get readOnlyCantMoveTooltip => 'Лише читання — переміщення неможливе';

  @override
  String get readOnlyCantRenameTooltip =>
      'Лише читання — перейменування неможливе';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes (обчислення…)';
  }

  @override
  String get sizeCalculatingLabel => 'обчислення…';

  @override
  String get editSecureItemsToRenameMessage =>
      'Редагуйте захищені записи для їх перейменування';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage =>
      'Елементи сховища не можна відкривати у сторонніх програмах';

  @override
  String get mountedReadOnlyTooltip => 'Змонтовано лише для читання';

  @override
  String get readOnlyBadgeAbbreviation => 'RO';

  @override
  String freeSpaceLabel(String bytes) {
    return 'вільно $bytes';
  }

  @override
  String get filteredLabel => 'відфільтровано';

  @override
  String get statsStorageSectionHeader => 'ПАМ\'ЯТЬ';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count папок',
      many: '$count папок',
      few: '$count папки',
      one: '1 папка',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файлів',
      many: '$count файлів',
      few: '$count файли',
      one: '1 файл',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => 'Усі файли';

  @override
  String get filterImagesOption => 'Зображення';

  @override
  String get filterVideosOption => 'Відео';

  @override
  String get filterAudioOption => 'Аудіо';

  @override
  String get filterDocumentsOption => 'Документи';

  @override
  String get folderExposedAsStorageExplanation =>
      'Ця папка відкрита як окреме сховище, тому інші програми можуть відкривати її файли напряму.';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count елементів уже існують',
      many: '$count елементів уже існують',
      few: '$count елементи вже існують',
      one: '1 елемент уже існує',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle =>
      'Виберіть дію для кожного елемента або застосуйте одну дію до всіх.';

  @override
  String get skipAllChipLabel => 'Пропустити всі';

  @override
  String get overwriteAllChipLabel => 'Перезаписати всі';

  @override
  String get overwriteItemDropdownLabel => 'Перезаписати';

  @override
  String get overwriteFolderDropdownLabel => 'Перезаписати папку';

  @override
  String get fileOpsTransfersInProgressTitle => 'Операції передачі';

  @override
  String get fileOpsRecentTransfersTitle => 'Останні передачі';

  @override
  String get fileOpsNoRecentTransfersMessage => 'Немає недавніх передач';

  @override
  String get fileOpsNoRecentTransfersSubtitle =>
      'Операції копіювання, переміщення та видалення відображатимуться тут під час виконання.';

  @override
  String fileOpsShowDetailsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count елементів',
      many: '$count елементів',
      few: '$count елементи',
      one: '1 елемент',
    );
    return '$_temp0';
  }

  @override
  String get fileOpsCancelTooltip => 'Скасувати';

  @override
  String get fileOpsRootDestinationLabel => 'Корінь';

  @override
  String get fileOpsCancelledStatusLabel => 'Скасовано';

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
    return '+ ще $count';
  }

  @override
  String get transferActivityTooltip => 'Передавання';

  @override
  String fileOpsSpeedLabel(String speed) {
    return '$speed/с';
  }

  @override
  String fileOpsEtaLabel(String time) {
    return 'Залишилося ~$time';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return 'Помилка читання файлу: $error';
  }

  @override
  String get archivePreviewNotAvailableMessage =>
      'Попередній перегляд недоступний для цього типу файлу.';

  @override
  String get avifFailedToRenderMessage => 'Не вдалося відтворити AVIF';

  @override
  String get encryptedImageLoadFailedMessage =>
      'Не вдалося завантажити зашифроване зображення';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return 'Не вдалося завантажити зображення: $error';
  }

  @override
  String get invalidOrCorruptedImageMessage =>
      'Недійсний або пошкоджений формат зображення.';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '$current з $total';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '$current з $total · сканування…';
  }

  @override
  String get mediaViewerScanningLabel => 'Сканування…';

  @override
  String get mediaFileDeletedMessage => 'Файл успішно видалено';

  @override
  String get mediaFileDeleteFailedMessage => 'Не вдалося видалити файл';

  @override
  String get mediaFileRenamedMessage => 'Файл успішно перейменовано';

  @override
  String get aboutScreenTitle => 'Про програму';

  @override
  String get couldNotOpenLinkMessage => 'Не вдалося відкрити посилання';

  @override
  String get fileManagerSettingsTitle => 'Налаштування файлового менеджера';

  @override
  String get showMediaThumbnailsLabel => 'Показувати мініатюри медіа';

  @override
  String get showMediaThumbnailsDesc =>
      'Відображати попередній перегляд зображень та відео у списку';

  @override
  String get showFileNamesLabel => 'Показувати назви файлів';

  @override
  String get showFileNamesDesc =>
      'Відображати текстові підписи під елементами в сітці';

  @override
  String get showBreadcrumbBarLabel => 'Показувати рядок шляху';

  @override
  String get showBreadcrumbBarDesc => 'Панель навігації по папках угорі';

  @override
  String get showStatsBarLabel => 'Показувати рядок статистики';

  @override
  String get showStatsBarDesc =>
      'Інформація про кількість файлів та вільне місце';

  @override
  String get autoStartPlaylistModeLabel => 'Автозапуск режиму списку';

  @override
  String get autoStartPlaylistModeDesc =>
      'Автоматично відкривати список при перегляді медіа';

  @override
  String get showPlaylistCarouselLabel => 'Показувати карусель списку';

  @override
  String get showPlaylistCarouselDesc =>
      'Кнопка каруселі мініатюр під час перегляду списку медіа';

  @override
  String get videoPlaybackSliderLabel => 'Повзунок позиції відео';

  @override
  String get longPressPlaybackDiagnosticsHint =>
      'Затисніть для діагностики відтворення';

  @override
  String get staticImageModeLabel => 'Режим статичного зображення';

  @override
  String slideshowModeActiveLabel(int seconds) {
    return 'Активне слайд-шоу із затримкою $seconds с';
  }

  @override
  String videoPlaybackModeLabel(String mode) {
    return 'Режим відтворення відео: $mode';
  }

  @override
  String get pauseLabel => 'Пауза';

  @override
  String get playLabel => 'Відтворити';

  @override
  String get emptyFolderTitle => 'Порожня папка';

  @override
  String get emptyFolderMessage =>
      'Використовуйте дію \"Додати\" для створення файлів або імпорту з пристрою.';

  @override
  String get noResultsTitle => 'Нічого не знайдено';

  @override
  String noResultsForQueryMessage(String query) {
    return 'У цій папці немає збігів за запитом \"$query\".';
  }

  @override
  String get closeCarouselTooltip => 'Закрити карусель';

  @override
  String get playlistScrollModeMenu => 'Режим прокручування списку';

  @override
  String get playlistScrollHorizontalLabel => 'Горизонтальний';

  @override
  String get playlistScrollVerticalPageLabel => 'Вертикальний (посторінково)';

  @override
  String get playlistScrollVerticalContinuousLabel =>
      'Вертикальний (безперервно)';

  @override
  String get undoTooltip => 'Скасувати';

  @override
  String get redoTooltip => 'Повторити';

  @override
  String get autosavingLabel => 'Автозбереження…';

  @override
  String get savingLabel => 'Збереження…';

  @override
  String autosavedAtLabel(String time) {
    return 'Автозбережено о $time';
  }

  @override
  String cameraDisconnectedError(String message) {
    return 'Камеру відключено: $message';
  }

  @override
  String get unknownErrorFallback => 'невідома помилка';

  @override
  String get cameraPermissionsRequiredMessage =>
      'Для використання камери потрібні дозволи на камеру та мікрофон.';

  @override
  String cameraErrorMessage(String error) {
    return 'Помилка камери: $error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage => 'Не вдалося зробити фото';

  @override
  String get cameraRecordingFailedMessage => 'Помилка запису відео';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return 'Помилка запису: $error';
  }

  @override
  String get cameraRecordingTooShortMessage =>
      'Запис занадто короткий для збереження';

  @override
  String get cameraCouldNotSaveRecordingMessage => 'Не вдалося зберегти запис';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return 'Не вдалося зберегти запис: $error';
  }

  @override
  String get cameraCouldNotSwitchLensMessage =>
      'Не вдалося перемкнути об\'єктив';

  @override
  String get cameraEncryptingPhotoLabel => 'Шифрування фото…';

  @override
  String get cameraEncryptingVideoLabel => 'Шифрування відео…';

  @override
  String get aboutApplicationSectionHeader => 'Програма';

  @override
  String get aboutTagline =>
      'Вільне · Відкрите · Автономне зашифроване сховище';

  @override
  String get aboutVersionTitle => 'Версія';

  @override
  String aboutVersionSubtitle(String version) {
    return 'v$version · Торкніться, щоб скопіювати версію для звіту';
  }

  @override
  String get aboutWhatsNewTitle => 'Що нового';

  @override
  String get aboutWhatsNewSubtitle => 'Останні зміни та примітки до випуску';

  @override
  String get aboutPrivacySecurityTitle => 'Конфіденційність і безпека';

  @override
  String get aboutPrivacySecuritySubtitle =>
      'Zero-trust, 100% офлайн, локальна безпека в пам\'яті';

  @override
  String get aboutSupportedFormatsSectionHeader => 'Підтримувані формати';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt та LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      'Стандартні та приховані томи, власний PIM, keyfiles, xts-plain64, Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker та BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle =>
      'Паролі користувача та 48-значні цифрові ключі відновлення';

  @override
  String get aboutDirectoryVaultsTitle => 'Сховища папок';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator (v7/v8 SIV_GCM & SIV_CTRMAC), gocryptfs (v2 AES-GCM & XChaCha20), CryFS (v0.10+ XChaCha20 & AES)';

  @override
  String get aboutVhdTitle => 'Віртуальні диски (VHD / VHDX)';

  @override
  String get aboutVhdSubtitle =>
      'Трансляція BAT для фіксованих та динамічних образів дисків';

  @override
  String get aboutNativeCoreEngineSectionHeader => 'Вбудований рушій (C++)';

  @override
  String get aboutCompiledLibrariesTitle => 'Скомпільовані бібліотеки C++';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.0 (Апаратне шифрування ARMv8 та SHA-2)\n• libavif & libgav1 (Нативний декодер AVIF)\n• ChaN FatFs v4.0.4 (FAT12/16/32 та exFAT)\n• Tuxera NTFS-3G & вбудований mkntfs\n• e2fsprogs v1.47.4 libext2fs (ext2/ext3/ext4)\n• Dislocker Virtual I/O (BitLocker FVE / To Go)\n• VeraCrypt 1.26.29 (Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id/i)\n• cJSON v1.7.18 (метадані LUKS2 та Cryptomator)';

  @override
  String get aboutCommunitySectionHeader => 'Спільнота та відкритий код';

  @override
  String get aboutReportIssueTitle => 'Повідомити про помилку';

  @override
  String get aboutReportIssueSubtitle =>
      'Знайшли баг? Створіть issue на GitHub';

  @override
  String get aboutContributorsTitle => 'Співавтори';

  @override
  String get aboutContributorsSubtitle =>
      'Люди, які допомагали у створенні VaultExplorer';

  @override
  String get aboutLicensesTitle => 'Ліцензії відкритого коду';

  @override
  String get aboutLicensesSubtitle =>
      'Сторонні бібліотеки, використані у програмі';

  @override
  String get aboutFooterMadeWithLove => 'Створено з ❤ для приватності.';

  @override
  String get aboutVersionCopiedMessage => 'Інформацію про версію скопійовано';

  @override
  String aboutVersionClipboardText(String version) {
    return 'VaultExplorer v$version (Android)';
  }

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer — безкоштовне, відкрите та автономне зашифроване сховище для Android.\n\nЗберігайте паролі, нотатки та файли всередині зашифрованих контейнерів (VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs, CryFS).\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage =>
      'Посилання для поширення скопійовано в буфер';

  @override
  String get aboutPrivacySheetTitle => 'Конфіденційність і безпека даних';

  @override
  String get aboutPrivacySheetSubtitle =>
      '100% офлайн, безпечна архітектура без доступу до мережі';

  @override
  String get privacyPointNoNetworkTitle => 'Доступ до інтернету не потрібен';

  @override
  String get privacyPointNoNetworkBody =>
      'VaultExplorer взагалі не запитує дозвіл android.permission.INTERNET на Android і фізично не може надсилати чи отримувати дані мережею.';

  @override
  String get privacyPointNoDiskLeaksTitle =>
      'Жодних витоків незашифрованих даних на диск';

  @override
  String get privacyPointNoDiskLeaksBody =>
      'Дешифрування та шифрування відбуваються виключно в оперативній пам\'яті. Тимчасові незашифровані файли ніколи не зберігаються на внутрішньому накопичувачі.';

  @override
  String get privacyPointNoAnalyticsTitle => 'Без аналітики та телеметрії';

  @override
  String get privacyPointNoAnalyticsBody =>
      'У програмі повністю відсутні збір помилок, трекери активності чи сторонні SDK, що збирають інформацію про вас чи ваш пристрій.';

  @override
  String get privacyPointKeystoreTitle => 'Секрети захищені в Android Keystore';

  @override
  String get privacyPointKeystoreBody =>
      'Збережені паролі, графічні ключі та похідні ключі шифруються за допомогою AES-256-GCM в апаратно захищеному сховищі Android Keystore.';

  @override
  String get privacyPointPosixTitle => 'Прискорення POSIX та прямий доступ';

  @override
  String get privacyPointPosixBody =>
      'Файли всередині контейнерів обробляються локально. При наявності прямого доступу операції відбуваються в обхід повільного SAF, прискорюючи введення/виведення до 1000 разів.';

  @override
  String get privacyPointScreenClipboardTitle =>
      'Захист екрана та буфера обміну';

  @override
  String get privacyPointScreenClipboardBody =>
      'Блокування знімків екрана та мініатюр у списку додатків (FLAG_SECURE), а також автоматичне очищення буфера обміну.';

  @override
  String get privacyPointMaskModeTitle => 'Режим маскування';

  @override
  String get privacyPointMaskModeBody =>
      'За бажанням маскує програму під повноцінний переглядач zip-архівів із іншою назвою та іконкою. Затисніть заголовок на 3 секунди, щоб відкрити справжнє сховище.';

  @override
  String get privacyPointExternalLinksTitle =>
      'Зовнішні посилання відкриваються у браузері';

  @override
  String get privacyPointExternalLinksBody =>
      'Натискання на зовнішні посилання відкриває ваш стандартний системний браузер.';

  @override
  String get truncatedListingWarning =>
      'Показано перші 50 000 елементів — у цій папці більше файлів.';

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '$size пкс · $quality% якості';
  }

  @override
  String holdToSpeedIndicatorLabel(String speed) {
    return '$speed× швидкість';
  }

  @override
  String get toolbarLayoutSectionHeader => 'Панель інструментів';

  @override
  String get listViewOptionsSectionHeader => 'Параметри списку';

  @override
  String get detailedListViewColumnsSectionHeader =>
      'Стовпці детального списку';

  @override
  String get galleryGridViewSectionHeader => 'Сітка галереї';

  @override
  String get browserLayoutSectionHeader => 'Макет файлового браузера';

  @override
  String get mediaViewerSectionHeader => 'Переглядач медіа';

  @override
  String get viewModeAction => 'Вигляд';

  @override
  String get sortAction => 'Сортування';

  @override
  String get playMediaAction => 'Відтворити';

  @override
  String containerSpaceSummary(String free, String total) {
    return 'вільно $free · всього $total';
  }

  @override
  String volMountedSummary(int volId) {
    return 'Том $volId · Змонтовано';
  }

  @override
  String vaultOccupiedSpaceSummary(String used) {
    return 'Використано $used';
  }

  @override
  String get incorrectPasswordOrKeyfilesDriveError =>
      'Невірний пароль/ключовий файл або непідтримуваний диск';

  @override
  String driveUsableCapacity(int mb) {
    return 'Корисна місткість диска: $mb МБ. Розмір не повинен перевищувати це значення.';
  }

  @override
  String get unlockMethodManualPassword => 'Пароль вручну';

  @override
  String get unlockMethodRememberPassword => 'Збережений пароль';

  @override
  String get unlockMethodBiometrics => 'Біометричне розблокування';

  @override
  String get unlockMethodPattern => 'Графічний ключ';

  @override
  String get unlockMethodSubtitlePassword => 'Вводити пароль щоразу';

  @override
  String get unlockMethodSubtitleRememberPassword =>
      'Надійно збережено в Android Keystore';

  @override
  String get unlockMethodSubtitleBiometrics =>
      'Використовувати відбиток пальця або обличчя';

  @override
  String get unlockMethodSubtitlePattern => 'Намалювати графічний ключ';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError =>
      'Відеодекодер недоступний — конфлікт апаратних кодеків';

  @override
  String get mediaStreamInitFailedError => 'Помилка ініціалізації медіапотоку';

  @override
  String get invalidAvifImage => 'Недійсне або пошкоджене зображення AVIF';

  @override
  String get verbImport => 'Імпортувати';

  @override
  String get verbMove => 'Перемістити';

  @override
  String get verbCopy => 'Копіювати';

  @override
  String get verbDelete => 'Видалити';

  @override
  String get verbImported => 'Імпортовано';

  @override
  String get verbMoved => 'Переміщено';

  @override
  String get verbCopied => 'Скопійовано';

  @override
  String get verbDeleted => 'Видалено';

  @override
  String get verbImporting => 'Імпортування';

  @override
  String get verbMoving => 'Переміщення';

  @override
  String get verbCopying => 'Копіювання';

  @override
  String get verbDeleting => 'Видалення';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count елементів',
      many: '$count елементів',
      few: '$count елементи',
      one: '1 елемент',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count елементів $verb',
      many: '$count елементів $verb',
      few: '$count елементи $verb',
      one: '1 елемент $verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return 'пропущено: $count';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return 'помилок: $count';
  }

  @override
  String get statusCancelled => 'Скасовано';

  @override
  String get statusFailed => 'Помилка';

  @override
  String get statusCompleted => 'Завершено';

  @override
  String get fileOpCheckingSpace => 'Перевірка вільного місця…';

  @override
  String get fileOpResolvingConflicts => 'Вирішення конфліктів…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return 'Недостатньо місця — потрібно $required, вільно лише $free';
  }

  @override
  String get fileOpDiskFullPartialRemoved =>
      'Диск заповнено — часткові файли видалено';

  @override
  String get fileOpMoveFailed => 'Помилка переміщення';

  @override
  String get fileOpCopyFailed => 'Помилка копіювання';

  @override
  String get fileOpDeleteFailed => 'Не вдалося видалити';

  @override
  String get fileOpDiskFull => 'Диск заповнено';

  @override
  String get fileOpImporting => 'Імпортування…';

  @override
  String fileOpImportingName(String name) {
    return 'Імпортування $name…';
  }

  @override
  String fileOpMovingName(String name) {
    return 'Переміщення $name…';
  }

  @override
  String fileOpCopyingName(String name) {
    return 'Копіювання $name…';
  }

  @override
  String get fileOpDeleting => 'Видалення…';

  @override
  String fileOpDeletingName(String name) {
    return 'Видалення $name…';
  }

  @override
  String fileOpDeletedSoFar(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Видалено $count елементів',
      many: 'Видалено $count елементів',
      few: 'Видалено $count елементи',
      one: 'Видалено 1 елемент',
    );
    return '$_temp0';
  }

  @override
  String get searchInSubfoldersHint => 'Шукати в усіх підпапках…';

  @override
  String get deepSearchEnabledTooltip =>
      'Пошук у підпапках — торкніться для пошуку лише в поточній папці';

  @override
  String get deepSearchDisabledTooltip =>
      'Пошук у поточній папці — торкніться для пошуку у підпапках';

  @override
  String get filterAction => 'Фільтр';

  @override
  String get bookmarkAction => 'Додати до закладок';

  @override
  String get unbookmarkAction => 'Вилучити із закладок';

  @override
  String get bookmarkSelectedAction => 'Додати вибране до закладок';

  @override
  String get unbookmarkSelectedAction => 'Вилучити вибране із закладок';

  @override
  String bookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Додано до закладок $count елементів',
      many: 'Додано до закладок $count елементів',
      few: 'Додано до закладок $count елементи',
      one: 'Додано до закладок 1 елемент',
    );
    return '$_temp0';
  }

  @override
  String unbookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вилучено із закладок $count елементів',
      many: 'Вилучено із закладок $count елементів',
      few: 'Вилучено із закладок $count елементи',
      one: 'Вилучено із закладок 1 елемент',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => 'Показувати панель закладок';

  @override
  String get showBookmarkBarDesc =>
      'Відображати обрані папки на панелі закладок';

  @override
  String get bookmarkBarSectionHeader => 'Панель закладок та обране';

  @override
  String get noBookmarksYet => 'Обраних папок ще немає';

  @override
  String get reorderBookmarksTitle => 'Впорядкувати закладки';

  @override
  String get reorderBookmarksDesc =>
      'Перетягуйте елементи для зміни їхнього порядку';

  @override
  String get navBarVaultsLabel => 'Сховища';

  @override
  String get navBarToolsLabel => 'Інструменти';

  @override
  String get toolsScreenTitle => 'Інструменти';

  @override
  String get toolsSectionContainerUtilities => 'Утиліти контейнерів';

  @override
  String get toolsSectionFileCryptography => 'Криптографія файлів';

  @override
  String get toolsSectionStorageDiagnostics => 'Пам\'ять та діагностика';

  @override
  String get toolContainerSplitterTitle => 'Розділення та об\'єднання';

  @override
  String get toolContainerSplitterSubtitle =>
      'Розділити контейнер на частини або з\'єднати їх знову';

  @override
  String get toolContainerRepairTitle => 'Перевірка та відновлення';

  @override
  String get toolContainerRepairSubtitle =>
      'Діагностика заголовка або файлової системи';

  @override
  String get toolSingleFileCryptoTitle => 'Шифрування файлів';

  @override
  String get toolSingleFileCryptoSubtitle =>
      'Захист окремих файлів без створення повного сховища';

  @override
  String get toolStorageAnalyzerTitle => 'Аналізатор пам\'яті';

  @override
  String get toolStorageAnalyzerSubtitle =>
      'Візуалізація зайнятого простору у відкритому сховищі';

  @override
  String get toolDuplicateFinderTitle => 'Пошук дублікатів файлів';

  @override
  String get toolDuplicateFinderSubtitle =>
      'Пошук та видалення байт-у-байт однакових файлів для звільнення місця';

  @override
  String get toolHashVerifierTitle => 'Перевірка контрольних сум і хешів';

  @override
  String get toolHashVerifierSubtitle =>
      'Перевірка цілісності великих файлів за допомогою контрольних сум MD5/SHA';

  @override
  String get hashVerifierModeCompute => 'Обчислення';

  @override
  String get hashVerifierModeVerify => 'Перевірка';

  @override
  String get hashVerifierSelectSourceTitle => 'Вибір джерела файлів';

  @override
  String get hashVerifierAlgorithmsLabel => 'Алгоритми';

  @override
  String get hashVerifierNoAlgorithmSelected =>
      'Виберіть щонайменше один алгоритм';

  @override
  String get hashVerifierFilesLabel => 'Файли для хешування';

  @override
  String hashVerifierFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вибрано $count файлів',
      many: 'Вибрано $count файлів',
      few: 'Вибрано $count файли',
      one: 'Вибрано 1 файл',
      zero: 'Файли не вибрано',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierComputeButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Обчислити $count хешів',
      many: 'Обчислити $count хешів',
      few: 'Обчислити $count хеші',
      one: 'Обчислити хеш',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCancelButton => 'Скасувати';

  @override
  String hashVerifierBatchProgressLabel(Object current, Object total) {
    return 'Файл $current із $total';
  }

  @override
  String get hashVerifierCancelledMessage => 'Скасовано.';

  @override
  String hashVerifierComputeErrorsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Не вдалося обчислити хеш для $count файлів',
      many: 'Не вдалося обчислити хеш для $count файлів',
      few: 'Не вдалося обчислити хеш для $count файлів',
      one: 'Не вдалося обчислити хеш для 1 файлу',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCopiedMessage => 'Скопійовано в буфер обміну';

  @override
  String get hashVerifierExportManifestButton => 'Експортувати як маніфест';

  @override
  String get hashVerifierExportAlgorithmLabel => 'Алгоритм маніфесту';

  @override
  String hashVerifierExportSuccessMessage(Object path) {
    return 'Збережено до $path';
  }

  @override
  String hashVerifierExportFailedMessage(Object error) {
    return 'Помилка експорту: $error';
  }

  @override
  String get hashVerifierLoadManifestButton => 'Завантажити маніфест';

  @override
  String get hashVerifierChangeManifestButton => 'Змінити';

  @override
  String get hashVerifierManifestLabel => 'Файл маніфесту';

  @override
  String hashVerifierManifestEntryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count записів',
      many: '$count записів',
      few: '$count записи',
      one: '1 запис',
      zero: 'Немає записів',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierAutoAddFolderButton => 'Додати всі файли з цієї папки';

  @override
  String get hashVerifierAddFilesToVerifyButton => 'Додати файли для перевірки';

  @override
  String get hashVerifierVerifyAllButton => 'Перевірити все';

  @override
  String hashVerifierVerifyProgressLabel(Object current, Object total) {
    return 'Перевірка файлу $current із $total';
  }

  @override
  String hashVerifierSummaryMessage(
    Object ok,
    Object mismatch,
    Object missing,
  ) {
    return '$ok збігається, $mismatch не збігається, $missing відсутньо';
  }

  @override
  String get hashVerifierStatusMatch => 'Збігається';

  @override
  String get hashVerifierStatusMismatch => 'Незбіг';

  @override
  String get hashVerifierStatusMissing => 'Файл не додано';

  @override
  String get hashVerifierStatusPending => 'Ще не перевірено';

  @override
  String get hashVerifierExpectedLabel => 'Очікуваний';

  @override
  String get hashVerifierActualLabel => 'Фактичний';

  @override
  String hashVerifierExtraFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count додаткових файлів, яких немає в маніфесті',
      many: '$count додаткових файлів, яких немає в маніфесті',
      few: '$count додаткові файли, яких немає в маніфесті',
      one: '1 додатковий файл, якого немає в маніфесті',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierNoManifestLoadedMessage =>
      'Завантажте файл маніфесту, щоб почати';

  @override
  String get hashVerifierManifestParseEmptyMessage =>
      'У цьому файлі не знайдено записів контрольних сум';

  @override
  String hashVerifierLoadManifestFailedMessage(Object error) {
    return 'Не вдалося прочитати маніфест: $error';
  }

  @override
  String hashVerifierAutoAddedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Додано $count файлів із папки сховища',
      many: 'Додано $count файлів із папки сховища',
      few: 'Додано $count файли з папки сховища',
      one: 'Додано 1 файл із папки сховища',
      zero: 'Нових файлів не знайдено',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierModeVault => 'Сховище';

  @override
  String get hashVerifierVaultPickerLabel => 'Сховище';

  @override
  String get hashVerifierVaultNoVaultsMessage =>
      'Наразі немає змонтованих сховищ';

  @override
  String get hashVerifierCheckEntireVaultButton => 'Перевірити все сховище';

  @override
  String get hashVerifierVaultScanningLabel => 'Сканування сховища…';

  @override
  String hashVerifierVaultFilesDiscoveredLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Виявлено $count файлів',
      many: 'Виявлено $count файлів',
      few: 'Виявлено $count файли',
      one: 'Виявлено 1 файл',
      zero: 'Файлів ще не виявлено',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmTitle => 'Перевірити все сховище?';

  @override
  String hashVerifierVaultConfirmFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файлів',
      many: '$count файлів',
      few: '$count файли',
      one: '1 файл',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmWarning =>
      'Буде прочитано кожен файл у цьому сховищі.';

  @override
  String get hashVerifierVaultEmptyMessage =>
      'У цьому сховищі немає файлів для перевірки';

  @override
  String get hashVerifierVaultStartButton => 'Почати перевірку';

  @override
  String hashVerifierVaultHashingProgressLabel(Object current, Object total) {
    return 'Перевірка $current / $total';
  }

  @override
  String get hashVerifierVaultCompleteTitle => 'Перевірку сховища завершено';

  @override
  String hashVerifierVaultCompleteFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Перевірено $count файлів',
      many: 'Перевірено $count файлів',
      few: 'Перевірено $count файли',
      one: 'Перевірено 1 файл',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteBytesLabel(Object size) {
    return 'Оброблено $size';
  }

  @override
  String hashVerifierVaultCompleteSucceededLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count успішно',
      many: '$count успішно',
      few: '$count успішно',
      one: '1 успішно',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count з помилками',
      many: '$count з помилками',
      few: '$count з помилками',
      one: '1 з помилкою',
      zero: '0 з помилкою',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultElapsedLabel(Object time) {
    return 'Витрачено часу: $time';
  }

  @override
  String get hashVerifierVaultCancelledMessage =>
      'Перевірку сховища скасовано.';

  @override
  String hashVerifierVaultFailedMessage(Object error) {
    return 'Помилка перевірки сховища: $error';
  }

  @override
  String get hashVerifierVaultNewCheckButton => 'Нова перевірка';

  @override
  String get hashVerifierVaultActionComputeTitle =>
      'Обчислити для всього сховища';

  @override
  String get hashVerifierVaultActionComputeSubtitle =>
      'Обчислити хеш кожного файлу у сховищі';

  @override
  String get hashVerifierVaultActionVerifyTitle => 'Перевірити все сховище';

  @override
  String get hashVerifierVaultActionVerifySubtitle =>
      'Перевірити всі файли сховища за завантаженим маніфестом';

  @override
  String get hashVerifierVaultChangeActionButton => 'Змінити';

  @override
  String get hashVerifierVaultVerifyButton => 'Перевірити все сховище';

  @override
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage =>
      'Для перевірки всього сховища потрібен маніфест, завантажений із середини сховища.';

  @override
  String get duplicateFinderTargetLabel => 'Цільове сховище';

  @override
  String get duplicateFinderTargetAllVaults => 'Усі відкриті сховища';

  @override
  String get duplicateFinderStartScan => 'Почати сканування';

  @override
  String get duplicateFinderCancelScan => 'Скасувати';

  @override
  String get duplicateFinderRescan => 'Повторити';

  @override
  String get duplicateFinderScanningStage1 =>
      'Етап 1: Індексація та групування за розміром...';

  @override
  String get duplicateFinderScanningStage2 =>
      'Етап 2: Перевірка заголовків файлів...';

  @override
  String get duplicateFinderScanningStage3 =>
      'Етап 3: Повна перевірка хешів SHA-256...';

  @override
  String get duplicateFinderScanComplete => 'Сканування завершено';

  @override
  String get duplicateFinderNoDuplicatesTitle => 'Дублікатів не знайдено';

  @override
  String get duplicateFinderNoDuplicatesMessage =>
      'Усі файли у вибраних сховищах мають унікальний вміст.';

  @override
  String get duplicateFinderSelectRedundant => 'Вибрати зайві копії';

  @override
  String get duplicateFinderSelectAll => 'Вибрати все';

  @override
  String get duplicateFinderDeselectAll => 'Зняти виділення';

  @override
  String get duplicateFinderOriginalLabel => 'Оригінал';

  @override
  String get duplicateFinderDuplicateLabel => 'Дублікат';

  @override
  String get duplicateFinderConfirmDeleteTitle => 'Видалити дублікати файлів?';

  @override
  String get duplicateFinderSearchHint =>
      'Пошук дублікатів за назвою або шляхом...';

  @override
  String get toolNotImplementedYetMessage =>
      'Цей інструмент буде підключено у наступному оновленні.';

  @override
  String get splitJoinModeSplit => 'Розділити';

  @override
  String get splitJoinModeJoin => 'Об\'єднати';

  @override
  String get splitSourceFileLabel => 'Вхідний файл';

  @override
  String get splitDestinationFolderLabel => 'Папка призначення';

  @override
  String get splitChunkSizeLabel => 'Розмір частини';

  @override
  String get splitChunkSizeCustomLabel => 'Власний розмір (МБ)';

  @override
  String get splitChunkSizeFourMb => '4 МБ';

  @override
  String get splitChunkSizeCloud8mb => '8 МБ';

  @override
  String get splitChunkSizeCloud32mb => '32 МБ';

  @override
  String get splitChunkSizeCloud => '100 МБ';

  @override
  String get splitChunkSizeFat32 => '2 ГБ';

  @override
  String get splitChunkSizeFourGb => '4 ГБ';

  @override
  String get splitChunkSizeCustom => 'Власний розмір';

  @override
  String get splitContainerButton => 'Розділити контейнер';

  @override
  String get joinFirstPartLabel => 'Перша частина (.001)';

  @override
  String get joinOutputFileNameLabel => 'Назва вихідного файлу';

  @override
  String get joinContainerButton => 'Об\'єднати файли';

  @override
  String get chooseFileButton => 'Вибрати файл';

  @override
  String get chooseFolderButton => 'Вибрати папку';

  @override
  String get noFileSelectedLabel => 'Файл не вибрано';

  @override
  String get noFolderSelectedLabel => 'Папку не вибрано';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage =>
      'Контейнер успішно розділено на частини';

  @override
  String get joinContainerSuccessMessage => 'Файли успішно об\'єднано';

  @override
  String get cryptoDirectionEncrypt => 'Зашифрувати';

  @override
  String get cryptoDirectionDecrypt => 'Розшифрувати';

  @override
  String get singleFileCryptoInputFileLabel => 'Вхідні файли';

  @override
  String get singleFileCryptoCipherLabel => 'Шифр';

  @override
  String get singleFileCryptoDeleteOriginalLabel =>
      'Видалити оригінальні файли після шифрування';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Зашифрувати $count файлів',
      many: 'Зашифрувати $count файлів',
      few: 'Зашифрувати $count файли',
      one: 'Зашифрувати файл',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Розшифрувати $count файлів',
      many: 'Розшифрувати $count файлів',
      few: 'Розшифрувати $count файли',
      one: 'Розшифрувати файл',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Готово — $count файлів оброблено',
      many: 'Готово — $count файлів оброблено',
      few: 'Готово — $count файли оброблено',
      one: 'Готово',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return 'Оброблено $succeeded з $total файлів — $failed з помилкою';
  }

  @override
  String get singleFileCryptoAddFilesButton => 'Додати файли';

  @override
  String get singleFileCryptoClearFilesButton => 'Очистити';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Вибрано $count файлів',
      many: 'Вибрано $count файлів',
      few: 'Вибрано $count файли',
      one: 'Вибрано 1 файл',
      zero: 'Файли не вибрано',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return 'Файл $current з $total';
  }

  @override
  String get repairTargetStepTitle => 'Виберіть ціль';

  @override
  String get repairTargetUnmountedFileOption => 'Незмонтований файл контейнера';

  @override
  String get repairTargetUnmountedFileSubtitle =>
      'Відновити заголовок з резервної копії для закритого контейнера';

  @override
  String get repairTargetMountedVolumeSubtitle =>
      'Перевірити файлову систему відкритого сховища';

  @override
  String get repairNoMountedVolumes => 'Наразі немає відкритих сховищ';

  @override
  String get repairScanButton => 'Запустити діагностику';

  @override
  String get repairChangeTargetButton => 'Змінити ціль';

  @override
  String get repairDiagnosisHealthy => 'Проблем не виявлено';

  @override
  String get repairDiagnosisHeaderCorrupted => 'Заголовок пошкоджено';

  @override
  String get repairDiagnosisFilesystemDirty =>
      'Файлова система містить помилки / некоректне закриття';

  @override
  String get repairRestoreBackupHeaderButton =>
      'Відновити заголовок з резервної копії';

  @override
  String get repairRunFilesystemCheckButton =>
      'Перевірити та виправити файлову систему';

  @override
  String get repairActionSucceededMessage => 'Відновлення успішно завершено';

  @override
  String get repairActionFailedMessage => 'Не вдалося виконати відновлення';

  @override
  String get storageAnalyzerTargetLabel => 'Том';

  @override
  String get storageAnalyzerNoTargetsTitle => 'Нічого аналізувати';

  @override
  String get storageAnalyzerNoTargetsMessage =>
      'Спочатку відкрийте сховище, а потім поверніться сюди для перегляду аналітики.';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return 'використано $used з $total';
  }

  @override
  String get storageAnalyzerHeaviestFilesHeader => 'Найбільші файли';

  @override
  String get storageAnalyzerBreakdownHeader => 'За типами файлів';

  @override
  String get storageAnalyzerScanningMessage => 'Сканування тома…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return 'Сканування зупинено після $count файлів — результати можуть бути неповними.';
  }

  @override
  String get storageAnalyzerNoFilesFound => 'Файлів не знайдено';

  @override
  String get storageCategoryImages => 'Зображення';

  @override
  String get storageCategoryVideos => 'Відео';

  @override
  String get storageCategoryAudio => 'Аудіо';

  @override
  String get storageCategoryDocuments => 'Документи';

  @override
  String get storageCategoryArchives => 'Архіви';

  @override
  String get storageCategoryOther => 'Інше';

  @override
  String get keyfilePassphraseGeneratorTitle =>
      'Генератор паролів і ключових файлів';

  @override
  String get keyfilePassphraseGeneratorSubtitle =>
      'Генерація фраз Diceware, надійних паролів та високоентропійних файлів ключів';

  @override
  String get tabPassphrase => 'Ключова фраза';

  @override
  String get tabKeyfile => 'Ключовий файл';

  @override
  String get modeDiceware => 'Фраза Diceware';

  @override
  String get modeCustomPassword => 'Власний пароль';

  @override
  String get keyfileTypeBinary => 'Бінарний файл ключа (.key)';

  @override
  String get keyfileTypeImage => 'Шумовий графічний ключ (.png)';

  @override
  String get copyPassphraseSuccess =>
      'Ключову фразу скопійовано в захищений буфер';

  @override
  String get copyFingerprintSuccess => 'Відбиток SHA-256 скопійовано в буфер';

  @override
  String get saveKeyfileToVault => 'Зберегти у змонтоване сховище';

  @override
  String get exportKeyfileToStorage => 'Експортувати в пам\'ять пристрою';

  @override
  String get keyfileNoOpenVaultsMessage =>
      'Немає відкритих сховищ. Спочатку змонтуйте том.';

  @override
  String get keyfileSelectDestinationVaultTitle =>
      'Виберіть сховище призначення';

  @override
  String keyfileVolumeIdLabel(Object volId) {
    return 'ID тома: $volId';
  }

  @override
  String keyfileExportSuccessMessage(Object path) {
    return 'Ключовий файл експортовано до $path';
  }

  @override
  String keyfileExportFailedMessage(Object error) {
    return 'Помилка експорту: $error';
  }

  @override
  String keyfileSavedToVaultMessage(Object vaultName, Object path) {
    return 'Ключовий файл збережено в $vaultName: $path';
  }

  @override
  String get keyfileWriteFailedMessage =>
      'Не вдалося записати файл ключа у сховище';

  @override
  String keyfileSaveErrorMessage(Object error) {
    return 'Помилка збереження у сховище: $error';
  }

  @override
  String get passphraseGeneratedSecretLabel => 'Згенерований секрет';

  @override
  String get copyToClipboardTooltip => 'Скопіювати в буфер';

  @override
  String get generateNewTooltip => 'Згенерувати новий';

  @override
  String get passphraseStrengthWeak => 'Слабкий';

  @override
  String get passphraseStrengthGood => 'Добрий';

  @override
  String get passphraseStrengthStrong => 'Надійний';

  @override
  String get passphraseStrengthUnbreakable => 'Незламний';

  @override
  String get passphraseCrackTimeInstant => '< 1 секунди';

  @override
  String get passphraseCrackTimeShort => 'Кілька днів / місяців';

  @override
  String get passphraseCrackTimeCenturies => 'Кілька століть';

  @override
  String get passphraseCrackTimeMillionsOfYears => 'Мільйони років';

  @override
  String passphraseStrengthLabel(Object label) {
    return 'Надійність: $label';
  }

  @override
  String passphraseEntropyBitsLabel(Object bits) {
    return '$bits біт ентропії';
  }

  @override
  String passphraseCrackTimeLabel(Object crackTime) {
    return 'Оціночний час підбору: $crackTime';
  }

  @override
  String get dicewareOptionsTitle => 'Параметри EFF Diceware';

  @override
  String dicewareWordCountLabel(Object count) {
    return 'Кількість слів: $count';
  }

  @override
  String dicewareWordCountBitsLabel(Object bits) {
    return '$bits біт';
  }

  @override
  String dicewareWordCountSliderLabel(Object count) {
    return '$count слів';
  }

  @override
  String get dicewareWordSeparatorLabel => 'Розділювач слів';

  @override
  String get dicewareSeparatorHyphen => 'Дефіс ( - )';

  @override
  String get dicewareSeparatorSpace => 'Пробіл (   )';

  @override
  String get dicewareSeparatorUnderscore => 'Підкреслення ( _ )';

  @override
  String get dicewareSeparatorDot => 'Крапка ( . )';

  @override
  String get dicewareSeparatorSlash => 'Скісна риска ( / )';

  @override
  String get dicewareWordCasingLabel => 'Регістр слів';

  @override
  String get dicewareCasingLowercase => 'малі літери';

  @override
  String get dicewareCasingTitleCase => 'З Великої Літери';

  @override
  String get dicewareCasingUppercase => 'ВЕЛИКІ ЛІТЕРИ';

  @override
  String get dicewareAppendDigitLabel => 'Додати випадкову цифру (0-9)';

  @override
  String get dicewareAppendSymbolLabel => 'Додати спецсимвол (!@#\$%)';

  @override
  String get customPasswordOptionsTitle => 'Параметри пароля';

  @override
  String customPasswordLengthLabel(Object length) {
    return 'Довжина: $length символів';
  }

  @override
  String customPasswordLengthSliderLabel(Object length) {
    return '$length симв.';
  }

  @override
  String get customPasswordUppercaseLabel => 'Великі літери (A-Z)';

  @override
  String get customPasswordLowercaseLabel => 'Малі літери (a-z)';

  @override
  String get customPasswordNumbersLabel => 'Цифри (0-9)';

  @override
  String get customPasswordSymbolsLabel => 'Символи (!@#\$%^&*)';

  @override
  String get customPasswordExcludeAmbiguousLabel =>
      'Виключити схожі символи (1, l, I, 0, O)';

  @override
  String get keyfileBinarySizeTitle => 'Розмір бінарного ключа';

  @override
  String get keyfileImageResolutionTitle => 'Роздільність графічного ключа';

  @override
  String get keyfilePresetBytes64 => '64 байти (стандарт VeraCrypt)';

  @override
  String get keyfilePresetBytes256 => '256 байтів';

  @override
  String get keyfilePresetBytes2048 => '2 КБ';

  @override
  String get keyfilePresetBytes64kb => '64 КБ';

  @override
  String get keyfilePresetBytes1mb => '1 МБ (максимальна межа)';

  @override
  String get keyfilePresetRes64 => '64 x 64 пікселів (~16 КБ)';

  @override
  String get keyfilePresetRes256 => '256 x 256 пікселів (~256 КБ)';

  @override
  String get keyfilePresetRes512 => '512 x 512 пікселів (~1 МБ)';

  @override
  String get keyfileGenerateNewTooltip => 'Згенерувати новий ключ';

  @override
  String keyfileSizeLabel(Object size) {
    return 'Розмір: $size';
  }

  @override
  String get keyfileFingerprintLabel => 'Відбиток SHA-256';

  @override
  String get keyfileCopyFingerprintTooltip => 'Скопіювати відбиток';

  @override
  String get duplicateFinderNoVaultsTitle => 'Немає відкритих сховищ';

  @override
  String get duplicateFinderNoVaultsMessage =>
      'Відкрийте хоча б одне сховище для пошуку дублікатів файлів.';

  @override
  String duplicateFinderConfirmDeleteMessage(Object count, Object size) {
    return 'Ви впевнені, що хочете безповоротно видалити $count дублікатів ($size) зі сховищ? Цю дію не можна буде скасувати.';
  }

  @override
  String get duplicateFinderDeletePermanentlyButton => 'Видалити безповоротно';

  @override
  String duplicateFinderDeleteSuccessMessage(Object count) {
    return 'Успішно видалено $count дублікатів файлів.';
  }

  @override
  String get duplicateFinderIntroTitle => '3-етапний точний пошук дублікатів';

  @override
  String get duplicateFinderIntroSubtitle =>
      'Знаходить повністю ідентичні файли незалежно від їхньої назви.';

  @override
  String get duplicateFinderStagesDescription =>
      '• Етап 1: Групування за розміром (миттєвий аналіз метаданих)\n• Етап 2: Перевірка заголовків (16 КБ SHA-256)\n• Етап 3: Повна звірка хешів SHA-256 (100% збіг байтів)';

  @override
  String get duplicateFinderScanningVaultFallback => 'Сканування сховища...';

  @override
  String duplicateFinderProcessingFileLabel(Object fileName) {
    return 'Обробка: $fileName';
  }

  @override
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  ) {
    return 'Перевірено файлів: $scanned | Знайдено груп дублікатів: $groups ($saved)';
  }

  @override
  String duplicateFinderGroupsFoundLabel(Object count) {
    return 'Знайдено груп дублікатів: $count';
  }

  @override
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved) {
    return 'Знайдено $copies копій • Можна звільнити $saved';
  }

  @override
  String duplicateFinderVaultsSelectedLabel(Object count) {
    return 'Вибрано сховищ: $count';
  }

  @override
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  ) {
    return 'Група $groupIndex: $size (знайдено копій: $count)';
  }

  @override
  String duplicateFinderRecoverableSpaceLabel(Object size) {
    return 'Можна звільнити: $size';
  }

  @override
  String get duplicateFinderPreviewFileTooltip => 'Переглянути файл';

  @override
  String duplicateFinderPreviewFailedMessage(Object fileName) {
    return 'Не вдалося відкрити перегляд для $fileName';
  }

  @override
  String duplicateFinderPreviewErrorMessage(Object error) {
    return 'Помилка перегляду файлу: $error';
  }

  @override
  String duplicateFinderFilesSelectedLabel(Object count) {
    return 'Вибрано файлів: $count';
  }

  @override
  String duplicateFinderBytesToBeFreedLabel(Object size) {
    return 'Буде звільнено: $size';
  }

  @override
  String duplicateFinderDeleteSelectedButton(Object count) {
    return 'Видалити вибране ($count)';
  }

  @override
  String get vaultBrowserSwitchVaultTooltip => 'Змінити сховище';

  @override
  String get vaultBrowserRootFolderLabel => 'Коренева папка';

  @override
  String vaultFilePickerTitle(Object vaultName) {
    return 'Вибір файлів ($vaultName)';
  }

  @override
  String get vaultFilePickerEmptyMessage => 'Папка порожня';

  @override
  String vaultFilePickerConfirmButton(Object count) {
    return 'Вибрати файли ($count)';
  }

  @override
  String vaultFolderPickerTitle(Object vaultName) {
    return 'Вибір папки ($vaultName)';
  }

  @override
  String get vaultFolderPickerEmptyMessage => 'Тут немає підпапок';

  @override
  String get vaultFolderPickerRootLabel => 'Корінь';

  @override
  String get vaultFolderPickerConfirmRootButton => 'Вибрати кореневу папку';

  @override
  String vaultFolderPickerConfirmNamedButton(Object folderName) {
    return 'Вибрати \"$folderName\"';
  }

  @override
  String get singleFileCryptoSelectInputTitle => 'Вибір вхідних файлів';

  @override
  String get singleFileCryptoFromDeviceTitle => 'З пам\'яті пристрою';

  @override
  String get singleFileCryptoFromDeviceSubtitle =>
      'Вибрати файли за допомогою системного провідника';

  @override
  String get singleFileCryptoFromVaultTitle => 'З відкритого сховища';

  @override
  String get singleFileCryptoFromVaultSubtitle =>
      'Вибрати файли з відкритого зашифрованого контейнера';

  @override
  String get singleFileCryptoSelectDestinationTitle =>
      'Вибір папки призначення';

  @override
  String get singleFileCryptoDeviceFolderTitle => 'Папка в пам\'яті пристрою';

  @override
  String get singleFileCryptoDeviceFolderSubtitle =>
      'Зберегти результат у пам\'ять пристрою';

  @override
  String get singleFileCryptoVaultFolderTitle => 'Папка у відкритому сховищі';

  @override
  String get singleFileCryptoVaultFolderSubtitle =>
      'Зберегти результат всередині зашифрованого сховища';

  @override
  String get toolsSectionBackupSync => 'Резервне копіювання та синхронізація';

  @override
  String get toolVaultSyncTitle => 'Синхронізація сховищ';

  @override
  String get toolVaultSyncSubtitle =>
      'Порівняння двох сховищ і копіювання відсутніх або новіших файлів';

  @override
  String get vaultSyncNoVaultsTitle => 'Немає змонтованих сховищ';

  @override
  String get vaultSyncNoVaultsMessage =>
      'Змонтуйте щонайменше одне сховище, щоб порівнювати та синхронізувати його файли.';

  @override
  String get vaultSyncLeftLabel => 'Зліва';

  @override
  String get vaultSyncRightLabel => 'Справа';

  @override
  String get vaultSyncTapToSelect => 'Торкніться, щоб вибрати сховище та папку';

  @override
  String get vaultSyncSwapTooltip => 'Поміняти місцями Ліве і Праве';

  @override
  String get vaultSyncSameLocationWarning =>
      'Ліва і права папки мають відрізнятися.';

  @override
  String get vaultSyncIntroTitle => 'Порівняння двох сховищ';

  @override
  String get vaultSyncIntroSubtitle =>
      'Виберіть Ліве і Праве сховище (або дві папки в одному сховищі), щоб побачити відсутні, змінені чи новіші файли з кожного боку.';

  @override
  String get vaultSyncCompareButton => 'Порівняти';

  @override
  String get vaultSyncComparingLabel => 'Порівняння сховищ…';

  @override
  String vaultSyncCompareStatsLabel(Object dirs, Object entries) {
    return 'Відскановано папок: $dirs | Знайдено відмінностей: $entries';
  }

  @override
  String get vaultSyncCancelCompareButton => 'Скасувати';

  @override
  String get vaultSyncInSyncTitle => 'Уже синхронізовано';

  @override
  String vaultSyncInSyncMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count відповідних файлів ідентичні',
      many: '$count відповідних файлів ідентичні',
      few: '$count відповідні файли ідентичні',
      one: '1 відповідний файл ідентичний',
    );
    return 'Усі $_temp0 з обох боків.';
  }

  @override
  String get vaultSyncRecompareButton => 'Порівняти знову';

  @override
  String vaultSyncDifferencesFoundLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Знайдено $count відмінностей',
      many: 'Знайдено $count відмінностей',
      few: 'Знайдено $count відмінності',
      one: 'Знайдено 1 відмінність',
    );
    return '$_temp0';
  }

  @override
  String vaultSyncInSyncCountLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count файлів уже збігаються з обох боків',
      many: '$count файлів уже збігаються з обох боків',
      few: '$count файли вже збігаються з обох боків',
      one: '$count файл уже збігається з обох боків',
    );
    return '$_temp0';
  }

  @override
  String vaultSyncBadgeOnlyLeft(Object count) {
    return '$count лише зліва';
  }

  @override
  String vaultSyncBadgeOnlyRight(Object count) {
    return '$count лише справа';
  }

  @override
  String vaultSyncBadgeLeftNewer(Object count) {
    return '$count новіших зліва';
  }

  @override
  String vaultSyncBadgeRightNewer(Object count) {
    return '$count новіших справа';
  }

  @override
  String vaultSyncBadgeConflicts(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count потребують перегляду',
      many: '$count потребують перегляду',
      few: '$count потребують перегляду',
      one: '$count потребує перегляду',
    );
    return '$_temp0';
  }

  @override
  String get vaultSyncDirectionLabel => 'Напрямок синхронізації';

  @override
  String get vaultSyncDirectionTwoWay => 'Двосторонній (рекомендовано)';

  @override
  String get vaultSyncDirectionTwoWaySubtitle =>
      'Копіює кожен файл на ту сторону, де він відсутній або застарілий';

  @override
  String get vaultSyncDirectionLeftToRight => 'Зліва → Справа (в один бік)';

  @override
  String get vaultSyncDirectionLeftToRightSubtitle =>
      'Передає нові й оновлені файли зліва направо; ніколи не змінює ліву сторону';

  @override
  String get vaultSyncDirectionRightToLeft => 'Справа → Зліва (в один бік)';

  @override
  String get vaultSyncDirectionRightToLeftSubtitle =>
      'Передає нові й оновлені файли справа наліво; ніколи не змінює праву сторону';

  @override
  String get vaultSyncSearchHint => 'Пошук відмінностей';

  @override
  String get vaultSyncStatusOnlyLeft => 'Лише зліва';

  @override
  String get vaultSyncStatusOnlyRight => 'Лише справа';

  @override
  String get vaultSyncStatusLeftNewer => 'Новіший зліва';

  @override
  String get vaultSyncStatusRightNewer => 'Новіший справа';

  @override
  String get vaultSyncStatusConflict => 'Потребує перегляду';

  @override
  String get vaultSyncStatusTypeMismatch => 'Невідповідність типу';

  @override
  String get vaultSyncFolderOnlyLeftDetail => 'Папка — лише зліва';

  @override
  String get vaultSyncFolderOnlyRightDetail => 'Папка — лише справа';

  @override
  String vaultSyncBothSidesDetail(
    Object leftSize,
    Object leftDate,
    Object rightSize,
    Object rightDate,
  ) {
    return 'Л: $leftSize · $leftDate  →  П: $rightSize · $rightDate';
  }

  @override
  String get vaultSyncTypeMismatchTooltip =>
      'З одного боку файл, з іншого — папка. Вирішіть вручну у файловому менеджері';

  @override
  String get vaultSyncChangeActionTooltip => 'Змінити дію синхронізації';

  @override
  String get vaultSyncActionCopyToRight => 'Копіювати → Справа';

  @override
  String get vaultSyncActionCopyToLeft => 'Копіювати → Зліва';

  @override
  String get vaultSyncActionSkip => 'Пропустити';

  @override
  String vaultSyncChangesQueuedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'У черзі $count змін',
      many: 'У черзі $count змін',
      few: 'У черзі $count зміни',
      one: 'У черзі $count зміна',
    );
    return '$_temp0';
  }

  @override
  String get vaultSyncSyncNowButton => 'Синхронізувати зараз';

  @override
  String get vaultSyncConfirmTitle => 'Почати синхронізацію?';

  @override
  String vaultSyncConfirmMessage(num count, Object bytes) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count елементів',
      many: '$count елементів',
      few: '$count елементи',
      one: '1 елемент',
    );
    return 'Це скопіює $_temp0 (загалом $bytes) між двома сторонами. Наявні файли з однаковими іменами буде перезаписано.';
  }

  @override
  String vaultSyncStartedMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count елементів у черзі',
      many: '$count елементів у черзі',
      few: '$count елементи у черзі',
      one: '1 елемент у черзі',
    );
    return 'Синхронізацію розпочато — $_temp0';
  }

  @override
  String vaultSyncPickLocationTitle(Object side) {
    return 'Виберіть сховище та папку ($side)';
  }

  @override
  String get vaultSyncReadOnlyBadge => 'Лише для читання';

  @override
  String get vaultSyncReadOnlyTooltip =>
      'Це сховище змонтовано лише для читання — копіювати файли до нього неможливо';

  @override
  String get vaultSyncSyncingButton => 'Синхронізація…';

  @override
  String get vaultSyncNotEnoughSpaceTitle => 'Недостатньо місця';

  @override
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  ) {
    return 'Недостатньо вільного місця на $side — потрібно $required, вільно лише $free.';
  }

  @override
  String get removeMasterPasswordTitle => 'Видалити головний пароль';

  @override
  String get confirmRemoveMasterPasswordMessage =>
      'Введіть поточний головний пароль для підтвердження видалення:';

  @override
  String get authenticateToRemoveMasterPassword =>
      'Підтвердьте особу для видалення головного пароля';

  @override
  String get incorrectPassword => 'Невірний пароль';

  @override
  String get rememberPerFolderLayoutLabel =>
      'Пам\'ятати вигляд для кожної папки';

  @override
  String get rememberPerFolderLayoutDesc =>
      'Зберігати окремий вигляд (список, сітка, мозаїка) для кожної папки';

  @override
  String get fileInfoAction => 'Info';
}
