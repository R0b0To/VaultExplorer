// OS mounts for the desktop engine: the desktop equivalent of Android's "expose this folder through the
// DocumentsProvider". An unlocked vault (or one of its folders) becomes a real directory, so the file
// manager and every other program can use it.
//
// The native side (ffi/ve_mount_*.cpp) does the work -- a FUSE 3 filesystem over the slot, the same for
// every vault format. This class only decides where mounts live, remembers which vault folder is
// mounted where, and reaps mounts the user ejected from outside the app.
//
//   Linux    FUSE 3 (libfuse3 + fusermount3 must be installed; reported through [unsupportedReason])
//   Windows  not built yet (the native side reports "unsupported")
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'engine_worker_pool.dart';
import 've_native.dart';

class DesktopMounts {
  DesktopMounts({required this.pool, Directory? baseDir}) : _baseDir = baseDir;

  final EngineWorkerPool pool;
  final Directory? _baseDir;

  /// vol id -> (vault-relative folder, "" = whole vault) -> the live mount.
  final Map<int, Map<String, _Active>> _byVol = {};
  Timer? _watch;

  /// Why the last mount/unmount failed, in words a user can act on ("" if it did not fail).
  String lastError = '';

  /// null when mounting works on this machine, otherwise a short reason ("libfuse3 not found ...").
  Future<String?> unsupportedReason() async {
    final r = await pool.call('mountSupported', const []) as List<Object?>;
    return r[0] == true ? null : (r[1] as String? ?? 'mounting is not available');
  }

  /// Vault-relative folders of [vol] that are mounted right now, in the form the browser UI uses for
  /// folder paths: no leading slash ("a/b"; the vault root is "").
  List<String> paths(int vol) => (_byVol[vol]?.keys ?? const <String>[]).toList();

  /// Mount point of a mounted folder, or null.
  String? mountPointOf(int vol, String path) => _byVol[vol]?[_normalize(path)]?.mountPoint;

  /// Mounts [path] (vault-relative; "" or "/" = the whole vault) of the unlocked slot [vol].
  Future<bool> mount({
    required int vol,
    required String path,
    String? displayName,
    String? containerName,
    bool readOnly = false,
  }) async {
    final key = _normalize(path);
    if (_byVol[vol]?[key] != null) return true; // already mounted
    final reason = await unsupportedReason();
    if (reason != null) {
      lastError = reason;
      debugPrint('[desktop-mounts] mounting is not available: $reason');
      return false;
    }
    final label = _label(displayName, key, containerName);
    final mp = await _freeMountPoint(label);
    if (mp == null) {
      lastError = 'could not choose a mount point';
      return false;
    }
    final r = await pool.call('mount', [vol, mp, readOnly, label, key.isEmpty ? null : '/$key']) as List<Object?>;
    final rc = r[0] as int;
    if (rc != veOk) {
      lastError = (r[2] as String?)?.trim().isNotEmpty == true ? r[2] as String : 'mount failed (code $rc)';
      debugPrint('[desktop-mounts] mount failed: $lastError');
      await _removeIfEmpty(mp);
      return false;
    }
    lastError = '';
    (_byVol[vol] ??= {})[key] = _Active(id: r[1] as int, mountPoint: mp);
    _ensureWatching();
    return true;
  }

  /// Unmounts [path]. [force] detaches even with files open (what locking does); otherwise a busy mount
  /// is refused and [lastError] says so.
  Future<bool> unmount({required int vol, required String path, bool force = false}) async {
    final key = _normalize(path);
    final m = _byVol[vol]?[key];
    if (m == null) return true;
    final r = await pool.call('unmount', [m.id, force]) as List<Object?>;
    final rc = r[0] as int;
    if (rc != veOk) {
      lastError = rc == veErrBusy ? 'files in the mounted folder are still open' : ((r[1] as String?) ?? 'unmount failed');
      return false;
    }
    lastError = '';
    _drop(vol, key);
    await _removeIfEmpty(m.mountPoint);
    return true;
  }

  /// The engine locked [vol] (which unmounts everything on it): forget our bookkeeping.
  void forgetVolume(int vol) {
    final mine = _byVol.remove(vol);
    if (mine == null) return;
    for (final m in mine.values) {
      unawaited(_removeIfEmpty(m.mountPoint));
    }
    if (_byVol.isEmpty) _stopWatching();
  }

  Future<void> dispose() async {
    _stopWatching();
    for (final vol in _byVol.keys.toList()) {
      forgetVolume(vol);
    }
  }

  // ── watching for mounts that were ejected from outside ──────────────────────────────────────────

  void _ensureWatching() {
    _watch ??= Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_reapEnded()));
  }

  void _stopWatching() {
    _watch?.cancel();
    _watch = null;
  }

  Future<void> _reapEnded() async {
    if (_byVol.isEmpty) {
      _stopWatching();
      return;
    }
    final rows = await pool.call('listMounts', const []) as List<Object?>;
    final live = <int, bool>{}; // id -> ended
    for (final row in rows) {
      final r = row as List<Object?>;
      live[r[0] as int] = r[2] as bool;
    }
    for (final vol in _byVol.keys.toList()) {
      for (final entry in (_byVol[vol] ?? const <String, _Active>{}).entries.toList()) {
        final ended = live[entry.value.id];
        if (ended == null || ended) {
          // Ejected from the file manager (or the FUSE side died): release the engine's bookkeeping.
          if (ended == true) await pool.call('unmount', [entry.value.id, true]);
          _drop(vol, entry.key);
          await _removeIfEmpty(entry.value.mountPoint);
        }
      }
    }
  }

  void _drop(int vol, String key) {
    final mine = _byVol[vol];
    if (mine == null) return;
    mine.remove(key);
    if (mine.isEmpty) _byVol.remove(vol);
    if (_byVol.isEmpty) _stopWatching();
  }

  // ── where mounts live ───────────────────────────────────────────────────────────────────────────

  /// `<data dir>/VaultExplorer/mnt`: a stable, user-visible place (Cryptomator uses the same idea).
  Directory _root() {
    final base = _baseDir;
    if (base != null) return base;
    final env = Platform.environment;
    if (Platform.isWindows) {
      return Directory(p.join(env['LOCALAPPDATA'] ?? Directory.systemTemp.path, 'VaultExplorer', 'mnt'));
    }
    final data = env['XDG_DATA_HOME']?.isNotEmpty == true
        ? env['XDG_DATA_HOME']!
        : p.join(env['HOME'] ?? Directory.systemTemp.path, '.local', 'share');
    return Directory(p.join(data, 'VaultExplorer', 'mnt'));
  }

  Future<String?> _freeMountPoint(String label) async {
    if (Platform.isWindows) return _freeDriveLetter();
    final root = _root();
    try {
      await root.create(recursive: true);
    } on Object catch (e) {
      debugPrint('[desktop-mounts] cannot create ${root.path}: $e');
      return null;
    }
    final taken = {for (final m in _byVol.values) for (final a in m.values) a.mountPoint};
    for (var i = 1; i < 100; i++) {
      final candidate = p.join(root.path, i == 1 ? label : '$label ($i)');
      if (taken.contains(candidate)) continue;
      final dir = Directory(candidate);
      if (!await dir.exists()) return candidate; // the engine creates it
      if (await dir.list().isEmpty) return candidate; // left over from an earlier run
    }
    return null;
  }

  /// Windows: a drive letter (Z: downwards) shows up in Explorer's "This PC" at once, which is what
  /// users expect from a mounted vault (Cryptomator does the same). WinFsp wants it as "X:".
  Future<String?> _freeDriveLetter() async {
    final taken = {for (final m in _byVol.values) for (final a in m.values) a.mountPoint.toUpperCase()};
    for (var c = 'Z'.codeUnitAt(0); c >= 'D'.codeUnitAt(0); c--) {
      final mp = '${String.fromCharCode(c)}:';
      if (taken.contains(mp)) continue;
      if (!await Directory('$mp\\').exists()) return mp;
    }
    return null;
  }

  Future<void> _removeIfEmpty(String mountPoint) async {
    if (Platform.isWindows && mountPoint.length == 2 && mountPoint[1] == ':') return; // a drive letter
    try {
      final d = Directory(mountPoint);
      if (await d.exists() && await d.list().isEmpty) await d.delete();
    } on Object {
      // Still mounted or not ours to delete: leave it.
    }
  }

  static String _normalize(String path) => path.replaceAll(RegExp(r'^/+|/+$'), '');

  static String _label(String? displayName, String key, String? containerName) {
    var s = (displayName ?? '').trim();
    if (s.isEmpty && key.isNotEmpty) s = key.split('/').last;
    if (s.isEmpty) s = (containerName ?? '').trim();
    if (s.isEmpty) s = 'Vault';
    s = s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').replaceAll(RegExp(r'^\.+'), '_');
    return s.length > 64 ? s.substring(0, 64) : s;
  }
}

class _Active {
  _Active({required this.id, required this.mountPoint});
  final int id;
  final String mountPoint;
}
