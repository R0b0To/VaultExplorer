// A small pool of long-lived worker isolates that run the blocking native engine calls.
//
// Why isolates: unlocking a container derives keys (PBKDF2/Argon2, seconds of CPU) and file
// operations can block on large I/O -- none of that may run on the UI isolate. Native state is
// process-wide, so any worker can serve any volume; the engine does its own per-volume locking.
// A call goes to the least-loaded worker, so one long unlock never queues small calls behind it.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

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
    return best.call(op, args);
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

  Future<Object?> call(String op, List<Object?> args) {
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
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
    try {
      final result = veExecute(n, m[1] as String, (m[2] as List<Object?>));
      reply.send(<Object?>[id, result, null]);
    } on Object catch (e) {
      reply.send(<Object?>[id, null, '$e']);
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

    case 'cancelUnlock':
      n.requestCancelUnlock(a[0] as int);
      return null;
    case 'lock':
      n.lock(a[0] as int);
      return null;

    case 'list':
      {
        final (rc, files) = n.listDirectory(a[0] as int, a[1] as String);
        return [rc, files];
      }
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
    case 'import':
      {
        final opId = a[3] as int;
        if (opId > 0) n.opRegister(opId, veOpImport);
        try {
          return n.importFile(a[0] as int, a[1] as String, a[2] as String, opId);
        } finally {
          if (opId > 0) n.opUnregister(opId);
        }
      }
    case 'export':
      {
        final opId = a[3] as int;
        if (opId > 0) n.opRegister(opId, veOpExport);
        try {
          return n.exportFile(a[0] as int, a[1] as String, a[2] as String, opId);
        } finally {
          if (opId > 0) n.opUnregister(opId);
        }
      }
    case 'space':
      {
        final (rc, vals) = n.spaceInfo(a[0] as int);
        return [rc, vals];
      }
    case 'opCancel':
      n.opCancel(a[0] as int);
      return null;
  }
  throw ArgumentError('unknown engine op: $op');
}
