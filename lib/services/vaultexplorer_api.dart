import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/models/usb_device_info.dart';
import '../models/mounted_container.dart';
import 'channel_methods.dart';
import '../models/crypto_algorithms.dart';

/// A single keyfile picked via [VaultExplorerApi.pickKeyfiles]: [uri] is
/// what gets sent back to native (and round-tripped through
/// [VaultExplorerApi.unlockContainer]/[unlockUsbContainer]/[deriveDerivedKey]/
/// [createContainer] as a `keyfilePaths` entry); [displayName] is purely for
/// showing a chip or list entry in the unlock/create UI.
typedef KeyfileRef = ({String uri, String displayName});

/// One "onUnlockProgress" push from native during cipher/hash auto-detect.
/// [attempted]/[total] count hash-algorithm rounds tried so far (auto-detect
/// runs up to 5 in parallel, each then tries up to 8 ciphers against it very
/// quickly) — suitable for a "trying combination 2 of 5" style indicator.
/// [hashId]/[cipherId] are whichever combination was just attempted (-1 for
/// cipherId if that hash's PBKDF2 itself hadn't finished yet); see
/// [hashAlgorithmName]/[cipherAlgorithmName] to render them.
typedef UnlockProgress = ({
  int volId,
  int attempted,
  int total,
  int hashId,
  int cipherId,
  String containerFormat,
});

String hashAlgorithmName(int hashId) => HashAlgo.nameFor(hashId);
String cipherAlgorithmName(int cipherId) => CipherAlgo.nameFor(cipherId);

/// One "onImportProgress" push from native while importing files/folders
/// from device storage (see [VaultExplorerApi.importFiles]/[importFolder]).
/// [opId] is the [FileOperation.id] passed into that call — listeners
/// should filter on it themselves if more than one import could be in
/// flight. [done]/[total] count files written so far vs. the total native
/// discovered during its pre-count pass; [currentName] is the leaf name of
/// the file most recently written.
typedef ImportProgress = ({
  int opId,
  int done,
  int total,
  String currentName,
});


/// Logs an exception this method is about to swallow (return a default
/// value instead of rethrowing) so a real native/channel failure is at
/// least visible in the debug console instead of silently degrading to
/// "false"/"null"/"0" — which looks identical to a legitimate empty
/// result at every call site.
///
/// [method] is the channel method name (or a short description) so the
/// log line identifies *what* failed without needing a stack trace.
/// [expected] marks a catch that's already documented as intentionally
/// best-effort (e.g. [VaultExplorerApi.cancelUnlock] racing a call that's
/// about to resolve on its own) — those still get logged, but tagged
/// separately so they don't read as equally alarming as a genuine
/// unexpected failure such as a corrupted container header or a revoked
/// SAF permission.
void _logSwallowed(String method, Object error, {bool expected = false}) {
  debugPrint(
    '${expected ? '[VaultExplorerApi:expected]' : '[VaultExplorerApi]'} '
    '$method failed: $error',
  );
}

class VaultExplorerApi {
  const VaultExplorerApi();

  static const _channel = MethodChannel('com.aeidolon.vaultexplorer/engine');

  static void Function(String ext, String pkg)? onAppSelectedCallback;


  static final List<void Function(int volId)> _usbContainerDetachedListeners =
      [];

  static void addUsbContainerDetachedListener(
    void Function(int volId) listener,
  ) {
    _usbContainerDetachedListeners.add(listener);
  }

  static void removeUsbContainerDetachedListener(
    void Function(int volId) listener,
  ) {
    _usbContainerDetachedListeners.remove(listener);
  }


  static final List<void Function()> _screenOffListeners = [];

  static void addScreenOffListener(void Function() listener) {
    _screenOffListeners.add(listener);
  }

  static void removeScreenOffListener(void Function() listener) {
    _screenOffListeners.remove(listener);
  }

  // ── Unlock progress / cancellation ──────────────────────────────────────
  //
  // "onUnlockStarted" fires once, synchronously from the native method call
  // handler, as soon as a volId has been allocated for this attempt — before
  // the (potentially several-second) auto-detect search actually begins.
  // "onUnlockProgress" then fires repeatedly during that search. Listeners
  // should filter on volId themselves if more than one unlock could be in
  // flight (in practice: at most one per UnlockSheet/UsbUnlockSheet instance).

  static final List<void Function(int volId)> _unlockStartedListeners = [];
  static final List<void Function(UnlockProgress progress)>
      _unlockProgressListeners = [];

  static void addUnlockStartedListener(void Function(int volId) listener) {
    _unlockStartedListeners.add(listener);
  }

  static void removeUnlockStartedListener(void Function(int volId) listener) {
    _unlockStartedListeners.remove(listener);
  }

  static void addUnlockProgressListener(
    void Function(UnlockProgress progress) listener,
  ) {
    _unlockProgressListeners.add(listener);
  }

  static void removeUnlockProgressListener(
    void Function(UnlockProgress progress) listener,
  ) {
    _unlockProgressListeners.remove(listener);
  }

  // ── Import progress ───────────────────────────────────────────────────
  //
  // "onImportProgress" fires repeatedly from native while importFile/
  // importFolder is running. Listeners should filter on opId themselves if
  // more than one import could be in flight (see FileOperationService, the
  // only current subscriber).

  static final List<void Function(ImportProgress progress)>
      _importProgressListeners = [];

  static void addImportProgressListener(
    void Function(ImportProgress progress) listener,
  ) {
    _importProgressListeners.add(listener);
  }

  static void removeImportProgressListener(
    void Function(ImportProgress progress) listener,
  ) {
    _importProgressListeners.remove(listener);
  }

  static void initMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onAppSelected') {
        final ext = call.arguments['extension'] as String?;
        final pkg = call.arguments['package'] as String?;
        if (ext != null && pkg != null) {
          onAppSelectedCallback?.call(ext, pkg);
        }
      } else if (call.method == 'onUsbContainerDetached') {
        final volId = call.arguments['volId'] as int?;
        if (volId != null) {
          for (final listener in List.of(_usbContainerDetachedListeners)) {
            listener(volId);
          }
        }
      } else if (call.method == 'onScreenOff') {
        for (final listener in List.of(_screenOffListeners)) {
          listener();
        }
      } else if (call.method == 'onUnlockStarted') {
        final volId = call.arguments['volId'] as int?;
        if (volId != null) {
          for (final listener in List.of(_unlockStartedListeners)) {
            listener(volId);
          }
        }
      } else if (call.method == 'onUnlockProgress') {
        final args = call.arguments as Map<Object?, Object?>;
        final volId = args['volId'] as int?;
        final attempted = args['attempted'] as int?;
        final total = args['total'] as int?;
        if (volId != null && attempted != null && total != null) {
          final progress = (
            volId: volId,
            attempted: attempted,
            total: total,
            hashId: args['hashId'] as int? ?? 255,
            cipherId: args['cipherId'] as int? ?? 255,
            containerFormat: args['containerFormat'] as String? ?? 'veracrypt',
          );
          for (final listener in List.of(_unlockProgressListeners)) {
            listener(progress);
          }
        }
      } else if (call.method == 'onImportProgress') {
        final args = call.arguments as Map<Object?, Object?>;
        final opId = args['opId'] as int?;
        final done = args['done'] as int?;
        final total = args['total'] as int?;
        if (opId != null && done != null && total != null) {
          final progress = (
            opId: opId,
            done: done,
            total: total,
            currentName: args['currentName'] as String? ?? '',
          );
          for (final listener in List.of(_importProgressListeners)) {
            listener(progress);
          }
        }
      }
    });
  }

  static final Set<int> _activeBatches = {};
  static final Set<int> _lockPending = {};

  void beginBatch(int volId) {
    _activeBatches.add(volId);
  }

  void endBatch(int volId) {
    _activeBatches.remove(volId);
  }

  bool hasActiveBatch(int volId) => _activeBatches.contains(volId);

  /// Attempts to acquire the lock guard for [volId].
  ///
  /// Returns `true` if:
  /// - No batch is active for [volId], AND
  /// - No lock is already pending for [volId].
  ///
  /// If this returns `true` the caller MUST call [releaseLockGuard] after
  /// the lock operation completes (success or failure).

  bool acquireLockGuard(int volId) {
    if (_activeBatches.contains(volId) || _lockPending.contains(volId)) {
      return false;
    }
    _lockPending.add(volId);
    return true;
  }

  void releaseLockGuard(int volId) {
    _lockPending.remove(volId);
  }

  // ── Crypto ─────────────────────────────────────────────────────────────────

  /// PBKDF2-SHA512 via the C++ mbedTLS layer.
  ///
  /// Returns 64 raw bytes of derived key, or null on failure.
  /// [salt] must be non-empty (16 bytes recommended).
  Future<Uint8List?> hashPassword({
    required String password,
    required Uint8List salt,
    int iterations = 200000,
  }) async {
    assert(salt.isNotEmpty, 'salt must not be empty');
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.hashPassword,
      {'password': password, 'salt': salt, 'iterations': iterations},
    );
    return result;
  }

  Future<Uint8List?> deriveDerivedKey({
    required String filePath,
    required String password,
    required int pim,
    int? cipherId,
    int? hashId,
    List<String>? keyfilePaths,
  }) async {
    final result = await _channel.invokeMethod<String>(
      ChannelMethods.deriveDerivedKey,
      {
        'filePath': filePath,
        'password': password,
        'pim': pim,
        'cipherId': cipherId ?? 255,
        'hashId': hashId ?? 255,
        if (keyfilePaths != null && keyfilePaths.isNotEmpty)
          'keyfilePaths': keyfilePaths,
      },
    );
    if (result == null || result.isEmpty) return null;
    return base64Decode(result);
  }

  Future<bool> storeDerivedKey(String filePath, Uint8List derivedKey) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.storeDerivedKey,
      {'filePath': filePath, 'derivedKey': base64Encode(derivedKey)},
    );
    return result ?? false;
  }

  Future<Uint8List?> loadDerivedKey(String filePath) async {
    final result = await _channel.invokeMethod<String>(
      ChannelMethods.loadDerivedKey,
      {'filePath': filePath},
    );
    if (result == null || result.isEmpty) return null;
    return base64Decode(result);
  }

  Future<bool> clearDerivedKey(String filePath) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.clearDerivedKey,
      {'filePath': filePath},
    );
    return result ?? false;
  }

  // ── Container lifecycle ───────────────────────────────────────────────────

  /// [containerFormat]: 0 = VeraCrypt, 1 = LUKS1, 2 = LUKS2 (see
  /// [CreateFormat] in crypto_algorithms.dart) — matches the native
  /// ContainerFormat ordinal.
  ///
  /// [keyfilePaths]: for VeraCrypt, keyfiles mix ADDITIVELY into
  /// [password] (an empty password with keyfiles alone is valid, matching
  /// real VeraCrypt). For LUKS, a keyfile REPLACES [password] entirely
  /// (matching real `cryptsetup --key-file`) and only the first keyfile is
  /// used.
  Future<bool> createContainer({
    required String displayName,
    required int sizeBytes,
    required String password,
    required int pim,
    required String fileSystem,
    int containerFormat = 0,
    required int cipherId,
    required int hashId,
    required List<String> keyfilePaths,
    bool createHiddenVolume = false,
    String? hiddenPassword,
    String? hiddenFileSystem,
    int? hiddenSizeBytes,
    List<String>? hiddenKeyfilePaths,
    int? hiddenPim,
    int? hiddenCipherId,
    int? hiddenHashId,
  }) async {
    try {
      final success = await _channel
          .invokeMethod<bool>(ChannelMethods.createContainer, {
        'displayName': displayName,
        'sizeBytes': sizeBytes,
        'password': password,
        'pim': pim,
        'fileSystem': fileSystem,
        'containerFormat': containerFormat,
        'cipherId': cipherId,
        'hashId': hashId,
        'keyfilePaths': keyfilePaths,
        'createHiddenVolume': createHiddenVolume,
        'hiddenPassword': hiddenPassword,
        'hiddenFileSystem': hiddenFileSystem,
        'hiddenSizeBytes': hiddenSizeBytes,
        'hiddenKeyfilePaths': hiddenKeyfilePaths ?? [],
        'hiddenPim': hiddenPim,
        'hiddenCipherId': hiddenCipherId,
        'hiddenHashId': hiddenHashId,
      });
      return success ?? false;
    } catch (e) {
      _logSwallowed('createContainer', e);
      return false;
    }
  }

/// Returns usable capacity in bytes (device capacity minus the MBR
/// partition offset), or null on failure. Requires [deviceName] to
/// already have USB permission granted.
Future<int?> getUsbDeviceCapacity(String deviceName) async {
  try {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.getUsbDeviceCapacity,
      {'deviceName': deviceName},
    );
    return result;
  } on PlatformException catch (e) {
    _logSwallowed('getUsbDeviceCapacity', e);
    return null;
  }
}
  Future<bool> createUsbContainer({
    required String deviceName,
    required int sizeBytes,
    required String password,
    required int pim,
    required String fileSystem,
    int containerFormat = 0,
    required int cipherId,
    required int hashId,
    required List<String> keyfilePaths,
    String partitionScheme = 'mbr',
    bool quickFormat = false,
    bool createHiddenVolume = false,
    String? hiddenPassword,
    String? hiddenFileSystem,
    int? hiddenSizeBytes,
    List<String>? hiddenKeyfilePaths,
    int? hiddenPim,
    int? hiddenCipherId,
    int? hiddenHashId,
  }) async {
    try {
      final success = await _channel
          .invokeMethod<bool>(ChannelMethods.createUsbContainer, {
        'deviceName': deviceName,
        'sizeBytes': sizeBytes,
        'password': password,
        'pim': pim,
        'fileSystem': fileSystem,
        'containerFormat': containerFormat,
        'cipherId': cipherId,
        'hashId': hashId,
        'keyfilePaths': keyfilePaths,
        'partitionScheme': partitionScheme,
        'quickFormat': quickFormat,
        'createHiddenVolume': createHiddenVolume,
        'hiddenPassword': hiddenPassword,
        'hiddenFileSystem': hiddenFileSystem,
        'hiddenSizeBytes': hiddenSizeBytes,
        'hiddenKeyfilePaths': hiddenKeyfilePaths ?? [],
        'hiddenPim': hiddenPim,
        'hiddenCipherId': hiddenCipherId,
        'hiddenHashId': hiddenHashId,
      });
      return success ?? false;
    } catch (e) {
      _logSwallowed('createUsbContainer', e);
      return false;
    }
  }

  /// Changes the password (and optionally PIM) of a VeraCrypt container.
  /// For LUKS containers, password change is not supported in-app — the user
  /// should use `cryptsetup luksChangeKey` on a Linux machine.
  Future<bool> changeContainerPassword({
    required String uri,
    required String oldPassword,
    required String newPassword,
    int oldPim = 0,
    int newPim = 0,
    int cipherId = 255,
    int hashId = 255,
    List<String>? oldKeyfilePaths,
    List<String>? newKeyfilePaths,
  }) async {
    try {
      final success = await _channel
          .invokeMethod<bool>(ChannelMethods.changeContainerPassword, {
        'uri': uri,
        'oldPassword': oldPassword,
        'newPassword': newPassword,
        'oldPim': oldPim,
        'newPim': newPim,
        'cipherId': cipherId,
        'hashId': hashId,
        'oldKeyfilePaths': oldKeyfilePaths ?? [],
        'newKeyfilePaths': newKeyfilePaths ?? [],
      });
      return success ?? false;
    } catch (e) {
      _logSwallowed('changeContainerPassword', e);
      return false;
    }
  }

  Future<({String uri, String displayName})?> pickContainer() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.pickContainer,
    );
    if (raw == null) return null;
    return (
      uri: raw['uri'] as String,
      displayName: raw['displayName'] as String,
    );
  }

  /// Opens a multi-select document picker for keyfiles. Returns an empty
  /// list if the user cancels. Any file type is a valid keyfile (VeraCrypt
  /// keyfile mixing just hashes the raw bytes — a photo, an mp3, a random
  /// binary blob are all equally valid), so this doesn't filter by
  /// extension or mime type.
  Future<List<KeyfileRef>> pickKeyfiles() async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.pickKeyfiles,
    );
    if (raw == null) return [];
    return raw
        .cast<Map<Object?, Object?>>()
        .map((m) => (
              uri: m['uri'] as String,
              displayName: m['displayName'] as String,
            ))
        .toList();
  }

  /// Opens a folder picker (ACTION_OPEN_DOCUMENT_TREE) for selecting a
  /// Cryptomator vault — vaults are directory trees (vault.cryptomator +
  /// masterkey.cryptomator + d/), not single files, so this is distinct from
  /// [pickContainer]. [looksLikeVault] is a quick heuristic (checks for
  /// masterkey.cryptomator) the caller can use to warn the user immediately
  /// if they picked an unrelated folder, before asking for a password.
  Future<({String uri, String displayName, bool looksLikeVault})?> pickCryptomatorVault() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.pickCryptomatorVault,
    );
    if (raw == null) return null;
    return (
      uri: raw['uri'] as String,
      displayName: raw['displayName'] as String,
      looksLikeVault: raw['looksLikeVault'] as bool? ?? false,
    );
  }

  /// Unlocks a Cryptomator vault. Result shape matches [unlockContainer]
  /// exactly (containerFormat: 'cryptomator') so callers can treat the two
  /// uniformly once unlocked. matchedCipherId/matchedHashId are always 255
  /// (not applicable — Cryptomator's cipher suite is fixed per vault format,
  /// not user-selectable).
  Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockCryptomatorVault(
    String filePath,
    String password, {
    String? displayName,
    bool documentProvider = false,
    bool readOnly = false,
  }) async {
    final raw = await _channel
        .invokeMethod<Map<Object?, Object?>>(ChannelMethods.unlockCryptomatorVault, {
          'filePath': filePath,
          'password': password,
          'displayName': displayName,
          'documentProvider': documentProvider,
          'readOnly': readOnly,
        });
    if (raw == null) return null;
    final files = (raw['files'] as List<Object?>).cast<String>();
    return (
      volId: raw['volId'] as int,
      files: files,
      matchedCipherId: raw['matchedCipherId'] as int? ?? 255,
      matchedHashId: raw['matchedHashId'] as int? ?? 255,
      containerFormat: raw['containerFormat'] as String? ?? 'cryptomator',
    );
  }

  /// Creates a new Cryptomator vault (always vault format 8 / SIV_GCM) in
  /// an empty folder the user already granted tree access to via
  /// [pickCryptomatorVault]. The vault is left locked afterward — the
  /// caller should unlock it explicitly via [unlockCryptomatorVault], same
  /// as [createContainer] leaves VeraCrypt/LUKS containers locked.
  Future<bool> createCryptomatorVault(String folderUri, String password) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.createCryptomatorVault,
        {'filePath': folderUri, 'password': password},
      );
      return success ?? false;
    } catch (e) {
      _logSwallowed('createCryptomatorVault', e);
      return false;
    }
  }

  /// Opens a folder picker (ACTION_OPEN_DOCUMENT_TREE) for selecting a
  /// Gocryptfs vault — vaults are directory trees (gocryptfs.conf +
  /// gocryptfs.diriv), not single files, so this is distinct from
  /// [pickContainer]. [looksLikeVault] is a quick heuristic the caller can
  /// use to warn the user immediately if they picked an unrelated folder,
  /// before asking for a password.
  Future<({String uri, String displayName, bool looksLikeVault})?> pickGocryptfsVault() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.pickGocryptfsVault,
    );
    if (raw == null) return null;
    return (
      uri: raw['uri'] as String,
      displayName: raw['displayName'] as String,
      looksLikeVault: raw['looksLikeVault'] as bool? ?? false,
    );
  }

  /// Unlocks a Gocryptfs vault. Result shape matches [unlockContainer]
  /// exactly (containerFormat: 'gocryptfs') so callers can treat the two
  /// uniformly once unlocked. matchedCipherId/matchedHashId are always 255
  /// (not applicable — Gocryptfs's cipher suite is fixed per vault format,
  /// not user-selectable).
  Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockGocryptfsVault(
    String filePath,
    String password, {
    String? displayName,
    bool documentProvider = false,
    bool readOnly = false,
  }) async {
    final raw = await _channel
        .invokeMethod<Map<Object?, Object?>>(ChannelMethods.unlockGocryptfsVault, {
          'filePath': filePath,
          'password': password,
          'displayName': displayName,
          'documentProvider': documentProvider,
          'readOnly': readOnly,
        });
    if (raw == null) return null;
    final files = (raw['files'] as List<Object?>).cast<String>();
    return (
      volId: raw['volId'] as int,
      files: files,
      matchedCipherId: raw['matchedCipherId'] as int? ?? 255,
      matchedHashId: raw['matchedHashId'] as int? ?? 255,
      containerFormat: raw['containerFormat'] as String? ?? 'gocryptfs',
    );
  }

  /// Creates a new Gocryptfs vault in an empty folder the user already
  /// granted tree access to via [pickGocryptfsVault]. The vault is left
  /// locked afterward — the caller should unlock it explicitly via
  /// [unlockGocryptfsVault].
  Future<bool> createGocryptfsVault(String folderUri, String password) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.createGocryptfsVault,
        {'filePath': folderUri, 'password': password},
      );
      return success ?? false;
    } catch (e) {
      _logSwallowed('createGocryptfsVault', e);
      return false;
    }
  }

  /// Must be called once after the final [writeFileChunk] call in a
  /// sequence for a given [fileName], to flush Cryptomator's buffered final
  /// (possibly partial) chunk and materialize the file. Safe to call
  /// unconditionally for any container — it's a no-op for VeraCrypt/LUKS.
  Future<bool> finishWriteIfCryptomator(
    MountedContainer container,
    String fileName,
  ) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.finishWriteIfCryptomator,
        {'volId': container.volId, 'path': fileName},
      );
      return success ?? true;
    } catch (e) {
      _logSwallowed('finishWriteIfCryptomator', e);
      return true;
    }
  }

  /// Asks native to abort the in-flight unlock for [volId] (see
  /// [addUnlockStartedListener] for how the caller learns [volId] before the
  /// original [unlockContainer]/[unlockUsbContainer] call has resolved).
  ///
  /// Fire-and-forget and best-effort: this doesn't itself throw or resolve
  /// the pending unlock — that call will still complete on its own shortly
  /// after, but with a `PlatformException(code: 'CANCELLED')` instead of a
  /// result, once native notices the request. Safe to call more than once,
  /// or after the unlock has already finished.
  Future<void> cancelUnlock(int volId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelUnlock, {'volId': volId});
    } catch (e) {
      // Best-effort — the pending unlock call resolves on its own regardless.
      _logSwallowed('cancelUnlock', e, expected: true);
    }
  }

 Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockContainer(
    String filePath,
    String password,
    int pim, {
    String? displayName,
    bool documentProvider = false,
    int? cipherId,
    int? hashId,
    Uint8List? preservedKey,
    bool cacheDerivedKey = false,
    List<String>? keyfilePaths,
    bool readOnly = false,
  }) async {
    final raw = await _channel
        .invokeMethod<Map<Object?, Object?>>(ChannelMethods.unlockContainer, {
          'filePath': filePath,
          'password': password,
          'pim': pim,
          'displayName': displayName,
          'documentProvider': documentProvider,
          'cipherId': cipherId ?? 255,
          'hashId': hashId ?? 255,
          if (preservedKey != null) 'preservedKey': base64Encode(preservedKey),
          'cacheDerivedKey': cacheDerivedKey,
          if (keyfilePaths != null && keyfilePaths.isNotEmpty)
            'keyfilePaths': keyfilePaths,
            'readOnly': readOnly,
        });
    if (raw == null) return null;
    final volId = raw['volId'] as int;
    final files = (raw['files'] as List<Object?>).cast<String>();
    return (
      volId: volId,
      files: files,
      matchedCipherId: raw['matchedCipherId'] as int? ?? 255,
      matchedHashId: raw['matchedHashId'] as int? ?? 255,
      containerFormat: raw['containerFormat'] as String? ?? 'veracrypt',
    );
  }

  /// Checks whether the document/file at [filePath] (a content:// SAF uri
  /// or a plain file:// path) can currently be resolved — without
  /// attempting to unlock it. Returns false for a container living on
  /// removable storage that's been disconnected or a file that was moved
  /// or deleted, and also false if a previously-granted content:// SAF
  /// permission was revoked (e.g. after removing and re-inserting an SD
  /// card resets the grant).
  Future<bool> documentExists(String filePath) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        ChannelMethods.documentExists,
        {'filePath': filePath},
      );
      return result ?? false;
    } catch (e) {
      // Treat a failed check as "unknown", not "missing" — let the normal
      // unlock attempt surface the real error rather than blocking access
      // to a container that might actually be fine.
      _logSwallowed('documentExists', e, expected: true);
      return true;
    }
  }

  /// Speculatively warms [filePath] for a subsequent [unlockContainer]
  /// call: opens it read-only, reads a small prefix, closes it again.
  /// Fire-and-forget — no fd is held open, so there's nothing to cancel or
  /// clean up if the user backs out. Purely a latency optimization; on SAF
  /// providers this overlaps the binder round trip (and, for cloud-backed
  /// providers, the network fetch) with the time the user spends typing
  /// their password instead of paying it after they tap "Unlock."
  void warmContainer(String filePath) {
    _channel
        .invokeMethod(ChannelMethods.warmContainer, {'filePath': filePath})
        .catchError((e) => _logSwallowed('warmContainer', e, expected: true));
  }
  Future<List<UsbDeviceInfo>> listUsbDevices() async {
    final raw = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.listUsbDevices,
    );
    if (raw == null) return [];
    return raw
        .cast<Map<Object?, Object?>>()
        .map((m) => UsbDeviceInfo(
              deviceName: m['deviceName'] as String,
              productName: m['productName'] as String,
              hasPermission: m['hasPermission'] as bool,
            ))
        .toList();
  }

  Future<bool> requestUsbPermission(String deviceName) async {
    try {
      final granted = await _channel.invokeMethod<bool>(
        ChannelMethods.requestUsbPermission,
        {'deviceName': deviceName},
      );
      return granted ?? false;
    } on PlatformException {
      return false;
    }
  }

 Future<({int volId, List<String> files, int matchedCipherId, int matchedHashId, String containerFormat})?> unlockUsbContainer(
    String deviceName,
    String password,
    int pim, {
    String? displayName,
    bool documentProvider = false,
    int? cipherId,
    int? hashId,
    Uint8List? preservedKey,
    bool cacheDerivedKey = false,
    List<String>? keyfilePaths,
    bool readOnly = false,
  }) async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
      ChannelMethods.unlockUsbContainer,
      {
        'deviceName': deviceName,
        'password': password,
        'pim': pim,
        'displayName': displayName,
        'documentProvider': documentProvider,
        'cipherId': cipherId ?? 255,
        'hashId': hashId ?? 255,
        if (preservedKey != null) 'preservedKey': base64Encode(preservedKey),
        'cacheDerivedKey': cacheDerivedKey,
        if (keyfilePaths != null && keyfilePaths.isNotEmpty)
          'keyfilePaths': keyfilePaths,
          'readOnly': readOnly,
      },
    );
    if (raw == null) return null;
    final volId = raw['volId'] as int;
    final files = (raw['files'] as List<Object?>).cast<String>();
    return (
      volId: volId,
      files: files,
      matchedCipherId: raw['matchedCipherId'] as int? ?? 255,
      matchedHashId: raw['matchedHashId'] as int? ?? 255,
      containerFormat: raw['containerFormat'] as String? ?? 'veracrypt',
    );
  }

  Future<bool> lockContainer(String filePath) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.lockContainer,
      {'filePath': filePath},
    );
    return result ?? false;
  }

  Future<bool> updateContainerSettings(
    String filePath,
    String displayName,
    bool documentProvider,
  ) async {
    final result = await _channel
        .invokeMethod<bool>(ChannelMethods.updateContainerSettings, {
          'filePath': filePath,
          'displayName': displayName,
          'documentProvider': documentProvider,
        });
    return result ?? false;
  }

  // ── File I/O ──────────────────────────────────────────────────────────────

  Future<bool> openWithApp(
    MountedContainer container,
    String fileName, {
    String? packageName,
  }) async {
    final result = await _channel
        .invokeMethod<bool>(ChannelMethods.openWithApp, {
          'filePath': container.uri,
          'fileName': fileName,
          'packageName': packageName,
        });
    return result ?? false;
  }

  Future<bool> decryptFile(
    MountedContainer container,
    String fileName,
    String destPath,
  ) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.decryptFile,
      {'filePath': container.uri, 'fileName': fileName, 'destPath': destPath},
    );
    return result ?? false;
  }

  Future<bool> exportFileToStorage(
    MountedContainer container,
    String sourcePath,
  ) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.exportFileToStorage,
      {'filePath': container.uri, 'sourcePath': sourcePath},
    );
    return result ?? false;
  }

  Future<int> getFileSize(MountedContainer container, String fileName) async {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.getFileSize,
      {'filePath': container.uri, 'fileName': fileName},
    );
    return result ?? 0;
  }

  /// Returns the recursive byte total of all files inside [dirPath].
  ///
  /// This is a potentially slow operation for large directory trees; callers
  /// should invoke it on a background-triggered path (e.g. from
  /// [SelectionMixin.fetchFolderSizes]) rather than on every build cycle.
  ///
  /// Returns 0 if the container is not mounted or the directory is empty.
  Future<int> getFolderSize(MountedContainer container, String dirPath) async {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.getFolderSize,
      {'filePath': container.uri, 'dirPath': dirPath},
    );
    return result ?? 0;
  }

  Future<Uint8List?> readFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    int length,
  ) async {
    final result = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.readFileChunk,
      {
        'filePath': container.uri,
        'fileName': fileName,
        'offset': offset,
        'length': length,
      },
    );
    return result;
  }

  /// Requests a scaled image thumbnail from the native Android JPEG pipeline.
  /// Returns null on failure — callers will display a standard file fallback.
  Future<Uint8List?> getImageThumbnail(
    MountedContainer container,
    String fileName, {
    int targetSize = 180,
    int quality = 70,
  }) async {
    try {
      final Uint8List? bytes = await _channel.invokeMethod<Uint8List>(
        'getImageThumbnail',
        {
          'filePath': container.uri,
          'fileName': fileName,
          'targetSize': targetSize,
          'quality': quality,
        },
      );
      return bytes;
    } catch (e) {
      _logSwallowed('getImageThumbnail', e, expected: true);
      return null;
    }
  }

  /// Triggers thumbnail generation and encryption entirely on native threads,
  /// bypassing Dart and saving directly to local App Cache [ThumbnailCacheMode.appCache].
  Future<void> generateAndCacheThumbnail({
    required MountedContainer container,
    required String filePath,
    required List<int> keyBytes,
    int quality = 70,
    int targetSize = 180,
  }) async {
    try {
      await _channel.invokeMethod<void>('generateAndCacheThumbnail', {
        'filePath': container.uri,
        'fileName': filePath,
        'keyBytes': Uint8List.fromList(keyBytes),
        'quality': quality,
        'targetSize': targetSize,
      });
    } catch (e) {
      _logSwallowed('generateAndCacheThumbnail', e, expected: true);
    }
  }

  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath,
  ) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.listDirectory,
      {'filePath': container.uri, 'dirPath': dirPath},
    );
    return result?.cast<String>();
  }

  Future<bool> createDirectory(
    MountedContainer container,
    String dirPath,
  ) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.createDirectory,
      {'filePath': container.uri, 'dirPath': dirPath},
    );
    return result ?? false;
  }

  Future<bool> renameFile(
    MountedContainer container,
    String oldPath,
    String newPath,
  ) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.renameFile,
      {'filePath': container.uri, 'oldPath': oldPath, 'newPath': newPath},
    );
    return result ?? false;
  }

  Future<bool> writeFileChunk(
    MountedContainer container,
    String fileName,
    int offset,
    Uint8List data,
  ) async {
    final result = await _channel.invokeMethod<bool>('writeFileChunk', {
      'filePath': container.uri,
      'fileName': fileName,
      'offset': offset,
      'data': data,
    });
    return result ?? false;
  }

  Future<bool> deleteFile(MountedContainer container, String fileName) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.deleteFile,
      {'filePath': container.uri, 'fileName': fileName},
    );
    return result ?? false;
  }

  Future<bool> setLastModifiedTime(
    MountedContainer container,
    String fileName,
    int epochSeconds,
  ) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.setLastModifiedTime,
      {
        'filePath': container.uri,
        'fileName': fileName,
        'epochSeconds': epochSeconds,
      },
    );
    return result ?? false;
  }

  Future<bool> writeBackFile(
    MountedContainer container,
    String fileName,
    String sourcePath,
  ) async {
    final result = await _channel.invokeMethod<bool>(
      ChannelMethods.writeBackFile,
      {
        'filePath': container.uri,
        'fileName': fileName,
        'sourcePath': sourcePath,
      },
    );
    return result ?? false;
  }

  Future<bool> createEmptyFile(
    MountedContainer container,
    String fileName,
  ) async {
    final tmpDir = await getTemporaryDirectory();
    final tempFile = File(
      '${tmpDir.path}/cb_empty_${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await tempFile.create(recursive: true);
      return await writeBackFile(container, fileName, tempFile.path);
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
    }
  }

  Future<List<int>?> getSpaceInfo(MountedContainer container) async {
    final result = await _channel.invokeMethod<List<Object?>>(
      ChannelMethods.getSpaceInfo,
      {'filePath': container.uri},
    );
    return result?.cast<int>();
  }

  /// [opId] is the caller's [FileOperation.id] — native echoes it back on
  /// every "onImportProgress" push and matches it against
  /// [cancelImport] requests.
  Future<int> importFiles(
    MountedContainer container,
    String targetPath,
    int opId,
  ) async {
    final result = await _channel.invokeMethod<int>(ChannelMethods.importFile, {
      'filePath': container.uri,
      'targetPath': targetPath,
      'opId': opId,
    });
    return result ?? 0;
  }

  Future<int> exportSelectedToFolder(
    MountedContainer container,
    List<Map<String, dynamic>> items,
  ) async {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.exportFilesToFolder,
      {'filePath': container.uri, 'items': items},
    );
    return result ?? 0;
  }

  /// [opId] is the caller's [FileOperation.id] — native echoes it back on
  /// every "onImportProgress" push and matches it against
  /// [cancelImport] requests.
  Future<int> importFolder(
    MountedContainer container,
    String targetPath,
    int opId,
  ) async {
    final result = await _channel.invokeMethod<int>(
      ChannelMethods.importFolder,
      {'filePath': container.uri, 'targetPath': targetPath, 'opId': opId},
    );
    return result ?? 0;
  }

  /// Asks native to abort the in-flight import identified by [opId] (the
  /// [FileOperation.id] originally passed into [importFiles]/[importFolder]).
  ///
  /// Fire-and-forget and best-effort: this doesn't itself throw or resolve
  /// the pending import — that call will still complete on its own shortly
  /// after, but with a `PlatformException(code: 'CANCELLED')` instead of a
  /// result, once native notices the request between files. Files already
  /// written before that point stay in place. Safe to call more than once,
  /// or after the import has already finished.
  Future<void> cancelImport(int opId) async {
    try {
      await _channel.invokeMethod(ChannelMethods.cancelImport, {'opId': opId});
    } catch (e) {
      // Best-effort — the pending import call resolves on its own regardless.
      _logSwallowed('cancelImport', e, expected: true);
    }
  }

  /// Requests a scaled video thumbnail from the native layer.
  /// Returns null on any error — callers should show a fallback icon.
  Future<Uint8List?> getVideoThumbnail(
  MountedContainer container,
  String fileName, {
  int quality = 60,
  int targetSize = 180,
}) async {
  try {
    final Uint8List? bytes = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.getVideoThumbnail,
      {
        'filePath': container.uri,
        'fileName': fileName,
        'quality': quality,
        'targetSize': targetSize,
      },
    );
    return bytes;
  } catch (e) {
    _logSwallowed('getVideoThumbnail', e, expected: true);
    return null;
  }
}

  Future<bool> setSecureScreen(bool enabled) async {
    try {
      final bool? success = await _channel.invokeMethod<bool>(
        ChannelMethods.setSecureScreen,
        {'enabled': enabled},
      );
      return success ?? false;
    } catch (e) {
      _logSwallowed('setSecureScreen', e);
      return false;
    }
  }

  /// Checks if the folder at [uri] contains a "gocryptfs.conf" file.
  Future<bool> isGocryptfsVault(String uri) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isGocryptfsVault',
        {'uri': uri},
      );
      return result ?? false;
    } catch (e) {
      _logSwallowed('isGocryptfsVault', e);
      return false;
    }
  }

}

final vaultExplorerApi = VaultExplorerApi();