import 'dart:io';
import 'dart:typed_data';

/// Best-effort secure deletion for plaintext staging files that a native
/// crypto/vault engine required to be real files on host disk.
class SecureTempFile {
  SecureTempFile._();

  static const _wipeChunkSize = 4 * 1024 * 1024; // 4 MB

  /// Zero-fills [file] in place, then deletes it. Safe to call on a file
  /// that doesn't exist (or was already deleted) -- both are treated as
  /// success, since "no plaintext left under this path" is the actual
  /// postcondition callers care about.
  static Future<void> wipeAndDelete(File file) async {
    try {
      if (!await file.exists()) return;
      final length = await file.length();
      if (length > 0) {
        final raf = await file.open(mode: FileMode.write);
        try {
          final zeros = Uint8List(_wipeChunkSize);
          var remaining = length;
          while (remaining > 0) {
            final n = remaining > _wipeChunkSize ? _wipeChunkSize : remaining;
            await raf.writeFrom(zeros, 0, n);
            remaining -= n;
          }
          await raf.flush();
        } finally {
          await raf.close();
        }
      }
      await file.delete();
    } catch (_) {
      // Best-effort: if the zero-fill pass failed partway through (disk
      // full, permission race, etc.) still try a plain delete so we
      // don't leave the directory entry behind.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  /// Recursively [wipeAndDelete]s every regular file under [dir], then
  /// removes the (now-empty) directory tree. Use for whole-directory
  /// staging areas, e.g. a `Directory.systemTemp.createTemp(...)` used as
  /// a scratch dir for a single crypto operation.
  static Future<void> wipeAndDeleteDir(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          await wipeAndDelete(entity);
        }
      }
      await dir.delete(recursive: true);
    } catch (_) {
      try {
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
