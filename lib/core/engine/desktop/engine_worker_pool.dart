// A small pool of long-lived worker isolates that run the blocking native engine calls.
//
// Why isolates: unlocking a container derives keys (PBKDF2/Argon2, seconds of CPU) and file
// operations can block on large I/O -- none of that may run on the UI isolate. Native state is
// process-wide, so any worker can serve any volume; the engine does its own per-volume locking.
// A call goes to the least-loaded worker, so one long unlock never queues small calls behind it.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:vaultexplorer/core/diagnostics/stall_diagnostics.dart';

import 've_native.dart';

class EngineWorkerPool {
  EngineWorkerPool({this.size = 4, this.libraryPath});

  final int size;
  final String? libraryPath;
  final List<_Worker> _workers = [];
  Future<void>? _starting;

  Future<void> _ensureStarted() => _starting ??= _start();

  Future<void> _start() async {
    for (var i = 0; i < size; i++) {
      _workers.add(await _Worker.spawn(libraryPath));
    }
  }

  /// Runs [op] (see [veExecute]) on the least-loaded worker.
  Future<Object?> call(String op, [List<Object?> args = const []]) async {
    await _ensureStarted();
    var best = _workers.first;
    for (final w in _workers) {
      if (w.load < best.load) best = w;
    }
    final diag = StallDiagnostics.poolBegin(op, best.load);
    var execMicros = -1;
    try {
      return await best.call(op, args, (micros) => execMicros = micros);
    } finally {
      StallDiagnostics.poolEnd(diag, execMicros: execMicros);
    }
  }

  Future<void> dispose() async {
    for (final w in _workers) {
      w.kill();
    }
    _workers.clear();
    _starting = null;
  }
}

class _Worker {
  _Worker._(this._isolate, this._send, this._recv);

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _recv;
  final Map<int, Completer<Object?>> _pending = {};
  final Map<int, void Function(int)> _onExec = {};
  int _nextId = 0;

  int get load => _pending.length;

  static Future<_Worker> spawn(String? libraryPath) async {
    final recv = ReceivePort();
    final ready = Completer<SendPort>();
    late final _Worker worker;
    recv.listen((Object? msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else if (msg is List<Object?>) {
        final c = worker._pending.remove(msg[0] as int);
        final onExec = worker._onExec.remove(msg[0] as int);
        if (onExec != null && msg.length > 3) onExec(msg[3] as int);
        if (c == null) return;
        final err = msg[2];
        if (err != null) {
          c.completeError(StateError(err as String));
        } else {
          c.complete(msg[1]);
        }
      }
    });
    final isolate = await Isolate.spawn(_workerMain, <Object?>[recv.sendPort, libraryPath],
        debugName: 've-engine-worker');
    worker = _Worker._(isolate, await ready.future, recv);
    return worker;
  }

  /// [onExec] is told how long the worker spent inside the engine, in
  /// microseconds (diagnostics: the rest of the time was spent queued).
  Future<Object?> call(
    String op,
    List<Object?> args, [
    void Function(int)? onExec,
  ]) {
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    if (onExec != null) _onExec[id] = onExec;
    _send.send(<Object?>[id, op, args]);
    return c.future;
  }

  void kill() {
    _isolate.kill(priority: Isolate.immediate);
    _recv.close();
    for (final c in _pending.values) {
      c.completeError(StateError('engine worker disposed'));
    }
    _pending.clear();
    _onExec.clear();
  }
}

void _workerMain(List<Object?> init) {
  final reply = init[0] as SendPort;
  final libraryPath = init[1] as String?;
  final port = ReceivePort();
  reply.send(port.sendPort);

  VeNative? native;
  String? loadError;
  try {
    native = VeNative.open(libraryPath);
  } on Object catch (e) {
    loadError = '$e';
  }

  port.listen((Object? msg) {
    final m = msg as List<Object?>;
    final id = m[0] as int;
    final n = native;
    if (n == null) {
      reply.send(<Object?>[id, null, loadError ?? 'engine library not loaded']);
      return;
    }
    final watch = Stopwatch()..start();
    try {
      final result = veExecute(n, m[1] as String, (m[2] as List<Object?>));
      reply.send(<Object?>[id, result, null, watch.elapsedMicroseconds]);
    } on Object catch (e) {
      reply.send(<Object?>[id, null, '$e', watch.elapsedMicroseconds]);
    }
  });
}

/// The operation table. Arguments and results are plain sendable values (ints, strings, lists,
/// maps, Uint8List) so they cross the isolate boundary untouched.
Object? veExecute(VeNative n, String op, List<Object?> a) {
  switch (op) {
    case 'init':
      return {'maxVolumes': n.maxVolumes};

    case 'probe':
      {
        final fd = n.openFile(a[0] as String);
        if (fd < 0) return 'unknown';
        try {
          return n.probeFormat(fd);
        } finally {
          n.closeFd(fd);
        }
      }

    case 'unlock':
      {
        final m = Map<String, Object?>.from(a[0] as Map);
        final volId = m['volId'] as int;
        final rc = n.unlock(
          containerPath: m['path'] as String,
          password: m['password'] as Uint8List,
          pim: m['pim'] as int,
          volId: volId,
          cipherId: m['cipherId'] as int,
          hashId: m['hashId'] as int,
          preservedKey: m['preservedKey'] as Uint8List?,
          keyfilePaths: (m['keyfilePaths'] as List<Object?>).cast<String>(),
          readOnly: m['readOnly'] as bool,
          hiddenPassword: m['hiddenPassword'] as Uint8List?,
          hiddenPim: m['hiddenPim'] as int,
          hiddenCipherId: m['hiddenCipherId'] as int,
          hiddenHashId: m['hiddenHashId'] as int,
          hiddenKeyfilePaths: (m['hiddenKeyfilePaths'] as List<Object?>).cast<String>(),
        );
        if (rc != veOk) return {'rc': rc};
        final (listRc, files) = n.listDirectory(volId, '');
        return {
          'rc': veOk,
          'format': veFormatWireName(n.containerFormat(volId)),
          'cipherId': n.matchedCipherId(volId),
          'hashId': n.matchedHashId(volId),
          'files': listRc == veOk ? files : const <String>[],
        };
      }

    case 'unlockDevice':
      {
        // A raw disk / partition (BitLocker, VeraCrypt, LUKS). The worker opens the device itself, so no descriptor
        // crosses an isolate; the engine keeps it for the slot until `lock`.
        final m = Map<String, Object?>.from(a[0] as Map);
        final volId = m['volId'] as int;
        final (rc, osError) = n.unlockDevice(
          devicePath: m['path'] as String,
          password: m['password'] as Uint8List,
          pim: m['pim'] as int,
          volId: volId,
          cipherId: m['cipherId'] as int,
          hashId: m['hashId'] as int,
          preservedKey: m['preservedKey'] as Uint8List?,
          keyfilePaths: (m['keyfilePaths'] as List<Object?>).cast<String>(),
          readOnly: m['readOnly'] as bool,
          hiddenPassword: m['hiddenPassword'] as Uint8List?,
          hiddenPim: m['hiddenPim'] as int,
          hiddenCipherId: m['hiddenCipherId'] as int,
          hiddenHashId: m['hiddenHashId'] as int,
          hiddenKeyfilePaths: (m['hiddenKeyfilePaths'] as List<Object?>).cast<String>(),
        );
        if (rc != veOk) return {'rc': rc, 'osError': osError};
        final (listRc, files) = n.listDirectory(volId, '');
        return {
          'rc': veOk,
          'osError': 0,
          'format': veFormatWireName(n.containerFormat(volId)),
          'cipherId': n.matchedCipherId(volId),
          'hashId': n.matchedHashId(volId),
          'files': listRc == veOk ? files : const <String>[],
        };
      }

    case 'listBlockDevices':
      return [
        for (final d in n.listBlockDevices())
          {
            'path': d.path,
            'name': d.name,
            'bus': d.bus,
            'sizeBytes': d.sizeBytes,
            'sectorSize': d.sectorSize,
            'removable': d.removable,
            'readable': d.readable,
            'writable': d.writable,
            'inUse': d.inUse,
            'system': d.system,
            'formats': d.formats,
          },
      ];

    case 'createContainer':
      {
        final m = Map<String, Object?>.from(a[0] as Map);
        return n.createContainer(
          path: m['path'] as String,
          password: m['password'] as Uint8List,
          pim: m['pim'] as int,
          sizeBytes: m['sizeBytes'] as int,
          fileSystem: m['fileSystem'] as String,
          containerFormat: m['containerFormat'] as int,
          cipherId: m['cipherId'] as int,
          hashId: m['hashId'] as int,
          keyfilePaths: (m['keyfilePaths'] as List<Object?>).cast<String>(),
          quickFormat: m['quickFormat'] as bool,
          userEntropy: m['userEntropy'] as Uint8List?,
          hiddenPassword: m['hiddenPassword'] as Uint8List?,
          hiddenFileSystem: m['hiddenFileSystem'] as String?,
          hiddenSizeBytes: m['hiddenSizeBytes'] as int,
          hiddenPim: m['hiddenPim'] as int,
          hiddenCipherId: m['hiddenCipherId'] as int,
          hiddenHashId: m['hiddenHashId'] as int,
          hiddenKeyfilePaths: (m['hiddenKeyfilePaths'] as List<Object?>).cast<String>(),
        );
      }

    case 'cancelUnlock':
      n.requestCancelUnlock(a[0] as int);
      return null;
    case 'lock':
      n.lock(a[0] as int);
      return null;

    // ── OS mounts ──
    case 'mountSupported':
      {
        final (ok, reason) = n.mountSupported();
        return [ok, reason];
      }
    case 'mount':
      {
        // [vol, mountPoint, readOnly, volumeName, subPath]
        final (rc, id) = n.mount(
          a[0] as int,
          a[1] as String,
          readOnly: a[2] as bool,
          volumeName: a[3] as String?,
          subPath: a[4] as String?,
        );
        return [rc, id, rc == veOk ? '' : n.mountLastError()];
      }
    case 'unmount':
      {
        final rc = n.unmount(a[0] as int, force: a[1] as bool);
        return [rc, rc == veOk ? '' : n.mountLastError()];
      }
    case 'listMounts':
      return [
        for (final m in n.listMounts()) [m.id, m.volId, m.ended, m.mountPoint],
      ];

    // ── folder vaults (gocryptfs / Cryptomator / CryFS) ──
    case 'fvSupported':
      return n.fvSupported;
    case 'fvProbe':
      return n.fvProbe(a[0] as String);
    case 'fvUnlock':
      {
        final m = Map<String, Object?>.from(a[0] as Map);
        final volId = m['volId'] as int;
        final ({int rc, String? message, Uint8List? derivedKey}) r;
        try {
          r = n.fvUnlock(
            volId: volId,
            format: m['format'] as int,
            root: m['path'] as String,
            password: m['password'] as Uint8List,
            combinedKey: m['combinedKey'] as Uint8List?,
            readOnly: m['readOnly'] as bool,
            backupKeyFiles: m['backupKeyFiles'] as bool,
            localStateDir: m['localStateDir'] as String,
            tempDir: m['tempDir'] as String,
          );
        } finally {
          _wipe(m['password'] as Uint8List?);
          _wipe(m['combinedKey'] as Uint8List?);
        }
        if (r.rc != veOk) return {'rc': r.rc, 'message': r.message};
        final (listRc, files) = n.listDirectory(volId, '');
        return {
          'rc': veOk,
          'format': veFormatWireName(n.containerFormat(volId)),
          'derivedKey': r.derivedKey,
          'files': listRc == veOk ? files : const <String>[],
        };
      }
    case 'fvCreate':
      {
        final m = Map<String, Object?>.from(a[0] as Map);
        try {
          final r = n.fvCreate(
            format: m['format'] as int,
            root: m['path'] as String,
            password: m['password'] as Uint8List,
            cipher: m['cipher'] as int,
            plaintextNames: m['plaintextNames'] as bool,
            deterministicNames: m['deterministicNames'] as bool,
            longNameMax: m['longNameMax'] as int,
            blockSize: m['blockSize'] as int,
            cipherName: m['cipherName'] as String,
            userEntropy: m['userEntropy'] as Uint8List?,
            localStateDir: m['localStateDir'] as String,
            tempDir: m['tempDir'] as String,
          );
          return {'rc': r.rc, 'message': r.message};
        } finally {
          _wipe(m['password'] as Uint8List?);
          _wipe(m['userEntropy'] as Uint8List?);
        }
      }
    case 'fvChangePassword':
      {
        final m = Map<String, Object?>.from(a[0] as Map);
        try {
          final r = n.fvChangePassword(
            format: m['format'] as int,
            root: m['path'] as String,
            oldPassword: m['oldPassword'] as Uint8List,
            newPassword: m['newPassword'] as Uint8List,
          );
          return {'rc': r.rc, 'message': r.message};
        } finally {
          _wipe(m['oldPassword'] as Uint8List?);
          _wipe(m['newPassword'] as Uint8List?);
        }
      }
    case 'fvMigrate':
      {
        final m = Map<String, Object?>.from(a[0] as Map);
        try {
          final r = n.fvMigrateCryptomator(root: m['path'] as String, password: m['password'] as Uint8List);
          return {'rc': r.rc, 'message': r.message};
        } finally {
          _wipe(m['password'] as Uint8List?);
        }
      }
    case 'fvProbeCryptomator':
      return n.fvProbeCryptomator(a[0] as String);
    // symbolic links (ext/NTFS containers and Cryptomator vaults alike)
    case 'listSymlinks':
      {
        final (rc, entries) = n.listSymlinks(a[0] as int, a[1] as String);
        return [rc, entries];
      }
    case 'readSymlink':
      {
        final (rc, target) = n.readSymlink(a[0] as int, a[1] as String);
        return [rc, target];
      }
    case 'createSymlink':
      return n.createSymlink(a[0] as int, a[1] as String, a[2] as String);
    case 'fvHidden':
      return n.fvHiddenEntryCount(a[0] as int, a[1] as String);
    case 'fvFinishWrite':
      return n.fvFinishWrite(a[0] as int, a[1] as String);
    case 'fvBatch':
      return n.fvBatch(a[0] as int, a[1] as int, begin: a[2] as bool);

    case 'list':
      {
        final (rc, files) = n.listDirectory(a[0] as int, a[1] as String);
        return [rc, files];
      }
    // crypto primitives -> [resultCode, bytes?]
    case 'pbkdf2':
      {
        final (rc, b) = n.pbkdf2(a[0] as int, a[1] as Uint8List, a[2] as Uint8List, a[3] as int, a[4] as int);
        return [rc, b];
      }
    case 'hmac':
      {
        final (rc, b) = n.hmac(a[0] as int, a[1] as Uint8List, a[2] as Uint8List);
        return [rc, b];
      }
    case 'scrypt':
      {
        final (rc, b) = n.scrypt(a[0] as Uint8List, a[1] as Uint8List, a[2] as int, a[3] as int, a[4] as int, a[5] as int);
        return [rc, b];
      }
    case 'argon2id':
      {
        final (rc, b) = n.argon2id(a[0] as Uint8List, a[1] as Uint8List, a[2] as int, a[3] as int, a[4] as int, a[5] as int);
        return [rc, b];
      }
    case 'gcmSeal':
      {
        final (rc, b) = n.aesGcmSeal(a[0] as Uint8List, a[1] as Uint8List, a[2] as Uint8List?, a[3] as Uint8List);
        return [rc, b];
      }
    case 'gcmOpen':
      {
        final (rc, b) = n.aesGcmOpen(a[0] as Uint8List, a[1] as Uint8List, a[2] as Uint8List?, a[3] as Uint8List);
        return [rc, b];
      }
    case 'cbcDecrypt':
      {
        final (rc, b) = n.aesCbcDecrypt(a[0] as Uint8List, a[1] as Uint8List, a[2] as Uint8List);
        return [rc, b];
      }
    case 'xchachaOpen':
      {
        final (rc, b) = n.xchacha20Poly1305Open(a[0] as Uint8List, a[1] as Uint8List, a[2] as Uint8List?, a[3] as Uint8List);
        return [rc, b];
      }
    case 'singleFile':
      {
        final m = Map<String, Object?>.from(a[0] as Map);
        return n.singleFileCrypt(
          srcPath: m['src'] as String,
          destPath: m['dest'] as String,
          encrypt: m['encrypt'] as bool,
          password: m['password'] as Uint8List,
          cipherIndex: m['cipher'] as int,
          keyfilePaths: (m['keyfilePaths'] as List<Object?>).cast<String>(),
          opId: m['opId'] as int,
        );
      }
    case 'changePassword':
      {
        final m = Map<String, Object?>.from(a[0] as Map);
        return n.changePassword(
          path: m['path'] as String,
          containerFormat: m['containerFormat'] as int,
          oldPassword: m['oldPassword'] as Uint8List,
          newPassword: m['newPassword'] as Uint8List,
          oldPim: m['oldPim'] as int,
          newPim: m['newPim'] as int,
          cipherId: m['cipherId'] as int,
          hashId: m['hashId'] as int,
          oldKeyfilePaths: (m['oldKeyfilePaths'] as List<Object?>).cast<String>(),
          newKeyfilePaths: (m['newKeyfilePaths'] as List<Object?>).cast<String>(),
        );
      }
    // streaming digests: [resultCode, ...]
    case 'hashBegin':
      return n.hashBegin(a[0] as int);
    case 'hashUpdate':
      return n.hashUpdate(a[0] as int, a[1] as Uint8List);
    case 'hashFinish':
      {
        final (rc, b) = n.hashFinish(a[0] as int, a[1] as int);
        return [rc, b];
      }
    case 'hashFree':
      n.hashFree(a[0] as int);
      return null;
    case 'hashBytes':
      {
        final (rc, b) = n.hashBytes(a[0] as int, a[1] as Uint8List);
        return [rc, b];
      }
    case 'vaultInfo':
      {
        final (rc, map) = n.vaultInfo(a[0] as int);
        return [rc, map];
      }
    case 'containerFormat':
      return n.containerFormat(a[0] as int);
    case 'fileSize':
      return n.fileSize(a[0] as int, a[1] as String);
    case 'folderSize':
      return n.folderSize(a[0] as int, a[1] as String);
    case 'read':
      {
        final (rc, bytes) = n.readFileChunk(a[0] as int, a[1] as String, a[2] as int, a[3] as int);
        return [rc, bytes];
      }
    case 'write':
      return n.writeFileChunk(a[0] as int, a[1] as String, a[2] as int, a[3] as Uint8List);
    case 'delete':
      return n.deleteFile(a[0] as int, a[1] as String);
    case 'mkdir':
      return n.createDirectory(a[0] as int, a[1] as String);
    case 'rename':
      return n.renameFile(a[0] as int, a[1] as String, a[2] as String);
    case 'setMtime':
      return n.setLastModified(a[0] as int, a[1] as String, a[2] as int);
    case 'copy':
      {
        final opId = a[4] as int;
        if (opId > 0) n.opRegister(opId, veOpCopy);
        try {
          return n.copyFile(a[0] as int, a[1] as String, a[2] as int, a[3] as String, opId);
        } finally {
          if (opId > 0) n.opUnregister(opId);
        }
      }
    // import / export: the CALLER registers the operation id (VeNative.opRegister) for the whole
    // batch, because one id covers many files and cancellation must outlive a single call.
    case 'import':
      return n.importFile(a[0] as int, a[1] as String, a[2] as String, a[3] as int);
    case 'export':
      return n.exportFile(a[0] as int, a[1] as String, a[2] as String, a[3] as int);
    case 'space':
      {
        final (rc, vals) = n.spaceInfo(a[0] as int);
        return [rc, vals];
      }
    // archives (ABI 10) -> [resultCode, result record bytes?]; an in-memory entry adds its bytes as a third item
    case 'archiveScan':
      {
        final (rc, record) = n.archiveScan(a[0] as int, a[1] as String, a[2] as String?);
        return [rc, record];
      }
    case 'archiveExtractEntry':
      {
        final r = n.archiveExtractEntry(
          srcVol: a[0] as int,
          srcPath: a[1] as String,
          index: a[2] as int,
          passphrase: a[3] as String?,
          destVol: a[4] as int,
          destPath: a[5] as String?,
        );
        return [r.rc, r.record, r.data];
      }
    case 'archiveExtractAll':
      {
        final (rc, record) = n.archiveExtractAll(
          srcVol: a[0] as int,
          srcPath: a[1] as String,
          passphrase: a[2] as String?,
          subPath: a[3] as String?,
          destVol: a[4] as int,
          destDir: a[5] as String,
          opId: a[6] as int,
        );
        return [rc, record];
      }
    // Check & Repair, header backup (ABI 11). The worker opens the files, so no descriptor crosses an isolate and
    // none is left open: the engine closes every fd it is handed.
    case 'repairDiagnoseFile':
      {
        final fd = n.openFile(a[0] as String);
        if (fd < 0) return [veErrFailed, 1, -1];
        final (rc, code, format) = n.repairDiagnoseFile(fd, a[1] as int);
        return [rc, code, format];
      }
    case 'repairRestoreLuks2':
      {
        final fd = n.openFile(a[0] as String, writable: true);
        if (fd < 0) return veErrFailed;
        return n.repairRestoreLuks2(fd, a[1] as int);
      }
    case 'repairRestoreVeracrypt':
      {
        final fd = n.openFile(a[0] as String, writable: true);
        if (fd < 0) return [veErrFailed, 3];
        final (rc, result) = n.repairRestoreVeracrypt(fd, a[1] as Uint8List, a[2] as int, a[3] as int, a[4] as int, a[5] as int);
        return [rc, result];
      }
    case 'repairDiagnoseMounted':
      {
        final (rc, code) = n.repairDiagnoseMounted(a[0] as int, a[1] as int);
        return [rc, code];
      }
    case 'repairCheckMounted':
      {
        final (rc, ok) = n.repairCheckMounted(a[0] as int, a[1] as int);
        return [rc, ok];
      }
    case 'headerExport':
      {
        final fd = n.openFile(a[0] as String);
        if (fd < 0) return [veErrFailed, null];
        final (rc, record) = n.headerExport(fd, a[1] as int);
        return [rc, record];
      }
    case 'headerRestore':
      {
        // Keyfiles first, so a keyfile that fails to open cannot strand the (already opened) target descriptor.
        final keyfileFds = <int>[];
        for (final path in (a[8] as List).cast<String>()) {
          final kfd = n.openFile(path);
          if (kfd < 0) {
            keyfileFds.forEach(n.closeFd);
            return [veErrFailed, 4];
          }
          keyfileFds.add(kfd);
        }
        final fd = n.openFile(a[0] as String, writable: true);
        if (fd < 0) {
          keyfileFds.forEach(n.closeFd);
          return [veErrFailed, 4];
        }
        final (rc, result) = n.headerRestore(
          fd: fd,
          format: a[1] as int,
          payload: a[2] as Uint8List,
          password: a[3] as Uint8List?,
          pim: a[4] as int,
          cipherId: a[5] as int,
          hashId: a[6] as int,
          opId: a[7] as int,
          keyfileFds: keyfileFds,
        );
        return [rc, result];
      }
    case 'fvCheck':
      {
        final (rc, record) = n.fvCheckOrRepair(
          repair: a[0] as bool,
          format: a[1] as int,
          root: a[2] as String,
          password: a[3] as Uint8List?,
          sessionVol: a[4] as int,
          localStateDir: a[5] as String,
          tempDir: a[6] as String,
          opId: a[7] as int,
        );
        return [rc, record];
      }
    case 'fvConfigFileName':
      return n.fvConfigFileName(a[0] as int);
    case 'fvValidateConfig':
      return n.fvValidateConfig(a[0] as int, a[1] as Uint8List);
    case 'archiveCreate':
      {
        final (rc, record) = n.archiveCreate(
          srcVol: a[0] as int,
          srcPaths: (a[1] as List).cast<String>(),
          entryNames: (a[2] as List).cast<String>(),
          modifiedSecs: (a[3] as List).cast<int>(),
          destVol: a[4] as int,
          destPath: a[5] as String,
          format: a[6] as int,
          passphrase: a[7] as String?,
          encryptFilenames: a[8] as bool,
          compressionLevel: a[9] as int,
          compressionMethod: a[10] as int,
          splitSize: a[11] as int,
          tempDir: a[12] as String?,
          opId: a[13] as int,
        );
        return [rc, record];
      }
    // Container tools (ABI 12). Like the repair ops the worker opens the files itself and the engine closes every
    // descriptor it is handed. Failures to open are reported as the tool outcomes they correspond to (container:
    // 4 I/O error, keyfile: 5 unreadable keyfile) so the host maps them the way it maps an engine answer.
    // toolExpand   [kind 0 VeraCrypt / 1 LUKS / 2 BitLocker, path, password, pim, cipherId, hashId, keyfilePaths,
    //               newSizeBytes, initFreeSpace, growFileSystem] -> [rc, [outcome, fsStep, fsKind]]
    case 'toolExpand':
      {
        final password = a[2] as Uint8List;
        try {
          final keyfileFds = _openKeyfiles(n, (a[6] as List).cast<String>());
          if (keyfileFds == null) return [veErrFailed, _kToolKeyfileError];
          final fd = n.openFile(a[1] as String, writable: true);
          if (fd < 0) {
            keyfileFds.forEach(n.closeFd);
            return [veErrFailed, _kToolIoError];
          }
          if (a[0] == 2) {
            // BitLocker takes no keyfile; release any the caller handed over rather than leave them open.
            keyfileFds.forEach(n.closeFd);
            keyfileFds.clear();
          }
          final (rc, result) = switch (a[0] as int) {
            0 => n.expandVeracrypt(
                fd: fd,
                password: password,
                pim: a[3] as int,
                cipherId: a[4] as int,
                hashId: a[5] as int,
                keyfileFds: keyfileFds,
                newSizeBytes: a[7] as int,
                initFreeSpace: a[8] as bool,
                growFileSystem: a[9] as bool,
              ),
            1 => n.expandLuks(
                fd: fd,
                password: password,
                keyfileFds: keyfileFds,
                newSizeBytes: a[7] as int,
                initFreeSpace: a[8] as bool,
                growFileSystem: a[9] as bool,
              ),
            2 => n.expandBitlocker(
                fd: fd,
                password: password,
                newSizeBytes: a[7] as int,
                initFreeSpace: a[8] as bool,
                growFileSystem: a[9] as bool,
              ),
            _ => _closeAndRefuse(n, fd, keyfileFds),
          };
          return [rc, result];
        } finally {
          _wipe(password);
        }
      }
    // toolGrowFs   [kind, path, password, pim, cipherId, hashId, keyfilePaths] -> [rc, [outcome, fsStep, fsKind]]
    case 'toolGrowFs':
      {
        final password = a[2] as Uint8List;
        try {
          final keyfileFds = _openKeyfiles(n, (a[6] as List).cast<String>());
          if (keyfileFds == null) return [veErrFailed, _kToolKeyfileError];
          final fd = n.openFile(a[1] as String, writable: true);
          if (fd < 0) {
            keyfileFds.forEach(n.closeFd);
            return [veErrFailed, _kToolIoError];
          }
          if (a[0] == 2) {
            keyfileFds.forEach(n.closeFd);
            keyfileFds.clear();
          }
          final (rc, result) = switch (a[0] as int) {
            0 => n.growVeracryptFs(
                fd: fd,
                password: password,
                pim: a[3] as int,
                cipherId: a[4] as int,
                hashId: a[5] as int,
                keyfileFds: keyfileFds,
              ),
            1 => n.growLuksFs(fd: fd, password: password, keyfileFds: keyfileFds),
            2 => n.growBitlockerFs(fd: fd, password: password),
            _ => _closeAndRefuse(n, fd, keyfileFds),
          };
          return [rc, result];
        } finally {
          _wipe(password);
        }
      }
    // toolHiddenAnalyze [path, password, pim, cipherId, hashId, keyfilePaths] -> [rc, [outcome, fsKind, cluster, maxHidden]]
    case 'toolHiddenAnalyze':
      {
        final password = a[1] as Uint8List;
        try {
          final keyfileFds = _openKeyfiles(n, (a[5] as List).cast<String>());
          if (keyfileFds == null) return [veErrFailed, _kToolAnalyzeKeyfileError];
          final fd = n.openFile(a[0] as String); // analysis only reads
          if (fd < 0) {
            keyfileFds.forEach(n.closeFd);
            return [veErrFailed, _kToolAnalyzeIoError];
          }
          final (rc, result) = n.hiddenAnalyze(
            fd: fd,
            password: password,
            pim: a[2] as int,
            cipherId: a[3] as int,
            hashId: a[4] as int,
            keyfileFds: keyfileFds,
          );
          return [rc, result];
        } finally {
          _wipe(password);
        }
      }
    // toolHiddenCreate [path, outerPassword, outerPim, outerCipherId, outerHashId, outerKeyfilePaths, hiddenPassword,
    //                   hiddenPim, hiddenFileSystem, hiddenSizeBytes, hiddenCipherId, hiddenHashId,
    //                   hiddenKeyfilePaths, quickFormat, userEntropy?] -> [rc, outcome]
    case 'toolHiddenCreate':
      {
        final outerPassword = a[1] as Uint8List;
        final hiddenPassword = a[6] as Uint8List;
        final userEntropy = a[14] as Uint8List?;
        try {
          final outerKeyfileFds = _openKeyfiles(n, (a[5] as List).cast<String>());
          if (outerKeyfileFds == null) return [veErrFailed, 5];
          final hiddenKeyfileFds = _openKeyfiles(n, (a[12] as List).cast<String>());
          if (hiddenKeyfileFds == null) {
            outerKeyfileFds.forEach(n.closeFd);
            return [veErrFailed, 5];
          }
          final fd = n.openFile(a[0] as String, writable: true);
          if (fd < 0) {
            outerKeyfileFds.forEach(n.closeFd);
            hiddenKeyfileFds.forEach(n.closeFd);
            return [veErrFailed, 4];
          }
          final (rc, outcome) = n.hiddenCreateInExisting(
            fd: fd,
            outerPassword: outerPassword,
            outerPim: a[2] as int,
            outerCipherId: a[3] as int,
            outerHashId: a[4] as int,
            outerKeyfileFds: outerKeyfileFds,
            hiddenPassword: hiddenPassword,
            hiddenPim: a[7] as int,
            hiddenFileSystem: a[8] as String,
            hiddenSizeBytes: a[9] as int,
            hiddenCipherId: a[10] as int,
            hiddenHashId: a[11] as int,
            hiddenKeyfileFds: hiddenKeyfileFds,
            quickFormat: a[13] as bool,
            userEntropy: userEntropy,
          );
          return [rc, outcome];
        } finally {
          _wipe(outerPassword);
          _wipe(hiddenPassword);
          _wipe(userEntropy);
        }
      }
    // ── composite containers (ABI 13): one volume over several ordinary files ──
    // compositeProfile [carrierPaths, safetyMarginPct] -> [rc, record?]   (record: see parseCompositeProfile)
    case 'compositeProfile':
      {
        final (rc, record) = n.compositeProfile(
          carrierPaths: (a[0] as List).cast<String>(),
          safetyMarginPct: a[1] as int,
        );
        return [rc, record];
      }
    // compositeCreate [carrierPaths, volId, requestedBytes, safetyMarginPct, password, pim, fileSystem, cipherId,
    //                  hashId, keyfilePaths, quickFormat, userEntropy?] -> [rc, errorCode?]
    case 'compositeCreate':
      {
        final password = a[4] as Uint8List;
        final userEntropy = a[11] as Uint8List?;
        try {
          final keyfileFds = _openKeyfiles(n, (a[9] as List).cast<String>());
          if (keyfileFds == null) return [veErrFailed, _kCompositeKeyfileError];
          final (rc, error) = n.compositeCreate(
            carrierPaths: (a[0] as List).cast<String>(),
            volId: a[1] as int,
            requestedBytes: a[2] as int,
            safetyMarginPct: a[3] as int,
            password: password,
            pim: a[5] as int,
            fileSystem: a[6] as String,
            cipherId: a[7] as int,
            hashId: a[8] as int,
            keyfileFds: keyfileFds,
            quickFormat: a[10] as bool,
            userEntropy: userEntropy,
          );
          return [rc, error];
        } finally {
          _wipe(password);
          _wipe(userEntropy);
        }
      }
    // compositeUnlock [carrierPaths, volId, password, pim, cipherId, hashId, keyfilePaths, readOnly]
    //   -> {rc, error?, format, cipherId, hashId, files}   (the last four only when rc is veOk)
    case 'compositeUnlock':
      {
        final password = a[2] as Uint8List;
        try {
          final keyfileFds = _openKeyfiles(n, (a[6] as List).cast<String>());
          if (keyfileFds == null) return {'rc': veErrFailed, 'error': _kCompositeKeyfileError};
          final volId = a[1] as int;
          final (rc, error) = n.compositeUnlock(
            carrierPaths: (a[0] as List).cast<String>(),
            volId: volId,
            password: password,
            pim: a[3] as int,
            cipherId: a[4] as int,
            hashId: a[5] as int,
            keyfileFds: keyfileFds,
            readOnly: a[7] as bool,
          );
          if (rc != veOk) return {'rc': rc, 'error': error};
          final (listRc, files) = n.listDirectory(volId, '');
          return {
            'rc': veOk,
            'format': veFormatWireName(n.containerFormat(volId)),
            'cipherId': n.matchedCipherId(volId),
            'hashId': n.matchedHashId(volId),
            'files': listRc == veOk ? files : const <String>[],
          };
        } finally {
          _wipe(password);
        }
      }
    // Image thumbnails (ABI 15) -> [resultCode, thumbnail bytes?, info ints]. Run in the thumbnail pool (see
    // DesktopEngineHost), never next to unlocks and listings.
    case 'imageThumbnail':
      {
        final (rc, bytes, info) = n.imageThumbnail(
          a[0] as int,
          a[1] as String,
          targetSize: a[2] as int,
          quality: a[3] as int,
          preserveAlpha: a[4] as bool,
          maxSourceBytes: a[5] as int,
        );
        return [rc, bytes, info];
      }
    case 'imageThumbnailFile':
      {
        final (rc, bytes, info) = n.imageThumbnailFile(
          a[0] as String,
          targetSize: a[1] as int,
          quality: a[2] as int,
          preserveAlpha: a[3] as bool,
          maxSourceBytes: a[4] as int,
        );
        return [rc, bytes, info];
      }
    case 'imageThumbnailMem':
      {
        final (rc, bytes, info) = n.imageThumbnailMem(
          a[0] as Uint8List,
          targetSize: a[1] as int,
          quality: a[2] as int,
          preserveAlpha: a[3] as bool,
        );
        return [rc, bytes, info];
      }
    // Video thumbnails (ABI 16) -> [resultCode, thumbnail bytes?, info ints]. Same pool as the image thumbnails.
    case 'videoThumbnail':
      {
        final (rc, bytes, info) = n.videoThumbnail(
          a[0] as int,
          a[1] as String,
          targetSize: a[2] as int,
          quality: a[3] as int,
          strategy: a[4] as int,
          framePosition: (a[5] as num).toDouble(),
          explicitTimeUs: a[6] as int,
          timeoutMs: a[7] as int,
        );
        return [rc, bytes, info];
      }
    case 'videoThumbnailFile':
      {
        final (rc, bytes, info) = n.videoThumbnailFile(
          a[0] as String,
          targetSize: a[1] as int,
          quality: a[2] as int,
          strategy: a[3] as int,
          framePosition: (a[4] as num).toDouble(),
          explicitTimeUs: a[5] as int,
          timeoutMs: a[6] as int,
        );
        return [rc, bytes, info];
      }
    case 'opCancel':
      n.opCancel(a[0] as int);
      return null;
  }
  throw ArgumentError('unknown engine op: $op');
}

// The engine's own code for a keyfile it could not read (ve_engine.h, composite containers).
const String _kCompositeKeyfileError = 'KEYFILE_FAILED';

// Tool results for a file the worker could not open (ve_engine.h, "container tools": outcome 4 I/O error,
// 5 unreadable keyfile; the analysis record is [outcome, fsKind, cluster size, largest hidden volume]).
const List<int> _kToolIoError = [4, -1, 0];
const List<int> _kToolKeyfileError = [5, -1, 0];
const List<int> _kToolAnalyzeIoError = [4, 0, 0, 0];
const List<int> _kToolAnalyzeKeyfileError = [5, 0, 0, 0];

/// Opens every keyfile read-only. On the first failure the ones already open are closed and null comes back.
List<int>? _openKeyfiles(VeNative n, List<String> paths) {
  final fds = <int>[];
  for (final path in paths) {
    final fd = n.openFile(path);
    if (fd < 0) {
      fds.forEach(n.closeFd);
      return null;
    }
    fds.add(fd);
  }
  return fds;
}

/// An expand / grow op whose kind the worker does not know: close what was opened, answer "invalid argument".
(int, List<int>) _closeAndRefuse(VeNative n, int fd, List<int> keyfileFds) {
  n.closeFd(fd);
  keyfileFds.forEach(n.closeFd);
  return (veErrInvalidArg, _kToolIoError);
}

/// Overwrites a secret's worker-side copy once the native call is done.
void _wipe(Uint8List? bytes) {
  if (bytes != null) bytes.fillRange(0, bytes.length, 0);
}
