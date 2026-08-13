import 'dart:io';
import 'dart:typed_data';

/// Best-effort secure deletion for plaintext staging files that a native
/// crypto/vault engine required to be real files on host disk.
///
/// This exists for the small set of call sites documented in
/// docs/temp-file-audit.md as "Category D: unavoidable hardware/library-
/// constrained temp files" -- e.g. [ContainerToolService.runBatchFileCrypto],
/// which has to hand a real file path to a native VeraCrypt/LUKS/gocryptfs
/// engine that reads and writes files directly, not streams. Those call
/// sites should:
///  1. Create the temp file/dir in a private, app-scoped location
///     ([Directory.systemTemp] on Android resolves under the app's own
///     cache dir, not shared external storage).
///  2. Do the minimum necessary work with it.
///  3. Always route cleanup through [wipeAndDelete]/[wipeAndDeleteDir] in
///     a `finally` block, instead of a plain `delete()`.
///
/// Overwrites the file's contents with zeros before removing the
/// directory entry, so the plaintext bytes aren't sitting in a
/// freed-but-untouched block if the filesystem hands that block back out
/// without zeroing it first.
///
/// This is defense-in-depth, not a guarantee: on flash storage with
/// wear-levelling (effectively all Android devices), the physical cell
/// backing the file's last-written state may not be the one that
/// actually gets overwritten by this pass, so remnants of the plaintext
/// can still persist at the hardware level afterwards. There's no
/// portable Dart API for a block-level TRIM/discard call, so this
/// deliberately doesn't claim to be forensically exhaustive -- it
/// guarantees the bytes are gone from the filesystem's perspective (a
/// same-process or file-manager-level read finds nothing), which is the
/// realistic threat model for a temp file that only exists for the
/// duration of one operation. Callers that can avoid touching disk at
/// all (see Category A/B/C in the audit) should always prefer that over
/// relying on this.
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
