// dart:ffi bindings for the desktop engine C ABI (android/app/src/main/cpp/ffi/ve_engine.h).
//
// Everything here is SYNCHRONOUS and BLOCKING (key derivation, large copies) -- it is meant to
// run inside a worker isolate (see engine_worker_pool.dart), never on the UI isolate. The native
// engine keeps its state process-wide, so any isolate may call it; each isolate just needs its
// own [VeNative] (a DynamicLibrary handle + looked-up function pointers).
//
// Keep this file in lock-step with ve_engine.h (VE_ABI_VERSION): the struct layouts below mirror
// the C structs field for field.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const int kVeAbiVersion = 1;

// Result codes (ve_engine.h)
const int veOk = 0;
const int veErrFailed = 1;
const int veErrCancelled = 2;
const int veErrNotUnlocked = 3;
const int veErrReadOnly = 4;
const int veErrInvalidArg = 5;
const int veErrException = 6;
const int veErrMountFailed = 7;

// Operation flavors / event kinds
const int veOpCopy = 0;
const int veOpImport = 1;
const int veOpExport = 2;
const int veEventUnlockProgress = 1;

/// ContainerFormat (native enum) -> the wire name the Dart layer uses.
String veFormatWireName(int native) => switch (native) {
  0 => 'veracrypt',
  1 => 'luks1',
  2 => 'luks2',
  3 => 'bitlocker',
  4 => 'plain',
  _ => 'unknown',
};

final class VeBuffer extends Struct {
  external Pointer<Uint8> data;
  @Size()
  external int len;
}

final class VeUnlockParams extends Struct {
  @Int32()
  external int structSize;
  @Int32()
  external int fd;
  external Pointer<Uint8> password;
  @Int32()
  external int passwordLen;
  @Int32()
  external int pim;
  @Int32()
  external int volId;
  @Int32()
  external int cipherId;
  @Int32()
  external int hashId;
  external Pointer<Uint8> preservedKey;
  @Int32()
  external int preservedKeyLen;
  external Pointer<Int32> keyfileFds;
  @Int32()
  external int keyfileCount;
  @Int32()
  external int readOnly;
  external Pointer<Uint8> hiddenPassword;
  @Int32()
  external int hiddenPasswordLen;
  @Int32()
  external int hiddenPim;
  @Int32()
  external int hiddenCipherId;
  @Int32()
  external int hiddenHashId;
  external Pointer<Int32> hiddenKeyfileFds;
  @Int32()
  external int hiddenKeyfileCount;
}

final class VeEvent extends Struct {
  @Int32()
  external int kind;
  @Int32()
  external int volId;
  @Int32()
  external int opId;
  @Int32()
  external int i0;
  @Int32()
  external int i1;
  @Int32()
  external int i2;
  @Int32()
  external int i3;
  @Int32()
  external int i4;
  @Int64()
  external int n0;
  @Int64()
  external int n1;
  @Array(240)
  external Array<Uint8> text;
}

/// A decoded native event (only the fields the host forwards).
class VeNativeEvent {
  VeNativeEvent(this.kind, this.volId, this.opId, this.i, this.n0, this.n1, this.text);
  final int kind;
  final int volId;
  final int opId;
  final List<int> i; // i0..i4
  final int n0;
  final int n1;
  final String text;
}

class VeNative {
  VeNative._(this._lib) {
    _openFile = _lib.lookupFunction<Int32 Function(Pointer<Utf8>, Int32), int Function(Pointer<Utf8>, int)>('ve_open_file');
    _closeFd = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ve_close_fd');
    _abiVersion = _lib.lookupFunction<Int32 Function(), int Function()>('ve_abi_version');
    _maxVolumes = _lib.lookupFunction<Int32 Function(), int Function()>('ve_max_volumes');
    _probe = _lib.lookupFunction<Pointer<Utf8> Function(Int32), Pointer<Utf8> Function(int)>('ve_probe_format');
    _unlock = _lib.lookupFunction<Int32 Function(Pointer<VeUnlockParams>), int Function(Pointer<VeUnlockParams>)>('ve_unlock');
    _cancelUnlock = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ve_request_cancel_unlock');
    _lock = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ve_lock');
    _format = _lib.lookupFunction<Int32 Function(Int32), int Function(int)>('ve_get_container_format');
    _matchedCipher = _lib.lookupFunction<Int32 Function(Int32), int Function(int)>('ve_get_matched_cipher_id');
    _matchedHash = _lib.lookupFunction<Int32 Function(Int32), int Function(int)>('ve_get_matched_hash_id');
    _bufferFree = _lib.lookupFunction<Void Function(Pointer<VeBuffer>), void Function(Pointer<VeBuffer>)>('ve_buffer_free');
    _list = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<VeBuffer>), int Function(int, Pointer<Utf8>, Pointer<VeBuffer>)>('ve_list_directory');
    _fileSize = _lib.lookupFunction<Int64 Function(Int32, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('ve_get_file_size');
    _folderSize = _lib.lookupFunction<Int64 Function(Int32, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('ve_get_folder_size');
    _readChunk = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Int64, Int32, Pointer<VeBuffer>), int Function(int, Pointer<Utf8>, int, int, Pointer<VeBuffer>)>('ve_read_file_chunk');
    _writeChunk = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Int64, Pointer<Uint8>, Size), int Function(int, Pointer<Utf8>, int, Pointer<Uint8>, int)>('ve_write_file_chunk');
    _delete = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('ve_delete_file');
    _mkdir = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>), int Function(int, Pointer<Utf8>)>('ve_create_directory');
    _rename = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>), int Function(int, Pointer<Utf8>, Pointer<Utf8>)>('ve_rename_file');
    _setMtime = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Int64), int Function(int, Pointer<Utf8>, int)>('ve_set_last_modified');
    _copy = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Int32, Pointer<Utf8>, Int32), int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int)>('ve_copy_file');
    _import = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>, Int32), int Function(int, Pointer<Utf8>, Pointer<Utf8>, int)>('ve_import_file');
    _export = _lib.lookupFunction<Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>, Int32), int Function(int, Pointer<Utf8>, Pointer<Utf8>, int)>('ve_export_file');
    _space = _lib.lookupFunction<Int32 Function(Int32, Pointer<Uint64>, Pointer<Uint64>), int Function(int, Pointer<Uint64>, Pointer<Uint64>)>('ve_get_space_info');
    _opRegister = _lib.lookupFunction<Void Function(Int32, Int32), void Function(int, int)>('ve_op_register');
    _opCancel = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ve_op_cancel');
    _opUnregister = _lib.lookupFunction<Void Function(Int32), void Function(int)>('ve_op_unregister');
    _poll = _lib.lookupFunction<Int32 Function(Pointer<VeEvent>), int Function(Pointer<VeEvent>)>('ve_poll_event');
  }

  final DynamicLibrary _lib;
  late final int Function(Pointer<Utf8>, int) _openFile;
  late final void Function(int) _closeFd;
  late final int Function() _abiVersion;
  late final int Function() _maxVolumes;
  late final Pointer<Utf8> Function(int) _probe;
  late final int Function(Pointer<VeUnlockParams>) _unlock;
  late final void Function(int) _cancelUnlock;
  late final void Function(int) _lock;
  late final int Function(int) _format;
  late final int Function(int) _matchedCipher;
  late final int Function(int) _matchedHash;
  late final void Function(Pointer<VeBuffer>) _bufferFree;
  late final int Function(int, Pointer<Utf8>, Pointer<VeBuffer>) _list;
  late final int Function(int, Pointer<Utf8>) _fileSize;
  late final int Function(int, Pointer<Utf8>) _folderSize;
  late final int Function(int, Pointer<Utf8>, int, int, Pointer<VeBuffer>) _readChunk;
  late final int Function(int, Pointer<Utf8>, int, Pointer<Uint8>, int) _writeChunk;
  late final int Function(int, Pointer<Utf8>) _delete;
  late final int Function(int, Pointer<Utf8>) _mkdir;
  late final int Function(int, Pointer<Utf8>, Pointer<Utf8>) _rename;
  late final int Function(int, Pointer<Utf8>, int) _setMtime;
  late final int Function(int, Pointer<Utf8>, int, Pointer<Utf8>, int) _copy;
  late final int Function(int, Pointer<Utf8>, Pointer<Utf8>, int) _import;
  late final int Function(int, Pointer<Utf8>, Pointer<Utf8>, int) _export;
  late final int Function(int, Pointer<Uint64>, Pointer<Uint64>) _space;
  late final void Function(int, int) _opRegister;
  late final void Function(int) _opCancel;
  late final void Function(int) _opUnregister;
  late final int Function(Pointer<VeEvent>) _poll;

  /// Where the engine library is looked for, in order: $VE_ENGINE_LIBRARY, next to the executable
  /// (the bundle layout the Flutter Linux/Windows build produces), then the system loader path.
  static List<String> candidatePaths() {
    final name = Platform.isWindows ? 'vaultexplorer_engine.dll' : 'libvaultexplorer_engine.so';
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    return [
      if (Platform.environment['VE_ENGINE_LIBRARY'] case final String env when env.isNotEmpty) env,
      '$exeDir$sep$name',
      '$exeDir${sep}lib$sep$name',
      name,
    ];
  }

  static VeNative open([String? explicitPath]) {
    final errors = <String>[];
    for (final path in [if (explicitPath != null) explicitPath, ...candidatePaths()]) {
      try {
        final native = VeNative._(DynamicLibrary.open(path));
        final v = native._abiVersion();
        if (v != kVeAbiVersion) {
          throw StateError('engine ABI $v, this app expects $kVeAbiVersion ($path)');
        }
        return native;
      } on Object catch (e) {
        errors.add('$path: $e');
      }
    }
    throw StateError('Could not load the VaultExplorer engine library:\n${errors.join('\n')}');
  }

  int get maxVolumes => _maxVolumes();

  // ── helpers ────────────────────────────────────────────────────────────

  T _withUtf8<T>(String s, T Function(Pointer<Utf8>) body) {
    final p = s.toNativeUtf8();
    try {
      return body(p);
    } finally {
      calloc.free(p);
    }
  }

  /// Runs [body] with a zeroed, freshly allocated VeBuffer and returns its contents (copied out and
  /// wiped natively) when the call reports success.
  (int, Uint8List?) _withBuffer(int Function(Pointer<VeBuffer>) body) {
    final buf = calloc<VeBuffer>();
    try {
      final rc = body(buf);
      Uint8List? bytes;
      if (rc == veOk && buf.ref.data != nullptr && buf.ref.len > 0) {
        bytes = Uint8List.fromList(buf.ref.data.asTypedList(buf.ref.len));
      } else if (rc == veOk) {
        bytes = Uint8List(0);
      }
      _bufferFree(buf);
      return (rc, bytes);
    } finally {
      calloc.free(buf);
    }
  }

  // ── host files / probing ───────────────────────────────────────────────

  int openFile(String path, {bool writable = false}) => _withUtf8(path, (p) => _openFile(p, writable ? 1 : 0));
  void closeFd(int fd) => _closeFd(fd);
  String probeFormat(int fd) => _probe(fd).toDartString();

  // ── lifecycle ──────────────────────────────────────────────────────────

  /// Unlocks [containerPath] into slot [volId]. The engine takes ownership of every descriptor
  /// opened here (container + keyfiles), exactly once, on success or failure.
  /// Returns a ve* result code (veOk on success), or -1 when the container file cannot be opened.
  int unlock({
    required String containerPath,
    required Uint8List password,
    required int pim,
    required int volId,
    int cipherId = 255,
    int hashId = 255,
    Uint8List? preservedKey,
    List<String> keyfilePaths = const [],
    bool readOnly = false,
    Uint8List? hiddenPassword,
    int hiddenPim = 0,
    int hiddenCipherId = 255,
    int hiddenHashId = 255,
    List<String> hiddenKeyfilePaths = const [],
  }) {
    final fd = openFile(containerPath, writable: !readOnly);
    if (fd < 0) return -1;

    List<int> openAll(List<String> paths) {
      final fds = <int>[];
      for (final p in paths) {
        final k = openFile(p);
        if (k < 0) {
          for (final f in fds) {
            closeFd(f);
          }
          return const [];
        }
        fds.add(k);
      }
      return fds;
    }

    final kf = openAll(keyfilePaths);
    if (keyfilePaths.isNotEmpty && kf.isEmpty) {
      closeFd(fd);
      return -1;
    }
    final hkf = hiddenPassword != null ? openAll(hiddenKeyfilePaths) : const <int>[];
    if (hiddenPassword != null && hiddenKeyfilePaths.isNotEmpty && hkf.isEmpty) {
      closeFd(fd);
      for (final f in kf) {
        closeFd(f);
      }
      return -1;
    }

    final params = calloc<VeUnlockParams>();
    Pointer<Uint8> copyBytes(Uint8List? src) {
      if (src == null) return nullptr;
      final p = calloc<Uint8>(src.isEmpty ? 1 : src.length);
      p.asTypedList(src.length).setAll(0, src);
      return p;
    }

    Pointer<Int32> copyFds(List<int> fds) {
      if (fds.isEmpty) return nullptr;
      final p = calloc<Int32>(fds.length);
      for (var i = 0; i < fds.length; i++) {
        p[i] = fds[i];
      }
      return p;
    }

    final pw = copyBytes(password);
    final pk = copyBytes(preservedKey);
    final hpw = copyBytes(hiddenPassword);
    final kfp = copyFds(kf);
    final hkfp = copyFds(hkf);
    try {
      final r = params.ref;
      r.structSize = sizeOf<VeUnlockParams>();
      r.fd = fd;
      r.password = pw;
      r.passwordLen = password.length;
      r.pim = pim;
      r.volId = volId;
      r.cipherId = cipherId;
      r.hashId = hashId;
      r.preservedKey = pk;
      r.preservedKeyLen = preservedKey?.length ?? 0;
      r.keyfileFds = kfp;
      r.keyfileCount = kf.length;
      r.readOnly = readOnly ? 1 : 0;
      r.hiddenPassword = hpw;
      r.hiddenPasswordLen = hiddenPassword?.length ?? 0;
      r.hiddenPim = hiddenPim;
      r.hiddenCipherId = hiddenCipherId;
      r.hiddenHashId = hiddenHashId;
      r.hiddenKeyfileFds = hkfp;
      r.hiddenKeyfileCount = hkf.length;
      return _unlock(params);
    } finally {
      // Wipe secrets before freeing.
      if (pw != nullptr) {
        pw.asTypedList(password.length).fillRange(0, password.length, 0);
        calloc.free(pw);
      }
      if (pk != nullptr) {
        pk.asTypedList(preservedKey!.length).fillRange(0, preservedKey.length, 0);
        calloc.free(pk);
      }
      if (hpw != nullptr) {
        hpw.asTypedList(hiddenPassword!.length).fillRange(0, hiddenPassword.length, 0);
        calloc.free(hpw);
      }
      if (kfp != nullptr) calloc.free(kfp);
      if (hkfp != nullptr) calloc.free(hkfp);
      calloc.free(params);
    }
  }

  void requestCancelUnlock(int volId) => _cancelUnlock(volId);
  void lock(int volId) => _lock(volId);
  int containerFormat(int volId) => _format(volId);
  int matchedCipherId(int volId) => _matchedCipher(volId);
  int matchedHashId(int volId) => _matchedHash(volId);

  // ── filesystem ─────────────────────────────────────────────────────────

  /// (resultCode, entries). Entries are the engine's directory-entry wire strings.
  (int, List<String>) listDirectory(int volId, String path) {
    final (rc, bytes) = _withUtf8(path, (p) => _withBuffer((b) => _list(volId, p, b)));
    if (rc != veOk || bytes == null || bytes.length < 4) return (rc, const []);
    final bd = ByteData.sublistView(bytes);
    final count = bd.getUint32(0, Endian.little);
    final out = <String>[];
    var off = 4;
    for (var i = 0; i < count && off + 4 <= bytes.length; i++) {
      final len = bd.getUint32(off, Endian.little);
      off += 4;
      if (off + len > bytes.length) break;
      out.add(utf8.decode(Uint8List.sublistView(bytes, off, off + len), allowMalformed: true));
      off += len;
    }
    return (rc, out);
  }

  /// >= 0 size, or a negative -veErr* code.
  int fileSize(int volId, String path) => _withUtf8(path, (p) => _fileSize(volId, p));
  int folderSize(int volId, String path) => _withUtf8(path, (p) => _folderSize(volId, p));

  (int, Uint8List?) readFileChunk(int volId, String path, int offset, int length) =>
      _withUtf8(path, (p) => _withBuffer((b) => _readChunk(volId, p, offset, length, b)));

  int writeFileChunk(int volId, String path, int offset, Uint8List data) {
    final buf = calloc<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      buf.asTypedList(data.length).setAll(0, data);
      return _withUtf8(path, (p) => _writeChunk(volId, p, offset, buf, data.length));
    } finally {
      buf.asTypedList(data.length).fillRange(0, data.length, 0);
      calloc.free(buf);
    }
  }

  int deleteFile(int volId, String path) => _withUtf8(path, (p) => _delete(volId, p));
  int createDirectory(int volId, String path) => _withUtf8(path, (p) => _mkdir(volId, p));
  int renameFile(int volId, String from, String to) =>
      _withUtf8(from, (a) => _withUtf8(to, (b) => _rename(volId, a, b)));
  int setLastModified(int volId, String path, int epochSeconds) =>
      _withUtf8(path, (p) => _setMtime(volId, p, epochSeconds));

  int copyFile(int srcVol, String src, int dstVol, String dst, int opId) =>
      _withUtf8(src, (a) => _withUtf8(dst, (b) => _copy(srcVol, a, dstVol, b, opId)));
  int importFile(int volId, String vaultPath, String hostSource, int opId) =>
      _withUtf8(vaultPath, (a) => _withUtf8(hostSource, (b) => _import(volId, a, b, opId)));
  int exportFile(int volId, String vaultPath, String hostDest, int opId) =>
      _withUtf8(vaultPath, (a) => _withUtf8(hostDest, (b) => _export(volId, a, b, opId)));

  /// (resultCode, [total, free])
  (int, List<int>) spaceInfo(int volId) {
    final t = calloc<Uint64>();
    final f = calloc<Uint64>();
    try {
      final rc = _space(volId, t, f);
      return (rc, rc == veOk ? [t.value, f.value] : const <int>[]);
    } finally {
      calloc.free(t);
      calloc.free(f);
    }
  }

  // ── operations / events ────────────────────────────────────────────────

  void opRegister(int opId, int flavor) => _opRegister(opId, flavor);
  void opCancel(int opId) => _opCancel(opId);
  void opUnregister(int opId) => _opUnregister(opId);

  /// Drains the native event queue (cheap; safe on the UI isolate).
  List<VeNativeEvent> pollEvents({int max = 64}) {
    final ev = calloc<VeEvent>();
    final out = <VeNativeEvent>[];
    try {
      while (out.length < max && _poll(ev) == 1) {
        final r = ev.ref;
        final chars = <int>[];
        for (var i = 0; i < 240; i++) {
          final c = r.text[i];
          if (c == 0) break;
          chars.add(c);
        }
        out.add(VeNativeEvent(r.kind, r.volId, r.opId, [r.i0, r.i1, r.i2, r.i3, r.i4], r.n0, r.n1,
            utf8.decode(chars, allowMalformed: true)));
      }
    } finally {
      calloc.free(ev);
    }
    return out;
  }
}
