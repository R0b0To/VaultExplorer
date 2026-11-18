import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_anchor.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_group_index.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_layout.dart';
import 'package:vaultexplorer/features/browser/widgets/date_group.dart';

Object _key(String s) => s;

void main() {
  group('findAnchorIndex', () {
    test('finds the same entry where it moved to', () {
      final prev = ['a', 'b', 'c', 'd'];
      final next = ['x', 'y', 'a', 'b', 'c', 'd'];
      expect(findAnchorIndex<String>(prev, 2, next, _key), 4);
    });

    test('an entry that is gone falls to the next one that survives', () {
      final prev = ['a', 'b', 'c', 'd'];
      final next = ['a', 'd'];
      expect(findAnchorIndex<String>(prev, 1, next, _key), 1); // d
    });

    test('with nothing after it left, the closest one before it', () {
      final prev = ['a', 'b', 'c'];
      final next = ['a', 'z'];
      expect(findAnchorIndex<String>(prev, 2, next, _key), 0);
    });

    test('null when nothing survives or the input is out of range', () {
      expect(findAnchorIndex<String>(['a'], 0, ['b'], _key), isNull);
      expect(findAnchorIndex<String>(['a'], 3, ['a'], _key), isNull);
      expect(findAnchorIndex<String>(['a'], 0, <String>[], _key), isNull);
    });

    test('the key, not equality, tells entries apart', () {
      final prev = [(1, 'p'), (2, 'p')];
      final next = [(2, 'p'), (1, 'p')];
      expect(
        findAnchorIndex<(int, String)>(prev, 1, next, (e) => e),
        0,
      );
    });
  });

  group('uniformAnchorOffset', () {
    test('rows added above push the offset down by whole rows', () {
      final prev = [for (var i = 0; i < 30; i++) 'p$i'];
      final next = [for (var i = 0; i < 6; i++) 'n$i', ...prev];
      // 3 columns, rows of 100, 12 of padding; scrolled 2.5 rows down.
      final target = uniformAnchorOffset<String>(
        previous: prev,
        next: next,
        keyOf: _key,
        offset: 12 + 250,
        rowExtent: 100,
        columns: 3,
        topPadding: 12,
      );
      expect(target, 12 + 250 + 2 * 100); // 6 entries = 2 rows
    });

    test('nothing to hold at the top of the list', () {
      expect(
        uniformAnchorOffset<String>(
          previous: ['a', 'b'],
          next: ['z', 'a', 'b'],
          keyOf: _key,
          offset: 0,
          rowExtent: 100,
        ),
        isNull,
      );
    });
  });

  group('host', () {
    GalleryLayoutHost hostOf(int items) => GalleryLayoutHost(
          flow: GalleryFlow.list,
          columnCount: 1,
          spacing: 0,
        )
          ..rowExtent = 50
          ..sections = [GallerySection(itemCount: items)];

    test('no top item before the first layout or at the very top', () {
      final host = hostOf(100);
      expect(host.captureTopItem(), isNull);
      host.modelFor(400);
      host.sliverScrollOffset = 0;
      expect(host.captureTopItem(), isNull);
    });

    test('the top item is the first one on screen, with its offset', () {
      final host = hostOf(100)..sliverCrossExtent = 400;
      host.modelFor(400);
      host.sliverScrollOffset = 1025;
      final top = host.captureTopItem()!;
      expect(top.item, 20);
      expect(top.viewportOffset, -25);
    });

    test('adoptAnchored hands the next layout pass the anchor', () {
      final host = hostOf(100)..sliverCrossExtent = 400;
      host.modelFor(400);
      host.sliverScrollOffset = 1000;
      final top = host.captureTopItem()!;
      host
        ..sections = [const GallerySection(itemCount: 120)]
        ..invalidate();
      final model = host.prepareModel()!;
      host.adoptAnchored(model, model.childOfItem[top.item + 20], top.viewportOffset);
      expect(host.pendingAnchor!.child, top.item + 20);
      expect(identical(host.modelFor(400), model), isTrue);
    });
  });

  group('carryGroupAnchor', () {
    GalleryGroupIndex<String> groupsOf(List<String> items, List<int> sizes) {
      final groups = <DateGroup<String>>[];
      var at = 0;
      for (final n in sizes) {
        groups.add(DateGroup<String>(
          date: null,
          items: items.sublist(at, at + n),
          globalIndices: [for (var i = 0; i < n; i++) at + i],
        ));
        at += n;
      }
      return GalleryGroupIndex<String>(items, groups);
    }

    test('maps the child of an entry to the child of the same entry', () {
      final prev = groupsOf(['a', 'b', 'c', 'd'], [2, 2]);
      // children: h0 a b h1 c d -> 'c' is child 4
      final next = groupsOf(['x', 'a', 'b', 'c', 'd'], [3, 2]);
      // children: h0 x a b h1 c d -> 'c' is child 5
      final carried = carryGroupAnchor<String>(
        const GalleryAnchor(child: 4, viewportOffset: -10),
        prev,
        next,
        _key,
      )!;
      expect(carried.child, 5);
      expect(carried.viewportOffset, -10);
    });

    test('a header is not an anchor', () {
      final prev = groupsOf(['a', 'b'], [2]);
      expect(
        carryGroupAnchor<String>(
          const GalleryAnchor(child: 0, viewportOffset: 0),
          prev,
          prev,
          _key,
        ),
        isNull,
      );
    });
  });
}
