import 'package:flutter/foundation.dart';
import '/../models/mounted_container.dart';
import '/../services/vaultexplorer_api.dart';
import '/../utils/raw_entry.dart';
import 'media_viewer_constants.dart';

class PlaylistController extends ChangeNotifier {
  final MountedContainer container;
  final String? startingFolder;

  List<String> _originalList;
  List<String> _currentPlaylist;
  int _currentIndex;

  bool _isShuffled = false;
  bool _allFilesScanned = false;
  bool _isScanningSubfolders = false;
  bool _isPlaylistMode;
  String _selectedFolder = 'Current Folder Only';

  // Bumped on every state-mutating call (enablePlaylist, disablePlaylist,
  // toggleShuffle, removeCurrent). enablePlaylist's directory scan is async
  // and can take a while on a large "All (incl. subfolders)" vault; if the
  // user disables playlist mode, re-scopes to a different folder, or
  // shuffles while that scan is still in flight, the scan's eventual result
  // must not overwrite the newer state. Each async scan snapshots the
  // generation it started with and checks it still matches before applying
  // its result.
  int _generation = 0;

  PlaylistController({
    required this.container,
    required List<String> initialMediaFiles,
    required int initialIndex,
    this.startingFolder,
  }) : _originalList = List.from(initialMediaFiles),
       _currentPlaylist = List.from(initialMediaFiles),
       _currentIndex = initialIndex,
       _isPlaylistMode = initialMediaFiles.length > 1 {
    if (_isPlaylistMode) _initializeFolderFilter();
  }

  List<String> get playlist => _currentPlaylist;
  int get currentIndex => _currentIndex;
  bool get isShuffled => _isShuffled;
  bool get isScanningSubfolders => _isScanningSubfolders;
  bool get isPlaylistMode => _isPlaylistMode;
  String get selectedFolder => _selectedFolder;
  bool get allFilesScanned => _allFilesScanned;
  bool get isEmpty => _currentPlaylist.isEmpty;
  String get currentFile => isEmpty ? '' : _currentPlaylist[_currentIndex];

  void updateIndex(int index) {
    if (index >= 0 && index < _currentPlaylist.length) {
      _currentIndex = index;
      notifyListeners();
    }
  }

  String getBaseDir() {
    if (startingFolder != null) return startingFolder!;
    if (_originalList.isEmpty) return '';
    final first = _originalList.first;
    if (!first.contains('/')) return '';
    return first.substring(0, first.lastIndexOf('/'));
  }

  void _initializeFolderFilter() {
    final baseDir = getBaseDir();
    final hasSubfolderItems = _originalList.any((file) {
      final dir = file.contains('/')
          ? file.substring(0, file.lastIndexOf('/'))
          : '';
      return dir != baseDir;
    });
    if (hasSubfolderItems) {
      _selectedFolder = 'All';
      _allFilesScanned = true;
    }
  }

  void toggleShuffle() {
    if (isEmpty || !_isPlaylistMode) return;
    final current = currentFile;
    if (!_isShuffled) {
      final shuffled = List<String>.from(_currentPlaylist)
        ..remove(current)
        ..shuffle();
      shuffled.insert(0, current);
      _currentPlaylist = shuffled;
      _currentIndex = 0;
      _isShuffled = true;
    } else {
      _isShuffled = false;
      _applyFolderFiltering(_selectedFolder, current);
    }
    notifyListeners();
  }

  /// Turns on (or re-scopes) playlist mode for the given folder scope
  /// ('Current Folder Only' or 'All'). If the viewer was opened as a single
  /// file, `_originalList` only contains that one file, so the first call
  /// for a given scope triggers a real directory scan to populate it.
  Future<void> enablePlaylist(String folder) async {
    final anchor = currentFile;
    final needsScan = !_isPlaylistMode || (folder == 'All' && !_allFilesScanned);
    final myGeneration = ++_generation;

    if (!needsScan) {
      _selectedFolder = folder;
      _isPlaylistMode = true;
      _applyFolderFiltering(folder, anchor);
      notifyListeners();
      return;
    }

    _isScanningSubfolders = true;
    notifyListeners();
    try {
      final baseDir = getBaseDir();
      final scanned = folder == 'All'
          ? await _scanDirectoryRecursively(baseDir)
          : await _scanDirectorySingleLevel(baseDir);

      // Another mutation (disablePlaylist, a second enablePlaylist for a
      // different scope, toggleShuffle, removeCurrent) ran while this scan
      // was in flight and has already moved state past what this scan
      // knows about. Applying our (now stale) result here would silently
      // undo whatever the user did in the meantime, so bail out instead.
      if (myGeneration != _generation) return;

      if (scanned.isNotEmpty) {
        _originalList = scanned;
        _allFilesScanned = folder == 'All';
      } else if (!_originalList.contains(anchor)) {
        _originalList = [anchor];
        _allFilesScanned = false;
      }

      // Only publish the new folder scope once the scan and filtering have
      // fully resolved. MediaViewerScreen keys its PageView off
      // selectedFolder (among other things) — flipping it earlier, before
      // _currentPlaylist/_currentIndex below are updated to match, causes a
      // premature rebuild with stale playlist/index data mid-scan, tearing
      // down whatever page/video controller was live for the file the user
      // was actually viewing.
      _selectedFolder = folder;
      _isPlaylistMode = true;
      _applyFolderFiltering(folder, anchor);
    } finally {
      // Only this generation's scan may clear the scanning indicator —
      // otherwise a stale scan resolving after a fresh one has already
      // started would flip "scanning…" off mid-way through the new scan.
      if (myGeneration == _generation) _isScanningSubfolders = false;
      notifyListeners();
    }
  }

  /// Leaves playlist mode and collapses back to viewing just the current file.
  void disablePlaylist() {
    if (!_isPlaylistMode) return;
    _generation++; // invalidate any in-flight enablePlaylist scan
    final anchor = currentFile;
    _isPlaylistMode = false;
    _isShuffled = false;
    _allFilesScanned = false;
    _isScanningSubfolders = false;
    _selectedFolder = 'Current Folder Only';
    _originalList = [anchor];
    _currentPlaylist = [anchor];
    _currentIndex = 0;
    notifyListeners();
  }

  void _applyFolderFiltering(String folder, String fileAnchor) {
    final baseDir = getBaseDir();
    List<String> filteredList;
    if (folder == 'All') {
      filteredList = List.from(_originalList);
    } else {
      filteredList = _originalList.where((file) {
        final dir = file.contains('/')
            ? file.substring(0, file.lastIndexOf('/'))
            : '';
        return dir == baseDir;
      }).toList();
    }

    int newIndex = filteredList.indexOf(fileAnchor);
    if (newIndex == -1) newIndex = 0;

    if (filteredList.isNotEmpty) {
      _currentPlaylist = filteredList;
      _currentIndex = newIndex;
    }
  }

  Future<List<String>> _scanDirectorySingleLevel(String baseDir) async {
    final foundFiles = <String>[];
    try {
      final items = await vaultExplorerApi.listDirectory(container, baseDir);
      if (items != null) {
        for (final item in items) {
          if (item.startsWith('System:')) continue;
          final entry = RawEntry.parse(item);
          if (!entry.isDir && MediaViewerConstants.isSupported(entry.name)) {
            final fullPath = baseDir.isEmpty
                ? entry.name
                : '$baseDir/${entry.name}';
            foundFiles.add(fullPath);
          }
        }
      }
    } catch (e) {
      debugPrint('Error scanning current folder: $e');
    }
    foundFiles.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return foundFiles;
  }

  Future<List<String>> _scanDirectoryRecursively(
    String baseDir, {
    int depth = 0,
  }) async {
    if (depth > MediaViewerConstants.maxDirectorySearchDepth) return [];

    final foundFiles = <String>[];
    final subdirNames = <String>[];

    try {
      final items = await vaultExplorerApi.listDirectory(container, baseDir);
      if (items != null) {
        for (final item in items) {
          if (item.startsWith('System:')) continue;
          final entry = RawEntry.parse(item);

          if (entry.isDir) {
            subdirNames.add(entry.name);
          } else {
            if (MediaViewerConstants.isSupported(entry.name)) {
              final fullPath = baseDir.isEmpty
                  ? entry.name
                  : '$baseDir/${entry.name}';
              foundFiles.add(fullPath);
            }
          }
        }

        // Walk subdirectories in bounded-size batches instead of firing off
        // every nested scan simultaneously — a large "All (incl.
        // subfolders)" vault can otherwise burst hundreds of concurrent
        // native channel calls at once.
        for (var i = 0;
            i < subdirNames.length;
            i += MediaViewerConstants.maxDirectoryScanConcurrency) {
          final end = (i + MediaViewerConstants.maxDirectoryScanConcurrency)
              .clamp(0, subdirNames.length);
          final batch = subdirNames.sublist(i, end);

          final nested = await Future.wait(
            batch.map((name) {
              final subPath = baseDir.isEmpty ? name : '$baseDir/$name';
              return _scanDirectoryRecursively(subPath, depth: depth + 1);
            }),
          );
          for (final list in nested) {
            foundFiles.addAll(list);
          }
        }
      }
    } catch (e) {
      debugPrint('Error walking subdirectories: $e');
    }

    return foundFiles;
  }

  void removeCurrent() {
    if (isEmpty) return;
    final file = currentFile;
    _currentPlaylist.removeAt(_currentIndex);
    _originalList.remove(file);
    if (_currentIndex >= _currentPlaylist.length &&
        _currentPlaylist.isNotEmpty) {
      _currentIndex = _currentPlaylist.length - 1;
    }
    notifyListeners();
  }
}