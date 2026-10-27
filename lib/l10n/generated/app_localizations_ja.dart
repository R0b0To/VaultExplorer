// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get usbAttachPromptTitle => 'USB接続時の確認を表示';

  @override
  String get usbAttachPromptSubtitle =>
      'オンにすると、USBドライブの接続時に Android が VaultExplorer を表示します。確認を表示しない場合はオフにしてください。USBドライブは引き続き「USBドライブをマウント」から開けます。';

  @override
  String get usbAttachPromptUpdateErrorMessage => 'USB接続の設定を変更できませんでした。';

  @override
  String get cancel => 'キャンセル';

  @override
  String get close => '閉じる';

  @override
  String get search => '検索';

  @override
  String get goBack => '戻る';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => 'ページに移動';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return 'ページ番号（1～$pageCount）';
  }

  @override
  String get pdfViewerPageLabel => 'ページ';

  @override
  String get pdfViewerGoButton => '移動';

  @override
  String get pdfViewerSearchHint => '文書内を検索';

  @override
  String get pdfViewerNoMatches => '一致する結果がありません';

  @override
  String get pdfViewerPreviousMatch => '前の一致';

  @override
  String get pdfViewerNextMatch => '次の一致';

  @override
  String get pdfViewerCloseSearch => '検索を閉じる';

  @override
  String get pdfViewerPrintTooltip => '文書を印刷';

  @override
  String get pdfViewerLoadingDocument => '文書を読み込み中…';

  @override
  String get pdfViewerCannotOpenTitle => 'PDFを開けません';

  @override
  String get pdfViewerFailedToLoad => 'PDFの読み込みに失敗しました';

  @override
  String get pdfViewerEditTooltip => '編集';

  @override
  String get pdfViewerDoneEditingTooltip => '編集を完了';

  @override
  String get pdfViewerSaveFailed => 'このPDFへの変更を保存できませんでした';

  @override
  String get pdfViewerEditUnavailable => 'この文書では編集を利用できません';

  @override
  String get paste => '貼り付け';

  @override
  String get clear => 'クリア';

  @override
  String get clipboardVerbMove => '移動';

  @override
  String get clipboardVerbCopy => 'コピー';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb（$count）— タップで詳細、長押しで貼り付け';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb（$count）— クリップボードの詳細';
  }

  @override
  String clipboardSourceLabel(String source) {
    return '元: $source';
  }

  @override
  String get clipboardDefaultSourceName => '保管庫';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のアイテム',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '他$count個',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => '詳細パラメータ';

  @override
  String get pimFieldLabel => 'PIM（空欄でデフォルト）';

  @override
  String get encryptionAlgorithmLabel => '暗号化アルゴリズム';

  @override
  String get hashAlgorithmLabel => 'ハッシュアルゴリズム';

  @override
  String get clipboardVerbMoving => '移動中';

  @override
  String get clipboardVerbCopying => 'コピー中';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のアイテム',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return ' 「$source」から';
  }

  @override
  String get clipboardOpenContainerToPaste => '貼り付け先のコンテナを開いてください';

  @override
  String get keyfilesOptionalLabel => 'キーファイル（任意）';

  @override
  String get addFile => 'ファイルを追加';

  @override
  String get noKeyfilesAttached => 'キーファイルが添付されていません';

  @override
  String get completed => '完了';

  @override
  String get dismiss => '閉じる';

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
      other: '$count件の転送',
    );
    return '$_temp0';
  }

  @override
  String multiOpSublabel(String summary) {
    return '$summary・タップしてすべて表示';
  }

  @override
  String get thumbnailSizeResolutionLabel => 'サムネイルサイズ（解像度）';

  @override
  String get jpegCompressionQualityLabel => 'JPEG圧縮品質';

  @override
  String get done => '完了';

  @override
  String get confirm => '確認';

  @override
  String get couldNotPickKeyfiles => 'キーファイルを選択できませんでした';

  @override
  String get filesystemLabelEncryptedVault => 'この暗号化された保管庫';

  @override
  String get filesystemLabelThisContainer => 'このコンテナ';

  @override
  String get nounFile => 'ファイル';

  @override
  String get nounFolder => 'フォルダ';

  @override
  String get nounFileCapitalized => 'ファイル';

  @override
  String get nounFolderCapitalized => 'フォルダ';

  @override
  String get unitBytes => 'バイト';

  @override
  String get unitCharacters => '文字';

  @override
  String get validationEmptyName => '名前を空にすることはできません。';

  @override
  String validationReservedNavName(String name, String noun) {
    return '「$name」は予約されたナビゲーション名のため、$noun名として使用できません。';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return '$fsLabelでは、位置$positionの「$char」は名前に使用できません。';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return '位置$positionに印刷できない制御文字（コード$code）が含まれています。これは$fsLabelでは使用できません。';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '「$name」は$fsLabelでの予約デバイス名（CON、PRN、AUX、NUL、COM0～9、LPT0～9のいずれか）に該当するため、拡張子の有無にかかわらず使用できません。';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return '$fsLabelでは、$noun名を空白で終わらせることはできません';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return '$fsLabelでは、$noun名を「.」で終わらせることはできません';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return 'この名前は$length$unitです。$fsLabelでは$noun名につき最大$maxLength$unitまでです。';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return '完全なパスは$length文字です。$fsLabelでは最大$maxLength文字までです。';
  }

  @override
  String conflictSameType(String noun, String name) {
    return '「$name」という名前の$nounはすでにここに存在します。';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return '「$name」という名前の$existingNounはすでにここに存在します — $candidateNounと同じ名前は使用できません。';
  }

  @override
  String get readOnlyContainerWarning => 'このコンテナは読み取り専用でマウントされています。';

  @override
  String get hiddenVolumeProtectionTriggeredWarning =>
      'この外側のボリュームへの書き込みは隠しボリュームを損傷させる可能性があったため、ブロックされました。このコンテナは今回のセッションの残り時間、読み取り専用に切り替わりました。';

  @override
  String get protectHiddenVolumeToggleTitle => '隠しボリュームを保護';

  @override
  String get protectHiddenVolumeToggleSubtitle => '外側のボリュームへの書き込みによる損傷を防止します';

  @override
  String get protectHiddenVolumeCredentialsRequired =>
      '隠しボリュームを保護するには、隠しボリュームのパスワードまたはキーファイルが必要です';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアイテムを削除しますか？',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning => '選択したフォルダの中身も含め、これらのアイテムは完全に削除されます。';

  @override
  String get deleteFilesWarning => 'これらのアイテムは暗号化されたボリュームから完全に消去されます。';

  @override
  String get delete => '削除';

  @override
  String get remove => '外す';

  @override
  String get create => '作成';

  @override
  String get rename => '名前を変更';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアイテムの名前を変更',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => '新規フォルダ';

  @override
  String get newTextFileTitle => '新規テキストファイル';

  @override
  String get folderNameHint => 'フォルダ名';

  @override
  String get filenameHint => 'ファイル名.txt';

  @override
  String get newNameHint => '新しい名前';

  @override
  String get baseNameHint => 'ベース名';

  @override
  String couldntCreateItem(String name) {
    return '「$name」を作成できませんでした — コンテナがまだマウントされているか確認してください';
  }

  @override
  String couldntRenameSingle(String name) {
    return '「$name」の名前を変更できませんでした — 同じ名前の項目がすでに存在する可能性があります';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の名前を変更できませんでした: $reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の名前を変更できませんでした',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize => '0より大きい有効な隠しサイズを入力してください';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter =>
      '隠しボリュームのサイズは外側のボリュームのサイズより小さくする必要があります';

  @override
  String get hiddenVolumeErrorTooLargeForContainer =>
      '隠しボリュームのサイズがこのコンテナサイズに対して大きすぎます';

  @override
  String get hiddenVolumeErrorCredentialsRequired =>
      '隠しボリュームを作成するには、隠しパスワードまたはキーファイルが必要です';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      '隠しボリュームの認証情報（パスワード、PIM、キーファイル）は、外側のボリュームの認証情報と同一にできません。';

  @override
  String get vaultItemTypePassword => 'パスワード';

  @override
  String get vaultItemTypePaymentCard => '支払いカード';

  @override
  String get vaultItemTypeIdentity => '身分証明書';

  @override
  String get vaultItemTypeSecureNote => 'セキュアノート';

  @override
  String get vaultItemTypeBankAccount => '銀行口座';

  @override
  String get vaultItemTypeSoftwareLicense => 'ソフトウェアライセンス';

  @override
  String get fieldUsernameEmail => 'ユーザー名 / メールアドレス';

  @override
  String get fieldPassword => 'パスワード';

  @override
  String get fieldWebsiteUrl => 'ウェブサイトURL';

  @override
  String get fieldTotpSecret => 'TOTPシークレット（2FA）';

  @override
  String get fieldNotes => 'メモ';

  @override
  String get fieldCardholderName => 'カード名義人';

  @override
  String get fieldCardNumber => 'カード番号';

  @override
  String get fieldExpiryMMYY => '有効期限（MM/YY）';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldIssuingBank => '発行銀行';

  @override
  String get fieldFullName => '氏名';

  @override
  String get fieldDateOfBirth => '生年月日';

  @override
  String get fieldNationality => '国籍';

  @override
  String get fieldPassportNumber => 'パスポート番号';

  @override
  String get fieldPassportExpiry => 'パスポート有効期限';

  @override
  String get fieldNationalIdSsn => 'マイナンバー / 国民ID';

  @override
  String get fieldDriversLicense => '運転免許証';

  @override
  String get fieldAddress => '住所';

  @override
  String get fieldPhone => '電話番号';

  @override
  String get fieldEmail => 'メールアドレス';

  @override
  String get fieldNote => 'メモ';

  @override
  String get fieldBankName => '銀行名';

  @override
  String get fieldAccountHolder => '口座名義人';

  @override
  String get fieldAccountNumber => '口座番号';

  @override
  String get fieldRoutingSortCode => '銀行コード / 支店コード';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => '口座種別';

  @override
  String get fieldProductName => '製品名';

  @override
  String get fieldLicenseKey => 'ライセンスキー';

  @override
  String get fieldRegisteredTo => '登録者';

  @override
  String get fieldPurchaseDate => '購入日';

  @override
  String get fieldExpiryRenewalDate => '有効期限 / 更新日';

  @override
  String get fieldDownloadUrl => 'ダウンロードURL';

  @override
  String get fieldRegistrationEmail => '登録用メールアドレス';

  @override
  String get titleRequired => 'タイトルは必須です';

  @override
  String newTypeTitle(String typeLabel) {
    return '新規$typeLabel';
  }

  @override
  String editItemTitle(String title) {
    return '$titleを編集';
  }

  @override
  String get save => '保存';

  @override
  String typeNameHint(String typeLabel) {
    return '$typeLabelの名前';
  }

  @override
  String get titleSectionLabel => 'タイトル';

  @override
  String get fieldsSectionLabel => '項目';

  @override
  String get encryptedStorageHint => 'すべての項目はコンテナ内に暗号化されて保存されます。';

  @override
  String copiedSuffix(String fieldLabel) {
    return '$fieldLabelをコピーしました';
  }

  @override
  String get copy => 'コピー';

  @override
  String get failedToSaveCheckMounted =>
      '保存に失敗しました — コンテナがまだマウントされているか確認してください';

  @override
  String get discardChangesTitle => '変更を破棄しますか？';

  @override
  String get discardChangesMessage => '保存されていない変更は失われます。';

  @override
  String get discard => '破棄';

  @override
  String get keepEditing => '編集を続ける';

  @override
  String get deleteItemTitle => 'アイテムを削除しますか？';

  @override
  String deleteItemMessage(String title) {
    return '「$title」は保管庫から完全に削除されます。';
  }

  @override
  String get removeFromBookmarks => 'ブックマークから削除';

  @override
  String get addToBookmarks => 'ブックマークに追加';

  @override
  String get edit => '編集';

  @override
  String labelCopiedToClipboard(String label) {
    return '$labelをクリップボードにコピーしました';
  }

  @override
  String get noFieldsFilledIn => '入力された項目がありません。\n「編集」をタップして詳細を追加してください。';

  @override
  String get sectionLabelDetails => '詳細';

  @override
  String get sectionLabelInfo => '情報';

  @override
  String get metaLabelType => '種類';

  @override
  String get metaLabelCreated => '作成日';

  @override
  String get metaLabelModified => '更新日';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return '$fieldLabelをコピー';
  }

  @override
  String get readOnlyCantAddItemsTooltip => '読み取り専用 — アイテムを追加できません';

  @override
  String get extractArchive => 'アーカイブを展開';

  @override
  String get verbArchive => '圧縮';

  @override
  String get verbExtract => '展開';

  @override
  String get verbArchived => '圧縮済み';

  @override
  String get verbExtracted => '展開済み';

  @override
  String get verbArchiving => '圧縮中';

  @override
  String get verbExtracting => '展開中';

  @override
  String get fileOpExtractingArchive => 'アーカイブを展開中…';

  @override
  String fileOpExtractingArchiveName(String name) {
    return '$nameを展開中…';
  }

  @override
  String fileOpArchivingBytes(String bytes) {
    return '圧縮中… ($bytes)';
  }

  @override
  String get newItemTooltip => '新規アイテム';

  @override
  String get camera => 'カメラ';

  @override
  String get importFiles => 'ファイルをインポート';

  @override
  String get importFolder => 'フォルダをインポート';

  @override
  String get secureItem => 'セキュアアイテム';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archive Explorer';

  @override
  String get archiveExplorerPermissionTitle => 'ストレージへのアクセスが必要です';

  @override
  String get archiveExplorerPermissionMessage =>
      'ダウンロードフォルダ内の.zipアーカイブを閲覧・展開するには、ファイルへのアクセスを許可してください。';

  @override
  String get archiveExplorerGrantAccess => 'アクセスを許可';

  @override
  String get archiveExplorerEmptyTitle => 'アーカイブが見つかりません';

  @override
  String get archiveExplorerEmptyMessage => 'ダウンロードしたZipファイルはここに表示されます。';

  @override
  String get archiveExplorerRefreshTooltip => '更新';

  @override
  String archiveExplorerEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のアイテム',
    );
    return '$_temp0';
  }

  @override
  String get archiveExplorerExtractAll => 'すべて展開';

  @override
  String get archiveExplorerExtracting => '展開中…';

  @override
  String archiveExplorerExtractSuccess(int count, String name) {
    return '$count個のファイルをDownload/Extracted/$nameに展開しました';
  }

  @override
  String get archiveExplorerExtractFailed => 'そのアーカイブを展開できませんでした。';

  @override
  String get archiveExplorerOpenFailed => 'そのアーカイブを開けませんでした。';

  @override
  String get archiveExplorerOpenArchive => 'アーカイブを開く…';

  @override
  String get archiveExplorerUnresolvedPath =>
      'そのファイルに直接アクセスできませんでした。代わりにダウンロードから選択してください。';

  @override
  String get archiveExplorerExtractTo => '展開先を指定…';

  @override
  String get archiveExplorerPreview => 'プレビュー';

  @override
  String get archiveExplorerChoosingDestination => '保存先を選択中…';

  @override
  String get archiveExplorerNoDestinationChosen => '保存先が選択されていません。';

  @override
  String archiveExplorerExtractSuccessTo(int count, String path) {
    return '$count個のファイルを$pathに展開しました';
  }

  @override
  String get archiveBrowserEmptyTitle => '空のフォルダ';

  @override
  String get archiveBrowserEmptyMessage => 'このフォルダにはファイルが含まれていません。';

  @override
  String get archiveBrowserRoot => 'アーカイブ';

  @override
  String get archiveBrowserOpenFileFailed => 'そのファイルを開けませんでした。';

  @override
  String get fileAssocInAppTextEditor => 'アプリ内テキストエディタ';

  @override
  String get fileAssocInAppMediaViewer => 'アプリ内メディアビューア';

  @override
  String fileAssocAppPrefix(String name) {
    return 'アプリ: $name';
  }

  @override
  String get fileAssocExternalApp => '外部アプリ';

  @override
  String get appSettingsTitle => 'アプリ設定';

  @override
  String get sectionSecurityPrivacy => 'セキュリティとプライバシー';

  @override
  String get sectionAppearanceInterface => '外観とインターフェース';

  @override
  String get sectionVaultFileHandling => '保管庫とファイル処理';

  @override
  String get masterPasswordTitle => 'マスターパスワード';

  @override
  String get masterPasswordActiveSubtitle => '有効 — タップして解除';

  @override
  String get masterPasswordInactiveSubtitle => 'アプリを開く際にパスワードを要求する';

  @override
  String get newPasswordLabel => '新しいパスワード';

  @override
  String get masterPasswordFieldLabel => 'マスターパスワード';

  @override
  String get confirmPasswordLabel => 'パスワードの確認';

  @override
  String get update => '更新';

  @override
  String get setPassword => 'パスワードを設定';

  @override
  String get biometricUnlockTitle => '生体認証ロック解除';

  @override
  String get biometricUnlockSubtitle => '認証してコンテナを安全にマウントします';

  @override
  String get changeMasterPasswordTitle => 'マスターパスワードを変更';

  @override
  String get changeMasterPasswordSubtitle => 'マスターパスワードの認証情報を更新します';

  @override
  String get autoLockContainersTitle => 'コンテナの自動ロック';

  @override
  String get autoLockContainersSubtitle => '非アクティブ状態が続くと、開いている保管庫を自動的にロックします';

  @override
  String get autoLockTimeoutLabel => '自動ロックまでの時間';

  @override
  String get immediately => 'すぐに';

  @override
  String nMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count分',
    );
    return '$_temp0';
  }

  @override
  String nHours(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count時間',
    );
    return '$_temp0';
  }

  @override
  String get customDurationOption => 'カスタム…';

  @override
  String get customDurationDialogTitle => 'カスタム時間';

  @override
  String get blockScreenshotsTitle => 'スクリーンショットをブロック';

  @override
  String get blockScreenshotsSubtitle => 'スクリーンショットを防止し、最近使ったアプリのプレビューを非表示にします';

  @override
  String get keepVaultsRunningInBackgroundTitle => '保管庫をバックグラウンドで維持';

  @override
  String get keepVaultsRunningInBackgroundSubtitle =>
      '通知を表示し、アプリを離れた後も開いている保管庫を利用可能な状態に保ちます。保管庫の鍵はロックされるまでメモリに残ります。';

  @override
  String get notificationPermissionDeniedMessage =>
      '通知の権限が拒否されました。保管庫は引き続き開いたままになりますが、常駐通知は表示されません。';

  @override
  String get discreteModeTitle => 'マスクモード';

  @override
  String get discreteModeActiveSubtitle =>
      '有効 — 現在アプリは「Archive Explorer」として表示されています';

  @override
  String get discreteModeInactiveSubtitle => 'ホーム画面でこのアプリをzipアーカイブブラウザに偽装します';

  @override
  String get enableDiscreteModeTitle => 'マスクモードを有効にしますか？';

  @override
  String get disableDiscreteModeTitle => 'マスクモードを無効にしますか？';

  @override
  String get enableDiscreteModeMessage =>
      'ホーム画面のアプリアイコンと名前が「Archive Explorer」に変わります。zipアーカイブのブラウザおよび展開ツールとして機能します。\n\n保管庫にアクセスするには、Archive Explorerを開き、タイトルを2秒間長押ししてください。';

  @override
  String get disableDiscreteModeMessage =>
      'ホーム画面のアプリアイコンと名前が「Vault Explorer」に戻ります。';

  @override
  String get enable => '有効にする';

  @override
  String get disable => '無効にする';

  @override
  String get discreteModeEnabledSnack =>
      'マスクモードが有効になりました。アプリは終了します — 新しいランチャーアイコンから再度開いてください。';

  @override
  String get discreteModeDisabledSnack =>
      'マスクモードが無効になりました。アプリは終了します — 新しいランチャーアイコンから再度開いてください。';

  @override
  String get failedToChangeDiscreteMode => 'マスクモードの変更に失敗しました';

  @override
  String get cacheDerivedKeysTitle => '導出鍵をデフォルトでキャッシュ';

  @override
  String get cacheDerivedKeysSubtitle => '導出された鍵情報をKeystoreに保存し、ロック解除を高速化します';

  @override
  String get appThemeLabel => 'アプリテーマ';

  @override
  String get systemDefault => 'システムのデフォルト';

  @override
  String get lightTheme => 'ライトテーマ';

  @override
  String get darkTheme => 'ダークテーマ';

  @override
  String get useMaterialYouTitle => 'Material Youを使用';

  @override
  String get useMaterialYouSubtitle => 'アプリの色を壁紙に合わせます（Android 12以降）';

  @override
  String get pureBlackThemeTitle => '純粋な黒（OLED）';

  @override
  String get pureBlackThemeSubtitle =>
      '真っ黒な背景を使ってバッテリーを節約し、OLED画面での眩しさを軽減します（ダークテーマのみ）';

  @override
  String get sortContainersByLabel => 'コンテナの並べ替え基準';

  @override
  String get swapCardSwipeActionsTitle => 'カードのスワイプ操作を入れ替え';

  @override
  String get swapCardSwipeActionsSubtitle => 'カードをスワイプしたときに左に編集、右に削除を表示します';

  @override
  String get swipeGestureHintTitle => 'スワイプ操作のヒント';

  @override
  String get swipeGestureHintSubtitle => '最初のコンテナでカードのプレビューアニメーションを表示します';

  @override
  String get autoOpenOnUnlockTitle => 'ロック解除時に自動で開く';

  @override
  String get autoOpenOnUnlockActiveSubtitle => '保管庫のロック解除後に自動的に開きます';

  @override
  String get autoOpenOnUnlockInactiveSubtitle => '保管庫のロック解除のみ行い、ダッシュボードにとどまります';

  @override
  String get enableJsHtmlTitle => 'HTMLビューアでJavaScriptを有効にする';

  @override
  String get jsEnabledSubtitle => 'ローカルHTMLファイルでJavaScriptが有効です';

  @override
  String get jsDisabledSubtitle => 'ローカルHTMLファイルでJavaScriptが無効です';

  @override
  String get fastStorageAccessTitle => '高速ストレージアクセス';

  @override
  String get fastStorageAccessGrantedSubtitle =>
      'すべてのファイルへのアクセスが許可されています（最大速度）';

  @override
  String get fastStorageAccessNotGrantedSubtitle =>
      '最適な速度のため、システム設定で「すべてのファイルへのアクセス」を許可してください';

  @override
  String get showStorageLocationsTitle => 'サイドバーにストレージの場所を表示';

  @override
  String get showStorageLocationsSubtitle =>
      'ローカルストレージと追加した保存場所を表示します。ローカルストレージを開くには、すべてのファイルへのアクセスが必要です。';

  @override
  String get localStorageCardTitle => 'ローカルストレージ';

  @override
  String get localStorageCardSubtitle => '暗号化されていません — 保管庫との迅速な転送用';

  @override
  String get enableFastStorageAccessTitle => '高速ストレージアクセスを有効にする';

  @override
  String get enableFastStorageAccessMessage =>
      '「すべてのファイルへのアクセス」を許可すると、Vault ExplorerはPOSIXファイル操作を直接実行できるようになり、フォルダ保管庫のパフォーマンスが最大1000倍向上します。';

  @override
  String get disableStorageAccessTitle => 'ストレージアクセスを無効にする';

  @override
  String get disableStorageAccessMessage =>
      'Androidでは、「すべてのファイルへのアクセス」をシステム設定内でオフにする必要があります。設定を開いてオフにしますか？';

  @override
  String get enableStoragePermissionLegacyTitle => 'ストレージへのアクセスを許可';

  @override
  String get enableStoragePermissionLegacyMessage =>
      'Vault Explorerは、フォルダ保管庫のパフォーマンスを高速化する直接ファイル操作を行うためにストレージ権限が必要です。この後Androidから確認が求められます。';

  @override
  String get disableStoragePermissionLegacyMessage =>
      'Androidでは、ストレージ権限をシステム設定内でオフにする必要があります。設定を開いてオフにしますか？';

  @override
  String get openSettings => '設定を開く';

  @override
  String get useThisPasswordButton => 'このパスワードを使用';

  @override
  String get quickPasswordGeneratorSheetTitle => 'パスワード生成ツール';

  @override
  String get androidFileProviderTitle => 'Androidファイルプロバイダ';

  @override
  String get androidFileProviderSubtitle =>
      '新規コンテナをデフォルトでAndroidファイルピッカーに公開します';

  @override
  String get thumbnailCachingDefaultLabel => 'サムネイルのキャッシュ（デフォルト）';

  @override
  String get thumbnailQualityDefaultLabel => 'サムネイルの画質（デフォルト）';

  @override
  String get fileAssociationsHeader => 'ファイルの関連付け';

  @override
  String get noFileAssociationsYet =>
      '記憶されたファイルの関連付けはまだありません。ファイルを開く際に確認が表示されます。';

  @override
  String get defaultActionsHeader => '非標準ファイルを開く際のデフォルト動作：';

  @override
  String get removeAssociationTooltip => '関連付けを削除';

  @override
  String get sectionBackupRestore => 'バックアップ';

  @override
  String get exportSettingsTitle => '設定をエクスポート';

  @override
  String get exportSettingsSubtitle =>
      'アプリ、ファイルマネージャー、メディアプレーヤー、テキストエディタの設定をファイルに保存します。カスタムスキンは任意です。';

  @override
  String get importSettingsTitle => '設定をインポート';

  @override
  String get importSettingsSubtitle =>
      'ファイルからアプリ、ファイルマネージャー、メディアプレーヤー、テキストエディタの設定を復元します';

  @override
  String get importSettingsConfirmTitle => '設定をインポートしますか？';

  @override
  String get importSettingsConfirmMessage =>
      '現在のアプリ設定が置き換えられます。スキンとインターフェースのレイアウトは影響を受けません。この操作は元に戻せません。';

  @override
  String get exportSettingsOnlyTitle => '設定のみ';

  @override
  String get exportSettingsOnlySubtitle =>
      'アプリ、ファイルマネージャー、メディアプレーヤー、テキストエディタの設定';

  @override
  String get exportSettingsWithSkinsTitle => '設定とスキン';

  @override
  String get exportSettingsWithSkinsSubtitle => 'カスタムアプリスキンも保存します';

  @override
  String get importSettingsConfirmFullMessage =>
      '現在のアプリ、ファイルマネージャー、メディアプレーヤー、テキストエディタの設定がレイアウトを含めて置き換えられます。スキンは影響を受けません。この操作は元に戻せません。';

  @override
  String get importSettingsConfirmFullSkinsMessage =>
      '現在のアプリ、ファイルマネージャー、メディアプレーヤー、テキストエディタの設定がレイアウトを含めて置き換えられ、このファイルのスキンが追加されます。すでにあるスキンはファイル内のものに置き換えられます。この操作は元に戻せません。';

  @override
  String get exportSettingsSuccessMessage => '設定をエクスポートしました';

  @override
  String get importSettingsSuccessMessage => '設定をインポートしました';

  @override
  String get exportSettingsErrorMessage => '設定をエクスポートできませんでした';

  @override
  String get importSettingsInvalidFileMessage => 'そのファイルは有効な設定エクスポートではありません';

  @override
  String get sectionDebug => 'デバッグ';

  @override
  String get debugLoggingTitle => 'デバッグログ';

  @override
  String get debugLoggingSubtitle => 'コンテナ操作の詳細な診断ログを記録します';

  @override
  String get logcatTitle => 'Logcat';

  @override
  String get logcatSubtitle => 'デバイスログの表示と保存';

  @override
  String logcatSavedMessage(String path) {
    return 'ログを$pathに保存しました';
  }

  @override
  String get logcatSaveErrorMessage => 'ログの保存に失敗しました';

  @override
  String get logcatCopiedMessage => 'ログをクリップボードにコピーしました';

  @override
  String get logcatUnavailableMessage => 'このデバイスではLogcatを利用できません';

  @override
  String get logcatEmptyMessage => 'ログ行を待機しています…';

  @override
  String get logcatClearTooltip => 'ログを消去';

  @override
  String get logcatSaveTooltip => 'ログを保存';

  @override
  String get logcatFilterAppOnly => 'アプリのみ';

  @override
  String get logcatFilterAll => 'すべてのログ';

  @override
  String get logcatSearchHint => 'ログを検索…';

  @override
  String get logcatClearedMessage => 'ログを消去しました';

  @override
  String get logcatCopyTooltip => 'ログをコピー';

  @override
  String get retryButton => '再試行';

  @override
  String get aboutAppTitle => 'VaultExplorerについて';

  @override
  String versionInfoSubtitle(String version) {
    return 'バージョン $version · オープンソースライセンスと詳細';
  }

  @override
  String get failedToSaveSettings => '設定の保存に失敗しました';

  @override
  String get masterPasswordSetSnack => 'マスターパスワードを設定しました';

  @override
  String get passwordCannotBeEmpty => 'パスワードを空にすることはできません';

  @override
  String get atLeast4CharsRequired => '4文字以上必要です';

  @override
  String get passwordsDoNotMatch => 'パスワードが一致しません';

  @override
  String get failedToHashPassword => 'パスワードのハッシュ化に失敗しました — もう一度お試しください';

  @override
  String get languageLabel => '言語';

  @override
  String get biometricNotAvailable => 'このデバイスでは生体認証を利用できません';

  @override
  String get biometricsChangedFallbackMessage =>
      'デバイスの生体情報が変更されたため、生体認証によるロック解除をオフにしました。パスワードを使用してください。';

  @override
  String get unlockVaultExplorerReason => 'VaultExplorerのロックを解除';

  @override
  String biometricErrorWithCode(String code) {
    return '生体認証エラー: $code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds秒',
    );
    return '失敗回数が多すぎます。$_temp0後にもう一度お試しください。';
  }

  @override
  String get enterMasterPasswordPrompt => 'マスターパスワードを入力してください';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts回',
    );
    return 'パスワードが正しくありません。$_temp0失敗したため、$seconds秒間ロックされます。';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '失敗$attempts回',
    );
    return 'パスワードが正しくありません（$_temp0）。';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle => '続行するにはマスターパスワードを入力してください';

  @override
  String get masterPasswordFieldLabelTitleCase => 'マスターパスワード';

  @override
  String get unlock => 'ロック解除';

  @override
  String get useBiometric => '生体認証を使用';

  @override
  String get connectAtLeast4Dots => '4つ以上のドットをつないでください';

  @override
  String get patternsDontMatch => 'パターンが一致しません — もう一度お試しください';

  @override
  String get drawUnlockPatternTitle => 'ロック解除パターンを描く';

  @override
  String get confirmPatternTitle => 'パターンを確認してください';

  @override
  String get drawSamePatternAgain => '同じパターンをもう一度描いてください';

  @override
  String get enterAtLeast4Digits => '4桁以上の数字を入力してください';

  @override
  String get pinsDontMatch => 'PINが一致しません — もう一度お試しください';

  @override
  String get createUnlockPinTitle => 'ロック解除用PINを作成してください';

  @override
  String get confirmPinTitle => 'PINを確認してください';

  @override
  String get enterSamePinAgain => '同じPINをもう一度入力してください';

  @override
  String get enterUnlockPinTitle => 'ロック解除用PINを入力';

  @override
  String get wrongPinTryAgain => 'PINが正しくありません — もう一度お試しください';

  @override
  String get enterYourPinSequence => 'PINを入力してください';

  @override
  String get enterPinToMount => 'マウントするにはPINを入力してください';

  @override
  String get noPinConfiguredMessage => 'PINが設定されていません。パスワードを手動で入力してください。';

  @override
  String pinLockedForSeconds(int seconds) {
    return '失敗回数が多すぎます。$seconds秒間ロックされます。';
  }

  @override
  String get initSecureCredsPinMessage =>
      '安全な認証情報を初期化しています。PINアクセスを許可するには、一度手動でロックを解除してください。';

  @override
  String get setPinButton => 'PINを設定';

  @override
  String get changePinButton => 'PINを変更';

  @override
  String get pinSetupRequiredBeforeSaving => '保存する前にPINを設定してください。';

  @override
  String get pinSetupRequiredAboveBeforeSaving => '保存する前に上でPINを設定してください。';

  @override
  String get verifyPinTitle => 'PINを確認';

  @override
  String get incorrectPinError => 'PINが正しくありません';

  @override
  String removedFromListSnack(String name) {
    return '「$name」をリストから削除しました';
  }

  @override
  String get clearRecentHistoryTitle => '最近の履歴を消去しますか？';

  @override
  String get clearRecentHistoryMessage =>
      'リスト内のすべての最近のドキュメントが削除されます。デバイス上の実際のファイルには影響しません。';

  @override
  String get clearAll => 'すべて消去';

  @override
  String get recentHistoryClearedSnack => '最近の履歴を消去しました';

  @override
  String get moreOptionsTooltip => 'その他のオプション';

  @override
  String get clearHistoryMenuItem => '履歴を消去';

  @override
  String get openPdfFile => 'PDFファイルを開く';

  @override
  String get noDocumentsYetTitle => 'まだドキュメントがありません';

  @override
  String get openPdfToStartMessage => 'デバイスからPDFを開いて読書を始めましょう。';

  @override
  String get removeFromListMenuItem => 'リストから削除';

  @override
  String get justNow => 'たった今';

  @override
  String minutesAgo(int count) {
    return '$count分前';
  }

  @override
  String hoursAgo(int count) {
    return '$count時間前';
  }

  @override
  String daysAgo(int count) {
    return '$count日前';
  }

  @override
  String get usbDriveDisconnectedLocked => 'USBドライブが切断されました — コンテナはロックされました';

  @override
  String get containerAlreadyMounted => 'このコンテナはすでにマウントされています。';

  @override
  String get noVaultFolderFormatDetected =>
      'そのフォルダにmasterkey.cryptomator、gocryptfs.conf、cryfs.configのいずれも見つかりませんでした。';

  @override
  String get savedContainerSettingsNotFound => 'このコンテナの保存済み設定が見つかりませんでした。';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return 'コンテナの場所を更新できませんでした: $error';
  }

  @override
  String filePickerFailed(String error) {
    return 'ファイル選択に失敗しました: $error';
  }

  @override
  String get selectContainerFirst => '先にコンテナを選択してください';

  @override
  String get passwordOrKeyfilesRequired => 'パスワードまたはキーファイルが必要です';

  @override
  String get slowPerformanceWarningTitle => 'パフォーマンス低下の警告';

  @override
  String get slowPerformanceWarningMessage =>
      '現在、直接ストレージアクセスは無効になっています。\n\nCryFSはファイルを数千の小さなブロックに分割して保存します。Android SAF経由で空でないCryFS保管庫を開くと非常に遅くなります。\n\n高速化のため、設定を開いて「すべてのファイルへのアクセス」を許可しますか？';

  @override
  String get unlockAnyway => 'このままロック解除';

  @override
  String get defaultVaultName => '保管庫';

  @override
  String get defaultContainerName => 'コンテナ';

  @override
  String get incorrectPasswordOrInvalidVault => 'パスワードが違うか、無効な保管庫です';

  @override
  String get incorrectPasswordOrInvalidContainer => 'パスワードが違うか、無効なコンテナです';

  @override
  String get genericUnknownError => '不明なエラー';

  @override
  String get decryptingLabel => '復号中…';

  @override
  String get loadingContainerFromStorage =>
      'ストレージからコンテナを読み込み中… 大容量のファイルやクラウド上のファイルは時間がかかる場合があります。';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return 'キースロット $attempted/$total を試しています…';
  }

  @override
  String get luksKeyslotProgressUnknown => 'キースロットを試しています…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return '認証情報 $attempted/$total を確認しています…';
  }

  @override
  String get bitlockerCredentialProgressUnknown => '認証情報を確認しています…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return '$algo（$slotName）を試しています…';
  }

  @override
  String get unlockContainerLabel => 'コンテナのロックを解除';

  @override
  String get mountContainerTitle => 'コンテナをマウント';

  @override
  String get containerFileSegmentLabel => 'コンテナファイル';

  @override
  String get folderVaultSegmentLabel => 'フォルダ保管庫';

  @override
  String formatContainerLabel(String format) {
    return '$formatコンテナ';
  }

  @override
  String formatVaultLabel(String format) {
    return '$format保管庫';
  }

  @override
  String formatDriveLabel(String format) {
    return '$formatドライブ';
  }

  @override
  String get encryptedContainerLabel => '暗号化コンテナ';

  @override
  String get tapToSelectVaultFolder => 'タップして保管庫フォルダを選択…';

  @override
  String get tapToSelectContainerFile => 'タップしてコンテナファイルを選択…';

  @override
  String get containerMissingTitle => 'コンテナが見つかりません';

  @override
  String get filePathCouldNotBeResolved => 'ファイルパスを解決できませんでした';

  @override
  String get containerMissingExplanation =>
      'コンテナファイルが移動または削除されたか、格納先のストレージが現在切断されている可能性があります。';

  @override
  String get retryButtonLabel => '再試行';

  @override
  String get locateFileButtonLabel => 'ファイルを探す';

  @override
  String get authenticateToMountSubtitle => '認証してコンテナを安全にマウントします';

  @override
  String get usePasswordButtonLabel => 'パスワードを使用';

  @override
  String get authenticateButtonLabel => '認証';

  @override
  String get drawUnlockPatternCardTitle => 'ロック解除パターンを描く';

  @override
  String get wrongPatternTryAgain => 'パターンが正しくありません — もう一度お試しください';

  @override
  String get connectYourPatternSequence => 'パターンをつないでください';

  @override
  String get usePasswordInsteadButtonLabel => '代わりにパスワードを使用';

  @override
  String get passwordHintFolderVault => '保管庫のパスワードを入力';

  @override
  String get passwordHintBitlocker => 'パスワードまたは回復キーを入力';

  @override
  String get passwordHintContainer => 'コンテナのパスワードを入力';

  @override
  String get usingSavedPasswordTooltip => '保存済みのパスワードを使用中';

  @override
  String get luksKeyfileReplacesPasswordNote =>
      'LUKSコンテナでは、キーファイルがパスワードの代わりになります。';

  @override
  String get readOnlyModeUsbSubtitle => 'このドライブへの変更を許可せずにマウントします';

  @override
  String get readOnlyModeContainerSubtitle => 'このコンテナへの変更を許可せずにマウントします';

  @override
  String get rememberContainerLabel => 'コンテナを記憶';

  @override
  String get rememberContainerSubtitle => 'すばやくアクセスできるようダッシュボードにピン留めします';

  @override
  String get cancelUnlockButtonLabel => 'ロック解除をキャンセル';

  @override
  String get biometricSubjectContainer => 'コンテナ';

  @override
  String get biometricSubjectUsbDrive => 'USBドライブ';

  @override
  String get usbNoSavedCredentialsMessage => '保存済みのパスワードが見つかりません。手動で入力してください。';

  @override
  String get decryptingDriveLabel => 'ドライブを復号中…';

  @override
  String get usbDeviceAlreadyActiveMounted => 'このUSBデバイスはすでにアクティブでマウントされています。';

  @override
  String reconnectUsbDriveTitle(String label) {
    return '「$label」を再接続';
  }

  @override
  String get unlockUsbDriveTitle => 'USBドライブのロックを解除';

  @override
  String get noUsbStorageDetectedTitle => 'USBストレージが検出されません';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return '$subjectのロックを解除するために認証してください';
  }

  @override
  String get noPatternConfiguredMessage => 'パターンが設定されていません。パスワードを手動で入力してください。';

  @override
  String patternLockedForSeconds(int seconds) {
    return '失敗回数が多すぎます。$seconds秒間ロックされます。';
  }

  @override
  String get initSecureCredsBiometricMessage =>
      '安全な認証情報を初期化しています。生体認証アクセスを許可するには、一度手動でロックを解除してください。';

  @override
  String get initSecureCredsPatternMessage =>
      '安全な認証情報を初期化しています。パターンアクセスを許可するには、一度手動でロックを解除してください。';

  @override
  String get mountExistingContainerTitle => '既存のコンテナをマウント';

  @override
  String get mountExistingContainerSubtitle => 'すでに持っているファイルコンテナのロックを解除します';

  @override
  String get mountSplitContainerTitle => '分割コンテナをマウント';

  @override
  String get mountSplitContainerSubtitle => '分割コンテナを結合せずに直接ロック解除します';

  @override
  String get mountUsbDriveTitle => 'USBドライブをマウント';

  @override
  String get mountUsbDriveSubtitle => 'OTGフラッシュドライブ上のコンテナのロックを解除します';

  @override
  String get formatUsbDriveTitle => 'USBドライブをフォーマット';

  @override
  String get formatUsbDriveSubtitle => 'ドライブを消去し、新しい暗号化コンテナを作成します';

  @override
  String get createNewContainerTitle => '新しいコンテナを作成';

  @override
  String get createNewContainerSubtitle => 'まったく新しい暗号化保管庫をフォーマットします';

  @override
  String get lockBeforeRemovingWarning => '削除する前にコンテナをロックしてください。';

  @override
  String get settingsTooltip => '設定';

  @override
  String get addVaultFabLabel => '保管庫を追加';

  @override
  String removedLabelUndo(String label) {
    return '「$label」を削除しました';
  }

  @override
  String get undo => '元に戻す';

  @override
  String get pdfViewerNoSourceProvided => 'PDFのソースが指定されていません。';

  @override
  String get pdfViewerFileEmpty => 'PDFファイルが空か読み取れません。';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return 'PDFファイルサイズの確認に失敗しました: $error';
  }

  @override
  String get pdfViewerErrorLoadingTitle => 'PDFの読み込みエラー';

  @override
  String get pdfViewerNoDocumentLoaded => 'PDF文書が読み込まれていません。';

  @override
  String get add => '追加';

  @override
  String get reset => 'リセット';

  @override
  String couldNotExpose(String name) {
    return '「$name」を公開できませんでした。';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return '「$name」が他のアプリで利用可能になりました。';
  }

  @override
  String couldNotUnmount(String name) {
    return '「$name」をアンマウントできませんでした。';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアイテムをピン留めしました',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアイテムのピン留めを解除しました',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning =>
      '読み取り専用でマウント中 — サムネイルは表示されますが、このセッションではコンテナ内に保存されません。';

  @override
  String failedLoadingFolder(String type) {
    return 'フォルダの読み込みに失敗しました: $type';
  }

  @override
  String failedToReadArchive(String type) {
    return 'アーカイブの読み込みに失敗しました: $type';
  }

  @override
  String archiveFormatNotSupported(String ext) {
    return '.$ext形式のアーカイブはまだサポートされていません';
  }

  @override
  String get archivePasswordPromptTitle => 'パスワード保護';

  @override
  String get archivePasswordPromptMessage =>
      'このアーカイブはパスワードで保護されています。内容を表示するにはパスワードを入力してください。';

  @override
  String get archiveSolidWarning =>
      'これはソリッドアーカイブです — 特に末尾付近のファイルを開くのに時間がかかる場合があります。';

  @override
  String get failedToReadFileFromArchive => 'アーカイブからファイルを読み込めませんでした';

  @override
  String failedToExtractFile(String type) {
    return 'ファイルの展開に失敗しました: $type';
  }

  @override
  String get failedToReadSecureItem => 'セキュアアイテムの読み込みに失敗しました';

  @override
  String get openFileDialogTitle => 'ファイルを開く';

  @override
  String chooseHowToOpen(String name) {
    return '「$name」の開き方を選択してください:';
  }

  @override
  String get playVideoAudioViewImageInApp => 'アプリ内で動画/音声を再生または画像を表示';

  @override
  String get viewEditTextMarkdownCode => 'テキスト、Markdown、コードを表示/編集';

  @override
  String get sendFileToThirdPartyApp => 'ファイルをサードパーティアプリに送信';

  @override
  String get openAsEllipsis => '開き方を指定…';

  @override
  String get chooseFileTypeToOpenAs => '開くファイルタイプを選択';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return '.$extファイルの選択を常に記憶する';
  }

  @override
  String get alwaysRememberChoiceNoExt => '拡張子のないファイルの選択を常に記憶する';

  @override
  String get openAsDialogTitle => '開き方を指定';

  @override
  String get mimeTypeText => 'テキスト';

  @override
  String get mimeTypeImage => '画像';

  @override
  String get mimeTypeVideo => '動画';

  @override
  String get mimeTypeAudio => '音声';

  @override
  String get mimeTypeArchive => 'アーカイブ';

  @override
  String get mimeTypeOther => 'その他';

  @override
  String get scanningSubfoldersForMedia => 'サブフォルダ内のメディアをスキャン中…';

  @override
  String get noMediaFilesFoundRecursive => 'このフォルダまたはサブフォルダにメディアファイルが見つかりません';

  @override
  String failedToScanSubfolders(String error) {
    return 'サブフォルダのスキャンに失敗しました: $error';
  }

  @override
  String scanningSubfoldersForMediaProgress(int count) {
    return 'サブフォルダ内のメディアをスキャン中…$count 件確認済み';
  }

  @override
  String get mediaScanCancelled => 'メディアのスキャンをキャンセルしました';

  @override
  String get mediaScanLimitReached =>
      '多数のフォルダを確認した後スキャンを停止しました。メディアは見つかりませんでした。';

  @override
  String get noAppFoundForFileType => 'このファイルタイプに対応するアプリが見つかりません';

  @override
  String couldNotOpenFile(String name) {
    return '「$name」を開けませんでした';
  }

  @override
  String get couldNotShareFiles => '選択したファイルを共有できませんでした';

  @override
  String get readOnlyCantMove => 'このコンテナは読み取り専用でマウントされています — ここからアイテムを移動できません。';

  @override
  String get readOnlyCantPaste =>
      'このコンテナは読み取り専用でマウントされています — ここにアイテムを貼り付けできません。';

  @override
  String get clipboardSourceInvalid => 'クリップボードのソースが無効です';

  @override
  String get crossContainerPasteNotConfigured => 'コンテナ間の貼り付けは設定されていません。';

  @override
  String get crossContainerPasteRequiresBothMounted =>
      'コンテナ間の貼り付けには、両方のコンテナがマウントされたままである必要があります。';

  @override
  String get readOnlyCantDelete => 'このコンテナは読み取り専用でマウントされています — アイテムを削除できません。';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアイテムを削除しました',
    );
    return '$_temp0';
  }

  @override
  String deletedWithFailures(int deleted, int failed) {
    return '$deleted件削除 · $failed件失敗';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイルをエクスポートしました',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed => 'エクスポートがキャンセルされたか失敗しました';

  @override
  String exportError(String type) {
    return 'エクスポートエラー: $type';
  }

  @override
  String get deleteOriginalTitle => '元のファイルを削除しますか？';

  @override
  String get deleteOriginalFolderMessage => 'インポートが完了したので、デバイス上の元のフォルダを削除しますか？';

  @override
  String get deleteOriginalFilesMessage => 'インポートが完了したので、デバイス上の元のファイルを削除しますか？';

  @override
  String get keepOriginal => '元のファイルを保持';

  @override
  String get deleteOriginalButton => '元のファイルを削除';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '元のアイテムを$count件削除しました',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals => '元のファイルを削除できませんでした';

  @override
  String get videoCapturedEncrypted => '動画を保存しました';

  @override
  String get photoCapturedEncrypted => '写真を保存しました';

  @override
  String cameraCaptureFailed(String type) {
    return 'カメラでの撮影に失敗しました: $type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return 'すべてのファイルをフォルダ「$folder」に展開しますか？';
  }

  @override
  String get extract => '展開';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイルを展開しました',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return '展開に失敗しました: $type';
  }

  @override
  String get archiveSelectionAction => '圧縮';

  @override
  String get createArchiveTitle => 'アーカイブを作成';

  @override
  String get archiveNameHint => 'アーカイブ.zip';

  @override
  String archivedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイルを圧縮しました',
    );
    return '$_temp0';
  }

  @override
  String failedToArchiveGeneric(String type) {
    return '圧縮に失敗しました: $type';
  }

  @override
  String get createArchivePasswordHint => '任意のパスワード（AES-256）';

  @override
  String get createArchivePasswordUnavailableForFormat =>
      'パスワード保護はZIPおよび7-Zipでのみ利用できます';

  @override
  String get createArchiveEncryptFilenames => 'ファイル名を暗号化';

  @override
  String get createArchiveEncryptFilenamesHint =>
      'パスワードが必要です。内容を一覧表示するだけでもパスワードが必要になります。';

  @override
  String get closeSearchTooltip => '検索を閉じる';

  @override
  String get searchInThisFolderTooltip => 'このフォルダ内を検索';

  @override
  String get playMediaHereTooltip => 'ここでメディアを再生';

  @override
  String get rootFolderLabel => 'ルート';

  @override
  String folderPickerFailed(String error) {
    return 'フォルダ選択に失敗しました: $error';
  }

  @override
  String get addAVaultTitle => '保管庫を追加';

  @override
  String get selectEmptyDestinationFolderFirst => '先に空の保存先フォルダを選択してください';

  @override
  String get passwordRequired => 'パスワードが必要です';

  @override
  String get vaultCreatedSuccessfully => '保管庫が正常に作成されました。';

  @override
  String get vaultCreationFailedEmptyFolder =>
      '保管庫の作成に失敗しました — 選択したフォルダが空であることを確認してください。';

  @override
  String get unknownErrorOccurred => '不明なエラーが発生しました';

  @override
  String get containerNameRequired => 'コンテナ名が必要です';

  @override
  String get enterValidSizeGreaterThanZero => '0より大きい有効なサイズを入力してください';

  @override
  String get passwordOrKeyfileRequired => 'パスワードまたは少なくとも1つのキーファイルが必要です';

  @override
  String get standardVolumePasswordsDoNotMatch => '標準ボリュームのパスワードが一致しません';

  @override
  String get hiddenVolumePasswordsDoNotMatch => '隠しボリュームのパスワードが一致しません';

  @override
  String get containerFileCreatedSuccessfully => 'コンテナファイルが正常に作成されました。';

  @override
  String get containerCreationCancelledOrFailed => 'コンテナの作成がキャンセルされたか失敗しました。';

  @override
  String insufficientSpaceForContainer(String needed, String available) {
    return '保存先の空き容量が不足しています。必要:$needed、空き容量:$availableのみ。';
  }

  @override
  String get vaultKindContainerFile => 'コンテナファイル';

  @override
  String get vaultKindFolderVault => 'フォルダ保管庫';

  @override
  String get formatFileSystemLabel => 'ファイルシステムをフォーマット';

  @override
  String get standardVolumeHeader => '標準ボリューム';

  @override
  String get containerFormatLabel => 'コンテナ形式';

  @override
  String get fileNameLabel => 'ファイル名';

  @override
  String get containerSizeLabel => 'コンテナサイズ';

  @override
  String get unitLabel => '単位';

  @override
  String get passwordFieldLabel => 'パスワード';

  @override
  String get confirmPasswordFieldLabelTitleCase => 'パスワードの確認';

  @override
  String get hiddenVolumeHeader => '隠しボリューム';

  @override
  String get createHiddenVolumeToggleTitle => '隠しボリュームを作成';

  @override
  String get createInvisibleSecondaryVolume => '目に見えない第2のボリュームを作成します';

  @override
  String get setOuterPasswordFirstToEnable =>
      '有効にするには、先に外側のパスワードまたはキーファイルを設定してください';

  @override
  String get hiddenPasswordLabel => '隠しパスワード';

  @override
  String get confirmHiddenPasswordLabel => '隠しパスワードの確認';

  @override
  String get hiddenSizeLabel => '隠しサイズ';

  @override
  String get unitMbMegabytes => 'MB（メガバイト）';

  @override
  String get unitGbGigabytes => 'GB（ギガバイト）';

  @override
  String get hiddenFileSystemLabel => '隠しファイルシステム';

  @override
  String get vaultFormatLabel => '保管庫形式';

  @override
  String get gocryptfsCipherLabel => 'コンテンツ暗号方式';

  @override
  String get cryfsCipherLabel => 'コンテンツ暗号方式';

  @override
  String get cryfsBlockSizeLabel => 'ブロックサイズ';

  @override
  String get destinationFolderLabel => '保存先フォルダ';

  @override
  String get selectEmptyFolderLabel => '空のフォルダを選択してください';

  @override
  String get tapToChooseVaultLocation => 'タップして保管庫の作成場所を選択…';

  @override
  String get folderVaultLimitationsNote =>
      'フォルダ保管庫は、キーファイル、PIM、隠しボリューム、VeraCrypt/LUKSの暗号方式の選択に対応していません。';

  @override
  String get createVaultButton => '保管庫を作成';

  @override
  String get createContainerButton => 'コンテナを作成';

  @override
  String get vaultCreationInProgressWait => '保管庫を作成しています。お待ちください。';

  @override
  String get containerCreationInProgressWait => 'コンテナを作成しています。お待ちください。';

  @override
  String get createEncryptedVaultTitle => '暗号化保管庫を作成';

  @override
  String get createEncryptedContainerTitle => '暗号化コンテナを作成';

  @override
  String get unitMbShort => 'MB';

  @override
  String get unitGbShort => 'GB';

  @override
  String failedToListUsbDevices(String error) {
    return 'USBデバイスの一覧取得に失敗しました: $error';
  }

  @override
  String get usbPermissionDenied => 'USBの権限が拒否されました';

  @override
  String get couldNotReadDriveCapacity =>
      'ドライブの容量を読み取れませんでした — サイズを手動で入力してください。';

  @override
  String get selectUsbDriveFirst => '先にUSBドライブを選択してください';

  @override
  String eraseDeviceTitle(String name) {
    return '「$name」を消去しますか？';
  }

  @override
  String get eraseDeviceMessage =>
      'このUSBドライブ上の現在のすべてのデータが完全に消去され、新しい暗号化コンテナに置き換えられます。この操作は元に戻せません。';

  @override
  String get eraseAndCreateButton => '消去して作成';

  @override
  String get usbPermissionRequiredToContinue => '続行するにはUSBの権限が必要です';

  @override
  String get usbContainerCreatedSnack =>
      'USBコンテナを作成しました。ロック解除するには「USBドライブをマウント」を使用してください。';

  @override
  String get usbContainerCreationFailed => 'USBコンテナの作成に失敗しました。';

  @override
  String get usbStandardVolumeSectionHeader => 'USBドライブと標準ボリューム';

  @override
  String get formattingErasesEverythingWarning =>
      'フォーマットすると、選択したドライブ上の現在のすべてのデータが消去されます。';

  @override
  String get selectUsbDriveLabel => 'USBドライブを選択';

  @override
  String get noUsbStorageDetected => 'USBストレージが検出されません';

  @override
  String get connectOtgDriveToFormat => 'フォーマットするにはOTGドライブを接続してください';

  @override
  String get refreshListButton => 'リストを更新';

  @override
  String get readyToFormat => 'フォーマットの準備完了';

  @override
  String get permissionRequired => '権限が必要です';

  @override
  String get readingDriveCapacity => 'ドライブ容量を読み取っています…';

  @override
  String get mustNotExceedDriveCapacity => 'ドライブの実際の容量を超えないようにしてください。';

  @override
  String get quickFormatTitle => 'クイックフォーマット';

  @override
  String get quickFormatDescription =>
      'ドライブのゼロ埋めをスキップします。高速ですが、古いデータを安全に消去しません。';

  @override
  String get eraseAndCreateContainerButton => '消去してコンテナを作成';

  @override
  String get usbContainerCreationInProgressWait => 'コンテナを作成しています。お待ちください。';

  @override
  String get formatUsbDriveScreenTitle => 'USBドライブをフォーマット';

  @override
  String get playlistTransitionAnimationLabel => 'プレイリストの切り替えアニメーション';

  @override
  String get playlistTransitionSlideLabel => 'スライド（デフォルト）';

  @override
  String get playlistTransitionFadeLabel => 'フェード';

  @override
  String get playlistTransitionZoomLabel => 'ズーム＆スケール';

  @override
  String get playlistTransitionDepthLabel => '奥行きスタック';

  @override
  String get playlistTransitionCubeLabel => '3Dキューブ';

  @override
  String get playlistTransitionFlipLabel => '3Dフリップ';

  @override
  String get unlockVaultTitle => '保管庫のロックを解除';

  @override
  String get openContainerTitle => 'コンテナを開く';

  @override
  String get selectContainerFileOrFolder => 'ファイルまたはフォルダを選択';

  @override
  String get readOnlyModeLabel => '読み取り専用モード';

  @override
  String get readOnlyModeSubtitle => '保管庫への書き込みや変更操作を防止します';

  @override
  String get alwaysOpenReadOnlyLabel => '常に読み取り専用';

  @override
  String get alwaysOpenReadOnlySubtitle => '新しいセッションは読み取り専用で開始します。';

  @override
  String get selectUsbDeviceLabel => 'USBデバイスを選択';

  @override
  String get noUsbDevicesFound => '互換性のあるUSBストレージデバイスが見つかりません';

  @override
  String get containerConfigTitle => '保管庫の設定';

  @override
  String get changePasswordTitle => 'パスワードを変更';

  @override
  String get confirmNewPasswordLabel => '新しいパスワードの確認';

  @override
  String get cameraCaptureTitle => '保管庫カメラ';

  @override
  String get takingPhoto => '写真を撮影中…';

  @override
  String get noVaultSelected => '保管庫が選択されていません';

  @override
  String get mediaDiagnosticsTitle => 'メディア診断';

  @override
  String get advancedViewerSettingsTitle => 'ビューア設定';

  @override
  String get textEditorSwitchToReadModeTooltip => '読み取り専用モードに切り替え';

  @override
  String get textEditorSwitchToEditModeTooltip => '編集モードに切り替え';

  @override
  String get textEditorReadOnlyIndicatorLabel => '読み取り専用';

  @override
  String get textEditorMoveCursorLeftTooltip => 'カーソルを左へ移動';

  @override
  String get textEditorMoveCursorRightTooltip => 'カーソルを右へ移動';

  @override
  String get textEditorSelectWordTooltip => '単語を選択';

  @override
  String get textEditorSwitchToHorizontalScrollTooltip => '水平スクロールに切り替える';

  @override
  String get textEditorSwitchToSoftWrapTooltip => '折り返しに切り替える';

  @override
  String get textEditorCaretScrubberLabel => '左右にドラッグしてカーソルを移動';

  @override
  String get textEditorFindTooltip => 'ファイル内を検索';

  @override
  String get textEditorFindHint => '検索';

  @override
  String get textEditorReplaceHint => '置換';

  @override
  String get textEditorToggleReplaceTooltip => '置換の切り替え';

  @override
  String get textEditorPreviousMatchTooltip => '前の一致';

  @override
  String get textEditorNextMatchTooltip => '次の一致';

  @override
  String get textEditorCaseSensitiveTooltip => '大文字と小文字を区別';

  @override
  String get textEditorRegexTooltip => '正規表現を使用';

  @override
  String get textEditorCloseFindTooltip => '検索を閉じる';

  @override
  String get textEditorNoMatches => '結果なし';

  @override
  String get textEditorReplaceButton => '置換';

  @override
  String get textEditorReplaceAllButton => 'すべて置換';

  @override
  String get textEditorMoreActionsTooltip => 'その他の操作';

  @override
  String get textEditorGoToLineMenuItem => '行へ移動…';

  @override
  String get textEditorGoToStartMenuItem => '先頭へ移動';

  @override
  String get textEditorGoToEndMenuItem => '末尾へ移動';

  @override
  String get textEditorFormatDocumentMenuItem => 'ドキュメントのフォーマット';

  @override
  String get textEditorMinifyJsonMenuItem => 'JSON を最小化';

  @override
  String get textEditorFormatFailedMessage =>
      'このファイルをフォーマットできませんでした。有効な形式か確認してください';

  @override
  String get textEditorGoToLineDialogTitle => '行へ移動';

  @override
  String get textEditorGoToLineFieldLabel => '行番号';

  @override
  String textEditorGoToLineHelperText(int maxLine) {
    return '1–$maxLine';
  }

  @override
  String textEditorGoToLineInvalidNumber(int maxLine) {
    return '1 から $maxLine までの行番号を入力してください';
  }

  @override
  String get goToLineButton => '移動';

  @override
  String get textEditorSaveConfirmTitle => '未保存の変更';

  @override
  String get textEditorSaveConfirmMessage => '閉じる前に変更を保存しますか？';

  @override
  String get saveAndClose => '保存して閉じる';

  @override
  String get discardChanges => '変更を破棄';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件選択中',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => 'すべて選択';

  @override
  String get deselectAll => '選択を解除';

  @override
  String get sortOptionsTitle => 'ファイルを並べ替え';

  @override
  String get layoutModeList => 'リスト表示';

  @override
  String get layoutModeGrid => 'グリッド表示';

  @override
  String get layoutModeMasonry => 'マソンリー';

  @override
  String get fileOperationsTitle => 'ファイル操作';

  @override
  String get conflictResolutionTitle => 'ファイルの競合';

  @override
  String get replaceExistingFile => '既存のファイルを置き換える';

  @override
  String get keepBothFiles => '両方を保持（新しいファイルの名前を変更）';

  @override
  String get skipFile => 'このファイルをスキップ';

  @override
  String get noVaultsFoundTitle => '保管庫が見つかりません';

  @override
  String get noVaultsFoundSubtitle =>
      '開始するには、新しい暗号化コンテナを作成するか、既存の保管庫を追加してください。';

  @override
  String get addExistingVaultButton => '既存の保管庫を追加';

  @override
  String get sortContainersModeManual => '手動（ドラッグで並べ替え）';

  @override
  String get sortContainersModeUnlockStatus => 'ロック解除状態（解除済みを先に）';

  @override
  String get sortContainersModeNameAZ => '名前（A→Z）';

  @override
  String get sortContainersModeNameZA => '名前（Z→A）';

  @override
  String get sortContainersModeNewest => '新しい順';

  @override
  String get sortContainersModeOldest => '古い順';

  @override
  String get thumbnailCacheAppCacheLabel => 'アプリキャッシュ';

  @override
  String get thumbnailCacheAppCacheDesc =>
      'アプリキャッシュ内に暗号化して保存されます。高速ですが、ストレージ容量が逼迫すると自動的に消去されます。';

  @override
  String get thumbnailCacheInContainerLabel => 'コンテナ内';

  @override
  String get thumbnailCacheInContainerDesc =>
      '暗号化コンテナ内に保存されます。コンテナ自体によって保護されますが、書き込みは遅くなります。';

  @override
  String get thumbnailCacheHiddenFolderLabel => '非表示フォルダ';

  @override
  String get thumbnailCacheHiddenFolderDesc =>
      'ルート内の非表示の .thumbcache フォルダに保存されます。アプリキャッシュと異なり、自動的には削除されません。';

  @override
  String get thumbnailCacheDisabledLabel => '無効';

  @override
  String get thumbnailCacheDisabledDesc => 'ディスクキャッシュなし。サムネイルは読み込みのたびに再生成されます。';

  @override
  String get unlockContainerTitle => 'コンテナのロックを解除';

  @override
  String get containerFileSegment => 'コンテナファイル';

  @override
  String get folderVaultSegment => 'フォルダ保管庫';

  @override
  String get enableButtonLabel => '有効にする';

  @override
  String get retryButtonLabelShort => '再試行';

  @override
  String get locateFileButton => 'ファイルを探す';

  @override
  String get authenticateButton => '認証';

  @override
  String get cancelUnlockButton => 'ロック解除をキャンセル';

  @override
  String tryingKeyslotProgress(int attempted, int total) {
    return 'キースロット $attempted/$total を試しています…';
  }

  @override
  String get tryingKeyslotSingle => 'キースロットを試しています…';

  @override
  String verifyingCredentialProgress(int attempted, int total) {
    return '認証情報 $attempted/$total を確認しています…';
  }

  @override
  String get verifyingCredentialSingle => '認証情報を確認しています…';

  @override
  String tryingAlgoSlot(String algo, String slotName) {
    return '$algo（$slotName）を試しています…';
  }

  @override
  String get hiddenVolumeSlotName => '隠しボリューム';

  @override
  String get standardVolumeSlotName => '標準ボリューム';

  @override
  String get containerMissingSubtitle => 'ファイルパスを解決できませんでした';

  @override
  String get containerMissingBody =>
      'コンテナファイルが移動または削除されたか、格納先のストレージが現在切断されている可能性があります。';

  @override
  String get connectPatternSequence => 'パターンをつないでください';

  @override
  String get passwordLabel => 'パスワード';

  @override
  String get enterVaultPasswordHint => '保管庫のパスワードを入力';

  @override
  String get enterBitlockerPasswordHint => 'パスワードまたは回復キーを入力';

  @override
  String get enterContainerPasswordHint => 'コンテナのパスワードを入力';

  @override
  String get readOnlyModeUsbSubtitleDrive => 'このドライブへの変更を許可せずにマウントします';

  @override
  String get rememberDriveLabel => 'ドライブを記憶';

  @override
  String get rememberDriveSubtitle => 'すばやくアクセスできるようダッシュボードにピン留めします';

  @override
  String get unlockVaultButtonLabel => '保管庫のロックを解除';

  @override
  String get cryfsStorageAccessWarning =>
      'CryFS保管庫は数千の小さなブロックファイルを使用します。直接ストレージアクセスがない場合、パフォーマンスが大幅に低下します。';

  @override
  String get folderVaultStorageAccessWarning =>
      '直接ストレージアクセスが無効になっています。フォルダ保管庫内のファイルの読み込みが遅くなる場合があります。';

  @override
  String get requestingPermission => '権限をリクエスト中…';

  @override
  String get unlockAndMountButton => 'ロック解除してマウント';

  @override
  String get unlockDriveButton => 'ドライブのロックを解除';

  @override
  String couldntFindDevice(String deviceName) {
    return '「$deviceName」が見つかりませんでした';
  }

  @override
  String get plugDriveBackInRetry =>
      'ドライブを再接続して「再試行」をタップするか、別の名前で表示されている場合は下から選択してください。';

  @override
  String get retryConnectionButton => '接続を再試行';

  @override
  String get refreshDevicesButton => 'デバイスを更新';

  @override
  String get connectOtgDriveToMount => 'マウントするにはOTGフラッシュドライブを接続してください';

  @override
  String get alreadyActive => 'すでにアクティブ';

  @override
  String get active => 'アクティブ';

  @override
  String get readyToUnlock => 'ロック解除の準備完了';

  @override
  String get enterUsbPartitionPassword => 'USBパーティションのパスワードを入力';

  @override
  String get biometricAuthenticationTitle => '生体認証';

  @override
  String get biometricAuthUsbSubtitle => 'このUSBデバイスのロックを解除してマウントするために認証します';

  @override
  String get connectPatternSequenceToMount => 'マウントするにはパターンをつないでください';

  @override
  String get selectAllAction => 'すべて選択';

  @override
  String get clearSelectionAction => '選択を解除';

  @override
  String get clearSelectionTooltip => '選択を解除';

  @override
  String get selectionOptionsTooltip => '選択オプション';

  @override
  String get readOnlyContainerTooltip => '読み取り専用コンテナ';

  @override
  String get copyAction => 'コピー';

  @override
  String get moveAction => '移動';

  @override
  String get renameAction => '名前を変更';

  @override
  String get exportToDeviceAction => 'デバイスにエクスポート';

  @override
  String get openWithAppAction => 'アプリで開く';

  @override
  String get shareAction => '共有';

  @override
  String get pinAction => 'ピン留め';

  @override
  String get pinSelectedAction => '選択項目をピン留め';

  @override
  String get unpinAction => 'ピン留めを解除';

  @override
  String get unpinSelectedAction => '選択項目のピン留めを解除';

  @override
  String get documentProviderSettingsMenu => 'ドキュメントプロバイダの設定';

  @override
  String get exposeAsDocumentProviderMenu => 'ドキュメントプロバイダとして公開';

  @override
  String get moreOptionsTooltipShort => 'その他のオプション';

  @override
  String get copyTooltip => 'コピー';

  @override
  String get searchInThisFolderHint => 'このフォルダ内を検索…';

  @override
  String get clearTooltip => 'クリア';

  @override
  String get backToDashboardTooltip => 'ダッシュボードに戻る';

  @override
  String get cancelPasteButton => '貼り付けをキャンセル';

  @override
  String get cancelImportButton => 'インポートをキャンセル';

  @override
  String get continueButton => '続行';

  @override
  String get skipButton => 'スキップ';

  @override
  String get keepBothButton => '両方を保持';

  @override
  String get clearAllButton => 'すべて消去';

  @override
  String get autoMountWhenUnlocksTitle => 'コンテナのロック解除時に自動マウント';

  @override
  String get autoMountWhenUnlocksSubtitle => '次回もこのフォルダを自動的に公開する';

  @override
  String get unmountButton => 'アンマウント';

  @override
  String get filtersMenuItem => 'フィルター';

  @override
  String get settingsMenuItem => '設定';

  @override
  String get sortOptionsTooltip => '並べ替えオプション';

  @override
  String get layoutOptionsTooltip => 'レイアウトオプション';

  @override
  String get lockContainerTooltip => 'コンテナをロック';

  @override
  String get renameTooltip => '名前を変更';

  @override
  String get cancelUpdatingPasswordTooltip => 'パスワードの更新をキャンセル';

  @override
  String get unlockSettingsButton => 'ロック解除設定';

  @override
  String get updateSavedCredentialsButton => '保存済みの認証情報を更新';

  @override
  String get verifyCredentialsTitle => '認証情報を確認';

  @override
  String get verifyButton => '確認';

  @override
  String get displayNameTitle => '表示名';

  @override
  String get containerNameHint => 'コンテナ名';

  @override
  String get deleteFileDialogTitle => 'ファイルを削除しますか？';

  @override
  String get deleteFilePermanentWarning => 'この操作は完全であり、元に戻せません。';

  @override
  String get unsavedChangesTitle => '未保存の変更';

  @override
  String get unsavedChangesMessage => '未保存の変更があります。閉じる前に保存しますか？';

  @override
  String get discardButton => '破棄';

  @override
  String get decryptingFileContent => 'ファイルの内容を復号しています...';

  @override
  String get cannotOpenFile => 'ファイルを開けません';

  @override
  String get changesSavedSuccessfully => '変更を正常に保存しました';

  @override
  String saveFailedWithError(String error) {
    return '保存に失敗しました: $error';
  }

  @override
  String linesCount(int count) {
    return '行数: $count';
  }

  @override
  String charsCount(int count) {
    return '文字数: $count';
  }

  @override
  String get unsavedChangesLabel => '未保存の変更';

  @override
  String get savedToVault => '保管庫に保存しました';

  @override
  String get saveChangesTooltip => '変更を保存';

  @override
  String get textEditorDecryptFailedMessage => '保管庫からファイルを復号できませんでした。';

  @override
  String get textEditorInvalidTextFileMessage => 'このファイルは有効なテキストファイルではないようです。';

  @override
  String get textEditorWriteBackFailedMessage => '保管庫へのファイルの書き戻しに失敗しました。';

  @override
  String get markdownViewerEditTooltip => '編集';

  @override
  String get markdownViewerPreviewTooltip => 'プレビュー';

  @override
  String get markdownEmptyPreviewMessage => 'プレビューする内容がまだありません。';

  @override
  String get backTooltip => '戻る';

  @override
  String get forwardTooltip => '進む';

  @override
  String get reloadTooltip => '再読み込み';

  @override
  String get optionsTooltip => 'オプション';

  @override
  String get htmlViewerErrorTitle => 'このページを表示できません';

  @override
  String get htmlViewerLoadFailedMessage => 'ファイルの読み込みに失敗しました';

  @override
  String get enableJavaScriptDialogTitle => 'JavaScriptを有効にしますか？';

  @override
  String get enableJavaScriptDialogMessage =>
      'このページは独自のローカルスクリプトを実行できるようになります。それでもネットワークアクセスはありません — この保管庫内のものはインターネット経由で送受信されません。';

  @override
  String get disableJavaScriptMenu => 'JavaScriptを無効にする';

  @override
  String get enableJavaScriptMenu => 'JavaScriptを有効にする';

  @override
  String get enterFullscreenMenu => '全画面表示にする';

  @override
  String failedToOpenExternalApp(String error) {
    return '外部アプリでの起動に失敗しました: $error';
  }

  @override
  String get thisFolderMenu => 'このフォルダ';

  @override
  String get allInclSubfoldersMenu => 'すべて（サブフォルダを含む）';

  @override
  String get disableShuffleMenu => 'シャッフルを無効にする';

  @override
  String get shufflePlaylistMenu => 'プレイリストをシャッフル';

  @override
  String get playlistOptionsTooltip => 'プレイリストオプション';

  @override
  String get enablePlaylistTooltip => 'プレイリストを有効にする';

  @override
  String get moreActionsTooltip => 'その他の操作';

  @override
  String get forcePortraitMenu => '縦向きに固定';

  @override
  String get forceLandscapeMenu => '横向きに固定';

  @override
  String get autoRotateSensorMenu => '自動回転（センサー）';

  @override
  String get screenOrientationMenu => '画面の向き';

  @override
  String get playlistTransitionMenu => 'プレイリストの切り替え';

  @override
  String get renameFileMenu => 'ファイル名を変更';

  @override
  String get deleteFileMenu => 'ファイルを削除';

  @override
  String get thumbnailCarouselTooltip => 'サムネイルカルーセル';

  @override
  String get advancedSettingsTooltip => '詳細設定';

  @override
  String get previousTooltip => '前へ';

  @override
  String get nextTooltip => '次へ';

  @override
  String get diagnosticsCopiedToClipboard => '診断情報をクリップボードにコピーしました';

  @override
  String get diagnosticsTitle => '診断情報';

  @override
  String get copyDiagnosticsTooltip => '診断情報をコピー';

  @override
  String get closeTooltip => '閉じる';

  @override
  String get diagnosticsPlaybackSection => '再生';

  @override
  String get diagnosticsEngineSection => 'エンジン';

  @override
  String get diagnosticsStateLabel => '状態';

  @override
  String get diagnosticsResolutionLabel => '解像度';

  @override
  String get diagnosticsAspectRatioLabel => 'アスペクト比';

  @override
  String get diagnosticsPositionLabel => '再生位置';

  @override
  String get diagnosticsDurationLabel => '長さ';

  @override
  String get diagnosticsErrorLabel => 'エラー';

  @override
  String get diagnosticsPlayerLabel => 'プレーヤー';

  @override
  String get diagnosticsDecodingLabel => 'デコード方式';

  @override
  String get diagnosticsExoPlayerValue => 'ExoPlayer（Android）';

  @override
  String get diagnosticsHardwareAcceleratedValue => 'ハードウェアアクセラレーション';

  @override
  String get diagnosticsUnknownValue => '不明';

  @override
  String get diagnosticsStateBuffering => 'バッファリング中';

  @override
  String get diagnosticsStatePlaying => '再生中';

  @override
  String get diagnosticsStatePaused => '一時停止中';

  @override
  String get diagnosticsDurationUnavailable => '--:--';

  @override
  String get rotate90Label => '90°回転';

  @override
  String get imageFitModeLabel => '画像の表示方法';

  @override
  String get slideshowDelayLabel => 'スライドショーの間隔';

  @override
  String get playbackSpeedLabel => '再生速度';

  @override
  String get subtitlesLabel => '字幕';

  @override
  String get imageSettingsTitle => '画像設定';

  @override
  String get playbackSettingsTitle => '再生設定';

  @override
  String get imageFitContain => '全体表示';

  @override
  String get imageFitWidth => '幅に合わせる';

  @override
  String get imageFitHeight => '高さに合わせる';

  @override
  String nSecondsDelay(int n) {
    return '$n秒';
  }

  @override
  String playbackSpeedNormal(String speed) {
    return '$speed倍（標準）';
  }

  @override
  String playbackSpeedValue(String speed) {
    return '$speed倍';
  }

  @override
  String slideshowDelaySecondsValue(int seconds) {
    return '$seconds秒';
  }

  @override
  String rotationDegreesValue(int degrees) {
    return '$degrees°';
  }

  @override
  String get settingsTooltipShort => '設定';

  @override
  String get sourceCodeTooltip => 'ソースコード';

  @override
  String get donateTooltip => '寄付';

  @override
  String get shareAppTooltip => 'アプリを共有';

  @override
  String get resetToDefaultsTooltip => 'デフォルトに戻す';

  @override
  String get usbUnlockContainerTitle => 'USBコンテナのロックを解除';

  @override
  String get usbMountContainerTitle => 'USBドライブをマウント';

  @override
  String get staticLabel => '静止';

  @override
  String get unmuteTooltip => 'ミュート解除';

  @override
  String get muteTooltip => 'ミュート';

  @override
  String get playOnceDisabledTooltip => '1回再生（自動送り無効）';

  @override
  String get playAndAdvanceTooltip => '再生して次へ進む';

  @override
  String get loopCurrentVideoTooltip => '現在の動画をループ再生';

  @override
  String get clearThumbnailCacheDialogTitle => 'サムネイルキャッシュを消去しますか？';

  @override
  String get clearThumbnailCacheDialogMessage =>
      'この保管庫のキャッシュ済みサムネイルが削除されます。次回メディアを閲覧する際に再生成されます。';

  @override
  String get clearCacheButton => 'キャッシュを消去';

  @override
  String get appCacheClearedUnlockMessage =>
      'アプリキャッシュを消去しました。内部キャッシュを消去するにはコンテナのロックを解除してください。';

  @override
  String get allThumbnailCachesClearedMessage => 'すべてのサムネイルキャッシュを正常に消去しました。';

  @override
  String get appCacheClearedContainerFailedMessage =>
      'アプリキャッシュは消去されましたが、コンテナ内部のキャッシュ消去に失敗しました。';

  @override
  String get failedToClearThumbnailCachesMessage => 'サムネイルキャッシュの消去に失敗しました。';

  @override
  String get authenticateToModifySettingsPrompt => '設定を変更するために認証してください';

  @override
  String get usbVaultSettingsTitle => 'USB保管庫の設定';

  @override
  String get vaultSettingsTitle => '保管庫の設定';

  @override
  String get generalSectionHeader => '一般';

  @override
  String get securityCredentialsSectionHeader => 'セキュリティと認証情報';

  @override
  String get securityOptionsLockedTitle => 'セキュリティオプションはロックされています';

  @override
  String get authenticateOriginalCredentialsMessage =>
      'セキュリティ設定を変更するには、コンテナの元の認証情報で認証してください。';

  @override
  String get unlockCredentialsLabel => 'ロック解除の認証情報';

  @override
  String get unavailableSuffixLabel => '（利用不可）';

  @override
  String get patternSetupRequiredBeforeSaving => '保存する前にパターンを設定してください。';

  @override
  String get passwordKeystoreEncryptedHelperText =>
      'パスワードはAndroid Keystoreを使用して暗号化されます。キーファイルのみを使用する場合は空欄にしてください。';

  @override
  String get changePatternButton => 'パターンを変更';

  @override
  String get setPatternButton => 'パターンを設定';

  @override
  String get cacheDerivedKeyLabel => '導出鍵をキャッシュ';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      '次回からCryFSのscrypt KDFをスキップします（鍵はAndroid Keystoreに保持）';

  @override
  String get reuseKeyMaterialKeystoreSubtitle => 'Android Keystore内の鍵情報を再利用します';

  @override
  String nDays(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count日',
    );
    return '$_temp0';
  }

  @override
  String get cacheDerivedKeyLifetimeTitle => 'キャッシュした鍵の保持期間';

  @override
  String get cacheDerivedKeyLifetimeNever => 'オフにするまで';

  @override
  String cacheDerivedKeyLifetimeExpiresOn(String date) {
    return '$dateに自動的に削除されます';
  }

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle =>
      'ロック解除時の自動検出をスキップするようアルゴリズムを固定します。';

  @override
  String get changeContainerPasswordTitle => 'コンテナのパスワードを変更';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      'BitLockerの認証情報はアプリ内では変更できません。Windowsの「BitLockerの管理」を使用してください。';

  @override
  String get systemIntegrationSectionHeader => 'システムと連携';

  @override
  String get autoLockDurationLabel => '自動ロックまでの時間';

  @override
  String get neverAutoLockOption => 'しない';

  @override
  String get neverAutoLockOptionSubtitle => 'アプリがロックされたり画面がオフになったりしても開いたままにします';

  @override
  String get defaultAutoLockOptionSubtitle => 'アプリの自動ロックおよび画面ロック設定に従います';

  @override
  String get exposeContentToFilePickerSubtitle =>
      'ロック解除中はシステムのファイルピッカーにコンテンツを公開する';

  @override
  String get thumbnailStorageSectionHeader => 'サムネイルの保存';

  @override
  String get cacheModeLabel => 'キャッシュモード';

  @override
  String get useGlobalDefaultSubtitle => 'グローバルデフォルトを使用';

  @override
  String get thumbnailQualityLabel => 'サムネイルの画質';

  @override
  String get clearThumbnailCacheTitle => 'サムネイルキャッシュを消去';

  @override
  String get removeCachedThumbnailsSubtitle => 'キャッシュされた画像・動画のサムネイルを削除します';

  @override
  String get vaultInformationSectionHeader => '保管庫情報';

  @override
  String get vaultInformationTileTitle => '保管庫の詳細を表示';

  @override
  String get vaultInformationTileSubtitle => '暗号方式、形式、その他の技術的詳細';

  @override
  String get vaultInfoLocationLabel => '場所';

  @override
  String get vaultInfoRequiresUnlockTitle => 'ロック解除が必要です';

  @override
  String get vaultInfoRequiresUnlockMessage =>
      '技術的詳細を表示するには、この保管庫のロックを解除してください。';

  @override
  String get vaultInfoLoadFailedTitle => '保管庫情報を読み込めませんでした';

  @override
  String get vaultInfoLoadFailedMessage => 'この保管庫の詳細を読み取る際に問題が発生しました。';

  @override
  String get vaultInfoVolumeSizeLabel => 'ボリュームサイズ';

  @override
  String get vaultInfoFileSystemLabel => 'ファイルシステム';

  @override
  String get vaultInfoHiddenVolumeLabel => '隠しボリューム';

  @override
  String get vaultInfoReadOnlyLabel => '読み取り専用';

  @override
  String get vaultInfoLuksVersionLabel => 'LUKSバージョン';

  @override
  String get vaultInfoSectorSizeLabel => 'セクタサイズ';

  @override
  String get vaultInfoVaultFormatLabel => '保管庫の形式';

  @override
  String get vaultInfoCipherComboLabel => '暗号方式の組み合わせ';

  @override
  String get vaultInfoShorteningThresholdLabel => 'ファイル名短縮のしきい値';

  @override
  String get vaultInfoFormatVersionLabel => '形式のバージョン';

  @override
  String get vaultInfoContentCipherLabel => 'コンテンツ暗号方式';

  @override
  String get vaultInfoFilenameEncryptionLabel => 'ファイル名';

  @override
  String get vaultInfoPlaintextNamesValue => '平文';

  @override
  String get vaultInfoEncryptedNamesValue => '暗号化済み';

  @override
  String get vaultInfoBlockCipherLabel => 'ブロック暗号方式';

  @override
  String get vaultInfoBlockSizeLabel => 'ブロックサイズ';

  @override
  String get vaultInfoCreatedWithVersionLabel => '作成時のバージョン';

  @override
  String get vaultInfoLastOpenedWithVersionLabel => '最終使用バージョン';

  @override
  String get vaultInfoYesValue => 'はい';

  @override
  String get vaultInfoNoValue => 'いいえ';

  @override
  String get vaultInfoBitlockerNote =>
      'このアプリはBitLocker独自のヘッダーメタデータを解析しないため、暗号方式やバージョンの詳細はここでは表示されません。';

  @override
  String get patternSetupRequiredAboveBeforeSaving => '保存する前に上でパターンを設定してください。';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      'このロック解除方法には、パスワード、またはキーファイルを使用した「導出鍵をキャッシュ」が必要です。';

  @override
  String get saveConfigurationButton => '設定を保存';

  @override
  String get incorrectPatternError => 'パターンが正しくありません';

  @override
  String get verifyPatternTitle => 'パターンを確認';

  @override
  String get incorrectPasswordError => 'パスワードが正しくありません';

  @override
  String get verificationFailedError => '確認に失敗しました';

  @override
  String get incorrectCredentialsError => '認証情報が正しくありません';

  @override
  String get containerPasswordOptionalLabel => 'コンテナのパスワード（キーファイルのみの場合は任意）';

  @override
  String get pimOptionalLabel => 'PIM（任意）';

  @override
  String get usbDriveLockedLabel => 'USBドライブ・ロック中';

  @override
  String get lockedContainerLabel => 'ロックされたコンテナ';

  @override
  String get operationInProgressWaitMessage => '操作が進行中です。ロックする前にお待ちください。';

  @override
  String get reconnectUsbTooltip => 'USBを再接続';

  @override
  String get unlockContainerTooltip => 'コンテナのロックを解除';

  @override
  String lockFailedMessage(String errorType) {
    return 'ロックに失敗しました: $errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired => '新しいパスワードまたはキーファイルが必要です。';

  @override
  String get newPasswordsDoNotMatch => '新しいパスワードが一致しません。';

  @override
  String get passwordChangedSuccessfullyMessage => 'パスワードを正常に変更しました。';

  @override
  String get failedToChangePasswordMessage =>
      'パスワードの変更に失敗しました。以前の認証情報を確認してください。';

  @override
  String get currentCredentialsSectionHeader => '現在の認証情報';

  @override
  String get oldPasswordLabel => '現在のパスワード';

  @override
  String get oldPimOptionalLabel => '現在のPIM（任意）';

  @override
  String get newCredentialsSectionHeader => '新しい認証情報';

  @override
  String get newPimOptionalLabel => '新しいPIM（任意）';

  @override
  String get noContainersYetTitle => 'コンテナがまだありません';

  @override
  String get dashboardEmptyStateMessage =>
      'VeraCryptコンテナをマウントするか、USBドライブを接続するか、まったく新しい暗号化保管庫を作成して始めましょう。';

  @override
  String get sortFieldName => '名前';

  @override
  String get sortFieldSize => 'サイズ';

  @override
  String get sortFieldType => '種類';

  @override
  String get sortFieldDate => '日付';

  @override
  String get layoutModeDetailedList => '詳細リスト';

  @override
  String get layoutModeCompactList => 'コンパクトリスト';

  @override
  String get layoutModeGalleryGrid => 'ギャラリーグリッド';

  @override
  String get readOnlyCantDeleteTooltip => '読み取り専用 — 削除できません';

  @override
  String get readOnlyCantMoveTooltip => '読み取り専用 — 移動できません';

  @override
  String get readOnlyCantRenameTooltip => '読み取り専用 — 名前を変更できません';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes（計算中…）';
  }

  @override
  String get sizeCalculatingLabel => '計算中…';

  @override
  String get editSecureItemsToRenameMessage => '名前を変更するにはセキュアアイテムを編集してください';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage =>
      '保管庫のアイテムは外部アプリで開けません';

  @override
  String get itemsCannotBeSharedMessage => 'これらの項目は他のアプリと共有できません';

  @override
  String get mountedReadOnlyTooltip => '読み取り専用でマウント中';

  @override
  String get readOnlyBadgeAbbreviation => 'RO';

  @override
  String freeSpaceLabel(String bytes) {
    return '空き容量 $bytes';
  }

  @override
  String get filteredLabel => 'フィルター中';

  @override
  String get statsStorageSectionHeader => 'ストレージ';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のフォルダ',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイル',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => 'すべてのファイル';

  @override
  String get filterImagesOption => '画像';

  @override
  String get filterVideosOption => '動画';

  @override
  String get filterAudioOption => '音声';

  @override
  String get filterDocumentsOption => 'ドキュメント';

  @override
  String get folderExposedAsStorageExplanation =>
      'このフォルダは独立したストレージ場所として公開されているため、他のアプリがそのファイルを直接閲覧・開くことができます。';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアイテムがすでに存在します',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle =>
      '各アイテムに対する処理を選択するか、1つの選択をすべてに適用してください。';

  @override
  String get skipAllChipLabel => 'すべてスキップ';

  @override
  String get overwriteAllChipLabel => 'すべて上書き';

  @override
  String get overwriteItemDropdownLabel => '上書き';

  @override
  String get overwriteFolderDropdownLabel => 'フォルダを上書き';

  @override
  String get fileOpsTransfersInProgressTitle => '転送中';

  @override
  String get fileOpsRecentTransfersTitle => '最近の転送';

  @override
  String get fileOpsNoRecentTransfersMessage => '最近の転送はありません';

  @override
  String get fileOpsNoRecentTransfersSubtitle => 'コピー、移動、削除の実行中にここに表示されます。';

  @override
  String fileOpsShowDetailsLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアイテム',
    );
    return '$_temp0';
  }

  @override
  String get fileOpsCancelTooltip => 'キャンセル';

  @override
  String get fileOpsDismissTooltip => '閉じる';

  @override
  String get fileOpsRootDestinationLabel => 'ルート';

  @override
  String get fileOpsCancelledStatusLabel => 'キャンセル済み';

  @override
  String fileOpsItemsFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のアイテムが失敗しました:',
    );
    return '$_temp0';
  }

  @override
  String fileOpsMoreItemsLabel(num count) {
    return '他$count件';
  }

  @override
  String get transferActivityTooltip => '転送';

  @override
  String fileOpsSpeedLabel(String speed) {
    return '$speed/秒';
  }

  @override
  String fileOpsEtaLabel(String time) {
    return '残り約$time';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return 'ファイルの読み込みエラー: $error';
  }

  @override
  String get archivePreviewNotAvailableMessage => 'このファイル形式のプレビューは利用できません。';

  @override
  String get avifFailedToRenderMessage => 'AVIFの表示に失敗しました';

  @override
  String get encryptedImageLoadFailedMessage => '暗号化画像の読み込みに失敗しました';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return '暗号化画像の読み込みに失敗しました: $error';
  }

  @override
  String get imagePreviewTooLargeMessage => 'この画像は大きすぎるためプレビューできません';

  @override
  String get imagePreviewOutOfMemoryMessage =>
      'この画像をプレビューするための十分な空きメモリがありません。他のアプリを閉じてからもう一度お試しください。';

  @override
  String get invalidOrCorruptedImageMessage => '無効または破損した画像形式です。';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '$total件中$current件目';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '$total件中$current件目  ·  スキャン中…';
  }

  @override
  String get mediaViewerScanningLabel => 'スキャン中…';

  @override
  String get mediaFileDeletedMessage => 'ファイルを正常に削除しました';

  @override
  String get mediaFileDeleteFailedMessage => 'ファイルの削除に失敗しました';

  @override
  String get mediaFileRenamedMessage => 'ファイル名を正常に変更しました';

  @override
  String get aboutScreenTitle => 'アプリについて';

  @override
  String get couldNotOpenLinkMessage => 'リンクを開けませんでした';

  @override
  String get fileManagerSettingsTitle => 'ファイルマネージャー設定';

  @override
  String get showMediaThumbnailsLabel => 'メディアのサムネイルを表示';

  @override
  String get showMediaThumbnailsDesc => 'リスト表示で画像や動画のサムネイルプレビューを表示します';

  @override
  String get showFileNamesLabel => 'ファイル名を表示';

  @override
  String get showFileNamesDesc => 'グリッド表示でアイテムの下にテキストラベルを表示します';

  @override
  String get showBreadcrumbBarLabel => 'パンくずバーを表示';

  @override
  String get showBreadcrumbBarDesc => 'ブラウザ上部のパス移動バー';

  @override
  String get showStatsBarLabel => '統計バーを表示';

  @override
  String get showStatsBarDesc => 'ファイル数と空き容量情報のバナー';

  @override
  String get autoStartPlaylistModeLabel => 'プレイリストモードを自動開始';

  @override
  String get autoStartPlaylistModeDesc => 'メディアアイテムを開いたときに自動的にプレイリストモードで開始します';

  @override
  String get showPlaylistCarouselLabel => 'プレイリストカルーセルを表示';

  @override
  String get showPlaylistCarouselDesc => 'メディアプレイリストの表示中にサムネイルカルーセルボタンを表示します';

  @override
  String get videoPlaybackSliderLabel => '動画再生位置スライダー';

  @override
  String get longPressPlaybackDiagnosticsHint => '長押しで再生診断情報を表示';

  @override
  String get staticImageModeLabel => '静止画像モード';

  @override
  String slideshowModeActiveLabel(int seconds) {
    return 'スライドショーモードが有効（間隔$seconds秒）';
  }

  @override
  String videoPlaybackModeLabel(String mode) {
    return '動画再生モード: $mode';
  }

  @override
  String get pauseLabel => '一時停止';

  @override
  String get playLabel => '再生';

  @override
  String get emptyFolderTitle => '空のフォルダ';

  @override
  String get emptyFolderMessage => '「追加」アクションを使ってファイルを作成するか、デバイスからインポートしてください。';

  @override
  String get noResultsTitle => '結果なし';

  @override
  String noResultsForQueryMessage(String query) {
    return 'このフォルダには「$query」に一致するものがありません。';
  }

  @override
  String get closeCarouselTooltip => 'カルーセルを閉じる';

  @override
  String get playlistScrollModeMenu => 'プレイリストのスクロールモード';

  @override
  String get playlistScrollHorizontalLabel => '横方向';

  @override
  String get playlistScrollVerticalPageLabel => '縦方向（ページ送り）';

  @override
  String get playlistScrollVerticalContinuousLabel => '縦方向（連続スクロール）';

  @override
  String get undoTooltip => '元に戻す';

  @override
  String get redoTooltip => 'やり直す';

  @override
  String get autosavingLabel => '自動保存中…';

  @override
  String get savingLabel => '保存中…';

  @override
  String autosavedAtLabel(String time) {
    return '$timeに自動保存しました';
  }

  @override
  String cameraDisconnectedError(String message) {
    return 'カメラが切断されました: $message';
  }

  @override
  String get unknownErrorFallback => '不明なエラー';

  @override
  String get cameraPermissionsRequiredMessage => 'カメラを使用するには、カメラとマイクの権限が必要です。';

  @override
  String cameraErrorMessage(String error) {
    return 'カメラエラー: $error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage => '写真の撮影に失敗しました';

  @override
  String get cameraRecordingFailedMessage => '録画に失敗しました';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return '録画に失敗しました: $error';
  }

  @override
  String get cameraRecordingTooShortMessage => '録画時間が短すぎたため保存できませんでした';

  @override
  String get cameraCouldNotSaveRecordingMessage => '録画を保存できませんでした';

  @override
  String get cameraCouldNotSaveCaptureMessage =>
      '撮影データを保存できませんでした。もう一度保存できるよう、データは残っています。';

  @override
  String get cameraNotEnoughVaultSpaceMessage =>
      '保管庫の空き容量が不足しています。空き容量を確保してから、もう一度お試しください。';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return '録画を保存できませんでした: $error';
  }

  @override
  String get cameraCouldNotSwitchLensMessage => 'レンズを切り替えられませんでした';

  @override
  String get cameraEncryptingPhotoLabel => '写真を暗号化中…';

  @override
  String get cameraEncryptingVideoLabel => '動画を暗号化中…';

  @override
  String get aboutApplicationSectionHeader => 'アプリケーション';

  @override
  String get aboutTagline => '無料・オープンソース・オフライン暗号化保管庫';

  @override
  String get aboutVersionTitle => 'バージョン';

  @override
  String aboutVersionSubtitle(String version) {
    return 'v$version';
  }

  @override
  String get aboutWhatsNewTitle => '新機能';

  @override
  String get aboutWhatsNewSubtitle => '最近の変更点とリリースノートを見る';

  @override
  String get aboutPrivacySecurityTitle => 'プライバシーとセキュリティ';

  @override
  String get aboutPrivacySecuritySubtitle => 'ネットワークアクセスなし、復号はメモリ内で行われます';

  @override
  String get aboutSupportedFormatsSectionHeader => '対応形式';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt および LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      '標準・隠しボリューム、カスタムPIM、キーファイル、xts-plain64、Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker および BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle => 'ユーザーパスフレーズおよび48桁の数値回復キーに対応';

  @override
  String get aboutDirectoryVaultsTitle => 'フォルダ保管庫';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator（v7/v8 SIV_GCM および SIV_CTRMAC）、gocryptfs（v2 AES-GCM および XChaCha20）、CryFS（v0.10+ XChaCha20 および AES）';

  @override
  String get aboutVhdTitle => '仮想ハードディスク（VHD / VHDX）';

  @override
  String get aboutVhdSubtitle => '固定・可変拡張ディスクイメージ向けのBAT変換';

  @override
  String get aboutNativeCoreEngineSectionHeader => 'ネイティブコアエンジン';

  @override
  String get aboutCompiledLibrariesTitle => 'コンパイル済みC++ライブラリ';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.7（ARMv8ハードウェア暗号化 & SHA-2）\n• libavif & libgav1（ネイティブAVIF画像デコーダー）\n• libarchive v3.8.9（ZIP、7-Zip、RAR、TARアーカイブエンジン）\n• ChaN FatFs v4.0.4（FAT12/16/32 & exFAT）\n• Tuxera NTFS-3G & 組み込みmkntfs\n• e2fsprogs v1.47.4 libext2fs（ext2/ext3/ext4）\n• Dislocker Virtual I/O（BitLocker FVE / To Go）\n• VeraCrypt 1.26.29（Twofish、Serpent、Camellia、Kuznyechik、Whirlpool、Streebog、BLAKE2s、Argon2id/i）\n• cJSON v1.7.18（LUKS2 & Cryptomatorのメタデータ）';

  @override
  String get aboutCommunitySectionHeader => 'コミュニティとオープンソース';

  @override
  String get aboutReportIssueTitle => '問題を報告';

  @override
  String get aboutReportIssueSubtitle => 'バグを見つけましたか？GitHubで報告してください';

  @override
  String get reportIssueSheetTitle => '問題を報告';

  @override
  String get reportIssueSheetSubtitle =>
      '問題に最も近い項目を選んでください。GitHubの入力済みフォームが開きます';

  @override
  String get reportIssueBugTitle => 'バグ報告';

  @override
  String get reportIssueBugSubtitle => 'クラッシュした、または正しく動作しない';

  @override
  String get reportIssueContainerTitle => 'コンテナ／ボールトの問題';

  @override
  String get reportIssueContainerSubtitle => 'アンロック、マウント、または形式固有の問題';

  @override
  String get reportIssueFeatureTitle => '機能リクエスト';

  @override
  String get reportIssueFeatureSubtitle => 'アイデアや改善案を提案する';

  @override
  String get reportIssueOtherTitle => 'その他';

  @override
  String get reportIssueOtherSubtitle => 'GitHubのすべてのテンプレートを見る';

  @override
  String get aboutContributorsTitle => 'コントリビューター';

  @override
  String get aboutContributorsSubtitle => 'VaultExplorerの開発に協力してくれた人々';

  @override
  String get aboutLicensesTitle => 'オープンソースライセンス';

  @override
  String get aboutLicensesSubtitle => 'このアプリで使用されているサードパーティライブラリ';

  @override
  String get aboutFooterMadeWithLove => 'プライバシーのために❤を込めて。';

  @override
  String get aboutVersionCopiedMessage => 'バージョン情報をコピーしました — バグレポートに便利です';

  @override
  String aboutVersionClipboardText(String version) {
    return 'VaultExplorer v$version (Android)';
  }

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer — Android向けの無料・オープンソース・オフライン保管庫。\n\nパスワード、メモ、ファイルを暗号化コンテナ（VeraCrypt、LUKS、BitLocker、Cryptomator、Gocryptfs、CryFS）内に保存できます。\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage => '共有可能なリンクをクリップボードにコピーしました';

  @override
  String get aboutPrivacySheetTitle => 'プライバシーとデータセキュリティ';

  @override
  String get aboutPrivacySheetSubtitle => '100%オフライン、ローカルメモリでのセキュリティ設計';

  @override
  String get privacyPointNoNetworkTitle => 'ネットワークアクセス不要';

  @override
  String get privacyPointNoNetworkBody =>
      'VaultExplorerはAndroidでandroid.permission.INTERNET権限を要求しません。いかなるネットワークとも通信できません。';

  @override
  String get privacyPointNoDiskLeaksTitle => 'メモリ内で復号';

  @override
  String get privacyPointNoDiskLeaksBody =>
      '復号と再暗号化はシステムメモリ内で行われます。ビデオ録画やエクスポートなど、一時ファイルが必要な一部の操作では、アプリ専用のストレージにそれを保持し、完了後にゼロで上書きします。';

  @override
  String get privacyPointNoAnalyticsTitle => '分析・テレメトリなし';

  @override
  String get privacyPointNoAnalyticsBody =>
      'クラッシュレポート、利用状況の追跡、あなたやあなたのデバイスに関するデータを収集するサードパーティ製SDKは一切ありません。';

  @override
  String get privacyPointKeystoreTitle => '秘密情報はAndroid Keystore内に保持';

  @override
  String get privacyPointKeystoreBody =>
      '記憶されたパスワード、パターン、キャッシュされた導出鍵は、Android Keystoreに保管された鍵を使ってAES-GCMで暗号化されます（対応する端末ではハードウェアに支えられます）。';

  @override
  String get privacyPointPosixTitle => 'POSIXアクセラレーションとストレージアクセス';

  @override
  String get privacyPointPosixBody =>
      'フォルダ保管庫内のファイルは、可能な場合は直接読み書きされ、大きなフォルダに対して低速なAndroidのSAF層を回避します。';

  @override
  String get privacyPointScreenClipboardTitle => '画面とクリップボードの保護';

  @override
  String get privacyPointScreenClipboardBody =>
      'タスク切り替えプレビューのブロックと任意のスクリーンショットブロック（FLAG_SECURE）に加え、ウィンドウがフォーカスされた際に破損したクリップボードを自動的にサニタイズします。アイテムボールトからコピーされたパスワードはAndroid 13以降で機密情報としてマークされ、未使用の場合は30秒後に自動的に消去されます。';

  @override
  String get privacyPointMaskModeTitle => 'マスクモード';

  @override
  String get privacyPointMaskModeBody =>
      'アプリを、動作するローカルファイルマネージャーとして異なるアイコンと名前で偽装できます（任意）。タイトルを2秒間長押しすると、実際の保管庫にアクセスできます。';

  @override
  String get privacyPointExternalLinksTitle => '外部リンクはブラウザで開きます';

  @override
  String get privacyPointExternalLinksBody =>
      'リンクをタップすると、その処理はデフォルトのブラウザアプリに引き渡されます。';

  @override
  String get truncatedListingWarning =>
      '最初の50,000件を表示しています — このフォルダにはさらに多くのファイルがあります。';

  @override
  String get gridCornerStyleLabel => 'サムネイルの角';

  @override
  String get gridCornerRoundedLabel => '角丸';

  @override
  String get gridCornerSquareLabel => '四角';

  @override
  String get gridSpacingLabel => 'サムネイルの間隔';

  @override
  String get gridSpacingNone => 'なし';

  @override
  String gridSpacingValue(int value) {
    return '$value dp';
  }

  @override
  String get thumbnailAutoSizeLabel => 'グリッドのセルサイズに合わせる';

  @override
  String get thumbnailAutoSizeDescription =>
      'グリッドおよびメイソンリー表示のサムネイルは各セルの画面表示サイズに合わせて生成されるため、列数を減らすとより鮮明なサムネイルになります。それ以外の場所では以下のサイズが使用されます。';

  @override
  String thumbnailQualityAutoSummary(int quality) {
    return '自動サイズ · 品質 $quality%';
  }

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '${size}px・画質$quality%';
  }

  @override
  String holdToSpeedIndicatorLabel(String speed) {
    return '$speed倍速';
  }

  @override
  String get toolbarLayoutSectionHeader => 'ツールバーのレイアウト';

  @override
  String get listViewOptionsSectionHeader => 'リスト表示のオプション';

  @override
  String get detailedListViewColumnsSectionHeader => '詳細リスト表示の列';

  @override
  String get galleryGridViewSectionHeader => 'ギャラリーグリッド表示';

  @override
  String get browserLayoutSectionHeader => 'ブラウザのレイアウト';

  @override
  String get mediaViewerSectionHeader => 'メディアビューア';

  @override
  String get viewModeAction => '表示モード';

  @override
  String get sortAction => '並べ替え';

  @override
  String get playMediaAction => 'メディアを再生';

  @override
  String containerSpaceSummary(String free, String total) {
    return '$free 空き / $total';
  }

  @override
  String volMountedSummary(int volId) {
    return 'ボリューム$volId・マウント中';
  }

  @override
  String vaultOccupiedSpaceSummary(String used) {
    return '使用済み$used';
  }

  @override
  String get incorrectPasswordOrKeyfilesDriveError =>
      'パスワード/キーファイルが正しくないか、サポートされていないドライブです';

  @override
  String driveUsableCapacity(int mb) {
    return 'ドライブの使用可能容量: $mb MB。これを超えないようにしてください。';
  }

  @override
  String get unlockMethodManualPassword => '手動パスワード';

  @override
  String get unlockMethodRememberPassword => 'パスワードを記憶';

  @override
  String get unlockMethodBiometrics => '生体認証によるロック解除';

  @override
  String get unlockMethodPattern => 'パターンによるロック解除';

  @override
  String get unlockMethodPin => 'PINによるロック解除';

  @override
  String get unlockMethodSubtitlePassword => '毎回パスワードを入力します';

  @override
  String get unlockMethodSubtitleRememberPassword =>
      'Android Keystoreに安全に保存されます';

  @override
  String get unlockMethodSubtitleBiometrics => '指紋または顔でロックを解除します';

  @override
  String get unlockMethodSubtitlePattern => 'パターンを描いてロックを解除します';

  @override
  String get unlockMethodSubtitlePin => 'PINを入力してロックを解除します';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError => '動画デコーダーを利用できません — ハードウェアコーデックの競合';

  @override
  String get mediaStreamInitFailedError => 'メディアストリームの初期化に失敗しました';

  @override
  String get invalidAvifImage => '無効なAVIF画像です';

  @override
  String get verbImport => 'インポート';

  @override
  String get verbExport => 'エクスポート';

  @override
  String get verbMove => '移動';

  @override
  String get verbCopy => 'コピー';

  @override
  String get verbDelete => '削除';

  @override
  String get verbImported => 'インポート済み';

  @override
  String get verbExported => 'エクスポート済み';

  @override
  String get verbMoved => '移動済み';

  @override
  String get verbCopied => 'コピー済み';

  @override
  String get verbDeleted => '削除済み';

  @override
  String get verbImporting => 'インポート中';

  @override
  String get verbExporting => 'エクスポート中';

  @override
  String get verbMoving => '移動中';

  @override
  String get verbCopying => 'コピー中';

  @override
  String get verbDeleting => '削除中';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のアイテム',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のアイテムを$verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return '$count件スキップ';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return '$count件失敗';
  }

  @override
  String get statusCancelled => 'キャンセル済み';

  @override
  String get statusFailed => '失敗';

  @override
  String get statusCompleted => '完了';

  @override
  String get fileOpCheckingSpace => '空き容量を確認しています…';

  @override
  String get fileOpResolvingConflicts => '競合を解決しています…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return '空き容量が不足しています — 必要:$required、空き:$freeのみ';
  }

  @override
  String get fileOpDiskFullPartialRemoved => 'ディスクがいっぱいです — 一部のファイルを削除しました';

  @override
  String get fileOpMoveFailed => '移動に失敗しました';

  @override
  String get fileOpCopyFailed => 'コピーに失敗しました';

  @override
  String get fileOpDeleteFailed => '削除に失敗しました';

  @override
  String get fileOpDiskFull => 'ディスクがいっぱいです';

  @override
  String get fileOpImporting => 'インポート中…';

  @override
  String get fileOpExporting => 'エクスポート中…';

  @override
  String fileOpImportingName(String name) {
    return '$nameをインポート中…';
  }

  @override
  String fileOpExportingName(String name) {
    return '$name をエクスポート中…';
  }

  @override
  String fileOpMovingName(String name) {
    return '$nameを移動中…';
  }

  @override
  String fileOpCopyingName(String name) {
    return '$nameをコピー中…';
  }

  @override
  String get fileOpDeleting => '削除中…';

  @override
  String fileOpDeletingName(String name) {
    return '$nameを削除中…';
  }

  @override
  String fileOpDeletedSoFar(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件削除しました',
    );
    return '$_temp0';
  }

  @override
  String get searchInSubfoldersHint => 'すべてのサブフォルダを検索…';

  @override
  String get deepSearchEnabledTooltip => 'サブフォルダを検索中 — タップで現在のフォルダのみに切り替え';

  @override
  String get deepSearchDisabledTooltip => '現在のフォルダを検索中 — タップでサブフォルダも検索';

  @override
  String get filterAction => 'フィルター';

  @override
  String get bookmarkAction => 'ブックマーク';

  @override
  String get unbookmarkAction => 'ブックマーク解除';

  @override
  String get bookmarkSelectedAction => '選択項目をブックマーク';

  @override
  String get unbookmarkSelectedAction => '選択項目のブックマークを解除';

  @override
  String bookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件をブックマークしました',
    );
    return '$_temp0';
  }

  @override
  String unbookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のブックマークを解除しました',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => 'ブックマークバーを表示';

  @override
  String get showBookmarkBarDesc => 'ブックマークバーまたはサイドバーにブックマーク済みアイテムを表示します';

  @override
  String get bookmarkBarSectionHeader => 'ブックマークバー';

  @override
  String get noBookmarksYet => 'まだブックマークされたアイテムがありません';

  @override
  String get reorderBookmarksTitle => 'ブックマークを並べ替え';

  @override
  String get reorderBookmarksDesc => 'アイテムをドラッグしてブックマークバー内の順序を変更します';

  @override
  String get drawerBookmarksSectionTitle => 'ブックマーク';

  @override
  String get openAction => '開く';

  @override
  String get bookmarkTargetMissing => 'ブックマークした項目は存在しなくなりました';

  @override
  String get navBarVaultsLabel => 'ボールト';

  @override
  String get navBarToolsLabel => 'ツール';

  @override
  String get toolsScreenTitle => 'ツール';

  @override
  String get toolsSectionContainerUtilities => 'コンテナユーティリティ';

  @override
  String get toolsSectionFileCryptography => 'ファイル暗号化';

  @override
  String get toolsSectionStorageDiagnostics => 'ストレージと診断';

  @override
  String get toolContainerSplitterTitle => '分割と結合';

  @override
  String get toolContainerSplitterSubtitle => 'コンテナを分割、または結合します';

  @override
  String get toolContainerRepairTitle => '確認と修復';

  @override
  String get toolContainerRepairSubtitle => 'ヘッダーまたはファイルシステムの問題を診断します';

  @override
  String get toolSingleFileCryptoTitle => 'ファイルの暗号化／復号';

  @override
  String get toolSingleFileCryptoSubtitle => 'コンテナ全体を使わずに1つ以上のファイルを保護します';

  @override
  String get toolStorageAnalyzerTitle => 'ストレージ分析';

  @override
  String get toolStorageAnalyzerSubtitle => 'マウント中の保管庫で何が容量を占めているか確認します';

  @override
  String get toolDuplicateFinderTitle => '重複ファイル検出';

  @override
  String get toolDuplicateFinderSubtitle => 'バイト単位で同一の重複ファイルを検出・削除して容量を回収します';

  @override
  String get toolHashVerifierTitle => 'ファイルチェックサム・ハッシュ検証';

  @override
  String get toolHashVerifierSubtitle => 'MD5/SHAチェックサムで大きなファイルが破損していないか確認します';

  @override
  String get hashVerifierModeCompute => '計算';

  @override
  String get hashVerifierModeVerify => '検証';

  @override
  String get hashVerifierSelectSourceTitle => 'ファイルソースを選択';

  @override
  String get hashVerifierAlgorithmsLabel => 'アルゴリズム';

  @override
  String get hashVerifierNoAlgorithmSelected => '少なくとも1つのアルゴリズムを選択してください';

  @override
  String get hashVerifierFilesLabel => 'ハッシュ化するファイル';

  @override
  String hashVerifierFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイルを選択中',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierComputeButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のハッシュを計算',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCancelButton => 'キャンセル';

  @override
  String hashVerifierBatchProgressLabel(Object current, Object total) {
    return 'ファイル $current/$total';
  }

  @override
  String get hashVerifierCancelledMessage => 'キャンセルしました。';

  @override
  String hashVerifierComputeErrorsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイルのハッシュ化に失敗しました',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCopiedMessage => 'クリップボードにコピーしました';

  @override
  String get hashVerifierExportManifestButton => 'マニフェストとしてエクスポート';

  @override
  String get hashVerifierExportAlgorithmLabel => 'マニフェストのアルゴリズム';

  @override
  String hashVerifierExportSuccessMessage(Object path) {
    return '$pathに保存しました';
  }

  @override
  String hashVerifierExportFailedMessage(Object error) {
    return 'エクスポートに失敗しました: $error';
  }

  @override
  String get hashVerifierLoadManifestButton => 'マニフェストを読み込む';

  @override
  String get hashVerifierChangeManifestButton => '変更';

  @override
  String get hashVerifierManifestLabel => 'マニフェストファイル';

  @override
  String hashVerifierManifestEntryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件のエントリ',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierAutoAddFolderButton => 'このフォルダのすべてのファイルを追加';

  @override
  String get hashVerifierAddFilesToVerifyButton => '検証するファイルを追加';

  @override
  String get hashVerifierVerifyAllButton => 'すべて検証';

  @override
  String hashVerifierVerifyProgressLabel(Object current, Object total) {
    return 'ファイル $current/$total を検証中';
  }

  @override
  String hashVerifierSummaryMessage(
    Object ok,
    Object mismatch,
    Object missing,
  ) {
    return '一致$ok件、不一致$mismatch件、未検出$missing件';
  }

  @override
  String get hashVerifierStatusMatch => '一致';

  @override
  String get hashVerifierStatusMismatch => '不一致';

  @override
  String get hashVerifierStatusMissing => 'ファイル未追加';

  @override
  String get hashVerifierStatusPending => '未検証';

  @override
  String get hashVerifierExpectedLabel => '期待値';

  @override
  String get hashVerifierActualLabel => '実際の値';

  @override
  String hashVerifierExtraFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'マニフェストに記載のないファイルが$count個あります',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierNoManifestLoadedMessage =>
      '開始するにはマニフェストファイルを読み込んでください';

  @override
  String get hashVerifierManifestParseEmptyMessage =>
      'このファイルにはチェックサムのエントリが見つかりませんでした';

  @override
  String hashVerifierLoadManifestFailedMessage(Object error) {
    return 'マニフェストを読み込めませんでした: $error';
  }

  @override
  String hashVerifierAutoAddedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '保管庫フォルダから$count個のファイルを追加しました',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierModeVault => '保管庫';

  @override
  String get hashVerifierVaultPickerLabel => '保管庫';

  @override
  String get hashVerifierVaultNoVaultsMessage => '現在マウントされている保管庫はありません';

  @override
  String get hashVerifierCheckEntireVaultButton => '保管庫全体を確認';

  @override
  String get hashVerifierVaultScanningLabel => '保管庫をスキャン中…';

  @override
  String hashVerifierVaultFilesDiscoveredLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイルを検出',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmTitle => '保管庫全体を確認しますか？';

  @override
  String hashVerifierVaultConfirmFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイル',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmWarning => 'この保管庫内のすべてのファイルが読み込まれます。';

  @override
  String get hashVerifierVaultEmptyMessage => 'この保管庫には確認するファイルがありません';

  @override
  String get hashVerifierVaultStartButton => '確認を開始';

  @override
  String hashVerifierVaultHashingProgressLabel(Object current, Object total) {
    return '確認中 $current / $total';
  }

  @override
  String get hashVerifierVaultCompleteTitle => '保管庫の確認が完了しました';

  @override
  String hashVerifierVaultCompleteFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイルを確認',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteBytesLabel(Object size) {
    return '$sizeを処理';
  }

  @override
  String hashVerifierVaultCompleteSucceededLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '成功$count件',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '失敗$count件',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultElapsedLabel(Object time) {
    return '経過時間: $time';
  }

  @override
  String get hashVerifierVaultCancelledMessage => '保管庫の確認をキャンセルしました。';

  @override
  String hashVerifierVaultFailedMessage(Object error) {
    return '保管庫の確認に失敗しました: $error';
  }

  @override
  String get hashVerifierVaultNewCheckButton => '新しい確認';

  @override
  String get hashVerifierVaultActionComputeTitle => '保管庫全体を計算';

  @override
  String get hashVerifierVaultActionComputeSubtitle => '保管庫内のすべてのファイルをハッシュ化します';

  @override
  String get hashVerifierVaultActionVerifyTitle => '保管庫全体を検証';

  @override
  String get hashVerifierVaultActionVerifySubtitle =>
      '読み込んだマニフェストと保管庫内のすべてのファイルを照合します';

  @override
  String get hashVerifierVaultChangeActionButton => '変更';

  @override
  String get hashVerifierVaultVerifyButton => '保管庫全体を検証';

  @override
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage =>
      '保管庫全体を検証するには、保管庫内から読み込んだマニフェストが必要です。';

  @override
  String get duplicateFinderTargetLabel => '対象の保管庫';

  @override
  String get duplicateFinderTargetAllVaults => '開いているすべての保管庫';

  @override
  String get duplicateFinderStartScan => 'スキャンを開始';

  @override
  String get duplicateFinderCancelScan => 'スキャンをキャンセル';

  @override
  String get duplicateFinderRescan => '再スキャン';

  @override
  String get duplicateFinderScanningStage1 => 'ステージ1：インデックス作成とサイズによるグループ化...';

  @override
  String get duplicateFinderScanningStage2 => 'ステージ2：部分ファイルヘッダーの確認...';

  @override
  String get duplicateFinderScanningStage3 => 'ステージ3：完全なバイトハッシュの検証...';

  @override
  String get duplicateFinderScanComplete => 'スキャン完了';

  @override
  String get duplicateFinderNoDuplicatesTitle => '重複ファイルは見つかりませんでした';

  @override
  String get duplicateFinderNoDuplicatesMessage =>
      'スキャンした保管庫内のすべてのファイルは、一意のバイト内容を含んでいます。';

  @override
  String get duplicateFinderSelectRedundant => '重複コピーを選択';

  @override
  String get duplicateFinderSelectAll => 'すべて選択';

  @override
  String get duplicateFinderDeselectAll => '選択を解除';

  @override
  String get duplicateFinderOriginalLabel => 'オリジナル';

  @override
  String get duplicateFinderDuplicateLabel => '重複';

  @override
  String get duplicateFinderConfirmDeleteTitle => '重複ファイルを削除しますか？';

  @override
  String get duplicateFinderSearchHint => 'ファイル名またはパスで重複を検索...';

  @override
  String get toolNotImplementedYetMessage =>
      'このツールはまだネイティブエンジンに接続されていません — 今後のアップデートをお待ちください。';

  @override
  String get splitJoinModeSplit => '分割';

  @override
  String get splitJoinModeJoin => '結合';

  @override
  String get splitSourceFileLabel => '元のファイル';

  @override
  String get splitDestinationFolderLabel => '保存先フォルダ';

  @override
  String get splitChunkSizeLabel => '分割サイズ';

  @override
  String get splitChunkSizeCustomLabel => 'カスタムサイズ（MB）';

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
  String get splitChunkSizeCustom => 'カスタム';

  @override
  String get splitContainerButton => 'コンテナを分割';

  @override
  String get joinFirstPartLabel => '最初のパート';

  @override
  String get joinOutputFileNameLabel => '出力ファイル名';

  @override
  String get joinContainerButton => 'ファイルを結合';

  @override
  String get chooseFileButton => 'ファイルを選択';

  @override
  String get chooseFolderButton => 'フォルダを選択';

  @override
  String get noFileSelectedLabel => 'ファイルが選択されていません';

  @override
  String get noFolderSelectedLabel => 'フォルダが選択されていません';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage => 'コンテナの分割に成功しました';

  @override
  String get joinContainerSuccessMessage => 'ファイルの結合に成功しました';

  @override
  String get cryptoDirectionEncrypt => '暗号化';

  @override
  String get cryptoDirectionDecrypt => '復号';

  @override
  String get singleFileCryptoInputFileLabel => '入力ファイル';

  @override
  String get singleFileCryptoCipherLabel => '暗号方式';

  @override
  String get singleFileCryptoDeleteOriginalLabel => '暗号化後に元のファイルを削除';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイルを暗号化',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイルを復号',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '完了 — $count個のファイルを処理しました',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return '$total個中$succeeded個のファイルを処理しました — $failed個失敗';
  }

  @override
  String get singleFileCryptoAddFilesButton => 'ファイルを追加';

  @override
  String get singleFileCryptoClearFilesButton => 'クリア';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個のファイルを選択中',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return 'ファイル $current/$total';
  }

  @override
  String get repairTargetStepTitle => '対象を選択';

  @override
  String get repairTargetUnmountedFileOption => 'アンマウント状態のファイル';

  @override
  String get repairTargetUnmountedFileSubtitle =>
      'まだ開いていないコンテナのバックアップヘッダーを復元します';

  @override
  String get repairTargetMountedVolumeSubtitle =>
      'すでに開いている保管庫でファイルシステムチェックを実行します';

  @override
  String get repairNoMountedVolumes => '現在マウントされている保管庫はありません';

  @override
  String get repairScanButton => '診断スキャンを実行';

  @override
  String get repairChangeTargetButton => '対象を変更';

  @override
  String get repairDiagnosisHealthy => '問題は見つかりませんでした';

  @override
  String get repairDiagnosisHeaderCorrupted => 'ヘッダーが破損しています';

  @override
  String get repairDiagnosisFilesystemDirty => 'ファイルシステムが不整合／正常にアンマウントされていません';

  @override
  String get repairRestoreBackupHeaderButton => 'バックアップヘッダーを復元';

  @override
  String get repairRunFilesystemCheckButton => 'ファイルシステムのチェックと修正を実行';

  @override
  String get repairActionSucceededMessage => '修復が正常に完了しました';

  @override
  String get repairActionFailedMessage => '修復アクションは成功しませんでした';

  @override
  String get storageAnalyzerTargetLabel => 'ボリューム';

  @override
  String get storageAnalyzerNoTargetsTitle => '分析対象がありません';

  @override
  String get storageAnalyzerNoTargetsMessage =>
      'まず保管庫をマウントしてから、ここに戻ってストレージの内訳を確認してください。';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return '$total中$usedを使用';
  }

  @override
  String get storageAnalyzerHeaviestFilesHeader => '容量の大きいファイル';

  @override
  String get storageAnalyzerBreakdownHeader => 'ファイル種類別';

  @override
  String get storageAnalyzerScanningMessage => 'ボリュームをスキャン中…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return '$count件のファイルでスキャンが早期終了しました — 結果は不完全な可能性があります。';
  }

  @override
  String get storageAnalyzerNoFilesFound => 'ファイルが見つかりません';

  @override
  String get storageCategoryImages => '画像';

  @override
  String get storageCategoryVideos => '動画';

  @override
  String get storageCategoryAudio => '音声';

  @override
  String get storageCategoryDocuments => 'ドキュメント';

  @override
  String get storageCategoryArchives => 'アーカイブ';

  @override
  String get storageCategoryOther => 'その他';

  @override
  String get keyfilePassphraseGeneratorTitle => 'キーファイル・パスフレーズ生成ツール';

  @override
  String get keyfilePassphraseGeneratorSubtitle =>
      'Dicewareパスフレーズ、カスタムパスワード、高エントロピーのキーファイルを生成します';

  @override
  String get tabPassphrase => 'パスフレーズ';

  @override
  String get tabKeyfile => 'キーファイル';

  @override
  String get modeDiceware => 'Dicewareパスフレーズ';

  @override
  String get modeCustomPassword => 'カスタムパスワード';

  @override
  String get keyfileTypeBinary => 'バイナリキーファイル（.key）';

  @override
  String get keyfileTypeImage => 'ノイズ画像キーファイル（.png）';

  @override
  String get copyPassphraseSuccess => 'パスフレーズを機密クリップボードにコピーしました';

  @override
  String get copyFingerprintSuccess => 'SHA-256フィンガープリントをクリップボードにコピーしました';

  @override
  String get saveKeyfileToVault => 'マウント中の保管庫に保存';

  @override
  String get exportKeyfileToStorage => 'デバイスストレージにエクスポート';

  @override
  String get keyfileNoOpenVaultsMessage => '開いている保管庫がありません。先に保管庫をマウントしてください。';

  @override
  String get keyfileSelectDestinationVaultTitle => '保存先の保管庫を選択';

  @override
  String keyfileVolumeIdLabel(Object volId) {
    return 'ボリュームID: $volId';
  }

  @override
  String keyfileExportSuccessMessage(Object path) {
    return 'キーファイルを$pathにエクスポートしました';
  }

  @override
  String keyfileExportFailedMessage(Object error) {
    return 'エクスポートに失敗しました: $error';
  }

  @override
  String keyfileSavedToVaultMessage(Object vaultName, Object path) {
    return 'キーファイルを$vaultNameに保存しました: $path';
  }

  @override
  String get keyfileWriteFailedMessage => 'キーファイルを保管庫に書き込めませんでした';

  @override
  String keyfileSaveErrorMessage(Object error) {
    return '保管庫への保存エラー: $error';
  }

  @override
  String get passphraseGeneratedSecretLabel => '生成されたシークレット';

  @override
  String get copyToClipboardTooltip => 'クリップボードにコピー';

  @override
  String get generateNewTooltip => '新規生成';

  @override
  String get passphraseStrengthWeak => '弱い';

  @override
  String get passphraseStrengthGood => '良好';

  @override
  String get passphraseStrengthStrong => '強い';

  @override
  String get passphraseStrengthUnbreakable => '解読不能';

  @override
  String get passphraseCrackTimeInstant => '1秒未満';

  @override
  String get passphraseCrackTimeShort => '数日～数か月';

  @override
  String get passphraseCrackTimeCenturies => '数世紀';

  @override
  String get passphraseCrackTimeMillionsOfYears => '数百万年';

  @override
  String passphraseStrengthLabel(Object label) {
    return '強度: $label';
  }

  @override
  String passphraseEntropyBitsLabel(Object bits) {
    return 'エントロピー$bitsビット';
  }

  @override
  String passphraseCrackTimeLabel(Object crackTime) {
    return '推定解読時間: $crackTime';
  }

  @override
  String get dicewareOptionsTitle => 'EFF Dicewareオプション';

  @override
  String dicewareWordCountLabel(Object count) {
    return '単語数: $count語';
  }

  @override
  String dicewareWordCountBitsLabel(Object bits) {
    return '$bitsビット';
  }

  @override
  String dicewareWordCountSliderLabel(Object count) {
    return '$count語';
  }

  @override
  String get dicewareWordSeparatorLabel => '単語の区切り文字';

  @override
  String get dicewareSeparatorHyphen => 'ハイフン（-）';

  @override
  String get dicewareSeparatorSpace => 'スペース（　）';

  @override
  String get dicewareSeparatorUnderscore => 'アンダースコア（_）';

  @override
  String get dicewareSeparatorDot => 'ドット（.）';

  @override
  String get dicewareSeparatorSlash => 'スラッシュ（/）';

  @override
  String get dicewareWordCasingLabel => '単語の大文字・小文字';

  @override
  String get dicewareCasingLowercase => '小文字';

  @override
  String get dicewareCasingTitleCase => 'タイトルケース';

  @override
  String get dicewareCasingUppercase => '大文字';

  @override
  String get dicewareAppendDigitLabel => 'ランダムな数字を追加（0～9）';

  @override
  String get dicewareAppendSymbolLabel => 'ランダムな記号を追加（!@#\$%）';

  @override
  String get customPasswordOptionsTitle => 'カスタムパスワードのオプション';

  @override
  String customPasswordLengthLabel(Object length) {
    return '長さ: $length文字';
  }

  @override
  String customPasswordLengthSliderLabel(Object length) {
    return '$length文字';
  }

  @override
  String get customPasswordUppercaseLabel => '大文字（A～Z）';

  @override
  String get customPasswordLowercaseLabel => '小文字（a～z）';

  @override
  String get customPasswordNumbersLabel => '数字（0～9）';

  @override
  String get customPasswordSymbolsLabel => '記号（!@#\$%^&*）';

  @override
  String get customPasswordExcludeAmbiguousLabel => '紛らわしい文字を除外（1、l、I、0、O）';

  @override
  String get keyfileBinarySizeTitle => 'バイナリキーファイルのサイズ';

  @override
  String get keyfileImageResolutionTitle => 'ノイズ画像の解像度';

  @override
  String get keyfilePresetBytes64 => '64バイト（VeraCrypt標準）';

  @override
  String get keyfilePresetBytes256 => '256バイト';

  @override
  String get keyfilePresetBytes2048 => '2KB';

  @override
  String get keyfilePresetBytes64kb => '64KB';

  @override
  String get keyfilePresetBytes1mb => '1MB（最大境界）';

  @override
  String get keyfilePresetRes64 => '64×64ピクセル（約16KB）';

  @override
  String get keyfilePresetRes256 => '256×256ピクセル（約256KB）';

  @override
  String get keyfilePresetRes512 => '512×512ピクセル（約1MB）';

  @override
  String get keyfileGenerateNewTooltip => '新しいキーファイルを生成';

  @override
  String keyfileSizeLabel(Object size) {
    return 'サイズ: $size';
  }

  @override
  String get keyfileFingerprintLabel => 'SHA-256フィンガープリント';

  @override
  String get keyfileCopyFingerprintTooltip => 'フィンガープリントをコピー';

  @override
  String get duplicateFinderNoVaultsTitle => 'マウントされた保管庫がありません';

  @override
  String get duplicateFinderNoVaultsMessage =>
      '重複ファイルをスキャンするには、少なくとも1つの保管庫コンテナのロックを解除してマウントしてください。';

  @override
  String duplicateFinderConfirmDeleteMessage(Object count, Object size) {
    return '保管庫から$count個の重複ファイル（$size）を完全に削除してもよろしいですか？この操作は元に戻せません。';
  }

  @override
  String get duplicateFinderDeletePermanentlyButton => '完全に削除';

  @override
  String duplicateFinderDeleteSuccessMessage(Object count) {
    return '$count個の重複ファイルを正常に削除しました。';
  }

  @override
  String get duplicateFinderIntroTitle => '3段階バイト一致検出';

  @override
  String get duplicateFinderIntroSubtitle => 'ファイル名に関係なく、完全に同一の内容を検出します。';

  @override
  String get duplicateFinderStagesDescription =>
      '• ステージ1：サイズによるグループ化（即時のメタデータ走査）\n• ステージ2：部分ヘッダーの確認（16KBのSHA-256ヘッダー）\n• ステージ3：完全なハッシュ検証（正確なSHA-256バイト一致）';

  @override
  String get duplicateFinderScanningVaultFallback => '保管庫をスキャン中...';

  @override
  String duplicateFinderProcessingFileLabel(Object fileName) {
    return '処理中: $fileName';
  }

  @override
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  ) {
    return 'スキャン済みファイル: $scanned | 検出された重複: $groupsグループ（$saved）';
  }

  @override
  String duplicateFinderGroupsFoundLabel(Object count) {
    return '$count件の重複グループが見つかりました';
  }

  @override
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved) {
    return '$copies件のコピーを検出 • $savedのストレージを節約可能';
  }

  @override
  String duplicateFinderVaultsSelectedLabel(Object count) {
    return '$count個の保管庫を選択中';
  }

  @override
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  ) {
    return 'グループ$groupIndex：$size（$count件のコピーを検出）';
  }

  @override
  String duplicateFinderRecoverableSpaceLabel(Object size) {
    return '回収可能な容量: $size';
  }

  @override
  String get duplicateFinderPreviewFileTooltip => 'ファイルをプレビュー';

  @override
  String duplicateFinderPreviewFailedMessage(Object fileName) {
    return '$fileNameのファイルプレビューを開けませんでした';
  }

  @override
  String duplicateFinderPreviewErrorMessage(Object error) {
    return 'ファイルのプレビュー中にエラーが発生しました: $error';
  }

  @override
  String duplicateFinderFilesSelectedLabel(Object count) {
    return '$count個のファイルを選択中';
  }

  @override
  String duplicateFinderBytesToBeFreedLabel(Object size) {
    return '$sizeを解放予定';
  }

  @override
  String duplicateFinderDeleteSelectedButton(Object count) {
    return '選択項目を削除（$count）';
  }

  @override
  String get vaultBrowserSwitchVaultTooltip => '保管庫を切り替え';

  @override
  String get vaultBrowserRootFolderLabel => 'ルートフォルダ';

  @override
  String vaultFilePickerTitle(Object vaultName) {
    return 'ファイルを選択（$vaultName）';
  }

  @override
  String get vaultFilePickerEmptyMessage => 'フォルダは空です';

  @override
  String vaultFilePickerConfirmButton(Object count) {
    return '$count個のファイルを選択';
  }

  @override
  String vaultFolderPickerTitle(Object vaultName) {
    return 'フォルダを選択（$vaultName）';
  }

  @override
  String get vaultFolderPickerEmptyMessage => 'ここにはサブフォルダがありません';

  @override
  String get vaultFolderPickerRootLabel => 'ルート';

  @override
  String get vaultFolderPickerConfirmRootButton => 'ルートフォルダを選択';

  @override
  String vaultFolderPickerConfirmNamedButton(Object folderName) {
    return '「$folderName」を選択';
  }

  @override
  String get singleFileCryptoSelectInputTitle => '入力ファイルを選択';

  @override
  String get singleFileCryptoFromDeviceTitle => 'デバイスストレージから';

  @override
  String get singleFileCryptoFromDeviceSubtitle =>
      'システムのファイル選択機能を使ってデバイスからファイルを選択します';

  @override
  String get singleFileCryptoFromVaultTitle => 'マウント中の保管庫から';

  @override
  String get singleFileCryptoFromVaultSubtitle => '開いている暗号化コンテナからファイルを選択します';

  @override
  String get singleFileCryptoSelectDestinationTitle => '保存先フォルダを選択';

  @override
  String get singleFileCryptoDeviceFolderTitle => 'デバイスストレージのフォルダ';

  @override
  String get singleFileCryptoDeviceFolderSubtitle => '出力をデバイスストレージ内のフォルダに保存します';

  @override
  String get singleFileCryptoVaultFolderTitle => 'マウント中の保管庫フォルダ';

  @override
  String get singleFileCryptoVaultFolderSubtitle => '出力を開いている暗号化コンテナ内に保存します';

  @override
  String get toolsSectionBackupSync => 'バックアップと同期';

  @override
  String get toolVaultSyncTitle => '保管庫の同期';

  @override
  String get toolVaultSyncSubtitle => '2つの保管庫を比較し、欠けているファイルや新しいファイルをコピーします';

  @override
  String get vaultSyncNoVaultsTitle => 'マウントされた保管庫がありません';

  @override
  String get vaultSyncNoVaultsMessage =>
      'ファイルを比較・同期するには、少なくとも1つの保管庫をマウントしてください。';

  @override
  String get vaultSyncLeftLabel => '左';

  @override
  String get vaultSyncRightLabel => '右';

  @override
  String get vaultSyncTapToSelect => 'タップして保管庫とフォルダを選択';

  @override
  String get vaultSyncSwapTooltip => '左右を入れ替え';

  @override
  String get vaultSyncSameLocationWarning => '左と右は異なるフォルダである必要があります。';

  @override
  String get vaultSyncIntroTitle => '2つの保管庫を比較';

  @override
  String get vaultSyncIntroSubtitle =>
      '左と右の保管庫（または同じ保管庫内の2つのフォルダ）を選択すると、それぞれの側で欠けている、変更されている、または新しいファイルを確認できます。';

  @override
  String get vaultSyncCompareButton => '比較';

  @override
  String get vaultSyncComparingLabel => '保管庫を比較中…';

  @override
  String vaultSyncCompareStatsLabel(Object dirs, Object entries) {
    return 'スキャン済みフォルダ: $dirs | 検出された差分: $entries';
  }

  @override
  String get vaultSyncCancelCompareButton => 'キャンセル';

  @override
  String get vaultSyncInSyncTitle => 'すでに同期済みです';

  @override
  String vaultSyncInSyncMessage(Object count) {
    return '一致する$count件のファイルはすべて両側で同一です。';
  }

  @override
  String get vaultSyncRecompareButton => '再比較';

  @override
  String vaultSyncDifferencesFoundLabel(Object count) {
    return '$count件の差分が見つかりました';
  }

  @override
  String vaultSyncInSyncCountLabel(Object count) {
    return '$count件のファイルはすでに両側で一致しています';
  }

  @override
  String vaultSyncBadgeOnlyLeft(Object count) {
    return '左のみ$count件';
  }

  @override
  String vaultSyncBadgeOnlyRight(Object count) {
    return '右のみ$count件';
  }

  @override
  String vaultSyncBadgeLeftNewer(Object count) {
    return '左が新しい$count件';
  }

  @override
  String vaultSyncBadgeRightNewer(Object count) {
    return '右が新しい$count件';
  }

  @override
  String vaultSyncBadgeConflicts(Object count) {
    return '確認が必要$count件';
  }

  @override
  String get vaultSyncDirectionLabel => '同期の方向';

  @override
  String get vaultSyncDirectionTwoWay => '双方向（推奨）';

  @override
  String get vaultSyncDirectionTwoWaySubtitle =>
      '各ファイルを、それが存在しないか古いコピーしかない側にコピーします';

  @override
  String get vaultSyncDirectionLeftToRight => '左 → 右（一方向）';

  @override
  String get vaultSyncDirectionLeftToRightSubtitle =>
      '新規および更新されたファイルを左から右へ送ります。左側は変更されません';

  @override
  String get vaultSyncDirectionRightToLeft => '右 → 左（一方向）';

  @override
  String get vaultSyncDirectionRightToLeftSubtitle =>
      '新規および更新されたファイルを右から左へ送ります。右側は変更されません';

  @override
  String get vaultSyncSearchHint => '差分を検索';

  @override
  String get vaultSyncStatusOnlyLeft => '左のみ';

  @override
  String get vaultSyncStatusOnlyRight => '右のみ';

  @override
  String get vaultSyncStatusLeftNewer => '左が新しい';

  @override
  String get vaultSyncStatusRightNewer => '右が新しい';

  @override
  String get vaultSyncStatusConflict => '確認が必要';

  @override
  String get vaultSyncStatusTypeMismatch => '種類が不一致';

  @override
  String get vaultSyncFolderOnlyLeftDetail => 'フォルダ — 左のみ';

  @override
  String get vaultSyncFolderOnlyRightDetail => 'フォルダ — 右のみ';

  @override
  String vaultSyncBothSidesDetail(
    Object leftSize,
    Object leftDate,
    Object rightSize,
    Object rightDate,
  ) {
    return '左: $leftSize · $leftDate  →  右: $rightSize · $rightDate';
  }

  @override
  String get vaultSyncTypeMismatchTooltip =>
      '片方がファイルでもう片方がフォルダです — ファイルブラウザで手動で解決してください';

  @override
  String get vaultSyncChangeActionTooltip => '同期アクションを変更';

  @override
  String get vaultSyncActionCopyToRight => 'コピー → 右';

  @override
  String get vaultSyncActionCopyToLeft => 'コピー → 左';

  @override
  String get vaultSyncActionSkip => 'スキップ';

  @override
  String vaultSyncChangesQueuedLabel(Object count) {
    return '$count件の変更がキュー登録済み';
  }

  @override
  String get vaultSyncSyncNowButton => '今すぐ同期';

  @override
  String get vaultSyncConfirmTitle => '同期を開始しますか？';

  @override
  String vaultSyncConfirmMessage(Object count, Object bytes) {
    return 'これにより、$count個の項目（合計$bytes）が両側の間でコピーされます。同名の既存ファイルは上書きされます。';
  }

  @override
  String vaultSyncStartedMessage(Object count) {
    return '同期を開始しました — $count件の項目をキューに登録しました';
  }

  @override
  String vaultSyncPickLocationTitle(Object side) {
    return '$sideの保管庫とフォルダを選択';
  }

  @override
  String get vaultSyncOverlapWarning =>
      'Left and Right must not be the same folder or nested inside each other.';

  @override
  String vaultSyncPlaintextWarning(Object targets) {
    return 'Files copied out of a vault to $targets will be stored unencrypted.';
  }

  @override
  String get vaultSyncStorageSelectorLabel => 'Storage';

  @override
  String get vaultSyncTargetKindVault => 'Encrypted vault';

  @override
  String get vaultSyncTargetKindDevice => 'Device storage · not encrypted';

  @override
  String get vaultSyncTargetKindProvider => 'Document provider · not encrypted';

  @override
  String get vaultSyncAddStorageTooltip => 'Add storage location';

  @override
  String get vaultSyncEnableLocalStorageTooltip =>
      'Enable Local Storage access';

  @override
  String get vaultSyncNoStoragesTitle => 'No storage to sync yet';

  @override
  String get vaultSyncNoStoragesMessage =>
      'Add a folder or document provider with the + button, or mount a vault.';

  @override
  String get vaultSyncReadOnlyBadge => '読み取り専用';

  @override
  String get vaultSyncReadOnlyTooltip =>
      'この保管庫は読み取り専用でマウントされています — ファイルをコピーできません';

  @override
  String get vaultSyncSyncingButton => '同期中…';

  @override
  String get vaultSyncNotEnoughSpaceTitle => '空き容量が不足しています';

  @override
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  ) {
    return '$sideの空き容量が不足しています — 必要:$required、空き:$freeのみ。';
  }

  @override
  String get removeMasterPasswordTitle => 'マスターパスワードを削除';

  @override
  String get confirmRemoveMasterPasswordMessage =>
      '削除を確認するため、現在のマスターパスワードを入力してください：';

  @override
  String get authenticateToRemoveMasterPassword => 'マスターパスワードを削除するために認証してください';

  @override
  String get incorrectPassword => 'パスワードが正しくありません';

  @override
  String get rememberPerFolderLayoutLabel => 'フォルダーごとのレイアウトと並べ替えを記憶';

  @override
  String get rememberPerFolderLayoutDesc =>
      'フォルダーごとに表示レイアウト（リスト、グリッド、メイソンリー）と並べ替え順を個別に保存';

  @override
  String get defaultFolderLayoutLabel => 'デフォルトのフォルダーレイアウト';

  @override
  String get fileInfoAction => '情報';

  @override
  String get automationSectionHeader => '自動化';

  @override
  String get automationTileTitle => '自動化';

  @override
  String get automationTileSubtitle =>
      '自動化によるこのボールトのロック解除・ロック・ファイルのインポート／エクスポートを許可します';

  @override
  String get automationScreenTitle => '自動化（Tasker / MacroDroid）';

  @override
  String get automationUsbUnsupportedMessage => 'USB接続の保管庫では自動化はまだ利用できません。';

  @override
  String get automationThisVaultSectionHeader => 'この保管庫';

  @override
  String get automationAccessLabel => '自動化アクセス';

  @override
  String get automationPasswordSectionHeader => '自動化パスワード';

  @override
  String get automationPasswordStoredHint =>
      '無人でのUNLOCK_VAULT呼び出し用にパスワードが保存されています。新しいものを保存すると置き換わり、空欄で保存すると消去されます — 自動化ではこれに頼る代わりに、ブロードキャストで直接パスワードを渡すこともできます。';

  @override
  String get automationPasswordNotStoredHint =>
      '任意項目です。パスワードが保存されていない場合、自動化はUNLOCK_VAULTブロードキャストのたびにパスワードを渡す必要があります。';

  @override
  String get automationNewPasswordFieldLabel => '新しいパスワード';

  @override
  String get automationPasswordFieldLabel => 'パスワード';

  @override
  String get automationClearPasswordButton => '保存済みパスワードを消去';

  @override
  String get automationSavePasswordButton => 'パスワードを保存';

  @override
  String get automationTokenSectionHeader => 'APIトークン';

  @override
  String get automationTokenDescription =>
      '自動化アクセスが有効なすべての保管庫で共有されます。自動化は各ブロードキャストでこれを送り返します。トークンが間違っているか欠落している場合、エラーにはならず黙って無視されます。';

  @override
  String get automationRegenerateTokenButton => 'トークンを再生成';

  @override
  String get automationRegenerateTokenDialogTitle => 'トークンを再生成しますか？';

  @override
  String get automationRegenerateTokenDialogMessage =>
      '現在のトークンを使用しているTaskerプロファイルやMacroDroidマクロは、新しいトークンで更新するまで、エラーなく動作しなくなります。';

  @override
  String get automationRegenerateConfirmLabel => '再生成';

  @override
  String get automationTokenRegeneratedMessage => 'トークンを再生成しました。';

  @override
  String get automationRegenerateTokenFailedMessage => 'トークンを再生成できませんでした。';

  @override
  String get automationUpdateSettingsFailedMessage => '自動化の設定を更新できませんでした。';

  @override
  String get automationSavePasswordFailedMessage => '自動化パスワードを保存できませんでした。';

  @override
  String get automationPasswordClearedMessage => '自動化パスワードを消去しました。';

  @override
  String get automationPasswordSavedMessage => '自動化パスワードを保存しました。';

  @override
  String get automationConfigSectionHeader => '設定用文字列';

  @override
  String get automationConfigIntro =>
      '下の値をタップするとコピーできます。Taskerでは「Send Intent」アクションを使用してください。MacroDroidでは、Intent TypeをBroadcastに設定した「Intent」アクションを使用してください — ActivityやServiceは「unable to find explicit activity class」エラーで失敗します。';

  @override
  String get automationConfigPackageLabel => 'パッケージ名';

  @override
  String get automationConfigClassLabel => 'レシーバークラス';

  @override
  String get automationConfigVaultUriLabel => 'この保管庫のURI';

  @override
  String get automationConfigActionsSectionHeader => 'ブロードキャストアクション';

  @override
  String get automationActionUnlockLabel => '保管庫のロック解除';

  @override
  String get automationActionLockLabel => '保管庫のロック';

  @override
  String get automationActionImportLabel => 'ファイルをインポート';

  @override
  String get automationActionExportLabel => 'ファイルをエクスポート';

  @override
  String get automationActionWipeLabel => 'ファイルを消去';

  @override
  String get automationActionEmergencyLockLabel => '緊急ロック（レベル1）';

  @override
  String get automationActionEmergencyPurgeLabel => '緊急パージ';

  @override
  String get automationDocCommentFootnote =>
      'すべてのextrasと結果ブロードキャストの契約については、VaultAutomationReceiver.ktに記載されています。';

  @override
  String get automationTierOffLabel => 'オフ';

  @override
  String get automationTierOffSubtitle => '自動化はこの保管庫に一切アクセスできません';

  @override
  String get automationTierLifecycleLabel => 'ロック解除／ロックのみ';

  @override
  String get automationTierLifecycleSubtitle => '自動化はこの保管庫のロック解除とロックのみ行えます';

  @override
  String get automationTierFullLabel => 'ロック解除／ロック + ファイルのインポート・エクスポート + 同期';

  @override
  String get automationTierFullSubtitle =>
      '自動化は、この保管庫のロック解除中に、設定済みフォルダの同期やファイルのインポート・エクスポートも行えます';

  @override
  String get automationTutorialLinkLabel => '手順を追った完全なチュートリアルを読む';

  @override
  String get showHiddenFilesLabel => '隠しファイルを表示';

  @override
  String get showHiddenFilesDesc => 'ドットファイルとシステムフォルダを表示します';

  @override
  String get dontAskAgain => '今後表示しない';

  @override
  String get deleteAfterImportLabel => 'インポート後にファイルを削除';

  @override
  String get deleteAfterImportModeAsk => '毎回確認する';

  @override
  String get deleteAfterImportModeAskSubtitle => 'インポート後に元のファイルを削除するかどうかを確認します';

  @override
  String get deleteAfterImportModeKeep => '元のファイルを保持する（削除しない）';

  @override
  String get deleteAfterImportModeKeepSubtitle => '元のファイルを削除せず、確認もしません';

  @override
  String get deleteAfterImportModeDelete => '元のファイルを自動的に削除する';

  @override
  String get deleteAfterImportModeDeleteSubtitle =>
      'インポート後、デバイスから元のファイルを自動的に削除します';

  @override
  String get deleteAfterImportVaultSettingLabel => 'この保管庫でのインポート後のファイル削除';

  @override
  String get deleteAfterImportInheritGlobal => '全体設定を継承';

  @override
  String deleteAfterImportInheritGlobalSubtitle(String mode) {
    return '全体設定を使用: $mode';
  }

  @override
  String get deleteAfterImportVaultAsk => '毎回確認';

  @override
  String get deleteAfterImportVaultKeep => '常に元のファイルを保持';

  @override
  String get deleteAfterImportVaultDelete => '常に元のファイルを削除';

  @override
  String get wizardBackButton => '戻る';

  @override
  String get wizardNextButton => '次へ';

  @override
  String get wizardStepTypeTitle => '種類';

  @override
  String get wizardStepBasicInfoTitle => '基本情報';

  @override
  String get wizardStepAdvancedTitle => '詳細設定';

  @override
  String get wizardStepReviewTitle => '確認';

  @override
  String get wizardCreateTypePrompt => '何を作成しますか？';

  @override
  String get wizardChooseFormatPrompt => 'コンテナ形式を選択してください';

  @override
  String get wizardEncryptionDetailsRowTitle => '暗号化の詳細';

  @override
  String get wizardHiddenVolumeRowSubtitleConfigured => '設定済み — タップして確認';

  @override
  String get wizardHiddenVolumeRowSubtitleNeedsSetup => 'タップして設定';

  @override
  String get wizardSummaryTitle => '概要';

  @override
  String get wizardSummaryPasswordLabel => 'パスワード';

  @override
  String get wizardPasswordSetValue => '設定済み';

  @override
  String get wizardPasswordNotSetValue => '未設定（キーファイルを使用）';

  @override
  String get wizardSummaryKeyfilesLabel => 'キーファイル';

  @override
  String get wizardSummaryPimDefaultValue => 'デフォルト';

  @override
  String get wizardSummaryPimLabel => 'PIM';

  @override
  String get wizardSummaryDriveLabel => 'USBドライブ';

  @override
  String get sectionKeyStorageIntegration => '鍵の保存とシステムアクセス';

  @override
  String get sectionMaskMode => 'マスクモード';

  @override
  String get advancedOptionsTitle => '詳細オプション';

  @override
  String get audioTrackTitle => '音声トラック';

  @override
  String get noAudioTracksAvailable => '利用可能な音声トラックがありません';

  @override
  String trackNumberLabel(int number) {
    return 'トラック $number';
  }

  @override
  String subtitleTrackNumberLabel(int number) {
    return '字幕 $number';
  }

  @override
  String get offLabel => 'オフ';

  @override
  String get externalSubtitlesLabel => '外部字幕 (.srt/.vtt)';

  @override
  String get externalLabel => '外部';

  @override
  String get subtitleSizeLabel => 'サイズ';

  @override
  String get subtitleSizeSmall => '小';

  @override
  String get subtitleSizeMedium => '中';

  @override
  String get subtitleSizeLarge => '大';

  @override
  String get subtitleSizeExtraLarge => '特大';

  @override
  String get subtitlePositionLabel => '位置';

  @override
  String get subtitlePositionBottom => '下';

  @override
  String get subtitlePositionLower => '下寄り';

  @override
  String get subtitlePositionCenter => '中央';

  @override
  String get subtitlePositionTop => '上';

  @override
  String get editImageAction => '画像を編集';

  @override
  String get imageEditorUnsupportedFormatMessage => 'この画像形式は編集に対応していません。';

  @override
  String get cropToolLabel => '切り抜き';

  @override
  String get drawToolLabel => '描画';

  @override
  String get textToolLabel => 'テキスト';

  @override
  String get redactToolLabel => '墨消し';

  @override
  String get rotateLeftTooltip => '左に回転';

  @override
  String get rotateRightTooltip => '右に回転';

  @override
  String get cropAspectFreeLabel => '自由';

  @override
  String get cropAspectSquareLabel => '正方形';

  @override
  String get cropAspectOriginalLabel => '元の比率';

  @override
  String get applyCropTooltip => '切り抜きを適用';

  @override
  String get annotationColorTooltip => '色';

  @override
  String get annotationStrokeWidthTooltip => '線の太さ';

  @override
  String get clearAnnotationsTooltip => 'すべての注釈を消去';

  @override
  String get resetImageTooltip => '元の画像に戻す';

  @override
  String get resetImageConfirmTitle => '画像をリセットしますか？';

  @override
  String get resetImageConfirmMessage => 'このセッションで行ったすべての切り抜きと描画の変更が破棄されます。';

  @override
  String get addTextAnnotationTitle => 'テキストを追加';

  @override
  String get addTextAnnotationHint => '何か入力してください…';

  @override
  String get textToolHint => '画像をタップしてテキストを追加';

  @override
  String get saveImageSheetTitle => '変更を保存';

  @override
  String get saveAsNewFileOption => '新しいファイルとして保存';

  @override
  String get saveAsNewFileDescription => '元のファイルはそのまま残ります';

  @override
  String get overwriteOriginalOption => '元のファイルを上書き';

  @override
  String get overwriteOriginalDescription => '元のファイルを置き換えます';

  @override
  String get newFileNameLabel => 'ファイル名';

  @override
  String get imageEditorPngNoteMessage => '編集した画像はPNG形式で保存されます。';

  @override
  String get imageSavedMessage => '画像を保存しました';

  @override
  String imageSaveFailedMessage(String error) {
    return '画像を保存できませんでした：$error';
  }

  @override
  String get advancedRenameButton => '詳細';

  @override
  String get advancedRenameBatchTitle => '一括名前変更';

  @override
  String get advancedRenameRulesTab => 'ルール';

  @override
  String advancedRenamePreviewTab(int count) {
    return 'プレビュー ($count)';
  }

  @override
  String get advancedRenameSearchReplaceTitle => '検索と置換';

  @override
  String get advancedRenameFindTextLabel => '検索するテキスト';

  @override
  String get advancedRenameFindTextHint => '一致させるテキストまたはパターンを入力...';

  @override
  String get advancedRenameReplaceWithLabel => '置換後のテキスト';

  @override
  String get advancedRenameReplaceWithHint => '新しいテキストまたは変数...';

  @override
  String get advancedRenameInsertVariableTooltip => '動的な変数トークンを挿入';

  @override
  String get advancedRenameDateTimeTokens => '日付と時刻のトークン';

  @override
  String advancedRenameStandardDate(String token) {
    return '標準日付 ($token)';
  }

  @override
  String advancedRenameYearFourDigit(String token) {
    return '西暦4桁 ($token)';
  }

  @override
  String advancedRenameMonth(String token) {
    return '月 ($token)';
  }

  @override
  String advancedRenameDayOfMonth(String token) {
    return '日 ($token)';
  }

  @override
  String advancedRenameTime(String token) {
    return '時刻 ($token)';
  }

  @override
  String get advancedRenameDynamicIdentifiers => '動的識別子';

  @override
  String advancedRenameUniqueUuid(String token) {
    return '一意のUUID v4 ($token)';
  }

  @override
  String get advancedRenameRandomAlphanumeric => 'ランダム英数字（8文字）';

  @override
  String get advancedRenameRandomDigits => 'ランダム数字（6桁）';

  @override
  String get advancedRenameEmbeddedCounter => '埋め込みカウンター';

  @override
  String advancedRenamePaddedCounter(String token) {
    return 'ゼロ埋めカウンター ($token)';
  }

  @override
  String get advancedRenameRegex => '正規表現';

  @override
  String get advancedRenameMatchCase => '大文字と小文字を区別';

  @override
  String get advancedRenameAllOccurrences => 'すべての一致箇所';

  @override
  String get advancedRenameScopeFormatting => '適用範囲と書式';

  @override
  String get advancedRenameApplyChangesTo => '変更を適用する対象';

  @override
  String get advancedRenameFilename => 'ファイル名';

  @override
  String get advancedRenameExtension => '拡張子';

  @override
  String get advancedRenameBoth => '両方';

  @override
  String get advancedRenameCaseTransformation => '大文字・小文字の変換';

  @override
  String get advancedRenameNoChange => '変更なし';

  @override
  String get advancedRenameLowercase => '小文字';

  @override
  String get advancedRenameUppercase => '大文字';

  @override
  String get advancedRenameTitleCase => 'タイトルケース';

  @override
  String get advancedRenameCapitalize => '先頭を大文字に';

  @override
  String get advancedRenameSequentialCounter => '連番カウンター';

  @override
  String get advancedRenameCounterDescription => '連番を前または後ろに追加します';

  @override
  String get advancedRenameSuffix => '接尾（末尾）';

  @override
  String get advancedRenamePrefix => '接頭（先頭）';

  @override
  String get advancedRenameStartAt => '開始番号';

  @override
  String get advancedRenameDigits => '桁数';

  @override
  String get advancedRenameDigitsHint => '例：2 (01)';

  @override
  String get advancedRenameSeparator => '区切り文字';

  @override
  String get advancedRenameSeparatorHint => '_ or -';

  @override
  String get advancedRenameLivePreview => 'リアルタイムプレビュー';

  @override
  String get advancedRenameDeselect => '選択を解除';

  @override
  String get advancedRenameSelectAll => 'すべて選択';

  @override
  String get advancedRenameNoFilesSelected => 'ファイルが選択されていません';

  @override
  String get advancedRenameNameConflictDetected => '名前の競合が検出されました';

  @override
  String get advancedRenameCheckPreviewToFix => '修正するにはプレビュータブを確認してください';

  @override
  String get advancedRenameReadyToRename => '名前変更の準備完了';

  @override
  String get advancedRenameErrorsDetected => 'エラーが検出されました';

  @override
  String advancedRenameApply(int count) {
    return '適用 ($count)';
  }

  @override
  String get advancedRenameNameCollisionWithinBatch => 'バッチ内で名前が競合しています。';

  @override
  String get advancedRenameCollidesWithUnselectedFile => '未選択のファイルと競合しています。';

  @override
  String advancedRenameReadyCount(int valid, int total) {
    return '$valid 件が名前変更の準備完了（全 $total 件中）';
  }

  @override
  String advancedRenameReadyOfTotal(int valid, int total) {
    return '$total 件中 $valid 件が準備完了';
  }

  @override
  String advancedRenameRenamedItems(int succeeded, int failed) {
    return '$succeeded 件の名前を変更しました（$failed 件失敗）。';
  }

  @override
  String advancedRenameSuccessfullyRenamed(int count) {
    return '$count 件の名前を正常に変更しました。';
  }

  @override
  String get advancedRenameMonthsFull =>
      '1月|2月|3月|4月|5月|6月|7月|8月|9月|10月|11月|12月';

  @override
  String get advancedRenameMonthsAbbr =>
      '1月|2月|3月|4月|5月|6月|7月|8月|9月|10月|11月|12月';

  @override
  String get advancedRenameDaysFull => '月曜日|火曜日|水曜日|木曜日|金曜日|土曜日|日曜日';

  @override
  String get advancedRenameDaysAbbr => '月|火|水|木|金|土|日';

  @override
  String get advancedRenameResolveConflicts => '適用する前に名前の競合を解決してください';

  @override
  String advancedRenameChangedCount(int changed, int total) {
    return '$total 件中 $changed 件';
  }

  @override
  String get automationKeyfilesPimSectionHeader => 'キーファイルとPIM';

  @override
  String get automationKeyfilesPimDescription =>
      '上のオートメーションパスワードと一緒に保存され、UNLOCK_VAULT呼び出しで同様に使用されます。通常、パスワードだけでなくキーファイルや非デフォルトのPIMでアンロックするVeraCrypt/LUKSボールト向けです。';

  @override
  String get automationSavePimButton => 'PIMを保存';

  @override
  String get automationCameraSectionHeader => 'カメラの自動化';

  @override
  String get automationCameraDescription =>
      'このボールトに対して自動化からTAKE_PHOTO／START_RECORDING／STOP_RECORDING／START_AUDIO_RECORDING／STOP_AUDIO_RECORDINGを実行できるようにします。フルアクセスでも既定でオフです。ファイルのインポート／エクスポートと異なり、写真撮影は画面上の表示が一切不要なため、別途明示的なオプトインとしています。';

  @override
  String get automationAllowCameraCapture => 'カメラ撮影を許可';

  @override
  String get automationOverlayPermissionTitle => '他のアプリの上に重ねて表示';

  @override
  String get automationOverlayPermissionMessage =>
      'Android 14+ では、バックグラウンドでのカメラ撮影に「他のアプリの上に重ねて表示」の権限が必要です。画面ロック時やアプリがバックグラウンドにあるときの自動撮影を許可するには、この権限を付与してください。';

  @override
  String get automationPimSavedMessage => 'PIMを保存しました';

  @override
  String get automationActionImportFolderLabel => 'フォルダをインポート';

  @override
  String get automationActionExportFolderLabel => 'フォルダをエクスポート';

  @override
  String get automationActionTakePhotoLabel => '写真を撮る';

  @override
  String get automationActionStartRecordingLabel => '録画を開始';

  @override
  String get automationActionStopRecordingLabel => '録画を停止';

  @override
  String get automationActionStartAudioRecordingLabel => '音声録音を開始';

  @override
  String get automationActionStopAudioRecordingLabel => '音声録音を停止';

  @override
  String get filePropertiesSectionHeader => 'ファイルのプロパティ';

  @override
  String get fullPathLabel => 'フルパス';

  @override
  String get sizeLabel => 'サイズ';

  @override
  String get modifiedLabel => '更新日時';

  @override
  String get vaultLabel => 'ボールト';

  @override
  String get mediaDimensionsSectionHeader => 'メディアと解像度';

  @override
  String get resolutionLabel => '解像度';

  @override
  String get aspectRatioLabel => 'アスペクト比';

  @override
  String get formatLabel => '形式';

  @override
  String get exifCameraDataSectionHeader => 'EXIF・カメラ情報';

  @override
  String get cameraLabel => 'カメラ';

  @override
  String get lensLabel => 'レンズ';

  @override
  String get dateTakenLabel => '撮影日時';

  @override
  String get shutterSpeedLabel => 'シャッター速度';

  @override
  String get apertureLabel => '絞り';

  @override
  String get isoLabel => 'ISO';

  @override
  String get focalLengthLabel => '焦点距離';

  @override
  String get flashLabel => 'フラッシュ';

  @override
  String get softwareLabel => 'ソフトウェア';

  @override
  String get gpsLocationLabel => 'GPS位置情報';

  @override
  String get integrityChecksumSectionHeader => '整合性とチェックサム';

  @override
  String get computingHashMessage => 'ハッシュを計算中…';

  @override
  String get tapCalculateToVerifyMessage => '確認するには「計算」をタップしてください';

  @override
  String get calculateButton => '計算';

  @override
  String get copyDiagnosticsButton => '診断情報をコピー';

  @override
  String get closeButton => '閉じる';

  @override
  String get hwAcceleratedBadge => 'ハードウェア支援';

  @override
  String get swDecoderBadge => 'ソフトウェアデコーダー';

  @override
  String get videoDecoderHardwareSection => '動画デコーダーとハードウェア';

  @override
  String get decoderNameLabel => 'デコーダー名';

  @override
  String get accelerationLabel => 'アクセラレーション';

  @override
  String get hardwareGpuDirect => 'ハードウェア（GPUダイレクト）';

  @override
  String get softwareCpuFallback => 'ソフトウェア（CPUフォールバック）';

  @override
  String get unknownValue => '不明';

  @override
  String get framerateLabel => 'フレームレート';

  @override
  String get variableOrUnknown => '可変／不明';

  @override
  String get videoCodecLabel => '動画コーデック';

  @override
  String get autoDetected => '自動検出';

  @override
  String get colorFormatLabel => 'カラーフォーマット';

  @override
  String get initLatencyLabel => '初期化レイテンシ';

  @override
  String get audioEngineSection => 'オーディオエンジン';

  @override
  String get audioDecoderLabel => '音声デコーダー';

  @override
  String get audioCodecLabel => '音声コーデック';

  @override
  String get pipelineHealthSection => 'パイプラインと状態';

  @override
  String get playbackStateLabel => '再生状態';

  @override
  String get decryptedBufferLabel => '復号済みバッファー';

  @override
  String secondsCached(String seconds) {
    return '$seconds 秒キャッシュ済み';
  }

  @override
  String get droppedFramesLabel => 'ドロップフレーム';

  @override
  String nFrames(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count フレーム',
    );
    return '$_temp0';
  }

  @override
  String get sourceStorageLabel => 'ソースストレージ';

  @override
  String directJniStreamSource(int volId) {
    return '直接C++ JNIストリーム（volId=$volId）';
  }

  @override
  String get archivesTabLabel => 'アーカイブ';

  @override
  String get filesTabLabel => 'ファイル';

  @override
  String get filesPermissionMessage => 'デバイス上のファイルを閲覧するにはアクセスを許可してください。';

  @override
  String get filesEmptyTitle => 'ファイルがありません';

  @override
  String get filesEmptyMessage => 'このフォルダは空です。';

  @override
  String get filesNewFolderTooltip => '新規フォルダ';

  @override
  String get filesNewFolderDialogTitle => '新規フォルダ';

  @override
  String get filesNameHint => '名前';

  @override
  String get filesCreate => '作成';

  @override
  String get filesRename => '名前を変更';

  @override
  String get filesDelete => '削除';

  @override
  String get filesShare => '共有';

  @override
  String get filesCopy => 'コピー';

  @override
  String get filesMove => '移動';

  @override
  String get filesDeleteConfirmTitle => '完全に削除しますか？';

  @override
  String get filesChooseDestinationTitle => 'フォルダを選択';

  @override
  String get filesMoveHere => 'ここに移動';

  @override
  String get filesCopyHere => 'ここにコピー';

  @override
  String get filesSelectAllTooltip => 'すべて選択';

  @override
  String get filesCloseSelectionTooltip => '閉じる';

  @override
  String get filesFolderCreated => 'フォルダを作成しました';

  @override
  String get filesCreateFolderFailed => 'フォルダを作成できませんでした';

  @override
  String get filesRenamed => '名前を変更しました';

  @override
  String get filesRenameFailed => '名前を変更できませんでした';

  @override
  String get filesNameAlreadyExists => 'その名前は既に使用されています';

  @override
  String get filesDeleted => '削除しました';

  @override
  String get filesDeleteFailed => '削除できませんでした';

  @override
  String get filesMoved => '移動しました';

  @override
  String get filesMoveFailed => '移動できませんでした';

  @override
  String get filesCopied => 'コピーしました';

  @override
  String get filesCopyFailed => 'コピーできませんでした';

  @override
  String get filesOpenFailed => 'このファイルを開けませんでした';

  @override
  String get filesShareFailed => 'このファイルを共有できませんでした';

  @override
  String get filesFilterTooltip => 'フィルター';

  @override
  String get filesFilterAll => 'すべてのファイル';

  @override
  String get filesFilterImages => '画像';

  @override
  String get filesFilterVideos => '動画';

  @override
  String get filesFilterAudio => '音声';

  @override
  String get filesFilterDocuments => 'ドキュメント';

  @override
  String get filesTextTooLarge => 'このファイルは大きすぎるため、ここではプレビューできません。';

  @override
  String get filesTextSaved => '保存しました';

  @override
  String get filesTextSaveFailed => '保存できませんでした';

  @override
  String get toolHeaderBackupTitle => 'ヘッダーのバックアップ';

  @override
  String get toolHeaderBackupSubtitle => 'コンテナヘッダーと保管庫設定のバックアップまたは復元';

  @override
  String get headerBackupModeExport => 'バックアップを保存';

  @override
  String get headerBackupModeRestore => 'バックアップを復元';

  @override
  String get headerBackupPickExportTarget => 'バックアップする対象を選択してください。';

  @override
  String get headerBackupPickRestoreTarget => 'バックアップを復元する対象を選択してください。';

  @override
  String get headerBackupTargetContainerSubtitle => 'VeraCrypt、LUKS1、またはLUKS2';

  @override
  String get headerBackupTargetFolderSubtitle =>
      'gocryptfs、CryFS、またはCryptomator';

  @override
  String get headerBackupExportInfoBanner =>
      'コンテナのヘッダーには鍵情報が含まれています — 不良セクタや書き込み失敗などでこれを失うと、無傷のデータ領域であっても復元できなくなります。フォルダ保管庫もルートにある小さな設定ファイルに同様の情報を保持しています。このバックアップはコンテナ本体とは別の場所に保管してください。';

  @override
  String get headerBackupRestoreInfoBanner =>
      '復元を行うと、対象の現在のヘッダー（または設定ファイル）がバックアップのもので上書きされます — バックアップがこの形式にとって真正であることは事前に検証されますが、正しい対象を選択していることを必ず確認してください。';

  @override
  String headerBackupUnhealthyExportWarning(String diagnosis) {
    return 'このコンテナは正常な状態ではありません（$diagnosis）。今バックアップを作成すると、バックアップにも同じ問題が含まれることになります。可能であれば先に「確認と修復」を実行してください — これが取得する唯一の機会である場合はそのままバックアップしてください。';
  }

  @override
  String get headerBackupBackUpAnyway => 'とにかくバックアップ';

  @override
  String get headerBackupExportHeader => 'ヘッダーをエクスポート';

  @override
  String get headerBackupSavedBanner => 'バックアップを保存しました。このコンテナとは別の場所に保管してください。';

  @override
  String get headerBackupSaveBackupFile => 'バックアップファイルを保存';

  @override
  String get headerBackupPickBackupFile => 'バックアップファイルを選択';

  @override
  String get headerBackupMismatchFolderVaultError =>
      'このバックアップはフォルダ保管庫用ですが、選択された対象はコンテナファイルです。';

  @override
  String get headerBackupMismatchContainerFileError =>
      'このバックアップはコンテナファイル用ですが、選択された対象はフォルダ保管庫です。';

  @override
  String get headerBackupRestoredSuccess => 'ヘッダーを復元しました。';

  @override
  String get headerBackupRestore => '復元';

  @override
  String headerBackupBackedUpAt(String date) {
    return 'バックアップ日時: $date';
  }

  @override
  String get headerBackupLogIdle => 'コンソールログの出力は待機状態です...';

  @override
  String get compositeCreateScreenTitle => '複合コンテナの作成';

  @override
  String get compositeProcessingStatus => '処理中…';

  @override
  String compositeCarrierFilesCountHeader(int count) {
    return 'キャリアファイル ($count)';
  }

  @override
  String get compositeAddCarrierFilesTitle => 'キャリアファイルを追加';

  @override
  String get compositeAddCarrierFilesSubtitle => '画像、動画、音声、またはドキュメントを選択';

  @override
  String get compositeBrowseButtonLabel => '参照';

  @override
  String compositeCarrierAllocatableSubtitle(String format, String size) {
    return '$format • 割り当て可能: $size';
  }

  @override
  String get compositeCarrierAnalyzingStatus => '解析中…';

  @override
  String get compositeTotalUsableCapacityHeader => '合計使用可能容量';

  @override
  String compositeCapacityDistributedSubtitle(int count) {
    return '$count 個のファイルに分散 (512B セクタにアライメント)';
  }

  @override
  String get compositePimFieldLabel => 'PIM (Personal Iteration Multiplier)';

  @override
  String get compositePimFieldHelper => '標準のデフォルト反復回数を使用する場合は空欄または0';

  @override
  String get compositeRememberContainerTitle => 'このコンテナを記憶';

  @override
  String get compositeRememberContainerSubtitle =>
      'ダッシュボードに固定して、次回以降これらのファイルを再選択する手間を省きます。リンクされたファイルを暗号化してこのデバイスに保存します。';

  @override
  String get compositeEncryptionAndFilesystemHeader => '暗号化とファイルシステム';

  @override
  String get compositeEncryptionAlgorithmLabel => '暗号化アルゴリズム';

  @override
  String get compositeHashAlgorithmLabel => 'ハッシュアルゴリズム (KDF)';

  @override
  String get compositeFilesystemTypeLabel => 'ファイルシステムの種類';

  @override
  String get compositeQuickFormatTitle => 'クイックフォーマット';

  @override
  String get compositeQuickFormatSubtitle => 'キャリアの割り当て領域のゼロ埋めをスキップ';

  @override
  String get compositeCreateContainerButton => 'コンテナを作成';

  @override
  String get compositeCreateSuccessMessage => '複合コンテナが正常に作成されました！';

  @override
  String compositeDefaultContainerName(int count) {
    return '複合コンテナ ($count 個のファイル)';
  }

  @override
  String get compositeAlreadyHaveUnlockPrompt =>
      'すでに複合コンテナをお持ちですか？ ロック解除してマウント';

  @override
  String compositeBadgeMultipleCarriers(int count) {
    return '複合 ($count 個のキャリア)';
  }

  @override
  String get compositeBadgeSingleCarrier => '複合キャリア (1個選択)';

  @override
  String get compositeBadgeDefault => '複合コンテナ';

  @override
  String get compositeSingleCarrierWarningBanner =>
      '複合キャリアが検出されました。複合コンテナのロックを解除するには、すべてのキャリアファイルが必要です。';

  @override
  String get compositeSelectAllCarriersButton => 'すべてのキャリアを選択';

  @override
  String get compositeCarriersMissingTitle => '複合キャリアが見つかりません';

  @override
  String get compositeCarriersMissingExplanation =>
      '1つ以上のキャリアファイルにアクセスできないか、移動された可能性があります。';

  @override
  String get compositeRelocateCarriersButton => 'キャリアファイルを再指定';

  @override
  String get passwordOptionalFieldLabel => 'パスワード (省略可能)';

  @override
  String get plainDiskImagePasswordHint => 'パスワードは不要です — このディスクイメージは暗号化されていません';

  @override
  String get compositePasswordHint => '複合コンテナのパスワードを入力';

  @override
  String get generateStrongPasswordTooltip => '強力なパスワードを生成';

  @override
  String get cryfsBlockSizeDefaultLabel => '32 KiB (デフォルト)';

  @override
  String get hiddenVolumeConfiguredInNextStepNotice =>
      '隠しボリュームのパラメータは次のステップで設定されます。';

  @override
  String get hiddenVolumeExplanationBanner =>
      '隠しボリュームは外側ボリュームの空き領域内に存在します。そのパスワードとキーファイルは外側ボリュームと必ず異なる必要があります。';

  @override
  String get hiddenVolumeCredentialsSectionHeader => '隠しボリュームの認証情報';

  @override
  String get hiddenVolumeSizeAndFormatSectionHeader => '隠しボリュームのサイズとフォーマット';

  @override
  String get shareSheetIntegrationTitle => '共有シートとの連携';

  @override
  String get shareSheetIntegrationSubtitle =>
      'Androidの共有メニューから直接保管庫へファイルを共有できるようにします。';

  @override
  String get shareSheetIntegrationUpdateErrorMessage => '共有シート連携を更新できませんでした。';

  @override
  String get autoLockOnShareImportTitle => '共有インポート後の自動ロック';

  @override
  String get autoLockOnShareImportSubtitle =>
      '共有ファイルのインポート専用にロック解除された保管庫を自動的に再ロックします';

  @override
  String get shareImportExpiredMessage => 'インポートするものがありません。共有リクエストが期限切れになりました。';

  @override
  String get sharedFileDefaultDisplayName => '共有ファイル';

  @override
  String importingSharedFilesMessage(int count, String destination) {
    return '$count 個のファイルを $destination にインポート中';
  }

  @override
  String sharedFileSavedMessage(int count, String destination) {
    return '$count 個のファイルを $destination に保存しました';
  }

  @override
  String get sharedFileSaveFailedMessage => '共有ファイルを保存できませんでした。';

  @override
  String get saveToVaultTitle => '保管庫に保存';

  @override
  String get noVaultsAvailableAddFromDashboardPrompt =>
      '保管庫がまだありません。最初にダッシュボードから追加してください。';

  @override
  String get vaultStatusUnlocked => 'ロック解除済み';

  @override
  String get vaultStatusLocked => 'ロック中';

  @override
  String get compositeCarrierGrowthSectionHeader => '秘匿性と容量';

  @override
  String get compositeCarrierGrowthSliderTitle => 'キャリアファイルのサイズ増加';

  @override
  String compositeCarrierGrowthPercentLabel(int percent) {
    return 'ファイルごとに +$percent%';
  }

  @override
  String get compositeCarrierGrowthUltraStealthDesc =>
      '超ステルス（約5%）: ファイルサイズはほとんど増加しません。カメラセンサーの自然なばらつきと完全に区別がつきません。';

  @override
  String get compositeCarrierGrowthRecommendedDesc =>
      '推奨（約10%）: 秘匿性と実用的な保管庫容量のバランスを取ります。';

  @override
  String get compositeCarrierGrowthHighCapacityDesc =>
      '大容量（約20%以上）: 保管庫の容量を最大化しますが、キャリアファイルのサイズ増加が目立ちます。';

  @override
  String get emergencyPanicTitle => '緊急パニック & 強要対策';

  @override
  String get emergencyPanicSubtitle => 'パニックトリガー、クイック設定タイル、PanicKit、強要解除';

  @override
  String get sectionPanicTiers => 'パニック消去レベル';

  @override
  String get panicTierSessionLabel => 'レベル 1: セッション消去';

  @override
  String get panicTierSessionSubtitle =>
      'すべてのボルトをアンマウントし、メモリをゼロクリアして記憶されたボルト認証情報を消去';

  @override
  String get panicTierCredentialLabel => 'レベル 2: 認証情報消去';

  @override
  String get panicTierCredentialSubtitle =>
      'ダッシュボードのボルト一覧、マスターロック、アプリ設定を消去し、Keystoreを初期化';

  @override
  String get panicTierNuclearLabel => 'レベル 3: 完全消去 (Nuclear Wipe)';

  @override
  String get panicTierNuclearSubtitle =>
      'すべてのアプリ保存領域をゼロ埋め・粉砕し、システムのアンインストールを要求';

  @override
  String get panicQuickTileTitle => 'クイック設定タイル';

  @override
  String get panicQuickTileSubtitle => '設定されたパニックレベルを即座に実行するクイック設定タイルを有効化';

  @override
  String get triggerPanicNowTitle => '今すぐパニックを実行';

  @override
  String get triggerPanicNowSubtitle => '設定されているパニック消去レベルを直ちに実行します';

  @override
  String get triggerPanicConfirmTitle => '緊急パニックを実行しますか？';

  @override
  String triggerPanicConfirmMessage(String tier) {
    return 'これにより直ちに$tierが実行されます。開いているコンテナと認証情報はこのレベルに従って消去されます。';
  }

  @override
  String get triggerPanicButton => 'パニックを実行';

  @override
  String get sectionPanicBootTrigger => 'Wipe on Reboot';

  @override
  String get panicBootTriggerLevelLabel => '再起動時に実行するレベル';

  @override
  String get panicBootTriggerArmTitle => '次回の起動に備える';

  @override
  String panicBootTriggerArmedSubtitle(Object tier) {
    return '準備完了 — 次回デバイスを起動すると $tier が自動的に実行され、その後解除されます';
  }

  @override
  String get panicBootTriggerDisarmedSubtitle => 'オフ — デバイスは通常通り再起動します';

  @override
  String get panicBootTriggerConfirmTitle => '再起動時のワイプを準備しますか？';

  @override
  String panicBootTriggerConfirmMessage(Object tier) {
    return '次回デバイスを起動した際（通常の再起動や自動アップデートを含む）、アプリを開く前に $tier が自動的に実行されます。これは一度だけ実行され、その後解除されます。';
  }

  @override
  String get panicBootTriggerArmButton => '準備する';

  @override
  String get panicBootTriggerArmedSuccessMessage => '起動トリガーを準備しました';

  @override
  String get panicBootTriggerDisarmedSuccessMessage => '起動トリガーを解除しました';

  @override
  String get sectionPanicKit => 'PanicKit レスポンダー';

  @override
  String get panicKitEnableTitle => 'PanicKit レスポンダー';

  @override
  String get panicKitEnableSubtitle =>
      'ペアリングされた外部パニックアプリ（Ripple、Wastedなど）からの起動を許可';

  @override
  String get panicKitEnforcePairingTitle => 'アプリのペアリングを強制';

  @override
  String get panicKitEnforcePairingSubtitle =>
      'トリガー受信時にパッケージIDおよびSHA-256証明書ダイジェストを検証';

  @override
  String get panicKitPairedAppLabel => 'ペアリング済みトリガーアプリ';

  @override
  String get panicKitNoAppPaired => 'ペアリングされたアプリはありません';

  @override
  String get panicKitUnpairButton => 'ペアリング解除';

  @override
  String get panicKitUnpairSuccess => 'PanicKitトリガーのペアリングを解除しました';

  @override
  String get sectionDuressUnlock => 'マスターロック強要解除';

  @override
  String get duressMasterPasswordRequired =>
      '強要解除を設定する前に、セキュリティでマスターパスワードを有効にする必要があります。';

  @override
  String get duressPasswordTitle => '強要用パスワード';

  @override
  String get duressPasswordConfiguredSubtitle =>
      '有効 — ロック画面でこのパスワードを入力すると強要アクションが実行されます';

  @override
  String get duressPasswordNotConfiguredSubtitle =>
      'ロック画面で緊急アクションを発動するための別のパスワードを設定';

  @override
  String get removeDuressPasswordButton => '強要用パスワードを削除';

  @override
  String get duressPasswordSetSuccess => '強要用パスワードを設定しました';

  @override
  String get duressPasswordRemovedSuccess => '強要用パスワードを削除しました';

  @override
  String get duressPinConfiguredTitle => '強要用PIN';

  @override
  String get duressPinConfiguredSubtitle =>
      '有効 — キーパッドでこのPINを入力すると強要アクションが実行されます';

  @override
  String get duressPinNotConfiguredSubtitle => 'キーパッドで緊急アクションを発動するための別のPINを設定';

  @override
  String get removeDuressPinButton => '強要用PINを削除';

  @override
  String get duressPinSetSuccess => '強要用PINを設定しました';

  @override
  String get duressPinRemovedSuccess => '強要用PINを削除しました';

  @override
  String get duressPatternTitle => '強要用パターン';

  @override
  String get duressPatternConfiguredSubtitle =>
      '有効 — このパターンを描画すると強要アクションが実行されます';

  @override
  String get duressPatternNotConfiguredSubtitle =>
      'ロック画面で緊急アクションを発動するための別のパターンを設定';

  @override
  String get removeDuressPatternButton => '強要用パターンを削除';

  @override
  String get duressPatternSetSuccess => '強要用パターンを設定しました';

  @override
  String get duressPatternRemovedSuccess => '強要用パターンを削除しました';

  @override
  String get duressMatchesMasterPasswordError => 'デュレスパスワードはマスターパスワードと一致できません';

  @override
  String get duressMatchesMasterPinError => 'マスターPINと一致できません';

  @override
  String get duressMatchesMasterPatternError => 'マスターパターンと一致できません';

  @override
  String get masterMatchesDuressPasswordError => 'マスターパスワードはデュレスパスワードと一致できません';

  @override
  String get masterMatchesDuressPinError => 'デュレスPINと一致できません';

  @override
  String get masterMatchesDuressPatternError => 'デュレスパターンと一致できません';

  @override
  String get toolCompositeContainerTitle => 'コンポジットコンテナ';

  @override
  String get toolCompositeContainerSubtitle =>
      '複数のメディアファイルにまたがって暗号化保管庫を埋め込みマウント';

  @override
  String get compositePasswordChangeNotSupportedMessage =>
      'コンポジットコンテナのパスワード変更はサポートされていません';

  @override
  String get compositeNoCarrierFilesFoundError => 'コンポジットコンテナのキャリアファイルが見つかりません';

  @override
  String get compositeIncorrectCredentialsOrCarrierMismatchError =>
      '認証情報が正しくないか、キャリアファイルの組み合わせが一致しません';

  @override
  String get incorrectCredentialsOrInvalidContainer => '認証情報が正しくないか、無効なコンテナです';

  @override
  String get repairTargetFolderVaultOption => 'フォルダ保管庫';

  @override
  String get repairTargetFolderVaultSubtitle =>
      'gocryptfs、CryFS、または Cryptomator';

  @override
  String get repairFolderVaultHealthyDeepScan =>
      '問題は見つかりませんでした -- 全ファイルのコンテンツが検証されました。';

  @override
  String get repairFolderVaultHealthyStructureOnly =>
      '構造上の問題は見つかりませんでした。ファイル内容も検証するにはパスワードを入力してディープスキャンを実行してください。';

  @override
  String repairFolderVaultIssuesCount(num count) {
    return '$count 個の問題が見つかりました';
  }

  @override
  String get repairFolderVaultStructureOnlySuffix =>
      ' (構造のみ -- 完全な内容検証にはディープスキャンを実行してください)';

  @override
  String get repairDeepScanWithPasswordButton => 'パスワードでディープスキャン';

  @override
  String repairFolderVaultSummary(
    Object fixed,
    Object recovered,
    Object removed,
  ) {
    return '修復の概要: $fixed 件修正、$recovered 件を /LOST+FOUND に復元、$removed 件クリーンアップ。';
  }

  @override
  String get repairAndRecoverVaultButton => '保管庫の修復と復元';

  @override
  String get repairScanAgainButton => '再スキャン';

  @override
  String panicPurgeCompletedMessage(Object count) {
    return 'パニックパージ完了 ($count 個ロック)。';
  }

  @override
  String get usbPermissionRequiredError => 'USB 権限が必要です';

  @override
  String get logcatScrollToBottomTooltip => '一番下までスクロール';

  @override
  String logcatLinesCount(num count) {
    return '$count 行';
  }

  @override
  String get compositeSpaceTooSmallError => '割り当て可能スペースが小さすぎます (最低 300 KB 必要)';

  @override
  String get compositeInitializingStatusMessage =>
      'コンポジット VeraCrypt ボリュームを初期化中…';

  @override
  String get compositeCreationFailedError => 'コンポジットコンテナの作成に失敗しました';

  @override
  String get compositeSelectCarriersFirstError => '最初にキャリアファイルを選択してください';

  @override
  String get compositePasswordOrKeyfileRequiredError => 'パスワードまたはキーファイルが必要です';

  @override
  String get compositeMountingStatusMessage => 'コンポジットボリュームをマウント中…';

  @override
  String get compositeAuthFailedOrCarrierMismatchError =>
      '認証に失敗したか、キャリアファイルの組み合わせが一致しません';

  @override
  String get layoutModeColumnedList => 'カラム形式リスト';

  @override
  String get longFileNameDisplayLabel => '長いファイル名の表示';

  @override
  String get longFileNameDisplayDesc => '名前が収まらない場合の省略方法を選択';

  @override
  String get longFileNameEllipsizeStartLabel => '先頭を省略';

  @override
  String get longFileNameEllipsizeStartDesc => 'ファイル名の先頭を省略し、末尾と拡張子を表示します。';

  @override
  String get longFileNameEllipsizeMiddleLabel => '中間を省略';

  @override
  String get longFileNameEllipsizeMiddleDesc => 'ファイル名の中間を省略し、先頭と拡張子を表示します。';

  @override
  String get longFileNameEllipsizeEndLabel => '末尾を省略';

  @override
  String get longFileNameEllipsizeEndDesc => 'ファイル名の末尾を省略し、先頭を表示します。';

  @override
  String get longFileNameMarqueeLabel => 'スクロール (マーキー)';

  @override
  String get longFileNameMarqueeDesc => 'フルネームを水平方向にゆっくりスクロールします。';

  @override
  String get showItemActionsMenuLabel => '項目の3点リーダーメニューを表示';

  @override
  String get showItemActionsMenuDesc => 'リスト表示でファイルやフォルダに3点のアクションボタンを表示します';

  @override
  String get gridAspectRatioLabel => 'グリッドのアスペクト比';

  @override
  String get gridAspectSquareLabel => '1:1 (正方形)';

  @override
  String get gridAspectLandscapeLabel => '16:9 (横長)';

  @override
  String get gridAspectPortraitLabel => '9:16 (縦長)';

  @override
  String get fileFolderDisplaySectionHeader => 'ファイルとフォルダの表示';

  @override
  String get navigationBarsSectionHeader => 'ナビゲーションとバー';

  @override
  String get columnedListViewColumnsSectionHeader => 'カラム形式リストの列';

  @override
  String get autoHideAppBarLabel => 'スクロール時にアプリバーを自動非表示';

  @override
  String get autoHideAppBarDesc => '下方向にスクロールしたときに上部バーを非表示にして表示領域を最大化';

  @override
  String get useFabForToolbarLabel => 'ツールバーにフローティングボタンを使用';

  @override
  String get useFabForToolbarDesc => '下部バーをフローティングボタンに置き換えて表示領域を最大化';

  @override
  String get bottomSelectionBarLabel => '選択バーを下部に表示';

  @override
  String get bottomSelectionBarDesc => '選択ツールバーを上部ではなく下部に表示';

  @override
  String get clipboardFabTapToPaste => 'タップで貼り付け、長押しで詳細';

  @override
  String get storageLocationsTitle => 'ストレージの場所';

  @override
  String get storageLocationsSubtitle => '内部ストレージ、SDカード、ドキュメントプロバイダー';

  @override
  String get storageLocationsSelectPrompt => 'アクティブなストレージを選択';

  @override
  String get addStorageLocationTitle => 'ストレージの場所を追加';

  @override
  String get addStorageLocationSubtitle => '外部SDカード、USBドライブ、またはフォルダを追加';

  @override
  String get documentProviderSafLabel => 'ドキュメントプロバイダー (SAF)';

  @override
  String get externalStorageLabel => '外部ストレージ';

  @override
  String get renameStorageLocationTitle => '場所の名前を変更';

  @override
  String get removeStorageLocationTitle => '場所を削除';

  @override
  String removeStorageLocationConfirm(String name) {
    return 'ストレージの場所から「$name」を削除しますか？ファイルは削除されません。';
  }

  @override
  String get storageLocationAddedSnack => 'ストレージの場所を追加しました';

  @override
  String get storageLocationUnresolvedError =>
      'その場所に直接アクセスできませんでした。ストレージの権限を確認してください。';

  @override
  String get storageLocationSelfReferenceError =>
      'これはすでにこのアプリのボールトのストレージなので、外部の場所として再度追加することはできません。代わりにボールトの一覧から開いてください。';

  @override
  String get internalStorageSubtitle => '内部ストレージ';

  @override
  String get mediaViewerActionPlayPause => '再生 / 一時停止';

  @override
  String get mediaViewerActionPlaybackMode => '再生モード';

  @override
  String get mediaViewerActionBookmark => 'ブックマーク';

  @override
  String get mediaViewerActionDiagnostics => '診断';

  @override
  String get mediaViewerCustomizeControls => 'コントロールをカスタマイズ...';

  @override
  String get mediaViewerControlsTitle => 'プレーヤーのコントロール';

  @override
  String get mediaViewerControlsReset => 'コントロールを初期状態にリセットしました';

  @override
  String get mediaViewerTransportDisplay => 'トランスポートと表示';

  @override
  String get mediaViewerShowScrubberTitle => 'プログレスバーを表示';

  @override
  String get mediaViewerShowScrubberDesc => '位置と長さのタイムラインスライダーを表示';

  @override
  String get mediaViewerShowCenterTransportTitle => '中央のコントロールを表示';

  @override
  String get mediaViewerShowCenterTransportDesc => '中央に大きな再生/一時停止ボタンを表示';

  @override
  String get mediaViewerShowPrevNextTitle => '次へ・前へボタンを表示';

  @override
  String get mediaViewerShowPrevNextDesc => 'オフにすると再生ボタンのみになります';

  @override
  String get mediaViewerShowStatusBadgeTitle => 'ステータスバッジを表示';

  @override
  String get mediaViewerShowStatusBadgeDesc => 'スライドショーの遅延や静止画像のインジケーターを表示';

  @override
  String get mediaViewerTopBarSection => 'トップバー';

  @override
  String get mediaViewerBottomBarSection => 'ボトムバー';

  @override
  String get mediaViewerUnpinnedSection => '未固定 (オーバーフロー)';

  @override
  String get mediaViewerAllControlsPinned => 'すべてのコントロールが既に固定されています。';

  @override
  String get mediaPlayerControlsTitle => 'メディアプレーヤーの操作設定';

  @override
  String get resumePlaybackTitle => '再生を再開';

  @override
  String get resumePlaybackAskEveryTime => '毎回確認';

  @override
  String get resumePlaybackNever => 'しない';

  @override
  String get resumePlaybackAlways => '常に';

  @override
  String get resumePlaybackPromptTitle => '再生を再開しますか？';

  @override
  String resumePlaybackPromptMessage(String position) {
    return '$position から再開しますか？';
  }

  @override
  String get resumePlaybackStartOver => '最初から';

  @override
  String get resumePlaybackResume => '再開';

  @override
  String get pictureInPictureTitle => '自動ピクチャーインピクチャー';

  @override
  String get pictureInPictureSubtitle => '動画の再生中にアプリを離れるとピクチャーインピクチャーに切り替わります';

  @override
  String get pictureInPictureAction => 'ピクチャーインピクチャー';

  @override
  String get keepAudioPlayingTitle => '閉じた後も音声を再生し続ける';

  @override
  String get keepAudioPlayingSubtitle =>
      'プレーヤーを離れても音声はバックグラウンドで再生され、通知から操作できます';

  @override
  String get mediaControlsResetSuccess => 'メディア操作設定をデフォルトに戻しました';

  @override
  String get playbackAndDisplayHeader => '再生と表示';

  @override
  String get showProgressBarTitle => 'プログレスバー（シークバー）を表示';

  @override
  String get showProgressBarSubtitle => '動画および音声のタイムラインスライダー';

  @override
  String get scrubPreviewStyleTitle => 'シーク時のプレビュー表示';

  @override
  String get scrubPreviewMiniBoxLabel => 'ミニボックス';

  @override
  String get scrubPreviewMiniBoxDesc => 'シークバーの上に小さなサムネイルを表示';

  @override
  String get scrubPreviewFullscreenLabel => '全画面';

  @override
  String get scrubPreviewFullscreenDesc => 'シークバーのドラッグ中、大きなフレームを画面全体に表示';

  @override
  String get showTransportControlsOnPhotosTitle => '写真に再生コントロールを表示';

  @override
  String get showTransportControlsOnPhotosSubtitle =>
      '画像のスライドショー操作を有効化（オフでシンプル表示）';

  @override
  String get statusBadgeTitle => 'ステータスバッジ';

  @override
  String get statusBadgeSubtitle => 'スライドショーのタイマーまたは静止画インジケーターを表示';

  @override
  String get topBarActionsHeader => 'トップバーのアクション';

  @override
  String get topBarActionsEmptyHint => 'アクションをここにドラッグしてトップバーに固定';

  @override
  String get bottomDockActionsHeader => 'ボトムドックのアクション';

  @override
  String get bottomDockActionsEmptyHint => 'アクションをここにドラッグしてボトムドックに固定';

  @override
  String get moreMenuActionsHeader => 'その他メニュー（•••）のアクション';

  @override
  String get moreMenuActionsEmptyHint => 'アクションをここにドラッグしてトップバーのドロップダウンに追加';

  @override
  String get advancedSettingsActionsHeader => '詳細設定アクション（オーバーフロー）';

  @override
  String get advancedSettingsActionsEmptyHint => 'アクションをここにドラッグして詳細設定シートに追加';

  @override
  String get dropHereAtEnd => '末尾にドロップ';

  @override
  String get dragItemsHereToAdd => '+ 項目をここにドラッグしてこのセクションに追加';

  @override
  String get moveToAdvancedSettingsTooltip => '詳細設定に移動';

  @override
  String get noVaultsMounted => 'マウントされた保管庫はありません';

  @override
  String get vaultsMountedSummary => '個の保管庫をマウント中';

  @override
  String get dashboardNavLabel => 'ダッシュボード';

  @override
  String get vaultsSectionTitle => '保管庫';

  @override
  String get vaultStatusMounted => 'マウント済み';

  @override
  String get lockVaultTooltip => '保管庫をロック';

  @override
  String get lockAllVaultsTitle => 'すべてロック';

  @override
  String get safProviderLabel => 'SAF プロバイダー';

  @override
  String get singleFileCryptoTitle => '単一ファイル暗号化';

  @override
  String get singleFileCryptoSubtitle => '保管庫外で暗号化/復号';

  @override
  String get passwordGeneratorTitle => 'パスワード生成ツール';

  @override
  String get contentsLabel => 'コンテンツ';

  @override
  String get totalSizeLabel => '合計サイズ';

  @override
  String folderItemCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個の項目',
      zero: '空',
    );
    return '$_temp0';
  }

  @override
  String get calculatingFolderStats => '計算中…';

  @override
  String get videoGesturesHeader => '動画のジェスチャーとズーム';

  @override
  String get swipeToSeekTitle => 'スワイプでシーク';

  @override
  String get swipeToSeekSubtitle =>
      '画面を水平にスワイプしてシークします。プレイリストでは、項目の切り替えにスワイプではなくナビゲーションボタンを使用する必要があります';

  @override
  String get swipeToDismissTitle => 'スワイプで閉じる';

  @override
  String get swipeToDismissSubtitle =>
      '下にスワイプしてビューアを閉じます。プレイリストが縦にスクロールする場合は、横にスワイプします';

  @override
  String get edgeSwipeBrightnessTitle => '明るさスワイプジェスチャー';

  @override
  String get edgeSwipeBrightnessSubtitle => '左端近くをスワイプして画面の明るさを調整します';

  @override
  String get edgeSwipeVolumeTitle => '音量スワイプジェスチャー';

  @override
  String get edgeSwipeVolumeSubtitle => '右端近くをスワイプして音量を調整します';

  @override
  String get edgeSwipeHudTitle => 'ジェスチャーインジケーターを表示';

  @override
  String get edgeSwipeHudSubtitle => 'スワイプ中にパーセンテージを表示します';

  @override
  String get edgeSwipeWidthTitle => 'エッジゾーンの幅';

  @override
  String get pinchZoomOutTitle => 'ズームアウトを許可';

  @override
  String get pinchZoomOutSubtitle => 'ピンチして動画を通常サイズより縮小します';

  @override
  String get minZoomTitle => '最小ズームレベル';

  @override
  String get holdSpeedMultiplierTitle => '長押し早送り速度';

  @override
  String get holdSpeedMultiplierSubtitle => '動画を長押ししている間の再生速度';

  @override
  String get defaultAspectRatioTitle => 'デフォルトのアスペクト比';

  @override
  String get defaultAspectRatioSubtitle => '動画を開いたときに自動的に適用されます';

  @override
  String get aspectRatioModeLabel => 'アスペクト比';

  @override
  String get aspectRatioBestFit => '最適表示';

  @override
  String get aspectRatioFill => '画面いっぱいに表示';

  @override
  String get aspectRatio16x9 => '16:9';

  @override
  String get aspectRatio4x3 => '4:3';

  @override
  String get aspectRatioCentre => '中央表示';

  @override
  String get autoSyncMenuAction => '自動同期…';

  @override
  String get autoSyncSheetTitle => '自動同期';

  @override
  String get autoSyncSheetIntro =>
      'このフォルダと別のフォルダを自動的に同じ状態に保ちます。同じファイルが両側で変更された場合は、下で別の設定を選ばない限り、両方のバージョンが保持されます。';

  @override
  String get autoSyncTargetSection => '同期先';

  @override
  String get autoSyncChooseFolder => 'フォルダを選択';

  @override
  String get autoSyncTargetNotSetHere =>
      'このルールは別のデバイスで設定されました。このデバイスで使うフォルダを選択してください。';

  @override
  String get autoSyncPickerSideLabel => '同期先';

  @override
  String get autoSyncDirectionSection => '方向';

  @override
  String get autoSyncDirectionTwoWay => '双方向';

  @override
  String get autoSyncDirectionTwoWayHint => 'どちらか一方の変更がもう一方にコピーされます。';

  @override
  String get autoSyncDirectionVaultToTarget => '保管庫からフォルダへ';

  @override
  String get autoSyncDirectionVaultToTargetHint =>
      'バックアップ用: フォルダが保管庫に追従します。フォルダ側の変更は戻されません。';

  @override
  String get autoSyncDirectionTargetToVault => 'フォルダから保管庫へ';

  @override
  String get autoSyncDirectionTargetToVaultHint =>
      'インポート用: 保管庫がフォルダに追従します。保管庫側の変更は戻されません。';

  @override
  String get autoSyncConflictSection => '両側でファイルが変更された場合';

  @override
  String get autoSyncConflictKeepBoth => '両方のバージョンを保持';

  @override
  String get autoSyncConflictKeepBothHint => 'もう一方のバージョンは、名前を変えたコピーとして両側に残ります。';

  @override
  String get autoSyncConflictKeepNewer => '新しい方を保持';

  @override
  String get autoSyncConflictKeepNewerHint => 'どちらが新しいか判断できない場合は両方を保持します。';

  @override
  String get autoSyncConflictVaultWins => '保管庫側を優先';

  @override
  String get autoSyncConflictVaultWinsHint => 'フォルダ側のバージョンは置き換えられます。';

  @override
  String get autoSyncConflictTargetWins => 'フォルダ側を優先';

  @override
  String get autoSyncConflictTargetWinsHint => '保管庫側のバージョンは置き換えられます。';

  @override
  String get autoSyncOptionsSection => 'オプション';

  @override
  String get autoSyncOnUnlockTitle => '保管庫のロック解除時に同期';

  @override
  String get autoSyncLiveTitle => 'ロック解除中は同期を維持';

  @override
  String get autoSyncLiveSubtitle =>
      '保管庫が開いている間、ときどき変更を確認します。すべての変更がすぐに検出されるわけではありません。';

  @override
  String get autoSyncDeleteTitle => '削除も反映';

  @override
  String get autoSyncDeleteSubtitle =>
      '片側で削除したファイルはもう一方でも削除されます。フォルダが予期せず空に見える場合、削除は一時停止されます。';

  @override
  String get autoSyncDeleteSourceAfterImportTitle => 'インポート後に元のファイルを削除';

  @override
  String get autoSyncDeleteSourceAfterImportSubtitle =>
      'フォルダーから保管庫への同期でのみ有効です。保管庫への書き込み完了後、SHA-256チェックサムの一致を確認してから元ファイルを削除します。';

  @override
  String get autoSyncIgnoreLabel => '一致するファイルとフォルダーを除外';

  @override
  String get autoSyncIgnoreHelper =>
      '1行に1パターン：*.tmp は場所を問わず名前に一致します。node_modules はそのフォルダーと中身をすべて除外します。Projects/old は同期ルートからのそのパスと中身を除外します。';

  @override
  String get autoSyncNeverSynced => 'まだ同期されていません';

  @override
  String autoSyncLastSynced(String time) {
    return '最終同期: $time';
  }

  @override
  String autoSyncReportSummary(int copied, int deleted, int kept) {
    return 'コピー $copied 件 · 削除 $deleted 件 · 競合を保持 $kept 件';
  }

  @override
  String autoSyncReportFailed(int count) {
    return '同期できなかったファイル: $count';
  }

  @override
  String get autoSyncReportDeletionsPaused =>
      'フォルダが予期せず空に見えたか、削除されるファイルが多すぎるため、削除を一時停止しました。';

  @override
  String get autoSyncReportIncomplete =>
      'フォルダの一部を読み取れなかったため、それらのファイルには手を付けていません。';

  @override
  String get autoSyncSyncNow => '今すぐ同期';

  @override
  String get autoSyncRemove => '自動同期を解除';

  @override
  String get autoSyncRemoveTitle => '自動同期を解除しますか?';

  @override
  String get autoSyncRemoveMessage => 'このフォルダの同期は停止します。両方のフォルダのファイルはそのまま残ります。';

  @override
  String get autoSyncSaved => '自動同期を保存しました';

  @override
  String get autoSyncStarted => '同期を開始しました';

  @override
  String get autoSyncRemoved => '自動同期を解除しました';

  @override
  String get autoSyncSaveFailed => '自動同期の設定を保存できませんでした';

  @override
  String get autoSyncUnavailable => '現在、この保管庫では同期を利用できません。';

  @override
  String get autoSyncProblemNoTarget => '同期するフォルダを選択してください。';

  @override
  String get autoSyncProblemOverlapsTarget =>
      '同期先のフォルダは、このフォルダの内側にあったり、このフォルダを含んでいたりしてはいけません。';

  @override
  String get autoSyncProblemOverlapsOtherRule =>
      'このフォルダ、またはその上位や内側のフォルダには、すでに自動同期が設定されています。';

  @override
  String get autoSyncProblemTargetIsVault =>
      'このフォルダには保管庫の暗号化されたデータが入っています。保管庫のロックを解除し、代わりに保管庫の一覧から選択してください。';

  @override
  String get autoSyncReadOnlyNotice => 'この保管庫は読み取り専用のため、自動同期を保存できません。';

  @override
  String get autoSyncConfigUnreadable => 'この保管庫に保存されている自動同期の設定を読み取れませんでした。';

  @override
  String autoSyncBannerRunning(String target, int done, int total) {
    return '$target と同期中 · $done/$total';
  }

  @override
  String get autoSyncBannerAttention =>
      '完全に同期できなかったフォルダがあります。詳細はフォルダの自動同期設定で確認してください。';

  @override
  String get autoSyncNotificationTitle => 'フォルダを同期中';

  @override
  String autoSyncNotificationProgress(int done, int total) {
    return '$done/$total ファイル';
  }

  @override
  String get sectionQuickCapture => 'クイックキャプチャ';

  @override
  String get quickCaptureSettingsTitle => 'クイックキャプチャ';

  @override
  String get quickCaptureSettingsSubtitle =>
      '保管庫へ直接キャプチャするためのクイック設定タイルとホーム画面のショートカット';

  @override
  String get quickCaptureTileToggleTitle => 'クイック設定タイル';

  @override
  String get quickCaptureTileToggleSubtitle =>
      'PINやパターンの入力を求めずに、クイック設定からすぐにカメラを開きます。保存する前には、保管庫を選んでロックを解除する必要があります。';

  @override
  String get quickCaptureAddShortcutTitle => 'ホーム画面に追加';

  @override
  String get quickCaptureAddShortcutSubtitle =>
      'ランチャーが対応していれば、クイックキャプチャのアイコンをホーム画面に固定します';

  @override
  String get quickCaptureShortcutRequestedMessage => 'リクエストしました。ホーム画面を確認してください';

  @override
  String get quickCaptureShortcutUnsupportedMessage =>
      'お使いのランチャーはショートカットの固定に対応していません';

  @override
  String quickCaptureSavedToast(String name, String destination) {
    return '$nameを$destinationに保存しました';
  }

  @override
  String get cardSwipeActionsTitle => 'カードのスワイプ操作';

  @override
  String get cardSwipeActionsSubtitle => '保管庫カードをスワイプして編集および削除アクションをすばやく表示します';

  @override
  String get cameraQualitySd => '480p (SD)';

  @override
  String get cameraQualityHd => '720p (HD)';

  @override
  String get cameraQualityFhd => '1080p (FHD)';

  @override
  String get cameraQualityUhd => '4K (UHD)';

  @override
  String get cameraPhotoResMax => 'フル (最高解像度)';

  @override
  String get cameraPhotoResHigh => '5 MP (高画質)';

  @override
  String get cameraPhotoResMedium => '2 MP (標準)';

  @override
  String get cameraPhotoResLow => '1.2 MP (低画質)';

  @override
  String get cameraLensWide => '広角';

  @override
  String get cameraLensInfrared => '赤外線';

  @override
  String get cameraLensFront => '前面';

  @override
  String get appLockBehaviorTitle => 'アプリのロック動作';

  @override
  String get lockAppOnScreenOffTitle => '画面消灯時にアプリをロック';

  @override
  String get lockAppOnScreenOffSubtitle => '画面が消灯するとすぐにロック画面を表示します';

  @override
  String get settingsHubSecuritySubtitle => 'マスターロック、生体認証、自動ロック';

  @override
  String get settingsHubStorageSubtitle => 'ストレージアクセス、バックグラウンド、共有メニュー';

  @override
  String get settingsHubFileHandlingSubtitle => '自動オープン、サムネイル、ファイルの関連付け';

  @override
  String get settingsHubAppearanceSubtitle => 'テーマ、OLED純黒、言語';

  @override
  String get settingsHubAdvancedSubtitle => '設定のバックアップ、デバッグログ、Logcat';

  @override
  String get toolPasswordInterchangeTitle => 'パスワードのインポート／エクスポート';

  @override
  String get toolPasswordInterchangeSubtitle =>
      'KeePass、Bitwarden、その他のパスワードマネージャーとの間でログイン情報、カード、メモを移行';

  @override
  String get toolsSectionPasswordManager => 'パスワードマネージャー';

  @override
  String get passwordInterchangeExportTab => 'エクスポート';

  @override
  String get passwordInterchangeImportTab => 'インポート';

  @override
  String get passwordInterchangeSourceHeader => 'エクスポート元';

  @override
  String get passwordInterchangeChooseFolder => '保管庫フォルダを選択';

  @override
  String get passwordInterchangeIncludeSubfolders => 'サブフォルダを含める';

  @override
  String get passwordInterchangeFormatHeader => '形式';

  @override
  String get passwordInterchangeFormatLabel => 'ファイル形式';

  @override
  String get passwordInterchangeMasterPassword => 'マスターパスワード';

  @override
  String get passwordInterchangeConfirmPassword => 'パスワードを再入力';

  @override
  String get passwordInterchangePasswordsDontMatch => 'パスワードが一致しません';

  @override
  String get passwordInterchangeRunExport => 'エクスポート';

  @override
  String passwordInterchangeExportReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の項目がエクスポート可能',
      one: '1 件の項目がエクスポート可能',
    );
    return '$_temp0';
  }

  @override
  String get passwordInterchangeSaveToDevice => '端末に保存…';

  @override
  String get passwordInterchangeSaved => '保存しました。';

  @override
  String get passwordInterchangeFileHeader => 'ファイル';

  @override
  String get passwordInterchangeChooseFile => 'ファイルを選択…';

  @override
  String get passwordInterchangeReadFile => 'ファイルを読み込む';

  @override
  String passwordInterchangeFoundItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の項目が見つかりました',
      one: '1 件の項目が見つかりました',
    );
    return '$_temp0';
  }

  @override
  String get passwordInterchangeSelectAll => 'すべて選択';

  @override
  String get passwordInterchangeSelectNone => '選択を解除';

  @override
  String passwordInterchangeWarningsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 行を読み込めませんでした',
      one: '1 行を読み込めませんでした',
    );
    return '$_temp0';
  }

  @override
  String get passwordInterchangeDestinationHeader => '保存先';

  @override
  String get passwordInterchangeMirrorFolders => 'フォルダを再現';

  @override
  String passwordInterchangeRunImport(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の項目をインポート',
      one: '1 件の項目をインポート',
    );
    return '$_temp0';
  }

  @override
  String passwordInterchangeImportedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の項目をインポートしました',
      one: '1 件の項目をインポートしました',
    );
    return '$_temp0';
  }

  @override
  String passwordInterchangeSkippedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件の項目をスキップしました',
      one: '1 件の項目をスキップしました',
    );
    return '$_temp0';
  }

  @override
  String autoLockIndicatorLocksAfter(String duration) {
    return '無操作ロック: $duration';
  }

  @override
  String get autoLockIndicatorLocksOnScreenOff => '画面オフ時ロック';

  @override
  String get autoLockIndicatorNeverLocks => '自動ロックしません';

  @override
  String autoLockIndicatorLocksAfterTooltip(String duration) {
    return '無操作が$duration続くとロック（操作中はリセット）';
  }

  @override
  String get badgeExperimental => '実験的';

  @override
  String get createCompositeHintPrompt => 'チャンクを通常のファイルに添付して保管庫を隠しますか？';

  @override
  String get createCompositeHintAction => 'コンポジットウィザードを開く';

  @override
  String get plainDiskImageNotice =>
      '暗号化されていないディスクイメージが検出されました。マウントにパスワードは必要ありません。';

  @override
  String storageLocationUnavailable(String name) {
    return 'ストレージの場所「$name」は利用できないか、切断されています。';
  }

  @override
  String get cameraEditPhotoTooltip => '写真を編集';

  @override
  String get cameraTrimVideoTooltip => '動画をトリミング';

  @override
  String get cameraDiscardMediaTooltip => '破棄';

  @override
  String get cameraSaveMediaTooltip => '金庫に保存';

  @override
  String get cameraContinueCaptureTooltip => '別の写真を撮影';

  @override
  String cameraBatchCount(int count) {
    return '$count枚の写真';
  }

  @override
  String get cameraReviewPhotosTooltip => '撮影した写真を確認';

  @override
  String get vaultItemTypeAuthenticator => 'Authenticator';

  @override
  String get fieldIssuer => 'Issuer';

  @override
  String get fieldAuthenticatorAccount => 'Account';

  @override
  String get fieldSecretKey => 'Secret Key';

  @override
  String get fieldTotpAlgorithm => 'Algorithm (default: SHA1)';

  @override
  String get fieldTotpDigits => 'Digits (default: 6)';

  @override
  String get fieldTotpPeriod => 'Refresh Interval, seconds (default: 30)';

  @override
  String get authenticatorScreenTitle => 'Authenticator';

  @override
  String get authenticatorAppBarTooltip => 'Authenticator codes';

  @override
  String get authenticatorEmptyStateTitle => 'No authenticator codes yet';

  @override
  String get authenticatorEmptyStateMessage =>
      'Add a TOTP secret to a password item, or create a standalone Authenticator item, in any unlocked vault to see live codes here.';

  @override
  String get authenticatorNoVaultsUnlockedMessage =>
      'Unlock a vault to see its authenticator codes here.';

  @override
  String get authenticatorCodeLabel => 'Code';

  @override
  String get authenticatorInvalidSecretError => 'Invalid secret';

  @override
  String get authenticatorAddButtonTooltip => 'Add authenticator';

  @override
  String get authenticatorChooseVaultTitle => 'Choose a vault';

  @override
  String get authenticatorOpenItemTooltip => 'Open item';

  @override
  String get authenticatorNextCodeLabel => '次のコード';

  @override
  String get authenticatorNextCodePrefix => '次';

  @override
  String get authenticatorCopyNextCodeTooltip => '次のコードをコピー';

  @override
  String get authenticatorSettingsTitle => '認証システムの設定';

  @override
  String get authenticatorEnableTitle => '認証システムを有効化';

  @override
  String get authenticatorEnableSubtitle => 'ロック解除された保管庫を自動スキャンして2FAコードを検索';

  @override
  String get authenticatorShowCodesTitle => '確認コードを表示';

  @override
  String get authenticatorShowCodesSubtitle => 'プライバシー保護のためにマスクせず数字を表示する';

  @override
  String get authenticatorSearchPlacementLabel => '検索バーの配置';

  @override
  String get authenticatorPlacementBottom => '下部';

  @override
  String get authenticatorPlacementTop => '上部';

  @override
  String get authenticatorInterchangeSection => 'インポートとエクスポート';

  @override
  String get scanQrCodeTooltip => 'QRコードをスキャン';

  @override
  String get qrScannerTitle => 'QRコードをスキャン';

  @override
  String get qrScannerHint => 'フレーム内にQRコードを合わせてください';

  @override
  String get qrCodeScannedSuccess => 'QRコードを正常にスキャンしました';

  @override
  String get invalidQrCodeError => '有効な2FA QRコードではありません';

  @override
  String get immediateAutoLockOptionSubtitle =>
      '画面が消灯するかアプリがバックグラウンドに移行するとすぐにロックされます';

  @override
  String get autoLockIndicatorLocksImmediately => '即時ロック';

  @override
  String get quickActionLockModeTitle => 'クイック操作後にロック';

  @override
  String get quickActionLockModeSubtitle =>
      'クイックキャプチャまたは共有メニューからの保存時のボールトのロック動作';

  @override
  String get quickActionLockModeLeaveAsFoundLabel => '元の状態を維持';

  @override
  String get quickActionLockModeLeaveAsFoundSubtitle => '保存前にロックされていた場合のみロック';

  @override
  String get quickActionLockModeAlwaysLockLabel => '常にロック';

  @override
  String get quickActionLockModeAlwaysLockSubtitle => '保存後すぐにボールトをロック';

  @override
  String get quickActionLockModeLeaveOpenLabel => 'ロック解除のまま維持';

  @override
  String get quickActionLockModeLeaveOpenSubtitle =>
      'ボールトを開いたままにし、自動ロックタイマーに従う';

  @override
  String get textEditorThemeMenuItem => 'エディタの外観…';

  @override
  String get textEditorThemeSheetTitle => 'エディタの外観';

  @override
  String get textEditorBackgroundSectionTitle => '背景';

  @override
  String get textEditorSyntaxThemeSectionTitle => '構文テーマ';

  @override
  String get textEditorBackgroundMatchTheme => 'テーマに合わせる';

  @override
  String get textEditorBackgroundAmoledBlack => 'AMOLEDブラック';

  @override
  String get textEditorBackgroundDarkSlate => 'ダークスレート';

  @override
  String get textEditorBackgroundClassicLight => 'クラシックライト';

  @override
  String get textEditorBackgroundSepia => 'セピア';

  @override
  String get textEditorSyntaxThemeAuto => '自動';

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
  String get textEditorRelativeLineNumbersLabel => '相対行番号';

  @override
  String get textEditorRelativeLineNumbersDescription =>
      '絶対行番号の代わりにカーソルからの行数を表示';

  @override
  String get textEditorAutoSaveLabel => '自動保存';

  @override
  String get textEditorAutoSaveDescription => '入力を停止したときに変更を自動的に保存します';

  @override
  String get cutTooltip => '切り取り';

  @override
  String get textEditorShowLineNumbersLabel => '行番号を表示';

  @override
  String get textEditorShowLineNumbersDescription => '左端に行番号を表示します';

  @override
  String get textEditorShowAccessoryBarLabel => 'ショートカットバーを表示';

  @override
  String get textEditorShowAccessoryBarDescription => 'キーボードの上に記号やツールを表示します';

  @override
  String textEditorFontSizeLabel(int size) {
    return 'フォントサイズ: $size pt';
  }

  @override
  String get textEditorCustomizeKeyBarLabel => '記号のカスタマイズ';

  @override
  String get textEditorCustomizeKeyBarDescription => '表示する記号を編集および並べ替えます';

  @override
  String get textEditorCustomizeKeyBarTitle => '記号をカスタマイズ';

  @override
  String get textEditorCustomizeKeyBarHint => 'スペース区切りの記号';

  @override
  String get textEditorSaveAsMenuItem => '名前を付けて保存…';

  @override
  String get textEditorSaveAsDialogTitle => '名前を付けて保存';

  @override
  String get textEditorSaveAsFileNameLabel => 'ファイル名';

  @override
  String get textEditorSaveAsButton => '保存';

  @override
  String get textEditorFileAlreadyExistsError => 'この名前のファイルは既に存在します';

  @override
  String get textEditorProjectFilesTitle => 'プロジェクトファイル';

  @override
  String get textEditorCloseTabTooltip => 'タブを閉じる';

  @override
  String get textEditorResetToDefault => 'デフォルトに戻す';

  @override
  String get textEditorLivePreviewTitle => 'ライブプレビュー';

  @override
  String get textEditorWordWrap => 'テキストの折り返し';

  @override
  String get textEditorReadOnly => '読み取り専用';

  @override
  String get selectImageTitle => '画像を選択';

  @override
  String get noImagesFoundMessage => 'このフォルダーに画像は見つかりませんでした。';

  @override
  String get textEditorShowSymbolsBarLabel => '記号バーを表示';

  @override
  String get textEditorShowSymbolsBarDescription => '記号と句読点のショートカットを表示';

  @override
  String get textEditorShowActionsBarLabel => 'アクションバーを表示';

  @override
  String get textEditorShowActionsBarDescription => 'エディタのアクションボタンを表示';

  @override
  String get textEditorCustomizeActionsLabel => 'アクションボタンをカスタマイズ';

  @override
  String get textEditorCustomizeActionsDescription => 'エディタアクションの選択と並べ替え';

  @override
  String get textEditorCustomizeActionsTitle => 'アクションのカスタマイズ';

  @override
  String get actionUndo => '元に戻す';

  @override
  String get actionRedo => 'やり直し';

  @override
  String get actionCursorLeft => 'カーソルを左へ';

  @override
  String get actionCursorRight => 'カーソルを右へ';

  @override
  String get actionSelectWord => '単語を選択';

  @override
  String get actionCopy => 'コピー';

  @override
  String get actionCut => '切り取り';

  @override
  String get actionPaste => '貼り付け';

  @override
  String get actionFind => '検索と置換';

  @override
  String get actionWordWrap => 'テキストの折り返し';

  @override
  String get actionGoToLine => '指定行へ移動';

  @override
  String get actionGoToStart => '先頭へ移動';

  @override
  String get actionGoToEnd => '末尾へ移動';

  @override
  String get actionIndent => 'インデント';

  @override
  String get actionOutdent => 'インデント解除';

  @override
  String get actionFormat => 'コードの整形';

  @override
  String get actionReadOnly => '読み取り専用';

  @override
  String get screenLockOnlyAutoLockOption => '画面ロック時のみ';

  @override
  String get screenLockOnlyAutoLockOptionSubtitle =>
      '画面がオフになった時のみロック — アプリがバックグラウンドになった時はロックされません';

  @override
  String get authenticatorScanQrSubtitle =>
      '単一のコードまたはGoogle認証システムの移行用QRコードをスキャン';

  @override
  String get authenticatorImportBackupsSubtitle =>
      'Aegis、2FAS、Bitwarden、Ente、Proton、またはandOTPのバックアップからインポート';

  @override
  String authenticatorGoogleAuthImportSuccess(int count) {
    return 'Google認証システムから$count件のアカウントをインポートしました';
  }

  @override
  String get authenticatorMultiQrTitle => '追加のQRコードが検出されました';

  @override
  String get authenticatorMultiQrMessage =>
      'Google認証システムはこのエクスポートを複数のQRコードに分割しました。次のコードを今すぐスキャンしますか？';

  @override
  String get authenticatorScanNextQr => '次をスキャン';

  @override
  String authenticatorGoogleAuthImportError(String error) {
    return 'Google認証システムQRコードのインポートに失敗しました: $error';
  }

  @override
  String get passwordInterchangeOptionalPasswordHelper =>
      'このバックアップがパスワードで保護されている場合のみ必要です';

  @override
  String authenticatorSingleAccountImportedHint(String title) {
    return '最初のアカウント（$title）を入力しました。すべてのアカウントをインポートするには認証システム画面でスキャンしてください。';
  }

  @override
  String get authenticatorHotpReadOnlyError =>
      'この保管庫は読み取り専用のため、HOTPカウンターを進めることはできません。';

  @override
  String get authenticatorHotpSaveError => '新しいHOTPカウンターを保存できませんでした。';

  @override
  String get authenticatorGenerateNextCode => '次のコードを生成';

  @override
  String get actionSelectAll => 'すべて選択';

  @override
  String get textEditorSelectAllMenuItem => 'すべて選択';

  @override
  String get textEditorShowCaretScrubberLabel => 'カーソルスクラバーを表示';

  @override
  String get textEditorShowCaretScrubberDescription =>
      'カーソルを正確に移動するためのドラッグストリップ';

  @override
  String get textEditorShowStatusBarLabel => 'ステータスバーを表示';

  @override
  String get textEditorShowStatusBarDescription => '下部に行数と文字数を表示';

  @override
  String textEditorCursorPosition(int line, int column) {
    return '行 $line、列 $column';
  }

  @override
  String get textEditorNewFileTooltip => '新規ファイル';

  @override
  String get textEditorCloseTab => '閉じる';

  @override
  String get textEditorCloseOtherTabs => '他を閉じる';

  @override
  String get textEditorCloseAllTabs => 'すべて閉じる';

  @override
  String get textEditorRevertToSaved => '保存時の状態に戻す';

  @override
  String get textEditorRevertDialogTitle => '変更を破棄しますか？';

  @override
  String get textEditorRevertDialogMessage =>
      '未保存の編集をすべて破棄し、保管庫からファイルを再読み込みしますか？';

  @override
  String get revertButton => '元に戻す';

  @override
  String get textEditorNewFolderTooltip => '新規フォルダー';

  @override
  String get textEditorNewFolderDialogTitle => '新規フォルダー';

  @override
  String get textEditorNewFolderFieldLabel => 'フォルダー名';

  @override
  String get textEditorRenameMenuItem => '名前を変更';

  @override
  String get textEditorRenameDialogTitle => '名前を変更';

  @override
  String get textEditorMoveToMenuItem => '移動...';

  @override
  String get textEditorMoveToDialogTitle => 'フォルダーへ移動';

  @override
  String get textEditorMoveHereButton => 'ここに移動';

  @override
  String get textEditorDeleteMenuItem => '削除';

  @override
  String textEditorDeleteConfirmTitle(String name) {
    return '$name を削除しますか？';
  }

  @override
  String textEditorDeleteConfirmMessage(String name) {
    return '\"$name\" を削除してもよろしいですか？この操作は取り消せません。';
  }

  @override
  String get videoEditorEditAction => 'Edit video';

  @override
  String get videoEditorExportAction => 'Export';

  @override
  String get videoEditorTimelineLabel => 'Video timeline';

  @override
  String get videoEditorSetStart => 'Set start';

  @override
  String get videoEditorSetEnd => 'Set end';

  @override
  String get videoEditorAddSegment => 'Add';

  @override
  String get videoEditorSplit => 'Split';

  @override
  String get videoEditorDeleteSegment => 'Delete';

  @override
  String get videoEditorModeKeep => 'Keep';

  @override
  String get videoEditorModeCutOut => 'Cut out';

  @override
  String get videoEditorNoSegments =>
      'No segments yet. Move the playhead and tap Add.';

  @override
  String videoEditorOutputSummary(int count, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Output: $count clips · $duration',
      one: 'Output: 1 clip · $duration',
    );
    return '$_temp0';
  }

  @override
  String videoEditorSnapNote(String start, String end) {
    return 'Lossless cut starts on a keyframe: $start – $end';
  }

  @override
  String get videoEditorBoundaryInvalid =>
      'That would leave the segment too short.';

  @override
  String get videoEditorNoRoom => 'There is no room for a segment here.';

  @override
  String get videoEditorNothingToExport => 'Nothing to export.';

  @override
  String get videoEditorReadOnly =>
      'This vault is read-only, so the edited video can\'t be saved.';

  @override
  String videoEditorLoadFailed(String message) {
    return 'Couldn\'t open this video: $message';
  }

  @override
  String get videoEditorZoomIn => 'Zoom in';

  @override
  String get videoEditorZoomOut => 'Zoom out';

  @override
  String get videoEditorZoomFit => 'Fit to screen';

  @override
  String get videoEditorPrevFrame => '前のフレーム';

  @override
  String get videoEditorNextFrame => '次のフレーム';

  @override
  String get videoEditorPrevKeyframe => 'Previous keyframe';

  @override
  String get videoEditorNextKeyframe => 'Next keyframe';

  @override
  String get videoEditorExporting => 'Exporting video';

  @override
  String videoEditorCutting(int current, int total) {
    return 'Cutting clip $current of $total';
  }

  @override
  String get videoEditorCuttingOne => 'Cutting…';

  @override
  String get videoEditorSaving => 'Saving…';

  @override
  String videoEditorSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Saved $count videos',
      one: 'Saved 1 video',
    );
    return '$_temp0';
  }

  @override
  String get videoEditorAudioDropped =>
      'Some audio tracks couldn\'t be copied.';

  @override
  String videoEditorExportFailed(String message) {
    return 'Export failed: $message';
  }

  @override
  String get videoEditorExportCancelled => 'Export cancelled';

  @override
  String get videoEditorExportTitle => 'Export';

  @override
  String videoEditorExportSummary(int count, String duration) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count clips · $duration',
      one: '1 clip · $duration',
    );
    return '$_temp0';
  }

  @override
  String get videoEditorExportSingle => 'Save as new video';

  @override
  String get videoEditorExportSingleHint => 'The original stays untouched.';

  @override
  String get videoEditorExportMerge => 'Merge into one video';

  @override
  String get videoEditorExportMergeHint =>
      'Clips are joined in timeline order.';

  @override
  String get videoEditorExportSeparate => 'Save as separate videos';

  @override
  String videoEditorExportSeparateHint(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new files',
      one: 'One new file',
    );
    return '$_temp0';
  }

  @override
  String get videoEditorLosslessNote =>
      'Cuts are lossless, so nothing is re-encoded. Each clip starts at the nearest keyframe before your start point and ends at the next keyframe after your end point. The thin bars under the timeline show exactly what will be saved.';

  @override
  String get videoEditorAnalyzing => '動画を解析中…';

  @override
  String get videoEditorDiscardTitle => '編集を破棄しますか？';

  @override
  String get videoEditorDiscardMessage => '保存されていない変更があります。破棄してもよろしいですか？';

  @override
  String get videoEditorDiscardAction => '破棄';

  @override
  String get videoEditorPreviewCut => 'カットをプレビュー';

  @override
  String get videoEditorSegments => 'セグメント';

  @override
  String get videoEditorReplaceOriginal => '元の動画を置き換える';

  @override
  String get videoEditorReplaceOriginalHint => '元の動画はエクスポートされたカットに置き換えられます。';

  @override
  String get videoEditorCustomFileName => '出力ファイル名';

  @override
  String get videoEditorSubtitlesWarning => '注意：無劣化エクスポートでは埋め込み字幕トラックを保持できません。';

  @override
  String get videoEditorRemoveSection => 'セクションを削除';

  @override
  String get fileSkinScreenTitle => 'ファイルマネージャーのスキン';

  @override
  String get fileSkinSectionHeader => '外観';

  @override
  String get fileSkinEntryTitle => 'スキン';

  @override
  String get fileSkinPreviewHeader => 'プレビュー';

  @override
  String get fileSkinPresetsHeader => 'スキン';

  @override
  String get fileSkinFoldersHeader => 'フォルダ';

  @override
  String get fileSkinFilesHeader => 'ファイル';

  @override
  String get fileSkinTextHeader => 'テキスト';

  @override
  String get fileSkinIconStyleLabel => 'アイコンのスタイル';

  @override
  String get fileSkinContainerLabel => 'アイコンの背景';

  @override
  String get fileSkinIconColorLabel => 'アイコンの色';

  @override
  String get fileSkinCustomIconColorLabel => 'カスタムのアイコン色';

  @override
  String get fileSkinNameColorLabel => '名前の色';

  @override
  String get fileSkinDetailsColorLabel => '詳細の色';

  @override
  String get fileSkinMonospaceLabel => '等幅フォントの名前';

  @override
  String get fileSkinMonospaceDesc => 'ファイル名とフォルダ名に等幅フォントを使用します';

  @override
  String get fileSkinIconFamilyDefault => 'デフォルト';

  @override
  String get fileSkinIconFamilyFilled => '塗りつぶし';

  @override
  String get fileSkinIconFamilyRounded => '丸み';

  @override
  String get fileSkinIconFamilyOutlined => 'アウトライン';

  @override
  String get fileSkinIconFamilySharp => 'シャープ';

  @override
  String get fileSkinContainerFilled => '塗りつぶし';

  @override
  String get fileSkinContainerOutlined => 'アウトライン';

  @override
  String get fileSkinContainerNone => 'なし';

  @override
  String get fileSkinColorAuto => '自動';

  @override
  String get fileSkinColorAccent => 'テーマのアクセント';

  @override
  String get fileSkinColorNeutral => 'ニュートラル';

  @override
  String get fileSkinColorCustom => 'カスタム';

  @override
  String get fileSkinColorDefault => 'デフォルト';

  @override
  String get fileSkinColorHexLabel => '16進カラー';

  @override
  String get fileSkinPresetClassic => 'クラシック';

  @override
  String get fileSkinPresetMinimalOutline => 'ミニマルアウトライン';

  @override
  String get fileSkinPresetFrames => 'フレーム';

  @override
  String get fileSkinPresetVivid => 'ビビッド';

  @override
  String get fileSkinPresetTerminal => 'ターミナル';

  @override
  String get fileSkinPresetCustom => 'カスタム';

  @override
  String get compositeArchiveCarrierBlockingWarning =>
      '続行するには、この選択からアーカイブを削除してください。複合保管庫を追加すると破損するおそれがあるため、アーカイブを複合保管庫のキャリアとして使用できません。';

  @override
  String get compositeArchiveCarrierRowWarning =>
      'サポートされていないアーカイブです。選択から削除してください。';

  @override
  String videoEditorSelectedSegmentSummary(
    int current,
    int total,
    String start,
    String end,
    String duration,
  ) {
    return 'セグメント $current/$total: $start – $end ($duration)';
  }

  @override
  String get videoEditorKeepModeDescription => '選択したセグメントをエクスポートし、それ以外を破棄します。';

  @override
  String get videoEditorCutOutModeDescription =>
      '選択したセグメントを削除し、残りの映像をエクスポートします。';

  @override
  String get tapEdgesToNavigateTitle => '画面端をタップして移動';

  @override
  String get tapEdgesToNavigateSubtitle => '画面の左端または右端をタップして、前または次のメディアを表示します。';

  @override
  String get doubleTapPlayPauseTitle => 'ダブルタップで再生/一時停止';

  @override
  String get doubleTapPlayPauseSubtitle =>
      '動画または音声画面の中央をダブルタップすると、ズームではなく再生または一時停止します。ズーム中に表示されるズームレベルをタップすると、表示がリセットされます。';

  @override
  String get loopPlaylistTitle => 'プレイリストをループ';

  @override
  String get loopPlaylistSubtitle => '移動中または再生中に最後の項目の後で最初の項目に戻ります。';

  @override
  String get showFileNamesInMediaNotificationTitle => 'メディア通知にファイル名を表示';

  @override
  String get showFileNamesInMediaNotificationSubtitle =>
      '復号されたファイル名を通知、ロック画面、接続済みデバイスに表示します。';

  @override
  String get textEditorEncodingTooltip => 'テキストのエンコード';

  @override
  String get textEditorEncodingEncodeError => 'このエンコードでは保存できない文字が含まれています。';

  @override
  String get textEditorShowTabBarLabel => 'エディターのタブを表示';

  @override
  String get textEditorShowTabBarDescription =>
      '開いているファイルのタブを表示または非表示にします。サイドバーからファイルを切り替えることもできます。';

  @override
  String get textEditorAutoHideTabBarLabel => 'スクロール時にタブを隠す';

  @override
  String get textEditorAutoHideTabBarDescription =>
      '下にスクロールするとタブバーを隠し、上にスクロールすると再表示します。';

  @override
  String get lockWaitingForOperationsMessage => 'ロックする前に、進行中の操作が完了するのを待っています…';

  @override
  String get mirrorSyncActivityLabel => '保管庫の変更をストレージに保存中';

  @override
  String get seekGestureSensitivityTitle => 'シークジェスチャーの感度';

  @override
  String get volumeGestureSensitivityTitle => '音量ジェスチャーの感度';

  @override
  String get brightnessGestureSensitivityTitle => '明るさジェスチャーの感度';

  @override
  String get thumbnailSettingsHeader => 'サムネイル生成';

  @override
  String get thumbnailGenerationStrategyTitle => 'サムネイルのフレーム選択方法';

  @override
  String get thumbnailFirstFrameOption => '最初のフレーム';

  @override
  String get thumbnailPercentageFrameOption => '指定位置のフレーム';

  @override
  String get thumbnailHybridOption => 'ハイブリッド（冒頭の空白をスキップ）';

  @override
  String get thumbnailFramePositionTitle => '優先するフレーム位置';

  @override
  String get volumeBoostHeader => '音量ブースト';

  @override
  String get volumeBoostTitle => '音量ブーストを有効にする';

  @override
  String get volumeBoostSubtitle => '音量の小さい動画の音声を通常のプレーヤー音量より大きくします。';

  @override
  String get volumeBoostGainTitle => 'ブースト量';

  @override
  String get decoderSelectionHeader => 'デコーダーの選択';

  @override
  String get videoDecoderTitle => '動画デコーダー';

  @override
  String get audioDecoderTitle => '音声デコーダー';

  @override
  String get decoderAutoOption => '自動';

  @override
  String get decoderHardwareOption => 'ハードウェア';

  @override
  String get decoderSoftwareOption => 'ソフトウェア';

  @override
  String get decoderFfmpegOption => 'FFmpeg';

  @override
  String get autoSyncLocalRootDeleteWarningTitle =>
      'ローカルストレージのルートからファイルを削除しますか？';

  @override
  String get autoSyncLocalRootDeleteWarningMessage =>
      'この一方向同期では、ローカルストレージのルート全体を確認します。「インポート後に元のファイルを削除」が有効な場合、VaultにコピーされたファイルはSHA-256の検証後に端末から削除されます。元のファイルを削除する意図がある場合のみ続行してください。';

  @override
  String get autoSyncLocalRootDeleteWarningConfirm => '理解しました';

  @override
  String get autoSyncScheduledTitle => 'Vault のロック中に毎日実行';

  @override
  String get autoSyncScheduledSubtitle =>
      'アプリを閉じていてもバックグラウンドで実行します。Android により遅延または長時間処理が停止される場合があります。同期後に Vault は再びロックされます。';

  @override
  String get autoSyncScheduledSetupRequired =>
      '完全な自動化アクセスと、保存済みの Vault パスワードが必要です。';

  @override
  String get autoSyncScheduledConfigure => 'バックグラウンドアクセスを設定';

  @override
  String get autoSyncScheduleWarningTitle => 'スケジュール同期を有効にしますか？';

  @override
  String get autoSyncScheduleWarningMessage =>
      'アプリは 1 日に 1 回バックグラウンドでこの Vault をロック解除し、同期後に再びロックします。Android により実行が遅れる場合があります。インポート後の削除が有効な場合、Vault のコピーを書き込み、サイズと SHA-256 ハッシュの一致を確認してから元ファイルを削除します。';

  @override
  String get autoSyncScheduleEnable => 'スケジュールを有効化';

  @override
  String get autoSyncScheduleNotificationRequired =>
      'バックグラウンド同期中に Android が「Vault を同期中...」と表示できるよう、通知を許可してください。';

  @override
  String get autoSyncScheduleFailed => 'ルールは保存されましたが、スケジュール同期を有効にできませんでした。';

  @override
  String get autoSyncSavedScheduled => 'ルールと毎日のスケジュールを保存しました。';

  @override
  String get autoSyncScheduledTimeTitle => 'Daily run time';

  @override
  String get autoSyncScheduledTimeSubtitle =>
      'Device local time. For a quick test, choose a time a minute or two from now; Android may run it later.';

  @override
  String get autoSyncExactAlarmAccessTitle => '毎日の同期に正確なアラームを許可しますか？';

  @override
  String get autoSyncExactAlarmAccessMessage =>
      'アプリを閉じている間に選択した時刻に毎日の同期を開始するには、Android の「アラームとリマインダー」へのアクセスが必要です。次の画面で許可し、ここに戻ってからスケジュール同期をもう一度有効にしてください。';

  @override
  String get autoSyncExactAlarmAccessOpen => '設定を開く';

  @override
  String get autoSyncExactAlarmAccessUnavailable =>
      'Android のアラーム設定を開けませんでした。システム設定で Vault Explorer の「アラームとリマインダー」を有効にして、もう一度お試しください。';

  @override
  String get localStoragePermissionTitle => 'ローカルストレージへのアクセスを許可';

  @override
  String get localStorageGrantAccess => 'アクセスを許可';

  @override
  String get hideStorageLocationsTitle => '保存場所を非表示にしますか？';

  @override
  String get hideStorageLocationsPrompt =>
      'すべてのファイルへのアクセスが許可されませんでした。ローカルストレージと追加した保存場所をサイドバーから非表示にしますか？設定から再表示できます。';

  @override
  String get hide => '非表示';

  @override
  String get mediaViewerActionAdjustments => '調整';

  @override
  String get adjustmentsSheetTitle => '調整';

  @override
  String get adjustmentBrightness => '明るさ';

  @override
  String get adjustmentContrast => 'コントラスト';

  @override
  String get adjustmentSaturation => '彩度';

  @override
  String get adjustmentHue => '色相';

  @override
  String get adjustmentGamma => 'ガンマ';

  @override
  String get adjustmentsApplyToAll => 'すべてのファイルに適用';

  @override
  String get adjustmentsCompareHold => '長押しして比較';

  @override
  String get adjustmentPresetVivid => 'ビビッド';

  @override
  String get adjustmentPresetBlackAndWhite => '白黒';

  @override
  String get adjustmentPresetWarm => '暖色';

  @override
  String get adjustmentPresetCool => '寒色';

  @override
  String get videoFilePropertiesSectionHeader => '動画と音声';

  @override
  String get durationLabel => '再生時間';

  @override
  String get rotationLabel => '回転';

  @override
  String get videoBitrateLabel => '動画ビットレート';

  @override
  String get audioBitrateLabel => '音声ビットレート';

  @override
  String get sampleRateLabel => 'サンプルレート';

  @override
  String get audioChannelsLabel => '音声チャンネル';

  @override
  String get subtitleTracksLabel => '字幕トラック';

  @override
  String get skinActionAccent => 'アクションアクセント';

  @override
  String get skinEmphasisForActionIconsActiveControlsProgressAndLinks =>
      'アクションアイコン、アクティブなコントロール、進行状況、リンクの強調。';

  @override
  String get skinTextAndIconsOnAccentButtons => 'アクセントボタン上のテキストとアイコン';

  @override
  String get skinForegroundForButtonsFilledWithTheActionAccentColor =>
      'アクションアクセントカラーで塗りつぶされたボタンの前景色。';

  @override
  String get skinSelectionAndIconTileBackground => '選択およびアイコンタイルの背景';

  @override
  String get skinSelectedFilesAndVaultFormat076e52 =>
      '選択されたファイルと保管庫形式のアイコンタイルにこの色が使われます。フローティングボタンの塗りつぶしには個別の設定があります。';

  @override
  String get skinTextAndIconsOnSelectionColors => '選択色上のテキストとアイコン';

  @override
  String get skinForegroundForIconTilesAndOtherPrimaryContainerSurfaces =>
      'アイコンタイルおよびその他のプライマリコンテナ表面の前景色。';

  @override
  String get skinSteadyMainAccent => '固定メインアクセント';

  @override
  String get skinAPrimaryAccentThatStaysTheSameInLightAndDarkSurfaces =>
      '明るい表面でも暗い表面でも変わらないプライマリアクセント。';

  @override
  String get skinMutedSteadyMainAccent => '控えめな固定メインアクセント';

  @override
  String get skinASofterVersionOfTheSteadyPrimaryAccent =>
      '固定プライマリアクセントのより柔らかいバージョン。';

  @override
  String get skinTextOnSteadyMainAccent => '固定メインアクセント上のテキスト';

  @override
  String get skinForegroundForPrimaryFixedColors => 'プライマリ固定カラーの前景色。';

  @override
  String get skinMutedTextOnSteadyMainAccent => '固定メインアクセント上の控えめなテキスト';

  @override
  String get skinSecondaryForegroundForPrimaryFixedColors =>
      'プライマリ固定カラーのセカンダリ前景色。';

  @override
  String get skinSecondaryAccent => 'セカンダリアクセント';

  @override
  String get skinSupportingActionsAndLessProminentHighlights =>
      '補助的なアクションと控えめなハイライト。';

  @override
  String get skinTextOnSecondaryAccent => 'セカンダリアクセント上のテキスト';

  @override
  String get skinLabelsAndIconsOnSecondaryColoredAreas =>
      'セカンダリカラー領域上のラベルとアイコン。';

  @override
  String get skinSecondaryBackground => 'セカンダリ背景';

  @override
  String get skinSoftFillForSupportingContent => '補助コンテンツ用の柔らかな塗りつぶし。';

  @override
  String get skinTextOnSecondaryBackgrounds => 'セカンダリ背景上のテキスト';

  @override
  String get skinForegroundForSecondaryContainers => 'セカンダリコンテナの前景色。';

  @override
  String get skinSteadySecondaryAccent => '固定セカンダリアクセント';

  @override
  String get skinASecondaryAccentThatStaysTheSameAcrossSurfaces =>
      '表面に関わらず一貫して保たれるセカンダリアクセント。';

  @override
  String get skinMutedSteadySecondaryAccent => '控えめな固定セカンダリアクセント';

  @override
  String get skinASofterVersionOfTheSteadySecondaryAccent =>
      '固定セカンダリアクセントのより柔らかいバージョン。';

  @override
  String get skinTextOnSteadySecondaryAccent => '固定セカンダリアクセント上のテキスト';

  @override
  String get skinForegroundForSecondaryFixedColors => 'セカンダリ固定カラーの前景色。';

  @override
  String get skinMutedTextOnSteadySecondaryAccent => '固定セカンダリアクセント上の控えめなテキスト';

  @override
  String get skinSecondaryForegroundForSecondaryFixedColors =>
      'セカンダリ固定カラーのセカンダリ前景色。';

  @override
  String get skinExtraAccentColor => '追加のアクセントカラー';

  @override
  String get skinDecorativeHighlightsAndContrastingAccents =>
      '装飾的なハイライトと対照的なアクセント。';

  @override
  String get skinTextOnExtraAccent => '追加のアクセント上のテキスト';

  @override
  String get skinLabelsAndIconsOnTertiaryColoredAreas =>
      'ターシャリカラー領域上のラベルとアイコン。';

  @override
  String get skinExtraAccentBackground => '追加のアクセント背景';

  @override
  String get skinSoftFillForTertiaryContent => 'ターシャリコンテンツ用の柔らかな塗りつぶし。';

  @override
  String get skinTextOnExtraAccentBackgrounds => '追加のアクセント背景上のテキスト';

  @override
  String get skinForegroundForTertiaryContainers => 'ターシャリコンテナの前景色。';

  @override
  String get skinSteadyExtraAccent => '固定追加アクセント';

  @override
  String get skinATertiaryAccentThatStaysTheSameAcrossSurfaces =>
      '表面に関わらず一貫して保たれるターシャリアクセント。';

  @override
  String get skinMutedSteadyExtraAccent => '控えめな固定追加アクセント';

  @override
  String get skinASofterVersionOfTheSteadyTertiaryAccent =>
      '固定ターシャリアクセントのより柔らかいバージョン。';

  @override
  String get skinTextOnSteadyExtraAccent => '固定追加アクセント上のテキスト';

  @override
  String get skinForegroundForTertiaryFixedColors => 'ターシャリ固定カラーの前景色。';

  @override
  String get skinMutedTextOnSteadyExtraAccent => '固定追加アクセント上の控えめなテキスト';

  @override
  String get skinSecondaryForegroundForTertiaryFixedColors =>
      'ターシャリ固定カラーのセカンダリ前景色。';

  @override
  String get skinErrorColor => 'エラー色';

  @override
  String get skinErrorsDestructiveActionsAndInvalidInput =>
      'エラー、破壊的なアクション、無効な入力。';

  @override
  String get skinTextOnErrorColor => 'エラー色上のテキスト';

  @override
  String get skinLabelsAndIconsOnErrorColoredAreas => 'エラー色領域上のラベルとアイコン。';

  @override
  String get skinErrorBackground => 'エラー背景';

  @override
  String get skinSoftFillBehindErrorMessages => 'エラーメッセージの背面の柔らかな塗りつぶし。';

  @override
  String get skinTextOnErrorBackgrounds => 'エラー背景上のテキスト';

  @override
  String get skinForegroundForErrorContainers => 'エラーコンテナの前景色。';

  @override
  String get skinPageBackground => 'ページの背景';

  @override
  String get skinTheMainBackgroundBehindAppContent => 'アプリコンテンツの背後にあるメイン背景。';

  @override
  String get skinMainTextAndIcons => 'メインテキストとアイコン';

  @override
  String get skinPrimaryContentDrawnOnPageAndCardBackgrounds =>
      'ページおよびカードの背景に描画される主要コンテンツ。';

  @override
  String get skinDimmedBackground => '減光された背景';

  @override
  String get skinTheDarkestNeutralSurfaceLayer => '最も暗いニュートラルなサーフェスレイヤー。';

  @override
  String get skinBrightBackground => '明るい背景';

  @override
  String get skinTheLightestNeutralSurfaceLayer => '最も明るいニュートラルなサーフェスレイヤー。';

  @override
  String get skinDeepestCardLayer => '最深部のカードレイヤー';

  @override
  String get skinTheLowestAndQuietestSurfaceContainer => '最も低く控えめなサーフェスコンテナ。';

  @override
  String get skinLowCardLayer => '低位のカードレイヤー';

  @override
  String get skinSubtleCardsAndRecessedAreas => '控えめなカードとくぼんだ領域。';

  @override
  String get skinStandardCardLayer => '標準のカードレイヤー';

  @override
  String get skinCommonCardsAndGroupedContent => '一般的なカードとグループ化されたコンテンツ。';

  @override
  String get skinRaisedCardLayer => '浮き上がったカードレイヤー';

  @override
  String get skinRaisedCardsMenusAndAppBars => '浮き上がったカード、メニュー、アプリバー。';

  @override
  String get skinTopCardLayer => '最上位のカードレイヤー';

  @override
  String get skinProminentPanelsAndSelectedSurfaces => '目立つパネルと選択された表面。';

  @override
  String get skinSecondaryTextAndIcons => 'セカンダリテキストとアイコン';

  @override
  String get skinDetailsHintsAndSupportingLabels => '詳細、ヒント、補足ラベル。';

  @override
  String get skinStrongBorder => '強調された境界線';

  @override
  String get skinVisibleBordersAndSeparators => '目に見える境界線と区切り線。';

  @override
  String get skinSubtleBorder => '控えめな境界線';

  @override
  String get skinQuietOutlinesAndLowEmphasisSeparators => '控えめな輪郭と強調度の低い区切り線。';

  @override
  String get skinShadowTint => '影の色合い';

  @override
  String get skinTintUsedByElevatedSurfaces => '浮き上がった表面で使用される色合い。';

  @override
  String get skinModalBackdrop => 'モーダルの背景';

  @override
  String get skinTintBehindDialogsAndModalSheets => 'ダイアログやモーダルシートの背後の色合い。';

  @override
  String get skinInvertedSurface => '反転サーフェス';

  @override
  String get skinAContrastingSurfaceForInverseElements => '反転要素のための対照的な表面。';

  @override
  String get skinTextOnInvertedSurfaces => '反転サーフェス上のテキスト';

  @override
  String get skinForegroundUsedOverInverseSurfaces => '反転サーフェス上で使用される前景色。';

  @override
  String get skinInvertedMainAccent => '反転メインアクセント';

  @override
  String get skinPrimaryAccentUsedOnInverseSurfaces =>
      '反転サーフェスで使用されるプライマリアクセント。';

  @override
  String get skinElevationTint => 'エレベーションの色合い';

  @override
  String get skinTintAppliedToElevatedSurfaces => '浮き上がった表面に適用される色合い。';

  @override
  String get skinSuccessColor => '成功の色';

  @override
  String get skinCompletedActionsAndPositiveStatus => '完了したアクションとポジティブな状態。';

  @override
  String get skinTextOnSuccessColor => '成功色上のテキスト';

  @override
  String get skinForegroundForSuccessColoredContent => '成功色のコンテンツの前景色。';

  @override
  String get skinSuccessBackground => '成功の背景';

  @override
  String get skinSoftFillBehindPositiveStatusMessages =>
      'ポジティブなステータスメッセージ背面の柔らかな塗りつぶし。';

  @override
  String get skinTextOnSuccessBackgrounds => '成功背景上のテキスト';

  @override
  String get skinForegroundForSuccessContainers => '成功コンテナの前景色。';

  @override
  String get skinWarningColor => '警告色';

  @override
  String get skinCautionAttentionAndPendingStatus => '注意、警告、保留中の状態。';

  @override
  String get skinTextOnWarningColor => '警告色上のテキスト';

  @override
  String get skinForegroundForWarningColoredContent => '警告色コンテンツの前景色。';

  @override
  String get skinWarningBackground => '警告の背景';

  @override
  String get skinSoftFillBehindWarningMessages => '警告メッセージ背面の柔らかな塗りつぶし。';

  @override
  String get skinTextOnWarningBackgrounds => '警告背景上のテキスト';

  @override
  String get skinForegroundForWarningContainers => '警告コンテナの前景色。';

  @override
  String get skinBookmarkColor => 'ブックマークの色';

  @override
  String get skinSavedAndBookmarkedItems => '保存およびブックマークされたアイテム。';

  @override
  String get skinMainActions => 'メインアクション';

  @override
  String get skinPrimaryButtonsSelectionsAndFixedPrimaryAccents =>
      'プライマリボタン、選択、固定プライマリアクセント。';

  @override
  String get skinSupportingAccents => '補助アクセント';

  @override
  String get skinSecondaryAndTertiaryHighlightsAndTheirTextColors =>
      'セカンダリおよびターシャリのハイライトとそのテキスト色。';

  @override
  String get skinErrorMessagesAndDestructiveOrInvalidStates =>
      'エラーメッセージ、破壊的または無効な状態。';

  @override
  String get skinPagesCardsAndText => 'ページ、カード、テキスト';

  @override
  String get skinAppBackgroundsCardsMenusAndForegroundText =>
      'アプリの背景、カード、メニュー、前景色テキスト。';

  @override
  String get skinBordersAndOverlays => '境界線とオーバーレイ';

  @override
  String get skinOutlinesShadowsAndModalBackdrops => '輪郭、影、モーダル背景。';

  @override
  String get skinTapAnyPreviewElement => 'プレビュー要素をタップ';

  @override
  String get skinChooseAnAppFileOrEditorColorToSeeWhatItControls =>
      'アプリ、ファイル、エディタの色を選択して、何が変更されるか確認します。';

  @override
  String get skinCustomizeSkin => 'スキンをカスタマイズ';

  @override
  String get skinLight => 'ライト';

  @override
  String get skinDark => 'ダーク';

  @override
  String get skinApp => 'アプリ';

  @override
  String get skinEditor => 'エディタ';

  @override
  String get skinSkinDetails => 'スキンの詳細';

  @override
  String get skinNameYourSkinAndChooseWhichPaletteToEdit =>
      'スキンに名前を付け、編集するパレットを選択します。';

  @override
  String get skinSkinName => 'スキン名';

  @override
  String get skinMyCustomSkin => 'マイスキン';

  @override
  String get skinLightColors => 'ライトカラー';

  @override
  String get skinDarkColors => 'ダークカラー';

  @override
  String get skinPageAndActions => 'ページとアクション';

  @override
  String get skinTheMainBackgroundTextAndActionColors => 'メインの背景、テキスト、アクションの色。';

  @override
  String get skinAppBar => 'アプリバー';

  @override
  String get skinTheTopNavigationBarIsIndependentFromCardsAndPages =>
      '上部のナビゲーションバーは、カードやページから独立しています。';

  @override
  String get skinTopBarFillColor => 'トップバーの塗りつぶし色。';

  @override
  String get skinTitleAndIcons => 'タイトルとアイコン';

  @override
  String get skinTopBarTextAndIconColor => 'トップバーのテキストとアイコンの色。';

  @override
  String get skinFloatingActionButton => 'フローティングアクションボタン';

  @override
  String get skinItsFillAndIconColorAreSeparateFromSelectionColors =>
      'その塗りつぶしとアイコンの色は選択色から独立しています。';

  @override
  String get skinButtonFill => 'ボタンの塗りつぶし';

  @override
  String get skinBackgroundOfTheRoundButton => '丸い「+」ボタンの背景。';

  @override
  String get skinButtonIcon => 'ボタンアイコン';

  @override
  String get skinIconColorOnTheRoundButton => '丸い「+」ボタンのアイコン色。';

  @override
  String get skinDashboardVaultCards => 'ダッシュボードの保管庫カード';

  @override
  String get skinSetTheBackgroundForLockedAndMountedVaultCards =>
      'ロックされた保管庫とマウントされた保管庫のカード背景を設定します。';

  @override
  String get skinLockedVaultCard => 'ロックされた保管庫カード';

  @override
  String get skinNeutralVaultCardFill => 'ニュートラルな保管庫カードの塗りつぶし。';

  @override
  String get skinMountedVaultCard => 'マウントされた保管庫カード';

  @override
  String get skinSeparateFillForAnUnlockedMountedVault =>
      'ロック解除されマウントされた保管庫用の個別塗りつぶし。';

  @override
  String get skinFineTuneAppColors => 'アプリの色を微調整';

  @override
  String get skinAdvancedMaterialColorsForLessCommonElements =>
      'あまり一般的でない要素用の高度なMaterialカラー。';

  @override
  String get skinStatusAndBookmarkColors => 'ステータスとブックマークの色';

  @override
  String get skinColorsForSuccessWarningsErrorsAndBookmarks =>
      '成功、警告、エラー、ブックマークの色。';

  @override
  String get skinTheCustomSkinIsActive971ce3 =>
      'カスタムスキンはすぐに適用され、ファイルマネージャーとエディタはアプリスキンに従うよう設定されます。';

  @override
  String get skinCustomColorTapToChangeOrReset =>
      'カスタムカラー — タップして変更、またはデフォルトにリセット。';

  @override
  String get skinTapTheColorCircleToChooseAColor => 'カラーサークルをタップして色を選択してください。';

  @override
  String get skinAppBarBackground => 'アプリバーの背景';

  @override
  String get skinTheDashboardAndOtherAppBarsUseThisIndependentColor =>
      'ダッシュボードやその他のアプリバーはこの独立した色を使用します。';

  @override
  String get skinDashboardMenuIcon => 'ダッシュボードメニューアイコン';

  @override
  String get skinTheHamburgerButtonUsesTheAppBarIconColor =>
      'ハンバーガーボタンはアプリバーのアイコン色を使用します。';

  @override
  String get skinDashboardTitle => 'ダッシュボードのタイトル';

  @override
  String get skinTheDashboardTitleUsesTheAppBarForegroundColor =>
      'ダッシュボードのタイトルはアプリバーの前景色を使用します。';

  @override
  String get skinActionLabelAndIcon => 'アクションラベルとアイコン';

  @override
  String get skinTheActionAccentColorsLabelsb08a63 =>
      'アクションアクセントは「保管庫を追加」などのラベルとそのアイコンを着色します。';

  @override
  String get skinDashboardAddButton => 'ダッシュボードの追加ボタン';

  @override
  String get skinTheButtonFillAndPlusIconHaveSeparateSkinColors =>
      'ボタンの塗りつぶしと「+」アイコンには個別のスキンカラーがあります。';

  @override
  String get skinVaultCardAndIconBackground => '保管庫カードとアイコンの背景';

  @override
  String get skinTheIconTileUsesPrimary5c2f93 =>
      'アイコンタイルはPrimary containerを使用します。マウントされた保管庫カードはその色を隆起した表面とブレンドします。';

  @override
  String get skinVaultFormatIconColor => '保管庫形式のアイコン色';

  @override
  String get skinVaultFormatInitialsUseOnPrimaryContainer =>
      '保管庫形式のイニシャルはOn primary containerを使用します。';

  @override
  String get skinVaultStorageDetails => '保管庫ストレージの詳細';

  @override
  String get skinFreeSpaceAndCapacityUseTheSupportingTextColor =>
      '空き容量と総容量は補足テキスト色を使用します。';

  @override
  String get skin17GBFree5GB => '空き 1.7 GB / 5 GB';

  @override
  String get skinVaultStorageProgress => '保管庫ストレージの進行状況';

  @override
  String get skinTheProgressBarUsesTheba7c98 =>
      'プログレスバーはアプリのアクセントを使用し、容量が満たされるにつれてターシャリおよびエラー色に切り替わります。';

  @override
  String get skinLockActionBackground => 'ロックアクションの背景';

  @override
  String get skinTheMountedVaultLockButtonUsesPrimaryContainer =>
      'マウントされた保管庫のロックボタンはPrimary containerを使用します。';

  @override
  String get skinVaultActionsIconColor => '保管庫アクションのアイコン色';

  @override
  String get skinTheOverflowMenuUsesTheSupportingIconColor =>
      'オーバーフローメニューは補足アイコン色を使用します。';

  @override
  String get skinMountedVaultCardBackground => 'マウントされた保管庫カードの背景';

  @override
  String get skinThisIsTheBackgroundOfa8d0d3 =>
      'これはマウントされた保管庫カードの背景です。そのアイコンタイルは引き続きメインアクションカラーを使用します。';

  @override
  String get skinLockedVaultCardBackground => 'ロックされた保管庫カードの背景';

  @override
  String get skinThisColorIsIndependentFromTheAppBarAndMountedVaultCard =>
      'この色はアプリバーやマウントされた保管庫カードとは独立しています。';

  @override
  String get skinLockedVaultFormatIcon => 'ロックされた保管庫の形式アイコン';

  @override
  String get skinLockedVaultIconsUseTheSupportingTextAndIconColor =>
      'ロックされた保管庫のアイコンは補足テキストおよびアイコン色を使用します。';

  @override
  String get skinSharedArchive => '共有アーカイブ';

  @override
  String get skinLockedVaultStatusText => 'ロックされた保管庫のステータステキスト';

  @override
  String get skinTheLockedStatusLabelUsesTheSupportingTextColor =>
      'ロック状態のラベルは補足テキスト色を使用します。';

  @override
  String get skinLockedVaultActionsIcon => 'ロックされた保管庫のアクションアイコン';

  @override
  String get skinVaultActionsMenuBackground => '保管庫アクションメニューの背景';

  @override
  String get skinTheEditAndRemovePopupUsesTheMenuSurfaceColor =>
      '「編集」と「削除」のポップアップはメニューサーフェスカラーを使用します。';

  @override
  String get skinEditMenuItem => '「編集」メニュー項目';

  @override
  String get skinTheEditActionUsesTheRegularForegroundColor =>
      '「編集」アクションは通常の前景色を使用します。';

  @override
  String get skinRemoveMenuItem => '「削除」メニュー項目';

  @override
  String get skinDestructiveActionsUseTheErrorColor => '破壊的なアクションはエラー色を使用します。';

  @override
  String get skinFileManagerAppBar => 'ファイルマネージャーのアプリバー';

  @override
  String get skinFileBrowserToolbarsUseTheSameAppBarBackground =>
      'ファイルブラウザのツールバーは同じアプリバーの背景を使用します。';

  @override
  String get skinFileManagerBackButton => 'ファイルマネージャーの戻るボタン';

  @override
  String get skinToolbarNavigationIconsUseThisColor =>
      'ツールバーのナビゲーションアイコンにこの色が使われます。';

  @override
  String get skinFileManagerTitle => 'ファイルマネージャーのタイトル';

  @override
  String get skinTheCurrentFolderNameUsesTheAppBarForeground =>
      '現在のフォルダ名はアプリバーの前景色を使用します。';

  @override
  String get skinFileManagerAppBarActions => 'ファイルマネージャーのアプリバーアクション';

  @override
  String get skinToolbarActionsUseThisIconColor => 'ツールバーのアクションはこのアイコン色を使用します。';

  @override
  String get skinProjects => 'プロジェクト';

  @override
  String get skinFolder12Items => 'フォルダ · 12項目';

  @override
  String get skinTextFile4KB => 'テキストファイル · 4 KB';

  @override
  String get skinCompressedFile28MB => '圧縮ファイル · 28 MB';

  @override
  String get skin3Items => '3項目';

  @override
  String get skinFileManagerAddButton => 'ファイルマネージャーの追加ボタン';

  @override
  String get skinAddButtonIconColor => '追加ボタンのアイコン色';

  @override
  String get skinThePlusIconUsesTheButtonForegroundColor =>
      '「+」アイコンはボタンの前景色を使用します。';

  @override
  String get skinEditorFileName => 'エディタのファイル名';

  @override
  String get skinTheEditorToolbarUsesTheAppForegroundColor =>
      'エディタツールバーはアプリの前景色を使用します。';

  @override
  String get skinDartUTF8Ln3Col12 => ' 3行, 12列';

  @override
  String get skinTheMainBackgroundBehindThisScreen => 'この画面の背後にあるメインの背景。';

  @override
  String get skinFolderIconColor => 'フォルダアイコンの色';

  @override
  String get skinFileIconColor => 'ファイルアイコンの色';

  @override
  String get skinText => ' : ';

  @override
  String get skinFolderNameColor => 'フォルダ名の色';

  @override
  String get skinFileNameColor => 'ファイル名の色';

  @override
  String get skinFileDetailsColor => 'ファイル詳細の色';

  @override
  String get skinTheSmallerDateSizeAndTypeLabelsUseThisColor =>
      '日付、サイズ、種類などの小さなラベルにこの色が使われます。';

  @override
  String get skinFileOverflowButton => 'ファイルのオーバーフローボタン';

  @override
  String get skinEachRowSThreeDotButtonUsesTheSupportingIconColor =>
      '各行の3点リーダーボタンは補足アイコン色を使用します。';

  @override
  String get skinSelectedFileRow => '選択されたファイル行';

  @override
  String get skinSelectedRowsUseATranslucente0ff21 =>
      '選択された行は半透明のプライマリコンテナハイライトを使用し、ファイルリスト自体はページ背景のままです。';

  @override
  String get skinFileActionsMenuBackground => 'ファイルアクションメニューの背景';

  @override
  String get skinTheFileActionsPopupUsesTheMenuSurfaceColor =>
      'ファイルアクションのポップアップはメニューサーフェスカラーを使用します。';

  @override
  String get skinOpenFileMenuItem => '「ファイルを開く」メニュー項目';

  @override
  String get skinRegularFileActionsUseTheMainTextColor =>
      '通常のアクションはメインテキスト色を使用します。';

  @override
  String get skinOpen => '開く';

  @override
  String get skinDeleteFileMenuItem => '「ファイルを削除」メニュー項目';

  @override
  String get skinEditorBackground => 'エディタの背景';

  @override
  String get skinTheCanvasColorBehindTheCode => 'コードの背後にあるキャンバスの色。';

  @override
  String get skinEditorLineNumbers => 'エディタの行番号';

  @override
  String get skinTheGutterAndLineNumbersBesideTheCode => 'コード横の余白と行番号。';

  @override
  String get skinEditorTextColor => 'コードの文字色';

  @override
  String get skinTheDefaultCodeAndEditorTextColor =>
      '通常のコードに使う既定の文字色です。構文強調表示の文字にはそれぞれの色が使われます。';

  @override
  String get skinEditorCursor => 'エディタカーソル';

  @override
  String get skinTheInsertionCaretColor => '挿入キャレットの色。';

  @override
  String get skinEditorSelectionHighlight => 'エディタの選択ハイライト';

  @override
  String get skinTheBackgroundUsedToHighlightSelectedCode =>
      '選択されたコードのハイライトに使用される背景。';

  @override
  String get skinEditorKeywords => 'キーワード';

  @override
  String get skinEditorKeywordsExplanation =>
      'class、void、return、if などの言語キーワード。';

  @override
  String get skinEditorTypes => '型とクラス';

  @override
  String get skinEditorTypesExplanation => 'クラス名、型、インターフェース。';

  @override
  String get skinEditorStrings => '文字列';

  @override
  String get skinEditorStringsExplanation => '引用符で囲まれたテキストと文字列リテラル。';

  @override
  String get skinEditorNumbers => '数値と値';

  @override
  String get skinEditorNumbersExplanation => '数値リテラル、ブール値、定数。';

  @override
  String get skinEditorFunctions => '関数とメソッド';

  @override
  String get skinEditorFunctionsExplanation => '関数名、メソッド呼び出し、組み込み要素。';

  @override
  String get skinEditorComments => 'コメント';

  @override
  String get skinEditorCommentsExplanation => 'コードコメントとドキュメントブロック。';

  @override
  String get textEditorColorsSectionTitle => 'エディタの色とフォント';

  @override
  String get textEditorSyntaxColorsSectionTitle => '構文要素の色';

  @override
  String get textEditorColorsCustomized => 'カスタム色を適用中';

  @override
  String get textEditorResetColors => '色をデフォルトに戻す';

  @override
  String get textEditorFollowAppSkinNotice => 'エディタの色はアクティブなアプリスキンに従います。';

  @override
  String get textEditorCustomizeColorsIndependently => '個別に色をカスタマイズ';

  @override
  String get textEditorDefaultFromTheme => 'デフォルト（テーマから）';

  @override
  String get skinFileManager => 'ファイルマネージャー';

  @override
  String get skinFolderAndFileGlyphsTilesAndLabelColors =>
      'フォルダとファイルのグリフ、タイル、ラベルの色。';

  @override
  String get skinDetailsTextColor => '詳細テキストの色';

  @override
  String get skinUseTheAppSSupportingTextColor => 'アプリの補足テキスト色を使用';

  @override
  String get skinCustomColor => 'カスタムカラー';

  @override
  String get skinMonospaceFileNames => '等幅フォントのファイル名';

  @override
  String get skinBackgroundBehindTheIcon => 'アイコン背面の背景';

  @override
  String get skinIconColorSource => 'アイコンカラーのソース';

  @override
  String get skinUseTheAppSMainTextColor => 'アプリのメインテキスト色を使用';

  @override
  String get skinTextEditor => 'テキストエディタ';

  @override
  String get skinCanvasGutterCursorSelectionBackgroundAndSyntaxTemplate =>
      'キャンバス、余白、カーソル、選択、背景、シンタックステンプレート。';

  @override
  String get skinGutterAndLineNumbers => '余白と行番号';

  @override
  String get skinCursor => 'カーソル';

  @override
  String get skinSelection => '選択';

  @override
  String get skinEditorBackgroundTemplate => 'エディタの背景テンプレート';

  @override
  String get skinSyntaxTemplate => 'シンタックステンプレート';

  @override
  String get skinTapTheColorCircleToChooseAColor246981 => 'カラーサークルをタップして色を選択';

  @override
  String get skinDefaultVaultExplorerIcons => 'デフォルトのVault Explorerアイコン';

  @override
  String get skinSolidIcons => '塗りつぶしアイコン';

  @override
  String get skinRoundedIcons => '角丸アイコン';

  @override
  String get skinOutlineIcons => 'アウトラインアイコン';

  @override
  String get skinSquareCornerIcons => '直角アイコン';

  @override
  String get skinTintedTileBehindTheIcon => 'アイコン背面の着色タイル';

  @override
  String get skinOutlinedTileBehindTheIcon => 'アイコン背面の輪郭付きタイル';

  @override
  String get skinNoTile => 'タイルなし';

  @override
  String get skinAutomaticFileTypeOrFolderColor => '自動 (ファイル形式またはフォルダの色)';

  @override
  String get skinUseTheMainAppAccent => 'アプリのメインアクセントを使用';

  @override
  String get skinUseAMutedNeutralColor => '控えめなニュートラルカラーを使用';

  @override
  String get skinChooseAColorBelow => '下から色を選択';

  @override
  String get skinUseTheSyntaxThemeBackground => 'シンタックステーマの背景を使用';

  @override
  String get skinPureBlack => 'ピュアブラック';

  @override
  String get skinDarkSlate => 'ダークスレート';

  @override
  String get skinCleanWhite => 'クリーンホワイト';

  @override
  String get skinWarmSepia => 'ウォームセピア';

  @override
  String get skinAutomaticMatchLightOrDarkMode => '自動 (ライトモードまたはダークモードに合わせる)';

  @override
  String get skinSkinExported => 'スキンをエクスポートしました。';

  @override
  String get skinSkinsExported => 'スキンをエクスポートしました。';

  @override
  String get skinRemoveSkin => 'スキンを削除しますか？';

  @override
  String get skinAppSkin => 'アプリスキン';

  @override
  String get skinImportSkins => 'スキンをインポート';

  @override
  String get skinExportSkins => 'スキンをエクスポート';

  @override
  String get skinChooseACoordinatedLookForTheAppFileManagerAndEditor =>
      'アプリ、ファイルマネージャー、エディタに統一されたデザインを選択します。 ';

  @override
  String get skinLightAndDarkSystemThemesUseMatchingPaletteVariants =>
      'ライトおよびダークのシステムテーマは一致するパレットのバリエーションを使用します。';

  @override
  String get skinEditCurrentSkin => '現在のスキンを編集';

  @override
  String get skinCreateASkinFromThisLook => 'このデザインからスキンを作成';

  @override
  String get skinYourSkins => '保存されたスキン';

  @override
  String get skinCustomAppFileManagerAndEditorColors =>
      'カスタムのアプリ、ファイルマネージャー、エディタの色';

  @override
  String get skinMaterialColorsWithLightAndDarkVariants =>
      'ライトとダークのバリエーションを持つMaterialカラー';

  @override
  String get skinTrueBlackEditorAndDarkf97e8f =>
      'OLEDアクセントパレットを備えたピュアブラックのエディタとダークなアプリ表面';

  @override
  String get skinYourEditableAppFileManagerAndEditorColors =>
      '編集可能なアプリ、ファイルマネージャー、エディタの色';

  @override
  String get skinSkinActions => 'スキンアクション';

  @override
  String get skinEditSkin => 'スキンを編集';

  @override
  String get skinExportSkin => 'スキンをエクスポート';

  @override
  String get skinRemoveSkinf09101 => 'スキンを削除';

  @override
  String get skinDragAroundTheRingTo868d62 =>
      'リングの周囲をドラッグして色相を選択し、内部で明暗を調整します。';

  @override
  String get skinQuickColors => 'クイックカラー';

  @override
  String get skinEnterAnExactColor => '正確な色を入力';

  @override
  String get skinOptionalRGBOrARGBValue => 'オプションのRGBまたはARGB値';

  @override
  String get skinRGBARGB => 'RGB / ARGB';

  @override
  String get skinUseThisValue => 'この値を使用';

  @override
  String get skinDefaultLightDark => 'デフォルト ライト / ダーク';

  @override
  String get skinOLEDPureBlack => 'OLED ピュアブラック';

  @override
  String get skinCustomSkin => 'カスタムスキン';

  @override
  String skinImportSucceeded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '# 個のスキンをインポートしました。',
    );
    return '$_temp0';
  }

  @override
  String skinImportFailed(String error) {
    return 'スキンをインポートできませんでした: $error';
  }

  @override
  String skinExportFailed(String error) {
    return 'スキンをエクスポートできませんでした: $error';
  }

  @override
  String skinRemoveConfirmation(String skin) {
    return '「$skin」が保存されたスキンから削除されます。';
  }

  @override
  String skinSelectPreviewElement(String title) {
    return '$title を選択';
  }

  @override
  String skinIconColorForItem(String item) {
    return '$item のアイコン色';
  }

  @override
  String skinNameColorForItem(String item) {
    return '$item の名前の色';
  }

  @override
  String get skinFileIconColorSettingDescription =>
      'この色はファイルマネージャーセクションのアイコン色設定で制御されます。';

  @override
  String get skinFileNameColorSettingDescription =>
      'この色はファイルマネージャーセクションの名前色設定で制御されます。';

  @override
  String get skinExportedSingle => 'スキンをエクスポートしました。';

  @override
  String get skinExportedMultiple => 'スキンをエクスポートしました。';

  @override
  String get skinExportSkinsOnly => 'スキンのみ';

  @override
  String get skinExportSkinsOnlySubtitle => '色とアイコンスタイル。共有しても安全です。';

  @override
  String get skinExportSkinsAndInterface => 'スキンとインターフェース';

  @override
  String get skinExportSkinsAndInterfaceSubtitle =>
      'テーマモード、ツールバーとグリッドのレイアウト、エディターの外観、メディアビューアーのレイアウトも保存します。ご自身のバックアップ用です。';

  @override
  String get skinAppearanceExported => 'スキンとインターフェースをエクスポートしました。';

  @override
  String get skinImportInterfaceTitle => 'インターフェース設定を適用しますか？';

  @override
  String get skinImportInterfaceMessage =>
      'このファイルにはインターフェース設定も含まれています。適用すると、現在のテーマモード、ツールバーとグリッドのレイアウト、エディターの外観、メディアビューアーのレイアウトが置き換えられます。';

  @override
  String get skinImportInterfaceApply => '適用';

  @override
  String get skinImportInterfaceSkip => 'スキンのみ';

  @override
  String get skinInterfaceApplied => 'インターフェース設定を適用しました。';

  @override
  String get automationBatteryHintTitle => 'バックグラウンドでの開始を許可';

  @override
  String get automationBatteryHintMessage =>
      'VaultExplorerが完全に終了している場合、Androidがオートメーションによる保管庫のロック解除をブロックすることがあります。TaskerやMacroDroidなどのアプリがバックグラウンドでロック解除できるように、VaultExplorerのバッテリー使用量を「制限なし」に設定してください。';

  @override
  String get automationBatteryHintButton => 'アプリの設定を開く';

  @override
  String get automationBatterySettingsOpenFailedMessage =>
      'アプリの設定を開けませんでした。「設定」>「アプリ」>「VaultExplorer」>「バッテリー」を開き、「制限なし」を選択してください。';

  @override
  String get skinPreviewMountedVaultName => '個人用保管庫';

  @override
  String get skinPreviewVaultName => '保管庫のタイトル';

  @override
  String get skinMainTextColorAlsoColorsRegularMenuItems =>
      '保管庫のタイトルと通常のメニュー操作は、アプリのメインテキスト色を共有します。';

  @override
  String get skinStatusBannerExamples => 'ステータスバナー';

  @override
  String get skinSuccessBanner => '成功バナー';

  @override
  String get skinWarningBanner => '警告バナー';

  @override
  String get skinErrorBanner => 'エラーバナー';

  @override
  String get skinSuccessBannerUsesSuccessContainer =>
      'バナーの背景とメッセージには成功の色が使用されます。';

  @override
  String get skinWarningBannerUsesWarningContainer =>
      'バナーの背景とメッセージには警告の色が使用されます。';

  @override
  String get skinErrorBannerUsesErrorContainer => 'バナーの背景とメッセージにはエラーの色が使用されます。';

  @override
  String get skinPreviewChangesSaved => '変更が保存されました';

  @override
  String get skinPreviewStorageAlmostFull => 'ストレージの空き容量が少なくなっています';

  @override
  String get skinPreviewCouldNotUnlockVault => '保管庫のロックを解除できませんでした';

  @override
  String get skinSurfaceAndBorderExamples => 'サーフェスと境界線';

  @override
  String get skinFileRowDetailsColor => 'ファイル行の詳細の色';

  @override
  String get skinFileActionOverflowIconColor => 'ファイル行のアクションアイコンの色';

  @override
  String get skinMatchingElementsHighlightTogether => '同じ色の他のプレビュー要素も強調表示されます。';

  @override
  String get skinStatusBannerTextColor => 'バナーテキストにはこの色が使用されます。';

  @override
  String get apkOpenPackageInstaller => 'パッケージインストーラー';

  @override
  String get apkOpenPackageInstallerSubtitle => 'このアプリを端末にインストールします';

  @override
  String get apkOpenAsZip => 'ZIPとして開く';

  @override
  String get apkOpenAsZipSubtitle => '中のファイルを参照して展開します';

  @override
  String get audioEditorEditAction => 'オーディオを編集';

  @override
  String get audioEditorTimelineLabel => 'オーディオのタイムライン';

  @override
  String get audioEditorAnalyzing => 'オーディオを読み込み中…';

  @override
  String audioEditorLoadFailed(String message) {
    return 'このオーディオファイルを開けませんでした: $message';
  }

  @override
  String get audioEditorReadOnly => 'この保管庫は読み取り専用のため、編集したオーディオを保存できません。';

  @override
  String get audioEditorExporting => 'オーディオをエクスポート中';

  @override
  String audioEditorSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 件のオーディオファイルを保存しました',
    );
    return '$_temp0';
  }

  @override
  String get audioEditorExportMerge => '1つのファイルに結合';

  @override
  String get audioEditorExportSeparate => '別々のファイルとして保存';

  @override
  String get audioEditorReplaceOriginal => '元のオーディオを置き換える';

  @override
  String get audioEditorReplaceOriginalHint => '元のファイルは、書き出したカット版に置き換えられます。';

  @override
  String get audioEditorLosslessNote =>
      'カットは劣化なしです。音声は再エンコードされずにコピーされるため、音質は変わりません。カット位置は設定した位置から数ミリ秒ほどずれた、最も近いオーディオフレームになります。タグとカバーアートは引き継がれません。';

  @override
  String get audioEditorCutOutModeDescription => '選択したセグメントを削除し、残りをエクスポートします。';

  @override
  String audioEditorUnsupportedFormat(String format) {
    return '$format ファイルはこのデバイスでは編集できないため、ここで再生はできますがエクスポートはできません。';
  }

  @override
  String get audioEditorPrevCutPoint => '前のカット位置';

  @override
  String get audioEditorNextCutPoint => '次のカット位置';

  @override
  String audioEditorReencodeBanner(String format) {
    return '$format のオーディオはそのままコピーできないため、エクスポート時に AAC (.m4a) へ再エンコードされます。';
  }

  @override
  String get audioEditorReencodeNote =>
      'この形式はそのままコピーできないため、書き出すオーディオは AAC に再エンコードされます。音質は高いままですが、ビット単位では同一になりません。カットは設定した位置どおりになります。タグとカバーアートは引き継がれません。';

  @override
  String get mediaViewerActionAbLoop => 'A-Bリピート';

  @override
  String abLoopStartMarkedMessage(String time) {
    return 'A地点を $time に設定しました。もう一度タップしてB地点を設定してください。';
  }

  @override
  String abLoopStartedMessage(String start, String end) {
    return '$start – $end をリピート再生中';
  }

  @override
  String get abLoopEndTooCloseMessage => 'BはAより後である必要があります。先に進めてから再度タップしてください。';

  @override
  String get abLoopClearedMessage => 'A-Bリピート オフ';

  @override
  String get skinEditorPanelBackground => 'エディターパネルの背景';

  @override
  String get skinEditorPanelBackgroundDescription =>
      'エディターのサイドバーとその他のアクションメニューで共有する背景です。';

  @override
  String get skinFollowAppSkin => 'アプリのスキンに合わせる';

  @override
  String get fileSkinFollowAppSkinDescription =>
      'ファイルとフォルダーのスタイルを選択中のアプリスキンに合わせます。';

  @override
  String get fileSkinUseIndependentStylesDescription =>
      'ここではファイルマネージャー独自のスタイルを設定します。アプリスキンに合わせている場合、以下のプリセットやスタイルを変更すると「アプリのスキンに合わせる」がオフになります。';

  @override
  String get fileSkinManagedByAppSkinTitle => 'ファイルマネージャーはアプリスキンに合わせています';

  @override
  String get fileSkinManagedByAppSkinDescription =>
      'プレビューには現在のアプリスキンが表示されます。以下のプリセットまたはスタイルを変更すると、ファイルマネージャー用の独立したスキンが保存され、「アプリのスキンに合わせる」がオフになります。';

  @override
  String get skinFileManagerIndependentTitle => 'ファイルマネージャーは独立したスキンを使用しています';

  @override
  String get skinFileManagerIndependentDescription =>
      'このアプリスキンでファイルやフォルダーのスタイルを変更しても、ファイルマネージャーが独自のスキンを使用している間は反映されません。「アプリのスキンに合わせる」をオンにすると、このスキンが適用されます。';

  @override
  String get skinChooseOrCreateSkin => 'スキンを選択または作成';

  @override
  String get skinSkinShortcutCustomDescription =>
      'アプリ全体の色と共通トークンを編集します。コンポーネント固有の設定はこのページに残ります。';

  @override
  String get skinSkinShortcutPresetDescription =>
      '内蔵スキンを確認するか、現在の外観からカスタムスキンを作成します。';

  @override
  String get textEditorUseIndependentAppearanceDescription =>
      '以下でエディター専用の背景色と構文テーマを選択します。';

  @override
  String get fileSkinComponentStyling => 'コンポーネントのスタイル';

  @override
  String get textEditorStyling => 'エディターのスタイル';

  @override
  String get audioFilePropertiesSectionHeader => 'オーディオ';

  @override
  String get audioTagsSectionHeader => 'トラック情報';

  @override
  String get artistLabel => 'アーティスト';

  @override
  String get albumLabel => 'アルバム';

  @override
  String get yearLabel => '年';

  @override
  String get genreLabel => 'ジャンル';

  @override
  String get audioTrackLabel => 'トラック';

  @override
  String get bitDepthLabel => 'ビット深度';

  @override
  String get colorModeLabel => 'カラーモード';

  @override
  String get transparencyLabel => '透明度';

  @override
  String get animationLabel => 'アニメーション';

  @override
  String get orientationLabel => '向き';

  @override
  String get densityLabel => 'ピクセル密度';

  @override
  String get encodingLabel => 'エンコード';

  @override
  String get skinEditorCodeTextColorDescription =>
      '通常のコードに使う既定の文字色です。構文強調表示の文字は個別の色を保持します。';

  @override
  String get skinEditorInterfaceText => 'エディターインターフェースの文字色';

  @override
  String get skinEditorInterfaceTextDescription =>
      'エディターのツールバー、サイドバー、メニュー、ステータスバーの文字とアイコンです。';

  @override
  String get equalizerTitle => 'イコライザー';

  @override
  String get equalizerPresetCustom => 'カスタム';

  @override
  String get equalizerPreampLabel => 'プリアンプ';

  @override
  String get equalizerPreventClippingTitle => 'クリッピングを防止';

  @override
  String get equalizerPreventClippingSubtitle =>
      '強調した帯域が歪まないよう、全体の音量を必要な分だけ下げます';

  @override
  String get equalizerPresetFlat => 'フラット';

  @override
  String get equalizerPresetBassBoost => '低音を強調';

  @override
  String get equalizerPresetTrebleBoost => '高音を強調';

  @override
  String get equalizerPresetVoice => 'ボーカル';

  @override
  String get equalizerPresetRock => 'ロック';

  @override
  String get equalizerPresetPop => 'ポップ';

  @override
  String get equalizerPresetJazz => 'ジャズ';

  @override
  String get equalizerPresetClassical => 'クラシック';

  @override
  String get equalizerPresetElectronic => 'エレクトロニック';

  @override
  String get equalizerPresetLoudness => 'ラウドネス';

  @override
  String get audioRecorder => '音声レコーダー';

  @override
  String get audioCapturedEncrypted => '音声を保存しました';

  @override
  String get audioMicPermissionRequiredMessage => '音声を録音するには、マイクの権限が必要です。';

  @override
  String get audioRecordingAllowMicrophone => 'マイクを許可';

  @override
  String get audioRecordingStartTooltip => '録画を開始';

  @override
  String get audioRecordingStopTooltip => '録画を停止';

  @override
  String get audioRecordingPauseTooltip => '一時停止';

  @override
  String get audioRecordingResumeTooltip => '再開';

  @override
  String get audioRecordingPausedLabel => '一時停止中';

  @override
  String get audioRecordingDiscardTitle => '録音を破棄しますか？';

  @override
  String get audioRecordingDiscardMessage => 'この録音は保存されておらず、完全に削除されます。';

  @override
  String get skinAreaDashboard => 'ダッシュボード';

  @override
  String get skinAreaDashboardDescription => '最初に表示される、金庫カードが並ぶ金庫一覧です。';

  @override
  String get skinAreaDrawer => 'サイドメニュー';

  @override
  String get skinAreaDrawerDescription => '金庫やショートカットが配置されたスライド式メニューです。';

  @override
  String get skinAreaFilesDescription => 'ロック解除された金庫内のファイルブラウザです。';

  @override
  String get skinAreaEditorDescription =>
      'テキストおよびコードエディタのツールバーです。キャンバスや構文の色は下の「エディタのテーマ」で設定します。';

  @override
  String get skinAreaToolsDescription => '「ツール」タブおよびそこから開く各ツールです。';

  @override
  String get skinAreaSettingsDescription => '「設定」タブおよびそのサブページです。';

  @override
  String get skinSharedPaletteTitle => '共通パレット';

  @override
  String get skinSharedPaletteShort => '共通';

  @override
  String get skinSharedPaletteDescription =>
      '各ページが独自の色を設定するまで継承する基本色です。ロック解除やカメラなど固有セクションのない画面でそのまま使用されます。';

  @override
  String get skinSharedBarDescription => '独自の色を設定していない全ページのトップバーです。';

  @override
  String get skinSharedFabDescription => '独自の色を設定していない全ページの丸型追加ボタンです。';

  @override
  String get skinPagesTitle => 'ページごとの色';

  @override
  String get skinPagesDescription =>
      '各ページは独自の色を保持します。1つのページを変更しても他のページには影響しません。';

  @override
  String get skinResetPageColors => 'ページの色をリセット';

  @override
  String get skinTokenBackground => 'ページの背景';

  @override
  String get skinTokenBackgroundHint => 'このページのすべての要素の背後にある背景です。';

  @override
  String get skinTokenText => 'メインテキスト';

  @override
  String get skinTokenTextHint => 'このページのタイトル、名前、本文テキストです。';

  @override
  String get skinTokenTextSecondary => 'サブテキストとアイコン';

  @override
  String get skinTokenTextSecondaryHint => '字幕、詳細、ヒント、控えめなアイコンです。';

  @override
  String get skinTokenAppBar => 'トップバー';

  @override
  String get skinTokenAppBarHint => 'このページのトップバーの塗りつぶし色です。';

  @override
  String get skinTokenOnAppBar => 'トップバーのテキストとアイコン';

  @override
  String get skinTokenOnAppBarHint => 'トップバーのタイトルとアイコンの色です。';

  @override
  String get skinTokenCard => 'カードと行';

  @override
  String get skinTokenCardHint => 'カード、リスト行、グループ化されたパネルです。';

  @override
  String get skinTokenCardActive => 'アクティブなカード';

  @override
  String get skinTokenCardActiveHint => 'ロック解除された金庫など、強調表示されているカードです。';

  @override
  String get skinTokenRaised => 'チップとコントロール';

  @override
  String get skinTokenRaisedHint => '検索フィールド、チップ、サムネイル、アイコンタイルです。';

  @override
  String get skinTokenOverlay => 'メニュー・ダイアログ・シート';

  @override
  String get skinTokenOverlayHint => 'このページから開くポップアップメニュー、ダイアログ、ボトムシートです。';

  @override
  String get skinTokenAccent => 'アクセント';

  @override
  String get skinTokenAccentHint => 'ボタン、リンク、進捗バー、アクティブアイコンです。';

  @override
  String get skinTokenOnAccent => 'アクセント上のテキスト';

  @override
  String get skinTokenOnAccentHint => 'アクセント色のボタン上に表示されるラベルとアイコンです。';

  @override
  String get skinTokenSelection => '選択項目';

  @override
  String get skinTokenSelectionHint => '選択された行や強調表示されたアイコンタイルです。';

  @override
  String get skinTokenOnSelection => '選択項目上のテキスト';

  @override
  String get skinTokenOnSelectionHint => '選択された項目上に表示されるアイコンとテキストです。';

  @override
  String get skinTokenDivider => '区切り線';

  @override
  String get skinTokenDividerHint => '細い区切り線と控えめな枠線です。';

  @override
  String get skinTokenOutline => '輪郭線';

  @override
  String get skinTokenOutlineHint => 'アウトラインボタンや入力欄の強調枠線です。';

  @override
  String get skinTokenFab => '丸型追加ボタン';

  @override
  String get skinTokenFabHint => '丸型追加ボタンの塗りつぶし色です。';

  @override
  String get skinTokenOnFab => '丸型追加ボタンのアイコン';

  @override
  String get skinTokenOnFabHint => '丸型追加ボタン上のプラスアイコンです。';

  @override
  String get skinPreviewConfirm => '確認';

  @override
  String get skinPreviewCancelButton => 'キャンセル';

  @override
  String get skinPreviewSaveButton => '保存';

  @override
  String get skinPreviewRunButton => '実行';

  @override
  String get skinPreviewPasteButton => 'ここに貼り付け';

  @override
  String get skinPreviewUnlockButton => 'ロック解除';

  @override
  String get skinPreviewSortChip => '並べ替え: 名前';

  @override
  String get skinPreviewSearchChip => 'ファイルを検索';

  @override
  String get skinPreviewPinnedBadge => '固定済み';

  @override
  String get skinPreviewVaultsHeader => '金庫';

  @override
  String get skinPreviewToolsSection => 'ファイル暗号化';

  @override
  String get skinPreviewToolOne => 'キーファイル・パスフレーズ生成';

  @override
  String get skinPreviewToolOneHint => 'パスワードとキーファイルを生成します';

  @override
  String get skinPreviewToolTwo => 'チェックサム・ハッシュ検証';

  @override
  String get skinPreviewToolTwoHint => '大きなファイルが破損していないかを検証します';

  @override
  String get skinPreviewSettingsSection => 'セキュリティ';

  @override
  String get skinPreviewSettingOne => 'アプリのロック';

  @override
  String get skinPreviewSettingOneHint => '生体認証と自動ロック';

  @override
  String get skinPreviewSettingTwo => 'ストレージ';

  @override
  String get skinPreviewSettingTwoHint => '外部ストレージとクラウドブリッジ';

  @override
  String get inPlaceEditDone => '完了';

  @override
  String get inPlaceEditTitle => 'コントロールを配置';

  @override
  String get inPlaceEditHint => 'バー間でアクションをドラッグするかタップして配置';

  @override
  String get inPlaceEditAvailable => '利用可能なアクション';

  @override
  String get inPlaceEditTopDock => '上部バー';

  @override
  String get inPlaceEditBottomDock => '下部ドック';

  @override
  String get inPlaceEditDragToRemove => 'ここにドラッグして削除';

  @override
  String get inPlaceEditAddToTop => '上部バーに追加';

  @override
  String get inPlaceEditAddToBottom => '下部ドックに追加';

  @override
  String get inPlaceEditEmptyDock => 'ここにアクションをドロップ';

  @override
  String get inPlaceEditPlayerSettings => 'プレーヤー設定';

  @override
  String get inPlaceEditMoveToMore => '詳細メニューに移動';

  @override
  String get inPlaceEditMoveToAdvanced => '詳細設定に移動';

  @override
  String get inPlaceEditHideAction => 'アクションを非表示';

  @override
  String get inPlaceEditHidden => '非表示';

  @override
  String get textEditorAutoHideAppBarLabel => 'アプリバーを自動的に非表示';

  @override
  String get textEditorAutoHideAppBarDescription =>
      '編集中に上部バーを非表示にして垂直方向のスペースを最大化';

  @override
  String get textEditorCopyToMenuItem => 'コピー先...';

  @override
  String get textEditorCopyToDialogTitle => 'フォルダーにコピー';

  @override
  String get textEditorCopyHereButton => 'ここにコピー';

  @override
  String get textEditorDuplicateMenuItem => 'コピーを作成';

  @override
  String get textEditorCopiedSuccessfully => 'コピーしました';

  @override
  String get textEditorSearchFilesHint => 'ファイルを絞り込み…';

  @override
  String get audioRecordingQualityLabel => '音声録音の品質';

  @override
  String get audioRecordingQualityVoice => '音声';

  @override
  String get audioRecordingQualityStandard => '標準';

  @override
  String get audioRecordingQualityHigh => '高';

  @override
  String audioRecordingQualityDetails(String bitrate, String sampleRate) {
    return 'AAC · $bitrate kbps · $sampleRate kHz · モノラル';
  }

  @override
  String get audioEditorCompressTitle => 'ファイルサイズ';

  @override
  String get audioEditorCompressOriginal => 'オリジナル';

  @override
  String audioEditorCompressEstimate(String size) {
    return '推定サイズ: 約 $size';
  }

  @override
  String get audioEditorCompressNote =>
      'オーディオはより低いビットレートで AAC に再エンコードされます。ファイルは小さくなりますが、音質は低下します。カットは設定した位置どおりになります。タグとカバーアートは引き継がれません。';

  @override
  String get entropyStepTitle => 'ランダム性を追加';

  @override
  String get entropyIntro =>
      'パッドの上で指を不規則にいろいろな方向へ動かしてください。動きは、端末の安全な乱数生成器に加えて（置き換えではなく）、暗号鍵とソルトに混ぜ合わされます。';

  @override
  String get entropyPadHint => 'ここを指でなぞってください';

  @override
  String get entropyPadSemantics => 'ランダム性パッド。指でなぞってランダムな動きを集めます。';

  @override
  String entropyProgress(int percent) {
    return 'ランダム性を収集中… $percent%';
  }

  @override
  String get entropyComplete => '十分なランダム性を収集しました。さらに動かして追加するか、次へ進めます。';

  @override
  String get entropySkippedStatus =>
      'スキップしました。端末の安全な乱数生成器のみを使用します。もう一度パッドをなぞると、ランダム性を追加できます。';

  @override
  String get entropyPoolLabel => 'ランダムプール';

  @override
  String get entropySkip => 'スキップして端末の生成器のみ使う';

  @override
  String get entropyReviewLabel => 'ランダム性';

  @override
  String get entropyReviewUserAdded => 'タッチ操作 + 端末の生成器';

  @override
  String get entropyReviewDeviceOnly => '端末の生成器のみ';

  @override
  String get automationCaptureSectionHeader => 'カメラとマイク';

  @override
  String get automationAllowCaptureTitle => 'カメラとマイクの撮影・録音を許可';

  @override
  String get automationAllowCaptureSubtitle => '写真、動画、音声の録音・録画';

  @override
  String get automationPermissionsSectionHeader => '権限';

  @override
  String get automationPermissionsIntro =>
      'これらはAndroidの権限であるため、この保管庫だけでなくアプリ全体に適用されます。この保管庫の設定で使用できる権限のみが、現在のステータスとともに表示されます。';

  @override
  String get automationPermSetupNeededTitle => '設定が必要です';

  @override
  String get automationPermAlmostReadyTitle => 'ほぼ完了';

  @override
  String get automationPermReadyTitle => '準備完了';

  @override
  String get automationPermReadyMessage => 'この保管庫の自動化に必要な設定はすべて整っています。';

  @override
  String get automationPermGrantButton => '許可する';

  @override
  String get automationPermGranted => '許可済み';

  @override
  String get automationPermTagRequired => '必須';

  @override
  String get automationPermTagRecommended => '推奨';

  @override
  String get automationPermTagOptional => '任意';

  @override
  String get automationPermDeniedMessage =>
      '権限が許可されませんでした。今後Androidから確認ダイアログが表示されない場合は、アプリの設定で有効にしてください。';

  @override
  String get automationPermSettingsOpenFailedMessage =>
      'アプリの設定を開けませんでした。「設定 > アプリ > VaultExplorer > 権限」から開いてください。';

  @override
  String get automationPermBatteryTitle => 'バッテリー使用量の無制限';

  @override
  String get automationPermBatteryDescription =>
      'VaultExplorerが完全に終了している状態でも、自動化によってこの保管庫のロックを解除できるようにします。無効の場合、Androidがアクションをブロックすることがあります。';

  @override
  String get automationPermNotificationsTitle => '通知';

  @override
  String get automationPermNotificationsDescription =>
      'インポート、エクスポート、同期の進行状況や、録音・録画実行中のインジケーターを表示します。';

  @override
  String get automationPermAllFilesTitle => 'すべてのファイルへのアクセス';

  @override
  String get automationPermAllFilesDescription =>
      'インポートおよびエクスポートで /storage/emulated/0/… などの通常のファイルパスを使用できるようにします。content:// リンクの場合は不要です。';

  @override
  String get automationPermCameraTitle => 'カメラ';

  @override
  String get automationPermCameraDescription => '自動化によって撮影される写真および動画用。';

  @override
  String get automationPermMicrophoneTitle => 'マイク';

  @override
  String get automationPermMicrophoneDescription =>
      '音声録音および動画の音声用。写真や動画の撮影時にも確認されます。';

  @override
  String get automationPermOverlayDescription =>
      'Android 14以降で、自動化アプリがブロードキャスト経由で写真や動画の撮影を開始する場合にのみ必要です。撮影アクティビティを直接起動する場合は不要です。';

  @override
  String automationPermSetupNeededMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '必要な権限が$count個不足しています。許可されるまで一部の自動化アクションは失敗します。',
    );
    return '$_temp0';
  }

  @override
  String automationPermAlmostReadyMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '推奨設定が$count個オフのままです。自動化は動作しますが、信頼性が低下する可能性があります。',
    );
    return '$_temp0';
  }

  @override
  String get resetSizeOnLayoutChangeLabel => 'レイアウト変更時にサイズをリセット';

  @override
  String get resetSizeOnLayoutChangeDesc =>
      'レイアウトを切り替えるたびに、リストのズームとグリッド／メイソンリーの列数を初期値に戻す';

  @override
  String get thumbnailUseGlobalDefaultDesc =>
      'アプリ設定のサムネイルのデフォルトに従うため、そこでの変更はこの保管庫にも反映されます。';

  @override
  String get resetVaultThumbnailsTitle => 'すべての保管庫をデフォルトに戻す';

  @override
  String get resetVaultThumbnailsSubtitle =>
      '独自の設定を持つ保管庫を含め、すべての保管庫が上記のサムネイルのデフォルトに従うようにします。';

  @override
  String resetVaultThumbnailsConfirmMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個の保管庫が独自のサムネイル設定を持っています。代わりにデフォルトに従わせますか？',
    );
    return '$_temp0';
  }

  @override
  String resetVaultThumbnailsDone(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count個の保管庫がデフォルトに従うようになりました',
    );
    return '$_temp0';
  }

  @override
  String thumbnailGlobalInContainerConfirmMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count個の保管庫がこのデフォルトに従い、保管庫内にサムネイルを保存し始めます。処理が遅くなり、読み取り専用の保管庫では使用できません。',
    );
    return '$_temp0';
  }

  @override
  String get scanAdjustCornersTitle => '角を調整';

  @override
  String get scanResultTitle => 'スキャンしたページ';

  @override
  String get scanAutoDetectButton => '自動検出';

  @override
  String get scanFullImageButton => '画像全体';

  @override
  String get scanFilterColor => 'カラー';

  @override
  String get scanFilterGrayscale => 'グレースケール';

  @override
  String get scanHintSearching => 'カメラを書類に向けてください';

  @override
  String get scanHintFound => '書類を検出しました';

  @override
  String get scanNoDocumentFound => '書類を検出できませんでした。角をドラッグしてページに合わせてください。';

  @override
  String get scanProcessingFailed => 'このページを処理できませんでした';

  @override
  String get scanDetectingEdges => '端を検出中…';

  @override
  String get scanOutputPdf => 'PDF';

  @override
  String get scanOutputImages => '画像';

  @override
  String get scanPdfFailed => 'PDFを作成できませんでした';

  @override
  String get settingsSearchHint => '設定を検索';

  @override
  String get settingsSearchClear => '検索をクリア';

  @override
  String get settingsSearchNoResults => '一致する設定がありません';

  @override
  String get settingsSearchNoResultsHint => '別のキーワードを試すか、スペルを確認してください。';

  @override
  String get settingsSearchUnavailable => 'このオプションは、関連する設定がオンのときにのみ表示されます。';

  @override
  String createArchiveCompressingSubtitle(String count, String size) {
    return '$count を圧縮中 ($size)';
  }

  @override
  String createArchiveInsufficientSpace(String required, String available) {
    return '空き容量が不足しています — $required が必要ですが、空きは $available のみです。';
  }

  @override
  String get createArchiveMediaRecommendation =>
      '圧縮済みメディアファイルを検出しました。CPUとバッテリーを節約するため「無圧縮 (Store)」が自動選択されました。';

  @override
  String get createArchiveNameLabel => 'アーカイブ名';

  @override
  String get createArchiveNameHint => 'archive';

  @override
  String get createArchiveSelectFormatTooltip => '形式を選択';

  @override
  String get createArchiveSecuritySection => 'セキュリティ';

  @override
  String get createArchivePasswordLabel => 'パスワード (省略可能)';

  @override
  String get createArchivePasswordHintText => 'パスワードを入力';

  @override
  String get createArchiveConfirmPasswordLabel => 'パスワードの確認';

  @override
  String get createArchiveConfirmPasswordHint => 'パスワードを再入力';

  @override
  String get passphraseStrengthFair => '普通';

  @override
  String get createArchiveEncryptFilenamesNeedsPassword =>
      'ファイルのプレビューにはパスワードが必要です';

  @override
  String get createArchiveEncryptFilenamesActive => 'ロック解除されるまでファイル一覧を非表示にします';

  @override
  String get createArchiveAdvancedOptions => '詳細設定';

  @override
  String get createArchiveCompressionLevel => '圧縮レベル';

  @override
  String get createArchiveSplitHintZip =>
      '.z01、.z02 … と最後の .zip として保存されます。すべてのパートを同じフォルダーに置いてください。';

  @override
  String get createArchiveSplitHintSevenZip =>
      '.7z.001、.7z.002 … として保存されます。すべてのパートを同じフォルダーに置いてください。';

  @override
  String get createArchiveSplitVolumes => '分割アーカイブ';

  @override
  String get createArchiveSplitVolumeNone => 'なし';

  @override
  String get createArchiveCustomVolumeSizeLabel => 'カスタム分割サイズ (MB)';

  @override
  String get createArchiveCustomVolumeSizeHint => '例: 50';

  @override
  String get archiveCompressionStoreTitle => '無圧縮 (0) — 圧縮なし';

  @override
  String get archiveCompressionStoreDesc => '瞬時にパッケージ化、動画・音楽・アーカイブに最適';

  @override
  String get archiveCompressionFastTitle => '高速 (1–3) — すばやく圧縮';

  @override
  String get archiveCompressionFastDesc => '日常的な共有に適した高速圧縮';

  @override
  String get archiveCompressionNormalTitle => '標準 (5) — バランス';

  @override
  String get archiveCompressionNormalDesc => '圧縮率と速度のバランスが良い';

  @override
  String get archiveCompressionUltraTitle => '最高 (9) — 最小サイズ';

  @override
  String get archiveCompressionUltraDesc => '最小サイズ、圧縮時間は長くなります';

  @override
  String get officeViewerErrorTitle => 'このドキュメントをプレビューできません';

  @override
  String get officeViewerEncrypted =>
      'このドキュメントはパスワードで保護されています。暗号化されたOfficeファイルはプレビューできません。';

  @override
  String get officeViewerUnsupported =>
      'このファイルを読み込めませんでした。破損しているか、ビューアが対応していない形式の可能性があります。';

  @override
  String get officeViewerTooLarge => 'このドキュメントはサイズが大きすぎて、アプリ内でプレビューできません。';

  @override
  String get officeViewerSpeakerNotes => 'スピーカーノート';

  @override
  String get fileAssocDocumentViewer => 'アプリ内ドキュメントビューア';

  @override
  String get viewOfficeDocumentsInApp =>
      'Word、Excel、PowerPoint、OpenDocumentファイルをアプリ内でプレビュー';

  @override
  String get archiveCompressionMethodLabel => '圧縮方式';

  @override
  String get archiveMethodLzma2Desc => '最もバランスの良い選択肢。.tar.xz でも使われます。';

  @override
  String get archiveMethodLzmaDesc => '7-Zip の従来方式。.tar.lzma でも使われます。';

  @override
  String get archiveMethodDeflateDesc =>
      '最速ですがファイルは大きくなります。互換性が最も広く、ZIP や .tar.gz でも使われます。';

  @override
  String archiveMethodFixedInfo(String format, String method) {
    return '$format は常に $method で圧縮します。';
  }

  @override
  String get archiveMethodMoreInSevenZip =>
      'LZMA2 と LZMA は 7-Zip アーカイブで利用できます。';

  @override
  String get archiveMethodStoreNote => '無圧縮では圧縮しないため、選択できる方式はありません。';

  @override
  String get browserTabsEnabledTitle => 'ファイルマネージャーのタブを使用';

  @override
  String get browserTabsEnabledSubtitle => '複数の場所を開いたまま切り替えられます。';

  @override
  String get browserTabNew => '新しいタブ';

  @override
  String get browserTabClose => 'タブを閉じる';

  @override
  String get browserTabCloseOthers => '他のタブを閉じる';

  @override
  String get browserTabDuplicate => 'タブを複製';

  @override
  String get browserTabMoveToOtherPane => 'もう一方のペインに移動';

  @override
  String get browserTabSwitchPrevious => '前のタブに切り替え';

  @override
  String get browserTabOpenInNewTab => '新しいタブで開く';

  @override
  String browserTabLimitReached(int max) {
    return 'タブの上限に達しました（$max）';
  }

  @override
  String get browserTabCloseToLeft => '左側のタブを閉じる';

  @override
  String get browserTabCloseToRight => '右側のタブを閉じる';

  @override
  String get browserTabCloseAll => 'すべて閉じる';

  @override
  String get dualPaneEnabledTitle => '2ペイン表示を使用';

  @override
  String get dualPaneEnabledSubtitle =>
      '画面に十分な幅があるとき、開いている2つのタブを並べて表示します。ファイルマネージャーのタブが必要です。';

  @override
  String get pressBackAgainToExit => 'もう一度戻るを押すと終了します';

  @override
  String get tabEdgeSwipeLabel => 'タブのスワイプ操作';

  @override
  String get tabEdgeSwipeDrawerAndNewTabLabel => 'サイドメニュー / 新しいタブ';

  @override
  String get tabEdgeSwipeDrawerAndNewTabDesc =>
      '最初のタブで右にスワイプするとサイドメニューが開き、最後のタブで左にスワイプすると新しいタブが開きます。';

  @override
  String get tabEdgeSwipeLoopLabel => 'タブをループ';

  @override
  String get tabEdgeSwipeLoopDesc =>
      '最後のタブを越えてスワイプすると最初のタブへ、最初のタブを越えると最後のタブへ移動します。サイドメニューは画面の左端またはメニューボタンから開きます。';

  @override
  String get tabEdgeSwipeNoEdgeActionsLabel => '端では何もしない';

  @override
  String get tabEdgeSwipeNoEdgeActionsDesc =>
      '最初または最後のタブを越えてスワイプしても何も起こりません。サイドメニューは画面の左端またはメニューボタンから、新しいタブはタブバーから開きます。';

  @override
  String get tabEdgeSwipeNoTabSwipingLabel => 'タブ間をスワイプしない';

  @override
  String get tabEdgeSwipeNoTabSwipingDesc =>
      'タブの切り替えはタブバーからのみ行います。どこでも右にスワイプするとサイドメニューが、左にスワイプすると新しいタブが開きます。すべてのタブが最初のタブであるかのように動作します。';

  @override
  String get appBarAtBottomLabel => 'アプリバーを下に表示';

  @override
  String get appBarAtBottomDesc => 'アプリバーを画面の上部から下部に移動し、親指で届きやすくします。';

  @override
  String get selectByIconLabel => 'アイコンのタップで選択';

  @override
  String get selectByIconDesc =>
      'リスト表示で、ファイルまたはフォルダのアイコンをタップすると選択されます。オフにすると、アイコンをタップしても何も起こりません。';

  @override
  String get showFileExtensionsLabel => 'ファイルの拡張子を表示';

  @override
  String get showFileExtensionsDesc => 'ファイル名の末尾に拡張子を表示します。検索中は常に拡張子が表示されます。';

  @override
  String get itemActionsMenuTitle => 'アイテムの操作';

  @override
  String get itemActionsMenuDesc => 'アイテムのメニューと選択メニューに表示する操作と、その並び順を選択します。';

  @override
  String get itemActionsQuickRowHeader => 'クイック操作の行';

  @override
  String get itemActionsMenuListHeader => 'メニューリスト';

  @override
  String get itemActionsMoveToQuickRow => 'クイック操作の行に移動';

  @override
  String get itemActionsMoveToMenuList => 'メニューリストに移動';

  @override
  String get skinEditStarted => 'スキンエディターがオンになりました。どの画面でも浮かぶボタンで色を選んで変更できます。';

  @override
  String get skinEditSaved => 'スキンを保存しました';

  @override
  String get skinEditPickTooltip => '色を変える要素を選ぶ';

  @override
  String get skinEditPickStopTooltip => '選択を終了して通常どおりアプリを操作';

  @override
  String get skinEditDoneTooltip => '保存してスキンエディターを閉じる';

  @override
  String get skinEditHint => '要素をタップすると色を変更できます。スポイトをもう一度タップすると通常どおり操作できます。';

  @override
  String get skinEditLayersTitle => 'この位置の色';

  @override
  String get skinEditAlsoUsedBy => '同じ色は次でも使われています';

  @override
  String get skinEditClosest => 'この色と完全に一致するスキンカラーはありません。最も近い色です。';

  @override
  String get skinEditNoMatch => 'この位置ではスキンカラーが直接使われていません。リストから色を選んでください。';

  @override
  String get skinEditAllColors => 'すべての色';

  @override
  String get skinEditBackToEditor => 'カラーエディターに戻る';

  @override
  String get skinEditStatusInherited => '継承';

  @override
  String get skinEditReset => 'リセット';

  @override
  String get skinEditMoreOptions => 'すべての色とオプション';

  @override
  String get skinEditCollapse => 'パネルを折りたたむ';

  @override
  String get skinEditExpand => 'パネルを展開';

  @override
  String skinEditPageColors(String page) {
    return '$pageの色';
  }

  @override
  String get skinEditDockTop => 'パネルを上に移動';

  @override
  String get skinEditDockBottom => 'パネルを下に移動';

  @override
  String get skinEditEditorIndependent =>
      'テキストエディターは独自の色を使っているため、アプリのスキンに従うよう設定するまで、ここでの変更は反映されません。';

  @override
  String get cameraKeepShootingTooltip => '撮影後もそのまま撮影を続ける';

  @override
  String get cameraSegmentLengthOff => 'オフ';

  @override
  String cameraSegmentLengthMinutes(int minutes) {
    return '$minutes分';
  }

  @override
  String get cameraSegmentLengthTooltip => '録画を分割し、進行に合わせて順次保存する';

  @override
  String get cameraSegmentSpaceMessage =>
      '保管庫に十分な空き容量がありません。録画を停止しました。保存できなかった部分は確認用に保持されています。';

  @override
  String get audioSegmentedStopTitle => '録音を停止しますか？';

  @override
  String get audioSegmentedStopMessage =>
      'これまでに録音された部分はすでに保管庫に保存されています。今すぐ停止して残りを保存しますか？';

  @override
  String get audioSegmentedStopAction => '停止して保存';

  @override
  String get audioUnsavedPartsTitle => '一部のパートが保存されませんでした';

  @override
  String audioUnsavedPartsMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count件の録音パートを保存できませんでした。空き容量を増やして再試行するか、破棄してください。',
    );
    return '$_temp0';
  }

  @override
  String get segmentRetrySave => '再試行';

  @override
  String get imageEditorActionAuto => '自動';

  @override
  String get imageEditorActionFlip => '反転';

  @override
  String get imageEditorActionRotate => '回転';

  @override
  String get imageEditorActionColor => '色';

  @override
  String get imageEditorActionSize => 'サイズ';

  @override
  String get imageEditorActionOpacity => '不透明度';

  @override
  String get imageEditorActionStyle => 'スタイル';

  @override
  String get imageEditorExportSave => 'エクスポート / 保存';

  @override
  String get imageEditorRevertOriginal => '元に戻す';

  @override
  String get imageEditorTuneImageToolLabel => '画像調整';

  @override
  String get imageEditorLooksToolLabel => 'スタイル';

  @override
  String get imageEditorLookCurrent => '現在';

  @override
  String get imageEditorLookPortrait => 'ポートレート';

  @override
  String get imageEditorLookDramatic => 'ドラマチック';

  @override
  String get imageEditorLookVintage => 'ビンテージ';

  @override
  String get imageEditorTuneAmbiance => 'アンビアンス';

  @override
  String get imageEditorTuneWarmth => '色温度';

  @override
  String get imageEditorTuneShadows => 'シャドウ';

  @override
  String get imageEditorCropAspectDin => 'DIN';

  @override
  String get imageEditorAngle => '角度';

  @override
  String get fontSizeSmall => '小';

  @override
  String get fontSizeMedium => '中';

  @override
  String get fontSizeLarge => '大';

  @override
  String get fontSizeExtraLarge => '特大';

  @override
  String get imageEditorTextPlaceholder => 'ダブルタップしてテキストを変更';

  @override
  String get imageEditorFontSizePreview => 'サンプルプレビュー ABC 123';

  @override
  String imageEditorPhotoLabel(int index) {
    return '写真 $index';
  }
}
