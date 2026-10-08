import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:vaultexplorer/core/utils/sha256.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/vault_delete_after_import_mode.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'container_repository.g.dart';

const _kLogTag = 'ContainerRepository';

void _logSwallowed(String method, Object error) {
  VeLog.w(_kLogTag, '$method swallowed error: $error', error);
}

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

@Riverpod(keepAlive: true)
ContainerRepository containerRepository(Ref ref) =>
    ContainerRepository.withCryptoApi(ref.watch(vaultCryptoApiProvider));

/// The string the platform layer uses to key a container's cached derived key.
///
/// It is the record's URI, except for USB drives: their record URI is the
/// synthetic `usb:<deviceName>` while the unlock flow stores, loads and clears
/// the cached key under the bare device name.
String derivedKeyPathForUri(String uri) =>
    uri.startsWith('usb:') ? uri.substring('usb:'.length) : uri;

class ContainerRepository {
  ContainerRepository._(this._clearDerivedKey, [AppSecureStorage? secure])
    : _secure = secure ?? AppSecureStorage.instance;
  ContainerRepository.withCryptoApi(
    VaultCryptoApi cryptoApi, [
    AppSecureStorage? secure,
  ]) : this._(cryptoApi.clearDerivedKey, secure);

  final Future<bool> Function(String filePath, {bool removeExpiry})
  _clearDerivedKey;
  final AppSecureStorage _secure;
  Map<String, ContainerRecord>? _cache;

  static Future<File> get _dataFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/containers_v2.json');
  }

  Future<Map<String, ContainerRecord>> loadAll() async {
    await _ensureLoaded();
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
    final pwKey = _keystoreKey(record.uri);
    final legacyPwKey = _legacyKeystoreKey(record.uri);
    if (needsPassword && record.pendingPassword != null) {
      await _writeKeyWithLegacyCleanup(
        record.uri,
        pwKey,
        legacyPwKey,
        _legacyKeystoreKey,
        record.pendingPassword!,
      );
    } else if (!needsPassword) {
      // Diagnostic for the "saved password vanished after creating another
      // vault" report: say when a save wipes an existing saved password, and
      // whether the Keystore key had to be truncated (two long URIs sharing
      // their first 135 chars would then share one key).
      try {
        if (await _secure.containsKey(key: pwKey) ||
            (legacyPwKey != pwKey &&
                await _secure.containsKey(key: legacyPwKey))) {
          VeLog.i(
            _kLogTag,
            'save: dropping saved password for ${VeLog.censorUri(record.uri)} '
            '(method=${record.unlockMethod.name})',
          );
        }
      } catch (e) {
        _logSwallowed('save/droppedPasswordDiagnostic', e);
      }
      await _deleteKeyWithLegacyCleanup(
        record.uri,
        pwKey,
        legacyPwKey,
        _legacyKeystoreKey,
      );
    }
    final patternKey = _patternHashKey(record.uri);
    final legacyPatternKey = _legacyPatternHashKey(record.uri);
    if (record.unlockMethod == ContainerUnlockMethod.pattern &&
        record.pendingPatternHash != null) {
      await _writeKeyWithLegacyCleanup(
        record.uri,
        patternKey,
        legacyPatternKey,
        _legacyPatternHashKey,
        record.pendingPatternHash!,
      );
    } else if (record.unlockMethod != ContainerUnlockMethod.pattern) {
      await _deleteKeyWithLegacyCleanup(
        record.uri,
        patternKey,
        legacyPatternKey,
        _legacyPatternHashKey,
      );
    }
    final pinKey = _pinHashKey(record.uri);
    final legacyPinKey = _legacyPinHashKey(record.uri);
    if (record.unlockMethod == ContainerUnlockMethod.pin &&
        record.pendingPinHash != null) {
      await _writeKeyWithLegacyCleanup(
        record.uri,
        pinKey,
        legacyPinKey,
        _legacyPinHashKey,
        record.pendingPinHash!,
      );
    } else if (record.unlockMethod != ContainerUnlockMethod.pin) {
      await _deleteKeyWithLegacyCleanup(
        record.uri,
        pinKey,
        legacyPinKey,
        _legacyPinHashKey,
      );
    }

    // Encrypt and store Bookmark & Pinned paths securely in the Keystore
    final bookmarkKey = _bookmarkKey(record.uri);
    final legacyBookmarkKey = _legacyBookmarkKey(record.uri);
    if (record.bookmarkPaths.isNotEmpty) {
      await _writeKeyWithLegacyCleanup(
        record.uri,
        bookmarkKey,
        legacyBookmarkKey,
        _legacyBookmarkKey,
        jsonEncode(record.bookmarkPaths),
      );
    } else {
      await _deleteKeyWithLegacyCleanup(
        record.uri,
        bookmarkKey,
        legacyBookmarkKey,
        _legacyBookmarkKey,
      );
    }

    final pinnedKey = _pinnedKey(record.uri);
    final legacyPinnedKey = _legacyPinnedKey(record.uri);
    if (record.pinnedPaths.isNotEmpty) {
      await _writeKeyWithLegacyCleanup(
        record.uri,
        pinnedKey,
        legacyPinnedKey,
        _legacyPinnedKey,
        jsonEncode(record.pinnedPaths),
      );
    } else {
      await _deleteKeyWithLegacyCleanup(
        record.uri,
        pinnedKey,
        legacyPinnedKey,
        _legacyPinnedKey,
      );
    }

    // documentProviderFolders names paths *inside* the vault; keyfiles names
    // external files used to unlock it. Both go to Keystore-backed storage,
    // same as bookmarks/pinned, instead of the clear-text containers file.
    final docFoldersKey = _docFoldersKey(record.uri);
    final legacyDocFoldersKey = _legacyDocFoldersKey(record.uri);
    if (record.documentProviderFolders.isNotEmpty) {
      await _writeKeyWithLegacyCleanup(
        record.uri,
        docFoldersKey,
        legacyDocFoldersKey,
        _legacyDocFoldersKey,
        jsonEncode(
          record.documentProviderFolders.map((f) => f.toJson()).toList(),
        ),
      );
    } else {
      await _deleteKeyWithLegacyCleanup(
        record.uri,
        docFoldersKey,
        legacyDocFoldersKey,
        _legacyDocFoldersKey,
      );
    }

    final keyfilesKey = _keyfilesKey(record.uri);
    final legacyKeyfilesKey = _legacyKeyfilesKey(record.uri);
    if (record.keyfiles.isNotEmpty) {
      await _writeKeyWithLegacyCleanup(
        record.uri,
        keyfilesKey,
        legacyKeyfilesKey,
        _legacyKeyfilesKey,
        jsonEncode(record.keyfiles),
      );
    } else {
      await _deleteKeyWithLegacyCleanup(
        record.uri,
        keyfilesKey,
        legacyKeyfilesKey,
        _legacyKeyfilesKey,
      );
    }

    final compositeCarriersKey = _compositeCarriersKey(record.uri);
    final legacyCompositeCarriersKey = _legacyCompositeCarriersKey(record.uri);
    if (record.compositeCarriers.isNotEmpty) {
      await _writeKeyWithLegacyCleanup(
        record.uri,
        compositeCarriersKey,
        legacyCompositeCarriersKey,
        _legacyCompositeCarriersKey,
        jsonEncode(record.compositeCarriers),
      );
    } else {
      await _deleteKeyWithLegacyCleanup(
        record.uri,
        compositeCarriersKey,
        legacyCompositeCarriersKey,
        _legacyCompositeCarriersKey,
      );
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
    await _deleteKeyWithLegacyCleanup(
      uri,
      _keystoreKey(uri),
      _legacyKeystoreKey(uri),
      _legacyKeystoreKey,
    );
    await _deleteKeyWithLegacyCleanup(
      uri,
      _patternHashKey(uri),
      _legacyPatternHashKey(uri),
      _legacyPatternHashKey,
    );
    await _deleteKeyWithLegacyCleanup(
      uri,
      _pinHashKey(uri),
      _legacyPinHashKey(uri),
      _legacyPinHashKey,
    );
    await _deleteKeyWithLegacyCleanup(
      uri,
      _bookmarkKey(uri),
      _legacyBookmarkKey(uri),
      _legacyBookmarkKey,
    );
    await _deleteKeyWithLegacyCleanup(
      uri,
      _pinnedKey(uri),
      _legacyPinnedKey(uri),
      _legacyPinnedKey,
    );
    await _deleteKeyWithLegacyCleanup(
      uri,
      _docFoldersKey(uri),
      _legacyDocFoldersKey(uri),
      _legacyDocFoldersKey,
    );
    await _deleteKeyWithLegacyCleanup(
      uri,
      _keyfilesKey(uri),
      _legacyKeyfilesKey(uri),
      _legacyKeyfilesKey,
    );
    await _deleteKeyWithLegacyCleanup(
      uri,
      _compositeCarriersKey(uri),
      _legacyCompositeCarriersKey(uri),
      _legacyCompositeCarriersKey,
    );
    try {
      await _clearDerivedKey(derivedKeyPathForUri(uri), removeExpiry: true);
    } catch (e) {
      _logSwallowed('remove/clearDerivedKey', e);
    }
    await _persist();
  }

  /// Switches derived-key caching off for every record whose cached key was
  /// keyed by one of [keyPaths] (see [derivedKeyPathForUri]). Used after the
  /// platform layer purged keys whose lifetime ran out, so the vault stops
  /// caching instead of quietly caching a fresh key on the next unlock.
  ///
  /// Returns how many records changed.
  Future<int> disableDerivedKeyCachingFor(Iterable<String> keyPaths) async {
    await _ensureLoaded();
    final wanted = keyPaths.toSet();
    var changed = 0;
    for (final record in _cache!.values.toList()) {
      if (!record.cacheDerivedKey) continue;
      if (!wanted.contains(derivedKeyPathForUri(record.uri))) continue;
      _cache![record.uri] = record.copyWith(cacheDerivedKey: false);
      changed++;
    }
    if (changed > 0) await _persist();
    return changed;
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
    final key = _docFoldersKey(uri);
    final legacyKey = _legacyDocFoldersKey(uri);
    if (folders.isNotEmpty) {
      await _writeKeyWithLegacyCleanup(
        uri,
        key,
        legacyKey,
        _legacyDocFoldersKey,
        jsonEncode(folders.map((f) => f.toJson()).toList()),
      );
    } else {
      await _deleteKeyWithLegacyCleanup(
        uri,
        key,
        legacyKey,
        _legacyDocFoldersKey,
      );
    }
  }

  Future<String?> getPassword(String uri) => _readWithLegacyFallback(
    uri,
    _keystoreKey(uri),
    _legacyKeystoreKey(uri),
    _legacyKeystoreKey,
  );

  Future<String?> getPatternHash(String uri) => _readWithLegacyFallback(
    uri,
    _patternHashKey(uri),
    _legacyPatternHashKey(uri),
    _legacyPatternHashKey,
  );

  Future<String?> getPinHash(String uri) => _readWithLegacyFallback(
    uri,
    _pinHashKey(uri),
    _legacyPinHashKey(uri),
    _legacyPinHashKey,
  );

  void invalidate() => _cache = null;

  bool _sharesLegacyKey(
    String uri,
    String legacyKey,
    String Function(String) legacyKeyExtractor, [
    Iterable<String>? otherUris,
  ]) {
    final others =
        otherUris ??
        (_cache?.keys.where((u) => u != uri) ?? const Iterable<String>.empty());
    return others.any((u) => legacyKeyExtractor(u) == legacyKey);
  }

  bool _shouldDeleteLegacyKey(
    String uri,
    String legacyKey,
    String Function(String) legacyKeyExtractor, [
    Iterable<String>? otherUris,
  ]) {
    return !_sharesLegacyKey(uri, legacyKey, legacyKeyExtractor, otherUris);
  }

  Future<void> _deleteKeyWithLegacyCleanup(
    String uri,
    String key,
    String legacyKey,
    String Function(String) legacyKeyExtractor,
  ) async {
    await _secure.delete(key: key);
    if (legacyKey != key &&
        _shouldDeleteLegacyKey(uri, legacyKey, legacyKeyExtractor)) {
      await _secure.delete(key: legacyKey);
    }
  }

  Future<void> _writeKeyWithLegacyCleanup(
    String uri,
    String key,
    String legacyKey,
    String Function(String) legacyKeyExtractor,
    String value,
  ) async {
    await _secure.write(key: key, value: value);
    if (legacyKey != key &&
        _shouldDeleteLegacyKey(uri, legacyKey, legacyKeyExtractor)) {
      await _secure.delete(key: legacyKey);
    }
  }

  Future<String?> _readWithLegacyFallback(
    String uri,
    String key,
    String legacyKey,
    String Function(String) legacyKeyExtractor,
  ) async {
    final value = await _secure.read(key: key);
    if (value != null) return value;

    if (key != legacyKey) {
      final legacyValue = await _secure.read(key: legacyKey);
      if (legacyValue != null) {
        await _secure.write(key: key, value: legacyValue);
        await _ensureLoaded();
        if (_shouldDeleteLegacyKey(uri, legacyKey, legacyKeyExtractor)) {
          await _secure.delete(key: legacyKey);
        }
        return legacyValue;
      }
    }
    return null;
  }

  Future<void> _migrateLegacySecureKey(
    String uri,
    String key,
    String legacyKey,
    String Function(String) legacyKeyExtractor,
    String value,
    Iterable<String> otherUris,
  ) async {
    try {
      await _secure.write(key: key, value: value);
      if (_shouldDeleteLegacyKey(
        uri,
        legacyKey,
        legacyKeyExtractor,
        otherUris,
      )) {
        await _secure.delete(key: legacyKey);
      }
    } catch (e) {
      _logSwallowed('_migrateLegacySecureKey', e);
    }
  }

  static String _scopedKey(String prefix, String uri, int legacyLimit) {
    final encoded = base64Url.encode(utf8.encode(uri));
    if (encoded.length <= legacyLimit) {
      return '$prefix$encoded';
    }
    final hash = sha256Hex(utf8.encode(uri));
    final head = encoded.substring(0, math.min(50, encoded.length));
    return '$prefix${head}_$hash';
  }

  static String _legacyScopedKey(String prefix, String uri, int legacyLimit) {
    final encoded = base64Url.encode(utf8.encode(uri));
    final trimmed = encoded.length > legacyLimit
        ? encoded.substring(0, legacyLimit)
        : encoded;
    return '$prefix$trimmed';
  }

  static String _keystoreKey(String uri) => _scopedKey('vc2_pw_', uri, 180);
  static String _legacyKeystoreKey(String uri) =>
      _legacyScopedKey('vc2_pw_', uri, 180);

  static String _patternHashKey(String uri) =>
      _scopedKey('vc2_pattern_', uri, 170);
  static String _legacyPatternHashKey(String uri) =>
      _legacyScopedKey('vc2_pattern_', uri, 170);

  static String _pinHashKey(String uri) =>
      _scopedKey('vc2_pin_hash_', uri, 170);
  static String _legacyPinHashKey(String uri) =>
      _legacyScopedKey('vc2_pin_hash_', uri, 170);

  static String _bookmarkKey(String uri) => _scopedKey('vc2_fav_', uri, 170);
  static String _legacyBookmarkKey(String uri) =>
      _legacyScopedKey('vc2_fav_', uri, 170);

  static String _pinnedKey(String uri) => _scopedKey('vc2_pin_', uri, 170);
  static String _legacyPinnedKey(String uri) =>
      _legacyScopedKey('vc2_pin_', uri, 170);

  static String _docFoldersKey(String uri) =>
      _scopedKey('vc2_docfolders_', uri, 170);
  static String _legacyDocFoldersKey(String uri) =>
      _legacyScopedKey('vc2_docfolders_', uri, 170);

  static String _keyfilesKey(String uri) =>
      _scopedKey('vc2_keyfiles_', uri, 170);
  static String _legacyKeyfilesKey(String uri) =>
      _legacyScopedKey('vc2_keyfiles_', uri, 170);

  static String _compositeCarriersKey(String uri) =>
      _scopedKey('vc2_composite_carriers_', uri, 170);
  static String _legacyCompositeCarriersKey(String uri) =>
      _legacyScopedKey('vc2_composite_carriers_', uri, 170);

  @visibleForTesting
  static String keystoreKey(String uri) => _keystoreKey(uri);
  @visibleForTesting
  static String legacyKeystoreKey(String uri) => _legacyKeystoreKey(uri);

  @visibleForTesting
  static String patternHashKey(String uri) => _patternHashKey(uri);
  @visibleForTesting
  static String legacyPatternHashKey(String uri) => _legacyPatternHashKey(uri);

  @visibleForTesting
  static String pinHashKey(String uri) => _pinHashKey(uri);
  @visibleForTesting
  static String legacyPinHashKey(String uri) => _legacyPinHashKey(uri);

  @visibleForTesting
  static String bookmarkKey(String uri) => _bookmarkKey(uri);
  @visibleForTesting
  static String legacyBookmarkKey(String uri) => _legacyBookmarkKey(uri);

  @visibleForTesting
  static String pinnedKey(String uri) => _pinnedKey(uri);
  @visibleForTesting
  static String legacyPinnedKey(String uri) => _legacyPinnedKey(uri);

  @visibleForTesting
  static String docFoldersKey(String uri) => _docFoldersKey(uri);
  @visibleForTesting
  static String legacyDocFoldersKey(String uri) => _legacyDocFoldersKey(uri);

  @visibleForTesting
  static String keyfilesKey(String uri) => _keyfilesKey(uri);
  @visibleForTesting
  static String legacyKeyfilesKey(String uri) => _legacyKeyfilesKey(uri);

  @visibleForTesting
  static String compositeCarriersKey(String uri) => _compositeCarriersKey(uri);
  @visibleForTesting
  static String legacyCompositeCarriersKey(String uri) =>
      _legacyCompositeCarriersKey(uri);

  /// The hydrate currently running, if any. _hydrate() installs an empty
  /// `_cache` before it has read anything, so without this a second caller
  /// arriving mid-hydrate (the file browser's init fires two overlapping
  /// loadAll() calls) saw `_cache != null`, skipped the wait, and got back an
  /// empty or partly filled map; callers that didn't skip it hydrated a
  /// second time in parallel.
  Future<void>? _hydrateInFlight;

  Future<void> _ensureLoaded() async {
    final inFlight = _hydrateInFlight;
    if (inFlight != null) return inFlight;
    if (_cache == null) {
      await (_hydrateInFlight = _hydrate().whenComplete(() {
        _hydrateInFlight = null;
      }));
    }
  }

  Future<void> _hydrate() async {
    _cache = {};
    try {
      final file = await _dataFile;
      if (!await file.exists()) return;
      final list = jsonDecode(await file.readAsString()) as List<dynamic>;

      // Fetch all secure encrypted preferences. Isolated so that transient Keystore
      // delays or errors on cold start do not wipe out valid container records from disk.
      Map<String, String> secureData = const {};
      try {
        // Only the per-container metadata keys below are needed here. Asking
        // for just those means the remembered-password (`vc2_pw_`) and
        // pattern/PIN-hash entries are never decrypted or handed to Dart on
        // cold start. `vc2_pin_` (pinned paths) is also a string prefix of
        // `vc2_pin_hash_`, so that one is excluded explicitly.
        secureData = await _secure.readAllWithPrefixes(
          const [
            'vc2_fav_',
            'vc2_pin_',
            'vc2_docfolders_',
            'vc2_keyfiles_',
            'vc2_composite_carriers_',
          ],
          excludePrefixes: const ['vc2_pin_hash_'],
        );
      } catch (e) {
        VeLog.w(
          _kLogTag,
          '_hydrate: Failed to read secure storage, proceeding with plain container records',
          e,
        );
      }

      final allUris = list
          .map((item) => (item as Map)['uri'] as String? ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
      final migrations = <Future<void>>[];

      for (final item in list) {
        final rawRecord = ContainerRecord.fromJson(
          item as Map<String, dynamic>,
        );

        final otherUris = allUris.where((u) => u != rawRecord.uri);

        String? readSecureWithFallback(
          String key,
          String legacyKey,
          String Function(String) legacyExtractor,
        ) {
          final val = secureData[key];
          if (val != null) return val;
          if (key != legacyKey) {
            final legacyVal = secureData[legacyKey];
            if (legacyVal != null) {
              migrations.add(
                _migrateLegacySecureKey(
                  rawRecord.uri,
                  key,
                  legacyKey,
                  legacyExtractor,
                  legacyVal,
                  otherUris,
                ),
              );
              return legacyVal;
            }
          }
          return null;
        }

        // Read the encrypted paths back from Keystore
        final bookmarkJson = readSecureWithFallback(
          _bookmarkKey(rawRecord.uri),
          _legacyBookmarkKey(rawRecord.uri),
          _legacyBookmarkKey,
        );
        final pinJson = readSecureWithFallback(
          _pinnedKey(rawRecord.uri),
          _legacyPinnedKey(rawRecord.uri),
          _legacyPinnedKey,
        );
        final docFoldersJson = readSecureWithFallback(
          _docFoldersKey(rawRecord.uri),
          _legacyDocFoldersKey(rawRecord.uri),
          _legacyDocFoldersKey,
        );
        final keyfilesJson = readSecureWithFallback(
          _keyfilesKey(rawRecord.uri),
          _legacyKeyfilesKey(rawRecord.uri),
          _legacyKeyfilesKey,
        );
        final compositeCarriersJson = readSecureWithFallback(
          _compositeCarriersKey(rawRecord.uri),
          _legacyCompositeCarriersKey(rawRecord.uri),
          _legacyCompositeCarriersKey,
        );

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
        final compositeCarriers = compositeCarriersJson != null
            ? (jsonDecode(compositeCarriersJson) as List<dynamic>)
                  .map((e) => Map<String, String>.from(e as Map))
                  .toList()
            : <Map<String, String>>[];

        final secureRecord = rawRecord.copyWith(
          bookmarkPaths: bookmarkPaths,
          pinnedPaths: pinPaths,
          documentProviderFolders: docFolders,
          keyfiles: keyfiles,
          compositeCarriers: compositeCarriers,
        );

        _cache![secureRecord.uri] = secureRecord;
      }

      if (migrations.isNotEmpty) {
        try {
          await Future.wait(migrations);
        } catch (e) {
          _logSwallowed('_hydrate/migrations', e);
        }
      }
    } catch (e) {
      VeLog.e(_kLogTag, '_hydrate: Failed to read container data file', e);
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
  // Distinct from "autoCloseMins == 0", which just means "no per-container
  // inactivity timer configured" and is also the default for every
  // never-touched container -- see the "never autolock" bug writeup this
  // field fixes. This flag is only ever true when the user has explicitly
  // picked "Never" in the per-container Auto-Lock Duration picker, and it's
  // what exempts this container from the app-wide lock-all sweep
  // (VaultDashboardScreen._lockAllMountedContainers) triggered by
  // SessionLockController / "Lock containers on screen lock". Records
  // written before this field existed have no key for it in the JSON file
  // and deserialize to false, so upgrading never silently exempts an
  // existing container from that security feature.
  final bool autoCloseNever;
  // The other explicit extreme alongside autoCloseNever: true only when the
  // user has explicitly picked "Immediately" in the per-container Auto-Lock
  // Duration picker. Stored separately rather than folded into autoCloseMins
  // because 0 there already means "App Default" (or "Never", disambiguated
  // by autoCloseNever above) -- "Immediately" needs a third state that isn't
  // spelled with autoCloseMins alone. Mutually exclusive with autoCloseNever
  // by construction (the picker only ever sets one at a time). Like
  // autoCloseNever, this also exempts the container from the app-wide
  // lock-all sweep (VaultDashboardScreen._lockAllMountedContainers) -- but
  // unlike an explicit duration or "Never", it isn't handled by that sweep's
  // timing or by the per-container inactivity timer (scheduleAutoClose):
  // a 0-minute foreground idle timer would re-lock the container almost
  // instantly after every tap, since the timer re-arms on every interaction
  // app-wide. Instead this is enforced directly by SessionLockController on
  // real screen-off/backgrounding events -- see handleScreenOff and
  // handleAppLifecycleState's use of lockImmediateOverrideContainers.
  // Records written before this field existed have no key for it in the
  // JSON file and deserialize to false, same reasoning as autoCloseNever.
  final bool autoCloseImmediately;
  // A third explicit extreme, alongside autoCloseNever and
  // autoCloseImmediately: true only when the user has explicitly picked
  // "Screen Lock Only" in the per-container Auto-Lock Duration picker.
  // Like autoCloseImmediately, this locks with no delay -- but only in
  // response to a genuine screen-off/device-lock signal, deliberately NOT
  // in response to plain app backgrounding (switching to another app while
  // the screen stays on), which autoCloseImmediately treats the same as a
  // screen-off. Mutually exclusive with autoCloseNever and
  // autoCloseImmediately by construction (the picker only ever sets one at
  // a time). Also exempts the container from the app-wide lock-all sweep,
  // same as the other two -- but is enforced through its own dedicated
  // path, never the per-container inactivity timer (which a 0-minute
  // foreground idle timer can't safely stand in for -- see
  // autoCloseImmediately's comment) and never the app-lifecycle-resumed
  // path that autoCloseImmediately also hooks into (that's exactly the
  // "plain backgrounding" case this flag is meant to ignore). See
  // SessionLockController.handleScreenOff's use of
  // lockScreenLockOnlyContainers. Records written before this field
  // existed have no key for it in the JSON file and deserialize to false,
  // same reasoning as autoCloseNever.
  final bool autoCloseScreenLockOnly;
  final bool documentProvider;
  final List<DocumentProviderFolder> documentProviderFolders;
  final ThumbnailCacheMode? thumbnailCacheMode;
  final ThumbnailQuality? thumbnailQuality;
  final bool cacheDerivedKey;
  final VaultDeleteAfterImportMode vaultDeleteAfterImportMode;
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
  // The carrier files making up a composite/distributed container -- see
  // isCompositeSource. Deliberately excluded from the cleartext JSON file
  // and Keystore-encrypted instead, same as `keyfiles`: this list is the
  // one thing that actually reveals which otherwise-unrelated files are
  // secretly linked together, which is exactly the metadata a distributed
  // hidden volume is meant to avoid ever writing down in the clear.
  final List<Map<String, String>> compositeCarriers;

  const ContainerRecord({
    required this.uri,
    required this.label,
    this.rememberPassword = false,
    this.unlockMethod = ContainerUnlockMethod.password,
    this.autoCloseMins = 0,
    this.autoCloseNever = false,
    this.autoCloseImmediately = false,
    this.autoCloseScreenLockOnly = false,
    this.documentProvider = false,
    this.documentProviderFolders = const [],
    this.thumbnailCacheMode,
    this.thumbnailQuality,
    this.readOnly = false,
    this.cacheDerivedKey = false,
    this.vaultDeleteAfterImportMode = VaultDeleteAfterImportMode.inherit,
    this.pendingPassword,
    this.pendingPatternHash,
    this.pendingPinHash,
    this.cipherId = 255,
    this.hashId = 255,
    this.containerFormat = 'veracrypt',
    this.keyfiles = const [],
    this.pinnedPaths = const [],
    this.bookmarkPaths = const [],
    this.compositeCarriers = const [],
  });

  bool get isUsbSource => uri.startsWith('usb:');
  bool get isCompositeSource => uri.startsWith('composite:');

  /// Whether this container should be skipped by the app-wide lock-all
  /// sweep (VaultDashboardScreen._lockAllMountedContainers, triggered by
  /// SessionLockController on the global auto-lock timeout or screen lock).
  /// True when the user explicitly configured this specific container to
  /// "Never" (autoCloseNever), "Immediately" (autoCloseImmediately),
  /// "Screen Lock Only" (autoCloseScreenLockOnly), or an explicit duration
  /// (autoCloseMins > 0). Only false when the container follows "App
  /// Default" (autoCloseMins == 0 && !autoCloseNever && !autoCloseImmediately
  /// && !autoCloseScreenLockOnly), which is also the default for every
  /// container that's never had this setting touched.
  bool get isExemptFromGlobalLock =>
      autoCloseNever ||
      autoCloseImmediately ||
      autoCloseScreenLockOnly ||
      autoCloseMins > 0;

  ContainerRecord copyWith({
    String? label,
    bool? rememberPassword,
    ContainerUnlockMethod? unlockMethod,
    int? autoCloseMins,
    bool? autoCloseNever,
    bool? autoCloseImmediately,
    bool? autoCloseScreenLockOnly,
    bool? documentProvider,
    List<DocumentProviderFolder>? documentProviderFolders,
    Object? thumbnailCacheMode = _keep,
    Object? thumbnailQuality = _keep,
    bool? cacheDerivedKey,
    VaultDeleteAfterImportMode? vaultDeleteAfterImportMode,
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
    List<Map<String, String>>? compositeCarriers,
  }) {
    return ContainerRecord(
      uri: uri,
      label: label ?? this.label,
      rememberPassword: rememberPassword ?? this.rememberPassword,
      unlockMethod: unlockMethod ?? this.unlockMethod,
      autoCloseMins: autoCloseMins ?? this.autoCloseMins,
      autoCloseNever: autoCloseNever ?? this.autoCloseNever,
      autoCloseImmediately: autoCloseImmediately ?? this.autoCloseImmediately,
      autoCloseScreenLockOnly:
          autoCloseScreenLockOnly ?? this.autoCloseScreenLockOnly,
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
      vaultDeleteAfterImportMode:
          vaultDeleteAfterImportMode ?? this.vaultDeleteAfterImportMode,
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
      compositeCarriers: compositeCarriers ?? this.compositeCarriers,
    );
  }

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'label': label,
    'rememberPassword': rememberPassword,
    'unlockMethod': unlockMethod.toJson(),
    'autoCloseMins': autoCloseMins,
    'autoCloseNever': autoCloseNever,
    'autoCloseImmediately': autoCloseImmediately,
    'autoCloseScreenLockOnly': autoCloseScreenLockOnly,
    'documentProvider': documentProvider,
    if (thumbnailCacheMode != null)
      'thumbnailCacheMode': thumbnailCacheMode!.toJson(),
    if (thumbnailQuality != null)
      'thumbnailQuality': thumbnailQuality!.toJson(),
    'cacheDerivedKey': cacheDerivedKey,
    'vaultDeleteAfterImportMode': vaultDeleteAfterImportMode.toJson(),
    'readOnly': readOnly,
    'cipherId': cipherId,
    'hashId': hashId,
    'containerFormat': containerFormat,

    // EXCLUDED FOR SECURITY: `bookmarkPaths`, `pinnedPaths`,
    // `documentProviderFolders`, `keyfiles`, and `compositeCarriers` all
    // name paths on disk (inside the vault, external keyfiles, or -- for
    // compositeCarriers -- the carrier files a distributed container is
    // secretly split across) and are Keystore-encrypted instead of being
    // serialized into this clear-text file.
  };

  factory ContainerRecord.fromJson(Map<String, dynamic> j) {
    final method = ContainerUnlockMethod.fromJson(j['unlockMethod'] as String?);
    return ContainerRecord(
      uri: j['uri'] as String,
      label: j['label'] as String? ?? '',
      rememberPassword: method != ContainerUnlockMethod.password,
      unlockMethod: method,
      autoCloseMins: j['autoCloseMins'] as int? ?? 0,
      // Absent (pre-upgrade records) -> false, i.e. not exempt. See the
      // field doc comment above for why this default matters.
      autoCloseNever: j['autoCloseNever'] as bool? ?? false,
      autoCloseImmediately: j['autoCloseImmediately'] as bool? ?? false,
      autoCloseScreenLockOnly: j['autoCloseScreenLockOnly'] as bool? ?? false,
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
      vaultDeleteAfterImportMode: VaultDeleteAfterImportMode.fromJson(
        j['vaultDeleteAfterImportMode'] as String?,
      ),
      readOnly: j['readOnly'] as bool? ?? false,
      cipherId: j['cipherId'] as int? ?? 255,
      hashId: j['hashId'] as int? ?? 255,
      containerFormat: j['containerFormat'] as String? ?? 'veracrypt',
      // Populated from secure storage in _hydrate(), not from this file.
      keyfiles: const [],
      pinnedPaths: [],
      bookmarkPaths: [],
      compositeCarriers: const [],
    );
  }
}

extension ContainerRecordFormatX on ContainerRecord {
  ContainerFormat get format => ContainerFormat.fromWire(containerFormat);
}

const _keep = Object();
