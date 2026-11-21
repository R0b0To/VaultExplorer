// Splitting a container file into `.001`, `.002`, ... parts and joining them back (the "container
// splitter" tool), for the desktop engine.
//
// Plain byte copying -- Android does it in Kotlin with no native engine involvement, and the same is
// true here -- so it runs in Dart with asynchronous file I/O (nothing blocks the UI) and reproduces the
// Android behaviour exactly:
//   * parts are named `<name>.NNN` (3-digit, zero padded) next to a best-effort `manifest.json`
//     (displayName, format, totalSizeBytes, chunkSizeBytes) for interop with other split/join tools;
//   * a cancelled split keeps the parts already completed and drops only the one in flight;
//   * join finds its parts by the `<base>.NNN` / `<base>.partN` naming convention, starting from
//     whichever first part was picked (a plain, unsplit file is just copied);
//   * progress is pushed as `onSplitJoinProgress` {opId, bytesDone, bytesTotal}, cancellation via
//     `cancelSplitJoin`, a cancel answers CANCELLED and any other failure IO_ERROR.
//
// One improvement over Android: a join is written under a temporary name and renamed into place when
// complete, so a failed or cancelled join never leaves a half-written file at the chosen path.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class DesktopSplitJoin {
  DesktopSplitJoin({required this.emit});

  final void Function(String method, Object? arguments) emit;
  final Set<int> _cancelled = {};

  static const int _bufferSize = 4 << 20;
  static final RegExp _partSuffix = RegExp(r'^(.*)\.(\d+|part\d+)$', caseSensitive: false);

  void cancel(int opId) {
    if (opId > 0) _cancelled.add(opId);
  }

  bool _isCancelled(int opId) => opId > 0 && _cancelled.contains(opId);

  static PlatformException _invalid(String what) => PlatformException(code: 'INVALID_ARGS', message: what);

  /// Progress is pushed at most ~12x per second, plus the final value.
  void Function(int done, {bool force}) _throttledProgress(int opId, int total) {
    if (opId <= 0) return (_, {bool force = false}) {};
    final clock = Stopwatch()..start();
    var lastMs = -1000;
    return (int done, {bool force = false}) {
      final now = clock.elapsedMilliseconds;
      if (!force && now - lastMs < 80) return;
      lastMs = now;
      emit('onSplitJoinProgress', {'opId': opId, 'bytesDone': done, 'bytesTotal': total});
    };
  }

  // ── split ───────────────────────────────────────────────────────────────

  static String _guessFormat(String displayName) {
    final lower = displayName.toLowerCase();
    if (lower.contains('luks')) return 'LUKS';
    if (lower.contains('bitlocker')) return 'BITLOCKER';
    return 'VERACRYPT';
  }

  Future<void> split(Map<Object?, Object?> args) async {
    final source = args['sourceUri'] as String?;
    final destDir = args['destinationPath'] as String?;
    final chunk = (args['chunkSizeBytes'] as num?)?.toInt();
    final opId = (args['opId'] as num?)?.toInt() ?? 0;
    if (source == null || destDir == null || chunk == null || chunk <= 0) {
      throw _invalid('sourceUri, destinationPath, and a positive chunkSizeBytes are required');
    }

    RandomAccessFile? input;
    RandomAccessFile? partOut;
    File? partInProgress;
    try {
      input = await File(source).open();
      final total = await input.length();
      if (total <= 0) throw const FileSystemException('Could not determine source file size');
      await Directory(destDir).create(recursive: true);

      final displayName = p.basename(source);
      File partFile(int i) => File(p.join(destDir, '$displayName.${i.toString().padLeft(3, '0')}'));
      final progress = _throttledProgress(opId, total);

      var index = 0;
      var inPart = 0;
      var written = 0;
      while (true) {
        if (_isCancelled(opId)) throw _Cancelled('Split cancelled');
        if (partOut == null || inPart >= chunk) {
          // Open the next part only when there is data left for it -- an exact multiple of the chunk
          // size therefore never ships an empty trailing part.
          if (written >= total) break;
          await partOut?.close();
          partOut = null;
          index++;
          partInProgress = partFile(index);
          partOut = await partInProgress.open(mode: FileMode.write);
          inPart = 0;
        }
        final toRead = chunk - inPart < _bufferSize ? chunk - inPart : _bufferSize;
        final data = await input.read(toRead);
        if (data.isEmpty) break;
        await partOut.writeFrom(data);
        inPart += data.length;
        written += data.length;
        progress(written);
      }
      await partOut?.close();
      partOut = null;
      partInProgress = null;
      progress(written, force: true);

      // Best-effort manifest; every part is already complete and valid without it.
      try {
        await File(p.join(destDir, 'manifest.json')).writeAsString(jsonEncode({
          'displayName': displayName,
          'format': _guessFormat(displayName),
          'totalSizeBytes': total,
          'chunkSizeBytes': chunk,
        }));
      } on FileSystemException {
        // non-fatal
      }
    } on _Cancelled catch (e) {
      try {
        await partOut?.close();
      } on Object {
        // already closed
      }
      partOut = null;
      if (partInProgress != null) {
        try {
          await partInProgress.delete();
        } on FileSystemException {
          // nothing to drop
        }
      }
      throw PlatformException(code: 'CANCELLED', message: e.message);
    } on FileSystemException catch (e) {
      try {
        await partOut?.close();
      } on Object {
        // already closed
      }
      throw PlatformException(code: 'IO_ERROR', message: e.message);
    } finally {
      await input?.close();
      _cancelled.remove(opId);
    }
  }

  // ── join ────────────────────────────────────────────────────────────────

  /// The part sequence that [first] belongs to, by naming convention; just [first] for a plain file.
  static Future<List<File>> resolvePartSequence(File first) async {
    final match = _partSuffix.firstMatch(p.basename(first.path));
    if (match == null) return [first];
    final base = match.group(1)!;
    final suffix = match.group(2)!;
    final isPartWord = suffix.toLowerCase().startsWith('part');
    final width = suffix.length;
    final dir = p.dirname(first.path);
    final parts = <File>[];
    for (var n = 1;; n++) {
      final name = isPartWord ? '$base.part$n' : '$base.${n.toString().padLeft(width, '0')}';
      final candidate = File(p.join(dir, name));
      if (!await candidate.exists()) break;
      parts.add(candidate);
    }
    return parts.isEmpty ? [first] : parts;
  }

  Future<void> join(Map<Object?, Object?> args) async {
    final firstPart = args['firstPartUri'] as String?;
    final destination = args['destinationPath'] as String?; // the output FILE path
    final opId = (args['opId'] as num?)?.toInt() ?? 0;
    if (firstPart == null || destination == null) {
      throw _invalid('firstPartUri and destinationPath are required');
    }

    final staging = '$destination.vaultexplorer-part';
    RandomAccessFile? out;
    try {
      final parts = await resolvePartSequence(File(firstPart));
      var total = 0;
      for (final f in parts) {
        total += await f.length();
      }
      await Directory(p.dirname(destination)).create(recursive: true);
      out = await File(staging).open(mode: FileMode.write);
      final progress = _throttledProgress(opId, total);

      var written = 0;
      for (final part in parts) {
        if (_isCancelled(opId)) throw _Cancelled('Join cancelled');
        final input = await part.open();
        try {
          while (true) {
            if (_isCancelled(opId)) throw _Cancelled('Join cancelled');
            final data = await input.read(_bufferSize);
            if (data.isEmpty) break;
            await out.writeFrom(data);
            written += data.length;
            progress(written);
          }
        } finally {
          await input.close();
        }
      }
      await out.close();
      out = null;
      progress(written, force: true);
      await File(staging).rename(destination);
    } on _Cancelled catch (e) {
      await _dropStaging(out, staging);
      throw PlatformException(code: 'CANCELLED', message: e.message);
    } on FileSystemException catch (e) {
      await _dropStaging(out, staging);
      throw PlatformException(code: 'IO_ERROR', message: e.message);
    } finally {
      _cancelled.remove(opId);
    }
  }

  Future<void> _dropStaging(RandomAccessFile? out, String staging) async {
    try {
      await out?.close();
    } on Object {
      // already closed
    }
    try {
      await File(staging).delete();
    } on FileSystemException {
      // nothing was created
    }
  }
}

class _Cancelled implements Exception {
  _Cancelled(this.message);
  final String message;
}
