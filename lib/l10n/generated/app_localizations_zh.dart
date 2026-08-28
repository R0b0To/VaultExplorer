// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get cancel => '取消';

  @override
  String get close => '关闭';

  @override
  String get search => '搜索';

  @override
  String get goBack => '返回';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => '跳转到页面';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return '页码（1-$pageCount）';
  }

  @override
  String get pdfViewerPageLabel => '页面';

  @override
  String get pdfViewerGoButton => '跳转';

  @override
  String get pdfViewerSearchHint => '在文档中搜索';

  @override
  String get pdfViewerNoMatches => '无匹配结果';

  @override
  String get pdfViewerPreviousMatch => '上一个匹配项';

  @override
  String get pdfViewerNextMatch => '下一个匹配项';

  @override
  String get pdfViewerCloseSearch => '关闭搜索';

  @override
  String get pdfViewerPrintTooltip => '打印文档';

  @override
  String get pdfViewerLoadingDocument => '正在加载文档…';

  @override
  String get pdfViewerCannotOpenTitle => '无法打开PDF';

  @override
  String get pdfViewerFailedToLoad => '加载PDF失败';

  @override
  String get pdfViewerEditTooltip => '编辑';

  @override
  String get pdfViewerDoneEditingTooltip => '完成编辑';

  @override
  String get pdfViewerSaveFailed => '无法保存对此PDF的更改';

  @override
  String get pdfViewerEditUnavailable => '此文档不支持编辑';

  @override
  String get paste => '粘贴';

  @override
  String get clear => '清除';

  @override
  String get clipboardVerbMove => '移动';

  @override
  String get clipboardVerbCopy => '复制';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb（$count）— 点击查看详情，长按粘贴';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb（$count）— 剪贴板详情';
  }

  @override
  String clipboardSourceLabel(String source) {
    return '来源：$source';
  }

  @override
  String get clipboardDefaultSourceName => '保险库';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个项目',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '还有$count个',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => '高级参数';

  @override
  String get pimFieldLabel => 'PIM（留空使用默认值）';

  @override
  String get encryptionAlgorithmLabel => '加密算法';

  @override
  String get hashAlgorithmLabel => '哈希算法';

  @override
  String get clipboardVerbMoving => '正在移动';

  @override
  String get clipboardVerbCopying => '正在复制';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个项目',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return '，来自“$source”';
  }

  @override
  String get clipboardOpenContainerToPaste => '打开一个容器以粘贴';

  @override
  String get keyfilesOptionalLabel => '密钥文件（可选）';

  @override
  String get addFile => '添加文件';

  @override
  String get noKeyfilesAttached => '未附加密钥文件';

  @override
  String get completed => '已完成';

  @override
  String get dismiss => '关闭';

  @override
  String byteProgressText(String transferred, String total, int pct) {
    return '$transferred / $total（$pct%）';
  }

  @override
  String countProgressText(int done, int total, int pct) {
    return '$done / $total（$pct%）';
  }

  @override
  String multiOpLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个传输任务',
    );
    return '$_temp0';
  }

  @override
  String multiOpSublabel(String summary) {
    return '$summary・点击查看全部';
  }

  @override
  String get thumbnailSizeResolutionLabel => '缩略图大小（分辨率）';

  @override
  String get jpegCompressionQualityLabel => 'JPEG压缩质量';

  @override
  String get done => '完成';

  @override
  String get confirm => '确认';

  @override
  String get couldNotPickKeyfiles => '无法选择密钥文件';

  @override
  String get filesystemLabelEncryptedVault => '这个加密保险库';

  @override
  String get filesystemLabelThisContainer => '这个容器';

  @override
  String get nounFile => '文件';

  @override
  String get nounFolder => '文件夹';

  @override
  String get nounFileCapitalized => '文件';

  @override
  String get nounFolderCapitalized => '文件夹';

  @override
  String get unitBytes => '字节';

  @override
  String get unitCharacters => '个字符';

  @override
  String get validationEmptyName => '名称不能为空。';

  @override
  String validationReservedNavName(String name, String noun) {
    return '“$name”是保留的导航名称，不能用作$noun名称。';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return '在$fsLabel上，名称中位置$position处的“$char”不被允许。';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return '位置$position包含一个不可打印的控制字符（代码$code），$fsLabel不允许使用该字符。';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '“$name”是$fsLabel上的保留设备名称（匹配CON、PRN、AUX、NUL、COM0–9或LPT0–9），无论是否带文件扩展名都不能使用。';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return '在$fsLabel上，$noun名称不能以空格结尾';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return '在$fsLabel上，$noun名称不能以“.”结尾';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return '此名称长度为$length$unit；$fsLabel允许每个$noun名称最多$maxLength$unit。';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return '完整路径长度为$length个字符；$fsLabel最多允许$maxLength个字符。';
  }

  @override
  String conflictSameType(String noun, String name) {
    return '此处已存在名为“$name”的$noun。';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return '此处已存在名为“$name”的$existingNoun——它不能与$candidateNoun共用同一个名称。';
  }

  @override
  String get readOnlyContainerWarning => '此容器已以只读方式挂载。';

  @override
  String get hiddenVolumeProtectionTriggeredWarning =>
      '对此外部卷的写入本会损坏隐藏卷，因此已被阻止。此容器在本次会话的剩余时间内已切换为只读。';

  @override
  String get protectHiddenVolumeToggleTitle => '保护隐藏卷';

  @override
  String get protectHiddenVolumeToggleSubtitle => '防止因写入外部卷而造成的损坏';

  @override
  String get protectHiddenVolumeCredentialsRequired => '需要隐藏卷的密码或密钥文件才能对其进行保护';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '删除$count个项目？',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning => '这些项目将被永久删除，包括所选文件夹中的全部内容。';

  @override
  String get deleteFilesWarning => '这些项目将从您的加密卷中永久清除。';

  @override
  String get delete => '删除';

  @override
  String get remove => '移除';

  @override
  String get create => '创建';

  @override
  String get rename => '重命名';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '重命名$count个项目',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => '新建文件夹';

  @override
  String get newTextFileTitle => '新建文本文件';

  @override
  String get folderNameHint => '文件夹名称';

  @override
  String get filenameHint => '文件名.txt';

  @override
  String get newNameHint => '新名称';

  @override
  String get baseNameHint => '基础名称';

  @override
  String couldntCreateItem(String name) {
    return '无法创建“$name”——请检查容器是否仍处于挂载状态';
  }

  @override
  String couldntRenameSingle(String name) {
    return '无法重命名“$name”——可能已存在同名项目';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '无法重命名$count个项目：$reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '无法重命名$count个项目',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize => '请输入大于0的有效隐藏卷大小';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter => '隐藏卷大小必须小于外部卷大小';

  @override
  String get hiddenVolumeErrorTooLargeForContainer => '隐藏卷大小对此容器大小来说过大';

  @override
  String get hiddenVolumeErrorCredentialsRequired => '创建隐藏卷时需要提供隐藏密码或密钥文件';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      '隐藏卷的凭据（密码、PIM和密钥文件）不能与外部卷的凭据相同。';

  @override
  String get vaultItemTypePassword => '密码';

  @override
  String get vaultItemTypePaymentCard => '支付卡';

  @override
  String get vaultItemTypeIdentity => '身份证件';

  @override
  String get vaultItemTypeSecureNote => '安全笔记';

  @override
  String get vaultItemTypeBankAccount => '银行账户';

  @override
  String get vaultItemTypeSoftwareLicense => '软件许可证';

  @override
  String get fieldUsernameEmail => '用户名 / 邮箱';

  @override
  String get fieldPassword => '密码';

  @override
  String get fieldWebsiteUrl => '网站URL';

  @override
  String get fieldTotpSecret => 'TOTP密钥（双重验证）';

  @override
  String get fieldNotes => '备注';

  @override
  String get fieldCardholderName => '持卡人姓名';

  @override
  String get fieldCardNumber => '卡号';

  @override
  String get fieldExpiryMMYY => '有效期（MM/YY）';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldIssuingBank => '发卡银行';

  @override
  String get fieldFullName => '全名';

  @override
  String get fieldDateOfBirth => '出生日期';

  @override
  String get fieldNationality => '国籍';

  @override
  String get fieldPassportNumber => '护照号码';

  @override
  String get fieldPassportExpiry => '护照有效期';

  @override
  String get fieldNationalIdSsn => '身份证号 / 社会保障号';

  @override
  String get fieldDriversLicense => '驾照';

  @override
  String get fieldAddress => '地址';

  @override
  String get fieldPhone => '电话';

  @override
  String get fieldEmail => '邮箱';

  @override
  String get fieldNote => '备注';

  @override
  String get fieldBankName => '银行名称';

  @override
  String get fieldAccountHolder => '账户持有人';

  @override
  String get fieldAccountNumber => '账号';

  @override
  String get fieldRoutingSortCode => '银行代码 / 分行代码';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => '账户类型';

  @override
  String get fieldProductName => '产品名称';

  @override
  String get fieldLicenseKey => '许可证密钥';

  @override
  String get fieldRegisteredTo => '注册人';

  @override
  String get fieldPurchaseDate => '购买日期';

  @override
  String get fieldExpiryRenewalDate => '到期 / 续订日期';

  @override
  String get fieldDownloadUrl => '下载链接';

  @override
  String get fieldRegistrationEmail => '注册邮箱';

  @override
  String get titleRequired => '标题为必填项';

  @override
  String newTypeTitle(String typeLabel) {
    return '新建$typeLabel';
  }

  @override
  String editItemTitle(String title) {
    return '编辑$title';
  }

  @override
  String get save => '保存';

  @override
  String typeNameHint(String typeLabel) {
    return '$typeLabel名称';
  }

  @override
  String get titleSectionLabel => '标题';

  @override
  String get fieldsSectionLabel => '字段';

  @override
  String get encryptedStorageHint => '所有字段均以加密方式存储在容器内。';

  @override
  String copiedSuffix(String fieldLabel) {
    return '已复制$fieldLabel';
  }

  @override
  String get copy => '复制';

  @override
  String get failedToSaveCheckMounted => '保存失败——请检查容器是否仍处于挂载状态';

  @override
  String get discardChangesTitle => '放弃更改？';

  @override
  String get discardChangesMessage => '未保存的更改将会丢失。';

  @override
  String get discard => '放弃';

  @override
  String get keepEditing => '继续编辑';

  @override
  String get deleteItemTitle => '删除项目？';

  @override
  String deleteItemMessage(String title) {
    return '“$title”将从保险库中永久删除。';
  }

  @override
  String get removeFromBookmarks => '从收藏中移除';

  @override
  String get addToBookmarks => '添加到收藏';

  @override
  String get edit => '编辑';

  @override
  String labelCopiedToClipboard(String label) {
    return '$label已复制到剪贴板';
  }

  @override
  String get noFieldsFilledIn => '尚未填写任何字段。\n点击编辑以添加详细信息。';

  @override
  String get sectionLabelDetails => '详细信息';

  @override
  String get sectionLabelInfo => '信息';

  @override
  String get metaLabelType => '类型';

  @override
  String get metaLabelCreated => '创建时间';

  @override
  String get metaLabelModified => '修改时间';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return '复制$fieldLabel';
  }

  @override
  String get readOnlyCantAddItemsTooltip => '只读——无法添加项目';

  @override
  String get extractArchive => '解压压缩包';

  @override
  String get newItemTooltip => '新建项目';

  @override
  String get camera => '相机';

  @override
  String get importFiles => '导入文件';

  @override
  String get importFolder => '导入文件夹';

  @override
  String get secureItem => '安全项目';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archive Explorer';

  @override
  String get archiveExplorerPermissionTitle => '需要存储访问权限';

  @override
  String get archiveExplorerPermissionMessage =>
      '允许访问您的文件，以便浏览和解压“下载”文件夹中的.zip压缩包。';

  @override
  String get archiveExplorerGrantAccess => '授予访问权限';

  @override
  String get archiveExplorerEmptyTitle => '未找到压缩包';

  @override
  String get archiveExplorerEmptyMessage => '您下载的zip文件将显示在此处。';

  @override
  String get archiveExplorerRefreshTooltip => '刷新';

  @override
  String archiveExplorerEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个项目',
    );
    return '$_temp0';
  }

  @override
  String get archiveExplorerExtractAll => '全部解压';

  @override
  String get archiveExplorerExtracting => '正在解压…';

  @override
  String archiveExplorerExtractSuccess(int count, String name) {
    return '已将$count个文件解压到Download/Extracted/$name';
  }

  @override
  String get archiveExplorerExtractFailed => '无法解压该压缩包。';

  @override
  String get archiveExplorerOpenFailed => '无法打开该压缩包。';

  @override
  String get archiveExplorerOpenArchive => '打开压缩包…';

  @override
  String get archiveExplorerUnresolvedPath => '无法直接访问该文件。请尝试从“下载”中选择一个文件。';

  @override
  String get archiveExplorerExtractTo => '解压到…';

  @override
  String get archiveExplorerPreview => '预览';

  @override
  String get archiveExplorerChoosingDestination => '正在选择目标位置…';

  @override
  String get archiveExplorerNoDestinationChosen => '未选择目标位置。';

  @override
  String archiveExplorerExtractSuccessTo(int count, String path) {
    return '已将$count个文件解压到$path';
  }

  @override
  String get archiveBrowserEmptyTitle => '空文件夹';

  @override
  String get archiveBrowserEmptyMessage => '此文件夹不包含任何文件。';

  @override
  String get archiveBrowserRoot => '压缩包';

  @override
  String get archiveBrowserOpenFileFailed => '无法打开该文件。';

  @override
  String get fileAssocInAppTextEditor => '应用内文本编辑器';

  @override
  String get fileAssocInAppMediaViewer => '应用内媒体查看器';

  @override
  String fileAssocAppPrefix(String name) {
    return '应用：$name';
  }

  @override
  String get fileAssocExternalApp => '外部应用';

  @override
  String get appSettingsTitle => '应用设置';

  @override
  String get sectionSecurityPrivacy => '安全与隐私';

  @override
  String get sectionAppearanceInterface => '外观与界面';

  @override
  String get sectionVaultFileHandling => '保险库与文件处理';

  @override
  String get masterPasswordTitle => '主密码';

  @override
  String get masterPasswordActiveSubtitle => '已启用——点击开关即可移除';

  @override
  String get masterPasswordInactiveSubtitle => '打开应用时需要密码';

  @override
  String get newPasswordLabel => '新密码';

  @override
  String get masterPasswordFieldLabel => '主密码';

  @override
  String get confirmPasswordLabel => '确认密码';

  @override
  String get update => '更新';

  @override
  String get setPassword => '设置密码';

  @override
  String get biometricUnlockTitle => '生物识别解锁';

  @override
  String get biometricUnlockSubtitle => '进行身份验证以安全挂载容器';

  @override
  String get changeMasterPasswordTitle => '更改主密码';

  @override
  String get changeMasterPasswordSubtitle => '更新主密码凭据';

  @override
  String get autoLockContainersTitle => '自动锁定容器';

  @override
  String get autoLockContainersSubtitle => '闲置一段时间后自动锁定已打开的保险库';

  @override
  String get autoLockTimeoutLabel => '自动锁定超时时间';

  @override
  String get immediately => '立即';

  @override
  String nMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count分钟',
    );
    return '$_temp0';
  }

  @override
  String get blockScreenshotsTitle => '阻止截屏';

  @override
  String get blockScreenshotsSubtitle => '阻止截屏并在最近任务中隐藏预览';

  @override
  String get keepVaultsRunningInBackgroundTitle => '在后台保持保险库运行';

  @override
  String get keepVaultsRunningInBackgroundSubtitle =>
      '显示通知，并在您离开应用后使已打开的保险库保持可用。保险库密钥会一直保留在内存中，直到锁定为止。';

  @override
  String get notificationPermissionDeniedMessage =>
      '通知权限被拒绝。保险库仍会保持打开，但不会显示持续通知。';

  @override
  String get discreteModeTitle => '伪装模式';

  @override
  String get discreteModeActiveSubtitle => '已启用——应用当前显示为“Archive Explorer”';

  @override
  String get discreteModeInactiveSubtitle => '在主屏幕上将此应用伪装成zip压缩包浏览器';

  @override
  String get enableDiscreteModeTitle => '启用伪装模式？';

  @override
  String get disableDiscreteModeTitle => '关闭伪装模式？';

  @override
  String get enableDiscreteModeMessage =>
      '主屏幕上的应用图标和名称将变为“Archive Explorer”。它将作为zip压缩包浏览及解压工具运行。\n\n要访问您的保险库，请打开Archive Explorer，并长按标题2秒。';

  @override
  String get disableDiscreteModeMessage => '主屏幕上的应用图标和名称将恢复为“Vault Explorer”。';

  @override
  String get enable => '启用';

  @override
  String get disable => '禁用';

  @override
  String get discreteModeEnabledSnack => '伪装模式已启用。应用即将关闭——请从新的启动器图标重新打开。';

  @override
  String get discreteModeDisabledSnack => '伪装模式已关闭。应用即将关闭——请从新的启动器图标重新打开。';

  @override
  String get failedToChangeDiscreteMode => '更改伪装模式失败';

  @override
  String get cacheDerivedKeysTitle => '默认缓存派生密钥';

  @override
  String get cacheDerivedKeysSubtitle => '将派生密钥材料存储在Keystore中以加快解锁速度';

  @override
  String get appThemeLabel => '应用主题';

  @override
  String get systemDefault => '系统默认';

  @override
  String get lightTheme => '浅色主题';

  @override
  String get darkTheme => '深色主题';

  @override
  String get useMaterialYouTitle => '使用Material You';

  @override
  String get useMaterialYouSubtitle => '使应用颜色与壁纸相匹配（Android 12+）';

  @override
  String get sortContainersByLabel => '容器排序方式';

  @override
  String get swapCardSwipeActionsTitle => '交换卡片滑动操作';

  @override
  String get swapCardSwipeActionsSubtitle => '滑动卡片时，左侧显示编辑，右侧显示移除';

  @override
  String get swipeGestureHintTitle => '滑动手势提示';

  @override
  String get swipeGestureHintSubtitle => '在第一个容器上显示卡片预览动画';

  @override
  String get autoOpenOnUnlockTitle => '解锁后自动打开';

  @override
  String get autoOpenOnUnlockActiveSubtitle => '解锁保险库后自动打开';

  @override
  String get autoOpenOnUnlockInactiveSubtitle => '仅解锁保险库并停留在仪表盘';

  @override
  String get enableJsHtmlTitle => '在HTML查看器中启用JavaScript';

  @override
  String get jsEnabledSubtitle => '已为本地HTML文件启用JavaScript';

  @override
  String get jsDisabledSubtitle => '已为本地HTML文件禁用JavaScript';

  @override
  String get fastStorageAccessTitle => '快速存储访问';

  @override
  String get fastStorageAccessGrantedSubtitle => '已授予所有文件访问权限（最高速度）';

  @override
  String get fastStorageAccessNotGrantedSubtitle => '在系统设置中授予所有文件访问权限以获得最佳速度';

  @override
  String get enableFastStorageAccessTitle => '启用快速存储访问';

  @override
  String get enableFastStorageAccessMessage =>
      '授予“所有文件访问权限”可让Vault Explorer执行直接的POSIX文件操作，将文件夹保险库的性能提升高达1000倍。';

  @override
  String get disableStorageAccessTitle => '关闭存储访问权限';

  @override
  String get disableStorageAccessMessage =>
      'Android要求在系统设置中关闭“所有文件访问权限”。是否打开设置将其关闭？';

  @override
  String get enableStoragePermissionLegacyTitle => '允许存储访问';

  @override
  String get enableStoragePermissionLegacyMessage =>
      'Vault Explorer需要存储权限才能执行直接文件操作，从而提升文件夹保险库的性能。系统现在会请求您确认。';

  @override
  String get disableStoragePermissionLegacyMessage =>
      'Android要求在系统设置中关闭存储权限。是否打开设置将其关闭？';

  @override
  String get openSettings => '打开设置';

  @override
  String get androidFileProviderTitle => 'Android文件提供程序';

  @override
  String get androidFileProviderSubtitle => '默认将新容器公开给Android文件选择器';

  @override
  String get thumbnailCachingDefaultLabel => '缩略图缓存（默认）';

  @override
  String get thumbnailQualityDefaultLabel => '缩略图质量（默认）';

  @override
  String get fileAssociationsHeader => '文件关联';

  @override
  String get noFileAssociationsYet => '尚无已记住的文件关联。打开文件时系统会提示您选择。';

  @override
  String get defaultActionsHeader => '打开非标准文件时的默认操作：';

  @override
  String get removeAssociationTooltip => '移除关联';

  @override
  String get sectionBackupRestore => '备份';

  @override
  String get exportSettingsTitle => '导出设置';

  @override
  String get exportSettingsSubtitle => '将应用设置和文件管理器布局保存到文件';

  @override
  String get importSettingsTitle => '导入设置';

  @override
  String get importSettingsSubtitle => '从文件恢复应用设置和文件管理器布局';

  @override
  String get importSettingsConfirmTitle => '导入设置？';

  @override
  String get importSettingsConfirmMessage => '这将替换您当前的应用设置和文件管理器布局。此操作无法撤销。';

  @override
  String get exportSettingsSuccessMessage => '设置已导出';

  @override
  String get importSettingsSuccessMessage => '设置已导入';

  @override
  String get exportSettingsErrorMessage => '无法导出设置';

  @override
  String get importSettingsInvalidFileMessage => '该文件不是有效的设置导出文件';

  @override
  String get sectionDebug => '调试';

  @override
  String get debugLoggingTitle => '调试日志';

  @override
  String get debugLoggingSubtitle => '记录容器操作的详细诊断日志';

  @override
  String get logcatTitle => 'Logcat';

  @override
  String get logcatSubtitle => '查看并保存设备日志';

  @override
  String logcatSavedMessage(String path) {
    return '日志已保存到$path';
  }

  @override
  String get logcatSaveErrorMessage => '保存日志失败';

  @override
  String get logcatCopiedMessage => '日志已复制到剪贴板';

  @override
  String get logcatUnavailableMessage => '此设备不支持Logcat';

  @override
  String get logcatEmptyMessage => '正在等待日志行…';

  @override
  String get logcatClearTooltip => '清除日志';

  @override
  String get logcatSaveTooltip => '保存日志';

  @override
  String get logcatFilterAppOnly => '仅应用';

  @override
  String get logcatFilterAll => '所有日志';

  @override
  String get logcatSearchHint => '搜索日志…';

  @override
  String get logcatClearedMessage => '日志已清除';

  @override
  String get logcatCopyTooltip => '复制日志';

  @override
  String get retryButton => '重试';

  @override
  String get aboutAppTitle => '关于VaultExplorer';

  @override
  String versionInfoSubtitle(String version) {
    return '版本 $version · 开源许可证及详细信息';
  }

  @override
  String get failedToSaveSettings => '保存设置失败';

  @override
  String get masterPasswordSetSnack => '主密码已设置';

  @override
  String get passwordCannotBeEmpty => '密码不能为空';

  @override
  String get atLeast4CharsRequired => '至少需要4个字符';

  @override
  String get passwordsDoNotMatch => '两次输入的密码不一致';

  @override
  String get failedToHashPassword => '密码哈希处理失败——请重试';

  @override
  String get languageLabel => '语言';

  @override
  String get biometricNotAvailable => '此设备不支持生物识别';

  @override
  String get unlockVaultExplorerReason => '解锁VaultExplorer';

  @override
  String biometricErrorWithCode(String code) {
    return '生物识别错误：$code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds秒',
    );
    return '失败次数过多。请在$_temp0后重试。';
  }

  @override
  String get enterMasterPasswordPrompt => '请输入主密码';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts次',
    );
    return '密码错误。由于$_temp0失败尝试，已锁定$seconds秒。';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '失败$attempts次',
    );
    return '密码错误（$_temp0）。';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle => '请输入主密码以继续';

  @override
  String get masterPasswordFieldLabelTitleCase => '主密码';

  @override
  String get unlock => '解锁';

  @override
  String get useBiometric => '使用生物识别';

  @override
  String get connectAtLeast4Dots => '至少连接4个点';

  @override
  String get patternsDontMatch => '图案不匹配——请重试';

  @override
  String get drawUnlockPatternTitle => '绘制解锁图案';

  @override
  String get confirmPatternTitle => '确认您的图案';

  @override
  String get drawSamePatternAgain => '再次绘制相同的图案';

  @override
  String get enterAtLeast4Digits => '请输入至少4位数字';

  @override
  String get pinsDontMatch => 'PIN不匹配——请重试';

  @override
  String get createUnlockPinTitle => '创建解锁PIN';

  @override
  String get confirmPinTitle => '确认您的PIN';

  @override
  String get enterSamePinAgain => '再次输入相同的PIN';

  @override
  String get enterUnlockPinTitle => '输入解锁PIN';

  @override
  String get wrongPinTryAgain => 'PIN错误——请重试';

  @override
  String get enterYourPinSequence => '请输入您的PIN';

  @override
  String get enterPinToMount => '请输入PIN以挂载';

  @override
  String get noPinConfiguredMessage => '尚未配置PIN。请手动输入密码。';

  @override
  String pinLockedForSeconds(int seconds) {
    return '失败次数过多。已锁定$seconds秒。';
  }

  @override
  String get initSecureCredsPinMessage => '正在初始化安全凭据。请手动解锁一次以授权PIN访问。';

  @override
  String get setPinButton => '设置PIN';

  @override
  String get changePinButton => '更改PIN';

  @override
  String get pinSetupRequiredBeforeSaving => '保存前请先设置PIN。';

  @override
  String get pinSetupRequiredAboveBeforeSaving => '保存前请在上方设置PIN。';

  @override
  String get verifyPinTitle => '验证PIN';

  @override
  String get incorrectPinError => 'PIN不正确';

  @override
  String removedFromListSnack(String name) {
    return '已从列表中移除“$name”';
  }

  @override
  String get clearRecentHistoryTitle => '清除最近记录？';

  @override
  String get clearRecentHistoryMessage => '这将从您的列表中移除所有最近的文档。设备上的实际文件不会受到影响。';

  @override
  String get clearAll => '全部清除';

  @override
  String get recentHistoryClearedSnack => '最近记录已清除';

  @override
  String get moreOptionsTooltip => '更多选项';

  @override
  String get clearHistoryMenuItem => '清除历史记录';

  @override
  String get openPdfFile => '打开PDF文件';

  @override
  String get noDocumentsYetTitle => '尚无文档';

  @override
  String get openPdfToStartMessage => '从您的设备打开一个PDF开始阅读。';

  @override
  String get removeFromListMenuItem => '从列表中移除';

  @override
  String get justNow => '刚刚';

  @override
  String minutesAgo(int count) {
    return '$count分钟前';
  }

  @override
  String hoursAgo(int count) {
    return '$count小时前';
  }

  @override
  String daysAgo(int count) {
    return '$count天前';
  }

  @override
  String get usbDriveDisconnectedLocked => 'USB驱动器已断开——容器已锁定';

  @override
  String get containerAlreadyMounted => '此容器已挂载。';

  @override
  String get noVaultFolderFormatDetected =>
      '在该文件夹中未找到masterkey.cryptomator、gocryptfs.conf或cryfs.config。';

  @override
  String get savedContainerSettingsNotFound => '找不到此容器的已保存设置。';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return '无法更新容器位置：$error';
  }

  @override
  String filePickerFailed(String error) {
    return '文件选择器失败：$error';
  }

  @override
  String get selectContainerFirst => '请先选择一个容器';

  @override
  String get passwordOrKeyfilesRequired => '需要密码或密钥文件';

  @override
  String get slowPerformanceWarningTitle => '性能缓慢警告';

  @override
  String get slowPerformanceWarningMessage =>
      '快速存储访问当前已禁用。\n\nCryFS将文件分散存储在数千个小块中。通过Android SAF打开非空的CryFS保险库将非常缓慢。\n\n是否打开设置以授予“所有文件访问权限”以获得更快速度？';

  @override
  String get unlockAnyway => '仍然解锁';

  @override
  String get defaultVaultName => '保险库';

  @override
  String get defaultContainerName => '容器';

  @override
  String get incorrectPasswordOrInvalidVault => '密码错误或保险库无效';

  @override
  String get incorrectPasswordOrInvalidContainer => '密码错误或容器无效';

  @override
  String get genericUnknownError => '未知错误';

  @override
  String get decryptingLabel => '正在解密…';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return '正在尝试密钥槽 $attempted/$total…';
  }

  @override
  String get luksKeyslotProgressUnknown => '正在尝试密钥槽…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return '正在验证凭据 $attempted/$total…';
  }

  @override
  String get bitlockerCredentialProgressUnknown => '正在验证凭据…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return '正在尝试$algo（$slotName）…';
  }

  @override
  String get unlockContainerLabel => '解锁容器';

  @override
  String get mountContainerTitle => '挂载容器';

  @override
  String get containerFileSegmentLabel => '容器文件';

  @override
  String get folderVaultSegmentLabel => '文件夹保险库';

  @override
  String formatContainerLabel(String format) {
    return '$format容器';
  }

  @override
  String formatVaultLabel(String format) {
    return '$format保险库';
  }

  @override
  String formatDriveLabel(String format) {
    return '$format驱动器';
  }

  @override
  String get encryptedContainerLabel => '加密容器';

  @override
  String get tapToSelectVaultFolder => '点击选择保险库文件夹…';

  @override
  String get tapToSelectContainerFile => '点击选择容器文件…';

  @override
  String get containerMissingTitle => '容器缺失';

  @override
  String get filePathCouldNotBeResolved => '无法解析文件路径';

  @override
  String get containerMissingExplanation => '容器文件可能已被移动、删除，或其所在存储设备当前已断开连接。';

  @override
  String get retryButtonLabel => '重试';

  @override
  String get locateFileButtonLabel => '定位文件';

  @override
  String get authenticateToMountSubtitle => '进行身份验证以安全挂载容器';

  @override
  String get usePasswordButtonLabel => '使用密码';

  @override
  String get authenticateButtonLabel => '进行身份验证';

  @override
  String get drawUnlockPatternCardTitle => '绘制解锁图案';

  @override
  String get wrongPatternTryAgain => '图案错误——请重试';

  @override
  String get connectYourPatternSequence => '连接您的图案序列';

  @override
  String get usePasswordInsteadButtonLabel => '改用密码';

  @override
  String get passwordHintFolderVault => '输入保险库密码';

  @override
  String get passwordHintBitlocker => '输入密码或恢复密钥';

  @override
  String get passwordHintContainer => '输入容器密码';

  @override
  String get usingSavedPasswordTooltip => '正在使用已保存的密码';

  @override
  String get luksKeyfileReplacesPasswordNote => '对于LUKS容器，密钥文件将取代密码。';

  @override
  String get readOnlyModeUsbSubtitle => '挂载时不允许更改此驱动器';

  @override
  String get readOnlyModeContainerSubtitle => '挂载时不允许更改此容器';

  @override
  String get rememberContainerLabel => '记住容器';

  @override
  String get rememberContainerSubtitle => '将容器固定在仪表盘上以便快速访问';

  @override
  String get cancelUnlockButtonLabel => '取消解锁';

  @override
  String get biometricSubjectContainer => '容器';

  @override
  String get biometricSubjectUsbDrive => 'USB驱动器';

  @override
  String get usbNoSavedCredentialsMessage => '未找到已保存的密码。请手动输入。';

  @override
  String get decryptingDriveLabel => '正在解密驱动器…';

  @override
  String get usbDeviceAlreadyActiveMounted => '此USB设备已处于活动状态并已挂载。';

  @override
  String reconnectUsbDriveTitle(String label) {
    return '重新连接“$label”';
  }

  @override
  String get unlockUsbDriveTitle => '解锁USB驱动器';

  @override
  String get noUsbStorageDetectedTitle => '未检测到USB存储设备';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return '进行身份验证以解锁$subject';
  }

  @override
  String get noPatternConfiguredMessage => '未配置图案。请手动输入密码。';

  @override
  String patternLockedForSeconds(int seconds) {
    return '失败次数过多。已锁定$seconds秒。';
  }

  @override
  String get initSecureCredsBiometricMessage => '正在初始化安全凭据。请手动解锁一次以授权生物识别访问。';

  @override
  String get initSecureCredsPatternMessage => '正在初始化安全凭据。请手动解锁一次以授权图案访问。';

  @override
  String get mountExistingContainerTitle => '挂载现有容器';

  @override
  String get mountExistingContainerSubtitle => '解锁您已有的文件容器';

  @override
  String get mountSplitContainerTitle => '挂载分割容器';

  @override
  String get mountSplitContainerSubtitle => '直接解锁分割容器，无需先合并';

  @override
  String get mountUsbDriveTitle => '挂载USB驱动器';

  @override
  String get mountUsbDriveSubtitle => '解锁OTG闪存驱动器上的容器';

  @override
  String get formatUsbDriveTitle => '格式化USB驱动器';

  @override
  String get formatUsbDriveSubtitle => '清除驱动器并在其上创建一个新的加密容器';

  @override
  String get createNewContainerTitle => '创建新容器';

  @override
  String get createNewContainerSubtitle => '格式化一个全新的加密保险库';

  @override
  String get lockBeforeRemovingWarning => '移除容器前请先将其锁定。';

  @override
  String get settingsTooltip => '设置';

  @override
  String get addVaultFabLabel => '添加保险库';

  @override
  String removedLabelUndo(String label) {
    return '已移除“$label”';
  }

  @override
  String get undo => '撤销';

  @override
  String get pdfViewerNoSourceProvided => '未提供PDF来源。';

  @override
  String get pdfViewerFileEmpty => 'PDF文件为空或无法读取。';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return '检查PDF文件大小失败：$error';
  }

  @override
  String get pdfViewerErrorLoadingTitle => '加载PDF时出错';

  @override
  String get pdfViewerNoDocumentLoaded => '未加载PDF文档。';

  @override
  String get add => '添加';

  @override
  String get reset => '重置';

  @override
  String couldNotExpose(String name) {
    return '无法公开“$name”。';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return '“$name”现已可供其他应用使用。';
  }

  @override
  String couldNotUnmount(String name) {
    return '无法卸载“$name”。';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已固定$count个项目',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已取消固定$count个项目',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning => '只读挂载——缩略图将会显示，但本次会话中不会保存在容器内。';

  @override
  String failedLoadingFolder(String type) {
    return '加载文件夹失败：$type';
  }

  @override
  String failedToReadArchive(String type) {
    return '读取压缩包失败：$type';
  }

  @override
  String archiveFormatNotSupported(String ext) {
    return '尚不支持.$ext压缩格式';
  }

  @override
  String get failedToReadFileFromArchive => '从压缩包读取文件失败';

  @override
  String failedToExtractFile(String type) {
    return '解压文件失败：$type';
  }

  @override
  String get failedToReadSecureItem => '读取安全项目失败';

  @override
  String get openFileDialogTitle => '打开文件';

  @override
  String chooseHowToOpen(String name) {
    return '选择打开“$name”的方式：';
  }

  @override
  String get playVideoAudioViewImageInApp => '在应用内播放视频/音频或查看图片';

  @override
  String get viewEditTextMarkdownCode => '查看/编辑文本、Markdown、代码';

  @override
  String get sendFileToThirdPartyApp => '将文件发送到第三方应用';

  @override
  String get openAsEllipsis => '打开方式…';

  @override
  String get chooseFileTypeToOpenAs => '选择要以哪种文件类型打开';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return '始终记住.$ext文件的选择';
  }

  @override
  String get alwaysRememberChoiceNoExt => '始终记住无扩展名文件的选择';

  @override
  String get openAsDialogTitle => '打开方式';

  @override
  String get mimeTypeText => '文本';

  @override
  String get mimeTypeImage => '图片';

  @override
  String get mimeTypeVideo => '视频';

  @override
  String get mimeTypeAudio => '音频';

  @override
  String get mimeTypeArchive => '压缩包';

  @override
  String get mimeTypeOther => '其他';

  @override
  String get scanningSubfoldersForMedia => '正在扫描子文件夹中的媒体…';

  @override
  String get noMediaFilesFoundRecursive => '在此文件夹及其子文件夹中未找到媒体文件';

  @override
  String failedToScanSubfolders(String error) {
    return '扫描子文件夹失败：$error';
  }

  @override
  String get noAppFoundForFileType => '未找到可处理此文件类型的应用';

  @override
  String couldNotOpenFile(String name) {
    return '无法打开“$name”';
  }

  @override
  String get readOnlyCantMove => '此容器以只读方式挂载——无法从此处移动项目。';

  @override
  String get readOnlyCantPaste => '此容器以只读方式挂载——无法在此粘贴项目。';

  @override
  String get clipboardSourceInvalid => '剪贴板来源无效';

  @override
  String get crossContainerPasteNotConfigured => '尚未配置跨容器粘贴。';

  @override
  String get crossContainerPasteRequiresBothMounted => '跨容器粘贴要求两个容器都保持挂载状态。';

  @override
  String get readOnlyCantDelete => '此容器以只读方式挂载——无法删除项目。';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已删除$count个项目',
    );
    return '$_temp0';
  }

  @override
  String deletedWithFailures(int deleted, int failed) {
    return '已删除$deleted个 · 失败$failed个';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已导出$count个文件',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed => '导出已取消或失败';

  @override
  String exportError(String type) {
    return '导出错误：$type';
  }

  @override
  String get deleteOriginalTitle => '删除原始文件？';

  @override
  String get deleteOriginalFolderMessage => '原始文件夹已导入，是否要从您的设备中删除它？';

  @override
  String get deleteOriginalFilesMessage => '原始文件已导入，是否要从您的设备中删除它们？';

  @override
  String get keepOriginal => '保留原始文件';

  @override
  String get deleteOriginalButton => '删除原始文件';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已删除$count个原始项目',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals => '无法删除原始文件';

  @override
  String get videoCapturedEncrypted => '视频已拍摄并加密';

  @override
  String get photoCapturedEncrypted => '照片已拍摄并加密';

  @override
  String cameraCaptureFailed(String type) {
    return '相机拍摄失败：$type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return '将所有文件解压到文件夹“$folder”？';
  }

  @override
  String get extract => '解压';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已解压$count个文件',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return '解压失败：$type';
  }

  @override
  String get closeSearchTooltip => '关闭搜索';

  @override
  String get searchInThisFolderTooltip => '在此文件夹中搜索';

  @override
  String get playMediaHereTooltip => '在此播放媒体';

  @override
  String get rootFolderLabel => '根目录';

  @override
  String folderPickerFailed(String error) {
    return '文件夹选择器失败：$error';
  }

  @override
  String get addAVaultTitle => '添加保险库';

  @override
  String get selectEmptyDestinationFolderFirst => '请先选择一个空的目标文件夹';

  @override
  String get passwordRequired => '需要密码';

  @override
  String get vaultCreatedSuccessfully => '保险库创建成功。';

  @override
  String get vaultCreationFailedEmptyFolder => '保险库创建失败——请确保所选文件夹为空。';

  @override
  String get unknownErrorOccurred => '发生未知错误';

  @override
  String get containerNameRequired => '需要容器名称';

  @override
  String get enterValidSizeGreaterThanZero => '请输入大于0的有效大小';

  @override
  String get passwordOrKeyfileRequired => '需要密码或至少一个密钥文件';

  @override
  String get standardVolumePasswordsDoNotMatch => '标准卷密码不匹配';

  @override
  String get hiddenVolumePasswordsDoNotMatch => '隐藏卷密码不匹配';

  @override
  String get containerFileCreatedSuccessfully => '容器文件创建成功。';

  @override
  String get containerCreationCancelledOrFailed => '容器创建已取消或失败。';

  @override
  String insufficientSpaceForContainer(String needed, String available) {
    return 'Not enough free space at the destination. Need $needed, only $available available.';
  }

  @override
  String get vaultKindContainerFile => '容器文件';

  @override
  String get vaultKindFolderVault => '文件夹保险库';

  @override
  String get formatFileSystemLabel => '格式化文件系统';

  @override
  String get standardVolumeHeader => '标准卷';

  @override
  String get containerFormatLabel => '容器格式';

  @override
  String get fileNameLabel => '文件名';

  @override
  String get containerSizeLabel => '容器大小';

  @override
  String get unitLabel => '单位';

  @override
  String get passwordFieldLabel => '密码';

  @override
  String get confirmPasswordFieldLabelTitleCase => '确认密码';

  @override
  String get hiddenVolumeHeader => '隐藏卷';

  @override
  String get createHiddenVolumeToggleTitle => '创建隐藏卷';

  @override
  String get createInvisibleSecondaryVolume => '创建一个不可见的次级卷';

  @override
  String get setOuterPasswordFirstToEnable => '请先设置外部密码或密钥文件以启用';

  @override
  String get hiddenPasswordLabel => '隐藏密码';

  @override
  String get confirmHiddenPasswordLabel => '确认隐藏密码';

  @override
  String get hiddenSizeLabel => '隐藏大小';

  @override
  String get unitMbMegabytes => 'MB（兆字节）';

  @override
  String get unitGbGigabytes => 'GB（吉字节）';

  @override
  String get hiddenFileSystemLabel => '隐藏文件系统';

  @override
  String get vaultFormatLabel => '保险库格式';

  @override
  String get gocryptfsCipherLabel => '内容加密算法';

  @override
  String get cryfsCipherLabel => '内容加密算法';

  @override
  String get cryfsBlockSizeLabel => '块大小';

  @override
  String get destinationFolderLabel => '目标文件夹';

  @override
  String get selectEmptyFolderLabel => '选择一个空文件夹';

  @override
  String get tapToChooseVaultLocation => '点击选择保险库的创建位置…';

  @override
  String get folderVaultLimitationsNote =>
      '文件夹保险库不支持密钥文件、PIM、隐藏卷或VeraCrypt/LUKS加密算法选择。';

  @override
  String get createVaultButton => '创建保险库';

  @override
  String get createContainerButton => '创建容器';

  @override
  String get vaultCreationInProgressWait => '正在创建保险库，请稍候。';

  @override
  String get containerCreationInProgressWait => '正在创建容器，请稍候。';

  @override
  String get createEncryptedVaultTitle => '创建加密保险库';

  @override
  String get createEncryptedContainerTitle => '创建加密容器';

  @override
  String get unitMbShort => 'MB';

  @override
  String get unitGbShort => 'GB';

  @override
  String failedToListUsbDevices(String error) {
    return '列出USB设备失败：$error';
  }

  @override
  String get usbPermissionDenied => 'USB权限被拒绝';

  @override
  String get couldNotReadDriveCapacity => '无法读取驱动器容量——请手动输入大小。';

  @override
  String get selectUsbDriveFirst => '请先选择一个USB驱动器';

  @override
  String eraseDeviceTitle(String name) {
    return '清除“$name”？';
  }

  @override
  String get eraseDeviceMessage => '这将永久清除此USB驱动器上当前的所有内容，并用新的加密容器替换。此操作无法撤销。';

  @override
  String get eraseAndCreateButton => '清除并创建';

  @override
  String get usbPermissionRequiredToContinue => '需要USB权限才能继续';

  @override
  String get usbContainerCreatedSnack => 'USB容器已创建。使用“挂载USB驱动器”将其解锁。';

  @override
  String get usbContainerCreationFailed => 'USB容器创建失败。';

  @override
  String get usbStandardVolumeSectionHeader => 'USB驱动器与标准卷';

  @override
  String get formattingErasesEverythingWarning => '格式化将清除所选驱动器上当前的所有内容。';

  @override
  String get selectUsbDriveLabel => '选择USB驱动器';

  @override
  String get noUsbStorageDetected => '未检测到USB存储设备';

  @override
  String get connectOtgDriveToFormat => '连接OTG驱动器以进行格式化';

  @override
  String get refreshListButton => '刷新列表';

  @override
  String get readyToFormat => '已准备好格式化';

  @override
  String get permissionRequired => '需要权限';

  @override
  String get readingDriveCapacity => '正在读取驱动器容量…';

  @override
  String get mustNotExceedDriveCapacity => '不得超过驱动器的实际容量。';

  @override
  String get quickFormatTitle => '快速格式化';

  @override
  String get quickFormatDescription => '跳过驱动器的清零填充。速度更快，但不会安全清除旧数据。';

  @override
  String get eraseAndCreateContainerButton => '清除并创建容器';

  @override
  String get usbContainerCreationInProgressWait => '正在创建容器，请稍候。';

  @override
  String get formatUsbDriveScreenTitle => '格式化USB驱动器';

  @override
  String get playlistTransitionAnimationLabel => '播放列表切换动画';

  @override
  String get playlistTransitionSlideLabel => '滑动（默认）';

  @override
  String get playlistTransitionFadeLabel => '淡入淡出';

  @override
  String get playlistTransitionZoomLabel => '缩放';

  @override
  String get playlistTransitionDepthLabel => '深度堆叠';

  @override
  String get playlistTransitionCubeLabel => '3D立方体';

  @override
  String get playlistTransitionFlipLabel => '3D翻转';

  @override
  String get unlockVaultTitle => '解锁保险库';

  @override
  String get openContainerTitle => '打开容器';

  @override
  String get selectContainerFileOrFolder => '选择文件或文件夹';

  @override
  String get readOnlyModeLabel => '只读模式';

  @override
  String get readOnlyModeSubtitle => '阻止对保险库进行任何写入或修改操作';

  @override
  String get selectUsbDeviceLabel => '选择USB设备';

  @override
  String get noUsbDevicesFound => '未找到兼容的USB存储设备';

  @override
  String get containerConfigTitle => '保险库配置';

  @override
  String get changePasswordTitle => '更改密码';

  @override
  String get confirmNewPasswordLabel => '确认新密码';

  @override
  String get cameraCaptureTitle => '保险库相机';

  @override
  String get takingPhoto => '正在拍照…';

  @override
  String get savingToVault => '正在保存到保险库…';

  @override
  String get noVaultSelected => '未选择保险库';

  @override
  String get mediaDiagnosticsTitle => '媒体诊断';

  @override
  String get advancedViewerSettingsTitle => '查看器设置';

  @override
  String get textEditorSaveConfirmTitle => '未保存的更改';

  @override
  String get textEditorSaveConfirmMessage => '关闭前是否要保存更改？';

  @override
  String get saveAndClose => '保存并关闭';

  @override
  String get discardChanges => '放弃更改';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选择$count个项目',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => '全选';

  @override
  String get deselectAll => '取消全选';

  @override
  String get sortOptionsTitle => '文件排序';

  @override
  String get layoutModeList => '列表视图';

  @override
  String get layoutModeGrid => '网格视图';

  @override
  String get layoutModeMasonry => '瀑布流';

  @override
  String get fileOperationsTitle => '文件操作';

  @override
  String get conflictResolutionTitle => '文件冲突';

  @override
  String get replaceExistingFile => '替换现有文件';

  @override
  String get keepBothFiles => '保留两者（重命名新文件）';

  @override
  String get skipFile => '跳过此文件';

  @override
  String get noVaultsFoundTitle => '未找到保险库';

  @override
  String get noVaultsFoundSubtitle => '创建一个新的加密容器或添加一个现有保险库以开始使用。';

  @override
  String get addExistingVaultButton => '添加现有保险库';

  @override
  String get sortContainersModeManual => '手动（拖动以重新排序）';

  @override
  String get sortContainersModeUnlockStatus => '解锁状态（已解锁优先）';

  @override
  String get sortContainersModeNameAZ => '名称（A–Z）';

  @override
  String get sortContainersModeNameZA => '名称（Z–A）';

  @override
  String get sortContainersModeNewest => '最新优先';

  @override
  String get sortContainersModeOldest => '最旧优先';

  @override
  String get thumbnailCacheAppCacheLabel => '应用缓存';

  @override
  String get thumbnailCacheAppCacheDesc => '以加密方式存储在应用缓存中。速度快；存储空间紧张时会自动清除。';

  @override
  String get thumbnailCacheInContainerLabel => '容器内部';

  @override
  String get thumbnailCacheInContainerDesc => '存储在加密容器内部。受容器本身保护，但写入速度较慢。';

  @override
  String get thumbnailCacheDisabledLabel => '已禁用';

  @override
  String get thumbnailCacheDisabledDesc => '无磁盘缓存。每次加载时都会重新生成缩略图。';

  @override
  String get unlockContainerTitle => '解锁容器';

  @override
  String get containerFileSegment => '容器文件';

  @override
  String get folderVaultSegment => '文件夹保险库';

  @override
  String get enableButtonLabel => '启用';

  @override
  String get retryButtonLabelShort => '重试';

  @override
  String get locateFileButton => '定位文件';

  @override
  String get authenticateButton => '进行身份验证';

  @override
  String get cancelUnlockButton => '取消解锁';

  @override
  String tryingKeyslotProgress(int attempted, int total) {
    return '正在尝试密钥槽 $attempted/$total…';
  }

  @override
  String get tryingKeyslotSingle => '正在尝试密钥槽…';

  @override
  String verifyingCredentialProgress(int attempted, int total) {
    return '正在验证凭据 $attempted/$total…';
  }

  @override
  String get verifyingCredentialSingle => '正在验证凭据…';

  @override
  String tryingAlgoSlot(String algo, String slotName) {
    return '正在尝试$algo（$slotName）…';
  }

  @override
  String get hiddenVolumeSlotName => '隐藏卷';

  @override
  String get standardVolumeSlotName => '标准卷';

  @override
  String get containerMissingSubtitle => '无法解析文件路径';

  @override
  String get containerMissingBody => '容器文件可能已被移动、删除，或其所在存储设备当前已断开连接。';

  @override
  String get connectPatternSequence => '连接您的图案序列';

  @override
  String get passwordLabel => '密码';

  @override
  String get enterVaultPasswordHint => '输入保险库密码';

  @override
  String get enterBitlockerPasswordHint => '输入密码或恢复密钥';

  @override
  String get enterContainerPasswordHint => '输入容器密码';

  @override
  String get readOnlyModeUsbSubtitleDrive => '挂载时不允许更改此驱动器';

  @override
  String get rememberDriveLabel => '记住驱动器';

  @override
  String get rememberDriveSubtitle => '将驱动器固定在仪表盘上以便快速访问';

  @override
  String get unlockVaultButtonLabel => '解锁保险库';

  @override
  String get cryfsStorageAccessWarning =>
      'CryFS保险库使用数千个小型块文件。若没有快速存储访问，性能将明显变慢。';

  @override
  String get folderVaultStorageAccessWarning =>
      '快速存储访问已禁用。在文件夹保险库中打开和读取文件的速度可能较慢。';

  @override
  String get requestingPermission => '正在请求权限…';

  @override
  String get unlockAndMountButton => '解锁并挂载';

  @override
  String get unlockDriveButton => '解锁驱动器';

  @override
  String couldntFindDevice(String deviceName) {
    return '找不到“$deviceName”';
  }

  @override
  String get plugDriveBackInRetry => '请重新插入驱动器并点击重试，或者如果它以不同名称显示，请在下方选择它。';

  @override
  String get retryConnectionButton => '重试连接';

  @override
  String get refreshDevicesButton => '刷新设备';

  @override
  String get connectOtgDriveToMount => '连接OTG闪存驱动器以进行挂载';

  @override
  String get alreadyActive => '已处于活动状态';

  @override
  String get active => '活动';

  @override
  String get readyToUnlock => '已准备好解锁';

  @override
  String get enterUsbPartitionPassword => '输入USB分区密码';

  @override
  String get biometricAuthenticationTitle => '生物识别验证';

  @override
  String get biometricAuthUsbSubtitle => '进行身份验证以解锁并挂载此USB设备';

  @override
  String get connectPatternSequenceToMount => '连接您的图案序列以进行挂载';

  @override
  String get selectAllAction => '全选';

  @override
  String get clearSelectionAction => '清除选择';

  @override
  String get clearSelectionTooltip => '清除选择';

  @override
  String get selectionOptionsTooltip => '选择选项';

  @override
  String get readOnlyContainerTooltip => '只读容器';

  @override
  String get copyAction => '复制';

  @override
  String get moveAction => '移动';

  @override
  String get renameAction => '重命名';

  @override
  String get exportToDeviceAction => '导出到设备';

  @override
  String get openWithAppAction => '用应用打开';

  @override
  String get pinAction => '固定';

  @override
  String get pinSelectedAction => '固定所选项';

  @override
  String get unpinAction => '取消固定';

  @override
  String get unpinSelectedAction => '取消固定所选项';

  @override
  String get documentProviderSettingsMenu => '文档提供程序设置';

  @override
  String get exposeAsDocumentProviderMenu => '公开为文档提供程序';

  @override
  String get moreOptionsTooltipShort => '更多选项';

  @override
  String get copyTooltip => '复制';

  @override
  String get searchInThisFolderHint => '在此文件夹中搜索…';

  @override
  String get clearTooltip => '清除';

  @override
  String get backToDashboardTooltip => '返回仪表盘';

  @override
  String get cancelPasteButton => '取消粘贴';

  @override
  String get cancelImportButton => '取消导入';

  @override
  String get continueButton => '继续';

  @override
  String get skipButton => '跳过';

  @override
  String get keepBothButton => '两者都保留';

  @override
  String get clearAllButton => '全部清除';

  @override
  String get autoMountWhenUnlocksTitle => '容器解锁时自动挂载';

  @override
  String get autoMountWhenUnlocksSubtitle => '下次自动重新公开此文件夹';

  @override
  String get unmountButton => '卸载';

  @override
  String get filtersMenuItem => '筛选';

  @override
  String get settingsMenuItem => '设置';

  @override
  String get sortOptionsTooltip => '排序选项';

  @override
  String get layoutOptionsTooltip => '布局选项';

  @override
  String get lockContainerTooltip => '锁定容器';

  @override
  String get renameTooltip => '重命名';

  @override
  String get cancelUpdatingPasswordTooltip => '取消更新密码';

  @override
  String get unlockSettingsButton => '解锁设置';

  @override
  String get updateSavedCredentialsButton => '更新已保存的凭据';

  @override
  String get verifyCredentialsTitle => '验证凭据';

  @override
  String get verifyButton => '验证';

  @override
  String get displayNameTitle => '显示名称';

  @override
  String get containerNameHint => '容器名称';

  @override
  String get deleteFileDialogTitle => '删除文件？';

  @override
  String get deleteFilePermanentWarning => '此操作是永久性的，无法撤销。';

  @override
  String get unsavedChangesTitle => '未保存的更改';

  @override
  String get unsavedChangesMessage => '您有未保存的更改。是否要在关闭前保存？';

  @override
  String get discardButton => '放弃';

  @override
  String get decryptingFileContent => '正在解密文件内容...';

  @override
  String get cannotOpenFile => '无法打开文件';

  @override
  String get changesSavedSuccessfully => '更改已成功保存';

  @override
  String saveFailedWithError(String error) {
    return '保存失败：$error';
  }

  @override
  String linesCount(int count) {
    return '行数：$count';
  }

  @override
  String charsCount(int count) {
    return '字符数：$count';
  }

  @override
  String get unsavedChangesLabel => '未保存的更改';

  @override
  String get savedToVault => '已保存到保险库';

  @override
  String get saveChangesTooltip => '保存更改';

  @override
  String get textEditorDecryptFailedMessage => '从保险库解密文件失败。';

  @override
  String get textEditorInvalidTextFileMessage => '该文件似乎不是有效的文本文件。';

  @override
  String get textEditorWriteBackFailedMessage => '将文件写回保险库失败。';

  @override
  String get backTooltip => '后退';

  @override
  String get forwardTooltip => '前进';

  @override
  String get reloadTooltip => '重新加载';

  @override
  String get optionsTooltip => '选项';

  @override
  String get htmlViewerErrorTitle => '无法显示此页面';

  @override
  String get htmlViewerLoadFailedMessage => '加载文件失败';

  @override
  String get enableJavaScriptDialogTitle => '启用JavaScript？';

  @override
  String get enableJavaScriptDialogMessage =>
      '该页面将被允许运行其自身的本地脚本。它仍然没有网络访问权限——此保险库中的任何内容都无法通过互联网发送或接收。';

  @override
  String get disableJavaScriptMenu => '禁用JavaScript';

  @override
  String get enableJavaScriptMenu => '启用JavaScript';

  @override
  String get enterFullscreenMenu => '进入全屏';

  @override
  String failedToOpenExternalApp(String error) {
    return '在外部应用中打开失败：$error';
  }

  @override
  String get thisFolderMenu => '此文件夹';

  @override
  String get allInclSubfoldersMenu => '全部（含子文件夹）';

  @override
  String get disableShuffleMenu => '关闭随机播放';

  @override
  String get shufflePlaylistMenu => '随机播放列表';

  @override
  String get playlistOptionsTooltip => '播放列表选项';

  @override
  String get enablePlaylistTooltip => '启用播放列表';

  @override
  String get moreActionsTooltip => '更多操作';

  @override
  String get forcePortraitMenu => '强制竖屏';

  @override
  String get forceLandscapeMenu => '强制横屏';

  @override
  String get autoRotateSensorMenu => '自动旋转（传感器）';

  @override
  String get screenOrientationMenu => '屏幕方向';

  @override
  String get playlistTransitionMenu => '播放列表切换效果';

  @override
  String get renameFileMenu => '重命名文件';

  @override
  String get deleteFileMenu => '删除文件';

  @override
  String get thumbnailCarouselTooltip => '缩略图轮播';

  @override
  String get advancedSettingsTooltip => '高级设置';

  @override
  String get previousTooltip => '上一个';

  @override
  String get nextTooltip => '下一个';

  @override
  String get diagnosticsCopiedToClipboard => '诊断信息已复制到剪贴板';

  @override
  String get diagnosticsTitle => '诊断信息';

  @override
  String get copyDiagnosticsTooltip => '复制诊断信息';

  @override
  String get closeTooltip => '关闭';

  @override
  String get diagnosticsPlaybackSection => '播放';

  @override
  String get diagnosticsEngineSection => '引擎';

  @override
  String get diagnosticsStateLabel => '状态';

  @override
  String get diagnosticsResolutionLabel => '分辨率';

  @override
  String get diagnosticsAspectRatioLabel => '宽高比';

  @override
  String get diagnosticsPositionLabel => '播放位置';

  @override
  String get diagnosticsDurationLabel => '时长';

  @override
  String get diagnosticsErrorLabel => '错误';

  @override
  String get diagnosticsPlayerLabel => '播放器';

  @override
  String get diagnosticsDecodingLabel => '解码方式';

  @override
  String get diagnosticsExoPlayerValue => 'ExoPlayer（Android）';

  @override
  String get diagnosticsHardwareAcceleratedValue => '硬件加速';

  @override
  String get diagnosticsUnknownValue => '未知';

  @override
  String get diagnosticsStateBuffering => '正在缓冲';

  @override
  String get diagnosticsStatePlaying => '正在播放';

  @override
  String get diagnosticsStatePaused => '已暂停';

  @override
  String get diagnosticsDurationUnavailable => '--:--';

  @override
  String get rotate90Label => '旋转90°';

  @override
  String get imageFitModeLabel => '图片适配模式';

  @override
  String get slideshowDelayLabel => '幻灯片间隔';

  @override
  String get playbackSpeedLabel => '播放速度';

  @override
  String get subtitlesLabel => '字幕';

  @override
  String get imageSettingsTitle => '图片设置';

  @override
  String get playbackSettingsTitle => '播放设置';

  @override
  String get imageFitContain => '完整显示';

  @override
  String get imageFitWidth => '适应宽度';

  @override
  String get imageFitHeight => '适应高度';

  @override
  String nSecondsDelay(int n) {
    return '$n秒';
  }

  @override
  String playbackSpeedNormal(String speed) {
    return '$speed倍（正常）';
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
  String get settingsTooltipShort => '设置';

  @override
  String get sourceCodeTooltip => '源代码';

  @override
  String get donateTooltip => '捐赠';

  @override
  String get shareAppTooltip => '分享应用';

  @override
  String get resetToDefaultsTooltip => '重置为默认值';

  @override
  String get usbUnlockContainerTitle => '解锁USB容器';

  @override
  String get usbMountContainerTitle => '挂载USB驱动器';

  @override
  String get staticLabel => '静止';

  @override
  String get unmuteTooltip => '取消静音';

  @override
  String get muteTooltip => '静音';

  @override
  String get playOnceDisabledTooltip => '仅播放一次（已禁用自动前进）';

  @override
  String get playAndAdvanceTooltip => '播放并前进到下一个';

  @override
  String get loopCurrentVideoTooltip => '循环播放当前视频';

  @override
  String get clearThumbnailCacheDialogTitle => '清除缩略图缓存？';

  @override
  String get clearThumbnailCacheDialogMessage =>
      '这将删除此保险库的缓存缩略图。下次浏览媒体时会重新生成它们。';

  @override
  String get clearCacheButton => '清除缓存';

  @override
  String get appCacheClearedUnlockMessage => '应用缓存已清除。解锁容器以清除内部缓存。';

  @override
  String get allThumbnailCachesClearedMessage => '所有缩略图缓存已成功清除。';

  @override
  String get appCacheClearedContainerFailedMessage => '应用缓存已清除，但清除容器内部缓存失败。';

  @override
  String get failedToClearThumbnailCachesMessage => '清除缩略图缓存失败。';

  @override
  String get authenticateToModifySettingsPrompt => '进行身份验证以修改设置';

  @override
  String get usbVaultSettingsTitle => 'USB保险库设置';

  @override
  String get vaultSettingsTitle => '保险库设置';

  @override
  String get generalSectionHeader => '通用';

  @override
  String get securityCredentialsSectionHeader => '安全与凭据';

  @override
  String get securityOptionsLockedTitle => '安全选项已锁定';

  @override
  String get authenticateOriginalCredentialsMessage =>
      '使用容器的原始凭据进行身份验证以修改安全设置。';

  @override
  String get unlockCredentialsLabel => '解锁凭据';

  @override
  String get unavailableSuffixLabel => '（不可用）';

  @override
  String get patternSetupRequiredBeforeSaving => '保存前请先设置图案。';

  @override
  String get passwordKeystoreEncryptedHelperText =>
      '密码使用Android Keystore加密。如果仅使用密钥文件，请留空。';

  @override
  String get changePatternButton => '更改图案';

  @override
  String get setPatternButton => '设置图案';

  @override
  String get cacheDerivedKeyLabel => '缓存派生密钥';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      '下次跳过CryFS的scrypt KDF（密钥保存在Android Keystore中）';

  @override
  String get reuseKeyMaterialKeystoreSubtitle => '重用Android Keystore中的密钥材料';

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle => '固定算法以在解锁时跳过自动检测。';

  @override
  String get changeContainerPasswordTitle => '更改容器密码';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      '无法在应用内更改BitLocker凭据。请在Windows上使用“管理BitLocker”。';

  @override
  String get systemIntegrationSectionHeader => '系统与集成';

  @override
  String get autoLockDurationLabel => '自动锁定时长';

  @override
  String get neverAutoLockOption => '从不';

  @override
  String get exposeContentToFilePickerSubtitle => '解锁时向系统文件选择器公开内容';

  @override
  String get thumbnailStorageSectionHeader => '缩略图存储';

  @override
  String get cacheModeLabel => '缓存模式';

  @override
  String get useGlobalDefaultSubtitle => '使用全局默认值';

  @override
  String get thumbnailQualityLabel => '缩略图质量';

  @override
  String get clearThumbnailCacheTitle => '清除缩略图缓存';

  @override
  String get removeCachedThumbnailsSubtitle => '移除已缓存的图片和视频缩略图';

  @override
  String get vaultInformationSectionHeader => '保险库信息';

  @override
  String get vaultInformationTileTitle => '查看保险库详情';

  @override
  String get vaultInformationTileSubtitle => '加密算法、格式及其他技术详情';

  @override
  String get vaultInfoLocationLabel => '位置';

  @override
  String get vaultInfoRequiresUnlockTitle => '需要解锁';

  @override
  String get vaultInfoRequiresUnlockMessage => '解锁此保险库以查看其技术详情。';

  @override
  String get vaultInfoLoadFailedTitle => '无法加载保险库信息';

  @override
  String get vaultInfoLoadFailedMessage => '读取此保险库的详情时出了点问题。';

  @override
  String get vaultInfoVolumeSizeLabel => '卷大小';

  @override
  String get vaultInfoFileSystemLabel => 'File System';

  @override
  String get vaultInfoHiddenVolumeLabel => '隐藏卷';

  @override
  String get vaultInfoReadOnlyLabel => '只读';

  @override
  String get vaultInfoLuksVersionLabel => 'LUKS版本';

  @override
  String get vaultInfoSectorSizeLabel => '扇区大小';

  @override
  String get vaultInfoVaultFormatLabel => '保险库格式';

  @override
  String get vaultInfoCipherComboLabel => '加密算法组合';

  @override
  String get vaultInfoShorteningThresholdLabel => '文件名缩短阈值';

  @override
  String get vaultInfoFormatVersionLabel => '格式版本';

  @override
  String get vaultInfoContentCipherLabel => '内容加密算法';

  @override
  String get vaultInfoFilenameEncryptionLabel => '文件名';

  @override
  String get vaultInfoPlaintextNamesValue => '明文';

  @override
  String get vaultInfoEncryptedNamesValue => '已加密';

  @override
  String get vaultInfoBlockCipherLabel => '分组加密算法';

  @override
  String get vaultInfoBlockSizeLabel => '块大小';

  @override
  String get vaultInfoCreatedWithVersionLabel => '创建版本';

  @override
  String get vaultInfoLastOpenedWithVersionLabel => '最后打开版本';

  @override
  String get vaultInfoYesValue => '是';

  @override
  String get vaultInfoNoValue => '否';

  @override
  String get vaultInfoBitlockerNote =>
      '此应用不解析BitLocker自身的头部元数据，因此这里无法提供加密算法和版本详情。';

  @override
  String get patternSetupRequiredAboveBeforeSaving => '保存前请先在上方设置图案。';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      '此解锁方式需要密码，或带密钥文件的“缓存派生密钥”。';

  @override
  String get saveConfigurationButton => '保存配置';

  @override
  String get incorrectPatternError => '图案错误';

  @override
  String get verifyPatternTitle => '验证图案';

  @override
  String get incorrectPasswordError => '密码错误';

  @override
  String get verificationFailedError => '验证失败';

  @override
  String get incorrectCredentialsError => '凭据不正确';

  @override
  String get containerPasswordOptionalLabel => '容器密码（仅使用密钥文件时可选）';

  @override
  String get pimOptionalLabel => 'PIM（可选）';

  @override
  String get usbDriveLockedLabel => 'USB驱动器・已锁定';

  @override
  String get lockedContainerLabel => '已锁定的容器';

  @override
  String get operationInProgressWaitMessage => '操作正在进行中。请在锁定前稍候。';

  @override
  String get reconnectUsbTooltip => '重新连接USB';

  @override
  String get unlockContainerTooltip => '解锁容器';

  @override
  String lockFailedMessage(String errorType) {
    return '锁定失败：$errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired => '需要新密码或密钥文件。';

  @override
  String get newPasswordsDoNotMatch => '新密码不匹配。';

  @override
  String get passwordChangedSuccessfullyMessage => '密码更改成功。';

  @override
  String get failedToChangePasswordMessage => '更改密码失败。请检查旧凭据。';

  @override
  String get currentCredentialsSectionHeader => '当前凭据';

  @override
  String get oldPasswordLabel => '旧密码';

  @override
  String get oldPimOptionalLabel => '旧PIM（可选）';

  @override
  String get newCredentialsSectionHeader => '新凭据';

  @override
  String get newPimOptionalLabel => '新PIM（可选）';

  @override
  String get noContainersYetTitle => '尚无容器';

  @override
  String get dashboardEmptyStateMessage =>
      '挂载一个VeraCrypt容器、连接USB驱动器，或创建一个全新的加密保险库以开始使用。';

  @override
  String get sortFieldName => '名称';

  @override
  String get sortFieldSize => '大小';

  @override
  String get sortFieldType => '类型';

  @override
  String get sortFieldDate => '日期';

  @override
  String get layoutModeDetailedList => '详细列表';

  @override
  String get layoutModeCompactList => '紧凑列表';

  @override
  String get layoutModeGalleryGrid => '图库网格';

  @override
  String get readOnlyCantDeleteTooltip => '只读——无法删除';

  @override
  String get readOnlyCantMoveTooltip => '只读——无法移动';

  @override
  String get readOnlyCantRenameTooltip => '只读——无法重命名';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes（正在计算…）';
  }

  @override
  String get sizeCalculatingLabel => '正在计算…';

  @override
  String get editSecureItemsToRenameMessage => '编辑安全项目以重命名它们';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage => '保险库项目无法在外部应用中打开';

  @override
  String get mountedReadOnlyTooltip => '以只读方式挂载';

  @override
  String get readOnlyBadgeAbbreviation => '只读';

  @override
  String freeSpaceLabel(String bytes) {
    return '剩余$bytes';
  }

  @override
  String get filteredLabel => '已筛选';

  @override
  String get statsStorageSectionHeader => '存储空间';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个文件夹',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个文件',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => '所有文件';

  @override
  String get filterImagesOption => '图片';

  @override
  String get filterVideosOption => '视频';

  @override
  String get filterAudioOption => '音频';

  @override
  String get filterDocumentsOption => '文档';

  @override
  String get folderExposedAsStorageExplanation =>
      '此文件夹被公开为一个独立的存储位置，因此其他应用可以直接浏览和打开其中的文件。';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已存在$count个项目',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle => '选择如何处理每个项目，或将一个选择应用于全部。';

  @override
  String get skipAllChipLabel => '全部跳过';

  @override
  String get overwriteAllChipLabel => '全部覆盖';

  @override
  String get overwriteItemDropdownLabel => '覆盖';

  @override
  String get overwriteFolderDropdownLabel => '覆盖文件夹';

  @override
  String get fileOpsTransfersInProgressTitle => '正在传输';

  @override
  String get fileOpsRecentTransfersTitle => '最近的传输';

  @override
  String get fileOpsNoRecentTransfersMessage => '没有最近的传输';

  @override
  String get fileOpsNoRecentTransfersSubtitle => '复制、移动和删除操作运行时将显示在此处。';

  @override
  String fileOpsShowDetailsLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个项目',
    );
    return '$_temp0';
  }

  @override
  String get fileOpsCancelTooltip => '取消';

  @override
  String get fileOpsDismissTooltip => 'Dismiss';

  @override
  String get fileOpsRootDestinationLabel => '根目录';

  @override
  String get fileOpsCancelledStatusLabel => '已取消';

  @override
  String fileOpsItemsFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个项目失败：',
    );
    return '$_temp0';
  }

  @override
  String fileOpsMoreItemsLabel(num count) {
    return '+还有$count个';
  }

  @override
  String get transferActivityTooltip => '传输';

  @override
  String fileOpsSpeedLabel(String speed) {
    return '$speed/秒';
  }

  @override
  String fileOpsEtaLabel(String time) {
    return '剩余约$time';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return '读取文件出错：$error';
  }

  @override
  String get archivePreviewNotAvailableMessage => '此文件类型不支持预览。';

  @override
  String get avifFailedToRenderMessage => '渲染AVIF失败';

  @override
  String get encryptedImageLoadFailedMessage => '加载加密图片失败';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return '加载加密图片失败：$error';
  }

  @override
  String get invalidOrCorruptedImageMessage => '图片格式无效或已损坏。';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '第$current项，共$total项';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '第$current项，共$total项  ·  正在扫描…';
  }

  @override
  String get mediaViewerScanningLabel => '正在扫描…';

  @override
  String get mediaFileDeletedMessage => '文件删除成功';

  @override
  String get mediaFileDeleteFailedMessage => '删除文件失败';

  @override
  String get mediaFileRenamedMessage => '文件重命名成功';

  @override
  String get aboutScreenTitle => '关于';

  @override
  String get couldNotOpenLinkMessage => '无法打开链接';

  @override
  String get fileManagerSettingsTitle => '文件管理器设置';

  @override
  String get showMediaThumbnailsLabel => '显示媒体缩略图';

  @override
  String get showMediaThumbnailsDesc => '在列表视图中显示图片和视频的缩略图预览';

  @override
  String get showFileNamesLabel => '显示文件名';

  @override
  String get showFileNamesDesc => '在网格布局中于项目下方显示文本标签';

  @override
  String get showBreadcrumbBarLabel => '显示面包屑导航栏';

  @override
  String get showBreadcrumbBarDesc => '浏览器顶部的路径导航栏';

  @override
  String get showStatsBarLabel => '显示统计栏';

  @override
  String get showStatsBarDesc => '显示文件数量和可用空间信息的横幅';

  @override
  String get autoStartPlaylistModeLabel => '自动启动播放列表模式';

  @override
  String get autoStartPlaylistModeDesc => '打开媒体项目时自动以播放列表模式启动';

  @override
  String get showPlaylistCarouselLabel => '显示播放列表轮播';

  @override
  String get showPlaylistCarouselDesc => '查看媒体播放列表时显示缩略图轮播按钮';

  @override
  String get videoPlaybackSliderLabel => '视频播放位置滑块';

  @override
  String get longPressPlaybackDiagnosticsHint => '长按查看播放诊断信息';

  @override
  String get staticImageModeLabel => '静态图片模式';

  @override
  String slideshowModeActiveLabel(int seconds) {
    return '幻灯片模式已启用，间隔$seconds秒';
  }

  @override
  String videoPlaybackModeLabel(String mode) {
    return '视频播放模式：$mode';
  }

  @override
  String get pauseLabel => '暂停';

  @override
  String get playLabel => '播放';

  @override
  String get emptyFolderTitle => '空文件夹';

  @override
  String get emptyFolderMessage => '使用“添加”操作创建文件，或从设备导入。';

  @override
  String get noResultsTitle => '没有结果';

  @override
  String noResultsForQueryMessage(String query) {
    return '此文件夹中没有与“$query”匹配的内容。';
  }

  @override
  String get closeCarouselTooltip => '关闭轮播';

  @override
  String get playlistScrollModeMenu => '播放列表滚动模式';

  @override
  String get playlistScrollHorizontalLabel => '水平';

  @override
  String get playlistScrollVerticalPageLabel => '垂直分页';

  @override
  String get playlistScrollVerticalContinuousLabel => '垂直连续';

  @override
  String get undoTooltip => '撤销';

  @override
  String get redoTooltip => '重做';

  @override
  String get autosavingLabel => '正在自动保存…';

  @override
  String get savingLabel => '正在保存…';

  @override
  String autosavedAtLabel(String time) {
    return '已于$time自动保存';
  }

  @override
  String cameraDisconnectedError(String message) {
    return '相机已断开连接：$message';
  }

  @override
  String get unknownErrorFallback => '未知错误';

  @override
  String get cameraPermissionsRequiredMessage => '使用相机需要相机和麦克风权限。';

  @override
  String cameraErrorMessage(String error) {
    return '相机错误：$error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage => '拍照失败';

  @override
  String get cameraRecordingFailedMessage => '录制失败';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return '录制失败：$error';
  }

  @override
  String get cameraRecordingTooShortMessage => '录制时间过短，无法保存';

  @override
  String get cameraCouldNotSaveRecordingMessage => '无法保存录制内容';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return '无法保存录制内容：$error';
  }

  @override
  String get cameraCouldNotSwitchLensMessage => '无法切换镜头';

  @override
  String get cameraEncryptingPhotoLabel => '正在加密照片…';

  @override
  String get cameraEncryptingVideoLabel => '正在加密视频…';

  @override
  String get aboutApplicationSectionHeader => '应用程序';

  @override
  String get aboutTagline => '免费・开源・离线加密保险库';

  @override
  String get aboutVersionTitle => '版本';

  @override
  String aboutVersionSubtitle(String version) {
    return 'v$version · 点击复制版本信息，用于错误报告';
  }

  @override
  String get aboutWhatsNewTitle => '新功能';

  @override
  String get aboutWhatsNewSubtitle => '查看最近的更改和版本说明';

  @override
  String get aboutPrivacySecurityTitle => '隐私与安全';

  @override
  String get aboutPrivacySecuritySubtitle => '无网络访问，绝不将未加密内容写入磁盘';

  @override
  String get aboutSupportedFormatsSectionHeader => '支持的格式';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt 与 LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      '标准卷与隐藏卷、自定义PIM、密钥文件、xts-plain64、Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker 与 BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle => '支持用户密码及48位数字恢复密钥';

  @override
  String get aboutDirectoryVaultsTitle => '文件夹保险库';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator（v7/v8 SIV_GCM 与 SIV_CTRMAC）、gocryptfs（v2 AES-GCM 与 XChaCha20）、CryFS（v0.10+ XChaCha20 与 AES）';

  @override
  String get aboutVhdTitle => '虚拟硬盘（VHD / VHDX）';

  @override
  String get aboutVhdSubtitle => '适用于固定及动态可扩展磁盘映像的BAT转换';

  @override
  String get aboutNativeCoreEngineSectionHeader => '原生核心引擎';

  @override
  String get aboutCompiledLibrariesTitle => '已编译的C++库';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.0（ARMv8硬件加密与SHA-2）\n• libavif 与 libgav1（原生AVIF图像解码器）\n• ChaN FatFs v4.0.4（FAT12/16/32 与 exFAT）\n• Tuxera NTFS-3G 与内置mkntfs\n• e2fsprogs v1.47.4 libext2fs（ext2/ext3/ext4）\n• Dislocker Virtual I/O（BitLocker FVE / To Go）\n• VeraCrypt 1.26.29（Twofish、Serpent、Camellia、Kuznyechik、Whirlpool、Streebog、BLAKE2s、Argon2id/i）\n• cJSON v1.7.18（LUKS2 与 Cryptomator 元数据）';

  @override
  String get aboutCommunitySectionHeader => '社区与开源';

  @override
  String get aboutReportIssueTitle => '报告问题';

  @override
  String get aboutReportIssueSubtitle => '发现了错误？在GitHub上提交issue';

  @override
  String get reportIssueSheetTitle => 'Report an Issue';

  @override
  String get reportIssueSheetSubtitle =>
      'Pick the option that best matches your issue — it opens a pre-filled GitHub form';

  @override
  String get reportIssueBugTitle => 'Bug Report';

  @override
  String get reportIssueBugSubtitle =>
      'Something crashed or isn\'t working right';

  @override
  String get reportIssueContainerTitle => 'Container / Vault Problem';

  @override
  String get reportIssueContainerSubtitle =>
      'Unlock, mount, or format-specific issue';

  @override
  String get reportIssueFeatureTitle => 'Feature Request';

  @override
  String get reportIssueFeatureSubtitle => 'Suggest an idea or improvement';

  @override
  String get reportIssueOtherTitle => 'Something Else';

  @override
  String get reportIssueOtherSubtitle => 'Browse all templates on GitHub';

  @override
  String get aboutContributorsTitle => '贡献者';

  @override
  String get aboutContributorsSubtitle => '帮助构建VaultExplorer的人们';

  @override
  String get aboutLicensesTitle => '开源许可证';

  @override
  String get aboutLicensesSubtitle => '本应用使用的第三方库';

  @override
  String get aboutFooterMadeWithLove => '为隐私而用❤打造。';

  @override
  String get aboutVersionCopiedMessage => '版本信息已复制——便于错误报告';

  @override
  String aboutVersionClipboardText(String version) {
    return 'VaultExplorer v$version (Android)';
  }

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer——一款适用于Android的免费开源离线保险库应用。\n\n将密码、笔记和文件存储在加密容器（VeraCrypt、LUKS、BitLocker、Cryptomator、Gocryptfs、CryFS）中。\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage => '可分享的链接已复制到剪贴板';

  @override
  String get aboutPrivacySheetTitle => '隐私与数据安全';

  @override
  String get aboutPrivacySheetSubtitle => '100%离线，基于本地内存的安全设计';

  @override
  String get privacyPointNoNetworkTitle => '无需网络访问';

  @override
  String get privacyPointNoNetworkBody =>
      'VaultExplorer在Android上不请求android.permission.INTERNET权限。它无法通过任何网络进行通信。';

  @override
  String get privacyPointNoDiskLeaksTitle => '零未加密磁盘泄露';

  @override
  String get privacyPointNoDiskLeaksBody =>
      '解密和重新加密完全在系统内存中进行。未加密的临时文件永远不会保存到设备存储中。';

  @override
  String get privacyPointNoAnalyticsTitle => '无分析或遥测';

  @override
  String get privacyPointNoAnalyticsBody =>
      '完全没有崩溃报告、使用情况跟踪，或收集您或您设备数据的第三方SDK。';

  @override
  String get privacyPointKeystoreTitle => '密钥保留在Android Keystore中';

  @override
  String get privacyPointKeystoreBody =>
      '记住的密码、图案以及缓存的派生密钥均使用AES-256-GCM在硬件支持的Android Keystore中加密封存。';

  @override
  String get privacyPointPosixTitle => 'POSIX加速与存储访问';

  @override
  String get privacyPointPosixBody =>
      '文件夹保险库内的文件在可能的情况下会被直接读写，绕过Android较慢的SAF层以处理大型文件夹。';

  @override
  String get privacyPointScreenClipboardTitle => '屏幕与剪贴板保护';

  @override
  String get privacyPointScreenClipboardBody =>
      '阻止截屏/任务切换器预览（FLAG_SECURE），并在窗口获得焦点时自动清理损坏的剪贴板内容。从项目保险库复制的密码在Android 13及以上版本中会被标记为敏感信息，若30秒内未使用则会自动清除。';

  @override
  String get privacyPointMaskModeTitle => '伪装模式';

  @override
  String get privacyPointMaskModeBody =>
      '可选择将应用伪装成一个可正常使用的zip压缩包浏览器，使用不同的图标和名称。长按标题2秒即可进入您的真实保险库。';

  @override
  String get privacyPointExternalLinksTitle => '外部链接在浏览器中打开';

  @override
  String get privacyPointExternalLinksBody => '点击链接会将请求交给您的默认浏览器应用处理。';

  @override
  String get truncatedListingWarning => '正在显示前50,000个项目——此文件夹中还有更多文件。';

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '$size像素 · $quality%质量';
  }

  @override
  String holdToSpeedIndicatorLabel(String speed) {
    return '$speed倍速';
  }

  @override
  String get toolbarLayoutSectionHeader => '工具栏布局';

  @override
  String get listViewOptionsSectionHeader => '列表视图选项';

  @override
  String get detailedListViewColumnsSectionHeader => '详细列表视图列';

  @override
  String get galleryGridViewSectionHeader => '图库网格视图';

  @override
  String get browserLayoutSectionHeader => '浏览器布局';

  @override
  String get mediaViewerSectionHeader => '媒体查看器';

  @override
  String get viewModeAction => '查看模式';

  @override
  String get sortAction => '排序';

  @override
  String get playMediaAction => '播放媒体';

  @override
  String containerSpaceSummary(String free, String total) {
    return '剩余$free · 共$total';
  }

  @override
  String volMountedSummary(int volId) {
    return '卷$volId · 已挂载';
  }

  @override
  String vaultOccupiedSpaceSummary(String used) {
    return '已用$used';
  }

  @override
  String get incorrectPasswordOrKeyfilesDriveError => '密码/密钥文件不正确，或驱动器不受支持';

  @override
  String driveUsableCapacity(int mb) {
    return '驱动器可用容量：$mb MB。不得超过此容量。';
  }

  @override
  String get unlockMethodManualPassword => '手动密码';

  @override
  String get unlockMethodRememberPassword => '记住密码';

  @override
  String get unlockMethodBiometrics => '生物识别解锁';

  @override
  String get unlockMethodPattern => '图案解锁';

  @override
  String get unlockMethodPin => 'PIN解锁';

  @override
  String get unlockMethodSubtitlePassword => '每次都输入密码';

  @override
  String get unlockMethodSubtitleRememberPassword => '安全存储在Android Keystore中';

  @override
  String get unlockMethodSubtitleBiometrics => '使用指纹或面容解锁';

  @override
  String get unlockMethodSubtitlePattern => '绘制图案以解锁';

  @override
  String get unlockMethodSubtitlePin => '输入PIN以解锁';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError => '视频解码器不可用——硬件编解码器争用';

  @override
  String get mediaStreamInitFailedError => '媒体流初始化失败';

  @override
  String get invalidAvifImage => '无效的AVIF图像';

  @override
  String get verbImport => '导入';

  @override
  String get verbExport => 'Export';

  @override
  String get verbMove => '移动';

  @override
  String get verbCopy => '复制';

  @override
  String get verbDelete => '删除';

  @override
  String get verbImported => '已导入';

  @override
  String get verbExported => 'Exported';

  @override
  String get verbMoved => '已移动';

  @override
  String get verbCopied => '已复制';

  @override
  String get verbDeleted => '已删除';

  @override
  String get verbImporting => '正在导入';

  @override
  String get verbExporting => 'Exporting';

  @override
  String get verbMoving => '正在移动';

  @override
  String get verbCopying => '正在复制';

  @override
  String get verbDeleting => '正在删除';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个项目',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个项目已$verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return '已跳过$count个';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return '$count个失败';
  }

  @override
  String get statusCancelled => '已取消';

  @override
  String get statusFailed => '失败';

  @override
  String get statusCompleted => '已完成';

  @override
  String get fileOpCheckingSpace => '正在检查可用空间…';

  @override
  String get fileOpResolvingConflicts => '正在解决冲突…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return '空间不足——需要$required，仅剩$free可用';
  }

  @override
  String get fileOpDiskFullPartialRemoved => '磁盘已满——已移除部分文件';

  @override
  String get fileOpMoveFailed => '移动失败';

  @override
  String get fileOpCopyFailed => '复制失败';

  @override
  String get fileOpDeleteFailed => '删除失败';

  @override
  String get fileOpDiskFull => '磁盘已满';

  @override
  String get fileOpImporting => '正在导入…';

  @override
  String get fileOpExporting => 'Exporting…';

  @override
  String fileOpImportingName(String name) {
    return '正在导入$name…';
  }

  @override
  String fileOpExportingName(String name) {
    return 'Exporting $name…';
  }

  @override
  String fileOpMovingName(String name) {
    return '正在移动$name…';
  }

  @override
  String fileOpCopyingName(String name) {
    return '正在复制$name…';
  }

  @override
  String get fileOpDeleting => '正在删除…';

  @override
  String fileOpDeletingName(String name) {
    return '正在删除$name…';
  }

  @override
  String fileOpDeletedSoFar(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已移除$count个项目',
    );
    return '$_temp0';
  }

  @override
  String get searchInSubfoldersHint => '搜索所有子文件夹…';

  @override
  String get deepSearchEnabledTooltip => '正在搜索子文件夹——点击以仅搜索当前文件夹';

  @override
  String get deepSearchDisabledTooltip => '正在搜索当前文件夹——点击以搜索子文件夹';

  @override
  String get filterAction => '筛选';

  @override
  String get bookmarkAction => '收藏';

  @override
  String get unbookmarkAction => '取消收藏';

  @override
  String get bookmarkSelectedAction => '收藏所选项';

  @override
  String get unbookmarkSelectedAction => '取消收藏所选项';

  @override
  String bookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已收藏$count个项目',
    );
    return '$_temp0';
  }

  @override
  String unbookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已取消收藏$count个项目',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => '显示收藏栏';

  @override
  String get showBookmarkBarDesc => '在收藏栏或侧边栏中显示已收藏的项目';

  @override
  String get bookmarkBarSectionHeader => '收藏栏';

  @override
  String get noBookmarksYet => '尚未收藏任何项目';

  @override
  String get reorderBookmarksTitle => '重新排列收藏项';

  @override
  String get reorderBookmarksDesc => '拖动项目以在收藏栏中重新排序';

  @override
  String get navBarVaultsLabel => '保险库';

  @override
  String get navBarToolsLabel => '工具';

  @override
  String get toolsScreenTitle => '工具';

  @override
  String get toolsSectionContainerUtilities => '容器实用工具';

  @override
  String get toolsSectionFileCryptography => '文件加密';

  @override
  String get toolsSectionStorageDiagnostics => '存储与诊断';

  @override
  String get toolContainerSplitterTitle => '拆分与合并';

  @override
  String get toolContainerSplitterSubtitle => '将容器拆分为多个块，或重新合并它们';

  @override
  String get toolContainerRepairTitle => '检查与修复';

  @override
  String get toolContainerRepairSubtitle => '诊断头部或文件系统问题';

  @override
  String get toolSingleFileCryptoTitle => '加密/解密文件';

  @override
  String get toolSingleFileCryptoSubtitle => '无需完整容器即可保护一个或多个文件';

  @override
  String get toolStorageAnalyzerTitle => '存储分析器';

  @override
  String get toolStorageAnalyzerSubtitle => '查看已挂载保险库中哪些内容占用了空间';

  @override
  String get toolDuplicateFinderTitle => '重复文件查找器';

  @override
  String get toolDuplicateFinderSubtitle => '查找并删除字节完全相同的重复文件以回收空间';

  @override
  String get toolHashVerifierTitle => '文件校验和与哈希验证器';

  @override
  String get toolHashVerifierSubtitle => '使用MD5/SHA校验和验证大文件未损坏';

  @override
  String get hashVerifierModeCompute => '计算';

  @override
  String get hashVerifierModeVerify => '验证';

  @override
  String get hashVerifierSelectSourceTitle => '选择文件来源';

  @override
  String get hashVerifierAlgorithmsLabel => '算法';

  @override
  String get hashVerifierNoAlgorithmSelected => '请至少选择一种算法';

  @override
  String get hashVerifierFilesLabel => '待哈希的文件';

  @override
  String hashVerifierFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选择$count个文件',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierComputeButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '计算$count个哈希值',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCancelButton => '取消';

  @override
  String hashVerifierBatchProgressLabel(Object current, Object total) {
    return '文件 $current/$total';
  }

  @override
  String get hashVerifierCancelledMessage => '已取消。';

  @override
  String hashVerifierComputeErrorsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个文件哈希计算失败',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCopiedMessage => '已复制到剪贴板';

  @override
  String get hashVerifierExportManifestButton => '导出为清单文件';

  @override
  String get hashVerifierExportAlgorithmLabel => '清单算法';

  @override
  String hashVerifierExportSuccessMessage(Object path) {
    return '已保存到$path';
  }

  @override
  String hashVerifierExportFailedMessage(Object error) {
    return '导出失败：$error';
  }

  @override
  String get hashVerifierLoadManifestButton => '加载清单文件';

  @override
  String get hashVerifierChangeManifestButton => '更改';

  @override
  String get hashVerifierManifestLabel => '清单文件';

  @override
  String hashVerifierManifestEntryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个条目',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierAutoAddFolderButton => '添加此文件夹中的所有文件';

  @override
  String get hashVerifierAddFilesToVerifyButton => '添加待验证文件';

  @override
  String get hashVerifierVerifyAllButton => '全部验证';

  @override
  String hashVerifierVerifyProgressLabel(Object current, Object total) {
    return '正在验证文件 $current/$total';
  }

  @override
  String hashVerifierSummaryMessage(
    Object ok,
    Object mismatch,
    Object missing,
  ) {
    return '匹配$ok个，不匹配$mismatch个，缺失$missing个';
  }

  @override
  String get hashVerifierStatusMatch => '匹配';

  @override
  String get hashVerifierStatusMismatch => '不匹配';

  @override
  String get hashVerifierStatusMissing => '文件未添加';

  @override
  String get hashVerifierStatusPending => '尚未验证';

  @override
  String get hashVerifierExpectedLabel => '预期值';

  @override
  String get hashVerifierActualLabel => '实际值';

  @override
  String hashVerifierExtraFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '有$count个未列入清单的额外文件',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierNoManifestLoadedMessage => '加载清单文件以开始';

  @override
  String get hashVerifierManifestParseEmptyMessage => '此文件中未找到任何校验和条目';

  @override
  String hashVerifierLoadManifestFailedMessage(Object error) {
    return '无法读取清单文件：$error';
  }

  @override
  String hashVerifierAutoAddedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已从保险库文件夹添加$count个文件',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierModeVault => '保险库';

  @override
  String get hashVerifierVaultPickerLabel => '保险库';

  @override
  String get hashVerifierVaultNoVaultsMessage => '当前没有已挂载的保险库';

  @override
  String get hashVerifierCheckEntireVaultButton => '检查整个保险库';

  @override
  String get hashVerifierVaultScanningLabel => '正在扫描保险库…';

  @override
  String hashVerifierVaultFilesDiscoveredLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已发现$count个文件',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmTitle => '检查整个保险库？';

  @override
  String hashVerifierVaultConfirmFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个文件',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmWarning => '此保险库中的每个文件都将被读取。';

  @override
  String get hashVerifierVaultEmptyMessage => '此保险库没有可检查的文件';

  @override
  String get hashVerifierVaultStartButton => '开始检查';

  @override
  String hashVerifierVaultHashingProgressLabel(Object current, Object total) {
    return '正在检查 $current / $total';
  }

  @override
  String get hashVerifierVaultCompleteTitle => '保险库检查完成';

  @override
  String hashVerifierVaultCompleteFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已检查$count个文件',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteBytesLabel(Object size) {
    return '已处理$size';
  }

  @override
  String hashVerifierVaultCompleteSucceededLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个成功',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count个失败',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultElapsedLabel(Object time) {
    return '已用时间：$time';
  }

  @override
  String get hashVerifierVaultCancelledMessage => '保险库检查已取消。';

  @override
  String hashVerifierVaultFailedMessage(Object error) {
    return '保险库检查失败：$error';
  }

  @override
  String get hashVerifierVaultNewCheckButton => '新检查';

  @override
  String get hashVerifierVaultActionComputeTitle => '计算整个保险库';

  @override
  String get hashVerifierVaultActionComputeSubtitle => '对保险库中的每个文件计算哈希值';

  @override
  String get hashVerifierVaultActionVerifyTitle => '验证整个保险库';

  @override
  String get hashVerifierVaultActionVerifySubtitle => '将保险库中的每个文件与已加载的清单进行核对';

  @override
  String get hashVerifierVaultChangeActionButton => '更改';

  @override
  String get hashVerifierVaultVerifyButton => '验证整个保险库';

  @override
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage =>
      '验证整个保险库需要从保险库内部加载的清单文件。';

  @override
  String get duplicateFinderTargetLabel => '目标保险库';

  @override
  String get duplicateFinderTargetAllVaults => '所有已打开的保险库';

  @override
  String get duplicateFinderStartScan => '开始扫描';

  @override
  String get duplicateFinderCancelScan => '取消扫描';

  @override
  String get duplicateFinderRescan => '重新扫描';

  @override
  String get duplicateFinderScanningStage1 => '第1阶段：正在索引并按大小分组...';

  @override
  String get duplicateFinderScanningStage2 => '第2阶段：正在检查部分文件头...';

  @override
  String get duplicateFinderScanningStage3 => '第3阶段：正在验证完整字节哈希...';

  @override
  String get duplicateFinderScanComplete => '扫描完成';

  @override
  String get duplicateFinderNoDuplicatesTitle => '未找到重复文件';

  @override
  String get duplicateFinderNoDuplicatesMessage => '已扫描保险库中的所有文件均包含唯一的字节内容。';

  @override
  String get duplicateFinderSelectRedundant => '选择冗余项';

  @override
  String get duplicateFinderSelectAll => '全选';

  @override
  String get duplicateFinderDeselectAll => '取消全选';

  @override
  String get duplicateFinderOriginalLabel => '原始文件';

  @override
  String get duplicateFinderDuplicateLabel => '重复项';

  @override
  String get duplicateFinderConfirmDeleteTitle => '删除重复文件？';

  @override
  String get duplicateFinderSearchHint => '按文件名或路径搜索重复项...';

  @override
  String get toolNotImplementedYetMessage => '此工具尚未连接到原生引擎——请在未来的更新中查看。';

  @override
  String get splitJoinModeSplit => '拆分';

  @override
  String get splitJoinModeJoin => '合并';

  @override
  String get splitSourceFileLabel => '源文件';

  @override
  String get splitDestinationFolderLabel => '目标文件夹';

  @override
  String get splitChunkSizeLabel => '分块大小';

  @override
  String get splitChunkSizeCustomLabel => '自定义大小（MB）';

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
  String get splitChunkSizeCustom => '自定义';

  @override
  String get splitContainerButton => '拆分容器';

  @override
  String get joinFirstPartLabel => '第一部分';

  @override
  String get joinOutputFileNameLabel => '输出文件名';

  @override
  String get joinContainerButton => '合并文件';

  @override
  String get chooseFileButton => '选择文件';

  @override
  String get chooseFolderButton => '选择文件夹';

  @override
  String get noFileSelectedLabel => '未选择文件';

  @override
  String get noFolderSelectedLabel => '未选择文件夹';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage => '容器拆分成功';

  @override
  String get joinContainerSuccessMessage => '文件合并成功';

  @override
  String get cryptoDirectionEncrypt => '加密';

  @override
  String get cryptoDirectionDecrypt => '解密';

  @override
  String get singleFileCryptoInputFileLabel => '输入文件';

  @override
  String get singleFileCryptoCipherLabel => '加密算法';

  @override
  String get singleFileCryptoDeleteOriginalLabel => '加密后删除原始文件';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '加密$count个文件',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '解密$count个文件',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '完成——已处理$count个文件',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return '$total个文件中已处理$succeeded个——$failed个失败';
  }

  @override
  String get singleFileCryptoAddFilesButton => '添加文件';

  @override
  String get singleFileCryptoClearFilesButton => '清除';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已选择$count个文件',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return '文件 $current/$total';
  }

  @override
  String get repairTargetStepTitle => '选择目标';

  @override
  String get repairTargetUnmountedFileOption => '未挂载的文件';

  @override
  String get repairTargetUnmountedFileSubtitle => '在您尚未打开的容器上恢复备份头';

  @override
  String get repairTargetMountedVolumeSubtitle => '对已打开的保险库运行文件系统检查';

  @override
  String get repairNoMountedVolumes => '当前没有已挂载的保险库';

  @override
  String get repairScanButton => '运行诊断扫描';

  @override
  String get repairChangeTargetButton => '更改目标';

  @override
  String get repairDiagnosisHealthy => '未发现问题';

  @override
  String get repairDiagnosisHeaderCorrupted => '头部已损坏';

  @override
  String get repairDiagnosisFilesystemDirty => '文件系统不干净／未正常卸载';

  @override
  String get repairRestoreBackupHeaderButton => '恢复备份头';

  @override
  String get repairRunFilesystemCheckButton => '运行文件系统检查与修复';

  @override
  String get repairActionSucceededMessage => '修复已成功完成';

  @override
  String get repairActionFailedMessage => '修复操作未成功';

  @override
  String get storageAnalyzerTargetLabel => '卷';

  @override
  String get storageAnalyzerNoTargetsTitle => '没有可分析的内容';

  @override
  String get storageAnalyzerNoTargetsMessage => '请先挂载一个保险库，然后返回此处查看其存储明细。';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return '已用$used，共$total';
  }

  @override
  String get storageAnalyzerHeaviestFilesHeader => '最大文件';

  @override
  String get storageAnalyzerBreakdownHeader => '按文件类型';

  @override
  String get storageAnalyzerScanningMessage => '正在扫描卷…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return '扫描在$count个文件后提前停止——结果可能不完整。';
  }

  @override
  String get storageAnalyzerNoFilesFound => '未找到文件';

  @override
  String get storageCategoryImages => '图片';

  @override
  String get storageCategoryVideos => '视频';

  @override
  String get storageCategoryAudio => '音频';

  @override
  String get storageCategoryDocuments => '文档';

  @override
  String get storageCategoryArchives => '压缩包';

  @override
  String get storageCategoryOther => '其他';

  @override
  String get keyfilePassphraseGeneratorTitle => '密钥文件与密码短语生成器';

  @override
  String get keyfilePassphraseGeneratorSubtitle =>
      '生成Diceware密码短语、自定义密码和高熵密钥文件';

  @override
  String get tabPassphrase => '密码短语';

  @override
  String get tabKeyfile => '密钥文件';

  @override
  String get modeDiceware => 'Diceware密码短语';

  @override
  String get modeCustomPassword => '自定义密码';

  @override
  String get keyfileTypeBinary => '二进制密钥文件（.key）';

  @override
  String get keyfileTypeImage => '噪点图像密钥文件（.png）';

  @override
  String get copyPassphraseSuccess => '密码短语已复制到安全剪贴板';

  @override
  String get copyFingerprintSuccess => 'SHA-256指纹已复制到剪贴板';

  @override
  String get saveKeyfileToVault => '保存到已挂载的保险库';

  @override
  String get exportKeyfileToStorage => '导出到设备存储';

  @override
  String get keyfileNoOpenVaultsMessage => '没有可用的已打开保险库。请先挂载一个保险库。';

  @override
  String get keyfileSelectDestinationVaultTitle => '选择目标保险库';

  @override
  String keyfileVolumeIdLabel(Object volId) {
    return '卷ID：$volId';
  }

  @override
  String keyfileExportSuccessMessage(Object path) {
    return '密钥文件已导出到$path';
  }

  @override
  String keyfileExportFailedMessage(Object error) {
    return '导出失败：$error';
  }

  @override
  String keyfileSavedToVaultMessage(Object vaultName, Object path) {
    return '密钥文件已保存到$vaultName：$path';
  }

  @override
  String get keyfileWriteFailedMessage => '无法将密钥文件写入保险库';

  @override
  String keyfileSaveErrorMessage(Object error) {
    return '保存到保险库时出错：$error';
  }

  @override
  String get passphraseGeneratedSecretLabel => '生成的密钥';

  @override
  String get copyToClipboardTooltip => '复制到剪贴板';

  @override
  String get generateNewTooltip => '重新生成';

  @override
  String get passphraseStrengthWeak => '弱';

  @override
  String get passphraseStrengthGood => '良好';

  @override
  String get passphraseStrengthStrong => '强';

  @override
  String get passphraseStrengthUnbreakable => '无法破解';

  @override
  String get passphraseCrackTimeInstant => '小于1秒';

  @override
  String get passphraseCrackTimeShort => '几天/几个月';

  @override
  String get passphraseCrackTimeCenturies => '数个世纪';

  @override
  String get passphraseCrackTimeMillionsOfYears => '数百万年';

  @override
  String passphraseStrengthLabel(Object label) {
    return '强度：$label';
  }

  @override
  String passphraseEntropyBitsLabel(Object bits) {
    return '熵值$bits位';
  }

  @override
  String passphraseCrackTimeLabel(Object crackTime) {
    return '预计破解时间：$crackTime';
  }

  @override
  String get dicewareOptionsTitle => 'EFF Diceware选项';

  @override
  String dicewareWordCountLabel(Object count) {
    return '单词数：$count个';
  }

  @override
  String dicewareWordCountBitsLabel(Object bits) {
    return '$bits位';
  }

  @override
  String dicewareWordCountSliderLabel(Object count) {
    return '$count个单词';
  }

  @override
  String get dicewareWordSeparatorLabel => '单词分隔符';

  @override
  String get dicewareSeparatorHyphen => '连字符（-）';

  @override
  String get dicewareSeparatorSpace => '空格（ ）';

  @override
  String get dicewareSeparatorUnderscore => '下划线（_）';

  @override
  String get dicewareSeparatorDot => '点（.）';

  @override
  String get dicewareSeparatorSlash => '斜杠（/）';

  @override
  String get dicewareWordCasingLabel => '单词大小写';

  @override
  String get dicewareCasingLowercase => '小写';

  @override
  String get dicewareCasingTitleCase => '首字母大写';

  @override
  String get dicewareCasingUppercase => '大写';

  @override
  String get dicewareAppendDigitLabel => '附加随机数字（0-9）';

  @override
  String get dicewareAppendSymbolLabel => '附加随机符号（!@#\$%）';

  @override
  String get customPasswordOptionsTitle => '自定义密码选项';

  @override
  String customPasswordLengthLabel(Object length) {
    return '长度：$length个字符';
  }

  @override
  String customPasswordLengthSliderLabel(Object length) {
    return '$length个字符';
  }

  @override
  String get customPasswordUppercaseLabel => '大写字母（A-Z）';

  @override
  String get customPasswordLowercaseLabel => '小写字母（a-z）';

  @override
  String get customPasswordNumbersLabel => '数字（0-9）';

  @override
  String get customPasswordSymbolsLabel => '符号（!@#\$%^&*）';

  @override
  String get customPasswordExcludeAmbiguousLabel => '排除易混淆字符（1、l、I、0、O）';

  @override
  String get keyfileBinarySizeTitle => '二进制密钥文件大小';

  @override
  String get keyfileImageResolutionTitle => '噪点图像分辨率';

  @override
  String get keyfilePresetBytes64 => '64字节（VeraCrypt标准）';

  @override
  String get keyfilePresetBytes256 => '256字节';

  @override
  String get keyfilePresetBytes2048 => '2 KB';

  @override
  String get keyfilePresetBytes64kb => '64 KB';

  @override
  String get keyfilePresetBytes1mb => '1 MB（最大限制）';

  @override
  String get keyfilePresetRes64 => '64×64像素（约16 KB）';

  @override
  String get keyfilePresetRes256 => '256×256像素（约256 KB）';

  @override
  String get keyfilePresetRes512 => '512×512像素（约1 MB）';

  @override
  String get keyfileGenerateNewTooltip => '生成新密钥文件';

  @override
  String keyfileSizeLabel(Object size) {
    return '大小：$size';
  }

  @override
  String get keyfileFingerprintLabel => 'SHA-256指纹';

  @override
  String get keyfileCopyFingerprintTooltip => '复制指纹';

  @override
  String get duplicateFinderNoVaultsTitle => '没有已挂载的保险库';

  @override
  String get duplicateFinderNoVaultsMessage => '请先解锁并挂载至少一个保险库容器，以扫描重复文件。';

  @override
  String duplicateFinderConfirmDeleteMessage(Object count, Object size) {
    return '确定要从您的保险库中永久删除$count个重复文件（$size）吗？此操作无法撤销。';
  }

  @override
  String get duplicateFinderDeletePermanentlyButton => '永久删除';

  @override
  String duplicateFinderDeleteSuccessMessage(Object count) {
    return '已成功删除$count个重复文件。';
  }

  @override
  String get duplicateFinderIntroTitle => '三阶段字节级完全匹配查找';

  @override
  String get duplicateFinderIntroSubtitle => '无论文件名如何，都能检测出内容完全相同的文件。';

  @override
  String get duplicateFinderStagesDescription =>
      '• 第1阶段：按大小分组（即时元数据扫描）\n• 第2阶段：部分文件头检查（16 KB SHA-256文件头）\n• 第3阶段：完整哈希验证（精确的SHA-256字节匹配）';

  @override
  String get duplicateFinderScanningVaultFallback => '正在扫描保险库...';

  @override
  String duplicateFinderProcessingFileLabel(Object fileName) {
    return '正在处理：$fileName';
  }

  @override
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  ) {
    return '已扫描文件：$scanned | 发现重复：$groups组（$saved）';
  }

  @override
  String duplicateFinderGroupsFoundLabel(Object count) {
    return '发现$count个重复组';
  }

  @override
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved) {
    return '发现$copies份副本 • 可节省$saved存储空间';
  }

  @override
  String duplicateFinderVaultsSelectedLabel(Object count) {
    return '已选择$count个保险库';
  }

  @override
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  ) {
    return '第$groupIndex组：$size（发现$count份副本）';
  }

  @override
  String duplicateFinderRecoverableSpaceLabel(Object size) {
    return '可恢复空间：$size';
  }

  @override
  String get duplicateFinderPreviewFileTooltip => '预览文件';

  @override
  String duplicateFinderPreviewFailedMessage(Object fileName) {
    return '无法打开$fileName的文件预览';
  }

  @override
  String duplicateFinderPreviewErrorMessage(Object error) {
    return '预览文件时出错：$error';
  }

  @override
  String duplicateFinderFilesSelectedLabel(Object count) {
    return '已选择$count个文件';
  }

  @override
  String duplicateFinderBytesToBeFreedLabel(Object size) {
    return '将释放$size';
  }

  @override
  String duplicateFinderDeleteSelectedButton(Object count) {
    return '删除所选（$count）';
  }

  @override
  String get vaultBrowserSwitchVaultTooltip => '切换保险库';

  @override
  String get vaultBrowserRootFolderLabel => '根文件夹';

  @override
  String vaultFilePickerTitle(Object vaultName) {
    return '选择文件（$vaultName）';
  }

  @override
  String get vaultFilePickerEmptyMessage => '文件夹为空';

  @override
  String vaultFilePickerConfirmButton(Object count) {
    return '选择$count个文件';
  }

  @override
  String vaultFolderPickerTitle(Object vaultName) {
    return '选择文件夹（$vaultName）';
  }

  @override
  String get vaultFolderPickerEmptyMessage => '此处没有子文件夹';

  @override
  String get vaultFolderPickerRootLabel => '根目录';

  @override
  String get vaultFolderPickerConfirmRootButton => '选择根文件夹';

  @override
  String vaultFolderPickerConfirmNamedButton(Object folderName) {
    return '选择“$folderName”';
  }

  @override
  String get singleFileCryptoSelectInputTitle => '选择输入文件';

  @override
  String get singleFileCryptoFromDeviceTitle => '从设备存储';

  @override
  String get singleFileCryptoFromDeviceSubtitle => '使用系统文件选择器从设备中选取文件';

  @override
  String get singleFileCryptoFromVaultTitle => '从已挂载的保险库';

  @override
  String get singleFileCryptoFromVaultSubtitle => '从已打开的加密容器中选取文件';

  @override
  String get singleFileCryptoSelectDestinationTitle => '选择目标文件夹';

  @override
  String get singleFileCryptoDeviceFolderTitle => '设备存储文件夹';

  @override
  String get singleFileCryptoDeviceFolderSubtitle => '将输出保存到设备存储中的文件夹';

  @override
  String get singleFileCryptoVaultFolderTitle => '已挂载的保险库文件夹';

  @override
  String get singleFileCryptoVaultFolderSubtitle => '将输出保存在已打开的加密容器内';

  @override
  String get toolsSectionBackupSync => '备份与同步';

  @override
  String get toolVaultSyncTitle => '保险库同步';

  @override
  String get toolVaultSyncSubtitle => '比较两个保险库并复制缺失或更新的内容';

  @override
  String get vaultSyncNoVaultsTitle => '没有已挂载的保险库';

  @override
  String get vaultSyncNoVaultsMessage => '请至少挂载一个保险库以比较和同步其文件。';

  @override
  String get vaultSyncLeftLabel => '左侧';

  @override
  String get vaultSyncRightLabel => '右侧';

  @override
  String get vaultSyncTapToSelect => '点击选择保险库和文件夹';

  @override
  String get vaultSyncSwapTooltip => '交换左右两侧';

  @override
  String get vaultSyncSameLocationWarning => '左侧和右侧必须是不同的文件夹。';

  @override
  String get vaultSyncIntroTitle => '比较两个保险库';

  @override
  String get vaultSyncIntroSubtitle =>
      '选择左侧和右侧的保险库（或同一保险库中的两个文件夹），以查看每一侧缺失、已修改或较新的内容。';

  @override
  String get vaultSyncCompareButton => '比较';

  @override
  String get vaultSyncComparingLabel => '正在比较保险库…';

  @override
  String vaultSyncCompareStatsLabel(Object dirs, Object entries) {
    return '已扫描文件夹：$dirs | 发现差异：$entries';
  }

  @override
  String get vaultSyncCancelCompareButton => '取消';

  @override
  String get vaultSyncInSyncTitle => '已同步';

  @override
  String vaultSyncInSyncMessage(num count) {
    return '所有$count个匹配文件在两侧完全相同。';
  }

  @override
  String get vaultSyncRecompareButton => '重新比较';

  @override
  String vaultSyncDifferencesFoundLabel(num count) {
    return '发现$count处差异';
  }

  @override
  String vaultSyncInSyncCountLabel(num count) {
    return '$count个文件在两侧已经匹配';
  }

  @override
  String vaultSyncBadgeOnlyLeft(Object count) {
    return '仅左侧有$count个';
  }

  @override
  String vaultSyncBadgeOnlyRight(Object count) {
    return '仅右侧有$count个';
  }

  @override
  String vaultSyncBadgeLeftNewer(Object count) {
    return '左侧较新$count个';
  }

  @override
  String vaultSyncBadgeRightNewer(Object count) {
    return '右侧较新$count个';
  }

  @override
  String vaultSyncBadgeConflicts(num count) {
    return '需审核$count个';
  }

  @override
  String get vaultSyncDirectionLabel => '同步方向';

  @override
  String get vaultSyncDirectionTwoWay => '双向（推荐）';

  @override
  String get vaultSyncDirectionTwoWaySubtitle => '将每个文件复制到缺失该文件或副本较旧的一侧';

  @override
  String get vaultSyncDirectionLeftToRight => '左侧 → 右侧（单向）';

  @override
  String get vaultSyncDirectionLeftToRightSubtitle =>
      '将新增和更新的文件从左侧推送到右侧；绝不更改左侧';

  @override
  String get vaultSyncDirectionRightToLeft => '右侧 → 左侧（单向）';

  @override
  String get vaultSyncDirectionRightToLeftSubtitle =>
      '将新增和更新的文件从右侧推送到左侧；绝不更改右侧';

  @override
  String get vaultSyncSearchHint => '搜索差异';

  @override
  String get vaultSyncStatusOnlyLeft => '仅左侧';

  @override
  String get vaultSyncStatusOnlyRight => '仅右侧';

  @override
  String get vaultSyncStatusLeftNewer => '左侧较新';

  @override
  String get vaultSyncStatusRightNewer => '右侧较新';

  @override
  String get vaultSyncStatusConflict => '需审核';

  @override
  String get vaultSyncStatusTypeMismatch => '类型不匹配';

  @override
  String get vaultSyncFolderOnlyLeftDetail => '文件夹——仅左侧';

  @override
  String get vaultSyncFolderOnlyRightDetail => '文件夹——仅右侧';

  @override
  String vaultSyncBothSidesDetail(
    Object leftSize,
    Object leftDate,
    Object rightSize,
    Object rightDate,
  ) {
    return '左：$leftSize · $leftDate  →  右：$rightSize · $rightDate';
  }

  @override
  String get vaultSyncTypeMismatchTooltip => '一侧是文件，另一侧是文件夹——请在文件浏览器中手动处理';

  @override
  String get vaultSyncChangeActionTooltip => '更改同步操作';

  @override
  String get vaultSyncActionCopyToRight => '复制 → 右侧';

  @override
  String get vaultSyncActionCopyToLeft => '复制 → 左侧';

  @override
  String get vaultSyncActionSkip => '跳过';

  @override
  String vaultSyncChangesQueuedLabel(num count) {
    return '已排队$count项更改';
  }

  @override
  String get vaultSyncSyncNowButton => '立即同步';

  @override
  String get vaultSyncConfirmTitle => '开始同步？';

  @override
  String vaultSyncConfirmMessage(num count, Object bytes) {
    return '这将在两侧之间复制$count个项目（共$bytes）。同名的现有文件将被覆盖。';
  }

  @override
  String vaultSyncStartedMessage(num count) {
    return '同步已开始——已排队$count个项目';
  }

  @override
  String vaultSyncPickLocationTitle(Object side) {
    return '选择$side保险库和文件夹';
  }

  @override
  String get vaultSyncReadOnlyBadge => '只读';

  @override
  String get vaultSyncReadOnlyTooltip => '此保险库以只读方式挂载——无法向其中复制文件';

  @override
  String get vaultSyncSyncingButton => '正在同步…';

  @override
  String get vaultSyncNotEnoughSpaceTitle => '空间不足';

  @override
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  ) {
    return '$side空间不足——需要$required，仅剩$free可用。';
  }

  @override
  String get removeMasterPasswordTitle => '移除主密码';

  @override
  String get confirmRemoveMasterPasswordMessage => '请输入您当前的主密码以确认移除：';

  @override
  String get authenticateToRemoveMasterPassword => '进行身份验证以移除主密码';

  @override
  String get incorrectPassword => '密码错误';

  @override
  String get rememberPerFolderLayoutLabel => '记住每个文件夹的布局';

  @override
  String get rememberPerFolderLayoutDesc => '为每个文件夹分别保存视图布局（列表、网格、瀑布流）';

  @override
  String get fileInfoAction => '信息';

  @override
  String get automationScreenTitle => '自动化（Tasker / MacroDroid）';

  @override
  String get automationUsbUnsupportedMessage => 'USB连接的保险库尚不支持自动化。';

  @override
  String get automationThisVaultSectionHeader => '此保险库';

  @override
  String get automationAccessLabel => '自动化访问权限';

  @override
  String get automationPasswordSectionHeader => '自动化密码';

  @override
  String get automationPasswordStoredHint =>
      '已为无人值守的UNLOCK_VAULT调用存储了密码。保存新密码即可替换，或保存空字段以清除它——自动化也可以直接在广播中提供密码，而不依赖此设置。';

  @override
  String get automationPasswordNotStoredHint =>
      '可选。若未存储密码，自动化必须在每次UNLOCK_VAULT广播中提供一个。';

  @override
  String get automationNewPasswordFieldLabel => '新密码';

  @override
  String get automationPasswordFieldLabel => '密码';

  @override
  String get automationClearPasswordButton => '清除已存储的密码';

  @override
  String get automationSavePasswordButton => '保存密码';

  @override
  String get automationTokenSectionHeader => 'API令牌';

  @override
  String get automationTokenDescription =>
      '由所有已启用自动化访问权限的保险库共享。自动化会在每次广播时将其发回；令牌错误或缺失会被静默忽略，不会报错。';

  @override
  String get automationRegenerateTokenButton => '重新生成令牌';

  @override
  String get automationRegenerateTokenDialogTitle => '重新生成令牌？';

  @override
  String get automationRegenerateTokenDialogMessage =>
      '在您用新令牌更新之前，任何使用当前令牌的Tasker配置文件或MacroDroid宏都将静默失效。';

  @override
  String get automationRegenerateConfirmLabel => '重新生成';

  @override
  String get automationTokenRegeneratedMessage => '令牌已重新生成。';

  @override
  String get automationRegenerateTokenFailedMessage => '无法重新生成令牌。';

  @override
  String get automationUpdateSettingsFailedMessage => '无法更新自动化设置。';

  @override
  String get automationSavePasswordFailedMessage => '无法保存自动化密码。';

  @override
  String get automationPasswordClearedMessage => '自动化密码已清除。';

  @override
  String get automationPasswordSavedMessage => '自动化密码已保存。';

  @override
  String get automationConfigSectionHeader => '配置字符串';

  @override
  String get automationConfigIntro =>
      '点击下方任意值即可复制。在Tasker中，使用“Send Intent”操作；在MacroDroid中，使用Intent Type设置为Broadcast的“Intent”操作——而非Activity或Service，后者会因“unable to find explicit activity class”而失败。';

  @override
  String get automationConfigPackageLabel => '包名';

  @override
  String get automationConfigClassLabel => '接收器类';

  @override
  String get automationConfigVaultUriLabel => '此保险库的URI';

  @override
  String get automationConfigActionsSectionHeader => '广播操作';

  @override
  String get automationActionUnlockLabel => '解锁保险库';

  @override
  String get automationActionLockLabel => '锁定保险库';

  @override
  String get automationActionImportLabel => '导入文件';

  @override
  String get automationActionExportLabel => '导出文件';

  @override
  String get automationActionWipeLabel => '清除文件';

  @override
  String get automationDocCommentFootnote =>
      '完整的附加参数和结果广播约定记录在VaultAutomationReceiver.kt中。';

  @override
  String get automationTierOffLabel => '关闭';

  @override
  String get automationTierOffSubtitle => '自动化无法访问此保险库';

  @override
  String get automationTierLifecycleLabel => '仅解锁／锁定';

  @override
  String get automationTierLifecycleSubtitle => '自动化只能解锁和锁定此保险库，不能执行其他操作';

  @override
  String get automationTierFullLabel => '解锁／锁定 + 文件导入导出';

  @override
  String get automationTierFullSubtitle => '在此保险库解锁期间，自动化还可以导入和导出文件';

  @override
  String get automationTutorialLinkLabel => '阅读完整的分步教程';

  @override
  String get showHiddenFilesLabel => '显示隐藏文件';

  @override
  String get showHiddenFilesDesc => '显示点文件和系统文件夹';

  @override
  String get dontAskAgain => '不再询问';

  @override
  String get deleteAfterImportLabel => '导入后删除文件';

  @override
  String get deleteAfterImportModeAsk => '每次询问';

  @override
  String get deleteAfterImportModeAskSubtitle => '导入后询问是否删除原始文件';

  @override
  String get deleteAfterImportModeKeep => '保留原始文件（不删除）';

  @override
  String get deleteAfterImportModeKeepSubtitle => '永不删除原始文件，且不再询问';

  @override
  String get deleteAfterImportModeDelete => '自动删除原始文件';

  @override
  String get deleteAfterImportModeDeleteSubtitle => '导入后自动从设备中删除原始文件';

  @override
  String get wizardBackButton => 'Back';

  @override
  String get wizardNextButton => 'Next';

  @override
  String get wizardStepTypeTitle => 'Type';

  @override
  String get wizardStepBasicInfoTitle => 'Basic Info';

  @override
  String get wizardStepAdvancedTitle => 'Advanced';

  @override
  String get wizardStepReviewTitle => 'Review';

  @override
  String get wizardCreateTypePrompt => 'What would you like to create?';

  @override
  String get wizardChooseFormatPrompt => 'Choose a container format';

  @override
  String get wizardEncryptionDetailsRowTitle => 'Encryption Details';

  @override
  String get wizardHiddenVolumeRowSubtitleConfigured =>
      'Configured — tap to review';

  @override
  String get wizardHiddenVolumeRowSubtitleNeedsSetup => 'Tap to set up';

  @override
  String get wizardSummaryTitle => 'Summary';

  @override
  String get wizardSummaryPasswordLabel => 'Password';

  @override
  String get wizardPasswordSetValue => 'Set';

  @override
  String get wizardPasswordNotSetValue => 'Not set (using keyfiles)';

  @override
  String get wizardSummaryKeyfilesLabel => 'Keyfiles';

  @override
  String get wizardSummaryPimDefaultValue => 'Default';

  @override
  String get wizardSummaryPimLabel => 'PIM';

  @override
  String get wizardSummaryDriveLabel => 'USB Drive';

  @override
  String get sectionKeyStorageIntegration => '密钥存储与系统访问';

  @override
  String get sectionMaskMode => '伪装模式';

  @override
  String get advancedOptionsTitle => 'Advanced Options';

  @override
  String get audioTrackTitle => 'Audio Track';

  @override
  String get noAudioTracksAvailable => 'No audio tracks available';

  @override
  String trackNumberLabel(int number) {
    return 'Track $number';
  }

  @override
  String subtitleTrackNumberLabel(int number) {
    return 'Subtitle $number';
  }

  @override
  String get offLabel => 'Off';

  @override
  String get externalSubtitlesLabel => 'External Subtitles (.srt/.vtt)';

  @override
  String get externalLabel => 'External';

  @override
  String get subtitleSizeLabel => 'Size';

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
  String get subtitlePositionBottom => 'Bottom';

  @override
  String get subtitlePositionLower => 'Lower';

  @override
  String get subtitlePositionCenter => 'Center';

  @override
  String get subtitlePositionTop => 'Top';

  @override
  String get editImageAction => 'Edit Image';

  @override
  String get imageEditorUnsupportedFormatMessage =>
      'This image format isn\'t supported for editing.';

  @override
  String get cropToolLabel => 'Crop';

  @override
  String get drawToolLabel => 'Draw';

  @override
  String get textToolLabel => 'Text';

  @override
  String get redactToolLabel => 'Redact';

  @override
  String get rotateLeftTooltip => 'Rotate left';

  @override
  String get rotateRightTooltip => 'Rotate right';

  @override
  String get cropAspectFreeLabel => 'Free';

  @override
  String get cropAspectSquareLabel => 'Square';

  @override
  String get cropAspectOriginalLabel => 'Original';

  @override
  String get applyCropTooltip => 'Apply crop';

  @override
  String get annotationColorTooltip => 'Color';

  @override
  String get annotationStrokeWidthTooltip => 'Stroke width';

  @override
  String get clearAnnotationsTooltip => 'Clear all annotations';

  @override
  String get resetImageTooltip => 'Reset to original';

  @override
  String get resetImageConfirmTitle => 'Reset image?';

  @override
  String get resetImageConfirmMessage =>
      'This discards every crop and drawing change made in this session.';

  @override
  String get addTextAnnotationTitle => 'Add text';

  @override
  String get addTextAnnotationHint => 'Type something…';

  @override
  String get textToolHint => 'Tap the image to add text';

  @override
  String get saveImageSheetTitle => 'Save changes';

  @override
  String get saveAsNewFileOption => 'Save as new file';

  @override
  String get saveAsNewFileDescription => 'Keeps the original untouched';

  @override
  String get overwriteOriginalOption => 'Overwrite original';

  @override
  String get overwriteOriginalDescription => 'Replaces the original file';

  @override
  String get newFileNameLabel => 'File name';

  @override
  String get imageEditorPngNoteMessage => 'Edited images are saved as PNG.';

  @override
  String get imageSavedMessage => 'Image saved';

  @override
  String imageSaveFailedMessage(String error) {
    return 'Couldn\'t save image: $error';
  }
}
