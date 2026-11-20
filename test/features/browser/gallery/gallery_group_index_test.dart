import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_group_index.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_layout.dart';
import 'package:vaultexplorer/features/browser/widgets/date_group.dart';

DateGroup<String> _group(List<String> items, List<int> globals) =>
    DateGroup<String>(date: null, items: items, globalIndices: globals);

void main() {
  group('GalleryGroupIndex', () {
    test('maps child indices to groups and items, with a header per group', () {
      final source = ['a', 'b', 'c', 'd', 'e'];
      final idx = GalleryGroupIndex<String>(source, [
        _group(['a', 'b'], [0, 1]),
        _group(['c', 'd', 'e'], [2, 3, 4]),
      ]);
      expect(idx.childCount, 7);
      expect(idx.childGroup.toList(), [0, 0, 0, 1, 1, 1, 1]);
      expect(idx.childLocal.toList(), [-1, 0, 1, -1, 0, 1, 2]);
      expect(idx.childOfGlobal.toList(), [1, 2, 4, 5, 6]);
    });

    test('follows globalIndices when the groups are not in list order', () {
      // computeDateGroups orders groups by date, not by position in the list.
      final source = ['x0', 'y1', 'x2', 'y3'];
      final idx = GalleryGroupIndex<String>(source, [
        _group(['y1', 'y3'], [1, 3]),
        _group(['x0', 'x2'], [0, 2]),
      ]);
      expect(idx.childOfGlobal.toList(), [4, 1, 5, 2]);
      expect(idx.childLocal[idx.childOfGlobal[3]], 1);
      expect(idx.childGroup[idx.childOfGlobal[3]], 0);
    });

    test('an item no group holds maps to -1', () {
      final idx = GalleryGroupIndex<String>(['a', 'b', 'c'], [
        _group(['a', 'c'], [0, 2]),
      ]);
      expect(idx.childOfGlobal.toList(), [1, -1, 2]);
    });

    test('an empty list has no children', () {
      final idx = GalleryGroupIndex<String>(const [], const []);
      expect(idx.childCount, 0);
      expect(idx.childOfGlobal.length, 0);
    });

    test('its child indices are exactly those of the list layout', () {
      final source = [for (var i = 0; i < 40; i++) 'p$i'];
      final groups = [
        _group(source.sublist(0, 7), [for (var i = 0; i < 7; i++) i]),
        _group(source.sublist(7, 8), [7]),
        _group(source.sublist(8, 40), [for (var i = 8; i < 40; i++) i]),
      ];
      final idx = GalleryGroupIndex<String>(source, groups);
      final model = GalleryLayoutModel.compute(
        sections: [
          for (final g in groups) GallerySection(itemCount: g.items.length, headerExtent: 44),
        ],
        spec: const GalleryLayoutSpec(
          crossExtent: 360,
          spacing: 0,
          flow: GalleryFlow.list,
          columnCount: 1,
          rowExtent: 70,
        ),
        ratioOf: (_) => 1.0,
      );
      expect(model.childCount, idx.childCount);
      for (var c = 0; c < idx.childCount; c++) {
        final isHeader = idx.childLocal[c] < 0;
        expect(model.itemOfChild[c] < 0, isHeader, reason: 'child $c');
        expect(model.sectionOfChild[c], idx.childGroup[c], reason: 'child $c');
        expect(model.heights[c], isHeader ? 44.0 : 70.0);
      }
      for (var i = 0; i < source.length; i++) {
        expect(model.childOfItem[i], idx.childOfGlobal[i], reason: 'item $i');
      }
    });
  });
}
