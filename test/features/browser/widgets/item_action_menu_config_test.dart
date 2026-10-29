import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/file_item_action.dart';
import 'package:vaultexplorer/features/browser/widgets/item_action_menu_config.dart';

PopupMenuItem<String> _item(String value) =>
    PopupMenuItem<String>(value: value, child: const SizedBox());

List<String?> _values(List<PopupMenuItem<String>> items) =>
    items.map((i) => i.value).toList();

void main() {
  group('applyItemActionMenuConfig', () {
    final menu = [
      _item('open_in_new_tab'),
      _item('select_all'),
      _item('open_with_app'),
      _item('rename'),
      _item('compress'),
      _item('pin'),
      _item('bookmark'),
      _item('file_info'),
    ];

    test('the default order leaves a default-ordered menu untouched', () {
      final result = applyItemActionMenuConfig(
        menu,
        order: FileItemAction.values,
        hidden: const {},
      );

      expect(_values(result), _values(menu));
    });

    test('hidden actions are removed; unconfigurable items stay', () {
      final result = applyItemActionMenuConfig(
        menu,
        order: FileItemAction.values,
        hidden: {FileItemAction.rename, FileItemAction.pin},
      );

      expect(_values(result), [
        'open_in_new_tab',
        'select_all',
        'open_with_app',
        'compress',
        'bookmark',
        'file_info',
      ]);
    });

    test('reordering moves configurable items between their own slots', () {
      final order = [
        FileItemAction.bookmark,
        FileItemAction.pin,
        FileItemAction.archive,
        FileItemAction.rename,
        FileItemAction.openWith,
        FileItemAction.openInNewTab,
        ...FileItemAction.values.where(
          (a) => !{
            FileItemAction.bookmark,
            FileItemAction.pin,
            FileItemAction.archive,
            FileItemAction.rename,
            FileItemAction.openWith,
            FileItemAction.openInNewTab,
          }.contains(a),
        ),
      ];

      final result = applyItemActionMenuConfig(
        menu,
        order: order,
        hidden: const {},
      );

      // select_all keeps slot 1 and file_info the last slot.
      expect(_values(result), [
        'bookmark',
        'select_all',
        'pin',
        'compress',
        'rename',
        'open_with_app',
        'open_in_new_tab',
        'file_info',
      ]);
    });

    test('pin and unpin share one action and keep their relative order', () {
      final items = [_item('rename'), _item('pin'), _item('unpin')];

      final result = applyItemActionMenuConfig(
        items,
        order: [
          FileItemAction.pin,
          ...FileItemAction.values.where((a) => a != FileItemAction.pin),
        ],
        hidden: const {},
      );

      expect(_values(result), ['pin', 'unpin', 'rename']);
    });

    test('hiding the action hides both its toggle variants', () {
      final items = [
        _item('pin'),
        _item('unpin'),
        _item('bookmark'),
        _item('unbookmark'),
      ];

      final result = applyItemActionMenuConfig(
        items,
        order: FileItemAction.values,
        hidden: {FileItemAction.pin},
      );

      expect(_values(result), ['bookmark', 'unbookmark']);
    });

    test('an empty or single configurable menu is returned as is', () {
      expect(
        applyItemActionMenuConfig(
          const [],
          order: FileItemAction.values,
          hidden: const {},
        ),
        isEmpty,
      );
      expect(
        _values(
          applyItemActionMenuConfig(
            [_item('select_all'), _item('copy')],
            order: FileItemAction.values,
            hidden: const {},
          ),
        ),
        ['select_all', 'copy'],
      );
    });
  });

  group('go to location and copy path are configurable', () {
    final menu = [
      _item('select_all'),
      _item('open_in_new_tab'),
      _item('open_with_app'),
      _item('bookmark'),
      _item('go_to_location'),
      _item('copy_path'),
      _item('file_info'),
    ];

    test('by default go to location leads the configurable items', () {
      final result = applyItemActionMenuConfig(
        menu,
        order: FileItemAction.values,
        hidden: const {},
      );

      expect(_values(result), [
        'select_all',
        'go_to_location',
        'open_in_new_tab',
        'open_with_app',
        'bookmark',
        'copy_path',
        'file_info',
      ]);
    });

    test('hiding either action removes just that entry', () {
      expect(
        _values(
          applyItemActionMenuConfig(
            menu,
            order: FileItemAction.values,
            hidden: {FileItemAction.copyPath},
          ),
        ),
        isNot(contains('copy_path')),
      );
      final withoutGoTo = _values(
        applyItemActionMenuConfig(
          menu,
          order: FileItemAction.values,
          hidden: {FileItemAction.goToLocation},
        ),
      );
      expect(withoutGoTo, isNot(contains('go_to_location')));
      expect(withoutGoTo, contains('copy_path'));
    });

    test('they follow the user\'s order like any other action', () {
      final order = [
        FileItemAction.copyPath,
        ...FileItemAction.values.where((a) => a != FileItemAction.copyPath),
      ];

      final result = applyItemActionMenuConfig(
        menu,
        order: order,
        hidden: const {},
      );

      expect(_values(result).indexOf('copy_path'), 1);
      expect(_values(result).first, 'select_all');
      expect(_values(result).last, 'file_info');
    });
  });
}
