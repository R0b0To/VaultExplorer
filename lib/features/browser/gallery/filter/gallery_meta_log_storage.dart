import 'dart:convert';
import 'dart:typed_data';

import 'gallery_meta_index.dart';

/// The few file operations the stored index log needs, on the folder that
/// holds one source's index files.
abstract interface class GalleryMetaFiles {
  /// Nothing may be written (a read-only source).
  bool get readOnly;

  /// Names of the files in the folder; null when it cannot be listed.
  Future<List<String>?> listNames();

  Future<Uint8List?> read(String name);

  /// Creates the folder if needed, then replaces [name] atomically.
  Future<bool> write(String name, Uint8List bytes);

  Future<bool> delete(String name);
}

/// How the files of the index log are named: `gallery_meta.json` is the base
/// (and what versions before the log wrote as the whole index), then
/// `gallery_meta.000001.json`, `gallery_meta.000002.json`...
abstract final class GalleryMetaSegmentNames {
  static const String base = 'gallery_meta.json';
  static const String _prefix = 'gallery_meta.';
  static const String _suffix = '.json';

  /// The sequence number [name] stands for: 0 for the base file, n for
  /// `gallery_meta.00000n.json`, null for any other file.
  static int? seqOf(String name) {
    if (name == base) return 0;
    if (!name.startsWith(_prefix) || !name.endsWith(_suffix)) return null;
    if (name.length <= _prefix.length + _suffix.length) return null;
    final n = int.tryParse(
      name.substring(_prefix.length, name.length - _suffix.length),
    );
    return n != null && n > 0 ? n : null;
  }

  static String nameOf(int seq) => seq == 0
      ? base
      : '$_prefix${seq.toString().padLeft(6, '0')}$_suffix';
}

/// A [GalleryMetaStorage] that keeps the index as a log of small files (see
/// [GalleryMetaSegmentNames]): appending a batch of photos writes one new file,
/// whatever the size of the library, where the previous single-file format
/// rewrote the whole index every time.
class GalleryMetaLogStorage implements GalleryMetaStorage {
  GalleryMetaLogStorage(this._filesOf, {this.allowWrite});

  /// The files of a source, or null when it has none to offer (locked, or its
  /// own phone storage, which gets nothing written).
  final GalleryMetaFiles? Function(int volId) _filesOf;

  /// Whether the source may be written to at all (false when its owner turned
  /// persistent caching off: nothing derived from the files is then kept).
  final bool Function(int volId)? allowWrite;

  final Map<int, int> _nextSeq = {};

  Future<List<({int seq, String name})>> _list(GalleryMetaFiles files) async {
    final names = await files.listNames();
    if (names == null) return const [];
    final found = <({int seq, String name})>[];
    for (final name in names) {
      final seq = GalleryMetaSegmentNames.seqOf(name);
      if (seq != null) found.add((seq: seq, name: name));
    }
    found.sort((a, b) => a.seq.compareTo(b.seq));
    return found;
  }

  GalleryMetaFiles? _writable(int volId) {
    final files = _filesOf(volId);
    if (files == null || files.readOnly) return null;
    if (allowWrite != null && !allowWrite!(volId)) return null;
    return files;
  }

  @override
  bool persists(int volId) => _writable(volId) != null;

  @override
  Future<List<String>> loadSegments(int volId) async {
    final files = _filesOf(volId);
    if (files == null) return const [];
    final list = await _list(files);
    _nextSeq[volId] = (list.isEmpty ? 0 : list.last.seq) + 1;
    final texts = <String>[];
    for (final f in list) {
      final bytes = await files.read(f.name);
      if (bytes == null || bytes.isEmpty) continue;
      texts.add(utf8.decode(bytes, allowMalformed: true));
    }
    return texts;
  }

  @override
  Future<bool> appendSegment(int volId, String json) async {
    final files = _writable(volId);
    if (files == null) return false;
    var seq = _nextSeq[volId];
    if (seq == null) {
      final list = await _list(files);
      seq = (list.isEmpty ? 0 : list.last.seq) + 1;
    }
    final ok = await files.write(
      GalleryMetaSegmentNames.nameOf(seq),
      Uint8List.fromList(utf8.encode(json)),
    );
    if (ok) _nextSeq[volId] = seq + 1;
    return ok;
  }

  @override
  Future<bool> replaceSegments(int volId, String json) async {
    final files = _writable(volId);
    if (files == null) return false;
    // The base file is committed atomically; only then are the segments it now
    // contains dropped. A crash in between leaves duplicates, which merge to
    // the same result.
    final ok = await files.write(
      GalleryMetaSegmentNames.base,
      Uint8List.fromList(utf8.encode(json)),
    );
    if (!ok) return false;
    var highest = 0;
    for (final f in await _list(files)) {
      if (f.seq == 0) continue;
      if (!await files.delete(f.name) && f.seq > highest) highest = f.seq;
    }
    _nextSeq[volId] = highest + 1;
    return true;
  }
}
