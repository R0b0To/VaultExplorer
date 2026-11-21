// Digest support for the checksum tool and the thumbnail cache's key derivation:
// hashBytesSha256 / hashBytesMd5, the begin/update/finish/discard hash sessions (used while Dart
// streams a vault file's chunks), and computeExternalFileHash (a plain host file).
//
// The digests are computed by the native engine (BoringSSL), one session feeding several algorithms
// in a single pass, exactly like the Android handler's per-algorithm MessageDigests. Wire names and
// result shape match: {"MD5": "<lowercase hex>", "SHA-1": ..., "SHA-256": ..., "SHA-512": ...}.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'engine_worker_pool.dart';
import 've_native.dart';

class _HashSession {
  _HashSession(this.handle, this.algorithms);
  final int handle;
  final List<String> algorithms;
}

class DesktopHash {
  DesktopHash(this.pool);

  final EngineWorkerPool pool;
  final Map<int, _HashSession> _sessions = {};
  final Set<int> _cancelled = {};

  static const Map<String, int> _ids = {
    'MD5': veHashMd5,
    'SHA-1': veHashSha1,
    'SHA-256': veHashSha256,
    'SHA-512': veHashSha512,
  };

  static String _hex(Uint8List b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  static PlatformException _error(String message) => PlatformException(code: 'HASH_ERROR', message: message);

  // ── one-shot ────────────────────────────────────────────────────────────

  Future<String> bytesHex(int algorithm, Uint8List bytes) async {
    final r = await pool.call('hashBytes', [algorithm, bytes]) as List<Object?>;
    if (r[0] != veOk) throw _error('digest failed');
    return _hex(r[1] as Uint8List);
  }

  // ── sessions ────────────────────────────────────────────────────────────

  Future<_HashSession> _open(List<String> algorithms) async {
    var mask = 0;
    for (final a in algorithms) {
      final id = _ids[a];
      if (id == null) throw _error('Unsupported algorithm: $a');
      mask |= 1 << id;
    }
    final handle = await pool.call('hashBegin', [mask]) as int;
    if (handle == 0) throw _error('could not open a hash session');
    return _HashSession(handle, List.of(algorithms));
  }

  Future<Map<String, String>> _finish(_HashSession s) async {
    final out = <String, String>{};
    try {
      for (final a in s.algorithms) {
        final r = await pool.call('hashFinish', [s.handle, _ids[a]]) as List<Object?>;
        if (r[0] != veOk) throw _error('digest failed for $a');
        out[a] = _hex(r[1] as Uint8List);
      }
    } finally {
      await pool.call('hashFree', [s.handle]);
    }
    return out;
  }

  Future<void> begin(int opId, List<String> algorithms) async {
    if (algorithms.isEmpty) {
      throw PlatformException(code: 'INVALID_ARGS', message: 'opId and a non-empty algorithms list are required');
    }
    final previous = _sessions.remove(opId);
    if (previous != null) await pool.call('hashFree', [previous.handle]);
    _sessions[opId] = await _open(algorithms);
  }

  Future<void> update(int opId, Uint8List bytes) async {
    final s = _sessions[opId];
    if (s == null) throw PlatformException(code: 'NO_SESSION', message: 'No hash session for opId $opId');
    final rc = await pool.call('hashUpdate', [s.handle, bytes]) as int;
    if (rc != veOk) throw _error('hash update failed');
  }

  Future<Map<String, String>> finish(int opId) async {
    final s = _sessions.remove(opId);
    if (s == null) throw PlatformException(code: 'NO_SESSION', message: 'No hash session for opId $opId');
    return _finish(s);
  }

  Future<void> discard(int opId) async {
    final s = _sessions.remove(opId);
    if (s != null) await pool.call('hashFree', [s.handle]);
  }

  void cancel(int opId) => _cancelled.add(opId);

  // ── a host file, in one read pass ───────────────────────────────────────

  /// Digests of the file at [uri] (a path or file:// URL); null if [opId] was cancelled.
  Future<Map<String, String>?> computeExternalFile(String uri, List<String> algorithms, int opId) async {
    final path = uri.startsWith('file:') ? Uri.parse(uri).toFilePath() : uri;
    final session = await _open(algorithms);
    RandomAccessFile? raf;
    var finished = false;
    try {
      raf = await File(path).open();
      while (true) {
        if (_cancelled.contains(opId)) return null;
        final chunk = await raf.read(4 << 20);
        if (chunk.isEmpty) break;
        final rc = await pool.call('hashUpdate', [session.handle, chunk]) as int;
        if (rc != veOk) throw _error('hash update failed');
      }
      finished = true;
      return await _finish(session);
    } on FileSystemException catch (e) {
      throw PlatformException(code: 'IO_ERROR', message: e.message);
    } finally {
      await raf?.close();
      if (!finished) await pool.call('hashFree', [session.handle]);
      _cancelled.remove(opId);
    }
  }

  Future<void> dispose() async {
    for (final s in _sessions.values) {
      await pool.call('hashFree', [s.handle]);
    }
    _sessions.clear();
  }
}
