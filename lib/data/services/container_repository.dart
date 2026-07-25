// File: lib/data/services/container_repository.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

void _logSwallowed(String method, Object error) {
  debugPrint('[ContainerRepository] $method failed: $error');
}

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
        ContainerUnlockMethod.password => Icons.key_rounded,
        ContainerUnlockMethod.rememberPassword => Icons.lock_open_rounded,
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

class ContainerRepository {
  ContainerRepository._();

  static final ContainerRepository instance = ContainerRepository._();
  static const _secure = AppSecureStorage.instance;

  Map<String, ContainerRecord>? _cache;

  static Future<File> get _dataFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/containers_v2.json');
  }

  Future<Map<String, ContainerRecord>> loadAll() async {
    if (_cache != null) return Map.unmodifiable(_cache!);
    await _hydrate();
    return Map.unmodifiable(_cache!);
  }

  Future<void> save(ContainerRecord record) async {
    await _ensureLoaded();
    _cache![record.uri] = record;
    final needsPassword = record.unlockMethod != ContainerUnlockMethod.password;
    if (needsPassword && record.pendingPassword != null) {
      await _secure.write(
        key: _keystoreKey(record.uri),
        value: record.pendingPassword,
      );
    } else if (!needsPassword) {
      await _secure.delete(key: _keystoreKey(record.uri));
    }
    if (record.unlockMethod == ContainerUnlockMethod.pattern &&
        record.pendingPatternHash != null) {
      await _secure.write(
        key: _patternHashKey(record.uri),
        value: record.pendingPatternHash,
      );
    } else if (record.unlockMethod != ContainerUnlockMethod.pattern) {
      await _secure.delete(key: _patternHashKey(record.uri));
    }
    await _persist();
  }

  Future<void> saveOrder(List<String> orderedUris) async {
    await _ensureLoaded();
    if (_cache == null) return;
    final newCache = <String, ContainerRecord>{};
    for (final uri in orderedUris) {
      if (_cache!.containsKey(uri)) {
        newCache[uri] = _cache![uri]!;
      }
    }
    for (final entry in _cache!.entries) {
      if (!newCache.containsKey(entry.key)) {
        newCache[entry.key] = entry.value;
      }
    }
    _cache = newCache;
    await _persist();
  }

  Future<void> remove(String uri) async {
    await _ensureLoaded();
    _cache!.remove(uri);
    await _secure.delete(key: _keystoreKey(uri));
    await _secure.delete(key: _patternHashKey(uri));
    try {
      await vaultExplorerApi.clearDerivedKey(uri);
    } catch (e) {
      _logSwallowed('remove/clearDerivedKey', e);
    }
    await _persist();
  }

  Future<String?> getPassword(String uri) =>
      _secure.read(key: _keystoreKey(uri));

  Future<String?> getPatternHash(String uri) =>
      _secure.read(key: _patternHashKey(uri));

  void invalidate() => _cache = null;

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
    } catch (e) {
      _logSwallowed('_hydrate', e);
      _cache = {};
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _dataFile;
      final list = _cache!.values.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(list));
    } catch (e) {
      _logSwallowed('_persist', e);
    }
  }
}

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
  final bool readOnly;
  final String? pendingPassword;
  final String? pendingPatternHash;
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
    this.readOnly = false,
    this.cacheDerivedKey = false,
    this.pendingPassword,
    this.pendingPatternHash,
    this.cipherId = 255,
    this.hashId = 255,
    this.containerFormat = 'veracrypt',
  });

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
    bool? readOnly,
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
      readOnly: readOnly ?? this.readOnly,
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
        'readOnly': readOnly,
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
          ? ThumbnailQuality.fromJson(j['thumbnailQuality'])
          : null,
      cacheDerivedKey: j['cacheDerivedKey'] as bool? ?? false,
      readOnly: j['readOnly'] as bool? ?? false,
      cipherId: j['cipherId'] as int? ?? 255,
      hashId: j['hashId'] as int? ?? 255,
      containerFormat: j['containerFormat'] as String? ?? 'veracrypt',
    );
  }
}

extension ContainerRecordFormatX on ContainerRecord {
  ContainerFormat get format => ContainerFormat.fromWire(containerFormat);
}

const _keep = Object();