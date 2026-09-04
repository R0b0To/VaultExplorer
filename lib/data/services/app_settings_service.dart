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
export 'container_repository.dart'
    show ContainerRepository, ContainerRecord, ContainerUnlockMethod;
export 'package:vaultexplorer/data/models/delete_after_import_mode.dart';

const _secure = AppSecureStorage.instance;
const _kMasterHash = 'vc_master_hash_v2';
const _kMasterSalt = 'vc_master_salt_v2';

class AppSettings {
  bool useMasterPassword;
  bool masterPasswordIsFingerprint;
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
  String? _masterPasswordHash;
  String? _masterPasswordSalt;

  AppSettings({
    this.useMasterPassword = false,
    this.masterPasswordIsFingerprint = false,
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
    Map<String, String>? extensionPreferences,
    this._masterPasswordHash,
    this._masterPasswordSalt,
  })  : extensionPreferences = extensionPreferences ?? {};

  Axis get playlistScrollDirection => playlistScrollMode.axis;
  set playlistScrollDirection(Axis axis) {
    playlistScrollMode = axis == Axis.vertical
        ? PlaylistScrollMode.verticalPage
        : PlaylistScrollMode.horizontal;
  }

  String? get masterPasswordHash => _masterPasswordHash;
  String? get masterPasswordSalt => _masterPasswordSalt;

  void _setHashMaterial(String hash, String salt) {
    _masterPasswordHash = hash;
    _masterPasswordSalt = salt;
  }

  void _clearHashMaterial() {
    _masterPasswordHash = null;
    _masterPasswordSalt = null;
  }

  bool get needsHashUpgrade =>
      _masterPasswordHash != null &&
      (_masterPasswordSalt == null || _masterPasswordSalt!.isEmpty) &&
      _masterPasswordHash!.length == 8;

  AppSettings copyWith({
    bool? useMasterPassword,
    bool? masterPasswordIsFingerprint,
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
    SortBy? defaultFileSortBy,
    bool? defaultFileSortAscending,
    bool? htmlEnableJavaScript,
    PlaylistScrollMode? playlistScrollMode,
    Axis? playlistScrollDirection,
    String? languageCode,
    bool? debugLoggingEnabled,
    DeleteAfterImportMode? deleteAfterImportMode,
    bool? videoMuted,
  }) {
    return AppSettings(
      useMasterPassword: useMasterPassword ?? this.useMasterPassword,
      masterPasswordIsFingerprint: masterPasswordIsFingerprint ?? this.masterPasswordIsFingerprint,
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
      defaultFileSortBy: defaultFileSortBy ?? this.defaultFileSortBy,
      defaultFileSortAscending: defaultFileSortAscending ?? this.defaultFileSortAscending,
      htmlEnableJavaScript: htmlEnableJavaScript ?? this.htmlEnableJavaScript,
      playlistScrollMode: playlistScrollMode ??
          (playlistScrollDirection != null
              ? (playlistScrollDirection == Axis.vertical
                  ? PlaylistScrollMode.verticalPage
                  : PlaylistScrollMode.horizontal)
              : this.playlistScrollMode),
      languageCode: languageCode ?? this.languageCode,
      debugLoggingEnabled: debugLoggingEnabled ?? this.debugLoggingEnabled,
      deleteAfterImportMode: deleteAfterImportMode ?? this.deleteAfterImportMode,
      videoMuted: videoMuted ?? this.videoMuted,
    );
  }

  Map<String, dynamic> toJson() => {
    'useMasterPassword': useMasterPassword,
    'masterPasswordIsFingerprint': masterPasswordIsFingerprint,
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
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    useMasterPassword: j['useMasterPassword'] as bool? ?? false,
    masterPasswordIsFingerprint: j['masterPasswordIsFingerprint'] as bool? ?? false,
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
  );
}

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
    await _secure.delete(key: _kMasterHash);
    await _secure.delete(key: _kMasterSalt);
    await saveSettings(settings);
  }

}