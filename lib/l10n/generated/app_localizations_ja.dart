// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

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
  String get useThisPasswordButton => 'Use This Password';

  @override
  String get quickPasswordGeneratorSheetTitle => 'Password Generator';

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
  String get exportSettingsSubtitle => 'アプリの設定とファイルマネージャーのレイアウトをファイルに保存します';

  @override
  String get importSettingsTitle => '設定をインポート';

  @override
  String get importSettingsSubtitle => 'ファイルからアプリの設定とファイルマネージャーのレイアウトを復元します';

  @override
  String get importSettingsConfirmTitle => '設定をインポートしますか？';

  @override
  String get importSettingsConfirmMessage =>
      '現在のアプリ設定とファイルマネージャーのレイアウトが置き換えられます。この操作は元に戻せません。';

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
  String get videoCapturedEncrypted => '動画を撮影して暗号化しました';

  @override
  String get photoCapturedEncrypted => '写真を撮影して暗号化しました';

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
  String get savingToVault => '保管庫に保存中…';

  @override
  String get noVaultSelected => '保管庫が選択されていません';

  @override
  String get mediaDiagnosticsTitle => 'メディア診断';

  @override
  String get advancedViewerSettingsTitle => 'ビューア設定';

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
  String get aboutPrivacySecuritySubtitle =>
      'ネットワークアクセスなし、暗号化されていないデータをディスクに書き込むことは一切ありません';

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
      '• mbedTLS v3.6.0（ARMv8ハードウェア暗号化 & SHA-2）\n• libavif & libgav1（ネイティブAVIF画像デコーダー）\n• ChaN FatFs v4.0.4（FAT12/16/32 & exFAT）\n• Tuxera NTFS-3G & 組み込みmkntfs\n• e2fsprogs v1.47.4 libext2fs（ext2/ext3/ext4）\n• Dislocker Virtual I/O（BitLocker FVE / To Go）\n• VeraCrypt 1.26.29（Twofish、Serpent、Camellia、Kuznyechik、Whirlpool、Streebog、BLAKE2s、Argon2id/i）\n• cJSON v1.7.18（LUKS2 & Cryptomatorのメタデータ）';

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
  String get privacyPointNoDiskLeaksTitle => '暗号化されていないディスク漏洩ゼロ';

  @override
  String get privacyPointNoDiskLeaksBody =>
      '復号と再暗号化はすべてシステムメモリ内で行われます。暗号化されていない一時ファイルがデバイスストレージに保存されることは一切ありません。';

  @override
  String get privacyPointNoAnalyticsTitle => '分析・テレメトリなし';

  @override
  String get privacyPointNoAnalyticsBody =>
      'クラッシュレポート、利用状況の追跡、あなたやあなたのデバイスに関するデータを収集するサードパーティ製SDKは一切ありません。';

  @override
  String get privacyPointKeystoreTitle => '秘密情報はAndroid Keystore内に保持';

  @override
  String get privacyPointKeystoreBody =>
      '記憶されたパスワード、パターン、キャッシュされた導出鍵は、ハードウェアに支えられたAndroid Keystore内でAES-256-GCMを使って封印されます。';

  @override
  String get privacyPointPosixTitle => 'POSIXアクセラレーションとストレージアクセス';

  @override
  String get privacyPointPosixBody =>
      'フォルダ保管庫内のファイルは、可能な場合は直接読み書きされ、大きなフォルダに対して低速なAndroidのSAF層を回避します。';

  @override
  String get privacyPointScreenClipboardTitle => '画面とクリップボードの保護';

  @override
  String get privacyPointScreenClipboardBody =>
      'スクリーンショット／タスク切り替えプレビューのブロック（FLAG_SECURE）に加え、ウィンドウがフォーカスされた際に破損したクリップボードを自動的にサニタイズします。アイテムボールトからコピーされたパスワードはAndroid 13以降で機密情報としてマークされ、未使用の場合は30秒後に自動的に消去されます。';

  @override
  String get privacyPointMaskModeTitle => 'マスクモード';

  @override
  String get privacyPointMaskModeBody =>
      'アプリを、動作するzipアーカイブブラウザとして異なるアイコンと名前で偽装できます（任意）。タイトルを2秒間長押しすると、実際の保管庫にアクセスできます。';

  @override
  String get privacyPointExternalLinksTitle => '外部リンクはブラウザで開きます';

  @override
  String get privacyPointExternalLinksBody =>
      'リンクをタップすると、その処理はデフォルトのブラウザアプリに引き渡されます。';

  @override
  String get truncatedListingWarning =>
      '最初の50,000件を表示しています — このフォルダにはさらに多くのファイルがあります。';

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
    return '空き$free・合計$total';
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
  String get rememberPerFolderLayoutLabel => 'フォルダごとのレイアウトを記憶';

  @override
  String get rememberPerFolderLayoutDesc =>
      'フォルダごとに個別の表示レイアウト（リスト、グリッド、マソンリー）を保存します';

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
  String get automationTierFullLabel => 'ロック解除／ロック + ファイルのインポート・エクスポート';

  @override
  String get automationTierFullSubtitle =>
      '自動化は、この保管庫のロックが解除されている間、ファイルのインポート・エクスポートも行えます';

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
      'このボールトに対して自動化からTAKE_PHOTO／START_RECORDING／STOP_RECORDINGを実行できるようにします。フルアクセスでも既定でオフです。ファイルのインポート／エクスポートと異なり、写真撮影は画面上の表示が一切不要なため、別途明示的なオプトインとしています。';

  @override
  String get automationAllowCameraCapture => 'カメラ撮影を許可';

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
