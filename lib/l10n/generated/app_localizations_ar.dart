// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get cancel => 'إلغاء';

  @override
  String get close => 'إغلاق';

  @override
  String get search => 'بحث';

  @override
  String get goBack => 'رجوع';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => 'الانتقال إلى صفحة';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return 'رقم الصفحة (1 - $pageCount)';
  }

  @override
  String get pdfViewerPageLabel => 'الصفحة';

  @override
  String get pdfViewerGoButton => 'انتقال';

  @override
  String get pdfViewerSearchHint => 'البحث في المستند';

  @override
  String get pdfViewerNoMatches => 'لا توجد نتائج مطابقة';

  @override
  String get pdfViewerPreviousMatch => 'النتيجة السابقة';

  @override
  String get pdfViewerNextMatch => 'النتيجة التالية';

  @override
  String get pdfViewerCloseSearch => 'إغلاق البحث';

  @override
  String get pdfViewerPrintTooltip => 'طباعة المستند';

  @override
  String get pdfViewerLoadingDocument => 'جارٍ تحميل المستند…';

  @override
  String get pdfViewerCannotOpenTitle => 'تعذّر فتح ملف PDF';

  @override
  String get pdfViewerFailedToLoad => 'فشل تحميل ملف PDF';

  @override
  String get pdfViewerEditTooltip => 'تعديل';

  @override
  String get pdfViewerDoneEditingTooltip => 'إنهاء التعديل';

  @override
  String get pdfViewerSaveFailed => 'تعذّر حفظ التغييرات في ملف PDF هذا';

  @override
  String get pdfViewerEditUnavailable => 'التعديل غير متاح لهذا المستند';

  @override
  String get paste => 'لصق';

  @override
  String get clear => 'مسح';

  @override
  String get clipboardVerbMove => 'نقل';

  @override
  String get clipboardVerbCopy => 'نسخ';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb ($count) — اضغط للتفاصيل، اضغط مطولاً للصق';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb ($count) — تفاصيل الحافظة';
  }

  @override
  String clipboardSourceLabel(String source) {
    return 'المصدر: $source';
  }

  @override
  String get clipboardDefaultSourceName => 'الخزنة';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      many: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصران',
      one: 'عنصر واحد',
      zero: 'لا عناصر',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count عنصر إضافي',
      many: '+$count عنصرًا إضافيًا',
      few: '+$count عناصر إضافية',
      two: '+عنصران إضافيان',
      one: '+عنصر واحد إضافي',
      zero: 'لا عناصر إضافية',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => 'المعاملات المتقدمة';

  @override
  String get pimFieldLabel => 'PIM (اتركه فارغًا لاستخدام القيمة الافتراضية)';

  @override
  String get encryptionAlgorithmLabel => 'خوارزمية التشفير';

  @override
  String get hashAlgorithmLabel => 'خوارزمية التجزئة';

  @override
  String get clipboardVerbMoving => 'جارٍ النقل';

  @override
  String get clipboardVerbCopying => 'جارٍ النسخ';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      many: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصران',
      one: 'عنصر واحد',
      zero: 'لا عناصر',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return ' من \"$source\"';
  }

  @override
  String get clipboardOpenContainerToPaste => 'افتح حاوية للصق';

  @override
  String get keyfilesOptionalLabel => 'ملفات المفاتيح (اختياري)';

  @override
  String get addFile => 'إضافة ملف';

  @override
  String get noKeyfilesAttached => 'لا توجد ملفات مفاتيح مرفقة';

  @override
  String get completed => 'مكتمل';

  @override
  String get dismiss => 'تجاهل';

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
      other: '$count عملية نقل',
      many: '$count عملية نقل',
      few: '$count عمليات نقل',
      two: 'عمليتا نقل',
      one: 'عملية نقل واحدة',
      zero: 'لا عمليات نقل',
    );
    return '$_temp0';
  }

  @override
  String multiOpSublabel(String summary) {
    return '$summary · اضغط لعرض الكل';
  }

  @override
  String get thumbnailSizeResolutionLabel => 'حجم الصورة المصغرة (الدقة)';

  @override
  String get jpegCompressionQualityLabel => 'جودة ضغط JPEG';

  @override
  String get done => 'تم';

  @override
  String get confirm => 'تأكيد';

  @override
  String get couldNotPickKeyfiles => 'تعذّر اختيار ملفات المفاتيح';

  @override
  String get filesystemLabelEncryptedVault => 'هذه الخزنة المشفّرة';

  @override
  String get filesystemLabelThisContainer => 'هذه الحاوية';

  @override
  String get nounFile => 'ملف';

  @override
  String get nounFolder => 'مجلد';

  @override
  String get nounFileCapitalized => 'ملف';

  @override
  String get nounFolderCapitalized => 'مجلد';

  @override
  String get unitBytes => 'بايت';

  @override
  String get unitCharacters => 'حرفًا';

  @override
  String get validationEmptyName => 'لا يمكن أن يكون الاسم فارغًا.';

  @override
  String validationReservedNavName(String name, String noun) {
    return '\"$name\" اسم تنقّل محجوز ولا يمكن استخدامه كاسم $noun.';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return 'الحرف \"$char\" في الموضع $position غير مسموح به في الاسم على $fsLabel.';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return 'يحتوي الموضع $position على حرف تحكم غير قابل للطباعة (الرمز $code)، وهو غير مسموح به على $fsLabel.';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '\"$name\" اسم جهاز محجوز على $fsLabel (يطابق CON أو PRN أو AUX أو NUL أو COM0–9 أو LPT0–9) ولا يمكن استخدامه، سواء بامتداد ملف أو بدونه.';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return 'لا يمكن أن ينتهي اسم $noun بمسافة على $fsLabel';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return 'لا يمكن أن ينتهي اسم $noun بنقطة \".\" على $fsLabel';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return 'طول هذا الاسم $length $unit؛ يسمح $fsLabel بحد أقصى $maxLength $unit لاسم $noun.';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return 'طول المسار الكامل $length حرفًا؛ يسمح $fsLabel بحد أقصى $maxLength.';
  }

  @override
  String conflictSameType(String noun, String name) {
    return 'يوجد بالفعل $noun بالاسم \"$name\" هنا.';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return 'يوجد بالفعل $existingNoun بالاسم \"$name\" هنا — ولا يمكنه مشاركة الاسم مع $candidateNoun.';
  }

  @override
  String get readOnlyContainerWarning => 'تم تحميل هذه الحاوية للقراءة فقط.';

  @override
  String get hiddenVolumeProtectionTriggeredWarning =>
      'كانت الكتابة على وحدة التخزين الخارجية هذه ستُتلف الوحدة المخفية، لذا تم حظرها. تم تحويل هذه الحاوية إلى وضع القراءة فقط لبقية هذه الجلسة.';

  @override
  String get protectHiddenVolumeToggleTitle => 'حماية الوحدة المخفية';

  @override
  String get protectHiddenVolumeToggleSubtitle =>
      'منع التلف الناتج عن الكتابة على الوحدة الخارجية';

  @override
  String get protectHiddenVolumeCredentialsRequired =>
      'يلزم توفير كلمة مرور أو ملف مفتاح للوحدة المخفية لحمايتها';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'حذف $count عنصر؟',
      many: 'حذف $count عنصرًا؟',
      few: 'حذف $count عناصر؟',
      two: 'حذف عنصرين؟',
      one: 'حذف عنصر واحد؟',
      zero: 'حذف لا عناصر؟',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning =>
      'سيتم حذف هذه العناصر نهائيًا، بما في ذلك جميع محتويات أي مجلدات محددة.';

  @override
  String get deleteFilesWarning =>
      'سيتم محو هذه العناصر نهائيًا من وحدة التخزين المشفرة الخاصة بك.';

  @override
  String get delete => 'حذف';

  @override
  String get remove => 'إزالة';

  @override
  String get create => 'إنشاء';

  @override
  String get rename => 'إعادة تسمية';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'إعادة تسمية $count عنصر',
      many: 'إعادة تسمية $count عنصرًا',
      few: 'إعادة تسمية $count عناصر',
      two: 'إعادة تسمية عنصرين',
      one: 'إعادة تسمية عنصر واحد',
      zero: 'إعادة تسمية لا عناصر',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => 'مجلد جديد';

  @override
  String get newTextFileTitle => 'ملف نصي جديد';

  @override
  String get folderNameHint => 'اسم المجلد';

  @override
  String get filenameHint => 'اسم_الملف.txt';

  @override
  String get newNameHint => 'اسم جديد';

  @override
  String get baseNameHint => 'الاسم الأساسي';

  @override
  String couldntCreateItem(String name) {
    return 'تعذّر إنشاء \"$name\" — تحقق من أن الحاوية لا تزال مثبَّتة';
  }

  @override
  String couldntRenameSingle(String name) {
    return 'تعذّر إعادة تسمية \"$name\" — قد يوجد بالفعل عنصر بهذا الاسم';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تعذّرت إعادة تسمية $count عنصر: $reason',
      many: 'تعذّرت إعادة تسمية $count عنصرًا: $reason',
      few: 'تعذّرت إعادة تسمية $count عناصر: $reason',
      two: 'تعذّرت إعادة تسمية عنصرين: $reason',
      one: 'تعذّرت إعادة تسمية عنصر واحد: $reason',
      zero: 'تعذّرت إعادة تسمية لا عناصر: $reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تعذّرت إعادة تسمية $count عنصر',
      many: 'تعذّرت إعادة تسمية $count عنصرًا',
      few: 'تعذّرت إعادة تسمية $count عناصر',
      two: 'تعذّرت إعادة تسمية عنصرين',
      one: 'تعذّرت إعادة تسمية عنصر واحد',
      zero: 'تعذّرت إعادة تسمية لا عناصر',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize =>
      'أدخل حجمًا مخفيًا صالحًا أكبر من 0';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter =>
      'يجب أن يكون حجم الوحدة المخفية أصغر من حجم الوحدة الخارجية';

  @override
  String get hiddenVolumeErrorTooLargeForContainer =>
      'حجم الوحدة المخفية كبير جدًا بالنسبة لحجم هذه الحاوية';

  @override
  String get hiddenVolumeErrorCredentialsRequired =>
      'يلزم توفير كلمة مرور مخفية أو ملف مفتاح عند إنشاء وحدة مخفية';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      'لا يمكن أن تكون بيانات اعتماد الوحدة المخفية (كلمة المرور وPIM وملفات المفاتيح) مطابقة لبيانات اعتماد الوحدة الخارجية.';

  @override
  String get vaultItemTypePassword => 'كلمة مرور';

  @override
  String get vaultItemTypePaymentCard => 'بطاقة دفع';

  @override
  String get vaultItemTypeIdentity => 'هوية';

  @override
  String get vaultItemTypeSecureNote => 'ملاحظة آمنة';

  @override
  String get vaultItemTypeBankAccount => 'حساب مصرفي';

  @override
  String get vaultItemTypeSoftwareLicense => 'ترخيص برمجي';

  @override
  String get fieldUsernameEmail => 'اسم المستخدم / البريد الإلكتروني';

  @override
  String get fieldPassword => 'كلمة المرور';

  @override
  String get fieldWebsiteUrl => 'رابط الموقع';

  @override
  String get fieldTotpSecret => 'سر TOTP (التحقق بخطوتين)';

  @override
  String get fieldNotes => 'ملاحظات';

  @override
  String get fieldCardholderName => 'اسم حامل البطاقة';

  @override
  String get fieldCardNumber => 'رقم البطاقة';

  @override
  String get fieldExpiryMMYY => 'تاريخ الانتهاء (شهر/سنة)';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldIssuingBank => 'البنك المُصدر';

  @override
  String get fieldFullName => 'الاسم الكامل';

  @override
  String get fieldDateOfBirth => 'تاريخ الميلاد';

  @override
  String get fieldNationality => 'الجنسية';

  @override
  String get fieldPassportNumber => 'رقم جواز السفر';

  @override
  String get fieldPassportExpiry => 'تاريخ انتهاء جواز السفر';

  @override
  String get fieldNationalIdSsn => 'الهوية الوطنية / الرقم القومي';

  @override
  String get fieldDriversLicense => 'رخصة القيادة';

  @override
  String get fieldAddress => 'العنوان';

  @override
  String get fieldPhone => 'الهاتف';

  @override
  String get fieldEmail => 'البريد الإلكتروني';

  @override
  String get fieldNote => 'ملاحظة';

  @override
  String get fieldBankName => 'اسم البنك';

  @override
  String get fieldAccountHolder => 'صاحب الحساب';

  @override
  String get fieldAccountNumber => 'رقم الحساب';

  @override
  String get fieldRoutingSortCode => 'رمز التوجيه المصرفي / رمز الفرع';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => 'نوع الحساب';

  @override
  String get fieldProductName => 'اسم المنتج';

  @override
  String get fieldLicenseKey => 'مفتاح الترخيص';

  @override
  String get fieldRegisteredTo => 'مسجَّل باسم';

  @override
  String get fieldPurchaseDate => 'تاريخ الشراء';

  @override
  String get fieldExpiryRenewalDate => 'تاريخ الانتهاء / التجديد';

  @override
  String get fieldDownloadUrl => 'رابط التنزيل';

  @override
  String get fieldRegistrationEmail => 'بريد التسجيل الإلكتروني';

  @override
  String get titleRequired => 'العنوان مطلوب';

  @override
  String newTypeTitle(String typeLabel) {
    return '$typeLabel جديد';
  }

  @override
  String editItemTitle(String title) {
    return 'تعديل $title';
  }

  @override
  String get save => 'حفظ';

  @override
  String typeNameHint(String typeLabel) {
    return 'اسم $typeLabel';
  }

  @override
  String get titleSectionLabel => 'العنوان';

  @override
  String get fieldsSectionLabel => 'الحقول';

  @override
  String get encryptedStorageHint =>
      'يتم تخزين جميع الحقول بشكل مشفّر داخل الحاوية.';

  @override
  String copiedSuffix(String fieldLabel) {
    return 'تم نسخ $fieldLabel';
  }

  @override
  String get copy => 'نسخ';

  @override
  String get failedToSaveCheckMounted =>
      'فشل الحفظ — تحقق من أن الحاوية لا تزال مثبَّتة';

  @override
  String get discardChangesTitle => 'تجاهل التغييرات؟';

  @override
  String get discardChangesMessage => 'ستفقد تغييراتك غير المحفوظة.';

  @override
  String get discard => 'تجاهل';

  @override
  String get keepEditing => 'متابعة التعديل';

  @override
  String get deleteItemTitle => 'حذف العنصر؟';

  @override
  String deleteItemMessage(String title) {
    return 'سيتم حذف \"$title\" نهائيًا من الخزنة.';
  }

  @override
  String get removeFromBookmarks => 'إزالة من المفضلة';

  @override
  String get addToBookmarks => 'إضافة إلى المفضلة';

  @override
  String get edit => 'تعديل';

  @override
  String labelCopiedToClipboard(String label) {
    return 'تم نسخ $label إلى الحافظة';
  }

  @override
  String get noFieldsFilledIn =>
      'لا توجد حقول معبأة.\nاضغط على تعديل لإضافة التفاصيل.';

  @override
  String get sectionLabelDetails => 'التفاصيل';

  @override
  String get sectionLabelInfo => 'معلومات';

  @override
  String get metaLabelType => 'النوع';

  @override
  String get metaLabelCreated => 'تاريخ الإنشاء';

  @override
  String get metaLabelModified => 'تاريخ التعديل';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return 'نسخ $fieldLabel';
  }

  @override
  String get readOnlyCantAddItemsTooltip => 'للقراءة فقط — لا يمكن إضافة عناصر';

  @override
  String get extractArchive => 'استخراج الأرشيف';

  @override
  String get newItemTooltip => 'عنصر جديد';

  @override
  String get camera => 'الكاميرا';

  @override
  String get importFiles => 'استيراد ملفات';

  @override
  String get importFolder => 'استيراد مجلد';

  @override
  String get secureItem => 'عنصر آمن';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archive Explorer';

  @override
  String get archiveExplorerPermissionTitle => 'يلزم الوصول إلى وحدة التخزين';

  @override
  String get archiveExplorerPermissionMessage =>
      'اسمح بالوصول إلى ملفاتك لتصفح واستخراج أرشيفات .zip من مجلد التنزيلات.';

  @override
  String get archiveExplorerGrantAccess => 'منح الوصول';

  @override
  String get archiveExplorerEmptyTitle => 'لم يتم العثور على أرشيفات';

  @override
  String get archiveExplorerEmptyMessage =>
      'ستظهر هنا ملفات zip التي تقوم بتنزيلها.';

  @override
  String get archiveExplorerRefreshTooltip => 'تحديث';

  @override
  String archiveExplorerEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      many: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصران',
      one: 'عنصر واحد',
      zero: 'لا عناصر',
    );
    return '$_temp0';
  }

  @override
  String get archiveExplorerExtractAll => 'استخراج الكل';

  @override
  String get archiveExplorerExtracting => 'جارٍ الاستخراج…';

  @override
  String archiveExplorerExtractSuccess(int count, String name) {
    return 'تم استخراج $count ملف إلى Download/Extracted/$name';
  }

  @override
  String get archiveExplorerExtractFailed => 'تعذّر استخراج ذلك الأرشيف.';

  @override
  String get archiveExplorerOpenFailed => 'تعذّر فتح ذلك الأرشيف.';

  @override
  String get archiveExplorerOpenArchive => 'فتح أرشيف…';

  @override
  String get archiveExplorerUnresolvedPath =>
      'تعذّر الوصول إلى ذلك الملف مباشرةً. جرّب اختيار ملف من التنزيلات بدلاً من ذلك.';

  @override
  String get archiveExplorerExtractTo => 'استخراج إلى…';

  @override
  String get archiveExplorerPreview => 'معاينة';

  @override
  String get archiveExplorerChoosingDestination => 'جارٍ اختيار الوجهة…';

  @override
  String get archiveExplorerNoDestinationChosen => 'لم يتم اختيار وجهة.';

  @override
  String archiveExplorerExtractSuccessTo(int count, String path) {
    return 'تم استخراج $count ملف إلى $path';
  }

  @override
  String get archiveBrowserEmptyTitle => 'مجلد فارغ';

  @override
  String get archiveBrowserEmptyMessage => 'لا يحتوي هذا المجلد على أي ملفات.';

  @override
  String get archiveBrowserRoot => 'الأرشيف';

  @override
  String get archiveBrowserOpenFileFailed => 'تعذّر فتح ذلك الملف.';

  @override
  String get fileAssocInAppTextEditor => 'محرر النصوص المدمج';

  @override
  String get fileAssocInAppMediaViewer => 'عارض الوسائط المدمج';

  @override
  String fileAssocAppPrefix(String name) {
    return 'التطبيق: $name';
  }

  @override
  String get fileAssocExternalApp => 'تطبيق خارجي';

  @override
  String get appSettingsTitle => 'إعدادات التطبيق';

  @override
  String get sectionSecurityPrivacy => 'الأمان والخصوصية';

  @override
  String get sectionAppearanceInterface => 'المظهر والواجهة';

  @override
  String get sectionVaultFileHandling => 'الخزنة ومعالجة الملفات';

  @override
  String get masterPasswordTitle => 'كلمة المرور الرئيسية';

  @override
  String get masterPasswordActiveSubtitle =>
      'مفعّلة — اضغط على المفتاح لإزالتها';

  @override
  String get masterPasswordInactiveSubtitle => 'طلب كلمة مرور لفتح التطبيق';

  @override
  String get newPasswordLabel => 'كلمة مرور جديدة';

  @override
  String get masterPasswordFieldLabel => 'كلمة المرور الرئيسية';

  @override
  String get confirmPasswordLabel => 'تأكيد كلمة المرور';

  @override
  String get update => 'تحديث';

  @override
  String get setPassword => 'تعيين كلمة المرور';

  @override
  String get biometricUnlockTitle => 'فتح القفل بالبصمة الحيوية';

  @override
  String get biometricUnlockSubtitle => 'أجرِ المصادقة لتحميل الحاوية بأمان';

  @override
  String get changeMasterPasswordTitle => 'تغيير كلمة المرور الرئيسية';

  @override
  String get changeMasterPasswordSubtitle =>
      'تحديث بيانات اعتماد كلمة المرور الرئيسية';

  @override
  String get autoLockContainersTitle => 'القفل التلقائي للحاويات';

  @override
  String get autoLockContainersSubtitle =>
      'قفل الخزنات المفتوحة تلقائيًا بعد فترة من عدم النشاط';

  @override
  String get autoLockTimeoutLabel => 'مهلة القفل التلقائي';

  @override
  String get immediately => 'فورًا';

  @override
  String nMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count دقيقة',
      many: '$count دقيقة',
      few: '$count دقائق',
      two: 'دقيقتان',
      one: 'دقيقة واحدة',
      zero: '0 دقيقة',
    );
    return '$_temp0';
  }

  @override
  String get blockScreenshotsTitle => 'حظر لقطات الشاشة';

  @override
  String get blockScreenshotsSubtitle =>
      'منع لقطات الشاشة وإخفاء معاينة التطبيقات الأخيرة';

  @override
  String get keepVaultsRunningInBackgroundTitle =>
      'إبقاء الخزنات نشطة في الخلفية';

  @override
  String get keepVaultsRunningInBackgroundSubtitle =>
      'عرض إشعار وإبقاء الخزنات المفتوحة متاحة بعد مغادرة التطبيق. تبقى مفاتيح الخزنة في الذاكرة حتى يتم قفلها.';

  @override
  String get notificationPermissionDeniedMessage =>
      'تم رفض إذن الإشعارات. ستبقى الخزنات مفتوحة، لكن لن يظهر الإشعار المستمر.';

  @override
  String get discreteModeTitle => 'وضع التمويه';

  @override
  String get discreteModeActiveSubtitle =>
      'مفعّل — يظهر التطبيق حاليًا باسم \"Archive Explorer\"';

  @override
  String get discreteModeInactiveSubtitle =>
      'تمويه هذا التطبيق كمتصفح أرشيف zip على الشاشة الرئيسية';

  @override
  String get enableDiscreteModeTitle => 'تفعيل وضع التمويه؟';

  @override
  String get disableDiscreteModeTitle => 'تعطيل وضع التمويه؟';

  @override
  String get enableDiscreteModeMessage =>
      'سيتغير رمز التطبيق واسمه على شاشتك الرئيسية إلى \"Archive Explorer\". سيعمل كمتصفح ومستخرج لأرشيفات zip.\n\nللوصول إلى خزنتك، افتح Archive Explorer واضغط مطولاً على العنوان لمدة ثانيتين.';

  @override
  String get disableDiscreteModeMessage =>
      'سيعود رمز التطبيق واسمه على شاشتك الرئيسية إلى \"Vault Explorer\".';

  @override
  String get enable => 'تفعيل';

  @override
  String get disable => 'تعطيل';

  @override
  String get discreteModeEnabledSnack =>
      'تم تفعيل وضع التمويه. سيُغلق التطبيق — أعد فتحه من أيقونة المشغّل الجديدة.';

  @override
  String get discreteModeDisabledSnack =>
      'تم تعطيل وضع التمويه. سيُغلق التطبيق — أعد فتحه من أيقونة المشغّل الجديدة.';

  @override
  String get failedToChangeDiscreteMode => 'فشل تغيير وضع التمويه';

  @override
  String get cacheDerivedKeysTitle => 'تخزين المفاتيح المشتقة مؤقتًا افتراضيًا';

  @override
  String get cacheDerivedKeysSubtitle =>
      'تخزين مادة المفتاح المشتق في Keystore لتسريع عمليات فتح القفل';

  @override
  String get appThemeLabel => 'سمة التطبيق';

  @override
  String get systemDefault => 'افتراضي النظام';

  @override
  String get lightTheme => 'السمة الفاتحة';

  @override
  String get darkTheme => 'السمة الداكنة';

  @override
  String get useMaterialYouTitle => 'استخدام Material You';

  @override
  String get useMaterialYouSubtitle =>
      'مطابقة ألوان التطبيق مع خلفيتك (Android 12 فأعلى)';

  @override
  String get pureBlackThemeTitle => 'أسود نقي (OLED)';

  @override
  String get pureBlackThemeSubtitle =>
      'خلفيات سوداء نقية لتوفير البطارية وتقليل الوهج على شاشات OLED (يعمل فقط مع المظهر الداكن)';

  @override
  String get sortContainersByLabel => 'ترتيب الحاويات حسب';

  @override
  String get swapCardSwipeActionsTitle => 'تبديل إجراءات سحب البطاقات';

  @override
  String get swapCardSwipeActionsSubtitle =>
      'إظهار تعديل على اليسار وإزالة على اليمين عند سحب البطاقات';

  @override
  String get swipeGestureHintTitle => 'تلميح إيماءة السحب';

  @override
  String get swipeGestureHintSubtitle =>
      'إظهار حركة معاينة البطاقة عند أول حاوية';

  @override
  String get autoOpenOnUnlockTitle => 'الفتح التلقائي عند فتح القفل';

  @override
  String get autoOpenOnUnlockActiveSubtitle =>
      'الفتح تلقائيًا بعد فتح قفل الخزنة';

  @override
  String get autoOpenOnUnlockInactiveSubtitle =>
      'فتح قفل الخزنة فقط والبقاء في لوحة التحكم';

  @override
  String get enableJsHtmlTitle => 'تفعيل JavaScript في عارض HTML';

  @override
  String get jsEnabledSubtitle => 'تم تفعيل JavaScript لملفات HTML المحلية';

  @override
  String get jsDisabledSubtitle => 'تم تعطيل JavaScript لملفات HTML المحلية';

  @override
  String get fastStorageAccessTitle => 'الوصول السريع لوحدة التخزين';

  @override
  String get fastStorageAccessGrantedSubtitle =>
      'تم منح الوصول إلى جميع الملفات (أقصى سرعة)';

  @override
  String get fastStorageAccessNotGrantedSubtitle =>
      'امنح إذن الوصول إلى جميع الملفات في إعدادات النظام للحصول على أفضل سرعة';

  @override
  String get enableFastStorageAccessTitle =>
      'تفعيل الوصول السريع لوحدة التخزين';

  @override
  String get enableFastStorageAccessMessage =>
      'يتيح منح \"الوصول إلى جميع الملفات\" لتطبيق Vault Explorer إجراء عمليات ملفات POSIX مباشرة، مما يسرّع أداء خزنات المجلدات بمقدار يصل إلى 1000 ضعف.';

  @override
  String get disableStorageAccessTitle => 'تعطيل الوصول إلى وحدة التخزين';

  @override
  String get disableStorageAccessMessage =>
      'يتطلب Android إيقاف تشغيل \"الوصول إلى جميع الملفات\" من داخل إعدادات النظام. هل تريد فتح الإعدادات لإيقاف تشغيله؟';

  @override
  String get enableStoragePermissionLegacyTitle =>
      'السماح بالوصول إلى وحدة التخزين';

  @override
  String get enableStoragePermissionLegacyMessage =>
      'يحتاج Vault Explorer إلى إذن التخزين لإجراء عمليات ملفات مباشرة، مما يسرّع أداء خزنات المجلدات. سيطلب منك Android الآن التأكيد.';

  @override
  String get disableStoragePermissionLegacyMessage =>
      'يتطلب Android إيقاف تشغيل إذن التخزين من داخل إعدادات النظام. هل تريد فتح الإعدادات لإيقاف تشغيله؟';

  @override
  String get openSettings => 'فتح الإعدادات';

  @override
  String get useThisPasswordButton => 'Use This Password';

  @override
  String get quickPasswordGeneratorSheetTitle => 'Password Generator';

  @override
  String get androidFileProviderTitle => 'مزوّد ملفات Android';

  @override
  String get androidFileProviderSubtitle =>
      'عرض الحاويات الجديدة في منتقي ملفات Android افتراضيًا';

  @override
  String get thumbnailCachingDefaultLabel =>
      'تخزين الصور المصغّرة مؤقتًا (افتراضي)';

  @override
  String get thumbnailQualityDefaultLabel => 'جودة الصور المصغّرة (افتراضي)';

  @override
  String get fileAssociationsHeader => 'ارتباطات الملفات';

  @override
  String get noFileAssociationsYet =>
      'لا توجد ارتباطات ملفات محفوظة بعد. سيُطلب منك الاختيار عند فتح الملفات.';

  @override
  String get defaultActionsHeader =>
      'الإجراءات الافتراضية عند فتح ملفات غير قياسية:';

  @override
  String get removeAssociationTooltip => 'إزالة الارتباط';

  @override
  String get sectionBackupRestore => 'النسخ الاحتياطي';

  @override
  String get exportSettingsTitle => 'تصدير الإعدادات';

  @override
  String get exportSettingsSubtitle =>
      'حفظ إعدادات التطبيق وتخطيط مدير الملفات في ملف';

  @override
  String get importSettingsTitle => 'استيراد الإعدادات';

  @override
  String get importSettingsSubtitle =>
      'استعادة إعدادات التطبيق وتخطيط مدير الملفات من ملف';

  @override
  String get importSettingsConfirmTitle => 'استيراد الإعدادات؟';

  @override
  String get importSettingsConfirmMessage =>
      'سيستبدل هذا إعدادات التطبيق الحالية وتخطيط مدير الملفات. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get exportSettingsSuccessMessage => 'تم تصدير الإعدادات';

  @override
  String get importSettingsSuccessMessage => 'تم استيراد الإعدادات';

  @override
  String get exportSettingsErrorMessage => 'تعذّر تصدير الإعدادات';

  @override
  String get importSettingsInvalidFileMessage =>
      'هذا الملف ليس ملف تصدير إعدادات صالحًا';

  @override
  String get sectionDebug => 'تصحيح الأخطاء';

  @override
  String get debugLoggingTitle => 'تسجيل تصحيح الأخطاء';

  @override
  String get debugLoggingSubtitle => 'تسجيل سجلات تشخيص مفصّلة لعمليات الحاوية';

  @override
  String get logcatTitle => 'Logcat';

  @override
  String get logcatSubtitle => 'عرض سجلات الجهاز وحفظها';

  @override
  String logcatSavedMessage(String path) {
    return 'تم حفظ السجل في $path';
  }

  @override
  String get logcatSaveErrorMessage => 'فشل حفظ السجل';

  @override
  String get logcatCopiedMessage => 'تم نسخ السجل إلى الحافظة';

  @override
  String get logcatUnavailableMessage => 'Logcat غير متاح على هذا الجهاز';

  @override
  String get logcatEmptyMessage => 'بانتظار أسطر السجل…';

  @override
  String get logcatClearTooltip => 'مسح السجل';

  @override
  String get logcatSaveTooltip => 'حفظ السجل';

  @override
  String get logcatFilterAppOnly => 'التطبيق فقط';

  @override
  String get logcatFilterAll => 'جميع السجلات';

  @override
  String get logcatSearchHint => 'البحث في السجلات…';

  @override
  String get logcatClearedMessage => 'تم مسح السجلات';

  @override
  String get logcatCopyTooltip => 'نسخ السجل';

  @override
  String get retryButton => 'إعادة المحاولة';

  @override
  String get aboutAppTitle => 'حول VaultExplorer';

  @override
  String versionInfoSubtitle(String version) {
    return 'الإصدار $version · تراخيص المصدر المفتوح والتفاصيل';
  }

  @override
  String get failedToSaveSettings => 'فشل حفظ الإعدادات';

  @override
  String get masterPasswordSetSnack => 'تم تعيين كلمة المرور الرئيسية';

  @override
  String get passwordCannotBeEmpty => 'لا يمكن أن تكون كلمة المرور فارغة';

  @override
  String get atLeast4CharsRequired => 'يلزم 4 أحرف على الأقل';

  @override
  String get passwordsDoNotMatch => 'كلمتا المرور غير متطابقتين';

  @override
  String get failedToHashPassword =>
      'فشل تجزئة كلمة المرور — يرجى المحاولة مرة أخرى';

  @override
  String get languageLabel => 'اللغة';

  @override
  String get biometricNotAvailable => 'البصمة الحيوية غير متاحة على هذا الجهاز';

  @override
  String get unlockVaultExplorerReason => 'فتح قفل VaultExplorer';

  @override
  String biometricErrorWithCode(String code) {
    return 'خطأ في البصمة الحيوية: $code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds ثانية',
      many: '$seconds ثانية',
      few: '$seconds ثوانٍ',
      two: 'ثانيتين',
      one: 'ثانية واحدة',
      zero: '0 ثانية',
    );
    return 'عدد كبير جدًا من المحاولات الفاشلة. حاول مرة أخرى خلال $_temp0.';
  }

  @override
  String get enterMasterPasswordPrompt => 'أدخل كلمة المرور الرئيسية';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts محاولة فاشلة',
      many: '$attempts محاولة فاشلة',
      few: '$attempts محاولات فاشلة',
      two: 'محاولتين فاشلتين',
      one: 'محاولة فاشلة واحدة',
      zero: 'لا محاولات فاشلة',
    );
    return 'كلمة مرور غير صحيحة. تم القفل لمدة $seconds ثانية بسبب $_temp0.';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts محاولة فاشلة',
      many: '$attempts محاولة فاشلة',
      few: '$attempts محاولات فاشلة',
      two: 'محاولتان فاشلتان',
      one: 'محاولة فاشلة واحدة',
      zero: 'لا محاولات فاشلة',
    );
    return 'كلمة مرور غير صحيحة ($_temp0).';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle => 'أدخل كلمة المرور الرئيسية للمتابعة';

  @override
  String get masterPasswordFieldLabelTitleCase => 'كلمة المرور الرئيسية';

  @override
  String get unlock => 'فتح القفل';

  @override
  String get useBiometric => 'استخدام البصمة الحيوية';

  @override
  String get connectAtLeast4Dots => 'صِل 4 نقاط على الأقل';

  @override
  String get patternsDontMatch => 'النمطان غير متطابقين — حاول مرة أخرى';

  @override
  String get drawUnlockPatternTitle => 'ارسم نمط فتح القفل';

  @override
  String get confirmPatternTitle => 'أكّد نمطك';

  @override
  String get drawSamePatternAgain => 'ارسم نفس النمط مرة أخرى';

  @override
  String get enterAtLeast4Digits => 'أدخل 4 أرقام على الأقل';

  @override
  String get pinsDontMatch => 'رمزا PIN غير متطابقين — حاول مرة أخرى';

  @override
  String get createUnlockPinTitle => 'أنشئ رمز PIN لفتح القفل';

  @override
  String get confirmPinTitle => 'أكّد رمز PIN الخاص بك';

  @override
  String get enterSamePinAgain => 'أدخل نفس رمز PIN مرة أخرى';

  @override
  String get enterUnlockPinTitle => 'أدخل رمز PIN لفتح القفل';

  @override
  String get wrongPinTryAgain => 'رمز PIN خاطئ — حاول مرة أخرى';

  @override
  String get enterYourPinSequence => 'أدخل رمز PIN الخاص بك';

  @override
  String get enterPinToMount => 'أدخل رمز PIN للتحميل';

  @override
  String get noPinConfiguredMessage =>
      'لا يوجد رمز PIN مُعدّ. يرجى إدخال كلمة المرور يدويًا.';

  @override
  String pinLockedForSeconds(int seconds) {
    return 'عدد كبير جدًا من المحاولات الفاشلة. تم القفل لمدة $seconds ثانية.';
  }

  @override
  String get initSecureCredsPinMessage =>
      'جارٍ تهيئة بيانات الاعتماد الآمنة. يرجى فتح القفل يدويًا مرة واحدة لتفويض الوصول عبر رمز PIN.';

  @override
  String get setPinButton => 'تعيين رمز PIN';

  @override
  String get changePinButton => 'تغيير رمز PIN';

  @override
  String get pinSetupRequiredBeforeSaving => 'أعدّ رمز PIN قبل الحفظ.';

  @override
  String get pinSetupRequiredAboveBeforeSaving =>
      'أعدّ رمز PIN أعلاه قبل الحفظ.';

  @override
  String get verifyPinTitle => 'التحقق من رمز PIN';

  @override
  String get incorrectPinError => 'رمز PIN غير صحيح';

  @override
  String removedFromListSnack(String name) {
    return 'تمت إزالة \"$name\" من القائمة';
  }

  @override
  String get clearRecentHistoryTitle => 'مسح السجل الأخير؟';

  @override
  String get clearRecentHistoryMessage =>
      'سيؤدي هذا إلى إزالة جميع المستندات الأخيرة من قائمتك. لن تتأثر الملفات الفعلية الموجودة على جهازك.';

  @override
  String get clearAll => 'مسح الكل';

  @override
  String get recentHistoryClearedSnack => 'تم مسح السجل الأخير';

  @override
  String get moreOptionsTooltip => 'المزيد من الخيارات';

  @override
  String get clearHistoryMenuItem => 'مسح السجل';

  @override
  String get openPdfFile => 'فتح ملف PDF';

  @override
  String get noDocumentsYetTitle => 'لا توجد مستندات بعد';

  @override
  String get openPdfToStartMessage => 'افتح ملف PDF من جهازك لبدء القراءة.';

  @override
  String get removeFromListMenuItem => 'إزالة من القائمة';

  @override
  String get justNow => 'الآن';

  @override
  String minutesAgo(int count) {
    return 'قبل $count دقيقة';
  }

  @override
  String hoursAgo(int count) {
    return 'قبل $count ساعة';
  }

  @override
  String daysAgo(int count) {
    return 'قبل $count يوم';
  }

  @override
  String get usbDriveDisconnectedLocked => 'تم فصل محرك USB — تم قفل الحاوية';

  @override
  String get containerAlreadyMounted => 'هذه الحاوية مثبَّتة بالفعل.';

  @override
  String get noVaultFolderFormatDetected =>
      'لم يتم العثور على masterkey.cryptomator أو gocryptfs.conf أو cryfs.config في ذلك المجلد.';

  @override
  String get savedContainerSettingsNotFound =>
      'تعذّر العثور على الإعدادات المحفوظة لهذه الحاوية.';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return 'تعذّر تحديث موقع الحاوية: $error';
  }

  @override
  String filePickerFailed(String error) {
    return 'فشل منتقي الملفات: $error';
  }

  @override
  String get selectContainerFirst => 'اختر حاوية أولاً';

  @override
  String get passwordOrKeyfilesRequired => 'مطلوب كلمة مرور أو ملفات مفاتيح';

  @override
  String get slowPerformanceWarningTitle => 'تحذير من بطء الأداء';

  @override
  String get slowPerformanceWarningMessage =>
      'الوصول المباشر لوحدة التخزين مُعطّل حاليًا.\n\nيخزّن CryFS الملفات موزّعة على آلاف الكتل الصغيرة. سيكون فتح خزنات CryFS غير الفارغة عبر SAF الخاص بـ Android بطيئًا جدًا.\n\nهل تريد فتح الإعدادات لمنح \"الوصول إلى جميع الملفات\" لسرعة أفضل؟';

  @override
  String get unlockAnyway => 'فتح القفل رغم ذلك';

  @override
  String get defaultVaultName => 'الخزنة';

  @override
  String get defaultContainerName => 'الحاوية';

  @override
  String get incorrectPasswordOrInvalidVault =>
      'كلمة مرور غير صحيحة أو خزنة غير صالحة';

  @override
  String get incorrectPasswordOrInvalidContainer =>
      'كلمة مرور غير صحيحة أو حاوية غير صالحة';

  @override
  String get genericUnknownError => 'خطأ غير معروف';

  @override
  String get decryptingLabel => 'جارٍ فك التشفير…';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return 'جارِ تجربة فتحة المفتاح $attempted من $total…';
  }

  @override
  String get luksKeyslotProgressUnknown => 'جارِ تجربة فتحة مفتاح…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return 'جارٍ التحقق من بيانات الاعتماد $attempted من $total…';
  }

  @override
  String get bitlockerCredentialProgressUnknown =>
      'جارٍ التحقق من بيانات الاعتماد…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return 'جارِ تجربة $algo ($slotName)…';
  }

  @override
  String get unlockContainerLabel => 'فتح قفل الحاوية';

  @override
  String get mountContainerTitle => 'تحميل حاوية';

  @override
  String get containerFileSegmentLabel => 'ملف حاوية';

  @override
  String get folderVaultSegmentLabel => 'خزنة مجلد';

  @override
  String formatContainerLabel(String format) {
    return 'حاوية $format';
  }

  @override
  String formatVaultLabel(String format) {
    return 'خزنة $format';
  }

  @override
  String formatDriveLabel(String format) {
    return 'محرك $format';
  }

  @override
  String get encryptedContainerLabel => 'حاوية مشفّرة';

  @override
  String get tapToSelectVaultFolder => 'اضغط لاختيار مجلد الخزنة…';

  @override
  String get tapToSelectContainerFile => 'اضغط لاختيار ملف الحاوية…';

  @override
  String get containerMissingTitle => 'الحاوية مفقودة';

  @override
  String get filePathCouldNotBeResolved => 'تعذّر تحديد مسار الملف';

  @override
  String get containerMissingExplanation =>
      'ربما تم نقل ملف الحاوية أو حذفه، أو أن وحدة التخزين المضيفة له غير متصلة حاليًا.';

  @override
  String get retryButtonLabel => 'إعادة المحاولة';

  @override
  String get locateFileButtonLabel => 'تحديد موقع الملف';

  @override
  String get authenticateToMountSubtitle =>
      'أجرِ المصادقة لتحميل الحاوية بأمان';

  @override
  String get usePasswordButtonLabel => 'استخدام كلمة المرور';

  @override
  String get authenticateButtonLabel => 'المصادقة';

  @override
  String get drawUnlockPatternCardTitle => 'ارسم نمط فتح القفل';

  @override
  String get wrongPatternTryAgain => 'نمط خاطئ — حاول مرة أخرى';

  @override
  String get connectYourPatternSequence => 'صِل تسلسل نمطك';

  @override
  String get usePasswordInsteadButtonLabel =>
      'استخدام كلمة المرور بدلاً من ذلك';

  @override
  String get passwordHintFolderVault => 'أدخل كلمة مرور الخزنة';

  @override
  String get passwordHintBitlocker => 'أدخل كلمة المرور أو مفتاح الاسترداد';

  @override
  String get passwordHintContainer => 'أدخل كلمة مرور الحاوية';

  @override
  String get usingSavedPasswordTooltip => 'يتم استخدام كلمة المرور المحفوظة';

  @override
  String get luksKeyfileReplacesPasswordNote =>
      'بالنسبة لحاويات LUKS، يحل ملف المفتاح محل كلمة المرور.';

  @override
  String get readOnlyModeUsbSubtitle =>
      'التحميل دون السماح بإجراء تغييرات على هذا المحرك';

  @override
  String get readOnlyModeContainerSubtitle =>
      'التحميل دون السماح بإجراء تغييرات على هذه الحاوية';

  @override
  String get rememberContainerLabel => 'تذكّر الحاوية';

  @override
  String get rememberContainerSubtitle =>
      'تثبيت الحاوية في لوحة التحكم للوصول السريع';

  @override
  String get cancelUnlockButtonLabel => 'إلغاء فتح القفل';

  @override
  String get biometricSubjectContainer => 'الحاوية';

  @override
  String get biometricSubjectUsbDrive => 'محرك USB';

  @override
  String get usbNoSavedCredentialsMessage =>
      'لم يتم العثور على كلمة مرور محفوظة. يرجى إدخالها يدويًا.';

  @override
  String get decryptingDriveLabel => 'جارٍ فك تشفير المحرك…';

  @override
  String get usbDeviceAlreadyActiveMounted =>
      'جهاز USB هذا نشط ومثبَّت بالفعل.';

  @override
  String reconnectUsbDriveTitle(String label) {
    return 'إعادة الاتصال بـ \"$label\"';
  }

  @override
  String get unlockUsbDriveTitle => 'فتح قفل محرك USB';

  @override
  String get noUsbStorageDetectedTitle => 'لم يتم اكتشاف تخزين USB';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return 'أجرِ المصادقة لفتح قفل $subject';
  }

  @override
  String get noPatternConfiguredMessage =>
      'لا يوجد نمط مُعدّ. يرجى إدخال كلمة المرور يدويًا.';

  @override
  String patternLockedForSeconds(int seconds) {
    return 'عدد كبير جدًا من المحاولات الفاشلة. تم القفل لمدة $seconds ثانية.';
  }

  @override
  String get initSecureCredsBiometricMessage =>
      'جارٍ تهيئة بيانات الاعتماد الآمنة. يرجى فتح القفل يدويًا مرة واحدة لتفويض الوصول بالبصمة الحيوية.';

  @override
  String get initSecureCredsPatternMessage =>
      'جارٍ تهيئة بيانات الاعتماد الآمنة. يرجى فتح القفل يدويًا مرة واحدة لتفويض الوصول بالنمط.';

  @override
  String get mountExistingContainerTitle => 'تحميل حاوية موجودة';

  @override
  String get mountExistingContainerSubtitle =>
      'فتح قفل حاوية ملف تملكها بالفعل';

  @override
  String get mountSplitContainerTitle => 'تحميل حاوية مجزّأة';

  @override
  String get mountSplitContainerSubtitle =>
      'فتح قفل حاوية مجزّأة مباشرةً، دون دمجها أولاً';

  @override
  String get mountUsbDriveTitle => 'تحميل محرك USB';

  @override
  String get mountUsbDriveSubtitle => 'فتح قفل حاوية على محرك أقراص USB OTG';

  @override
  String get formatUsbDriveTitle => 'تهيئة محرك USB';

  @override
  String get formatUsbDriveSubtitle =>
      'مسح محرك وإنشاء حاوية مشفّرة جديدة عليه';

  @override
  String get createNewContainerTitle => 'إنشاء حاوية جديدة';

  @override
  String get createNewContainerSubtitle => 'تهيئة خزنة مشفّرة جديدة تمامًا';

  @override
  String get lockBeforeRemovingWarning => 'اقفل الحاوية قبل إزالتها.';

  @override
  String get settingsTooltip => 'الإعدادات';

  @override
  String get addVaultFabLabel => 'إضافة خزنة';

  @override
  String removedLabelUndo(String label) {
    return 'تمت إزالة \"$label\"';
  }

  @override
  String get undo => 'تراجع';

  @override
  String get pdfViewerNoSourceProvided => 'لم يتم توفير مصدر PDF.';

  @override
  String get pdfViewerFileEmpty => 'ملف PDF فارغ أو غير قابل للقراءة.';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return 'فشل فحص حجم ملف PDF: $error';
  }

  @override
  String get pdfViewerErrorLoadingTitle => 'خطأ في تحميل PDF';

  @override
  String get pdfViewerNoDocumentLoaded => 'لا يوجد مستند PDF محمّل.';

  @override
  String get add => 'إضافة';

  @override
  String get reset => 'إعادة تعيين';

  @override
  String couldNotExpose(String name) {
    return 'تعذّر عرض \"$name\".';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return 'أصبح \"$name\" متاحًا الآن للتطبيقات الأخرى.';
  }

  @override
  String couldNotUnmount(String name) {
    return 'تعذّر إلغاء تحميل \"$name\".';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تثبيت $count عنصر',
      many: 'تم تثبيت $count عنصرًا',
      few: 'تم تثبيت $count عناصر',
      two: 'تم تثبيت عنصرين',
      one: 'تم تثبيت عنصر واحد',
      zero: 'لم يتم تثبيت عناصر',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم إلغاء تثبيت $count عنصر',
      many: 'تم إلغاء تثبيت $count عنصرًا',
      few: 'تم إلغاء تثبيت $count عناصر',
      two: 'تم إلغاء تثبيت عنصرين',
      one: 'تم إلغاء تثبيت عنصر واحد',
      zero: 'لم يتم إلغاء تثبيت عناصر',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning =>
      'تحميل للقراءة فقط — ستظهر الصور المصغّرة لكن لن يتم حفظها داخل الحاوية في هذه الجلسة.';

  @override
  String failedLoadingFolder(String type) {
    return 'فشل تحميل المجلد: $type';
  }

  @override
  String failedToReadArchive(String type) {
    return 'فشل قراءة الأرشيف: $type';
  }

  @override
  String archiveFormatNotSupported(String ext) {
    return 'تنسيق الأرشيف .$ext غير مدعوم بعد';
  }

  @override
  String get failedToReadFileFromArchive => 'فشل قراءة الملف من الأرشيف';

  @override
  String failedToExtractFile(String type) {
    return 'فشل استخراج الملف: $type';
  }

  @override
  String get failedToReadSecureItem => 'فشل قراءة العنصر الآمن';

  @override
  String get openFileDialogTitle => 'فتح ملف';

  @override
  String chooseHowToOpen(String name) {
    return 'اختر كيفية فتح \"$name\":';
  }

  @override
  String get playVideoAudioViewImageInApp =>
      'تشغيل الفيديو/الصوت أو عرض الصورة داخل التطبيق';

  @override
  String get viewEditTextMarkdownCode => 'عرض/تعديل النص أو Markdown أو الكود';

  @override
  String get sendFileToThirdPartyApp => 'إرسال الملف إلى تطبيق خارجي';

  @override
  String get openAsEllipsis => 'فتح كـ…';

  @override
  String get chooseFileTypeToOpenAs => 'اختر نوع الملف للفتح كـ';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return 'تذكّر الاختيار دائمًا لملفات .$ext';
  }

  @override
  String get alwaysRememberChoiceNoExt =>
      'تذكّر الاختيار دائمًا للملفات بدون امتداد';

  @override
  String get openAsDialogTitle => 'فتح كـ';

  @override
  String get mimeTypeText => 'نص';

  @override
  String get mimeTypeImage => 'صورة';

  @override
  String get mimeTypeVideo => 'فيديو';

  @override
  String get mimeTypeAudio => 'صوت';

  @override
  String get mimeTypeArchive => 'أرشيف';

  @override
  String get mimeTypeOther => 'أخرى';

  @override
  String get scanningSubfoldersForMedia =>
      'جارٍ مسح المجلدات الفرعية بحثًا عن الوسائط…';

  @override
  String get noMediaFilesFoundRecursive =>
      'لم يتم العثور على ملفات وسائط في هذا المجلد أو مجلداته الفرعية';

  @override
  String failedToScanSubfolders(String error) {
    return 'فشل مسح المجلدات الفرعية: $error';
  }

  @override
  String scanningSubfoldersForMediaProgress(int count) {
    return 'جارٍ البحث عن الوسائط في المجلدات الفرعية… تم فحص $count';
  }

  @override
  String get mediaScanCancelled => 'تم إلغاء البحث عن الوسائط';

  @override
  String get mediaScanLimitReached =>
      'تم إيقاف البحث بعد فحص عدد كبير من المجلدات. لم يُعثر على وسائط.';

  @override
  String get noAppFoundForFileType =>
      'لم يتم العثور على تطبيق لهذا النوع من الملفات';

  @override
  String couldNotOpenFile(String name) {
    return 'تعذّر فتح \"$name\"';
  }

  @override
  String get readOnlyCantMove =>
      'هذه الحاوية مثبَّتة للقراءة فقط — لا يمكن نقل العناصر منها.';

  @override
  String get readOnlyCantPaste =>
      'هذه الحاوية مثبَّتة للقراءة فقط — لا يمكن لصق العناصر هنا.';

  @override
  String get clipboardSourceInvalid => 'مصدر الحافظة غير صالح';

  @override
  String get crossContainerPasteNotConfigured =>
      'اللصق بين الحاويات غير مُهيَّأ.';

  @override
  String get crossContainerPasteRequiresBothMounted =>
      'يتطلب اللصق بين الحاويات بقاء كلتا الحاويتين مثبَّتتين.';

  @override
  String get readOnlyCantDelete =>
      'هذه الحاوية مثبَّتة للقراءة فقط — لا يمكن حذف العناصر.';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم حذف $count عنصر',
      many: 'تم حذف $count عنصرًا',
      few: 'تم حذف $count عناصر',
      two: 'تم حذف عنصرين',
      one: 'تم حذف عنصر واحد',
      zero: 'لم يتم حذف عناصر',
    );
    return '$_temp0';
  }

  @override
  String deletedWithFailures(int deleted, int failed) {
    return 'تم حذف $deleted · فشل $failed';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تصدير $count ملف',
      many: 'تم تصدير $count ملفًا',
      few: 'تم تصدير $count ملفات',
      two: 'تم تصدير ملفين',
      one: 'تم تصدير ملف واحد',
      zero: 'لم يتم تصدير ملفات',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed => 'تم إلغاء التصدير أو فشل';

  @override
  String exportError(String type) {
    return 'خطأ في التصدير: $type';
  }

  @override
  String get deleteOriginalTitle => 'حذف الأصل؟';

  @override
  String get deleteOriginalFolderMessage =>
      'هل تريد حذف المجلد الأصلي من جهازك الآن بعد استيراده؟';

  @override
  String get deleteOriginalFilesMessage =>
      'هل تريد حذف الملف (الملفات) الأصلية من جهازك الآن بعد استيرادها؟';

  @override
  String get keepOriginal => 'الاحتفاظ بالأصل';

  @override
  String get deleteOriginalButton => 'حذف الأصل';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم حذف $count عنصر أصلي',
      many: 'تم حذف $count عنصرًا أصليًا',
      few: 'تم حذف $count عناصر أصلية',
      two: 'تم حذف عنصرين أصليين',
      one: 'تم حذف عنصر أصلي واحد',
      zero: 'لم يتم حذف عناصر أصلية',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals => 'تعذّر حذف الملفات الأصلية';

  @override
  String get videoCapturedEncrypted => 'تم التقاط الفيديو وتشفيره';

  @override
  String get photoCapturedEncrypted => 'تم التقاط الصورة وتشفيرها';

  @override
  String cameraCaptureFailed(String type) {
    return 'فشل التقاط الكاميرا: $type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return 'استخراج جميع الملفات إلى المجلد \"$folder\"؟';
  }

  @override
  String get extract => 'استخراج';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم استخراج $count ملف',
      many: 'تم استخراج $count ملفًا',
      few: 'تم استخراج $count ملفات',
      two: 'تم استخراج ملفين',
      one: 'تم استخراج ملف واحد',
      zero: 'لم يتم استخراج ملفات',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return 'فشل الاستخراج: $type';
  }

  @override
  String get archiveSelectionAction => 'أرشفة';

  @override
  String get createArchiveTitle => 'إنشاء أرشيف';

  @override
  String get archiveNameHint => 'أرشيف.zip';

  @override
  String archivedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمت أرشفة $count ملف',
      many: 'تمت أرشفة $count ملفًا',
      few: 'تمت أرشفة $count ملفات',
      two: 'تمت أرشفة ملفين',
      one: 'تمت أرشفة ملف واحد',
      zero: 'لم تتم أرشفة أي ملفات',
    );
    return '$_temp0';
  }

  @override
  String failedToArchiveGeneric(String type) {
    return 'فشل إنشاء الأرشيف: $type';
  }

  @override
  String get closeSearchTooltip => 'إغلاق البحث';

  @override
  String get searchInThisFolderTooltip => 'البحث في هذا المجلد';

  @override
  String get playMediaHereTooltip => 'تشغيل الوسائط هنا';

  @override
  String get rootFolderLabel => 'الجذر';

  @override
  String folderPickerFailed(String error) {
    return 'فشل منتقي المجلد: $error';
  }

  @override
  String get addAVaultTitle => 'إضافة خزنة';

  @override
  String get selectEmptyDestinationFolderFirst => 'اختر مجلد وجهة فارغًا أولاً';

  @override
  String get passwordRequired => 'كلمة المرور مطلوبة';

  @override
  String get vaultCreatedSuccessfully => 'تم إنشاء الخزنة بنجاح.';

  @override
  String get vaultCreationFailedEmptyFolder =>
      'فشل إنشاء الخزنة — تأكد من أن المجلد المحدد فارغ.';

  @override
  String get unknownErrorOccurred => 'حدث خطأ غير معروف';

  @override
  String get containerNameRequired => 'اسم الحاوية مطلوب';

  @override
  String get enterValidSizeGreaterThanZero => 'أدخل حجمًا صالحًا أكبر من 0';

  @override
  String get passwordOrKeyfileRequired =>
      'مطلوب كلمة مرور أو ملف مفتاح واحد على الأقل';

  @override
  String get standardVolumePasswordsDoNotMatch =>
      'كلمتا مرور الوحدة القياسية غير متطابقتين';

  @override
  String get hiddenVolumePasswordsDoNotMatch =>
      'كلمتا مرور الوحدة المخفية غير متطابقتين';

  @override
  String get containerFileCreatedSuccessfully => 'تم إنشاء ملف الحاوية بنجاح.';

  @override
  String get containerCreationCancelledOrFailed =>
      'تم إلغاء إنشاء الحاوية أو فشل.';

  @override
  String insufficientSpaceForContainer(String needed, String available) {
    return 'لا توجد مساحة كافية في الوجهة. المطلوب $needed، والمتاح فقط $available.';
  }

  @override
  String get vaultKindContainerFile => 'ملف حاوية';

  @override
  String get vaultKindFolderVault => 'خزنة مجلد';

  @override
  String get formatFileSystemLabel => 'تهيئة نظام الملفات';

  @override
  String get standardVolumeHeader => 'الوحدة القياسية';

  @override
  String get containerFormatLabel => 'تنسيق الحاوية';

  @override
  String get fileNameLabel => 'اسم الملف';

  @override
  String get containerSizeLabel => 'حجم الحاوية';

  @override
  String get unitLabel => 'الوحدة';

  @override
  String get passwordFieldLabel => 'كلمة المرور';

  @override
  String get confirmPasswordFieldLabelTitleCase => 'تأكيد كلمة المرور';

  @override
  String get hiddenVolumeHeader => 'الوحدة المخفية';

  @override
  String get createHiddenVolumeToggleTitle => 'إنشاء وحدة مخفية';

  @override
  String get createInvisibleSecondaryVolume => 'إنشاء وحدة ثانوية غير مرئية';

  @override
  String get setOuterPasswordFirstToEnable =>
      'عيّن كلمة المرور أو ملفات المفاتيح الخارجية أولاً للتفعيل';

  @override
  String get hiddenPasswordLabel => 'كلمة المرور المخفية';

  @override
  String get confirmHiddenPasswordLabel => 'تأكيد كلمة المرور المخفية';

  @override
  String get hiddenSizeLabel => 'الحجم المخفي';

  @override
  String get unitMbMegabytes => 'ميغابايت (MB)';

  @override
  String get unitGbGigabytes => 'غيغابايت (GB)';

  @override
  String get hiddenFileSystemLabel => 'نظام الملفات المخفي';

  @override
  String get vaultFormatLabel => 'تنسيق الخزنة';

  @override
  String get gocryptfsCipherLabel => 'شيفرة المحتوى';

  @override
  String get cryfsCipherLabel => 'شيفرة المحتوى';

  @override
  String get cryfsBlockSizeLabel => 'حجم الكتلة';

  @override
  String get destinationFolderLabel => 'مجلد الوجهة';

  @override
  String get selectEmptyFolderLabel => 'اختر مجلدًا فارغًا';

  @override
  String get tapToChooseVaultLocation => 'اضغط لاختيار مكان إنشاء الخزنة…';

  @override
  String get folderVaultLimitationsNote =>
      'لا تدعم خزنات المجلدات ملفات المفاتيح أو PIM أو الوحدات المخفية أو اختيار شيفرات VeraCrypt/LUKS.';

  @override
  String get createVaultButton => 'إنشاء الخزنة';

  @override
  String get createContainerButton => 'إنشاء الحاوية';

  @override
  String get vaultCreationInProgressWait => 'جارٍ إنشاء الخزنة. يرجى الانتظار.';

  @override
  String get containerCreationInProgressWait =>
      'جارٍ إنشاء الحاوية. يرجى الانتظار.';

  @override
  String get createEncryptedVaultTitle => 'إنشاء خزنة مشفّرة';

  @override
  String get createEncryptedContainerTitle => 'إنشاء حاوية مشفّرة';

  @override
  String get unitMbShort => 'MB';

  @override
  String get unitGbShort => 'GB';

  @override
  String failedToListUsbDevices(String error) {
    return 'فشل سرد أجهزة USB: $error';
  }

  @override
  String get usbPermissionDenied => 'تم رفض إذن USB';

  @override
  String get couldNotReadDriveCapacity =>
      'تعذّر قراءة سعة المحرك — أدخل الحجم يدويًا.';

  @override
  String get selectUsbDriveFirst => 'اختر محرك USB أولاً';

  @override
  String eraseDeviceTitle(String name) {
    return 'مسح \"$name\"؟';
  }

  @override
  String get eraseDeviceMessage =>
      'سيؤدي هذا إلى مسح كل ما هو موجود حاليًا على محرك USB هذا نهائيًا واستبداله بحاوية مشفّرة جديدة. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get eraseAndCreateButton => 'مسح وإنشاء';

  @override
  String get usbPermissionRequiredToContinue => 'إذن USB مطلوب للمتابعة';

  @override
  String get usbContainerCreatedSnack =>
      'تم إنشاء حاوية USB. استخدم \"تحميل محرك USB\" لفتح قفلها.';

  @override
  String get usbContainerCreationFailed => 'فشل إنشاء حاوية USB.';

  @override
  String get usbStandardVolumeSectionHeader => 'محرك USB والوحدة القياسية';

  @override
  String get formattingErasesEverythingWarning =>
      'تؤدي التهيئة إلى مسح كل ما هو موجود حاليًا على المحرك المحدد.';

  @override
  String get selectUsbDriveLabel => 'اختيار محرك USB';

  @override
  String get noUsbStorageDetected => 'لم يتم اكتشاف تخزين USB';

  @override
  String get connectOtgDriveToFormat => 'قم بتوصيل محرك OTG للتهيئة';

  @override
  String get refreshListButton => 'تحديث القائمة';

  @override
  String get readyToFormat => 'جاهز للتهيئة';

  @override
  String get permissionRequired => 'الإذن مطلوب';

  @override
  String get readingDriveCapacity => 'جارٍ قراءة سعة المحرك…';

  @override
  String get mustNotExceedDriveCapacity =>
      'يجب ألا يتجاوز السعة الفعلية للمحرك.';

  @override
  String get quickFormatTitle => 'تهيئة سريعة';

  @override
  String get quickFormatDescription =>
      'تخطي ملء المحرك بالأصفار. أسرع، لكن لا يمحو البيانات القديمة بأمان.';

  @override
  String get eraseAndCreateContainerButton => 'مسح وإنشاء الحاوية';

  @override
  String get usbContainerCreationInProgressWait =>
      'جارٍ إنشاء الحاوية. يرجى الانتظار.';

  @override
  String get formatUsbDriveScreenTitle => 'تهيئة محرك USB';

  @override
  String get playlistTransitionAnimationLabel => 'حركة انتقال قائمة التشغيل';

  @override
  String get playlistTransitionSlideLabel => 'انزلاق (افتراضي)';

  @override
  String get playlistTransitionFadeLabel => 'تلاشٍ';

  @override
  String get playlistTransitionZoomLabel => 'تكبير وتحجيم';

  @override
  String get playlistTransitionDepthLabel => 'تكديس بالعمق';

  @override
  String get playlistTransitionCubeLabel => 'مكعب ثلاثي الأبعاد';

  @override
  String get playlistTransitionFlipLabel => 'قلب ثلاثي الأبعاد';

  @override
  String get unlockVaultTitle => 'فتح قفل الخزنة';

  @override
  String get openContainerTitle => 'فتح الحاوية';

  @override
  String get selectContainerFileOrFolder => 'اختيار ملف أو مجلد';

  @override
  String get readOnlyModeLabel => 'وضع القراءة فقط';

  @override
  String get readOnlyModeSubtitle => 'يمنع أي عمليات كتابة أو تعديل على الخزنة';

  @override
  String get selectUsbDeviceLabel => 'اختيار جهاز USB';

  @override
  String get noUsbDevicesFound => 'لم يتم العثور على أجهزة تخزين USB متوافقة';

  @override
  String get containerConfigTitle => 'تكوين الخزنة';

  @override
  String get changePasswordTitle => 'تغيير كلمة المرور';

  @override
  String get confirmNewPasswordLabel => 'تأكيد كلمة المرور الجديدة';

  @override
  String get cameraCaptureTitle => 'كاميرا الخزنة';

  @override
  String get takingPhoto => 'جارٍ التقاط الصورة…';

  @override
  String get savingToVault => 'جارٍ الحفظ في الخزنة…';

  @override
  String get noVaultSelected => 'لم يتم تحديد خزنة';

  @override
  String get mediaDiagnosticsTitle => 'تشخيص الوسائط';

  @override
  String get advancedViewerSettingsTitle => 'إعدادات العارض';

  @override
  String get textEditorSaveConfirmTitle => 'تغييرات غير محفوظة';

  @override
  String get textEditorSaveConfirmMessage =>
      'هل تريد حفظ تغييراتك قبل الإغلاق؟';

  @override
  String get saveAndClose => 'حفظ وإغلاق';

  @override
  String get discardChanges => 'تجاهل التغييرات';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تحديد $count عنصر',
      many: 'تم تحديد $count عنصرًا',
      few: 'تم تحديد $count عناصر',
      two: 'تم تحديد عنصرين',
      one: 'تم تحديد عنصر واحد',
      zero: 'لم يتم تحديد عناصر',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'تحديد الكل';

  @override
  String get deselectAll => 'إلغاء تحديد الكل';

  @override
  String get sortOptionsTitle => 'فرز الملفات';

  @override
  String get layoutModeList => 'عرض القائمة';

  @override
  String get layoutModeGrid => 'عرض شبكي';

  @override
  String get layoutModeMasonry => 'شبكة متدرّجة';

  @override
  String get fileOperationsTitle => 'عمليات الملفات';

  @override
  String get conflictResolutionTitle => 'تعارض في الملف';

  @override
  String get replaceExistingFile => 'استبدال الملف الموجود';

  @override
  String get keepBothFiles => 'الاحتفاظ بكليهما (إعادة تسمية الملف الجديد)';

  @override
  String get skipFile => 'تخطي هذا الملف';

  @override
  String get noVaultsFoundTitle => 'لم يتم العثور على خزنات';

  @override
  String get noVaultsFoundSubtitle =>
      'أنشئ حاوية مشفّرة جديدة أو أضف خزنة موجودة للبدء.';

  @override
  String get addExistingVaultButton => 'إضافة خزنة موجودة';

  @override
  String get sortContainersModeManual => 'يدوي (اسحب لإعادة الترتيب)';

  @override
  String get sortContainersModeUnlockStatus =>
      'حالة فتح القفل (المفتوحة أولاً)';

  @override
  String get sortContainersModeNameAZ => 'الاسم (أ–ي)';

  @override
  String get sortContainersModeNameZA => 'الاسم (ي–أ)';

  @override
  String get sortContainersModeNewest => 'الأحدث أولاً';

  @override
  String get sortContainersModeOldest => 'الأقدم أولاً';

  @override
  String get thumbnailCacheAppCacheLabel => 'ذاكرة التخزين المؤقت للتطبيق';

  @override
  String get thumbnailCacheAppCacheDesc =>
      'مخزَّنة بشكل مشفّر في ذاكرة التخزين المؤقت للتطبيق. سريعة؛ تُمسح تلقائيًا عند ضغط التخزين.';

  @override
  String get thumbnailCacheInContainerLabel => 'داخل الحاوية';

  @override
  String get thumbnailCacheInContainerDesc =>
      'مخزَّنة داخل الحاوية المشفّرة. محمية بواسطة الحاوية نفسها، لكن الكتابة أبطأ.';

  @override
  String get thumbnailCacheHiddenFolderLabel => 'مجلد مخفي';

  @override
  String get thumbnailCacheHiddenFolderDesc =>
      'يُخزَّن في مجلد مخفي باسم .thumbcache داخل المجلد الجذري. على عكس ذاكرة التخزين المؤقت للتطبيق، لا يُحذف تلقائيًا.';

  @override
  String get thumbnailCacheDisabledLabel => 'معطّل';

  @override
  String get thumbnailCacheDisabledDesc =>
      'لا يوجد تخزين مؤقت على القرص. يُعاد إنشاء الصور المصغّرة في كل تحميل.';

  @override
  String get unlockContainerTitle => 'فتح قفل الحاوية';

  @override
  String get containerFileSegment => 'ملف حاوية';

  @override
  String get folderVaultSegment => 'خزنة مجلد';

  @override
  String get enableButtonLabel => 'تفعيل';

  @override
  String get retryButtonLabelShort => 'إعادة المحاولة';

  @override
  String get locateFileButton => 'تحديد موقع الملف';

  @override
  String get authenticateButton => 'المصادقة';

  @override
  String get cancelUnlockButton => 'إلغاء فتح القفل';

  @override
  String tryingKeyslotProgress(int attempted, int total) {
    return 'جارِ تجربة فتحة المفتاح $attempted من $total…';
  }

  @override
  String get tryingKeyslotSingle => 'جارِ تجربة فتحة مفتاح…';

  @override
  String verifyingCredentialProgress(int attempted, int total) {
    return 'جارٍ التحقق من بيانات الاعتماد $attempted من $total…';
  }

  @override
  String get verifyingCredentialSingle => 'جارٍ التحقق من بيانات الاعتماد…';

  @override
  String tryingAlgoSlot(String algo, String slotName) {
    return 'جارِ تجربة $algo ($slotName)…';
  }

  @override
  String get hiddenVolumeSlotName => 'الوحدة المخفية';

  @override
  String get standardVolumeSlotName => 'الوحدة القياسية';

  @override
  String get containerMissingSubtitle => 'تعذّر تحديد مسار الملف';

  @override
  String get containerMissingBody =>
      'ربما تم نقل ملف الحاوية أو حذفه، أو أن وحدة التخزين المضيفة له غير متصلة حاليًا.';

  @override
  String get connectPatternSequence => 'صِل تسلسل نمطك';

  @override
  String get passwordLabel => 'كلمة المرور';

  @override
  String get enterVaultPasswordHint => 'أدخل كلمة مرور الخزنة';

  @override
  String get enterBitlockerPasswordHint =>
      'أدخل كلمة المرور أو مفتاح الاسترداد';

  @override
  String get enterContainerPasswordHint => 'أدخل كلمة مرور الحاوية';

  @override
  String get readOnlyModeUsbSubtitleDrive =>
      'التحميل دون السماح بإجراء تغييرات على هذا المحرك';

  @override
  String get rememberDriveLabel => 'تذكّر المحرك';

  @override
  String get rememberDriveSubtitle =>
      'تثبيت المحرك في لوحة التحكم للوصول السريع';

  @override
  String get unlockVaultButtonLabel => 'فتح قفل الخزنة';

  @override
  String get cryfsStorageAccessWarning =>
      'تستخدم خزنات CryFS آلاف ملفات الكتل الصغيرة. بدون الوصول المباشر لوحدة التخزين، سيكون الأداء أبطأ بكثير.';

  @override
  String get folderVaultStorageAccessWarning =>
      'الوصول المباشر لوحدة التخزين مُعطّل. قد يكون فتح الملفات وقراءتها في خزنات المجلدات أبطأ.';

  @override
  String get requestingPermission => 'جارٍ طلب الإذن…';

  @override
  String get unlockAndMountButton => 'فتح القفل والتحميل';

  @override
  String get unlockDriveButton => 'فتح قفل المحرك';

  @override
  String couldntFindDevice(String deviceName) {
    return 'تعذّر العثور على \"$deviceName\"';
  }

  @override
  String get plugDriveBackInRetry =>
      'أعد توصيل المحرك واضغط على إعادة المحاولة، أو اختره أدناه إذا ظهر باسم مختلف.';

  @override
  String get retryConnectionButton => 'إعادة محاولة الاتصال';

  @override
  String get refreshDevicesButton => 'تحديث الأجهزة';

  @override
  String get connectOtgDriveToMount => 'قم بتوصيل محرك أقراص USB OTG للتحميل';

  @override
  String get alreadyActive => 'نشط بالفعل';

  @override
  String get active => 'نشط';

  @override
  String get readyToUnlock => 'جاهز لفتح القفل';

  @override
  String get enterUsbPartitionPassword => 'أدخل كلمة مرور قسم USB';

  @override
  String get biometricAuthenticationTitle => 'المصادقة بالبصمة الحيوية';

  @override
  String get biometricAuthUsbSubtitle =>
      'أجرِ المصادقة لفتح قفل هذا الجهاز USB وتحميله';

  @override
  String get connectPatternSequenceToMount => 'صِل تسلسل نمطك للتحميل';

  @override
  String get selectAllAction => 'تحديد الكل';

  @override
  String get clearSelectionAction => 'مسح التحديد';

  @override
  String get clearSelectionTooltip => 'مسح التحديد';

  @override
  String get selectionOptionsTooltip => 'خيارات التحديد';

  @override
  String get readOnlyContainerTooltip => 'حاوية للقراءة فقط';

  @override
  String get copyAction => 'نسخ';

  @override
  String get moveAction => 'نقل';

  @override
  String get renameAction => 'إعادة تسمية';

  @override
  String get exportToDeviceAction => 'التصدير إلى الجهاز';

  @override
  String get openWithAppAction => 'الفتح باستخدام تطبيق';

  @override
  String get pinAction => 'تثبيت';

  @override
  String get pinSelectedAction => 'تثبيت المحدد';

  @override
  String get unpinAction => 'إلغاء التثبيت';

  @override
  String get unpinSelectedAction => 'إلغاء تثبيت المحدد';

  @override
  String get documentProviderSettingsMenu => 'إعدادات مزوّد المستندات';

  @override
  String get exposeAsDocumentProviderMenu => 'العرض كمزوّد مستندات';

  @override
  String get moreOptionsTooltipShort => 'المزيد من الخيارات';

  @override
  String get copyTooltip => 'نسخ';

  @override
  String get searchInThisFolderHint => 'البحث في هذا المجلد…';

  @override
  String get clearTooltip => 'مسح';

  @override
  String get backToDashboardTooltip => 'العودة إلى لوحة التحكم';

  @override
  String get cancelPasteButton => 'إلغاء اللصق';

  @override
  String get cancelImportButton => 'إلغاء الاستيراد';

  @override
  String get continueButton => 'متابعة';

  @override
  String get skipButton => 'تخطي';

  @override
  String get keepBothButton => 'الاحتفاظ بكليهما';

  @override
  String get clearAllButton => 'مسح الكل';

  @override
  String get autoMountWhenUnlocksTitle =>
      'التحميل التلقائي عند فتح قفل الحاوية';

  @override
  String get autoMountWhenUnlocksSubtitle =>
      'عرض هذا المجلد تلقائيًا مرة أخرى في المرة القادمة';

  @override
  String get unmountButton => 'إلغاء التحميل';

  @override
  String get filtersMenuItem => 'عوامل التصفية';

  @override
  String get settingsMenuItem => 'الإعدادات';

  @override
  String get sortOptionsTooltip => 'خيارات الفرز';

  @override
  String get layoutOptionsTooltip => 'خيارات التخطيط';

  @override
  String get lockContainerTooltip => 'قفل الحاوية';

  @override
  String get renameTooltip => 'إعادة تسمية';

  @override
  String get cancelUpdatingPasswordTooltip => 'إلغاء تحديث كلمة المرور';

  @override
  String get unlockSettingsButton => 'إعدادات فتح القفل';

  @override
  String get updateSavedCredentialsButton => 'تحديث بيانات الاعتماد المحفوظة';

  @override
  String get verifyCredentialsTitle => 'التحقق من بيانات الاعتماد';

  @override
  String get verifyButton => 'تحقق';

  @override
  String get displayNameTitle => 'اسم العرض';

  @override
  String get containerNameHint => 'اسم الحاوية';

  @override
  String get deleteFileDialogTitle => 'حذف الملف؟';

  @override
  String get deleteFilePermanentWarning =>
      'هذا الإجراء نهائي ولا يمكن التراجع عنه.';

  @override
  String get unsavedChangesTitle => 'تغييرات غير محفوظة';

  @override
  String get unsavedChangesMessage =>
      'لديك تغييرات غير محفوظة. هل تريد حفظها قبل الإغلاق؟';

  @override
  String get discardButton => 'تجاهل';

  @override
  String get decryptingFileContent => 'جارٍ فك تشفير محتوى الملف...';

  @override
  String get cannotOpenFile => 'لا يمكن فتح الملف';

  @override
  String get changesSavedSuccessfully => 'تم حفظ التغييرات بنجاح';

  @override
  String saveFailedWithError(String error) {
    return 'فشل الحفظ: $error';
  }

  @override
  String linesCount(int count) {
    return 'الأسطر: $count';
  }

  @override
  String charsCount(int count) {
    return 'الأحرف: $count';
  }

  @override
  String get unsavedChangesLabel => 'تغييرات غير محفوظة';

  @override
  String get savedToVault => 'تم الحفظ في الخزنة';

  @override
  String get saveChangesTooltip => 'حفظ التغييرات';

  @override
  String get textEditorDecryptFailedMessage => 'فشل فك تشفير الملف من الخزنة.';

  @override
  String get textEditorInvalidTextFileMessage =>
      'لا يبدو أن هذا الملف ملف نصي صالح.';

  @override
  String get textEditorWriteBackFailedMessage =>
      'فشلت إعادة كتابة الملف إلى الخزنة.';

  @override
  String get backTooltip => 'رجوع';

  @override
  String get forwardTooltip => 'التالي';

  @override
  String get reloadTooltip => 'إعادة التحميل';

  @override
  String get optionsTooltip => 'خيارات';

  @override
  String get htmlViewerErrorTitle => 'تعذّر عرض هذه الصفحة';

  @override
  String get htmlViewerLoadFailedMessage => 'فشل تحميل الملف';

  @override
  String get enableJavaScriptDialogTitle => 'تفعيل JavaScript؟';

  @override
  String get enableJavaScriptDialogMessage =>
      'سيُسمح للصفحة بتشغيل نصوصها البرمجية المحلية الخاصة بها. ما زال لا يوجد لديها وصول إلى الشبكة — لا يمكن إرسال أو استقبال أي شيء في هذه الخزنة عبر الإنترنت.';

  @override
  String get disableJavaScriptMenu => 'تعطيل JavaScript';

  @override
  String get enableJavaScriptMenu => 'تفعيل JavaScript';

  @override
  String get enterFullscreenMenu => 'الدخول إلى ملء الشاشة';

  @override
  String failedToOpenExternalApp(String error) {
    return 'فشل الفتح في تطبيق خارجي: $error';
  }

  @override
  String get thisFolderMenu => 'هذا المجلد';

  @override
  String get allInclSubfoldersMenu => 'الكل (بما في ذلك المجلدات الفرعية)';

  @override
  String get disableShuffleMenu => 'تعطيل التشغيل العشوائي';

  @override
  String get shufflePlaylistMenu => 'تشغيل قائمة التشغيل عشوائيًا';

  @override
  String get playlistOptionsTooltip => 'خيارات قائمة التشغيل';

  @override
  String get enablePlaylistTooltip => 'تفعيل قائمة التشغيل';

  @override
  String get moreActionsTooltip => 'المزيد من الإجراءات';

  @override
  String get forcePortraitMenu => 'فرض الوضع الرأسي';

  @override
  String get forceLandscapeMenu => 'فرض الوضع الأفقي';

  @override
  String get autoRotateSensorMenu => 'تدوير تلقائي (المستشعر)';

  @override
  String get screenOrientationMenu => 'اتجاه الشاشة';

  @override
  String get playlistTransitionMenu => 'انتقال قائمة التشغيل';

  @override
  String get renameFileMenu => 'إعادة تسمية الملف';

  @override
  String get deleteFileMenu => 'حذف الملف';

  @override
  String get thumbnailCarouselTooltip => 'عرض دائري للصور المصغّرة';

  @override
  String get advancedSettingsTooltip => 'إعدادات متقدمة';

  @override
  String get previousTooltip => 'السابق';

  @override
  String get nextTooltip => 'التالي';

  @override
  String get diagnosticsCopiedToClipboard => 'تم نسخ التشخيص إلى الحافظة';

  @override
  String get diagnosticsTitle => 'التشخيص';

  @override
  String get copyDiagnosticsTooltip => 'نسخ التشخيص';

  @override
  String get closeTooltip => 'إغلاق';

  @override
  String get diagnosticsPlaybackSection => 'التشغيل';

  @override
  String get diagnosticsEngineSection => 'المحرك';

  @override
  String get diagnosticsStateLabel => 'الحالة';

  @override
  String get diagnosticsResolutionLabel => 'الدقة';

  @override
  String get diagnosticsAspectRatioLabel => 'نسبة العرض إلى الارتفاع';

  @override
  String get diagnosticsPositionLabel => 'الموضع';

  @override
  String get diagnosticsDurationLabel => 'المدة';

  @override
  String get diagnosticsErrorLabel => 'خطأ';

  @override
  String get diagnosticsPlayerLabel => 'المشغّل';

  @override
  String get diagnosticsDecodingLabel => 'فك الترميز';

  @override
  String get diagnosticsExoPlayerValue => 'ExoPlayer (Android)';

  @override
  String get diagnosticsHardwareAcceleratedValue => 'مُسرَّع بالأجهزة';

  @override
  String get diagnosticsUnknownValue => 'غير معروف';

  @override
  String get diagnosticsStateBuffering => 'جارٍ التخزين المؤقت';

  @override
  String get diagnosticsStatePlaying => 'قيد التشغيل';

  @override
  String get diagnosticsStatePaused => 'متوقف مؤقتًا';

  @override
  String get diagnosticsDurationUnavailable => '--:--';

  @override
  String get rotate90Label => 'تدوير 90°';

  @override
  String get imageFitModeLabel => 'وضع ملاءمة الصورة';

  @override
  String get slideshowDelayLabel => 'مدة عرض الشرائح';

  @override
  String get playbackSpeedLabel => 'سرعة التشغيل';

  @override
  String get subtitlesLabel => 'الترجمة';

  @override
  String get imageSettingsTitle => 'إعدادات الصورة';

  @override
  String get playbackSettingsTitle => 'إعدادات التشغيل';

  @override
  String get imageFitContain => 'احتواء';

  @override
  String get imageFitWidth => 'ملاءمة العرض';

  @override
  String get imageFitHeight => 'ملاءمة الارتفاع';

  @override
  String nSecondsDelay(int n) {
    return '$n ثانية';
  }

  @override
  String playbackSpeedNormal(String speed) {
    return '${speed}x (عادي)';
  }

  @override
  String playbackSpeedValue(String speed) {
    return '${speed}x';
  }

  @override
  String slideshowDelaySecondsValue(int seconds) {
    return '$seconds ث';
  }

  @override
  String rotationDegreesValue(int degrees) {
    return '$degrees°';
  }

  @override
  String get settingsTooltipShort => 'الإعدادات';

  @override
  String get sourceCodeTooltip => 'الكود المصدري';

  @override
  String get donateTooltip => 'تبرّع';

  @override
  String get shareAppTooltip => 'مشاركة التطبيق';

  @override
  String get resetToDefaultsTooltip => 'إعادة التعيين إلى الافتراضي';

  @override
  String get usbUnlockContainerTitle => 'فتح قفل حاوية USB';

  @override
  String get usbMountContainerTitle => 'تحميل محرك USB';

  @override
  String get staticLabel => 'ثابت';

  @override
  String get unmuteTooltip => 'إلغاء كتم الصوت';

  @override
  String get muteTooltip => 'كتم الصوت';

  @override
  String get playOnceDisabledTooltip =>
      'تشغيل مرة واحدة (التقدم التلقائي معطّل)';

  @override
  String get playAndAdvanceTooltip => 'تشغيل والانتقال إلى التالي';

  @override
  String get loopCurrentVideoTooltip => 'تكرار الفيديو الحالي';

  @override
  String get clearThumbnailCacheDialogTitle =>
      'مسح ذاكرة الصور المصغّرة المؤقتة؟';

  @override
  String get clearThumbnailCacheDialogMessage =>
      'سيؤدي هذا إلى حذف الصور المصغّرة المخزّنة مؤقتًا لهذه الخزنة. سيُعاد إنشاؤها في المرة التالية التي تتصفح فيها الوسائط.';

  @override
  String get clearCacheButton => 'مسح ذاكرة التخزين المؤقت';

  @override
  String get appCacheClearedUnlockMessage =>
      'تم مسح ذاكرة التخزين المؤقت للتطبيق. افتح قفل الحاوية لمسح الذاكرة المؤقتة الداخلية.';

  @override
  String get allThumbnailCachesClearedMessage =>
      'تم مسح جميع ذاكرات التخزين المؤقت للصور المصغّرة بنجاح.';

  @override
  String get appCacheClearedContainerFailedMessage =>
      'تم مسح ذاكرة التخزين المؤقت للتطبيق، لكن فشل المسح داخل الحاوية.';

  @override
  String get failedToClearThumbnailCachesMessage =>
      'فشل مسح ذاكرات التخزين المؤقت للصور المصغّرة.';

  @override
  String get authenticateToModifySettingsPrompt =>
      'أجرِ المصادقة لتعديل الإعدادات';

  @override
  String get usbVaultSettingsTitle => 'إعدادات خزنة USB';

  @override
  String get vaultSettingsTitle => 'إعدادات الخزنة';

  @override
  String get generalSectionHeader => 'عام';

  @override
  String get securityCredentialsSectionHeader => 'الأمان وبيانات الاعتماد';

  @override
  String get securityOptionsLockedTitle => 'خيارات الأمان مقفلة';

  @override
  String get authenticateOriginalCredentialsMessage =>
      'أجرِ المصادقة ببيانات اعتماد الحاوية الأصلية لتعديل إعدادات الأمان.';

  @override
  String get unlockCredentialsLabel => 'بيانات اعتماد فتح القفل';

  @override
  String get unavailableSuffixLabel => '(غير متاح)';

  @override
  String get patternSetupRequiredBeforeSaving => 'أعدّ نمطًا قبل الحفظ.';

  @override
  String get passwordKeystoreEncryptedHelperText =>
      'يتم تشفير كلمة المرور باستخدام Android Keystore. اتركها فارغة إذا كنت تستخدم ملفات المفاتيح فقط.';

  @override
  String get changePatternButton => 'تغيير النمط';

  @override
  String get setPatternButton => 'تعيين نمط';

  @override
  String get cacheDerivedKeyLabel => 'تخزين المفتاح المشتق مؤقتًا';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      'تخطي دالة اشتقاق المفتاح scrypt الخاصة بـ CryFS في المرة القادمة (يبقى المفتاح في Android Keystore)';

  @override
  String get reuseKeyMaterialKeystoreSubtitle =>
      'إعادة استخدام مادة المفتاح في Android Keystore';

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle =>
      'تثبيت الخوارزمية لتخطي الكشف التلقائي عند فتح القفل.';

  @override
  String get changeContainerPasswordTitle => 'تغيير كلمة مرور الحاوية';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      'لا يمكن تغيير بيانات اعتماد BitLocker داخل التطبيق. استخدم \"إدارة BitLocker\" على Windows.';

  @override
  String get systemIntegrationSectionHeader => 'النظام والتكامل';

  @override
  String get autoLockDurationLabel => 'مدة القفل التلقائي';

  @override
  String get neverAutoLockOption => 'أبدًا';

  @override
  String get exposeContentToFilePickerSubtitle =>
      'عرض المحتوى في منتقي ملفات النظام عند فتح القفل';

  @override
  String get thumbnailStorageSectionHeader => 'تخزين الصور المصغّرة';

  @override
  String get cacheModeLabel => 'وضع التخزين المؤقت';

  @override
  String get useGlobalDefaultSubtitle => 'استخدام الإعداد الافتراضي العام';

  @override
  String get thumbnailQualityLabel => 'جودة الصور المصغّرة';

  @override
  String get clearThumbnailCacheTitle => 'مسح ذاكرة الصور المصغّرة المؤقتة';

  @override
  String get removeCachedThumbnailsSubtitle =>
      'إزالة الصور المصغّرة المخزَّنة مؤقتًا للصور والفيديوهات';

  @override
  String get vaultInformationSectionHeader => 'معلومات الخزنة';

  @override
  String get vaultInformationTileTitle => 'عرض تفاصيل الخزنة';

  @override
  String get vaultInformationTileSubtitle =>
      'الشيفرة والتنسيق وتفاصيل تقنية أخرى';

  @override
  String get vaultInfoLocationLabel => 'الموقع';

  @override
  String get vaultInfoRequiresUnlockTitle => 'يلزم فتح القفل';

  @override
  String get vaultInfoRequiresUnlockMessage =>
      'افتح قفل هذه الخزنة لعرض تفاصيلها التقنية.';

  @override
  String get vaultInfoLoadFailedTitle => 'تعذّر تحميل معلومات الخزنة';

  @override
  String get vaultInfoLoadFailedMessage =>
      'حدث خطأ ما أثناء قراءة تفاصيل هذه الخزنة.';

  @override
  String get vaultInfoVolumeSizeLabel => 'حجم الوحدة';

  @override
  String get vaultInfoFileSystemLabel => 'نظام الملفات';

  @override
  String get vaultInfoHiddenVolumeLabel => 'الوحدة المخفية';

  @override
  String get vaultInfoReadOnlyLabel => 'للقراءة فقط';

  @override
  String get vaultInfoLuksVersionLabel => 'إصدار LUKS';

  @override
  String get vaultInfoSectorSizeLabel => 'حجم القطاع';

  @override
  String get vaultInfoVaultFormatLabel => 'تنسيق الخزنة';

  @override
  String get vaultInfoCipherComboLabel => 'مجموعة الشيفرات';

  @override
  String get vaultInfoShorteningThresholdLabel => 'عتبة اختصار اسم الملف';

  @override
  String get vaultInfoFormatVersionLabel => 'إصدار التنسيق';

  @override
  String get vaultInfoContentCipherLabel => 'شيفرة المحتوى';

  @override
  String get vaultInfoFilenameEncryptionLabel => 'أسماء الملفات';

  @override
  String get vaultInfoPlaintextNamesValue => 'نص عادي';

  @override
  String get vaultInfoEncryptedNamesValue => 'مشفّرة';

  @override
  String get vaultInfoBlockCipherLabel => 'شيفرة الكتلة';

  @override
  String get vaultInfoBlockSizeLabel => 'حجم الكتلة';

  @override
  String get vaultInfoCreatedWithVersionLabel => 'أُنشئت باستخدام';

  @override
  String get vaultInfoLastOpenedWithVersionLabel => 'آخر فتح باستخدام';

  @override
  String get vaultInfoYesValue => 'نعم';

  @override
  String get vaultInfoNoValue => 'لا';

  @override
  String get vaultInfoBitlockerNote =>
      'لا يقوم هذا التطبيق بتحليل بيانات تعريف رأس BitLocker الخاصة به، لذا فإن تفاصيل الشيفرة والإصدار غير متاحة هنا.';

  @override
  String get patternSetupRequiredAboveBeforeSaving =>
      'أعدّ نمطًا أعلاه قبل الحفظ.';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      'مطلوب كلمة مرور أو \"تخزين المفتاح المشتق مؤقتًا\" مع ملفات مفاتيح لطريقة فتح القفل هذه.';

  @override
  String get saveConfigurationButton => 'حفظ التكوين';

  @override
  String get incorrectPatternError => 'نمط غير صحيح';

  @override
  String get verifyPatternTitle => 'التحقق من النمط';

  @override
  String get incorrectPasswordError => 'كلمة مرور غير صحيحة';

  @override
  String get verificationFailedError => 'فشل التحقق';

  @override
  String get incorrectCredentialsError => 'بيانات اعتماد غير صحيحة';

  @override
  String get containerPasswordOptionalLabel =>
      'كلمة مرور الحاوية (اختيارية عند استخدام ملف مفتاح فقط)';

  @override
  String get pimOptionalLabel => 'PIM (اختياري)';

  @override
  String get usbDriveLockedLabel => 'محرك USB · مقفل';

  @override
  String get lockedContainerLabel => 'حاوية مقفلة';

  @override
  String get operationInProgressWaitMessage =>
      'هناك عملية قيد التنفيذ. يرجى الانتظار قبل القفل.';

  @override
  String get reconnectUsbTooltip => 'إعادة توصيل USB';

  @override
  String get unlockContainerTooltip => 'فتح قفل الحاوية';

  @override
  String lockFailedMessage(String errorType) {
    return 'فشل القفل: $errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired =>
      'مطلوب كلمة مرور جديدة أو ملفات مفاتيح.';

  @override
  String get newPasswordsDoNotMatch => 'كلمتا المرور الجديدتان غير متطابقتين.';

  @override
  String get passwordChangedSuccessfullyMessage =>
      'تم تغيير كلمة المرور بنجاح.';

  @override
  String get failedToChangePasswordMessage =>
      'فشل تغيير كلمة المرور. تحقق من بيانات الاعتماد القديمة.';

  @override
  String get currentCredentialsSectionHeader => 'بيانات الاعتماد الحالية';

  @override
  String get oldPasswordLabel => 'كلمة المرور القديمة';

  @override
  String get oldPimOptionalLabel => 'PIM القديم (اختياري)';

  @override
  String get newCredentialsSectionHeader => 'بيانات الاعتماد الجديدة';

  @override
  String get newPimOptionalLabel => 'PIM الجديد (اختياري)';

  @override
  String get noContainersYetTitle => 'لا توجد حاويات بعد';

  @override
  String get dashboardEmptyStateMessage =>
      'قم بتحميل حاوية VeraCrypt، أو وصّل محرك USB، أو أنشئ خزنة مشفّرة جديدة تمامًا للبدء.';

  @override
  String get sortFieldName => 'الاسم';

  @override
  String get sortFieldSize => 'الحجم';

  @override
  String get sortFieldType => 'النوع';

  @override
  String get sortFieldDate => 'التاريخ';

  @override
  String get layoutModeDetailedList => 'قائمة مفصّلة';

  @override
  String get layoutModeCompactList => 'قائمة مضغوطة';

  @override
  String get layoutModeGalleryGrid => 'شبكة معرض';

  @override
  String get readOnlyCantDeleteTooltip => 'للقراءة فقط — لا يمكن الحذف';

  @override
  String get readOnlyCantMoveTooltip => 'للقراءة فقط — لا يمكن النقل';

  @override
  String get readOnlyCantRenameTooltip => 'للقراءة فقط — لا يمكن إعادة التسمية';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes (جارٍ الحساب…)';
  }

  @override
  String get sizeCalculatingLabel => 'جارٍ الحساب…';

  @override
  String get editSecureItemsToRenameMessage =>
      'عدّل العناصر الآمنة لإعادة تسميتها';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage =>
      'لا يمكن فتح عناصر الخزنة في تطبيقات خارجية';

  @override
  String get mountedReadOnlyTooltip => 'مُحمَّلة للقراءة فقط';

  @override
  String get readOnlyBadgeAbbreviation => 'قراءة فقط';

  @override
  String freeSpaceLabel(String bytes) {
    return '$bytes متاحة';
  }

  @override
  String get filteredLabel => 'مُصفّى';

  @override
  String get statsStorageSectionHeader => 'التخزين';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مجلد',
      many: '$count مجلدًا',
      few: '$count مجلدات',
      two: 'مجلدان',
      one: 'مجلد واحد',
      zero: 'لا مجلدات',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف',
      many: '$count ملفًا',
      few: '$count ملفات',
      two: 'ملفان',
      one: 'ملف واحد',
      zero: 'لا ملفات',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => 'جميع الملفات';

  @override
  String get filterImagesOption => 'الصور';

  @override
  String get filterVideosOption => 'الفيديوهات';

  @override
  String get filterAudioOption => 'الصوت';

  @override
  String get filterDocumentsOption => 'المستندات';

  @override
  String get folderExposedAsStorageExplanation =>
      'يُعرض هذا المجلد كموقع تخزين مستقل خاص به، بحيث يمكن للتطبيقات الأخرى تصفح ملفاته وفتحها مباشرةً.';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر موجود بالفعل',
      many: '$count عنصرًا موجودًا بالفعل',
      few: '$count عناصر موجودة بالفعل',
      two: 'عنصران موجودان بالفعل',
      one: 'عنصر واحد موجود بالفعل',
      zero: 'لا عناصر موجودة بالفعل',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle =>
      'اختر ما سيحدث لكل عنصر، أو طبّق اختيارًا واحدًا على الكل.';

  @override
  String get skipAllChipLabel => 'تخطي الكل';

  @override
  String get overwriteAllChipLabel => 'استبدال الكل';

  @override
  String get overwriteItemDropdownLabel => 'استبدال';

  @override
  String get overwriteFolderDropdownLabel => 'استبدال المجلد';

  @override
  String get fileOpsTransfersInProgressTitle => 'عمليات نقل جارية';

  @override
  String get fileOpsRecentTransfersTitle => 'عمليات النقل الأخيرة';

  @override
  String get fileOpsNoRecentTransfersMessage => 'لا توجد عمليات نقل حديثة';

  @override
  String get fileOpsNoRecentTransfersSubtitle =>
      'ستظهر هنا عمليات النسخ والنقل والحذف أثناء تنفيذها.';

  @override
  String fileOpsShowDetailsLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      many: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصران',
      one: 'عنصر واحد',
      zero: 'لا عناصر',
    );
    return '$_temp0';
  }

  @override
  String get fileOpsCancelTooltip => 'إلغاء';

  @override
  String get fileOpsDismissTooltip => 'إغلاق';

  @override
  String get fileOpsRootDestinationLabel => 'الجذر';

  @override
  String get fileOpsCancelledStatusLabel => 'أُلغي';

  @override
  String fileOpsItemsFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'فشل $count عنصر:',
      many: 'فشل $count عنصرًا:',
      few: 'فشلت $count عناصر:',
      two: 'فشل عنصران:',
      one: 'فشل عنصر واحد:',
      zero: 'فشلت لا عناصر:',
    );
    return '$_temp0';
  }

  @override
  String fileOpsMoreItemsLabel(num count) {
    return '+ $count أخرى';
  }

  @override
  String get transferActivityTooltip => 'عمليات النقل';

  @override
  String fileOpsSpeedLabel(String speed) {
    return '$speed/ث';
  }

  @override
  String fileOpsEtaLabel(String time) {
    return '~$time متبقٍ';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return 'خطأ في قراءة الملف: $error';
  }

  @override
  String get archivePreviewNotAvailableMessage =>
      'المعاينة غير متاحة لهذا النوع من الملفات.';

  @override
  String get avifFailedToRenderMessage => 'فشل عرض AVIF';

  @override
  String get encryptedImageLoadFailedMessage => 'فشل تحميل الصورة المشفّرة';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return 'فشل تحميل الصورة المشفّرة: $error';
  }

  @override
  String get invalidOrCorruptedImageMessage => 'تنسيق صورة غير صالح أو تالف.';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '$current من $total';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '$current من $total  ·  جارٍ الفحص…';
  }

  @override
  String get mediaViewerScanningLabel => 'جارٍ الفحص…';

  @override
  String get mediaFileDeletedMessage => 'تم حذف الملف بنجاح';

  @override
  String get mediaFileDeleteFailedMessage => 'فشل حذف الملف';

  @override
  String get mediaFileRenamedMessage => 'تمت إعادة تسمية الملف بنجاح';

  @override
  String get aboutScreenTitle => 'حول';

  @override
  String get couldNotOpenLinkMessage => 'تعذّر فتح الرابط';

  @override
  String get fileManagerSettingsTitle => 'إعدادات مدير الملفات';

  @override
  String get showMediaThumbnailsLabel => 'إظهار الصور المصغّرة للوسائط';

  @override
  String get showMediaThumbnailsDesc =>
      'عرض معاينات مصغّرة للصور والفيديوهات في طريقة عرض القائمة';

  @override
  String get showFileNamesLabel => 'إظهار أسماء الملفات';

  @override
  String get showFileNamesDesc =>
      'عرض تسميات نصية أسفل العناصر في تخطيط الشبكة';

  @override
  String get showBreadcrumbBarLabel => 'إظهار شريط المسار';

  @override
  String get showBreadcrumbBarDesc => 'شريط التنقل بالمسار أعلى المتصفح';

  @override
  String get showStatsBarLabel => 'إظهار شريط الإحصاءات';

  @override
  String get showStatsBarDesc => 'شريط معلومات عدد الملفات والمساحة الحرة';

  @override
  String get autoStartPlaylistModeLabel => 'بدء وضع قائمة التشغيل تلقائيًا';

  @override
  String get autoStartPlaylistModeDesc =>
      'البدء تلقائيًا في وضع قائمة التشغيل عند فتح عنصر وسائط';

  @override
  String get showPlaylistCarouselLabel => 'إظهار عرض قائمة التشغيل الدائري';

  @override
  String get showPlaylistCarouselDesc =>
      'إظهار زر العرض الدائري للصور المصغّرة عند عرض قوائم تشغيل الوسائط';

  @override
  String get videoPlaybackSliderLabel => 'شريط تمرير موضع تشغيل الفيديو';

  @override
  String get longPressPlaybackDiagnosticsHint =>
      'اضغط مطولاً لعرض تشخيص التشغيل';

  @override
  String get staticImageModeLabel => 'وضع الصورة الثابتة';

  @override
  String slideshowModeActiveLabel(int seconds) {
    return 'وضع عرض الشرائح مفعّل بمهلة $seconds ثانية';
  }

  @override
  String videoPlaybackModeLabel(String mode) {
    return 'وضع تشغيل الفيديو: $mode';
  }

  @override
  String get pauseLabel => 'إيقاف مؤقت';

  @override
  String get playLabel => 'تشغيل';

  @override
  String get emptyFolderTitle => 'مجلد فارغ';

  @override
  String get emptyFolderMessage =>
      'استخدم إجراء الإضافة لإنشاء ملفات أو الاستيراد من الجهاز.';

  @override
  String get noResultsTitle => 'لا توجد نتائج';

  @override
  String noResultsForQueryMessage(String query) {
    return 'لا يوجد في هذا المجلد ما يطابق \"$query\".';
  }

  @override
  String get closeCarouselTooltip => 'إغلاق العرض الدائري';

  @override
  String get playlistScrollModeMenu => 'وضع تمرير قائمة التشغيل';

  @override
  String get playlistScrollHorizontalLabel => 'أفقي';

  @override
  String get playlistScrollVerticalPageLabel => 'رأسي بالصفحات';

  @override
  String get playlistScrollVerticalContinuousLabel => 'رأسي متواصل';

  @override
  String get undoTooltip => 'تراجع';

  @override
  String get redoTooltip => 'إعادة';

  @override
  String get autosavingLabel => 'جارٍ الحفظ التلقائي…';

  @override
  String get savingLabel => 'جارٍ الحفظ…';

  @override
  String autosavedAtLabel(String time) {
    return 'تم الحفظ التلقائي في $time';
  }

  @override
  String cameraDisconnectedError(String message) {
    return 'انقطع اتصال الكاميرا: $message';
  }

  @override
  String get unknownErrorFallback => 'خطأ غير معروف';

  @override
  String get cameraPermissionsRequiredMessage =>
      'يلزم إذنا الكاميرا والميكروفون لاستخدام الكاميرا.';

  @override
  String cameraErrorMessage(String error) {
    return 'خطأ في الكاميرا: $error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage => 'فشل التقاط الصورة';

  @override
  String get cameraRecordingFailedMessage => 'فشل التسجيل';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return 'فشل التسجيل: $error';
  }

  @override
  String get cameraRecordingTooShortMessage =>
      'كان التسجيل قصيرًا جدًا ولا يمكن حفظه';

  @override
  String get cameraCouldNotSaveRecordingMessage => 'تعذّر حفظ التسجيل';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return 'تعذّر حفظ التسجيل: $error';
  }

  @override
  String get cameraCouldNotSwitchLensMessage => 'تعذّر تبديل العدسة';

  @override
  String get cameraEncryptingPhotoLabel => 'جارٍ تشفير الصورة…';

  @override
  String get cameraEncryptingVideoLabel => 'جارٍ تشفير الفيديو…';

  @override
  String get aboutApplicationSectionHeader => 'التطبيق';

  @override
  String get aboutTagline => 'مجاني · مفتوح المصدر · خزنة مشفّرة دون اتصال';

  @override
  String get aboutVersionTitle => 'الإصدار';

  @override
  String aboutVersionSubtitle(String version) {
    return 'الإصدار $version';
  }

  @override
  String get aboutWhatsNewTitle => 'ما الجديد';

  @override
  String get aboutWhatsNewSubtitle =>
      'الاطلاع على التغييرات الأخيرة وملاحظات الإصدار';

  @override
  String get aboutPrivacySecurityTitle => 'الخصوصية والأمان';

  @override
  String get aboutPrivacySecuritySubtitle =>
      'لا وصول للشبكة، ولا يُكتب أي شيء غير مشفّر على القرص';

  @override
  String get aboutSupportedFormatsSectionHeader => 'التنسيقات المدعومة';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt و LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      'الوحدات القياسية والمخفية، PIM مخصّص، ملفات المفاتيح، xts-plain64، Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker و BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle =>
      'دعم عبارات مرور المستخدم ومفتاح الاسترداد الرقمي المكوّن من 48 رقمًا';

  @override
  String get aboutDirectoryVaultsTitle => 'خزنات المجلدات';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator (v7/v8 SIV_GCM و SIV_CTRMAC)، gocryptfs (v2 AES-GCM و XChaCha20)، CryFS (v0.10+ XChaCha20 و AES)';

  @override
  String get aboutVhdTitle => 'الأقراص الصلبة الافتراضية (VHD / VHDX)';

  @override
  String get aboutVhdSubtitle =>
      'تحويل BAT لصور الأقراص الثابتة والديناميكية القابلة للتوسيع';

  @override
  String get aboutNativeCoreEngineSectionHeader => 'المحرك الأساسي الأصلي';

  @override
  String get aboutCompiledLibrariesTitle => 'مكتبات ++C المُجمَّعة';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.0 (تشفير الأجهزة ARMv8 و SHA-2)\n• libavif و libgav1 (وحدة فك ترميز صور AVIF الأصلية)\n• ChaN FatFs v4.0.4 (FAT12/16/32 و exFAT)\n• Tuxera NTFS-3G و mkntfs المدمج\n• e2fsprogs v1.47.4 libext2fs (ext2/ext3/ext4)\n• Dislocker Virtual I/O (BitLocker FVE / To Go)\n• VeraCrypt 1.26.29 (Twofish، Serpent، Camellia، Kuznyechik، Whirlpool، Streebog، BLAKE2s، Argon2id/i)\n• cJSON v1.7.18 (بيانات وصفية لـ LUKS2 و Cryptomator)';

  @override
  String get aboutCommunitySectionHeader => 'المجتمع والمصادر المفتوحة';

  @override
  String get aboutReportIssueTitle => 'الإبلاغ عن مشكلة';

  @override
  String get aboutReportIssueSubtitle => 'وجدت خطأً؟ أرسل بلاغًا على GitHub';

  @override
  String get reportIssueSheetTitle => 'الإبلاغ عن مشكلة';

  @override
  String get reportIssueSheetSubtitle =>
      'اختر الخيار الأنسب لمشكلتك — سيؤدي ذلك إلى فتح نموذج GitHub معبأ مسبقًا';

  @override
  String get reportIssueBugTitle => 'الإبلاغ عن خلل';

  @override
  String get reportIssueBugSubtitle => 'حدث تعطل أو شيء ما لا يعمل كما ينبغي';

  @override
  String get reportIssueContainerTitle => 'مشكلة في الحاوية / الخزنة';

  @override
  String get reportIssueContainerSubtitle =>
      'مشكلة في فتح القفل أو التحميل أو خاصة بتنسيق معيّن';

  @override
  String get reportIssueFeatureTitle => 'طلب ميزة';

  @override
  String get reportIssueFeatureSubtitle => 'اقترح فكرة أو تحسينًا';

  @override
  String get reportIssueOtherTitle => 'شيء آخر';

  @override
  String get reportIssueOtherSubtitle => 'تصفح جميع القوالب على GitHub';

  @override
  String get aboutContributorsTitle => 'المساهمون';

  @override
  String get aboutContributorsSubtitle =>
      'الأشخاص الذين ساعدوا في بناء VaultExplorer';

  @override
  String get aboutLicensesTitle => 'تراخيص المصدر المفتوح';

  @override
  String get aboutLicensesSubtitle =>
      'المكتبات الخارجية المستخدَمة في هذا التطبيق';

  @override
  String get aboutFooterMadeWithLove => 'صُنع بـ ❤ من أجل الخصوصية.';

  @override
  String get aboutVersionCopiedMessage =>
      'تم نسخ معلومات الإصدار — مفيدة لتقارير الأخطاء';

  @override
  String aboutVersionClipboardText(String version) {
    return 'VaultExplorer v$version (Android)';
  }

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer — خزنة مجانية ومفتوحة المصدر وتعمل دون اتصال لأجهزة Android.\n\nخزّن كلمات المرور والملاحظات والملفات داخل حاوية مشفّرة (VeraCrypt وLUKS وBitLocker وCryptomator وGocryptfs وCryFS).\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage =>
      'تم نسخ رابط قابل للمشاركة إلى الحافظة';

  @override
  String get aboutPrivacySheetTitle => 'الخصوصية وأمان البيانات';

  @override
  String get aboutPrivacySheetSubtitle =>
      'تصميم أمني محلي 100% دون اتصال بالشبكة';

  @override
  String get privacyPointNoNetworkTitle => 'لا حاجة للوصول إلى الشبكة';

  @override
  String get privacyPointNoNetworkBody =>
      'لا يطلب VaultExplorer إذن android.permission.INTERNET على Android. ولا يمكنه التواصل عبر أي شبكة.';

  @override
  String get privacyPointNoDiskLeaksTitle => 'صفر تسريبات غير مشفّرة على القرص';

  @override
  String get privacyPointNoDiskLeaksBody =>
      'يتم فك التشفير وإعادة التشفير بالكامل داخل ذاكرة النظام. لا يتم أبدًا حفظ ملفات مؤقتة غير مشفّرة على تخزين الجهاز.';

  @override
  String get privacyPointNoAnalyticsTitle => 'لا تحليلات ولا قياس عن بُعد';

  @override
  String get privacyPointNoAnalyticsBody =>
      'لا يوجد أي إبلاغ عن الأعطال، أو تتبع للاستخدام، أو حزمة تطوير برمجيات (SDK) خارجية تجمع بيانات عنك أو عن جهازك.';

  @override
  String get privacyPointKeystoreTitle => 'تبقى الأسرار داخل Android Keystore';

  @override
  String get privacyPointKeystoreBody =>
      'يتم إحكام إغلاق كلمات المرور المحفوظة والأنماط والمفاتيح المشتقة المخزَّنة مؤقتًا باستخدام AES-256-GCM داخل Android Keystore المدعوم بالأجهزة.';

  @override
  String get privacyPointPosixTitle => 'تسريع POSIX والوصول إلى وحدة التخزين';

  @override
  String get privacyPointPosixBody =>
      'تُقرأ الملفات داخل خزنات المجلدات وتُكتب مباشرةً عند الإمكان، متجاوزةً طبقة SAF الأبطأ في Android بالنسبة للمجلدات الكبيرة.';

  @override
  String get privacyPointScreenClipboardTitle => 'حماية الشاشة والحافظة';

  @override
  String get privacyPointScreenClipboardBody =>
      'حظر معاينة لقطات الشاشة/مبدّل المهام (FLAG_SECURE)، بالإضافة إلى تعقيم تلقائي للحافظة التالفة عند تركيز النافذة. تُوسَم كلمات المرور المنسوخة من خزنة العناصر كحساسة على Android 13 فأعلى وتُمسح تلقائيًا بعد 30 ثانية إذا لم تُستخدم.';

  @override
  String get privacyPointMaskModeTitle => 'وضع التمويه';

  @override
  String get privacyPointMaskModeBody =>
      'يموّه التطبيق اختياريًا كمتصفح أرشيف zip يعمل فعليًا، بأيقونة واسم مختلفين. اضغط مطولاً على العنوان لمدة ثانيتين للوصول إلى خزنتك الحقيقية.';

  @override
  String get privacyPointExternalLinksTitle =>
      'تُفتح الروابط الخارجية في المتصفح';

  @override
  String get privacyPointExternalLinksBody =>
      'يؤدي الضغط على الروابط إلى تسليم الطلب لتطبيق المتصفح الافتراضي لديك، الذي يتولى معالجته.';

  @override
  String get truncatedListingWarning =>
      'يتم عرض أول 50,000 عنصر — يحتوي هذا المجلد على ملفات أكثر.';

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '$size بكسل · جودة $quality%';
  }

  @override
  String holdToSpeedIndicatorLabel(String speed) {
    return 'سرعة ×$speed';
  }

  @override
  String get toolbarLayoutSectionHeader => 'تخطيط شريط الأدوات';

  @override
  String get listViewOptionsSectionHeader => 'خيارات عرض القائمة';

  @override
  String get detailedListViewColumnsSectionHeader =>
      'أعمدة عرض القائمة المفصّلة';

  @override
  String get galleryGridViewSectionHeader => 'عرض شبكة المعرض';

  @override
  String get browserLayoutSectionHeader => 'تخطيط المتصفح';

  @override
  String get mediaViewerSectionHeader => 'عارض الوسائط';

  @override
  String get viewModeAction => 'وضع العرض';

  @override
  String get sortAction => 'فرز';

  @override
  String get playMediaAction => 'تشغيل الوسائط';

  @override
  String containerSpaceSummary(String free, String total) {
    return '$free حرة · $total إجمالي';
  }

  @override
  String volMountedSummary(int volId) {
    return 'المجلد $volId · مثبَّت';
  }

  @override
  String vaultOccupiedSpaceSummary(String used) {
    return '$used مستخدمة';
  }

  @override
  String get incorrectPasswordOrKeyfilesDriveError =>
      'كلمة مرور/ملفات مفاتيح غير صحيحة أو محرك غير مدعوم';

  @override
  String driveUsableCapacity(int mb) {
    return 'السعة القابلة للاستخدام للمحرك: $mb ميغابايت. يجب ألا تتجاوزها.';
  }

  @override
  String get unlockMethodManualPassword => 'كلمة مرور يدوية';

  @override
  String get unlockMethodRememberPassword => 'تذكّر كلمة المرور';

  @override
  String get unlockMethodBiometrics => 'فتح القفل بالبصمة الحيوية';

  @override
  String get unlockMethodPattern => 'فتح القفل بالنمط';

  @override
  String get unlockMethodPin => 'فتح القفل برمز PIN';

  @override
  String get unlockMethodSubtitlePassword => 'اكتب كلمة المرور في كل مرة';

  @override
  String get unlockMethodSubtitleRememberPassword =>
      'مخزَّنة بأمان في Android Keystore';

  @override
  String get unlockMethodSubtitleBiometrics =>
      'استخدم بصمة الإصبع أو الوجه لفتح القفل';

  @override
  String get unlockMethodSubtitlePattern => 'ارسم نمطًا لفتح القفل';

  @override
  String get unlockMethodSubtitlePin => 'أدخل رمز PIN لفتح القفل';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError =>
      'وحدة فك ترميز الفيديو غير متاحة — تعارض في برنامج ترميز الأجهزة';

  @override
  String get mediaStreamInitFailedError => 'فشلت تهيئة تدفق الوسائط';

  @override
  String get invalidAvifImage => 'صورة AVIF غير صالحة';

  @override
  String get verbImport => 'استيراد';

  @override
  String get verbExport => 'تصدير';

  @override
  String get verbMove => 'نقل';

  @override
  String get verbCopy => 'نسخ';

  @override
  String get verbDelete => 'حذف';

  @override
  String get verbImported => 'مستورَد';

  @override
  String get verbExported => 'تم التصدير';

  @override
  String get verbMoved => 'منقول';

  @override
  String get verbCopied => 'منسوخ';

  @override
  String get verbDeleted => 'محذوف';

  @override
  String get verbImporting => 'جارٍ الاستيراد';

  @override
  String get verbExporting => 'جارٍ التصدير';

  @override
  String get verbMoving => 'جارٍ النقل';

  @override
  String get verbCopying => 'جارٍ النسخ';

  @override
  String get verbDeleting => 'جارٍ الحذف';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر',
      many: '$count عنصرًا',
      few: '$count عناصر',
      two: 'عنصران',
      one: 'عنصر واحد',
      zero: 'لا عناصر',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count عنصر $verb',
      many: '$count عنصرًا $verb',
      few: '$count عناصر $verb',
      two: 'عنصران $verb',
      one: 'عنصر واحد $verb',
      zero: 'لا عناصر $verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return 'تم تخطي $count';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return 'فشل $count';
  }

  @override
  String get statusCancelled => 'أُلغي';

  @override
  String get statusFailed => 'فشل';

  @override
  String get statusCompleted => 'اكتمل';

  @override
  String get fileOpCheckingSpace => 'جارٍ التحقق من المساحة المتاحة…';

  @override
  String get fileOpResolvingConflicts => 'جارٍ حل التعارضات…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return 'لا توجد مساحة كافية — مطلوب $required، والمتاح فقط $free';
  }

  @override
  String get fileOpDiskFullPartialRemoved =>
      'القرص ممتلئ — تمت إزالة الملفات الجزئية';

  @override
  String get fileOpMoveFailed => 'فشل النقل';

  @override
  String get fileOpCopyFailed => 'فشل النسخ';

  @override
  String get fileOpDeleteFailed => 'فشل الحذف';

  @override
  String get fileOpDiskFull => 'القرص ممتلئ';

  @override
  String get fileOpImporting => 'جارٍ الاستيراد…';

  @override
  String get fileOpExporting => 'جارٍ التصدير…';

  @override
  String fileOpImportingName(String name) {
    return 'جارٍ استيراد $name…';
  }

  @override
  String fileOpExportingName(String name) {
    return 'جارٍ تصدير $name…';
  }

  @override
  String fileOpMovingName(String name) {
    return 'جارٍ نقل $name…';
  }

  @override
  String fileOpCopyingName(String name) {
    return 'جارٍ نسخ $name…';
  }

  @override
  String get fileOpDeleting => 'جارٍ الحذف…';

  @override
  String fileOpDeletingName(String name) {
    return 'جارٍ حذف $name…';
  }

  @override
  String fileOpDeletedSoFar(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمت إزالة $count عنصر',
      many: 'تمت إزالة $count عنصرًا',
      few: 'تمت إزالة $count عناصر',
      two: 'تمت إزالة عنصرين',
      one: 'تمت إزالة عنصر واحد',
      zero: 'لم تتم إزالة عناصر',
    );
    return '$_temp0';
  }

  @override
  String get searchInSubfoldersHint => 'البحث في جميع المجلدات الفرعية…';

  @override
  String get deepSearchEnabledTooltip =>
      'جارٍ البحث في المجلدات الفرعية — اضغط للبحث في المجلد الحالي فقط';

  @override
  String get deepSearchDisabledTooltip =>
      'جارٍ البحث في المجلد الحالي — اضغط للبحث في المجلدات الفرعية';

  @override
  String get filterAction => 'تصفية';

  @override
  String get bookmarkAction => 'إضافة إلى المفضلة';

  @override
  String get unbookmarkAction => 'إزالة من المفضلة';

  @override
  String get bookmarkSelectedAction => 'إضافة المحدد إلى المفضلة';

  @override
  String get unbookmarkSelectedAction => 'إزالة المحدد من المفضلة';

  @override
  String bookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمت إضافة $count عنصر إلى المفضلة',
      many: 'تمت إضافة $count عنصرًا إلى المفضلة',
      few: 'تمت إضافة $count عناصر إلى المفضلة',
      two: 'تمت إضافة عنصرين إلى المفضلة',
      one: 'تمت إضافة عنصر واحد إلى المفضلة',
      zero: 'لم تتم إضافة عناصر إلى المفضلة',
    );
    return '$_temp0';
  }

  @override
  String unbookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمت إزالة $count عنصر من المفضلة',
      many: 'تمت إزالة $count عنصرًا من المفضلة',
      few: 'تمت إزالة $count عناصر من المفضلة',
      two: 'تمت إزالة عنصرين من المفضلة',
      one: 'تمت إزالة عنصر واحد من المفضلة',
      zero: 'لم تتم إزالة عناصر من المفضلة',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => 'إظهار شريط المفضلة';

  @override
  String get showBookmarkBarDesc =>
      'عرض العناصر المفضّلة في شريط أو لوحة جانبية للمفضلة';

  @override
  String get bookmarkBarSectionHeader => 'شريط المفضلة';

  @override
  String get noBookmarksYet => 'لا توجد عناصر في المفضلة بعد';

  @override
  String get reorderBookmarksTitle => 'إعادة ترتيب المفضلة';

  @override
  String get reorderBookmarksDesc =>
      'اسحب العناصر لإعادة ترتيبها في شريط المفضلة';

  @override
  String get navBarVaultsLabel => 'الخزنات';

  @override
  String get navBarToolsLabel => 'الأدوات';

  @override
  String get toolsScreenTitle => 'الأدوات';

  @override
  String get toolsSectionContainerUtilities => 'أدوات الحاوية المساعدة';

  @override
  String get toolsSectionFileCryptography => 'تشفير الملفات';

  @override
  String get toolsSectionStorageDiagnostics => 'التخزين والتشخيص';

  @override
  String get toolContainerSplitterTitle => 'التقسيم والدمج';

  @override
  String get toolContainerSplitterSubtitle =>
      'تقسيم حاوية إلى أجزاء، أو دمجها مرة أخرى';

  @override
  String get toolContainerRepairTitle => 'الفحص والإصلاح';

  @override
  String get toolContainerRepairSubtitle =>
      'تشخيص مشكلات الرأس أو نظام الملفات';

  @override
  String get toolSingleFileCryptoTitle => 'تشفير / فك تشفير الملفات';

  @override
  String get toolSingleFileCryptoSubtitle =>
      'حماية ملف واحد أو أكثر دون حاوية كاملة';

  @override
  String get toolStorageAnalyzerTitle => 'محلل التخزين';

  @override
  String get toolStorageAnalyzerSubtitle =>
      'معرفة ما يشغل المساحة في خزنة مثبَّتة';

  @override
  String get toolDuplicateFinderTitle => 'أداة العثور على الملفات المكررة';

  @override
  String get toolDuplicateFinderSubtitle =>
      'العثور على الملفات المكررة المطابقة بايتًا بايت وإزالتها لاستعادة المساحة';

  @override
  String get toolHashVerifierTitle =>
      'أداة التحقق من المجموع الاختباري والتجزئة للملفات';

  @override
  String get toolHashVerifierSubtitle =>
      'تحقق من أن الملفات الكبيرة لم تتلف باستخدام مجاميع MD5/SHA الاختبارية';

  @override
  String get hashVerifierModeCompute => 'حساب';

  @override
  String get hashVerifierModeVerify => 'تحقق';

  @override
  String get hashVerifierSelectSourceTitle => 'اختيار مصدر الملف';

  @override
  String get hashVerifierAlgorithmsLabel => 'الخوارزميات';

  @override
  String get hashVerifierNoAlgorithmSelected => 'اختر خوارزمية واحدة على الأقل';

  @override
  String get hashVerifierFilesLabel => 'الملفات المطلوب تجزئتها';

  @override
  String hashVerifierFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تحديد $count ملف',
      many: 'تم تحديد $count ملفًا',
      few: 'تم تحديد $count ملفات',
      two: 'تم تحديد ملفين',
      one: 'تم تحديد ملف واحد',
      zero: 'لم يتم تحديد ملفات',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierComputeButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'حساب $count تجزئة',
      one: 'حساب التجزئة',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCancelButton => 'إلغاء';

  @override
  String hashVerifierBatchProgressLabel(Object current, Object total) {
    return 'الملف $current من $total';
  }

  @override
  String get hashVerifierCancelledMessage => 'أُلغي.';

  @override
  String hashVerifierComputeErrorsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'فشلت تجزئة $count ملف',
      many: 'فشلت تجزئة $count ملفًا',
      few: 'فشلت تجزئة $count ملفات',
      two: 'فشلت تجزئة ملفين',
      one: 'فشلت تجزئة ملف واحد',
      zero: 'لم يفشل أي ملف',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCopiedMessage => 'تم النسخ إلى الحافظة';

  @override
  String get hashVerifierExportManifestButton => 'التصدير كقائمة بيانات';

  @override
  String get hashVerifierExportAlgorithmLabel => 'خوارزمية قائمة البيانات';

  @override
  String hashVerifierExportSuccessMessage(Object path) {
    return 'تم الحفظ في $path';
  }

  @override
  String hashVerifierExportFailedMessage(Object error) {
    return 'فشل التصدير: $error';
  }

  @override
  String get hashVerifierLoadManifestButton => 'تحميل قائمة البيانات';

  @override
  String get hashVerifierChangeManifestButton => 'تغيير';

  @override
  String get hashVerifierManifestLabel => 'ملف قائمة البيانات';

  @override
  String hashVerifierManifestEntryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count إدخال',
      many: '$count إدخالًا',
      few: '$count إدخالات',
      two: 'إدخالان',
      one: 'إدخال واحد',
      zero: 'لا إدخالات',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierAutoAddFolderButton =>
      'إضافة جميع الملفات من هذا المجلد';

  @override
  String get hashVerifierAddFilesToVerifyButton => 'إضافة ملفات للتحقق منها';

  @override
  String get hashVerifierVerifyAllButton => 'التحقق من الكل';

  @override
  String hashVerifierVerifyProgressLabel(Object current, Object total) {
    return 'جارٍ التحقق من الملف $current من $total';
  }

  @override
  String hashVerifierSummaryMessage(
    Object ok,
    Object mismatch,
    Object missing,
  ) {
    return '$ok مطابقة، $mismatch غير مطابقة، $missing مفقودة';
  }

  @override
  String get hashVerifierStatusMatch => 'متطابق';

  @override
  String get hashVerifierStatusMismatch => 'غير متطابق';

  @override
  String get hashVerifierStatusMissing => 'الملف غير مُضاف';

  @override
  String get hashVerifierStatusPending => 'لم يتم التحقق بعد';

  @override
  String get hashVerifierExpectedLabel => 'المتوقَّع';

  @override
  String get hashVerifierActualLabel => 'الفعلي';

  @override
  String hashVerifierExtraFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف إضافي غير مدرج في قائمة البيانات',
      many: '$count ملفًا إضافيًا غير مدرج في قائمة البيانات',
      few: '$count ملفات إضافية غير مدرجة في قائمة البيانات',
      two: 'ملفان إضافيان غير مدرجين في قائمة البيانات',
      one: 'ملف إضافي واحد غير مدرج في قائمة البيانات',
      zero: 'لا ملفات إضافية غير مدرجة في قائمة البيانات',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierNoManifestLoadedMessage =>
      'حمّل ملف قائمة بيانات للبدء';

  @override
  String get hashVerifierManifestParseEmptyMessage =>
      'لم يتم العثور على إدخالات مجموع اختباري في هذا الملف';

  @override
  String hashVerifierLoadManifestFailedMessage(Object error) {
    return 'تعذّرت قراءة قائمة البيانات: $error';
  }

  @override
  String hashVerifierAutoAddedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تمت إضافة $count ملف من مجلد الخزنة',
      many: 'تمت إضافة $count ملفًا من مجلد الخزنة',
      few: 'تمت إضافة $count ملفات من مجلد الخزنة',
      two: 'تمت إضافة ملفين من مجلد الخزنة',
      one: 'تمت إضافة ملف واحد من مجلد الخزنة',
      zero: 'لم يتم العثور على ملفات جديدة',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierModeVault => 'الخزنة';

  @override
  String get hashVerifierVaultPickerLabel => 'الخزنة';

  @override
  String get hashVerifierVaultNoVaultsMessage => 'لا توجد خزنات مثبَّتة حاليًا';

  @override
  String get hashVerifierCheckEntireVaultButton => 'فحص الخزنة بالكامل';

  @override
  String get hashVerifierVaultScanningLabel => 'جارٍ فحص الخزنة…';

  @override
  String hashVerifierVaultFilesDiscoveredLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم اكتشاف $count ملف',
      many: 'تم اكتشاف $count ملفًا',
      few: 'تم اكتشاف $count ملفات',
      two: 'تم اكتشاف ملفين',
      one: 'تم اكتشاف ملف واحد',
      zero: 'لم يتم اكتشاف ملفات بعد',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmTitle => 'فحص الخزنة بالكامل؟';

  @override
  String hashVerifierVaultConfirmFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ملف',
      many: '$count ملفًا',
      few: '$count ملفات',
      two: 'ملفان',
      one: 'ملف واحد',
      zero: 'لا ملفات',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmWarning =>
      'سيتم قراءة كل ملف في هذه الخزنة.';

  @override
  String get hashVerifierVaultEmptyMessage =>
      'لا توجد ملفات في هذه الخزنة للفحص';

  @override
  String get hashVerifierVaultStartButton => 'بدء الفحص';

  @override
  String hashVerifierVaultHashingProgressLabel(Object current, Object total) {
    return 'جارٍ الفحص $current / $total';
  }

  @override
  String get hashVerifierVaultCompleteTitle => 'اكتمل فحص الخزنة';

  @override
  String hashVerifierVaultCompleteFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم فحص $count ملف',
      many: 'تم فحص $count ملفًا',
      few: 'تم فحص $count ملفات',
      two: 'تم فحص ملفين',
      one: 'تم فحص ملف واحد',
      zero: 'لم يتم فحص ملفات',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteBytesLabel(Object size) {
    return 'تمت معالجة $size';
  }

  @override
  String hashVerifierVaultCompleteSucceededLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count نجاح',
      many: '$count نجاحًا',
      few: '$count نجاحات',
      two: 'نجاحان',
      one: 'نجاح واحد',
      zero: 'لا نجاحات',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count فشل',
      many: '$count حالة فشل',
      few: '$count حالات فشل',
      two: 'فشلان',
      one: 'فشل واحد',
      zero: '0 فشل',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultElapsedLabel(Object time) {
    return 'الوقت المنقضي: $time';
  }

  @override
  String get hashVerifierVaultCancelledMessage => 'تم إلغاء فحص الخزنة.';

  @override
  String hashVerifierVaultFailedMessage(Object error) {
    return 'فشل فحص الخزنة: $error';
  }

  @override
  String get hashVerifierVaultNewCheckButton => 'فحص جديد';

  @override
  String get hashVerifierVaultActionComputeTitle => 'حساب الخزنة بالكامل';

  @override
  String get hashVerifierVaultActionComputeSubtitle => 'تجزئة كل ملف في الخزنة';

  @override
  String get hashVerifierVaultActionVerifyTitle => 'التحقق من الخزنة بالكامل';

  @override
  String get hashVerifierVaultActionVerifySubtitle =>
      'فحص كل ملف في الخزنة مقابل قائمة بيانات محمَّلة';

  @override
  String get hashVerifierVaultChangeActionButton => 'تغيير';

  @override
  String get hashVerifierVaultVerifyButton => 'التحقق من الخزنة بالكامل';

  @override
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage =>
      'يتطلب التحقق من خزنة بأكملها قائمة بيانات مُحمَّلة من داخل خزنة.';

  @override
  String get duplicateFinderTargetLabel => 'الخزنة المستهدفة';

  @override
  String get duplicateFinderTargetAllVaults => 'جميع الخزنات المفتوحة';

  @override
  String get duplicateFinderStartScan => 'بدء الفحص';

  @override
  String get duplicateFinderCancelScan => 'إلغاء الفحص';

  @override
  String get duplicateFinderRescan => 'إعادة الفحص';

  @override
  String get duplicateFinderScanningStage1 =>
      'المرحلة 1: الفهرسة والتجميع حسب الحجم...';

  @override
  String get duplicateFinderScanningStage2 =>
      'المرحلة 2: فحص رؤوس الملفات الجزئية...';

  @override
  String get duplicateFinderScanningStage3 =>
      'المرحلة 3: التحقق من تجزئات البايتات الكاملة...';

  @override
  String get duplicateFinderScanComplete => 'اكتمل الفحص';

  @override
  String get duplicateFinderNoDuplicatesTitle =>
      'لم يتم العثور على ملفات مكررة';

  @override
  String get duplicateFinderNoDuplicatesMessage =>
      'تحتوي جميع الملفات في الخزنة (الخزنات) التي تم فحصها على محتوى بايتات فريد.';

  @override
  String get duplicateFinderSelectRedundant => 'تحديد النسخ الزائدة';

  @override
  String get duplicateFinderSelectAll => 'تحديد الكل';

  @override
  String get duplicateFinderDeselectAll => 'إلغاء تحديد الكل';

  @override
  String get duplicateFinderOriginalLabel => 'الأصل';

  @override
  String get duplicateFinderDuplicateLabel => 'مكرر';

  @override
  String get duplicateFinderConfirmDeleteTitle => 'حذف الملفات المكررة؟';

  @override
  String get duplicateFinderSearchHint =>
      'البحث عن التكرارات حسب اسم الملف أو المسار...';

  @override
  String get toolNotImplementedYetMessage =>
      'لم يتم ربط هذه الأداة بالمحرك الأصلي بعد — تحقق مرة أخرى في تحديث مستقبلي.';

  @override
  String get splitJoinModeSplit => 'تقسيم';

  @override
  String get splitJoinModeJoin => 'دمج';

  @override
  String get splitSourceFileLabel => 'الملف المصدر';

  @override
  String get splitDestinationFolderLabel => 'مجلد الوجهة';

  @override
  String get splitChunkSizeLabel => 'حجم الجزء';

  @override
  String get splitChunkSizeCustomLabel => 'حجم مخصص (ميغابايت)';

  @override
  String get splitChunkSizeFourMb => '4 ميغابايت';

  @override
  String get splitChunkSizeCloud8mb => '8 ميغابايت';

  @override
  String get splitChunkSizeCloud32mb => '32 ميغابايت';

  @override
  String get splitChunkSizeCloud => '100 ميغابايت';

  @override
  String get splitChunkSizeFat32 => '2 غيغابايت';

  @override
  String get splitChunkSizeFourGb => '4 غيغابايت';

  @override
  String get splitChunkSizeCustom => 'مخصص';

  @override
  String get splitContainerButton => 'تقسيم الحاوية';

  @override
  String get joinFirstPartLabel => 'الجزء الأول';

  @override
  String get joinOutputFileNameLabel => 'اسم ملف الإخراج';

  @override
  String get joinContainerButton => 'دمج الملفات';

  @override
  String get chooseFileButton => 'اختيار ملف';

  @override
  String get chooseFolderButton => 'اختيار مجلد';

  @override
  String get noFileSelectedLabel => 'لم يتم اختيار ملف';

  @override
  String get noFolderSelectedLabel => 'لم يتم اختيار مجلد';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage => 'تم تقسيم الحاوية بنجاح';

  @override
  String get joinContainerSuccessMessage => 'تم دمج الملفات بنجاح';

  @override
  String get cryptoDirectionEncrypt => 'تشفير';

  @override
  String get cryptoDirectionDecrypt => 'فك التشفير';

  @override
  String get singleFileCryptoInputFileLabel => 'ملفات الإدخال';

  @override
  String get singleFileCryptoCipherLabel => 'الشيفرة';

  @override
  String get singleFileCryptoDeleteOriginalLabel =>
      'حذف الملفات الأصلية بعد التشفير';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تشفير $count ملف',
      many: 'تشفير $count ملفًا',
      few: 'تشفير $count ملفات',
      two: 'تشفير الملفين',
      one: 'تشفير الملف',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'فك تشفير $count ملف',
      many: 'فك تشفير $count ملفًا',
      few: 'فك تشفير $count ملفات',
      two: 'فك تشفير الملفين',
      one: 'فك تشفير الملف',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم — $count ملف تمت معالجته',
      one: 'تم',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return 'تمت معالجة $succeeded من $total ملفًا — فشل $failed';
  }

  @override
  String get singleFileCryptoAddFilesButton => 'إضافة ملفات';

  @override
  String get singleFileCryptoClearFilesButton => 'مسح';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تحديد $count ملف',
      many: 'تم تحديد $count ملفًا',
      few: 'تم تحديد $count ملفات',
      two: 'تم تحديد ملفين',
      one: 'تم تحديد ملف واحد',
      zero: 'لم يتم تحديد ملفات',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return 'الملف $current من $total';
  }

  @override
  String get repairTargetStepTitle => 'اختيار هدف';

  @override
  String get repairTargetUnmountedFileOption => 'ملف غير مثبَّت';

  @override
  String get repairTargetUnmountedFileSubtitle =>
      'استعادة رأس النسخة الاحتياطية على حاوية لم تفتحها';

  @override
  String get repairTargetMountedVolumeSubtitle =>
      'تشغيل فحص لنظام الملفات على خزنة مفتوحة بالفعل';

  @override
  String get repairNoMountedVolumes => 'لا توجد خزنات مثبَّتة حاليًا';

  @override
  String get repairScanButton => 'تشغيل الفحص التشخيصي';

  @override
  String get repairChangeTargetButton => 'تغيير الهدف';

  @override
  String get repairDiagnosisHealthy => 'لم يتم العثور على مشكلات';

  @override
  String get repairDiagnosisHeaderCorrupted => 'الرأس تالف';

  @override
  String get repairDiagnosisFilesystemDirty =>
      'نظام الملفات غير سليم / إلغاء تحميل غير نظيف';

  @override
  String get repairRestoreBackupHeaderButton => 'استعادة رأس النسخة الاحتياطية';

  @override
  String get repairRunFilesystemCheckButton => 'تشغيل فحص وإصلاح نظام الملفات';

  @override
  String get repairActionSucceededMessage => 'اكتمل الإصلاح بنجاح';

  @override
  String get repairActionFailedMessage => 'لم ينجح إجراء الإصلاح';

  @override
  String get storageAnalyzerTargetLabel => 'الوحدة';

  @override
  String get storageAnalyzerNoTargetsTitle => 'لا يوجد ما يمكن تحليله';

  @override
  String get storageAnalyzerNoTargetsMessage =>
      'قم بتحميل خزنة أولاً، ثم عد إلى هنا لعرض توزيع مساحة التخزين الخاصة بها.';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return '$used من $total مستخدَمة';
  }

  @override
  String get storageAnalyzerHeaviestFilesHeader => 'أكبر الملفات';

  @override
  String get storageAnalyzerBreakdownHeader => 'حسب نوع الملف';

  @override
  String get storageAnalyzerScanningMessage => 'جارٍ فحص الوحدة…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return 'توقف الفحص مبكرًا بعد $count ملف — قد تكون النتائج غير مكتملة.';
  }

  @override
  String get storageAnalyzerNoFilesFound => 'لم يتم العثور على ملفات';

  @override
  String get storageCategoryImages => 'الصور';

  @override
  String get storageCategoryVideos => 'الفيديوهات';

  @override
  String get storageCategoryAudio => 'الصوت';

  @override
  String get storageCategoryDocuments => 'المستندات';

  @override
  String get storageCategoryArchives => 'الأرشيفات';

  @override
  String get storageCategoryOther => 'أخرى';

  @override
  String get keyfilePassphraseGeneratorTitle =>
      'مولّد ملفات المفاتيح وعبارات المرور';

  @override
  String get keyfilePassphraseGeneratorSubtitle =>
      'توليد عبارات مرور Diceware وكلمات مرور مخصصة وملفات مفاتيح عالية العشوائية';

  @override
  String get tabPassphrase => 'عبارة المرور';

  @override
  String get tabKeyfile => 'ملف المفتاح';

  @override
  String get modeDiceware => 'عبارة مرور Diceware';

  @override
  String get modeCustomPassword => 'كلمة مرور مخصصة';

  @override
  String get keyfileTypeBinary => 'ملف مفتاح ثنائي (.key)';

  @override
  String get keyfileTypeImage => 'ملف مفتاح صورة ضوضاء (.png)';

  @override
  String get copyPassphraseSuccess => 'تم نسخ عبارة المرور إلى الحافظة الحساسة';

  @override
  String get copyFingerprintSuccess => 'تم نسخ بصمة SHA-256 إلى الحافظة';

  @override
  String get saveKeyfileToVault => 'الحفظ في خزنة مثبَّتة';

  @override
  String get exportKeyfileToStorage => 'التصدير إلى تخزين الجهاز';

  @override
  String get keyfileNoOpenVaultsMessage =>
      'لا توجد خزنات مفتوحة متاحة. يرجى تحميل خزنة أولاً.';

  @override
  String get keyfileSelectDestinationVaultTitle => 'اختيار خزنة الوجهة';

  @override
  String keyfileVolumeIdLabel(Object volId) {
    return 'معرّف الوحدة: $volId';
  }

  @override
  String keyfileExportSuccessMessage(Object path) {
    return 'تم تصدير ملف المفتاح إلى $path';
  }

  @override
  String keyfileExportFailedMessage(Object error) {
    return 'فشل التصدير: $error';
  }

  @override
  String keyfileSavedToVaultMessage(Object vaultName, Object path) {
    return 'تم حفظ ملف المفتاح في $vaultName: $path';
  }

  @override
  String get keyfileWriteFailedMessage => 'فشلت كتابة ملف المفتاح إلى الخزنة';

  @override
  String keyfileSaveErrorMessage(Object error) {
    return 'خطأ أثناء الحفظ في الخزنة: $error';
  }

  @override
  String get passphraseGeneratedSecretLabel => 'السر المُولَّد';

  @override
  String get copyToClipboardTooltip => 'نسخ إلى الحافظة';

  @override
  String get generateNewTooltip => 'توليد جديد';

  @override
  String get passphraseStrengthWeak => 'ضعيفة';

  @override
  String get passphraseStrengthGood => 'جيدة';

  @override
  String get passphraseStrengthStrong => 'قوية';

  @override
  String get passphraseStrengthUnbreakable => 'غير قابلة للكسر';

  @override
  String get passphraseCrackTimeInstant => 'أقل من ثانية واحدة';

  @override
  String get passphraseCrackTimeShort => 'بضعة أيام / أشهر';

  @override
  String get passphraseCrackTimeCenturies => 'عدة قرون';

  @override
  String get passphraseCrackTimeMillionsOfYears => 'ملايين السنين';

  @override
  String passphraseStrengthLabel(Object label) {
    return 'القوة: $label';
  }

  @override
  String passphraseEntropyBitsLabel(Object bits) {
    return 'إنتروبيا $bits بت';
  }

  @override
  String passphraseCrackTimeLabel(Object crackTime) {
    return 'الوقت المقدَّر للكسر: $crackTime';
  }

  @override
  String get dicewareOptionsTitle => 'خيارات EFF Diceware';

  @override
  String dicewareWordCountLabel(Object count) {
    return 'عدد الكلمات: $count كلمة';
  }

  @override
  String dicewareWordCountBitsLabel(Object bits) {
    return '$bits بت';
  }

  @override
  String dicewareWordCountSliderLabel(Object count) {
    return '$count كلمة';
  }

  @override
  String get dicewareWordSeparatorLabel => 'فاصل الكلمات';

  @override
  String get dicewareSeparatorHyphen => 'شرطة ( - )';

  @override
  String get dicewareSeparatorSpace => 'مسافة (   )';

  @override
  String get dicewareSeparatorUnderscore => 'شرطة سفلية ( _ )';

  @override
  String get dicewareSeparatorDot => 'نقطة ( . )';

  @override
  String get dicewareSeparatorSlash => 'شرطة مائلة ( / )';

  @override
  String get dicewareWordCasingLabel => 'حالة أحرف الكلمات';

  @override
  String get dicewareCasingLowercase => 'أحرف صغيرة';

  @override
  String get dicewareCasingTitleCase => 'حالة العنوان';

  @override
  String get dicewareCasingUppercase => 'أحرف كبيرة';

  @override
  String get dicewareAppendDigitLabel => 'إضافة رقم عشوائي (0-9)';

  @override
  String get dicewareAppendSymbolLabel => 'إضافة رمز عشوائي (!@#\$%)';

  @override
  String get customPasswordOptionsTitle => 'خيارات كلمة المرور المخصصة';

  @override
  String customPasswordLengthLabel(Object length) {
    return 'الطول: $length حرفًا';
  }

  @override
  String customPasswordLengthSliderLabel(Object length) {
    return '$length حرفًا';
  }

  @override
  String get customPasswordUppercaseLabel => 'أحرف كبيرة (A-Z)';

  @override
  String get customPasswordLowercaseLabel => 'أحرف صغيرة (a-z)';

  @override
  String get customPasswordNumbersLabel => 'أرقام (0-9)';

  @override
  String get customPasswordSymbolsLabel => 'رموز (!@#\$%^&*)';

  @override
  String get customPasswordExcludeAmbiguousLabel =>
      'استبعاد الأحرف الملتبسة (1، l، I، 0، O)';

  @override
  String get keyfileBinarySizeTitle => 'حجم ملف المفتاح الثنائي';

  @override
  String get keyfileImageResolutionTitle => 'دقة صورة الضوضاء';

  @override
  String get keyfilePresetBytes64 => '64 بايت (معيار VeraCrypt)';

  @override
  String get keyfilePresetBytes256 => '256 بايت';

  @override
  String get keyfilePresetBytes2048 => '2 كيلوبايت';

  @override
  String get keyfilePresetBytes64kb => '64 كيلوبايت';

  @override
  String get keyfilePresetBytes1mb => '1 ميغابايت (الحد الأقصى)';

  @override
  String get keyfilePresetRes64 => '64×64 بكسل (~16 كيلوبايت)';

  @override
  String get keyfilePresetRes256 => '256×256 بكسل (~256 كيلوبايت)';

  @override
  String get keyfilePresetRes512 => '512×512 بكسل (~1 ميغابايت)';

  @override
  String get keyfileGenerateNewTooltip => 'توليد ملف مفتاح جديد';

  @override
  String keyfileSizeLabel(Object size) {
    return 'الحجم: $size';
  }

  @override
  String get keyfileFingerprintLabel => 'بصمة SHA-256';

  @override
  String get keyfileCopyFingerprintTooltip => 'نسخ البصمة';

  @override
  String get duplicateFinderNoVaultsTitle => 'لا توجد خزنات مثبَّتة';

  @override
  String get duplicateFinderNoVaultsMessage =>
      'افتح قفل حاوية خزنة واحدة على الأقل وقم بتحميلها للبحث عن الملفات المكررة.';

  @override
  String duplicateFinderConfirmDeleteMessage(Object count, Object size) {
    return 'هل أنت متأكد من رغبتك في حذف $count ملف مكرر ($size) نهائيًا من خزنتك (خزناتك)؟ لا يمكن التراجع عن هذا الإجراء.';
  }

  @override
  String get duplicateFinderDeletePermanentlyButton => 'حذف نهائي';

  @override
  String duplicateFinderDeleteSuccessMessage(Object count) {
    return 'تم حذف $count ملف مكرر بنجاح.';
  }

  @override
  String get duplicateFinderIntroTitle =>
      'أداة عثور من 3 مراحل بمطابقة البايتات';

  @override
  String get duplicateFinderIntroSubtitle =>
      'اكتشاف المحتوى المطابق تمامًا بصرف النظر عن أسماء الملفات.';

  @override
  String get duplicateFinderStagesDescription =>
      '• المرحلة 1: التجميع حسب الحجم (فحص فوري للبيانات الوصفية)\n• المرحلة 2: فحص الرأس الجزئي (رأس SHA-256 بحجم 16 كيلوبايت)\n• المرحلة 3: التحقق الكامل من التجزئة (مطابقة دقيقة للبايتات عبر SHA-256)';

  @override
  String get duplicateFinderScanningVaultFallback => 'جارٍ فحص الخزنة...';

  @override
  String duplicateFinderProcessingFileLabel(Object fileName) {
    return 'جارٍ المعالجة: $fileName';
  }

  @override
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  ) {
    return 'الملفات التي تم فحصها: $scanned | التكرارات الموجودة: $groups مجموعات ($saved)';
  }

  @override
  String duplicateFinderGroupsFoundLabel(Object count) {
    return 'تم العثور على $count مجموعة مكررة';
  }

  @override
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved) {
    return 'تم العثور على $copies نسخة • وفّر $saved من مساحة التخزين';
  }

  @override
  String duplicateFinderVaultsSelectedLabel(Object count) {
    return 'تم تحديد $count خزنة';
  }

  @override
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  ) {
    return 'المجموعة $groupIndex: $size (تم العثور على $count نسخة)';
  }

  @override
  String duplicateFinderRecoverableSpaceLabel(Object size) {
    return 'المساحة القابلة للاسترداد: $size';
  }

  @override
  String get duplicateFinderPreviewFileTooltip => 'معاينة الملف';

  @override
  String duplicateFinderPreviewFailedMessage(Object fileName) {
    return 'تعذّر فتح معاينة الملف لـ $fileName';
  }

  @override
  String duplicateFinderPreviewErrorMessage(Object error) {
    return 'خطأ في معاينة الملف: $error';
  }

  @override
  String duplicateFinderFilesSelectedLabel(Object count) {
    return 'تم تحديد $count ملف';
  }

  @override
  String duplicateFinderBytesToBeFreedLabel(Object size) {
    return 'سيتم تحرير $size';
  }

  @override
  String duplicateFinderDeleteSelectedButton(Object count) {
    return 'حذف المحدد ($count)';
  }

  @override
  String get vaultBrowserSwitchVaultTooltip => 'تبديل الخزنة';

  @override
  String get vaultBrowserRootFolderLabel => 'المجلد الجذر';

  @override
  String vaultFilePickerTitle(Object vaultName) {
    return 'اختيار ملفات ($vaultName)';
  }

  @override
  String get vaultFilePickerEmptyMessage => 'المجلد فارغ';

  @override
  String vaultFilePickerConfirmButton(Object count) {
    return 'اختيار $count ملف';
  }

  @override
  String vaultFolderPickerTitle(Object vaultName) {
    return 'اختيار مجلد ($vaultName)';
  }

  @override
  String get vaultFolderPickerEmptyMessage => 'لا توجد مجلدات فرعية هنا';

  @override
  String get vaultFolderPickerRootLabel => 'الجذر';

  @override
  String get vaultFolderPickerConfirmRootButton => 'اختيار المجلد الجذر';

  @override
  String vaultFolderPickerConfirmNamedButton(Object folderName) {
    return 'اختيار \"$folderName\"';
  }

  @override
  String get singleFileCryptoSelectInputTitle => 'اختيار ملفات الإدخال';

  @override
  String get singleFileCryptoFromDeviceTitle => 'من تخزين الجهاز';

  @override
  String get singleFileCryptoFromDeviceSubtitle =>
      'اختيار ملفات من الجهاز باستخدام منتقي ملفات النظام';

  @override
  String get singleFileCryptoFromVaultTitle => 'من خزنة مثبَّتة';

  @override
  String get singleFileCryptoFromVaultSubtitle =>
      'اختيار ملفات من حاوية مشفّرة مفتوحة';

  @override
  String get singleFileCryptoSelectDestinationTitle => 'اختيار مجلد الوجهة';

  @override
  String get singleFileCryptoDeviceFolderTitle => 'مجلد تخزين الجهاز';

  @override
  String get singleFileCryptoDeviceFolderSubtitle =>
      'حفظ الإخراج في مجلد على تخزين الجهاز';

  @override
  String get singleFileCryptoVaultFolderTitle => 'مجلد خزنة مثبَّتة';

  @override
  String get singleFileCryptoVaultFolderSubtitle =>
      'حفظ الإخراج داخل حاوية مشفّرة مفتوحة';

  @override
  String get toolsSectionBackupSync => 'النسخ الاحتياطي والمزامنة';

  @override
  String get toolVaultSyncTitle => 'مزامنة الخزنات';

  @override
  String get toolVaultSyncSubtitle => 'مقارنة خزنتين ونسخ ما هو مفقود أو أحدث';

  @override
  String get vaultSyncNoVaultsTitle => 'لا توجد خزنات مثبَّتة';

  @override
  String get vaultSyncNoVaultsMessage =>
      'قم بتحميل خزنة واحدة على الأقل لمقارنة ملفاتها ومزامنتها.';

  @override
  String get vaultSyncLeftLabel => 'اليسار';

  @override
  String get vaultSyncRightLabel => 'اليمين';

  @override
  String get vaultSyncTapToSelect => 'اضغط لاختيار خزنة ومجلد';

  @override
  String get vaultSyncSwapTooltip => 'تبديل اليسار واليمين';

  @override
  String get vaultSyncSameLocationWarning =>
      'يجب أن يكون اليسار واليمين مجلدين مختلفين.';

  @override
  String get vaultSyncIntroTitle => 'مقارنة خزنتين';

  @override
  String get vaultSyncIntroSubtitle =>
      'اختر خزنة يسرى وأخرى يمنى (أو مجلدين في نفس الخزنة) لمعرفة ما هو مفقود أو مُعدَّل أو أحدث في كل جانب.';

  @override
  String get vaultSyncCompareButton => 'مقارنة';

  @override
  String get vaultSyncComparingLabel => 'جارٍ مقارنة الخزنات…';

  @override
  String vaultSyncCompareStatsLabel(Object dirs, Object entries) {
    return 'المجلدات التي تم فحصها: $dirs | الفروقات الموجودة: $entries';
  }

  @override
  String get vaultSyncCancelCompareButton => 'إلغاء';

  @override
  String get vaultSyncInSyncTitle => 'متزامنة بالفعل';

  @override
  String vaultSyncInSyncMessage(Object count) {
    return 'جميع الملفات المتطابقة البالغ عددها $count متطابقة في كلا الجانبين.';
  }

  @override
  String get vaultSyncRecompareButton => 'مقارنة مرة أخرى';

  @override
  String vaultSyncDifferencesFoundLabel(Object count) {
    return 'تم العثور على $count فرق';
  }

  @override
  String vaultSyncInSyncCountLabel(Object count) {
    return '$count ملف متطابق بالفعل في كلا الجانبين';
  }

  @override
  String vaultSyncBadgeOnlyLeft(Object count) {
    return '$count في اليسار فقط';
  }

  @override
  String vaultSyncBadgeOnlyRight(Object count) {
    return '$count في اليمين فقط';
  }

  @override
  String vaultSyncBadgeLeftNewer(Object count) {
    return '$count أحدث في اليسار';
  }

  @override
  String vaultSyncBadgeRightNewer(Object count) {
    return '$count أحدث في اليمين';
  }

  @override
  String vaultSyncBadgeConflicts(Object count) {
    return '$count بحاجة إلى مراجعة';
  }

  @override
  String get vaultSyncDirectionLabel => 'اتجاه المزامنة';

  @override
  String get vaultSyncDirectionTwoWay => 'ثنائي الاتجاه (موصى به)';

  @override
  String get vaultSyncDirectionTwoWaySubtitle =>
      'ينسخ كل ملف إلى الجانب الذي يفتقده أو لديه نسخة أقدم';

  @override
  String get vaultSyncDirectionLeftToRight => 'اليسار ← اليمين (اتجاه واحد)';

  @override
  String get vaultSyncDirectionLeftToRightSubtitle =>
      'يدفع الملفات الجديدة والمحدَّثة من اليسار إلى اليمين؛ لا يغيّر اليسار أبدًا';

  @override
  String get vaultSyncDirectionRightToLeft => 'اليمين ← اليسار (اتجاه واحد)';

  @override
  String get vaultSyncDirectionRightToLeftSubtitle =>
      'يدفع الملفات الجديدة والمحدَّثة من اليمين إلى اليسار؛ لا يغيّر اليمين أبدًا';

  @override
  String get vaultSyncSearchHint => 'البحث في الفروقات';

  @override
  String get vaultSyncStatusOnlyLeft => 'اليسار فقط';

  @override
  String get vaultSyncStatusOnlyRight => 'اليمين فقط';

  @override
  String get vaultSyncStatusLeftNewer => 'اليسار أحدث';

  @override
  String get vaultSyncStatusRightNewer => 'اليمين أحدث';

  @override
  String get vaultSyncStatusConflict => 'بحاجة إلى مراجعة';

  @override
  String get vaultSyncStatusTypeMismatch => 'عدم تطابق النوع';

  @override
  String get vaultSyncFolderOnlyLeftDetail => 'مجلد — اليسار فقط';

  @override
  String get vaultSyncFolderOnlyRightDetail => 'مجلد — اليمين فقط';

  @override
  String vaultSyncBothSidesDetail(
    Object leftSize,
    Object leftDate,
    Object rightSize,
    Object rightDate,
  ) {
    return 'يسار: $leftSize · $leftDate  ←  يمين: $rightSize · $rightDate';
  }

  @override
  String get vaultSyncTypeMismatchTooltip =>
      'ملف في جانب ومجلد في الآخر — يُحل يدويًا في متصفح الملفات';

  @override
  String get vaultSyncChangeActionTooltip => 'تغيير إجراء المزامنة';

  @override
  String get vaultSyncActionCopyToRight => 'نسخ ← اليمين';

  @override
  String get vaultSyncActionCopyToLeft => 'نسخ ← اليسار';

  @override
  String get vaultSyncActionSkip => 'تخطي';

  @override
  String vaultSyncChangesQueuedLabel(Object count) {
    return '$count تغيير في قائمة الانتظار';
  }

  @override
  String get vaultSyncSyncNowButton => 'مزامنة الآن';

  @override
  String get vaultSyncConfirmTitle => 'بدء المزامنة؟';

  @override
  String vaultSyncConfirmMessage(Object count, Object bytes) {
    return 'سيؤدي هذا إلى نسخ $count عنصر ($bytes إجمالاً) بين الجانبين. سيتم استبدال الملفات الموجودة التي تحمل نفس الاسم.';
  }

  @override
  String vaultSyncStartedMessage(Object count) {
    return 'بدأت المزامنة — $count عنصر في قائمة الانتظار';
  }

  @override
  String vaultSyncPickLocationTitle(Object side) {
    return 'اختيار خزنة ومجلد ($side)';
  }

  @override
  String get vaultSyncReadOnlyBadge => 'للقراءة فقط';

  @override
  String get vaultSyncReadOnlyTooltip =>
      'هذه الخزنة مثبَّتة للقراءة فقط — لا يمكن نسخ ملفات إليها';

  @override
  String get vaultSyncSyncingButton => 'جارٍ المزامنة…';

  @override
  String get vaultSyncNotEnoughSpaceTitle => 'لا توجد مساحة كافية';

  @override
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  ) {
    return 'لا توجد مساحة كافية في $side — مطلوب $required، والمتاح فقط $free.';
  }

  @override
  String get removeMasterPasswordTitle => 'إزالة كلمة المرور الرئيسية';

  @override
  String get confirmRemoveMasterPasswordMessage =>
      'أدخل كلمة المرور الرئيسية الحالية لتأكيد الإزالة:';

  @override
  String get authenticateToRemoveMasterPassword =>
      'أجرِ المصادقة لإزالة كلمة المرور الرئيسية';

  @override
  String get incorrectPassword => 'كلمة مرور غير صحيحة';

  @override
  String get rememberPerFolderLayoutLabel => 'تذكّر التخطيط لكل مجلد';

  @override
  String get rememberPerFolderLayoutDesc =>
      'حفظ تخطيط عرض منفصل (قائمة، شبكة، متدرّج) لكل مجلد';

  @override
  String get fileInfoAction => 'معلومات';

  @override
  String get automationSectionHeader => 'الأتمتة';

  @override
  String get automationTileTitle => 'الأتمتة';

  @override
  String get automationTileSubtitle =>
      'السماح للأتمتة بفتح قفل هذه الخزنة أو قفلها أو استيراد ملفات منها أو تصديرها إليها';

  @override
  String get automationScreenTitle => 'الأتمتة (Tasker / MacroDroid)';

  @override
  String get automationUsbUnsupportedMessage =>
      'الأتمتة غير متاحة بعد للخزنات المتصلة عبر USB.';

  @override
  String get automationThisVaultSectionHeader => 'هذه الخزنة';

  @override
  String get automationAccessLabel => 'الوصول إلى الأتمتة';

  @override
  String get automationPasswordSectionHeader => 'كلمة مرور الأتمتة';

  @override
  String get automationPasswordStoredHint =>
      'توجد كلمة مرور محفوظة لطلبات UNLOCK_VAULT غير المراقَبة. احفظ كلمة جديدة لاستبدالها، أو احفظ حقلاً فارغًا لمسحها — يمكن للأتمتة أيضًا توفير كلمة مرور مباشرةً ضمن البث بدلاً من الاعتماد على هذه.';

  @override
  String get automationPasswordNotStoredHint =>
      'اختياري. بدون كلمة مرور محفوظة، يجب على الأتمتة توفير واحدة مع كل بث UNLOCK_VAULT.';

  @override
  String get automationNewPasswordFieldLabel => 'كلمة مرور جديدة';

  @override
  String get automationPasswordFieldLabel => 'كلمة المرور';

  @override
  String get automationClearPasswordButton => 'مسح كلمة المرور المحفوظة';

  @override
  String get automationSavePasswordButton => 'حفظ كلمة المرور';

  @override
  String get automationTokenSectionHeader => 'رمز API';

  @override
  String get automationTokenDescription =>
      'مشترك بين جميع الخزنات التي تم تفعيل وصول الأتمتة لها. ترسل الأتمتة هذا الرمز مرة أخرى مع كل بث؛ يتم تجاهل الرمز الخاطئ أو المفقود بصمت دون ظهور خطأ.';

  @override
  String get automationRegenerateTokenButton => 'إعادة توليد الرمز';

  @override
  String get automationRegenerateTokenDialogTitle => 'إعادة توليد الرمز؟';

  @override
  String get automationRegenerateTokenDialogMessage =>
      'سيتوقف أي ملف تعريف Tasker أو ماكرو MacroDroid يستخدم الرمز الحالي عن العمل بصمت إلى أن تُحدّثه بالرمز الجديد.';

  @override
  String get automationRegenerateConfirmLabel => 'إعادة التوليد';

  @override
  String get automationTokenRegeneratedMessage => 'تمت إعادة توليد الرمز.';

  @override
  String get automationRegenerateTokenFailedMessage =>
      'تعذّرت إعادة توليد الرمز.';

  @override
  String get automationUpdateSettingsFailedMessage =>
      'تعذّر تحديث إعدادات الأتمتة.';

  @override
  String get automationSavePasswordFailedMessage =>
      'تعذّر حفظ كلمة مرور الأتمتة.';

  @override
  String get automationPasswordClearedMessage => 'تم مسح كلمة مرور الأتمتة.';

  @override
  String get automationPasswordSavedMessage => 'تم حفظ كلمة مرور الأتمتة.';

  @override
  String get automationConfigSectionHeader => 'سلاسل التكوين';

  @override
  String get automationConfigIntro =>
      'اضغط على أي قيمة أدناه لنسخها. في Tasker، استخدم إجراء \"Send Intent\"؛ وفي MacroDroid، استخدم إجراء \"Intent\" مع ضبط Intent Type على Broadcast — وليس Activity أو Service، اللذين يفشلان بخطأ \"unable to find explicit activity class\".';

  @override
  String get automationConfigPackageLabel => 'اسم الحزمة';

  @override
  String get automationConfigClassLabel => 'فئة المستقبِل';

  @override
  String get automationConfigVaultUriLabel => 'عنوان URI لهذه الخزنة';

  @override
  String get automationConfigActionsSectionHeader => 'إجراءات البث';

  @override
  String get automationActionUnlockLabel => 'فتح قفل الخزنة';

  @override
  String get automationActionLockLabel => 'قفل الخزنة';

  @override
  String get automationActionImportLabel => 'استيراد ملف';

  @override
  String get automationActionExportLabel => 'تصدير ملف';

  @override
  String get automationActionWipeLabel => 'مسح ملف';

  @override
  String get automationDocCommentFootnote =>
      'جميع العناصر الإضافية وعقد بث النتائج موثّقة في VaultAutomationReceiver.kt.';

  @override
  String get automationTierOffLabel => 'إيقاف';

  @override
  String get automationTierOffSubtitle =>
      'لا يمكن للأتمتة الوصول إلى هذه الخزنة';

  @override
  String get automationTierLifecycleLabel => 'فتح القفل / القفل فقط';

  @override
  String get automationTierLifecycleSubtitle =>
      'يمكن للأتمتة فتح قفل هذه الخزنة وقفلها فقط، ولا شيء غير ذلك';

  @override
  String get automationTierFullLabel =>
      'فتح القفل / القفل + استيراد وتصدير الملفات';

  @override
  String get automationTierFullSubtitle =>
      'يمكن للأتمتة أيضًا استيراد الملفات وتصديرها أثناء فتح قفل هذه الخزنة';

  @override
  String get automationTutorialLinkLabel =>
      'قراءة الدليل التفصيلي الكامل خطوة بخطوة';

  @override
  String get showHiddenFilesLabel => 'إظهار الملفات المخفية';

  @override
  String get showHiddenFilesDesc => 'عرض الملفات ذات النقطة ومجلدات النظام';

  @override
  String get dontAskAgain => 'عدم السؤال مرة أخرى';

  @override
  String get deleteAfterImportLabel => 'حذف الملفات بعد الاستيراد';

  @override
  String get deleteAfterImportModeAsk => 'السؤال في كل مرة';

  @override
  String get deleteAfterImportModeAskSubtitle =>
      'السؤال عمّا إذا كان يجب حذف الملفات الأصلية بعد الاستيراد';

  @override
  String get deleteAfterImportModeKeep =>
      'الاحتفاظ بالملفات الأصلية (عدم الحذف)';

  @override
  String get deleteAfterImportModeKeepSubtitle =>
      'عدم حذف الملفات الأصلية أبدًا وعدم السؤال';

  @override
  String get deleteAfterImportModeDelete => 'حذف الملفات الأصلية تلقائيًا';

  @override
  String get deleteAfterImportModeDeleteSubtitle =>
      'حذف الملفات الأصلية من الجهاز تلقائيًا بعد الاستيراد';

  @override
  String get wizardBackButton => 'رجوع';

  @override
  String get wizardNextButton => 'التالي';

  @override
  String get wizardStepTypeTitle => 'النوع';

  @override
  String get wizardStepBasicInfoTitle => 'معلومات أساسية';

  @override
  String get wizardStepAdvancedTitle => 'متقدم';

  @override
  String get wizardStepReviewTitle => 'مراجعة';

  @override
  String get wizardCreateTypePrompt => 'ماذا تريد أن تنشئ؟';

  @override
  String get wizardChooseFormatPrompt => 'اختر تنسيق حاوية';

  @override
  String get wizardEncryptionDetailsRowTitle => 'تفاصيل التشفير';

  @override
  String get wizardHiddenVolumeRowSubtitleConfigured =>
      'تم الإعداد — اضغط للمراجعة';

  @override
  String get wizardHiddenVolumeRowSubtitleNeedsSetup => 'اضغط للإعداد';

  @override
  String get wizardSummaryTitle => 'الملخص';

  @override
  String get wizardSummaryPasswordLabel => 'كلمة المرور';

  @override
  String get wizardPasswordSetValue => 'تم التعيين';

  @override
  String get wizardPasswordNotSetValue =>
      'غير معيّنة (باستخدام ملفات المفاتيح)';

  @override
  String get wizardSummaryKeyfilesLabel => 'ملفات المفاتيح';

  @override
  String get wizardSummaryPimDefaultValue => 'افتراضي';

  @override
  String get wizardSummaryPimLabel => 'PIM';

  @override
  String get wizardSummaryDriveLabel => 'محرك USB';

  @override
  String get sectionKeyStorageIntegration =>
      'تخزين المفاتيح والوصول إلى النظام';

  @override
  String get sectionMaskMode => 'وضع التمويه';

  @override
  String get advancedOptionsTitle => 'خيارات متقدمة';

  @override
  String get audioTrackTitle => 'مسار الصوت';

  @override
  String get noAudioTracksAvailable => 'لا توجد مسارات صوتية متاحة';

  @override
  String trackNumberLabel(int number) {
    return 'المسار $number';
  }

  @override
  String subtitleTrackNumberLabel(int number) {
    return 'الترجمة $number';
  }

  @override
  String get offLabel => 'إيقاف';

  @override
  String get externalSubtitlesLabel => 'ترجمات خارجية (.srt/.vtt)';

  @override
  String get externalLabel => 'خارجي';

  @override
  String get subtitleSizeLabel => 'الحجم';

  @override
  String get subtitleSizeSmall => 'ص';

  @override
  String get subtitleSizeMedium => 'م';

  @override
  String get subtitleSizeLarge => 'ك';

  @override
  String get subtitleSizeExtraLarge => 'ك.ج';

  @override
  String get subtitlePositionLabel => 'الموضع';

  @override
  String get subtitlePositionBottom => 'أسفل';

  @override
  String get subtitlePositionLower => 'أسفل قليلاً';

  @override
  String get subtitlePositionCenter => 'وسط';

  @override
  String get subtitlePositionTop => 'أعلى';

  @override
  String get editImageAction => 'تحرير الصورة';

  @override
  String get imageEditorUnsupportedFormatMessage =>
      'تنسيق هذه الصورة غير مدعوم للتحرير.';

  @override
  String get cropToolLabel => 'قص';

  @override
  String get drawToolLabel => 'رسم';

  @override
  String get textToolLabel => 'نص';

  @override
  String get redactToolLabel => 'تعتيم';

  @override
  String get rotateLeftTooltip => 'تدوير لليسار';

  @override
  String get rotateRightTooltip => 'تدوير لليمين';

  @override
  String get cropAspectFreeLabel => 'حر';

  @override
  String get cropAspectSquareLabel => 'مربع';

  @override
  String get cropAspectOriginalLabel => 'الأصلي';

  @override
  String get applyCropTooltip => 'تطبيق القص';

  @override
  String get annotationColorTooltip => 'اللون';

  @override
  String get annotationStrokeWidthTooltip => 'سُمك الخط';

  @override
  String get clearAnnotationsTooltip => 'مسح كل التعليقات التوضيحية';

  @override
  String get resetImageTooltip => 'إعادة التعيين إلى الأصل';

  @override
  String get resetImageConfirmTitle => 'إعادة تعيين الصورة؟';

  @override
  String get resetImageConfirmMessage =>
      'سيؤدي هذا إلى إلغاء كل عمليات القص والرسم التي تمت في هذه الجلسة.';

  @override
  String get addTextAnnotationTitle => 'إضافة نص';

  @override
  String get addTextAnnotationHint => 'اكتب شيئًا…';

  @override
  String get textToolHint => 'اضغط على الصورة لإضافة نص';

  @override
  String get saveImageSheetTitle => 'حفظ التغييرات';

  @override
  String get saveAsNewFileOption => 'حفظ كملف جديد';

  @override
  String get saveAsNewFileDescription => 'يحافظ على الملف الأصلي دون تغيير';

  @override
  String get overwriteOriginalOption => 'استبدال الأصل';

  @override
  String get overwriteOriginalDescription => 'يستبدل الملف الأصلي';

  @override
  String get newFileNameLabel => 'اسم الملف';

  @override
  String get imageEditorPngNoteMessage => 'تُحفظ الصور المعدَّلة بتنسيق PNG.';

  @override
  String get imageSavedMessage => 'تم حفظ الصورة';

  @override
  String imageSaveFailedMessage(String error) {
    return 'تعذّر حفظ الصورة: $error';
  }

  @override
  String get advancedRenameButton => 'متقدم';

  @override
  String get advancedRenameBatchTitle => 'إعادة تسمية دفعية';

  @override
  String get advancedRenameRulesTab => 'القواعد';

  @override
  String advancedRenamePreviewTab(int count) {
    return 'معاينة ($count)';
  }

  @override
  String get advancedRenameSearchReplaceTitle => 'بحث واستبدال';

  @override
  String get advancedRenameFindTextLabel => 'البحث عن نص';

  @override
  String get advancedRenameFindTextHint => 'أدخل نصًا أو نمطًا للمطابقة...';

  @override
  String get advancedRenameReplaceWithLabel => 'استبدال بـ';

  @override
  String get advancedRenameReplaceWithHint => 'نص جديد أو متغيرات...';

  @override
  String get advancedRenameInsertVariableTooltip => 'إدراج رمز متغيّر ديناميكي';

  @override
  String get advancedRenameDateTimeTokens => 'رموز التاريخ والوقت';

  @override
  String advancedRenameStandardDate(String token) {
    return 'التاريخ القياسي ($token)';
  }

  @override
  String advancedRenameYearFourDigit(String token) {
    return 'سنة من 4 أرقام ($token)';
  }

  @override
  String advancedRenameMonth(String token) {
    return 'الشهر ($token)';
  }

  @override
  String advancedRenameDayOfMonth(String token) {
    return 'يوم الشهر ($token)';
  }

  @override
  String advancedRenameTime(String token) {
    return 'الوقت ($token)';
  }

  @override
  String get advancedRenameDynamicIdentifiers => 'معرّفات ديناميكية';

  @override
  String advancedRenameUniqueUuid(String token) {
    return 'معرّف UUID v4 فريد ($token)';
  }

  @override
  String get advancedRenameRandomAlphanumeric => 'أحرف وأرقام عشوائية (8 أحرف)';

  @override
  String get advancedRenameRandomDigits => 'أرقام عشوائية (6 أرقام)';

  @override
  String get advancedRenameEmbeddedCounter => 'عدّاد مضمّن';

  @override
  String advancedRenamePaddedCounter(String token) {
    return 'عدّاد بأصفار بادئة ($token)';
  }

  @override
  String get advancedRenameRegex => 'تعبير نمطي';

  @override
  String get advancedRenameMatchCase => 'مطابقة حالة الأحرف';

  @override
  String get advancedRenameAllOccurrences => 'كل التكرارات';

  @override
  String get advancedRenameScopeFormatting => 'النطاق والتنسيق';

  @override
  String get advancedRenameApplyChangesTo => 'تطبيق التغييرات على';

  @override
  String get advancedRenameFilename => 'اسم الملف';

  @override
  String get advancedRenameExtension => 'الامتداد';

  @override
  String get advancedRenameBoth => 'كلاهما';

  @override
  String get advancedRenameCaseTransformation => 'تحويل حالة الأحرف';

  @override
  String get advancedRenameNoChange => 'بدون تغيير';

  @override
  String get advancedRenameLowercase => 'أحرف صغيرة';

  @override
  String get advancedRenameUppercase => 'أحرف كبيرة';

  @override
  String get advancedRenameTitleCase => 'حالة العنوان';

  @override
  String get advancedRenameCapitalize => 'بدء الجملة بحرف كبير';

  @override
  String get advancedRenameSequentialCounter => 'عدّاد تسلسلي';

  @override
  String get advancedRenameCounterDescription => 'إلحاق أو إضافة أرقام مرتّبة';

  @override
  String get advancedRenameSuffix => 'لاحقة (النهاية)';

  @override
  String get advancedRenamePrefix => 'بادئة (البداية)';

  @override
  String get advancedRenameStartAt => 'البدء من';

  @override
  String get advancedRenameDigits => 'عدد الأرقام';

  @override
  String get advancedRenameDigitsHint => 'مثال: 2 (01)';

  @override
  String get advancedRenameSeparator => 'الفاصل';

  @override
  String get advancedRenameSeparatorHint => '_ or -';

  @override
  String get advancedRenameLivePreview => 'معاينة حيّة';

  @override
  String get advancedRenameDeselect => 'إلغاء التحديد';

  @override
  String get advancedRenameSelectAll => 'تحديد الكل';

  @override
  String get advancedRenameNoFilesSelected => 'لم يتم تحديد أي ملفات';

  @override
  String get advancedRenameNameConflictDetected => 'تم اكتشاف تعارض في الأسماء';

  @override
  String get advancedRenameCheckPreviewToFix =>
      'تحقق من علامة تبويب المعاينة للإصلاح';

  @override
  String get advancedRenameReadyToRename => 'جاهز لإعادة التسمية';

  @override
  String get advancedRenameErrorsDetected => 'تم اكتشاف أخطاء';

  @override
  String advancedRenameApply(int count) {
    return 'تطبيق ($count)';
  }

  @override
  String get advancedRenameNameCollisionWithinBatch => 'تعارض اسم ضمن الدفعة.';

  @override
  String get advancedRenameCollidesWithUnselectedFile =>
      'يتعارض مع ملف غير محدد.';

  @override
  String advancedRenameReadyCount(int valid, int total) {
    return '$valid جاهز لإعادة التسمية (من أصل $total)';
  }

  @override
  String advancedRenameReadyOfTotal(int valid, int total) {
    return '$valid من $total جاهز';
  }

  @override
  String advancedRenameRenamedItems(int succeeded, int failed) {
    return 'تمت إعادة تسمية $succeeded عنصرًا ($failed فشل).';
  }

  @override
  String advancedRenameSuccessfullyRenamed(int count) {
    return 'تمت إعادة تسمية $count عنصرًا بنجاح.';
  }

  @override
  String get advancedRenameMonthsFull =>
      'يناير|فبراير|مارس|أبريل|مايو|يونيو|يوليو|أغسطس|سبتمبر|أكتوبر|نوفمبر|ديسمبر';

  @override
  String get advancedRenameMonthsAbbr =>
      'ينا|فبر|مار|أبر|ماي|يون|يول|أغس|سبت|أكت|نوف|ديس';

  @override
  String get advancedRenameDaysFull =>
      'الاثنين|الثلاثاء|الأربعاء|الخميس|الجمعة|السبت|الأحد';

  @override
  String get advancedRenameDaysAbbr => 'إثن|ثلا|أرب|خمی|جمع|سبت|أحد';

  @override
  String get advancedRenameResolveConflicts => 'حل تعارضات الأسماء قبل التطبيق';

  @override
  String advancedRenameChangedCount(int changed, int total) {
    return '$changed من $total';
  }

  @override
  String get automationKeyfilesPimSectionHeader => 'ملفات المفاتيح و PIM';

  @override
  String get automationKeyfilesPimDescription =>
      'يُخزَّن إلى جانب كلمة مرور الأتمتة أعلاه ويُستخدم بنفس الطريقة لاستدعاءات UNLOCK_VAULT — لخزنة VeraCrypt/LUKS التي تُفتح عادةً بملف مفتاح و/أو قيمة PIM غير افتراضية بدلاً من كلمة مرور فقط.';

  @override
  String get automationSavePimButton => 'حفظ PIM';

  @override
  String get automationCameraSectionHeader => 'أتمتة الكاميرا';

  @override
  String get automationCameraDescription =>
      'تتيح للأتمتة تشغيل TAKE_PHOTO / START_RECORDING / STOP_RECORDING لهذه الخزنة. مُعطَّل افتراضيًا حتى مع الوصول الكامل — على عكس استيراد/تصدير الملفات، لا تحتاج الصورة إلى أي مؤشر على الشاشة على الإطلاق، لذا فهذا خيار انضمام منفصل وصريح.';

  @override
  String get automationAllowCameraCapture => 'السماح بالتقاط الصور بالكاميرا';

  @override
  String get automationPimSavedMessage => 'تم حفظ PIM';

  @override
  String get automationActionImportFolderLabel => 'استيراد مجلد';

  @override
  String get automationActionExportFolderLabel => 'تصدير مجلد';

  @override
  String get automationActionTakePhotoLabel => 'التقاط صورة';

  @override
  String get automationActionStartRecordingLabel => 'بدء التسجيل';

  @override
  String get automationActionStopRecordingLabel => 'إيقاف التسجيل';

  @override
  String get filePropertiesSectionHeader => 'خصائص الملف';

  @override
  String get fullPathLabel => 'المسار الكامل';

  @override
  String get sizeLabel => 'الحجم';

  @override
  String get modifiedLabel => 'تاريخ التعديل';

  @override
  String get vaultLabel => 'الخزنة';

  @override
  String get mediaDimensionsSectionHeader => 'الوسائط والأبعاد';

  @override
  String get resolutionLabel => 'الدقة';

  @override
  String get aspectRatioLabel => 'نسبة العرض إلى الارتفاع';

  @override
  String get formatLabel => 'التنسيق';

  @override
  String get exifCameraDataSectionHeader => 'بيانات EXIF والكاميرا';

  @override
  String get cameraLabel => 'الكاميرا';

  @override
  String get lensLabel => 'العدسة';

  @override
  String get dateTakenLabel => 'تاريخ الالتقاط';

  @override
  String get shutterSpeedLabel => 'سرعة الغالق';

  @override
  String get apertureLabel => 'فتحة العدسة';

  @override
  String get isoLabel => 'ISO';

  @override
  String get focalLengthLabel => 'البعد البؤري';

  @override
  String get flashLabel => 'الفلاش';

  @override
  String get softwareLabel => 'البرنامج';

  @override
  String get gpsLocationLabel => 'موقع GPS';

  @override
  String get integrityChecksumSectionHeader => 'السلامة والمجموع الاختباري';

  @override
  String get computingHashMessage => 'جارٍ حساب التجزئة…';

  @override
  String get tapCalculateToVerifyMessage => 'اضغط على «حساب» للتحقق';

  @override
  String get calculateButton => 'حساب';

  @override
  String get copyDiagnosticsButton => 'نسخ التشخيصات';

  @override
  String get closeButton => 'إغلاق';

  @override
  String get hwAcceleratedBadge => 'تسريع الأجهزة';

  @override
  String get swDecoderBadge => 'فك ترميز برمجي';

  @override
  String get videoDecoderHardwareSection => 'مُفكِّك ترميز الفيديو والأجهزة';

  @override
  String get decoderNameLabel => 'اسم مُفكِّك الترميز';

  @override
  String get accelerationLabel => 'التسريع';

  @override
  String get hardwareGpuDirect => 'أجهزة (GPU مباشر)';

  @override
  String get softwareCpuFallback => 'برمجي (احتياطي CPU)';

  @override
  String get unknownValue => 'غير معروف';

  @override
  String get framerateLabel => 'معدل الإطارات';

  @override
  String get variableOrUnknown => 'متغيّر / غير معروف';

  @override
  String get videoCodecLabel => 'ترميز الفيديو';

  @override
  String get autoDetected => 'اكتشاف تلقائي';

  @override
  String get colorFormatLabel => 'تنسيق اللون';

  @override
  String get initLatencyLabel => 'زمن التهيئة';

  @override
  String get audioEngineSection => 'محرك الصوت';

  @override
  String get audioDecoderLabel => 'مُفكِّك ترميز الصوت';

  @override
  String get audioCodecLabel => 'ترميز الصوت';

  @override
  String get pipelineHealthSection => 'مسار المعالجة والحالة';

  @override
  String get playbackStateLabel => 'حالة التشغيل';

  @override
  String get decryptedBufferLabel => 'المخزن المؤقت المفكوك التشفير';

  @override
  String secondsCached(String seconds) {
    return '$seconds ثانية مخزَّنة مؤقتًا';
  }

  @override
  String get droppedFramesLabel => 'الإطارات المُسقَطة';

  @override
  String nFrames(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count إطار',
      many: '$count إطارًا',
      few: '$count إطارات',
      two: 'إطاران',
      one: 'إطار واحد',
      zero: '0 إطار',
    );
    return '$_temp0';
  }

  @override
  String get sourceStorageLabel => 'مصدر التخزين';

  @override
  String directJniStreamSource(int volId) {
    return 'دفق JNI مباشر بلغة C++‎ (volId=$volId)';
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
