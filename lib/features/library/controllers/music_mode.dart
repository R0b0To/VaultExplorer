import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';
import 'package:vaultexplorer/features/library/models/music_config.dart';

/// What the library shows while music mode is on. Files is retained as the
/// inactive-mode state; it is not a selectable library tab.
enum MusicCategory { files, albums, artists, genres, tracks }

/// Music mode for one container: whether it is on, which folders it covers,
/// and which view is showing.
///
/// The on/off switch and the folders are saved with the container (see
/// [LibraryIndexStore]); the visible category is for this session and resumes
/// on Tracks whenever saved music mode is reopened.
class MusicModeEntry extends ChangeNotifier {
  final MountedContainer container;
  final LibraryIndexStore _store;

  MusicModeEntry(this.container, this._store);

  MusicConfig _config = MusicConfig.off;
  MusicCategory _category = MusicCategory.files;
  bool _loaded = false;
  bool _disposed = false;
  Future<void>? _loading;

  MusicConfig get config => _config;
  MusicCategory get category => _category;

  /// Whether the saved config has been read yet.
  bool get loaded => _loaded;

  /// True when a library view (not the file listing) is on screen.
  bool get libraryVisible => _config.enabled && _category != MusicCategory.files;

  /// Reads the saved config once. Safe to call repeatedly.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final saved = await _store.loadConfig(container);
    if (_disposed) return;
    _config = saved;
    _category = saved.enabled ? MusicCategory.tracks : MusicCategory.files;
    _loaded = true;
    _notify();
  }

  /// Turns music mode on for [folders] (empty: the whole container) and opens
  /// the Tracks view.
  Future<void> enable({List<String> folders = const []}) async {
    _config = MusicConfig(enabled: true, folders: MusicConfig.normalizeFolders(folders));
    _category = MusicCategory.tracks;
    _notify();
    await _store.saveConfig(container, _config);
  }

  /// Turns music mode off and returns to the file listing. The saved index
  /// stays, so turning it back on is instant.
  Future<void> disable() async {
    _config = _config.copyWith(enabled: false);
    _category = MusicCategory.files;
    _notify();
    await _store.saveConfig(container, _config);
  }

  Future<void> setFolders(List<String> folders) async {
    final next = _config.copyWith(folders: folders);
    if (next == _config) return;
    _config = next;
    _notify();
    await _store.saveConfig(container, _config);
  }

  void setCategory(MusicCategory category) {
    if (category == _category) return;
    _category = category;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// One [MusicModeEntry] per container, shared by everything that shows that
/// container (two panes, a tab and the toolbar button), and forgotten when the
/// last of them goes away, so a locked vault leaves nothing behind.
class MusicModeRegistry {
  final LibraryIndexStore _store;

  MusicModeRegistry(this._store);

  final Map<String, _Slot> _slots = {};

  /// The entry for [container], created (and its config load started) on first
  /// use. Does not keep it alive; hold it with [acquire].
  MusicModeEntry entryFor(MountedContainer container) {
    final slot = _slots.putIfAbsent(container.uri, () {
      final entry = MusicModeEntry(container, _store);
      unawaited(entry.load());
      return _Slot(entry);
    });
    return slot.entry;
  }

  /// Like [entryFor], and counts one more user. Pair with [release].
  MusicModeEntry acquire(MountedContainer container) {
    final entry = entryFor(container);
    _slots[container.uri]!.holders++;
    return entry;
  }

  void release(MountedContainer container) {
    final slot = _slots[container.uri];
    if (slot == null) return;
    slot.holders--;
    if (slot.holders <= 0) {
      _slots.remove(container.uri);
      slot.entry.dispose();
    }
  }

  /// Entry count, for tests.
  @visibleForTesting
  int get entryCount => _slots.length;
}

class _Slot {
  final MusicModeEntry entry;
  int holders = 0;

  _Slot(this.entry);
}
