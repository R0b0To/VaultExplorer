import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/delete_after_import_mode.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';
export 'container_repository.dart'
    show ContainerRepository, ContainerRecord, ContainerUnlockMethod;
export 'package:vaultexplorer/data/models/delete_after_import_mode.dart';

part 'app_settings_service.g.dart';

const _secure = AppSecureStorage.instance;
const _kMasterHash = 'vc_master_hash_v2';
const _kMasterSalt = 'vc_master_salt_v2';
const _kMasterPatternHash = 'vc_master_pattern_hash_v1';
const _kMasterPinHash = 'vc_master_pin_hash_v1';

/// How the app-wide lock gate ([LockGateScreen]) accepts unlock input.
///
/// The real master password (hashed via [AppSettings.masterPasswordHash])
/// stays the security root no matter which method is active here -- it's
/// always required to *enable* the gate in the first place, and it's what
/// [AppSettingsScreen]'s "remove master password" flow re-verifies against.
/// [pattern]/[pin]/[biometrics] are quick-unlock shortcuts layered on top,
/// mirroring [ContainerUnlockMethod.biometrics]'s relationship to a vault's
/// real password: a correct pattern/PIN/biometric grants access to the app
/// without the master password ever being re-typed, exactly like a correct
/// fingerprint already did for [masterPasswordIsFingerprint] before this
/// enum replaced it.
enum MasterUnlockMethod {
  password,
  biometrics,
  pattern,
  pin;

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
    MasterUnlockMethod.password => l10n.unlockMethodManualPassword,
    MasterUnlockMethod.biometrics => l10n.unlockMethodBiometrics,
    MasterUnlockMethod.pattern => l10n.unlockMethodPattern,
    MasterUnlockMethod.pin => l10n.unlockMethodPin,
  };

  String getLocalizedSubtitle(AppLocalizations l10n) => switch (this) {
    MasterUnlockMethod.password => l10n.unlockMethodSubtitlePassword,
    MasterUnlockMethod.biometrics => l10n.unlockMethodSubtitleBiometrics,
    MasterUnlockMethod.pattern => l10n.unlockMethodSubtitlePattern,
    MasterUnlockMethod.pin => l10n.unlockMethodSubtitlePin,
  };

  IconData get icon => switch (this) {
    MasterUnlockMethod.password => Icons.key_rounded,
    MasterUnlockMethod.biometrics => Icons.fingerprint,
    MasterUnlockMethod.pattern => Icons.pattern,
    MasterUnlockMethod.pin => Icons.dialpad_rounded,
  };

  String toJson() => name;
  static MasterUnlockMethod fromJson(String? value) => switch (value) {
    'password' => MasterUnlockMethod.password,
    'biometrics' => MasterUnlockMethod.biometrics,
    'pattern' => MasterUnlockMethod.pattern,
    'pin' => MasterUnlockMethod.pin,
    _ => MasterUnlockMethod.password,
  };
}

class AppSettings {
  bool useMasterPassword;
  MasterUnlockMethod masterUnlockMethod;
  bool defaultDocumentProvider;
  bool videoAutoPlay;
  bool blockScreenshots;
  bool keepVaultsRunningInBackground;
  bool defaultDerivedKeyCacheEnabled;
  bool lockContainersOnScreenLock;
  int autoLockMins;
  bool hasSeenSwipeTutorial;
  ContainerSortMode containerSortMode;
  bool swapCardActions;
  ThemeMode themeMode;
  bool useDynamicColor;
  bool useOledBlackTheme;
  BrowserLayoutMode defaultLayoutMode;
  Map<String, String> extensionPreferences;
  bool autoOpenOnUnlock;
  SortBy defaultFileSortBy;
  bool defaultFileSortAscending;
  bool htmlEnableJavaScript;
  PlaylistScrollMode playlistScrollMode;
  String? languageCode;
  bool debugLoggingEnabled;
  DeleteAfterImportMode deleteAfterImportMode;
  bool videoMuted;

  /// Whether [LocalStorageCard] is pinned to the top of the vault
  /// dashboard, opening the same [FileBrowserScreen] used for an unlocked
  /// vault but pointed at real device storage (see
  /// [buildLocalStorageContainer]) -- letting a cut/copy in an open vault
  /// be pasted straight into device storage (or vice versa) through
  /// [CrossContainerClipboard] instead of an OS document-picker round
  /// trip. Meaningless without all-files access, so the dashboard also
  /// gates on a live [VaultLifecycleApi.hasAllFilesAccess] check -- this
  /// flag alone only tracks the user's preference, and is deliberately
  /// left untouched if access is later revoked so the card silently
  /// reappears if access is re-granted, without the user needing to
  /// toggle this back on.
  bool showLocalStorageCard;
  String? _masterPasswordHash;
  String? _masterPasswordSalt;
  String? _masterPatternHash;
  String? _masterPinHash;

  AppSettings({
    this.useMasterPassword = false,
    this.masterUnlockMethod = MasterUnlockMethod.password,
    this.defaultDocumentProvider = false,
    this.videoAutoPlay = true,
    this.blockScreenshots = false,
    this.keepVaultsRunningInBackground = false,
    this.hasSeenSwipeTutorial = false,
    this.lockContainersOnScreenLock = true,
    this.defaultDerivedKeyCacheEnabled = false,
    this.autoLockMins = 0,
    this.defaultLayoutMode = BrowserLayoutMode.list,
    this.containerSortMode = ContainerSortMode.manual,
    this.swapCardActions = false,
    this.themeMode = ThemeMode.system,
    this.useDynamicColor = false,
    this.useOledBlackTheme = false,
    this.autoOpenOnUnlock = false,
    this.defaultFileSortBy = SortBy.name,
    this.defaultFileSortAscending = true,
    this.htmlEnableJavaScript = false,
    this.playlistScrollMode = PlaylistScrollMode.horizontal,
    this.languageCode,
    this.debugLoggingEnabled = false,
    this.deleteAfterImportMode = DeleteAfterImportMode.ask,
    this.videoMuted = false,
    this.showLocalStorageCard = false,
    Map<String, String>? extensionPreferences,
    this._masterPasswordHash,
    this._masterPasswordSalt,
    this._masterPatternHash,
    this._masterPinHash,
  })  : extensionPreferences = extensionPreferences ?? {};

  Axis get playlistScrollDirection => playlistScrollMode.axis;
  set playlistScrollDirection(Axis axis) {
    playlistScrollMode = axis == Axis.vertical
        ? PlaylistScrollMode.verticalPage
        : PlaylistScrollMode.horizontal;
  }

  String? get masterPasswordHash => _masterPasswordHash;
  String? get masterPasswordSalt => _masterPasswordSalt;
  String? get masterPatternHash => _masterPatternHash;
  String? get masterPinHash => _masterPinHash;

  void _setHashMaterial(String hash, String salt) {
    _masterPasswordHash = hash;
    _masterPasswordSalt = salt;
  }

  void _clearHashMaterial() {
    _masterPasswordHash = null;
    _masterPasswordSalt = null;
  }

  void _setPatternHash(String hash) => _masterPatternHash = hash;
  void _clearPatternHash() => _masterPatternHash = null;
  void _setPinHash(String hash) => _masterPinHash = hash;
  void _clearPinHash() => _masterPinHash = null;

  bool get needsHashUpgrade =>
      _masterPasswordHash != null &&
      (_masterPasswordSalt == null || _masterPasswordSalt!.isEmpty) &&
      _masterPasswordHash!.length == 8;

  AppSettings copyWith({
    bool? useMasterPassword,
    MasterUnlockMethod? masterUnlockMethod,
    bool? defaultDocumentProvider,
    bool? videoAutoPlay,
    bool? blockScreenshots,
    bool? keepVaultsRunningInBackground,
    bool? defaultDerivedKeyCacheEnabled,
    bool? lockContainersOnScreenLock,
    int? autoLockMins,
    bool? hasSeenSwipeTutorial,
    ContainerSortMode? containerSortMode,
    bool? swapCardActions,
    ThemeMode? themeMode,
    bool? useDynamicColor,
    bool? useOledBlackTheme,
    BrowserLayoutMode? defaultLayoutMode,
    Map<String, String>? extensionPreferences,
    bool? autoOpenOnUnlock,
    String? masterPasswordHash,
    String? masterPasswordSalt,
    String? masterPatternHash,
    String? masterPinHash,
    SortBy? defaultFileSortBy,
    bool? defaultFileSortAscending,
    bool? htmlEnableJavaScript,
    PlaylistScrollMode? playlistScrollMode,
    Axis? playlistScrollDirection,
    String? languageCode,
    bool clearLanguageCode = false,
    bool? debugLoggingEnabled,
    DeleteAfterImportMode? deleteAfterImportMode,
    bool? videoMuted,
    bool? showLocalStorageCard,
  }) {
    return AppSettings(
      useMasterPassword: useMasterPassword ?? this.useMasterPassword,
      masterUnlockMethod: masterUnlockMethod ?? this.masterUnlockMethod,
      defaultDocumentProvider: defaultDocumentProvider ?? this.defaultDocumentProvider,
      videoAutoPlay: videoAutoPlay ?? this.videoAutoPlay,
      blockScreenshots: blockScreenshots ?? this.blockScreenshots,
      keepVaultsRunningInBackground: keepVaultsRunningInBackground ?? this.keepVaultsRunningInBackground,
      defaultDerivedKeyCacheEnabled: defaultDerivedKeyCacheEnabled ?? this.defaultDerivedKeyCacheEnabled,
      lockContainersOnScreenLock: lockContainersOnScreenLock ?? this.lockContainersOnScreenLock,
      autoLockMins: autoLockMins ?? this.autoLockMins,
      hasSeenSwipeTutorial: hasSeenSwipeTutorial ?? this.hasSeenSwipeTutorial,
      defaultLayoutMode: defaultLayoutMode ?? this.defaultLayoutMode,
      containerSortMode: containerSortMode ?? this.containerSortMode,
      swapCardActions: swapCardActions ?? this.swapCardActions,
      themeMode: themeMode ?? this.themeMode,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      useOledBlackTheme: useOledBlackTheme ?? this.useOledBlackTheme,
      extensionPreferences: extensionPreferences ?? this.extensionPreferences,
      autoOpenOnUnlock: autoOpenOnUnlock ?? this.autoOpenOnUnlock,
      masterPasswordHash: masterPasswordHash ?? _masterPasswordHash,
      masterPasswordSalt: masterPasswordSalt ?? _masterPasswordSalt,
      masterPatternHash: masterPatternHash ?? _masterPatternHash,
      masterPinHash: masterPinHash ?? _masterPinHash,
      defaultFileSortBy: defaultFileSortBy ?? this.defaultFileSortBy,
      defaultFileSortAscending: defaultFileSortAscending ?? this.defaultFileSortAscending,
      htmlEnableJavaScript: htmlEnableJavaScript ?? this.htmlEnableJavaScript,
      playlistScrollMode: playlistScrollMode ??
          (playlistScrollDirection != null
              ? (playlistScrollDirection == Axis.vertical
                  ? PlaylistScrollMode.verticalPage
                  : PlaylistScrollMode.horizontal)
              : this.playlistScrollMode),
      languageCode: clearLanguageCode
          ? null
          : (languageCode ?? this.languageCode),
      debugLoggingEnabled: debugLoggingEnabled ?? this.debugLoggingEnabled,
      deleteAfterImportMode: deleteAfterImportMode ?? this.deleteAfterImportMode,
      videoMuted: videoMuted ?? this.videoMuted,
      showLocalStorageCard: showLocalStorageCard ?? this.showLocalStorageCard,
    );
  }

  Map<String, dynamic> toJson() => {
    'useMasterPassword': useMasterPassword,
    'masterUnlockMethod': masterUnlockMethod.toJson(),
    'defaultDocumentProvider': defaultDocumentProvider,
    'videoAutoPlay': videoAutoPlay,
    'blockScreenshots': blockScreenshots,
    'keepVaultsRunningInBackground': keepVaultsRunningInBackground,
    'defaultDerivedKeyCacheEnabled': defaultDerivedKeyCacheEnabled,
    'lockContainersOnScreenLock': lockContainersOnScreenLock,
    'autoLockMins': autoLockMins,
    'hasSeenSwipeTutorial': hasSeenSwipeTutorial,
    'defaultLayoutMode': defaultLayoutMode.toJson(),
    'containerSortMode': containerSortMode.toJson(),
    'swapCardActions': swapCardActions,
    'themeMode': themeMode.index,
    'useDynamicColor': useDynamicColor,
    'useOledBlackTheme': useOledBlackTheme,
    'extensionPreferences': extensionPreferences,
    'autoOpenOnUnlock': autoOpenOnUnlock,
    'defaultFileSortBy': defaultFileSortBy.toJson(),
    'defaultFileSortAscending': defaultFileSortAscending,
    'htmlEnableJavaScript': htmlEnableJavaScript,
    'playlistScrollMode': playlistScrollMode.toJson(),
    'playlistScrollDirection': playlistScrollMode == PlaylistScrollMode.verticalPage
        ? 'vertical'
        : (playlistScrollMode == PlaylistScrollMode.verticalContinuous
            ? 'verticalContinuous'
            : 'horizontal'),
    'languageCode': languageCode,
    'debugLoggingEnabled': debugLoggingEnabled,
    'deleteAfterImportMode': deleteAfterImportMode.toJson(),
    'videoMuted': videoMuted,
    'showLocalStorageCard': showLocalStorageCard,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    useMasterPassword: j['useMasterPassword'] as bool? ?? false,
    // Migrates pre-existing installs: the boolean this replaced only ever
    // meant "biometrics"; a settings file with no 'masterUnlockMethod' key
    // yet is always from before pattern/PIN quick-unlock existed.
    masterUnlockMethod: j['masterUnlockMethod'] != null
        ? MasterUnlockMethod.fromJson(j['masterUnlockMethod'] as String?)
        : (j['masterPasswordIsFingerprint'] as bool? ?? false)
            ? MasterUnlockMethod.biometrics
            : MasterUnlockMethod.password,
    defaultDocumentProvider: j['defaultDocumentProvider'] as bool? ?? false,
    videoAutoPlay: j['videoAutoPlay'] as bool? ?? true,
    blockScreenshots: j['blockScreenshots'] as bool? ?? false,
    keepVaultsRunningInBackground: j['keepVaultsRunningInBackground'] as bool? ?? false,
    hasSeenSwipeTutorial: j['hasSeenSwipeTutorial'] as bool? ?? false,
    defaultDerivedKeyCacheEnabled: j['defaultDerivedKeyCacheEnabled'] as bool? ?? false,
    containerSortMode: ContainerSortMode.fromJson(j['containerSortMode'] as String?),
    swapCardActions: j['swapCardActions'] as bool? ?? false,
    themeMode: j['themeMode'] != null ? ThemeMode.values[j['themeMode'] as int] : ThemeMode.system,
    useDynamicColor: j['useDynamicColor'] as bool? ?? false,
    useOledBlackTheme: j['useOledBlackTheme'] as bool? ?? false,
    lockContainersOnScreenLock: j['lockContainersOnScreenLock'] as bool? ?? true,
    autoLockMins: j['autoLockMins'] as int? ?? 0,
    defaultLayoutMode:
        BrowserLayoutMode.fromJson(
          j['defaultLayoutMode'] as String?,
        ) ??
        BrowserLayoutMode.list,
    extensionPreferences:
        (j['extensionPreferences'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as String),
        ) ??
        {},
    autoOpenOnUnlock: j['autoOpenOnUnlock'] as bool? ?? false,
    defaultFileSortBy: SortBy.fromJson(j['defaultFileSortBy'] as String?),
    defaultFileSortAscending: j['defaultFileSortAscending'] as bool? ?? true,
    htmlEnableJavaScript: j['htmlEnableJavaScript'] as bool? ?? false,
    playlistScrollMode: PlaylistScrollMode.fromJson(
      j['playlistScrollMode'] as String? ?? j['playlistScrollDirection'] as String?,
    ),
    languageCode: j['languageCode'] as String?,
    debugLoggingEnabled: j['debugLoggingEnabled'] as bool? ?? false,
    deleteAfterImportMode: DeleteAfterImportMode.fromJson(
      j['deleteAfterImportMode'] as String?,
    ),
    videoMuted: j['videoMuted'] as bool? ?? false,
    showLocalStorageCard: j['showLocalStorageCard'] as bool? ?? false,
  );
}

@Riverpod(keepAlive: true)
AppSettingsService appSettingsService(Ref ref) => const AppSettingsService();

class AppSettingsService {
  const AppSettingsService();

  static Future<File> get _settingsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_settings.json');
  }

  Future<AppSettings> loadSettings() async {
    AppSettings settings;
    try {
      final file = await _settingsFile;
      if (await file.exists()) {
        final raw =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        settings = AppSettings.fromJson(raw);
      } else {
        settings = AppSettings();
      }
    } catch (_) {
      settings = AppSettings();
    }
    if (settings.useMasterPassword) {
      final hash = await _secure.read(key: _kMasterHash);
      final salt = await _secure.read(key: _kMasterSalt) ?? '';
      if (hash != null) {
        settings._setHashMaterial(hash, salt);
      }
      // Only the active quick-unlock method's hash is ever loaded, mirroring
      // ContainerRepository's per-uri pattern/PIN loading: the other method's
      // material (if any lingers from a prior switch) is simply never read.
      switch (settings.masterUnlockMethod) {
        case MasterUnlockMethod.pattern:
          final patternHash = await _secure.read(key: _kMasterPatternHash);
          if (patternHash != null) settings._setPatternHash(patternHash);
        case MasterUnlockMethod.pin:
          final pinHash = await _secure.read(key: _kMasterPinHash);
          if (pinHash != null) settings._setPinHash(pinHash);
        case MasterUnlockMethod.password:
        case MasterUnlockMethod.biometrics:
          break;
      }
    }
    return settings;
  }

  Future<void> saveSettings(AppSettings settings) async {
    try {
      final file = await _settingsFile;
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {
      // Same reasoning as FileManagerToolbarService.save(): the caller's
      // in-memory settings object already reflects the change for this
      // session; a failed write only risks it not surviving a restart.
    }
  }

  Future<void> saveMasterPassword(
    AppSettings settings,
    String hash,
    String salt,
  ) async {
    settings._setHashMaterial(hash, salt);
    await _secure.write(key: _kMasterHash, value: hash);
    await _secure.write(key: _kMasterSalt, value: salt);
    await saveSettings(settings);
  }

  Future<void> clearMasterPassword(AppSettings settings) async {
    settings._clearHashMaterial();
    settings._clearPatternHash();
    settings._clearPinHash();
    settings.masterUnlockMethod = MasterUnlockMethod.password;
    await _secure.delete(key: _kMasterHash);
    await _secure.delete(key: _kMasterSalt);
    await _secure.delete(key: _kMasterPatternHash);
    await _secure.delete(key: _kMasterPinHash);
    await saveSettings(settings);
  }

  /// Persists a new master-gate unlock pattern and makes it the active
  /// [MasterUnlockMethod], the same way drawing a pattern for a vault makes
  /// [ContainerUnlockMethod.pattern] that container's method.
  Future<void> saveMasterPattern(AppSettings settings, String hash) async {
    settings._setPatternHash(hash);
    settings.masterUnlockMethod = MasterUnlockMethod.pattern;
    await _secure.write(key: _kMasterPatternHash, value: hash);
    await saveSettings(settings);
  }

  Future<void> clearMasterPattern(AppSettings settings) async {
    settings._clearPatternHash();
    await _secure.delete(key: _kMasterPatternHash);
    await saveSettings(settings);
  }

  /// Persists a new master-gate unlock PIN and makes it the active
  /// [MasterUnlockMethod], mirroring [saveMasterPattern].
  Future<void> saveMasterPin(AppSettings settings, String hash) async {
    settings._setPinHash(hash);
    settings.masterUnlockMethod = MasterUnlockMethod.pin;
    await _secure.write(key: _kMasterPinHash, value: hash);
    await saveSettings(settings);
  }

  Future<void> clearMasterPin(AppSettings settings) async {
    settings._clearPinHash();
    await _secure.delete(key: _kMasterPinHash);
    await saveSettings(settings);
  }

  /// Switches which method the lock gate shows first, without touching any
  /// stored hash. The caller is responsible for clearing the outgoing
  /// method's stored hash first (via [clearMasterPattern]/[clearMasterPin])
  /// if it's being abandoned rather than kept for a later switch-back.
  Future<void> setMasterUnlockMethod(
    AppSettings settings,
    MasterUnlockMethod method,
  ) async {
    settings.masterUnlockMethod = method;
    await saveSettings(settings);
  }
}