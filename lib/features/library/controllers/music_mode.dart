import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';
import 'package:vaultexplorer/features/library/models/music_config.dart';

/// What the library shows while music mode is on. Files is the inactive-mode
/// state; it is not a selectable library tab, so with the mode on the entry
/// always rests on one of the library views.
enum MusicCategory { files, albums, artists, genres, tracks, folders }

/// Music mode for one container: whether it is on, which folders it covers,
/// and which view is showing.
///
/// The on/off switch and the folders are saved with the container (see
/// [LibraryIndexStore]); the visible category is for this session. Music mode
/// always opens on the library (Albums): enabling it does, and so does loading
/// a saved enabled mode, so a vault never opens on the file listing with just
/// the music toolbar underneath it.
class MusicModeEntry extends ChangeNotifier {
  final MountedContainer container;
  final LibraryIndexStore _store;

  MusicModeEntry(this.container, this._store);

  MusicConfig _config = MusicConfig.off;
  MusicCategory _category = MusicCategory.files;
  bool _loaded = false;
  bool? _hint;
  bool _disposed = false;
  Future<void>? _loading;

  MusicConfig get config => _config;
  MusicCategory get category => _category;

  /// Whether the saved config has been read yet.
  bool get loaded => _loaded;

  /// What this device remembers about whether music mode was on, before the
  /// saved setting has been read: null when nothing is known. Only a hint --
  /// see [applyHint]; ignored once [loaded].
  bool? get hint => _loaded ? null : _hint;

  /// Whether music mode is on, or is expected to be: the saved setting once
  /// read, the hint until then. Lets the chrome (the music toolbar) match
  /// from the first frame.
  bool get expectedEnabled => _loaded ? _config.enabled : _hint == true;

  /// True while the screen cannot yet tell which view to show: the saved
  /// setting has not been read and the hint does not say music mode is off.
  bool get pendingView => !_loaded && _hint != false;

  /// Gives the entry the on-device hint (kept in the toolbar config) so the
  /// first frame can match before the vault's own setting is read. The saved
  /// setting stays the source of truth and replaces the hint when it loads.
  void applyHint(bool enabled) {
    if (_loaded || _hint == enabled) return;
    _hint = enabled;
    if (enabled) _category = MusicCategory.albums;
    _notify();
  }

  /// True when a library view (not the file listing) is on screen.
  bool get libraryVisible => _config.enabled && _category != MusicCategory.files;

  /// Reads the saved config once. Safe to call repeatedly.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final saved = await _store.loadConfig(container);
    if (_disposed) return;
    _config = saved;
    _category = saved.enabled ? MusicCategory.albums : MusicCategory.files;
    _loaded = true;
    _notify();
  }

  /// Turns music mode on for [folders] (empty: the whole container) and opens
  /// the Albums view.
  Future<void> enable({List<String> folders = const []}) async {
    _config = MusicConfig(enabled: true, folders: MusicConfig.normalizeFolders(folders));
    _category = MusicCategory.albums;
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
