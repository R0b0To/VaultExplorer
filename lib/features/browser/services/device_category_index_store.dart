import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:vaultexplorer/core/utils/raw_entry.dart';

/// Turns bytes into other bytes (encrypts or decrypts them); null when it
/// cannot, e.g. a file that was written under a key that no longer exists.
typedef IndexBytesTransform = Future<Uint8List?> Function(Uint8List data);

const _formatTag = 'VEIDX1';

/// Keeps what a scan of phone storage found on disk, so the next time the app
/// starts the category can be shown at once instead of after a scan.
///
/// What is stored is a list of the person's file paths, so it is never written
/// as plain text: the bytes go through [encrypt] before they reach the disk
/// and through [decrypt] after they leave it. In the app both use the same
/// key as the thumbnail cache, which means wiping that key makes every stored
/// list unreadable at once.
///
/// One file per key. A file that cannot be read, decrypted or understood is
/// treated as missing (and removed): this is a cache, and the worst a bad
/// file may cost is one scan.
class DeviceCategoryIndexStore {
  DeviceCategoryIndexStore({
    required this.directory,
    required this.encrypt,
    required this.decrypt,
  });

  /// The folder the files live in; created on first write.
  final Future<Directory> Function() directory;
  final IndexBytesTransform encrypt;
  final IndexBytesTransform decrypt;

  Future<File> _fileFor(String key) async =>
      File('${(await directory()).path}/${fileNameForKey(key)}');

  /// The stored entries of [key], or null when there are none (or they cannot
  /// be read).
  Future<List<RawEntry>?> load(String key) async {
    final file = await _fileFor(key);
    try {
      if (!await file.exists()) return null;
      final plain = await decrypt(await file.readAsBytes());
      final entries = plain == null
          ? null
          : await Isolate.run(() => _decode(plain, key));
      if (entries == null) await _deleteQuietly(file);
      return entries;
    } catch (_) {
      await _deleteQuietly(file);
      return null;
    }
  }

  /// Replaces what is stored for [key] with [entries].
  Future<void> save(String key, List<RawEntry> entries) async {
    final lines = [for (final e in entries) e.raw];
    final builtAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final packed = await Isolate.run(() => _encode(key, builtAt, lines));
    final sealed = await encrypt(packed);
    if (sealed == null) return;
    final file = await _fileFor(key);
    await file.parent.create(recursive: true);
    // Written beside the target and moved over it, so a crash mid-write never
    // leaves half a list under the real name.
    final temp = File('${file.path}.tmp');
    await temp.writeAsBytes(sealed, flush: true);
    await temp.rename(file.path);
  }

  Future<void> delete(String key) async => _deleteQuietly(await _fileFor(key));

  /// Removes every stored list.
  Future<void> clear() async {
    try {
      final dir = await directory();
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Nothing useful to do about a folder that cannot be removed.
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best effort: an undeletable cache file is overwritten by the next
      // save, or rejected on load for failing to decrypt.
    }
  }

  /// A file name for [key] that is the same on every run and safe on any file
  /// system: two 32-bit FNV-1a hashes of the key, in hex. Not secret and not
  /// meant to be; the key is also written inside the file and checked on
  /// load, so a collision costs a cache miss, never a wrong answer.
  static String fileNameForKey(String key) {
    final bytes = utf8.encode(key);
    var a = 0x811c9dc5;
    var b = 0x9747b28c;
    for (final byte in bytes) {
      a = ((a ^ byte) * 0x01000193) & 0xFFFFFFFF;
      b = ((b ^ byte) * 0x01000193) & 0xFFFFFFFF;
    }
    return '${a.toRadixString(16).padLeft(8, '0')}'
        '${b.toRadixString(16).padLeft(8, '0')}.idx';
  }
}

// Both run in a worker isolate: gzip and (de)serialising tens of thousands of
// lines is real work that should not cost the UI a frame.

Uint8List _encode(String key, int builtAtSecs, List<String> lines) {
  final text = StringBuffer()
    ..writeln(_formatTag)
    ..writeln(key)
    ..writeln(builtAtSecs);
  for (final line in lines) {
    // A name with a line break cannot be told apart from two entries; such a
    // file simply is not cached.
    if (line.contains('\n') || line.contains('\r')) continue;
    text.writeln(line);
  }
  return Uint8List.fromList(gzip.encode(utf8.encode(text.toString())));
}

List<RawEntry>? _decode(Uint8List packed, String expectedKey) {
  final text = utf8.decode(gzip.decode(packed));
  final lines = const LineSplitter().convert(text);
  if (lines.length < 3 || lines[0] != _formatTag || lines[1] != expectedKey) {
    return null;
  }
  final entries = <RawEntry>[];
  for (var i = 3; i < lines.length; i++) {
    try {
      entries.add(RawEntry.parse(lines[i]));
    } on FormatException {
      return null;
    }
  }
  return entries.isEmpty ? null : entries;
}
