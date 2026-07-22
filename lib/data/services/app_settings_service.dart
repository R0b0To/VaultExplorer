import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/container_sort_mode.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';

import 'package:flutter/material.dart';

export 'container_repository.dart'
    show ContainerRepository, ContainerRecord, ContainerUnlockMethod;

// ── Secure storage instance ───────────────────────────────────────────────────

const _secure = AppSecureStorage.instance;

const _kMasterHash = 'vc_master_hash_v2';
const _kMasterSalt = 'vc_master_salt_v2';

// ── Global app settings ───────────────────────────────────────────────────────

class AppSettings {
  bool useMasterPassword;
  bool masterPasswordIsFingerprint;
  bool defaultDocumentProvider;
  bool videoAutoPlay;
  bool blockScreenshots;
  bool defaultDerivedKeyCacheEnabled;
  bool lockContainersOnScreenLock;
  int autoLockMins;
  bool hasSeenSwipeTutorial;
  ContainerSortMode containerSortMode;
  bool swapCardActions;
  ThemeMode themeMode;

  /// Default browser layout mode (list, compact, grid).
  BrowserLayoutMode defaultLayoutMode;

  /// App-wide default thumbnail cache mode, applied to every container whose
  /// [ContainerRecord.thumbnailCacheMode] is null.
  ThumbnailCacheMode defaultThumbnailCacheMode;

  /// App-wide default thumbnail quality settings, applied to every container whose
  /// [ContainerRecord.thumbnailQuality] is null.
  ThumbnailQuality defaultThumbnailQuality;

  Map<String, String> extensionPreferences;

  String? _masterPasswordHash;
  String? _masterPasswordSalt;

  AppSettings({
    this.useMasterPassword = false,
    this.masterPasswordIsFingerprint = false,
    this.defaultDocumentProvider = false,
    this.videoAutoPlay = true,
    this.blockScreenshots = false,
    this.hasSeenSwipeTutorial = false,
    this.lockContainersOnScreenLock = true,
    this.defaultDerivedKeyCacheEnabled = false,
    this.autoLockMins = 0,
    this.defaultLayoutMode = BrowserLayoutMode.list, // Default added
    this.defaultThumbnailCacheMode = ThumbnailCacheMode.disabled,
    this.defaultThumbnailQuality = ThumbnailQuality.medium,
    this.containerSortMode = ContainerSortMode.manual,   // ADD
    this.swapCardActions = false,
    this.themeMode = ThemeMode.system,
    Map<String, String>? extensionPreferences,
    this._masterPasswordHash,
    this._masterPasswordSalt,
  }) : extensionPreferences = extensionPreferences ?? {};

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
    bool? defaultDerivedKeyCacheEnabled,
    bool? lockContainersOnScreenLock,
    int? autoLockMins,
    bool? hasSeenSwipeTutorial,
    ContainerSortMode? containerSortMode,
    bool? swapCardActions,   
    ThemeMode? themeMode,
    BrowserLayoutMode? defaultLayoutMode,
    ThumbnailCacheMode? defaultThumbnailCacheMode,
    ThumbnailQuality? defaultThumbnailQuality,
    Map<String, String>? extensionPreferences,
    String? masterPasswordHash,
    String? masterPasswordSalt,
  }) {
    return AppSettings(
      useMasterPassword: useMasterPassword ?? this.useMasterPassword,
      masterPasswordIsFingerprint: masterPasswordIsFingerprint ?? this.masterPasswordIsFingerprint,
      defaultDocumentProvider: defaultDocumentProvider ?? this.defaultDocumentProvider,
      videoAutoPlay: videoAutoPlay ?? this.videoAutoPlay,
      blockScreenshots: blockScreenshots ?? this.blockScreenshots,
      defaultDerivedKeyCacheEnabled: defaultDerivedKeyCacheEnabled ?? this.defaultDerivedKeyCacheEnabled,
      lockContainersOnScreenLock: lockContainersOnScreenLock ?? this.lockContainersOnScreenLock,
      autoLockMins: autoLockMins ?? this.autoLockMins,
      hasSeenSwipeTutorial: hasSeenSwipeTutorial ?? this.hasSeenSwipeTutorial,
      defaultLayoutMode: defaultLayoutMode ?? this.defaultLayoutMode,
      containerSortMode: containerSortMode ?? this.containerSortMode,
      swapCardActions: swapCardActions ?? this.swapCardActions, 
      themeMode: themeMode ?? this.themeMode,
      defaultThumbnailCacheMode: defaultThumbnailCacheMode ?? this.defaultThumbnailCacheMode,
      defaultThumbnailQuality: defaultThumbnailQuality ?? this.defaultThumbnailQuality,
      extensionPreferences: extensionPreferences ?? this.extensionPreferences,
      masterPasswordHash: masterPasswordHash ?? _masterPasswordHash,
      masterPasswordSalt: masterPasswordSalt ?? _masterPasswordSalt,
    );
  }

  Map<String, dynamic> toJson() => {
    'useMasterPassword': useMasterPassword,
    'masterPasswordIsFingerprint': masterPasswordIsFingerprint,
    'defaultDocumentProvider': defaultDocumentProvider,
    'videoAutoPlay': videoAutoPlay,
    'blockScreenshots': blockScreenshots,
    'defaultDerivedKeyCacheEnabled': defaultDerivedKeyCacheEnabled,
    'lockContainersOnScreenLock': lockContainersOnScreenLock,
    'autoLockMins': autoLockMins,
    'hasSeenSwipeTutorial': hasSeenSwipeTutorial,
    'defaultLayoutMode': defaultLayoutMode.toJson(), // Serialize layout mode
    'defaultThumbnailCacheMode': defaultThumbnailCacheMode.toJson(),
    'defaultThumbnailQuality': defaultThumbnailQuality.toJson(),
    'containerSortMode': containerSortMode.toJson(),
    'swapCardActions': swapCardActions,
    'themeMode': themeMode.index,
    'extensionPreferences': extensionPreferences,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    useMasterPassword: j['useMasterPassword'] as bool? ?? false,
    masterPasswordIsFingerprint: j['masterPasswordIsFingerprint'] as bool? ?? false,
    defaultDocumentProvider: j['defaultDocumentProvider'] as bool? ?? false,
    videoAutoPlay: j['videoAutoPlay'] as bool? ?? true,
    blockScreenshots: j['blockScreenshots'] as bool? ?? false,
    hasSeenSwipeTutorial: j['hasSeenSwipeTutorial'] as bool? ?? false,
    defaultDerivedKeyCacheEnabled: j['defaultDerivedKeyCacheEnabled'] as bool? ?? false,
    containerSortMode: ContainerSortMode.fromJson(j['containerSortMode'] as String?),  
    swapCardActions: j['swapCardActions'] as bool? ?? false,   
    themeMode: j['themeMode'] != null ? ThemeMode.values[j['themeMode'] as int] : ThemeMode.system,
    lockContainersOnScreenLock: j['lockContainersOnScreenLock'] as bool? ?? true,
    autoLockMins: j['autoLockMins'] as int? ?? 0,

    // Deserialize layout mode, defaulting to list if missing
    defaultLayoutMode:
        BrowserLayoutMode.fromJson(
          j['defaultLayoutMode'] as String?,
        ) ??
        BrowserLayoutMode.list,

    defaultThumbnailCacheMode:
        ThumbnailCacheMode.fromJson(
          j['defaultThumbnailCacheMode'] as String?,
        ) ??
        ThumbnailCacheMode.appCache,
    defaultThumbnailQuality:
        ThumbnailQuality.fromJson(
          j['defaultThumbnailQuality'] as String?,
        ) ??
        ThumbnailQuality.medium,
    extensionPreferences:
        (j['extensionPreferences'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as String),
        ) ??
        {},
  );
}

// ── Persistence service ───────────────────────────────────────────────────────

class AppSettingsService {
  static Future<File> get _settingsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/app_settings.json');
  }

  static Future<AppSettings> loadSettings() async {
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

  static Future<void> saveSettings(AppSettings settings) async {
    try {
      final file = await _settingsFile;
      await file.writeAsString(jsonEncode(settings.toJson()));
    } catch (_) {}
  }

  static Future<void> saveMasterPassword(
    AppSettings settings,
    String hash,
    String salt,
  ) async {
    settings._setHashMaterial(hash, salt);
    await _secure.write(key: _kMasterHash, value: hash);
    await _secure.write(key: _kMasterSalt, value: salt);
    await saveSettings(settings);
  }

  static Future<void> clearMasterPassword(AppSettings settings) async {
    settings._clearHashMaterial();
    await _secure.delete(key: _kMasterHash);
    await _secure.delete(key: _kMasterSalt);
    await saveSettings(settings);
  }
}
