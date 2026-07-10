import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import '../models/thumbnail_cache_mode.dart';
import '../models/thumbnail_quality.dart';
import 'vaultexplorer_api.dart';

// ── ContainerUnlockMethod ─────────────────────────────────────────────────────

/// How the user authenticates before a container is unlocked.
///
/// [password]         – user types the container password every time.
/// [rememberPassword] – password is stored in Android Keystore; auto-filled.
/// [biometrics]       – biometric prompt gates access to the stored password.
/// [pattern]          – drawn pattern gates access to the stored password.
enum ContainerUnlockMethod {
  password,
  rememberPassword,
  biometrics,
  pattern;

  String get label => switch (this) {
    ContainerUnlockMethod.password => 'Manual Password',
    ContainerUnlockMethod.rememberPassword => 'Remember Password',
    ContainerUnlockMethod.biometrics => 'Biometric Unlock',
    ContainerUnlockMethod.pattern => 'Pattern Unlock',
  };

  String get subtitle => switch (this) {
    ContainerUnlockMethod.password => 'Type the password every time',
    ContainerUnlockMethod.rememberPassword =>
      'Stored securely in Android Keystore',
    ContainerUnlockMethod.biometrics => 'Use fingerprint or face to unlock',
    ContainerUnlockMethod.pattern => 'Draw a pattern to unlock',
  };

  IconData get icon => switch (this) {
    ContainerUnlockMethod.password => Icons.key,
    ContainerUnlockMethod.rememberPassword => Icons.lock_open,
    ContainerUnlockMethod.biometrics => Icons.fingerprint,
    ContainerUnlockMethod.pattern => Icons.pattern,
  };

  String toJson() => name;

  static ContainerUnlockMethod fromJson(String? value) => switch (value) {
    'password' => ContainerUnlockMethod.password,
    'rememberPassword' => ContainerUnlockMethod.rememberPassword,
    'biometrics' => ContainerUnlockMethod.biometrics,
    'pattern' => ContainerUnlockMethod.pattern,
    _ => ContainerUnlockMethod.password,
  };
}

/// Unified repository for per-container state.
///
/// Replaces the split between [SavedContainerService] (saved_containers.json)
/// and [AppSettingsService] container config handling (container_configs.json).
///
/// Lifecycle: [add] → [update] → [remove] atomically handles all three
/// backing stores: the JSON index, the config JSON, and Android Keystore.
///
class ContainerRepository {
  ContainerRepository._();
  static final ContainerRepository instance = ContainerRepository._();

  // ── Backing stores ────────────────────────────────────────────────────────

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // In-memory cache — loaded once on first access, written-through on every mutation.
  Map<String, ContainerRecord>? _cache;

  static Future<File> get _dataFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/containers_v2.json');
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Loads all containers. Subsequent calls return the in-memory cache.
  Future<Map<String, ContainerRecord>> loadAll() async {
    if (_cache != null) return Map.unmodifiable(_cache!);
    await _hydrate();
    return Map.unmodifiable(_cache!);
  }

  /// Inserts or fully replaces a container record.
  Future<void> save(ContainerRecord record) async {
    await _ensureLoaded();
    _cache![record.uri] = record;

    // ── Password storage ──────────────────────────────────────────────────
    final needsPassword = record.unlockMethod != ContainerUnlockMethod.password;
    if (needsPassword && record.pendingPassword != null) {
      await _secure.write(
        key: _keystoreKey(record.uri),
        value: record.pendingPassword,
      );
    } else if (!needsPassword) {
      await _secure.delete(key: _keystoreKey(record.uri));
    }

    // ── Pattern hash storage ──────────────────────────────────────────────
    if (record.unlockMethod == ContainerUnlockMethod.pattern &&
        record.pendingPatternHash != null) {
      await _secure.write(
        key: _patternHashKey(record.uri),
        value: record.pendingPatternHash,
      );
    } else if (record.unlockMethod != ContainerUnlockMethod.pattern) {
      // Clean up stale pattern hash when switching away from pattern unlock.
      await _secure.delete(key: _patternHashKey(record.uri));
    }

    await _persist();
  }

Future<void> remove(String uri) async {
    await _ensureLoaded();
    _cache!.remove(uri);
    await _secure.delete(key: _keystoreKey(uri));
    await _secure.delete(key: _patternHashKey(uri));
    try {
      await vaultExplorerApi.clearDerivedKey(uri);
    } catch (_) {}
    await _persist();
  }

  /// Reads the stored password for [uri] from Android Keystore.
  Future<String?> getPassword(String uri) =>
      _secure.read(key: _keystoreKey(uri));

  /// Reads the stored pattern hash for [uri] from Android Keystore.
  Future<String?> getPatternHash(String uri) =>
      _secure.read(key: _patternHashKey(uri));

  /// Invalidates the in-memory cache, forcing a reload on next access.
  void invalidate() => _cache = null;

  // ── Internals ─────────────────────────────────────────────────────────────

  static String _keystoreKey(String uri) {
    final encoded = base64Url.encode(utf8.encode(uri));
    final trimmed = encoded.length > 180 ? encoded.substring(0, 180) : encoded;
    return 'vc2_pw_$trimmed';
  }

  static String _patternHashKey(String uri) {
    final encoded = base64Url.encode(utf8.encode(uri));
    final trimmed = encoded.length > 170 ? encoded.substring(0, 170) : encoded;
    return 'vc2_pattern_$trimmed';
  }

  Future<void> _ensureLoaded() async {
    if (_cache == null) await _hydrate();
  }

  Future<void> _hydrate() async {
    _cache = {};
    try {
      final file = await _dataFile;
      if (!await file.exists()) return;
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;
      for (final item in list) {
        final r = ContainerRecord.fromJson(item as Map<String, dynamic>);
        _cache![r.uri] = r;
      }
    } catch (_) {
      _cache = {};
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _dataFile;
      final list = _cache!.values.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
    } catch (_) {}
  }
}

// ── ContainerRecord ───────────────────────────────────────────────────────────

/// Unified model for a saved container entry.
///
/// [pendingPassword] is transient — it is written to Keystore during [save]
/// and is never serialised to the JSON file.
///
/// [thumbnailCacheMode] is null when the container should inherit the
/// app-level default (see [AppSettings.defaultThumbnailCacheMode]).
class ContainerRecord {
  final String uri;
  final String label;
  final bool rememberPassword;
  final ContainerUnlockMethod unlockMethod;
  final int autoCloseMins;
  final bool documentProvider;
  final ThumbnailCacheMode? thumbnailCacheMode;
  final ThumbnailQuality? thumbnailQuality;
  final bool cacheDerivedKey;
  final String? pendingPassword;
  final String? pendingPatternHash;

  // FIX (perf): the cipher/hash combo that successfully unlocked this
  // container last time. 255 = unknown / never resolved — falls back to
  // full auto-detect. Persisting this collapses a 5x8-combination search
  // down to exactly one KDF run on every subsequent unlock.
  final int cipherId;
  final int hashId;
  final String containerFormat;

  const ContainerRecord({
    required this.uri,
    required this.label,
    this.rememberPassword = false,
    this.unlockMethod = ContainerUnlockMethod.password,
    this.autoCloseMins = 0,
    this.documentProvider = false,
    this.thumbnailCacheMode,
    this.thumbnailQuality,
    this.cacheDerivedKey = false,
    this.pendingPassword,
    this.pendingPatternHash,
    this.cipherId = 255,
    this.hashId = 255,
    this.containerFormat = 'veracrypt',
  });

  /// True for containers mounted from a USB mass-storage device (uri format
  /// `usb:<deviceName>`) rather than a picked container file (content:// or
  /// file:// uri).
  ///
  /// FIX: this distinction previously didn't exist anywhere — a USB-mounted
  /// volume got saved to the dashboard exactly like a file container, and
  /// re-unlocking it from the saved entry routed to the file-based
  /// UnlockSheet, which handed the raw `usb:...` string to
  /// `contentResolver.openFileDescriptor()` and failed with "no content
  /// provider" (there IS no content provider for a `usb:` scheme — it's
  /// resolved entirely differently, via UsbUnlockSheet / unlockUsbContainer).
  /// Callers now check this to route to the correct unlock sheet instead of
  /// guessing from context.
  bool get isUsbSource => uri.startsWith('usb:');

  ContainerRecord copyWith({
    String? label,
    bool? rememberPassword,
    ContainerUnlockMethod? unlockMethod,
    int? autoCloseMins,
    bool? documentProvider,
    Object? thumbnailCacheMode = _keep,
    Object? thumbnailQuality = _keep,
    bool? cacheDerivedKey,
    String? pendingPassword,
    String? pendingPatternHash,
    int? cipherId,
    int? hashId,
    String? containerFormat,
  }) {
    return ContainerRecord(
      uri: uri,
      label: label ?? this.label,
      rememberPassword: rememberPassword ?? this.rememberPassword,
      unlockMethod: unlockMethod ?? this.unlockMethod,
      autoCloseMins: autoCloseMins ?? this.autoCloseMins,
      documentProvider: documentProvider ?? this.documentProvider,
      thumbnailCacheMode: thumbnailCacheMode == _keep
          ? this.thumbnailCacheMode
          : thumbnailCacheMode as ThumbnailCacheMode?,
      thumbnailQuality: thumbnailQuality == _keep
          ? this.thumbnailQuality
          : thumbnailQuality as ThumbnailQuality?,
      cacheDerivedKey: cacheDerivedKey ?? this.cacheDerivedKey,
      pendingPassword: pendingPassword,
      pendingPatternHash: pendingPatternHash,
      cipherId: cipherId ?? this.cipherId,
      hashId: hashId ?? this.hashId,
      containerFormat: containerFormat ?? this.containerFormat,
    );
  }

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'label': label,
    'rememberPassword': rememberPassword,
    'unlockMethod': unlockMethod.toJson(),
    'autoCloseMins': autoCloseMins,
    'documentProvider': documentProvider,
    if (thumbnailCacheMode != null)
      'thumbnailCacheMode': thumbnailCacheMode!.toJson(),
    if (thumbnailQuality != null)
      'thumbnailQuality': thumbnailQuality!.toJson(),
    'cacheDerivedKey': cacheDerivedKey,
    'cipherId': cipherId,
    'hashId': hashId,
    'containerFormat': containerFormat,
  };

  factory ContainerRecord.fromJson(Map<String, dynamic> j) {
    final method = ContainerUnlockMethod.fromJson(j['unlockMethod'] as String?);

    return ContainerRecord(
      uri: j['uri'] as String,
      label: j['label'] as String? ?? '',
      rememberPassword: method != ContainerUnlockMethod.password,
      unlockMethod: method,
      autoCloseMins: j['autoCloseMins'] as int? ?? 0,
      documentProvider: j['documentProvider'] as bool? ?? false,
      thumbnailCacheMode: j.containsKey('thumbnailCacheMode')
          ? ThumbnailCacheMode.fromJson(j['thumbnailCacheMode'] as String?)
          : null,
      thumbnailQuality: j.containsKey('thumbnailQuality')
          ? ThumbnailQuality.fromJson(j['thumbnailQuality'] as String?)
          : null,
      cacheDerivedKey: j['cacheDerivedKey'] as bool? ?? false,
      cipherId: j['cipherId'] as int? ?? 255,
      hashId: j['hashId'] as int? ?? 255,
      containerFormat: j['containerFormat'] as String? ?? 'veracrypt',
    );
  }
}

// Sentinel object for copyWith's nullable field pattern.
const _keep = Object();