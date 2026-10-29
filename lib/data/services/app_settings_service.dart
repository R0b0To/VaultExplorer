import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/tab_swipe_gestures.dart';
import 'package:vaultexplorer/data/models/app_skin_preset.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/audio_recording_quality.dart';
import 'package:vaultexplorer/data/models/delete_after_import_mode.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/data/models/playlist_scroll_mode.dart';
import 'package:vaultexplorer/data/models/video_playback_mode.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';
export 'container_repository.dart'
    show ContainerRepository, ContainerRecord, ContainerUnlockMethod;
export 'package:vaultexplorer/data/models/audio_recording_quality.dart';
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
enum AuthenticatorSearchPlacement {
  bottom,
  top;

  String toJson() => name;
  static AuthenticatorSearchPlacement fromJson(String? value) =>
      switch (value) {
        'top' => AuthenticatorSearchPlacement.top,
        _ => AuthenticatorSearchPlacement.bottom,
      };
}

enum QuickActionLockMode {
  leaveAsFound,
  alwaysLock,
  leaveOpen;

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
    QuickActionLockMode.leaveAsFound =>
      l10n.quickActionLockModeLeaveAsFoundLabel,
    QuickActionLockMode.alwaysLock => l10n.quickActionLockModeAlwaysLockLabel,
    QuickActionLockMode.leaveOpen => l10n.quickActionLockModeLeaveOpenLabel,
  };

  String getLocalizedSubtitle(AppLocalizations l10n) => switch (this) {
    QuickActionLockMode.leaveAsFound =>
      l10n.quickActionLockModeLeaveAsFoundSubtitle,
    QuickActionLockMode.alwaysLock =>
      l10n.quickActionLockModeAlwaysLockSubtitle,
    QuickActionLockMode.leaveOpen => l10n.quickActionLockModeLeaveOpenSubtitle,
  };

  String toJson() => name;
  static QuickActionLockMode fromJson(String? value) => switch (value) {
    'alwaysLock' => QuickActionLockMode.alwaysLock,
    'leaveOpen' => QuickActionLockMode.leaveOpen,
    _ => QuickActionLockMode.leaveAsFound,
  };
}

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
  // When true, autoLockMins is ignored for vault auto-lock -- there's no
  // inactivity timer at all (foreground or away-duration-based); the vault
  // only locks on a genuine screen-off/device-lock signal, and explicitly
  // NOT on plain app backgrounding (switching to another app while the
  // screen stays on). Distinct from autoLockMins == 0 ("Immediately"),
  // which locks on both. Mutually exclusive with a positive autoLockMins by
  // construction (the picker only ever sets one at a time) -- see
  // SessionLockController's use of this flag in _scheduleVaultLockTimer,
  // handleScreenOff, and handleAppLifecycleState.
  bool autoLockScreenLockOnly;
  // App-lock behavior below (lockAppOnScreenLock/appLockAfterMins) is
  // intentionally separate from vault auto-lock above
  // (lockContainersOnScreenLock/autoLockMins). Vault auto-lock unmounts
  // open containers -- expensive to reverse (re-decrypt). App lock only
  // re-shows LockGateScreen -- cheap to reverse -- so a container can stay
  // mounted in the background while the app still asks for the master
  // password again, or vice versa. See SessionLockController.
  bool lockAppOnScreenLock;
  int appLockAfterMins;
  bool appLockScreenLockOnly;
  ContainerSortMode containerSortMode;
  ThemeMode themeMode;
  bool useDynamicColor;
  bool useOledBlackTheme;
  BrowserLayoutMode defaultLayoutMode;
  bool useBrowserTabs;
  bool useDualPaneBrowsing;
  TabSwipeGestures tabSwipeGestures;
  bool appBarAtBottom;
  Map<String, String> extensionPreferences;
  bool autoOpenOnUnlock;
  SortBy defaultFileSortBy;
  bool defaultFileSortAscending;
  bool htmlEnableJavaScript;
  PlaylistScrollMode playlistScrollMode;
  String? languageCode;
  bool debugLoggingEnabled;
  DeleteAfterImportMode deleteAfterImportMode;
  AudioRecordingQuality audioRecordingQuality;
  bool videoMuted;
  VideoPlaybackMode videoPlaybackMode;
  bool showStorageLocationsInDrawer;
  bool autoLockOnShareImport;
  QuickActionLockMode quickActionLockMode;
  bool enableAuthenticator;
  bool authenticatorShowNumbers;
  AuthenticatorSearchPlacement authenticatorSearchPlacement;
  AppSkinPreset appSkinPreset;
  CustomAppSkin customAppSkin;
  List<CustomAppSkin> customAppSkins;
  FileManagerSkin fileManagerSkin;
  bool fileManagerFollowsAppSkin;
  bool editorFollowsAppSkin;
  Map<String, dynamic> editorAppearancePrefs;
  int appSkinSchemaVersion;
  String? _masterPasswordHash;
  String? _masterPasswordSalt;
  String? _masterPatternHash;
  String? _masterPinHash;

  AppSettings({
    this.useMasterPassword = false,
    this.masterUnlockMethod = MasterUnlockMethod.password,
    this.defaultDocumentProvider = false,
    this.videoAutoPlay = true,
    this.blockScreenshots = true,
    this.keepVaultsRunningInBackground = false,
    this.lockContainersOnScreenLock = true,
    this.defaultDerivedKeyCacheEnabled = false,
    this.autoLockMins = 0,
    this.autoLockScreenLockOnly = false,
    this.lockAppOnScreenLock = true,
    this.appLockAfterMins = 0,
    this.appLockScreenLockOnly = false,
    this.defaultLayoutMode = BrowserLayoutMode.detailed,
    this.useBrowserTabs = true,
    this.useDualPaneBrowsing = false,
    this.tabSwipeGestures = const TabSwipeGestures(),
    this.appBarAtBottom = false,
    this.containerSortMode = ContainerSortMode.manual,
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
    this.audioRecordingQuality = AudioRecordingQuality.defaultQuality,
    this.videoMuted = false,
    this.videoPlaybackMode = VideoPlaybackMode.playOnce,
    this.showStorageLocationsInDrawer = true,
    this.autoLockOnShareImport = true,
    this.quickActionLockMode = QuickActionLockMode.leaveAsFound,
    this.enableAuthenticator = true,
    this.authenticatorShowNumbers = true,
    this.authenticatorSearchPlacement = AuthenticatorSearchPlacement.bottom,
    this.appSkinPreset = AppSkinPreset.defaultSkin,
    this.customAppSkin = const CustomAppSkin(),
    this.customAppSkins = const [],
    this.fileManagerSkin = FileManagerSkin.classic,
    this.fileManagerFollowsAppSkin = true,
    this.editorFollowsAppSkin = true,
    Map<String, dynamic>? editorAppearancePrefs,
    this.appSkinSchemaVersion = 1,
    Map<String, String>? extensionPreferences,
    this._masterPasswordHash,
    this._masterPasswordSalt,
    this._masterPatternHash,
    this._masterPinHash,
  }) : extensionPreferences = extensionPreferences ?? {},
       editorAppearancePrefs = editorAppearancePrefs ?? {};

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
    bool? autoLockScreenLockOnly,
    bool? lockAppOnScreenLock,
    int? appLockAfterMins,
    bool? appLockScreenLockOnly,
    ContainerSortMode? containerSortMode,
    ThemeMode? themeMode,
    bool? useDynamicColor,
    bool? useOledBlackTheme,
    BrowserLayoutMode? defaultLayoutMode,
    bool? useBrowserTabs,
    bool? useDualPaneBrowsing,
    TabSwipeGestures? tabSwipeGestures,
    bool? appBarAtBottom,
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
    AudioRecordingQuality? audioRecordingQuality,
    bool? videoMuted,
    VideoPlaybackMode? videoPlaybackMode,
    bool? showStorageLocationsInDrawer,
    bool? autoLockOnShareImport,
    QuickActionLockMode? quickActionLockMode,
    bool? enableAuthenticator,
    bool? authenticatorShowNumbers,
    AuthenticatorSearchPlacement? authenticatorSearchPlacement,
    AppSkinPreset? appSkinPreset,
    CustomAppSkin? customAppSkin,
    List<CustomAppSkin>? customAppSkins,
    FileManagerSkin? fileManagerSkin,
    bool? fileManagerFollowsAppSkin,
    bool? editorFollowsAppSkin,
    Map<String, dynamic>? editorAppearancePrefs,
    int? appSkinSchemaVersion,
  }) {
    return AppSettings(
      useMasterPassword: useMasterPassword ?? this.useMasterPassword,
      masterUnlockMethod: masterUnlockMethod ?? this.masterUnlockMethod,
      defaultDocumentProvider:
          defaultDocumentProvider ?? this.defaultDocumentProvider,
      videoAutoPlay: videoAutoPlay ?? this.videoAutoPlay,
      blockScreenshots: blockScreenshots ?? this.blockScreenshots,
      keepVaultsRunningInBackground:
          keepVaultsRunningInBackground ?? this.keepVaultsRunningInBackground,
      defaultDerivedKeyCacheEnabled:
          defaultDerivedKeyCacheEnabled ?? this.defaultDerivedKeyCacheEnabled,
      lockContainersOnScreenLock:
          lockContainersOnScreenLock ?? this.lockContainersOnScreenLock,
      autoLockMins: autoLockMins ?? this.autoLockMins,
      autoLockScreenLockOnly:
          autoLockScreenLockOnly ?? this.autoLockScreenLockOnly,
      lockAppOnScreenLock: lockAppOnScreenLock ?? this.lockAppOnScreenLock,
      appLockAfterMins: appLockAfterMins ?? this.appLockAfterMins,
      appLockScreenLockOnly:
          appLockScreenLockOnly ?? this.appLockScreenLockOnly,
      defaultLayoutMode: defaultLayoutMode ?? this.defaultLayoutMode,
      useBrowserTabs: useBrowserTabs ?? this.useBrowserTabs,
      useDualPaneBrowsing: useDualPaneBrowsing ?? this.useDualPaneBrowsing,
      tabSwipeGestures: tabSwipeGestures ?? this.tabSwipeGestures,
      appBarAtBottom: appBarAtBottom ?? this.appBarAtBottom,
      containerSortMode: containerSortMode ?? this.containerSortMode,
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
      defaultFileSortAscending:
          defaultFileSortAscending ?? this.defaultFileSortAscending,
      htmlEnableJavaScript: htmlEnableJavaScript ?? this.htmlEnableJavaScript,
      playlistScrollMode:
          playlistScrollMode ??
          (playlistScrollDirection != null
              ? (playlistScrollDirection == Axis.vertical
                    ? PlaylistScrollMode.verticalPage
                    : PlaylistScrollMode.horizontal)
              : this.playlistScrollMode),
      languageCode: clearLanguageCode
          ? null
          : (languageCode ?? this.languageCode),
      debugLoggingEnabled: debugLoggingEnabled ?? this.debugLoggingEnabled,
      deleteAfterImportMode:
          deleteAfterImportMode ?? this.deleteAfterImportMode,
      audioRecordingQuality:
          audioRecordingQuality ?? this.audioRecordingQuality,
      videoMuted: videoMuted ?? this.videoMuted,
      videoPlaybackMode: videoPlaybackMode ?? this.videoPlaybackMode,
      showStorageLocationsInDrawer:
          showStorageLocationsInDrawer ?? this.showStorageLocationsInDrawer,
      autoLockOnShareImport:
          autoLockOnShareImport ??
          (quickActionLockMode != null
              ? quickActionLockMode != QuickActionLockMode.leaveOpen
              : this.autoLockOnShareImport),
      quickActionLockMode: quickActionLockMode ?? this.quickActionLockMode,
      enableAuthenticator: enableAuthenticator ?? this.enableAuthenticator,
      authenticatorShowNumbers:
          authenticatorShowNumbers ?? this.authenticatorShowNumbers,
      authenticatorSearchPlacement:
          authenticatorSearchPlacement ?? this.authenticatorSearchPlacement,
      appSkinPreset: appSkinPreset ?? this.appSkinPreset,
      customAppSkin: customAppSkin ?? this.customAppSkin,
      customAppSkins: customAppSkins ?? this.customAppSkins,
      fileManagerSkin: fileManagerSkin ?? this.fileManagerSkin,
      fileManagerFollowsAppSkin:
          fileManagerFollowsAppSkin ?? this.fileManagerFollowsAppSkin,
      editorFollowsAppSkin: editorFollowsAppSkin ?? this.editorFollowsAppSkin,
      editorAppearancePrefs:
          editorAppearancePrefs ?? this.editorAppearancePrefs,
      appSkinSchemaVersion: appSkinSchemaVersion ?? this.appSkinSchemaVersion,
    );
  }

  /// Every persisted field is in exactly one of the three groups below, so a
  /// new setting has to be classified when it is added:
  ///
  /// * [configurationToJson] -- how the app *behaves* (locks, defaults,
  ///   playback/import handling, language). Travels with Settings -> Export.
  /// * [interfaceToJson] -- how the app *looks and is laid out* (theme mode,
  ///   view modes, editor appearance, ...). Travels with both Settings ->
  ///   Export and App skin -> Export ("Skins and interface").
  /// * [skinsToJson] -- the skin library and which skin is active. Owned by
  ///   the App skin screens; Settings -> Export includes the library only
  ///   when asked to.
  Map<String, dynamic> toJson() => {
    ...configurationToJson(),
    ...interfaceToJson(),
    ...skinsToJson(),
  };

  /// Behavior, security and defaults. Never contains the master-password,
  /// pattern or PIN hashes (they live in their own secure-storage keys).
  Map<String, dynamic> configurationToJson() => {
    'useMasterPassword': useMasterPassword,
    'masterUnlockMethod': masterUnlockMethod.toJson(),
    'defaultDocumentProvider': defaultDocumentProvider,
    'videoAutoPlay': videoAutoPlay,
    'blockScreenshots': blockScreenshots,
    'keepVaultsRunningInBackground': keepVaultsRunningInBackground,
    'defaultDerivedKeyCacheEnabled': defaultDerivedKeyCacheEnabled,
    'lockContainersOnScreenLock': lockContainersOnScreenLock,
    'autoLockMins': autoLockMins,
    'autoLockScreenLockOnly': autoLockScreenLockOnly,
    'lockAppOnScreenLock': lockAppOnScreenLock,
    'appLockAfterMins': appLockAfterMins,
    'appLockScreenLockOnly': appLockScreenLockOnly,
    'extensionPreferences': extensionPreferences,
    'useBrowserTabs': useBrowserTabs,
    'useDualPaneBrowsing': useDualPaneBrowsing,
    'tabSwipeGestures': tabSwipeGestures.toJson(),
    'autoOpenOnUnlock': autoOpenOnUnlock,
    'htmlEnableJavaScript': htmlEnableJavaScript,
    'languageCode': languageCode,
    'debugLoggingEnabled': debugLoggingEnabled,
    'deleteAfterImportMode': deleteAfterImportMode.toJson(),
    'audioRecordingQuality': audioRecordingQuality.toJson(),
    'videoMuted': videoMuted,
    'videoPlaybackMode': videoPlaybackMode.name,
    'autoLockOnShareImport': autoLockOnShareImport,
    'quickActionLockMode': quickActionLockMode.toJson(),
    'enableAuthenticator': enableAuthenticator,
  };

  /// Look and layout: everything the "Appearance & Interface" pages and the
  /// per-screen appearance sheets let the person change.
  Map<String, dynamic> interfaceToJson() => {
    'themeMode': themeMode.index,
    'useDynamicColor': useDynamicColor,
    'defaultLayoutMode': defaultLayoutMode.toJson(),
    'defaultFileSortBy': defaultFileSortBy.toJson(),
    'defaultFileSortAscending': defaultFileSortAscending,
    'containerSortMode': containerSortMode.toJson(),
    'showStorageLocationsInDrawer': showStorageLocationsInDrawer,
    'appBarAtBottom': appBarAtBottom,
    'playlistScrollMode': playlistScrollMode.toJson(),
    'playlistScrollDirection':
        playlistScrollMode == PlaylistScrollMode.verticalPage
        ? 'vertical'
        : (playlistScrollMode == PlaylistScrollMode.verticalContinuous
              ? 'verticalContinuous'
              : 'horizontal'),
    'authenticatorShowNumbers': authenticatorShowNumbers,
    'authenticatorSearchPlacement': authenticatorSearchPlacement.toJson(),
    'fileManagerSkin': fileManagerSkin.toJson(),
    'fileManagerFollowsAppSkin': fileManagerFollowsAppSkin,
    'editorFollowsAppSkin': editorFollowsAppSkin,
    'editorAppearancePrefs': editorAppearancePrefs,
  };

  /// The skin library and the active selection. Unlike the other two groups
  /// this is not merged field-by-field: skins are added, selected and removed
  /// through the App skin screens.
  Map<String, dynamic> skinsToJson() => {
    'appSkinPreset': appSkinPreset.id,
    'useOledBlackTheme': useOledBlackTheme,
    'customAppSkin': customAppSkin.toJson(),
    'customAppSkins': customAppSkins.map((skin) => skin.toJson()).toList(),
    'appSkinSchemaVersion': appSkinSchemaVersion,
  };

  /// A copy of this with every *configuration* field taken from [other].
  /// Interface fields, skins and the private hash material stay as they are.
  AppSettings withConfigurationFrom(AppSettings other) => copyWith(
    useMasterPassword: other.useMasterPassword,
    masterUnlockMethod: other.masterUnlockMethod,
    defaultDocumentProvider: other.defaultDocumentProvider,
    videoAutoPlay: other.videoAutoPlay,
    blockScreenshots: other.blockScreenshots,
    keepVaultsRunningInBackground: other.keepVaultsRunningInBackground,
    defaultDerivedKeyCacheEnabled: other.defaultDerivedKeyCacheEnabled,
    lockContainersOnScreenLock: other.lockContainersOnScreenLock,
    autoLockMins: other.autoLockMins,
    autoLockScreenLockOnly: other.autoLockScreenLockOnly,
    lockAppOnScreenLock: other.lockAppOnScreenLock,
    appLockAfterMins: other.appLockAfterMins,
    appLockScreenLockOnly: other.appLockScreenLockOnly,
    extensionPreferences: other.extensionPreferences,
    useBrowserTabs: other.useBrowserTabs,
    useDualPaneBrowsing: other.useDualPaneBrowsing,
    tabSwipeGestures: other.tabSwipeGestures,
    autoOpenOnUnlock: other.autoOpenOnUnlock,
    htmlEnableJavaScript: other.htmlEnableJavaScript,
    // copyWith can't set a null language through `languageCode` alone.
    languageCode: other.languageCode,
    clearLanguageCode: other.languageCode == null,
    debugLoggingEnabled: other.debugLoggingEnabled,
    deleteAfterImportMode: other.deleteAfterImportMode,
    audioRecordingQuality: other.audioRecordingQuality,
    videoMuted: other.videoMuted,
    videoPlaybackMode: other.videoPlaybackMode,
    autoLockOnShareImport: other.autoLockOnShareImport,
    quickActionLockMode: other.quickActionLockMode,
    enableAuthenticator: other.enableAuthenticator,
  );

  /// A copy of this with every *interface* field taken from [other].
  /// Configuration, skins and the private hash material stay as they are.
  AppSettings withInterfaceFrom(AppSettings other) => copyWith(
    themeMode: other.themeMode,
    useDynamicColor: other.useDynamicColor,
    defaultLayoutMode: other.defaultLayoutMode,
    defaultFileSortBy: other.defaultFileSortBy,
    defaultFileSortAscending: other.defaultFileSortAscending,
    containerSortMode: other.containerSortMode,
    showStorageLocationsInDrawer: other.showStorageLocationsInDrawer,
    appBarAtBottom: other.appBarAtBottom,
    playlistScrollMode: other.playlistScrollMode,
    authenticatorShowNumbers: other.authenticatorShowNumbers,
    authenticatorSearchPlacement: other.authenticatorSearchPlacement,
    fileManagerSkin: other.fileManagerSkin,
    fileManagerFollowsAppSkin: other.fileManagerFollowsAppSkin,
    editorFollowsAppSkin: other.editorFollowsAppSkin,
    editorAppearancePrefs: other.editorAppearancePrefs,
  );

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
    blockScreenshots: j['blockScreenshots'] as bool? ?? true,
    keepVaultsRunningInBackground:
        j['keepVaultsRunningInBackground'] as bool? ?? false,
    defaultDerivedKeyCacheEnabled:
        j['defaultDerivedKeyCacheEnabled'] as bool? ?? false,
    containerSortMode: ContainerSortMode.fromJson(
      j['containerSortMode'] as String?,
    ),
    themeMode: j['themeMode'] != null
        ? ThemeMode.values[j['themeMode'] as int]
        : ThemeMode.system,
    useDynamicColor: j['useDynamicColor'] as bool? ?? false,
    useOledBlackTheme: j['useOledBlackTheme'] as bool? ?? false,
    lockContainersOnScreenLock:
        j['lockContainersOnScreenLock'] as bool? ?? true,
    autoLockMins: j['autoLockMins'] as int? ?? 0,
    autoLockScreenLockOnly: j['autoLockScreenLockOnly'] as bool? ?? false,
    // Migrates installs from before App Lock and Vault Auto-Lock had
    // separate timeouts: they used to share lockContainersOnScreenLock/
    // autoLockMins for both. A settings file with no 'lockAppOnScreenLock'/
    // 'appLockAfterMins' key yet is always from before this split, so seed
    // the new app-gate-only settings from the old shared ones once (only
    // when a master password was actually in use -- otherwise there's
    // nothing to preserve), the same way masterUnlockMethod below backfills
    // from the legacy masterPasswordIsFingerprint boolean it replaced.
    lockAppOnScreenLock:
        j['lockAppOnScreenLock'] as bool? ??
        ((j['useMasterPassword'] as bool? ?? false)
            ? (j['lockContainersOnScreenLock'] as bool? ?? true)
            : true),
    appLockAfterMins:
        j['appLockAfterMins'] as int? ??
        ((j['useMasterPassword'] as bool? ?? false)
            ? (j['autoLockMins'] as int? ?? 0)
            : 0),
    appLockScreenLockOnly: j['appLockScreenLockOnly'] as bool? ?? false,
    defaultLayoutMode:
        BrowserLayoutMode.fromJson(j['defaultLayoutMode'] as String?) ??
        BrowserLayoutMode.detailed,
    useBrowserTabs: j['useBrowserTabs'] as bool? ?? true,
    useDualPaneBrowsing: j['useDualPaneBrowsing'] as bool? ?? false,
    // Older versions saved one `tabEdgeSwipe` mode; it still seeds the three
    // gestures until the new value has been saved.
    tabSwipeGestures: TabSwipeGestures.fromJson(
      j['tabSwipeGestures'],
      legacyMode: j['tabEdgeSwipe'] as String?,
    ),
    appBarAtBottom: j['appBarAtBottom'] as bool? ?? false,
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
      j['playlistScrollMode'] as String? ??
          j['playlistScrollDirection'] as String?,
    ),
    languageCode: j['languageCode'] as String?,
    debugLoggingEnabled: j['debugLoggingEnabled'] as bool? ?? false,
    deleteAfterImportMode: DeleteAfterImportMode.fromJson(
      j['deleteAfterImportMode'] as String?,
    ),
    audioRecordingQuality: AudioRecordingQuality.fromJson(
      j['audioRecordingQuality'] as String?,
    ),
    videoMuted: j['videoMuted'] as bool? ?? false,
    videoPlaybackMode: VideoPlaybackMode.fromJson(
      j['videoPlaybackMode'] as String?,
    ),
    showStorageLocationsInDrawer:
        j['showStorageLocationsInDrawer'] as bool? ?? true,
    autoLockOnShareImport: j['autoLockOnShareImport'] as bool? ?? true,
    quickActionLockMode: j['quickActionLockMode'] != null
        ? QuickActionLockMode.fromJson(j['quickActionLockMode'] as String?)
        : (j['autoLockOnShareImport'] as bool? ?? true)
        ? QuickActionLockMode.leaveAsFound
        : QuickActionLockMode.leaveOpen,
    enableAuthenticator: j['enableAuthenticator'] as bool? ?? true,
    authenticatorShowNumbers: j['authenticatorShowNumbers'] as bool? ?? true,
    authenticatorSearchPlacement: AuthenticatorSearchPlacement.fromJson(
      j['authenticatorSearchPlacement'] as String?,
    ),
    appSkinPreset: AppSkinPreset.fromJson(j['appSkinPreset']),
    customAppSkin: CustomAppSkin.fromJson(j['customAppSkin']),
    customAppSkins: j['customAppSkins'] is List
        ? (j['customAppSkins'] as List)
              .whereType<Map>()
              .map(CustomAppSkin.fromJson)
              .toList()
        : const [],
    fileManagerSkin: FileManagerSkin.fromJson(j['fileManagerSkin']),
    fileManagerFollowsAppSkin:
        j['fileManagerFollowsAppSkin'] as bool? ??
        ((j['appSkinSchemaVersion'] as int? ?? 0) >= 1),
    editorFollowsAppSkin:
        j['editorFollowsAppSkin'] as bool? ??
        ((j['appSkinSchemaVersion'] as int? ?? 0) >= 1),
    editorAppearancePrefs: j['editorAppearancePrefs'] is Map
        ? Map<String, dynamic>.from(j['editorAppearancePrefs'] as Map)
        : {},
    appSkinSchemaVersion: j['appSkinSchemaVersion'] as int? ?? 0,
  );
}

@Riverpod(keepAlive: true)
AppSettingsService appSettingsService(Ref ref) => const AppSettingsService();

class AppSettingsService {
  const AppSettingsService();

  static Future<void> _writeQueue = Future<void>.value();

  Future<T> _withWriteLock<T>(Future<T> Function() action) {
    final previous = _writeQueue;
    final done = Completer<void>();
    _writeQueue = done.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        done.complete();
      }
    }();
  }

  /// Storage key for the whole [AppSettings] blob (everything [toJson]
  /// covers -- never the master-password hash/salt or pattern/PIN hashes,
  /// which have their own dedicated [_secure] keys above and their own
  /// load/save paths below). Kept behind [AppSecureStorage] rather than a
  /// plain file for the same reason those hashes already were: this is
  /// app-lock/theme/behavior config, not itself secret, but it's cheap to
  /// encrypt at rest and there's no reason to leave it as the one plain-JSON
  /// file sitting next to the (also now-encrypted, see
  /// FileManagerToolbarService) toolbar config.
  static const _kSettingsBlob = 'app_settings_blob_v1';

  /// In-memory copy of the *raw decrypted* settings blob (never the parsed
  /// [AppSettings] -- callers freely mutate the object they get back, so each
  /// [loadSettings] call still builds its own fresh instance from this
  /// string). [loadSettings] has dozens of call sites, several of them on
  /// every cold start and on every file open, and each used to cost a
  /// platform-channel hop plus a Keystore decrypt.
  ///
  /// Only the blob is cached. The master-password hash/salt and the pattern
  /// and PIN hashes keep being read from secure storage every time. The blob
  /// itself is documented above as non-secret app configuration.
  static String? _cachedBlob;

  /// Bumped by every [invalidateCache] so a read that was already in flight
  /// when a write happened can't store its (now stale) result afterwards.
  static int _cacheGeneration = 0;

  /// Drops the cached blob. Called around every write in this class, and by
  /// the app bootstrap when native code wipes secure storage (panic purge),
  /// which this class can't observe on its own.
  static void invalidateCache() {
    _cachedBlob = null;
    _cacheGeneration++;
  }

  Future<String?> _readSettingsBlob() async {
    final cached = _cachedBlob;
    if (cached != null) return cached;
    final generation = _cacheGeneration;
    final blob = await _secure.read(key: _kSettingsBlob);
    // A null read is never cached, so first-run/legacy-migration and
    // post-wipe states are always re-checked against real storage.
    if (blob != null && generation == _cacheGeneration) {
      _cachedBlob = blob;
    }
    return blob;
  }

  /// Where [AppSettings] lived before the switch to [_kSettingsBlob] above.
  /// Consulted only by [_migrateLegacySettings], once per install, to move
  /// an existing user's settings into the encrypted store; deleted once
  /// migrated so plaintext doesn't linger alongside the encrypted copy.
  static Future<File> get _legacySettingsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_settings.json');
  }

  /// One-time migration from [_legacySettingsFile] to [_kSettingsBlob].
  /// Returns null (caller falls back to [AppSettings] defaults) when
  /// there's no legacy file -- i.e. this is a fresh install, not an
  /// upgrade, so there's nothing to migrate.
  Future<AppSettings?> _migrateLegacySettings() async {
    final legacy = await _legacySettingsFile;
    if (!await legacy.exists()) return null;
    final raw = jsonDecode(await legacy.readAsString()) as Map<String, dynamic>;
    final settings = AppSettings.fromJson(raw);
    await _secure.write(
      key: _kSettingsBlob,
      value: jsonEncode(settings.toJson()),
    );
    invalidateCache();
    try {
      await legacy.delete();
    } catch (_) {
      // Best-effort: the encrypted copy written above is the source of
      // truth from here on regardless (loadSettings checks it first, every
      // time), so a failed delete only leaves a stale, never-read plaintext
      // file behind rather than losing anything.
    }
    return settings;
  }

  Future<AppSettings> loadSettings() async {
    AppSettings settings;
    try {
      final blob = await _readSettingsBlob();
      if (blob != null) {
        settings = AppSettings.fromJson(
          jsonDecode(blob) as Map<String, dynamic>,
        );
      } else {
        settings = await _migrateLegacySettings() ?? AppSettings();
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

  /// Saves general settings while retaining skin preferences written by the
  /// dedicated read/modify/write methods below. Several legacy callers build
  /// an AppSettings copy from a screen snapshot, so this protects newer skin
  /// and editor choices from being replaced by that older snapshot.
  Future<void> saveSettings(AppSettings settings) => _withWriteLock(() async {
    final current = await loadSettings();
    await _saveSettings(
      settings.copyWith(
        appSkinPreset: current.appSkinPreset,
        customAppSkin: current.customAppSkin,
        customAppSkins: current.customAppSkins,
        fileManagerSkin: current.fileManagerSkin,
        fileManagerFollowsAppSkin: current.fileManagerFollowsAppSkin,
        editorFollowsAppSkin: current.editorFollowsAppSkin,
        editorAppearancePrefs: current.editorAppearancePrefs,
        appSkinSchemaVersion: current.appSkinSchemaVersion,
      ),
    );
  });

  /// Replaces the complete settings snapshot, used for an explicit import or
  /// a one-time migration where the caller has already resolved all fields.
  Future<void> replaceSettings(AppSettings settings) =>
      _withWriteLock(() => _saveSettings(settings));

  /// Updates one or more settings against the latest persisted snapshot.
  /// Serializing the read/modify/write avoids independent skin and editor
  /// preference changes overwriting each other when they happen together.
  Future<AppSettings> updateSettings(
    AppSettings Function(AppSettings current) updater,
  ) => _withWriteLock(() async {
    final current = await loadSettings();
    final updated = updater(current);
    await _saveSettings(updated);
    return updated;
  });

  Future<void> _saveSettings(AppSettings settings) async {
    // Invalidate on both sides of the write: before, so nothing reads the old
    // blob from cache while the write is in flight; after, so a read that
    // began before the write finished can't have repopulated the cache with
    // the old value (see _cacheGeneration).
    invalidateCache();
    try {
      await _secure.write(
        key: _kSettingsBlob,
        value: jsonEncode(settings.toJson()),
      );
    } catch (_) {
      // Same reasoning as FileManagerToolbarService.save(): the caller's
      // in-memory settings object already reflects the change for this
      // session; a failed write only risks it not surviving a restart.
    } finally {
      invalidateCache();
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
