// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get usbAttachPromptTitle => 'USB bağlantı istemini göster';

  @override
  String get usbAttachPromptSubtitle =>
      'Açıkken, bir USB sürücü takıldığında Android VaultExplorer\'ı önerir. Bu istemi durdurmak için kapatın; sürücüleri yine de USB Sürücü Bağla menüsünden açabilirsiniz.';

  @override
  String get usbAttachPromptUpdateErrorMessage =>
      'USB bağlantı ayarı güncellenemedi.';

  @override
  String get cancel => 'İptal';

  @override
  String get close => 'Kapat';

  @override
  String get search => 'Ara';

  @override
  String get goBack => 'Geri git';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => 'Sayfaya git';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return 'Sayfa numarası (1 - $pageCount)';
  }

  @override
  String get pdfViewerPageLabel => 'Sayfa';

  @override
  String get pdfViewerGoButton => 'Git';

  @override
  String get pdfViewerSearchHint => 'Belgede ara';

  @override
  String get pdfViewerNoMatches => 'Eşleşme yok';

  @override
  String get pdfViewerPreviousMatch => 'Önceki eşleşme';

  @override
  String get pdfViewerNextMatch => 'Sonraki eşleşme';

  @override
  String get pdfViewerPrintTooltip => 'Belgeyi yazdır';

  @override
  String get pdfViewerLoadingDocument => 'Belge yükleniyor…';

  @override
  String get pdfViewerCannotOpenTitle => 'PDF açılamıyor';

  @override
  String get pdfViewerFailedToLoad => 'PDF yüklenemedi';

  @override
  String get pdfViewerEditUnavailable =>
      'Bu belge için düzenleme kullanılamıyor';

  @override
  String get paste => 'Yapıştır';

  @override
  String get clear => 'Temizle';

  @override
  String get clipboardVerbMove => 'Taşı';

  @override
  String get clipboardVerbCopy => 'Kopyala';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb ($count) — Ayrıntılar için dokun, yapıştırmak için uzun bas';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb ($count) — Pano ayrıntıları';
  }

  @override
  String clipboardSourceLabel(String source) {
    return 'Kaynak: $source';
  }

  @override
  String get clipboardDefaultSourceName => 'Kasa';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe',
      one: '1 öğe',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count öğe daha',
      one: '+1 öğe daha',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => 'Gelişmiş Parametreler';

  @override
  String get encryptionAlgorithmLabel => 'Şifreleme algoritması';

  @override
  String get hashAlgorithmLabel => 'Özet algoritması';

  @override
  String get clipboardVerbMoving => 'Taşınıyor';

  @override
  String get clipboardVerbCopying => 'Kopyalanıyor';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe',
      one: '1 öğe',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return ' kaynak: \"$source\"';
  }

  @override
  String get clipboardOpenContainerToPaste =>
      'Yapıştırmak için bir kapsayıcı aç';

  @override
  String get keyfilesOptionalLabel => 'Anahtar dosyaları (isteğe bağlı)';

  @override
  String get addFile => 'Dosya ekle';

  @override
  String get noKeyfilesAttached => 'Anahtar dosyası eklenmedi';

  @override
  String get completed => 'Tamamlandı';

  @override
  String get dismiss => 'Kapat';

  @override
  String multiOpLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count aktarım',
      one: '1 aktarım',
    );
    return '$_temp0';
  }

  @override
  String get thumbnailSizeResolutionLabel => 'Küçük resim boyutu (çözünürlük)';

  @override
  String get jpegCompressionQualityLabel => 'JPEG sıkıştırma kalitesi';

  @override
  String get done => 'Bitti';

  @override
  String get confirm => 'Onayla';

  @override
  String get couldNotPickKeyfiles => 'Anahtar dosyaları seçilemedi';

  @override
  String get filesystemLabelEncryptedVault => 'bu şifreli kasa';

  @override
  String get filesystemLabelThisContainer => 'bu kapsayıcı';

  @override
  String get nounFile => 'dosya';

  @override
  String get nounFolder => 'klasör';

  @override
  String get nounFileCapitalized => 'Dosya';

  @override
  String get nounFolderCapitalized => 'Klasör';

  @override
  String get unitBytes => 'bayt';

  @override
  String get unitCharacters => 'karakter';

  @override
  String get validationEmptyName => 'Ad boş olamaz.';

  @override
  String validationReservedNavName(String name, String noun) {
    return '\"$name\" ayrılmış bir gezinme adıdır ve kullanılamaz ($noun adı için).';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return '\"$char\" karakteri $position. konumda kullanılamaz; ad hedefi: $fsLabel.';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return 'Konum $position: yazdırılamayan bir denetim karakteri (kod $code) var; izin verilmeyen hedef: $fsLabel.';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '\"$name\", $fsLabel üzerinde ayrılmış bir aygıt adıdır (CON, PRN, AUX, NUL, COM0–9 veya LPT0–9 ile eşleşir) ve dosya uzantılı ya da uzantısız kullanılamaz.';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return '$noun adları boşlukla bitemez: $fsLabel';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return '$noun adları \".\" ile bitemez: $fsLabel';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return 'Bu ad $length $unit uzunluğunda; $fsLabel üzerinde en fazla $maxLength $unit olabilir ($noun adı için).';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return 'Tam yol $length karakter uzunluğunda; $fsLabel üzerinde en fazla $maxLength.';
  }

  @override
  String conflictSameType(String noun, String name) {
    return 'Burada zaten var ($noun): \"$name\" adlı öğe.';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return 'Burada zaten var ($existingNoun): \"$name\" — ad şu türle paylaşılamaz: $candidateNoun.';
  }

  @override
  String get readOnlyContainerWarning => 'Bu kapsayıcı salt okunur bağlandı.';

  @override
  String get protectHiddenVolumeToggleTitle => 'Gizli birimi koru';

  @override
  String get protectHiddenVolumeToggleSubtitle =>
      'Dış birime yazmanın neden olacağı hasarı önler';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sil: $count öğe?',
      one: 'Sil: 1 öğe?',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning =>
      'Bu öğeler, seçili klasörlerin tüm içeriğiyle birlikte kalıcı olarak silinecek.';

  @override
  String get deleteFilesWarning =>
      'Bu öğeler şifreli biriminizden kalıcı olarak silinecek.';

  @override
  String get delete => 'Sil';

  @override
  String get remove => 'Kaldır';

  @override
  String get create => 'Oluştur';

  @override
  String get rename => 'Yeniden adlandır';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Yeniden adlandır: $count öğe',
      one: 'Yeniden adlandır: 1 öğe',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => 'Yeni klasör';

  @override
  String get newTextFileTitle => 'Yeni metin dosyası';

  @override
  String get folderNameHint => 'Klasör adı';

  @override
  String get filenameHint => 'dosyaadi.txt';

  @override
  String get newNameHint => 'Yeni ad';

  @override
  String get baseNameHint => 'Temel ad';

  @override
  String couldntCreateItem(String name) {
    return '\"$name\" oluşturulamadı — kapsayıcının hâlâ bağlı olduğunu kontrol edin';
  }

  @override
  String couldntRenameSingle(String name) {
    return '\"$name\" yeniden adlandırılamadı — bu adda bir öğe zaten var olabilir';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Yeniden adlandırılamadı: $count öğe — $reason',
      one: 'Yeniden adlandırılamadı: 1 öğe — $reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Yeniden adlandırılamadı: $count öğe',
      one: 'Yeniden adlandırılamadı: 1 öğe',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize =>
      '0\'dan büyük geçerli bir gizli boyut girin';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter =>
      'Gizli birim boyutu dış birim boyutundan küçük olmalıdır';

  @override
  String get hiddenVolumeErrorTooLargeForContainer =>
      'Gizli birim boyutu bu kapsayıcı boyutu için çok büyük';

  @override
  String get hiddenVolumeErrorCredentialsRequired =>
      'Gizli birim oluştururken gizli bir parola veya anahtar dosyası gerekir';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      'Gizli birim kimlik bilgileri (parola, PIM ve anahtar dosyaları) dış birimin kimlik bilgileriyle aynı olamaz.';

  @override
  String get vaultItemTypePassword => 'Parola';

  @override
  String get vaultItemTypePaymentCard => 'Ödeme kartı';

  @override
  String get vaultItemTypeIdentity => 'Kimlik';

  @override
  String get vaultItemTypeSecureNote => 'Güvenli not';

  @override
  String get vaultItemTypeBankAccount => 'Banka hesabı';

  @override
  String get vaultItemTypeSoftwareLicense => 'Yazılım lisansı';

  @override
  String get fieldUsernameEmail => 'Kullanıcı adı / E-posta';

  @override
  String get fieldPassword => 'Parola';

  @override
  String get fieldWebsiteUrl => 'Web sitesi adresi';

  @override
  String get fieldTotpSecret => 'TOTP gizli anahtarı (2FA)';

  @override
  String get fieldNotes => 'Notlar';

  @override
  String get fieldCardholderName => 'Kart sahibinin adı';

  @override
  String get fieldCardNumber => 'Kart numarası';

  @override
  String get fieldExpiryMMYY => 'Son kullanma (AA/YY)';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldIssuingBank => 'Veren banka';

  @override
  String get fieldFullName => 'Ad soyad';

  @override
  String get fieldDateOfBirth => 'Doğum tarihi';

  @override
  String get fieldNationality => 'Uyruk';

  @override
  String get fieldPassportNumber => 'Pasaport numarası';

  @override
  String get fieldPassportExpiry => 'Pasaport geçerlilik süresi';

  @override
  String get fieldNationalIdSsn => 'T.C. kimlik no / SGK no';

  @override
  String get fieldDriversLicense => 'Ehliyet';

  @override
  String get fieldAddress => 'Adres';

  @override
  String get fieldPhone => 'Telefon';

  @override
  String get fieldEmail => 'E-posta';

  @override
  String get fieldNote => 'Not';

  @override
  String get fieldBankName => 'Banka adı';

  @override
  String get fieldAccountHolder => 'Hesap sahibi';

  @override
  String get fieldAccountNumber => 'Hesap numarası';

  @override
  String get fieldRoutingSortCode => 'Şube / Sıralama kodu';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => 'Hesap türü';

  @override
  String get fieldProductName => 'Ürün adı';

  @override
  String get fieldLicenseKey => 'Lisans anahtarı';

  @override
  String get fieldRegisteredTo => 'Kayıtlı kişi';

  @override
  String get fieldPurchaseDate => 'Satın alma tarihi';

  @override
  String get fieldExpiryRenewalDate => 'Bitiş / Yenileme tarihi';

  @override
  String get fieldDownloadUrl => 'İndirme adresi';

  @override
  String get fieldRegistrationEmail => 'Kayıt e-postası';

  @override
  String get titleRequired => 'Başlık gerekli';

  @override
  String newTypeTitle(String typeLabel) {
    return 'Yeni $typeLabel';
  }

  @override
  String editItemTitle(String title) {
    return 'Düzenle: $title';
  }

  @override
  String get save => 'Kaydet';

  @override
  String typeNameHint(String typeLabel) {
    return '$typeLabel adı';
  }

  @override
  String get titleSectionLabel => 'Başlık';

  @override
  String get fieldsSectionLabel => 'Alanlar';

  @override
  String get encryptedStorageHint =>
      'Tüm alanlar kapsayıcının içinde şifreli olarak saklanır.';

  @override
  String copiedSuffix(String fieldLabel) {
    return '$fieldLabel kopyalandı';
  }

  @override
  String get copy => 'Kopyala';

  @override
  String get failedToSaveCheckMounted =>
      'Kaydedilemedi — kapsayıcının hâlâ bağlı olduğunu kontrol edin';

  @override
  String get discardChangesTitle => 'Değişiklikler silinsin mi?';

  @override
  String get discardChangesMessage =>
      'Kaydedilmemiş değişiklikleriniz kaybolacak.';

  @override
  String get discard => 'Vazgeç';

  @override
  String get keepEditing => 'Düzenlemeye devam et';

  @override
  String get deleteItemTitle => 'Öğe silinsin mi?';

  @override
  String deleteItemMessage(String title) {
    return '\"$title\" kasadan kalıcı olarak silinecek.';
  }

  @override
  String get removeFromBookmarks => 'Yer imlerinden kaldır';

  @override
  String get edit => 'Düzenle';

  @override
  String labelCopiedToClipboard(String label) {
    return '$label panoya kopyalandı';
  }

  @override
  String get noFieldsFilledIn =>
      'Hiçbir alan doldurulmadı.\nAyrıntı eklemek için Düzenle\'ye dokunun.';

  @override
  String get sectionLabelDetails => 'Ayrıntılar';

  @override
  String get sectionLabelInfo => 'Bilgi';

  @override
  String get metaLabelType => 'Tür';

  @override
  String get metaLabelCreated => 'Oluşturulma';

  @override
  String get metaLabelModified => 'Değiştirilme';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return 'Kopyala: $fieldLabel';
  }

  @override
  String get readOnlyCantAddItemsTooltip => 'Salt okunur — öğe eklenemez';

  @override
  String get extractArchive => 'Arşivi çıkar';

  @override
  String get verbArchive => 'Arşiv';

  @override
  String get verbExtract => 'Çıkar';

  @override
  String get verbArchived => 'Arşivlendi';

  @override
  String get verbExtracted => 'Çıkarıldı';

  @override
  String get verbArchiving => 'Arşivleniyor';

  @override
  String get verbExtracting => 'Çıkarılıyor';

  @override
  String get fileOpExtractingArchive => 'Arşiv çıkarılıyor…';

  @override
  String fileOpExtractingArchiveName(String name) {
    return 'Çıkarılıyor: $name…';
  }

  @override
  String fileOpArchivingBytes(String bytes) {
    return 'Arşivleniyor… ($bytes)';
  }

  @override
  String get newItemTooltip => 'Yeni öğe';

  @override
  String get camera => 'Kamera';

  @override
  String get importFiles => 'Dosyaları içe aktar';

  @override
  String get importFolder => 'Klasörü içe aktar';

  @override
  String get secureItem => 'Güvenli öğe';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archive Explorer';

  @override
  String get archiveExplorerPermissionTitle => 'Depolama erişimi gerekli';

  @override
  String get archiveExplorerGrantAccess => 'Erişim ver';

  @override
  String get fileAssocInAppTextEditor => 'Uygulama içi metin düzenleyici';

  @override
  String get fileAssocInAppMediaViewer => 'Uygulama içi medya görüntüleyici';

  @override
  String fileAssocAppPrefix(String name) {
    return 'Uygulama: $name';
  }

  @override
  String get fileAssocExternalApp => 'Harici uygulama';

  @override
  String get appSettingsTitle => 'Uygulama ayarları';

  @override
  String get sectionSecurityPrivacy => 'Güvenlik ve gizlilik';

  @override
  String get sectionAppearanceInterface => 'Görünüm ve arayüz';

  @override
  String get sectionVaultFileHandling => 'Kasa ve dosya işleme';

  @override
  String get masterPasswordTitle => 'Ana parola';

  @override
  String get masterPasswordActiveSubtitle =>
      'Etkin — kaldırmak için anahtara dokunun';

  @override
  String get newPasswordLabel => 'Yeni parola';

  @override
  String get masterPasswordFieldLabel => 'Ana parola';

  @override
  String get confirmPasswordLabel => 'Parolayı onayla';

  @override
  String get update => 'Güncelle';

  @override
  String get setPassword => 'Parola belirle';

  @override
  String get biometricUnlockTitle => 'Biyometrik kilit açma';

  @override
  String get autoLockContainersTitle => 'Kapsayıcıları otomatik kilitle';

  @override
  String get autoLockContainersSubtitle =>
      'Hareketsizlikten sonra açık kasaları otomatik kilitle';

  @override
  String get autoLockTimeoutLabel => 'Otomatik kilit süresi';

  @override
  String get immediately => 'Hemen';

  @override
  String nMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dakika',
      one: '1 dakika',
    );
    return '$_temp0';
  }

  @override
  String nHours(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saat',
      one: '1 saat',
    );
    return '$_temp0';
  }

  @override
  String get customDurationOption => 'Özel…';

  @override
  String get customDurationDialogTitle => 'Özel süre';

  @override
  String get blockScreenshotsTitle => 'Ekran görüntülerini engelle';

  @override
  String get blockScreenshotsSubtitle =>
      'Ekran görüntülerini engelle ve son uygulamalar önizlemesini gizle';

  @override
  String get keepVaultsRunningInBackgroundTitle =>
      'Kasaları arka planda açık tut';

  @override
  String get keepVaultsRunningInBackgroundSubtitle =>
      'Bir bildirim göster ve uygulamadan çıktıktan sonra açık kasaları kullanılabilir tut. Kasa anahtarları kilitlenene kadar bellekte kalır.';

  @override
  String get notificationPermissionDeniedMessage =>
      'Bildirim izni reddedildi. Kasalar yine de açık kalacak ancak sürekli bildirim gösterilmeyecek.';

  @override
  String get discreteModeTitle => 'Maske modu';

  @override
  String get discreteModeActiveSubtitle =>
      'Etkin — uygulama şu anda \"Archive Explorer\" olarak görünüyor';

  @override
  String get discreteModeInactiveSubtitle =>
      'Bu uygulamayı ana ekranda bir zip arşiv gezgini olarak gizle';

  @override
  String get enableDiscreteModeTitle => 'Maske modu etkinleştirilsin mi?';

  @override
  String get disableDiscreteModeTitle => 'Maske modu devre dışı bırakılsın mı?';

  @override
  String get enableDiscreteModeMessage =>
      'Ana ekrandaki uygulama simgesi ve adı \"Archive Explorer\" olarak değişecek. Bir zip arşiv gezgini ve çıkarıcı olarak çalışacak.\n\nKasanıza erişmek için Archive Explorer\'ı açın ve parmağınızı başlığın üzerinde 2 saniye basılı tutun.';

  @override
  String get disableDiscreteModeMessage =>
      'Ana ekrandaki uygulama simgesi ve adı \"Vault Explorer\" olarak geri değişecek.';

  @override
  String get enable => 'Etkinleştir';

  @override
  String get disable => 'Devre dışı bırak';

  @override
  String get discreteModeEnabledSnack =>
      'Maske modu etkinleştirildi. Uygulama kapanacak — yeni başlatıcı simgesinden yeniden açın.';

  @override
  String get discreteModeDisabledSnack =>
      'Maske modu devre dışı bırakıldı. Uygulama kapanacak — yeni başlatıcı simgesinden yeniden açın.';

  @override
  String get failedToChangeDiscreteMode => 'Maske modu değiştirilemedi';

  @override
  String get cacheDerivedKeysTitle =>
      'Türetilmiş anahtarları varsayılan olarak önbelleğe al';

  @override
  String get cacheDerivedKeysSubtitle =>
      'Daha hızlı kilit açma için türetilmiş anahtar malzemesini Keystore\'da sakla';

  @override
  String get appThemeLabel => 'Uygulama teması';

  @override
  String get systemDefault => 'Sistem varsayılanı';

  @override
  String get lightTheme => 'Açık tema';

  @override
  String get darkTheme => 'Koyu tema';

  @override
  String get useMaterialYouTitle => 'Material You kullan';

  @override
  String get useMaterialYouSubtitle =>
      'Uygulama renklerini duvar kağıdınıza uydur (Android 12+)';

  @override
  String get sortContainersByLabel => 'Kapsayıcıları sırala';

  @override
  String get autoOpenOnUnlockTitle => 'Kilit açılınca otomatik aç';

  @override
  String get autoOpenOnUnlockActiveSubtitle =>
      'Kasanın kilidi açıldıktan sonra otomatik olarak aç';

  @override
  String get autoOpenOnUnlockInactiveSubtitle =>
      'Yalnızca kasanın kilidini aç ve panoda kal';

  @override
  String get enableJsHtmlTitle =>
      'HTML görüntüleyicide JavaScript\'i etkinleştir';

  @override
  String get jsEnabledSubtitle => 'Yerel HTML dosyaları için JavaScript etkin';

  @override
  String get jsDisabledSubtitle =>
      'Yerel HTML dosyaları için JavaScript devre dışı';

  @override
  String get fastStorageAccessTitle => 'Hızlı depolama erişimi';

  @override
  String get fastStorageAccessGrantedSubtitle =>
      'Tüm dosyalara erişim verildi (maksimum hız)';

  @override
  String get fastStorageAccessNotGrantedSubtitle =>
      'En iyi hız için Sistem Ayarları\'nda tüm dosyalara erişim izni verin';

  @override
  String get showStorageLocationsTitle =>
      'Depolama konumlarını kenar çubuğunda göster';

  @override
  String get showStorageLocationsSubtitle =>
      'Yerel depolamayı ve eklenen konumları gösterir. Yerel depolamayı açmak için tüm dosyalara erişim gerekir.';

  @override
  String get localStorageCardTitle => 'Yerel depolama';

  @override
  String get enableFastStorageAccessTitle =>
      'Hızlı depolama erişimini etkinleştir';

  @override
  String get enableFastStorageAccessMessage =>
      '\"Tüm dosyalara erişim\" izni vermek, Vault Explorer\'ın doğrudan POSIX dosya işlemleri yapmasını sağlar ve klasör kasası performansını artırır';

  @override
  String get disableStorageAccessTitle => 'Depolama erişimini devre dışı bırak';

  @override
  String get disableStorageAccessMessage =>
      'Android, \"Tüm dosyalara erişim\" iznini Sistem Ayarları içinden kapatmanızı gerektirir. Kapatmak için Ayarlar\'ı açmak ister misiniz?';

  @override
  String get enableStoragePermissionLegacyTitle =>
      'Depolama erişimine izin ver';

  @override
  String get enableStoragePermissionLegacyMessage =>
      'Vault Explorer\'ın doğrudan dosya işlemleri yapabilmesi için depolama iznine ihtiyacı var; bu, klasör kasası performansını artırır. Android şimdi onayınızı isteyecek.';

  @override
  String get disableStoragePermissionLegacyMessage =>
      'Android, depolama izninin Sistem Ayarları içinden kapatılmasını gerektirir. Kapatmak için Ayarlar\'ı açmak ister misiniz?';

  @override
  String get openSettings => 'Ayarları aç';

  @override
  String get useThisPasswordButton => 'Bu parolayı kullan';

  @override
  String get quickPasswordGeneratorSheetTitle => 'Parola oluşturucu';

  @override
  String get androidFileProviderTitle => 'Android dosya sağlayıcı';

  @override
  String get androidFileProviderSubtitle =>
      'Yeni kapsayıcıları varsayılan olarak Android dosya seçicisine aç';

  @override
  String get thumbnailCachingDefaultLabel =>
      'Küçük resim önbelleği (varsayılan)';

  @override
  String get thumbnailQualityDefaultLabel =>
      'Küçük resim kalitesi (varsayılan)';

  @override
  String get fileAssociationsHeader => 'Dosya ilişkilendirmeleri';

  @override
  String get noFileAssociationsYet =>
      'Henüz hatırlanan dosya ilişkilendirmesi yok. Dosya açarken size sorulacak.';

  @override
  String get defaultActionsHeader =>
      'Standart dışı dosyalar açılırken varsayılan eylemler:';

  @override
  String get removeAssociationTooltip => 'İlişkilendirmeyi kaldır';

  @override
  String get sectionBackupRestore => 'Yedekleme';

  @override
  String get exportSettingsTitle => 'Ayarları dışa aktar';

  @override
  String get exportSettingsSubtitle =>
      'Uygulama, dosya yöneticisi, medya oynatıcı ve metin düzenleyici ayarlarını bir dosyaya kaydedin. Özel temalar isteğe bağlıdır.';

  @override
  String get importSettingsTitle => 'Ayarları içe aktar';

  @override
  String get importSettingsSubtitle =>
      'Uygulama, dosya yöneticisi, medya oynatıcı ve metin düzenleyici ayarlarını bir dosyadan geri yükleyin';

  @override
  String get importSettingsConfirmTitle => 'Ayarlar içe aktarılsın mı?';

  @override
  String get importSettingsConfirmMessage =>
      'Bu işlem mevcut uygulama ayarlarınızın yerine geçer. Kaplamalarınız ve arayüz düzeniniz etkilenmez. Bu işlem geri alınamaz.';

  @override
  String get exportSettingsOnlyTitle => 'Yalnızca ayarlar';

  @override
  String get exportSettingsOnlySubtitle =>
      'Uygulama, dosya yöneticisi, medya oynatıcı ve metin düzenleyici ayarları';

  @override
  String get exportSettingsWithSkinsTitle => 'Ayarlar ve temalar';

  @override
  String get exportSettingsWithSkinsSubtitle =>
      'Özel uygulama temalarınızı da kaydeder';

  @override
  String get importSettingsConfirmFullMessage =>
      'Bu işlem uygulama, dosya yöneticisi, medya oynatıcı ve metin düzenleyici ayarlarınızı düzenleriyle birlikte değiştirir. Temalarınız etkilenmez. Bu işlem geri alınamaz.';

  @override
  String get importSettingsConfirmFullSkinsMessage =>
      'Bu işlem uygulama, dosya yöneticisi, medya oynatıcı ve metin düzenleyici ayarlarınızı düzenleriyle birlikte değiştirir ve bu dosyadaki temaları ekler. Zaten sahip olduğunuz bir tema, dosyadaki sürümle değiştirilir. Bu işlem geri alınamaz.';

  @override
  String get exportSettingsSuccessMessage => 'Ayarlar dışa aktarıldı';

  @override
  String get importSettingsSuccessMessage => 'Ayarlar içe aktarıldı';

  @override
  String get exportSettingsErrorMessage => 'Ayarlar dışa aktarılamadı';

  @override
  String get importSettingsInvalidFileMessage =>
      'Bu dosya geçerli bir ayar dışa aktarımı değil';

  @override
  String get sectionDebug => 'Hata ayıklama';

  @override
  String get debugLoggingTitle => 'Hata ayıklama günlüğü';

  @override
  String get debugLoggingSubtitle =>
      'Kapsayıcı işlemleri için ayrıntılı tanılama günlükleri kaydet';

  @override
  String get logcatTitle => 'Logcat';

  @override
  String get logcatSubtitle => 'Cihaz günlüklerini görüntüle ve kaydet';

  @override
  String logcatSavedMessage(String path) {
    return 'Günlük şuraya kaydedildi: $path';
  }

  @override
  String get logcatSaveErrorMessage => 'Günlük kaydedilemedi';

  @override
  String get logcatCopiedMessage => 'Günlük panoya kopyalandı';

  @override
  String get logcatUnavailableMessage => 'Logcat bu cihazda kullanılamıyor';

  @override
  String get logcatEmptyMessage => 'Günlük satırları bekleniyor…';

  @override
  String get logcatClearTooltip => 'Günlüğü temizle';

  @override
  String get logcatSaveTooltip => 'Günlüğü kaydet';

  @override
  String get logcatFilterAppOnly => 'Yalnızca uygulama';

  @override
  String get logcatFilterAll => 'Tüm günlükler';

  @override
  String get logcatSearchHint => 'Günlüklerde ara…';

  @override
  String get logcatClearedMessage => 'Günlükler temizlendi';

  @override
  String get logcatCopyTooltip => 'Günlüğü kopyala';

  @override
  String get retryButton => 'Yeniden dene';

  @override
  String get aboutAppTitle => 'VaultExplorer hakkında';

  @override
  String versionInfoSubtitle(String version) {
    return 'Sürüm $version · Açık kaynak lisansları ve ayrıntılar';
  }

  @override
  String get failedToSaveSettings => 'Ayarlar kaydedilemedi';

  @override
  String get masterPasswordSetSnack => 'Ana parola belirlendi';

  @override
  String get passwordCannotBeEmpty => 'Parola boş olamaz';

  @override
  String get atLeast4CharsRequired => 'En az 4 karakter gerekli';

  @override
  String get passwordsDoNotMatch => 'Parolalar eşleşmiyor';

  @override
  String get failedToHashPassword =>
      'Parola özetlenemedi — lütfen tekrar deneyin';

  @override
  String get languageLabel => 'Dil';

  @override
  String get biometricNotAvailable =>
      'Bu cihazda biyometrik doğrulama kullanılamıyor';

  @override
  String get biometricsChangedFallbackMessage =>
      'Cihazınızın biyometrik verileri değişti, bu yüzden biyometrik kilit açma kapatıldı. Parolanızı kullanın.';

  @override
  String get unlockVaultExplorerReason => 'VaultExplorer kilidini aç';

  @override
  String biometricErrorWithCode(String code) {
    return 'Biyometrik hata: $code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds saniye',
      one: '1 saniye',
    );
    return 'Çok fazla başarısız deneme. Şu süre sonra tekrar deneyin: $_temp0.';
  }

  @override
  String get enterMasterPasswordPrompt => 'Ana parolanızı girin';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts başarısız deneme',
      one: '1 başarısız deneme',
    );
    return 'Yanlış parola. Kilitli: ${seconds}sn — $_temp0.';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts başarısız deneme',
      one: '1 başarısız deneme',
    );
    return 'Yanlış parola ($_temp0).';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle => 'Devam etmek için ana parolanızı girin';

  @override
  String get masterPasswordFieldLabelTitleCase => 'Ana parola';

  @override
  String get unlock => 'Kilidi aç';

  @override
  String get connectAtLeast4Dots => 'En az 4 noktayı birleştirin';

  @override
  String get patternsDontMatch => 'Desenler eşleşmiyor — tekrar deneyin';

  @override
  String get drawUnlockPatternTitle => 'Kilit açma desenini çizin';

  @override
  String get confirmPatternTitle => 'Deseninizi onaylayın';

  @override
  String get drawSamePatternAgain => 'Aynı deseni tekrar çizin';

  @override
  String get enterAtLeast4Digits => 'En az 4 rakam girin';

  @override
  String get pinsDontMatch => 'PIN\'ler eşleşmiyor — tekrar deneyin';

  @override
  String get createUnlockPinTitle => 'Kilit açma PIN\'inizi oluşturun';

  @override
  String get confirmPinTitle => 'PIN\'inizi onaylayın';

  @override
  String get enterSamePinAgain => 'Aynı PIN\'i tekrar girin';

  @override
  String get enterUnlockPinTitle => 'Kilit açma PIN\'ini girin';

  @override
  String get noPinConfiguredMessage =>
      'PIN yapılandırılmamış. Lütfen parolayı elle girin.';

  @override
  String pinLockedForSeconds(int seconds) {
    return 'Çok fazla başarısız deneme. ${seconds}sn boyunca kilitli.';
  }

  @override
  String get initSecureCredsPinMessage =>
      'Güvenli kimlik bilgileri hazırlanıyor. PIN erişimini yetkilendirmek için lütfen bir kez elle kilidi açın.';

  @override
  String get setPinButton => 'PIN belirle';

  @override
  String get changePinButton => 'PIN değiştir';

  @override
  String get pinSetupRequiredBeforeSaving =>
      'Kaydetmeden önce bir PIN belirleyin.';

  @override
  String get pinSetupRequiredAboveBeforeSaving =>
      'Kaydetmeden önce yukarıda bir PIN belirleyin.';

  @override
  String get verifyPinTitle => 'PIN\'i doğrula';

  @override
  String get incorrectPinError => 'Yanlış PIN';

  @override
  String get moreOptionsTooltip => 'Diğer seçenekler';

  @override
  String get containerAlreadyMounted => 'Bu kapsayıcı zaten bağlı.';

  @override
  String get noVaultFolderFormatDetected =>
      'Bu klasörde masterkey.cryptomator, gocryptfs.conf veya cryfs.config bulunamadı.';

  @override
  String get savedContainerSettingsNotFound =>
      'Bu kapsayıcının kayıtlı ayarları bulunamadı.';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return 'Kapsayıcı konumu güncellenemedi: $error';
  }

  @override
  String filePickerFailed(String error) {
    return 'Dosya seçici başarısız oldu: $error';
  }

  @override
  String get passwordOrKeyfilesRequired =>
      'Parola veya anahtar dosyaları gerekli';

  @override
  String get incorrectPasswordOrInvalidVault =>
      'Yanlış parola veya geçersiz kasa';

  @override
  String get incorrectPasswordOrInvalidContainer =>
      'Yanlış parola veya geçersiz kapsayıcı';

  @override
  String get decryptingLabel => 'Şifre çözülüyor…';

  @override
  String get loadingContainerFromStorage =>
      'Kapsayıcı depolamadan yükleniyor… Büyük veya bulutta depolanan kapsayıcılar biraz zaman alabilir.';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return 'Anahtar yuvası deneniyor: $attempted / $total…';
  }

  @override
  String get luksKeyslotProgressUnknown => 'Anahtar yuvası deneniyor…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return 'Kimlik bilgisi doğrulanıyor: $attempted / $total…';
  }

  @override
  String get bitlockerCredentialProgressUnknown =>
      'Kimlik bilgisi doğrulanıyor…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return 'Deneniyor: $algo ($slotName)…';
  }

  @override
  String get unlockContainerLabel => 'Kapsayıcının kilidini aç';

  @override
  String get mountContainerTitle => 'Kapsayıcıyı bağla';

  @override
  String formatContainerLabel(String format) {
    return '$format Kapsayıcı';
  }

  @override
  String formatVaultLabel(String format) {
    return '$format Kasa';
  }

  @override
  String get encryptedContainerLabel => 'Şifreli kapsayıcı';

  @override
  String get tapToSelectVaultFolder => 'Kasa klasörünü seçmek için dokunun…';

  @override
  String get tapToSelectContainerFile =>
      'Kapsayıcı dosyasını seçmek için dokunun…';

  @override
  String get containerMissingTitle => 'Kapsayıcı bulunamadı';

  @override
  String get containerMissingExplanation =>
      'Kapsayıcı dosyası taşınmış veya silinmiş olabilir ya da barındıran depolama şu anda bağlı değil.';

  @override
  String get retryButtonLabel => 'Yeniden dene';

  @override
  String get locateFileButtonLabel => 'Dosyayı bul';

  @override
  String get usePasswordButtonLabel => 'Parola kullan';

  @override
  String get authenticateButtonLabel => 'Kimlik doğrula';

  @override
  String get usePasswordInsteadButtonLabel => 'Bunun yerine parola kullan';

  @override
  String get usingSavedPasswordTooltip => 'Kayıtlı parola kullanılıyor';

  @override
  String get luksKeyfileReplacesPasswordNote =>
      'LUKS kapsayıcılarında anahtar dosyası parolanın yerini alır.';

  @override
  String get readOnlyModeContainerSubtitle =>
      'Bu kapsayıcıda değişikliğe izin vermeden bağla';

  @override
  String get rememberContainerLabel => 'Kapsayıcıyı hatırla';

  @override
  String get rememberContainerSubtitle =>
      'Hızlı erişim için kapsayıcıyı panoya sabitle';

  @override
  String get cancelUnlockButtonLabel => 'Kilit açmayı iptal et';

  @override
  String get biometricSubjectContainer => 'kapsayıcı';

  @override
  String get biometricSubjectUsbDrive => 'USB sürücü';

  @override
  String get usbNoSavedCredentialsMessage =>
      'Kayıtlı parola bulunamadı. Lütfen elle girin.';

  @override
  String get decryptingDriveLabel => 'Sürücünün şifresi çözülüyor…';

  @override
  String reconnectUsbDriveTitle(String label) {
    return 'Yeniden bağla: \"$label\"';
  }

  @override
  String get unlockUsbDriveTitle => 'USB sürücünün kilidini aç';

  @override
  String get noUsbStorageDetectedTitle => 'USB depolama algılanmadı';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return 'Kilidi açmak için kimlik doğrulayın: $subject';
  }

  @override
  String get noPatternConfiguredMessage =>
      'Desen yapılandırılmamış. Lütfen parolayı elle girin.';

  @override
  String patternLockedForSeconds(int seconds) {
    return 'Çok fazla başarısız deneme. ${seconds}sn boyunca kilitli.';
  }

  @override
  String get initSecureCredsBiometricMessage =>
      'Güvenli kimlik bilgileri hazırlanıyor. Biyometrik erişimi yetkilendirmek için lütfen bir kez elle kilidi açın.';

  @override
  String get initSecureCredsPatternMessage =>
      'Güvenli kimlik bilgileri hazırlanıyor. Desen erişimini yetkilendirmek için lütfen bir kez elle kilidi açın.';

  @override
  String get mountExistingContainerTitle => 'Mevcut kapsayıcıyı bağla';

  @override
  String get mountExistingContainerSubtitle =>
      'Sahip olduğunuz bir dosya kapsayıcısının kilidini açın';

  @override
  String get mountUsbDriveTitle => 'USB sürücü bağla';

  @override
  String get mountUsbDriveSubtitle =>
      'OTG flash sürücüdeki bir kapsayıcının kilidini açın';

  @override
  String get formatUsbDriveTitle => 'USB sürücüyü biçimlendir';

  @override
  String get formatUsbDriveSubtitle =>
      'Bir sürücüyü silin ve üzerinde yeni bir şifreli kapsayıcı oluşturun';

  @override
  String get createNewContainerTitle => 'Yeni kapsayıcı oluştur';

  @override
  String get createNewContainerSubtitle =>
      'Sıfırdan yeni bir şifreli kasa biçimlendirin';

  @override
  String get lockBeforeRemovingWarning =>
      'Kapsayıcıyı çıkarmadan önce kilitleyin.';

  @override
  String get settingsTooltip => 'Ayarlar';

  @override
  String get addVaultFabLabel => 'Kasa ekle';

  @override
  String removedLabelUndo(String label) {
    return 'Kaldırıldı: \"$label\"';
  }

  @override
  String get undo => 'Geri al';

  @override
  String get pdfViewerNoSourceProvided => 'PDF kaynağı sağlanmadı.';

  @override
  String get pdfViewerFileEmpty => 'PDF dosyası boş veya okunamıyor.';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return 'PDF dosya boyutu incelenemedi: $error';
  }

  @override
  String get pdfViewerNoDocumentLoaded => 'Yüklenmiş PDF belgesi yok.';

  @override
  String get add => 'Ekle';

  @override
  String get reset => 'Sıfırla';

  @override
  String couldNotExpose(String name) {
    return 'Sunulamadı: \"$name\".';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return '\"$name\" artık diğer uygulamalara açık.';
  }

  @override
  String couldNotUnmount(String name) {
    return 'Bağlantı kesilemedi: \"$name\".';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sabitlendi: $count öğe',
      one: 'Sabitlendi: 1 öğe',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sabitleme kaldırıldı: $count öğe',
      one: 'Sabitleme kaldırıldı: 1 öğe',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning =>
      'Salt okunur bağlama — küçük resimler gösterilir ancak bu oturumda kapsayıcının içine kaydedilmez.';

  @override
  String failedLoadingFolder(String type) {
    return 'Klasör yüklenemedi: $type';
  }

  @override
  String failedToReadArchive(String type) {
    return 'Arşiv okunamadı: $type';
  }

  @override
  String get archivePasswordPromptTitle => 'Parola korumalı';

  @override
  String get archivePasswordPromptMessage =>
      'Bu arşiv parola korumalı. İçeriğini görmek için parolayı girin.';

  @override
  String get failedToReadFileFromArchive => 'Dosya arşivden okunamadı';

  @override
  String failedToExtractFile(String type) {
    return 'Dosya çıkarılamadı: $type';
  }

  @override
  String get failedToReadSecureItem => 'Güvenli öğe okunamadı';

  @override
  String get openFileDialogTitle => 'Dosyayı aç';

  @override
  String chooseHowToOpen(String name) {
    return 'Şunun için yöntem seçin: \"$name\":';
  }

  @override
  String get playVideoAudioViewImageInApp =>
      'Videoyu/sesi uygulama içinde oynat veya görüntüyü göster';

  @override
  String get viewEditTextMarkdownCode =>
      'Metin, markdown, kod görüntüle/düzenle';

  @override
  String get sendFileToThirdPartyApp =>
      'Dosyayı üçüncü taraf uygulamaya gönder';

  @override
  String get openAsEllipsis => 'Şu şekilde aç…';

  @override
  String get chooseFileTypeToOpenAs => 'Açılacak dosya türünü seçin';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return 'Her zaman hatırla: .$ext dosya';
  }

  @override
  String get alwaysRememberChoiceNoExt =>
      'Uzantısız dosyalar için seçimi her zaman hatırla';

  @override
  String get openAsDialogTitle => 'Şu şekilde aç';

  @override
  String get mimeTypeText => 'Metin';

  @override
  String get mimeTypeImage => 'Resim';

  @override
  String get mimeTypeVideo => 'Video';

  @override
  String get mimeTypeAudio => 'Ses';

  @override
  String get mimeTypeArchive => 'Arşiv';

  @override
  String get mimeTypeOther => 'Diğer';

  @override
  String get scanningSubfoldersForMedia => 'Alt klasörlerde medya taranıyor…';

  @override
  String get noMediaFilesFoundRecursive =>
      'Bu klasörde veya alt klasörlerinde medya dosyası bulunamadı';

  @override
  String failedToScanSubfolders(String error) {
    return 'Alt klasörler taranamadı: $error';
  }

  @override
  String scanningSubfoldersForMediaProgress(int count) {
    return 'Alt klasörlerde medya taranıyor… $count denetlendi';
  }

  @override
  String get mediaScanCancelled => 'Medya taraması iptal edildi';

  @override
  String get mediaScanLimitReached =>
      'Çok sayıda klasör denetlendikten sonra tarama durduruldu. Medya bulunamadı.';

  @override
  String get noAppFoundForFileType => 'Bu dosya türü için uygulama bulunamadı';

  @override
  String couldNotOpenFile(String name) {
    return 'Açılamadı: \"$name\"';
  }

  @override
  String get couldNotShareFiles => 'Seçilen dosyalar paylaşılamadı';

  @override
  String get readOnlyCantMove =>
      'Bu kapsayıcı salt okunur bağlandı — öğeler buradan taşınamaz.';

  @override
  String get readOnlyCantPaste =>
      'Bu kapsayıcı salt okunur bağlandı — öğeler buraya yapıştırılamaz.';

  @override
  String get clipboardSourceInvalid => 'Pano kaynağı geçersiz';

  @override
  String get crossContainerPasteNotConfigured =>
      'Kapsayıcılar arası yapıştırma ayarlanmamış.';

  @override
  String get crossContainerPasteRequiresBothMounted =>
      'Kapsayıcılar arası yapıştırma için her iki kapsayıcının da bağlı kalması gerekir.';

  @override
  String get readOnlyCantDelete =>
      'Bu kapsayıcı salt okunur bağlandı — öğeler silinemez.';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Silindi: $count öğe',
      one: 'Silindi: 1 öğe',
    );
    return '$_temp0';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dışa aktarıldı: $count dosya',
      one: 'Dışa aktarıldı: 1 dosya',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed =>
      'Dışa aktarma iptal edildi veya başarısız oldu';

  @override
  String get deleteOriginalTitle => 'Orijinal silinsin mi?';

  @override
  String get deleteOriginalFolderMessage =>
      'İçe aktarma tamamlandığına göre orijinal klasör cihazınızdan şimdi silinsin mi?';

  @override
  String get deleteOriginalFilesMessage =>
      'İçe aktarma tamamlandığına göre orijinal dosyalar cihazınızdan şimdi silinsin mi?';

  @override
  String get keepOriginal => 'Orijinali koru';

  @override
  String get deleteOriginalButton => 'Orijinali sil';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Silindi: $count orijinal öğe',
      one: 'Silindi: 1 orijinal öğe',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals => 'Orijinaller silinemedi';

  @override
  String get videoCapturedEncrypted => 'Video kaydedildi';

  @override
  String get photoCapturedEncrypted => 'Fotoğraf kaydedildi';

  @override
  String cameraCaptureFailed(String type) {
    return 'Kamera çekimi başarısız: $type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return 'Tüm dosyalar şu klasöre çıkarılsın mı: \"$folder\"?';
  }

  @override
  String get extract => 'Çıkar';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Çıkarıldı: $count dosya',
      one: 'Çıkarıldı: 1 dosya',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return 'Çıkarılamadı: $type';
  }

  @override
  String get archiveSelectionAction => 'Arşiv';

  @override
  String get createArchiveTitle => 'Arşiv oluştur';

  @override
  String failedToArchiveGeneric(String type) {
    return 'Arşiv oluşturulamadı: $type';
  }

  @override
  String get createArchiveEncryptFilenames => 'Dosya adlarını şifrele';

  @override
  String get closeSearchTooltip => 'Aramayı kapat';

  @override
  String get searchInThisFolderTooltip => 'Bu klasörde ara';

  @override
  String get playMediaHereTooltip => 'Medyayı burada oynat';

  @override
  String get rootFolderLabel => 'Kök';

  @override
  String folderPickerFailed(String error) {
    return 'Klasör seçici başarısız oldu: $error';
  }

  @override
  String get addAVaultTitle => 'Kasa ekle';

  @override
  String get selectEmptyDestinationFolderFirst =>
      'Önce boş bir hedef klasör seçin';

  @override
  String get passwordRequired => 'Parola gerekli';

  @override
  String get vaultCreatedSuccessfully => 'Kasa başarıyla oluşturuldu.';

  @override
  String get vaultCreationFailedEmptyFolder =>
      'Kasa oluşturulamadı — seçili klasörün boş olduğundan emin olun.';

  @override
  String get unknownErrorOccurred => 'Bilinmeyen bir hata oluştu';

  @override
  String get containerNameRequired => 'Kapsayıcı adı gerekli';

  @override
  String get enterValidSizeGreaterThanZero =>
      '0\'dan büyük geçerli bir boyut girin';

  @override
  String get passwordOrKeyfileRequired =>
      'Bir parola veya en az bir anahtar dosyası gerekli';

  @override
  String get standardVolumePasswordsDoNotMatch =>
      'Standart birim parolaları eşleşmiyor';

  @override
  String get hiddenVolumePasswordsDoNotMatch =>
      'Gizli birim parolaları eşleşmiyor';

  @override
  String get containerFileCreatedSuccessfully =>
      'Kapsayıcı dosyası başarıyla oluşturuldu.';

  @override
  String get containerCreationCancelledOrFailed =>
      'Kapsayıcı oluşturma iptal edildi veya başarısız oldu.';

  @override
  String insufficientSpaceForContainer(String needed, String available) {
    return 'Hedefte yeterli boş alan yok. Gereken: $needed, yalnızca $available mevcut.';
  }

  @override
  String get vaultKindContainerFile => 'Kapsayıcı dosyası';

  @override
  String get vaultKindFolderVault => 'Klasör kasası';

  @override
  String get formatFileSystemLabel => 'Dosya sistemini biçimlendir';

  @override
  String get containerFormatLabel => 'Kapsayıcı biçimi';

  @override
  String get fileNameLabel => 'Dosya adı';

  @override
  String get containerSizeLabel => 'Kapsayıcı boyutu';

  @override
  String get unitLabel => 'Birim';

  @override
  String get passwordFieldLabel => 'Parola';

  @override
  String get confirmPasswordFieldLabelTitleCase => 'Parolayı onayla';

  @override
  String get hiddenVolumeHeader => 'Gizli birim';

  @override
  String get createHiddenVolumeToggleTitle => 'Gizli birim oluştur';

  @override
  String get createInvisibleSecondaryVolume =>
      'Görünmez bir ikincil birim oluşturun';

  @override
  String get setOuterPasswordFirstToEnable =>
      'Etkinleştirmek için önce dış parolayı veya anahtar dosyalarını belirleyin';

  @override
  String get hiddenPasswordLabel => 'Gizli parola';

  @override
  String get confirmHiddenPasswordLabel => 'Gizli parolayı onayla';

  @override
  String get hiddenSizeLabel => 'Gizli boyut';

  @override
  String get unitMbMegabytes => 'MB (Megabayt)';

  @override
  String get unitGbGigabytes => 'GB (Gigabayt)';

  @override
  String get hiddenFileSystemLabel => 'Gizli dosya sistemi';

  @override
  String get vaultFormatLabel => 'Kasa biçimi';

  @override
  String get gocryptfsCipherLabel => 'İçerik şifresi';

  @override
  String get gocryptfsNamesRandomIvOption =>
      'Klasör başına rastgele (varsayılan)';

  @override
  String get gocryptfsNamesDeterministicOption =>
      'Belirlenimci (eşitlenen klasörler için)';

  @override
  String get cryfsCipherLabel => 'İçerik şifresi';

  @override
  String get cryfsBlockSizeLabel => 'Blok boyutu';

  @override
  String get destinationFolderLabel => 'Hedef klasör';

  @override
  String get selectEmptyFolderLabel => 'Boş bir klasör seçin';

  @override
  String get tapToChooseVaultLocation =>
      'Kasanın oluşturulacağı yeri seçmek için dokunun…';

  @override
  String get folderVaultLimitationsNote =>
      'Klasör kasaları anahtar dosyalarını, PIM\'i, gizli birimleri veya VeraCrypt/LUKS şifre seçeneklerini desteklemez.';

  @override
  String get createVaultButton => 'Kasa oluştur';

  @override
  String get createContainerButton => 'Kapsayıcı oluştur';

  @override
  String get vaultCreationInProgressWait =>
      'Kasa oluşturuluyor. Lütfen bekleyin.';

  @override
  String get containerCreationInProgressWait =>
      'Kapsayıcı oluşturuluyor. Lütfen bekleyin.';

  @override
  String get createEncryptedVaultTitle => 'Şifreli kasa oluştur';

  @override
  String get createEncryptedContainerTitle => 'Şifreli kapsayıcı oluştur';

  @override
  String get unitMbShort => 'MB';

  @override
  String get unitGbShort => 'GB';

  @override
  String get couldNotReadDriveCapacity =>
      'Sürücü kapasitesi okunamadı — boyutu elle girin.';

  @override
  String get selectUsbDriveFirst => 'Önce bir USB sürücü seçin';

  @override
  String eraseDeviceTitle(String name) {
    return 'Sil: \"$name\"?';
  }

  @override
  String get eraseDeviceMessage =>
      'Bu işlem, USB sürücüdeki her şeyi kalıcı olarak silecek ve yerine yeni bir şifreli kapsayıcı koyacak. Bu işlem geri alınamaz.';

  @override
  String get eraseAndCreateButton => 'Sil ve oluştur';

  @override
  String get usbPermissionRequiredToContinue =>
      'Devam etmek için USB izni gerekli';

  @override
  String get usbContainerCreatedSnack =>
      'USB kapsayıcı oluşturuldu. Kilidini açmak için \"USB sürücü bağla\"yı kullanın.';

  @override
  String get usbContainerCreationFailed => 'USB kapsayıcı oluşturulamadı.';

  @override
  String get formattingErasesEverythingWarning =>
      'Biçimlendirme, seçili sürücüdeki her şeyi siler.';

  @override
  String get selectUsbDriveLabel => 'USB sürücü seçin';

  @override
  String get noUsbStorageDetected => 'USB depolama algılanmadı';

  @override
  String get connectOtgDriveToFormat =>
      'Biçimlendirmek için bir OTG sürücü bağlayın';

  @override
  String get refreshListButton => 'Listeyi yenile';

  @override
  String get readyToFormat => 'Biçimlendirmeye hazır';

  @override
  String get permissionRequired => 'İzin gerekli';

  @override
  String get readingDriveCapacity => 'Sürücü kapasitesi okunuyor…';

  @override
  String get mustNotExceedDriveCapacity =>
      'Sürücünün gerçek kapasitesini aşmamalıdır.';

  @override
  String get quickFormatTitle => 'Hızlı biçimlendirme';

  @override
  String get quickFormatDescription =>
      'Sürücünün sıfırlarla doldurulmasını atlar. Daha hızlıdır ancak eski verileri güvenli şekilde silmez.';

  @override
  String get eraseAndCreateContainerButton => 'Sil ve kapsayıcı oluştur';

  @override
  String get usbContainerCreationInProgressWait =>
      'Kapsayıcı oluşturuluyor. Lütfen bekleyin.';

  @override
  String get formatUsbDriveScreenTitle => 'USB sürücüyü biçimlendir';

  @override
  String get playlistTransitionAnimationLabel =>
      'Oynatma listesi geçiş animasyonu';

  @override
  String get playlistTransitionSlideLabel => 'Kaydırma (varsayılan)';

  @override
  String get playlistTransitionFadeLabel => 'Solma';

  @override
  String get playlistTransitionZoomLabel => 'Yakınlaştırma ve ölçekleme';

  @override
  String get playlistTransitionDepthLabel => 'Derinlik yığını';

  @override
  String get playlistTransitionCubeLabel => '3B küp';

  @override
  String get playlistTransitionFlipLabel => '3B çevirme';

  @override
  String get useBackupHeaderToggleTitle => 'Yedek başlığı kullan';

  @override
  String get useBackupHeaderToggleSubtitle =>
      'Birimin sonunda saklanan başlık yedeğiyle açın. Ana başlık hasarlıysa kullanın.';

  @override
  String get keepCurrentOption => 'Mevcut olanı koru';

  @override
  String get toolExpandVolumeSubtitle =>
      'Standart bir birimi, masaüstündeki Volume Expander gibi büyütün';

  @override
  String get luksToolsExpandNote =>
      'Önce kapsayıcının yedeğini alın. LUKS1 ve LUKS2 desteklenir. NTFS ve ext2/3/4 dosya sistemleri yerinde genişletilebilir (FAT ve exFAT genişletilemez). Eklenen alan şifreli sıfırlarla doldurulabilir. Anahtar dosyası kullanılıyorsa parolanın yerine geçer.';

  @override
  String get bitlockerToolsExpandNote =>
      'Önce kapsayıcının yedeğini alın. Bu işlem BitLocker üst verisini yeniden yazar, böylece şifreli birim eklenen alanı da kapsar; güvenmeden önce sonucu bir kopya üzerinde denetleyin. Windows 7 ve sonrasından tamamen şifrelenmiş BitLocker birimlerinde, ham birim dosyası olarak ya da sabit veya dinamik bir VHD veya VHDX içinde çalışır. Disk görüntüsü için yeni toplam disk boyutunu girin: sanal disk ve son bölümü (MBR veya GPT) de büyütülür, bu yüzden BitLocker bölümü sonuncu olmalıdır. BitLocker To Go ve yazarken şifreleme (yalnızca kullanılan alan) birimleri desteklenmez. NTFS yerinde genişletilebilir (FAT ve exFAT genişletilemez). Eklenen alan isteğe bağlı olarak şifreli sıfırlarla doldurulabilir. Parola veya 48 haneli kurtarma anahtarıyla kilidi açın.';

  @override
  String get bitlockerToolsPasswordLabel => 'Parola veya kurtarma anahtarı';

  @override
  String get toolHiddenInExistingTitle => 'Gizli birim ekle';

  @override
  String get toolHiddenInExistingSubtitle =>
      'Mevcut bir standart birimin içinde gizli birim oluşturun';

  @override
  String get vcToolsNoContainer => 'Kapsayıcı seçilmedi';

  @override
  String get vcToolsPasswordLabel => 'Birim parolası';

  @override
  String get vcToolsPimLabel => 'PIM (isteğe bağlı)';

  @override
  String get vcToolsInitFreeSpace => 'Yeni alanı hazırla';

  @override
  String get vcToolsInitFreeSpaceHint =>
      'Eklenen alanı birim anahtarıyla şifrelenmiş verilerle doldurur, böylece geri kalanından ayırt edilemez. Hızlı genişletme için kapatın.';

  @override
  String get vcToolsExpandAction => 'Birimi genişlet';

  @override
  String get vcToolsExpandNote =>
      'Önce kapsayıcı büyütülür. Ardından içindeki dosya sistemi, yeniden biçimlendirme gerekmeden mümkün olan yerlerde (NTFS, ext2/3/4) eklenen alana genişletilir. FAT ve exFAT yerinde genişletilemez; eklenen alanları ayrılmamış kalır. Önce birimin yedeğini alın.';

  @override
  String get vcToolsExpandDone => 'Birim genişletildi';

  @override
  String get vcToolsGrowFsToggle => 'Dosya sistemini de genişlet';

  @override
  String get vcToolsGrowFsToggleHint =>
      'NTFS ve ext2/3/4 birimlerinin eklenen alanı yeniden biçimlendirmeden hemen kullanmasını sağlar.';

  @override
  String get vcToolsGrowFsOnlyAction => 'Yalnızca dosya sistemini genişlet';

  @override
  String get vcToolsFsGrown =>
      'Dosya sistemi genişletildi: eklenen alan kullanıma hazır.';

  @override
  String get vcToolsFsAlreadyFills =>
      'Dosya sistemi zaten tüm birimi dolduruyor.';

  @override
  String get vcToolsFsUnsupported =>
      'Bu dosya sistemi yerinde genişletilemez (FAT ve exFAT genişletilemez). Eklenen alan, birim yeniden biçimlendirilene kadar ayrılmamış kalır; önce dosyalarının yedeğini alın.';

  @override
  String get vcToolsFsBusy =>
      'Birimde hâlâ açık dosyalar var. Bunları kapatın, birimi kilitleyin, sonra “Yalnızca dosya sistemini genişlet” seçeneğini yeniden deneyin.';

  @override
  String get vcToolsFsNeedsCheck =>
      'Dosya sistemi denetim gerektiriyor olarak işaretli. Birimde Denetle ve Onar\'ı çalıştırın, sonra “Yalnızca dosya sistemini genişlet” seçeneğini kullanın.';

  @override
  String get vcToolsFsFailed =>
      'Dosya sistemi genişletilemedi. Birimin kendisi genişletildi; kullanmadan önce üzerinde Denetle ve Onar\'ı çalıştırın.';

  @override
  String get vcToolsAnalyzeAction => 'Boş alanı denetle';

  @override
  String get vcToolsMaxHidden => 'Mümkün olan en büyük gizli birim';

  @override
  String get vcToolsNoRoom =>
      'Gizli birim için yer yok: dış birimin sonu kullanımda.';

  @override
  String get vcToolsHiddenSizeLabel => 'Gizli birim boyutu (MiB)';

  @override
  String get vcToolsHiddenPasswordLabel => 'Gizli birim parolası';

  @override
  String get vcToolsHiddenConfirmLabel => 'Gizli birim parolasını onayla';

  @override
  String get vcToolsHiddenFsLabel => 'Gizli birim dosya sistemi';

  @override
  String get vcToolsQuickFormat => 'Hızlı biçimlendirme';

  @override
  String get vcToolsCreateHiddenAction => 'Gizli birim oluştur';

  @override
  String get vcToolsHiddenDone => 'Gizli birim oluşturuldu';

  @override
  String get vcToolsHiddenNote =>
      'Gizli birim, dış birimin sonundaki boş alanı kullanır. Sonrasında dış birime her yazdığınızda gizli birim korumasıyla bağlayın, yoksa gizli birimin üzerine yazılabilir.';

  @override
  String get vcToolsPasswordsDiffer => 'Parolalar eşleşmiyor.';

  @override
  String get vcToolsInvalidSize => 'Geçerli bir boyut girin.';

  @override
  String get vcToolsCredentialsRequired =>
      'Birim parolasını girin veya bir anahtar dosyası ekleyin.';

  @override
  String get readOnlyModeLabel => 'Salt okunur mod';

  @override
  String get alwaysOpenReadOnlyLabel => 'Her zaman salt okunur';

  @override
  String get alwaysOpenReadOnlySubtitle => 'Yeni oturumlar salt okunur başlar.';

  @override
  String get changePasswordTitle => 'Parolayı değiştir';

  @override
  String get confirmNewPasswordLabel => 'Yeni parolayı onayla';

  @override
  String get mediaDiagnosticsTitle => 'Medya tanılama';

  @override
  String get textEditorReadOnlyIndicatorLabel => 'Salt okunur';

  @override
  String get textEditorCaretScrubberLabel =>
      'İmleci taşımak için sola veya sağa sürükleyin';

  @override
  String get textEditorFindTooltip => 'Dosyada bul';

  @override
  String get textEditorFindHint => 'Bul';

  @override
  String get textEditorReplaceHint => 'Değiştir';

  @override
  String get textEditorToggleReplaceTooltip => 'Değiştirmeyi aç/kapat';

  @override
  String get textEditorPreviousMatchTooltip => 'Önceki eşleşme';

  @override
  String get textEditorNextMatchTooltip => 'Sonraki eşleşme';

  @override
  String get textEditorCaseSensitiveTooltip => 'Büyük/küçük harf eşleştir';

  @override
  String get textEditorRegexTooltip => 'Düzenli ifade kullan';

  @override
  String get textEditorCloseFindTooltip => 'Bulmayı kapat';

  @override
  String get textEditorNoMatches => 'Sonuç yok';

  @override
  String get textEditorReplaceButton => 'Değiştir';

  @override
  String get textEditorReplaceAllButton => 'Tümünü değiştir';

  @override
  String get textEditorMoreActionsTooltip => 'Diğer eylemler';

  @override
  String get textEditorGoToLineMenuItem => 'Satıra git…';

  @override
  String get textEditorGoToStartMenuItem => 'Başa git';

  @override
  String get textEditorGoToEndMenuItem => 'Sona git';

  @override
  String get textEditorFormatDocumentMenuItem => 'Belgeyi biçimlendir';

  @override
  String get textEditorMinifyJsonMenuItem => 'JSON\'u küçült';

  @override
  String get textEditorFormatFailedMessage =>
      'Bu dosya biçimlendirilemedi -- önce geçerli olduğundan emin olun';

  @override
  String get textEditorGoToLineDialogTitle => 'Satıra git';

  @override
  String get textEditorGoToLineFieldLabel => 'Satır numarası';

  @override
  String textEditorGoToLineHelperText(int maxLine) {
    return '1–$maxLine';
  }

  @override
  String textEditorGoToLineInvalidNumber(int maxLine) {
    return 'Bir satır numarası girin — 1 ile şu değer arasında: $maxLine';
  }

  @override
  String get goToLineButton => 'Git';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe seçildi',
      one: '1 öğe seçildi',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'Tümünü seç';

  @override
  String get deselectAll => 'Tüm seçimi kaldır';

  @override
  String get layoutModeList => 'Liste görünümü';

  @override
  String get layoutModeGrid => 'Izgara görünümü';

  @override
  String get layoutModeMasonry => 'Mozaik görünüm';

  @override
  String get conflictResolutionTitle => 'Dosya çakışması';

  @override
  String get replaceExistingFile => 'Mevcut dosyanın üzerine yaz';

  @override
  String get sortContainersModeManual => 'Elle (sürükleyerek sırala)';

  @override
  String get sortContainersModeUnlockStatus =>
      'Kilit durumu (önce kilidi açık olanlar)';

  @override
  String get sortContainersModeNameAZ => 'Ad (A–Z)';

  @override
  String get sortContainersModeNameZA => 'Ad (Z–A)';

  @override
  String get sortContainersModeNewest => 'Önce en yeni';

  @override
  String get sortContainersModeOldest => 'Önce en eski';

  @override
  String get thumbnailCacheAppCacheLabel => 'Uygulama önbelleği';

  @override
  String get thumbnailCacheAppCacheDesc =>
      'Şifreli olarak uygulama önbelleğinde saklanır. Hızlıdır; depolama baskısında otomatik temizlenir.';

  @override
  String get thumbnailCacheInContainerLabel => 'Kapsayıcı içinde';

  @override
  String get thumbnailCacheInContainerDesc =>
      'Şifreli kapsayıcının içinde saklanır. Kapsayıcının kendisi tarafından korunur ancak yazma daha yavaştır.';

  @override
  String get thumbnailCacheHiddenFolderLabel => 'Gizli klasör';

  @override
  String get thumbnailCacheHiddenFolderDesc =>
      'Kökte gizli bir .thumbcache klasöründe saklanır. Uygulama önbelleğinden farklı olarak otomatik temizlenmez.';

  @override
  String get thumbnailCacheDisabledLabel => 'Devre dışı';

  @override
  String get thumbnailCacheDisabledDesc =>
      'Disk önbelleği yok. Küçük resimler her yüklemede yeniden oluşturulur.';

  @override
  String get unlockContainerTitle => 'Kapsayıcının kilidini aç';

  @override
  String get enableButtonLabel => 'Etkinleştir';

  @override
  String get hiddenVolumeSlotName => 'Gizli birim';

  @override
  String get standardVolumeSlotName => 'Standart birim';

  @override
  String get passwordLabel => 'Parola';

  @override
  String get unlockVaultButtonLabel => 'Kasanın kilidini aç';

  @override
  String get cryfsStorageAccessWarning =>
      'CryFS kasaları binlerce küçük blok dosyası kullanır. Doğrudan depolama erişimi olmadan performans belirgin şekilde yavaş olur.';

  @override
  String get folderVaultStorageAccessWarning =>
      'Doğrudan depolama erişimi devre dışı. Klasör kasalarındaki dosyaları açmak ve okumak daha yavaş olabilir.';

  @override
  String get requestingPermission => 'İzin isteniyor…';

  @override
  String get unlockDriveButton => 'Sürücünün kilidini aç';

  @override
  String get active => 'Etkin';

  @override
  String get selectAllAction => 'Tümünü seç';

  @override
  String get clearSelectionAction => 'Seçimi temizle';

  @override
  String get clearSelectionTooltip => 'Seçimi temizle';

  @override
  String get selectionOptionsTooltip => 'Seçim seçenekleri';

  @override
  String get readOnlyContainerTooltip => 'Salt okunur kapsayıcı';

  @override
  String get copyAction => 'Kopyala';

  @override
  String get moveAction => 'Taşı';

  @override
  String get renameAction => 'Yeniden adlandır';

  @override
  String get exportToDeviceAction => 'Cihaza aktar';

  @override
  String get openWithAppAction => 'Uygulamayla aç';

  @override
  String get shareAction => 'Paylaş';

  @override
  String get pinAction => 'Sabitle';

  @override
  String get pinSelectedAction => 'Seçilenleri sabitle';

  @override
  String get unpinAction => 'Sabitlemeyi kaldır';

  @override
  String get unpinSelectedAction => 'Seçilenlerin sabitlemesini kaldır';

  @override
  String get documentProviderSettingsMenu => 'Belge sağlayıcı ayarları';

  @override
  String get exposeAsDocumentProviderMenu => 'Belge sağlayıcı olarak sun';

  @override
  String get copyTooltip => 'Kopyala';

  @override
  String get searchInThisFolderHint => 'Bu klasörde ara…';

  @override
  String get clearTooltip => 'Temizle';

  @override
  String get backToDashboardTooltip => 'Panoya dön';

  @override
  String get cancelPasteButton => 'Yapıştırmayı iptal et';

  @override
  String get cancelImportButton => 'İçe aktarmayı iptal et';

  @override
  String get continueButton => 'Devam';

  @override
  String get skipButton => 'Atla';

  @override
  String get keepBothButton => 'İkisini de koru';

  @override
  String get clearAllButton => 'Tümünü temizle';

  @override
  String get autoMountWhenUnlocksTitle =>
      'Kapsayıcının kilidi açılınca otomatik bağla';

  @override
  String get autoMountWhenUnlocksSubtitle =>
      'Bu klasörü bir sonraki sefer otomatik olarak yeniden sun';

  @override
  String get unmountButton => 'Bağlantıyı kes';

  @override
  String get filtersMenuItem => 'Filtreler';

  @override
  String get settingsMenuItem => 'Ayarlar';

  @override
  String get sortOptionsTooltip => 'Sıralama seçenekleri';

  @override
  String get layoutOptionsTooltip => 'Düzen seçenekleri';

  @override
  String get lockContainerTooltip => 'Kapsayıcıyı kilitle';

  @override
  String get renameTooltip => 'Yeniden adlandır';

  @override
  String get cancelUpdatingPasswordTooltip => 'Parola güncellemeyi iptal et';

  @override
  String get unlockSettingsButton => 'Kilit ayarları';

  @override
  String get updateSavedCredentialsButton =>
      'Kayıtlı kimlik bilgilerini güncelle';

  @override
  String get verifyCredentialsTitle => 'Kimlik bilgilerini doğrula';

  @override
  String get verifyButton => 'Doğrula';

  @override
  String get displayNameTitle => 'Görünen ad';

  @override
  String get containerNameHint => 'Kapsayıcı adı';

  @override
  String get deleteFileDialogTitle => 'Dosya silinsin mi?';

  @override
  String get deleteFilePermanentWarning =>
      'Bu işlem kalıcıdır ve geri alınamaz.';

  @override
  String get unsavedChangesTitle => 'Kaydedilmemiş değişiklikler';

  @override
  String get unsavedChangesMessage =>
      'Kaydedilmemiş değişiklikleriniz var. Kapatmadan önce kaydetmek ister misiniz?';

  @override
  String get discardButton => 'Vazgeç';

  @override
  String get decryptingFileContent => 'Dosya içeriğinin şifresi çözülüyor...';

  @override
  String get cannotOpenFile => 'Dosya açılamıyor';

  @override
  String get changesSavedSuccessfully => 'Değişiklikler başarıyla kaydedildi';

  @override
  String saveFailedWithError(String error) {
    return 'Kaydedilemedi: $error';
  }

  @override
  String linesCount(int count) {
    return 'Satır: $count';
  }

  @override
  String charsCount(int count) {
    return 'Karakter: $count';
  }

  @override
  String get unsavedChangesLabel => 'Kaydedilmemiş değişiklikler';

  @override
  String get savedToVault => 'Kasaya kaydedildi';

  @override
  String get saveChangesTooltip => 'Değişiklikleri kaydet';

  @override
  String get textEditorDecryptFailedMessage =>
      'Dosyanın şifresi kasadan çözülemedi.';

  @override
  String get textEditorInvalidTextFileMessage =>
      'Dosya geçerli bir metin dosyası gibi görünmüyor.';

  @override
  String get textEditorWriteBackFailedMessage =>
      'Dosya kasaya geri yazılamadı.';

  @override
  String get markdownViewerEditTooltip => 'Düzenle';

  @override
  String get markdownViewerPreviewTooltip => 'Önizleme';

  @override
  String get markdownEmptyPreviewMessage => 'Henüz önizlenecek bir şey yok.';

  @override
  String get backTooltip => 'Geri';

  @override
  String get forwardTooltip => 'İleri';

  @override
  String get reloadTooltip => 'Yeniden yükle';

  @override
  String get optionsTooltip => 'Seçenekler';

  @override
  String get htmlViewerErrorTitle => 'Bu sayfa görüntülenemiyor';

  @override
  String get htmlViewerLoadFailedMessage => 'Dosya yüklenemedi';

  @override
  String get enableJavaScriptDialogTitle => 'JavaScript etkinleştirilsin mi?';

  @override
  String get enableJavaScriptDialogMessage =>
      'Sayfanın kendi yerel betiklerini çalıştırmasına izin verilecek. Yine de ağ erişimi yoktur — bu kasadaki hiçbir şey internet üzerinden gönderilemez veya alınamaz.';

  @override
  String get disableJavaScriptMenu => 'JavaScript\'i devre dışı bırak';

  @override
  String get enableJavaScriptMenu => 'JavaScript\'i etkinleştir';

  @override
  String get enterFullscreenMenu => 'Tam ekrana geç';

  @override
  String get thisFolderMenu => 'Bu klasör';

  @override
  String get allInclSubfoldersMenu => 'Tümü (alt klasörler dahil)';

  @override
  String get disableShuffleMenu => 'Karıştırmayı kapat';

  @override
  String get shufflePlaylistMenu => 'Oynatma listesini karıştır';

  @override
  String get playlistOptionsTooltip => 'Oynatma listesi seçenekleri';

  @override
  String get screenOrientationMenu => 'Ekran yönü';

  @override
  String get playlistTransitionMenu => 'Oynatma listesi geçişi';

  @override
  String get renameFileMenu => 'Dosyayı yeniden adlandır';

  @override
  String get deleteFileMenu => 'Dosyayı sil';

  @override
  String get thumbnailCarouselTooltip => 'Küçük resim şeridi';

  @override
  String get advancedSettingsTooltip => 'Gelişmiş ayarlar';

  @override
  String get previousTooltip => 'Önceki';

  @override
  String get nextTooltip => 'Sonraki';

  @override
  String get diagnosticsCopiedToClipboard =>
      'Tanılama bilgisi panoya kopyalandı';

  @override
  String get closeTooltip => 'Kapat';

  @override
  String get diagnosticsErrorLabel => 'Hata';

  @override
  String get diagnosticsStateBuffering => 'Arabelleğe alınıyor';

  @override
  String get diagnosticsStatePlaying => 'Oynatılıyor';

  @override
  String get diagnosticsStatePaused => 'Duraklatıldı';

  @override
  String get rotate90Label => '90° döndür';

  @override
  String get imageFitModeLabel => 'Resim sığdırma modu';

  @override
  String get slideshowDelayLabel => 'Slayt gösterisi gecikmesi';

  @override
  String get playbackSpeedLabel => 'Oynatma hızı';

  @override
  String get subtitlesLabel => 'Altyazılar';

  @override
  String get playbackSettingsTitle => 'Oynatma ayarları';

  @override
  String get imageFitContain => 'Sığdır';

  @override
  String get imageFitWidth => 'Genişliğe sığdır';

  @override
  String get imageFitHeight => 'Yüksekliğe sığdır';

  @override
  String nSecondsDelay(int n) {
    return '$n saniye';
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
  String get sourceCodeTooltip => 'Kaynak kodu';

  @override
  String get donateTooltip => 'Bağış yap';

  @override
  String get shareAppTooltip => 'Uygulamayı paylaş';

  @override
  String get resetToDefaultsTooltip => 'Varsayılanlara sıfırla';

  @override
  String get staticLabel => 'Statik';

  @override
  String get unmuteTooltip => 'Sesi aç';

  @override
  String get muteTooltip => 'Sesi kapat';

  @override
  String get clearThumbnailCacheDialogTitle =>
      'Küçük resim önbelleği temizlensin mi?';

  @override
  String get clearThumbnailCacheDialogMessage =>
      'Bu işlem bu kasanın önbelleğe alınmış küçük resimlerini siler. Medyaya bir sonraki göz atışınızda yeniden oluşturulurlar.';

  @override
  String get clearCacheButton => 'Önbelleği temizle';

  @override
  String get appCacheClearedUnlockMessage =>
      'Uygulama önbelleği temizlendi. Kapsayıcı içi önbelleği temizlemek için kapsayıcının kilidini açın.';

  @override
  String get allThumbnailCachesClearedMessage =>
      'Tüm küçük resim önbellekleri başarıyla temizlendi.';

  @override
  String get appCacheClearedContainerFailedMessage =>
      'Uygulama önbelleği temizlendi, ancak kapsayıcı içi önbellek temizlenemedi.';

  @override
  String get failedToClearThumbnailCachesMessage =>
      'Küçük resim önbellekleri temizlenemedi.';

  @override
  String get authenticateToModifySettingsPrompt =>
      'Ayarları değiştirmek için kimlik doğrulayın';

  @override
  String get usbVaultSettingsTitle => 'USB kasa ayarları';

  @override
  String get vaultSettingsTitle => 'Kasa ayarları';

  @override
  String get generalSectionHeader => 'Genel';

  @override
  String get securityCredentialsSectionHeader => 'Güvenlik ve kimlik bilgileri';

  @override
  String get securityOptionsLockedTitle => 'Güvenlik seçenekleri kilitli';

  @override
  String get authenticateOriginalCredentialsMessage =>
      'Güvenlik ayarlarını değiştirmek için özgün kapsayıcı kimlik bilgileriyle kimlik doğrulayın.';

  @override
  String get unlockCredentialsLabel => 'Kilit açma kimlik bilgileri';

  @override
  String get unavailableSuffixLabel => '(Kullanılamıyor)';

  @override
  String get patternSetupRequiredBeforeSaving =>
      'Kaydetmeden önce bir desen belirleyin.';

  @override
  String get changePatternButton => 'Deseni değiştir';

  @override
  String get setPatternButton => 'Desen belirle';

  @override
  String get cacheDerivedKeyLabel => 'Türetilmiş anahtarı önbelleğe al';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      'Bir sonraki sefer CryFS\'in scrypt KDF adımını atla (anahtar Android Keystore\'da tutulur)';

  @override
  String get reuseKeyMaterialKeystoreSubtitle =>
      'Android Keystore\'daki anahtar malzemesini yeniden kullan';

  @override
  String nDays(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gün',
      one: '1 gün',
    );
    return '$_temp0';
  }

  @override
  String get cacheDerivedKeyLifetimeTitle => 'Önbellekteki anahtarın ömrü';

  @override
  String get cacheDerivedKeyLifetimeNever => 'Ben kapatana kadar';

  @override
  String cacheDerivedKeyLifetimeExpiresOn(String date) {
    return 'Şu tarihte otomatik kaldırılır: $date';
  }

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle =>
      'Kilit açarken otomatik algılamayı atlamak için algoritmayı sabitle.';

  @override
  String get changeContainerPasswordTitle => 'Kapsayıcı parolasını değiştir';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      'BitLocker kimlik bilgileri uygulama içinde değiştirilemez. Windows\'ta \"BitLocker\'ı Yönet\"i kullanın.';

  @override
  String get systemIntegrationSectionHeader => 'Sistem ve entegrasyon';

  @override
  String get autoLockDurationLabel => 'Otomatik kilit süresi';

  @override
  String get neverAutoLockOption => 'Asla';

  @override
  String get neverAutoLockOptionSubtitle =>
      'Uygulama kilitlense veya ekran kapansa bile açık kalır';

  @override
  String get defaultAutoLockOptionSubtitle =>
      'Uygulamanın otomatik kilit ve ekran kilidi ayarlarını izler';

  @override
  String get exposeContentToFilePickerSubtitle =>
      'Kilit açıkken içeriği sistem dosya seçicisine sun';

  @override
  String get thumbnailStorageSectionHeader => 'Küçük resim depolama';

  @override
  String get cacheModeLabel => 'Önbellek modu';

  @override
  String get useGlobalDefaultSubtitle => 'Genel varsayılanı kullan';

  @override
  String get thumbnailQualityLabel => 'Küçük resim kalitesi';

  @override
  String get clearThumbnailCacheTitle => 'Küçük resim önbelleğini temizle';

  @override
  String get removeCachedThumbnailsSubtitle =>
      'Önbelleğe alınmış resim ve video küçük resimlerini kaldır';

  @override
  String get vaultInformationSectionHeader => 'Kasa bilgileri';

  @override
  String get vaultInformationTileTitle => 'Kasa ayrıntılarını görüntüle';

  @override
  String get vaultInformationTileSubtitle =>
      'Şifre, biçim ve diğer teknik ayrıntılar';

  @override
  String get vaultInfoLocationLabel => 'Konum';

  @override
  String get vaultInfoRequiresUnlockTitle => 'Kilit açma gerekli';

  @override
  String get vaultInfoRequiresUnlockMessage =>
      'Teknik ayrıntıları görmek için bu kasanın kilidini açın.';

  @override
  String get vaultInfoLoadFailedTitle => 'Kasa bilgileri yüklenemedi';

  @override
  String get vaultInfoLoadFailedMessage =>
      'Bu kasanın ayrıntıları okunurken bir şeyler ters gitti.';

  @override
  String get vaultInfoVolumeSizeLabel => 'Birim boyutu';

  @override
  String get vaultInfoFileSystemLabel => 'Dosya sistemi';

  @override
  String get vaultInfoHiddenVolumeLabel => 'Gizli birim';

  @override
  String get vaultInfoReadOnlyLabel => 'Salt okunur';

  @override
  String get vaultInfoLuksVersionLabel => 'LUKS sürümü';

  @override
  String get vaultInfoSectorSizeLabel => 'Sektör boyutu';

  @override
  String get vaultInfoVaultFormatLabel => 'Kasa biçimi';

  @override
  String get vaultInfoCipherComboLabel => 'Şifre birleşimi';

  @override
  String get vaultInfoShorteningThresholdLabel => 'Dosya adı kısaltma eşiği';

  @override
  String get vaultInfoFormatVersionLabel => 'Biçim sürümü';

  @override
  String get vaultInfoContentCipherLabel => 'İçerik şifresi';

  @override
  String get vaultInfoFilenameEncryptionLabel => 'Dosya adları';

  @override
  String get vaultInfoPlaintextNamesValue => 'Düz metin';

  @override
  String get vaultInfoEncryptedNamesValue => 'Şifreli';

  @override
  String get vaultInfoBlockCipherLabel => 'Blok şifresi';

  @override
  String get vaultInfoBlockSizeLabel => 'Blok boyutu';

  @override
  String get vaultInfoCreatedWithVersionLabel => 'Oluşturan sürüm';

  @override
  String get vaultInfoLastOpenedWithVersionLabel => 'Son açan sürüm';

  @override
  String get vaultInfoYesValue => 'Evet';

  @override
  String get vaultInfoNoValue => 'Hayır';

  @override
  String get vaultInfoBitlockerNote =>
      'Bu uygulama BitLocker\'ın kendi başlık meta verilerini ayrıştırmaz, bu yüzden şifre ve sürüm ayrıntıları burada kullanılamaz.';

  @override
  String get patternSetupRequiredAboveBeforeSaving =>
      'Kaydetmeden önce yukarıda bir desen belirleyin.';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      'Bu kilit açma yöntemi için bir parola veya anahtar dosyalarıyla birlikte \"Türetilmiş anahtarı önbelleğe al\" gerekli.';

  @override
  String get saveConfigurationButton => 'Yapılandırmayı kaydet';

  @override
  String get incorrectPatternError => 'Yanlış desen';

  @override
  String get verifyPatternTitle => 'Deseni doğrula';

  @override
  String get incorrectPasswordError => 'Yanlış parola';

  @override
  String get verificationFailedError => 'Doğrulama başarısız';

  @override
  String get incorrectCredentialsError => 'Yanlış kimlik bilgileri';

  @override
  String get containerPasswordOptionalLabel =>
      'Kapsayıcı parolası (yalnızca anahtar dosyası için isteğe bağlı)';

  @override
  String get pimOptionalLabel => 'PIM (isteğe bağlı)';

  @override
  String get usbDriveLockedLabel => 'USB sürücü · Kilitli';

  @override
  String get lockedContainerLabel => 'Kilitli kapsayıcı';

  @override
  String get operationInProgressWaitMessage =>
      'Bir işlem sürüyor. Kilitlemeden önce lütfen bekleyin.';

  @override
  String lockFailedMessage(String errorType) {
    return 'Kilitleme başarısız: $errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired =>
      'Yeni parola veya anahtar dosyaları gerekli.';

  @override
  String get newPasswordsDoNotMatch => 'Yeni parolalar eşleşmiyor.';

  @override
  String get passwordChangedSuccessfullyMessage =>
      'Parola başarıyla değiştirildi.';

  @override
  String get failedToChangePasswordMessage =>
      'Parola değiştirilemedi. Eski kimlik bilgilerini kontrol edin.';

  @override
  String get currentCredentialsSectionHeader => 'Mevcut kimlik bilgileri';

  @override
  String get oldPasswordLabel => 'Eski parola';

  @override
  String get oldPimOptionalLabel => 'Eski PIM (isteğe bağlı)';

  @override
  String get newCredentialsSectionHeader => 'Yeni kimlik bilgileri';

  @override
  String get newPimOptionalLabel => 'Yeni PIM (isteğe bağlı)';

  @override
  String get noContainersYetTitle => 'Henüz kapsayıcı yok';

  @override
  String get dashboardEmptyStateMessage =>
      'Başlamak için bir VeraCrypt kapsayıcısı bağlayın, bir USB sürücü takın veya yepyeni bir şifreli kasa oluşturun.';

  @override
  String get sortFieldName => 'Ad';

  @override
  String get sortFieldSize => 'Boyut';

  @override
  String get sortFieldType => 'Tür';

  @override
  String get sortFieldDate => 'Tarih';

  @override
  String get layoutModeDetailedList => 'Ayrıntılı liste';

  @override
  String get layoutModeCompactList => 'Kompakt liste';

  @override
  String get layoutModeGalleryGrid => 'Galeri ızgarası';

  @override
  String get galleryModeAction => 'Galeri';

  @override
  String get galleryModeTooltip => 'Galeri modu';

  @override
  String get optionsAction => 'Seçenekler';

  @override
  String get optionsActionTooltip => 'Seçenekler';

  @override
  String get dateToday => 'Bugün';

  @override
  String get dateYesterday => 'Dün';

  @override
  String get dateEarlier => 'Daha önce';

  @override
  String get readOnlyCantDeleteTooltip => 'Salt okunur — silinemez';

  @override
  String get readOnlyCantMoveTooltip => 'Salt okunur — taşınamaz';

  @override
  String get readOnlyCantRenameTooltip =>
      'Salt okunur — yeniden adlandırılamaz';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes (hesaplanıyor…)';
  }

  @override
  String get sizeCalculatingLabel => 'hesaplanıyor…';

  @override
  String get editSecureItemsToRenameMessage =>
      'Güvenli öğeleri yeniden adlandırmak için düzenleyin';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage =>
      'Kasa öğeleri harici uygulamalarda açılamaz';

  @override
  String get itemsCannotBeSharedMessage =>
      'Bu öğeler diğer uygulamalarla paylaşılamaz';

  @override
  String get mountedReadOnlyTooltip => 'Salt okunur bağlı';

  @override
  String get readOnlyBadgeAbbreviation => 'SO';

  @override
  String freeSpaceLabel(String bytes) {
    return '$bytes boş';
  }

  @override
  String get filteredLabel => 'filtrelendi';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count klasör',
      one: '1 klasör',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dosya',
      one: '1 dosya',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => 'Tüm dosyalar';

  @override
  String get filterImagesOption => 'Resimler';

  @override
  String get filterVideosOption => 'Videolar';

  @override
  String get filterAudioOption => 'Ses';

  @override
  String get filterDocumentsOption => 'Belgeler';

  @override
  String get folderExposedAsStorageExplanation =>
      'Bu klasör kendi depolama konumu olarak sunulur; böylece diğer uygulamalar dosyalarına doğrudan göz atabilir ve açabilir.';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe zaten var',
      one: '1 öğe zaten var',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle =>
      'Her öğe için ne olacağını seçin veya tek bir seçimi tümüne uygulayın.';

  @override
  String get skipAllChipLabel => 'Tümünü atla';

  @override
  String get overwriteAllChipLabel => 'Tümünün üzerine yaz';

  @override
  String get overwriteItemDropdownLabel => 'Üzerine yaz';

  @override
  String get overwriteFolderDropdownLabel => 'Klasörün üzerine yaz';

  @override
  String get fileOpsTransfersInProgressTitle => 'Süren aktarımlar';

  @override
  String get fileOpsRecentTransfersTitle => 'Son aktarımlar';

  @override
  String get fileOpsNoRecentTransfersMessage => 'Son aktarım yok';

  @override
  String get fileOpsNoRecentTransfersSubtitle =>
      'Kopyalama, taşıma ve silme işlemleri çalışırken burada görünür.';

  @override
  String fileOpsShowDetailsLabel(num count) {
    return 'Ayrıntıları göster';
  }

  @override
  String get fileOpsCancelTooltip => 'İptal';

  @override
  String get fileOpsDismissTooltip => 'Kapat';

  @override
  String get fileOpsCancelledStatusLabel => 'İptal edildi';

  @override
  String fileOpsItemsFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe başarısız:',
      one: '1 öğe başarısız:',
    );
    return '$_temp0';
  }

  @override
  String fileOpsMoreItemsLabel(num count) {
    return '+ $count daha';
  }

  @override
  String get transferActivityTooltip => 'Aktarımlar';

  @override
  String fileOpsSpeedLabel(String speed) {
    return '$speed/s';
  }

  @override
  String fileOpsEtaLabel(String time) {
    return '~$time kaldı';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return 'Dosya okunurken hata: $error';
  }

  @override
  String get archivePreviewNotAvailableMessage =>
      'Bu dosya türü için önizleme kullanılamıyor.';

  @override
  String get avifFailedToRenderMessage => 'AVIF işlenemedi';

  @override
  String get encryptedImageLoadFailedMessage => 'Şifreli resim yüklenemedi';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return 'Şifreli resim yüklenemedi: $error';
  }

  @override
  String get imagePreviewTooLargeMessage => 'Bu resim önizleme için çok büyük';

  @override
  String get imagePreviewOutOfMemoryMessage =>
      'Bu resmi önizlemek için yeterli boş bellek yok. Diğer uygulamaları kapatıp tekrar deneyin.';

  @override
  String get invalidOrCorruptedImageMessage =>
      'Geçersiz veya bozuk resim biçimi.';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '$current / $total';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '$current / $total  ·  taranıyor…';
  }

  @override
  String get mediaViewerScanningLabel => 'Taranıyor…';

  @override
  String get mediaFileDeletedMessage => 'Dosya başarıyla silindi';

  @override
  String get mediaFileDeleteFailedMessage => 'Dosya silinemedi';

  @override
  String get mediaFileRenamedMessage => 'Dosya başarıyla yeniden adlandırıldı';

  @override
  String get aboutScreenTitle => 'Hakkında';

  @override
  String get couldNotOpenLinkMessage => 'Bağlantı açılamadı';

  @override
  String get fileManagerSettingsTitle => 'Dosya yöneticisi ayarları';

  @override
  String get showMediaThumbnailsLabel => 'Medya küçük resimlerini göster';

  @override
  String get showMediaThumbnailsDesc =>
      'Liste görünümünde resim ve videolar için küçük resim önizlemelerini göster';

  @override
  String get showFileNamesLabel => 'Dosya adlarını göster';

  @override
  String get showFileNamesDesc =>
      'Izgara düzeninde öğelerin altında metin etiketlerini göster';

  @override
  String get showBreadcrumbBarLabel => 'Yol çubuğunu göster';

  @override
  String get showBreadcrumbBarDesc =>
      'Tarayıcının üstündeki yol gezinme çubuğu';

  @override
  String get showStatsBarLabel => 'İstatistik çubuğunu göster';

  @override
  String get showStatsBarDesc => 'Dosya sayısı ve boş alan bilgi şeridi';

  @override
  String get autoStartPlaylistModeLabel =>
      'Oynatma listesi modunu otomatik başlat';

  @override
  String get autoStartPlaylistModeDesc =>
      'Bir medya öğesi açılırken otomatik olarak oynatma listesi modunda başla';

  @override
  String get showPlaylistCarouselLabel => 'Oynatma listesi şeridini göster';

  @override
  String get showPlaylistCarouselDesc =>
      'Medya oynatma listelerini görüntülerken küçük resim şeridi düğmesini göster';

  @override
  String get pauseLabel => 'Duraklat';

  @override
  String get playLabel => 'Oynat';

  @override
  String get emptyFolderTitle => 'Boş klasör';

  @override
  String get emptyFolderMessage =>
      'Dosya oluşturmak veya cihazdan içe aktarmak için Ekle eylemini kullanın.';

  @override
  String get noResultsTitle => 'Sonuç yok';

  @override
  String noResultsForQueryMessage(String query) {
    return 'Bu klasörde eşleşen öğe yok: \"$query\".';
  }

  @override
  String get playlistScrollModeMenu => 'Oynatma listesi kaydırma modu';

  @override
  String get playlistScrollHorizontalLabel => 'Yatay';

  @override
  String get playlistScrollVerticalPageLabel => 'Dikey sayfalı';

  @override
  String get playlistScrollVerticalContinuousLabel => 'Dikey sürekli';

  @override
  String get undoTooltip => 'Geri al';

  @override
  String get redoTooltip => 'Yinele';

  @override
  String get autosavingLabel => 'Otomatik kaydediliyor…';

  @override
  String get savingLabel => 'Kaydediliyor…';

  @override
  String autosavedAtLabel(String time) {
    return '$time saatinde otomatik kaydedildi';
  }

  @override
  String cameraDisconnectedError(String message) {
    return 'Kamera bağlantısı kesildi: $message';
  }

  @override
  String get unknownErrorFallback => 'bilinmeyen hata';

  @override
  String get panoramaModeWide => 'Geniş';

  @override
  String get panoramaStitching => 'Panorama birleştiriliyor…';

  @override
  String panoramaShotCount(int count) {
    return 'Çekim: $count';
  }

  @override
  String get panoramaWaitingForMotionSensor => 'Hareket sensörü bekleniyor…';

  @override
  String get panoramaStartSphereHint =>
      'Deklanşöre dokunun, ardından her noktaya yönelin';

  @override
  String get panoramaStartWideHint =>
      'Deklanşöre dokunun, ardından yavaşça kaydırın';

  @override
  String get panoramaHoldStillHint => 'Sabit tutun…';

  @override
  String get panoramaKeepVerticallyAlignedHint => 'Dikey hizayı koruyun';

  @override
  String get panoramaKeepLevelHint => 'Telefonu düz tutun';

  @override
  String get panoramaAimAtDotOrHoldStillHint =>
      'Bir noktaya yönelin (veya çekmek için sabit tutun)';

  @override
  String get panoramaSlowDownHint => 'Yavaşlayın';

  @override
  String get panoramaAimAtDotHint => 'Bir noktaya yönelin';

  @override
  String panoramaFollowLineHint(String done) {
    return 'Çizgiyi izleyin — bitirmek için $done düğmesine dokunun';
  }

  @override
  String get panoramaNoMotionSensorError =>
      'Bu cihazda panoramalar için hareket sensörü yok';

  @override
  String get panoramaRearCameraRequiredError =>
      'Panorama çekimi için arka kamera gerekir';

  @override
  String get panoramaNotEnoughPhotosError =>
      'Yeterli fotoğraf yok. Biraz daha kaydırın.';

  @override
  String get panoramaStitchFailedError => 'Panorama birleştirilemedi';

  @override
  String get cameraPermissionsRequiredMessage =>
      'Kamerayı kullanmak için kamera ve mikrofon izinleri gerekli.';

  @override
  String cameraErrorMessage(String error) {
    return 'Kamera hatası: $error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage => 'Fotoğraf çekilemedi';

  @override
  String get cameraRecordingFailedMessage => 'Kayıt başarısız oldu';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return 'Kayıt başarısız oldu: $error';
  }

  @override
  String get cameraRecordingTooShortMessage =>
      'Kayıt kaydedilemeyecek kadar kısaydı';

  @override
  String get cameraCouldNotSaveRecordingMessage => 'Kayıt kaydedilemedi';

  @override
  String get cameraCouldNotSaveCaptureMessage =>
      'Çekim kaydedilemedi. Yeniden denemek için hâlâ kullanılabilir.';

  @override
  String get cameraNotEnoughVaultSpaceMessage =>
      'Kasada yeterli boş alan yok. Yer açıp tekrar deneyin.';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return 'Kayıt kaydedilemedi: $error';
  }

  @override
  String get aboutApplicationSectionHeader => 'Uygulama';

  @override
  String get aboutTagline => 'Ücretsiz · Açık kaynak · Çevrimdışı şifreli kasa';

  @override
  String get aboutVersionTitle => 'Sürüm';

  @override
  String aboutVersionSubtitle(String version) {
    return 'v$version';
  }

  @override
  String get aboutWhatsNewTitle => 'Yenilikler';

  @override
  String get aboutWhatsNewSubtitle =>
      'Son değişiklikleri ve sürüm notlarını görün';

  @override
  String get aboutPrivacySecurityTitle => 'Gizlilik ve güvenlik';

  @override
  String get aboutPrivacySecuritySubtitle =>
      'Ağ erişimi yok, şifre çözme bellekte gerçekleşir';

  @override
  String get aboutSupportedFormatsSectionHeader => 'Desteklenen biçimler';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt ve LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      'Standart ve gizli birimler, özel PIM, anahtar dosyaları, xts-plain64, Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker ve BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle =>
      'Kullanıcı parolaları ve 48 haneli sayısal kurtarma anahtarı desteği';

  @override
  String get aboutDirectoryVaultsTitle => 'Dizin kasaları';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator (v7/v8 SIV_GCM ve SIV_CTRMAC), gocryptfs (v2 AES-GCM ve XChaCha20), CryFS (v0.10+ XChaCha20 ve AES)';

  @override
  String get aboutVhdTitle => 'Sanal sabit diskler (VHD / VHDX)';

  @override
  String get aboutVhdSubtitle =>
      'Sabit ve dinamik genişleyen disk görüntüleri için BAT çevirisi';

  @override
  String get aboutNativeCoreEngineSectionHeader => 'Yerel çekirdek motor';

  @override
  String get aboutCompiledLibrariesTitle => 'Derlenmiş C++ kütüphaneleri';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.7 (ARMv8 donanım kriptosu ve SHA-2)\n• libavif ve libgav1 (yerel AVIF resim çözücü)\n• libarchive v3.8.9 (ZIP, 7-Zip, RAR ve TAR arşiv motoru)\n• ChaN FatFs v4.0.4 (FAT12/16/32 ve exFAT)\n• Tuxera NTFS-3G ve gömülü mkntfs\n• e2fsprogs v1.47.4 libext2fs (ext2/ext3/ext4)\n• Dislocker Virtual I/O (BitLocker FVE / To Go)\n• VeraCrypt 1.26.29 (Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id/i)\n• cJSON v1.7.18 (LUKS2 ve Cryptomator meta verileri)';

  @override
  String get aboutCommunitySectionHeader => 'Topluluk ve açık kaynak';

  @override
  String get aboutReportIssueTitle => 'Sorun bildir';

  @override
  String get aboutReportIssueSubtitle =>
      'Bir hata mı buldunuz? GitHub\'da bir kayıt açın';

  @override
  String get reportIssueSheetTitle => 'Sorun bildir';

  @override
  String get reportIssueSheetSubtitle =>
      'Sorununuza en uygun seçeneği seçin — önceden doldurulmuş bir GitHub formu açılır';

  @override
  String get reportIssueBugTitle => 'Hata bildirimi';

  @override
  String get reportIssueBugSubtitle => 'Bir şey çöktü veya düzgün çalışmıyor';

  @override
  String get reportIssueContainerTitle => 'Kapsayıcı / kasa sorunu';

  @override
  String get reportIssueContainerSubtitle =>
      'Kilit açma, bağlama veya biçime özgü sorun';

  @override
  String get reportIssueFeatureTitle => 'Özellik isteği';

  @override
  String get reportIssueFeatureSubtitle => 'Bir fikir veya iyileştirme önerin';

  @override
  String get reportIssueOtherTitle => 'Başka bir şey';

  @override
  String get reportIssueOtherSubtitle => 'GitHub\'daki tüm şablonlara göz atın';

  @override
  String get aboutContributorsTitle => 'Katkıda bulunanlar';

  @override
  String get aboutContributorsSubtitle =>
      'VaultExplorer\'ın geliştirilmesine yardım edenler';

  @override
  String get aboutLicensesTitle => 'Açık kaynak lisansları';

  @override
  String get aboutLicensesSubtitle =>
      'Bu uygulamada kullanılan üçüncü taraf kütüphaneler';

  @override
  String get aboutFooterMadeWithLove => 'Gizlilik için ❤ ile yapıldı.';

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer — Android için ücretsiz, açık kaynaklı, çevrimdışı bir kasa.\n\nParolalarını, notlarını ve dosyalarını şifreli bir kapsayıcıda sakla (VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs, CryFS).\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage =>
      'Paylaşılabilir bağlantı panonuza kopyalandı';

  @override
  String get aboutPrivacySheetTitle => 'Gizlilik ve veri güvenliği';

  @override
  String get aboutPrivacySheetSubtitle =>
      '%100 çevrimdışı, yerel bellek güvenliği tasarımı';

  @override
  String get privacyPointNoNetworkTitle => 'Ağ erişimi gerekmez';

  @override
  String get privacyPointNoNetworkBody =>
      'VaultExplorer, Android\'de android.permission.INTERNET iznini istemez. Hiçbir ağ üzerinden iletişim kuramaz.';

  @override
  String get privacyPointNoDiskLeaksTitle => 'Bellekte şifresi çözülür';

  @override
  String get privacyPointNoDiskLeaksBody =>
      'Şifre çözme ve yeniden şifreleme sistem belleğinde gerçekleşir. Video kaydı veya dışa aktarma gibi geçici dosya gerektiren az sayıdaki işlem, bu dosyayı özel uygulama depolamasında tutar ve iş bitince sıfırlarla ezer.';

  @override
  String get privacyPointNoAnalyticsTitle => 'Analiz veya telemetri yok';

  @override
  String get privacyPointNoAnalyticsBody =>
      'Sizin veya cihazınız hakkında veri toplayan hiçbir çökme raporlama, kullanım takibi veya üçüncü taraf SDK yoktur.';

  @override
  String get privacyPointKeystoreTitle => 'Sırlar Android Keystore\'da kalır';

  @override
  String get privacyPointKeystoreBody =>
      'Hatırlanan parolalar, desenler ve önbelleğe alınmış türetilmiş anahtarlar, Android Keystore\'da tutulan bir anahtarla (desteklenen yerlerde donanım destekli) AES-GCM ile şifrelenir.';

  @override
  String get privacyPointPosixTitle => 'POSIX hızlandırma ve depolama erişimi';

  @override
  String get privacyPointPosixBody =>
      'Dizin kasalarındaki dosyalar mümkün olduğunda doğrudan okunur ve yazılır; büyük klasörlerde Android\'in daha yavaş SAF katmanı atlanır.';

  @override
  String get privacyPointScreenClipboardTitle => 'Ekran ve pano koruması';

  @override
  String get privacyPointScreenClipboardBody =>
      'Görev değiştirici önizleme engelleme, isteğe bağlı ekran görüntüsü engelleme (FLAG_SECURE) ve pencere odağında otomatik bozuk pano temizleme. Öğe Kasası\'ndan kopyalanan parolalar Android 13+\'ta hassas olarak işaretlenir ve dokunulmazsa 30 saniye sonra otomatik temizlenir.';

  @override
  String get privacyPointMaskModeTitle => 'Maske modu';

  @override
  String get privacyPointMaskModeBody =>
      'İsteğe bağlı olarak uygulamayı farklı bir simge ve adla çalışan bir yerel dosya yöneticisi gibi gizler. Gerçek kasanıza ulaşmak için başlığı 2 saniye basılı tutun.';

  @override
  String get privacyPointExternalLinksTitle =>
      'Harici bağlantılar tarayıcıda açılır';

  @override
  String get privacyPointExternalLinksBody =>
      'Bağlantılara dokunmak, isteği yöneten varsayılan tarayıcı uygulamanıza devredilir.';

  @override
  String get truncatedListingWarning =>
      'İlk 50.000 öğe gösteriliyor — bu klasörde daha fazla dosya var.';

  @override
  String get gridCornerStyleLabel => 'Küçük resim köşeleri';

  @override
  String get gridCornerRoundedLabel => 'Yuvarlak';

  @override
  String get gridCornerSquareLabel => 'Kare';

  @override
  String get gridSpacingLabel => 'Küçük resim aralığı';

  @override
  String get gridSpacingNone => 'Yok';

  @override
  String gridSpacingValue(int value) {
    return '$value dp';
  }

  @override
  String get thumbnailAutoSizeLabel => 'Izgara hücre boyutuna uydur';

  @override
  String get thumbnailAutoSizeDescription =>
      'Izgara ve mozaik küçük resimleri her hücrenin ekrandaki boyutunda oluşturulur; böylece daha az sütun daha keskin küçük resim verir. Aşağıdaki boyut diğer her yerde kullanılır.';

  @override
  String thumbnailQualityAutoSummary(int quality) {
    return 'Otomatik boyut · $quality% kalite';
  }

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '$size px · $quality% kalite';
  }

  @override
  String get toolbarLayoutSectionHeader => 'Araç çubuğu düzeni';

  @override
  String get listViewOptionsSectionHeader => 'Liste görünümü seçenekleri';

  @override
  String get detailedListViewColumnsSectionHeader =>
      'Ayrıntılı liste görünümü sütunları';

  @override
  String get galleryGridViewSectionHeader => 'Galeri ızgara görünümü';

  @override
  String get browserLayoutSectionHeader => 'Tarayıcı düzeni';

  @override
  String get mediaViewerSectionHeader => 'Medya görüntüleyici';

  @override
  String get viewModeAction => 'Görünüm modu';

  @override
  String get sortAction => 'Sırala';

  @override
  String get playMediaAction => 'Medyayı oynat';

  @override
  String get libraryTabAlbums => 'Albümler';

  @override
  String get libraryTabArtists => 'Sanatçılar';

  @override
  String get libraryTabGenres => 'Türler';

  @override
  String get libraryTabTracks => 'Parçalar';

  @override
  String get libraryTabFolders => 'Klasörler';

  @override
  String get nowPlayingQueue => 'Sıra';

  @override
  String get nowPlayingShuffle => 'Karıştır';

  @override
  String get nowPlayingRepeatOff => 'Tekrar kapalı';

  @override
  String get nowPlayingRepeatAll => 'Tümünü tekrarla';

  @override
  String get nowPlayingRepeatOne => 'Bu parçayı tekrarla';

  @override
  String get nowPlayingOpenViewer => 'Medya oynatıcıda aç';

  @override
  String get nowPlayingCollapse => 'Oynatıcıyı küçült';

  @override
  String libraryFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count klasör',
      one: '1 klasör',
    );
    return '$_temp0';
  }

  @override
  String get librarySearchHint => 'Müzik ara';

  @override
  String libraryScanListing(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'şimdiye kadar $count ses dosyası',
      one: 'şimdiye kadar 1 ses dosyası',
    );
    return 'Klasörlere bakılıyor... $_temp0';
  }

  @override
  String libraryScanReading(int read, int total) {
    return 'Etiketler okunuyor... $read / $total';
  }

  @override
  String get libraryScanStop => 'Durdur';

  @override
  String get libraryEmptyTitle => 'Müzik bulunamadı';

  @override
  String get libraryEmptyMessage =>
      'Bu kasada ses dosyası yok ya da dosyalar okunamayan klasörlerde.';

  @override
  String get libraryNoResults => 'Aramanızla eşleşen bir şey yok';

  @override
  String get libraryUnknownArtist => 'Bilinmeyen sanatçı';

  @override
  String get libraryUnknownAlbum => 'Bilinmeyen albüm';

  @override
  String get libraryUnknownGenre => 'Bilinmeyen tür';

  @override
  String get libraryVariousArtists => 'Çeşitli sanatçılar';

  @override
  String libraryTrackCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count parça',
      one: '1 parça',
    );
    return '$_temp0';
  }

  @override
  String libraryAlbumCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count albüm',
      one: '1 albüm',
    );
    return '$_temp0';
  }

  @override
  String get libraryPlayAll => 'Oynat';

  @override
  String get libraryShuffleAll => 'Karıştır';

  @override
  String get libraryMenuRescan => 'Değişiklikleri tara';

  @override
  String get libraryMenuRebuild => 'Tüm etiketleri yeniden oku';

  @override
  String get libraryMenuDeleteSaved => 'Kayıtlı dizini sil';

  @override
  String get libraryMenuDeleteSavedDone => 'Kayıtlı dizin silindi';

  @override
  String get libraryIncompleteNote =>
      'Bazı klasörler okunamadı, bu yüzden kaldırılmış olabilecek dosyalar hâlâ listeleniyor.';

  @override
  String libraryReadFailuresNote(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dosya okunamadı',
      one: '1 dosya okunamadı',
    );
    return '$_temp0';
  }

  @override
  String get libraryArtistAlbumsHeader => 'Albümler';

  @override
  String get libraryArtistTracksHeader => 'Parçalar';

  @override
  String get librarySortTooltip => 'Sırala';

  @override
  String get librarySortTitle => 'Başlık';

  @override
  String get librarySortArtist => 'Sanatçı';

  @override
  String get librarySortAlbum => 'Albüm';

  @override
  String get librarySortYear => 'Yıl';

  @override
  String get librarySortRecentlyAdded => 'Son eklenen';

  @override
  String get librarySortName => 'Ad';

  @override
  String get librarySortTrackCount => 'Parça sayısı';

  @override
  String get librarySortLength => 'Uzunluk';

  @override
  String get librarySortReverse => 'Ters sıra';

  @override
  String get musicModeAction => 'Müzik modu';

  @override
  String get musicModeFiles => 'Dosyalar';

  @override
  String get musicModeMenuFolders => 'Müzik klasörleri';

  @override
  String get musicModeMenuTurnOff => 'Müzik modunu kapat';

  @override
  String get libraryStorageInVault => 'Dizin bu kasanın içine kaydedildi';

  @override
  String get libraryStorageThisDevice =>
      'Dizin bu cihaza şifreli olarak kaydedildi';

  @override
  String get musicScopeTitle => 'Müzik modu';

  @override
  String get musicScopeMessage => 'Müzik modunun neleri kapsayacağını seçin.';

  @override
  String get musicScopeAll => 'Bu konumdaki her şey';

  @override
  String get musicScopeAllHint =>
      'Her klasöre bakar. Büyük konumlarda daha yavaştır.';

  @override
  String get musicScopeChoose => 'Yalnızca bazı klasörler';

  @override
  String get musicScopeAddFolder => 'Klasör ekle';

  @override
  String get musicScopeNoFolders => 'Henüz klasör seçilmedi';

  @override
  String get musicScopeStart => 'Başlat';

  @override
  String get musicScopePickerAdd => 'Bu klasörü ekle';

  @override
  String get musicScopePickerEmpty => 'Burada alt klasör yok';

  @override
  String get musicScopePickerRoot => 'En üst düzey';

  @override
  String get musicScopeRemoveFolder => 'Klasörü kaldır';

  @override
  String libraryArtistCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sanatçı',
      one: '1 sanatçı',
    );
    return '$_temp0';
  }

  @override
  String libraryGenreCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tür',
      one: '1 tür',
    );
    return '$_temp0';
  }

  @override
  String musicPlayPartialNote(num count, String source) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count parça',
      one: '1 parça',
    );
    return '$source konumundan $_temp0 oynatılıyor. Bu listenin geri kalanı başka konumlarda.';
  }

  @override
  String get musicCoverChoose => 'Kapak resmi seç';

  @override
  String get musicCoverRemove => 'Özel kapağı kaldır';

  @override
  String get musicCoverFailed => 'Bu resim kapak olarak kullanılamadı';

  @override
  String get musicMiniPrevious => 'Önceki';

  @override
  String get musicMiniNext => 'Sonraki';

  @override
  String get musicMiniPlay => 'Oynat';

  @override
  String get musicMiniPause => 'Duraklat';

  @override
  String get musicMiniStop => 'Oynatmayı durdur';

  @override
  String containerSpaceSummary(String free, String total) {
    return '$free boş / $total';
  }

  @override
  String volMountedSummary(int volId) {
    return 'Birim $volId · Bağlı';
  }

  @override
  String driveUsableCapacity(int mb) {
    return 'Sürücünün kullanılabilir kapasitesi: $mb MB. Bunu aşmamalıdır.';
  }

  @override
  String get unlockMethodManualPassword => 'Elle parola';

  @override
  String get unlockMethodRememberPassword => 'Parolayı hatırla';

  @override
  String get unlockMethodBiometrics => 'Biyometrik kilit açma';

  @override
  String get unlockMethodPattern => 'Desenle kilit açma';

  @override
  String get unlockMethodPin => 'PIN ile kilit açma';

  @override
  String get unlockMethodSubtitlePassword => 'Her seferinde parolayı yazın';

  @override
  String get unlockMethodSubtitleRememberPassword =>
      'Android Keystore\'da güvenle saklanır';

  @override
  String get unlockMethodSubtitleBiometrics =>
      'Kilidi açmak için parmak izi veya yüz kullanın';

  @override
  String get unlockMethodSubtitlePattern => 'Kilidi açmak için bir desen çizin';

  @override
  String get unlockMethodSubtitlePin => 'Kilidi açmak için bir PIN girin';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError =>
      'Video çözücü kullanılamıyor — donanım codec çakışması';

  @override
  String get mediaStreamInitFailedError => 'Medya akışı başlatılamadı';

  @override
  String get invalidAvifImage => 'Geçersiz AVIF resmi';

  @override
  String get verbImport => 'İçe aktar';

  @override
  String get verbExport => 'Dışa aktar';

  @override
  String get verbMove => 'Taşı';

  @override
  String get verbCopy => 'Kopyala';

  @override
  String get verbDelete => 'Sil';

  @override
  String get verbImported => 'içe aktarıldı';

  @override
  String get verbExported => 'dışa aktarıldı';

  @override
  String get verbMoved => 'taşındı';

  @override
  String get verbCopied => 'kopyalandı';

  @override
  String get verbDeleted => 'silindi';

  @override
  String get verbImporting => 'İçe aktarılıyor';

  @override
  String get verbExporting => 'Dışa aktarılıyor';

  @override
  String get verbMoving => 'Taşınıyor';

  @override
  String get verbCopying => 'Kopyalanıyor';

  @override
  String get verbDeleting => 'Siliniyor';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe',
      one: '1 öğe',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe $verb',
      one: '1 öğe $verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return '$count atlandı';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return '$count başarısız';
  }

  @override
  String get statusCancelled => 'İptal edildi';

  @override
  String get statusFailed => 'Başarısız';

  @override
  String get statusCompleted => 'Tamamlandı';

  @override
  String get fileOpCheckingSpace => 'Kullanılabilir alan denetleniyor…';

  @override
  String get fileOpResolvingConflicts => 'Çakışmalar çözülüyor…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return 'Yeterli alan yok — gereken: $required, yalnızca $free boş';
  }

  @override
  String get fileOpDiskFullPartialRemoved =>
      'Disk dolu — kısmi dosyalar kaldırıldı';

  @override
  String get fileOpMoveFailed => 'Taşıma başarısız';

  @override
  String get fileOpCopyFailed => 'Kopyalama başarısız';

  @override
  String get fileOpDeleteFailed => 'Silme başarısız';

  @override
  String get fileOpDiskFull => 'Disk dolu';

  @override
  String get fileOpImporting => 'İçe aktarılıyor…';

  @override
  String get fileOpExporting => 'Dışa aktarılıyor…';

  @override
  String fileOpImportingName(String name) {
    return 'İçe aktarılıyor: $name…';
  }

  @override
  String fileOpExportingName(String name) {
    return 'Dışa aktarılıyor: $name…';
  }

  @override
  String fileOpMovingName(String name) {
    return 'Taşınıyor: $name…';
  }

  @override
  String fileOpCopyingName(String name) {
    return 'Kopyalanıyor: $name…';
  }

  @override
  String get fileOpDeleting => 'Siliniyor…';

  @override
  String fileOpDeletingName(String name) {
    return 'Siliniyor: $name…';
  }

  @override
  String fileOpDeletedSoFar(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe kaldırıldı',
      one: '1 öğe kaldırıldı',
    );
    return '$_temp0';
  }

  @override
  String get searchInSubfoldersHint => 'Tüm alt klasörlerde ara…';

  @override
  String get deepSearchEnabledTooltip =>
      'Alt klasörlerde aranıyor — yalnızca geçerli klasör için dokunun';

  @override
  String get deepSearchDisabledTooltip =>
      'Geçerli klasörde aranıyor — alt klasörlerde aramak için dokunun';

  @override
  String get filterAction => 'Filtre';

  @override
  String get bookmarkAction => 'Yer imi ekle';

  @override
  String get unbookmarkAction => 'Yer imini kaldır';

  @override
  String get bookmarkSelectedAction => 'Seçilenlere yer imi ekle';

  @override
  String get unbookmarkSelectedAction => 'Seçilenlerin yer imini kaldır';

  @override
  String bookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Yer imi eklendi: $count öğe',
      one: 'Yer imi eklendi: 1 öğe',
    );
    return '$_temp0';
  }

  @override
  String unbookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Yer imi kaldırıldı: $count öğe',
      one: 'Yer imi kaldırıldı: 1 öğe',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => 'Yer imi çubuğunu göster';

  @override
  String get showBookmarkBarDesc =>
      'Yer imli öğeleri bir yer imi çubuğunda veya kenar çubuğunda göster';

  @override
  String get bookmarkBarSectionHeader => 'Yer imi çubuğu';

  @override
  String get noBookmarksYet => 'Henüz yer imi eklenmiş öğe yok';

  @override
  String get reorderBookmarksTitle => 'Yer imlerini yeniden düzenle';

  @override
  String get drawerBookmarksSectionTitle => 'Yer imleri';

  @override
  String get openAction => 'Aç';

  @override
  String get bookmarkTargetMissing => 'Yer imli öğe artık yok';

  @override
  String get navBarVaultsLabel => 'Kasalar';

  @override
  String get navBarToolsLabel => 'Araçlar';

  @override
  String get toolsScreenTitle => 'Araçlar';

  @override
  String get toolsSearchHint => 'Araçlarda ara…';

  @override
  String get toolsSectionContainerUtilities => 'Kapsayıcı araçları';

  @override
  String get toolsSectionFileCryptography => 'Dosya kriptografisi';

  @override
  String get toolsSectionStorageDiagnostics => 'Depolama ve tanılama';

  @override
  String get toolContainerSplitterTitle => 'Böl ve birleştir';

  @override
  String get toolContainerSplitterSubtitle =>
      'Bir kapsayıcıyı parçalara bölün veya yeniden birleştirin';

  @override
  String get toolContainerRepairTitle => 'Denetle ve onar';

  @override
  String get toolContainerRepairSubtitle => 'Kasa sorunlarını teşhis et';

  @override
  String get toolSingleFileCryptoTitle => 'Dosyaları şifrele / şifresini çöz';

  @override
  String get toolSingleFileCryptoSubtitle =>
      'Tam bir kapsayıcı olmadan bir veya daha fazla dosyayı koruyun';

  @override
  String get toolStorageAnalyzerTitle => 'Depolama çözümleyici';

  @override
  String get toolStorageAnalyzerSubtitle =>
      'Yerel Depolama\'da veya bağlı bir kasada neyin yer kapladığını görün';

  @override
  String get toolDuplicateFinderTitle => 'Yinelenen dosya bulucu';

  @override
  String get toolDuplicateFinderSubtitle =>
      'Bayt bayt aynı olan yinelenen dosyaları bul ve kaldır';

  @override
  String get toolHashVerifierTitle =>
      'Dosya sağlama toplamı ve özet doğrulayıcı';

  @override
  String get toolHashVerifierSubtitle =>
      'MD5/SHA sağlama toplamlarıyla büyük dosyaların bozulmadığını doğrulayın';

  @override
  String get hashVerifierModeCompute => 'Hesapla';

  @override
  String get hashVerifierModeVerify => 'Doğrula';

  @override
  String get hashVerifierSelectSourceTitle => 'Dosya kaynağını seçin';

  @override
  String get hashVerifierAlgorithmsLabel => 'Algoritmalar';

  @override
  String get hashVerifierNoAlgorithmSelected => 'En az bir algoritma seçin';

  @override
  String get hashVerifierFilesLabel => 'Özeti alınacak dosyalar';

  @override
  String hashVerifierFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dosya seçildi',
      one: '1 dosya seçildi',
      zero: 'Dosya seçilmedi',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierComputeButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hesapla: $count özet',
      one: 'Özet hesapla',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCancelButton => 'İptal';

  @override
  String hashVerifierBatchProgressLabel(Object current, Object total) {
    return 'Dosya $current / $total';
  }

  @override
  String get hashVerifierCancelledMessage => 'İptal edildi.';

  @override
  String hashVerifierComputeErrorsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dosyanın özeti hesaplanamadı',
      one: '1 dosyanın özeti hesaplanamadı',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCopiedMessage => 'Panoya kopyalandı';

  @override
  String get hashVerifierExportManifestButton => 'Manifest olarak dışa aktar';

  @override
  String get hashVerifierExportAlgorithmLabel => 'Manifest algoritması';

  @override
  String hashVerifierExportSuccessMessage(Object path) {
    return 'Şuraya kaydedildi: $path';
  }

  @override
  String hashVerifierExportFailedMessage(Object error) {
    return 'Dışa aktarma başarısız: $error';
  }

  @override
  String get hashVerifierLoadManifestButton => 'Manifest yükle';

  @override
  String get hashVerifierChangeManifestButton => 'Değiştir';

  @override
  String get hashVerifierManifestLabel => 'Manifest dosyası';

  @override
  String hashVerifierManifestEntryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kayıt',
      one: '1 kayıt',
      zero: 'Kayıt yok',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierAutoAddFolderButton =>
      'Bu klasördeki tüm dosyaları ekle';

  @override
  String get hashVerifierAddFilesToVerifyButton =>
      'Doğrulanacak dosyaları ekle';

  @override
  String get hashVerifierVerifyAllButton => 'Tümünü doğrula';

  @override
  String hashVerifierVerifyProgressLabel(Object current, Object total) {
    return 'Dosya doğrulanıyor: $current / $total';
  }

  @override
  String hashVerifierSummaryMessage(
    Object ok,
    Object mismatch,
    Object missing,
  ) {
    return '$ok eşleşti, $mismatch eşleşmedi, $missing eksik';
  }

  @override
  String get hashVerifierStatusMatch => 'Eşleşti';

  @override
  String get hashVerifierStatusMismatch => 'Eşleşmedi';

  @override
  String get hashVerifierStatusMissing => 'Dosya eklenmedi';

  @override
  String get hashVerifierStatusPending => 'Henüz doğrulanmadı';

  @override
  String get hashVerifierExpectedLabel => 'Beklenen';

  @override
  String get hashVerifierActualLabel => 'Gerçek';

  @override
  String hashVerifierExtraFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fazladan dosya manifestte listelenmiyor',
      one: '1 fazladan dosya manifestte listelenmiyor',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierNoManifestLoadedMessage =>
      'Başlamak için bir manifest dosyası yükleyin';

  @override
  String get hashVerifierManifestParseEmptyMessage =>
      'Bu dosyada sağlama toplamı kaydı bulunamadı';

  @override
  String hashVerifierLoadManifestFailedMessage(Object error) {
    return 'Manifest okunamadı: $error';
  }

  @override
  String hashVerifierAutoAddedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eklendi: $count dosya (kasa klasöründen)',
      one: 'Eklendi: 1 dosya (kasa klasöründen)',
      zero: 'Yeni dosya bulunamadı',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierModeVault => 'Kasa';

  @override
  String get hashVerifierVaultPickerLabel => 'Kasa';

  @override
  String get hashVerifierVaultNoVaultsMessage => 'Şu anda bağlı kasa yok';

  @override
  String get hashVerifierCheckEntireVaultButton => 'Tüm kasayı denetle';

  @override
  String get hashVerifierVaultScanningLabel => 'Kasa taranıyor…';

  @override
  String hashVerifierVaultFilesDiscoveredLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dosya bulundu',
      one: '1 dosya bulundu',
      zero: 'Henüz dosya bulunmadı',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmTitle => 'Tüm kasa denetlensin mi?';

  @override
  String hashVerifierVaultConfirmFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dosya',
      one: '1 dosya',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultStartButton => 'Denetimi başlat';

  @override
  String hashVerifierVaultHashingProgressLabel(Object current, Object total) {
    return 'Denetleniyor: $current / $total';
  }

  @override
  String get hashVerifierVaultCompleteTitle => 'Kasa denetimi tamamlandı';

  @override
  String hashVerifierVaultCompleteFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dosya denetlendi',
      one: '1 dosya denetlendi',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteBytesLabel(Object size) {
    return '$size işlendi';
  }

  @override
  String hashVerifierVaultCompleteSucceededLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count başarılı',
      one: '1 başarılı',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count başarısız',
      one: '1 başarısız',
      zero: '0 başarısız',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultElapsedLabel(Object time) {
    return 'Geçen süre: $time';
  }

  @override
  String get hashVerifierVaultCancelledMessage => 'Kasa denetimi iptal edildi.';

  @override
  String hashVerifierVaultFailedMessage(Object error) {
    return 'Kasa denetimi başarısız: $error';
  }

  @override
  String get hashVerifierVaultNewCheckButton => 'Yeni denetim';

  @override
  String get hashVerifierVaultActionComputeTitle =>
      'Tüm kasanın özetini hesapla';

  @override
  String get hashVerifierVaultActionComputeSubtitle =>
      'Bir kasadaki her dosyanın özetini al';

  @override
  String get hashVerifierVaultActionVerifyTitle => 'Tüm kasayı doğrula';

  @override
  String get hashVerifierVaultActionVerifySubtitle =>
      'Bir kasadaki her dosyayı yüklü bir manifeste göre denetle';

  @override
  String get hashVerifierVaultVerifyButton => 'Tüm kasayı doğrula';

  @override
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage =>
      'Tüm bir kasayı doğrulamak için bir kasanın içinden yüklenmiş manifest gerekir.';

  @override
  String get duplicateFinderTargetLabel => 'Hedef kasa';

  @override
  String get duplicateFinderTargetAllVaults => 'Tüm açık kasalar';

  @override
  String get duplicateFinderStartScan => 'Taramayı başlat';

  @override
  String get duplicateFinderCancelScan => 'Taramayı iptal et';

  @override
  String get duplicateFinderRescan => 'Yeniden tara';

  @override
  String get duplicateFinderScanningStage1 =>
      '1. Aşama: Dizinleme ve boyuta göre gruplama...';

  @override
  String get duplicateFinderScanningStage2 =>
      '2. Aşama: Kısmi dosya başlıkları denetleniyor...';

  @override
  String get duplicateFinderScanningStage3 =>
      '3. Aşama: Tam bayt özetleri doğrulanıyor...';

  @override
  String get duplicateFinderNoDuplicatesTitle => 'Yinelenen dosya bulunamadı';

  @override
  String get duplicateFinderNoDuplicatesMessage =>
      'Taranan kasalardaki tüm dosyaların bayt içerikleri benzersiz.';

  @override
  String get duplicateFinderSelectRedundant => 'Gereksizleri seç';

  @override
  String get duplicateFinderSelectAll => 'Tümünü seç';

  @override
  String get duplicateFinderDeselectAll => 'Tüm seçimi kaldır';

  @override
  String get duplicateFinderOriginalLabel => 'Orijinal';

  @override
  String get duplicateFinderDuplicateLabel => 'Yinelenen';

  @override
  String get duplicateFinderConfirmDeleteTitle =>
      'Yinelenen dosyalar silinsin mi?';

  @override
  String get duplicateFinderSearchHint =>
      'Yinelenenleri dosya adı veya yola göre ara...';

  @override
  String get toolNotImplementedYetMessage =>
      'Bu araç henüz yerel motora bağlanmadı — gelecekteki bir güncellemeyi bekleyin.';

  @override
  String get splitJoinModeSplit => 'Böl';

  @override
  String get splitJoinModeJoin => 'Birleştir';

  @override
  String get splitSourceFileLabel => 'Kaynak dosya';

  @override
  String get splitDestinationFolderLabel => 'Hedef klasör';

  @override
  String get splitChunkSizeLabel => 'Parça boyutu';

  @override
  String get splitChunkSizeCustomLabel => 'Özel boyut (MB)';

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
  String get splitChunkSizeCustom => 'Özel';

  @override
  String get splitContainerButton => 'Kapsayıcıyı böl';

  @override
  String get joinFirstPartLabel => 'İlk parça';

  @override
  String get joinOutputFileNameLabel => 'Çıktı dosya adı';

  @override
  String get joinContainerButton => 'Dosyaları birleştir';

  @override
  String get chooseFileButton => 'Dosya seç';

  @override
  String get chooseFolderButton => 'Klasör seç';

  @override
  String get noFileSelectedLabel => 'Dosya seçilmedi';

  @override
  String get noFolderSelectedLabel => 'Klasör seçilmedi';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage => 'Kapsayıcı başarıyla bölündü';

  @override
  String get joinContainerSuccessMessage => 'Dosyalar başarıyla birleştirildi';

  @override
  String get cryptoDirectionEncrypt => 'Şifrele';

  @override
  String get cryptoDirectionDecrypt => 'Şifresini çöz';

  @override
  String get singleFileCryptoInputFileLabel => 'Girdi dosyaları';

  @override
  String get singleFileCryptoCipherLabel => 'Şifre';

  @override
  String get singleFileCryptoDeleteOriginalLabel =>
      'Şifrelemeden sonra orijinal dosyaları sil';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Şifrele: $count dosya',
      one: 'Dosyayı şifrele',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Şifresini çöz: $count dosya',
      one: 'Dosyanın şifresini çöz',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bitti: $count dosya işlendi',
      one: 'Bitti',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return '$succeeded / $total dosya işlendi — $failed başarısız';
  }

  @override
  String get singleFileCryptoAddFilesButton => 'Dosya ekle';

  @override
  String get singleFileCryptoClearFilesButton => 'Temizle';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dosya seçildi',
      one: '1 dosya seçildi',
      zero: 'Dosya seçilmedi',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return 'Dosya $current / $total';
  }

  @override
  String get repairTargetStepTitle => 'Bir hedef seçin';

  @override
  String get repairTargetUnmountedFileOption => 'Bağlı olmayan dosya';

  @override
  String get repairTargetUnmountedFileSubtitle =>
      'Açmadığınız bir kapsayıcıdaki yedek başlığı geri yükleyin';

  @override
  String get repairTargetMountedVolumeSubtitle =>
      'Zaten açık bir kasada dosya sistemi denetimi çalıştırın';

  @override
  String get repairNoMountedVolumes => 'Şu anda bağlı kasa yok';

  @override
  String get repairScanButton => 'Tanılama taraması çalıştır';

  @override
  String get repairChangeTargetButton => 'Hedefi değiştir';

  @override
  String get repairDiagnosisHealthy => 'Sorun bulunamadı';

  @override
  String get repairDiagnosisHeaderCorrupted => 'Başlık bozuk';

  @override
  String get repairDiagnosisFilesystemDirty =>
      'Dosya sistemi kirli / temiz olmayan bağlantı kesme';

  @override
  String get repairRestoreBackupHeaderButton => 'Yedek başlığı geri yükle';

  @override
  String get repairRunFilesystemCheckButton =>
      'Dosya sistemi denetimi çalıştır ve düzelt';

  @override
  String get repairActionSucceededMessage => 'Onarım başarıyla tamamlandı';

  @override
  String get repairActionFailedMessage => 'Onarım eylemi başarılı olmadı';

  @override
  String get storageAnalyzerTargetLabel => 'Birim';

  @override
  String get storageAnalyzerNoTargetsTitle => 'Çözümlenecek bir şey yok';

  @override
  String get storageAnalyzerNoTargetsMessage =>
      'Önce Yerel Depolama\'yı açın ya da bir kasa bağlayın, sonra depolama dökümünü görmek için buraya dönün.';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return '$used / $total kullanıldı';
  }

  @override
  String get storageAnalyzerBreakdownHeader => 'Dosya türüne göre';

  @override
  String get storageAnalyzerScanningMessage => 'Birim taranıyor…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return 'Tarama $count dosyadan sonra erken durdu — sonuçlar eksik olabilir.';
  }

  @override
  String get storageAnalyzerNoFilesFound => 'Dosya bulunamadı';

  @override
  String get storageCategoryImages => 'Resimler';

  @override
  String get storageCategoryVideos => 'Videolar';

  @override
  String get storageCategoryAudio => 'Ses';

  @override
  String get storageCategoryDocuments => 'Belgeler';

  @override
  String get storageCategoryArchives => 'Arşivler';

  @override
  String get storageCategoryOther => 'Diğer';

  @override
  String get storageAnalyzerTabMap => 'Harita';

  @override
  String get storageAnalyzerTabFolders => 'Klasörler';

  @override
  String get storageAnalyzerTabTypes => 'Türler';

  @override
  String get storageAnalyzerTabCleanup => 'Temizlik';

  @override
  String storageAnalyzerFreeSpace(String free) {
    return '$free boş';
  }

  @override
  String storageAnalyzerFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dosya',
      one: '1 dosya',
    );
    return '$_temp0';
  }

  @override
  String storageAnalyzerItemCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe',
      one: '1 öğe',
    );
    return '$_temp0';
  }

  @override
  String storageAnalyzerContentSize(String size) {
    return 'Kasa içeriği: $size';
  }

  @override
  String storageAnalyzerScanProgress(String files, String size) {
    return 'Şimdiye kadar $files dosya · $size';
  }

  @override
  String get storageAnalyzerPartialNotice =>
      'Bazı klasörler tamamen okunamadı, bu yüzden toplamlar gerçek değerlerden düşük olabilir.';

  @override
  String get storageAnalyzerStaleNotice =>
      'Bu birim taranmasından sonra değişti.';

  @override
  String get storageAnalyzerUpOneLevel => 'Bir üst düzey';

  @override
  String get storageAnalyzerEmptyFolder => 'Bu klasör boş.';

  @override
  String get storageAnalyzerMapHint =>
      'Açmak için bir klasöre dokunun. Seçmek için basılı tutun.';

  @override
  String get storageAnalyzerSortFiles => 'Dosya sayısı';

  @override
  String get storageAnalyzerAllTypes => 'Tüm türler';

  @override
  String storageAnalyzerLargestOfType(String type) {
    return 'En büyük dosyalar · $type';
  }

  @override
  String get storageAnalyzerCleanupHeader => 'Öneriler';

  @override
  String get storageAnalyzerCleanupLarge => 'Büyük dosyalar';

  @override
  String get storageAnalyzerCleanupStale =>
      'Bir yıldan uzun süredir değiştirilmeyenler';

  @override
  String get storageAnalyzerCleanupTemp => 'Geçici ve gereksiz dosyalar';

  @override
  String get storageAnalyzerCleanupEmpty => 'Boş klasörler';

  @override
  String get storageAnalyzerCleanupReview => 'İncele';

  @override
  String get storageAnalyzerCleanupNothing =>
      'Temizlenecek belirgin bir şey yok. Bu birim derli toplu görünüyor.';

  @override
  String get storageAnalyzerBiggestFiles => 'En büyük dosyalar';

  @override
  String get storageAnalyzerBiggestFilesSubtitle =>
      'Bu birimdeki en büyük dosyalara göz atın';

  @override
  String get storageAnalyzerAllSuggestions => 'Tüm öneriler';

  @override
  String storageAnalyzerSelectedSummary(int count, String size) {
    return '$count seçili · $size';
  }

  @override
  String storageAnalyzerDeleteFilesMessage(String size) {
    return 'Bu işlem seçili öğeleri bu depolamadan kalıcı olarak siler ve $size alan açar. Geri alınamaz.';
  }

  @override
  String storageAnalyzerDeleteFoldersMessage(String files, String size) {
    return 'Bu işlem seçili öğeleri ($files dosya, seçili klasörlerin içindeki her şey dahil) kalıcı olarak siler ve $size alan açar. Geri alınamaz.';
  }

  @override
  String storageAnalyzerDeleteDone(String size) {
    return '$size alan açıldı';
  }

  @override
  String storageAnalyzerDeletePartial(
    String deleted,
    String failed,
    String size,
  ) {
    return '$deleted silindi, ama $failed silinemedi. $size alan açıldı.';
  }

  @override
  String get storageAnalyzerDeleteNone => 'Hiçbir şey silinmedi.';

  @override
  String get storageAnalyzerDeleteError => 'Seçili öğeler silinemedi.';

  @override
  String get storageAnalyzerRescanFolder => 'Bu klasörü yeniden tara';

  @override
  String get storageAnalyzerSelectAction => 'Seç';

  @override
  String get storageAnalyzerSelectAllHere => 'Bu klasördekilerin tümünü seç';

  @override
  String get storageAnalyzerOpenFolder => 'Klasörü aç';

  @override
  String get keyfilePassphraseGeneratorTitle =>
      'Anahtar dosyası ve parola ifadesi oluşturucu';

  @override
  String get keyfilePassphraseGeneratorSubtitle =>
      'Parola ve anahtar dosyası oluşturun';

  @override
  String get tabPassphrase => 'Parola ifadesi';

  @override
  String get tabKeyfile => 'Anahtar dosyası';

  @override
  String get modeDiceware => 'Diceware parola ifadesi';

  @override
  String get modeCustomPassword => 'Özel parola';

  @override
  String get keyfileTypeBinary => 'İkili anahtar dosyası (.key)';

  @override
  String get keyfileTypeImage => 'Gürültü resmi anahtar dosyası (.png)';

  @override
  String get copyPassphraseSuccess => 'Parola ifadesi hassas panoya kopyalandı';

  @override
  String get copyFingerprintSuccess => 'SHA-256 parmak izi panoya kopyalandı';

  @override
  String get saveKeyfileToVault => 'Bağlı kasaya kaydet';

  @override
  String get exportKeyfileToStorage => 'Cihaz depolamasına aktar';

  @override
  String get keyfileNoOpenVaultsMessage =>
      'Açık kasa yok. Lütfen önce bir kasa bağlayın.';

  @override
  String get keyfileSelectDestinationVaultTitle => 'Hedef kasayı seçin';

  @override
  String keyfileVolumeIdLabel(Object volId) {
    return 'Birim kimliği: $volId';
  }

  @override
  String keyfileExportSuccessMessage(Object path) {
    return 'Anahtar dosyası şuraya aktarıldı: $path';
  }

  @override
  String keyfileExportFailedMessage(Object error) {
    return 'Dışa aktarma başarısız: $error';
  }

  @override
  String keyfileSavedToVaultMessage(Object vaultName, Object path) {
    return 'Anahtar dosyası kaydedildi — $vaultName: $path';
  }

  @override
  String get keyfileWriteFailedMessage => 'Anahtar dosyası kasaya yazılamadı';

  @override
  String keyfileSaveErrorMessage(Object error) {
    return 'Kasaya kaydederken hata: $error';
  }

  @override
  String get passphraseGeneratedSecretLabel => 'Oluşturulan gizli anahtar';

  @override
  String get copyToClipboardTooltip => 'Panoya kopyala';

  @override
  String get generateNewTooltip => 'Yenisini oluştur';

  @override
  String get passphraseStrengthWeak => 'Zayıf';

  @override
  String get passphraseStrengthGood => 'İyi';

  @override
  String get passphraseStrengthStrong => 'Güçlü';

  @override
  String get passphraseStrengthUnbreakable => 'Kırılamaz';

  @override
  String get passphraseCrackTimeInstant => '< 1 saniye';

  @override
  String get passphraseCrackTimeShort => 'Birkaç gün / ay';

  @override
  String get passphraseCrackTimeCenturies => 'Birkaç yüzyıl';

  @override
  String get passphraseCrackTimeMillionsOfYears => 'Milyonlarca yıl';

  @override
  String passphraseStrengthLabel(Object label) {
    return 'Güç: $label';
  }

  @override
  String passphraseEntropyBitsLabel(Object bits) {
    return '$bits bit entropi';
  }

  @override
  String passphraseCrackTimeLabel(Object crackTime) {
    return 'Tahmini kırılma süresi: $crackTime';
  }

  @override
  String get dicewareOptionsTitle => 'EFF Diceware seçenekleri';

  @override
  String dicewareWordCountLabel(Object count) {
    return 'Kelime sayısı: $count kelime';
  }

  @override
  String dicewareWordCountBitsLabel(Object bits) {
    return '$bits bit';
  }

  @override
  String dicewareWordCountSliderLabel(Object count) {
    return '$count kelime';
  }

  @override
  String get dicewareWordSeparatorLabel => 'Kelime ayırıcı';

  @override
  String get dicewareSeparatorHyphen => 'Tire ( - )';

  @override
  String get dicewareSeparatorSpace => 'Boşluk (   )';

  @override
  String get dicewareSeparatorUnderscore => 'Alt çizgi ( _ )';

  @override
  String get dicewareSeparatorDot => 'Nokta ( . )';

  @override
  String get dicewareSeparatorSlash => 'Eğik çizgi ( / )';

  @override
  String get dicewareWordCasingLabel => 'Kelime büyük/küçük harf';

  @override
  String get dicewareCasingLowercase => 'küçük harf';

  @override
  String get dicewareCasingTitleCase => 'Baş Harfler Büyük';

  @override
  String get dicewareCasingUppercase => 'BÜYÜK HARF';

  @override
  String get dicewareAppendDigitLabel => 'Rastgele rakam ekle (0-9)';

  @override
  String get dicewareAppendSymbolLabel => 'Rastgele sembol ekle (!@#\$%)';

  @override
  String get customPasswordOptionsTitle => 'Özel parola seçenekleri';

  @override
  String customPasswordLengthLabel(Object length) {
    return 'Uzunluk: $length karakter';
  }

  @override
  String customPasswordLengthSliderLabel(Object length) {
    return '$length krk';
  }

  @override
  String get customPasswordUppercaseLabel => 'Büyük harfler (A-Z)';

  @override
  String get customPasswordLowercaseLabel => 'Küçük harfler (a-z)';

  @override
  String get customPasswordNumbersLabel => 'Rakamlar (0-9)';

  @override
  String get customPasswordSymbolsLabel => 'Semboller (!@#\$%^&*)';

  @override
  String get customPasswordExcludeAmbiguousLabel =>
      'Karıştırılanları hariç tut (1, l, I, 0, O)';

  @override
  String get keyfileBinarySizeTitle => 'İkili anahtar dosyası boyutu';

  @override
  String get keyfileImageResolutionTitle => 'Gürültü resmi çözünürlüğü';

  @override
  String get keyfilePresetBytes64 => '64 bayt (VeraCrypt standardı)';

  @override
  String get keyfilePresetBytes256 => '256 bayt';

  @override
  String get keyfilePresetBytes2048 => '2 KB';

  @override
  String get keyfilePresetBytes64kb => '64 KB';

  @override
  String get keyfilePresetBytes1mb => '1 MB (azami sınır)';

  @override
  String get keyfilePresetRes64 => '64 x 64 piksel (~16 KB)';

  @override
  String get keyfilePresetRes256 => '256 x 256 piksel (~256 KB)';

  @override
  String get keyfilePresetRes512 => '512 x 512 piksel (~1 MB)';

  @override
  String get keyfileGenerateNewTooltip => 'Yeni anahtar dosyası oluştur';

  @override
  String keyfileSizeLabel(Object size) {
    return 'Boyut: $size';
  }

  @override
  String get keyfileFingerprintLabel => 'SHA-256 parmak izi';

  @override
  String get keyfileCopyFingerprintTooltip => 'Parmak izini kopyala';

  @override
  String get duplicateFinderNoVaultsTitle => 'Bağlı kasa yok';

  @override
  String get duplicateFinderNoVaultsMessage =>
      'Yinelenen dosyaları taramak için en az bir kasa kapsayıcısının kilidini açıp bağlayın.';

  @override
  String duplicateFinderConfirmDeleteMessage(Object count, Object size) {
    return 'Yinelenen dosyalar kasalarınızdan kalıcı olarak silinsin mi? Silinecek: $count dosya ($size). Bu işlem geri alınamaz.';
  }

  @override
  String get duplicateFinderDeletePermanentlyButton => 'Kalıcı olarak sil';

  @override
  String duplicateFinderDeleteSuccessMessage(Object count) {
    return 'Başarıyla silindi: $count yinelenen dosya.';
  }

  @override
  String get duplicateFinderIntroTitle => '3 aşamalı bayt eşitliği bulucu';

  @override
  String get duplicateFinderIntroSubtitle =>
      'Dosya adlarından bağımsız olarak tamamen aynı içeriği algılar.';

  @override
  String get duplicateFinderStagesDescription =>
      '• 1. Aşama: Boyuta göre gruplama (anlık meta veri taraması)\n• 2. Aşama: Kısmi başlık denetimi (16 KB SHA-256 başlığı)\n• 3. Aşama: Tam özet doğrulaması (tam SHA-256 bayt eşleşmesi)';

  @override
  String get duplicateFinderScanningVaultFallback => 'Kasa taranıyor...';

  @override
  String duplicateFinderProcessingFileLabel(Object fileName) {
    return 'İşleniyor: $fileName';
  }

  @override
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  ) {
    return 'Taranan dosya: $scanned | Bulunan yinelenen: $groups grup ($saved)';
  }

  @override
  String duplicateFinderGroupsFoundLabel(Object count) {
    return '$count yinelenen grup bulundu';
  }

  @override
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved) {
    return '$copies kopya bulundu • $saved depolama alanı kazanın';
  }

  @override
  String duplicateFinderVaultsSelectedLabel(Object count) {
    return '$count kasa seçildi';
  }

  @override
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  ) {
    return 'Grup $groupIndex: $size ($count kopya bulundu)';
  }

  @override
  String duplicateFinderRecoverableSpaceLabel(Object size) {
    return 'Kazanılabilir alan: $size';
  }

  @override
  String get duplicateFinderPreviewFileTooltip => 'Dosyayı önizle';

  @override
  String duplicateFinderPreviewFailedMessage(Object fileName) {
    return 'Dosya önizlemesi açılamadı: $fileName';
  }

  @override
  String duplicateFinderPreviewErrorMessage(Object error) {
    return 'Dosya önizlenirken hata: $error';
  }

  @override
  String duplicateFinderFilesSelectedLabel(Object count) {
    return '$count dosya seçildi';
  }

  @override
  String duplicateFinderBytesToBeFreedLabel(Object size) {
    return '$size boşaltılacak';
  }

  @override
  String duplicateFinderDeleteSelectedButton(Object count) {
    return 'Seçilenleri sil ($count)';
  }

  @override
  String get vaultBrowserRootFolderLabel => 'Kök klasör';

  @override
  String vaultFilePickerTitle(Object vaultName) {
    return 'Dosya seç ($vaultName)';
  }

  @override
  String get vaultFilePickerEmptyMessage => 'Klasör boş';

  @override
  String vaultFilePickerConfirmButton(Object count) {
    return 'Seç: $count dosya';
  }

  @override
  String vaultFolderPickerTitle(Object vaultName) {
    return 'Klasör seç ($vaultName)';
  }

  @override
  String get vaultFolderPickerEmptyMessage => 'Burada alt klasör yok';

  @override
  String get vaultFolderPickerRootLabel => 'Kök';

  @override
  String get vaultFolderPickerConfirmRootButton => 'Kök klasörü seç';

  @override
  String vaultFolderPickerConfirmNamedButton(Object folderName) {
    return 'Seç: \"$folderName\"';
  }

  @override
  String get singleFileCryptoSelectInputTitle => 'Girdi dosyalarını seçin';

  @override
  String get singleFileCryptoFromDeviceTitle => 'Cihaz depolamasından';

  @override
  String get singleFileCryptoFromDeviceSubtitle =>
      'Sistem dosya seçicisiyle cihazdan dosya seçin';

  @override
  String get singleFileCryptoFromVaultTitle => 'Bağlı kasadan';

  @override
  String get singleFileCryptoFromVaultSubtitle =>
      'Açık bir şifreli kapsayıcıdan dosya seçin';

  @override
  String get singleFileCryptoSelectDestinationTitle => 'Hedef klasörü seçin';

  @override
  String get singleFileCryptoDeviceFolderTitle => 'Cihaz depolama klasörü';

  @override
  String get singleFileCryptoDeviceFolderSubtitle =>
      'Çıktıyı cihaz depolamasındaki bir klasöre kaydedin';

  @override
  String get singleFileCryptoVaultFolderTitle => 'Bağlı kasa klasörü';

  @override
  String get singleFileCryptoVaultFolderSubtitle =>
      'Çıktıyı açık bir şifreli kapsayıcının içine kaydedin';

  @override
  String get toolsSectionBackupSync => 'Yedekleme ve eşitleme';

  @override
  String get toolVaultSyncTitle => 'Kasa eşitleme';

  @override
  String get toolVaultSyncSubtitle =>
      'İki klasörü karşılaştırın — kasalarda, bu cihazda veya bir belge sağlayıcıda — ve eksik ya da daha yeni olanı kopyalayın';

  @override
  String get vaultSyncTapToSelect =>
      'Bir depolama ve klasör seçmek için dokunun';

  @override
  String get vaultSyncSwapTooltip => 'İki depolamayı değiştir';

  @override
  String get vaultSyncIntroTitle => 'İki klasörü karşılaştır';

  @override
  String get vaultSyncIntroSubtitle =>
      'Her birinde nelerin eksik, değiştirilmiş veya daha yeni olduğunu görmek için iki klasör seçin — bir kasada, cihaz depolamasında veya SD kart ya da bulut sürücü gibi bir belge sağlayıcıda.';

  @override
  String get vaultSyncCompareButton => 'Karşılaştır';

  @override
  String get vaultSyncComparingLabel => 'Klasörler karşılaştırılıyor…';

  @override
  String get vaultSyncScanFailedTitle => 'Klasör okunamadı';

  @override
  String get vaultSyncScanFailedMessage =>
      'Bir kasadaki bir klasör okunamadı, bu yüzden karşılaştırma tahmin yürütmek yerine durduruldu. Hiçbir şey değiştirilmedi. Kasayı yeniden kilitleyip açın, sonra yeniden karşılaştırın.';

  @override
  String vaultSyncCompareStatsLabel(Object dirs, Object entries) {
    return 'Taranan klasör: $dirs | Bulunan fark: $entries';
  }

  @override
  String get vaultSyncCancelCompareButton => 'İptal';

  @override
  String get vaultSyncInSyncTitle => 'Zaten eşitlenmiş';

  @override
  String vaultSyncInSyncMessage(Object count) {
    return 'Eşleşen tüm $count dosya iki tarafta da aynı.';
  }

  @override
  String get vaultSyncRecompareButton => 'Yeniden karşılaştır';

  @override
  String vaultSyncDifferencesFoundLabel(Object count) {
    return '$count fark bulundu';
  }

  @override
  String vaultSyncInSyncCountLabel(Object count) {
    return '$count dosya iki tarafta zaten eşleşiyor';
  }

  @override
  String vaultSyncBadgeConflicts(Object count) {
    return '$count inceleme gerekli';
  }

  @override
  String get vaultSyncDirectionLabel => 'Eşitleme yönü';

  @override
  String get vaultSyncDirectionTwoWay => 'İki yönlü';

  @override
  String get vaultSyncDirectionTwoWaySubtitle =>
      'Eksik dosyaları ve daha yeni sürümleri diğer tarafa kopyalar.';

  @override
  String get vaultSyncStatusConflict => 'İnceleme gerekli';

  @override
  String get vaultSyncStatusTypeMismatch => 'Tür uyuşmazlığı';

  @override
  String get vaultSyncTypeMismatchTooltip =>
      'Bir tarafta dosya, diğer tarafta klasör var — dosya tarayıcısında elle çözün';

  @override
  String get vaultSyncChangeActionTooltip => 'Eşitleme eylemini değiştir';

  @override
  String get vaultSyncActionSkip => 'Atla';

  @override
  String vaultSyncChangesQueuedLabel(Object count) {
    return '$count değişiklik sırada';
  }

  @override
  String get vaultSyncSyncNowButton => 'Şimdi eşitle';

  @override
  String get vaultSyncConfirmTitle => 'Eşitleme başlatılsın mı?';

  @override
  String vaultSyncConfirmMessage(Object count, Object bytes) {
    return 'İki taraf arasında kopyalanacak: $count öğe ($bytes toplam). Aynı ada sahip mevcut dosyaların üzerine yazılacak.';
  }

  @override
  String vaultSyncPickLocationTitle(Object side) {
    return 'Seç: $side klasörü';
  }

  @override
  String get vaultSyncOverlapWarning =>
      'İki klasör aynı olmamalı veya birbirinin içinde yer almamalıdır.';

  @override
  String vaultSyncPlaintextWarning(Object targets) {
    return 'Bir kasadan $targets konumuna kopyalanan dosyalar şifresiz saklanır.';
  }

  @override
  String get vaultSyncTargetKindVault => 'Şifreli kasa';

  @override
  String get vaultSyncTargetKindDevice => 'Cihaz depolaması · şifreli değil';

  @override
  String get vaultSyncTargetKindProvider => 'Belge sağlayıcı · şifreli değil';

  @override
  String get vaultSyncEnableLocalStorageTooltip =>
      'Yerel depolama erişimini etkinleştir';

  @override
  String get vaultSyncNoStoragesTitle => 'Henüz eşitlenecek depolama yok';

  @override
  String get vaultSyncNoStoragesMessage =>
      '+ düğmesiyle bir klasör veya belge sağlayıcı ekleyin ya da bir kasa bağlayın.';

  @override
  String get vaultSyncReadOnlyBadge => 'Salt okunur';

  @override
  String get vaultSyncReadOnlyTooltip =>
      'Bu kasa salt okunur bağlı — dosyalar içine kopyalanamaz';

  @override
  String get vaultSyncSyncingButton => 'Eşitleniyor…';

  @override
  String get vaultSyncNotEnoughSpaceTitle => 'Yeterli alan yok';

  @override
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  ) {
    return 'Yeterli alan yok: $side — gereken: $required, yalnızca $free boş.';
  }

  @override
  String get removeMasterPasswordTitle => 'Ana parolayı kaldır';

  @override
  String get confirmRemoveMasterPasswordMessage =>
      'Kaldırmayı onaylamak için mevcut Ana Parolanızı girin:';

  @override
  String get incorrectPassword => 'Yanlış parola';

  @override
  String get rememberPerFolderLayoutLabel =>
      'Klasör başına düzeni ve sıralamayı hatırla';

  @override
  String get rememberPerFolderLayoutDesc =>
      'Her klasörün görünüm düzenini (liste, ızgara, mozaik) ve sıralamasını ayrı ayrı kaydet';

  @override
  String get defaultFolderLayoutLabel => 'Varsayılan klasör düzeni';

  @override
  String get fileInfoAction => 'Bilgi';

  @override
  String get goToLocationAction => 'Konuma git';

  @override
  String get copyPathAction => 'Yolu kopyala';

  @override
  String get automationTileTitle => 'Otomasyon';

  @override
  String get automationTileSubtitle =>
      'Otomasyonun bu kasanın kilidini açmasına, kilitlemesine, içe veya dışa aktarmasına izin ver';

  @override
  String get automationScreenTitle => 'Otomasyon (Tasker / MacroDroid)';

  @override
  String get automationUsbUnsupportedMessage =>
      'Otomasyon henüz USB\'ye bağlı kasalar için kullanılamıyor.';

  @override
  String get automationThisVaultSectionHeader => 'Bu kasa';

  @override
  String get automationAccessLabel => 'Otomasyon erişimi';

  @override
  String get automationPasswordSectionHeader => 'Otomasyon parolası';

  @override
  String get automationPasswordStoredHint =>
      'Gözetimsiz UNLOCK_VAULT çağrıları için bir parola saklanıyor. Değiştirmek için yeni bir tane kaydedin veya temizlemek için boş bir alanı kaydedin — otomasyon, buna güvenmek yerine parolayı doğrudan yayında da sağlayabilir.';

  @override
  String get automationPasswordNotStoredHint =>
      'İsteğe bağlı. Saklanan parola yoksa otomasyonun her UNLOCK_VAULT yayınında bir parola sağlaması gerekir.';

  @override
  String get automationNewPasswordFieldLabel => 'Yeni parola';

  @override
  String get automationPasswordFieldLabel => 'Parola';

  @override
  String get automationClearPasswordButton => 'Saklanan parolayı temizle';

  @override
  String get automationSavePasswordButton => 'Parolayı kaydet';

  @override
  String get automationTokenSectionHeader => 'API belirteci';

  @override
  String get automationTokenDescription =>
      'Otomasyon erişimi etkin olan her kasa tarafından paylaşılır. Otomasyon bunu her yayında geri gönderir; yanlış veya eksik belirteç hata vermeden sessizce yok sayılır.';

  @override
  String get automationRegenerateTokenButton => 'Belirteci yeniden oluştur';

  @override
  String get automationRegenerateTokenDialogTitle =>
      'Belirteç yeniden oluşturulsun mu?';

  @override
  String get automationRegenerateTokenDialogMessage =>
      'Geçerli belirteci kullanan her Tasker profili veya MacroDroid makrosu, yenisiyle güncelleyene kadar sessizce çalışmayı durduracak.';

  @override
  String get automationRegenerateConfirmLabel => 'Yeniden oluştur';

  @override
  String get automationTokenRegeneratedMessage =>
      'Belirteç yeniden oluşturuldu.';

  @override
  String get automationRegenerateTokenFailedMessage =>
      'Belirteç yeniden oluşturulamadı.';

  @override
  String get automationUpdateSettingsFailedMessage =>
      'Otomasyon ayarları güncellenemedi.';

  @override
  String get automationSavePasswordFailedMessage =>
      'Otomasyon parolası kaydedilemedi.';

  @override
  String get automationPasswordClearedMessage =>
      'Otomasyon parolası temizlendi.';

  @override
  String get automationPasswordSavedMessage => 'Otomasyon parolası kaydedildi.';

  @override
  String get automationConfigSectionHeader => 'Yapılandırma dizeleri';

  @override
  String get automationConfigIntro =>
      'Kopyalamak için aşağıdaki herhangi bir değere dokunun. Tasker\'da bir \"Send Intent\" eylemi kullanın; MacroDroid\'de Intent Type değeri Broadcast olarak ayarlanmış bir \"Intent\" eylemi kullanın — Activity veya Service değil, bunlar \"unable to find explicit activity class\" hatasıyla başarısız olur.';

  @override
  String get automationConfigPackageLabel => 'Paket adı';

  @override
  String get automationConfigClassLabel => 'Alıcı sınıfı';

  @override
  String get automationConfigVaultUriLabel => 'Bu kasanın URI\'si';

  @override
  String get automationConfigActionsSectionHeader => 'Yayın eylemleri';

  @override
  String get automationActionUnlockLabel => 'Kasanın kilidini aç';

  @override
  String get automationActionLockLabel => 'Kasayı kilitle';

  @override
  String get automationActionImportLabel => 'Dosyayı içe aktar';

  @override
  String get automationActionExportLabel => 'Dosyayı dışa aktar';

  @override
  String get automationActionWipeLabel => 'Dosyayı sil (ezerek)';

  @override
  String get automationActionEmergencyLockLabel => 'Acil kilit (Kademe 1)';

  @override
  String get automationActionEmergencyPurgeLabel => 'Acil temizleme';

  @override
  String get automationTierOffLabel => 'Kapalı';

  @override
  String get automationTierOffSubtitle => 'Otomasyon bu kasaya dokunamaz';

  @override
  String get automationTierLifecycleLabel => 'Yalnızca kilit aç / kilitle';

  @override
  String get automationTierLifecycleSubtitle =>
      'Otomasyon bu kasayı açıp kilitleyebilir, başka bir şey yapamaz';

  @override
  String get automationTierFullLabel =>
      'Kilit aç / kilitle + dosya içe-dışa aktarma + eşitleme';

  @override
  String get automationTierFullSubtitle =>
      'Bu kasanın kilidi açıkken otomasyon yapılandırılmış klasörleri de eşitleyebilir ve dosyaları içe veya dışa aktarabilir';

  @override
  String get automationTutorialLinkLabel => 'Adım adım tüm öğreticiyi okuyun';

  @override
  String get showHiddenFilesLabel => 'Gizli dosyaları göster';

  @override
  String get showHiddenFilesDesc =>
      'Nokta ile başlayan dosyaları ve sistem klasörlerini göster';

  @override
  String get dontAskAgain => 'Bir daha sorma';

  @override
  String get deleteAfterImportLabel => 'İçe aktarmadan sonra dosyaları sil';

  @override
  String get deleteAfterImportModeAsk => 'Her seferinde sor';

  @override
  String get deleteAfterImportModeAskSubtitle =>
      'İçe aktarmadan sonra orijinal dosyaların silinip silinmeyeceğini sor';

  @override
  String get deleteAfterImportModeKeep => 'Orijinalleri koru (silme)';

  @override
  String get deleteAfterImportModeKeepSubtitle =>
      'Orijinal dosyaları asla silme ve sorma';

  @override
  String get deleteAfterImportModeDelete => 'Orijinalleri otomatik sil';

  @override
  String get deleteAfterImportModeDeleteSubtitle =>
      'İçe aktarmadan sonra orijinal dosyaları cihazdan otomatik olarak sil';

  @override
  String get deleteAfterImportVaultSettingLabel =>
      'Bu kasa için içe aktarmadan sonra dosyaları sil';

  @override
  String get deleteAfterImportInheritGlobal => 'Genel varsayılanı kullan';

  @override
  String deleteAfterImportInheritGlobalSubtitle(String mode) {
    return 'Genel varsayılan kullanılıyor: $mode';
  }

  @override
  String get deleteAfterImportVaultAsk => 'Her seferinde sor';

  @override
  String get deleteAfterImportVaultKeep => 'Kaynak dosyaları her zaman koru';

  @override
  String get deleteAfterImportVaultDelete => 'Kaynak dosyaları her zaman sil';

  @override
  String get wizardBackButton => 'Geri';

  @override
  String get wizardNextButton => 'Sonraki';

  @override
  String get wizardStepBasicInfoTitle => 'Temel bilgiler';

  @override
  String get wizardStepReviewTitle => 'Gözden geçir';

  @override
  String get wizardCreateTypePrompt => 'Ne oluşturmak istersiniz?';

  @override
  String get wizardChooseFormatPrompt => 'Bir kapsayıcı biçimi seçin';

  @override
  String get wizardEncryptionDetailsRowTitle => 'Şifreleme ayrıntıları';

  @override
  String get wizardSummaryTitle => 'Özet';

  @override
  String get wizardSummaryPasswordLabel => 'Parola';

  @override
  String get wizardPasswordSetValue => 'Belirlendi';

  @override
  String get wizardPasswordNotSetValue =>
      'Belirlenmedi (anahtar dosyaları kullanılıyor)';

  @override
  String get wizardSummaryKeyfilesLabel => 'Anahtar dosyaları';

  @override
  String get wizardSummaryPimDefaultValue => 'Varsayılan';

  @override
  String get wizardSummaryPimLabel => 'PIM';

  @override
  String get wizardSummaryDriveLabel => 'USB sürücü';

  @override
  String get sectionKeyStorageIntegration =>
      'Anahtar depolama ve sistem erişimi';

  @override
  String get sectionMaskMode => 'Maske modu';

  @override
  String get advancedOptionsTitle => 'Gelişmiş seçenekler';

  @override
  String get audioTrackTitle => 'Ses parçası';

  @override
  String get noAudioTracksAvailable => 'Kullanılabilir ses parçası yok';

  @override
  String trackNumberLabel(int number) {
    return 'Parça $number';
  }

  @override
  String subtitleTrackNumberLabel(int number) {
    return 'Altyazı $number';
  }

  @override
  String get offLabel => 'Kapalı';

  @override
  String get externalSubtitlesLabel => 'Harici altyazılar (.srt/.vtt)';

  @override
  String get subtitleSizeLabel => 'Boyut';

  @override
  String get subtitleSizeSmall => 'S';

  @override
  String get subtitleSizeMedium => 'M';

  @override
  String get subtitleSizeLarge => 'L';

  @override
  String get subtitleSizeExtraLarge => 'XL';

  @override
  String get subtitlePositionLabel => 'Konum';

  @override
  String get subtitlePositionBottom => 'Alt';

  @override
  String get subtitlePositionLower => 'Alt orta';

  @override
  String get subtitlePositionCenter => 'Orta';

  @override
  String get subtitlePositionTop => 'Üst';

  @override
  String get editImageAction => 'Resmi düzenle';

  @override
  String get imageEditorUnsupportedFormatMessage =>
      'Bu resim biçimi düzenleme için desteklenmiyor.';

  @override
  String get cropToolLabel => 'Kırp';

  @override
  String get drawToolLabel => 'Çiz';

  @override
  String get textToolLabel => 'Metin';

  @override
  String get redactToolLabel => 'Karart';

  @override
  String get rotateRightTooltip => 'Sağa döndür';

  @override
  String get cropAspectFreeLabel => 'Serbest';

  @override
  String get cropAspectSquareLabel => 'Kare';

  @override
  String get cropAspectOriginalLabel => 'Orijinal';

  @override
  String get resetImageTooltip => 'Orijinale sıfırla';

  @override
  String get resetImageConfirmTitle => 'Resim sıfırlansın mı?';

  @override
  String get resetImageConfirmMessage =>
      'Bu oturumda yapılan tüm kırpma ve çizim değişiklikleri atılır.';

  @override
  String get addTextAnnotationTitle => 'Metin ekle';

  @override
  String get addTextAnnotationHint => 'Bir şeyler yazın…';

  @override
  String get saveImageSheetTitle => 'Değişiklikleri kaydet';

  @override
  String get saveAsNewFileOption => 'Yeni dosya olarak kaydet';

  @override
  String get saveAsNewFileDescription => 'Orijinale dokunmaz';

  @override
  String get overwriteOriginalOption => 'Orijinalin üzerine yaz';

  @override
  String get overwriteOriginalDescription => 'Orijinal dosyanın yerine geçer';

  @override
  String get newFileNameLabel => 'Dosya adı';

  @override
  String get imageEditorPngNoteMessage =>
      'Düzenlenen resimler PNG olarak kaydedilir.';

  @override
  String get imageSavedMessage => 'Resim kaydedildi';

  @override
  String imageSaveFailedMessage(String error) {
    return 'Resim kaydedilemedi: $error';
  }

  @override
  String get advancedRenameButton => 'Gelişmiş';

  @override
  String get advancedRenameBatchTitle => 'Toplu yeniden adlandırma';

  @override
  String get advancedRenameRulesTab => 'Kurallar';

  @override
  String advancedRenamePreviewTab(int count) {
    return 'Önizleme ($count)';
  }

  @override
  String get advancedRenameSearchReplaceTitle => 'Ara ve değiştir';

  @override
  String get advancedRenameFindTextLabel => 'Aranacak metin';

  @override
  String get advancedRenameFindTextHint =>
      'Eşleştirilecek metin veya kalıp girin...';

  @override
  String get advancedRenameReplaceWithLabel => 'Şununla değiştir';

  @override
  String get advancedRenameReplaceWithHint => 'Yeni metin veya değişkenler...';

  @override
  String get advancedRenameInsertVariableTooltip =>
      'Dinamik değişken belirteci ekle';

  @override
  String get advancedRenameDateTimeTokens => 'TARİH VE SAAT BELİRTEÇLERİ';

  @override
  String advancedRenameStandardDate(String token) {
    return 'Standart tarih ($token)';
  }

  @override
  String advancedRenameYearFourDigit(String token) {
    return 'Yıl, 4 haneli ($token)';
  }

  @override
  String advancedRenameMonth(String token) {
    return 'Ay ($token)';
  }

  @override
  String advancedRenameDayOfMonth(String token) {
    return 'Ayın günü ($token)';
  }

  @override
  String advancedRenameTime(String token) {
    return 'Saat ($token)';
  }

  @override
  String get advancedRenameDynamicIdentifiers => 'DİNAMİK TANIMLAYICILAR';

  @override
  String advancedRenameUniqueUuid(String token) {
    return 'Benzersiz UUID v4 ($token)';
  }

  @override
  String get advancedRenameRandomAlphanumeric =>
      'Rastgele alfasayısal (8 karakter)';

  @override
  String get advancedRenameRandomDigits => 'Rastgele rakamlar (6 rakam)';

  @override
  String get advancedRenameEmbeddedCounter => 'GÖMÜLÜ SAYAÇ';

  @override
  String advancedRenamePaddedCounter(String token) {
    return 'Sıfır dolgulu sayaç ($token)';
  }

  @override
  String get advancedRenameRegex => 'Regex';

  @override
  String get advancedRenameMatchCase => 'Büyük/küçük harf eşleştir';

  @override
  String get advancedRenameAllOccurrences => 'Tüm eşleşmeler';

  @override
  String get advancedRenameScopeFormatting => 'Kapsam ve biçimlendirme';

  @override
  String get advancedRenameApplyChangesTo => 'Değişiklikleri şuna uygula';

  @override
  String get advancedRenameFilename => 'Dosya adı';

  @override
  String get advancedRenameExtension => 'Uzantı';

  @override
  String get advancedRenameBoth => 'İkisi de';

  @override
  String get advancedRenameCaseTransformation => 'Harf büyüklüğü dönüşümü';

  @override
  String get advancedRenameNoChange => 'Değişiklik yok';

  @override
  String get advancedRenameLowercase => 'küçük harf';

  @override
  String get advancedRenameUppercase => 'BÜYÜK HARF';

  @override
  String get advancedRenameTitleCase => 'Baş Harfler Büyük';

  @override
  String get advancedRenameCapitalize => 'İlk harf büyük';

  @override
  String get advancedRenameSequentialCounter => 'Sıralı sayaç';

  @override
  String get advancedRenameCounterDescription =>
      'Sıralı numaralar ekle (sona veya başa)';

  @override
  String get advancedRenameSuffix => 'Sona ekle';

  @override
  String get advancedRenamePrefix => 'Başa ekle';

  @override
  String get advancedRenameStartAt => 'Başlangıç';

  @override
  String get advancedRenameDigits => 'Hane sayısı';

  @override
  String get advancedRenameDigitsHint => 'örn. 2 (01)';

  @override
  String get advancedRenameSeparator => 'Ayırıcı';

  @override
  String get advancedRenameSeparatorHint => '_ veya -';

  @override
  String get advancedRenameLivePreview => 'Canlı önizleme';

  @override
  String get advancedRenameDeselect => 'Seçimi kaldır';

  @override
  String get advancedRenameSelectAll => 'Tümünü seç';

  @override
  String get advancedRenameNoFilesSelected => 'Dosya seçilmedi';

  @override
  String get advancedRenameNameConflictDetected => 'Ad çakışması algılandı';

  @override
  String get advancedRenameCheckPreviewToFix =>
      'Düzeltmek için Önizleme sekmesine bakın';

  @override
  String get advancedRenameReadyToRename => 'Yeniden adlandırmaya hazır';

  @override
  String get advancedRenameErrorsDetected => 'Hatalar algılandı';

  @override
  String advancedRenameApply(int count) {
    return 'Uygula ($count)';
  }

  @override
  String get advancedRenameNameCollisionWithinBatch =>
      'Toplu işlem içinde ad çakışması.';

  @override
  String get advancedRenameCollidesWithUnselectedFile =>
      'Seçili olmayan bir dosyayla çakışıyor.';

  @override
  String advancedRenameReadyCount(int valid, int total) {
    return '$valid yeniden adlandırmaya hazır (toplam $total)';
  }

  @override
  String advancedRenameReadyOfTotal(int valid, int total) {
    return '$valid / $total hazır';
  }

  @override
  String advancedRenameRenamedItems(int succeeded, int failed) {
    return 'Yeniden adlandırılan: $succeeded öğe ($failed başarısız).';
  }

  @override
  String advancedRenameSuccessfullyRenamed(int count) {
    return '$count öğe başarıyla yeniden adlandırıldı.';
  }

  @override
  String get advancedRenameMonthsFull =>
      'Ocak|Şubat|Mart|Nisan|Mayıs|Haziran|Temmuz|Ağustos|Eylül|Ekim|Kasım|Aralık';

  @override
  String get advancedRenameMonthsAbbr =>
      'Oca|Şub|Mar|Nis|May|Haz|Tem|Ağu|Eyl|Eki|Kas|Ara';

  @override
  String get advancedRenameDaysFull =>
      'Pazartesi|Salı|Çarşamba|Perşembe|Cuma|Cumartesi|Pazar';

  @override
  String get advancedRenameDaysAbbr => 'Pzt|Sal|Çar|Per|Cum|Cmt|Paz';

  @override
  String get advancedRenameResolveConflicts =>
      'Uygulamadan önce ad çakışmalarını çözün';

  @override
  String advancedRenameChangedCount(int changed, int total) {
    return '$changed / $total';
  }

  @override
  String get automationKeyfilesPimSectionHeader => 'Anahtar dosyaları ve PIM';

  @override
  String get automationKeyfilesPimDescription =>
      'Yukarıdaki otomasyon parolasıyla birlikte saklanır ve UNLOCK_VAULT için aynı şekilde kullanılır -- yalnızca parolayla değil, anahtar dosyası ve/veya varsayılan olmayan bir PIM ile açılan VeraCrypt/LUKS kasaları için.';

  @override
  String get automationSavePimButton => 'PIM\'i kaydet';

  @override
  String get automationCameraDescription =>
      'Otomasyonun bu kasa için TAKE_PHOTO / START_RECORDING / STOP_RECORDING / START_AUDIO_RECORDING / STOP_AUDIO_RECORDING tetiklemesine izin verir. Tam erişimde bile varsayılan olarak kapalıdır -- dosya içe/dışa aktarmanın aksine, fotoğraf çekmek ekranda hiçbir gösterge gerektirmez, bu yüzden ayrı ve açık bir onay gerekir.';

  @override
  String get automationOverlayPermissionTitle =>
      'Diğer uygulamaların üzerinde göster';

  @override
  String get automationPimSavedMessage => 'PIM kaydedildi';

  @override
  String get automationActionImportFolderLabel => 'Klasörü içe aktar';

  @override
  String get automationActionExportFolderLabel => 'Klasörü dışa aktar';

  @override
  String get automationActionTakePhotoLabel => 'Fotoğraf çek';

  @override
  String get automationActionStartRecordingLabel => 'Kaydı başlat';

  @override
  String get automationActionStopRecordingLabel => 'Kaydı durdur';

  @override
  String get automationActionStartAudioRecordingLabel => 'Ses kaydını başlat';

  @override
  String get automationActionStopAudioRecordingLabel => 'Ses kaydını durdur';

  @override
  String get filePropertiesSectionHeader => 'DOSYA ÖZELLİKLERİ';

  @override
  String get fullPathLabel => 'Tam yol';

  @override
  String get sizeLabel => 'Boyut';

  @override
  String get modifiedLabel => 'Değiştirilme';

  @override
  String get vaultLabel => 'Kasa';

  @override
  String get mediaDimensionsSectionHeader => 'MEDYA VE BOYUTLAR';

  @override
  String get resolutionLabel => 'Çözünürlük';

  @override
  String get aspectRatioLabel => 'En boy oranı';

  @override
  String get formatLabel => 'Biçim';

  @override
  String get exifCameraDataSectionHeader => 'EXIF VE KAMERA VERİSİ';

  @override
  String get cameraLabel => 'Kamera';

  @override
  String get lensLabel => 'Lens';

  @override
  String get dateTakenLabel => 'Çekim tarihi';

  @override
  String get shutterSpeedLabel => 'Enstantane';

  @override
  String get apertureLabel => 'Diyafram';

  @override
  String get isoLabel => 'ISO';

  @override
  String get focalLengthLabel => 'Odak uzaklığı';

  @override
  String get flashLabel => 'Flaş';

  @override
  String get softwareLabel => 'Yazılım';

  @override
  String get gpsLocationLabel => 'GPS konumu';

  @override
  String get integrityChecksumSectionHeader => 'BÜTÜNLÜK VE SAĞLAMA TOPLAMI';

  @override
  String get computingHashMessage => 'Özet hesaplanıyor…';

  @override
  String get copyDiagnosticsButton => 'Tanılama bilgisini kopyala';

  @override
  String get closeButton => 'Kapat';

  @override
  String get hwAcceleratedBadge => 'DONANIM HIZLANDIRMALI';

  @override
  String get swDecoderBadge => 'YAZILIM ÇÖZÜCÜ';

  @override
  String get videoDecoderHardwareSection => 'VİDEO ÇÖZÜCÜ VE DONANIM';

  @override
  String get decoderNameLabel => 'Çözücü adı';

  @override
  String get accelerationLabel => 'Hızlandırma';

  @override
  String get hardwareGpuDirect => 'Donanım (doğrudan GPU)';

  @override
  String get softwareCpuFallback => 'Yazılım (CPU yedeği)';

  @override
  String get unknownValue => 'Bilinmiyor';

  @override
  String get framerateLabel => 'Kare hızı';

  @override
  String get variableOrUnknown => 'Değişken / Bilinmiyor';

  @override
  String get videoCodecLabel => 'Video codec bileşeni';

  @override
  String get autoDetected => 'Otomatik algılandı';

  @override
  String get colorFormatLabel => 'Renk biçimi';

  @override
  String get initLatencyLabel => 'Başlatma gecikmesi';

  @override
  String get audioEngineSection => 'SES MOTORU';

  @override
  String get audioDecoderLabel => 'Ses çözücü';

  @override
  String get audioCodecLabel => 'Ses codec bileşeni';

  @override
  String get pipelineHealthSection => 'İŞLEM HATTI VE SAĞLIK';

  @override
  String get playbackStateLabel => 'Oynatma durumu';

  @override
  String get decryptedBufferLabel => 'Şifresi çözülmüş arabellek';

  @override
  String secondsCached(String seconds) {
    return '$seconds sn önbellekte';
  }

  @override
  String get droppedFramesLabel => 'Atlanan kareler';

  @override
  String nFrames(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kare',
      one: '1 kare',
    );
    return '$_temp0';
  }

  @override
  String get sourceStorageLabel => 'Kaynak depolama';

  @override
  String directJniStreamSource(int volId) {
    return 'Doğrudan C++ JNI akışı (volId=$volId)';
  }

  @override
  String get filesTabLabel => 'Dosyalar';

  @override
  String get filesPermissionMessage =>
      'Cihazınızdaki dosyalara göz atmak için erişime izin verin.';

  @override
  String get filesEmptyMessage => 'Bu klasör boş.';

  @override
  String get filesCopy => 'Kopyala';

  @override
  String get filesChooseDestinationTitle => 'Bir klasör seçin';

  @override
  String get filesMoveHere => 'Buraya taşı';

  @override
  String get filesCopyHere => 'Buraya kopyala';

  @override
  String get filesDeleteFailed => 'Silinemedi';

  @override
  String get filesFilterTooltip => 'Filtre';

  @override
  String get filesFilterAll => 'Tüm dosyalar';

  @override
  String get filesFilterImages => 'Resimler';

  @override
  String get filesFilterVideos => 'Videolar';

  @override
  String get filesFilterAudio => 'Ses';

  @override
  String get filesFilterDocuments => 'Belgeler';

  @override
  String get filesTextTooLarge => 'Bu dosya burada önizleme için çok büyük.';

  @override
  String get filesTextSaved => 'Kaydedildi';

  @override
  String get filesTextSaveFailed => 'Kaydedilemedi';

  @override
  String get toolHeaderBackupTitle => 'Başlık yedeği';

  @override
  String get toolHeaderBackupSubtitle =>
      'Kapsayıcı başlıklarını ve kasa yapılandırmalarını yedekleyin veya geri yükleyin';

  @override
  String get headerBackupModeExport => 'Kaydet';

  @override
  String get headerBackupModeRestore => 'Geri yükle';

  @override
  String get headerBackupPickExportTarget => 'Yedeklemek istediğinizi seçin.';

  @override
  String get headerBackupPickRestoreTarget =>
      'Yedeği geri yüklemek istediğiniz hedefi seçin.';

  @override
  String get headerBackupTargetContainerSubtitle =>
      'VeraCrypt, LUKS1 veya LUKS2';

  @override
  String get headerBackupTargetFolderSubtitle =>
      'gocryptfs, CryFS veya Cryptomator';

  @override
  String get headerBackupExportInfoBanner =>
      'Bir kapsayıcının başlığı anahtar materyalini taşır -- onu kaybederseniz (bozuk sektörler, yarım kalan yazma) veri alanı sağlam olsa bile kurtarılamaz. Klasör kasası aynısını kökündeki küçük bir yapılandırma dosyasında tutar. Bu yedeği kapsayıcının kendisinden ayrı bir yerde saklayın.';

  @override
  String get headerBackupRestoreInfoBanner =>
      'Geri yükleme, hedefin mevcut başlığının (veya yapılandırma dosyasının) üzerine yedeği yazar -- yedeğin bu biçim için gerçek olduğu önce doğrulanır, ama doğru hedefi seçtiğinizden emin olun.';

  @override
  String headerBackupUnhealthyExportWarning(String diagnosis) {
    return 'Bu kapsayıcı sağlıklı çıkmadı ($diagnosis). Şimdi yedeklerseniz yedek de aynı sorunu taşır. Mümkünse önce Denetle ve Onar\'ı çalıştırın -- ya da yakalayabileceğiniz tek şans buysa yine de yedekleyin.';
  }

  @override
  String get headerBackupBackUpAnyway => 'Yine de yedekle';

  @override
  String get headerBackupExportHeader => 'Başlığı dışa aktar';

  @override
  String get headerBackupSavedBanner =>
      'Yedek kaydedildi. Bu kapsayıcıdan ayrı bir yerde saklayın.';

  @override
  String get headerBackupSaveBackupFile => 'Yedek dosyasını kaydet';

  @override
  String get headerBackupPickBackupFile => 'Yedek dosyası seç';

  @override
  String get headerBackupMismatchFolderVaultError =>
      'Bu yedek bir klasör kasasına ait, ama seçilen hedef bir kapsayıcı dosyası.';

  @override
  String get headerBackupMismatchContainerFileError =>
      'Bu yedek bir kapsayıcı dosyasına ait, ama seçilen hedef bir klasör kasası.';

  @override
  String get headerBackupRestoredSuccess => 'Başlık geri yüklendi.';

  @override
  String get headerBackupRestore => 'Geri yükle';

  @override
  String headerBackupBackedUpAt(String date) {
    return 'yedeklendi: $date';
  }

  @override
  String get headerBackupLogIdle => 'Konsol günlüğü boşta...';

  @override
  String get compositeCreateScreenTitle => 'Bileşik kapsayıcı oluştur';

  @override
  String get compositeProcessingStatus => 'İşleniyor…';

  @override
  String compositeCarrierFilesCountHeader(int count) {
    return 'Taşıyıcı dosyalar ($count)';
  }

  @override
  String get compositeAddCarrierFilesTitle => 'Taşıyıcı dosya ekle';

  @override
  String get compositeAddCarrierFilesSubtitle =>
      'Resim, video, ses veya belge seçin';

  @override
  String get compositeBrowseButtonLabel => 'Gözat';

  @override
  String compositeCarrierAllocatableSubtitle(String format, String size) {
    return '$format • Ayrılabilir: $size';
  }

  @override
  String get compositeCarrierAnalyzingStatus => 'Çözümleniyor…';

  @override
  String get compositeTotalUsableCapacityHeader =>
      'Toplam kullanılabilir kapasite';

  @override
  String compositeCapacityDistributedSubtitle(int count) {
    return '$count dosyaya dağıtıldı (512B sektörlere hizalı)';
  }

  @override
  String get compositePimFieldLabel => 'PIM (Kişisel yineleme çarpanı)';

  @override
  String get compositeRememberContainerTitle => 'Bu kapsayıcıyı hatırla';

  @override
  String get compositeRememberContainerSubtitle =>
      'Bir dahaki sefere bu dosyaları yeniden seçmek zorunda kalmamanız için panoya sabitler. Hangi dosyaların birbirine bağlı olduğunu şifreli olarak bu cihazda saklar.';

  @override
  String get compositeEncryptionAndFilesystemHeader =>
      'Şifreleme ve dosya sistemi';

  @override
  String get compositeEncryptionAlgorithmLabel => 'Şifreleme algoritması';

  @override
  String get compositeHashAlgorithmLabel => 'Özet algoritması (KDF)';

  @override
  String get compositeFilesystemTypeLabel => 'Dosya sistemi türü';

  @override
  String get compositeQuickFormatTitle => 'Hızlı biçimlendirme';

  @override
  String get compositeQuickFormatSubtitle =>
      'Taşıyıcıda ayrılan alanın sıfırla doldurulmasını atlar';

  @override
  String get compositeCreateContainerButton => 'Kapsayıcı oluştur';

  @override
  String get compositeCreateSuccessMessage =>
      'Bileşik kapsayıcı başarıyla oluşturuldu!';

  @override
  String compositeDefaultContainerName(int count) {
    return 'Bileşik kapsayıcı ($count dosya)';
  }

  @override
  String get compositeAlreadyHaveUnlockPrompt =>
      'Zaten bir bileşik kapsayıcınız var mı? Kilidi aç ve bağla';

  @override
  String compositeBadgeMultipleCarriers(int count) {
    return 'Bileşik ($count taşıyıcı)';
  }

  @override
  String get compositeBadgeSingleCarrier => 'Bileşik taşıyıcı (1 seçili)';

  @override
  String get compositeBadgeDefault => 'Bileşik kapsayıcı';

  @override
  String get compositeSingleCarrierWarningBanner =>
      'Bileşik taşıyıcı algılandı. Bileşik bir kapsayıcının kilidini açmak için tüm taşıyıcı dosyaları gerekir.';

  @override
  String get compositeCarriersMissingTitle => 'Bileşik taşıyıcılar eksik';

  @override
  String get compositeCarriersMissingExplanation =>
      'Bir veya daha fazla taşıyıcı dosyaya artık erişilemiyor ya da taşınmış.';

  @override
  String get compositeRelocateCarriersButton =>
      'Taşıyıcı dosyaları yeniden bul';

  @override
  String get generateStrongPasswordTooltip => 'Güçlü parola oluştur';

  @override
  String get cryfsBlockSizeDefaultLabel => '32 KiB (varsayılan)';

  @override
  String get hiddenVolumeConfiguredInNextStepNotice =>
      'Gizli birim parametreleri sonraki adımda yapılandırılacak.';

  @override
  String get hiddenVolumeExplanationBanner =>
      'Gizli birim, dış birimin boş alanında bulunur. Parolası ve anahtar dosyaları dış birimden FARKLI olmalıdır.';

  @override
  String get hiddenVolumeCredentialsSectionHeader =>
      'Gizli birim kimlik bilgileri';

  @override
  String get hiddenVolumeSizeAndFormatSectionHeader =>
      'Gizli birim boyutu ve biçimi';

  @override
  String get shareSheetIntegrationTitle => 'Paylaşım menüsü entegrasyonu';

  @override
  String get shareSheetIntegrationSubtitle =>
      'Diğer uygulamaların Android\'in Paylaş menüsüyle dosyaları doğrudan bir kasaya paylaşmasına izin verin.';

  @override
  String get shareSheetIntegrationUpdateErrorMessage =>
      'Paylaşım menüsü entegrasyonu güncellenemedi.';

  @override
  String get autoLockOnShareImportTitle =>
      'Paylaşımla içe aktarmadan sonra otomatik kilitle';

  @override
  String get autoLockOnShareImportSubtitle =>
      'Bir kasa yalnızca paylaşılan bir dosyayı içe aktarmak için açıldıysa otomatik olarak yeniden kilitle';

  @override
  String get shareImportExpiredMessage =>
      'İçe aktarılacak bir şey yok -- paylaşım isteğinin süresi doldu.';

  @override
  String get sharedFileDefaultDisplayName => 'Paylaşılan dosya';

  @override
  String importingSharedFilesMessage(int count, String destination) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'İçe aktarılıyor: $count dosya → $destination',
      one: 'İçe aktarılıyor: 1 dosya → $destination',
    );
    return '$_temp0';
  }

  @override
  String sharedFileSavedMessage(int count, String destination) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Kaydedildi: $count dosya → $destination',
      one: 'Kaydedildi: 1 dosya → $destination',
    );
    return '$_temp0';
  }

  @override
  String get sharedFileSaveFailedMessage => 'Paylaşılan dosya kaydedilemedi.';

  @override
  String get saveToVaultTitle => 'Kasaya kaydet';

  @override
  String get noVaultsAvailableAddFromDashboardPrompt =>
      'Henüz kasa yok. Önce panodan bir tane ekleyin.';

  @override
  String get vaultStatusUnlocked => 'Kilidi açık';

  @override
  String get vaultStatusLocked => 'Kilitli';

  @override
  String get compositeCarrierGrowthSectionHeader => 'Gizlilik ve kapasite';

  @override
  String get compositeCarrierGrowthSliderTitle => 'Taşıyıcı dosya büyümesi';

  @override
  String compositeCarrierGrowthPercentLabel(int percent) {
    return '+$percent% dosya başına';
  }

  @override
  String get compositeCarrierGrowthUltraStealthDesc =>
      'Ultra gizlilik (~%5): Dosyalar neredeyse hiç büyümez. Doğal kamera sensörü farklarından tamamen ayırt edilemez.';

  @override
  String get compositeCarrierGrowthRecommendedDesc =>
      'Önerilen (~%10): Gizliliği iyi bir kullanılabilir kasa kapasitesiyle dengeler.';

  @override
  String get compositeCarrierGrowthHighCapacityDesc =>
      'Yüksek kapasite (~%20+): Kasa alanını en üst düzeye çıkarır, ama taşıyıcı dosyalar gözle görülür biçimde büyür.';

  @override
  String get emergencyPanicTitle => 'Acil panik ve baskı altı kilit açma';

  @override
  String get emergencyPanicSubtitle =>
      'Panik tetikleyicileri, Hızlı Ayarlar karosu, PanicKit ve baskı altı kilit açma';

  @override
  String get sectionPanicTiers => 'Panik temizleme düzeyi';

  @override
  String get panicTierSessionLabel => 'Düzey 1: Oturum temizleme';

  @override
  String get panicTierSessionSubtitle =>
      'Kasaları ayır, belleği sıfırla ve hatırlanan kasa parolalarını/kimlik bilgilerini temizle';

  @override
  String get panicTierCredentialLabel => 'Düzey 2: Kimlik bilgisi temizleme';

  @override
  String get panicTierCredentialSubtitle =>
      'Pano kasa listesini sil, ana kilidi ve uygulama ayarlarını sıfırla, Keystore\'u temizle';

  @override
  String get panicTierNuclearLabel => 'Düzey 3: Tam imha';

  @override
  String get panicTierNuclearSubtitle =>
      'Tüm uygulama depolamasını diskte sıfırla doldurup parçala, ardından sistemden kaldırma iste';

  @override
  String get panicQuickTileTitle => 'Hızlı Ayarlar karosu';

  @override
  String get panicQuickTileSubtitle =>
      'Hızlı Ayarlar karosunu, yapılandırılmış panik düzeyini anında tetikleyecek şekilde kur';

  @override
  String get triggerPanicNowTitle => 'Paniği şimdi tetikle';

  @override
  String get triggerPanicNowSubtitle =>
      'Yapılandırılmış panik temizleme düzeyini hemen uygula';

  @override
  String get triggerPanicConfirmTitle => 'Acil panik tetiklensin mi?';

  @override
  String triggerPanicConfirmMessage(String tier) {
    return 'Bu işlem hemen şunu uygulayacak: $tier. Açık kapsayıcılar ve kimlik bilgileri bu düzeye göre temizlenecek.';
  }

  @override
  String get triggerPanicButton => 'Paniği tetikle';

  @override
  String get sectionPanicBootTrigger => 'Yeniden başlatmada sil';

  @override
  String get panicBootTriggerLevelLabel =>
      'Yeniden başlatmada çalıştırılacak düzey';

  @override
  String get panicBootTriggerArmTitle => 'Sonraki açılış için kur';

  @override
  String panicBootTriggerArmedSubtitle(Object tier) {
    return 'Kuruldu — bu cihaz bir sonraki açıldığında $tier otomatik çalışacak, sonra kendini devre dışı bırakacak';
  }

  @override
  String get panicBootTriggerDisarmedSubtitle =>
      'Kapalı — bu cihazı yeniden başlatmak normal davranır';

  @override
  String get panicBootTriggerConfirmTitle =>
      'Yeniden başlatmada silme kurulsun mu?';

  @override
  String panicBootTriggerConfirmMessage(Object tier) {
    return 'Bu cihaz bir sonraki açıldığında — yalnızca sizin tetiklediğiniz değil, sıradan bir yeniden başlatma veya otomatik güncelleme dahil — uygulamayı açmadan önce $tier otomatik çalışacak. Bu bir kez tetiklenir, sonra kendini devre dışı bırakır.';
  }

  @override
  String get panicBootTriggerArmButton => 'Kur';

  @override
  String get panicBootTriggerArmedSuccessMessage =>
      'Açılış tetikleyicisi kuruldu';

  @override
  String get panicBootTriggerDisarmedSuccessMessage =>
      'Açılış tetikleyicisi devre dışı bırakıldı';

  @override
  String get sectionPanicKit => 'PanicKit yanıtlayıcısı';

  @override
  String get panicKitEnableTitle => 'PanicKit yanıtlayıcısı';

  @override
  String get panicKitEnableSubtitle =>
      'Eşleştirilmiş harici panik uygulamalarının (örn. Ripple, Wasted) paniği tetiklemesine izin ver';

  @override
  String get panicKitEnforcePairingTitle =>
      'Uygulama eşleştirmesini zorunlu kıl';

  @override
  String get panicKitEnforcePairingSubtitle =>
      'Her tetikleme yayınında paket kimliğini ve SHA-256 sertifika özetini doğrula';

  @override
  String get panicKitPairedAppLabel => 'Eşleştirilmiş tetikleyici uygulama';

  @override
  String get panicKitNoAppPaired => 'Eşleştirilmiş tetikleyici uygulama yok';

  @override
  String get panicKitUnpairButton => 'Eşleşmeyi kaldır';

  @override
  String get panicKitUnpairSuccess =>
      'PanicKit tetikleyicisinin eşleşmesi kaldırıldı';

  @override
  String get sectionDuressUnlock => 'Ana kilit baskı altı modu';

  @override
  String get duressPasswordTitle => 'Baskı altı parolası';

  @override
  String get duressPasswordConfiguredSubtitle =>
      'Etkin — kilit ekranında bu parolayı girmek baskı altı modunu tetikler';

  @override
  String get duressPasswordNotConfiguredSubtitle =>
      'Acil eylemleri tetiklemek için kilit ekranında farklı bir parola girin';

  @override
  String get removeDuressPasswordButton => 'Baskı altı parolasını kaldır';

  @override
  String get duressPasswordSetSuccess => 'Baskı altı parolası ayarlandı';

  @override
  String get duressPasswordRemovedSuccess => 'Baskı altı parolası kaldırıldı';

  @override
  String get duressPinConfiguredTitle => 'Baskı altı PIN\'i';

  @override
  String get duressPinConfiguredSubtitle =>
      'Etkin — tuş takımında bu PIN\'i girmek baskı altı modunu tetikler';

  @override
  String get duressPinNotConfiguredSubtitle =>
      'Acil eylemleri tetiklemek için tuş takımında farklı bir PIN girin';

  @override
  String get removeDuressPinButton => 'Baskı altı PIN\'ini kaldır';

  @override
  String get duressPinSetSuccess => 'Baskı altı PIN\'i ayarlandı';

  @override
  String get duressPinRemovedSuccess => 'Baskı altı PIN\'i kaldırıldı';

  @override
  String get duressPatternTitle => 'Baskı altı deseni';

  @override
  String get duressPatternConfiguredSubtitle =>
      'Etkin — bu deseni çizmek baskı altı modunu tetikler';

  @override
  String get duressPatternNotConfiguredSubtitle =>
      'Acil eylemleri tetiklemek için kilit ekranında farklı bir desen çizin';

  @override
  String get removeDuressPatternButton => 'Baskı altı desenini kaldır';

  @override
  String get duressPatternSetSuccess => 'Baskı altı deseni ayarlandı';

  @override
  String get duressPatternRemovedSuccess => 'Baskı altı deseni kaldırıldı';

  @override
  String get duressMatchesMasterPasswordError =>
      'Baskı altı parolası ana parolayla aynı olamaz';

  @override
  String get duressMatchesMasterPinError => 'Ana PIN ile aynı olamaz';

  @override
  String get duressMatchesMasterPatternError => 'Ana desenle aynı olamaz';

  @override
  String get masterMatchesDuressPasswordError =>
      'Ana parola baskı altı parolasıyla aynı olamaz';

  @override
  String get masterMatchesDuressPinError => 'Baskı altı PIN\'i ile aynı olamaz';

  @override
  String get masterMatchesDuressPatternError =>
      'Baskı altı deseniyle aynı olamaz';

  @override
  String get toolCompositeContainerTitle => 'Bileşik kapsayıcı';

  @override
  String get toolCompositeContainerSubtitle =>
      'Şifreli bir kasayı birden fazla medya dosyasına gömün ve bağlayın';

  @override
  String get compositePasswordChangeNotSupportedMessage =>
      'Bileşik kapsayıcılarda parola değiştirme desteklenmiyor';

  @override
  String get compositeNoCarrierFilesFoundError =>
      'Bileşik kapsayıcı için taşıyıcı dosya bulunamadı';

  @override
  String get compositeIncorrectCredentialsOrCarrierMismatchError =>
      'Kimlik bilgileri yanlış veya taşıyıcı kümesi uyuşmuyor';

  @override
  String get incorrectCredentialsOrInvalidContainer =>
      'Kimlik bilgileri yanlış veya kapsayıcı geçersiz';

  @override
  String get repairTargetFolderVaultOption => 'Klasör kasası';

  @override
  String get repairTargetFolderVaultSubtitle =>
      'gocryptfs, CryFS veya Cryptomator';

  @override
  String get repairFolderVaultHealthyDeepScan =>
      'Sorun bulunamadı -- her dosyanın içeriği doğrulandı.';

  @override
  String get repairFolderVaultHealthyStructureOnly =>
      'Yapısal sorun bulunamadı. Dosya içeriklerini de doğrulamak için parolayla derin tarama çalıştırın.';

  @override
  String repairFolderVaultIssuesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sorun bulundu',
      one: '1 sorun bulundu',
    );
    return '$_temp0';
  }

  @override
  String get repairFolderVaultStructureOnlySuffix =>
      ' (yalnızca yapı -- tam içerik denetimi için derin tarama çalıştırın)';

  @override
  String get repairDeepScanWithPasswordButton => 'Parolayla derin tarama';

  @override
  String repairFolderVaultSummary(
    Object fixed,
    Object recovered,
    Object removed,
  ) {
    return 'Onarım özeti: $fixed düzeltildi, $recovered /LOST+FOUND içine kurtarıldı, $removed temizlendi.';
  }

  @override
  String get repairAndRecoverVaultButton => 'Kasayı onar ve kurtar';

  @override
  String get repairScanAgainButton => 'Yeniden tara';

  @override
  String panicPurgeCompletedMessage(Object count) {
    return 'Panik temizleme tamamlandı ($count kilitlendi).';
  }

  @override
  String get usbPermissionRequiredError => 'USB izni gerekli';

  @override
  String get logcatScrollToBottomTooltip => 'En alta kaydır';

  @override
  String logcatLinesCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count satır',
      one: '1 satır',
    );
    return '$_temp0';
  }

  @override
  String get compositeSpaceTooSmallError =>
      'Ayrılabilir alan çok küçük (en az 300 KB gerekir)';

  @override
  String get compositeInitializingStatusMessage =>
      'Bileşik VeraCrypt birimi başlatılıyor…';

  @override
  String get compositeCreationFailedError => 'Bileşik kapsayıcı oluşturulamadı';

  @override
  String get compositeSelectCarriersFirstError =>
      'Lütfen önce taşıyıcı dosyalarını seç';

  @override
  String get compositePasswordOrKeyfileRequiredError =>
      'Parola veya anahtar dosyası gerekli';

  @override
  String get compositeMountingStatusMessage => 'Bileşik birim bağlanıyor…';

  @override
  String get compositeAuthFailedOrCarrierMismatchError =>
      'Kimlik doğrulama başarısız veya taşıyıcı kümesi uyuşmuyor';

  @override
  String get layoutModeColumnedList => 'Sütunlu liste';

  @override
  String get longFileNameDisplayLabel => 'Uzun dosya adları';

  @override
  String get longFileNameEllipsizeStartLabel => 'Başı kısalt';

  @override
  String get longFileNameEllipsizeStartDesc =>
      'Uzun adların başını kısaltır, sonunu ve dosya uzantısını görünür tutar.';

  @override
  String get longFileNameEllipsizeMiddleLabel => 'Ortayı kısalt';

  @override
  String get longFileNameEllipsizeMiddleDesc =>
      'Uzun adların ortasını kısaltır, başını ve dosya uzantısını görünür tutar.';

  @override
  String get longFileNameEllipsizeEndLabel => 'Sonu kısalt';

  @override
  String get longFileNameEllipsizeEndDesc =>
      'Uzun adların sonunu kısaltır, başını görünür tutar.';

  @override
  String get longFileNameMarqueeLabel => 'Kaydır (kayan yazı)';

  @override
  String get longFileNameMarqueeDesc =>
      'Adın tamamını korur ve hepsi okunabilsin diye yavaşça ileri geri kaydırır.';

  @override
  String get showItemActionsMenuLabel => '3 noktalı öğe menülerini göster';

  @override
  String get showItemActionsMenuDesc =>
      'Liste, ızgara ve mozaik görünümlerinde dosya ve klasörlerde 3 noktalı eylem düğmesini göster';

  @override
  String get gridAspectRatioLabel => 'Izgara en boy oranı';

  @override
  String get gridAspectSquareLabel => '1:1 (Kare)';

  @override
  String get gridAspectLandscapeLabel => '16:9 (Yatay)';

  @override
  String get gridAspectPortraitLabel => '9:16 (Dikey)';

  @override
  String get autoHideAppBarLabel =>
      'Kaydırırken uygulama çubuğunu otomatik gizle';

  @override
  String get autoHideAppBarDesc =>
      'Görüntüleme alanını en üst düzeye çıkarmak için aşağı kaydırırken üst çubuğu gizle';

  @override
  String get autoHideToolbarLabel => 'Kaydırırken araç çubuğunu otomatik gizle';

  @override
  String get autoHideToolbarDesc =>
      'Görüntüleme alanını genişletmek için aşağı kaydırırken alt araç çubuğunu gizle';

  @override
  String get autoHideBreadcrumbBarLabel =>
      'Kaydırırken klasör yolu çubuğunu otomatik gizle';

  @override
  String get autoHideBreadcrumbBarDesc =>
      'Görüntüleme alanını genişletmek için aşağı kaydırırken klasör yolu çubuğunu gizle';

  @override
  String get useFabForToolbarLabel => 'Araç çubuğu için yüzen düğme kullan';

  @override
  String get useFabForToolbarDesc =>
      'Görüntüleme alanını en üst düzeye çıkarmak için alt çubuğu tek bir yüzen düğmeyle değiştir';

  @override
  String get bottomSelectionBarLabel => 'Seçim çubuğunu altta göster';

  @override
  String get bottomSelectionBarDesc =>
      'Seçim araç çubuğunu üstte değil altta göster';

  @override
  String get clipboardFabTapToPaste =>
      'Yapıştırmak için dokunun, ayrıntılar için basılı tutun';

  @override
  String get storageLocationsTitle => 'Depolama konumları';

  @override
  String get addStorageLocationTitle => 'Depolama konumu ekle';

  @override
  String get addStorageLocationSubtitle =>
      'Harici bir SD kart, USB sürücü veya klasör ekle';

  @override
  String get renameStorageLocationTitle => 'Konumu yeniden adlandır';

  @override
  String get removeStorageLocationTitle => 'Konumu kaldır';

  @override
  String removeStorageLocationConfirm(String name) {
    return '\"$name\" depolama konumlarından kaldırılsın mı? Depolamadaki dosyalar silinmez.';
  }

  @override
  String get storageLocationUnresolvedError =>
      'Bu konuma doğrudan erişilemedi. Depolama izinlerinin verildiğinden emin ol.';

  @override
  String get storageLocationSelfReferenceError =>
      'Burası zaten bu uygulamanın kendi kasa depolaması, bu yüzden harici konum olarak yeniden eklenemez. Bunun yerine kasa listenizden açın.';

  @override
  String get internalStorageSubtitle => 'Dahili depolama';

  @override
  String get mediaViewerActionPlayPause => 'Oynat / Duraklat';

  @override
  String get mediaViewerActionPlaybackMode => 'Oynatma modu';

  @override
  String get mediaViewerActionBookmark => 'Yer imi ekle';

  @override
  String get mediaViewerActionDiagnostics => 'Tanılama';

  @override
  String get mediaViewerCustomizeControls => 'Denetimleri özelleştir...';

  @override
  String get mediaPlayerControlsTitle => 'Medya oynatıcı denetimleri';

  @override
  String get resumePlaybackTitle => 'Oynatmayı sürdür';

  @override
  String get resumePlaybackAskEveryTime => 'Her seferinde sor';

  @override
  String get resumePlaybackNever => 'Asla';

  @override
  String get resumePlaybackAlways => 'Her zaman';

  @override
  String get resumePlaybackPromptTitle => 'Oynatma sürdürülsün mü?';

  @override
  String resumePlaybackPromptMessage(String position) {
    return 'Şuradan devam: $position?';
  }

  @override
  String get resumePlaybackStartOver => 'Baştan başla';

  @override
  String get resumePlaybackResume => 'Sürdür';

  @override
  String get pictureInPictureTitle => 'Otomatik pencere içinde pencere';

  @override
  String get pictureInPictureSubtitle =>
      'Video oynarken uygulamadan çıktığınızda pencere içinde pencereye geç';

  @override
  String get pictureInPictureAction => 'Pencere içinde pencere';

  @override
  String get mediaViewerActionLockControls => 'Denetimleri kilitle';

  @override
  String get mediaViewerHoldToUnlock => 'Kilidi açmak için basılı tutun';

  @override
  String get keepAudioPlayingTitle =>
      'Kapattıktan sonra sesi çalmaya devam ettir';

  @override
  String get keepAudioPlayingSubtitle =>
      'Oynatıcıdan çıktığınızda ses arka planda çalmaya devam eder; denetlemek için bildirimi kullanın';

  @override
  String get mediaControlsResetSuccess =>
      'Medya denetimleri varsayılanlara sıfırlandı';

  @override
  String get playbackAndDisplayHeader => 'Oynatma ve görüntü';

  @override
  String get showProgressBarTitle => 'İlerleme çubuğunu göster (kaydırıcı)';

  @override
  String get showProgressBarSubtitle =>
      'Video ve sesler için zaman çizelgesi kaydırıcısı';

  @override
  String get scrubPreviewStyleTitle => 'Kaydırma önizleme stili';

  @override
  String get scrubPreviewMiniBoxLabel => 'Mini kutu';

  @override
  String get scrubPreviewMiniBoxDesc =>
      'Arama çubuğunun üstünde küçük önizleme';

  @override
  String get scrubPreviewFullscreenLabel => 'Tam ekran';

  @override
  String get scrubPreviewFullscreenDesc =>
      'Arama çubuğunu sürüklerken büyük kare ekranı kaplar';

  @override
  String get showTransportControlsOnPhotosTitle =>
      'Fotoğraflarda oynatma denetimlerini göster';

  @override
  String get showTransportControlsOnPhotosSubtitle =>
      'Resimlerde slayt gösterisi denetimlerini etkinleştir (sade görünüm için kapalı)';

  @override
  String get statusBadgeTitle => 'Durum rozeti';

  @override
  String get statusBadgeSubtitle =>
      'Slayt gösterisi oynarken geri sayımı gösterir';

  @override
  String get topBarActionsHeader => 'Üst çubuk eylemleri';

  @override
  String get topBarActionsEmptyHint =>
      'Üst çubuğa sabitlemek için işlemleri buraya sürükle';

  @override
  String get bottomDockActionsHeader => 'Alt çubuk eylemleri';

  @override
  String get bottomDockActionsEmptyHint =>
      'Alt panele sabitlemek için işlemleri buraya sürükle';

  @override
  String get moreMenuActionsHeader => 'Diğer menüsü (•••) eylemleri';

  @override
  String get moreMenuActionsEmptyHint =>
      'Üst çubuk açılır menüsü için işlemleri buraya sürükle';

  @override
  String get advancedSettingsActionsHeader => 'Gelişmiş ayar eylemleri (taşan)';

  @override
  String get advancedSettingsActionsEmptyHint =>
      'Gelişmiş Ayarlar paneli için işlemleri buraya sürükle';

  @override
  String get moveToAdvancedSettingsTooltip => 'Gelişmiş ayarlara taşı';

  @override
  String get dashboardNavLabel => 'Pano';

  @override
  String get vaultsSectionTitle => 'Kasalar';

  @override
  String get lockVaultTooltip => 'Kasayı kilitle';

  @override
  String get lockAllVaultsTitle => 'Tümünü kilitle';

  @override
  String get contentsLabel => 'İçerik';

  @override
  String get totalSizeLabel => 'Toplam boyut';

  @override
  String folderItemCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe',
      one: '1 öğe',
      zero: 'Boş',
    );
    return '$_temp0';
  }

  @override
  String get calculatingFolderStats => 'Hesaplanıyor…';

  @override
  String get videoGesturesHeader => 'Video hareketleri ve yakınlaştırma';

  @override
  String get swipeToSeekTitle => 'Kaydırarak ara';

  @override
  String get swipeToSeekSubtitle =>
      'Aramak için ekran boyunca yatay kaydırın. Oynatma listelerinde öğeler arasında kaydırmak yerine gezinme düğmeleri kullanılmalıdır';

  @override
  String get swipeToDismissTitle => 'Kapatmak için kaydır';

  @override
  String get swipeToDismissSubtitle =>
      'Görüntüleyiciyi aşağı kaydırarak kapatın. Bir oynatma listesi dikey kayıyorsa bunun yerine yana kaydırın';

  @override
  String get edgeSwipeBrightnessTitle => 'Parlaklık kaydırma hareketi';

  @override
  String get edgeSwipeBrightnessSubtitle =>
      'Ekran parlaklığını ayarlamak için sol kenarın yakınında kaydırın';

  @override
  String get edgeSwipeVolumeTitle => 'Ses kaydırma hareketi';

  @override
  String get edgeSwipeVolumeSubtitle =>
      'Sesi ayarlamak için sağ kenarın yakınında kaydırın';

  @override
  String get edgeSwipeHudTitle => 'Hareket göstergesini göster';

  @override
  String get edgeSwipeHudSubtitle => 'Kaydırırken yüzde katmanı göster';

  @override
  String get edgeSwipeWidthTitle => 'Kenar bölgesi genişliği';

  @override
  String get pinchZoomOutTitle => 'Uzaklaştırmaya izin ver';

  @override
  String get pinchZoomOutSubtitle =>
      'Videoyu normal boyutunun altına küçültmek için çimdikleyin';

  @override
  String get minZoomTitle => 'En düşük yakınlaştırma düzeyi';

  @override
  String get holdSpeedMultiplierTitle =>
      'Basılı tutarak hızlı ileri sarma hızı';

  @override
  String get defaultAspectRatioTitle => 'Varsayılan en boy oranı';

  @override
  String get aspectRatioModeLabel => 'En boy oranı';

  @override
  String get aspectRatioBestFit => 'En iyi sığdır';

  @override
  String get aspectRatioFill => 'Doldur';

  @override
  String get aspectRatio16x9 => '16:9';

  @override
  String get aspectRatio4x3 => '4:3';

  @override
  String get aspectRatioCentre => 'Ortala';

  @override
  String get autoSyncMenuAction => 'Otomatik eşitleme…';

  @override
  String get autoSyncSheetTitle => 'Otomatik eşitleme';

  @override
  String get autoSyncSheetIntro =>
      'Bu klasörü ve başka bir klasörü otomatik olarak eşit tutar. Aynı dosya iki tarafta da değiştiyse, aşağıda başka bir seçim yapmadığınız sürece iki sürüm de korunur.';

  @override
  String get autoSyncTargetSection => 'Eşitlenecek konum';

  @override
  String get autoSyncChooseFolder => 'Bir klasör seçin';

  @override
  String get autoSyncTargetNotSetHere =>
      'Bu kural başka bir cihazda oluşturulmuş. Bu cihazda kullanılacak klasörü seçin.';

  @override
  String get autoSyncPickerSideLabel => 'Eşitleme hedefi';

  @override
  String get autoSyncDirectionSection => 'Yön';

  @override
  String get autoSyncDirectionTwoWay => 'İki yönlü';

  @override
  String get autoSyncDirectionTwoWayHint =>
      'Her iki taraftaki değişiklikler diğerine kopyalanır.';

  @override
  String get autoSyncDirectionVaultToTarget => 'Kasadan klasöre';

  @override
  String get autoSyncDirectionVaultToTargetHint =>
      'Bir yedekleme: klasör kasayı izler. Klasörde yapılan değişiklikler geri kopyalanmaz.';

  @override
  String get autoSyncDirectionTargetToVault => 'Klasörden kasaya';

  @override
  String get autoSyncDirectionTargetToVaultHint =>
      'Bir içe aktarma: kasa klasörü izler. Kasada yapılan değişiklikler geri kopyalanmaz.';

  @override
  String get autoSyncConflictSection =>
      'Her iki taraf da bir dosyayı değiştirdiyse';

  @override
  String get autoSyncConflictKeepBoth => 'İki sürümü de koru';

  @override
  String get autoSyncConflictKeepBothHint =>
      'Diğer sürüm, her iki tarafta da yeniden adlandırılmış bir kopya olarak korunur.';

  @override
  String get autoSyncConflictKeepNewer => 'Yeni olanı koru';

  @override
  String get autoSyncConflictKeepNewerHint =>
      'Hangisinin daha yeni olduğu anlaşılamazsa ikisini de korur.';

  @override
  String get autoSyncConflictVaultWins => 'Kasa sürümü geçerli';

  @override
  String get autoSyncConflictVaultWinsHint =>
      'Klasörün sürümünün yerine geçer.';

  @override
  String get autoSyncConflictTargetWins => 'Klasör sürümü geçerli';

  @override
  String get autoSyncConflictTargetWinsHint =>
      'Kasanın sürümünün yerine geçer.';

  @override
  String get autoSyncOptionsSection => 'Seçenekler';

  @override
  String get autoSyncOnUnlockTitle => 'Kasanın kilidi açıldığında eşitle';

  @override
  String get autoSyncLiveTitle => 'Kilit açıkken eşit tut';

  @override
  String get autoSyncLiveSubtitle =>
      'Kasa açıkken zaman zaman değişiklikleri denetler. Her değişiklik hemen fark edilmez.';

  @override
  String get autoSyncDeleteTitle => 'Silmeleri de kopyala';

  @override
  String get autoSyncDeleteSubtitle =>
      'Bir tarafta silinen dosya diğer tarafta da silinir. Bir klasör beklenmedik şekilde boş görünürse silmeler duraklatılır.';

  @override
  String get autoSyncDeleteSourceAfterImportTitle =>
      'İçe aktarmadan sonra kaynak dosyaları sil';

  @override
  String get autoSyncDeleteSourceAfterImportSubtitle =>
      'Yalnızca klasörden kasaya eşitleme için. Kasadaki kopya işlendikten ve SHA-256 sağlama toplamı eşleştikten sonra kaynak dosya silinir.';

  @override
  String get autoSyncIgnoreLabel => 'Eşleşen dosya ve klasörleri atla';

  @override
  String get autoSyncIgnoreHelper =>
      'Satır başına bir kalıp: *.tmp her yerdeki adları eşler; node_modules o klasörü ve içeriğini her yerde atlar; Projects/old eşitleme kökünden başlayan o yolu ve içindeki her şeyi atlar.';

  @override
  String get autoSyncNeverSynced => 'Henüz eşitlenmedi';

  @override
  String autoSyncLastSynced(String time) {
    return 'Son eşitleme: $time';
  }

  @override
  String autoSyncReportSummary(int copied, int deleted, int kept) {
    return '$copied kopyalandı · $deleted silindi · $kept çakışma korundu';
  }

  @override
  String autoSyncReportFailed(int count) {
    return 'Eşitlenemeyen dosyalar: $count';
  }

  @override
  String get autoSyncReportDeletionsPaused =>
      'Bir klasör beklenmedik şekilde boş göründüğü veya çok fazla dosya silineceği için silmeler duraklatıldı.';

  @override
  String get autoSyncReportIncomplete =>
      'Bir klasörün bir kısmı okunamadı, bu yüzden o dosyalara dokunulmadı.';

  @override
  String get autoSyncSyncNow => 'Şimdi eşitle';

  @override
  String get autoSyncRemove => 'Otomatik eşitlemeyi kaldır';

  @override
  String get autoSyncRemoveTitle => 'Otomatik eşitleme kaldırılsın mı?';

  @override
  String get autoSyncRemoveMessage =>
      'Bu klasör için eşitleme durur. Her iki klasördeki dosyalar olduğu gibi kalır.';

  @override
  String get autoSyncSaved => 'Otomatik eşitleme kaydedildi';

  @override
  String get autoSyncStarted => 'Eşitleme başladı';

  @override
  String get autoSyncRemoved => 'Otomatik eşitleme kaldırıldı';

  @override
  String get autoSyncSaveFailed => 'Otomatik eşitleme ayarları kaydedilemedi';

  @override
  String get autoSyncUnavailable =>
      'Eşitleme şu anda bu kasa için kullanılamıyor.';

  @override
  String get autoSyncProblemNoTarget => 'Eşitlenecek bir klasör seçin.';

  @override
  String get autoSyncProblemOverlapsTarget =>
      'Eşitlenecek klasör bu klasörün içinde olamaz veya onu içeremez.';

  @override
  String get autoSyncProblemOverlapsOtherRule =>
      'Bu klasörde, üstündeki veya içindeki bir klasörde zaten otomatik eşitleme var.';

  @override
  String get autoSyncProblemTargetIsVault =>
      'Bu klasör bir kasanın şifreli verilerini tutuyor. O kasanın kilidini açın ve bunun yerine kasa listesinden seçin.';

  @override
  String get autoSyncReadOnlyNotice =>
      'Bu kasa salt okunur, bu yüzden otomatik eşitleme kaydedilemez.';

  @override
  String get autoSyncConfigUnreadable =>
      'Bu kasa için kaydedilmiş otomatik eşitleme ayarları okunamadı.';

  @override
  String autoSyncBannerRunning(String target, int done, int total) {
    return 'Eşitleniyor: $target · $done / $total';
  }

  @override
  String get autoSyncBannerAttention =>
      'Bazı klasörler tamamen eşitlenemedi. Ayrıntılar için bir klasörün Otomatik eşitleme ayarlarını açın.';

  @override
  String get autoSyncNotificationTitle => 'Klasörler eşitleniyor';

  @override
  String autoSyncNotificationProgress(int done, int total) {
    return '$done / $total dosya';
  }

  @override
  String get sectionQuickCapture => 'Hızlı yakalama';

  @override
  String get quickCaptureSettingsTitle => 'Hızlı yakalama';

  @override
  String get quickCaptureSettingsSubtitle =>
      'Doğrudan bir kasaya çekim yapmak için Hızlı Ayarlar karosu ve ana ekran kısayolu';

  @override
  String get quickCaptureTileToggleTitle => 'Hızlı Ayarlar karosu';

  @override
  String get quickCaptureTileToggleSubtitle =>
      'Kamerayı PIN veya desen istemeden doğrudan Hızlı Ayarlar\'dan açar. Bir şey kaydedilmeden önce yine de bir kasa seçip kilidini açarsınız.';

  @override
  String get quickCaptureAddShortcutTitle => 'Ana ekrana ekle';

  @override
  String get quickCaptureAddShortcutSubtitle =>
      'Başlatıcınız destekliyorsa ana ekranınıza bir Hızlı Yakalama simgesi sabitleyin';

  @override
  String get quickCaptureShortcutRequestedMessage =>
      'İstendi — ana ekranınıza bakın';

  @override
  String get quickCaptureShortcutUnsupportedMessage =>
      'Başlatıcınız kısayol sabitlemeyi desteklemiyor';

  @override
  String quickCaptureSavedToast(String name, String destination) {
    return 'Kaydedildi: $name → $destination';
  }

  @override
  String get appLockBehaviorTitle => 'Uygulama kilidi davranışı';

  @override
  String get lockAppOnScreenOffTitle => 'Ekran kapanınca uygulamayı kilitle';

  @override
  String get lockAppOnScreenOffSubtitle =>
      'Ekran kapanır kapanmaz kilit ekranını göster';

  @override
  String get settingsHubSecuritySubtitle =>
      'Ana kilit, biyometri ve otomatik kilit';

  @override
  String get settingsHubStorageSubtitle =>
      'Depolama erişimi, arka plan hizmeti ve paylaşım menüsü';

  @override
  String get settingsHubFileHandlingSubtitle =>
      'Otomatik açma, küçük resimler ve dosya ilişkilendirmeleri';

  @override
  String get settingsHubAppearanceSubtitle => 'Temalar, saf siyah OLED ve dil';

  @override
  String get settingsHubAdvancedSubtitle =>
      'Ayar yedeği, hata ayıklama günlükleri ve logcat';

  @override
  String get toolPasswordInterchangeTitle => 'Parolaları içe / dışa aktar';

  @override
  String get toolPasswordInterchangeSubtitle =>
      'Girişleri, kartları ve notları KeePass, Bitwarden ve diğer parola yöneticilerine veya onlardan taşıyın';

  @override
  String get toolsSectionPasswordManager => 'Parola yöneticisi';

  @override
  String get passwordInterchangeExportTab => 'Dışa aktar';

  @override
  String get passwordInterchangeImportTab => 'İçe aktar';

  @override
  String get passwordInterchangeSourceHeader => 'Kaynak';

  @override
  String get passwordInterchangeChooseFolder => 'Bir kasa klasörü seçin';

  @override
  String get passwordInterchangeIncludeSubfolders => 'Alt klasörleri dahil et';

  @override
  String get passwordInterchangeFormatLabel => 'Dosya biçimi';

  @override
  String get passwordInterchangeMasterPassword => 'Ana parola';

  @override
  String get passwordInterchangeConfirmPassword => 'Parolayı onayla';

  @override
  String get passwordInterchangePasswordsDontMatch => 'Parolalar eşleşmiyor';

  @override
  String get passwordInterchangeRunExport => 'Dışa aktar';

  @override
  String passwordInterchangeExportReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe dışa aktarmaya hazır',
      one: '1 öğe dışa aktarmaya hazır',
    );
    return '$_temp0';
  }

  @override
  String get passwordInterchangeSaveToDevice => 'Cihaza kaydet…';

  @override
  String get passwordInterchangeSaved => 'Kaydedildi.';

  @override
  String get passwordInterchangeFileHeader => 'Dosya';

  @override
  String get passwordInterchangeChooseFile => 'Bir dosya seçin…';

  @override
  String get passwordInterchangeReadFile => 'Dosyayı oku';

  @override
  String passwordInterchangeFoundItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bulundu: $count öğe',
      one: 'Bulundu: 1 öğe',
    );
    return '$_temp0';
  }

  @override
  String get passwordInterchangeSelectAll => 'Tümünü seç';

  @override
  String get passwordInterchangeSelectNone => 'Hiçbirini seçme';

  @override
  String passwordInterchangeWarningsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count satır okunamadı',
      one: '1 satır okunamadı',
    );
    return '$_temp0';
  }

  @override
  String get passwordInterchangeDestinationHeader => 'Şuraya kaydet';

  @override
  String get passwordInterchangeMirrorFolders => 'Klasörleri yeniden oluştur';

  @override
  String passwordInterchangeRunImport(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'İçe aktar: $count öğe',
      one: 'İçe aktar: 1 öğe',
    );
    return '$_temp0';
  }

  @override
  String passwordInterchangeImportedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'İçe aktarıldı: $count öğe',
      one: 'İçe aktarıldı: 1 öğe',
    );
    return '$_temp0';
  }

  @override
  String passwordInterchangeSkippedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe atlandı',
      one: '1 öğe atlandı',
    );
    return '$_temp0';
  }

  @override
  String autoLockIndicatorLocksAfter(String duration) {
    return 'Hareketsizlik kilidi: $duration';
  }

  @override
  String autoLockIndicatorLocksAfterTooltip(String duration) {
    return '$duration hareketsizlikten sonra kilitlenir (uygulama kullanılırken sıfırlanır)';
  }

  @override
  String get badgeExperimental => 'Deneysel';

  @override
  String get createCompositeHintPrompt =>
      'Bir kasayı parçalarını sıradan dosyalara ekleyerek gizlemek ister misiniz?';

  @override
  String get createCompositeHintAction => 'Bileşik sihirbazını aç';

  @override
  String get plainDiskImageNotice =>
      'Şifresiz disk görüntüsü algılandı. Bu birimi bağlamak için parola gerekmez.';

  @override
  String storageLocationUnavailable(String name) {
    return 'Depolama konumu \"$name\" kullanılamıyor veya bağlı değil.';
  }

  @override
  String get vaultItemTypeAuthenticator => 'Authenticator';

  @override
  String get fieldIssuer => 'Veren';

  @override
  String get fieldAuthenticatorAccount => 'Hesap';

  @override
  String get fieldSecretKey => 'Gizli anahtar';

  @override
  String get fieldTotpAlgorithm => 'Algoritma (varsayılan: SHA1)';

  @override
  String get fieldTotpDigits => 'Hane sayısı (varsayılan: 6)';

  @override
  String get fieldTotpPeriod => 'Yenileme aralığı, saniye (varsayılan: 30)';

  @override
  String get authenticatorScreenTitle => 'Authenticator';

  @override
  String get authenticatorAppBarTooltip => 'Authenticator kodları';

  @override
  String get authenticatorEmptyStateTitle => 'Henüz authenticator kodu yok';

  @override
  String get authenticatorEmptyStateMessage =>
      'Canlı kodları burada görmek için açık herhangi bir kasada bir parola öğesine TOTP gizli anahtarı ekleyin veya bağımsız bir Authenticator öğesi oluşturun.';

  @override
  String get authenticatorNoVaultsUnlockedMessage =>
      'Authenticator kodlarını burada görmek için bir kasanın kilidini açın.';

  @override
  String get authenticatorCodeLabel => 'Kod';

  @override
  String get authenticatorInvalidSecretError => 'Geçersiz gizli anahtar';

  @override
  String get authenticatorAddButtonTooltip => 'Authenticator ekle';

  @override
  String get authenticatorChooseVaultTitle => 'Bir kasa seçin';

  @override
  String get authenticatorOpenItemTooltip => 'Öğeyi aç';

  @override
  String get authenticatorNextCodeLabel => 'Sonraki kod';

  @override
  String get authenticatorNextCodePrefix => 'Sonraki';

  @override
  String get authenticatorCopyNextCodeTooltip => 'Sonraki kodu kopyala';

  @override
  String get authenticatorSettingsTitle => 'Authenticator ayarları';

  @override
  String get authenticatorEnableTitle => 'Authenticator\'ı etkinleştir';

  @override
  String get authenticatorEnableSubtitle =>
      'Bağlı kasalarda 2FA doğrulama kodlarını otomatik tara';

  @override
  String get authenticatorShowCodesTitle => 'Doğrulama kodlarını göster';

  @override
  String get authenticatorShowCodesSubtitle =>
      'Rakamları gizlilik için maskelemek yerine açıkça göster';

  @override
  String get authenticatorSearchPlacementLabel => 'Arama çubuğu konumu';

  @override
  String get authenticatorPlacementBottom => 'Alt';

  @override
  String get authenticatorPlacementTop => 'Üst';

  @override
  String get authenticatorInterchangeSection => 'İçe ve dışa aktarma';

  @override
  String get scanQrCodeTooltip => 'QR kodu tara';

  @override
  String get qrScannerTitle => 'QR kodu tara';

  @override
  String get qrScannerHint => 'QR kodunu çerçevenin içine hizalayın';

  @override
  String get qrCodeScannedSuccess => 'QR kodu başarıyla tarandı';

  @override
  String get invalidQrCodeError => 'Geçerli bir 2FA QR kodu değil';

  @override
  String get immediateAutoLockOptionSubtitle =>
      'Ekran kapanır kapanmaz veya uygulama arka plana alınır alınmaz kilitler';

  @override
  String get autoLockIndicatorLocksImmediately => 'Anında kilit';

  @override
  String get quickActionLockModeLeaveAsFoundLabel => 'Bulduğun gibi bırak';

  @override
  String get quickActionLockModeLeaveAsFoundSubtitle =>
      'Yalnızca kaydetmeden önce kasa kilitliyse kilitle';

  @override
  String get quickActionLockModeAlwaysLockLabel => 'Her zaman kilitle';

  @override
  String get quickActionLockModeAlwaysLockSubtitle =>
      'Kaydettikten hemen sonra kasayı kilitle';

  @override
  String get quickActionLockModeLeaveOpenLabel => 'Kilidi açık tut';

  @override
  String get quickActionLockModeLeaveOpenSubtitle =>
      'Kasayı açık bırak ve otomatik kilit zamanlayıcılarını takip et';

  @override
  String get textEditorThemeMenuItem => 'Düzenleyici görünümü…';

  @override
  String get textEditorThemeSheetTitle => 'Düzenleyici görünümü';

  @override
  String get textEditorBackgroundSectionTitle => 'Arka plan';

  @override
  String get textEditorSyntaxThemeSectionTitle => 'Sözdizimi teması';

  @override
  String get textEditorBackgroundMatchTheme => 'Temayla eşleştir';

  @override
  String get textEditorBackgroundAmoledBlack => 'AMOLED siyah';

  @override
  String get textEditorBackgroundDarkSlate => 'Koyu arduvaz';

  @override
  String get textEditorBackgroundClassicLight => 'Klasik açık';

  @override
  String get textEditorBackgroundSepia => 'Sepya';

  @override
  String get textEditorSyntaxThemeAuto => 'Otomatik';

  @override
  String get textEditorSyntaxThemeOneDark => 'One Dark';

  @override
  String get textEditorSyntaxThemeDracula => 'Dracula';

  @override
  String get textEditorSyntaxThemeGithubLight => 'GitHub Light';

  @override
  String get textEditorSyntaxThemeMonokai => 'Monokai';

  @override
  String get textEditorSyntaxThemeNord => 'Nord';

  @override
  String get textEditorRelativeLineNumbersLabel => 'Göreli satır numaraları';

  @override
  String get textEditorRelativeLineNumbersDescription =>
      'Her satırın mutlak numarası yerine imlece olan uzaklığını göster';

  @override
  String get textEditorAutoSaveLabel => 'Otomatik kaydet';

  @override
  String get textEditorAutoSaveDescription =>
      'Yazmayı bıraktığınızda değişiklikleri otomatik kaydet';

  @override
  String get cutTooltip => 'Kes';

  @override
  String get textEditorShowLineNumbersLabel => 'Satır numaralarını göster';

  @override
  String get textEditorShowLineNumbersDescription =>
      'Sol kenarda satır numaralarını göster';

  @override
  String get textEditorShowAccessoryBarLabel =>
      'Klavye kısayol çubuğunu göster';

  @override
  String get textEditorShowAccessoryBarDescription =>
      'Ekran klavyesinin üstünde simgeleri ve düzenleme araçlarını göster';

  @override
  String textEditorFontSizeLabel(int size) {
    return 'Yazı boyutu: $size pt';
  }

  @override
  String get textEditorCustomizeKeyBarLabel => 'Kısayol simgelerini özelleştir';

  @override
  String get textEditorCustomizeKeyBarDescription =>
      'Klavyenin üstünde gösterilen simgeleri düzenleyin ve sıralayın';

  @override
  String get textEditorCustomizeKeyBarTitle => 'Simgeleri özelleştir';

  @override
  String get textEditorCustomizeKeyBarHint => 'Boşlukla ayrılmış simgeler';

  @override
  String get textEditorSaveAsMenuItem => 'Farklı kaydet…';

  @override
  String get textEditorSaveAsDialogTitle => 'Farklı kaydet';

  @override
  String get textEditorSaveAsFileNameLabel => 'Dosya adı';

  @override
  String get textEditorSaveAsButton => 'Farklı kaydet';

  @override
  String get textEditorFileAlreadyExistsError =>
      'Burada bu adda bir dosya zaten var';

  @override
  String get textEditorProjectFilesTitle => 'Proje dosyaları';

  @override
  String get textEditorResetToDefault => 'Varsayılanlara sıfırla';

  @override
  String get textEditorLivePreviewTitle => 'Canlı önizleme';

  @override
  String get textEditorWordWrap => 'Sözcük kaydır';

  @override
  String get textEditorReadOnly => 'Salt okunur';

  @override
  String get selectImageTitle => 'Resim seç';

  @override
  String get noImagesFoundMessage => 'Bu klasörde resim bulunamadı.';

  @override
  String get textEditorShowSymbolsBarLabel => 'Simge satırını göster';

  @override
  String get textEditorShowSymbolsBarDescription =>
      'Hızlı noktalama ve parantez kısayollarını göster';

  @override
  String get textEditorShowActionsBarLabel => 'Eylem satırını göster';

  @override
  String get textEditorShowActionsBarDescription =>
      'Düzenleyici eylemleri için kısayol düğmelerini göster';

  @override
  String get textEditorCustomizeActionsLabel => 'Eylem düğmelerini özelleştir';

  @override
  String get textEditorCustomizeActionsDescription =>
      'Düzenleyici eylemlerini seçin ve sıralayın';

  @override
  String get textEditorCustomizeActionsTitle => 'Eylemleri özelleştir';

  @override
  String get actionUndo => 'Geri al';

  @override
  String get actionRedo => 'Yinele';

  @override
  String get actionCursorLeft => 'İmleci sola taşı';

  @override
  String get actionCursorRight => 'İmleci sağa taşı';

  @override
  String get actionSelectWord => 'Sözcüğü seç';

  @override
  String get actionCopy => 'Kopyala';

  @override
  String get actionCut => 'Kes';

  @override
  String get actionPaste => 'Yapıştır';

  @override
  String get actionFind => 'Bul ve değiştir';

  @override
  String get actionWordWrap => 'Sözcük kaydır';

  @override
  String get actionGoToLine => 'Satıra git';

  @override
  String get actionGoToStart => 'Başa git';

  @override
  String get actionGoToEnd => 'Sona git';

  @override
  String get actionIndent => 'Girinti artır';

  @override
  String get actionOutdent => 'Girinti azalt';

  @override
  String get actionFormat => 'Kodu biçimlendir';

  @override
  String get actionReadOnly => 'Salt okunur modunu aç/kapat';

  @override
  String get screenLockOnlyAutoLockOption => 'Yalnızca ekran kilidi';

  @override
  String get screenLockOnlyAutoLockOptionSubtitle =>
      'Yalnızca ekran kapanınca kilitler — uygulama arka plana alınınca kilitlemez';

  @override
  String get authenticatorScanQrSubtitle =>
      'Tek bir kodu veya Google Authenticator aktarım QR kodunu tarayın';

  @override
  String get authenticatorImportBackupsSubtitle =>
      'Aegis, 2FAS, Bitwarden, Ente, Proton veya andOTP yedeklerinden içe aktarın';

  @override
  String authenticatorGoogleAuthImportSuccess(int count) {
    return 'İçe aktarıldı: $count hesap (Google Authenticator)';
  }

  @override
  String get authenticatorMultiQrTitle => 'Ek QR kodları algılandı';

  @override
  String get authenticatorMultiQrMessage =>
      'Google Authenticator bu dışa aktarmayı birden fazla QR koduna böldü. Sonrakini şimdi tarayalım mı?';

  @override
  String get authenticatorScanNextQr => 'Sonrakini tara';

  @override
  String authenticatorGoogleAuthImportError(String error) {
    return 'Google Authenticator QR kodu içe aktarılamadı: $error';
  }

  @override
  String get passwordInterchangeOptionalPasswordHelper =>
      'Yalnızca bu yedek parolayla korunuyorsa gerekir';

  @override
  String authenticatorSingleAccountImportedHint(String title) {
    return 'İlk hesapla dolduruldu ($title). Tüm hesapları içe aktarmak için Authenticator ekranında tarayın.';
  }

  @override
  String get authenticatorHotpReadOnlyError =>
      'Bu kasa salt okunur, bu yüzden HOTP sayacı ilerletilemiyor.';

  @override
  String get authenticatorHotpSaveError => 'Yeni HOTP sayacı kaydedilemedi.';

  @override
  String get authenticatorGenerateNextCode => 'Sonraki kodu üret';

  @override
  String get actionSelectAll => 'Tümünü seç';

  @override
  String get textEditorSelectAllMenuItem => 'Tümünü seç';

  @override
  String get textEditorShowCaretScrubberLabel => 'İmleç kaydırıcısını göster';

  @override
  String get textEditorShowCaretScrubberDescription =>
      'Hassas imleç hareketi için sürükleme şeridi';

  @override
  String get textEditorShowStatusBarLabel => 'Durum çubuğunu göster';

  @override
  String get textEditorShowStatusBarDescription =>
      'Altta satır ve karakter sayılarını göster';

  @override
  String textEditorCursorPosition(int line, int column) {
    return 'Sat $line, Sütun $column';
  }

  @override
  String get textEditorNewFileTooltip => 'Yeni dosya';

  @override
  String get textEditorCloseTab => 'Kapat';

  @override
  String get textEditorCloseOtherTabs => 'Diğerlerini kapat';

  @override
  String get textEditorCloseAllTabs => 'Tümünü kapat';

  @override
  String get textEditorRevertToSaved => 'Kaydedilene dön';

  @override
  String get textEditorRevertDialogTitle => 'Değişiklikler silinsin mi?';

  @override
  String get textEditorRevertDialogMessage =>
      'Kaydedilmemiş tüm düzenlemeler atılıp dosya kasadan yeniden yüklensin mi?';

  @override
  String get revertButton => 'Geri dön';

  @override
  String get textEditorNewFolderTooltip => 'Yeni klasör';

  @override
  String get textEditorNewFolderDialogTitle => 'Yeni klasör';

  @override
  String get textEditorNewFolderFieldLabel => 'Klasör adı';

  @override
  String get textEditorRenameMenuItem => 'Yeniden adlandır';

  @override
  String get textEditorRenameDialogTitle => 'Yeniden adlandır';

  @override
  String get textEditorMoveToMenuItem => 'Şuraya taşı...';

  @override
  String get textEditorMoveToDialogTitle => 'Klasöre taşı';

  @override
  String get textEditorMoveHereButton => 'Buraya taşı';

  @override
  String get textEditorDeleteMenuItem => 'Sil';

  @override
  String textEditorDeleteConfirmTitle(String name) {
    return 'Sil: $name?';
  }

  @override
  String textEditorDeleteConfirmMessage(String name) {
    return '\"$name\" silinsin mi? Bu işlem geri alınamaz.';
  }

  @override
  String get videoEditorEditAction => 'Videoyu düzenle';

  @override
  String get videoEditorExportAction => 'Dışa aktar';

  @override
  String get videoEditorTimelineLabel => 'Video zaman çizelgesi';

  @override
  String get videoEditorSetStart => 'Başlangıcı ayarla';

  @override
  String get videoEditorSetEnd => 'Bitişi ayarla';

  @override
  String get videoEditorAddSegment => 'Ekle';

  @override
  String get videoEditorSplit => 'Böl';

  @override
  String get videoEditorDeleteSegment => 'Sil';

  @override
  String get videoEditorModeKeep => 'Tut';

  @override
  String get videoEditorModeCutOut => 'Kes çıkar';

  @override
  String get videoEditorNoSegments =>
      'Henüz bölüm yok. Oynatma başlığını taşıyıp Ekle\'ye dokunun.';

  @override
  String videoEditorOutputSummary(int count, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Çıktı: $count klip · $duration',
      one: 'Çıktı: 1 klip · $duration',
    );
    return '$_temp0';
  }

  @override
  String get videoEditorBoundaryInvalid => 'Bu, bölümü çok kısa bırakır.';

  @override
  String get videoEditorNoRoom => 'Burada bir bölüm için yer yok.';

  @override
  String get videoEditorNothingToExport => 'Dışa aktarılacak bir şey yok.';

  @override
  String get videoEditorReadOnly =>
      'Bu kasa salt okunur, bu yüzden düzenlenen video kaydedilemez.';

  @override
  String videoEditorLoadFailed(String message) {
    return 'Bu video açılamadı: $message';
  }

  @override
  String get videoEditorZoomIn => 'Yakınlaştır';

  @override
  String get videoEditorZoomOut => 'Uzaklaştır';

  @override
  String get videoEditorZoomFit => 'Ekrana sığdır';

  @override
  String get videoEditorPrevFrame => 'Önceki kare';

  @override
  String get videoEditorNextFrame => 'Sonraki kare';

  @override
  String get videoEditorPrevKeyframe => 'Önceki ana kare';

  @override
  String get videoEditorNextKeyframe => 'Sonraki ana kare';

  @override
  String get videoEditorExporting => 'Video dışa aktarılıyor';

  @override
  String videoEditorCutting(int current, int total) {
    return 'Klip kesiliyor: $current / $total';
  }

  @override
  String get videoEditorCuttingOne => 'Kesiliyor…';

  @override
  String get videoEditorSaving => 'Kaydediliyor…';

  @override
  String videoEditorSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Kaydedildi: $count video',
      one: 'Kaydedildi: 1 video',
    );
    return '$_temp0';
  }

  @override
  String get videoEditorAudioDropped => 'Bazı ses parçaları kopyalanamadı.';

  @override
  String videoEditorExportFailed(String message) {
    return 'Dışa aktarma başarısız: $message';
  }

  @override
  String get videoEditorExportCancelled => 'Dışa aktarma iptal edildi';

  @override
  String get videoEditorExportTitle => 'Dışa aktar';

  @override
  String videoEditorExportSummary(int count, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count klip · $duration',
      one: '1 klip · $duration',
    );
    return '$_temp0';
  }

  @override
  String get videoEditorExportMerge => 'Tek videoda birleştir';

  @override
  String get videoEditorExportSeparate => 'Ayrı videolar olarak kaydet';

  @override
  String get videoEditorLosslessNote =>
      'Kesimler kayıpsızdır, yani hiçbir şey yeniden kodlanmaz. Her klip başlangıç noktanızdan önceki en yakın ana karede başlar ve bitiş noktanızdan sonraki ana karede biter. Zaman çizelgesinin altındaki ince çubuklar tam olarak neyin kaydedileceğini gösterir.';

  @override
  String get videoEditorAnalyzing => 'Video çözümleniyor…';

  @override
  String get videoEditorDiscardTitle => 'Düzenlemeler atılsın mı?';

  @override
  String get videoEditorDiscardMessage =>
      'Kaydedilmemiş değişiklikleriniz var. Bunları atmak istediğinizden emin misiniz?';

  @override
  String get videoEditorDiscardAction => 'Vazgeç';

  @override
  String get videoEditorPreviewCut => 'Kesimi önizle';

  @override
  String get videoEditorSegments => 'Bölümler';

  @override
  String get videoEditorReplaceOriginal => 'Orijinal videonun yerine geç';

  @override
  String get videoEditorReplaceOriginalHint =>
      'Orijinal video, dışa aktarılan kesimle değiştirilecek.';

  @override
  String get videoEditorCustomFileName => 'Çıktı dosya adı';

  @override
  String get videoEditorSubtitlesWarning =>
      'Not: Gömülü altyazı parçaları kayıpsız dışa aktarmada korunamaz.';

  @override
  String get videoEditorRemoveSection => 'Bölümü kaldır';

  @override
  String get fileSkinScreenTitle => 'Dosya yöneticisi teması';

  @override
  String get fileSkinSectionHeader => 'Görünüm';

  @override
  String get fileSkinEntryTitle => 'Tema';

  @override
  String get fileSkinPreviewHeader => 'Önizleme';

  @override
  String get fileSkinPresetsHeader => 'Temalar';

  @override
  String get fileSkinFoldersHeader => 'Klasörler';

  @override
  String get fileSkinFilesHeader => 'Dosyalar';

  @override
  String get fileSkinTextHeader => 'Metin';

  @override
  String get fileSkinIconStyleLabel => 'Simge stili';

  @override
  String get fileSkinContainerLabel => 'Simge arka planı';

  @override
  String get fileSkinIconColorLabel => 'Simge rengi';

  @override
  String get fileSkinCustomIconColorLabel => 'Özel simge rengi';

  @override
  String get fileSkinNameColorLabel => 'Ad rengi';

  @override
  String get fileSkinDetailsColorLabel => 'Ayrıntı rengi';

  @override
  String get fileSkinMonospaceLabel => 'Sabit genişlikli adlar';

  @override
  String get fileSkinMonospaceDesc =>
      'Dosya ve klasör adları için sabit genişlikli yazı tipi kullan';

  @override
  String get fileSkinIconFamilyDefault => 'Varsayılan';

  @override
  String get fileSkinIconFamilyFilled => 'Dolu';

  @override
  String get fileSkinIconFamilyRounded => 'Yuvarlak';

  @override
  String get fileSkinIconFamilyOutlined => 'Çerçeveli';

  @override
  String get fileSkinIconFamilySharp => 'Keskin';

  @override
  String get fileSkinContainerFilled => 'Dolu';

  @override
  String get fileSkinContainerOutlined => 'Çerçeveli';

  @override
  String get fileSkinContainerNone => 'Yok';

  @override
  String get fileSkinColorAuto => 'Otomatik';

  @override
  String get fileSkinColorAccent => 'Tema vurgusu';

  @override
  String get fileSkinColorNeutral => 'Nötr';

  @override
  String get fileSkinColorCustom => 'Özel';

  @override
  String get fileSkinColorDefault => 'Varsayılan';

  @override
  String get fileSkinPresetClassic => 'Klasik';

  @override
  String get fileSkinPresetMinimalOutline => 'Minimal çerçeve';

  @override
  String get fileSkinPresetFrames => 'Çerçeveler';

  @override
  String get fileSkinPresetVivid => 'Canlı';

  @override
  String get fileSkinPresetTerminal => 'Terminal';

  @override
  String get fileSkinPresetCustom => 'Özel';

  @override
  String get compositeArchiveCarrierBlockingWarning =>
      'Devam etmek için arşivi bu seçimden kaldırın. Kasa eklemek arşivleri bozabileceğinden arşivler bileşik taşıyıcı olarak kullanılamaz.';

  @override
  String get compositeArchiveCarrierRowWarning =>
      'Desteklenmeyen arşiv — seçimden kaldırın.';

  @override
  String get videoEditorKeepModeDescription =>
      'Seçili bölümleri dışa aktar, geri kalan her şeyi at.';

  @override
  String get videoEditorCutOutModeDescription =>
      'Seçili bölümleri kaldır ve kalan görüntüyü dışa aktar.';

  @override
  String get tapEdgesToNavigateTitle => 'Gezinmek için kenarlara dokun';

  @override
  String get tapEdgesToNavigateSubtitle =>
      'Önceki veya sonraki medya öğesini göstermek için sol ya da sağ kenara dokunun.';

  @override
  String get doubleTapPlayPauseTitle => 'Oynat/duraklat için çift dokun';

  @override
  String get doubleTapPlayPauseSubtitle =>
      'Yakınlaştırmak yerine oynatmak veya duraklatmak için video ya da ses ekranının ortasına çift dokunun. Yakınlaştırılmışken görünen yakınlaştırma düzeyine dokunarak görünümü sıfırlayın.';

  @override
  String get doubleTapSkipTitle => 'Atlamak için çift dokun';

  @override
  String get doubleTapSkipSubtitle =>
      'Bir videoda geri veya ileri atlamak için sol ya da sağ tarafa çift dokunun. Daha fazla atlamak için dokunmaya devam edin.';

  @override
  String get doubleTapSkipDurationTitle => 'Atlama süresi';

  @override
  String get loopPlaylistTitle => 'Oynatma listesini döngüye al';

  @override
  String get loopPlaylistSubtitle =>
      'Oynatma listesinde gezinirken veya oynatırken son öğeden sonra ilk öğeden devam et.';

  @override
  String get showFileNamesInMediaNotificationTitle =>
      'Medya bildirimlerinde dosya adlarını göster';

  @override
  String get showFileNamesInMediaNotificationSubtitle =>
      'Şifresi çözülmüş dosya adlarını bildirimde, kilit ekranında ve bağlı cihazlarda gösterir.';

  @override
  String get textEditorEncodingTooltip => 'Metin kodlaması';

  @override
  String get textEditorEncodingEncodeError =>
      'Bazı karakterler bu kodlamayla kaydedilemiyor.';

  @override
  String get textEditorShowTabBarLabel => 'Düzenleyici sekmelerini göster';

  @override
  String get textEditorShowTabBarDescription =>
      'Açık dosyalar için sekmeleri göster veya gizle. Dosyaları yine de kenar çubuğundan değiştirebilirsiniz.';

  @override
  String get textEditorAutoHideTabBarLabel => 'Kaydırırken sekmeleri gizle';

  @override
  String get textEditorAutoHideTabBarDescription =>
      'Aşağı kaydırırken sekme çubuğunu gizle; yeniden göstermek için yukarı kaydırın.';

  @override
  String get lockWaitingForOperationsMessage =>
      'Kilitlemeden önce mevcut işlemlerin bitmesi bekleniyor…';

  @override
  String get mirrorSyncActivityLabel =>
      'Kasa değişiklikleri depolamaya kaydediliyor';

  @override
  String get seekGestureSensitivityTitle => 'Arama hareketi hassasiyeti';

  @override
  String get volumeGestureSensitivityTitle => 'Ses hareketi hassasiyeti';

  @override
  String get brightnessGestureSensitivityTitle =>
      'Parlaklık hareketi hassasiyeti';

  @override
  String get thumbnailSettingsHeader => 'Küçük resim oluşturma';

  @override
  String get thumbnailGenerationStrategyTitle => 'Küçük resim kare stratejisi';

  @override
  String get thumbnailFirstFrameOption => 'İlk kare';

  @override
  String get thumbnailPercentageFrameOption => 'Belirli konumdaki kare';

  @override
  String get thumbnailHybridOption => 'Karma (boş açılışı atla)';

  @override
  String get thumbnailFramePositionTitle => 'Tercih edilen kare konumu';

  @override
  String get volumeBoostHeader => 'Ses yükseltme';

  @override
  String get volumeBoostTitle => 'Ses yükseltmeyi etkinleştir';

  @override
  String get volumeBoostSubtitle =>
      'Sessiz video seslerini normal oynatıcı ses düzeyinin üzerine çıkarır.';

  @override
  String get volumeBoostGainTitle => 'Yükseltme miktarı';

  @override
  String get decoderSelectionHeader => 'Çözücü seçimi';

  @override
  String get videoDecoderTitle => 'Video çözücü';

  @override
  String get audioDecoderTitle => 'Ses çözücü';

  @override
  String get decoderAutoOption => 'Otomatik';

  @override
  String get decoderHardwareOption => 'Donanım';

  @override
  String get decoderSoftwareOption => 'Yazılım';

  @override
  String get decoderFfmpegOption => 'FFmpeg';

  @override
  String get autoSyncLocalRootDeleteWarningTitle =>
      'Yerel Depolama kökündeki dosyalar silinsin mi?';

  @override
  String get autoSyncLocalRootDeleteWarningMessage =>
      'Bu tek yönlü eşitleme Yerel Depolama kökünün tamamını tarar. İçe aktarmadan sonra kaynak dosyaları sil seçeneği açıksa, kasaya kopyalanan ve SHA-256 ile doğrulanan dosyalar cihazınızdan kaldırılabilir. Yalnızca bu orijinalleri silmek istiyorsanız devam edin.';

  @override
  String get autoSyncLocalRootDeleteWarningConfirm => 'Anladım';

  @override
  String get autoSyncScheduledTitle => 'Kasa kilitliyken günlük çalıştır';

  @override
  String get autoSyncScheduledSubtitle =>
      'Uygulama kapalıyken arka planda çalışır. Android bunu geciktirebilir veya uzun bir çalışmayı durdurabilir. Eşitleme bitince kasa yeniden kilitlenir.';

  @override
  String get autoSyncScheduledSetupRequired =>
      'Tam otomasyon erişimi ve kayıtlı bir kasa parolası gerektirir.';

  @override
  String get autoSyncScheduledConfigure => 'Arka plan erişimini ayarla';

  @override
  String get autoSyncScheduleWarningTitle =>
      'Zamanlanmış eşitleme etkinleştirilsin mi?';

  @override
  String get autoSyncScheduleWarningMessage =>
      'Uygulama bu kasanın kilidini günde bir kez arka planda açacak ve eşitlemeden sonra kilitleyecek. Android bir çalışmayı geciktirebilir. İçe aktarmadan sonra silme açıksa, kaynak dosya yalnızca kasadaki kopya işlendikten ve boyutu ile SHA-256 sağlama toplamı eşleştikten sonra kaldırılır.';

  @override
  String get autoSyncScheduleEnable => 'Zamanlamayı etkinleştir';

  @override
  String get autoSyncScheduleNotificationRequired =>
      'Arka plan eşitlemesi çalışırken Android\'in “Kasa eşitleniyor...” göstermesi için bildirimlere izin verin.';

  @override
  String get autoSyncScheduleFailed =>
      'Kural kaydedildi, ama zamanlanmış eşitleme etkinleştirilemedi.';

  @override
  String get autoSyncSavedScheduled => 'Kural ve günlük zamanlama kaydedildi.';

  @override
  String get autoSyncScheduledTimeTitle => 'Günlük çalışma saati';

  @override
  String get autoSyncScheduledTimeSubtitle =>
      'Cihazın yerel saati. Hızlı test için şimdiden bir iki dakika sonrasını seçin; Android daha geç çalıştırabilir.';

  @override
  String get autoSyncExactAlarmAccessTitle =>
      'Günlük eşitleme için tam zamanlı alarmlara izin verilsin mi?';

  @override
  String get autoSyncExactAlarmAccessMessage =>
      'Android, Vault Explorer\'ın uygulama kapalıyken seçtiğiniz saatte günlük eşitlemeyi başlatabilmesi için Alarmlar ve hatırlatıcılar erişimi ister. Sonraki ekranda izin verin, buraya dönün, sonra Zamanlanmış eşitlemeyi yeniden açın.';

  @override
  String get autoSyncExactAlarmAccessOpen => 'Ayarları aç';

  @override
  String get autoSyncExactAlarmAccessUnavailable =>
      'Android alarm ayarları açılamadı. Sistem ayarlarında Vault Explorer için Alarmlar ve hatırlatıcılar iznini etkinleştirin, sonra yeniden deneyin.';

  @override
  String get localStoragePermissionTitle => 'Yerel Depolama erişimine izin ver';

  @override
  String get localStorageGrantAccess => 'Erişim ver';

  @override
  String get hideStorageLocationsTitle => 'Depolama konumları gizlensin mi?';

  @override
  String get hideStorageLocationsPrompt =>
      'Tüm dosyalara erişim verilmedi. Yerel Depolama ve eklenen konumlar kenar çubuğundan gizlensin mi? Bunları Ayarlar\'dan yeniden gösterebilirsiniz.';

  @override
  String get hide => 'Gizle';

  @override
  String get mediaViewerActionAdjustments => 'Ayarlamalar';

  @override
  String get adjustmentsSheetTitle => 'Ayarlamalar';

  @override
  String get adjustmentBrightness => 'Parlaklık';

  @override
  String get adjustmentContrast => 'Kontrast';

  @override
  String get adjustmentSaturation => 'Doygunluk';

  @override
  String get adjustmentHue => 'Ton';

  @override
  String get adjustmentGamma => 'Gama';

  @override
  String get adjustmentsApplyToAll => 'Tüm dosyalara uygula';

  @override
  String get adjustmentsCompareHold => 'Karşılaştırmak için basılı tutun';

  @override
  String get adjustmentPresetVivid => 'Canlı';

  @override
  String get adjustmentPresetBlackAndWhite => 'S&B';

  @override
  String get adjustmentPresetWarm => 'Sıcak';

  @override
  String get adjustmentPresetCool => 'Soğuk';

  @override
  String get videoFilePropertiesSectionHeader => 'VİDEO VE SES';

  @override
  String get durationLabel => 'Süre';

  @override
  String get rotationLabel => 'Döndürme';

  @override
  String get videoBitrateLabel => 'Video bit hızı';

  @override
  String get audioBitrateLabel => 'Ses bit hızı';

  @override
  String get sampleRateLabel => 'Örnekleme hızı';

  @override
  String get audioChannelsLabel => 'Ses kanalları';

  @override
  String get subtitleTracksLabel => 'Altyazı parçaları';

  @override
  String get skinActionAccent => 'Eylem vurgusu';

  @override
  String get skinEmphasisForActionIconsActiveControlsProgressAndLinks =>
      'Eylem simgeleri, etkin denetimler, ilerleme ve bağlantılar için vurgu.';

  @override
  String get skinTextAndIconsOnAccentButtons =>
      'Vurgu düğmelerindeki metin ve simgeler';

  @override
  String get skinForegroundForButtonsFilledWithTheActionAccentColor =>
      'Eylem vurgu rengiyle doldurulmuş düğmelerin ön planı.';

  @override
  String get skinSelectionAndIconTileBackground =>
      'Seçim ve simge karosu arka planı';

  @override
  String get skinSelectedFilesAndVaultFormat076e52 =>
      'Seçili dosyalar ve kasa biçimi simge karoları bu rengi kullanır. Yüzen düğme dolgusunun kendi ayarı vardır.';

  @override
  String get skinTextAndIconsOnSelectionColors =>
      'Seçim renklerindeki metin ve simgeler';

  @override
  String get skinForegroundForIconTilesAndOtherPrimaryContainerSurfaces =>
      'Simge karoları ve diğer birincil kapsayıcı yüzeylerin ön planı.';

  @override
  String get skinSteadyMainAccent => 'Sabit ana vurgu';

  @override
  String get skinAPrimaryAccentThatStaysTheSameInLightAndDarkSurfaces =>
      'Açık ve koyu yüzeylerde aynı kalan birincil vurgu.';

  @override
  String get skinMutedSteadyMainAccent => 'Soluk sabit ana vurgu';

  @override
  String get skinASofterVersionOfTheSteadyPrimaryAccent =>
      'Sabit birincil vurgunun daha yumuşak bir sürümü.';

  @override
  String get skinTextOnSteadyMainAccent => 'Sabit ana vurgu üzerindeki metin';

  @override
  String get skinForegroundForPrimaryFixedColors =>
      'Birincil sabit renklerin ön planı.';

  @override
  String get skinMutedTextOnSteadyMainAccent =>
      'Sabit ana vurgu üzerindeki soluk metin';

  @override
  String get skinSecondaryForegroundForPrimaryFixedColors =>
      'Birincil sabit renkler için ikincil ön plan.';

  @override
  String get skinSecondaryAccent => 'İkincil vurgu';

  @override
  String get skinSupportingActionsAndLessProminentHighlights =>
      'Destekleyici eylemler ve daha az belirgin vurgular.';

  @override
  String get skinTextOnSecondaryAccent => 'İkincil vurgu üzerindeki metin';

  @override
  String get skinLabelsAndIconsOnSecondaryColoredAreas =>
      'İkincil renkli alanlardaki etiketler ve simgeler.';

  @override
  String get skinSecondaryBackground => 'İkincil arka plan';

  @override
  String get skinSoftFillForSupportingContent =>
      'Destekleyici içerik için yumuşak dolgu.';

  @override
  String get skinTextOnSecondaryBackgrounds =>
      'İkincil arka planlar üzerindeki metin';

  @override
  String get skinForegroundForSecondaryContainers =>
      'İkincil kapsayıcıların ön planı.';

  @override
  String get skinSteadySecondaryAccent => 'Sabit ikincil vurgu';

  @override
  String get skinASecondaryAccentThatStaysTheSameAcrossSurfaces =>
      'Yüzeyler arasında aynı kalan ikincil vurgu.';

  @override
  String get skinMutedSteadySecondaryAccent => 'Soluk sabit ikincil vurgu';

  @override
  String get skinASofterVersionOfTheSteadySecondaryAccent =>
      'Sabit ikincil vurgunun daha yumuşak bir sürümü.';

  @override
  String get skinTextOnSteadySecondaryAccent =>
      'Sabit ikincil vurgu üzerindeki metin';

  @override
  String get skinForegroundForSecondaryFixedColors =>
      'İkincil sabit renklerin ön planı.';

  @override
  String get skinMutedTextOnSteadySecondaryAccent =>
      'Sabit ikincil vurgu üzerindeki soluk metin';

  @override
  String get skinSecondaryForegroundForSecondaryFixedColors =>
      'İkincil sabit renkler için ikincil ön plan.';

  @override
  String get skinExtraAccentColor => 'Ek vurgu rengi';

  @override
  String get skinDecorativeHighlightsAndContrastingAccents =>
      'Dekoratif vurgular ve zıt aksanlar.';

  @override
  String get skinTextOnExtraAccent => 'Ek vurgu üzerindeki metin';

  @override
  String get skinLabelsAndIconsOnTertiaryColoredAreas =>
      'Üçüncül renkli alanlardaki etiketler ve simgeler.';

  @override
  String get skinExtraAccentBackground => 'Ek vurgu arka planı';

  @override
  String get skinSoftFillForTertiaryContent =>
      'Üçüncül içerik için yumuşak dolgu.';

  @override
  String get skinTextOnExtraAccentBackgrounds =>
      'Ek vurgu arka planları üzerindeki metin';

  @override
  String get skinForegroundForTertiaryContainers =>
      'Üçüncül kapsayıcıların ön planı.';

  @override
  String get skinSteadyExtraAccent => 'Sabit ek vurgu';

  @override
  String get skinATertiaryAccentThatStaysTheSameAcrossSurfaces =>
      'Yüzeyler arasında aynı kalan üçüncül vurgu.';

  @override
  String get skinMutedSteadyExtraAccent => 'Soluk sabit ek vurgu';

  @override
  String get skinASofterVersionOfTheSteadyTertiaryAccent =>
      'Sabit üçüncül vurgunun daha yumuşak bir sürümü.';

  @override
  String get skinTextOnSteadyExtraAccent => 'Sabit ek vurgu üzerindeki metin';

  @override
  String get skinForegroundForTertiaryFixedColors =>
      'Üçüncül sabit renklerin ön planı.';

  @override
  String get skinMutedTextOnSteadyExtraAccent =>
      'Sabit ek vurgu üzerindeki soluk metin';

  @override
  String get skinSecondaryForegroundForTertiaryFixedColors =>
      'Üçüncül sabit renkler için ikincil ön plan.';

  @override
  String get skinErrorColor => 'Hata rengi';

  @override
  String get skinErrorsDestructiveActionsAndInvalidInput =>
      'Hatalar, yıkıcı eylemler ve geçersiz girdi.';

  @override
  String get skinTextOnErrorColor => 'Hata rengi üzerindeki metin';

  @override
  String get skinLabelsAndIconsOnErrorColoredAreas =>
      'Hata renkli alanlardaki etiketler ve simgeler.';

  @override
  String get skinErrorBackground => 'Hata arka planı';

  @override
  String get skinSoftFillBehindErrorMessages =>
      'Hata iletilerinin arkasında yumuşak dolgu.';

  @override
  String get skinTextOnErrorBackgrounds =>
      'Hata arka planları üzerindeki metin';

  @override
  String get skinForegroundForErrorContainers =>
      'Hata kapsayıcılarının ön planı.';

  @override
  String get skinPageBackground => 'Sayfa arka planı';

  @override
  String get skinTheMainBackgroundBehindAppContent =>
      'Uygulama içeriğinin arkasındaki ana arka plan.';

  @override
  String get skinMainTextAndIcons => 'Ana metin ve simgeler';

  @override
  String get skinPrimaryContentDrawnOnPageAndCardBackgrounds =>
      'Sayfa ve kart arka planları üzerine çizilen birincil içerik.';

  @override
  String get skinDimmedBackground => 'Kısık arka plan';

  @override
  String get skinTheDarkestNeutralSurfaceLayer => 'En koyu nötr yüzey katmanı.';

  @override
  String get skinBrightBackground => 'Parlak arka plan';

  @override
  String get skinTheLightestNeutralSurfaceLayer =>
      'En açık nötr yüzey katmanı.';

  @override
  String get skinDeepestCardLayer => 'En derin kart katmanı';

  @override
  String get skinTheLowestAndQuietestSurfaceContainer =>
      'En alçak ve en sakin yüzey kapsayıcısı.';

  @override
  String get skinLowCardLayer => 'Alçak kart katmanı';

  @override
  String get skinSubtleCardsAndRecessedAreas =>
      'İnce kartlar ve çökük alanlar.';

  @override
  String get skinStandardCardLayer => 'Standart kart katmanı';

  @override
  String get skinCommonCardsAndGroupedContent =>
      'Yaygın kartlar ve gruplanmış içerik.';

  @override
  String get skinRaisedCardLayer => 'Yükseltilmiş kart katmanı';

  @override
  String get skinRaisedCardsMenusAndAppBars =>
      'Yükseltilmiş kartlar, menüler ve uygulama çubukları.';

  @override
  String get skinTopCardLayer => 'Üst kart katmanı';

  @override
  String get skinProminentPanelsAndSelectedSurfaces =>
      'Belirgin paneller ve seçili yüzeyler.';

  @override
  String get skinSecondaryTextAndIcons => 'İkincil metin ve simgeler';

  @override
  String get skinDetailsHintsAndSupportingLabels =>
      'Ayrıntılar, ipuçları ve destekleyici etiketler.';

  @override
  String get skinStrongBorder => 'Güçlü kenarlık';

  @override
  String get skinVisibleBordersAndSeparators =>
      'Görünür kenarlıklar ve ayırıcılar.';

  @override
  String get skinSubtleBorder => 'İnce kenarlık';

  @override
  String get skinQuietOutlinesAndLowEmphasisSeparators =>
      'Sakin çerçeveler ve düşük vurgulu ayırıcılar.';

  @override
  String get skinShadowTint => 'Gölge tonu';

  @override
  String get skinTintUsedByElevatedSurfaces =>
      'Yükseltilmiş yüzeylerin kullandığı ton.';

  @override
  String get skinModalBackdrop => 'Kalıcı iletişim arka perdesi';

  @override
  String get skinTintBehindDialogsAndModalSheets =>
      'İletişim kutularının ve alt sayfaların arkasındaki ton.';

  @override
  String get skinInvertedSurface => 'Ters yüzey';

  @override
  String get skinAContrastingSurfaceForInverseElements =>
      'Ters öğeler için zıt bir yüzey.';

  @override
  String get skinTextOnInvertedSurfaces => 'Ters yüzeyler üzerindeki metin';

  @override
  String get skinForegroundUsedOverInverseSurfaces =>
      'Ters yüzeyler üzerinde kullanılan ön plan.';

  @override
  String get skinInvertedMainAccent => 'Ters ana vurgu';

  @override
  String get skinPrimaryAccentUsedOnInverseSurfaces =>
      'Ters yüzeylerde kullanılan birincil vurgu.';

  @override
  String get skinElevationTint => 'Yükselti tonu';

  @override
  String get skinTintAppliedToElevatedSurfaces =>
      'Yükseltilmiş yüzeylere uygulanan ton.';

  @override
  String get skinSuccessColor => 'Başarı rengi';

  @override
  String get skinCompletedActionsAndPositiveStatus =>
      'Tamamlanan eylemler ve olumlu durum.';

  @override
  String get skinTextOnSuccessColor => 'Başarı rengi üzerindeki metin';

  @override
  String get skinForegroundForSuccessColoredContent =>
      'Başarı renkli içeriğin ön planı.';

  @override
  String get skinSuccessBackground => 'Başarı arka planı';

  @override
  String get skinSoftFillBehindPositiveStatusMessages =>
      'Olumlu durum iletilerinin arkasında yumuşak dolgu.';

  @override
  String get skinTextOnSuccessBackgrounds =>
      'Başarı arka planları üzerindeki metin';

  @override
  String get skinForegroundForSuccessContainers =>
      'Başarı kapsayıcılarının ön planı.';

  @override
  String get skinWarningColor => 'Uyarı rengi';

  @override
  String get skinCautionAttentionAndPendingStatus =>
      'Dikkat, uyarı ve bekleyen durum.';

  @override
  String get skinTextOnWarningColor => 'Uyarı rengi üzerindeki metin';

  @override
  String get skinForegroundForWarningColoredContent =>
      'Uyarı renkli içeriğin ön planı.';

  @override
  String get skinWarningBackground => 'Uyarı arka planı';

  @override
  String get skinSoftFillBehindWarningMessages =>
      'Uyarı iletilerinin arkasında yumuşak dolgu.';

  @override
  String get skinTextOnWarningBackgrounds =>
      'Uyarı arka planları üzerindeki metin';

  @override
  String get skinForegroundForWarningContainers =>
      'Uyarı kapsayıcılarının ön planı.';

  @override
  String get skinBookmarkColor => 'Yer imi rengi';

  @override
  String get skinSavedAndBookmarkedItems =>
      'Kaydedilen ve yer imi eklenen öğeler.';

  @override
  String get skinMainActions => 'Ana eylemler';

  @override
  String get skinPrimaryButtonsSelectionsAndFixedPrimaryAccents =>
      'Birincil düğmeler, seçimler ve sabit birincil vurgular.';

  @override
  String get skinSupportingAccents => 'Destekleyici vurgular';

  @override
  String get skinSecondaryAndTertiaryHighlightsAndTheirTextColors =>
      'İkincil ve üçüncül vurgular ile metin renkleri.';

  @override
  String get skinErrorMessagesAndDestructiveOrInvalidStates =>
      'Hata iletileri ile yıkıcı veya geçersiz durumlar.';

  @override
  String get skinPagesCardsAndText => 'Sayfalar, kartlar ve metin';

  @override
  String get skinAppBackgroundsCardsMenusAndForegroundText =>
      'Uygulama arka planları, kartlar, menüler ve ön plan metni.';

  @override
  String get skinBordersAndOverlays => 'Kenarlıklar ve katmanlar';

  @override
  String get skinOutlinesShadowsAndModalBackdrops =>
      'Çerçeveler, gölgeler ve iletişim kutusu arka perdeleri.';

  @override
  String get skinCustomizeSkin => 'Temayı özelleştir';

  @override
  String get skinLight => 'Açık';

  @override
  String get skinDark => 'Koyu';

  @override
  String get skinEditor => 'Düzenleyici';

  @override
  String get skinSkinDetails => 'Tema ayrıntıları';

  @override
  String get skinNameYourSkinAndChooseWhichPaletteToEdit =>
      'Temanıza ad verin ve hangi paleti düzenleyeceğinizi seçin.';

  @override
  String get skinSkinName => 'Tema adı';

  @override
  String get skinMyCustomSkin => 'Özel temam';

  @override
  String get skinLightColors => 'Açık renkler';

  @override
  String get skinDarkColors => 'Koyu renkler';

  @override
  String get skinPageAndActions => 'Sayfa ve eylemler';

  @override
  String get skinTheMainBackgroundTextAndActionColors =>
      'Ana arka plan, metin ve eylem renkleri.';

  @override
  String get skinAppBar => 'Uygulama çubuğu';

  @override
  String get skinTopBarFillColor => 'Üst çubuk dolgu rengi.';

  @override
  String get skinTitleAndIcons => 'Başlık ve simgeler';

  @override
  String get skinTopBarTextAndIconColor => 'Üst çubuk metin ve simge rengi.';

  @override
  String get skinFloatingActionButton => 'Yüzen eylem düğmesi';

  @override
  String get skinButtonFill => 'Düğme dolgusu';

  @override
  String get skinBackgroundOfTheRoundButton =>
      'Yuvarlak + düğmesinin arka planı.';

  @override
  String get skinButtonIcon => 'Düğme simgesi';

  @override
  String get skinIconColorOnTheRoundButton =>
      'Yuvarlak + düğmesindeki simge rengi.';

  @override
  String get skinFineTuneAppColors => 'Uygulama renklerine ince ayar';

  @override
  String get skinAdvancedMaterialColorsForLessCommonElements =>
      'Daha az yaygın öğeler için gelişmiş Material renkleri.';

  @override
  String get skinStatusAndBookmarkColors => 'Durum ve yer imi renkleri';

  @override
  String get skinColorsForSuccessWarningsErrorsAndBookmarks =>
      'Başarı, uyarı, hata ve yer imleri için renkler.';

  @override
  String get skinTheCustomSkinIsActive971ce3 =>
      'Özel tema, Dosya Yöneticisi ve Düzenleyici uygulama temasını izleyecek şekilde ayarlıyken hemen etkin olur.';

  @override
  String get skinCustomColorTapToChangeOrReset =>
      'Özel renk — değiştirmek veya varsayılana sıfırlamak için dokunun.';

  @override
  String get skinTapTheColorCircleToChooseAColor =>
      'Renk seçmek için renk dairesine dokunun.';

  @override
  String get skinEditorBackground => 'Düzenleyici arka planı';

  @override
  String get skinTheCanvasColorBehindTheCode =>
      'Kodun arkasındaki tuval rengi.';

  @override
  String get skinEditorLineNumbers => 'Düzenleyici satır numaraları';

  @override
  String get skinTheGutterAndLineNumbersBesideTheCode =>
      'Kodun yanındaki oluk ve satır numaraları.';

  @override
  String get skinEditorTextColor => 'Kod metni rengi';

  @override
  String get skinEditorCursor => 'Düzenleyici imleci';

  @override
  String get skinTheInsertionCaretColor => 'Ekleme imlecinin rengi.';

  @override
  String get skinEditorSelectionHighlight => 'Düzenleyici seçim vurgusu';

  @override
  String get skinTheBackgroundUsedToHighlightSelectedCode =>
      'Seçili kodu vurgulamak için kullanılan arka plan.';

  @override
  String get skinEditorKeywords => 'Anahtar sözcükler';

  @override
  String get skinEditorTypes => 'Türler ve sınıflar';

  @override
  String get skinEditorStrings => 'Dizeler';

  @override
  String get skinEditorNumbers => 'Sayılar ve değerler';

  @override
  String get skinEditorFunctions => 'İşlevler ve yöntemler';

  @override
  String get skinEditorComments => 'Yorumlar';

  @override
  String get textEditorColorsSectionTitle =>
      'Düzenleyici renkleri ve yazı tipi';

  @override
  String get textEditorSyntaxColorsSectionTitle => 'Sözdizimi öğesi renkleri';

  @override
  String get textEditorColorsCustomized => 'Özel renkler etkin';

  @override
  String get textEditorFollowAppSkinNotice =>
      'Düzenleyici renkleri etkin uygulama temasını izler.';

  @override
  String get textEditorCustomizeColorsIndependently =>
      'Renkleri bağımsız olarak özelleştir';

  @override
  String get textEditorDefaultFromTheme => 'Varsayılan (temadan)';

  @override
  String get skinFileManager => 'Dosya yöneticisi';

  @override
  String get skinFolderAndFileGlyphsTilesAndLabelColors =>
      'Klasör ve dosya simgeleri, karolar ve etiket renkleri.';

  @override
  String get skinDetailsTextColor => 'Ayrıntı metni rengi';

  @override
  String get skinUseTheAppSSupportingTextColor =>
      'Uygulamanın destekleyici metin rengini kullan';

  @override
  String get skinCustomColor => 'Özel renk';

  @override
  String get skinMonospaceFileNames => 'Sabit genişlikli dosya adları';

  @override
  String get skinBackgroundBehindTheIcon => 'Simgenin arkasındaki arka plan';

  @override
  String get skinIconColorSource => 'Simge rengi kaynağı';

  @override
  String get skinUseTheAppSMainTextColor =>
      'Uygulamanın ana metin rengini kullan';

  @override
  String get skinTextEditor => 'Metin düzenleyici';

  @override
  String get skinCanvasGutterCursorSelectionBackgroundAndSyntaxTemplate =>
      'Tuval, oluk, imleç, seçim, arka plan ve sözdizimi şablonu.';

  @override
  String get skinEditorBackgroundTemplate => 'Düzenleyici arka plan şablonu';

  @override
  String get skinSyntaxTemplate => 'Sözdizimi şablonu';

  @override
  String get skinTapTheColorCircleToChooseAColor246981 =>
      'Renk seçmek için renk dairesine dokunun';

  @override
  String get skinDefaultVaultExplorerIcons =>
      'Varsayılan Vault Explorer simgeleri';

  @override
  String get skinSolidIcons => 'Dolu simgeler';

  @override
  String get skinRoundedIcons => 'Yuvarlak simgeler';

  @override
  String get skinOutlineIcons => 'Çerçeveli simgeler';

  @override
  String get skinSquareCornerIcons => 'Köşeli simgeler';

  @override
  String get skinTintedTileBehindTheIcon => 'Simgenin arkasında renkli karo';

  @override
  String get skinOutlinedTileBehindTheIcon =>
      'Simgenin arkasında çerçeveli karo';

  @override
  String get skinNoTile => 'Karo yok';

  @override
  String get skinAutomaticFileTypeOrFolderColor =>
      'Otomatik (dosya türü veya klasör rengi)';

  @override
  String get skinUseTheMainAppAccent => 'Ana uygulama vurgusunu kullan';

  @override
  String get skinUseAMutedNeutralColor => 'Soluk nötr bir renk kullan';

  @override
  String get skinChooseAColorBelow => 'Aşağıdan bir renk seçin';

  @override
  String get skinUseTheSyntaxThemeBackground =>
      'Sözdizimi teması arka planını kullan';

  @override
  String get skinPureBlack => 'Saf siyah';

  @override
  String get skinDarkSlate => 'Koyu arduvaz';

  @override
  String get skinCleanWhite => 'Temiz beyaz';

  @override
  String get skinWarmSepia => 'Sıcak sepya';

  @override
  String get skinAutomaticMatchLightOrDarkMode =>
      'Otomatik (açık veya koyu moda uy)';

  @override
  String get skinRemoveSkin => 'Tema kaldırılsın mı?';

  @override
  String get skinAppSkin => 'Uygulama teması';

  @override
  String get skinImportSkins => 'Temaları içe aktar';

  @override
  String get skinExportSkins => 'Temaları dışa aktar';

  @override
  String get skinChooseACoordinatedLookForTheAppFileManagerAndEditor =>
      'Uygulama, dosya yöneticisi ve düzenleyici için uyumlu bir görünüm seçin.';

  @override
  String get skinLightAndDarkSystemThemesUseMatchingPaletteVariants =>
      'Açık ve koyu sistem temaları eşleşen palet varyantlarını kullanır.';

  @override
  String get skinEditCurrentSkin => 'Geçerli temayı düzenle';

  @override
  String get skinCreateASkinFromThisLook => 'Bu görünümden bir tema oluştur';

  @override
  String get skinYourSkins => 'Temalarınız';

  @override
  String get skinCustomAppFileManagerAndEditorColors =>
      'Özel uygulama, dosya yöneticisi ve düzenleyici renkleri';

  @override
  String get skinMaterialColorsWithLightAndDarkVariants =>
      'Açık ve koyu varyantlı Material renkleri';

  @override
  String get skinTrueBlackEditorAndDarkf97e8f =>
      'OLED vurgu paletli gerçek siyah düzenleyici ve koyu uygulama yüzeyleri';

  @override
  String get skinYourEditableAppFileManagerAndEditorColors =>
      'Düzenlenebilir uygulama, dosya yöneticisi ve düzenleyici renkleriniz';

  @override
  String get skinSkinActions => 'Tema eylemleri';

  @override
  String get skinEditSkin => 'Temayı düzenle';

  @override
  String get skinExportSkin => 'Temayı dışa aktar';

  @override
  String get skinRemoveSkinf09101 => 'Temayı kaldır';

  @override
  String get skinDragAroundTheRingTo868d62 =>
      'Ton seçmek için halka boyunca sürükleyin, sonra gölgeyi ayarlamak için içeri doğru kaydırın.';

  @override
  String get skinQuickColors => 'Hızlı renkler';

  @override
  String get skinEnterAnExactColor => 'Tam bir renk girin';

  @override
  String get skinOptionalRGBOrARGBValue => 'İsteğe bağlı RGB veya ARGB değeri';

  @override
  String get skinRGBARGB => 'RGB / ARGB';

  @override
  String get skinUseThisValue => 'Bu değeri kullan';

  @override
  String get skinDefaultLightDark => 'Varsayılan Açık / Koyu';

  @override
  String get skinOLEDPureBlack => 'OLED saf siyah';

  @override
  String get skinCustomSkin => 'Özel tema';

  @override
  String skinImportSucceeded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'İçe aktarıldı: # tema.',
      one: 'Bir tema içe aktarıldı.',
    );
    return '$_temp0';
  }

  @override
  String skinImportFailed(String error) {
    return 'Tema içe aktarılamadı: $error';
  }

  @override
  String skinExportFailed(String error) {
    return 'Tema dışa aktarılamadı: $error';
  }

  @override
  String skinRemoveConfirmation(String skin) {
    return '“$skin” kayıtlı temalarınızdan kaldırılacak.';
  }

  @override
  String skinIconColorForItem(String item) {
    return '$item simge rengi';
  }

  @override
  String skinNameColorForItem(String item) {
    return '$item ad rengi';
  }

  @override
  String get skinExportedSingle => 'Tema dışa aktarıldı.';

  @override
  String get skinExportedMultiple => 'Temalar dışa aktarıldı.';

  @override
  String get skinExportSkinsOnly => 'Yalnızca temalar';

  @override
  String get skinExportSkinsOnlySubtitle =>
      'Renkler ve simge stilleri. Paylaşmak güvenlidir.';

  @override
  String get skinExportSkinsAndInterface => 'Temalar ve arayüz';

  @override
  String get skinExportSkinsAndInterfaceSubtitle =>
      'Ayrıca tema modunu, araç çubuğu ve ızgara düzenini, düzenleyici görünümünü ve medya görüntüleyici düzenini de kaydeder. Kendi yedekleriniz için.';

  @override
  String get skinAppearanceExported => 'Temalar ve arayüz dışa aktarıldı.';

  @override
  String get skinImportInterfaceTitle => 'Arayüz ayarları uygulansın mı?';

  @override
  String get skinImportInterfaceMessage =>
      'Bu dosya arayüz ayarlarını da içeriyor. Bunları uygulamak mevcut tema modunuzu, araç çubuğu ve ızgara düzeninizi, düzenleyici görünümünüzü ve medya görüntüleyici düzeninizi değiştirir.';

  @override
  String get skinImportInterfaceApply => 'Uygula';

  @override
  String get skinImportInterfaceSkip => 'Yalnızca temalar';

  @override
  String get skinInterfaceApplied => 'Arayüz ayarları uygulandı.';

  @override
  String get automationBatterySettingsOpenFailedMessage =>
      'Uygulama ayarları açılamadı. Ayarlar > Uygulamalar > VaultExplorer > Pil bölümünü açıp Kısıtlanmamış seçeneğini seçin.';

  @override
  String get apkOpenPackageInstaller => 'Paket yükleyici';

  @override
  String get apkOpenPackageInstallerSubtitle =>
      'Bu uygulamayı cihazınıza yükleyin';

  @override
  String get apkOpenAsZip => 'ZIP olarak aç';

  @override
  String get apkOpenAsZipSubtitle => 'İçindeki dosyalara göz atın ve çıkarın';

  @override
  String get audioEditorEditAction => 'Sesi düzenle';

  @override
  String get audioEditorTimelineLabel => 'Ses zaman çizelgesi';

  @override
  String get audioEditorAnalyzing => 'Ses okunuyor…';

  @override
  String audioEditorLoadFailed(String message) {
    return 'Bu ses dosyası açılamadı: $message';
  }

  @override
  String get audioEditorReadOnly =>
      'Bu kasa salt okunur, bu yüzden düzenlenen ses kaydedilemez.';

  @override
  String get audioEditorExporting => 'Ses dışa aktarılıyor';

  @override
  String audioEditorSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Kaydedildi: $count ses dosyası',
      one: 'Kaydedildi: 1 ses dosyası',
    );
    return '$_temp0';
  }

  @override
  String get audioEditorExportMerge => 'Tek dosyada birleştir';

  @override
  String get audioEditorExportSeparate => 'Ayrı dosyalar olarak kaydet';

  @override
  String get audioEditorReplaceOriginal => 'Orijinal sesin yerine geç';

  @override
  String get audioEditorReplaceOriginalHint =>
      'Orijinal dosya, dışa aktarılan kesimle değiştirilecek.';

  @override
  String get audioEditorLosslessNote =>
      'Kesimler kayıpsızdır: ses yeniden kodlanmadan kopyalanır, bu yüzden kalite değişmez. Kesimler ayarladığınız yerden birkaç milisaniye uzakta, en yakın ses karesine oturur. Etiketler ve kapak resmi aktarılmaz.';

  @override
  String get audioEditorCutOutModeDescription =>
      'Seçili bölümleri kaldırın ve geri kalanı dışa aktarın.';

  @override
  String audioEditorUnsupportedFormat(String format) {
    return '$format dosyaları bu cihazda düzenlenemez, bu yüzden bu dosya burada oynatılabilir ama dışa aktarılamaz.';
  }

  @override
  String get audioEditorPrevCutPoint => 'Önceki kesim noktası';

  @override
  String get audioEditorNextCutPoint => 'Sonraki kesim noktası';

  @override
  String get audioEditorStepBack => 'Geri git';

  @override
  String get audioEditorStepForward => 'İleri git';

  @override
  String audioEditorReencodeBanner(String format) {
    return '$format sesi olduğu gibi kopyalanamaz, bu yüzden dışa aktarırken AAC\'ye (.m4a) yeniden kodlanacak.';
  }

  @override
  String get audioEditorReencodeNote =>
      'Bu biçim kopyalanamaz, bu yüzden dışa aktarılan ses AAC\'ye yeniden kodlanır. Kalite yüksek kalır ama bit bit aynı olmaz. Kesimler tam ayarladığınız yere oturur. Etiketler ve kapak resmi aktarılmaz.';

  @override
  String get mediaViewerActionAbLoop => 'A-B tekrarı';

  @override
  String abLoopStartMarkedMessage(String time) {
    return 'A noktası: $time. B\'yi ayarlamak için yeniden dokunun.';
  }

  @override
  String abLoopStartedMessage(String start, String end) {
    return 'Tekrarlanıyor: $start – $end';
  }

  @override
  String get abLoopClearedMessage => 'A-B tekrarı kapalı';

  @override
  String get skinEditorPanelBackground => 'Düzenleyici paneli arka planı';

  @override
  String get skinEditorPanelBackgroundDescription =>
      'Düzenleyici kenar çubuğu ve Diğer Eylemler menüleri için ortak arka plan.';

  @override
  String get skinFollowAppSkin => 'Uygulama temasını izle';

  @override
  String get fileSkinFollowAppSkinDescription =>
      'Dosya ve klasör stili seçili uygulama temasını izler.';

  @override
  String get fileSkinUseIndependentStylesDescription =>
      'Bu seçenekler Dosya Yöneticisi\'nin kendi stilini belirler. Uygulama Temasını izliyorsa, aşağıdaki bir hazır ayarı veya stili değiştirmek Uygulama temasını izle seçeneğini kapatır.';

  @override
  String get fileSkinManagedByAppSkinTitle =>
      'Dosya yöneticisi uygulama temasını izliyor';

  @override
  String get fileSkinManagedByAppSkinDescription =>
      'Önizleme etkin Uygulama Temasını kullanır. Aşağıdaki bir hazır ayarı veya stili değiştirmek bağımsız bir dosya yöneticisi teması kaydeder ve Uygulama temasını izle seçeneğini kapatır.';

  @override
  String get skinFileManagerIndependentTitle =>
      'Dosya yöneticisi bağımsız bir tema kullanıyor';

  @override
  String get skinFileManagerIndependentDescription =>
      'Bu Uygulama Temasındaki dosya ve klasör stili değişiklikleri, Dosya Yöneticisi kendi temasını kullandığı sürece orada görünmez. Bu Uygulama Temasını oraya uygulamak için Uygulama temasını izle seçeneğini açın.';

  @override
  String get skinChooseOrCreateSkin => 'Bir tema seçin veya oluşturun';

  @override
  String get skinSkinShortcutCustomDescription =>
      'Uygulama genelindeki renkleri ve ortak belirteçleri düzenleyin. Bileşen geçersiz kılmaları bu sayfada kalır.';

  @override
  String get skinSkinShortcutPresetDescription =>
      'Yerleşik temalara göz atın veya bu görünümden özel bir tema oluşturun.';

  @override
  String get textEditorUseIndependentAppearanceDescription =>
      'Aşağıdan bağımsız bir düzenleyici arka planı ve sözdizimi teması seçin.';

  @override
  String get fileSkinComponentStyling => 'Bileşen stili';

  @override
  String get textEditorStyling => 'Düzenleyici stili';

  @override
  String get audioFilePropertiesSectionHeader => 'SES';

  @override
  String get audioTagsSectionHeader => 'PARÇA BİLGİSİ';

  @override
  String get artistLabel => 'Sanatçı';

  @override
  String get albumLabel => 'Albüm';

  @override
  String get yearLabel => 'Yıl';

  @override
  String get genreLabel => 'Tür';

  @override
  String get audioTrackLabel => 'Parça';

  @override
  String get bitDepthLabel => 'Bit derinliği';

  @override
  String get colorModeLabel => 'Renk modu';

  @override
  String get transparencyLabel => 'Saydamlık';

  @override
  String get animationLabel => 'Animasyon';

  @override
  String get orientationLabel => 'Yönelim';

  @override
  String get densityLabel => 'Piksel yoğunluğu';

  @override
  String get encodingLabel => 'Kodlama';

  @override
  String get skinEditorCodeTextColorDescription =>
      'Düz kod için varsayılan metin rengi. Sözdizimi vurgulu metin kendi renklerini korur.';

  @override
  String get skinEditorInterfaceText => 'Düzenleyici arayüz metni';

  @override
  String get skinEditorInterfaceTextDescription =>
      'Düzenleyici araç çubuğu, kenar çubuğu, menüler ve durum çubuğundaki metin ve simgeler.';

  @override
  String get equalizerTitle => 'Ekolayzer';

  @override
  String get equalizerPresetCustom => 'Özel';

  @override
  String get equalizerPreampLabel => 'Ön yükselteç';

  @override
  String get equalizerPreventClippingTitle => 'Kırpılmayı önle';

  @override
  String get equalizerPreventClippingSubtitle =>
      'Yükseltilen bantların bozulmaması için genel sesi yalnızca gerektiği kadar düşürür';

  @override
  String get equalizerPresetFlat => 'Düz';

  @override
  String get equalizerPresetBassBoost => 'Bas yükseltme';

  @override
  String get equalizerPresetTrebleBoost => 'Tiz yükseltme';

  @override
  String get equalizerPresetVoice => 'Ses';

  @override
  String get equalizerPresetRock => 'Rock';

  @override
  String get equalizerPresetPop => 'Pop';

  @override
  String get equalizerPresetJazz => 'Caz';

  @override
  String get equalizerPresetClassical => 'Klasik';

  @override
  String get equalizerPresetElectronic => 'Elektronik';

  @override
  String get equalizerPresetLoudness => 'Loudness';

  @override
  String get audioRecorder => 'Ses kaydedici';

  @override
  String get audioCapturedEncrypted => 'Ses kaydedildi';

  @override
  String get audioMicPermissionRequiredMessage =>
      'Ses kaydetmek için mikrofon izni gerekli.';

  @override
  String get audioRecordingAllowMicrophone => 'Mikrofona izin ver';

  @override
  String get audioRecordingStartTooltip => 'Kaydı başlat';

  @override
  String get audioRecordingStopTooltip => 'Kaydı durdur';

  @override
  String get audioRecordingPauseTooltip => 'Duraklat';

  @override
  String get audioRecordingResumeTooltip => 'Sürdür';

  @override
  String get audioRecordingPausedLabel => 'Duraklatıldı';

  @override
  String get audioRecordingDiscardTitle => 'Kayıt atılsın mı?';

  @override
  String get audioRecordingDiscardMessage =>
      'Bu kayıt kaydedilmedi ve kalıcı olarak silinecek.';

  @override
  String get skinAreaDashboard => 'Pano';

  @override
  String get skinAreaDashboardDescription =>
      'Açılışta karşılaştığınız kasa listesi ve kasa kartları.';

  @override
  String get skinAreaDrawer => 'Yan menü';

  @override
  String get skinAreaDrawerDescription =>
      'Kasalarınızı ve kısayollarınızı içeren kayan menü.';

  @override
  String get skinAreaFilesDescription =>
      'Kilidi açık bir kasanın içindeki dosya tarayıcısı.';

  @override
  String get skinAreaEditorDescription =>
      'Metin ve kod düzenleyicinin araç çubuğu. Tuval ve sözdizimi renkleri aşağıdaki düzenleyici temasında ayarlanır.';

  @override
  String get skinAreaToolsDescription =>
      'Araçlar sekmesi ve ondan açılan her araç.';

  @override
  String get skinAreaSettingsDescription => 'Ayarlar sekmesi ve alt sayfaları.';

  @override
  String get skinSharedPaletteTitle => 'Ortak palet';

  @override
  String get skinSharedPaletteDescription =>
      'Her sayfanın kendi rengini belirleyene kadar devraldığı renkler. Kilit açma ve kamera gibi kendi bölümü olmayan ekranlar bunları doğrudan kullanır.';

  @override
  String get skinSharedBarDescription =>
      'Kendi çubuğunu belirlemeyen her sayfanın üst çubuğu.';

  @override
  String get skinSharedFabDescription =>
      'Kendi düğmesini belirlemeyen her sayfanın yuvarlak ekle düğmesi.';

  @override
  String get skinPagesTitle => 'Sayfa renkleri';

  @override
  String get skinPagesDescription =>
      'Her sayfa kendi renklerini korur. Bir sayfayı değiştirmek asla diğerini değiştirmez.';

  @override
  String get skinResetPageColors => 'Sayfa renklerini sıfırla';

  @override
  String get inPlaceEditDone => 'Bitti';

  @override
  String get inPlaceEditTitle => 'Denetimleri düzenle';

  @override
  String get inPlaceEditHint =>
      'Eylemleri çubuklar arasında sürükleyin veya düzenlemek için dokunun';

  @override
  String get inPlaceEditTopDock => 'Üst çubuk';

  @override
  String get inPlaceEditBottomDock => 'Alt çubuk';

  @override
  String get inPlaceEditDragToRemove => 'Kaldırmak için buraya sürükleyin';

  @override
  String get inPlaceEditAddToTop => 'Üst çubuğa ekle';

  @override
  String get inPlaceEditAddToBottom => 'Alt çubuğa ekle';

  @override
  String get inPlaceEditEmptyDock => 'Eylemleri buraya bırakın';

  @override
  String get inPlaceEditPlayerSettings => 'Oynatıcı ayarları';

  @override
  String get inPlaceEditMoveToMore => 'Diğer menüsüne taşı';

  @override
  String get inPlaceEditMoveToAdvanced => 'Gelişmiş ayarlara taşı';

  @override
  String get inPlaceEditHideAction => 'Eylemi gizle';

  @override
  String get inPlaceEditHidden => 'Gizli';

  @override
  String get textEditorAutoHideAppBarLabel =>
      'Uygulama çubuğunu otomatik gizle';

  @override
  String get textEditorAutoHideAppBarDescription =>
      'Dikey alanı en üst düzeye çıkarmak için düzenlerken üst çubuğu gizle';

  @override
  String get textEditorCopyToMenuItem => 'Şuraya kopyala...';

  @override
  String get textEditorCopyToDialogTitle => 'Klasöre kopyala';

  @override
  String get textEditorCopyHereButton => 'Buraya kopyala';

  @override
  String get textEditorDuplicateMenuItem => 'Kopyasını oluştur';

  @override
  String get textEditorCopiedSuccessfully => 'Başarıyla kopyalandı';

  @override
  String get textEditorSearchFilesHint => 'Dosyaları filtrele…';

  @override
  String get audioRecordingQualityLabel => 'Ses kaydı kalitesi';

  @override
  String get audioRecordingQualityVoice => 'Ses';

  @override
  String get audioRecordingQualityStandard => 'Standart';

  @override
  String get audioRecordingQualityHigh => 'Yüksek';

  @override
  String audioRecordingQualityDetails(String bitrate, String sampleRate) {
    return 'AAC · $bitrate kbps · $sampleRate kHz · mono';
  }

  @override
  String get audioEditorCompressTitle => 'Dosya boyutu';

  @override
  String get audioEditorCompressOriginal => 'Orijinal';

  @override
  String audioEditorCompressEstimate(String size) {
    return 'Tahmini boyut: yaklaşık $size';
  }

  @override
  String get audioEditorCompressNote =>
      'Ses daha düşük bit hızıyla AAC\'ye yeniden kodlanır, bu yüzden dosya daha küçük olur ama kalite düşer. Kesimler tam ayarladığınız yere oturur. Etiketler ve kapak resmi aktarılmaz.';

  @override
  String get entropyStepTitle => 'Rastgelelik ekle';

  @override
  String get entropyIntro =>
      'Parmağınızı ped üzerinde tahmin edilemez, çeşitli hareketlerle gezdirin. Hareketleriniz, cihazın güvenli rastgele üretecine ek olarak, onun yerine geçmeden, şifreleme anahtarlarına ve tuzlarına karıştırılır.';

  @override
  String get entropyPadHint => 'Parmağınızla buraya çizin';

  @override
  String get entropyPadSemantics =>
      'Rastgelelik pedi. Rastgele hareket toplamak için parmağınızı üzerinde gezdirin.';

  @override
  String entropyProgress(int percent) {
    return 'Rastgelelik toplanıyor… $percent%';
  }

  @override
  String get entropyComplete =>
      'Yeterli rastgelelik toplandı. Daha fazla eklemek için hareket etmeye devam edin ya da devam edin.';

  @override
  String get entropySkippedStatus =>
      'Atlandı. Yalnızca cihazın güvenli rastgele üreteci kullanılacak. Rastgelelik eklemek için pede yeniden çizin.';

  @override
  String get entropyPoolLabel => 'Rastgele havuz';

  @override
  String get entropySkip => 'Atla ve yalnızca cihaz üretecini kullan';

  @override
  String get entropyReviewLabel => 'Rastgelelik';

  @override
  String get entropyReviewUserAdded => 'Dokunma hareketi + cihaz üreteci';

  @override
  String get entropyReviewDeviceOnly => 'Yalnızca cihaz üreteci';

  @override
  String get automationCaptureSectionHeader => 'Kamera ve mikrofon';

  @override
  String get automationAllowCaptureTitle =>
      'Kamera ve mikrofon yakalamasına izin ver';

  @override
  String get automationAllowCaptureSubtitle => 'Fotoğraf, video ve ses kaydı';

  @override
  String get automationPermissionsSectionHeader => 'İzinler';

  @override
  String get automationPermissionsIntro =>
      'Bunlar Android izinleridir, yani yalnızca bu kasa için değil tüm uygulama için geçerlidir. Yalnızca bu kasanın kurulumunun kullanabildikleri, her birinin mevcut durumuyla listelenir.';

  @override
  String get automationPermSetupNeededTitle => 'Kurulum gerekli';

  @override
  String get automationPermAlmostReadyTitle => 'Neredeyse hazır';

  @override
  String get automationPermReadyTitle => 'Hazır';

  @override
  String get automationPermReadyMessage =>
      'Bu kasanın otomasyonu için gereken her şey hazır.';

  @override
  String get automationPermGrantButton => 'İzin ver';

  @override
  String get automationPermGranted => 'Verildi';

  @override
  String get automationPermTagRequired => 'Gerekli';

  @override
  String get automationPermTagRecommended => 'Önerilen';

  @override
  String get automationPermTagOptional => 'İsteğe bağlı';

  @override
  String get automationPermDeniedMessage =>
      'İzin verilmedi. Android yeniden sormazsa uygulamanın ayarlarından açın.';

  @override
  String get automationPermSettingsOpenFailedMessage =>
      'Uygulama ayarları açılamadı. Ayarlar > Uygulamalar > VaultExplorer > İzinler bölümünü açın.';

  @override
  String get automationPermBatteryTitle => 'Kısıtlanmamış pil kullanımı';

  @override
  String get automationPermBatteryDescription =>
      'VaultExplorer tamamen kapalıyken otomasyonun bu kasanın kilidini açmasını sağlar. Bu olmadan Android eylemi engelleyebilir.';

  @override
  String get automationPermNotificationsTitle => 'Bildirimler';

  @override
  String get automationPermNotificationsDescription =>
      'İçe aktarma, dışa aktarma ve eşitleme ilerlemesini ve kayıt çalışırken göstergeyi gösterir.';

  @override
  String get automationPermAllFilesTitle => 'Tüm dosyalara erişim';

  @override
  String get automationPermAllFilesDescription =>
      'İçe ve dışa aktarma eylemlerinin /storage/emulated/0/… gibi düz dosya yollarını kullanmasını sağlar. content:// bağlantıları için gerekmez.';

  @override
  String get automationPermCameraTitle => 'Kamera';

  @override
  String get automationPermCameraDescription =>
      'Otomasyonun çektiği fotoğraf ve videolar.';

  @override
  String get automationPermMicrophoneTitle => 'Mikrofon';

  @override
  String get automationPermMicrophoneDescription =>
      'Ses kayıtları ve video sesi. Fotoğraf ve video çekimi de bunu denetler.';

  @override
  String get automationPermOverlayDescription =>
      'Yalnızca otomasyon uygulamanız Android 14+ üzerinde Broadcast ile fotoğraf veya video çekimi başlatıyorsa gerekir. Doğrudan çekim etkinliğini hedeflediğinde gerekmez.';

  @override
  String automationPermSetupNeededMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count gerekli izin eksik. İzinler verilene kadar bazı otomasyon eylemleri başarısız olur.',
      one:
          '1 gerekli izin eksik. İzin verilene kadar bazı otomasyon eylemleri başarısız olur.',
    );
    return '$_temp0';
  }

  @override
  String automationPermAlmostReadyMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count önerilen ayar hâlâ kapalı. Otomasyon çalışır, ama daha az güvenilir olabilir.',
      one:
          '1 önerilen ayar hâlâ kapalı. Otomasyon çalışır, ama daha az güvenilir olabilir.',
    );
    return '$_temp0';
  }

  @override
  String get resetSizeOnLayoutChangeLabel => 'Düzen değişince boyutu sıfırla';

  @override
  String get resetSizeOnLayoutChangeDesc =>
      'Düzen değiştirdiğinizde liste yakınlaştırmasını ve ızgara/mozaik sütun sayısını varsayılanlara döndür';

  @override
  String get thumbnailUseGlobalDefaultDesc =>
      'Uygulama ayarlarındaki küçük resim varsayılanlarını izler, bu yüzden oradaki değişiklikler bu kasaya da ulaşır.';

  @override
  String get resetVaultThumbnailsTitle => 'Tüm kasaları varsayılana sıfırla';

  @override
  String get resetVaultThumbnailsSubtitle =>
      'Kendi ayarları olan kasalar dahil her kasanın yukarıdaki küçük resim varsayılanlarını izlemesini sağlar.';

  @override
  String resetVaultThumbnailsConfirmMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count kasanın kendi küçük resim ayarları var. Bunun yerine varsayılanı izlesin mi?',
      one:
          '1 kasanın kendi küçük resim ayarları var. Bunun yerine varsayılanı izlesin mi?',
    );
    return '$_temp0';
  }

  @override
  String resetVaultThumbnailsDone(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kasa artık varsayılanı izliyor',
      one: '1 kasa artık varsayılanı izliyor',
    );
    return '$_temp0';
  }

  @override
  String get scanAdjustCornersTitle => 'Köşeleri ayarla';

  @override
  String get scanResultTitle => 'Taranan sayfa';

  @override
  String get scanAutoDetectButton => 'Otomatik algıla';

  @override
  String get scanFullImageButton => 'Tam resim';

  @override
  String get scanFilterColor => 'Renk';

  @override
  String get scanFilterGrayscale => 'Gri tonlama';

  @override
  String get scanHintSearching => 'Kamerayı bir belgeye doğrultun';

  @override
  String get scanHintFound => 'Belge algılandı';

  @override
  String get scanNoDocumentFound =>
      'Belge algılanamadı. Sayfaya oturtmak için köşeleri sürükleyin.';

  @override
  String get scanProcessingFailed => 'Bu sayfa işlenemedi';

  @override
  String get scanDetectingEdges => 'Kenarlar algılanıyor…';

  @override
  String get scanOutputPdf => 'PDF';

  @override
  String get scanOutputImages => 'Resimler';

  @override
  String get scanPdfFailed => 'PDF oluşturulamadı';

  @override
  String get settingsSearchHint => 'Ayarlarda ara';

  @override
  String get settingsSearchClear => 'Aramayı temizle';

  @override
  String get settingsSearchNoResults => 'Eşleşen ayar yok';

  @override
  String get settingsSearchNoResultsHint =>
      'Farklı bir sözcük deneyin veya yazımı denetleyin.';

  @override
  String get settingsSearchUnavailable =>
      'Bu seçenek yalnızca ilgili bir ayar açıkken görünür.';

  @override
  String createArchiveCompressingSubtitle(String count, String size) {
    return 'Sıkıştırılıyor: $count ($size)';
  }

  @override
  String createArchiveInsufficientSpace(String required, String available) {
    return 'Yeterli boş alan yok — gereken: $required, yalnızca $available boş.';
  }

  @override
  String get createArchiveNameLabel => 'Arşiv adı';

  @override
  String get createArchiveNameHint => 'arşiv';

  @override
  String get createArchiveSelectFormatTooltip => 'Biçim seç';

  @override
  String get createArchivePasswordLabel => 'Parola (isteğe bağlı)';

  @override
  String get createArchiveConfirmPasswordLabel => 'Parolayı onayla';

  @override
  String get passphraseStrengthFair => 'Orta';

  @override
  String get createArchiveCompressionLevel => 'Sıkıştırma düzeyi';

  @override
  String get createArchiveSplitVolumes => 'Ciltlere böl';

  @override
  String get createArchiveSplitVolumeNone => 'Yok';

  @override
  String get createArchiveCustomVolumeSizeLabel => 'Özel cilt boyutu (MB)';

  @override
  String get createArchiveCustomVolumeSizeHint => 'örn. 50';

  @override
  String get archiveCompressionStoreTitle => 'Sakla (0) — Sıkıştırma yok';

  @override
  String get archiveCompressionStoreDesc =>
      'Anında paketleme, videolar, müzik ve arşivler için en iyisi';

  @override
  String get archiveCompressionFastTitle => 'Hızlı (1–3) — Çabuk';

  @override
  String get archiveCompressionFastDesc =>
      'Günlük paylaşım için hızlı sıkıştırma';

  @override
  String get archiveCompressionNormalTitle => 'Normal (5) — Dengeli';

  @override
  String get archiveCompressionNormalDesc => 'Dengeli sıkıştırma ve hız';

  @override
  String get archiveCompressionUltraTitle => 'Ultra (9) — En küçük boyut';

  @override
  String get archiveCompressionUltraDesc =>
      'En küçük boyut, daha yavaş sıkıştırma';

  @override
  String get fileAssocDocumentViewer => 'Uygulama içi belge görüntüleyici';

  @override
  String get archiveCompressionMethodLabel => 'Sıkıştırma yöntemi';

  @override
  String get archiveMethodLzma2Desc =>
      'Genel olarak en iyi seçim. .tar.xz için de kullanılır.';

  @override
  String get archiveMethodLzmaDesc =>
      '7-Zip\'in eski yöntemi. .tar.lzma için de kullanılır.';

  @override
  String get archiveMethodDeflateDesc =>
      'En hızlısı, daha büyük dosyalar ve en geniş destek. ZIP ve .tar.gz için de kullanılır.';

  @override
  String get browserTabsEnabledTitle => 'Dosya yöneticisi sekmelerini kullan';

  @override
  String get browserTabsEnabledSubtitle =>
      'Birden fazla konumu açık tutun ve aralarında geçiş yapın.';

  @override
  String get browserTabNew => 'Yeni sekme';

  @override
  String get browserTabClose => 'Sekmeyi kapat';

  @override
  String get browserTabCloseOthers => 'Diğer sekmeleri kapat';

  @override
  String get browserTabDuplicate => 'Sekmeyi çoğalt';

  @override
  String get browserTabMoveToOtherPane => 'Diğer bölmeye taşı';

  @override
  String get browserTabOpenInNewTab => 'Yeni sekmede aç';

  @override
  String browserTabLimitReached(int max) {
    return 'Sekme sınırına ulaşıldı ($max)';
  }

  @override
  String get browserTabCloseToLeft => 'Soldaki sekmeleri kapat';

  @override
  String get browserTabCloseToRight => 'Sağdaki sekmeleri kapat';

  @override
  String get dualPaneEnabledTitle => 'Çift bölme kullan';

  @override
  String get dualPaneEnabledSubtitle =>
      'Ekran yeterince genişse iki açık sekmeyi yan yana göster. Dosya yöneticisi sekmeleri gerekir.';

  @override
  String get pressBackAgainToExit => 'Çıkmak için geri tuşuna yeniden basın';

  @override
  String get tabEdgeSwipeLabel => 'Sekme kaydırma hareketi';

  @override
  String get tabSwipeBetweenTabsTitle => 'Sekmeler arasında kaydır';

  @override
  String get tabSwipeBetweenTabsOnDesc =>
      'Sonraki veya önceki sekmeye geçmek için bir klasörde yana kaydırın.';

  @override
  String get tabSwipeBetweenTabsOffDesc =>
      'Sekmeler yalnızca sekme şeridinden değişir. Aşağıdaki iki hareket o zaman ekranın her yerinde çalışır.';

  @override
  String get tabSwipeRightOnFirstTab => 'İlk sekmede sağa kaydır';

  @override
  String get tabSwipeRightAnywhere => 'Her yerde sağa kaydır';

  @override
  String get tabSwipeLeftOnLastTab => 'Son sekmede sola kaydır';

  @override
  String get tabSwipeLeftAnywhere => 'Her yerde sola kaydır';

  @override
  String get tabSwipeActionNewTab => 'Yeni sekme aç';

  @override
  String get tabSwipeActionOpenDrawer => 'Yan menüyü aç';

  @override
  String get tabSwipeActionLoopFirst => 'İlk sekmeye dön';

  @override
  String get tabSwipeActionLoopLast => 'Son sekmeye dön';

  @override
  String get tabSwipeActionNothing => 'Hiçbir şey yapma';

  @override
  String get tabSwipeRightNothingDesc =>
      'Yan menü yine sol ekran kenarından ve menü düğmesinden açılır.';

  @override
  String get tabSwipeRightLoopDesc =>
      'Yan menü sol ekran kenarından veya menü düğmesinden açılır. Tek sekme varsa bu kaydırma onu açar.';

  @override
  String get tabSwipeNewTabsFromStripDesc =>
      'Yeni sekmeler yine sekme şeridinden açılır.';

  @override
  String get tabSwipePreviewFirstTab => 'İlk sekme';

  @override
  String get tabSwipePreviewLastTab => 'Son sekme';

  @override
  String get appBarAtBottomLabel => 'Uygulama çubuğunu altta göster';

  @override
  String get appBarAtBottomDesc =>
      'Uygulama çubuğunu ekranın üstünden, başparmağınızın daha kolay ulaşabileceği alta taşıyın.';

  @override
  String get sectionNavigation => 'Gezinme';

  @override
  String get predictiveBackAnimationsLabel => 'Öngörülü geri animasyonları';

  @override
  String get predictiveBackAnimationsDesc =>
      'Geri giderken etkileşimli önizlemeler ve animasyonlar göster.';

  @override
  String get selectByIconLabel => 'Simgeye dokunarak seç';

  @override
  String get selectByIconDesc =>
      'Liste görünümünde bir dosya veya klasörün simgesine dokunmak onu seçer. Kapalıyken simgeye dokunmak bir şey yapmaz.';

  @override
  String get doubleClickToOpenLabel => 'Açmak için çift tıkla';

  @override
  String get doubleClickToOpenDesc =>
      'Bir tıklama öğeyi seçer, çift tıklama açar; masaüstü dosya yöneticilerindeki gibi. Kapalıyken tek dokunuş veya tıklama öğeyi açar.';

  @override
  String get showFileExtensionsLabel => 'Dosya uzantılarını göster';

  @override
  String get showFileExtensionsDesc =>
      'Dosya adlarının sonunda uzantıyı göster. Arama sırasında uzantılar her zaman gösterilir.';

  @override
  String get itemActionsMenuTitle => 'Öğe eylemleri';

  @override
  String get itemActionsMenuDesc =>
      'Öğe menüsünde ve seçim menüsünde hangi eylemlerin görüneceğini ve görünme sırasını seçin.';

  @override
  String get itemActionsQuickRowHeader => 'Hızlı eylemler satırı';

  @override
  String get itemActionsMenuListHeader => 'Menü listesi';

  @override
  String get itemActionsMoveToQuickRow => 'Hızlı eylemler satırına taşı';

  @override
  String get itemActionsMoveToMenuList => 'Menü listesine taşı';

  @override
  String get skinEditStarted =>
      'Tema düzenleyici açık. Bir renk seçip değiştirmek için herhangi bir ekrandaki yüzen düğmeleri kullanın.';

  @override
  String get skinEditSaved => 'Tema kaydedildi';

  @override
  String get skinEditPickTooltip => 'Rengini değiştirmek için bir öğe seç';

  @override
  String get skinEditPickStopTooltip =>
      'Seçmeyi bırak ve uygulamayı normal kullan';

  @override
  String get skinEditDoneTooltip => 'Tema düzenleyiciyi kaydet ve kapat';

  @override
  String get skinEditHint =>
      'Rengini değiştirmek için herhangi bir öğeye dokunun. Uygulamayı normal kullanmak için damlalığa yeniden dokunun.';

  @override
  String get skinEditLayersTitle => 'Bu noktadaki renkler';

  @override
  String get skinEditAlsoUsedBy => 'Aynı renk şuralarda da kullanılıyor';

  @override
  String get skinEditClosest =>
      'Bu boyaya tam eşleşme yok, bu yüzden en yakın tema rengi bu.';

  @override
  String get skinEditNoMatch =>
      'Bu nokta doğrudan bir tema rengi kullanmıyor. Listeden bir renk seçin.';

  @override
  String get skinEditAllColors => 'Tüm renkler';

  @override
  String get skinEditBackToEditor => 'Renk düzenleyiciye dön';

  @override
  String get skinEditStatusInherited => 'Devralınmış';

  @override
  String get skinEditReset => 'Sıfırla';

  @override
  String get skinEditMoreOptions => 'Tüm renkler ve seçenekler';

  @override
  String get skinEditCollapse => 'Paneli daralt';

  @override
  String get skinEditExpand => 'Paneli genişlet';

  @override
  String skinEditPageColors(String page) {
    return 'Renkler: $page';
  }

  @override
  String get skinEditDockTop => 'Paneli üste taşı';

  @override
  String get skinEditDockBottom => 'Paneli alta taşı';

  @override
  String get skinEditEditorIndependent =>
      'Metin düzenleyici kendi renklerini kullanıyor, bu yüzden uygulama temasını izleyene kadar buradaki değişiklikler onda görünmez.';

  @override
  String get cameraKeepShootingTooltip => 'Her çekimden sonra çekime devam et';

  @override
  String get cameraSegmentLengthOff => 'Kapalı';

  @override
  String cameraSegmentLengthMinutes(int minutes) {
    return '$minutes dk';
  }

  @override
  String get cameraSegmentLengthTooltip =>
      'Kaydı ilerledikçe kaydedilen parçalara böl';

  @override
  String get cameraSegmentSpaceMessage =>
      'Kasada yeterli boş alan yok. Kayıt durduruldu; kaydedilemeyen parça incelemeniz için saklandı.';

  @override
  String get audioSegmentedStopTitle => 'Kayıt durdurulsun mu?';

  @override
  String get audioSegmentedStopMessage =>
      'Şimdiye kadar kaydedilen parçalar zaten kasaya kaydedildi. Şimdi durdurup kalanı kaydedelim mi?';

  @override
  String get audioSegmentedStopAction => 'Durdur ve kaydet';

  @override
  String get audioUnsavedPartsTitle => 'Bazı parçalar kaydedilmedi';

  @override
  String audioUnsavedPartsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Kaydedilen $count parça kaydedilemedi.',
      one: 'Kaydedilen 1 parça kaydedilemedi.',
    );
    return '$_temp0 Alan açıp yeniden deneyin ya da bunları atın.';
  }

  @override
  String get segmentRetrySave => 'Yeniden dene';

  @override
  String get imageEditorActionAuto => 'Otomatik';

  @override
  String get imageEditorActionFlip => 'Çevir';

  @override
  String get imageEditorActionRotate => 'Döndür';

  @override
  String get imageEditorActionColor => 'Renk';

  @override
  String get imageEditorActionSize => 'Boyut';

  @override
  String get imageEditorActionOpacity => 'Opaklık';

  @override
  String get imageEditorActionStyle => 'Stil';

  @override
  String get imageEditorExportSave => 'Dışa aktar / Kaydet';

  @override
  String get imageEditorRevertOriginal => 'Orijinale dön';

  @override
  String get imageEditorTuneImageToolLabel => 'Resmi ayarla';

  @override
  String get imageEditorLooksToolLabel => 'Görünümler';

  @override
  String get imageEditorLookCurrent => 'Mevcut';

  @override
  String get imageEditorLookPortrait => 'Portre';

  @override
  String get imageEditorLookDramatic => 'Dramatik';

  @override
  String get imageEditorLookVintage => 'Nostaljik';

  @override
  String get imageEditorTuneAmbiance => 'Ortam';

  @override
  String get imageEditorTuneWarmth => 'Sıcaklık';

  @override
  String get imageEditorTuneShadows => 'Gölgeler';

  @override
  String get imageEditorCropAspectDin => 'DIN';

  @override
  String get imageEditorAngle => 'Açı';

  @override
  String get imageEditorTextPlaceholder =>
      'METNİ DEĞİŞTİRMEK İÇİN BURAYA ÇİFT DOKUNUN';

  @override
  String imageEditorPhotoLabel(int index) {
    return 'Fotoğraf $index';
  }

  @override
  String get cameraPauseRecordingTooltip => 'Kaydı duraklat';

  @override
  String get cameraResumeRecordingTooltip => 'Kaydı sürdür';

  @override
  String get cameraSnapshotTooltip => 'Kayıt sırasında fotoğraf çek';

  @override
  String get cameraPauseFailedMessage =>
      'Kayıt duraklatılamadı veya sürdürülemedi';

  @override
  String get floatingPlayerTitle => 'Yüzen video oynatıcı';

  @override
  String get floatingPlayerSubtitle =>
      'Bir video oynarken oynatıcıyı kapatmak, onu taşıyabileceğiniz küçük bir pencerede tutar. Uygulamadan çıkmak onu yalnızca ses düğmeli pencere içinde pencereye dönüştürür';

  @override
  String get floatingPlayerExpandTooltip => 'Genişlet';

  @override
  String get floatingPlayerAudioOnly => 'Yalnızca ses';

  @override
  String get masterLockTitle => 'Ana kilit';

  @override
  String get masterLockInactiveSubtitle =>
      'Uygulamayı açmak için parola, PIN veya desen iste';

  @override
  String get masterLockChooseTitle => 'Uygulamanın nasıl kilitleneceğini seçin';

  @override
  String get masterLockBackupTitle => 'Yedek kilit açma ekle';

  @override
  String get masterLockBackupMessage =>
      'Biyometrik kilit açma için yedek olarak bir parola, PIN veya desen gerekir. Birini de kurmak için seçin.';

  @override
  String get masterCredentialPassword => 'Parola';

  @override
  String get masterCredentialPin => 'PIN';

  @override
  String get masterCredentialPattern => 'Desen';

  @override
  String get masterCredentialSet => 'Ayarlandı';

  @override
  String get masterCredentialNotSet => 'Ayarlanmadı';

  @override
  String get duressMasterLockRequired =>
      'Baskı altı kilit açmayı yapılandırmadan önce Uygulama Güvenliği\'nde bir ana kilit etkinleştirilmelidir.';

  @override
  String get skinTokenGroupSurface => 'Yüzeyler';

  @override
  String get skinTokenGroupContent => 'Metin ve simgeler';

  @override
  String get skinTokenGroupBorder => 'Kenarlıklar';

  @override
  String get skinTokenGroupChrome => 'Üst çubuk';

  @override
  String get skinTokenGroupAction => 'Düğmeler';

  @override
  String get skinTokenGroupControl => 'Anahtarlar ve kaydırıcılar';

  @override
  String get skinTokenGroupChoice => 'Çipler ve bölümler';

  @override
  String get skinTokenGroupSelection => 'Seçili öğeler';

  @override
  String get skinTokenGroupOverlay => 'Menüler, iletişim kutuları ve sayfalar';

  @override
  String get skinTokenGroupFloating => 'Yüzen öğeler';

  @override
  String get skinTokenSurfacePage => 'Sayfa arka planı';

  @override
  String get skinTokenSurfacePageHint =>
      'Bu sayfadaki her şeyin arkasındaki tuval.';

  @override
  String get skinTokenSurfaceCard => 'Kartlar ve satırlar';

  @override
  String get skinTokenSurfaceCardHint =>
      'Kartlar, liste satırları ve gruplanmış paneller.';

  @override
  String get skinTokenSurfaceCardActive => 'Etkin kart';

  @override
  String get skinTokenSurfaceCardActiveHint =>
      'Kilidi açık bir kasa gibi vurgulanan kart.';

  @override
  String get skinTokenSurfaceTile => 'Karolar ve küçük resimler';

  @override
  String get skinTokenSurfaceTileHint =>
      'Küçük resim yer tutucuları, simge karoları ve kod blokları.';

  @override
  String get skinTokenSurfaceField => 'Giriş alanları';

  @override
  String get skinTokenSurfaceFieldHint =>
      'Metin alanlarının ve arama çubuklarının dolgusu.';

  @override
  String get skinTokenContentPrimary => 'Ana metin';

  @override
  String get skinTokenContentPrimaryHint => 'Başlıklar, adlar ve gövde metni.';

  @override
  String get skinTokenContentSecondary => 'İkincil metin';

  @override
  String get skinTokenContentSecondaryHint =>
      'Alt başlıklar, ayrıntılar ve ipuçları.';

  @override
  String get skinTokenContentIcon => 'Simgeler';

  @override
  String get skinTokenContentIconHint =>
      'Bir düğmenin veya çubuğun üzerinde olmayan düz simgeler.';

  @override
  String get skinTokenBorderDivider => 'Ayırıcılar';

  @override
  String get skinTokenBorderDividerHint =>
      'Satırlar ve bölümler arasındaki ince çizgiler.';

  @override
  String get skinTokenBorderOutline => 'Çerçeveler';

  @override
  String get skinTokenBorderOutlineHint =>
      'Çerçeveli düğmelerin ve seçilmemiş seçenek kutularının kenarlıkları.';

  @override
  String get skinTokenBorderFocus => 'Odak halkası';

  @override
  String get skinTokenBorderFocusHint => 'Düzenlenen metin alanının kenarlığı.';

  @override
  String get skinTokenChromeTopBar => 'Üst çubuk';

  @override
  String get skinTokenChromeTopBarHint => 'Üst çubuğun dolgusu.';

  @override
  String get skinTokenChromeOnTopBar => 'Üst çubuk metni ve simgeleri';

  @override
  String get skinTokenChromeOnTopBarHint =>
      'Üst çubuktaki başlık ve simge rengi.';

  @override
  String get skinTokenActionPrimary => 'Dolu düğmeler';

  @override
  String get skinTokenActionPrimaryHint => 'Dolu düğmelerin dolgusu.';

  @override
  String get skinTokenActionOnPrimary => 'Dolu düğme etiketi';

  @override
  String get skinTokenActionOnPrimaryHint =>
      'Dolu bir düğmedeki etiket ve simge.';

  @override
  String get skinTokenActionTonal => 'Yükseltilmiş düğmeler';

  @override
  String get skinTokenActionTonalHint =>
      'Yükseltilmiş ve tonlu düğmelerin dolgusu.';

  @override
  String get skinTokenActionOnTonal => 'Yükseltilmiş düğme etiketi';

  @override
  String get skinTokenActionOnTonalHint =>
      'Yükseltilmiş düğmedeki etiket ve simge.';

  @override
  String get skinTokenActionText => 'Metin ve çerçeveli düğmeler';

  @override
  String get skinTokenActionTextHint =>
      'Metin düğmelerinin, çerçeveli düğmelerin ve bağlantıların etiket rengi.';

  @override
  String get skinTokenControlActive => 'Denetim açık durumu';

  @override
  String get skinTokenControlActiveHint =>
      'Açık anahtarın izi, seçili onay kutusu ve radyo düğmesi, kaydırıcı ve ilerleme dolgusu.';

  @override
  String get skinTokenControlOnActive => 'Anahtar topuzu ve onay işareti';

  @override
  String get skinTokenControlOnActiveHint =>
      'Açık bir anahtarın topuzu ve onay kutusundaki işaret.';

  @override
  String get skinTokenControlTrack => 'Denetim izi';

  @override
  String get skinTokenControlTrackHint =>
      'Kapalı anahtarın izi ile kaydırıcıların ve ilerleme çubuklarının boş kısmı.';

  @override
  String get skinTokenControlInactive => 'Denetim kapalı durumu';

  @override
  String get skinTokenControlInactiveHint =>
      'Kapalı bir anahtarın topuzu ve işaretlenmemiş kutuların kenarlıkları.';

  @override
  String get skinTokenChoiceBackground => 'Çip';

  @override
  String get skinTokenChoiceBackgroundHint =>
      'Seçilmemiş çiplerin ve bölümlerin dolgusu.';

  @override
  String get skinTokenChoiceSelected => 'Seçili çip';

  @override
  String get skinTokenChoiceSelectedHint =>
      'Seçili çipin veya bölümün dolgusu.';

  @override
  String get skinTokenChoiceOnSelected => 'Seçili çip etiketi';

  @override
  String get skinTokenChoiceOnSelectedHint =>
      'Seçili çipteki veya bölümdeki etiket ve simge.';

  @override
  String get skinTokenChoiceBorder => 'Çip kenarlığı';

  @override
  String get skinTokenChoiceBorderHint =>
      'Çiplerin ve bölümlü düğmelerin çerçevesi.';

  @override
  String get skinTokenSelectionFill => 'Seçili satır';

  @override
  String get skinTokenSelectionFillHint =>
      'Seçili dosyalar ve satırlar ile vurgulanan simge karoları.';

  @override
  String get skinTokenSelectionOn => 'Seçili satır metni ve simgeleri';

  @override
  String get skinTokenSelectionOnHint =>
      'Seçili bir satırın üzerine çizilen metin ve simgeler.';

  @override
  String get skinTokenOverlayMenu => 'Menüler';

  @override
  String get skinTokenOverlayMenuHint =>
      'Açılır, aşağı açılan ve bağlam menüleri.';

  @override
  String get skinTokenOverlayOnMenu => 'Menü metni';

  @override
  String get skinTokenOverlayOnMenuHint => 'Menülerdeki metin ve simgeler.';

  @override
  String get skinTokenOverlayDialog => 'İletişim kutuları';

  @override
  String get skinTokenOverlayDialogHint => 'İletişim kutularının dolgusu.';

  @override
  String get skinTokenOverlayOnDialog => 'İletişim kutusu başlığı';

  @override
  String get skinTokenOverlayOnDialogHint =>
      'İletişim kutularının başlık metni.';

  @override
  String get skinTokenOverlaySheet => 'Alt sayfalar';

  @override
  String get skinTokenOverlaySheetHint => 'Alt sayfaların dolgusu.';

  @override
  String get skinTokenOverlayOnSheet => 'Alt sayfa metni';

  @override
  String get skinTokenOverlayOnSheetHint =>
      'Alt sayfalardaki metin ve simgeler.';

  @override
  String get skinTokenOverlayScrim =>
      'İletişim kutularının arkasındaki karartma';

  @override
  String get skinTokenOverlayScrimHint =>
      'İletişim kutularının ve alt sayfaların arkasındaki koyulaştırma.';

  @override
  String get skinTokenFloatingFab => 'Yuvarlak ekle düğmesi';

  @override
  String get skinTokenFloatingFabHint => 'Yuvarlak ekle düğmesinin dolgusu.';

  @override
  String get skinTokenFloatingOnFab => 'Yuvarlak ekle düğmesi simgesi';

  @override
  String get skinTokenFloatingOnFabHint => 'Yuvarlak ekle düğmesindeki simge.';

  @override
  String get skinTokenFloatingToast => 'İleti hapı';

  @override
  String get skinTokenFloatingToastHint =>
      'Altta beliren bilgi iletisinin dolgusu.';

  @override
  String get skinTokenFloatingOnToast => 'İleti hapı metni';

  @override
  String get skinTokenFloatingOnToastHint =>
      'Bilgi iletisindeki metin ve simge.';

  @override
  String get skinTokenFloatingTooltip => 'İpuçları';

  @override
  String get skinTokenFloatingTooltipHint => 'İpuçlarının dolgusu.';

  @override
  String get skinTokenFloatingOnTooltip => 'İpucu metni';

  @override
  String get skinTokenFloatingOnTooltipHint => 'İpuçlarındaki metin.';

  @override
  String get skinTokenGroupAccent => 'Vurgu renkleri';

  @override
  String get skinTokenGroupStatus => 'Durum ve hatalar';

  @override
  String get skinTokenSurfacePanel => 'Paneller';

  @override
  String get skinTokenSurfacePanelHint =>
      'Standart kart bileşeninden yapılan kartlar, yer imi çubuğu, ızgara hücreleri ve bilgi sayfaları.';

  @override
  String get skinTokenChromeBar => 'Çubuklar ve sekme şeritleri';

  @override
  String get skinTokenChromeBarHint =>
      'Eylem çubukları, sekme şeritleri, seçim çubuğu ve alt çubuklar.';

  @override
  String get skinTokenAccentPrimary => 'Vurgu';

  @override
  String get skinTokenAccentPrimaryHint =>
      'Vurgular, metin içi bağlantılar, küçük vurgu simgeleri ve rozetler.';

  @override
  String get skinTokenAccentSecondary => 'İkincil vurgu';

  @override
  String get skinTokenAccentSecondaryHint => 'İkincil vurgular ve etiketler.';

  @override
  String get skinTokenAccentTertiary => 'Üçüncül vurgu';

  @override
  String get skinTokenAccentTertiaryHint => 'Üçüncül vurgular ve etiketler.';

  @override
  String get skinTokenAccentTertiaryContainer => 'Üçüncül vurgu dolgusu';

  @override
  String get skinTokenAccentTertiaryContainerHint =>
      'Üçüncül vurguların arkasındaki dolgu.';

  @override
  String get skinTokenAccentOnTertiaryContainer =>
      'Üçüncül vurgu dolgusu metni';

  @override
  String get skinTokenAccentOnTertiaryContainerHint =>
      'Üçüncül dolgudaki metin ve simgeler.';

  @override
  String get skinTokenStatusDanger => 'Hatalar ve silme';

  @override
  String get skinTokenStatusDangerHint =>
      'Hata metni, silme eylemleri ve hata kenarlıkları.';

  @override
  String get skinTokenStatusOnDanger => 'Hata rengi üzerindeki metin';

  @override
  String get skinTokenStatusOnDangerHint =>
      'Hata rengi üzerine çizilen metin ve simgeler.';

  @override
  String get skinTokenStatusDangerContainer => 'Hata iletisi dolgusu';

  @override
  String get skinTokenStatusDangerContainerHint =>
      'Hata iletilerinin ve bannerlarının dolgusu.';

  @override
  String get skinTokenStatusOnDangerContainer => 'Hata iletisi metni';

  @override
  String get skinTokenStatusOnDangerContainerHint =>
      'Hata iletilerindeki metin ve simgeler.';

  @override
  String get skinTokenStatusInfo => 'Bilgi iletisi dolgusu';

  @override
  String get skinTokenStatusInfoHint => 'Bilgi bannerlarının dolgusu.';

  @override
  String get skinTokenStatusOnInfo => 'Bilgi iletisi metni';

  @override
  String get skinTokenStatusOnInfoHint =>
      'Bilgi bannerlarındaki metin ve simgeler.';

  @override
  String get bookReaderOpenFailed => 'Bu kitap açılamadı';

  @override
  String get comicNoPages => 'Bu çizgi romanda resim bulunamadı';

  @override
  String get comicPageLoadFailed => 'Bu sayfa yüklenemedi';

  @override
  String get comicReadingDirectionRtl => 'Sağdan sola okuma';

  @override
  String get comicReadingDirectionLtr => 'Soldan sağa okuma';

  @override
  String get epubTextSize => 'Metin boyutu';

  @override
  String get epubThemeOriginal => 'Orijinal';

  @override
  String epubChapterFallbackTitle(int number) {
    return 'Bölüm $number';
  }

  @override
  String get bookReaderSettingsTitle => 'Okuyucu ayarları';

  @override
  String get bookReaderPageSection => 'Sayfa';

  @override
  String get bookReaderTextSection => 'Metin';

  @override
  String get bookReaderReadingModeTitle => 'Okuma modu';

  @override
  String get bookReaderPageFlippingLabel => 'Sayfa çevirme';

  @override
  String get bookReaderColorModeLabel => 'Renk modu';

  @override
  String get bookReaderTextDirectionLabel => 'Metin yönü';

  @override
  String get bookReaderTwoPageLandscapeLabel => 'Yatayda iki sayfa';

  @override
  String get bookReaderPageMarginsLabel => 'Sayfa kenar boşlukları';

  @override
  String get bookReaderFontFaceLabel => 'Yazı tipi';

  @override
  String get bookReaderFontPublisherDefault => 'Yayıncı varsayılanı';

  @override
  String get bookReaderFontSerif => 'Tırnaklı';

  @override
  String get bookReaderFontSansSerif => 'Tırnaksız';

  @override
  String get bookReaderFontMonospace => 'Sabit genişlikli';

  @override
  String get bookReaderFontWeightLabel => 'Yazı kalınlığı';

  @override
  String get bookReaderLineSpacingLabel => 'Satır aralığı';

  @override
  String get bookReaderTextAlignmentLabel => 'Metin hizalama';

  @override
  String get bookReaderTextAlignLeft => 'Sola';

  @override
  String get bookReaderTextAlignJustified => 'İki yana yaslı';

  @override
  String get bookReaderTextAlignCenter => 'Ortala';

  @override
  String get bookReaderTextAlignRight => 'Sağa';

  @override
  String get comicReaderModeSinglePage => 'Tek sayfa';

  @override
  String get comicReaderModeTwoPageSpread => 'İki sayfa yayılımı';

  @override
  String get comicReaderCarouselScrubberSubtitle =>
      'İlerleme çubuğunun üstünde sayfa küçük resimlerini göster';

  @override
  String get vaultSyncBrowseAllButton => 'Tüm öğelere göz at';

  @override
  String get vaultSyncExplorerTitle => 'Her iki depolamaya göz at';

  @override
  String get vaultSyncExplorerEmptyTitle => 'Gösterilecek bir şey yok';

  @override
  String get vaultSyncExplorerEmptyMessage =>
      'Bu klasörde bu filtreyle eşleşen öğe yok.';

  @override
  String get vaultSyncExplorerLoadFailedTitle => 'Bu klasör okunamadı';

  @override
  String get vaultSyncExplorerLoadFailedMessage =>
      'İki depolamadan biri listelenemedi. Yeniden deneyin ve ikisinin de hâlâ kilidinin açık ve bağlı olduğundan emin olun.';

  @override
  String get vaultSyncFilterAll => 'Tümü';

  @override
  String get vaultSyncFilterDifferences => 'Farklar';

  @override
  String get vaultSyncFilterNewer => 'Daha yeni kopya';

  @override
  String get vaultSyncFilterConflicts => 'İnceleme gerekli';

  @override
  String get vaultSyncFilterDeletions => 'Silmeler';

  @override
  String get vaultSyncFilterNoMatchesMessage => 'Bu filtreyle eşleşen öğe yok.';

  @override
  String get vaultSyncSortTooltip => 'Sırala';

  @override
  String get vaultSyncSortPath => 'Yol';

  @override
  String get vaultSyncSortSize => 'Önce en büyük';

  @override
  String get vaultSyncSortModified => 'Önce en yeni';

  @override
  String get vaultSyncSortStatus => 'Durum';

  @override
  String get vaultSyncStatusInSync => 'Eşitlenmiş';

  @override
  String get vaultSyncStatusFolder => 'Klasör';

  @override
  String vaultSyncDeletionsQueuedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count silme',
      one: '1 silme',
    );
    return '$_temp0';
  }

  @override
  String vaultSyncConfirmDeletionsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe kalıcı olarak silinecek. Bu işlem geri alınamaz.',
      one: '1 öğe kalıcı olarak silinecek. Bu işlem geri alınamaz.',
    );
    return '$_temp0';
  }

  @override
  String get vaultSyncResultsStaleMessage =>
      'Silme işleminden sonra sonuçlar güncel olmayabilir. Sayıları yenilemek için yeniden karşılaştırın.';

  @override
  String vaultSyncSelectedCount(num count) {
    return '$count seçili';
  }

  @override
  String get vaultSyncOpenAction => 'Aç';

  @override
  String vaultSyncOpenCopyAction(String side) {
    return 'Kopyayı şurada aç: $side';
  }

  @override
  String get vaultSyncOpenFolderAction => 'Klasörü aç';

  @override
  String get vaultSyncOpenFolderSubtitle =>
      'İçindekilere her iki depolamada da göz atın';

  @override
  String get vaultSyncShowInFolderAction => 'Klasörde göster';

  @override
  String get vaultSyncShowInFolderSubtitle =>
      'Her iki depolamada komşularının yanında görün';

  @override
  String get vaultSyncDeleteFromBothAction => 'Her iki depolamadan sil';

  @override
  String vaultSyncDeleteBothSidesLabel(String left, String right) {
    return '$left ve $right';
  }

  @override
  String vaultSyncDeleteConfirmMessage(String where) {
    return 'Bu öğeler, herhangi bir klasörün içindekiler dahil, şuradan kalıcı olarak silinecek: $where. Bu işlem geri alınamaz.';
  }

  @override
  String vaultSyncDeleteDoneMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count öğe silindi',
      one: '1 öğe silindi',
    );
    return '$_temp0';
  }

  @override
  String vaultSyncDeletePartialMessage(int deleted, int failed) {
    return '$deleted silindi, ama $failed silinemedi';
  }

  @override
  String get vaultSyncCopyDoneMessage => 'Kopyalandı';

  @override
  String get vaultSyncCopyFailedMessage =>
      'Bazı öğeler kopyalanamadı. Ayrıntılar için aktarım listesine bakın.';

  @override
  String vaultSyncOpenFailedMessage(String name) {
    return 'Açılamadı: $name';
  }

  @override
  String get vaultSyncDetailsNotOnThisSide => 'Bu depolamada yok';

  @override
  String get vaultSyncDetailsFolder => 'Klasör';

  @override
  String vaultSyncStatusOnlyIn(String storage) {
    return 'Yalnızca şurada: $storage';
  }

  @override
  String vaultSyncStatusNewerIn(String storage) {
    return 'Şurada daha yeni: $storage';
  }

  @override
  String vaultSyncBadgeOnlyIn(int count, String storage) {
    return '$count yalnızca şurada: $storage';
  }

  @override
  String vaultSyncBadgeNewerIn(int count, String storage) {
    return '$count şurada daha yeni: $storage';
  }

  @override
  String vaultSyncFolderOnlyInDetail(String storage) {
    return 'Klasör — yalnızca şurada: $storage';
  }

  @override
  String get vaultSyncDirectionOneWay => 'Tek yönlü kopyalama';

  @override
  String get vaultSyncDirectionOneWaySubtitle =>
      'Yeni ve güncellenen dosyaları gösterilen yönde kopyalar; kaynak değişmez.';

  @override
  String get vaultSyncDirectionMirror => 'Yansıtma eşitlemesi';

  @override
  String get vaultSyncDirectionMirrorSubtitle =>
      'Hedefi birebir bir kopyayla değiştirir; yalnızca hedefte olan öğeler silinir.';

  @override
  String vaultSyncActionCopyTo(String storage) {
    return 'Kopyala → $storage';
  }

  @override
  String vaultSyncCopyNowToAction(String storage) {
    return 'Şimdi kopyala: $storage';
  }

  @override
  String vaultSyncDeleteFromAction(String storage) {
    return 'Sil: $storage';
  }

  @override
  String vaultSyncPlanDeleteFrom(String storage) {
    return 'Eşitlerken sil: $storage';
  }

  @override
  String vaultSyncFilterOnlyIn(String storage) {
    return 'Yalnızca şurada: $storage';
  }

  @override
  String get vaultSyncChooseFirstStorage => 'İlk depolamayı seçin';

  @override
  String get vaultSyncChooseSecondStorage => 'İkinci depolamayı seçin';

  @override
  String get vaultSyncChangeButton => 'Değiştir';

  @override
  String get vaultSyncChooseButton => 'Seç';

  @override
  String get vaultSyncChooseStorageTitle => 'Bir depolama seçin';

  @override
  String get vaultSyncChooseStorageHint =>
      'Önce bir depolama, sonra karşılaştırılacak klasörü seçin.';

  @override
  String get vaultSyncCurrentStorageBadge => 'Geçerli';

  @override
  String vaultSyncPickFolderTitle(String storage) {
    return 'Klasör: $storage';
  }

  @override
  String get vaultSyncDirectionSectionTitle => 'Yön';

  @override
  String get vaultSyncDirectionMirrorWarning => 'Dosyaları siler';

  @override
  String get vaultSyncDirectionSourceLabel => 'Kaynak';

  @override
  String get vaultSyncDirectionTargetLabel => 'Hedef';

  @override
  String get vaultSyncDirectionSwapButton => 'Değiştir';

  @override
  String get vaultSyncDirectionRecommendedLabel => 'Önerilen';

  @override
  String get categoriesSectionTitle => 'Kategoriler';

  @override
  String get categoryShortcutsTitle => 'Kategori kısayolları';

  @override
  String get categoryShortcutsEnable => 'Kategori kısayollarını göster';

  @override
  String get categoryShortcutsEnableSubtitle =>
      'Tüm depolamanızdaki resimler, videolar, sesler ve belgeler, yan menüde';

  @override
  String get categoryShortcutsRestore => 'Varsayılan kısayolları geri yükle';

  @override
  String get categorySourceAll => 'Tüm depolama';

  @override
  String get categorySourceTooltip => 'Kaynak seç';

  @override
  String get categoryFolderStructure => 'Özgün klasör yapısını göster';

  @override
  String categoryScanning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Taranıyor… $count klasör denetlendi',
      one: 'Taranıyor… 1 klasör denetlendi',
    );
    return '$_temp0';
  }

  @override
  String get categoryEmpty => 'Bu kategoride bir şey bulunamadı';

  @override
  String get categoryNoVaultsUnlocked => 'Kilidi açık kasa yok';

  @override
  String get categoryScanLimitReached =>
      'Sonuçlar eksik olabilir — tarama sınırına ulaşınca durdu.';

  @override
  String get categoryShareOneSource =>
      'Paylaşmak için aynı anda yalnızca tek bir depolamadan dosya seçin.';

  @override
  String categoryClipboardReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dosya yapıştırmaya hazır',
      one: '1 dosya yapıştırmaya hazır',
    );
    return '$_temp0 — yapıştırmak için bir klasör açın';
  }

  @override
  String get categoryIndexInVaultsTitle => 'Kategori dizinini kasalarda tut';

  @override
  String get categoryIndexInVaultsSubtitle =>
      'Bir kategoriyi açtığınızda her kasanın yapılandırma klasöründe şifreli olarak kaydedilir, böylece dosyalar bir dahaki sefere anında görünür. Telefonunuza hiçbir şey kaydedilmez.';

  @override
  String get categoryIndexClear => 'Kategori dizinlerini temizle';

  @override
  String get categoryIndexClearSubtitle =>
      'Dizini kilidi açık her kasadan kaldırır';

  @override
  String get categoryIndexCleared => 'Kategori dizinleri temizlendi';

  @override
  String get lockFlushRefusedTitle => 'Cihaza yazılamadı';

  @override
  String lockFlushRefusedMessage(String name) {
    return '$name kilitlenmedi, çünkü cihaz son değişiklikleri kabul etmedi. Bunlar hâlâ uygulamada bekliyor. Bağlantıyı denetleyip yeniden deneyin ya da yine de kilitleyip bunları atın.';
  }

  @override
  String get lockAnywayButton => 'Yine de kilitle';

  @override
  String vaultListingHiddenEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kayıt gösterilmiyor',
      one: '1 kayıt gösterilmiyor',
      zero: '0 kayıt gösterilmiyor',
    );
    return '$_temp0';
  }

  @override
  String get vaultListingDetails => 'Ayrıntılar';

  @override
  String get vaultListingSymbolicLinksTitle => 'Kısayollar';

  @override
  String get vaultListingSymbolicLinksNote =>
      'Kısayollar dokunulduğunda hedeflerini açar. Göreli hedefler bu kasanın içinde kalır; mutlak veya bozuk hedefler açılamaz.';

  @override
  String get vaultListingHiddenEntriesTitle => 'Gösterilmeyen kayıtlar';

  @override
  String get vaultListingHiddenEntriesBody =>
      'Bu kayıtlar kasada var ama listelenemedi. Bu çoğunlukla bir eşitleme uygulaması çakışma kopyaları oluşturduğunda (örneğin \"ad (1)\") ya da bir yükleme bitmediğinde olur. Bilgisayardaki Cryptomator çakışma kopyalarını çözebilir. Burada hiçbir şey değiştirilmedi veya silinmedi.';

  @override
  String get vaultListingTargetUnreadable => '(hedef okunamıyor)';

  @override
  String get vaultListingLinkTargetCopied => 'Bağlantı hedefi kopyalandı';

  @override
  String get galleryFilterTooltip => 'Filtre';

  @override
  String get galleryFilterMenuOpen => 'Filtre…';

  @override
  String get galleryFilterClearAll => 'Filtreleri temizle';

  @override
  String get galleryFilterClear => 'Temizle';

  @override
  String get galleryFilterMatchAny => 'En az biri';

  @override
  String get galleryFilterMatchAll => 'Tümü';

  @override
  String get galleryFoldersMenu => 'Galeri klasörleri';

  @override
  String get galleryFoldersHint =>
      'Galerinin tarayacağı klasörleri seçin. Alt klasörler de taranır. Hiç klasör seçmezseniz tüm depolama alanı taranır.';

  @override
  String get galleryFoldersUseAll => 'Her şeyi tara';

  @override
  String get galleryFoldersApply => 'Uygula';

  @override
  String galleryFilterShownOfTotal(int shown, int total) {
    return '$shown / $total gösteriliyor';
  }

  @override
  String galleryFilterTotal(int count) {
    return 'Toplam: $count';
  }

  @override
  String galleryFilterIndexing(int done, int total) {
    return 'Fotoğraf ayrıntıları okunuyor: $done / $total. Etiketler, yerler ve kameralar ilerledikçe görünür.';
  }

  @override
  String get galleryFilterSearchHint => 'Etiket, yer, kamera, klasör ara…';

  @override
  String get galleryFilterTapHint =>
      'Yalnızca göstermek için dokunun, gizlemek için basılı tutun.';

  @override
  String get galleryFilterGroupBy => 'Gruplandır';

  @override
  String galleryFilterShowAll(int count) {
    return 'Tümü ($count)';
  }

  @override
  String get galleryFilterShowFewer => 'Daha az';

  @override
  String get galleryGroupNone => 'Yok';

  @override
  String get galleryGroupDay => 'Gün';

  @override
  String get galleryGroupMonth => 'Ay';

  @override
  String get galleryGroupYear => 'Yıl';

  @override
  String get galleryGroupFolder => 'Klasör';

  @override
  String get galleryGroupType => 'Tür';

  @override
  String get galleryGroupPlace => 'Yer';

  @override
  String get galleryGroupCamera => 'Kamera';

  @override
  String get galleryFilterSectionType => 'Tür';

  @override
  String get galleryFilterSectionDate => 'Tarih';

  @override
  String get galleryFilterSectionTags => 'Etiketler';

  @override
  String get galleryFilterSectionPlaces => 'Yerler';

  @override
  String get galleryFilterSectionCameras => 'Kameralar';

  @override
  String get galleryFilterSectionOrientation => 'Yönelim';

  @override
  String get galleryFilterSectionRating => 'Puan';

  @override
  String get galleryFilterSectionSize => 'Dosya boyutu';

  @override
  String get galleryFilterSectionFolders => 'Klasörler';

  @override
  String get galleryFilterSectionMissing => 'Eksik';

  @override
  String get galleryTypePhotos => 'Fotoğraflar';

  @override
  String get galleryTypeVideos => 'Videolar';

  @override
  String get galleryTypeAnimated => 'Animasyonlu';

  @override
  String get galleryOrientationLandscape => 'Yatay';

  @override
  String get galleryOrientationPortrait => 'Dikey';

  @override
  String get galleryOrientationSquare => 'Kare';

  @override
  String get gallerySizeSmall => '1 MB altı';

  @override
  String get gallerySizeMedium => '1 – 10 MB';

  @override
  String get gallerySizeLarge => '10 MB üstü';

  @override
  String get galleryMissingLocation => 'Konum yok';

  @override
  String get galleryMissingTags => 'Etiket yok';

  @override
  String get galleryMissingCamera => 'Kamera bilgisi yok';

  @override
  String get galleryMissingDateTaken => 'Çekim tarihi yok';

  @override
  String galleryPlaceHintCity(int km) {
    return '$km km içindeki en yakın şehir';
  }

  @override
  String galleryPlaceHintCoordinates(int km) {
    return '$km km içinde şehir yok: koordinatlara göre gruplandı';
  }

  @override
  String get cryptomatorBackupKeyFilesTitle =>
      'Kilidi açarken anahtar dosyalarını yedekle';

  @override
  String get cryptomatorBackupKeyFilesSubtitle =>
      'Masaüstündeki Cryptomator gibi, masterkey.cryptomator ve vault.cryptomator dosyalarının bir kopyasını orijinallerin yanında tutar. Bir sonraki kilit açmadan itibaren geçerlidir. Salt okunur oturumlar hiçbir zaman yazmaz.';

  @override
  String get cryptomatorUpgradeTitle => 'Kasa biçimini yükselt';

  @override
  String get cryptomatorUpgradeSubtitle =>
      'Bu kasa eski 7 biçimini kullanıyor.';

  @override
  String get cryptomatorUpgradeLockFirst => 'Yükseltmek için kasayı kilitleyin';

  @override
  String get cryptomatorUpgradeWarning =>
      'Yükseltme bu kasayı 8 biçimine geçirir. Geri alınamaz ve 1.6\'dan eski Cryptomator sürümleri bundan sonra kasayı açamaz.\n\nMevcut anahtar dosyasının bir kopyası masterkey.cryptomator.<id>.bkup olarak saklanır. Bu kasayı başka bir uygulama eşitliyorsa önce eşitlemeyi bitirmesine izin verin.';

  @override
  String get cryptomatorUpgradeConfirm =>
      'Bunun geri alınamayacağını anlıyorum';

  @override
  String get cryptomatorUpgradeAction => 'Yükselt';

  @override
  String get cryptomatorUpgradedMessage => 'Kasa 8 biçimine yükseltildi';

  @override
  String get cryptomatorUpgradeUnlockedError => 'Önce kasayı kilitleyin';

  @override
  String get cryptomatorConfigMissingWarning =>
      'vault.cryptomator eksik. Bu kasayı başka bir uygulama eşitliyorsa bitmesini bekleyin, sonra yeniden deneyin. Yükseltmeyin.';

  @override
  String get cryptomatorUpgradeFailedMessage => 'Kasa yükseltilemedi';

  @override
  String get newSymbolicLinkTitle => 'Yeni sembolik bağlantı';

  @override
  String get symbolicLinkNameHint => 'Bağlantı adı';

  @override
  String get symbolicLinkTargetHint => 'Hedef';

  @override
  String get symbolicLinkTargetHelper =>
      'Yazıldığı gibi saklanır. Göreli hedefler açılırken bu kasanın içinde çözülür; mutlak hedefler izlenmez.';

  @override
  String get symbolicLinkTargetTooLong =>
      'Hedef çok uzun (en fazla 32.767 bayt)';

  @override
  String get symbolicLinkTargetInvalid => 'Hedef null karakteri içeremez';

  @override
  String get symbolicLinkNameTaken =>
      'Bu adda bir dosya, klasör veya bağlantı zaten var';

  @override
  String get deleteSymbolicLinkTitle => 'Sembolik bağlantı silinsin mi?';

  @override
  String deleteSymbolicLinkMessage(String name) {
    return '\"$name\" bağlantısı silinsin mi? Yalnızca bağlantı kaldırılır; işaret ettiği şeye dokunulmaz.';
  }

  @override
  String get symbolicLinkRenameTitle => 'Sembolik bağlantıyı yeniden adlandır';

  @override
  String get symbolicLinkBrowseTarget => 'Kasaya göz at';

  @override
  String get symbolicLinkSelectTargetTitle => 'Kısayol hedefini seçin';

  @override
  String get symbolicLinkSelectThisFolder => 'Bu klasörü seç';

  @override
  String get symbolicLinkPickerLoadError => 'Bu klasör yüklenemedi';

  @override
  String get shortcutBadge => 'Kısayol';

  @override
  String get emptyFolder => 'Bu klasör boş';

  @override
  String get symbolicLinkTargetHelperRelative =>
      'Bu kapsayıcının içinde göreli bir yol kullanın. Hedef eksik olabilir; bağlantıyı yeniden adlandırmak veya silmek hedefi değiştirmez.';

  @override
  String get symbolicLinkTargetOutsideVault =>
      'Hedef, bu kapsayıcının içinde kalan göreli bir yol olmalıdır.';

  @override
  String get symbolicLinkPickerUnresolvable =>
      'Buradan göreli bir hedef oluşturulamıyor. Bunun yerine hedefi yazın.';

  @override
  String get editMetadataAction => 'Üst veriyi düzenle';

  @override
  String get editTagsAction => 'Etiketleri düzenle';

  @override
  String get editDateTimeAction => 'Tarih ve saati düzenle';

  @override
  String get removeMetadataAction => 'Üst veriyi kaldır';

  @override
  String get metadataFormatsNote =>
      'Etiketler, tarihler ve kaldırma işlemi JPEG, PNG ve WebP resimlerine yazılır. Diğer dosyalar yalnızca yeni bir değiştirilme tarihi alır.';

  @override
  String get metadataReadOnlyMessage => 'Bu kasa salt okunur';

  @override
  String get tagsAddHint => 'Virgülle ayırarak etiket ekleyin';

  @override
  String get tagsNoneYet => 'Henüz etiket yok';

  @override
  String get dateModeSet => 'Ayarla';

  @override
  String get dateModeShift => 'Kaydır';

  @override
  String get dateModeFromModified => 'Değiştirilme tarihinden';

  @override
  String get dateModeFromName => 'Dosya adından';

  @override
  String get dateShiftLater => 'Daha geç';

  @override
  String get dateShiftEarlier => 'Daha erken';

  @override
  String get dateDaysLabel => 'Gün';

  @override
  String get dateHoursLabel => 'Saat';

  @override
  String get dateMinutesLabel => 'Dakika';

  @override
  String get dateAlsoSetModified => 'Dosyanın değiştirilme tarihini de ayarla';

  @override
  String dateFromNameMatches(int matched, int total) {
    return '$total dosya adının $matched tanesi bir tarih içeriyor';
  }

  @override
  String get stripExifLabel => 'Exif (kamera, tarih, konum)';

  @override
  String get stripXmpLabel => 'XMP (etiketler, puan, düzenleme verisi)';

  @override
  String get stripIptcLabel => 'IPTC / Photoshop (açıklamalar, künyeler)';

  @override
  String get stripCommentsLabel => 'Yorumlar';

  @override
  String get stripIccLabel => 'Renk profili (renkleri değiştirebilir)';

  @override
  String get stripKeepOrientationLabel => 'Yönelimi koru';

  @override
  String get stripKeepOrientationDesc =>
      'Bu olmadan yan çekilen fotoğraflar döndürülmüş görünebilir';

  @override
  String get stripWarning =>
      'Bu işlem dosyaları yeniden yazar ve geri alınamaz.';

  @override
  String metadataProgress(int done, int total) {
    return 'Güncelleniyor: $done / $total';
  }

  @override
  String metadataResultUpdated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dosya güncellendi',
      one: '1 dosya güncellendi',
    );
    return '$_temp0';
  }

  @override
  String get metadataResultUnchanged => 'Değiştirilmesi gereken bir şey yoktu';

  @override
  String metadataResultSkipped(int count) {
    return '$count atlandı (desteklenmiyor)';
  }

  @override
  String metadataResultFailed(int count) {
    return '$count başarısız';
  }

  @override
  String get showNoMediaFoldersLabel => '.nomedia klasörlerini göster';

  @override
  String get showNoMediaFoldersDesc =>
      'Galeri uygulamalarının normalde atladığı, .nomedia dosyasıyla işaretli klasörleri de dahil et';

  @override
  String get motionPhotoCopyNote =>
      'Düzenlenen kopya hareketsiz bir görüntü olur. Orijinal dosya, EXIF meta verileri ve varsa dosyaya gömülü video değişmeden kalır.';

  @override
  String get galleryMetadataIndexStorageLabel =>
      'Galeri meta veri dizininin depolama konumu';

  @override
  String get galleryMetadataUseGlobalDefaultDesc =>
      'Uygulama genelindeki galeri meta veri dizini depolama ayarını kullanın.';

  @override
  String get galleryMetadataAppStorageOption => 'Uygulama depolaması';

  @override
  String get galleryMetadataInVaultOption => 'Kasa içinde';

  @override
  String get galleryMetadataSectionHeader => 'Galeri meta veri dizini';

  @override
  String get galleryMetadataUseGlobalDefaultTitle =>
      'Uygulama genelindeki galeri dizini ayarını kullan';

  @override
  String get musicIndexSectionHeader => 'Müzik dizini';

  @override
  String get musicIndexStorageLabel => 'Müzik dizininin depolama konumu';

  @override
  String get musicIndexUseGlobalDefaultTitle =>
      'Uygulama genelindeki müzik dizini ayarını kullan';

  @override
  String get musicIndexUseGlobalDefaultDesc =>
      'Uygulama genelindeki müzik dizini depolama ayarını kullanın.';

  @override
  String get musicIndexAppStorageOption => 'Uygulama depolaması';

  @override
  String get musicIndexInVaultOption => 'Kasa içinde';

  @override
  String get musicIndexHiddenFolderOption => 'Gizli klasör';

  @override
  String get libraryStorageHiddenFolder =>
      'Dizin şifrelenmemiş gizli bir klasöre kaydedildi';

  @override
  String get libraryStorageDisabled =>
      'Kaydedilmiş müzik dizini devre dışı; parçalar her seferinde yeniden taranır.';

  @override
  String get galleryMetadataClearAction =>
      'Kaydedilmiş galeri dizinini temizle';

  @override
  String get galleryMetadataClearConfirmTitle =>
      'Galeri meta veri dizini temizlensin mi?';

  @override
  String get galleryMetadataClearConfirmMessage =>
      'Kaydedilmiş fotoğraf ayrıntıları silinir. Galeride gezinirken dizin yeniden oluşturulur.';

  @override
  String get galleryMetadataIndexClearedMessage =>
      'Galeri meta veri dizini temizlendi.';

  @override
  String get musicIndexClearAction => 'Kaydedilmiş müzik dizinini temizle';

  @override
  String get musicIndexClearConfirmTitle =>
      'Kaydedilmiş müzik dizini temizlensin mi?';

  @override
  String get musicIndexClearConfirmMessage =>
      'Kaydedilmiş parça ayrıntıları silinir. Müzik Modu, bir sonraki açılışında dizini yeniden oluşturur.';

  @override
  String get musicIndexClearedMessage => 'Müzik dizini temizlendi.';

  @override
  String get clearSavedIndexButton => 'Dizini temizle';

  @override
  String get appIndexClearedUnlockMessage =>
      'Uygulama depolamasındaki kopya temizlendi. Kasa içindeki dizin kopyasını temizlemek için kasayı yazma erişimiyle açın.';

  @override
  String get savedIndexClearFailedMessage =>
      'Kaydedilmiş dizin verilerinin tamamı temizlenemedi.';

  @override
  String get libraryStorageReadOnly =>
      'Kasa salt okunur; müzik dizini kaydedilmiyor.';

  @override
  String get clearLocalStorageThumbnailCacheMessage =>
      'Bu işlem Yerel Depolama için önbelleğe alınmış küçük resimleri siler. Medyalara bir sonraki göz atışınızda yeniden oluşturulurlar.';

  @override
  String vcToolsDetectedFormat(String format) {
    return 'Algılanan biçim: $format';
  }

  @override
  String get vcToolsUnencryptedDetected =>
      'Şifrelenmemiş görünüyor; bu araç şifreli bir kapsayıcı gerektirir';

  @override
  String get vcToolsAssumingVeraCrypt =>
      'Otomatik olarak algılanamadı; VeraCrypt olduğu varsayılıyor';

  @override
  String get vcToolsManualFormat => 'Elle ayarla';

  @override
  String get vcToolsExpandInsufficientSpaceForSize =>
      'Bu boyut için cihazda yeterli boş alan yok.';

  @override
  String vcToolsNewSizePreview(String size) {
    return 'Yeni boyut: $size';
  }

  @override
  String vcToolsNewSizePreviewWithAdded(String size, String added) {
    return 'Yeni boyut: $size (+$added)';
  }

  @override
  String get vcToolsFileSize => 'Dosya boyutu';

  @override
  String get vcToolsCurrentSize => 'Mevcut boyut';

  @override
  String vcToolsFreeOnDevice(String size) {
    return 'Cihazda boş alan: $size';
  }

  @override
  String get vcToolsSetExactTotalInstead => 'Toplam boyutu tam olarak ayarla';

  @override
  String get vcToolsBitLockerDiskImageSizeHint =>
      'Disk görüntüsü (VHD/VHDX) için dosya boyutunu değil, yeni toplam sanal disk boyutunu girin.';

  @override
  String get vcToolsNewTotalSize => 'Yeni toplam boyut';

  @override
  String get vcToolsAddSize => 'Ekle';

  @override
  String vcToolsQuickAddGiB(String amount) {
    return '+$amount GiB';
  }

  @override
  String get vcToolsDoubleSize => 'İki katına çıkar';

  @override
  String get vcToolsSizeMustExceedCurrent =>
      'Yeni boyut geçerli boyuttan büyük olmalıdır.';

  @override
  String get vcToolsInsufficientFreeSpace => 'Cihazda yeterli boş alan yok.';

  @override
  String get vcToolsContainerSectionHeader => 'Kapsayıcı';

  @override
  String get vcToolsCredentialsSectionHeader => 'Kimlik bilgileri';

  @override
  String get vcToolsVolumeOptionsSectionHeader => 'Birim seçenekleri';

  @override
  String get vcToolsDetectingFormat => 'Biçim algılanıyor…';

  @override
  String get indexesAndThumbnailsTitle => 'Dizinler ve küçük resimler';

  @override
  String get indexesAndThumbnailsSubtitle =>
      'Küçük resim depolamasını, galeri meta verilerini ve müzik dizini ayarlarını yönetin.';

  @override
  String get resetFileManagerSettingsTitle =>
      'Dosya yöneticisi ayarları sıfırlansın mı?';

  @override
  String get resetFileManagerSettingsMessage =>
      'Bu ekrandaki tüm seçenekler varsayılan değerlerine döner; sekme, düzen, araç çubuğu, ızgara, küçük resim, görüntüleyici ve tema ayarları da buna dahildir. Dosyalarınız, yer imleriniz ve klasöre özel tercihleriniz değişmez.';

  @override
  String get dropImportOverlayLabel => 'Bu klasöre içe aktarmak için bırakın';

  @override
  String get dropImportUnavailableHere =>
      'Dosyalar yalnızca bir kasa klasörüne bırakılabilir.';

  @override
  String dropImportSkippedItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bırakılan $count öğe içe aktarılamıyor',
      one: 'Bırakılan 1 öğe içe aktarılamıyor',
    );
    return '$_temp0';
  }

  @override
  String get dropVaultOverlayLabel =>
      'Eklemek için bir kapsayıcı veya kasa klasörü bırakın';

  @override
  String get dropVaultUnsupported =>
      'Kapsayıcı dosyalarını veya yalnızca tek bir kasa klasörünü bırakın.';

  @override
  String get pathFieldHint => 'Bir yol yazın';

  @override
  String get editPathTooltip => 'Yolu düzenle';

  @override
  String get goToPathTooltip => 'Git';

  @override
  String get pathOutsideStorage => 'Bu yol bu depolamanın dışında';

  @override
  String pathNotFound(String path) {
    return 'Yol bulunamadı: $path';
  }

  @override
  String get browserTabOpenInNewWindow => 'Yeni pencerede aç';

  @override
  String get storageLocationLabel => 'Depolama konumu';

  @override
  String get storageLocationPicked => 'Konum seç';

  @override
  String get storageLocationAppStorage => 'Uygulama depolaması';

  @override
  String get appStorageCreateNote =>
      'Uygulamanın özel depolamasında tutulur; yalnızca bu uygulama erişebilir. Uygulamayı kaldırırsanız veya verilerini temizlerseniz silinir, bu yüzden önemli olan her şeyin yedeğini alın.';

  @override
  String get vaultNameLabel => 'Kasa adı';

  @override
  String get vaultNameRequired => 'Kasa adı gerekli';

  @override
  String get moveToAppStorageTile => 'Uygulama depolamasına taşı';

  @override
  String get moveToAppStorageSubtitle =>
      'Bu kasayı uygulamanın özel depolamasında tutun';

  @override
  String get moveOutOfAppStorageTile => 'Uygulama depolamasından çıkar';

  @override
  String get moveOutOfAppStorageSubtitle =>
      'Bu kasayı seçtiğiniz bir konuma kaydedin';

  @override
  String get relocateSaveChangesFirst =>
      'Kasayı taşımadan önce değişikliklerinizi kaydedin veya iptal edin.';

  @override
  String get relocateToAppStorageTitle => 'Uygulama depolamasına taşınsın mı?';

  @override
  String get relocateToAppStorageBody =>
      'Kasa, uygulamanın özel depolamasına kopyalanır ve başka hiçbir şey yapılmadan önce bayt bayt doğrulanır. Kayıtlı parolanız ve ayarlarınız da onunla birlikte taşınır.';

  @override
  String get relocateFromAppStorageTitle =>
      'Uygulama depolamasından çıkarılsın mı?';

  @override
  String get relocateFromAppStorageBody =>
      'Kasanın nereye kaydedileceğini seçersiniz. Buraya kopyalanır ve başka hiçbir şey yapılmadan önce bayt bayt doğrulanır. Kayıtlı parolanız ve ayarlarınız da onunla birlikte taşınır.';

  @override
  String get appStorageRiskNote =>
      'Uygulama depolamasındaki kasalar, uygulamayı kaldırırsanız, verilerini temizlerseniz veya acil durum silmesini çalıştırırsanız silinir. Önemli olan her şeyin yedeğini alın.';

  @override
  String get relocateDeleteOriginal =>
      'Kopya doğrulandıktan sonra orijinali sil';

  @override
  String get relocateMoveButton => 'Taşı';

  @override
  String get relocatePhaseCopying => 'Kasa kopyalanıp denetleniyor…';

  @override
  String get relocatePhaseSwitching => 'Yeni konuma geçiliyor…';

  @override
  String get relocatePhaseFinishing => 'Tamamlanıyor…';

  @override
  String get relocatedToAppStorage => 'Kasa uygulama depolamasına taşındı.';

  @override
  String get relocatedFromAppStorage =>
      'Kasa uygulama depolamasından çıkarıldı.';

  @override
  String get relocateNoteBiometricsDropped =>
      'Biyometrik kilit açma aktarılamadı. Bu kasayı parolasıyla açın ve biyometriyi yeniden kurun.';

  @override
  String get relocateNoteAutomationReset =>
      'Bu kasa için otomasyon erişimi sıfırlandı. Kasanın otomasyon ayarlarından yeniden açın.';

  @override
  String get relocateNoteOriginalLeftBehind =>
      'Orijinal silinemedi ve eski konumunda duruyor. İsterseniz kendiniz silebilirsiniz.';

  @override
  String get relocateErrorUnlocked => 'Kasayı taşımadan önce kilitleyin.';

  @override
  String get relocateErrorUnsupported => 'Bu tür bir kasa taşınamaz.';

  @override
  String get relocateErrorSplit =>
      'Bölünmüş kapsayıcılar taşınamaz. Önce parçaları birleştirin.';

  @override
  String get relocateErrorNotVaultFolder =>
      'Bu klasörde bir kasanın yapılandırma dosyası yok.';

  @override
  String get relocateErrorVerifyFailed =>
      'Kopya orijinaliyle eşleşmedi, bu yüzden atıldı. Hiçbir şey değiştirilmedi.';

  @override
  String get relocateErrorSwitchFailed =>
      'Kopya oluşturuldu ancak uygulama ona geçemedi, bu yüzden kaldırıldı. Hiçbir şey değiştirilmedi.';

  @override
  String relocateErrorGeneric(String details) {
    return 'Kasa taşınamadı. $details';
  }

  @override
  String get deleteAppStorageVaultTitle => 'Bu kasa silinsin mi?';

  @override
  String deleteAppStorageVaultBody(String name) {
    return '\"$name\" uygulamanın içinde saklanıyor, bu yüzden kaldırmak onu kalıcı olarak siler. Yedek almadıysanız başka kopyası yoktur.';
  }

  @override
  String get deleteAppStorageVaultMoveOut => 'Bunun yerine çıkar';

  @override
  String get deleteAppStorageVaultFailed => 'Kasa silinemedi.';

  @override
  String get dateModeToModified => 'Çekim tarihinden değiştirilme tarihine';

  @override
  String get dateToModifiedNote =>
      'Her dosyanın değiştirilme tarihini, içinde saklanan çekim tarihine ayarlar. Çekim tarihi olmayan dosyalar atlanır. Dosyaların kendisi değiştirilmez.';

  @override
  String get dashboardLayoutLabel => 'Düzen';

  @override
  String get dashboardLayoutCards => 'Kartlar';

  @override
  String get dashboardLayoutGrid => 'Izgara';

  @override
  String get dashboardLayoutList => 'Liste';

  @override
  String get dashboardLayoutDetails => 'Ayrıntılar';

  @override
  String get dashboardColumnFree => 'Boş alan';

  @override
  String get dashboardColumnUsage => 'Kullanım';

  @override
  String get newTabBehaviorLabel => 'Yeni sekme açılırken';

  @override
  String get newTabBehaviorDuplicate => 'Geçerli sekmeyi çoğalt';

  @override
  String get newTabBehaviorDuplicateDesc =>
      'Öndeki sekmenin bir kopyasını aynı konumda açar.';

  @override
  String get newTabBehaviorPrompt => 'Nerede açılacağını sor';

  @override
  String get newTabBehaviorPromptDesc =>
      'Aralarından seçim yapabileceğiniz kullanılabilir konumların listesini gösterir.';

  @override
  String get newTabBehaviorSpecificStorage => 'Belirli bir konumu aç';

  @override
  String get newTabBehaviorSpecificStorageDesc =>
      'Aşağıda seçilen konumu her zaman açar. Açılamazsa size sorulur.';

  @override
  String get newTabStorageLabel => 'Yeni sekmeler için konum';

  @override
  String get newTabStorageUnavailable => 'Konum kullanılamıyor';

  @override
  String get copyImageAction => 'Resmi kopyala';
}
