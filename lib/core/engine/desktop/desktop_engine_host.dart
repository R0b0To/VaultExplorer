// The desktop implementation of the engine channel contract.
//
// On Android every call on the engine platform channel is answered by Kotlin handlers
// sitting on top of the native engine. On Linux/Windows there is no Kotlin; this class answers
// the SAME method names with the SAME argument and result shapes, backed by the C ABI through
// worker isolates. Because it speaks the existing contract, the ~7K lines of VaultXxxApi classes
// and everything above them run unchanged (see desktop_engine_binding.dart for how it is
// plugged in underneath `MethodChannel`).
//
// Scope of this first cut (see docs/desktop-port.md): open a VeraCrypt/LUKS/BitLocker/plain
// block container by path, browse, read, write, copy, rename, delete, lock. Everything else
// answers with a harmless default so the rest of the app can start; each unimplemented method
// is logged once in debug builds.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

import 'desktop_crypto.dart';
import 'desktop_external.dart';
import 'desktop_hash.dart';
import 'desktop_images.dart';
import 'desktop_secure_store.dart';
import 'desktop_split_join.dart';
import 'desktop_transfers.dart';
import 'engine_worker_pool.dart';
import 've_native.dart';

/// What the app is told about an active session (Android keeps this in ContainerSessionRegistry).
class _SessionMeta {
  _SessionMeta({required this.displayName, required this.format, required this.readOnly});
  String displayName;
  final String format;
  final bool readOnly;
}

class DesktopEngineHost {
  DesktopEngineHost({required this.pool, required this.emit, DesktopSecureStore? secureStore})
      : secureStore = secureStore ?? DesktopSecureStore();

  final EngineWorkerPool pool;

  /// Backs readSecure / writeSecure / ... (the OS keyring; see desktop_secure_store.dart).
  final DesktopSecureStore secureStore;

  /// Pushes a native->Dart call (e.g. `onUnlockProgress`) to the Dart side of the channel.
  final void Function(String method, Object? arguments) emit;

  /// Import / export between the host filesystem and a vault (see desktop_transfers.dart).
  late final DesktopTransfers _transfers = DesktopTransfers(
    pool: pool,
    volFor: _vol,
    emit: emit,
    native: () => _nativeLocal,
    withActivity: (body) => _withActivity<Object?>(body),
  );

  /// Container splitter tool (see desktop_split_join.dart).
  late final DesktopSplitJoin _splitJoin = DesktopSplitJoin(emit: emit);

  /// Checksum tool + digest sessions (see desktop_hash.dart).
  late final DesktopHash _hash = DesktopHash(pool);

  /// Hashing / KDF / AEAD primitives backed by the native engine (see desktop_crypto.dart).
  late final DesktopCrypto _crypto = DesktopCrypto(pool);

  /// Thumbnails / image export (Flutter codecs; see desktop_images.dart).
  late final DesktopImages _images = DesktopImages(readWhole: _readWholeVaultFile);

  /// Handing files to other apps + a few host-file helpers (see desktop_external.dart).
  final DesktopExternal _external = DesktopExternal();

  final Map<String, int> _volByUri = {};
  final Map<int, String> _uriByVol = {};
  final Map<int, _SessionMeta> _meta = {};
  final Set<String> _warned = {};
  int? _maxVolumes;

  // Event pump: the native event queue is polled (cheaply, on this isolate) only while an
  // operation that produces progress is in flight.
  VeNative? _native;
  Timer? _pump;
  int _activity = 0;

  VeNative get _nativeLocal => _native ??= VeNative.open();

  // Methods that exist only for Android integration; answered with the value a "nothing to do /
  // already granted" device would give, so callers that expect a reply keep working.
  static const Map<String, Object?> _androidOnlyDefaults = {
    'syncBackgroundService': null,
    'scheduleContainerAutoClose': null,
    'scheduleVaultSync': null,
    'canScheduleExactAlarms': true,
    'requestExactAlarmAccess': true,
    'isHeadlessSyncActive': false,
    'setNotificationLocale': null,
    'updateBackgroundServiceProgress': null,
    'hasAllFilesAccess': true,
    'requestAllFilesAccess': true,
    'hasOverlayPermission': true,
    'requestOverlayPermission': true,
    'hasUnrestrictedBattery': true,
    'openBatterySettings': true,
    'requestNotificationPermission': true,
    'openAppSettings': true,
    'getMountedContainerFolders': <Object?>[],
    'isShareTargetEnabled': false,
    'setShareTargetEnabled': null,
    'isUsbAttachPromptEnabled': false,
    'setUsbAttachPromptEnabled': null,
    'getAndroidSdkInt': 0,
    'setPlaybackActive': null,
    'finishWrite': true,
    'beginBatchWrite': true,
    'endBatchWrite': true,
    'beginBatchDelete': true,
    'endBatchDelete': true,
    'detectsAsPlainDiskImage': false,
    // Cached derived keys and biometric sentinel keys are Android Keystore features; on desktop
    // there is never one to clear, which is the success case of these idempotent calls.
    'clearDerivedKey': true,
    'storeDerivedKey': false,
    'loadDerivedKey': null,
    'setDerivedKeyExpiry': false,
    'getDerivedKeyExpiry': null,
    'deriveDerivedKey': null,
    'biometricKeyCreate': false,
    'clearCopyState': null,
    // Android window/OS integration with no desktop equivalent (or nothing to do): quiet no-ops.
    'setSecureScreen': null,
    'setRecentsSnapshotBlocked': null,
    'setDebugLogging': null,
    'checkPendingShareRequest': null,
    'checkPendingQuickCaptureRequest': null,
    'notifyResumedFramePainted': null,
    'warmContainer': null,
    'biometricKeyDelete': true,
  };

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments is Map ? Map<Object?, Object?>.from(call.arguments as Map) : const <Object?, Object?>{};
    switch (call.method) {
      case ChannelMethods.pickContainer:
        return _pickContainer();
      case ChannelMethods.pickCryptoFiles: // the "add a vault" picker (multi-select, composite-aware)
      case ChannelMethods.pickKeyfiles:
        return _pickFiles();
      case ChannelMethods.createContainer:
        return _createContainer(args);
      case ChannelMethods.documentExists:
        {
          final path = args['filePath'] as String?;
          return path != null && await File(path).exists();
        }
      case ChannelMethods.getVaultInfo:
        {
          final r = await pool.call('vaultInfo', [_vol(args['filePath'])]) as List<Object?>;
          final rc = r[0] as int;
          if (rc != veOk) {
            _throwFor(rc);
            return null;
          }
          return r[1];
        }

      // ── secret store (OS keyring) ──
      case ChannelMethods.readSecure:
        return secureStore.read(args['key'] as String);
      case ChannelMethods.writeSecure:
        {
          final key = args['key'] as String;
          final value = args['value'] as String?;
          return value == null ? secureStore.delete(key) : secureStore.write(key, value);
        }
      case ChannelMethods.deleteSecure:
        return secureStore.delete(args['key'] as String);
      case ChannelMethods.deleteAllSecure:
        return secureStore.deleteAll();
      case ChannelMethods.readAllSecure:
        return secureStore.readAll(
          prefixes: (args['prefixes'] as List<Object?>?)?.cast<String>(),
          excludePrefixes: (args['excludePrefixes'] as List<Object?>?)?.cast<String>(),
        );
      case ChannelMethods.containsKeySecure:
        return secureStore.containsKey(args['key'] as String);

      // ── import / export ──
      case ChannelMethods.pickImportFiles:
        return _transfers.pickImportFiles(args);
      case ChannelMethods.pickImportFolder:
        return _transfers.pickImportFolder(args);
      case ChannelMethods.cancelPickedImport:
        _transfers.cancelPickedImport(args['pickToken']);
        return null;
      case ChannelMethods.importFile:
      case ChannelMethods.importFolder:
        return _transfers.importPicked(args);
      case ChannelMethods.cancelImport:
        _transfers.cancel((args['opId'] as num?)?.toInt() ?? 0);
        return true;
      case ChannelMethods.cancelExport:
        _transfers.cancel((args['opId'] as num?)?.toInt() ?? 0);
        return null;
      case ChannelMethods.deleteImportSources:
        return _transfers.deleteImportSources((args['opId'] as num?)?.toInt() ?? 0);
      case ChannelMethods.clearImportSources:
        _transfers.clearImportSources((args['opId'] as num?)?.toInt() ?? 0);
        return true;
      case ChannelMethods.exportFilesToFolder:
        return _transfers.exportToFolder(args);
      case ChannelMethods.exportFileToStorage:
        return _transfers.exportFileToStorage(args);
      case ChannelMethods.decryptFile:
        return _transfers.decryptFile(args);

      case ChannelMethods.getActiveContainerSessions:
        return _activeSessions();
      case ChannelMethods.updateContainerSettings:
        {
          final vol = _volByUri[args['filePath']];
          final meta = vol == null ? null : _meta[vol];
          if (meta == null) return false;
          meta.displayName = (args['displayName'] as String?) ?? meta.displayName;
          return true;
        }
      case ChannelMethods.getDeviceCapabilityProfile:
        return _capabilityProfile();
      case ChannelMethods.getMirrorPushActivity:
        return {'activeCount': 0}; // no mirror proxy on desktop
      case ChannelMethods.purgeExpiredDerivedKeys:
        return <String>[]; // no cached derived keys on desktop

      // ── images ──
      case ChannelMethods.getImageThumbnail:
        {
          final t = await _images.thumbnail(_vol(args['filePath']), args['fileName'] as String,
              targetSize: (args['targetSize'] as num?)?.toInt() ?? 180);
          return t?.bytes;
        }
      case ChannelMethods.getImageThumbnailWithSize:
        {
          final t = await _images.thumbnail(_vol(args['filePath']), args['fileName'] as String,
              targetSize: (args['targetSize'] as num?)?.toInt() ?? 180);
          return t == null ? null : {'bytes': t.bytes, 'width': t.width, 'height': t.height};
        }
      case ChannelMethods.encodeImage:
        return _images.encode(args);

      // ── other applications ──
      case ChannelMethods.launchUrl:
        return _external.launchUrl(args['url'] as String? ?? '');
      case ChannelMethods.openLocalFileWithApp:
        return _external.openLocalFile(args['filePath'] as String? ?? '');
      case ChannelMethods.getLocalFileUri:
        return args['filePath'] is String ? Uri.file(args['filePath'] as String).toString() : null;
      case ChannelMethods.openWithApp:
        return _openVaultFileWithApp(args);
      case ChannelMethods.readExternalFileBytes:
        return _external.readFileBytes(args['uri'] as String? ?? '');
      case ChannelMethods.writeExternalFileBytes:
        await _external.writeFileBytes(
          (args['destinationPath'] ?? args['destinationTreeUri']) as String,
          args['fileName'] as String,
          args['bytes'] as Uint8List,
        );
        return null;

      // ── digests ──
      case ChannelMethods.hashBytesSha256:
        return _hash.bytesHex(veHashSha256, args['bytes'] as Uint8List);
      case ChannelMethods.hashBytesMd5:
        return _hash.bytesHex(veHashMd5, args['bytes'] as Uint8List);
      case ChannelMethods.beginHashSession:
        await _hash.begin((args['opId'] as num).toInt(), (args['algorithms'] as List<Object?>).cast<String>());
        return null;
      case ChannelMethods.updateHashSession:
        await _hash.update((args['opId'] as num).toInt(), args['bytes'] as Uint8List);
        return null;
      case ChannelMethods.finishHashSession:
        return _hash.finish((args['opId'] as num).toInt());
      case ChannelMethods.discardHashSession:
        await _hash.discard((args['opId'] as num).toInt());
        return null;
      case ChannelMethods.cancelHashCompute:
        _hash.cancel((args['opId'] as num).toInt());
        return null;
      case ChannelMethods.computeExternalFileHash:
        return _hash.computeExternalFile(
          args['uri'] as String,
          (args['algorithms'] as List<Object?>).cast<String>(),
          (args['opId'] as num?)?.toInt() ?? 0,
        );

      // ── single-file encryption tool ──
      case ChannelMethods.encryptSingleFile:
        return _singleFileCrypt(args, encrypt: true);
      case ChannelMethods.decryptSingleFile:
        return _singleFileCrypt(args, encrypt: false);
      case ChannelMethods.splitContainer:
        await _splitJoin.split(args);
        return null;
      case ChannelMethods.joinContainer:
        await _splitJoin.join(args);
        return null;
      case ChannelMethods.cancelSplitJoin:
        if (args['opId'] is num) {
          final id = (args['opId'] as num).toInt();
          _splitJoin.cancel(id); // split / join run in Dart
          _nativeLocal.opCancel(id); // single-file encryption runs in the engine
        }
        return true; // Android answers true here

      // ── change a container's password ──
      case ChannelMethods.changeContainerPassword:
        return _changePassword(args, luks: false);
      case ChannelMethods.changeLuksContainerPassword:
        return _changePassword(args, luks: true);

      case ChannelMethods.probeContainerFormat:
        return await pool.call('probe', [args['filePath']]) as String;
      case ChannelMethods.unlockContainer:
        return _unlock(args);
      case ChannelMethods.cancelUnlock:
        _nativeLocal.requestCancelUnlock(args['volId'] as int);
        return null;
      case ChannelMethods.lockContainer:
        return _lock(args['filePath'] as String);

      case ChannelMethods.listDirectory:
        {
          final r = await pool.call('list', [_vol(args['filePath']), (args['dirPath'] as String?) ?? '']) as List<Object?>;
          _throwFor(r[0] as int);
          return (r[1] as List<Object?>).cast<String>();
        }
      case ChannelMethods.getFileSize:
        return _size(await pool.call('fileSize', [_vol(args['filePath']), args['fileName']]) as int);
      case ChannelMethods.getFolderSize:
        return _size(await pool.call('folderSize', [_vol(args['filePath']), args['dirPath']]) as int);
      case ChannelMethods.readFileChunk:
        {
          final r = await pool.call('read', [
            _vol(args['filePath']),
            args['fileName'],
            (args['offset'] as num).toInt(),
            (args['length'] as num).toInt(),
          ]) as List<Object?>;
          final rc = r[0] as int;
          if (rc == veOk) return r[1] as Uint8List;
          _throwFor(rc);
          return null; // EOF / failure, same as the native side
        }
      case ChannelMethods.writeFileChunk:
        return _ok(await pool.call('write', [
          _vol(args['filePath']),
          args['fileName'],
          (args['offset'] as num).toInt(),
          args['data'] as Uint8List,
        ]) as int);
      case ChannelMethods.createDirectory:
        return _ok(await pool.call('mkdir', [_vol(args['filePath']), args['dirPath']]) as int);
      case ChannelMethods.renameFile:
        return _ok(await pool.call('rename', [_vol(args['filePath']), args['oldPath'], args['newPath']]) as int);
      case ChannelMethods.deleteFile:
        return _ok(await pool.call('delete', [_vol(args['filePath']), args['fileName']]) as int);
      case ChannelMethods.setLastModifiedTime:
        return _ok(await pool.call('setMtime', [
          _vol(args['filePath']),
          args['fileName'],
          (args['epochSeconds'] as num).toInt(),
        ]) as int);
      case ChannelMethods.copyFile:
        return _withActivity(() async => _ok(await pool.call('copy', [
              _vol(args['srcUri']),
              args['srcPath'],
              _vol(args['destUri']),
              args['destPath'],
              (args['opId'] as num?)?.toInt() ?? 0,
            ]) as int));
      case ChannelMethods.cancelCopy:
        if (args['opId'] is num) _nativeLocal.opCancel((args['opId'] as num).toInt());
        return null;
      case ChannelMethods.getSpaceInfo:
        {
          final r = await pool.call('space', [_vol(args['filePath'])]) as List<Object?>;
          if (r[0] != veOk) return null;
          return (r[1] as List<Object?>).cast<int>();
        }
    }

    final (handledByCrypto, cryptoResult) = await _crypto.handle(call.method, args);
    if (handledByCrypto) return cryptoResult;

    if (_androidOnlyDefaults.containsKey(call.method)) return _androidOnlyDefaults[call.method];

    if (kDebugMode && _warned.add(call.method)) {
      debugPrint('[desktop-engine] not implemented yet: ${call.method} (replying null)');
    }
    return null;
  }

  // ── picking ────────────────────────────────────────────────────────────

  Future<Object?> _pickContainer() async {
    final file = await openFile();
    if (file == null) return null;
    // On desktop the container "URI" is simply its filesystem path.
    return {'uri': file.path, 'displayName': p.basename(file.path)};
  }

  /// Multi-select picker shared by "add a vault" and keyfile selection. A file's `uri` is simply its
  /// filesystem path on desktop (keyfile "paths" handed back to unlock/create are the same value).
  Future<Object?> _pickFiles() async {
    final files = await openFiles();
    return [
      for (final f in files) {'uri': f.path, 'displayName': p.basename(f.path)},
    ];
  }

  // ── creation ───────────────────────────────────────────────────────────

  /// Android shows ACTION_CREATE_DOCUMENT, builds the container in a staging file, then copies it to
  /// the chosen document. Here: a save dialog, then the container is built next to the destination
  /// under a temporary name and renamed into place only once it is complete, so a failed or
  /// cancelled creation never leaves a half-written file at the chosen path.
  Future<Object?> _createContainer(Map<Object?, Object?> args) async {
    final location = await getSaveLocation(suggestedName: args['displayName'] as String?);
    if (location == null) return {'success': false, 'uri': null};
    final destination = location.path;
    final staging = '$destination.vaultexplorer-part';

    final password = Uint8List.fromList(utf8.encode((args['password'] as String?) ?? ''));
    final createHidden = args['createHiddenVolume'] == true && ((args['containerFormat'] as num?)?.toInt() ?? 0) == 0;
    final hiddenPassword = createHidden
        ? Uint8List.fromList(utf8.encode((args['hiddenPassword'] as String?) ?? ''))
        : null;
    final entropy = args['userEntropy'] is Uint8List ? args['userEntropy'] as Uint8List : null;

    int rc;
    try {
      rc = await _withActivity(() async => await pool.call('createContainer', [
            {
              'path': staging,
              'password': password,
              'pim': (args['pim'] as num?)?.toInt() ?? 0,
              'sizeBytes': (args['sizeBytes'] as num).toInt(),
              'fileSystem': (args['fileSystem'] as String?) ?? 'fat',
              'containerFormat': (args['containerFormat'] as num?)?.toInt() ?? 0,
              'cipherId': (args['cipherId'] as num?)?.toInt() ?? 255,
              'hashId': (args['hashId'] as num?)?.toInt() ?? 255,
              'keyfilePaths': (args['keyfilePaths'] as List<Object?>?)?.cast<String>() ?? const <String>[],
              'quickFormat': args['quickFormat'] == true,
              'userEntropy': entropy,
              'hiddenPassword': hiddenPassword,
              'hiddenFileSystem': args['hiddenFileSystem'] as String?,
              'hiddenSizeBytes': (args['hiddenSizeBytes'] as num?)?.toInt() ?? 0,
              'hiddenPim': (args['hiddenPim'] as num?)?.toInt() ?? 0,
              'hiddenCipherId': (args['hiddenCipherId'] as num?)?.toInt() ?? 255,
              'hiddenHashId': (args['hiddenHashId'] as num?)?.toInt() ?? 255,
              'hiddenKeyfilePaths':
                  (args['hiddenKeyfilePaths'] as List<Object?>?)?.cast<String>() ?? const <String>[],
            },
          ]) as int);
    } finally {
      password.fillRange(0, password.length, 0);
      hiddenPassword?.fillRange(0, hiddenPassword.length, 0);
      entropy?.fillRange(0, entropy.length, 0);
    }

    if (rc != veOk) {
      try {
        await File(staging).delete();
      } on FileSystemException {
        // nothing was created
      }
      throw PlatformException(
        code: 'C++_ERROR',
        message: rc == -1
            ? 'Could not create the container file (or open a keyfile) at $destination'
            : 'Container creation failed (code $rc)',
      );
    }

    try {
      await File(staging).rename(destination);
    } on FileSystemException catch (e) {
      try {
        await File(staging).delete();
      } on FileSystemException {
        // best effort
      }
      throw PlatformException(code: 'C++_ERROR', message: 'Could not save the container to $destination: ${e.message}');
    }
    return {'success': true, 'uri': destination};
  }

  // ── lifecycle ──────────────────────────────────────────────────────────

  Future<int> _slotCount() async {
    return _maxVolumes ??= ((await pool.call('init') as Map)['maxVolumes'] as int);
  }

  Future<Object?> _unlock(Map<Object?, Object?> args) async {
    final uri = args['filePath'] as String;
    final protectHidden = args['protectHiddenVolume'] == true;

    int? vol = _volByUri[uri];
    if (vol == null) {
      final slots = await _slotCount();
      for (var i = 0; i < slots; i++) {
        if (!_uriByVol.containsKey(i)) {
          vol = i;
          break;
        }
      }
      if (vol == null) {
        throw PlatformException(code: 'MAX_CONTAINERS', message: 'Maximum $slots containers already mounted');
      }
    }

    emit('onUnlockStarted', {'volId': vol});

    final password = Uint8List.fromList(utf8.encode((args['password'] as String?) ?? ''));
    final hidden = protectHidden
        ? Uint8List.fromList(utf8.encode((args['hiddenVolumePassword'] as String?) ?? ''))
        : null;
    final preserved = args['preservedKey'] is String ? base64Decode(args['preservedKey'] as String) : null;

    final result = await _withActivity(() => pool.call('unlock', [
          {
            'path': uri,
            'volId': vol,
            'password': password,
            'pim': (args['pim'] as num?)?.toInt() ?? 0,
            'cipherId': (args['cipherId'] as num?)?.toInt() ?? 255,
            'hashId': (args['hashId'] as num?)?.toInt() ?? 255,
            'preservedKey': preserved,
            'keyfilePaths': (args['keyfilePaths'] as List<Object?>?)?.cast<String>() ?? const <String>[],
            'readOnly': args['readOnly'] == true,
            'hiddenPassword': hidden,
            'hiddenPim': (args['hiddenVolumePim'] as num?)?.toInt() ?? 0,
            'hiddenCipherId': (args['hiddenVolumeCipherId'] as num?)?.toInt() ?? 255,
            'hiddenHashId': (args['hiddenVolumeHashId'] as num?)?.toInt() ?? 255,
            'hiddenKeyfilePaths':
                (args['hiddenVolumeKeyfilePaths'] as List<Object?>?)?.cast<String>() ?? const <String>[],
          },
        ])) as Map;
    password.fillRange(0, password.length, 0);
    hidden?.fillRange(0, hidden.length, 0);

    final rc = result['rc'] as int;
    switch (rc) {
      case veOk:
        _volByUri[uri] = vol;
        _uriByVol[vol] = uri;
        _meta[vol] = _SessionMeta(
          displayName: (args['displayName'] as String?) ?? p.basename(uri),
          format: result['format'] as String,
          readOnly: args['readOnly'] == true,
        );
        return {
          'volId': vol,
          'files': (result['files'] as List<Object?>).cast<String>(),
          'matchedCipherId': result['cipherId'],
          'matchedHashId': result['hashId'],
          'containerFormat': result['format'],
        };
      case veErrFailed:
        final code = protectHidden
            ? 'INCORRECT_HIDDEN_VOLUME_CREDENTIALS'
            : 'INCORRECT_PASSWORD_OR_INVALID_CONTAINER';
        throw PlatformException(code: 'AUTH_FAIL', message: code, details: code);
      case veErrCancelled:
        throw PlatformException(code: 'CANCELLED', message: 'Unlock cancelled');
      case -1:
        throw PlatformException(code: 'C++_ERROR', message: 'Could not open the container file (or a keyfile)');
      case veErrMountFailed:
        throw PlatformException(code: 'C++_ERROR', message: 'Container decrypted but its filesystem could not be mounted');
      default:
        throw PlatformException(code: 'C++_ERROR', message: 'Native unlock failed (code $rc)');
    }
  }

  Future<bool> _lock(String uri) async {
    final vol = _volByUri[uri];
    if (vol == null) return true; // already locked
    await pool.call('lock', [vol]);
    _forget(vol);
    await _external.cleanupVolume(vol);
    return true;
  }

  // ── sessions ───────────────────────────────────────────────────────────

  void _forget(int vol) {
    final uri = _uriByVol.remove(vol);
    if (uri != null) _volByUri.remove(uri);
    _meta.remove(vol);
  }

  /// The ground truth the dashboard reconciles against (on start-up and every resume): every session
  /// that is REALLY active in the engine right now. A session the engine no longer has (wiped, e.g.
  /// by a panic lock) is dropped here too. Replying `null`/empty makes the app conclude nothing is
  /// mounted and lock everything -- so this must be accurate.
  Future<Object?> _activeSessions() async {
    final sessions = <Map<String, Object?>>[];
    for (final entry in _uriByVol.entries.toList()) {
      final vol = entry.key;
      final r = await pool.call('list', [vol, '']) as List<Object?>;
      if (r[0] == veErrNotUnlocked) {
        _forget(vol);
        await _external.cleanupVolume(vol);
        continue;
      }
      final meta = _meta[vol];
      sessions.add({
        'volId': vol,
        'uri': entry.value,
        'displayName': meta?.displayName ?? p.basename(entry.value),
        'containerFormat': meta?.format ?? 'unknown',
        'readOnly': meta?.readOnly ?? false,
        'files': (r[1] as List<Object?>).cast<String>(),
      });
    }
    return {'sessions': sessions};
  }

  /// Same tiering rule as the Android DeviceCapabilityProfiler (cores + memory class), with a fixed
  /// desktop memory class: it only decides thumbnail concurrency and cache budgets.
  Map<String, Object?> _capabilityProfile() {
    final cores = Platform.numberOfProcessors;
    const memoryClassMb = 512;
    final tier = cores <= 4 ? 'LOW' : (cores >= 8 ? 'HIGH' : 'MEDIUM');
    return {'tier': tier, 'cores': cores, 'memoryClassMb': memoryClassMb, 'isLowRamDevice': false};
  }

  /// Reads a whole vault file in 8 MiB steps. Null on failure; IMAGE_TOO_LARGE above [maxBytes].
  Future<Uint8List?> _readWholeVaultFile(int vol, String path, int maxBytes) async {
    final size = await pool.call('fileSize', [vol, path]) as int;
    if (size < 0) {
      _throwFor(-size);
      return null;
    }
    if (size == 0) return Uint8List(0);
    if (size > maxBytes) {
      throw PlatformException(
        code: 'IMAGE_TOO_LARGE',
        message: 'File is $size bytes; the limit for in-memory decoding is $maxBytes',
      );
    }
    final out = Uint8List(size);
    var offset = 0;
    while (offset < size) {
      final r = await pool.call('read', [vol, path, offset, math.min(8 << 20, size - offset)]) as List<Object?>;
      if (r[0] != veOk) return null;
      final chunk = r[1] as Uint8List;
      if (chunk.isEmpty) return null;
      out.setAll(offset, chunk);
      offset += chunk.length;
    }
    return out;
  }

  /// "Open with": a desktop app needs a real file, so one decrypted copy is made in a contained
  /// temp directory (see desktop_external.dart) and removed when the vault is locked.
  Future<bool> _openVaultFileWithApp(Map<Object?, Object?> args) async {
    final vol = _vol(args['filePath']);
    final fileName = args['fileName'] as String;
    final dest = await _external.reserveTempCopy(vol, fileName);
    final rc = await _withActivity(() => pool.call('export', [vol, fileName, dest, 0])) as int;
    if (rc != veOk) {
      await _external.cleanupVolume(vol);
      return false;
    }
    final opened = await _external.launch(dest);
    if (!opened) await _external.cleanupVolume(vol);
    return opened;
  }

  // ── single-file encryption ─────────────────────────────────────────────

  /// Output file name rules, identical to the Android handler: encrypt appends .vxenc (or .aes for
  /// cipher index 2); decrypt strips .vxenc / .aes / .enc, otherwise adds .decrypted.
  static String _singleFileOutName(String source, bool encrypt, int cipherIndex) {
    final name = p.basename(source);
    final lower = name.toLowerCase();
    if (encrypt) {
      if (cipherIndex == 2) return lower.endsWith('.aes') ? name : '$name.aes';
      return lower.endsWith('.vxenc') ? name : '$name.vxenc';
    }
    final stripped = lower.endsWith('.vxenc')
        ? name.substring(0, name.length - 6)
        : (lower.endsWith('.aes') || lower.endsWith('.enc'))
            ? name.substring(0, name.length - 4)
            : '$name.decrypted';
    return stripped.isEmpty ? 'decrypted_file' : stripped;
  }

  /// The output is built under a temporary name beside its destination and renamed into place only
  /// when complete, so a wrong password, a cancel or a crash never leaves a partial file.
  Future<Object?> _singleFileCrypt(Map<Object?, Object?> args, {required bool encrypt}) async {
    final source = args['sourceUri'] as String?;
    if (source == null || source.isEmpty) {
      throw PlatformException(code: 'INVALID_ARGS', message: 'sourceUri is required');
    }
    final opId = (args['opId'] as num?)?.toInt() ?? 0;
    final cipher = encrypt ? ((args['cipherIndex'] as num?)?.toInt() ?? 0) : 0;
    final destArg = args['destinationPath'] as String?;
    final dir = (destArg != null && destArg.isNotEmpty && !destArg.startsWith('content:'))
        ? destArg
        : p.dirname(source);
    final dest = p.join(dir, _singleFileOutName(source, encrypt, cipher));
    if (p.equals(dest, source)) {
      throw PlatformException(code: 'INVALID_ARGS', message: 'Refusing to overwrite the source file');
    }
    await Directory(dir).create(recursive: true);
    final staging = '$dest.vaultexplorer-part';

    final password = Uint8List.fromList(utf8.encode((args['passphrase'] as String?) ?? ''));
    if (opId > 0) _nativeLocal.opRegister(opId, veOpCopy);
    int rc;
    try {
      rc = await _withActivity(() async => await pool.call('singleFile', [
            {
              'src': source,
              'dest': staging,
              'encrypt': encrypt,
              'cipher': cipher,
              'password': password,
              'keyfilePaths': (args['keyfilePaths'] as List<Object?>?)?.cast<String>() ?? const <String>[],
              'opId': opId,
            },
          ]) as int);
    } finally {
      password.fillRange(0, password.length, 0);
      if (opId > 0) _nativeLocal.opUnregister(opId);
    }

    Future<void> dropStaging() async {
      try {
        await File(staging).delete();
      } on FileSystemException {
        // nothing was created
      }
    }

    if (rc != veOk) {
      await dropStaging();
      if (rc == veErrCancelled) {
        throw PlatformException(code: 'CANCELLED', message: encrypt ? 'Encryption cancelled' : 'Decryption cancelled');
      }
      if (rc == -1) {
        throw PlatformException(code: 'C++_ERROR', message: 'Could not open the source file, a keyfile, or create the output file');
      }
      if (encrypt) throw PlatformException(code: 'CRYPTO_ERROR', message: 'Encryption failed');
      throw PlatformException(code: 'AUTH_FAIL', message: 'Incorrect password or keyfiles, or corrupted file');
    }

    try {
      await File(staging).rename(dest);
    } on FileSystemException catch (e) {
      await dropStaging();
      throw PlatformException(code: 'C++_ERROR', message: 'Could not save the result to $dest: ${e.message}');
    }
    if (encrypt && args['deleteOriginalAfter'] == true) {
      try {
        await File(source).delete();
      } on FileSystemException {
        // the encrypted copy exists; failing to remove the original is not a failure of the tool
      }
    }
    return true;
  }

  // ── password change ────────────────────────────────────────────────────

  /// VeraCrypt answers a bool (like Android); LUKS reports a wrong old password as AUTH_FAIL and any
  /// other failure as INVALID_VAULT, which the dialog turns into specific messages.
  Future<Object?> _changePassword(Map<Object?, Object?> args, {required bool luks}) async {
    final uri = args['uri'] as String?;
    final newPassword = (args['newPassword'] as String?) ?? '';
    final newKeyfiles = (args['newKeyfilePaths'] as List<Object?>?)?.cast<String>() ?? const <String>[];
    if (uri == null || uri.isEmpty || (newPassword.isEmpty && newKeyfiles.isEmpty)) {
      throw PlatformException(code: 'INVALID_ARGS', message: 'uri and newPassword required');
    }
    final oldBytes = Uint8List.fromList(utf8.encode((args['oldPassword'] as String?) ?? ''));
    final newBytes = Uint8List.fromList(utf8.encode(newPassword));
    int rc;
    try {
      rc = await _withActivity(() async => await pool.call('changePassword', [
            {
              'path': uri,
              'containerFormat': luks ? 1 : 0,
              'oldPassword': oldBytes,
              'newPassword': newBytes,
              'oldPim': (args['oldPim'] as num?)?.toInt() ?? 0,
              'newPim': (args['newPim'] as num?)?.toInt() ?? 0,
              'cipherId': (args['cipherId'] as num?)?.toInt() ?? 255,
              'hashId': (args['hashId'] as num?)?.toInt() ?? 255,
              'oldKeyfilePaths': (args['oldKeyfilePaths'] as List<Object?>?)?.cast<String>() ?? const <String>[],
              'newKeyfilePaths': newKeyfiles,
            },
          ]) as int);
    } finally {
      oldBytes.fillRange(0, oldBytes.length, 0);
      newBytes.fillRange(0, newBytes.length, 0);
    }
    if (rc == -1) {
      throw PlatformException(code: 'C++_ERROR', message: 'Could not open the container file (or a keyfile)');
    }
    if (luks) {
      if (rc == veOk) return true;
      if (rc == veErrAuthFailed) throw PlatformException(code: 'AUTH_FAIL', message: 'Incorrect password');
      throw PlatformException(code: 'INVALID_VAULT', message: "Could not change the LUKS container's password");
    }
    return rc == veOk;
  }

  // ── helpers ────────────────────────────────────────────────────────────

  int _vol(Object? uri) {
    final vol = _volByUri[uri];
    if (vol == null) {
      // Same code + message the Android side uses for a path with no mounted session (the Dart
      // callers test for NOT_MOUNTED, e.g. the vault-info and settings screens).
      throw PlatformException(code: 'NOT_MOUNTED', message: 'Container not mounted');
    }
    return vol;
  }

  void _throwFor(int rc) {
    if (rc == veErrNotUnlocked) {
      throw PlatformException(code: 'NOT_UNLOCKED', message: 'NOT_UNLOCKED');
    }
    if (rc == veErrReadOnly) {
      throw PlatformException(code: 'READ_ONLY', message: 'READ_ONLY: container is mounted read-only');
    }
  }

  bool _ok(int rc) {
    _throwFor(rc);
    return rc == veOk;
  }

  int _size(int v) {
    if (v >= 0) return v;
    _throwFor(-v);
    return 0;
  }

  Future<T> _withActivity<T>(Future<T> Function() body) async {
    _activity++;
    _pump ??= Timer.periodic(const Duration(milliseconds: 100), (_) => _drainEvents());
    try {
      return await body();
    } finally {
      _activity--;
      _drainEvents();
      if (_activity == 0) {
        _pump?.cancel();
        _pump = null;
      }
    }
  }

  void _drainEvents() {
    for (final e in _nativeLocal.pollEvents()) {
      if (e.kind == veEventUnlockProgress) {
        emit('onUnlockProgress', {
          'volId': e.volId,
          'attempted': e.i[0],
          'total': e.i[1],
          'hashId': e.i[2],
          'cipherId': e.i[3],
          'containerFormat': veFormatWireName(e.i[4]),
          'slot': e.n0,
        });
      }
      if (e.kind == veEventSplitJoinProgress) {
        emit('onSplitJoinProgress', {'opId': e.opId, 'bytesDone': e.n0, 'bytesTotal': e.n1});
      }
      _transfers.onNativeEvent(e); // copy / import / export byte progress
    }
  }

  Future<void> dispose() async {
    _pump?.cancel();
    for (final vol in _uriByVol.keys.toList()) {
      await pool.call('lock', [vol]);
    }
    _uriByVol.clear();
    _volByUri.clear();
    _meta.clear();
    await _external.cleanupAll();
    await _hash.dispose();
    await pool.dispose();
  }
}
