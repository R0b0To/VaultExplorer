import 'dart:ui' show Offset;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/controllers/browser_drag_session.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drag.dart';

MountedContainer _volume(int volId) => MountedContainer(
  volId: volId,
  uri: 'file:///vault$volId.hc',
  displayName: 'Vault $volId',
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000000,
  freeSpace: 500000,
  containerFormat: 'veracrypt',
);

// RawEntry overrides ==, so it cannot be an element of a const set.
const _file = RawEntry(name: 'a.txt', isDir: false, sizeBytes: 1, modifiedSecs: 0);
const _folder = RawEntry(name: 'docs', isDir: true, sizeBytes: 0, modifiedSecs: 0);

BrowserItemDragData _data({
  required MountedContainer source,
  String directory = '',
  Set<RawEntry>? entries,
}) => BrowserItemDragData(
  source: source,
  sourceDirectory: directory,
  entries: entries ?? {_file},
  onDrop: (_, _, _, _) async {},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('drop rules', () {
    test('dropping into the folder the items came from can only copy', () {
      final vault = _volume(1);
      final data = _data(source: vault, directory: 'photos');

      expect(data.canMoveInto(vault, 'photos'), isFalse);
      expect(data.canCopyInto(vault, 'photos'), isTrue);
      expect(data.canDropInto(vault, 'photos'), isTrue);
    });

    test('dropping into another folder can copy or move', () {
      final vault = _volume(1);
      final data = _data(source: vault, directory: 'photos');

      expect(data.canMoveInto(vault, 'archive'), isTrue);
      expect(data.canCopyInto(vault, 'archive'), isTrue);
    });

    test('the same path in another volume is a different folder', () {
      final data = _data(source: _volume(1), directory: 'photos');

      expect(data.canMoveInto(_volume(2), 'photos'), isTrue);
    });

    test('a folder cannot go into itself or its descendants', () {
      final vault = _volume(1);
      final data = _data(source: vault, entries: {_folder});

      for (final path in ['docs', 'docs/sub']) {
        expect(data.canMoveInto(vault, path), isFalse, reason: path);
        expect(data.canCopyInto(vault, path), isFalse, reason: path);
        expect(data.canDropInto(vault, path), isFalse, reason: path);
      }
      expect(data.canMoveInto(vault, 'docs-other'), isTrue);
    });

    test('a same-named path in another volume is not the folder itself', () {
      final data = _data(source: _volume(1), entries: {_folder});

      expect(data.canCopyInto(_volume(2), 'docs'), isTrue);
    });

    test('nothing to drop means nothing to do', () {
      final vault = _volume(1);
      final data = _data(source: vault, entries: <RawEntry>{});

      expect(data.canCopyInto(vault, 'x'), isFalse);
      expect(data.canMoveInto(vault, 'x'), isFalse);
    });
  });

  group('BrowserDragSession', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    BrowserDragSession session() =>
        container.read(browserDragSessionProvider.notifier);
    BrowserDragSessionState state() =>
        container.read(browserDragSessionProvider);

    test('only one drag may be active at a time', () {
      expect(session().tryBegin(const TabId(1), const Offset(10, 10)), isTrue);
      expect(session().tryBegin(const TabId(1), const Offset(50, 50)), isFalse);
      expect(session().tryBegin(const TabId(2), const Offset(50, 50)), isFalse);
      expect(state().sourceTabId, const TabId(1));
      expect(state().startPosition, const Offset(10, 10));
    });

    test('every other viewport is locked while a drag is active', () {
      session().tryBegin(const TabId(1), Offset.zero);

      expect(state().isLockedFor(const TabId(1)), isFalse);
      expect(state().isLockedFor(const TabId(2)), isTrue);
    });

    test('nothing is locked without a drag', () {
      expect(state().isActive, isFalse);
      expect(state().isLockedFor(const TabId(1)), isFalse);
    });

    test('ending frees the slot and is safe to repeat', () {
      session().tryBegin(const TabId(1), Offset.zero);
      session().end();
      session().end();

      expect(state().isActive, isFalse);
      expect(session().pointer.value, isNull);
      expect(session().tryBegin(const TabId(2), Offset.zero), isTrue);
    });

    test('pointer updates do not change the session state', () {
      session().tryBegin(const TabId(1), Offset.zero);
      final before = state();

      session().updatePointer(const Offset(30, 40));

      expect(identical(state(), before), isTrue);
      expect(session().pointer.value, const Offset(30, 40));
    });
  });

  group('BrowserDropRevealNotifier', () {
    late ProviderContainer container;

    setUp(() => container = ProviderContainer());
    tearDown(() => container.dispose());

    test('every announcement gets a new token, even an identical one', () {
      final notifier = container.read(browserDropRevealProvider.notifier);

      notifier.publish(volId: 1, namesByDir: {'': {'a.txt'}});
      final first = container.read(browserDropRevealProvider)!;
      notifier.publish(volId: 1, namesByDir: {'': {'a.txt'}});
      final second = container.read(browserDropRevealProvider)!;

      expect(second.token, greaterThan(first.token));
      expect(second.namesByDir[''], {'a.txt'});
    });

    test('empty announcements are dropped', () {
      final notifier = container.read(browserDropRevealProvider.notifier);

      notifier.publish(volId: 1, namesByDir: const {});
      notifier.publish(volId: 1, namesByDir: {'x': <String>{}});

      expect(container.read(browserDropRevealProvider), isNull);
    });
  });
}
