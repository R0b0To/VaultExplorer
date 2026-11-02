import 'dart:async';
import 'dart:convert';

import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';

/// Saved reading locations are encrypted with the app's secure preferences.
/// The archive path and its bookmarks therefore never appear in a preference
/// key or a plaintext cache file.
class BookReaderState {
  final int position;
  final double fraction;
  final bool rtl;
  final bool showComicThumbnails;
  final String mode;
  final List<BookReaderBookmark> bookmarks;
  final Map<String, Object?> epubSettings;

  const BookReaderState({
    this.position = 0,
    this.fraction = 0,
    this.rtl = false,
    this.showComicThumbnails = true,
    this.mode = '',
    this.bookmarks = const [],
    this.epubSettings = const {},
  });

  factory BookReaderState.fromMap(Map<Object?, Object?> map) => BookReaderState(
    position: (map['position'] as num?)?.toInt() ?? 0,
    fraction: ((map['fraction'] as num?)?.toDouble() ?? 0)
        .clamp(0.0, 1.0)
        .toDouble(),
    rtl: map['rtl'] as bool? ?? false,
    showComicThumbnails: map['showComicThumbnails'] as bool? ?? true,
    mode: map['mode'] as String? ?? '',
    bookmarks: (map['bookmarks'] as List? ?? const [])
        .whereType<Map>()
        .map(BookReaderBookmark.fromMap)
        .toList(growable: false),
    epubSettings: map['epubSettings'] is Map
        ? Map<String, Object?>.from(map['epubSettings'] as Map)
        : const {},
  );

  Map<String, Object?> toMap() => {
    'position': position,
    'fraction': fraction,
    'rtl': rtl,
    'showComicThumbnails': showComicThumbnails,
    'mode': mode,
    'bookmarks': bookmarks.map((e) => e.toMap()).toList(growable: false),
    'epubSettings': epubSettings,
  };

  BookReaderState copyWith({
    int? position,
    double? fraction,
    bool? rtl,
    bool? showComicThumbnails,
    String? mode,
    List<BookReaderBookmark>? bookmarks,
    Map<String, Object?>? epubSettings,
  }) => BookReaderState(
    position: position ?? this.position,
    fraction: fraction ?? this.fraction,
    rtl: rtl ?? this.rtl,
    showComicThumbnails: showComicThumbnails ?? this.showComicThumbnails,
    mode: mode ?? this.mode,
    bookmarks: bookmarks ?? this.bookmarks,
    epubSettings: epubSettings ?? this.epubSettings,
  );
}

class BookReaderBookmark {
  final int position;
  final double fraction;

  const BookReaderBookmark(this.position, [this.fraction = 0]);

  factory BookReaderBookmark.fromMap(Map map) => BookReaderBookmark(
    (map['position'] as num?)?.toInt() ?? 0,
    ((map['fraction'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0).toDouble(),
  );

  Map<String, Object?> toMap() => {'position': position, 'fraction': fraction};
}

class BookReaderStateStore {
  BookReaderStateStore([this._secure = AppSecureStorage.instance]);

  final AppSecureStorage _secure;
  static const _storageKey = 'book_reader_state_v1';
  static Future<void> _writes = Future<void>.value();

  String documentId(MountedContainer container, String path) =>
      '${container.isLocalStorage ? container.uri : container.volId}:$path';

  Future<BookReaderState> load(String id) async {
    try {
      final raw = await _secure.read(key: _storageKey);
      if (raw == null || raw.isEmpty) return const BookReaderState();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const BookReaderState();
      final books = decoded['books'];
      final value = books is Map ? books[id] : null;
      return value is Map
          ? BookReaderState.fromMap(value)
          : const BookReaderState();
    } catch (_) {
      return const BookReaderState();
    }
  }

  Future<void> save(String id, BookReaderState state) {
    // Serialize read/modify/write operations so a progress update cannot erase
    // a bookmark write that was queued immediately before it.
    final next = _writes.then((_) async {
      try {
        final raw = await _secure.read(key: _storageKey);
        final decoded = raw == null ? null : jsonDecode(raw);
        final books = <String, Object?>{};
        if (decoded is Map && decoded['books'] is Map) {
          (decoded['books'] as Map).forEach((key, value) {
            if (key is String) books[key] = value;
          });
        }
        books.remove(id);
        books[id] = state.toMap();
        while (books.length > 200) {
          books.remove(books.keys.first);
        }
        await _secure.write(
          key: _storageKey,
          value: jsonEncode({'version': 1, 'books': books}),
        );
      } catch (_) {
        // Reader UX should continue if the platform's secure preferences are
        // temporarily unavailable.
      }
    });
    _writes = next.catchError((Object _) {});
    return next;
  }
}

final bookReaderStateStore = BookReaderStateStore();
