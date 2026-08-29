import 'dart:convert';
import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

void _logSwallowed(String method, Object error) {}

@immutable
class DocumentProviderFolder {
  final String path;
  final bool autoMount;
  const DocumentProviderFolder({required this.path, this.autoMount = false});
  String get name =>
      path.contains('/') ? path.substring(path.lastIndexOf('/') + 1) : path;
  DocumentProviderFolder copyWith({bool? autoMount}) => DocumentProviderFolder(
    path: path,
    autoMount: autoMount ?? this.autoMount,
  );
  Map<String, dynamic> toJson() => {'path': path, 'autoMount': autoMount};
  factory DocumentProviderFolder.fromJson(Map<String, dynamic> j) =>
      DocumentProviderFolder(
        path: j['path'] as String? ?? '',
        autoMount: j['autoMount'] as bool? ?? false,
      );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocumentProviderFolder &&
          other.path == path &&
          other.autoMount == autoMount;
  @override
  int get hashCode => Object.hash(path, autoMount);
}

enum ContainerUnlockMethod {
  password,
  rememberPassword,
  biometrics,
  pattern,
  pin;

  String get label => switch (this) {
    ContainerUnlockMethod.password => 'Manual Password',
    ContainerUnlockMethod.rememberPassword => 'Remember Password',
    ContainerUnlockMethod.biometrics => 'Biometric Unlock',
    ContainerUnlockMethod.pattern => 'Pattern Unlock',
    ContainerUnlockMethod.pin => 'PIN Unlock',
  };
  String get subtitle => switch (this) {
    ContainerUnlockMethod.password => 'Type the password every time',
    ContainerUnlockMethod.rememberPassword =>
      'Stored securely in Android Keystore',
    ContainerUnlockMethod.biometrics => 'Use fingerprint or face to unlock',
    ContainerUnlockMethod.pattern => 'Draw a pattern to unlock',
    ContainerUnlockMethod.pin => 'Enter a PIN to unlock',
  };
  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
    ContainerUnlockMethod.password => l10n.unlockMethodManualPassword,
    ContainerUnlockMethod.rememberPassword => l10n.unlockMethodRememberPassword,
    ContainerUnlockMethod.biometrics => l10n.unlockMethodBiometrics,
    ContainerUnlockMethod.pattern => l10n.unlockMethodPattern,
    ContainerUnlockMethod.pin => l10n.unlockMethodPin,
  };
  String getLocalizedSubtitle(AppLocalizations l10n) => switch (this) {
    ContainerUnlockMethod.password => l10n.unlockMethodSubtitlePassword,
    ContainerUnlockMethod.rememberPassword =>
      l10n.unlockMethodSubtitleRememberPassword,
    ContainerUnlockMethod.biometrics => l10n.unlockMethodSubtitleBiometrics,
    ContainerUnlockMethod.pattern => l10n.unlockMethodSubtitlePattern,
    ContainerUnlockMethod.pin => l10n.unlockMethodSubtitlePin,
  };
  IconData get icon => switch (this) {
    ContainerUnlockMethod.password => Icons.key_rounded,
    ContainerUnlockMethod.rememberPassword => Icons.lock_open_rounded,
    ContainerUnlockMethod.biometrics => Icons.fingerprint,
    ContainerUnlockMethod.pattern => Icons.pattern,
    ContainerUnlockMethod.pin => Icons.dialpad_rounded,
  };
  String toJson() => name;
  static ContainerUnlockMethod fromJson(String? value) => switch (value) {
    'password' => ContainerUnlockMethod.password,
    'rememberPassword' => ContainerUnlockMethod.rememberPassword,
    'biometrics' => ContainerUnlockMethod.biometrics,
    'pattern' => ContainerUnlockMethod.pattern,
    'pin' => ContainerUnlockMethod.pin,
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

  Future<List<String>> loadOrder() async {
    await _ensureLoaded();
    return _cache?.keys.toList() ?? [];
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
    if (record.unlockMethod == ContainerUnlockMethod.pin &&
        record.pendingPinHash != null) {
      await _secure.write(
        key: _pinHashKey(record.uri),
        value: record.pendingPinHash,
      );
    } else if (record.unlockMethod != ContainerUnlockMethod.pin) {
      await _secure.delete(key: _pinHashKey(record.uri));
    }

    // Encrypt and store Bookmark & Pinned paths securely in the Keystore
    if (record.bookmarkPaths.isNotEmpty) {
      await _secure.write(
        key: _bookmarkKey(record.uri),
        value: jsonEncode(record.bookmarkPaths),
      );
    } else {
      await _secure.delete(key: _bookmarkKey(record.uri));
    }

    if (record.pinnedPaths.isNotEmpty) {
      await _secure.write(
        key: _pinnedKey(record.uri),
        value: jsonEncode(record.pinnedPaths),
      );
    } else {
      await _secure.delete(key: _pinnedKey(record.uri));
    }

    // documentProviderFolders names paths *inside* the vault; keyfiles names
    // external files used to unlock it. Both go to Keystore-backed storage,
    // same as bookmarks/pinned, instead of the clear-text containers file.
    if (record.documentProviderFolders.isNotEmpty) {
      await _secure.write(
        key: _docFoldersKey(record.uri),
        value: jsonEncode(
          record.documentProviderFolders.map((f) => f.toJson()).toList(),
        ),
      );
    } else {
      await _secure.delete(key: _docFoldersKey(record.uri));
    }

    if (record.keyfiles.isNotEmpty) {
      await _secure.write(
        key: _keyfilesKey(record.uri),
        value: jsonEncode(record.keyfiles),
      );
    } else {
      await _secure.delete(key: _keyfilesKey(record.uri));
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
    await _secure.delete(key: _pinHashKey(uri));
    await _secure.delete(key: _bookmarkKey(uri));
    await _secure.delete(key: _pinnedKey(uri));
    await _secure.delete(key: _docFoldersKey(uri));
    await _secure.delete(key: _keyfilesKey(uri));
    try {
      await vaultExplorerApi.clearDerivedKey(uri);
    } catch (e) {
      _logSwallowed('remove/clearDerivedKey', e);
    }
    await _persist();
  }

  Future<void> setFolderExposed(
    String uri,
    String path, {
    required bool exposed,
    bool autoMount = false,
  }) async {
    await _ensureLoaded();
    final existing = _cache![uri];
    if (existing == null) return;
    final folders = existing.documentProviderFolders
        .where((f) => f.path != path)
        .toList();
    if (exposed) {
      folders.add(DocumentProviderFolder(path: path, autoMount: autoMount));
    }
    _cache![uri] = existing.copyWith(documentProviderFolders: folders);
    await _persistDocumentProviderFolders(uri, folders);
    await _persist();
  }

  Future<void> setFolderAutoMount(
    String uri,
    String path,
    bool autoMount,
  ) async {
    await _ensureLoaded();
    final existing = _cache![uri];
    if (existing == null) return;
    final folders = existing.documentProviderFolders
        .map((f) => f.path == path ? f.copyWith(autoMount: autoMount) : f)
        .toList();
    _cache![uri] = existing.copyWith(documentProviderFolders: folders);
    await _persistDocumentProviderFolders(uri, folders);
    await _persist();
  }

  Future<void> _persistDocumentProviderFolders(
    String uri,
    List<DocumentProviderFolder> folders,
  ) async {
    if (folders.isNotEmpty) {
      await _secure.write(
        key: _docFoldersKey(uri),
        value: jsonEncode(folders.map((f) => f.toJson()).toList()),
      );
    } else {
      await _secure.delete(key: _docFoldersKey(uri));
    }
  }

  Future<String?> getPassword(String uri) =>
      _secure.read(key: _keystoreKey(uri));
  Future<String?> getPatternHash(String uri) =>
      _secure.read(key: _patternHashKey(uri));
  Future<String?> getPinHash(String uri) => _secure.read(key: _pinHashKey(uri));

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

  static String _pinHashKey(String uri) {
    final encoded = base64Url.encode(utf8.encode(uri));
    final trimmed = encoded.length > 170 ? encoded.substring(0, 170) : encoded;
    return 'vc2_pin_hash_$trimmed';
  }

  static String _bookmarkKey(String uri) {
    final encoded = base64Url.encode(utf8.encode(uri));
    final trimmed = encoded.length > 170 ? encoded.substring(0, 170) : encoded;
    // Keeps the legacy 'vc2_fav_' prefix intentionally: this is an opaque
    // Keystore key, and changing it would orphan every path already saved
    // under it by earlier app versions.
    return 'vc2_fav_$trimmed';
  }

  static String _pinnedKey(String uri) {
    final encoded = base64Url.encode(utf8.encode(uri));
    final trimmed = encoded.length > 170 ? encoded.substring(0, 170) : encoded;
    return 'vc2_pin_$trimmed';
  }

  static String _docFoldersKey(String uri) {
    final encoded = base64Url.encode(utf8.encode(uri));
    final trimmed = encoded.length > 170 ? encoded.substring(0, 170) : encoded;
    return 'vc2_docfolders_$trimmed';
  }

  static String _keyfilesKey(String uri) {
    final encoded = base64Url.encode(utf8.encode(uri));
    final trimmed = encoded.length > 170 ? encoded.substring(0, 170) : encoded;
    return 'vc2_keyfiles_$trimmed';
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

      // Fetch all secure encrypted preferences simultaneously to avoid N async calls
      final secureData = await _secure.readAll();

      for (final item in list) {
        final rawRecord = ContainerRecord.fromJson(
          item as Map<String, dynamic>,
        );

        // Read the encrypted paths back from Keystore
        final bookmarkJson = secureData[_bookmarkKey(rawRecord.uri)];
        final pinJson = secureData[_pinnedKey(rawRecord.uri)];
        final docFoldersJson = secureData[_docFoldersKey(rawRecord.uri)];
        final keyfilesJson = secureData[_keyfilesKey(rawRecord.uri)];

        final bookmarkPaths = bookmarkJson != null
            ? List<String>.from(jsonDecode(bookmarkJson))
            : <String>[];
        final pinPaths = pinJson != null
            ? List<String>.from(jsonDecode(pinJson))
            : <String>[];
        final docFolders = docFoldersJson != null
            ? (jsonDecode(docFoldersJson) as List<dynamic>)
                  .map(
                    (e) => DocumentProviderFolder.fromJson(
                      Map<String, dynamic>.from(e as Map),
                    ),
                  )
                  .toList()
            : <DocumentProviderFolder>[];
        final keyfiles = keyfilesJson != null
            ? (jsonDecode(keyfilesJson) as List<dynamic>)
                  .map((e) => Map<String, String>.from(e as Map))
                  .toList()
            : <Map<String, String>>[];

        final secureRecord = rawRecord.copyWith(
          bookmarkPaths: bookmarkPaths,
          pinnedPaths: pinPaths,
          documentProviderFolders: docFolders,
          keyfiles: keyfiles,
        );

        _cache![secureRecord.uri] = secureRecord;
      }
    } catch (e) {
      _logSwallowed('_hydrate', e);
      _cache = {};
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _dataFile;
      // .toJson() inherently excludes the secure paths so they are never written to the clear-text file.
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
  final List<DocumentProviderFolder> documentProviderFolders;
  final ThumbnailCacheMode? thumbnailCacheMode;
  final ThumbnailQuality? thumbnailQuality;
  final bool cacheDerivedKey;
  final bool readOnly;
  final String? pendingPassword;
  final String? pendingPatternHash;
  final String? pendingPinHash;
  final int cipherId;
  final int hashId;
  final String containerFormat;
  final List<Map<String, String>> keyfiles;
  final List<String> pinnedPaths;
  final List<String> bookmarkPaths;

  const ContainerRecord({
    required this.uri,
    required this.label,
    this.rememberPassword = false,
    this.unlockMethod = ContainerUnlockMethod.password,
    this.autoCloseMins = 0,
    this.documentProvider = false,
    this.documentProviderFolders = const [],
    this.thumbnailCacheMode,
    this.thumbnailQuality,
    this.readOnly = false,
    this.cacheDerivedKey = false,
    this.pendingPassword,
    this.pendingPatternHash,
    this.pendingPinHash,
    this.cipherId = 255,
    this.hashId = 255,
    this.containerFormat = 'veracrypt',
    this.keyfiles = const [],
    this.pinnedPaths = const [],
    this.bookmarkPaths = const [],
  });

  bool get isUsbSource => uri.startsWith('usb:');

  ContainerRecord copyWith({
    String? label,
    bool? rememberPassword,
    ContainerUnlockMethod? unlockMethod,
    int? autoCloseMins,
    bool? documentProvider,
    List<DocumentProviderFolder>? documentProviderFolders,
    Object? thumbnailCacheMode = _keep,
    Object? thumbnailQuality = _keep,
    bool? cacheDerivedKey,
    bool? readOnly,
    String? pendingPassword,
    String? pendingPatternHash,
    String? pendingPinHash,
    int? cipherId,
    int? hashId,
    String? containerFormat,
    List<Map<String, String>>? keyfiles,
    List<String>? pinnedPaths,
    List<String>? bookmarkPaths,
  }) {
    return ContainerRecord(
      uri: uri,
      label: label ?? this.label,
      rememberPassword: rememberPassword ?? this.rememberPassword,
      unlockMethod: unlockMethod ?? this.unlockMethod,
      autoCloseMins: autoCloseMins ?? this.autoCloseMins,
      documentProvider: documentProvider ?? this.documentProvider,
      documentProviderFolders:
          documentProviderFolders ?? this.documentProviderFolders,
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
      pendingPinHash: pendingPinHash,
      cipherId: cipherId ?? this.cipherId,
      hashId: hashId ?? this.hashId,
      containerFormat: containerFormat ?? this.containerFormat,
      keyfiles: keyfiles ?? this.keyfiles,
      pinnedPaths: pinnedPaths ?? this.pinnedPaths,
      bookmarkPaths: bookmarkPaths ?? this.bookmarkPaths,
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

    // EXCLUDED FOR SECURITY: `bookmarkPaths`, `pinnedPaths`,
    // `documentProviderFolders` and `keyfiles` all name paths on disk
    // (inside the vault, or to external keyfiles) and are Keystore-
    // encrypted instead of being serialized into this clear-text file.
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
      // Populated from secure storage in _hydrate(), not from this file.
      documentProviderFolders: const [],
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
      // Populated from secure storage in _hydrate(), not from this file.
      keyfiles: const [],
      pinnedPaths: [],
      bookmarkPaths: [],
    );
  }
}

extension ContainerRecordFormatX on ContainerRecord {
  ContainerFormat get format => ContainerFormat.fromWire(containerFormat);
}

const _keep = Object();
