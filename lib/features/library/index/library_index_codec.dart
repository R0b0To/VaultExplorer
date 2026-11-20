import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vaultexplorer/features/library/models/library_track.dart';

/// Serializes a track list to a compact byte blob and back.
///
/// The blob is gzip-compressed JSON of positional rows (see
/// [LibraryTrack.toJson]). It is only ever stored encrypted, so there is
/// nothing to protect here beyond making it small and rejecting damage:
/// [decode] checks every field's type and throws [FormatException] on any
/// mismatch, so a corrupt or outdated blob is treated as "no index" and
/// rebuilt rather than half-trusted.
class LibraryIndexCodec {
  LibraryIndexCodec._();

  /// Bump when the row layout changes; older blobs are then discarded.
  static const int version = 1;

  static Uint8List encode(Iterable<LibraryTrack> tracks) {
    final rows = [for (final t in tracks) t.toJson()];
    final json = jsonEncode({'v': version, 'n': rows.length, 't': rows});
    return Uint8List.fromList(gzip.encode(utf8.encode(json)));
  }

  static List<LibraryTrack> decode(Uint8List bytes) {
    final Object? parsed;
    try {
      parsed = jsonDecode(utf8.decode(gzip.decode(bytes)));
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('unreadable index blob: $e');
    }
    if (parsed is! Map) throw const FormatException('index root is not an object');
    if (parsed['v'] != version) {
      throw FormatException('index version ${parsed['v']} is not $version');
    }
    final rows = parsed['t'];
    final n = parsed['n'];
    if (rows is! List || n is! int || rows.length != n) {
      throw const FormatException('index row count mismatch');
    }
    return [for (final r in rows) LibraryTrack.fromJson(r)];
  }
}
