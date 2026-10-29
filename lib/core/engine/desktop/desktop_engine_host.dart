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
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

import 'engine_worker_pool.dart';
import 've_native.dart';

class DesktopEngineHost {
  DesktopEngineHost({required this.pool, required this.emit});

  final EngineWorkerPool pool;

  /// Pushes a native->Dart call (e.g. `onUnlockProgress`) to the Dart side of the channel.
  final void Function(String method, Object? arguments) emit;

  final Map<String, int> _volByUri = {};
  final Map<int, String> _uriByVol = {};
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
  };

  Future<Object?> handle(MethodCall call) async {
    final args = call.arguments is Map ? Map<Object?, Object?>.from(call.arguments as Map) : const <Object?, Object?>{};
    switch (call.method) {
      case ChannelMethods.pickContainer:
        return _pickContainer();
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
    _volByUri.remove(uri);
    _uriByVol.remove(vol);
    return true;
  }

  // ── helpers ────────────────────────────────────────────────────────────

  int _vol(Object? uri) {
    final vol = _volByUri[uri];
    if (vol == null) {
      throw PlatformException(code: 'NOT_UNLOCKED', message: 'NOT_UNLOCKED: no unlocked container for $uri');
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
      // Copy / import / export progress events are drained but not forwarded yet: their Dart-side
      // event names and payloads still need mapping (docs/desktop-port.md, next steps).
    }
  }

  Future<void> dispose() async {
    _pump?.cancel();
    for (final vol in _uriByVol.keys.toList()) {
      await pool.call('lock', [vol]);
    }
    _uriByVol.clear();
    _volByUri.clear();
    await pool.dispose();
  }
}
