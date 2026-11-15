import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/library/data/library_index_store.dart';
import 'package:vaultexplorer/features/library/models/music_config.dart';

/// What the library shows while music mode is on. Files is the inactive-mode
/// state; it is not a selectable library tab, so with the mode on the entry
/// always rests on one of the library views.
enum MusicCategory { files, albums, artists, genres, tracks, folders }

/// What every tab on one container shares about music mode: the folders it
/// covers, and the saved on/off switch.
///
/// The saved switch is only the *default for tabs opened afterwards* (the last
/// mode chosen on this container); it never changes a tab that is already
/// open. Whether a given tab is in music mode is that tab's own
/// [MusicModeEntry] state. Both the switch and the folders are saved with the
/// container (see [LibraryIndexStore]).
class MusicScope extends ChangeNotifier {
  final MountedContainer container;
  final LibraryIndexStore _store;

  MusicScope(this.container, this._store);

  MusicConfig _config = MusicConfig.off;
  bool _loaded = false;
  bool _disposed = false;
  Future<void>? _loading;

  /// The saved config: [MusicConfig.enabled] is the default for new tabs,
  /// [MusicConfig.folders] is what every tab's music library covers.
  MusicConfig get config => _config;

  /// Whether the saved config has been read yet.
  bool get loaded => _loaded;

  /// Reads the saved config once. Safe to call repeatedly.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final saved = await _store.loadConfig(container);
    if (_disposed) return;
    _config = saved;
    _loaded = true;
    _notify();
  }

  /// Replaces the saved config and persists it.
  Future<void> save(MusicConfig next) async {
    if (next != _config) {
      _config = next;
      _notify();
    }
    await _store.saveConfig(container, _config);
  }

  // A partial change starts from what is saved, so it waits for the load:
  // before it, [_config] is only the empty default and saving that would
  // erase the saved folders.
  Future<void> setFolders(List<String> folders) async {
    await load();
    if (_disposed) return;
    final next = _config.copyWith(folders: folders);
    if (next == _config) return;
    await save(next);
  }

  /// Changes only the default for tabs opened from now on.
  Future<void> setDefaultEnabled(bool enabled) async {
    await load();
    if (_disposed) return;
    if (_config.enabled == enabled) return;
    await save(_config.copyWith(enabled: enabled));
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

/// Music mode for one tab: whether it is on in this tab, and which view is
/// showing. Two tabs on the same container each have their own entry, so one
/// can be in music mode while the other stays on the file listing. The folders
/// they cover are shared through the container's [MusicScope].
///
/// A tab opens in the container's saved default mode, and music mode always
/// opens on the library (Albums): enabling it does, and so does adopting a
/// saved enabled default, so a tab never opens on the file listing with just
/// the music toolbar underneath it.
class MusicModeEntry extends ChangeNotifier {
  final MountedContainer container;
  final MusicScope _scope;
  final bool _ownsScope;

  /// [scope] is the container's shared scope. Without one the entry makes its
  /// own, which is only useful for a single standalone view (and for tests).
  MusicModeEntry(this.container, LibraryIndexStore store, {MusicScope? scope})
    : _scope = scope ?? MusicScope(container, store),
      _ownsScope = scope == null {
    _scope.addListener(_onScopeChanged);
    // A tab opened after the saved setting was read starts in the saved
    // default at once, with no pending state.
    if (_scope.loaded) _adoptDefault();
  }

  bool _enabled = false;
  MusicCategory _category = MusicCategory.files;

  /// True once this tab has been given a mode of its own (by the person, or by
  /// adopting the saved default). A later scope load never overrides it.
  bool _settled = false;
  bool? _hint;
  bool _disposed = false;

  /// Music mode as this tab has it, with the folders the container shares.
  MusicConfig get config => _scope.config.copyWith(enabled: _enabled);
  MusicCategory get category => _category;

  /// Whether the saved config has been read yet.
  bool get loaded => _scope.loaded;

  /// What new tabs on this container open in, as saved: not this tab's own
  /// state.
  bool get savedDefaultEnabled => _scope.config.enabled;

  /// What this device remembers about whether music mode was on, before the
  /// saved setting has been read: null when nothing is known. Only a hint --
  /// see [applyHint]; ignored once [loaded].
  bool? get hint => loaded ? null : _hint;

  /// Whether music mode is on, or is expected to be: this tab's own state once
  /// known, the hint until then. Lets the chrome (the music toolbar) match
  /// from the first frame.
  bool get expectedEnabled => (loaded || _settled) ? _enabled : _hint == true;

  /// True while the screen cannot yet tell which view to show: the saved
  /// setting has not been read and the hint does not say music mode is off.
  bool get pendingView => !loaded && !_settled && _hint != false;

  /// Gives the entry the on-device hint (kept in the toolbar config) so the
  /// first frame can match before the container's own setting is read. The
  /// saved setting stays the source of truth and replaces the hint when it
  /// loads.
  void applyHint(bool enabled) {
    if (loaded || _settled || _hint == enabled) return;
    _hint = enabled;
    if (enabled) _category = MusicCategory.albums;
    _notify();
  }

  /// True when a library view (not the file listing) is on screen.
  bool get libraryVisible => _enabled && _category != MusicCategory.files;

  /// Reads the saved config once. Safe to call repeatedly.
  Future<void> load() => _scope.load();

  void _onScopeChanged() {
    if (_disposed) return;
    if (_scope.loaded && !_settled) _adoptDefault();
    _notify();
  }

  void _adoptDefault() {
    _settled = true;
    _enabled = _scope.config.enabled;
    _category = _enabled ? MusicCategory.albums : MusicCategory.files;
  }

  /// Turns music mode on in this tab for [folders] (empty: the whole
  /// container) and opens the Albums view. The folders are shared by every tab
  /// on the container; the switch is this tab's alone.
  Future<void> enable({List<String> folders = const []}) async {
    _settled = true;
    _enabled = true;
    _category = MusicCategory.albums;
    _notify();
    await _scope.save(
      MusicConfig(enabled: true, folders: MusicConfig.normalizeFolders(folders)),
    );
  }

  /// Turns music mode off in this tab and returns it to the file listing. The
  /// saved index stays, so turning it back on is instant. Other tabs keep
  /// their own mode.
  Future<void> disable() async {
    _settled = true;
    _enabled = false;
    _category = MusicCategory.files;
    _notify();
    await _scope.setDefaultEnabled(false);
  }

  /// Changes which folders music mode covers, for every tab on the container.
  Future<void> setFolders(List<String> folders) => _scope.setFolders(folders);

  /// Changes only what tabs opened from now on start in; this tab and the
  /// other open tabs are untouched.
  Future<void> setDefaultForNewTabs(bool enabled) =>
      _scope.setDefaultEnabled(enabled);

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
    _scope.removeListener(_onScopeChanged);
    if (_ownsScope) _scope.dispose();
    super.dispose();
  }
}

/// One [MusicScope] per container (shared by every tab on it) and one
/// [MusicModeEntry] per tab. A tab's entry is forgotten when its tab goes away
/// and a container's scope when its last tab does, so a locked vault leaves
/// nothing behind.
class MusicModeRegistry {
  final LibraryIndexStore _store;

  MusicModeRegistry(this._store);

  final Map<String, _ScopeSlot> _scopes = {};
  final Map<TabId, _EntrySlot> _entries = {};

  /// The entry for the tab [tabId] showing [container], created (and its
  /// config load started) on first use. Does not keep it alive; hold it with
  /// [acquire].
  MusicModeEntry entryFor(MountedContainer container, TabId tabId) =>
      _slotFor(container, tabId).entry;

  /// Like [entryFor], and counts one more user. Pair with [release].
  MusicModeEntry acquire(MountedContainer container, TabId tabId) {
    final slot = _slotFor(container, tabId);
    slot.holders++;
    return slot.entry;
  }

  void release(MountedContainer container, TabId tabId) {
    final slot = _entries[tabId];
    if (slot == null) return;
    slot.holders--;
    if (slot.holders > 0) return;
    _entries.remove(tabId);
    slot.entry.dispose();
    final scopeSlot = _scopes[slot.containerUri];
    if (scopeSlot == null) return;
    scopeSlot.entries--;
    if (scopeSlot.entries <= 0) {
      _scopes.remove(slot.containerUri);
      scopeSlot.scope.dispose();
    }
  }

  _EntrySlot _slotFor(MountedContainer container, TabId tabId) {
    final existing = _entries[tabId];
    if (existing != null) return existing;
    final scopeSlot = _scopes.putIfAbsent(container.uri, () {
      final scope = MusicScope(container, _store);
      unawaited(scope.load());
      return _ScopeSlot(scope);
    });
    scopeSlot.entries++;
    final entry = MusicModeEntry(container, _store, scope: scopeSlot.scope);
    final slot = _EntrySlot(entry, container.uri);
    _entries[tabId] = slot;
    return slot;
  }

  /// Tab entry count, for tests.
  @visibleForTesting
  int get entryCount => _entries.length;

  /// Container scope count, for tests.
  @visibleForTesting
  int get scopeCount => _scopes.length;
}

class _ScopeSlot {
  final MusicScope scope;
  int entries = 0;

  _ScopeSlot(this.scope);
}

class _EntrySlot {
  final MusicModeEntry entry;
  final String containerUri;
  int holders = 0;

  _EntrySlot(this.entry, this.containerUri);
}
