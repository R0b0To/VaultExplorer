import 'package:vaultexplorer/features/library/models/library_track.dart';

/// Case and accent folding for sorting, grouping and search.
class LibraryText {
  LibraryText._();

  static final Map<int, String> _fold = _buildFoldTable();

  static Map<int, String> _buildFoldTable() {
    final m = <int, String>{};
    void add(String chars, String to) {
      for (final r in chars.runes) {
        m[r] = to;
      }
    }

    add('àáâãäåāăąǎ', 'a');
    add('çćĉċč', 'c');
    add('ďđð', 'd');
    add('èéêëēĕėęěȩ', 'e');
    add('ĝğġģ', 'g');
    add('ĥħ', 'h');
    add('ìíîïĩīĭįıǐ', 'i');
    add('ĵ', 'j');
    add('ķ', 'k');
    add('ĺļľŀł', 'l');
    add('ñńņňŉ', 'n');
    add('òóôõöøōŏőǒ', 'o');
    add('ŕŗř', 'r');
    add('śŝşšș', 's');
    add('ţťŧț', 't');
    add('ùúûüũūŭůűųǔ', 'u');
    add('ŵ', 'w');
    add('ýÿŷ', 'y');
    add('źżž', 'z');
    m['ß'.runes.first] = 'ss';
    m['æ'.runes.first] = 'ae';
    m['œ'.runes.first] = 'oe';
    m['þ'.runes.first] = 'th';
    return m;
  }

  /// Lowercases, strips common Latin diacritics and collapses whitespace.
  static String fold(String s) {
    if (s.isEmpty) return s;
    final lower = s.toLowerCase();
    final out = StringBuffer();
    var lastSpace = true;
    for (final r in lower.runes) {
      final String piece;
      if (r < 128) {
        piece = String.fromCharCode(r);
      } else {
        piece = _fold[r] ?? String.fromCharCode(r);
      }
      final isSpace = piece == ' ' || piece == '\t' || piece == '\n' || piece == '\u00A0';
      if (isSpace) {
        if (!lastSpace) out.write(' ');
        lastSpace = true;
      } else {
        out.write(piece);
        lastSpace = false;
      }
    }
    final result = out.toString();
    return result.endsWith(' ') ? result.substring(0, result.length - 1) : result;
  }

  /// Orders by folded text, then raw text, with digit runs compared as numbers
  /// ("Track 2" before "Track 10").
  static int compare(String a, String b) {
    final c = naturalCompare(fold(a), fold(b));
    return c != 0 ? c : a.compareTo(b);
  }

  static int naturalCompare(String a, String b) {
    var i = 0;
    var j = 0;
    while (i < a.length && j < b.length) {
      final ca = a.codeUnitAt(i);
      final cb = b.codeUnitAt(j);
      final da = ca >= 0x30 && ca <= 0x39;
      final db = cb >= 0x30 && cb <= 0x39;
      if (da && db) {
        var ei = i;
        while (ei < a.length && _isDigit(a.codeUnitAt(ei))) {
          ei++;
        }
        var ej = j;
        while (ej < b.length && _isDigit(b.codeUnitAt(ej))) {
          ej++;
        }
        final na = a.substring(i, ei).replaceFirst(RegExp(r'^0+(?=\d)'), '');
        final nb = b.substring(j, ej).replaceFirst(RegExp(r'^0+(?=\d)'), '');
        if (na.length != nb.length) return na.length - nb.length;
        final c = na.compareTo(nb);
        if (c != 0) return c;
        i = ei;
        j = ej;
      } else {
        if (ca != cb) return ca - cb;
        i++;
        j++;
      }
    }
    return (a.length - i) - (b.length - j);
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
}

/// How multi-name tag values are split into separate artists and genres.
///
/// Splitting is deliberately conservative. Separators need surrounding spaces
/// (so "AC/DC" and "Simon & Garfunkel" stay whole) and the list is short.
class TagSplitConfig {
  final List<String> artistSeparators;
  final List<String> genreSeparators;

  const TagSplitConfig({
    this.artistSeparators = const [';', ' / ', ' feat. ', ' feat ', ' ft. ', ' featuring '],
    this.genreSeparators = const [';', ' / '],
  });

  static RegExp _pattern(List<String> seps) => RegExp(
        seps.map(RegExp.escape).join('|'),
        caseSensitive: false,
      );

  List<String> splitArtists(Iterable<String> raw) =>
      _split(raw, _pattern(artistSeparators));

  List<String> splitGenres(Iterable<String> raw) =>
      _split(raw, _pattern(genreSeparators));

  static List<String> _split(Iterable<String> raw, RegExp pattern) {
    final out = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      for (final part in value.split(pattern)) {
        final name = part.trim();
        if (name.isEmpty) continue;
        if (seen.add(LibraryText.fold(name))) out.add(name);
      }
    }
    return out;
  }
}

/// Sorting for tracks that belong to one album.
int compareAlbumOrder(LibraryTrack a, LibraryTrack b) {
  final da = a.discNo == 0 ? 1 : a.discNo;
  final db = b.discNo == 0 ? 1 : b.discNo;
  if (da != db) return da - db;
  final ta = a.trackNo == 0 ? 1 << 30 : a.trackNo;
  final tb = b.trackNo == 0 ? 1 << 30 : b.trackNo;
  if (ta != tb) return ta - tb;
  return LibraryText.compare(a.fileName, b.fileName);
}

class AlbumGroup {
  final String key;

  /// The album tag, or the folder name when the files have no album tag.
  /// Empty when neither is available (files in the container root).
  final String title;

  /// True when [title] came from a tag rather than the folder.
  final bool tagged;

  /// Album artist, or the single track artist when the tracks share one.
  /// Empty when unknown or when [variousArtists].
  final String artist;
  final bool variousArtists;

  /// Earliest year among the tracks, 0 when none has one.
  final int year;

  final List<LibraryTrack> tracks;

  AlbumGroup({
    required this.key,
    required this.title,
    required this.tagged,
    required this.artist,
    required this.variousArtists,
    required this.year,
    required this.tracks,
  });

  int get durationMs => tracks.fold(0, (sum, t) => sum + t.durationMs);

  /// A track whose file carries a picture, to draw the album's cover from.
  LibraryTrack? get coverTrack {
    for (final t in tracks) {
      if (t.hasCover) return t;
    }
    return null;
  }

  late final String searchText = LibraryText.fold('$title $artist');

  /// When the newest file in the album was added or changed (0 when unknown).
  late final int addedSecs = tracks.fold(
    0,
    (latest, t) => t.modifiedSecs > latest ? t.modifiedSecs : latest,
  );
}

class ArtistGroup {
  final String key;

  /// Empty for the "unknown artist" group.
  final String name;
  final List<LibraryTrack> tracks;

  ArtistGroup({required this.key, required this.name, required this.tracks});

  bool get isUnknown => key.isEmpty;

  int get durationMs => tracks.fold(0, (sum, t) => sum + t.durationMs);

  LibraryTrack? get coverTrack {
    for (final t in tracks) {
      if (t.hasCover) return t;
    }
    return null;
  }

  late final String searchText = LibraryText.fold(name);
}

class GenreGroup {
  final String key;

  /// Empty for the "unknown genre" group.
  final String name;
  final List<LibraryTrack> tracks;

  GenreGroup({required this.key, required this.name, required this.tracks});

  bool get isUnknown => key.isEmpty;

  int get durationMs => tracks.fold(0, (sum, t) => sum + t.durationMs);

  late final String searchText = LibraryText.fold(name);
}

enum AlbumSort { title, artist, year, recentlyAdded }

enum ArtistSort { name, trackCount }

enum TrackSort { title, artist, album, duration, recentlyAdded }

/// Alternative orderings of the lists [LibraryIndex] builds.
///
/// Each call returns a new list. Entries with no value for the chosen
/// criterion (no year, unknown artist, no date) always sort to the end, in
/// either direction, so reversing a list never buries real entries under
/// blanks. Every ordering ends in a unique tie-break, so results are
/// deterministic. String keys are folded once up front rather than inside the
/// comparator, which matters for tens of thousands of tracks.
class LibrarySorting {
  LibrarySorting._();

  static List<AlbumGroup> albums(
    List<AlbumGroup> albums,
    AlbumSort by, {
    bool descending = false,
  }) {
    return _sort<AlbumGroup>(
      albums,
      descending: descending,
      key: (a) {
        final title = LibraryText.fold(a.title);
        switch (by) {
          case AlbumSort.title:
            return [title, LibraryText.fold(a.artist), a.key];
          case AlbumSort.artist:
            return [LibraryText.fold(a.artist), title, a.key];
          case AlbumSort.year:
            return [a.year, title, a.key];
          case AlbumSort.recentlyAdded:
            return [a.addedSecs, title, a.key];
        }
      },
      isBlank: (a) => switch (by) {
        AlbumSort.title => a.title.isEmpty,
        AlbumSort.artist => a.variousArtists || a.artist.isEmpty,
        AlbumSort.year => a.year == 0,
        AlbumSort.recentlyAdded => a.addedSecs == 0,
      },
    );
  }

  static List<ArtistGroup> artists(
    List<ArtistGroup> artists,
    ArtistSort by, {
    bool descending = false,
  }) {
    return _sort<ArtistGroup>(
      artists,
      descending: descending,
      key: (a) => switch (by) {
        ArtistSort.name => [LibraryText.fold(a.name), a.key],
        ArtistSort.trackCount => [a.tracks.length, LibraryText.fold(a.name), a.key],
      },
      isBlank: (a) => a.isUnknown,
    );
  }

  static List<LibraryTrack> tracks(
    List<LibraryTrack> tracks,
    TrackSort by, {
    bool descending = false,
  }) {
    return _sort<LibraryTrack>(
      tracks,
      descending: descending,
      key: (t) {
        final title = LibraryText.fold(t.title);
        switch (by) {
          case TrackSort.title:
            return [title, t.key];
          case TrackSort.artist:
            return [
              LibraryText.fold(t.artists.isEmpty ? '' : t.artists.first),
              LibraryText.fold(t.album),
              t.discNo == 0 ? 1 : t.discNo,
              t.trackNo == 0 ? 1 << 30 : t.trackNo,
              title,
              t.key,
            ];
          case TrackSort.album:
            return [
              LibraryText.fold(t.album),
              t.discNo == 0 ? 1 : t.discNo,
              t.trackNo == 0 ? 1 << 30 : t.trackNo,
              title,
              t.key,
            ];
          case TrackSort.duration:
            return [t.durationMs, title, t.key];
          case TrackSort.recentlyAdded:
            return [t.modifiedSecs, title, t.key];
        }
      },
      isBlank: (t) => switch (by) {
        TrackSort.title => false,
        TrackSort.artist => t.artists.isEmpty,
        TrackSort.album => t.album.isEmpty,
        TrackSort.duration => t.durationMs == 0,
        TrackSort.recentlyAdded => t.modifiedSecs == 0,
      },
    );
  }

  /// Sorts by a list-shaped key (compared element by element; strings with
  /// [LibraryText.naturalCompare], numbers numerically), with blanks last.
  static List<T> _sort<T>(
    List<T> items, {
    required bool descending,
    required List<Object> Function(T) key,
    required bool Function(T) isBlank,
  }) {
    final keyed = <(List<Object>, T)>[];
    final blanks = <(List<Object>, T)>[];
    for (final item in items) {
      (isBlank(item) ? blanks : keyed).add((key(item), item));
    }
    int cmp((List<Object>, T) a, (List<Object>, T) b) =>
        _compareKeys(a.$1, b.$1);
    keyed.sort(descending ? (a, b) => cmp(b, a) : cmp);
    // Blanks keep a stable, direction-independent order of their own.
    blanks.sort(cmp);
    return [for (final e in keyed) e.$2, for (final e in blanks) e.$2];
  }

  static int _compareKeys(List<Object> a, List<Object> b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final x = a[i];
      final y = b[i];
      final int c;
      if (x is int && y is int) {
        c = x.compareTo(y);
      } else {
        c = LibraryText.naturalCompare(x as String, y as String);
      }
      if (c != 0) return c;
    }
    return a.length - b.length;
  }
}

class _AlbumBuild {
  final List<AlbumGroup> groups;
  final Map<String, String> keyByTrack;
  final Map<String, AlbumGroup> byKey;

  _AlbumBuild(this.groups, this.keyByTrack, this.byKey);
}

/// An immutable snapshot of a container's tracks, grouped for browsing.
///
/// Groups are built lazily on first access, so a screen that only shows the
/// Tracks tab never pays for the others. A change produces a new index
/// ([withChanges]); nothing is mutated in place.
class LibraryIndex {
  /// All tracks, ordered by title.
  final List<LibraryTrack> tracks;
  final TagSplitConfig splitConfig;

  late final Map<String, LibraryTrack> _byKey = {
    for (final t in tracks) t.key: t,
  };

  late final List<String> _trackSearchText = [
    for (final t in tracks)
      LibraryText.fold(
        '${t.title} ${t.artists.join(' ')} ${t.album} ${t.genres.join(' ')}',
      ),
  ];

  LibraryIndex._(this.tracks, this.splitConfig);

  factory LibraryIndex(
    Iterable<LibraryTrack> tracks, {
    TagSplitConfig splitConfig = const TagSplitConfig(),
  }) {
    final keyed = [
      for (final t in tracks) (LibraryText.fold(t.title), t),
    ]..sort((a, b) {
        final c = LibraryText.naturalCompare(a.$1, b.$1);
        return c != 0 ? c : a.$2.key.compareTo(b.$2.key);
      });
    return LibraryIndex._(
      List.unmodifiable([for (final k in keyed) k.$2]),
      splitConfig,
    );
  }

  factory LibraryIndex.empty() => LibraryIndex(const []);

  bool get isEmpty => tracks.isEmpty;
  int get trackCount => tracks.length;
  int get totalDurationMs => tracks.fold(0, (sum, t) => sum + t.durationMs);

  /// The track with [key] (see [LibraryTrack.key]). For an index whose tracks
  /// have no source, the key is simply the path.
  LibraryTrack? trackForKey(String key) => _byKey[key];

  LibraryTrack? trackForPath(String path) => _byKey[path];

  /// A new index with [upserts] added or replacing same-key tracks and
  /// [removedKeys] ([LibraryTrack.key]s) dropped.
  LibraryIndex withChanges({
    Iterable<LibraryTrack> upserts = const [],
    Iterable<String> removedKeys = const [],
  }) {
    final map = Map<String, LibraryTrack>.from(_byKey);
    for (final k in removedKeys) {
      map.remove(k);
    }
    for (final t in upserts) {
      map[t.key] = t;
    }
    return LibraryIndex(map.values, splitConfig: splitConfig);
  }

  // ── Albums ─────────────────────────────────────────────────────────────────

  late final _AlbumBuild _albumBuild = _buildAlbums();

  List<AlbumGroup> get albums => _albumBuild.groups;

  _AlbumBuild _buildAlbums() {
    final keyByTrack = <String, String>{};
    // Pass 1: tracks with an album artist group on (album, album artist);
    // tracks with an album tag only share a provisional bucket per album;
    // tracks with no album tag group by folder.
    final tagged = <String, List<LibraryTrack>>{};
    final albumOnly = <String, List<LibraryTrack>>{};
    final byFolder = <String, List<LibraryTrack>>{};
    for (final t in tracks) {
      if (t.album.trim().isEmpty) {
        byFolder.putIfAbsent('#${_folderId(t)}', () => []).add(t);
      } else if (t.albumArtists.isNotEmpty) {
        final aa = LibraryText.fold(t.albumArtists.first);
        tagged
            .putIfAbsent('a:${LibraryText.fold(t.album)}|$aa', () => [])
            .add(t);
      } else {
        albumOnly.putIfAbsent(LibraryText.fold(t.album), () => []).add(t);
      }
    }

    // Pass 2: an album-only bucket stays one album unless it spans several
    // folders *and* several artists, which means unrelated albums that share
    // a name ("Greatest Hits"); those split per folder.
    final buckets = <String, List<LibraryTrack>>{...tagged};
    albumOnly.forEach((albumKey, list) {
      final folders = <String>{for (final t in list) _folderId(t)};
      final artists = <String>{
        for (final t in list)
          if (t.artists.isNotEmpty) LibraryText.fold(splitConfig.splitArtists(t.artists).first),
      };
      if (folders.length > 1 && artists.length > 1) {
        for (final t in list) {
          buckets.putIfAbsent('f:$albumKey|${_folderId(t)}', () => []).add(t);
        }
      } else {
        buckets['n:$albumKey'] = list;
      }
    });
    byFolder.forEach((k, v) => buckets['u:$k'] = v);

    final groups = <AlbumGroup>[];
    buckets.forEach((key, list) {
      list.sort(compareAlbumOrder);
      for (final t in list) {
        keyByTrack[t.key] = key;
      }
      groups.add(_albumGroup(key, list, untagged: key.startsWith('u:')));
    });
    groups.sort((a, b) {
      // Folder-derived albums with no name sink to the end.
      if (a.title.isEmpty != b.title.isEmpty) return a.title.isEmpty ? 1 : -1;
      final c = LibraryText.compare(a.title, b.title);
      if (c != 0) return c;
      final d = LibraryText.compare(a.artist, b.artist);
      return d != 0 ? d : a.key.compareTo(b.key);
    });
    return _AlbumBuild(
      List.unmodifiable(groups),
      keyByTrack,
      {for (final g in groups) g.key: g},
    );
  }

  /// A folder, qualified by the container it is in, so two containers' folders
  /// with the same name are not mistaken for one.
  static String _folderId(LibraryTrack t) => '${t.source}\u0000${t.folder}';

  AlbumGroup _albumGroup(String key, List<LibraryTrack> list, {required bool untagged}) {
    final first = list.first;
    final String title;
    if (untagged) {
      final f = first.folder;
      title = f.isEmpty ? '' : f.substring(f.lastIndexOf('/') + 1);
    } else {
      title = first.album.trim();
    }

    var artist = '';
    var various = false;
    final aa = <String>[];
    for (final t in list) {
      if (t.albumArtists.isNotEmpty) aa.add(t.albumArtists.first);
    }
    if (aa.isNotEmpty) {
      artist = aa.first;
    } else {
      final primary = <String, String>{};
      for (final t in list) {
        final names = splitConfig.splitArtists(t.artists);
        if (names.isNotEmpty) primary.putIfAbsent(LibraryText.fold(names.first), () => names.first);
      }
      if (primary.length == 1) {
        artist = primary.values.first;
      } else if (primary.length > 1) {
        various = true;
      }
    }

    var year = 0;
    for (final t in list) {
      if (t.year != 0 && (year == 0 || t.year < year)) year = t.year;
    }
    return AlbumGroup(
      key: key,
      title: title,
      tagged: !untagged,
      artist: artist,
      variousArtists: various,
      year: year,
      tracks: List.unmodifiable(list),
    );
  }

  /// The album a track was grouped into, or null when the path is unknown.
  AlbumGroup? albumOf(LibraryTrack track) {
    final key = _albumBuild.keyByTrack[track.key];
    return key == null ? null : _albumBuild.byKey[key];
  }

  /// Albums that contain at least one track by [artist], newest first.
  List<AlbumGroup> albumsOfArtist(ArtistGroup artist) {
    final keys = <String>{};
    for (final t in artist.tracks) {
      final k = _albumBuild.keyByTrack[t.key];
      if (k != null) keys.add(k);
    }
    final out = [
      for (final k in keys)
        if (_albumBuild.byKey[k] != null) _albumBuild.byKey[k]!,
    ];
    out.sort((a, b) {
      if (a.year != b.year) {
        if (a.year == 0) return 1;
        if (b.year == 0) return -1;
        return b.year - a.year;
      }
      return LibraryText.compare(a.title, b.title);
    });
    return out;
  }

  // ── Artists and genres ─────────────────────────────────────────────────────

  late final List<ArtistGroup> artists = _buildArtists();

  List<ArtistGroup> _buildArtists() {
    final names = <String, String>{};
    final lists = <String, List<LibraryTrack>>{};
    for (final t in tracks) {
      var list = splitConfig.splitArtists(t.artists);
      if (list.isEmpty) list = splitConfig.splitArtists(t.albumArtists);
      if (list.isEmpty) {
        lists.putIfAbsent('', () => []).add(t);
        continue;
      }
      for (final n in list) {
        final k = LibraryText.fold(n);
        names.putIfAbsent(k, () => n);
        lists.putIfAbsent(k, () => []).add(t);
      }
    }
    final groups = <ArtistGroup>[];
    lists.forEach((k, v) {
      v.sort(_byAlbumThenOrder);
      groups.add(ArtistGroup(key: k, name: names[k] ?? '', tracks: List.unmodifiable(v)));
    });
    groups.sort(_namedGroupOrder<ArtistGroup>((g) => g.key, (g) => g.name));
    return List.unmodifiable(groups);
  }

  static int _byAlbumThenOrder(LibraryTrack a, LibraryTrack b) {
    final c = LibraryText.compare(a.album, b.album);
    return c != 0 ? c : compareAlbumOrder(a, b);
  }

  late final List<GenreGroup> genres = _buildGenres();

  List<GenreGroup> _buildGenres() {
    final names = <String, String>{};
    final lists = <String, List<LibraryTrack>>{};
    for (final t in tracks) {
      final list = splitConfig.splitGenres(t.genres);
      if (list.isEmpty) {
        lists.putIfAbsent('', () => []).add(t);
        continue;
      }
      for (final n in list) {
        final k = LibraryText.fold(n);
        names.putIfAbsent(k, () => n);
        lists.putIfAbsent(k, () => []).add(t);
      }
    }
    final groups = <GenreGroup>[];
    lists.forEach((k, v) {
      groups.add(GenreGroup(key: k, name: names[k] ?? '', tracks: List.unmodifiable(v)));
    });
    groups.sort(_namedGroupOrder<GenreGroup>((g) => g.key, (g) => g.name));
    return List.unmodifiable(groups);
  }

  /// Named groups alphabetically, the unnamed "unknown" group last.
  static int Function(T, T) _namedGroupOrder<T>(
    String Function(T) key,
    String Function(T) name,
  ) {
    return (a, b) {
      final ua = key(a).isEmpty;
      final ub = key(b).isEmpty;
      if (ua != ub) return ua ? 1 : -1;
      return LibraryText.compare(name(a), name(b));
    };
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  static List<String> _tokens(String query) {
    final f = LibraryText.fold(query);
    return f.isEmpty ? const [] : f.split(' ');
  }

  static bool _matchesAll(String haystack, List<String> tokens) {
    for (final t in tokens) {
      if (!haystack.contains(t)) return false;
    }
    return true;
  }

  /// Every whitespace-separated word of [query] must appear in the track's
  /// title, artists, album or genres.
  List<LibraryTrack> searchTracks(String query) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return tracks;
    final hay = _trackSearchText;
    return [
      for (var i = 0; i < tracks.length; i++)
        if (_matchesAll(hay[i], tokens)) tracks[i],
    ];
  }

  List<AlbumGroup> searchAlbums(String query) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return albums;
    return [for (final a in albums) if (_matchesAll(a.searchText, tokens)) a];
  }

  List<ArtistGroup> searchArtists(String query) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return artists;
    return [for (final a in artists) if (_matchesAll(a.searchText, tokens)) a];
  }

  List<GenreGroup> searchGenres(String query) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return genres;
    return [for (final g in genres) if (_matchesAll(g.searchText, tokens)) g];
  }
}
