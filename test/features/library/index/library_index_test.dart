import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/library/index/library_index.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';

LibraryTrack t(
  String path, {
  String? title,
  List<String> artists = const [],
  String album = '',
  List<String> albumArtists = const [],
  List<String> genres = const [],
  int year = 0,
  int trackNo = 0,
  int discNo = 0,
  int durationMs = 1000,
  bool hasCover = false,
}) =>
    LibraryTrack(
      path: path,
      size: 100,
      modifiedSecs: 1,
      title: title ?? LibraryTrack.titleFromFileName(path.split('/').last),
      artists: artists,
      album: album,
      albumArtists: albumArtists,
      genres: genres,
      year: year,
      trackNo: trackNo,
      discNo: discNo,
      durationMs: durationMs,
      hasCover: hasCover,
    );

void main() {
  group('LibraryText', () {
    test('fold lowercases, strips accents and collapses whitespace', () {
      expect(LibraryText.fold('  Björk   Guðmundsdóttir '), 'bjork gudmundsdottir');
      expect(LibraryText.fold('Sigur Rós'), 'sigur ros');
      expect(LibraryText.fold('Straße'), 'strasse');
      expect(LibraryText.fold('日本語'), '日本語');
    });

    test('compare orders digit runs numerically', () {
      final list = ['Track 10', 'track 2', 'Track 1'];
      list.sort(LibraryText.compare);
      expect(list, ['Track 1', 'track 2', 'Track 10']);
    });
  });

  group('titleFromFileName', () {
    test('strips extension and leading track numbers', () {
      expect(LibraryTrack.titleFromFileName('03 - Some Song.mp3'), 'Some Song');
      expect(LibraryTrack.titleFromFileName('03. Some Song.flac'), 'Some Song');
      expect(LibraryTrack.titleFromFileName('Some Song.m4a'), 'Some Song');
      expect(LibraryTrack.titleFromFileName('1999.mp3'), '1999');
      expect(LibraryTrack.titleFromFileName('.mp3'), '.mp3');
    });
  });

  group('albums', () {
    test('tracks of one album are ordered by disc then track number', () {
      final idx = LibraryIndex([
        t('a/b.mp3', title: 'B', album: 'LP', albumArtists: ['X'], trackNo: 2, discNo: 1),
        t('a/c.mp3', title: 'C', album: 'LP', albumArtists: ['X'], trackNo: 1, discNo: 2),
        t('a/a.mp3', title: 'A', album: 'LP', albumArtists: ['X'], trackNo: 1, discNo: 1),
      ]);
      expect(idx.albums.length, 1);
      expect(idx.albums.first.tracks.map((e) => e.title), ['A', 'B', 'C']);
      expect(idx.albums.first.artist, 'X');
    });

    test('same-named albums by different artists in different folders stay apart', () {
      final idx = LibraryIndex([
        t('queen/gh1.mp3', album: 'Greatest Hits', artists: ['Queen']),
        t('queen/gh2.mp3', album: 'Greatest Hits', artists: ['Queen']),
        t('abba/gh1.mp3', album: 'Greatest Hits', artists: ['ABBA']),
      ]);
      expect(idx.albums.length, 2);
      final byArtist = {for (final a in idx.albums) a.artist: a.tracks.length};
      expect(byArtist, {'Queen': 2, 'ABBA': 1});
    });

    test('a multi-disc album by one artist split across folders stays whole', () {
      final idx = LibraryIndex([
        t('Album/CD1/01.mp3', album: 'Epic', artists: ['Band'], discNo: 1, trackNo: 1),
        t('Album/CD2/01.mp3', album: 'Epic', artists: ['Band'], discNo: 2, trackNo: 1),
      ]);
      expect(idx.albums.length, 1);
      expect(idx.albums.first.tracks.length, 2);
    });

    test('a compilation in one folder with many artists is one Various Artists album', () {
      final idx = LibraryIndex([
        t('mix/1.mp3', album: 'Mix', artists: ['A']),
        t('mix/2.mp3', album: 'Mix', artists: ['B']),
        t('mix/3.mp3', album: 'Mix', artists: ['C']),
      ]);
      expect(idx.albums.length, 1);
      expect(idx.albums.first.variousArtists, isTrue);
      expect(idx.albums.first.artist, '');
    });

    test('files with no album tag group by folder and take its name', () {
      final idx = LibraryIndex([
        t('Podcasts/Show/ep1.mp3'),
        t('Podcasts/Show/ep2.mp3'),
        t('Other/x.mp3'),
        t('root.mp3'),
      ]);
      final titles = idx.albums.map((a) => a.title).toList();
      expect(titles, ['Other', 'Show', '']);
      expect(idx.albums.every((a) => !a.tagged), isTrue);
      expect(idx.albums.last.tracks.single.path, 'root.mp3');
    });

    test('album year is the earliest year among its tracks; titles sort folded', () {
      final idx = LibraryIndex([
        t('1/a.mp3', album: 'Ärger', albumArtists: ['Z'], year: 2005),
        t('1/b.mp3', album: 'Ärger', albumArtists: ['Z'], year: 2003),
        t('2/a.mp3', album: 'Beta', albumArtists: ['Z']),
        t('3/a.mp3', album: 'Alpha', albumArtists: ['Z']),
      ]);
      expect(idx.albums.map((a) => a.title), ['Alpha', 'Ärger', 'Beta']);
      expect(idx.albums[1].year, 2003);
    });

    test('albumOf and the cover track', () {
      final idx = LibraryIndex([
        t('a/1.mp3', album: 'LP', albumArtists: ['X'], trackNo: 1),
        t('a/2.mp3', album: 'LP', albumArtists: ['X'], trackNo: 2, hasCover: true),
      ]);
      final track = idx.trackForPath('a/1.mp3')!;
      final album = idx.albumOf(track)!;
      expect(album.title, 'LP');
      expect(album.coverTrack!.path, 'a/2.mp3');
      expect(idx.albumOf(t('nope.mp3')), isNull);
    });
  });

  group('artists and genres', () {
    test('multi-artist values split on safe separators only', () {
      final idx = LibraryIndex([
        t('1.mp3', artists: ['A feat. B']),
        t('2.mp3', artists: ['C; D']),
        t('3.mp3', artists: ['AC/DC']),
        t('4.mp3', artists: ['Simon & Garfunkel']),
        t('5.mp3', artists: ['E / F']),
      ]);
      final names = idx.artists.map((a) => a.name).toSet();
      expect(names, {'A', 'B', 'C', 'D', 'AC/DC', 'Simon & Garfunkel', 'E', 'F'});
    });

    test('artists differing only by case or accent merge; first spelling wins', () {
      final idx = LibraryIndex([
        t('1.mp3', artists: ['Björk']),
        t('2.mp3', artists: ['BJORK']),
      ]);
      expect(idx.artists.length, 1);
      expect(idx.artists.first.tracks.length, 2);
    });

    test('tracks with no artist land in a trailing unknown group', () {
      final idx = LibraryIndex([
        t('1.mp3', artists: ['Zed']),
        t('2.mp3'),
      ]);
      expect(idx.artists.map((a) => a.name), ['Zed', '']);
      expect(idx.artists.last.isUnknown, isTrue);
      expect(idx.artists.last.tracks.single.path, '2.mp3');
    });

    test('album artist stands in when a track has no artist', () {
      final idx = LibraryIndex([t('1.mp3', albumArtists: ['Solo'])]);
      expect(idx.artists.single.name, 'Solo');
    });

    test('genres split, merge case-insensitively, and unknown sorts last', () {
      final idx = LibraryIndex([
        t('1.mp3', genres: ['Rock; Pop']),
        t('2.mp3', genres: ['rock']),
        t('3.mp3'),
      ]);
      expect(idx.genres.map((g) => g.name), ['Pop', 'Rock', '']);
      expect(idx.genres[1].tracks.length, 2);
    });

    test('albumsOfArtist lists each album once, newest first, undated last', () {
      final idx = LibraryIndex([
        t('a/1.mp3', album: 'Old', albumArtists: ['P'], artists: ['P'], year: 1990),
        t('a/2.mp3', album: 'Old', albumArtists: ['P'], artists: ['P'], year: 1990),
        t('b/1.mp3', album: 'New', albumArtists: ['P'], artists: ['P'], year: 2020),
        t('c/1.mp3', album: 'Undated', albumArtists: ['P'], artists: ['P']),
        t('d/1.mp3', album: 'Other', albumArtists: ['Q'], artists: ['Q']),
      ]);
      final p = idx.artists.firstWhere((a) => a.name == 'P');
      expect(idx.albumsOfArtist(p).map((a) => a.title), ['New', 'Old', 'Undated']);
    });
  });

  group('search', () {
    final idx = LibraryIndex([
      t('1.mp3', title: 'Hyperballad', artists: ['Björk'], album: 'Post', genres: ['Electronic']),
      t('2.mp3', title: 'Army of Me', artists: ['Björk'], album: 'Post'),
      t('3.mp3', title: 'Kid A', artists: ['Radiohead'], album: 'Kid A', genres: ['Rock']),
    ]);

    test('every word must match, accents ignored', () {
      expect(idx.searchTracks('bjork post').map((e) => e.title).toSet(), {'Hyperballad', 'Army of Me'});
      expect(idx.searchTracks('bjork hyper').map((e) => e.title), ['Hyperballad']);
      expect(idx.searchTracks('bjork radiohead'), isEmpty);
    });

    test('blank query returns everything', () {
      expect(idx.searchTracks('   ').length, 3);
      expect(idx.searchAlbums('').length, idx.albums.length);
    });

    test('album, artist and genre search', () {
      expect(idx.searchAlbums('post').single.title, 'Post');
      expect(idx.searchArtists('RADIO').single.name, 'Radiohead');
      expect(idx.searchGenres('elec').single.name, 'Electronic');
    });
  });

  group('changes', () {
    test('withChanges upserts, replaces and removes without touching the original', () {
      final base = LibraryIndex([
        t('a.mp3', title: 'A'),
        t('b.mp3', title: 'B'),
      ]);
      final next = base.withChanges(
        upserts: [t('b.mp3', title: 'B2'), t('c.mp3', title: 'C')],
        removedKeys: ['a.mp3'],
      );
      expect(next.tracks.map((e) => e.title), ['B2', 'C']);
      expect(base.tracks.map((e) => e.title), ['A', 'B']);
      expect(next.trackForPath('a.mp3'), isNull);
    });

    test('tracks are ordered by folded title then path', () {
      final idx = LibraryIndex([
        t('z.mp3', title: 'beta'),
        t('y.mp3', title: 'Alpha'),
        t('x.mp3', title: 'Ålpha'),
      ]);
      expect(idx.tracks.map((e) => e.path), ['x.mp3', 'y.mp3', 'z.mp3']);
    });
  });

  group('large index', () {
    test('builds 30k tracks across every grouping quickly', () {
      final tracks = [
        for (var i = 0; i < 30000; i++)
          t(
            'artist${i % 300}/album${i % 3000}/track$i.mp3',
            title: 'Song $i',
            artists: ['Artist ${i % 300}'],
            album: 'Album ${i % 3000}',
            genres: ['Genre ${i % 20}'],
            trackNo: i % 12,
          ),
      ];
      final sw = Stopwatch()..start();
      final idx = LibraryIndex(tracks);
      expect(idx.albums.length, 3000);
      expect(idx.artists.length, 300);
      expect(idx.genres.length, 20);
      expect(idx.searchTracks('artist 7 album 7').isNotEmpty, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('sorting', () {
    LibraryTrack m(
      String path, {
      String album = '',
      String artist = '',
      int year = 0,
      int mtime = 1,
      int dur = 1000,
      String? title,
      int trackNo = 0,
    }) =>
        LibraryTrack(
          path: path,
          size: 1,
          modifiedSecs: mtime,
          title: title ?? path,
          artists: artist.isEmpty ? const [] : [artist],
          album: album,
          albumArtists: artist.isEmpty ? const [] : [artist],
          year: year,
          trackNo: trackNo,
          durationMs: dur,
        );

    final idx = LibraryIndex([
      m('a/1.mp3', album: 'Alpha', artist: 'Zed', year: 2001, mtime: 300),
      m('b/1.mp3', album: 'Beta', artist: 'Amy', year: 1999, mtime: 100),
      m('c/1.mp3', album: 'Gamma', artist: 'Bob', mtime: 200),
      m('d/1.mp3', album: 'Delta', artist: 'Cat', year: 2010),
    ]);
    List<String> titles(List<AlbumGroup> l) => l.map((a) => a.title).toList();

    test('albums by title, artist, year and recency', () {
      expect(titles(LibrarySorting.albums(idx.albums, AlbumSort.title)),
          ['Alpha', 'Beta', 'Delta', 'Gamma']);
      expect(titles(LibrarySorting.albums(idx.albums, AlbumSort.artist)),
          ['Beta', 'Gamma', 'Delta', 'Alpha']);
      expect(titles(LibrarySorting.albums(idx.albums, AlbumSort.year)),
          ['Beta', 'Alpha', 'Delta', 'Gamma']);
      expect(titles(LibrarySorting.albums(idx.albums, AlbumSort.recentlyAdded, descending: true)),
          ['Alpha', 'Gamma', 'Beta', 'Delta']);
    });

    test('descending reverses real values but blanks stay last', () {
      // Gamma has no year: last both ways.
      expect(titles(LibrarySorting.albums(idx.albums, AlbumSort.year, descending: true)),
          ['Delta', 'Alpha', 'Beta', 'Gamma']);
      expect(titles(LibrarySorting.albums(idx.albums, AlbumSort.title, descending: true)),
          ['Gamma', 'Delta', 'Beta', 'Alpha']);
    });

    test('albums with various artists sort after named artists', () {
      final v = LibraryIndex([
        t('x/1.mp3', album: 'Mix', artists: ['A']),
        t('x/2.mp3', album: 'Mix', artists: ['B']),
        t('y/1.mp3', album: 'Solo', albumArtists: ['Q'], artists: ['Q']),
      ]);
      expect(titles(LibrarySorting.albums(v.albums, AlbumSort.artist)), ['Solo', 'Mix']);
    });

    test('artists by name and by track count; unknown artist last', () {
      final a = LibraryIndex([
        t('1.mp3', artists: ['Beta']),
        t('2.mp3', artists: ['Beta']),
        t('3.mp3', artists: ['Alpha']),
        t('4.mp3'),
        t('5.mp3'),
        t('6.mp3'),
      ]);
      List<String> names(List<ArtistGroup> l) => l.map((g) => g.name).toList();
      expect(names(LibrarySorting.artists(a.artists, ArtistSort.name)), ['Alpha', 'Beta', '']);
      expect(names(LibrarySorting.artists(a.artists, ArtistSort.name, descending: true)),
          ['Beta', 'Alpha', '']);
      expect(names(LibrarySorting.artists(a.artists, ArtistSort.trackCount, descending: true)),
          ['Beta', 'Alpha', '']);
    });

    test('tracks by artist keep album order within an artist; blanks last', () {
      final tr = LibraryIndex([
        m('1.mp3', title: 'T1', artist: 'Zed', album: 'B', trackNo: 2),
        m('2.mp3', title: 'T2', artist: 'Zed', album: 'B', trackNo: 1),
        m('3.mp3', title: 'T3', artist: 'Amy', album: 'A', trackNo: 1),
        m('4.mp3', title: 'T4'),
      ]);
      List<String> ts(List<LibraryTrack> l) => l.map((e) => e.title).toList();
      expect(ts(LibrarySorting.tracks(tr.tracks, TrackSort.artist)), ['T3', 'T2', 'T1', 'T4']);
      expect(ts(LibrarySorting.tracks(tr.tracks, TrackSort.artist, descending: true)),
          ['T1', 'T2', 'T3', 'T4']);
    });

    test('tracks by duration and recency; zero values sink', () {
      final tr = LibraryIndex([
        m('1.mp3', title: 'Short', dur: 100, mtime: 5),
        m('2.mp3', title: 'Long', dur: 900, mtime: 9),
        m('3.mp3', title: 'None', dur: 0, mtime: 0),
      ]);
      List<String> ts(List<LibraryTrack> l) => l.map((e) => e.title).toList();
      expect(ts(LibrarySorting.tracks(tr.tracks, TrackSort.duration, descending: true)),
          ['Long', 'Short', 'None']);
      expect(ts(LibrarySorting.tracks(tr.tracks, TrackSort.recentlyAdded, descending: true)),
          ['Long', 'Short', 'None']);
    });

    test('equal keys fall back to a unique tie-break, so results are deterministic', () {
      final same = [
        for (var i = 0; i < 50; i++) m('f$i.mp3', title: 'Same', dur: 500),
      ];
      final a = LibrarySorting.tracks(same, TrackSort.duration);
      final b = LibrarySorting.tracks(same.reversed.toList(), TrackSort.duration);
      expect(a.map((e) => e.path).toList(), b.map((e) => e.path).toList());
    });

    test('sorting returns a new list and leaves the index untouched', () {
      final before = idx.albums.map((a) => a.title).toList();
      LibrarySorting.albums(idx.albums, AlbumSort.year, descending: true);
      expect(idx.albums.map((a) => a.title).toList(), before);
    });

    test('30k tracks sort by artist quickly', () {
      final tracks = [
        for (var i = 0; i < 30000; i++)
          m('t$i.mp3', title: 'Song ${i % 977}', artist: 'Artist ${i % 411}', album: 'Album ${i % 1999}', trackNo: i % 14),
      ];
      final sw = Stopwatch()..start();
      final out = LibrarySorting.tracks(tracks, TrackSort.artist);
      expect(out.length, 30000);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });
  });

  group('merging containers', () {
    LibraryTrack src(String source, String path, {String album = '', List<String> artists = const [], List<String> albumArtists = const [], String? title, int trackNo = 0, int year = 0}) =>
        LibraryTrack(
          path: path,
          size: 1,
          modifiedSecs: 1,
          source: source,
          title: title ?? path,
          album: album,
          artists: artists,
          albumArtists: albumArtists,
          trackNo: trackNo,
          year: year,
        );

    test('the same relative path in two containers is two tracks', () {
      final idx = LibraryIndex([
        src('vault', 'Music/a.mp3', title: 'A'),
        src('phone', 'Music/a.mp3', title: 'A'),
      ]);
      expect(idx.trackCount, 2);
      expect(idx.trackForKey('vault\u0000Music/a.mp3'), isNotNull);
      expect(idx.trackForKey('phone\u0000Music/a.mp3'), isNotNull);
      expect(idx.trackForKey('Music/a.mp3'), isNull);
    });

    test('a tagged album spread over two containers is one album', () {
      final idx = LibraryIndex([
        src('vault', 'x/1.mp3', album: 'LP', albumArtists: ['Band'], trackNo: 1),
        src('phone', 'y/2.mp3', album: 'LP', albumArtists: ['Band'], trackNo: 2),
      ]);
      expect(idx.albums.length, 1);
      expect(idx.albums.single.tracks.map((t) => t.source), ['vault', 'phone']);
    });

    test('an artist and a genre merge across containers too', () {
      final idx = LibraryIndex([
        const LibraryTrack(path: 'a.mp3', size: 1, modifiedSecs: 1, source: 'v', title: 'A', artists: ['Björk'], genres: ['Pop']),
        const LibraryTrack(path: 'b.mp3', size: 1, modifiedSecs: 1, source: 'p', title: 'B', artists: ['BJORK'], genres: ['pop']),
      ]);
      expect(idx.artists.single.tracks.length, 2);
      expect(idx.genres.single.tracks.length, 2);
    });

    test('untagged folders with the same name in different containers stay separate albums', () {
      final idx = LibraryIndex([
        src('vault', 'Music/Mix/1.mp3'),
        src('phone', 'Music/Mix/1.mp3'),
      ]);
      expect(idx.albums.length, 2);
    });

    test('albumOf and removal work per container', () {
      final idx = LibraryIndex([
        src('vault', 'a.mp3', album: 'LP', albumArtists: ['B']),
        src('phone', 'a.mp3', album: 'LP', albumArtists: ['B']),
      ]);
      final v = idx.trackForKey('vault\u0000a.mp3')!;
      expect(idx.albumOf(v)!.tracks.length, 2);
      final next = idx.withChanges(removedKeys: [v.key]);
      expect(next.trackCount, 1);
      expect(next.tracks.single.source, 'phone');
    });
  });
}
