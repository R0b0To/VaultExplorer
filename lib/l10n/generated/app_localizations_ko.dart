// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get cancel => '취소';

  @override
  String get close => '닫기';

  @override
  String get search => '검색';

  @override
  String get goBack => '뒤로';

  @override
  String xOfYCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get pdfViewerGoToPageTitle => '페이지로 이동';

  @override
  String pdfViewerPageNumberHint(int pageCount) {
    return '페이지 번호 (1~$pageCount)';
  }

  @override
  String get pdfViewerPageLabel => '페이지';

  @override
  String get pdfViewerGoButton => '이동';

  @override
  String get pdfViewerSearchHint => '문서 내 검색';

  @override
  String get pdfViewerNoMatches => '일치하는 항목 없음';

  @override
  String get pdfViewerPreviousMatch => '이전 항목';

  @override
  String get pdfViewerNextMatch => '다음 항목';

  @override
  String get pdfViewerCloseSearch => '검색 닫기';

  @override
  String get pdfViewerPrintTooltip => '문서 인쇄';

  @override
  String get pdfViewerLoadingDocument => '문서 로드 중…';

  @override
  String get pdfViewerCannotOpenTitle => 'PDF를 열 수 없음';

  @override
  String get pdfViewerFailedToLoad => 'PDF 로드 실패';

  @override
  String get pdfViewerEditTooltip => '편집';

  @override
  String get pdfViewerDoneEditingTooltip => '편집 완료';

  @override
  String get pdfViewerSaveFailed => '이 PDF의 변경 사항을 저장할 수 없습니다';

  @override
  String get pdfViewerEditUnavailable => '이 문서는 편집을 사용할 수 없습니다';

  @override
  String get paste => '붙여넣기';

  @override
  String get clear => '지우기';

  @override
  String get clipboardVerbMove => '이동';

  @override
  String get clipboardVerbCopy => '복사';

  @override
  String clipboardTooltipInteractive(String verb, int count) {
    return '$verb ($count) — 탭하면 세부정보, 길게 누르면 붙여넣기';
  }

  @override
  String clipboardTooltipViewOnly(String verb, int count) {
    return '$verb ($count) — 클립보드 세부정보';
  }

  @override
  String clipboardSourceLabel(String source) {
    return '출처: $source';
  }

  @override
  String get clipboardDefaultSourceName => '볼트';

  @override
  String clipboardHeaderCount(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardMoreItems(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '+$count개 더보기',
    );
    return '$_temp0';
  }

  @override
  String get advancedParametersTitle => '고급 매개변수';

  @override
  String get pimFieldLabel => 'PIM (기본값을 사용하려면 비워 두세요)';

  @override
  String get encryptionAlgorithmLabel => '암호화 알고리즘';

  @override
  String get hashAlgorithmLabel => '해시 알고리즘';

  @override
  String get clipboardVerbMoving => '이동 중';

  @override
  String get clipboardVerbCopying => '복사 중';

  @override
  String clipboardPillTitle(String verb, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개',
    );
    return '$verb $_temp0';
  }

  @override
  String clipboardFromSourceSuffix(String source) {
    return ' \"$source\"에서';
  }

  @override
  String get clipboardOpenContainerToPaste => '붙여넣으려면 컨테이너를 여세요';

  @override
  String get keyfilesOptionalLabel => '키파일 (선택 사항)';

  @override
  String get addFile => '파일 추가';

  @override
  String get noKeyfilesAttached => '첨부된 키파일 없음';

  @override
  String get completed => '완료됨';

  @override
  String get dismiss => '닫기';

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
      other: '전송 $count개',
    );
    return '$_temp0';
  }

  @override
  String multiOpSublabel(String summary) {
    return '$summary · 탭하여 전체 보기';
  }

  @override
  String get thumbnailSizeResolutionLabel => '썸네일 크기 (해상도)';

  @override
  String get jpegCompressionQualityLabel => 'JPEG 압축 품질';

  @override
  String get done => '완료';

  @override
  String get confirm => '확인';

  @override
  String get couldNotPickKeyfiles => '키파일을 선택할 수 없습니다';

  @override
  String get filesystemLabelEncryptedVault => '이 암호화된 볼트';

  @override
  String get filesystemLabelThisContainer => '이 컨테이너';

  @override
  String get nounFile => '파일';

  @override
  String get nounFolder => '폴더';

  @override
  String get nounFileCapitalized => '파일';

  @override
  String get nounFolderCapitalized => '폴더';

  @override
  String get unitBytes => '바이트';

  @override
  String get unitCharacters => '자';

  @override
  String get validationEmptyName => '이름은 비워 둘 수 없습니다.';

  @override
  String validationReservedNavName(String name, String noun) {
    return '\"$name\"은(는) 예약된 탐색 이름이므로 $noun 이름으로 사용할 수 없습니다.';
  }

  @override
  String validationIllegalChar(String char, int position, String fsLabel) {
    return '$fsLabel에서는 위치 $position의 \"$char\"을(를) 이름에 사용할 수 없습니다.';
  }

  @override
  String validationControlChar(int position, String code, String fsLabel) {
    return '위치 $position에 인쇄할 수 없는 제어 문자(코드 $code)가 포함되어 있으며, $fsLabel에서는 허용되지 않습니다.';
  }

  @override
  String validationReservedDeviceName(String name, String fsLabel) {
    return '\"$name\"은(는) $fsLabel의 예약된 장치 이름(CON, PRN, AUX, NUL, COM0–9, LPT0–9 중 하나)에 해당하므로 확장자 유무와 관계없이 사용할 수 없습니다.';
  }

  @override
  String validationTrailingSpace(String noun, String fsLabel) {
    return '$fsLabel에서 $noun 이름은 공백으로 끝날 수 없습니다';
  }

  @override
  String validationTrailingDot(String noun, String fsLabel) {
    return '$fsLabel에서 $noun 이름은 \".\"으로 끝날 수 없습니다';
  }

  @override
  String validationNameTooLong(
    int length,
    String unit,
    String fsLabel,
    int maxLength,
    String noun,
  ) {
    return '이 이름은 $length$unit입니다. $fsLabel에서는 $noun 이름당 최대 $maxLength$unit까지 허용됩니다.';
  }

  @override
  String validationPathTooLong(int length, String fsLabel, int maxLength) {
    return '전체 경로는 $length자입니다. $fsLabel에서는 최대 $maxLength자까지 허용됩니다.';
  }

  @override
  String conflictSameType(String noun, String name) {
    return '\"$name\"(이)라는 이름의 $noun이(가) 이미 여기에 있습니다.';
  }

  @override
  String conflictCrossType(
    String existingNoun,
    String name,
    String candidateNoun,
  ) {
    return '\"$name\"(이)라는 이름의 $existingNoun이(가) 이미 여기에 있습니다 — $candidateNoun과(와) 같은 이름을 사용할 수 없습니다.';
  }

  @override
  String get readOnlyContainerWarning => '이 컨테이너는 읽기 전용으로 마운트되었습니다.';

  @override
  String get hiddenVolumeProtectionTriggeredWarning =>
      '이 외부 볼륨에 쓰기 작업을 하면 숨김 볼륨이 손상될 수 있어 차단되었습니다. 이 컨테이너는 이번 세션이 끝날 때까지 읽기 전용으로 전환되었습니다.';

  @override
  String get protectHiddenVolumeToggleTitle => '숨김 볼륨 보호';

  @override
  String get protectHiddenVolumeToggleSubtitle => '외부 볼륨에 쓰기로 인한 손상 방지';

  @override
  String get protectHiddenVolumeCredentialsRequired =>
      '숨김 볼륨을 보호하려면 숨김 볼륨의 비밀번호 또는 키파일이 필요합니다';

  @override
  String deleteItemsTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개를 삭제할까요?',
    );
    return '$_temp0';
  }

  @override
  String get deleteFoldersWarning => '선택한 폴더의 모든 내용을 포함하여 이 항목들이 영구적으로 삭제됩니다.';

  @override
  String get deleteFilesWarning => '이 항목들은 암호화된 볼륨에서 영구적으로 삭제됩니다.';

  @override
  String get delete => '삭제';

  @override
  String get remove => '제거';

  @override
  String get create => '만들기';

  @override
  String get rename => '이름 변경';

  @override
  String renameMultipleTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개의 이름 변경',
    );
    return '$_temp0';
  }

  @override
  String get newFolderTitle => '새 폴더';

  @override
  String get newTextFileTitle => '새 텍스트 파일';

  @override
  String get folderNameHint => '폴더 이름';

  @override
  String get filenameHint => '파일이름.txt';

  @override
  String get newNameHint => '새 이름';

  @override
  String get baseNameHint => '기본 이름';

  @override
  String couldntCreateItem(String name) {
    return '\"$name\"을(를) 만들 수 없습니다 — 컨테이너가 계속 마운트되어 있는지 확인하세요';
  }

  @override
  String couldntRenameSingle(String name) {
    return '\"$name\"의 이름을 변경할 수 없습니다 — 같은 이름의 항목이 이미 있을 수 있습니다';
  }

  @override
  String couldntRenameMultiWithReason(num count, String reason) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개의 이름을 변경할 수 없습니다: $reason',
    );
    return '$_temp0';
  }

  @override
  String couldntRenameMultiNoReason(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개의 이름을 변경할 수 없습니다',
    );
    return '$_temp0';
  }

  @override
  String get hiddenVolumeErrorInvalidSize => '0보다 큰 유효한 숨김 크기를 입력하세요';

  @override
  String get hiddenVolumeErrorTooLargeVsOuter => '숨김 볼륨 크기는 외부 볼륨 크기보다 작아야 합니다';

  @override
  String get hiddenVolumeErrorTooLargeForContainer =>
      '숨김 볼륨 크기가 이 컨테이너 크기에 비해 너무 큽니다';

  @override
  String get hiddenVolumeErrorCredentialsRequired =>
      '숨김 볼륨을 만들려면 숨김 비밀번호 또는 키파일이 필요합니다';

  @override
  String get hiddenVolumeErrorCredentialsMustDiffer =>
      '숨김 볼륨 자격 증명(비밀번호, PIM, 키파일)은 외부 볼륨 자격 증명과 동일할 수 없습니다.';

  @override
  String get vaultItemTypePassword => '비밀번호';

  @override
  String get vaultItemTypePaymentCard => '결제 카드';

  @override
  String get vaultItemTypeIdentity => '신분증';

  @override
  String get vaultItemTypeSecureNote => '보안 메모';

  @override
  String get vaultItemTypeBankAccount => '은행 계좌';

  @override
  String get vaultItemTypeSoftwareLicense => '소프트웨어 라이선스';

  @override
  String get fieldUsernameEmail => '사용자 이름 / 이메일';

  @override
  String get fieldPassword => '비밀번호';

  @override
  String get fieldWebsiteUrl => '웹사이트 URL';

  @override
  String get fieldTotpSecret => 'TOTP 비밀 키 (2FA)';

  @override
  String get fieldNotes => '메모';

  @override
  String get fieldCardholderName => '카드 소유자 이름';

  @override
  String get fieldCardNumber => '카드 번호';

  @override
  String get fieldExpiryMMYY => '유효 기간 (MM/YY)';

  @override
  String get fieldCvvCvc => 'CVV / CVC';

  @override
  String get fieldPin => 'PIN';

  @override
  String get fieldIssuingBank => '발급 은행';

  @override
  String get fieldFullName => '성명';

  @override
  String get fieldDateOfBirth => '생년월일';

  @override
  String get fieldNationality => '국적';

  @override
  String get fieldPassportNumber => '여권 번호';

  @override
  String get fieldPassportExpiry => '여권 만료일';

  @override
  String get fieldNationalIdSsn => '주민등록번호 / 국민 ID';

  @override
  String get fieldDriversLicense => '운전면허증';

  @override
  String get fieldAddress => '주소';

  @override
  String get fieldPhone => '전화번호';

  @override
  String get fieldEmail => '이메일';

  @override
  String get fieldNote => '메모';

  @override
  String get fieldBankName => '은행명';

  @override
  String get fieldAccountHolder => '예금주';

  @override
  String get fieldAccountNumber => '계좌번호';

  @override
  String get fieldRoutingSortCode => '은행 코드 / 지점 코드';

  @override
  String get fieldIban => 'IBAN';

  @override
  String get fieldSwiftBic => 'SWIFT / BIC';

  @override
  String get fieldAccountType => '계좌 유형';

  @override
  String get fieldProductName => '제품명';

  @override
  String get fieldLicenseKey => '라이선스 키';

  @override
  String get fieldRegisteredTo => '등록 대상';

  @override
  String get fieldPurchaseDate => '구매일';

  @override
  String get fieldExpiryRenewalDate => '만료일 / 갱신일';

  @override
  String get fieldDownloadUrl => '다운로드 URL';

  @override
  String get fieldRegistrationEmail => '등록 이메일';

  @override
  String get titleRequired => '제목은 필수입니다';

  @override
  String newTypeTitle(String typeLabel) {
    return '새 $typeLabel';
  }

  @override
  String editItemTitle(String title) {
    return '$title 편집';
  }

  @override
  String get save => '저장';

  @override
  String typeNameHint(String typeLabel) {
    return '$typeLabel 이름';
  }

  @override
  String get titleSectionLabel => '제목';

  @override
  String get fieldsSectionLabel => '필드';

  @override
  String get encryptedStorageHint => '모든 필드는 컨테이너 내부에 암호화되어 저장됩니다.';

  @override
  String copiedSuffix(String fieldLabel) {
    return '$fieldLabel 복사됨';
  }

  @override
  String get copy => '복사';

  @override
  String get failedToSaveCheckMounted =>
      '저장하지 못했습니다 — 컨테이너가 계속 마운트되어 있는지 확인하세요';

  @override
  String get discardChangesTitle => '변경 사항을 취소할까요?';

  @override
  String get discardChangesMessage => '저장하지 않은 변경 사항이 사라집니다.';

  @override
  String get discard => '취소';

  @override
  String get keepEditing => '계속 편집';

  @override
  String get deleteItemTitle => '항목을 삭제할까요?';

  @override
  String deleteItemMessage(String title) {
    return '\"$title\"이(가) 볼트에서 영구적으로 삭제됩니다.';
  }

  @override
  String get removeFromBookmarks => '북마크에서 제거';

  @override
  String get addToBookmarks => '북마크에 추가';

  @override
  String get edit => '편집';

  @override
  String labelCopiedToClipboard(String label) {
    return '$label이(가) 클립보드에 복사되었습니다';
  }

  @override
  String get noFieldsFilledIn => '입력된 필드가 없습니다.\n편집을 눌러 세부 정보를 추가하세요.';

  @override
  String get sectionLabelDetails => '세부 정보';

  @override
  String get sectionLabelInfo => '정보';

  @override
  String get metaLabelType => '유형';

  @override
  String get metaLabelCreated => '생성일';

  @override
  String get metaLabelModified => '수정일';

  @override
  String copyFieldTooltip(String fieldLabel) {
    return '$fieldLabel 복사';
  }

  @override
  String get readOnlyCantAddItemsTooltip => '읽기 전용 — 항목을 추가할 수 없습니다';

  @override
  String get extractArchive => '압축 풀기';

  @override
  String get verbArchive => '압축';

  @override
  String get verbExtract => '압축 풀기';

  @override
  String get verbArchived => '압축됨';

  @override
  String get verbExtracted => '압축 풀림';

  @override
  String get verbArchiving => '압축 중';

  @override
  String get verbExtracting => '압축 푸는 중';

  @override
  String get fileOpExtractingArchive => '압축 푸는 중…';

  @override
  String fileOpExtractingArchiveName(String name) {
    return '$name 압축 푸는 중…';
  }

  @override
  String fileOpArchivingBytes(String bytes) {
    return '압축 중… ($bytes)';
  }

  @override
  String get newItemTooltip => '새 항목';

  @override
  String get camera => '카메라';

  @override
  String get importFiles => '파일 가져오기';

  @override
  String get importFolder => '폴더 가져오기';

  @override
  String get secureItem => '보안 항목';

  @override
  String get appNameVaultExplorer => 'Vault Explorer';

  @override
  String get appNameZipExplorer => 'Archive Explorer';

  @override
  String get archiveExplorerPermissionTitle => '저장소 접근 권한 필요';

  @override
  String get archiveExplorerPermissionMessage =>
      '다운로드 폴더의 .zip 압축 파일을 찾아보고 압축을 풀려면 파일 접근을 허용하세요.';

  @override
  String get archiveExplorerGrantAccess => '접근 허용';

  @override
  String get archiveExplorerEmptyTitle => '압축 파일을 찾을 수 없음';

  @override
  String get archiveExplorerEmptyMessage => '다운로드한 zip 파일이 여기에 표시됩니다.';

  @override
  String get archiveExplorerRefreshTooltip => '새로고침';

  @override
  String archiveExplorerEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개',
    );
    return '$_temp0';
  }

  @override
  String get archiveExplorerExtractAll => '모두 압축 풀기';

  @override
  String get archiveExplorerExtracting => '압축 푸는 중…';

  @override
  String archiveExplorerExtractSuccess(int count, String name) {
    return '$count개 파일을 Download/Extracted/$name에 압축 풀었습니다';
  }

  @override
  String get archiveExplorerExtractFailed => '해당 압축 파일을 풀 수 없습니다.';

  @override
  String get archiveExplorerOpenFailed => '해당 압축 파일을 열 수 없습니다.';

  @override
  String get archiveExplorerOpenArchive => '압축 파일 열기…';

  @override
  String get archiveExplorerUnresolvedPath =>
      '해당 파일에 직접 접근할 수 없습니다. 대신 다운로드에서 선택해 보세요.';

  @override
  String get archiveExplorerExtractTo => '다음 위치로 압축 풀기…';

  @override
  String get archiveExplorerPreview => '미리보기';

  @override
  String get archiveExplorerChoosingDestination => '대상 위치 선택 중…';

  @override
  String get archiveExplorerNoDestinationChosen => '대상 위치가 선택되지 않았습니다.';

  @override
  String archiveExplorerExtractSuccessTo(int count, String path) {
    return '$count개 파일을 $path에 압축 풀었습니다';
  }

  @override
  String get archiveBrowserEmptyTitle => '빈 폴더';

  @override
  String get archiveBrowserEmptyMessage => '이 폴더에는 파일이 없습니다.';

  @override
  String get archiveBrowserRoot => '압축 파일';

  @override
  String get archiveBrowserOpenFileFailed => '해당 파일을 열 수 없습니다.';

  @override
  String get fileAssocInAppTextEditor => '앱 내장 텍스트 편집기';

  @override
  String get fileAssocInAppMediaViewer => '앱 내장 미디어 뷰어';

  @override
  String fileAssocAppPrefix(String name) {
    return '앱: $name';
  }

  @override
  String get fileAssocExternalApp => '외부 앱';

  @override
  String get appSettingsTitle => '앱 설정';

  @override
  String get sectionSecurityPrivacy => '보안 및 개인정보 보호';

  @override
  String get sectionAppearanceInterface => '화면 및 인터페이스';

  @override
  String get sectionVaultFileHandling => '볼트 및 파일 처리';

  @override
  String get masterPasswordTitle => '마스터 비밀번호';

  @override
  String get masterPasswordActiveSubtitle => '활성화됨 — 탭하여 제거';

  @override
  String get masterPasswordInactiveSubtitle => '앱을 열 때 비밀번호 요구';

  @override
  String get newPasswordLabel => '새 비밀번호';

  @override
  String get masterPasswordFieldLabel => '마스터 비밀번호';

  @override
  String get confirmPasswordLabel => '비밀번호 확인';

  @override
  String get update => '업데이트';

  @override
  String get setPassword => '비밀번호 설정';

  @override
  String get biometricUnlockTitle => '생체 인식 잠금 해제';

  @override
  String get biometricUnlockSubtitle => '인증하여 컨테이너를 안전하게 마운트하세요';

  @override
  String get changeMasterPasswordTitle => '마스터 비밀번호 변경';

  @override
  String get changeMasterPasswordSubtitle => '마스터 비밀번호 자격 증명 업데이트';

  @override
  String get autoLockContainersTitle => '컨테이너 자동 잠금';

  @override
  String get autoLockContainersSubtitle => '비활성 상태가 지속되면 열려 있는 볼트를 자동으로 잠급니다';

  @override
  String get autoLockTimeoutLabel => '자동 잠금 시간';

  @override
  String get immediately => '즉시';

  @override
  String nMinutes(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count분',
    );
    return '$_temp0';
  }

  @override
  String get blockScreenshotsTitle => '스크린샷 차단';

  @override
  String get blockScreenshotsSubtitle => '스크린샷을 방지하고 최근 앱 미리보기를 숨깁니다';

  @override
  String get keepVaultsRunningInBackgroundTitle => '백그라운드에서 볼트 유지';

  @override
  String get keepVaultsRunningInBackgroundSubtitle =>
      '알림을 표시하고 앱을 나간 후에도 열려 있는 볼트를 계속 사용할 수 있게 합니다. 볼트 키는 잠글 때까지 메모리에 남아 있습니다.';

  @override
  String get notificationPermissionDeniedMessage =>
      '알림 권한이 거부되었습니다. 볼트는 계속 열려 있지만, 지속 알림은 표시되지 않습니다.';

  @override
  String get discreteModeTitle => '마스크 모드';

  @override
  String get discreteModeActiveSubtitle =>
      '활성화됨 — 앱이 현재 \"Archive Explorer\"로 표시됩니다';

  @override
  String get discreteModeInactiveSubtitle => '홈 화면에서 이 앱을 zip 압축 파일 탐색기로 위장합니다';

  @override
  String get enableDiscreteModeTitle => '마스크 모드를 활성화할까요?';

  @override
  String get disableDiscreteModeTitle => '마스크 모드를 비활성화할까요?';

  @override
  String get enableDiscreteModeMessage =>
      '홈 화면의 앱 아이콘과 이름이 \"Archive Explorer\"로 변경됩니다. zip 압축 파일 탐색기 겸 압축 해제 도구로 작동합니다.\n\n볼트에 접근하려면 Archive Explorer를 열고 제목을 2초간 길게 누르세요.';

  @override
  String get disableDiscreteModeMessage =>
      '홈 화면의 앱 아이콘과 이름이 다시 \"Vault Explorer\"로 돌아갑니다.';

  @override
  String get enable => '활성화';

  @override
  String get disable => '비활성화';

  @override
  String get discreteModeEnabledSnack =>
      '마스크 모드가 활성화되었습니다. 앱이 종료됩니다 — 새 런처 아이콘에서 다시 여세요.';

  @override
  String get discreteModeDisabledSnack =>
      '마스크 모드가 비활성화되었습니다. 앱이 종료됩니다 — 새 런처 아이콘에서 다시 여세요.';

  @override
  String get failedToChangeDiscreteMode => '마스크 모드 변경에 실패했습니다';

  @override
  String get cacheDerivedKeysTitle => '파생 키를 기본적으로 캐시';

  @override
  String get cacheDerivedKeysSubtitle => '더 빠른 잠금 해제를 위해 파생된 키 자료를 키스토어에 저장합니다';

  @override
  String get appThemeLabel => '앱 테마';

  @override
  String get systemDefault => '시스템 기본값';

  @override
  String get lightTheme => '라이트 테마';

  @override
  String get darkTheme => '다크 테마';

  @override
  String get useMaterialYouTitle => 'Material You 사용';

  @override
  String get useMaterialYouSubtitle => '앱 색상을 배경화면에 맞춥니다 (Android 12 이상)';

  @override
  String get pureBlackThemeTitle => '순수한 검정색 (OLED)';

  @override
  String get pureBlackThemeSubtitle =>
      '배터리 소모를 줄이고 OLED 화면의 반사광을 줄이기 위한 진한 검은색 배경 (다크 테마만 사용 가능)';

  @override
  String get sortContainersByLabel => '컨테이너 정렬 기준';

  @override
  String get swapCardSwipeActionsTitle => '카드 스와이프 동작 바꾸기';

  @override
  String get swapCardSwipeActionsSubtitle =>
      '카드를 스와이프할 때 왼쪽에 편집, 오른쪽에 제거를 표시합니다';

  @override
  String get swipeGestureHintTitle => '스와이프 동작 안내';

  @override
  String get swipeGestureHintSubtitle => '첫 번째 컨테이너에서 카드 미리보기 애니메이션을 표시합니다';

  @override
  String get autoOpenOnUnlockTitle => '잠금 해제 시 자동으로 열기';

  @override
  String get autoOpenOnUnlockActiveSubtitle => '볼트 잠금 해제 후 자동으로 엽니다';

  @override
  String get autoOpenOnUnlockInactiveSubtitle => '볼트만 잠금 해제하고 대시보드에 머무릅니다';

  @override
  String get enableJsHtmlTitle => 'HTML 뷰어에서 자바스크립트 활성화';

  @override
  String get jsEnabledSubtitle => '로컬 HTML 파일에 자바스크립트가 활성화되어 있습니다';

  @override
  String get jsDisabledSubtitle => '로컬 HTML 파일에 자바스크립트가 비활성화되어 있습니다';

  @override
  String get fastStorageAccessTitle => '빠른 저장소 접근';

  @override
  String get fastStorageAccessGrantedSubtitle => '모든 파일 접근 권한이 부여됨 (최대 속도)';

  @override
  String get fastStorageAccessNotGrantedSubtitle =>
      '최적의 속도를 위해 시스템 설정에서 모든 파일 접근 권한을 부여하세요';

  @override
  String get enableFastStorageAccessTitle => '빠른 저장소 접근 활성화';

  @override
  String get enableFastStorageAccessMessage =>
      '\"모든 파일 접근\" 권한을 부여하면 Vault Explorer가 POSIX 파일 작업을 직접 수행할 수 있어, 폴더 볼트 성능이 최대 1000배 향상됩니다.';

  @override
  String get disableStorageAccessTitle => '저장소 접근 비활성화';

  @override
  String get disableStorageAccessMessage =>
      'Android에서는 시스템 설정에서 \"모든 파일 접근\"을 꺼야 합니다. 설정을 열어 끄시겠습니까?';

  @override
  String get enableStoragePermissionLegacyTitle => '저장소 접근 허용';

  @override
  String get enableStoragePermissionLegacyMessage =>
      'Vault Explorer는 폴더 볼트 성능을 높이기 위해 직접 파일 작업을 수행하려면 저장소 권한이 필요합니다. 이제 Android에서 확인을 요청합니다.';

  @override
  String get disableStoragePermissionLegacyMessage =>
      'Android에서는 시스템 설정에서 저장소 권한을 꺼야 합니다. 설정을 열어 끄시겠습니까?';

  @override
  String get openSettings => '설정 열기';

  @override
  String get useThisPasswordButton => '이 비밀번호 사용';

  @override
  String get quickPasswordGeneratorSheetTitle => '비밀번호 생성기';

  @override
  String get androidFileProviderTitle => 'Android 파일 제공자';

  @override
  String get androidFileProviderSubtitle => '새 컨테이너를 기본적으로 Android 파일 선택기에 노출';

  @override
  String get thumbnailCachingDefaultLabel => '썸네일 캐싱 (기본값)';

  @override
  String get thumbnailQualityDefaultLabel => '썸네일 품질 (기본값)';

  @override
  String get fileAssociationsHeader => '파일 연결';

  @override
  String get noFileAssociationsYet => '아직 저장된 파일 연결이 없습니다. 파일을 열 때 안내가 표시됩니다.';

  @override
  String get defaultActionsHeader => '비표준 파일을 열 때의 기본 동작:';

  @override
  String get removeAssociationTooltip => '연결 제거';

  @override
  String get sectionBackupRestore => '백업';

  @override
  String get exportSettingsTitle => '설정 내보내기';

  @override
  String get exportSettingsSubtitle => '앱 설정과 파일 관리자 레이아웃을 파일로 저장';

  @override
  String get importSettingsTitle => '설정 가져오기';

  @override
  String get importSettingsSubtitle => '파일에서 앱 설정과 파일 관리자 레이아웃을 복원';

  @override
  String get importSettingsConfirmTitle => '설정을 가져올까요?';

  @override
  String get importSettingsConfirmMessage =>
      '현재 앱 설정과 파일 관리자 레이아웃이 대체됩니다. 이 작업은 되돌릴 수 없습니다.';

  @override
  String get exportSettingsSuccessMessage => '설정을 내보냈습니다';

  @override
  String get importSettingsSuccessMessage => '설정을 가져왔습니다';

  @override
  String get exportSettingsErrorMessage => '설정을 내보낼 수 없습니다';

  @override
  String get importSettingsInvalidFileMessage => '해당 파일은 유효한 설정 내보내기 파일이 아닙니다';

  @override
  String get sectionDebug => '디버그';

  @override
  String get debugLoggingTitle => '디버그 로깅';

  @override
  String get debugLoggingSubtitle => '컨테이너 작업에 대한 자세한 진단 로그를 기록합니다';

  @override
  String get logcatTitle => 'Logcat';

  @override
  String get logcatSubtitle => '기기 로그 보기 및 저장';

  @override
  String logcatSavedMessage(String path) {
    return '로그가 $path에 저장되었습니다';
  }

  @override
  String get logcatSaveErrorMessage => '로그 저장에 실패했습니다';

  @override
  String get logcatCopiedMessage => '로그가 클립보드에 복사되었습니다';

  @override
  String get logcatUnavailableMessage => '이 기기에서는 Logcat을 사용할 수 없습니다';

  @override
  String get logcatEmptyMessage => '로그 줄을 기다리는 중…';

  @override
  String get logcatClearTooltip => '로그 지우기';

  @override
  String get logcatSaveTooltip => '로그 저장';

  @override
  String get logcatFilterAppOnly => '앱만';

  @override
  String get logcatFilterAll => '모든 로그';

  @override
  String get logcatSearchHint => '로그 검색…';

  @override
  String get logcatClearedMessage => '로그가 지워졌습니다';

  @override
  String get logcatCopyTooltip => '로그 복사';

  @override
  String get retryButton => '다시 시도';

  @override
  String get aboutAppTitle => 'VaultExplorer 정보';

  @override
  String versionInfoSubtitle(String version) {
    return '버전 $version · 오픈 소스 라이선스 및 세부정보';
  }

  @override
  String get failedToSaveSettings => '설정 저장에 실패했습니다';

  @override
  String get masterPasswordSetSnack => '마스터 비밀번호가 설정되었습니다';

  @override
  String get passwordCannotBeEmpty => '비밀번호는 비워 둘 수 없습니다';

  @override
  String get atLeast4CharsRequired => '4자 이상 필요합니다';

  @override
  String get passwordsDoNotMatch => '비밀번호가 일치하지 않습니다';

  @override
  String get failedToHashPassword => '비밀번호 해시 생성에 실패했습니다 — 다시 시도해 주세요';

  @override
  String get languageLabel => '언어';

  @override
  String get biometricNotAvailable => '이 기기에서는 생체 인식을 사용할 수 없습니다';

  @override
  String get unlockVaultExplorerReason => 'VaultExplorer 잠금 해제';

  @override
  String biometricErrorWithCode(String code) {
    return '생체 인식 오류: $code';
  }

  @override
  String tooManyFailedAttempts(num seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds초',
    );
    return '실패 횟수가 너무 많습니다. $_temp0 후 다시 시도하세요.';
  }

  @override
  String get enterMasterPasswordPrompt => '마스터 비밀번호를 입력하세요';

  @override
  String incorrectPasswordLockedFor(int seconds, num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '$attempts회',
    );
    return '비밀번호가 올바르지 않습니다. $_temp0 실패하여 $seconds초 동안 잠깁니다.';
  }

  @override
  String incorrectPasswordAttempts(num attempts) {
    String _temp0 = intl.Intl.pluralLogic(
      attempts,
      locale: localeName,
      other: '실패 $attempts회',
    );
    return '비밀번호가 올바르지 않습니다 ($_temp0).';
  }

  @override
  String get brandNameNoSpace => 'VaultExplorer';

  @override
  String get enterPasswordSubtitle => '계속하려면 마스터 비밀번호를 입력하세요';

  @override
  String get masterPasswordFieldLabelTitleCase => '마스터 비밀번호';

  @override
  String get unlock => '잠금 해제';

  @override
  String get useBiometric => '생체 인식 사용';

  @override
  String get connectAtLeast4Dots => '점을 4개 이상 연결하세요';

  @override
  String get patternsDontMatch => '패턴이 일치하지 않습니다 — 다시 시도하세요';

  @override
  String get drawUnlockPatternTitle => '잠금 해제 패턴 그리기';

  @override
  String get confirmPatternTitle => '패턴을 확인하세요';

  @override
  String get drawSamePatternAgain => '같은 패턴을 다시 그리세요';

  @override
  String get enterAtLeast4Digits => '4자리 이상의 숫자를 입력하세요';

  @override
  String get pinsDontMatch => 'PIN이 일치하지 않습니다 — 다시 시도하세요';

  @override
  String get createUnlockPinTitle => '잠금 해제 PIN을 만드세요';

  @override
  String get confirmPinTitle => 'PIN을 확인하세요';

  @override
  String get enterSamePinAgain => '같은 PIN을 다시 입력하세요';

  @override
  String get enterUnlockPinTitle => '잠금 해제 PIN 입력';

  @override
  String get wrongPinTryAgain => '잘못된 PIN — 다시 시도하세요';

  @override
  String get enterYourPinSequence => 'PIN을 입력하세요';

  @override
  String get enterPinToMount => '마운트하려면 PIN을 입력하세요';

  @override
  String get noPinConfiguredMessage => '설정된 PIN이 없습니다. 비밀번호를 수동으로 입력하세요.';

  @override
  String pinLockedForSeconds(int seconds) {
    return '실패 횟수가 너무 많습니다. $seconds초 동안 잠깁니다.';
  }

  @override
  String get initSecureCredsPinMessage =>
      '보안 자격 증명을 초기화하는 중입니다. PIN 접근을 승인하려면 한 번 수동으로 잠금을 해제하세요.';

  @override
  String get setPinButton => 'PIN 설정';

  @override
  String get changePinButton => 'PIN 변경';

  @override
  String get pinSetupRequiredBeforeSaving => '저장하기 전에 PIN을 설정하세요.';

  @override
  String get pinSetupRequiredAboveBeforeSaving => '저장하기 전에 위에서 PIN을 설정하세요.';

  @override
  String get verifyPinTitle => 'PIN 확인';

  @override
  String get incorrectPinError => 'PIN이 올바르지 않습니다';

  @override
  String removedFromListSnack(String name) {
    return '\"$name\"을(를) 목록에서 제거했습니다';
  }

  @override
  String get clearRecentHistoryTitle => '최근 기록을 지울까요?';

  @override
  String get clearRecentHistoryMessage =>
      '목록에서 모든 최근 문서가 제거됩니다. 기기의 실제 파일은 영향을 받지 않습니다.';

  @override
  String get clearAll => '모두 지우기';

  @override
  String get recentHistoryClearedSnack => '최근 기록이 지워졌습니다';

  @override
  String get moreOptionsTooltip => '더보기';

  @override
  String get clearHistoryMenuItem => '기록 지우기';

  @override
  String get openPdfFile => 'PDF 파일 열기';

  @override
  String get noDocumentsYetTitle => '아직 문서가 없습니다';

  @override
  String get openPdfToStartMessage => '기기에서 PDF를 열어 읽기를 시작하세요.';

  @override
  String get removeFromListMenuItem => '목록에서 제거';

  @override
  String get justNow => '방금 전';

  @override
  String minutesAgo(int count) {
    return '$count분 전';
  }

  @override
  String hoursAgo(int count) {
    return '$count시간 전';
  }

  @override
  String daysAgo(int count) {
    return '$count일 전';
  }

  @override
  String get usbDriveDisconnectedLocked => 'USB 드라이브 연결 끊김 — 컨테이너가 잠겼습니다';

  @override
  String get containerAlreadyMounted => '이 컨테이너는 이미 마운트되어 있습니다.';

  @override
  String get noVaultFolderFormatDetected =>
      '해당 폴더에서 masterkey.cryptomator, gocryptfs.conf, cryfs.config 파일을 찾을 수 없습니다.';

  @override
  String get savedContainerSettingsNotFound => '이 컨테이너의 저장된 설정을 찾을 수 없습니다.';

  @override
  String couldNotUpdateContainerLocation(String error) {
    return '컨테이너 위치를 업데이트할 수 없습니다: $error';
  }

  @override
  String filePickerFailed(String error) {
    return '파일 선택기 실패: $error';
  }

  @override
  String get selectContainerFirst => '먼저 컨테이너를 선택하세요';

  @override
  String get passwordOrKeyfilesRequired => '비밀번호 또는 키파일이 필요합니다';

  @override
  String get slowPerformanceWarningTitle => '느린 성능 경고';

  @override
  String get slowPerformanceWarningMessage =>
      '빠른 저장소 접근이 현재 비활성화되어 있습니다.\n\nCryFS는 파일을 수천 개의 작은 블록으로 나누어 저장합니다. Android SAF를 통해 비어 있지 않은 CryFS 볼트를 열면 매우 느려집니다.\n\n빠른 속도를 위해 설정을 열어 \"모든 파일 접근\"을 허용하시겠습니까?';

  @override
  String get unlockAnyway => '그래도 잠금 해제';

  @override
  String get defaultVaultName => '볼트';

  @override
  String get defaultContainerName => '컨테이너';

  @override
  String get incorrectPasswordOrInvalidVault => '비밀번호가 잘못되었거나 유효하지 않은 볼트입니다';

  @override
  String get incorrectPasswordOrInvalidContainer =>
      '비밀번호가 잘못되었거나 유효하지 않은 컨테이너입니다';

  @override
  String get genericUnknownError => '알 수 없는 오류';

  @override
  String get decryptingLabel => '복호화 중…';

  @override
  String luksKeyslotProgress(int attempted, int total) {
    return '키 슬롯 $attempted/$total 시도 중…';
  }

  @override
  String get luksKeyslotProgressUnknown => '키 슬롯 시도 중…';

  @override
  String bitlockerCredentialProgress(int attempted, int total) {
    return '자격 증명 $attempted/$total 확인 중…';
  }

  @override
  String get bitlockerCredentialProgressUnknown => '자격 증명 확인 중…';

  @override
  String veracryptAlgoProgress(String algo, String slotName) {
    return '$algo($slotName) 시도 중…';
  }

  @override
  String get unlockContainerLabel => '컨테이너 잠금 해제';

  @override
  String get mountContainerTitle => '컨테이너 마운트';

  @override
  String get containerFileSegmentLabel => '컨테이너 파일';

  @override
  String get folderVaultSegmentLabel => '폴더 볼트';

  @override
  String formatContainerLabel(String format) {
    return '$format 컨테이너';
  }

  @override
  String formatVaultLabel(String format) {
    return '$format 볼트';
  }

  @override
  String formatDriveLabel(String format) {
    return '$format 드라이브';
  }

  @override
  String get encryptedContainerLabel => '암호화된 컨테이너';

  @override
  String get tapToSelectVaultFolder => '탭하여 볼트 폴더 선택…';

  @override
  String get tapToSelectContainerFile => '탭하여 컨테이너 파일 선택…';

  @override
  String get containerMissingTitle => '컨테이너 없음';

  @override
  String get filePathCouldNotBeResolved => '파일 경로를 확인할 수 없습니다';

  @override
  String get containerMissingExplanation =>
      '컨테이너 파일이 이동되었거나 삭제되었을 수 있으며, 저장소 연결이 끊어져 있을 수도 있습니다.';

  @override
  String get retryButtonLabel => '다시 시도';

  @override
  String get locateFileButtonLabel => '파일 찾기';

  @override
  String get authenticateToMountSubtitle => '인증하여 컨테이너를 안전하게 마운트하세요';

  @override
  String get usePasswordButtonLabel => '비밀번호 사용';

  @override
  String get authenticateButtonLabel => '인증';

  @override
  String get drawUnlockPatternCardTitle => '잠금 해제 패턴 그리기';

  @override
  String get wrongPatternTryAgain => '잘못된 패턴 — 다시 시도하세요';

  @override
  String get connectYourPatternSequence => '패턴 순서를 연결하세요';

  @override
  String get usePasswordInsteadButtonLabel => '대신 비밀번호 사용';

  @override
  String get passwordHintFolderVault => '볼트 비밀번호 입력';

  @override
  String get passwordHintBitlocker => '비밀번호 또는 복구 키 입력';

  @override
  String get passwordHintContainer => '컨테이너 비밀번호 입력';

  @override
  String get usingSavedPasswordTooltip => '저장된 비밀번호 사용 중';

  @override
  String get luksKeyfileReplacesPasswordNote =>
      'LUKS 컨테이너에서는 키파일이 비밀번호를 대체합니다.';

  @override
  String get readOnlyModeUsbSubtitle => '이 드라이브 변경을 허용하지 않고 마운트합니다';

  @override
  String get readOnlyModeContainerSubtitle => '이 컨테이너 변경을 허용하지 않고 마운트합니다';

  @override
  String get rememberContainerLabel => '컨테이너 기억';

  @override
  String get rememberContainerSubtitle => '빠른 접근을 위해 대시보드에 고정';

  @override
  String get cancelUnlockButtonLabel => '잠금 해제 취소';

  @override
  String get biometricSubjectContainer => '컨테이너';

  @override
  String get biometricSubjectUsbDrive => 'USB 드라이브';

  @override
  String get usbNoSavedCredentialsMessage => '저장된 비밀번호를 찾을 수 없습니다. 수동으로 입력하세요.';

  @override
  String get decryptingDriveLabel => '드라이브 복호화 중…';

  @override
  String get usbDeviceAlreadyActiveMounted => '이 USB 장치는 이미 활성화되어 마운트되어 있습니다.';

  @override
  String reconnectUsbDriveTitle(String label) {
    return '\"$label\" 다시 연결';
  }

  @override
  String get unlockUsbDriveTitle => 'USB 드라이브 잠금 해제';

  @override
  String get noUsbStorageDetectedTitle => 'USB 저장소가 감지되지 않음';

  @override
  String authenticateToUnlockPrompt(String subject) {
    return '$subject 잠금 해제를 위해 인증하세요';
  }

  @override
  String get noPatternConfiguredMessage => '설정된 패턴이 없습니다. 비밀번호를 수동으로 입력하세요.';

  @override
  String patternLockedForSeconds(int seconds) {
    return '실패 횟수가 너무 많습니다. $seconds초 동안 잠깁니다.';
  }

  @override
  String get initSecureCredsBiometricMessage =>
      '보안 자격 증명을 초기화하는 중입니다. 생체 인식 접근을 승인하려면 한 번 수동으로 잠금을 해제하세요.';

  @override
  String get initSecureCredsPatternMessage =>
      '보안 자격 증명을 초기화하는 중입니다. 패턴 접근을 승인하려면 한 번 수동으로 잠금을 해제하세요.';

  @override
  String get mountExistingContainerTitle => '기존 컨테이너 마운트';

  @override
  String get mountExistingContainerSubtitle => '이미 가지고 있는 파일 컨테이너의 잠금을 해제합니다';

  @override
  String get mountSplitContainerTitle => '분할 컨테이너 마운트';

  @override
  String get mountSplitContainerSubtitle => '먼저 결합하지 않고 분할 컨테이너를 직접 잠금 해제합니다';

  @override
  String get mountUsbDriveTitle => 'USB 드라이브 마운트';

  @override
  String get mountUsbDriveSubtitle => 'OTG 플래시 드라이브의 컨테이너 잠금을 해제합니다';

  @override
  String get formatUsbDriveTitle => 'USB 드라이브 포맷';

  @override
  String get formatUsbDriveSubtitle => '드라이브를 지우고 새 암호화 컨테이너를 만듭니다';

  @override
  String get createNewContainerTitle => '새 컨테이너 만들기';

  @override
  String get createNewContainerSubtitle => '완전히 새로운 암호화 볼트를 포맷합니다';

  @override
  String get lockBeforeRemovingWarning => '제거하기 전에 컨테이너를 잠그세요.';

  @override
  String get settingsTooltip => '설정';

  @override
  String get addVaultFabLabel => '볼트 추가';

  @override
  String removedLabelUndo(String label) {
    return '\"$label\" 제거됨';
  }

  @override
  String get undo => '실행 취소';

  @override
  String get pdfViewerNoSourceProvided => 'PDF 소스가 제공되지 않았습니다.';

  @override
  String get pdfViewerFileEmpty => 'PDF 파일이 비어 있거나 읽을 수 없습니다.';

  @override
  String pdfViewerFailedToInspectSize(String error) {
    return 'PDF 파일 크기 확인에 실패했습니다: $error';
  }

  @override
  String get pdfViewerErrorLoadingTitle => 'PDF 로드 오류';

  @override
  String get pdfViewerNoDocumentLoaded => '로드된 PDF 문서가 없습니다.';

  @override
  String get add => '추가';

  @override
  String get reset => '재설정';

  @override
  String couldNotExpose(String name) {
    return '\"$name\"을(를) 노출할 수 없습니다.';
  }

  @override
  String nowAvailableToOtherApps(String name) {
    return '\"$name\"이(가) 이제 다른 앱에서 사용할 수 있습니다.';
  }

  @override
  String couldNotUnmount(String name) {
    return '\"$name\"을(를) 마운트 해제할 수 없습니다.';
  }

  @override
  String pinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개 고정됨',
    );
    return '$_temp0';
  }

  @override
  String unpinnedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개 고정 해제됨',
    );
    return '$_temp0';
  }

  @override
  String get readOnlyThumbnailWarning =>
      '읽기 전용 마운트 — 썸네일이 표시되지만 이번 세션에서는 컨테이너 내부에 저장되지 않습니다.';

  @override
  String failedLoadingFolder(String type) {
    return '폴더 로드 실패: $type';
  }

  @override
  String failedToReadArchive(String type) {
    return '압축 파일 읽기 실패: $type';
  }

  @override
  String archiveFormatNotSupported(String ext) {
    return '.$ext 압축 형식은 아직 지원되지 않습니다';
  }

  @override
  String get archivePasswordPromptTitle => '비밀번호로 보호됨';

  @override
  String get archivePasswordPromptMessage =>
      '이 압축 파일은 비밀번호로 보호되어 있습니다. 내용을 보려면 비밀번호를 입력하세요.';

  @override
  String get archiveSolidWarning =>
      '솔리드 압축 파일입니다 — 특히 끝부분의 파일을 열 때 속도가 느려질 수 있습니다.';

  @override
  String get failedToReadFileFromArchive => '압축 파일에서 파일을 읽지 못했습니다';

  @override
  String failedToExtractFile(String type) {
    return '파일 압축 풀기 실패: $type';
  }

  @override
  String get failedToReadSecureItem => '보안 항목 읽기 실패';

  @override
  String get openFileDialogTitle => '파일 열기';

  @override
  String chooseHowToOpen(String name) {
    return '\"$name\"을(를) 여는 방법을 선택하세요:';
  }

  @override
  String get playVideoAudioViewImageInApp => '앱 내에서 동영상/오디오 재생 또는 이미지 보기';

  @override
  String get viewEditTextMarkdownCode => '텍스트, 마크다운, 코드 보기/편집';

  @override
  String get sendFileToThirdPartyApp => '파일을 타사 앱으로 전송';

  @override
  String get openAsEllipsis => '다른 형식으로 열기…';

  @override
  String get chooseFileTypeToOpenAs => '열 파일 형식을 선택하세요';

  @override
  String alwaysRememberChoiceExt(String ext) {
    return '.$ext 파일에 대해 항상 선택 항목 기억';
  }

  @override
  String get alwaysRememberChoiceNoExt => '확장자 없는 파일에 대해 항상 선택 항목 기억';

  @override
  String get openAsDialogTitle => '다른 형식으로 열기';

  @override
  String get mimeTypeText => '텍스트';

  @override
  String get mimeTypeImage => '이미지';

  @override
  String get mimeTypeVideo => '동영상';

  @override
  String get mimeTypeAudio => '오디오';

  @override
  String get mimeTypeArchive => '압축 파일';

  @override
  String get mimeTypeOther => '기타';

  @override
  String get scanningSubfoldersForMedia => '하위 폴더에서 미디어를 검색하는 중…';

  @override
  String get noMediaFilesFoundRecursive => '이 폴더 또는 하위 폴더에서 미디어 파일을 찾을 수 없습니다';

  @override
  String failedToScanSubfolders(String error) {
    return '하위 폴더 검색 실패: $error';
  }

  @override
  String scanningSubfoldersForMediaProgress(int count) {
    return '하위 폴더에서 미디어 검색 중… $count개 확인함';
  }

  @override
  String get mediaScanCancelled => '미디어 검색이 취소되었습니다';

  @override
  String get mediaScanLimitReached => '많은 폴더를 확인한 후 검색을 중단했습니다. 미디어를 찾지 못했습니다.';

  @override
  String get noAppFoundForFileType => '이 파일 형식을 처리할 앱을 찾을 수 없습니다';

  @override
  String couldNotOpenFile(String name) {
    return '\"$name\"을(를) 열 수 없습니다';
  }

  @override
  String get readOnlyCantMove =>
      '이 컨테이너는 읽기 전용으로 마운트되어 있습니다 — 여기서 항목을 이동할 수 없습니다.';

  @override
  String get readOnlyCantPaste =>
      '이 컨테이너는 읽기 전용으로 마운트되어 있습니다 — 여기에 항목을 붙여넣을 수 없습니다.';

  @override
  String get clipboardSourceInvalid => '클립보드 소스가 유효하지 않습니다';

  @override
  String get crossContainerPasteNotConfigured => '컨테이너 간 붙여넣기가 설정되어 있지 않습니다.';

  @override
  String get crossContainerPasteRequiresBothMounted =>
      '컨테이너 간 붙여넣기는 두 컨테이너가 모두 마운트된 상태여야 합니다.';

  @override
  String get readOnlyCantDelete =>
      '이 컨테이너는 읽기 전용으로 마운트되어 있습니다 — 항목을 삭제할 수 없습니다.';

  @override
  String deletedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개 삭제됨',
    );
    return '$_temp0';
  }

  @override
  String deletedWithFailures(int deleted, int failed) {
    return '$deleted개 삭제됨 · $failed개 실패';
  }

  @override
  String exportedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개 내보내기 완료',
    );
    return '$_temp0';
  }

  @override
  String get exportCancelledOrFailed => '내보내기가 취소되었거나 실패했습니다';

  @override
  String exportError(String type) {
    return '내보내기 오류: $type';
  }

  @override
  String get deleteOriginalTitle => '원본을 삭제할까요?';

  @override
  String get deleteOriginalFolderMessage =>
      '가져오기가 완료되었습니다. 기기에서 원본 폴더를 삭제하시겠습니까?';

  @override
  String get deleteOriginalFilesMessage =>
      '가져오기가 완료되었습니다. 기기에서 원본 파일을 삭제하시겠습니까?';

  @override
  String get keepOriginal => '원본 유지';

  @override
  String get deleteOriginalButton => '원본 삭제';

  @override
  String deletedOriginalCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '원본 항목 $count개 삭제됨',
    );
    return '$_temp0';
  }

  @override
  String get couldNotDeleteOriginals => '원본을 삭제할 수 없습니다';

  @override
  String get videoCapturedEncrypted => '동영상을 촬영하고 암호화했습니다';

  @override
  String get photoCapturedEncrypted => '사진을 촬영하고 암호화했습니다';

  @override
  String cameraCaptureFailed(String type) {
    return '카메라 촬영 실패: $type';
  }

  @override
  String extractAllFilesToFolder(String folder) {
    return '모든 파일을 \"$folder\" 폴더에 압축 풀까요?';
  }

  @override
  String get extract => '압축 풀기';

  @override
  String extractedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개 압축 풀기 완료',
    );
    return '$_temp0';
  }

  @override
  String failedToExtractGeneric(String type) {
    return '압축 풀기 실패: $type';
  }

  @override
  String get archiveSelectionAction => '압축';

  @override
  String get createArchiveTitle => '압축 파일 만들기';

  @override
  String get archiveNameHint => '압축파일.zip';

  @override
  String archivedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개 압축 완료',
    );
    return '$_temp0';
  }

  @override
  String failedToArchiveGeneric(String type) {
    return '압축 실패: $type';
  }

  @override
  String get createArchivePasswordHint => '선택적 비밀번호 (AES-256)';

  @override
  String get createArchivePasswordUnavailableForFormat =>
      '비밀번호 보호는 ZIP 및 7-Zip 형식에서만 사용할 수 있습니다';

  @override
  String get closeSearchTooltip => '검색 닫기';

  @override
  String get searchInThisFolderTooltip => '이 폴더에서 검색';

  @override
  String get playMediaHereTooltip => '여기서 미디어 재생';

  @override
  String get rootFolderLabel => '루트';

  @override
  String folderPickerFailed(String error) {
    return '폴더 선택기 실패: $error';
  }

  @override
  String get addAVaultTitle => '볼트 추가';

  @override
  String get selectEmptyDestinationFolderFirst => '먼저 빈 대상 폴더를 선택하세요';

  @override
  String get passwordRequired => '비밀번호가 필요합니다';

  @override
  String get vaultCreatedSuccessfully => '볼트가 성공적으로 생성되었습니다.';

  @override
  String get vaultCreationFailedEmptyFolder =>
      '볼트 생성에 실패했습니다 — 선택한 폴더가 비어 있는지 확인하세요.';

  @override
  String get unknownErrorOccurred => '알 수 없는 오류가 발생했습니다';

  @override
  String get containerNameRequired => '컨테이너 이름이 필요합니다';

  @override
  String get enterValidSizeGreaterThanZero => '0보다 큰 유효한 크기를 입력하세요';

  @override
  String get passwordOrKeyfileRequired => '비밀번호 또는 최소 1개의 키파일이 필요합니다';

  @override
  String get standardVolumePasswordsDoNotMatch => '표준 볼륨 비밀번호가 일치하지 않습니다';

  @override
  String get hiddenVolumePasswordsDoNotMatch => '숨김 볼륨 비밀번호가 일치하지 않습니다';

  @override
  String get containerFileCreatedSuccessfully => '컨테이너 파일이 성공적으로 생성되었습니다.';

  @override
  String get containerCreationCancelledOrFailed => '컨테이너 생성이 취소되었거나 실패했습니다.';

  @override
  String insufficientSpaceForContainer(String needed, String available) {
    return '대상 위치에 여유 공간이 부족합니다. 필요 용량: $needed, 사용 가능: $available뿐입니다.';
  }

  @override
  String get vaultKindContainerFile => '컨테이너 파일';

  @override
  String get vaultKindFolderVault => '폴더 볼트';

  @override
  String get formatFileSystemLabel => '파일 시스템 포맷';

  @override
  String get standardVolumeHeader => '표준 볼륨';

  @override
  String get containerFormatLabel => '컨테이너 형식';

  @override
  String get fileNameLabel => '파일 이름';

  @override
  String get containerSizeLabel => '컨테이너 크기';

  @override
  String get unitLabel => '단위';

  @override
  String get passwordFieldLabel => '비밀번호';

  @override
  String get confirmPasswordFieldLabelTitleCase => '비밀번호 확인';

  @override
  String get hiddenVolumeHeader => '숨김 볼륨';

  @override
  String get createHiddenVolumeToggleTitle => '숨김 볼륨 만들기';

  @override
  String get createInvisibleSecondaryVolume => '보이지 않는 보조 볼륨을 만듭니다';

  @override
  String get setOuterPasswordFirstToEnable => '활성화하려면 먼저 외부 비밀번호 또는 키파일을 설정하세요';

  @override
  String get hiddenPasswordLabel => '숨김 비밀번호';

  @override
  String get confirmHiddenPasswordLabel => '숨김 비밀번호 확인';

  @override
  String get hiddenSizeLabel => '숨김 크기';

  @override
  String get unitMbMegabytes => 'MB(메가바이트)';

  @override
  String get unitGbGigabytes => 'GB(기가바이트)';

  @override
  String get hiddenFileSystemLabel => '숨김 파일 시스템';

  @override
  String get vaultFormatLabel => '볼트 형식';

  @override
  String get gocryptfsCipherLabel => '콘텐츠 암호화 방식';

  @override
  String get cryfsCipherLabel => '콘텐츠 암호화 방식';

  @override
  String get cryfsBlockSizeLabel => '블록 크기';

  @override
  String get destinationFolderLabel => '대상 폴더';

  @override
  String get selectEmptyFolderLabel => '빈 폴더를 선택하세요';

  @override
  String get tapToChooseVaultLocation => '탭하여 볼트가 생성될 위치 선택…';

  @override
  String get folderVaultLimitationsNote =>
      '폴더 볼트는 키파일, PIM, 숨김 볼륨, VeraCrypt/LUKS 암호화 방식 선택을 지원하지 않습니다.';

  @override
  String get createVaultButton => '볼트 만들기';

  @override
  String get createContainerButton => '컨테이너 만들기';

  @override
  String get vaultCreationInProgressWait => '볼트를 만드는 중입니다. 잠시 기다려 주세요.';

  @override
  String get containerCreationInProgressWait => '컨테이너를 만드는 중입니다. 잠시 기다려 주세요.';

  @override
  String get createEncryptedVaultTitle => '암호화된 볼트 만들기';

  @override
  String get createEncryptedContainerTitle => '암호화된 컨테이너 만들기';

  @override
  String get unitMbShort => 'MB';

  @override
  String get unitGbShort => 'GB';

  @override
  String failedToListUsbDevices(String error) {
    return 'USB 장치 목록 가져오기 실패: $error';
  }

  @override
  String get usbPermissionDenied => 'USB 권한이 거부되었습니다';

  @override
  String get couldNotReadDriveCapacity =>
      '드라이브 용량을 읽을 수 없습니다 — 크기를 수동으로 입력하세요.';

  @override
  String get selectUsbDriveFirst => '먼저 USB 드라이브를 선택하세요';

  @override
  String eraseDeviceTitle(String name) {
    return '\"$name\"을(를) 지울까요?';
  }

  @override
  String get eraseDeviceMessage =>
      '이 USB 드라이브의 현재 모든 데이터가 영구적으로 지워지고 새 암호화 컨테이너로 대체됩니다. 이 작업은 되돌릴 수 없습니다.';

  @override
  String get eraseAndCreateButton => '지우고 만들기';

  @override
  String get usbPermissionRequiredToContinue => '계속하려면 USB 권한이 필요합니다';

  @override
  String get usbContainerCreatedSnack =>
      'USB 컨테이너가 생성되었습니다. 잠금을 해제하려면 \"USB 드라이브 마운트\"를 사용하세요.';

  @override
  String get usbContainerCreationFailed => 'USB 컨테이너 생성에 실패했습니다.';

  @override
  String get usbStandardVolumeSectionHeader => 'USB 드라이브 및 표준 볼륨';

  @override
  String get formattingErasesEverythingWarning =>
      '포맷하면 선택한 드라이브에 있는 모든 데이터가 지워집니다.';

  @override
  String get selectUsbDriveLabel => 'USB 드라이브 선택';

  @override
  String get noUsbStorageDetected => 'USB 저장소가 감지되지 않음';

  @override
  String get connectOtgDriveToFormat => '포맷하려면 OTG 드라이브를 연결하세요';

  @override
  String get refreshListButton => '목록 새로고침';

  @override
  String get readyToFormat => '포맷 준비 완료';

  @override
  String get permissionRequired => '권한 필요';

  @override
  String get readingDriveCapacity => '드라이브 용량을 읽는 중…';

  @override
  String get mustNotExceedDriveCapacity => '드라이브의 실제 용량을 초과할 수 없습니다.';

  @override
  String get quickFormatTitle => '빠른 포맷';

  @override
  String get quickFormatDescription =>
      '드라이브 0채우기를 건너뜁니다. 더 빠르지만 이전 데이터를 안전하게 지우지는 않습니다.';

  @override
  String get eraseAndCreateContainerButton => '지우고 컨테이너 만들기';

  @override
  String get usbContainerCreationInProgressWait =>
      '컨테이너를 만드는 중입니다. 잠시 기다려 주세요.';

  @override
  String get formatUsbDriveScreenTitle => 'USB 드라이브 포맷';

  @override
  String get playlistTransitionAnimationLabel => '재생 목록 전환 애니메이션';

  @override
  String get playlistTransitionSlideLabel => '슬라이드(기본값)';

  @override
  String get playlistTransitionFadeLabel => '페이드';

  @override
  String get playlistTransitionZoomLabel => '확대/축소';

  @override
  String get playlistTransitionDepthLabel => '깊이 스택';

  @override
  String get playlistTransitionCubeLabel => '3D 큐브';

  @override
  String get playlistTransitionFlipLabel => '3D 플립';

  @override
  String get unlockVaultTitle => '볼트 잠금 해제';

  @override
  String get openContainerTitle => '컨테이너 열기';

  @override
  String get selectContainerFileOrFolder => '파일 또는 폴더 선택';

  @override
  String get readOnlyModeLabel => '읽기 전용 모드';

  @override
  String get readOnlyModeSubtitle => '볼트에 대한 쓰기 또는 수정 작업을 방지합니다';

  @override
  String get selectUsbDeviceLabel => 'USB 장치 선택';

  @override
  String get noUsbDevicesFound => '호환되는 USB 저장 장치를 찾을 수 없습니다';

  @override
  String get containerConfigTitle => '볼트 구성';

  @override
  String get changePasswordTitle => '비밀번호 변경';

  @override
  String get confirmNewPasswordLabel => '새 비밀번호 확인';

  @override
  String get cameraCaptureTitle => '볼트 카메라';

  @override
  String get takingPhoto => '사진 촬영 중…';

  @override
  String get savingToVault => '볼트에 저장 중…';

  @override
  String get noVaultSelected => '선택된 볼트가 없습니다';

  @override
  String get mediaDiagnosticsTitle => '미디어 진단';

  @override
  String get advancedViewerSettingsTitle => '뷰어 설정';

  @override
  String get textEditorSaveConfirmTitle => '저장되지 않은 변경 사항';

  @override
  String get textEditorSaveConfirmMessage => '닫기 전에 변경 사항을 저장하시겠습니까?';

  @override
  String get saveAndClose => '저장 후 닫기';

  @override
  String get discardChanges => '변경 사항 취소';

  @override
  String selectionBarSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 항목 선택됨',
    );
    return '$_temp0';
  }

  @override
  String get selectAll => '모두 선택';

  @override
  String get deselectAll => '모두 선택 해제';

  @override
  String get sortOptionsTitle => '파일 정렬';

  @override
  String get layoutModeList => '목록 보기';

  @override
  String get layoutModeGrid => '그리드 보기';

  @override
  String get layoutModeMasonry => '매스너리';

  @override
  String get fileOperationsTitle => '파일 작업';

  @override
  String get conflictResolutionTitle => '파일 충돌';

  @override
  String get replaceExistingFile => '기존 파일 바꾸기';

  @override
  String get keepBothFiles => '둘 다 유지 (새 파일 이름 변경)';

  @override
  String get skipFile => '이 파일 건너뛰기';

  @override
  String get noVaultsFoundTitle => '볼트를 찾을 수 없음';

  @override
  String get noVaultsFoundSubtitle => '시작하려면 새 암호화 컨테이너를 만들거나 기존 볼트를 추가하세요.';

  @override
  String get addExistingVaultButton => '기존 볼트 추가';

  @override
  String get sortContainersModeManual => '수동 (드래그하여 순서 변경)';

  @override
  String get sortContainersModeUnlockStatus => '잠금 해제 상태 (해제된 항목 먼저)';

  @override
  String get sortContainersModeNameAZ => '이름 (A–Z)';

  @override
  String get sortContainersModeNameZA => '이름 (Z–A)';

  @override
  String get sortContainersModeNewest => '최신순';

  @override
  String get sortContainersModeOldest => '오래된순';

  @override
  String get thumbnailCacheAppCacheLabel => '앱 캐시';

  @override
  String get thumbnailCacheAppCacheDesc =>
      '앱 캐시에 암호화되어 저장됩니다. 빠르지만, 저장 공간이 부족하면 자동으로 지워집니다.';

  @override
  String get thumbnailCacheInContainerLabel => '컨테이너 내부';

  @override
  String get thumbnailCacheInContainerDesc =>
      '암호화된 컨테이너 내부에 저장됩니다. 컨테이너 자체로 보호되지만 쓰기 속도가 느립니다.';

  @override
  String get thumbnailCacheHiddenFolderLabel => '숨김 폴더';

  @override
  String get thumbnailCacheHiddenFolderDesc =>
      '루트에 있는 숨김 .thumbcache 폴더에 저장됩니다. 앱 캐시와 달리 자동으로 지워지지 않습니다.';

  @override
  String get thumbnailCacheDisabledLabel => '비활성화됨';

  @override
  String get thumbnailCacheDisabledDesc =>
      '디스크 캐시가 없습니다. 썸네일은 로드할 때마다 다시 생성됩니다.';

  @override
  String get unlockContainerTitle => '컨테이너 잠금 해제';

  @override
  String get containerFileSegment => '컨테이너 파일';

  @override
  String get folderVaultSegment => '폴더 볼트';

  @override
  String get enableButtonLabel => '활성화';

  @override
  String get retryButtonLabelShort => '다시 시도';

  @override
  String get locateFileButton => '파일 찾기';

  @override
  String get authenticateButton => '인증';

  @override
  String get cancelUnlockButton => '잠금 해제 취소';

  @override
  String tryingKeyslotProgress(int attempted, int total) {
    return '키 슬롯 $attempted/$total 시도 중…';
  }

  @override
  String get tryingKeyslotSingle => '키 슬롯 시도 중…';

  @override
  String verifyingCredentialProgress(int attempted, int total) {
    return '자격 증명 $attempted/$total 확인 중…';
  }

  @override
  String get verifyingCredentialSingle => '자격 증명 확인 중…';

  @override
  String tryingAlgoSlot(String algo, String slotName) {
    return '$algo($slotName) 시도 중…';
  }

  @override
  String get hiddenVolumeSlotName => '숨김 볼륨';

  @override
  String get standardVolumeSlotName => '표준 볼륨';

  @override
  String get containerMissingSubtitle => '파일 경로를 확인할 수 없습니다';

  @override
  String get containerMissingBody =>
      '컨테이너 파일이 이동되었거나 삭제되었을 수 있으며, 저장소 연결이 끊어져 있을 수도 있습니다.';

  @override
  String get connectPatternSequence => '패턴 순서를 연결하세요';

  @override
  String get passwordLabel => '비밀번호';

  @override
  String get enterVaultPasswordHint => '볼트 비밀번호 입력';

  @override
  String get enterBitlockerPasswordHint => '비밀번호 또는 복구 키 입력';

  @override
  String get enterContainerPasswordHint => '컨테이너 비밀번호 입력';

  @override
  String get readOnlyModeUsbSubtitleDrive => '이 드라이브 변경을 허용하지 않고 마운트합니다';

  @override
  String get rememberDriveLabel => '드라이브 기억';

  @override
  String get rememberDriveSubtitle => '빠른 접근을 위해 대시보드에 고정';

  @override
  String get unlockVaultButtonLabel => '볼트 잠금 해제';

  @override
  String get cryfsStorageAccessWarning =>
      'CryFS 볼트는 수천 개의 작은 블록 파일을 사용합니다. 빠른 저장소 접근이 없으면 성능이 크게 느려집니다.';

  @override
  String get folderVaultStorageAccessWarning =>
      '빠른 저장소 접근이 비활성화되어 있습니다. 폴더 볼트에서 파일을 열고 읽는 속도가 느려질 수 있습니다.';

  @override
  String get requestingPermission => '권한 요청 중…';

  @override
  String get unlockAndMountButton => '잠금 해제 및 마운트';

  @override
  String get unlockDriveButton => '드라이브 잠금 해제';

  @override
  String couldntFindDevice(String deviceName) {
    return '\"$deviceName\"을(를) 찾을 수 없습니다';
  }

  @override
  String get plugDriveBackInRetry =>
      '드라이브를 다시 연결하고 다시 시도를 탭하거나, 다른 이름으로 표시되면 아래에서 선택하세요.';

  @override
  String get retryConnectionButton => '연결 다시 시도';

  @override
  String get refreshDevicesButton => '장치 새로고침';

  @override
  String get connectOtgDriveToMount => '마운트하려면 OTG 플래시 드라이브를 연결하세요';

  @override
  String get alreadyActive => '이미 활성화됨';

  @override
  String get active => '활성';

  @override
  String get readyToUnlock => '잠금 해제 준비 완료';

  @override
  String get enterUsbPartitionPassword => 'USB 파티션 비밀번호 입력';

  @override
  String get biometricAuthenticationTitle => '생체 인식';

  @override
  String get biometricAuthUsbSubtitle => '이 USB 장치의 잠금을 해제하고 마운트하려면 인증하세요';

  @override
  String get connectPatternSequenceToMount => '마운트하려면 패턴 순서를 연결하세요';

  @override
  String get selectAllAction => '모두 선택';

  @override
  String get clearSelectionAction => '선택 해제';

  @override
  String get clearSelectionTooltip => '선택 해제';

  @override
  String get selectionOptionsTooltip => '선택 옵션';

  @override
  String get readOnlyContainerTooltip => '읽기 전용 컨테이너';

  @override
  String get copyAction => '복사';

  @override
  String get moveAction => '이동';

  @override
  String get renameAction => '이름 변경';

  @override
  String get exportToDeviceAction => '기기로 내보내기';

  @override
  String get openWithAppAction => '앱으로 열기';

  @override
  String get pinAction => '고정';

  @override
  String get pinSelectedAction => '선택 항목 고정';

  @override
  String get unpinAction => '고정 해제';

  @override
  String get unpinSelectedAction => '선택 항목 고정 해제';

  @override
  String get documentProviderSettingsMenu => '문서 제공자 설정';

  @override
  String get exposeAsDocumentProviderMenu => '문서 제공자로 노출';

  @override
  String get moreOptionsTooltipShort => '더보기';

  @override
  String get copyTooltip => '복사';

  @override
  String get searchInThisFolderHint => '이 폴더에서 검색…';

  @override
  String get clearTooltip => '지우기';

  @override
  String get backToDashboardTooltip => '대시보드로 돌아가기';

  @override
  String get cancelPasteButton => '붙여넣기 취소';

  @override
  String get cancelImportButton => '가져오기 취소';

  @override
  String get continueButton => '계속';

  @override
  String get skipButton => '건너뛰기';

  @override
  String get keepBothButton => '둘 다 유지';

  @override
  String get clearAllButton => '모두 지우기';

  @override
  String get autoMountWhenUnlocksTitle => '컨테이너 잠금 해제 시 자동 마운트';

  @override
  String get autoMountWhenUnlocksSubtitle => '다음에도 이 폴더를 자동으로 다시 노출';

  @override
  String get unmountButton => '마운트 해제';

  @override
  String get filtersMenuItem => '필터';

  @override
  String get settingsMenuItem => '설정';

  @override
  String get sortOptionsTooltip => '정렬 옵션';

  @override
  String get layoutOptionsTooltip => '레이아웃 옵션';

  @override
  String get lockContainerTooltip => '컨테이너 잠금';

  @override
  String get renameTooltip => '이름 변경';

  @override
  String get cancelUpdatingPasswordTooltip => '비밀번호 업데이트 취소';

  @override
  String get unlockSettingsButton => '잠금 해제 설정';

  @override
  String get updateSavedCredentialsButton => '저장된 자격 증명 업데이트';

  @override
  String get verifyCredentialsTitle => '자격 증명 확인';

  @override
  String get verifyButton => '확인';

  @override
  String get displayNameTitle => '표시 이름';

  @override
  String get containerNameHint => '컨테이너 이름';

  @override
  String get deleteFileDialogTitle => '파일을 삭제할까요?';

  @override
  String get deleteFilePermanentWarning => '이 작업은 영구적이며 되돌릴 수 없습니다.';

  @override
  String get unsavedChangesTitle => '저장되지 않은 변경 사항';

  @override
  String get unsavedChangesMessage => '저장되지 않은 변경 사항이 있습니다. 닫기 전에 저장하시겠습니까?';

  @override
  String get discardButton => '취소';

  @override
  String get decryptingFileContent => '파일 내용을 복호화하는 중...';

  @override
  String get cannotOpenFile => '파일을 열 수 없습니다';

  @override
  String get changesSavedSuccessfully => '변경 사항이 성공적으로 저장되었습니다';

  @override
  String saveFailedWithError(String error) {
    return '저장 실패: $error';
  }

  @override
  String linesCount(int count) {
    return '줄 수: $count';
  }

  @override
  String charsCount(int count) {
    return '글자 수: $count';
  }

  @override
  String get unsavedChangesLabel => '저장되지 않은 변경 사항';

  @override
  String get savedToVault => '볼트에 저장됨';

  @override
  String get saveChangesTooltip => '변경 사항 저장';

  @override
  String get textEditorDecryptFailedMessage => '볼트에서 파일을 복호화하지 못했습니다.';

  @override
  String get textEditorInvalidTextFileMessage => '이 파일은 유효한 텍스트 파일이 아닌 것 같습니다.';

  @override
  String get textEditorWriteBackFailedMessage => '볼트에 파일을 다시 쓰지 못했습니다.';

  @override
  String get backTooltip => '뒤로';

  @override
  String get forwardTooltip => '앞으로';

  @override
  String get reloadTooltip => '새로고침';

  @override
  String get optionsTooltip => '옵션';

  @override
  String get htmlViewerErrorTitle => '이 페이지를 표시할 수 없습니다';

  @override
  String get htmlViewerLoadFailedMessage => '파일 로드에 실패했습니다';

  @override
  String get enableJavaScriptDialogTitle => '자바스크립트를 활성화할까요?';

  @override
  String get enableJavaScriptDialogMessage =>
      '이 페이지는 자체 로컬 스크립트를 실행할 수 있게 됩니다. 여전히 네트워크 접근 권한은 없습니다 — 이 볼트의 어떤 것도 인터넷으로 전송되거나 수신될 수 없습니다.';

  @override
  String get disableJavaScriptMenu => '자바스크립트 비활성화';

  @override
  String get enableJavaScriptMenu => '자바스크립트 활성화';

  @override
  String get enterFullscreenMenu => '전체 화면으로 전환';

  @override
  String failedToOpenExternalApp(String error) {
    return '외부 앱에서 열기 실패: $error';
  }

  @override
  String get thisFolderMenu => '이 폴더';

  @override
  String get allInclSubfoldersMenu => '전체(하위 폴더 포함)';

  @override
  String get disableShuffleMenu => '셔플 비활성화';

  @override
  String get shufflePlaylistMenu => '재생 목록 셔플';

  @override
  String get playlistOptionsTooltip => '재생 목록 옵션';

  @override
  String get enablePlaylistTooltip => '재생 목록 활성화';

  @override
  String get moreActionsTooltip => '더 많은 작업';

  @override
  String get forcePortraitMenu => '세로 모드 강제 적용';

  @override
  String get forceLandscapeMenu => '가로 모드 강제 적용';

  @override
  String get autoRotateSensorMenu => '자동 회전(센서)';

  @override
  String get screenOrientationMenu => '화면 방향';

  @override
  String get playlistTransitionMenu => '재생 목록 전환';

  @override
  String get renameFileMenu => '파일 이름 변경';

  @override
  String get deleteFileMenu => '파일 삭제';

  @override
  String get thumbnailCarouselTooltip => '썸네일 캐러셀';

  @override
  String get advancedSettingsTooltip => '고급 설정';

  @override
  String get previousTooltip => '이전';

  @override
  String get nextTooltip => '다음';

  @override
  String get diagnosticsCopiedToClipboard => '진단 정보가 클립보드에 복사되었습니다';

  @override
  String get diagnosticsTitle => '진단';

  @override
  String get copyDiagnosticsTooltip => '진단 정보 복사';

  @override
  String get closeTooltip => '닫기';

  @override
  String get diagnosticsPlaybackSection => '재생';

  @override
  String get diagnosticsEngineSection => '엔진';

  @override
  String get diagnosticsStateLabel => '상태';

  @override
  String get diagnosticsResolutionLabel => '해상도';

  @override
  String get diagnosticsAspectRatioLabel => '화면 비율';

  @override
  String get diagnosticsPositionLabel => '재생 위치';

  @override
  String get diagnosticsDurationLabel => '길이';

  @override
  String get diagnosticsErrorLabel => '오류';

  @override
  String get diagnosticsPlayerLabel => '플레이어';

  @override
  String get diagnosticsDecodingLabel => '디코딩';

  @override
  String get diagnosticsExoPlayerValue => 'ExoPlayer(Android)';

  @override
  String get diagnosticsHardwareAcceleratedValue => '하드웨어 가속';

  @override
  String get diagnosticsUnknownValue => '알 수 없음';

  @override
  String get diagnosticsStateBuffering => '버퍼링 중';

  @override
  String get diagnosticsStatePlaying => '재생 중';

  @override
  String get diagnosticsStatePaused => '일시 중지됨';

  @override
  String get diagnosticsDurationUnavailable => '--:--';

  @override
  String get rotate90Label => '90° 회전';

  @override
  String get imageFitModeLabel => '이미지 맞춤 모드';

  @override
  String get slideshowDelayLabel => '슬라이드쇼 지연 시간';

  @override
  String get playbackSpeedLabel => '재생 속도';

  @override
  String get subtitlesLabel => '자막';

  @override
  String get imageSettingsTitle => '이미지 설정';

  @override
  String get playbackSettingsTitle => '재생 설정';

  @override
  String get imageFitContain => '전체 맞춤';

  @override
  String get imageFitWidth => '너비에 맞춤';

  @override
  String get imageFitHeight => '높이에 맞춤';

  @override
  String nSecondsDelay(int n) {
    return '$n초';
  }

  @override
  String playbackSpeedNormal(String speed) {
    return '$speed배(표준)';
  }

  @override
  String playbackSpeedValue(String speed) {
    return '$speed배';
  }

  @override
  String slideshowDelaySecondsValue(int seconds) {
    return '$seconds초';
  }

  @override
  String rotationDegreesValue(int degrees) {
    return '$degrees°';
  }

  @override
  String get settingsTooltipShort => '설정';

  @override
  String get sourceCodeTooltip => '소스 코드';

  @override
  String get donateTooltip => '기부';

  @override
  String get shareAppTooltip => '앱 공유';

  @override
  String get resetToDefaultsTooltip => '기본값으로 재설정';

  @override
  String get usbUnlockContainerTitle => 'USB 컨테이너 잠금 해제';

  @override
  String get usbMountContainerTitle => 'USB 드라이브 마운트';

  @override
  String get staticLabel => '정지';

  @override
  String get unmuteTooltip => '음소거 해제';

  @override
  String get muteTooltip => '음소거';

  @override
  String get playOnceDisabledTooltip => '한 번만 재생(자동 넘김 비활성화)';

  @override
  String get playAndAdvanceTooltip => '재생 후 다음으로 넘기기';

  @override
  String get loopCurrentVideoTooltip => '현재 동영상 반복 재생';

  @override
  String get clearThumbnailCacheDialogTitle => '썸네일 캐시를 지울까요?';

  @override
  String get clearThumbnailCacheDialogMessage =>
      '이 볼트의 캐시된 썸네일이 삭제됩니다. 다음에 미디어를 탐색할 때 다시 생성됩니다.';

  @override
  String get clearCacheButton => '캐시 지우기';

  @override
  String get appCacheClearedUnlockMessage =>
      '앱 캐시가 지워졌습니다. 내부 캐시를 지우려면 컨테이너의 잠금을 해제하세요.';

  @override
  String get allThumbnailCachesClearedMessage => '모든 썸네일 캐시가 성공적으로 지워졌습니다.';

  @override
  String get appCacheClearedContainerFailedMessage =>
      '앱 캐시는 지워졌지만 컨테이너 내부는 지우지 못했습니다.';

  @override
  String get failedToClearThumbnailCachesMessage => '썸네일 캐시를 지우지 못했습니다.';

  @override
  String get authenticateToModifySettingsPrompt => '설정을 변경하려면 인증하세요';

  @override
  String get usbVaultSettingsTitle => 'USB 볼트 설정';

  @override
  String get vaultSettingsTitle => '볼트 설정';

  @override
  String get generalSectionHeader => '일반';

  @override
  String get securityCredentialsSectionHeader => '보안 및 자격 증명';

  @override
  String get securityOptionsLockedTitle => '보안 옵션 잠김';

  @override
  String get authenticateOriginalCredentialsMessage =>
      '보안 설정을 변경하려면 원래 컨테이너 자격 증명으로 인증하세요.';

  @override
  String get unlockCredentialsLabel => '잠금 해제 자격 증명';

  @override
  String get unavailableSuffixLabel => '(사용 불가)';

  @override
  String get patternSetupRequiredBeforeSaving => '저장하기 전에 패턴을 설정하세요.';

  @override
  String get passwordKeystoreEncryptedHelperText =>
      '비밀번호는 Android 키스토어를 사용해 암호화됩니다. 키파일만 사용하는 경우 비워 두세요.';

  @override
  String get changePatternButton => '패턴 변경';

  @override
  String get setPatternButton => '패턴 설정';

  @override
  String get cacheDerivedKeyLabel => '파생 키 캐시';

  @override
  String get cryfsSkipScryptKdfSubtitle =>
      '다음부터 CryFS의 scrypt KDF 건너뛰기(키는 Android 키스토어에 보관)';

  @override
  String get reuseKeyMaterialKeystoreSubtitle => 'Android 키스토어의 키 자료를 재사용';

  @override
  String get pinAlgorithmSkipAutoDetectSubtitle =>
      '잠금 해제 시 자동 감지를 건너뛰도록 알고리즘을 고정합니다.';

  @override
  String get changeContainerPasswordTitle => '컨테이너 비밀번호 변경';

  @override
  String get bitlockerCredentialsChangeNotSupportedMessage =>
      'BitLocker 자격 증명은 앱 내에서 변경할 수 없습니다. Windows에서 \"BitLocker 관리\"를 사용하세요.';

  @override
  String get systemIntegrationSectionHeader => '시스템 및 통합';

  @override
  String get autoLockDurationLabel => '자동 잠금 시간';

  @override
  String get neverAutoLockOption => '안 함';

  @override
  String get exposeContentToFilePickerSubtitle => '잠금 해제 시 시스템 파일 선택기에 콘텐츠 노출';

  @override
  String get thumbnailStorageSectionHeader => '썸네일 저장소';

  @override
  String get cacheModeLabel => '캐시 모드';

  @override
  String get useGlobalDefaultSubtitle => '전역 기본값 사용';

  @override
  String get thumbnailQualityLabel => '썸네일 품질';

  @override
  String get clearThumbnailCacheTitle => '썸네일 캐시 지우기';

  @override
  String get removeCachedThumbnailsSubtitle => '캐시된 이미지 및 동영상 썸네일 제거';

  @override
  String get vaultInformationSectionHeader => '볼트 정보';

  @override
  String get vaultInformationTileTitle => '볼트 세부정보 보기';

  @override
  String get vaultInformationTileSubtitle => '암호화 방식, 형식 및 기타 기술 세부정보';

  @override
  String get vaultInfoLocationLabel => '위치';

  @override
  String get vaultInfoRequiresUnlockTitle => '잠금 해제 필요';

  @override
  String get vaultInfoRequiresUnlockMessage => '기술 세부정보를 보려면 이 볼트의 잠금을 해제하세요.';

  @override
  String get vaultInfoLoadFailedTitle => '볼트 정보를 불러올 수 없습니다';

  @override
  String get vaultInfoLoadFailedMessage => '이 볼트의 세부정보를 읽는 중 문제가 발생했습니다.';

  @override
  String get vaultInfoVolumeSizeLabel => '볼륨 크기';

  @override
  String get vaultInfoFileSystemLabel => '파일 시스템';

  @override
  String get vaultInfoHiddenVolumeLabel => '숨김 볼륨';

  @override
  String get vaultInfoReadOnlyLabel => '읽기 전용';

  @override
  String get vaultInfoLuksVersionLabel => 'LUKS 버전';

  @override
  String get vaultInfoSectorSizeLabel => '섹터 크기';

  @override
  String get vaultInfoVaultFormatLabel => '볼트 형식';

  @override
  String get vaultInfoCipherComboLabel => '암호화 방식 조합';

  @override
  String get vaultInfoShorteningThresholdLabel => '파일명 축약 기준';

  @override
  String get vaultInfoFormatVersionLabel => '형식 버전';

  @override
  String get vaultInfoContentCipherLabel => '콘텐츠 암호화 방식';

  @override
  String get vaultInfoFilenameEncryptionLabel => '파일명';

  @override
  String get vaultInfoPlaintextNamesValue => '평문';

  @override
  String get vaultInfoEncryptedNamesValue => '암호화됨';

  @override
  String get vaultInfoBlockCipherLabel => '블록 암호화 방식';

  @override
  String get vaultInfoBlockSizeLabel => '블록 크기';

  @override
  String get vaultInfoCreatedWithVersionLabel => '생성 시 버전';

  @override
  String get vaultInfoLastOpenedWithVersionLabel => '마지막 사용 버전';

  @override
  String get vaultInfoYesValue => '예';

  @override
  String get vaultInfoNoValue => '아니요';

  @override
  String get vaultInfoBitlockerNote =>
      '이 앱은 BitLocker 자체의 헤더 메타데이터를 분석하지 않으므로, 암호화 방식 및 버전 세부정보는 여기에서 확인할 수 없습니다.';

  @override
  String get patternSetupRequiredAboveBeforeSaving => '저장하기 전에 위에서 패턴을 설정하세요.';

  @override
  String get passwordOrCacheDerivedKeyRequiredMessage =>
      '이 잠금 해제 방법에는 비밀번호 또는 키파일을 사용한 \"파생 키 캐시\"가 필요합니다.';

  @override
  String get saveConfigurationButton => '구성 저장';

  @override
  String get incorrectPatternError => '잘못된 패턴';

  @override
  String get verifyPatternTitle => '패턴 확인';

  @override
  String get incorrectPasswordError => '잘못된 비밀번호';

  @override
  String get verificationFailedError => '확인 실패';

  @override
  String get incorrectCredentialsError => '잘못된 자격 증명';

  @override
  String get containerPasswordOptionalLabel => '컨테이너 비밀번호(키파일만 사용 시 선택 사항)';

  @override
  String get pimOptionalLabel => 'PIM(선택 사항)';

  @override
  String get usbDriveLockedLabel => 'USB 드라이브 · 잠김';

  @override
  String get lockedContainerLabel => '잠긴 컨테이너';

  @override
  String get operationInProgressWaitMessage => '작업이 진행 중입니다. 잠그기 전에 기다려 주세요.';

  @override
  String get reconnectUsbTooltip => 'USB 다시 연결';

  @override
  String get unlockContainerTooltip => '컨테이너 잠금 해제';

  @override
  String lockFailedMessage(String errorType) {
    return '잠금 실패: $errorType';
  }

  @override
  String get newPasswordOrKeyfilesRequired => '새 비밀번호 또는 키파일이 필요합니다.';

  @override
  String get newPasswordsDoNotMatch => '새 비밀번호가 일치하지 않습니다.';

  @override
  String get passwordChangedSuccessfullyMessage => '비밀번호가 성공적으로 변경되었습니다.';

  @override
  String get failedToChangePasswordMessage =>
      '비밀번호 변경에 실패했습니다. 이전 자격 증명을 확인하세요.';

  @override
  String get currentCredentialsSectionHeader => '현재 자격 증명';

  @override
  String get oldPasswordLabel => '이전 비밀번호';

  @override
  String get oldPimOptionalLabel => '이전 PIM(선택 사항)';

  @override
  String get newCredentialsSectionHeader => '새 자격 증명';

  @override
  String get newPimOptionalLabel => '새 PIM(선택 사항)';

  @override
  String get noContainersYetTitle => '아직 컨테이너가 없습니다';

  @override
  String get dashboardEmptyStateMessage =>
      '시작하려면 VeraCrypt 컨테이너를 마운트하거나, USB 드라이브를 연결하거나, 완전히 새로운 암호화 볼트를 만드세요.';

  @override
  String get sortFieldName => '이름';

  @override
  String get sortFieldSize => '크기';

  @override
  String get sortFieldType => '유형';

  @override
  String get sortFieldDate => '날짜';

  @override
  String get layoutModeDetailedList => '자세한 목록';

  @override
  String get layoutModeCompactList => '간단한 목록';

  @override
  String get layoutModeGalleryGrid => '갤러리 그리드';

  @override
  String get readOnlyCantDeleteTooltip => '읽기 전용 — 삭제할 수 없음';

  @override
  String get readOnlyCantMoveTooltip => '읽기 전용 — 이동할 수 없음';

  @override
  String get readOnlyCantRenameTooltip => '읽기 전용 — 이름을 변경할 수 없음';

  @override
  String sizeCalculatingWithBytesLabel(String bytes) {
    return '$bytes(계산 중…)';
  }

  @override
  String get sizeCalculatingLabel => '계산 중…';

  @override
  String get editSecureItemsToRenameMessage => '이름을 변경하려면 보안 항목을 편집하세요';

  @override
  String get vaultItemsCannotBeOpenedExternallyMessage =>
      '볼트 항목은 외부 앱에서 열 수 없습니다';

  @override
  String get mountedReadOnlyTooltip => '읽기 전용으로 마운트됨';

  @override
  String get readOnlyBadgeAbbreviation => 'RO';

  @override
  String freeSpaceLabel(String bytes) {
    return '여유 공간 $bytes';
  }

  @override
  String get filteredLabel => '필터링됨';

  @override
  String get statsStorageSectionHeader => '저장소';

  @override
  String statsFolderCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '폴더 $count개',
    );
    return '$_temp0';
  }

  @override
  String statsFileCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개',
    );
    return '$_temp0';
  }

  @override
  String get filterAllFilesOption => '모든 파일';

  @override
  String get filterImagesOption => '이미지';

  @override
  String get filterVideosOption => '동영상';

  @override
  String get filterAudioOption => '오디오';

  @override
  String get filterDocumentsOption => '문서';

  @override
  String get folderExposedAsStorageExplanation =>
      '이 폴더는 독립적인 저장 위치로 노출되므로 다른 앱이 해당 파일을 직접 탐색하고 열 수 있습니다.';

  @override
  String conflictItemsAlreadyExistTitle(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '이미 존재하는 항목 $count개',
    );
    return '$_temp0';
  }

  @override
  String get conflictResolutionSubtitle =>
      '각 항목에 대해 어떻게 처리할지 선택하거나, 하나의 선택을 모두에 적용하세요.';

  @override
  String get skipAllChipLabel => '모두 건너뛰기';

  @override
  String get overwriteAllChipLabel => '모두 덮어쓰기';

  @override
  String get overwriteItemDropdownLabel => '덮어쓰기';

  @override
  String get overwriteFolderDropdownLabel => '폴더 덮어쓰기';

  @override
  String get fileOpsTransfersInProgressTitle => '진행 중인 전송';

  @override
  String get fileOpsRecentTransfersTitle => '최근 전송';

  @override
  String get fileOpsNoRecentTransfersMessage => '최근 전송 없음';

  @override
  String get fileOpsNoRecentTransfersSubtitle =>
      '복사, 이동, 삭제 작업이 실행되는 동안 여기에 표시됩니다.';

  @override
  String fileOpsShowDetailsLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개',
    );
    return '$_temp0';
  }

  @override
  String get fileOpsCancelTooltip => '취소';

  @override
  String get fileOpsDismissTooltip => '닫기';

  @override
  String get fileOpsRootDestinationLabel => '루트';

  @override
  String get fileOpsCancelledStatusLabel => '취소됨';

  @override
  String fileOpsItemsFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 항목 실패:',
    );
    return '$_temp0';
  }

  @override
  String fileOpsMoreItemsLabel(num count) {
    return '+$count개 더 보기';
  }

  @override
  String get transferActivityTooltip => '전송';

  @override
  String fileOpsSpeedLabel(String speed) {
    return '$speed/초';
  }

  @override
  String fileOpsEtaLabel(String time) {
    return '약 $time 남음';
  }

  @override
  String archiveErrorReadingFile(String error) {
    return '파일 읽기 오류: $error';
  }

  @override
  String get archivePreviewNotAvailableMessage => '이 파일 형식은 미리보기를 사용할 수 없습니다.';

  @override
  String get avifFailedToRenderMessage => 'AVIF 렌더링에 실패했습니다';

  @override
  String get encryptedImageLoadFailedMessage => '암호화된 이미지를 불러오지 못했습니다';

  @override
  String encryptedImageLoadFailedWithReasonMessage(String error) {
    return '암호화된 이미지를 불러오지 못했습니다: $error';
  }

  @override
  String get invalidOrCorruptedImageMessage => '잘못되었거나 손상된 이미지 형식입니다.';

  @override
  String mediaViewerPlaylistPositionLabel(num current, num total) {
    return '$total개 중 $current번째';
  }

  @override
  String mediaViewerPlaylistPositionScanningLabel(num current, num total) {
    return '$total개 중 $current번째  ·  검색 중…';
  }

  @override
  String get mediaViewerScanningLabel => '검색 중…';

  @override
  String get mediaFileDeletedMessage => '파일이 성공적으로 삭제되었습니다';

  @override
  String get mediaFileDeleteFailedMessage => '파일 삭제에 실패했습니다';

  @override
  String get mediaFileRenamedMessage => '파일 이름이 성공적으로 변경되었습니다';

  @override
  String get aboutScreenTitle => '정보';

  @override
  String get couldNotOpenLinkMessage => '링크를 열 수 없습니다';

  @override
  String get fileManagerSettingsTitle => '파일 관리자 설정';

  @override
  String get showMediaThumbnailsLabel => '미디어 썸네일 표시';

  @override
  String get showMediaThumbnailsDesc => '목록 보기에서 이미지 및 동영상의 썸네일 미리보기를 표시합니다';

  @override
  String get showFileNamesLabel => '파일 이름 표시';

  @override
  String get showFileNamesDesc => '그리드 레이아웃에서 항목 아래에 텍스트 라벨을 표시합니다';

  @override
  String get showBreadcrumbBarLabel => '경로 표시줄 표시';

  @override
  String get showBreadcrumbBarDesc => '탐색기 상단의 경로 탐색 표시줄';

  @override
  String get showStatsBarLabel => '통계 표시줄 표시';

  @override
  String get showStatsBarDesc => '파일 수 및 여유 공간 정보 배너';

  @override
  String get autoStartPlaylistModeLabel => '재생 목록 모드 자동 시작';

  @override
  String get autoStartPlaylistModeDesc => '미디어 항목을 열 때 자동으로 재생 목록 모드로 시작합니다';

  @override
  String get showPlaylistCarouselLabel => '재생 목록 캐러셀 표시';

  @override
  String get showPlaylistCarouselDesc => '미디어 재생 목록을 볼 때 썸네일 캐러셀 버튼을 표시합니다';

  @override
  String get videoPlaybackSliderLabel => '동영상 재생 위치 슬라이더';

  @override
  String get longPressPlaybackDiagnosticsHint => '길게 눌러 재생 진단 보기';

  @override
  String get staticImageModeLabel => '정지 이미지 모드';

  @override
  String slideshowModeActiveLabel(int seconds) {
    return '슬라이드쇼 모드 활성화됨($seconds초 간격)';
  }

  @override
  String videoPlaybackModeLabel(String mode) {
    return '동영상 재생 모드: $mode';
  }

  @override
  String get pauseLabel => '일시 정지';

  @override
  String get playLabel => '재생';

  @override
  String get emptyFolderTitle => '빈 폴더';

  @override
  String get emptyFolderMessage => '추가 작업을 사용해 파일을 만들거나 기기에서 가져오세요.';

  @override
  String get noResultsTitle => '결과 없음';

  @override
  String noResultsForQueryMessage(String query) {
    return '이 폴더에 \"$query\"와(과) 일치하는 항목이 없습니다.';
  }

  @override
  String get closeCarouselTooltip => '캐러셀 닫기';

  @override
  String get playlistScrollModeMenu => '재생 목록 스크롤 모드';

  @override
  String get playlistScrollHorizontalLabel => '가로';

  @override
  String get playlistScrollVerticalPageLabel => '세로 페이지 넘김';

  @override
  String get playlistScrollVerticalContinuousLabel => '세로 연속 스크롤';

  @override
  String get undoTooltip => '실행 취소';

  @override
  String get redoTooltip => '다시 실행';

  @override
  String get autosavingLabel => '자동 저장 중…';

  @override
  String get savingLabel => '저장 중…';

  @override
  String autosavedAtLabel(String time) {
    return '$time에 자동 저장됨';
  }

  @override
  String cameraDisconnectedError(String message) {
    return '카메라 연결 끊김: $message';
  }

  @override
  String get unknownErrorFallback => '알 수 없는 오류';

  @override
  String get cameraPermissionsRequiredMessage =>
      '카메라를 사용하려면 카메라 및 마이크 권한이 필요합니다.';

  @override
  String cameraErrorMessage(String error) {
    return '카메라 오류: $error';
  }

  @override
  String get cameraPhotoCaptureFailedMessage => '사진 촬영에 실패했습니다';

  @override
  String get cameraRecordingFailedMessage => '녹화에 실패했습니다';

  @override
  String cameraRecordingFailedWithReasonMessage(String error) {
    return '녹화에 실패했습니다: $error';
  }

  @override
  String get cameraRecordingTooShortMessage => '녹화 시간이 너무 짧아 저장할 수 없습니다';

  @override
  String get cameraCouldNotSaveRecordingMessage => '녹화 내용을 저장할 수 없습니다';

  @override
  String cameraCouldNotSaveRecordingWithReasonMessage(String error) {
    return '녹화 내용을 저장할 수 없습니다: $error';
  }

  @override
  String get cameraCouldNotSwitchLensMessage => '렌즈를 전환할 수 없습니다';

  @override
  String get cameraEncryptingPhotoLabel => '사진 암호화 중…';

  @override
  String get cameraEncryptingVideoLabel => '동영상 암호화 중…';

  @override
  String get aboutApplicationSectionHeader => '애플리케이션';

  @override
  String get aboutTagline => '무료 · 오픈 소스 · 오프라인 암호화 볼트';

  @override
  String get aboutVersionTitle => '버전';

  @override
  String aboutVersionSubtitle(String version) {
    return 'v$version';
  }

  @override
  String get aboutWhatsNewTitle => '새로운 기능';

  @override
  String get aboutWhatsNewSubtitle => '최근 변경 사항 및 릴리스 노트 보기';

  @override
  String get aboutPrivacySecurityTitle => '개인정보 보호 및 보안';

  @override
  String get aboutPrivacySecuritySubtitle =>
      '네트워크 접근 없음, 암호화되지 않은 데이터는 디스크에 기록되지 않음';

  @override
  String get aboutSupportedFormatsSectionHeader => '지원되는 형식';

  @override
  String get aboutVeraCryptLuksTitle => 'VeraCrypt 및 LUKS1/2';

  @override
  String get aboutVeraCryptLuksSubtitle =>
      '표준 및 숨김 볼륨, 사용자 지정 PIM, 키파일, xts-plain64, Argon2id/i';

  @override
  String get aboutBitLockerTitle => 'BitLocker 및 BitLocker To Go';

  @override
  String get aboutBitLockerSubtitle => '사용자 암호 및 48자리 숫자 복구 키 지원';

  @override
  String get aboutDirectoryVaultsTitle => '폴더 볼트';

  @override
  String get aboutDirectoryVaultsSubtitle =>
      'Cryptomator(v7/v8 SIV_GCM 및 SIV_CTRMAC), gocryptfs(v2 AES-GCM 및 XChaCha20), CryFS(v0.10+ XChaCha20 및 AES)';

  @override
  String get aboutVhdTitle => '가상 하드 디스크(VHD / VHDX)';

  @override
  String get aboutVhdSubtitle => '고정 및 동적 확장 디스크 이미지를 위한 BAT 변환';

  @override
  String get aboutNativeCoreEngineSectionHeader => '네이티브 코어 엔진';

  @override
  String get aboutCompiledLibrariesTitle => '컴파일된 C++ 라이브러리';

  @override
  String get aboutCompiledLibrariesBody =>
      '• mbedTLS v3.6.0(ARMv8 하드웨어 암호화 및 SHA-2)\n• libavif 및 libgav1(네이티브 AVIF 이미지 디코더)\n• ChaN FatFs v4.0.4(FAT12/16/32 및 exFAT)\n• Tuxera NTFS-3G 및 내장 mkntfs\n• e2fsprogs v1.47.4 libext2fs(ext2/ext3/ext4)\n• Dislocker Virtual I/O(BitLocker FVE / To Go)\n• VeraCrypt 1.26.29(Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id/i)\n• cJSON v1.7.18(LUKS2 및 Cryptomator 메타데이터)';

  @override
  String get aboutCommunitySectionHeader => '커뮤니티 및 오픈 소스';

  @override
  String get aboutReportIssueTitle => '문제 신고';

  @override
  String get aboutReportIssueSubtitle => '버그를 발견하셨나요? GitHub에 이슈를 제출하세요';

  @override
  String get reportIssueSheetTitle => '문제 신고';

  @override
  String get reportIssueSheetSubtitle =>
      '문제와 가장 일치하는 항목을 선택하세요 — 미리 채워진 GitHub 양식이 열립니다';

  @override
  String get reportIssueBugTitle => '버그 신고';

  @override
  String get reportIssueBugSubtitle => '충돌이 발생했거나 제대로 작동하지 않음';

  @override
  String get reportIssueContainerTitle => '컨테이너/볼트 문제';

  @override
  String get reportIssueContainerSubtitle => '잠금 해제, 마운트 또는 형식별 문제';

  @override
  String get reportIssueFeatureTitle => '기능 요청';

  @override
  String get reportIssueFeatureSubtitle => '아이디어나 개선 사항 제안';

  @override
  String get reportIssueOtherTitle => '기타';

  @override
  String get reportIssueOtherSubtitle => 'GitHub에서 모든 템플릿 찾아보기';

  @override
  String get aboutContributorsTitle => '기여자';

  @override
  String get aboutContributorsSubtitle => 'VaultExplorer 개발에 도움을 준 사람들';

  @override
  String get aboutLicensesTitle => '오픈 소스 라이선스';

  @override
  String get aboutLicensesSubtitle => '이 앱에서 사용된 타사 라이브러리';

  @override
  String get aboutFooterMadeWithLove => '프라이버시를 위해 ❤로 만들었습니다.';

  @override
  String get aboutVersionCopiedMessage => '버전 정보가 복사되었습니다 — 버그 신고에 유용합니다';

  @override
  String aboutVersionClipboardText(String version) {
    return 'VaultExplorer v$version (Android)';
  }

  @override
  String aboutShareText(String url) {
    return 'VaultExplorer — Android용 무료 오픈 소스 오프라인 볼트입니다.\n\n암호화된 컨테이너(VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs, CryFS) 안에 비밀번호, 메모, 파일을 저장하세요.\n\n$url';
  }

  @override
  String get aboutShareLinkCopiedMessage => '공유 가능한 링크가 클립보드에 복사되었습니다';

  @override
  String get aboutPrivacySheetTitle => '개인정보 보호 및 데이터 보안';

  @override
  String get aboutPrivacySheetSubtitle => '100% 오프라인, 로컬 메모리 기반 보안 설계';

  @override
  String get privacyPointNoNetworkTitle => '네트워크 접근 불필요';

  @override
  String get privacyPointNoNetworkBody =>
      'VaultExplorer는 Android에서 android.permission.INTERNET 권한을 요청하지 않습니다. 어떤 네트워크와도 통신할 수 없습니다.';

  @override
  String get privacyPointNoDiskLeaksTitle => '암호화되지 않은 디스크 유출 없음';

  @override
  String get privacyPointNoDiskLeaksBody =>
      '복호화 및 재암호화는 전적으로 시스템 메모리에서 이루어집니다. 암호화되지 않은 임시 파일은 기기 저장소에 저장되지 않습니다.';

  @override
  String get privacyPointNoAnalyticsTitle => '분석 또는 원격 측정 없음';

  @override
  String get privacyPointNoAnalyticsBody =>
      '충돌 보고, 사용 추적, 또는 사용자나 기기에 대한 데이터를 수집하는 타사 SDK가 전혀 없습니다.';

  @override
  String get privacyPointKeystoreTitle => '비밀 정보는 Android 키스토어에 보관됨';

  @override
  String get privacyPointKeystoreBody =>
      '기억된 비밀번호, 패턴, 캐시된 파생 키는 하드웨어 기반 Android 키스토어에서 AES-256-GCM으로 봉인됩니다.';

  @override
  String get privacyPointPosixTitle => 'POSIX 가속 및 저장소 접근';

  @override
  String get privacyPointPosixBody =>
      '폴더 볼트 내부의 파일은 가능한 경우 직접 읽고 쓰며, 큰 폴더의 경우 Android의 느린 SAF 계층을 우회합니다.';

  @override
  String get privacyPointScreenClipboardTitle => '화면 및 클립보드 보호';

  @override
  String get privacyPointScreenClipboardBody =>
      '스크린샷/작업 전환기 미리보기 차단(FLAG_SECURE)과 함께, 창이 포커스될 때 손상된 클립보드를 자동으로 정리합니다. 항목 볼트에서 복사된 비밀번호는 Android 13 이상에서 민감한 정보로 표시되며, 사용하지 않으면 30초 후 자동으로 지워집니다.';

  @override
  String get privacyPointMaskModeTitle => '마스크 모드';

  @override
  String get privacyPointMaskModeBody =>
      '선택적으로 앱을 다른 아이콘과 이름을 가진 실제로 작동하는 zip 압축 파일 탐색기로 위장합니다. 제목을 2초간 길게 누르면 실제 볼트에 접근할 수 있습니다.';

  @override
  String get privacyPointExternalLinksTitle => '외부 링크는 브라우저에서 열립니다';

  @override
  String get privacyPointExternalLinksBody =>
      '링크를 탭하면 기본 브라우저 앱으로 전달되어 요청을 처리합니다.';

  @override
  String get truncatedListingWarning =>
      '처음 50,000개 항목을 표시 중입니다 — 이 폴더에는 더 많은 파일이 있습니다.';

  @override
  String thumbnailQualitySummary(int size, int quality) {
    return '${size}px · 품질 $quality%';
  }

  @override
  String holdToSpeedIndicatorLabel(String speed) {
    return '$speed배속';
  }

  @override
  String get toolbarLayoutSectionHeader => '도구 모음 레이아웃';

  @override
  String get listViewOptionsSectionHeader => '목록 보기 옵션';

  @override
  String get detailedListViewColumnsSectionHeader => '자세한 목록 보기 열';

  @override
  String get galleryGridViewSectionHeader => '갤러리 그리드 보기';

  @override
  String get browserLayoutSectionHeader => '탐색기 레이아웃';

  @override
  String get mediaViewerSectionHeader => '미디어 뷰어';

  @override
  String get viewModeAction => '보기 모드';

  @override
  String get sortAction => '정렬';

  @override
  String get playMediaAction => '미디어 재생';

  @override
  String containerSpaceSummary(String free, String total) {
    return '여유 $free · 전체 $total';
  }

  @override
  String volMountedSummary(int volId) {
    return '볼륨 $volId · 마운트됨';
  }

  @override
  String vaultOccupiedSpaceSummary(String used) {
    return '$used 사용됨';
  }

  @override
  String get incorrectPasswordOrKeyfilesDriveError =>
      '비밀번호/키파일이 잘못되었거나 지원되지 않는 드라이브입니다';

  @override
  String driveUsableCapacity(int mb) {
    return '드라이브 사용 가능 용량: ${mb}MB. 이를 초과할 수 없습니다.';
  }

  @override
  String get unlockMethodManualPassword => '수동 비밀번호';

  @override
  String get unlockMethodRememberPassword => '비밀번호 기억';

  @override
  String get unlockMethodBiometrics => '생체 인식 잠금 해제';

  @override
  String get unlockMethodPattern => '패턴 잠금 해제';

  @override
  String get unlockMethodPin => 'PIN 잠금 해제';

  @override
  String get unlockMethodSubtitlePassword => '매번 비밀번호 입력';

  @override
  String get unlockMethodSubtitleRememberPassword => 'Android 키스토어에 안전하게 저장됨';

  @override
  String get unlockMethodSubtitleBiometrics => '지문 또는 얼굴로 잠금 해제';

  @override
  String get unlockMethodSubtitlePattern => '패턴을 그려 잠금 해제';

  @override
  String get unlockMethodSubtitlePin => 'PIN을 입력해 잠금 해제';

  @override
  String selectionSummaryCombined(String filePart, String folderPart) {
    return '$filePart + $folderPart';
  }

  @override
  String get videoDecoderUnavailableError => '동영상 디코더를 사용할 수 없음 — 하드웨어 코덱 충돌';

  @override
  String get mediaStreamInitFailedError => '미디어 스트림 초기화에 실패했습니다';

  @override
  String get invalidAvifImage => '잘못된 AVIF 이미지';

  @override
  String get verbImport => '가져오기';

  @override
  String get verbExport => '내보내기';

  @override
  String get verbMove => '이동';

  @override
  String get verbCopy => '복사';

  @override
  String get verbDelete => '삭제';

  @override
  String get verbImported => '가져옴';

  @override
  String get verbExported => '내보내기 완료';

  @override
  String get verbMoved => '이동됨';

  @override
  String get verbCopied => '복사됨';

  @override
  String get verbDeleted => '삭제됨';

  @override
  String get verbImporting => '가져오는 중';

  @override
  String get verbExporting => '내보내는 중';

  @override
  String get verbMoving => '이동 중';

  @override
  String get verbCopying => '복사 중';

  @override
  String get verbDeleting => '삭제 중';

  @override
  String fileOpItemsCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummaryCount(num count, String verb) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개 $verb',
    );
    return '$_temp0';
  }

  @override
  String fileOpSummarySkipped(num count) {
    return '$count개 건너뜀';
  }

  @override
  String fileOpSummaryFailed(num count) {
    return '$count개 실패';
  }

  @override
  String get statusCancelled => '취소됨';

  @override
  String get statusFailed => '실패';

  @override
  String get statusCompleted => '완료됨';

  @override
  String get fileOpCheckingSpace => '사용 가능한 공간 확인 중…';

  @override
  String get fileOpResolvingConflicts => '충돌 해결 중…';

  @override
  String fileOpNotEnoughSpace(String required, String free) {
    return '공간 부족 — $required 필요, $free만 사용 가능';
  }

  @override
  String get fileOpDiskFullPartialRemoved => '디스크 가득 참 — 부분 파일이 제거되었습니다';

  @override
  String get fileOpMoveFailed => '이동 실패';

  @override
  String get fileOpCopyFailed => '복사 실패';

  @override
  String get fileOpDeleteFailed => '삭제 실패';

  @override
  String get fileOpDiskFull => '디스크 가득 참';

  @override
  String get fileOpImporting => '가져오는 중…';

  @override
  String get fileOpExporting => '내보내는 중…';

  @override
  String fileOpImportingName(String name) {
    return '$name 가져오는 중…';
  }

  @override
  String fileOpExportingName(String name) {
    return '$name 내보내는 중…';
  }

  @override
  String fileOpMovingName(String name) {
    return '$name 이동 중…';
  }

  @override
  String fileOpCopyingName(String name) {
    return '$name 복사 중…';
  }

  @override
  String get fileOpDeleting => '삭제하는 중…';

  @override
  String fileOpDeletingName(String name) {
    return '$name 삭제하는 중…';
  }

  @override
  String fileOpDeletedSoFar(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개 제거됨',
    );
    return '$_temp0';
  }

  @override
  String get searchInSubfoldersHint => '모든 하위 폴더 검색…';

  @override
  String get deepSearchEnabledTooltip => '하위 폴더 검색 중 — 현재 폴더만 검색하려면 탭하세요';

  @override
  String get deepSearchDisabledTooltip => '현재 폴더 검색 중 — 하위 폴더도 검색하려면 탭하세요';

  @override
  String get filterAction => '필터';

  @override
  String get bookmarkAction => '북마크';

  @override
  String get unbookmarkAction => '북마크 해제';

  @override
  String get bookmarkSelectedAction => '선택 항목 북마크';

  @override
  String get unbookmarkSelectedAction => '선택 항목 북마크 해제';

  @override
  String bookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개 북마크됨',
    );
    return '$_temp0';
  }

  @override
  String unbookmarkedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개 북마크 해제됨',
    );
    return '$_temp0';
  }

  @override
  String get showBookmarkBarLabel => '북마크 표시줄 표시';

  @override
  String get showBookmarkBarDesc => '북마크 표시줄 또는 사이드바에 북마크된 항목 표시';

  @override
  String get bookmarkBarSectionHeader => '북마크 표시줄';

  @override
  String get noBookmarksYet => '아직 북마크된 항목이 없습니다';

  @override
  String get reorderBookmarksTitle => '북마크 재정렬';

  @override
  String get reorderBookmarksDesc => '항목을 드래그하여 북마크 표시줄의 순서를 변경하세요';

  @override
  String get navBarVaultsLabel => '볼트';

  @override
  String get navBarToolsLabel => '도구';

  @override
  String get toolsScreenTitle => '도구';

  @override
  String get toolsSectionContainerUtilities => '컨테이너 유틸리티';

  @override
  String get toolsSectionFileCryptography => '파일 암호화';

  @override
  String get toolsSectionStorageDiagnostics => '저장소 및 진단';

  @override
  String get toolContainerSplitterTitle => '분할 및 결합';

  @override
  String get toolContainerSplitterSubtitle => '컨테이너를 여러 조각으로 분할하거나 다시 결합합니다';

  @override
  String get toolContainerRepairTitle => '확인 및 복구';

  @override
  String get toolContainerRepairSubtitle => '헤더 또는 파일 시스템 문제 진단';

  @override
  String get toolSingleFileCryptoTitle => '파일 암호화 / 복호화';

  @override
  String get toolSingleFileCryptoSubtitle => '전체 컨테이너 없이 하나 이상의 파일을 보호합니다';

  @override
  String get toolStorageAnalyzerTitle => '저장소 분석기';

  @override
  String get toolStorageAnalyzerSubtitle => '마운트된 볼트에서 무엇이 공간을 차지하는지 확인합니다';

  @override
  String get toolDuplicateFinderTitle => '중복 파일 찾기';

  @override
  String get toolDuplicateFinderSubtitle =>
      '바이트 단위로 동일한 중복 파일을 찾아 제거하여 공간을 확보합니다';

  @override
  String get toolHashVerifierTitle => '파일 체크섬 및 해시 검증기';

  @override
  String get toolHashVerifierSubtitle => 'MD5/SHA 체크섬으로 큰 파일이 손상되지 않았는지 확인합니다';

  @override
  String get hashVerifierModeCompute => '계산';

  @override
  String get hashVerifierModeVerify => '검증';

  @override
  String get hashVerifierSelectSourceTitle => '파일 소스 선택';

  @override
  String get hashVerifierAlgorithmsLabel => '알고리즘';

  @override
  String get hashVerifierNoAlgorithmSelected => '알고리즘을 하나 이상 선택하세요';

  @override
  String get hashVerifierFilesLabel => '해시할 파일';

  @override
  String hashVerifierFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개 선택됨',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierComputeButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '해시 $count개 계산',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCancelButton => '취소';

  @override
  String hashVerifierBatchProgressLabel(Object current, Object total) {
    return '파일 $current/$total';
  }

  @override
  String get hashVerifierCancelledMessage => '취소되었습니다.';

  @override
  String hashVerifierComputeErrorsMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count개 파일의 해시 계산에 실패했습니다',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierCopiedMessage => '클립보드에 복사됨';

  @override
  String get hashVerifierExportManifestButton => '매니페스트로 내보내기';

  @override
  String get hashVerifierExportAlgorithmLabel => '매니페스트 알고리즘';

  @override
  String hashVerifierExportSuccessMessage(Object path) {
    return '$path에 저장됨';
  }

  @override
  String hashVerifierExportFailedMessage(Object error) {
    return '내보내기 실패: $error';
  }

  @override
  String get hashVerifierLoadManifestButton => '매니페스트 불러오기';

  @override
  String get hashVerifierChangeManifestButton => '변경';

  @override
  String get hashVerifierManifestLabel => '매니페스트 파일';

  @override
  String hashVerifierManifestEntryCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '항목 $count개',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierAutoAddFolderButton => '이 폴더의 모든 파일 추가';

  @override
  String get hashVerifierAddFilesToVerifyButton => '검증할 파일 추가';

  @override
  String get hashVerifierVerifyAllButton => '모두 검증';

  @override
  String hashVerifierVerifyProgressLabel(Object current, Object total) {
    return '파일 $current/$total 검증 중';
  }

  @override
  String hashVerifierSummaryMessage(
    Object ok,
    Object mismatch,
    Object missing,
  ) {
    return '일치 $ok개, 불일치 $mismatch개, 누락 $missing개';
  }

  @override
  String get hashVerifierStatusMatch => '일치';

  @override
  String get hashVerifierStatusMismatch => '불일치';

  @override
  String get hashVerifierStatusMissing => '파일이 추가되지 않음';

  @override
  String get hashVerifierStatusPending => '아직 검증되지 않음';

  @override
  String get hashVerifierExpectedLabel => '예상값';

  @override
  String get hashVerifierActualLabel => '실제값';

  @override
  String hashVerifierExtraFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '매니페스트에 없는 추가 파일 $count개',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierNoManifestLoadedMessage => '시작하려면 매니페스트 파일을 불러오세요';

  @override
  String get hashVerifierManifestParseEmptyMessage =>
      '이 파일에서 체크섬 항목을 찾을 수 없습니다';

  @override
  String hashVerifierLoadManifestFailedMessage(Object error) {
    return '매니페스트를 읽을 수 없습니다: $error';
  }

  @override
  String hashVerifierAutoAddedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '볼트 폴더에서 파일 $count개를 추가했습니다',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierModeVault => '볼트';

  @override
  String get hashVerifierVaultPickerLabel => '볼트';

  @override
  String get hashVerifierVaultNoVaultsMessage => '현재 마운트된 볼트가 없습니다';

  @override
  String get hashVerifierCheckEntireVaultButton => '전체 볼트 확인';

  @override
  String get hashVerifierVaultScanningLabel => '볼트 검색 중…';

  @override
  String hashVerifierVaultFilesDiscoveredLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개 발견됨',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmTitle => '전체 볼트를 확인할까요?';

  @override
  String hashVerifierVaultConfirmFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개',
    );
    return '$_temp0';
  }

  @override
  String get hashVerifierVaultConfirmWarning => '이 볼트의 모든 파일을 읽습니다.';

  @override
  String get hashVerifierVaultEmptyMessage => '이 볼트에는 확인할 파일이 없습니다';

  @override
  String get hashVerifierVaultStartButton => '확인 시작';

  @override
  String hashVerifierVaultHashingProgressLabel(Object current, Object total) {
    return '확인 중 $current / $total';
  }

  @override
  String get hashVerifierVaultCompleteTitle => '볼트 확인 완료';

  @override
  String hashVerifierVaultCompleteFilesLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개 확인됨',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteBytesLabel(Object size) {
    return '$size 처리됨';
  }

  @override
  String hashVerifierVaultCompleteSucceededLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '성공 $count개',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultCompleteFailedLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '실패 $count개',
    );
    return '$_temp0';
  }

  @override
  String hashVerifierVaultElapsedLabel(Object time) {
    return '경과 시간: $time';
  }

  @override
  String get hashVerifierVaultCancelledMessage => '볼트 확인이 취소되었습니다.';

  @override
  String hashVerifierVaultFailedMessage(Object error) {
    return '볼트 확인 실패: $error';
  }

  @override
  String get hashVerifierVaultNewCheckButton => '새 확인';

  @override
  String get hashVerifierVaultActionComputeTitle => '전체 볼트 계산';

  @override
  String get hashVerifierVaultActionComputeSubtitle => '볼트의 모든 파일을 해시합니다';

  @override
  String get hashVerifierVaultActionVerifyTitle => '전체 볼트 검증';

  @override
  String get hashVerifierVaultActionVerifySubtitle =>
      '불러온 매니페스트와 볼트의 모든 파일을 대조합니다';

  @override
  String get hashVerifierVaultChangeActionButton => '변경';

  @override
  String get hashVerifierVaultVerifyButton => '전체 볼트 검증';

  @override
  String get hashVerifierVaultVerifyRequiresVaultManifestMessage =>
      '전체 볼트를 검증하려면 볼트 내부에서 불러온 매니페스트가 필요합니다.';

  @override
  String get duplicateFinderTargetLabel => '대상 볼트';

  @override
  String get duplicateFinderTargetAllVaults => '열려 있는 모든 볼트';

  @override
  String get duplicateFinderStartScan => '검사 시작';

  @override
  String get duplicateFinderCancelScan => '검사 취소';

  @override
  String get duplicateFinderRescan => '다시 검사';

  @override
  String get duplicateFinderScanningStage1 => '1단계: 색인 생성 및 크기별 그룹화...';

  @override
  String get duplicateFinderScanningStage2 => '2단계: 부분 파일 헤더 확인...';

  @override
  String get duplicateFinderScanningStage3 => '3단계: 전체 바이트 해시 검증...';

  @override
  String get duplicateFinderScanComplete => '검사 완료';

  @override
  String get duplicateFinderNoDuplicatesTitle => '중복 파일을 찾지 못했습니다';

  @override
  String get duplicateFinderNoDuplicatesMessage =>
      '검사한 볼트의 모든 파일이 고유한 바이트 내용을 포함하고 있습니다.';

  @override
  String get duplicateFinderSelectRedundant => '중복 항목 선택';

  @override
  String get duplicateFinderSelectAll => '모두 선택';

  @override
  String get duplicateFinderDeselectAll => '모두 선택 해제';

  @override
  String get duplicateFinderOriginalLabel => '원본';

  @override
  String get duplicateFinderDuplicateLabel => '중복';

  @override
  String get duplicateFinderConfirmDeleteTitle => '중복 파일을 삭제할까요?';

  @override
  String get duplicateFinderSearchHint => '파일 이름 또는 경로로 중복 항목 검색...';

  @override
  String get toolNotImplementedYetMessage =>
      '이 도구는 아직 네이티브 엔진에 연결되어 있지 않습니다 — 향후 업데이트를 확인해 주세요.';

  @override
  String get splitJoinModeSplit => '분할';

  @override
  String get splitJoinModeJoin => '결합';

  @override
  String get splitSourceFileLabel => '원본 파일';

  @override
  String get splitDestinationFolderLabel => '대상 폴더';

  @override
  String get splitChunkSizeLabel => '조각 크기';

  @override
  String get splitChunkSizeCustomLabel => '사용자 지정 크기(MB)';

  @override
  String get splitChunkSizeFourMb => '4MB';

  @override
  String get splitChunkSizeCloud8mb => '8MB';

  @override
  String get splitChunkSizeCloud32mb => '32MB';

  @override
  String get splitChunkSizeCloud => '100MB';

  @override
  String get splitChunkSizeFat32 => '2GB';

  @override
  String get splitChunkSizeFourGb => '4GB';

  @override
  String get splitChunkSizeCustom => '사용자 지정';

  @override
  String get splitContainerButton => '컨테이너 분할';

  @override
  String get joinFirstPartLabel => '첫 번째 조각';

  @override
  String get joinOutputFileNameLabel => '출력 파일 이름';

  @override
  String get joinContainerButton => '파일 결합';

  @override
  String get chooseFileButton => '파일 선택';

  @override
  String get chooseFolderButton => '폴더 선택';

  @override
  String get noFileSelectedLabel => '선택된 파일 없음';

  @override
  String get noFolderSelectedLabel => '선택된 폴더 없음';

  @override
  String splitJoinOperationProgress(String done, String total) {
    return '$done / $total';
  }

  @override
  String get splitContainerSuccessMessage => '컨테이너가 성공적으로 분할되었습니다';

  @override
  String get joinContainerSuccessMessage => '파일이 성공적으로 결합되었습니다';

  @override
  String get cryptoDirectionEncrypt => '암호화';

  @override
  String get cryptoDirectionDecrypt => '복호화';

  @override
  String get singleFileCryptoInputFileLabel => '입력 파일';

  @override
  String get singleFileCryptoCipherLabel => '암호화 방식';

  @override
  String get singleFileCryptoDeleteOriginalLabel => '암호화 후 원본 파일 삭제';

  @override
  String singleFileCryptoEncryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개 암호화',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoDecryptButton(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개 복호화',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoSuccessMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '완료 — 파일 $count개 처리됨',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoPartialFailureMessage(
    Object succeeded,
    Object total,
    Object failed,
  ) {
    return '$total개 중 $succeeded개 파일 처리됨 — $failed개 실패';
  }

  @override
  String get singleFileCryptoAddFilesButton => '파일 추가';

  @override
  String get singleFileCryptoClearFilesButton => '지우기';

  @override
  String singleFileCryptoFilesQueuedCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '파일 $count개 선택됨',
    );
    return '$_temp0';
  }

  @override
  String singleFileCryptoBatchProgressLabel(Object current, Object total) {
    return '파일 $current/$total';
  }

  @override
  String get repairTargetStepTitle => '대상 선택';

  @override
  String get repairTargetUnmountedFileOption => '마운트되지 않은 파일';

  @override
  String get repairTargetUnmountedFileSubtitle => '열지 않은 컨테이너의 백업 헤더를 복원합니다';

  @override
  String get repairTargetMountedVolumeSubtitle =>
      '이미 열려 있는 볼트에서 파일 시스템 검사를 실행합니다';

  @override
  String get repairNoMountedVolumes => '현재 마운트된 볼트가 없습니다';

  @override
  String get repairScanButton => '진단 스캔 실행';

  @override
  String get repairChangeTargetButton => '대상 변경';

  @override
  String get repairDiagnosisHealthy => '문제가 발견되지 않았습니다';

  @override
  String get repairDiagnosisHeaderCorrupted => '헤더가 손상됨';

  @override
  String get repairDiagnosisFilesystemDirty => '파일 시스템 불안정 / 비정상 마운트 해제';

  @override
  String get repairRestoreBackupHeaderButton => '백업 헤더 복원';

  @override
  String get repairRunFilesystemCheckButton => '파일 시스템 검사 및 수정 실행';

  @override
  String get repairActionSucceededMessage => '복구가 성공적으로 완료되었습니다';

  @override
  String get repairActionFailedMessage => '복구 작업이 성공하지 못했습니다';

  @override
  String get storageAnalyzerTargetLabel => '볼륨';

  @override
  String get storageAnalyzerNoTargetsTitle => '분석할 항목 없음';

  @override
  String get storageAnalyzerNoTargetsMessage =>
      '먼저 볼트를 마운트한 후, 여기로 돌아와 저장소 세부 내역을 확인하세요.';

  @override
  String storageAnalyzerUsedOfTotal(String used, String total) {
    return '$total 중 $used 사용됨';
  }

  @override
  String get storageAnalyzerHeaviestFilesHeader => '용량이 큰 파일';

  @override
  String get storageAnalyzerBreakdownHeader => '파일 형식별';

  @override
  String get storageAnalyzerScanningMessage => '볼륨 검색 중…';

  @override
  String storageAnalyzerScanTruncatedNotice(String count) {
    return '$count개 파일 이후 스캔이 조기 중단되었습니다 — 결과가 불완전할 수 있습니다.';
  }

  @override
  String get storageAnalyzerNoFilesFound => '파일을 찾을 수 없습니다';

  @override
  String get storageCategoryImages => '이미지';

  @override
  String get storageCategoryVideos => '동영상';

  @override
  String get storageCategoryAudio => '오디오';

  @override
  String get storageCategoryDocuments => '문서';

  @override
  String get storageCategoryArchives => '압축 파일';

  @override
  String get storageCategoryOther => '기타';

  @override
  String get keyfilePassphraseGeneratorTitle => '키파일 및 패스프레이즈 생성기';

  @override
  String get keyfilePassphraseGeneratorSubtitle =>
      'Diceware 패스프레이즈, 사용자 지정 비밀번호, 고엔트로피 키파일을 생성합니다';

  @override
  String get tabPassphrase => '패스프레이즈';

  @override
  String get tabKeyfile => '키파일';

  @override
  String get modeDiceware => 'Diceware 패스프레이즈';

  @override
  String get modeCustomPassword => '사용자 지정 비밀번호';

  @override
  String get keyfileTypeBinary => '바이너리 키파일(.key)';

  @override
  String get keyfileTypeImage => '노이즈 이미지 키파일(.png)';

  @override
  String get copyPassphraseSuccess => '패스프레이즈가 보안 클립보드에 복사되었습니다';

  @override
  String get copyFingerprintSuccess => 'SHA-256 지문이 클립보드에 복사되었습니다';

  @override
  String get saveKeyfileToVault => '마운트된 볼트에 저장';

  @override
  String get exportKeyfileToStorage => '기기 저장소로 내보내기';

  @override
  String get keyfileNoOpenVaultsMessage => '열려 있는 볼트가 없습니다. 먼저 볼트를 마운트하세요.';

  @override
  String get keyfileSelectDestinationVaultTitle => '대상 볼트 선택';

  @override
  String keyfileVolumeIdLabel(Object volId) {
    return '볼륨 ID: $volId';
  }

  @override
  String keyfileExportSuccessMessage(Object path) {
    return '키파일을 $path에 내보냈습니다';
  }

  @override
  String keyfileExportFailedMessage(Object error) {
    return '내보내기 실패: $error';
  }

  @override
  String keyfileSavedToVaultMessage(Object vaultName, Object path) {
    return '키파일이 $vaultName에 저장되었습니다: $path';
  }

  @override
  String get keyfileWriteFailedMessage => '볼트에 키파일을 쓰지 못했습니다';

  @override
  String keyfileSaveErrorMessage(Object error) {
    return '볼트에 저장하는 중 오류 발생: $error';
  }

  @override
  String get passphraseGeneratedSecretLabel => '생성된 비밀 값';

  @override
  String get copyToClipboardTooltip => '클립보드에 복사';

  @override
  String get generateNewTooltip => '새로 생성';

  @override
  String get passphraseStrengthWeak => '약함';

  @override
  String get passphraseStrengthGood => '좋음';

  @override
  String get passphraseStrengthStrong => '강함';

  @override
  String get passphraseStrengthUnbreakable => '해독 불가';

  @override
  String get passphraseCrackTimeInstant => '1초 미만';

  @override
  String get passphraseCrackTimeShort => '며칠 ~ 몇 달';

  @override
  String get passphraseCrackTimeCenturies => '수 세기';

  @override
  String get passphraseCrackTimeMillionsOfYears => '수백만 년';

  @override
  String passphraseStrengthLabel(Object label) {
    return '강도: $label';
  }

  @override
  String passphraseEntropyBitsLabel(Object bits) {
    return '엔트로피 $bits비트';
  }

  @override
  String passphraseCrackTimeLabel(Object crackTime) {
    return '예상 해독 시간: $crackTime';
  }

  @override
  String get dicewareOptionsTitle => 'EFF Diceware 옵션';

  @override
  String dicewareWordCountLabel(Object count) {
    return '단어 수: $count개';
  }

  @override
  String dicewareWordCountBitsLabel(Object bits) {
    return '$bits비트';
  }

  @override
  String dicewareWordCountSliderLabel(Object count) {
    return '$count개 단어';
  }

  @override
  String get dicewareWordSeparatorLabel => '단어 구분 기호';

  @override
  String get dicewareSeparatorHyphen => '하이픈( - )';

  @override
  String get dicewareSeparatorSpace => '공백(   )';

  @override
  String get dicewareSeparatorUnderscore => '밑줄( _ )';

  @override
  String get dicewareSeparatorDot => '마침표( . )';

  @override
  String get dicewareSeparatorSlash => '슬래시( / )';

  @override
  String get dicewareWordCasingLabel => '단어 대소문자';

  @override
  String get dicewareCasingLowercase => '소문자';

  @override
  String get dicewareCasingTitleCase => '타이틀 케이스';

  @override
  String get dicewareCasingUppercase => '대문자';

  @override
  String get dicewareAppendDigitLabel => '임의의 숫자 추가(0-9)';

  @override
  String get dicewareAppendSymbolLabel => '임의의 기호 추가(!@#\$%)';

  @override
  String get customPasswordOptionsTitle => '사용자 지정 비밀번호 옵션';

  @override
  String customPasswordLengthLabel(Object length) {
    return '길이: $length자';
  }

  @override
  String customPasswordLengthSliderLabel(Object length) {
    return '$length자';
  }

  @override
  String get customPasswordUppercaseLabel => '대문자(A-Z)';

  @override
  String get customPasswordLowercaseLabel => '소문자(a-z)';

  @override
  String get customPasswordNumbersLabel => '숫자(0-9)';

  @override
  String get customPasswordSymbolsLabel => '기호(!@#\$%^&*)';

  @override
  String get customPasswordExcludeAmbiguousLabel => '혼동되는 문자 제외(1, l, I, 0, O)';

  @override
  String get keyfileBinarySizeTitle => '바이너리 키파일 크기';

  @override
  String get keyfileImageResolutionTitle => '노이즈 이미지 해상도';

  @override
  String get keyfilePresetBytes64 => '64바이트(VeraCrypt 표준)';

  @override
  String get keyfilePresetBytes256 => '256바이트';

  @override
  String get keyfilePresetBytes2048 => '2KB';

  @override
  String get keyfilePresetBytes64kb => '64KB';

  @override
  String get keyfilePresetBytes1mb => '1MB(최대 한도)';

  @override
  String get keyfilePresetRes64 => '64x64픽셀(~16KB)';

  @override
  String get keyfilePresetRes256 => '256x256픽셀(~256KB)';

  @override
  String get keyfilePresetRes512 => '512x512픽셀(~1MB)';

  @override
  String get keyfileGenerateNewTooltip => '새 키파일 생성';

  @override
  String keyfileSizeLabel(Object size) {
    return '크기: $size';
  }

  @override
  String get keyfileFingerprintLabel => 'SHA-256 지문';

  @override
  String get keyfileCopyFingerprintTooltip => '지문 복사';

  @override
  String get duplicateFinderNoVaultsTitle => '마운트된 볼트 없음';

  @override
  String get duplicateFinderNoVaultsMessage =>
      '중복 파일을 검사하려면 볼트 컨테이너를 최소 하나 이상 잠금 해제하고 마운트하세요.';

  @override
  String duplicateFinderConfirmDeleteMessage(Object count, Object size) {
    return '볼트에서 중복 파일 $count개($size)를 영구적으로 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.';
  }

  @override
  String get duplicateFinderDeletePermanentlyButton => '영구 삭제';

  @override
  String duplicateFinderDeleteSuccessMessage(Object count) {
    return '중복 파일 $count개를 성공적으로 삭제했습니다.';
  }

  @override
  String get duplicateFinderIntroTitle => '3단계 바이트 일치 검색기';

  @override
  String get duplicateFinderIntroSubtitle => '파일 이름과 관계없이 정확히 동일한 내용을 감지합니다.';

  @override
  String get duplicateFinderStagesDescription =>
      '• 1단계: 크기별 그룹화(즉시 메타데이터 탐색)\n• 2단계: 부분 헤더 확인(16KB SHA-256 헤더)\n• 3단계: 전체 해시 검증(정확한 SHA-256 바이트 일치)';

  @override
  String get duplicateFinderScanningVaultFallback => '볼트 검색 중...';

  @override
  String duplicateFinderProcessingFileLabel(Object fileName) {
    return '처리 중: $fileName';
  }

  @override
  String duplicateFinderScanStatsLabel(
    Object scanned,
    Object groups,
    Object saved,
  ) {
    return '검사한 파일: $scanned개 | 발견된 중복: $groups개 그룹($saved)';
  }

  @override
  String duplicateFinderGroupsFoundLabel(Object count) {
    return '중복 그룹 $count개 발견됨';
  }

  @override
  String duplicateFinderGroupsSummaryLabel(Object copies, Object saved) {
    return '$copies개 사본 발견 • $saved 저장 공간 절약 가능';
  }

  @override
  String duplicateFinderVaultsSelectedLabel(Object count) {
    return '볼트 $count개 선택됨';
  }

  @override
  String duplicateFinderGroupTitleLabel(
    Object groupIndex,
    Object size,
    Object count,
  ) {
    return '그룹 $groupIndex: $size($count개 사본 발견)';
  }

  @override
  String duplicateFinderRecoverableSpaceLabel(Object size) {
    return '복구 가능한 공간: $size';
  }

  @override
  String get duplicateFinderPreviewFileTooltip => '파일 미리보기';

  @override
  String duplicateFinderPreviewFailedMessage(Object fileName) {
    return '$fileName의 파일 미리보기를 열 수 없습니다';
  }

  @override
  String duplicateFinderPreviewErrorMessage(Object error) {
    return '파일 미리보기 오류: $error';
  }

  @override
  String duplicateFinderFilesSelectedLabel(Object count) {
    return '파일 $count개 선택됨';
  }

  @override
  String duplicateFinderBytesToBeFreedLabel(Object size) {
    return '$size 확보 예정';
  }

  @override
  String duplicateFinderDeleteSelectedButton(Object count) {
    return '선택 항목 삭제($count)';
  }

  @override
  String get vaultBrowserSwitchVaultTooltip => '볼트 전환';

  @override
  String get vaultBrowserRootFolderLabel => '루트 폴더';

  @override
  String vaultFilePickerTitle(Object vaultName) {
    return '파일 선택($vaultName)';
  }

  @override
  String get vaultFilePickerEmptyMessage => '폴더가 비어 있습니다';

  @override
  String vaultFilePickerConfirmButton(Object count) {
    return '파일 $count개 선택';
  }

  @override
  String vaultFolderPickerTitle(Object vaultName) {
    return '폴더 선택($vaultName)';
  }

  @override
  String get vaultFolderPickerEmptyMessage => '여기에는 하위 폴더가 없습니다';

  @override
  String get vaultFolderPickerRootLabel => '루트';

  @override
  String get vaultFolderPickerConfirmRootButton => '루트 폴더 선택';

  @override
  String vaultFolderPickerConfirmNamedButton(Object folderName) {
    return '\"$folderName\" 선택';
  }

  @override
  String get singleFileCryptoSelectInputTitle => '입력 파일 선택';

  @override
  String get singleFileCryptoFromDeviceTitle => '기기 저장소에서';

  @override
  String get singleFileCryptoFromDeviceSubtitle => '시스템 파일 선택기로 기기에서 파일 선택';

  @override
  String get singleFileCryptoFromVaultTitle => '마운트된 볼트에서';

  @override
  String get singleFileCryptoFromVaultSubtitle => '열려 있는 암호화된 컨테이너에서 파일 선택';

  @override
  String get singleFileCryptoSelectDestinationTitle => '대상 폴더 선택';

  @override
  String get singleFileCryptoDeviceFolderTitle => '기기 저장소 폴더';

  @override
  String get singleFileCryptoDeviceFolderSubtitle => '출력을 기기 저장소의 폴더에 저장합니다';

  @override
  String get singleFileCryptoVaultFolderTitle => '마운트된 볼트 폴더';

  @override
  String get singleFileCryptoVaultFolderSubtitle =>
      '출력을 열려 있는 암호화된 컨테이너 안에 저장합니다';

  @override
  String get toolsSectionBackupSync => '백업 및 동기화';

  @override
  String get toolVaultSyncTitle => '볼트 동기화';

  @override
  String get toolVaultSyncSubtitle => '두 볼트를 비교하고 누락되었거나 더 최신인 항목을 복사합니다';

  @override
  String get vaultSyncNoVaultsTitle => '마운트된 볼트 없음';

  @override
  String get vaultSyncNoVaultsMessage => '파일을 비교하고 동기화하려면 최소 하나의 볼트를 마운트하세요.';

  @override
  String get vaultSyncLeftLabel => '왼쪽';

  @override
  String get vaultSyncRightLabel => '오른쪽';

  @override
  String get vaultSyncTapToSelect => '탭하여 볼트 및 폴더 선택';

  @override
  String get vaultSyncSwapTooltip => '왼쪽/오른쪽 바꾸기';

  @override
  String get vaultSyncSameLocationWarning => '왼쪽과 오른쪽은 서로 다른 폴더여야 합니다.';

  @override
  String get vaultSyncIntroTitle => '두 볼트 비교';

  @override
  String get vaultSyncIntroSubtitle =>
      '왼쪽 및 오른쪽 볼트(또는 같은 볼트 내 두 폴더)를 선택하면 각 쪽에서 누락, 수정 또는 최신 항목을 확인할 수 있습니다.';

  @override
  String get vaultSyncCompareButton => '비교';

  @override
  String get vaultSyncComparingLabel => '볼트 비교 중…';

  @override
  String vaultSyncCompareStatsLabel(Object dirs, Object entries) {
    return '검사한 폴더: $dirs | 발견된 차이점: $entries';
  }

  @override
  String get vaultSyncCancelCompareButton => '취소';

  @override
  String get vaultSyncInSyncTitle => '이미 동기화됨';

  @override
  String vaultSyncInSyncMessage(Object count) {
    return '일치하는 $count개 파일이 양쪽에서 모두 동일합니다.';
  }

  @override
  String get vaultSyncRecompareButton => '다시 비교';

  @override
  String vaultSyncDifferencesFoundLabel(Object count) {
    return '차이점 $count개 발견됨';
  }

  @override
  String vaultSyncInSyncCountLabel(Object count) {
    return '$count개 파일이 이미 양쪽에서 일치합니다';
  }

  @override
  String vaultSyncBadgeOnlyLeft(Object count) {
    return '왼쪽에만 $count개';
  }

  @override
  String vaultSyncBadgeOnlyRight(Object count) {
    return '오른쪽에만 $count개';
  }

  @override
  String vaultSyncBadgeLeftNewer(Object count) {
    return '왼쪽이 더 최신인 $count개';
  }

  @override
  String vaultSyncBadgeRightNewer(Object count) {
    return '오른쪽이 더 최신인 $count개';
  }

  @override
  String vaultSyncBadgeConflicts(Object count) {
    return '검토가 필요한 $count개';
  }

  @override
  String get vaultSyncDirectionLabel => '동기화 방향';

  @override
  String get vaultSyncDirectionTwoWay => '양방향(권장)';

  @override
  String get vaultSyncDirectionTwoWaySubtitle =>
      '각 파일을 없거나 이전 사본만 있는 쪽으로 복사합니다';

  @override
  String get vaultSyncDirectionLeftToRight => '왼쪽 → 오른쪽(단방향)';

  @override
  String get vaultSyncDirectionLeftToRightSubtitle =>
      '새 파일과 업데이트된 파일을 왼쪽에서 오른쪽으로 보냅니다. 왼쪽은 변경되지 않습니다';

  @override
  String get vaultSyncDirectionRightToLeft => '오른쪽 → 왼쪽(단방향)';

  @override
  String get vaultSyncDirectionRightToLeftSubtitle =>
      '새 파일과 업데이트된 파일을 오른쪽에서 왼쪽으로 보냅니다. 오른쪽은 변경되지 않습니다';

  @override
  String get vaultSyncSearchHint => '차이점 검색';

  @override
  String get vaultSyncStatusOnlyLeft => '왼쪽에만 있음';

  @override
  String get vaultSyncStatusOnlyRight => '오른쪽에만 있음';

  @override
  String get vaultSyncStatusLeftNewer => '왼쪽이 더 최신';

  @override
  String get vaultSyncStatusRightNewer => '오른쪽이 더 최신';

  @override
  String get vaultSyncStatusConflict => '검토 필요';

  @override
  String get vaultSyncStatusTypeMismatch => '유형 불일치';

  @override
  String get vaultSyncFolderOnlyLeftDetail => '폴더 — 왼쪽에만 있음';

  @override
  String get vaultSyncFolderOnlyRightDetail => '폴더 — 오른쪽에만 있음';

  @override
  String vaultSyncBothSidesDetail(
    Object leftSize,
    Object leftDate,
    Object rightSize,
    Object rightDate,
  ) {
    return '왼쪽: $leftSize · $leftDate  →  오른쪽: $rightSize · $rightDate';
  }

  @override
  String get vaultSyncTypeMismatchTooltip =>
      '한쪽은 파일, 다른 쪽은 폴더입니다 — 파일 탐색기에서 수동으로 해결하세요';

  @override
  String get vaultSyncChangeActionTooltip => '동기화 작업 변경';

  @override
  String get vaultSyncActionCopyToRight => '복사 → 오른쪽';

  @override
  String get vaultSyncActionCopyToLeft => '복사 → 왼쪽';

  @override
  String get vaultSyncActionSkip => '건너뛰기';

  @override
  String vaultSyncChangesQueuedLabel(Object count) {
    return '변경 사항 $count개 대기 중';
  }

  @override
  String get vaultSyncSyncNowButton => '지금 동기화';

  @override
  String get vaultSyncConfirmTitle => '동기화를 시작할까요?';

  @override
  String vaultSyncConfirmMessage(Object count, Object bytes) {
    return '이 작업은 양쪽 간에 $count개 항목(총 $bytes)을 복사합니다. 같은 이름의 기존 파일은 덮어쓰기됩니다.';
  }

  @override
  String vaultSyncStartedMessage(Object count) {
    return '동기화가 시작되었습니다 — $count개 항목 대기 중';
  }

  @override
  String vaultSyncPickLocationTitle(Object side) {
    return '$side 볼트 및 폴더 선택';
  }

  @override
  String get vaultSyncReadOnlyBadge => '읽기 전용';

  @override
  String get vaultSyncReadOnlyTooltip =>
      '이 볼트는 읽기 전용으로 마운트되어 있어 파일을 복사할 수 없습니다';

  @override
  String get vaultSyncSyncingButton => '동기화 중…';

  @override
  String get vaultSyncNotEnoughSpaceTitle => '공간 부족';

  @override
  String vaultSyncNotEnoughSpaceMessage(
    Object side,
    Object required,
    Object free,
  ) {
    return '$side에 공간이 부족합니다 — $required 필요, $free만 사용 가능.';
  }

  @override
  String get removeMasterPasswordTitle => '마스터 비밀번호 제거';

  @override
  String get confirmRemoveMasterPasswordMessage =>
      '제거를 확인하려면 현재 마스터 비밀번호를 입력하세요:';

  @override
  String get authenticateToRemoveMasterPassword => '마스터 비밀번호를 제거하려면 인증하세요';

  @override
  String get incorrectPassword => '잘못된 비밀번호';

  @override
  String get rememberPerFolderLayoutLabel => '폴더별 레이아웃 기억';

  @override
  String get rememberPerFolderLayoutDesc =>
      '폴더마다 별도의 보기 레이아웃(목록, 그리드, 매스너리)을 저장합니다';

  @override
  String get fileInfoAction => '정보';

  @override
  String get automationSectionHeader => '자동화';

  @override
  String get automationTileTitle => '자동화';

  @override
  String get automationTileSubtitle =>
      '자동화가 이 볼트를 잠금 해제, 잠금, 파일 가져오기 또는 내보내기를 하도록 허용합니다';

  @override
  String get automationScreenTitle => '자동화(Tasker / MacroDroid)';

  @override
  String get automationUsbUnsupportedMessage =>
      'USB로 연결된 볼트에는 아직 자동화를 사용할 수 없습니다.';

  @override
  String get automationThisVaultSectionHeader => '이 볼트';

  @override
  String get automationAccessLabel => '자동화 접근 권한';

  @override
  String get automationPasswordSectionHeader => '자동화 비밀번호';

  @override
  String get automationPasswordStoredHint =>
      '무인 UNLOCK_VAULT 호출을 위해 비밀번호가 저장되어 있습니다. 새 비밀번호를 저장하면 교체되고, 빈 값을 저장하면 지워집니다 — 자동화는 이에 의존하는 대신 브로드캐스트에 직접 비밀번호를 제공할 수도 있습니다.';

  @override
  String get automationPasswordNotStoredHint =>
      '선택 사항입니다. 저장된 비밀번호가 없으면 자동화는 UNLOCK_VAULT 브로드캐스트마다 비밀번호를 제공해야 합니다.';

  @override
  String get automationNewPasswordFieldLabel => '새 비밀번호';

  @override
  String get automationPasswordFieldLabel => '비밀번호';

  @override
  String get automationClearPasswordButton => '저장된 비밀번호 지우기';

  @override
  String get automationSavePasswordButton => '비밀번호 저장';

  @override
  String get automationTokenSectionHeader => 'API 토큰';

  @override
  String get automationTokenDescription =>
      '자동화 접근 권한이 활성화된 모든 볼트가 공유합니다. 자동화는 매 브로드캐스트마다 이를 다시 전송합니다. 토큰이 잘못되었거나 누락된 경우 오류 없이 조용히 무시됩니다.';

  @override
  String get automationRegenerateTokenButton => '토큰 재생성';

  @override
  String get automationRegenerateTokenDialogTitle => '토큰을 재생성할까요?';

  @override
  String get automationRegenerateTokenDialogMessage =>
      '현재 토큰을 사용하는 모든 Tasker 프로필이나 MacroDroid 매크로는 새 토큰으로 업데이트할 때까지 조용히 작동을 멈춥니다.';

  @override
  String get automationRegenerateConfirmLabel => '재생성';

  @override
  String get automationTokenRegeneratedMessage => '토큰이 재생성되었습니다.';

  @override
  String get automationRegenerateTokenFailedMessage => '토큰을 재생성할 수 없습니다.';

  @override
  String get automationUpdateSettingsFailedMessage => '자동화 설정을 업데이트할 수 없습니다.';

  @override
  String get automationSavePasswordFailedMessage => '자동화 비밀번호를 저장할 수 없습니다.';

  @override
  String get automationPasswordClearedMessage => '자동화 비밀번호가 지워졌습니다.';

  @override
  String get automationPasswordSavedMessage => '자동화 비밀번호가 저장되었습니다.';

  @override
  String get automationConfigSectionHeader => '구성 문자열';

  @override
  String get automationConfigIntro =>
      '아래 값을 탭하여 복사하세요. Tasker에서는 \"Send Intent\" 작업을 사용하세요. MacroDroid에서는 Intent Type을 Broadcast로 설정한 \"Intent\" 작업을 사용하세요 — Activity나 Service는 \"unable to find explicit activity class\" 오류로 실패합니다.';

  @override
  String get automationConfigPackageLabel => '패키지 이름';

  @override
  String get automationConfigClassLabel => '리시버 클래스';

  @override
  String get automationConfigVaultUriLabel => '이 볼트의 URI';

  @override
  String get automationConfigActionsSectionHeader => '브로드캐스트 작업';

  @override
  String get automationActionUnlockLabel => '볼트 잠금 해제';

  @override
  String get automationActionLockLabel => '볼트 잠금';

  @override
  String get automationActionImportLabel => '파일 가져오기';

  @override
  String get automationActionExportLabel => '파일 내보내기';

  @override
  String get automationActionWipeLabel => '파일 삭제';

  @override
  String get automationDocCommentFootnote =>
      '전체 추가 항목 및 결과 브로드캐스트 계약은 VaultAutomationReceiver.kt에 문서화되어 있습니다.';

  @override
  String get automationTierOffLabel => '끄기';

  @override
  String get automationTierOffSubtitle => '자동화가 이 볼트에 접근할 수 없습니다';

  @override
  String get automationTierLifecycleLabel => '잠금 해제/잠금만';

  @override
  String get automationTierLifecycleSubtitle => '자동화는 이 볼트를 잠금 해제하고 잠글 수만 있습니다';

  @override
  String get automationTierFullLabel => '잠금 해제/잠금 + 파일 가져오기-내보내기';

  @override
  String get automationTierFullSubtitle =>
      '자동화는 이 볼트가 잠금 해제된 동안 파일을 가져오고 내보낼 수도 있습니다';

  @override
  String get automationTutorialLinkLabel => '전체 단계별 튜토리얼 읽기';

  @override
  String get showHiddenFilesLabel => '숨김 파일 표시';

  @override
  String get showHiddenFilesDesc => '점 파일 및 시스템 폴더를 표시합니다';

  @override
  String get dontAskAgain => '다시 묻지 않기';

  @override
  String get deleteAfterImportLabel => '가져온 후 파일 삭제';

  @override
  String get deleteAfterImportModeAsk => '매번 묻기';

  @override
  String get deleteAfterImportModeAskSubtitle => '가져오기 후 원본 파일을 삭제할지 묻습니다';

  @override
  String get deleteAfterImportModeKeep => '원본 유지(삭제하지 않음)';

  @override
  String get deleteAfterImportModeKeepSubtitle => '원본 파일을 절대 삭제하지 않으며 묻지 않습니다';

  @override
  String get deleteAfterImportModeDelete => '원본 자동 삭제';

  @override
  String get deleteAfterImportModeDeleteSubtitle =>
      '가져오기 후 기기에서 원본 파일을 자동으로 삭제합니다';

  @override
  String get wizardBackButton => '뒤로';

  @override
  String get wizardNextButton => '다음';

  @override
  String get wizardStepTypeTitle => '유형';

  @override
  String get wizardStepBasicInfoTitle => '기본 정보';

  @override
  String get wizardStepAdvancedTitle => '고급';

  @override
  String get wizardStepReviewTitle => '검토';

  @override
  String get wizardCreateTypePrompt => '무엇을 만드시겠습니까?';

  @override
  String get wizardChooseFormatPrompt => '컨테이너 형식을 선택하세요';

  @override
  String get wizardEncryptionDetailsRowTitle => '암호화 세부정보';

  @override
  String get wizardHiddenVolumeRowSubtitleConfigured => '구성됨 — 탭하여 검토';

  @override
  String get wizardHiddenVolumeRowSubtitleNeedsSetup => '탭하여 설정';

  @override
  String get wizardSummaryTitle => '요약';

  @override
  String get wizardSummaryPasswordLabel => '비밀번호';

  @override
  String get wizardPasswordSetValue => '설정됨';

  @override
  String get wizardPasswordNotSetValue => '설정 안 됨(키파일 사용)';

  @override
  String get wizardSummaryKeyfilesLabel => '키파일';

  @override
  String get wizardSummaryPimDefaultValue => '기본값';

  @override
  String get wizardSummaryPimLabel => 'PIM';

  @override
  String get wizardSummaryDriveLabel => 'USB 드라이브';

  @override
  String get sectionKeyStorageIntegration => '키 저장소 및 시스템 접근';

  @override
  String get sectionMaskMode => '마스크 모드';

  @override
  String get advancedOptionsTitle => '고급 옵션';

  @override
  String get audioTrackTitle => '오디오 트랙';

  @override
  String get noAudioTracksAvailable => '사용 가능한 오디오 트랙이 없습니다';

  @override
  String trackNumberLabel(int number) {
    return '트랙 $number';
  }

  @override
  String subtitleTrackNumberLabel(int number) {
    return '자막 $number';
  }

  @override
  String get offLabel => '끄기';

  @override
  String get externalSubtitlesLabel => '외부 자막 (.srt/.vtt)';

  @override
  String get externalLabel => '외부';

  @override
  String get subtitleSizeLabel => '크기';

  @override
  String get subtitleSizeSmall => '소';

  @override
  String get subtitleSizeMedium => '중';

  @override
  String get subtitleSizeLarge => '대';

  @override
  String get subtitleSizeExtraLarge => '특대';

  @override
  String get subtitlePositionLabel => '위치';

  @override
  String get subtitlePositionBottom => '하단';

  @override
  String get subtitlePositionLower => '하단 근처';

  @override
  String get subtitlePositionCenter => '중앙';

  @override
  String get subtitlePositionTop => '상단';

  @override
  String get editImageAction => '이미지 편집';

  @override
  String get imageEditorUnsupportedFormatMessage => '이 이미지 형식은 편집을 지원하지 않습니다.';

  @override
  String get cropToolLabel => '자르기';

  @override
  String get drawToolLabel => '그리기';

  @override
  String get textToolLabel => '텍스트';

  @override
  String get redactToolLabel => '가리기';

  @override
  String get rotateLeftTooltip => '왼쪽으로 회전';

  @override
  String get rotateRightTooltip => '오른쪽으로 회전';

  @override
  String get cropAspectFreeLabel => '자유';

  @override
  String get cropAspectSquareLabel => '정사각형';

  @override
  String get cropAspectOriginalLabel => '원본';

  @override
  String get applyCropTooltip => '자르기 적용';

  @override
  String get annotationColorTooltip => '색상';

  @override
  String get annotationStrokeWidthTooltip => '선 굵기';

  @override
  String get clearAnnotationsTooltip => '모든 주석 지우기';

  @override
  String get resetImageTooltip => '원본으로 재설정';

  @override
  String get resetImageConfirmTitle => '이미지를 재설정할까요?';

  @override
  String get resetImageConfirmMessage =>
      '이 세션에서 수행한 모든 자르기 및 그리기 변경 사항이 취소됩니다.';

  @override
  String get addTextAnnotationTitle => '텍스트 추가';

  @override
  String get addTextAnnotationHint => '내용을 입력하세요…';

  @override
  String get textToolHint => '이미지를 탭하여 텍스트 추가';

  @override
  String get saveImageSheetTitle => '변경 사항 저장';

  @override
  String get saveAsNewFileOption => '새 파일로 저장';

  @override
  String get saveAsNewFileDescription => '원본은 그대로 유지됩니다';

  @override
  String get overwriteOriginalOption => '원본 덮어쓰기';

  @override
  String get overwriteOriginalDescription => '원본 파일을 대체합니다';

  @override
  String get newFileNameLabel => '파일 이름';

  @override
  String get imageEditorPngNoteMessage => '편집한 이미지는 PNG로 저장됩니다.';

  @override
  String get imageSavedMessage => '이미지가 저장되었습니다';

  @override
  String imageSaveFailedMessage(String error) {
    return '이미지를 저장할 수 없습니다: $error';
  }

  @override
  String get advancedRenameButton => '고급';

  @override
  String get advancedRenameBatchTitle => '일괄 이름 변경';

  @override
  String get advancedRenameRulesTab => '규칙';

  @override
  String advancedRenamePreviewTab(int count) {
    return '미리보기 ($count)';
  }

  @override
  String get advancedRenameSearchReplaceTitle => '찾기 및 바꾸기';

  @override
  String get advancedRenameFindTextLabel => '찾을 텍스트';

  @override
  String get advancedRenameFindTextHint => '일치시킬 텍스트나 패턴 입력...';

  @override
  String get advancedRenameReplaceWithLabel => '바꿀 텍스트';

  @override
  String get advancedRenameReplaceWithHint => '새 텍스트 또는 변수...';

  @override
  String get advancedRenameInsertVariableTooltip => '동적 변수 토큰 삽입';

  @override
  String get advancedRenameDateTimeTokens => '날짜 및 시간 토큰';

  @override
  String advancedRenameStandardDate(String token) {
    return '표준 날짜 ($token)';
  }

  @override
  String advancedRenameYearFourDigit(String token) {
    return '4자리 연도 ($token)';
  }

  @override
  String advancedRenameMonth(String token) {
    return '월 ($token)';
  }

  @override
  String advancedRenameDayOfMonth(String token) {
    return '일 ($token)';
  }

  @override
  String advancedRenameTime(String token) {
    return '시간 ($token)';
  }

  @override
  String get advancedRenameDynamicIdentifiers => '동적 식별자';

  @override
  String advancedRenameUniqueUuid(String token) {
    return '고유 UUID v4 ($token)';
  }

  @override
  String get advancedRenameRandomAlphanumeric => '무작위 영숫자(8자)';

  @override
  String get advancedRenameRandomDigits => '무작위 숫자(6자리)';

  @override
  String get advancedRenameEmbeddedCounter => '내장 카운터';

  @override
  String advancedRenamePaddedCounter(String token) {
    return '자릿수 맞춤 카운터 ($token)';
  }

  @override
  String get advancedRenameRegex => '정규식';

  @override
  String get advancedRenameMatchCase => '대소문자 구분';

  @override
  String get advancedRenameAllOccurrences => '모든 항목';

  @override
  String get advancedRenameScopeFormatting => '범위 및 서식';

  @override
  String get advancedRenameApplyChangesTo => '변경 적용 대상';

  @override
  String get advancedRenameFilename => '파일 이름';

  @override
  String get advancedRenameExtension => '확장자';

  @override
  String get advancedRenameBoth => '둘 다';

  @override
  String get advancedRenameCaseTransformation => '대소문자 변환';

  @override
  String get advancedRenameNoChange => '변경 없음';

  @override
  String get advancedRenameLowercase => '소문자';

  @override
  String get advancedRenameUppercase => '대문자';

  @override
  String get advancedRenameTitleCase => '제목 표기';

  @override
  String get advancedRenameCapitalize => '첫 글자 대문자';

  @override
  String get advancedRenameSequentialCounter => '순차 카운터';

  @override
  String get advancedRenameCounterDescription => '순서대로 번호를 앞이나 뒤에 추가합니다';

  @override
  String get advancedRenameSuffix => '접미사(끝)';

  @override
  String get advancedRenamePrefix => '접두사(시작)';

  @override
  String get advancedRenameStartAt => '시작 값';

  @override
  String get advancedRenameDigits => '자릿수';

  @override
  String get advancedRenameDigitsHint => '예: 2 (01)';

  @override
  String get advancedRenameSeparator => '구분 기호';

  @override
  String get advancedRenameSeparatorHint => '_ or -';

  @override
  String get advancedRenameLivePreview => '실시간 미리보기';

  @override
  String get advancedRenameDeselect => '선택 해제';

  @override
  String get advancedRenameSelectAll => '모두 선택';

  @override
  String get advancedRenameNoFilesSelected => '선택된 파일이 없습니다';

  @override
  String get advancedRenameNameConflictDetected => '이름 충돌이 감지됨';

  @override
  String get advancedRenameCheckPreviewToFix => '수정하려면 미리보기 탭을 확인하세요';

  @override
  String get advancedRenameReadyToRename => '이름 변경 준비 완료';

  @override
  String get advancedRenameErrorsDetected => '오류 감지됨';

  @override
  String advancedRenameApply(int count) {
    return '적용 ($count)';
  }

  @override
  String get advancedRenameNameCollisionWithinBatch => '배치 내 이름 충돌.';

  @override
  String get advancedRenameCollidesWithUnselectedFile => '선택하지 않은 파일과 충돌합니다.';

  @override
  String advancedRenameReadyCount(int valid, int total) {
    return '이름 변경 준비됨 $valid개(전체 $total개)';
  }

  @override
  String advancedRenameReadyOfTotal(int valid, int total) {
    return '$total개 중 $valid개 준비됨';
  }

  @override
  String advancedRenameRenamedItems(int succeeded, int failed) {
    return '$succeeded개 이름 변경됨($failed개 실패).';
  }

  @override
  String advancedRenameSuccessfullyRenamed(int count) {
    return '$count개 항목의 이름을 성공적으로 변경했습니다.';
  }

  @override
  String get advancedRenameMonthsFull =>
      '1월|2월|3월|4월|5월|6월|7월|8월|9월|10월|11월|12월';

  @override
  String get advancedRenameMonthsAbbr =>
      '1월|2월|3월|4월|5월|6월|7월|8월|9월|10월|11월|12월';

  @override
  String get advancedRenameDaysFull => '월요일|화요일|수요일|목요일|금요일|토요일|일요일';

  @override
  String get advancedRenameDaysAbbr => '월|화|수|목|금|토|일';

  @override
  String get advancedRenameResolveConflicts => '적용하기 전에 이름 충돌을 해결하세요';

  @override
  String advancedRenameChangedCount(int changed, int total) {
    return '$total개 중 $changed개';
  }

  @override
  String get automationKeyfilesPimSectionHeader => '키파일 및 PIM';

  @override
  String get automationKeyfilesPimDescription =>
      '위의 자동화 비밀번호와 함께 저장되며 UNLOCK_VAULT 호출에 동일하게 사용됩니다. 비밀번호만이 아니라 키파일 및/또는 기본값이 아닌 PIM으로 잠금 해제하는 VeraCrypt/LUKS 볼트용입니다.';

  @override
  String get automationSavePimButton => 'PIM 저장';

  @override
  String get automationCameraSectionHeader => '카메라 자동화';

  @override
  String get automationCameraDescription =>
      '자동화가 이 볼트에 대해 TAKE_PHOTO / START_RECORDING / STOP_RECORDING을 실행하도록 허용합니다. 전체 액세스에서도 기본적으로 꺼져 있습니다. 파일 가져오기/내보내기와 달리 사진 촬영은 화면 표시가 전혀 필요 없으므로 별도의 명시적 동의 항목입니다.';

  @override
  String get automationAllowCameraCapture => '카메라 캡처 허용';

  @override
  String get automationPimSavedMessage => 'PIM이 저장되었습니다';

  @override
  String get automationActionImportFolderLabel => '폴더 가져오기';

  @override
  String get automationActionExportFolderLabel => '폴더 내보내기';

  @override
  String get automationActionTakePhotoLabel => '사진 촬영';

  @override
  String get automationActionStartRecordingLabel => '녹화 시작';

  @override
  String get automationActionStopRecordingLabel => '녹화 중지';

  @override
  String get filePropertiesSectionHeader => '파일 속성';

  @override
  String get fullPathLabel => '전체 경로';

  @override
  String get sizeLabel => '크기';

  @override
  String get modifiedLabel => '수정됨';

  @override
  String get vaultLabel => '볼트';

  @override
  String get mediaDimensionsSectionHeader => '미디어 및 크기';

  @override
  String get resolutionLabel => '해상도';

  @override
  String get aspectRatioLabel => '화면 비율';

  @override
  String get formatLabel => '형식';

  @override
  String get exifCameraDataSectionHeader => 'EXIF 및 카메라 데이터';

  @override
  String get cameraLabel => '카메라';

  @override
  String get lensLabel => '렌즈';

  @override
  String get dateTakenLabel => '촬영 날짜';

  @override
  String get shutterSpeedLabel => '셔터 속도';

  @override
  String get apertureLabel => '조리개';

  @override
  String get isoLabel => 'ISO';

  @override
  String get focalLengthLabel => '초점 거리';

  @override
  String get flashLabel => '플래시';

  @override
  String get softwareLabel => '소프트웨어';

  @override
  String get gpsLocationLabel => 'GPS 위치';

  @override
  String get integrityChecksumSectionHeader => '무결성 및 체크섬';

  @override
  String get computingHashMessage => '해시 계산 중…';

  @override
  String get tapCalculateToVerifyMessage => '확인하려면 계산을 탭하세요';

  @override
  String get calculateButton => '계산';

  @override
  String get copyDiagnosticsButton => '진단 정보 복사';

  @override
  String get closeButton => '닫기';

  @override
  String get hwAcceleratedBadge => 'HW 가속';

  @override
  String get swDecoderBadge => 'SW 디코더';

  @override
  String get videoDecoderHardwareSection => '비디오 디코더 및 하드웨어';

  @override
  String get decoderNameLabel => '디코더 이름';

  @override
  String get accelerationLabel => '가속';

  @override
  String get hardwareGpuDirect => '하드웨어(GPU 다이렉트)';

  @override
  String get softwareCpuFallback => '소프트웨어(CPU 대체)';

  @override
  String get unknownValue => '알 수 없음';

  @override
  String get framerateLabel => '프레임 속도';

  @override
  String get variableOrUnknown => '가변/알 수 없음';

  @override
  String get videoCodecLabel => '비디오 코덱';

  @override
  String get autoDetected => '자동 감지됨';

  @override
  String get colorFormatLabel => '색상 형식';

  @override
  String get initLatencyLabel => '초기화 지연 시간';

  @override
  String get audioEngineSection => '오디오 엔진';

  @override
  String get audioDecoderLabel => '오디오 디코더';

  @override
  String get audioCodecLabel => '오디오 코덱';

  @override
  String get pipelineHealthSection => '파이프라인 및 상태';

  @override
  String get playbackStateLabel => '재생 상태';

  @override
  String get decryptedBufferLabel => '복호화된 버퍼';

  @override
  String secondsCached(String seconds) {
    return '$seconds초 캐시됨';
  }

  @override
  String get droppedFramesLabel => '드롭된 프레임';

  @override
  String nFrames(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '프레임 $count개',
    );
    return '$_temp0';
  }

  @override
  String get sourceStorageLabel => '원본 저장소';

  @override
  String directJniStreamSource(int volId) {
    return '직접 C++ JNI 스트림(volId=$volId)';
  }

  @override
  String get archivesTabLabel => '압축 파일';

  @override
  String get filesTabLabel => '파일';

  @override
  String get filesPermissionMessage => '기기의 파일을 탐색하려면 접근을 허용하세요.';

  @override
  String get filesEmptyTitle => '파일이 없습니다';

  @override
  String get filesEmptyMessage => '이 폴더는 비어 있습니다.';

  @override
  String get filesNewFolderTooltip => '새 폴더';

  @override
  String get filesNewFolderDialogTitle => '새 폴더';

  @override
  String get filesNameHint => '이름';

  @override
  String get filesCreate => '만들기';

  @override
  String get filesRename => '이름 변경';

  @override
  String get filesDelete => '삭제';

  @override
  String get filesShare => '공유';

  @override
  String get filesCopy => '복사';

  @override
  String get filesMove => '이동';

  @override
  String get filesDeleteConfirmTitle => '영구적으로 삭제할까요?';

  @override
  String get filesChooseDestinationTitle => '폴더 선택';

  @override
  String get filesMoveHere => '여기로 이동';

  @override
  String get filesCopyHere => '여기에 복사';

  @override
  String get filesSelectAllTooltip => '모두 선택';

  @override
  String get filesCloseSelectionTooltip => '닫기';

  @override
  String get filesFolderCreated => '폴더가 생성되었습니다';

  @override
  String get filesCreateFolderFailed => '폴더를 만들 수 없습니다';

  @override
  String get filesRenamed => '이름이 변경되었습니다';

  @override
  String get filesRenameFailed => '이름을 변경할 수 없습니다';

  @override
  String get filesNameAlreadyExists => '이미 사용 중인 이름입니다';

  @override
  String get filesDeleted => '삭제되었습니다';

  @override
  String get filesDeleteFailed => '삭제할 수 없습니다';

  @override
  String get filesMoved => '이동되었습니다';

  @override
  String get filesMoveFailed => '이동할 수 없습니다';

  @override
  String get filesCopied => '복사되었습니다';

  @override
  String get filesCopyFailed => '복사할 수 없습니다';

  @override
  String get filesOpenFailed => '이 파일을 열 수 없습니다';

  @override
  String get filesShareFailed => '이 파일을 공유할 수 없습니다';

  @override
  String get filesFilterTooltip => '필터';

  @override
  String get filesFilterAll => '모든 파일';

  @override
  String get filesFilterImages => '이미지';

  @override
  String get filesFilterVideos => '동영상';

  @override
  String get filesFilterAudio => '오디오';

  @override
  String get filesFilterDocuments => '문서';

  @override
  String get filesTextTooLarge => '이 파일은 너무 커서 여기서 미리 볼 수 없습니다.';

  @override
  String get filesTextSaved => '저장됨';

  @override
  String get filesTextSaveFailed => '저장할 수 없습니다';

  @override
  String get toolHeaderBackupTitle => '헤더 백업';

  @override
  String get toolHeaderBackupSubtitle => '컨테이너 헤더 및 볼트 설정 백업 또는 복원';

  @override
  String get headerBackupModeExport => '백업 저장';

  @override
  String get headerBackupModeRestore => '백업 복원';

  @override
  String get headerBackupPickExportTarget => '백업할 대상을 선택하세요.';

  @override
  String get headerBackupPickRestoreTarget => '백업을 복원할 대상을 선택하세요.';

  @override
  String get headerBackupTargetContainerSubtitle => 'VeraCrypt, LUKS1 또는 LUKS2';

  @override
  String get headerBackupTargetFolderSubtitle =>
      'gocryptfs, CryFS 또는 Cryptomator';

  @override
  String get headerBackupExportInfoBanner =>
      '컨테이너 헤더에는 핵심 키 자료가 포함되어 있습니다 — 불량 섹터나 쓰기 오류 등으로 이를 잃어버리면 온전한 데이터 영역조차 복구할 수 없습니다. 폴더 볼트도 루트의 작은 설정 파일에 동일한 정보를 보관합니다. 이 백업은 컨테이너 자체와 별도의 장소에 보관하세요.';

  @override
  String get headerBackupRestoreInfoBanner =>
      '복원하면 대상의 현재 헤더(또는 설정 파일)를 백업 파일로 덮어씁니다 — 백업이 해당 형식에 적합한지 먼저 검증하지만, 올바른 대상을 선택했는지 확인하세요.';

  @override
  String headerBackupUnhealthyExportWarning(String diagnosis) {
    return '이 컨테이너는 정상적인 상태가 아닙니다 ($diagnosis). 지금 백업하면 백업 파일에도 동일한 문제가 포함됩니다. 가능한 경우 먼저 확인 및 복구를 실행하세요 — 지금이 백업을 남길 수 있는 유일한 기회라면 그대로 진행하세요.';
  }

  @override
  String get headerBackupBackUpAnyway => '그래도 백업';

  @override
  String get headerBackupExportHeader => '헤더 내보내기';

  @override
  String get headerBackupSavedBanner => '백업이 저장되었습니다. 이 컨테이너와 분리된 곳에 보관하세요.';

  @override
  String get headerBackupSaveBackupFile => '백업 파일 저장';

  @override
  String get headerBackupPickBackupFile => '백업 파일 선택';

  @override
  String get headerBackupMismatchFolderVaultError =>
      '이 백업은 폴더 볼트용이지만 선택한 대상은 컨테이너 파일입니다.';

  @override
  String get headerBackupMismatchContainerFileError =>
      '이 백업은 컨테이너 파일용이지만 선택한 대상은 폴더 볼트입니다.';

  @override
  String get headerBackupRestoredSuccess => '헤더가 복원되었습니다.';

  @override
  String get headerBackupRestore => '복원';

  @override
  String headerBackupBackedUpAt(String date) {
    return '백업 일시: $date';
  }

  @override
  String get headerBackupLogIdle => '콘솔 로그 출력이 대기 상태입니다...';
}
