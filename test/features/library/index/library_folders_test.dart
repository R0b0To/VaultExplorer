import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/library/index/library_index.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';

LibraryTrack t(
  String path, {
  String source = '',
  int modifiedSecs = 1,
  bool hasCover = false,
}) =>
    LibraryTrack(
      path: path,
      size: 100,
      modifiedSecs: modifiedSecs,
      source: source,
      title: LibraryTrack.titleFromFileName(path.split('/').last),
      hasCover: hasCover,
    );

void main() {
  group('folders', () {
    test('lists only folders that directly hold audio', () {
      final index = LibraryIndex([
        t('Music/Rock/a.mp3'),
        t('Music/Rock/b.mp3'),
        t('Music/Jazz/c.mp3'),
      ]);
      final paths = [for (final f in index.folders) f.path];
      // "Music" only contains folders, so it is not listed.
      expect(paths, ['Music/Jazz', 'Music/Rock']);
      expect(index.folders.last.tracks.length, 2);
    });

    test('names, parents and the root', () {
      final index = LibraryIndex([t('Music/Rock/a.mp3'), t('loose.mp3')]);
      final rock = index.folders.firstWhere((f) => f.path == 'Music/Rock');
      expect(rock.name, 'Rock');
      expect(rock.parentPath, 'Music');
      expect(rock.isRoot, isFalse);
      final root = index.folders.firstWhere((f) => f.isRoot);
      expect(root.name, '');
      expect(root.tracks.single.path, 'loose.mp3');
      // The root sorts last by name.
      expect(index.folders.last.isRoot, isTrue);
    });

    test('the same folder name in two containers stays two folders', () {
      final index = LibraryIndex([
        t('Music/a.mp3', source: 'vault-1'),
        t('Music/b.mp3', source: 'vault-2'),
      ]);
      expect(index.folders.length, 2);
      expect({for (final f in index.folders) f.source}, {'vault-1', 'vault-2'});
    });

    test('search matches the whole path', () {
      final index = LibraryIndex([
        t('Music/Rock/a.mp3'),
        t('Podcasts/b.mp3'),
      ]);
      expect([for (final f in index.searchFolders('rock')) f.path], ['Music/Rock']);
      expect(index.searchFolders(''), index.folders);
    });

    test('sorting by track count and recency, either direction', () {
      final index = LibraryIndex([
        t('A/1.mp3', modifiedSecs: 5),
        t('B/1.mp3', modifiedSecs: 9),
        t('B/2.mp3', modifiedSecs: 2),
        t('C/1.mp3', modifiedSecs: 0),
      ]);
      List<String> names(List<FolderGroup> l) => [for (final f in l) f.name];
      expect(
        names(LibrarySorting.folders(index.folders, FolderSort.trackCount, descending: true)).first,
        'B',
      );
      // C has no date, so it is last in both directions.
      expect(
        names(LibrarySorting.folders(index.folders, FolderSort.recentlyAdded, descending: true)),
        ['B', 'A', 'C'],
      );
      expect(
        names(LibrarySorting.folders(index.folders, FolderSort.recentlyAdded)),
        ['A', 'B', 'C'],
      );
    });
  });
}
