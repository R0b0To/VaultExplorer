// Handing files to other applications, and the small host-file helpers the app's checksum and
// export-to-folder features rely on.
//
// IMPORTANT privacy difference from Android: Android streams a vault file to the external app
// through a pipe, so no plaintext ever touches storage. A desktop application can only be given a
// FILE. "Open with" therefore writes one decrypted copy, which this class keeps as contained as it
// can:
//   * it lives in a fresh directory under $XDG_RUNTIME_DIR (a per-user, memory-backed tmpfs on
//     Linux) when available, otherwise the system temp directory, created with owner-only access;
//   * it is deleted when that vault is locked, when the engine shuts down, and -- for a crashed
//     run -- the next time the app starts (stale `vaultexplorer-open-*` directories are purged);
//   * nothing else in the app uses it.
// A viewer the user keeps open after locking loses its file, which is the intent.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class DesktopExternal {
  DesktopExternal();

  static const String _tempPrefix = 'vaultexplorer-open-';
  final Map<int, List<Directory>> _tempByVolume = {};
  bool _purgedStale = false;

  // ── launching ───────────────────────────────────────────────────────────

  /// Opens [target] (a file path, or a URL) with the desktop's default handler.
  Future<bool> launch(String target) async {
    try {
      if (Platform.isLinux) {
        await Process.start('xdg-open', [target], mode: ProcessStartMode.detached);
      } else if (Platform.isWindows) {
        await Process.start('rundll32', ['url.dll,FileProtocolHandler', target], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [target], mode: ProcessStartMode.detached);
      } else {
        return false;
      }
      return true;
    } on ProcessException catch (e) {
      debugPrint('[desktop-engine] could not launch a handler: ${e.message}');
      return false;
    }
  }

  /// Only web and mail links: this is reachable from content inside a vault, so it must not become
  /// a way to start arbitrary protocol handlers.
  Future<bool> launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !const {'http', 'https', 'mailto'}.contains(uri.scheme.toLowerCase())) return false;
    return launch(uri.toString());
  }

  Future<bool> openLocalFile(String path) async {
    if (!await File(path).exists()) return false;
    return launch(path);
  }

  // ── "open with" for a vault file: one contained plaintext copy ──────────

  Future<Directory> _newTempDir() async {
    if (!_purgedStale) {
      _purgedStale = true;
      await _purgeStale();
    }
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    final base = (runtime != null && runtime.isNotEmpty && Directory(runtime).existsSync())
        ? Directory(runtime)
        : Directory.systemTemp;
    final dir = await base.createTemp(_tempPrefix); // mkdtemp: created 0700 on POSIX
    return dir;
  }

  Future<void> _purgeStale() async {
    final bases = <Directory>{Directory.systemTemp};
    final runtime = Platform.environment['XDG_RUNTIME_DIR'];
    if (runtime != null && runtime.isNotEmpty) bases.add(Directory(runtime));
    for (final base in bases) {
      try {
        await for (final e in base.list(followLinks: false)) {
          if (e is Directory && p.basename(e.path).startsWith(_tempPrefix)) {
            try {
              await e.delete(recursive: true);
            } on FileSystemException {
              // in use or not ours; leave it
            }
          }
        }
      } on FileSystemException {
        // base not listable
      }
    }
  }

  /// Creates the directory + destination path for a decrypted copy of [fileName] belonging to [vol].
  Future<String> reserveTempCopy(int vol, String fileName) async {
    final dir = await _newTempDir();
    (_tempByVolume[vol] ??= []).add(dir);
    // Only the file name, never any directory part of the vault path.
    return p.join(dir.path, p.basename(fileName));
  }

  /// Deletes every decrypted copy made for [vol] (called on lock / when a session disappears).
  Future<void> cleanupVolume(int vol) async {
    final dirs = _tempByVolume.remove(vol);
    if (dirs == null) return;
    for (final d in dirs) {
      try {
        await d.delete(recursive: true);
      } on FileSystemException {
        // already gone
      }
    }
  }

  Future<void> cleanupAll() async {
    for (final vol in _tempByVolume.keys.toList()) {
      await cleanupVolume(vol);
    }
  }

  // ── plain host-file helpers ─────────────────────────────────────────────

  /// Whole contents of a small host file (checksum manifests); null if unreadable.
  Future<Uint8List?> readFileBytes(String path) async {
    try {
      return await File(path).readAsBytes();
    } on FileSystemException {
      return null;
    }
  }

  /// Writes [bytes] as [fileName] inside the folder [directory]; IO_ERROR on failure.
  Future<void> writeFileBytes(String directory, String fileName, Uint8List bytes) async {
    try {
      await File(p.join(directory, p.basename(fileName))).writeAsBytes(bytes, flush: true);
    } on FileSystemException catch (e) {
      throw PlatformException(code: 'IO_ERROR', message: e.message);
    }
  }
}
