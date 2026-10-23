import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_marks.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_pins_bookmarks_controller.dart';
import 'package:vaultexplorer/features/browser/services/vault_marks_store.dart';

// The one writer of bookmarks and pins: when it reads, in what order it saves,
// and what it refuses to do (save before it has read, rewrite what it could
// not read).

class Fx {
  Fx(this._container, this.notifier);
  final ProviderContainer _container;
  final FileBrowserPinsBookmarks notifier;
  VaultMarks get state =>
      _container.read(fileBrowserPinsBookmarksProvider(1));
  void dispose() => _container.dispose();
}

Fx _make(_FakeStore store) {
  final container = ProviderContainer(
    overrides: [vaultMarksStoreProvider.overrideWithValue(store)],
  );
  addTearDown(container.dispose);
  // autoDispose: keep it alive for the length of the test.
  container.listen(fileBrowserPinsBookmarksProvider(1), (_, _) {});
  return Fx(
    container,
    container.read(fileBrowserPinsBookmarksProvider(1).notifier),
  );
}

MountedContainer _vault({int volId = 1}) => MountedContainer(
  uri: 'file:///vault.hc',
  displayName: 'Vault',
  volId: volId,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000,
  freeSpace: 500,
);

const _a = VaultBookmark('Docs/a.txt', isDir: false);
const _b = VaultBookmark('Photos', isDir: true);

/// A store whose reads and writes the test can hold back, fail, and inspect.
class _FakeStore implements VaultMarksStore {
  VaultMarks stored;
  int loads = 0;
  final List<VaultMarks> saves = [];
  Completer<void>? loadGate;
  Object? loadError;
  final List<Completer<void>> saveGates = [];
  bool saveSucceeds = true;

  _FakeStore([VaultMarks? initial]) : stored = initial ?? VaultMarks.empty;

  @override
  Future<VaultMarks> load(MountedContainer container) async {
    loads++;
    await loadGate?.future;
    final error = loadError;
    if (error != null) throw error;
    return stored;
  }

  @override
  Future<bool> save(MountedContainer container, VaultMarks marks) async {
    if (saveGates.isNotEmpty) await saveGates.removeAt(0).future;
    saves.add(marks);
    if (saveSucceeds) stored = marks;
    return saveSucceeds;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void registerPinsBookmarksScenarios(Fx Function(_FakeStore store) make) {
  test('ensureLoaded reads once however many callers ask', () async {
    final store = _FakeStore(VaultMarks().withBookmarks([_a]));
    final fx = make(store);

    await Future.wait([
      fx.notifier.ensureLoaded(_vault()),
      fx.notifier.ensureLoaded(_vault()),
    ]);
    await fx.notifier.ensureLoaded(_vault());

    expect(store.loads, 1);
    expect(fx.notifier.isLoaded, isTrue);
    expect(fx.state.bookmarkPaths, ['Docs/a.txt']);
  });

  test('a change made before the first read finishes does not erase what '
      'was stored', () async {
    final store = _FakeStore(VaultMarks().withBookmarks([_a]))
      ..loadGate = Completer<void>();
    final fx = make(store);

    final pending = fx.notifier.toggleBookmarks(_vault(), [
      _b,
    ], bookmark: true);
    store.loadGate!.complete();
    await pending;

    expect(store.saves, hasLength(1));
    expect(store.saves.single.bookmarkPaths, ['Docs/a.txt', 'Photos']);
    expect(fx.state.bookmarkPaths, ['Docs/a.txt', 'Photos']);
  });

  test('if the stored marks cannot be read, nothing is saved over them', () async {
    final store = _FakeStore(VaultMarks().withBookmarks([_a]))
      ..loadError = StateError('storage unavailable');
    final fx = make(store);

    await fx.notifier.toggleBookmarks(_vault(), [_b], bookmark: true);

    expect(fx.notifier.isLoaded, isFalse);
    expect(store.saves, isEmpty);
    expect(fx.state.isEmpty, isTrue);

    // Storage comes back: the next change reads first, then saves.
    store.loadError = null;
    await fx.notifier.toggleBookmarks(_vault(), [_b], bookmark: true);
    expect(store.saves.single.bookmarkPaths, ['Docs/a.txt', 'Photos']);
  });

  test('a change that changes nothing does not write', () async {
    final store = _FakeStore(VaultMarks().withBookmarks([_a]));
    final fx = make(store);
    await fx.notifier.ensureLoaded(_vault());

    await fx.notifier.removeBookmark(_vault(), 'Nope');
    await fx.notifier.toggleBookmarks(_vault(), [_a], bookmark: true);
    await fx.notifier.removeDeletedPaths(_vault(), {'Elsewhere'});
    await fx.notifier.remapPaths(_vault(), const {});
    await fx.notifier.togglePins(_vault(), ['x'], pin: false);

    expect(store.saves, isEmpty);
  });

  test('saves run one at a time, in the order the changes were made', () async {
    final store = _FakeStore();
    final first = Completer<void>();
    store.saveGates.add(first);
    final fx = make(store);

    final one = fx.notifier.toggleBookmarks(_vault(), [_a], bookmark: true);
    await Future<void>.delayed(Duration.zero);
    final two = fx.notifier.toggleBookmarks(_vault(), [_b], bookmark: true);
    await Future<void>.delayed(Duration.zero);

    // The state moved on straight away, even though nothing is saved yet.
    expect(fx.state.bookmarkPaths, ['Docs/a.txt', 'Photos']);
    expect(store.saves, isEmpty);

    first.complete();
    await Future.wait([one, two]);

    expect(store.saves.map((m) => m.bookmarkPaths).toList(), [
      ['Docs/a.txt'],
      ['Docs/a.txt', 'Photos'],
    ]);
    expect(store.stored.bookmarkPaths, ['Docs/a.txt', 'Photos']);
  });

  test('a failed save neither throws nor undoes the change', () async {
    final store = _FakeStore()..saveSucceeds = false;
    final fx = make(store);

    await fx.notifier.toggleBookmarks(_vault(), [_a], bookmark: true);

    expect(fx.state.bookmarkPaths, ['Docs/a.txt']);
    expect(store.saves, hasLength(1));
  });

  test('deleting a folder drops marks on everything inside it', () async {
    final store = _FakeStore(
      VaultMarks(
        bookmarks: const [
          VaultBookmark('Photos', isDir: true),
          VaultBookmark('Photos/2024/a.jpg', isDir: false),
          VaultBookmark('PhotosOld', isDir: true),
        ],
        pinnedPaths: const {'Photos/x.txt'},
      ),
    );
    final fx = make(store);

    await fx.notifier.removeDeletedPaths(_vault(), {'Photos'});

    expect(fx.state.bookmarkPaths, ['PhotosOld']);
    expect(fx.state.pinnedPaths, isEmpty);
    expect(store.saves, hasLength(1));
  });

  test('renaming follows the entry', () async {
    final store = _FakeStore(
      VaultMarks().withBookmarks(const [
        VaultBookmark('Photos', isDir: true),
        VaultBookmark('Photos/a.jpg', isDir: false),
      ]),
    );
    final fx = make(store);

    await fx.notifier.remapPaths(_vault(), {'Photos': 'Pics'});

    expect(fx.state.bookmarkPaths, ['Pics', 'Pics/a.jpg']);
    expect(store.stored.bookmarkPaths, ['Pics', 'Pics/a.jpg']);
  });

  test('reordering and pinning are saved', () async {
    final store = _FakeStore(VaultMarks().withBookmarks([_a, _b]));
    final fx = make(store);

    await fx.notifier.reorderBookmarks(_vault(), 0, 1);
    await fx.notifier.togglePins(_vault(), ['Docs/a.txt'], pin: true);

    expect(store.stored.bookmarkPaths, ['Photos', 'Docs/a.txt']);
    expect(store.stored.pinnedPaths, {'Docs/a.txt'});
  });

  test('reload replaces the state with what is stored now', () async {
    final store = _FakeStore(VaultMarks().withBookmarks([_a]));
    final fx = make(store);
    await fx.notifier.ensureLoaded(_vault());

    store.stored = VaultMarks().withBookmarks([_b]);
    await fx.notifier.reload(_vault());

    expect(fx.state.bookmarkPaths, ['Photos']);
    expect(store.loads, 2);
  });

  test('a read that finishes after disposal changes nothing and does not '
      'throw', () async {
    final store = _FakeStore(VaultMarks().withBookmarks([_a]))
      ..loadGate = Completer<void>();
    final fx = make(store);

    final pending = fx.notifier.ensureLoaded(_vault());
    fx.dispose();
    store.loadGate!.complete();
    await pending;

    expect(fx.notifier.isLoaded, isFalse);
  });
}

void main() {
  registerPinsBookmarksScenarios(_make);
}
