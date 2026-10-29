import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/file_item_action.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  group('FileItemAction', () {
    test('the default quick actions are share, copy, move and delete', () {
      expect(FileItemAction.defaultQuickActions, {
        FileItemAction.share,
        FileItemAction.copy,
        FileItemAction.move,
        FileItemAction.delete,
      });
      expect(
        FileItemAction.defaultQuickActions.length,
        lessThanOrEqualTo(FileItemAction.maxQuickActions),
      );
    });

    test('default quick actions keep their share, copy, move, delete order', () {
      final quick = FileItemAction.values
          .where(FileItemAction.defaultQuickActions.contains)
          .toList();

      expect(quick, [
        FileItemAction.share,
        FileItemAction.copy,
        FileItemAction.move,
        FileItemAction.delete,
      ]);
    });

    test('the default order lists the list actions as the sheet did', () {
      final list = FileItemAction.values
          .where((a) => !FileItemAction.defaultQuickActions.contains(a))
          .toList();

      expect(list, [
        FileItemAction.goToLocation,
        FileItemAction.openInNewTab,
        FileItemAction.extract,
        FileItemAction.openWith,
        FileItemAction.editImage,
        FileItemAction.editVideo,
        FileItemAction.editAudio,
        FileItemAction.rename,
        FileItemAction.archive,
        FileItemAction.exportToDevice,
        FileItemAction.encrypt,
        FileItemAction.decrypt,
        FileItemAction.docProvider,
        FileItemAction.syncSettings,
        FileItemAction.pin,
        FileItemAction.bookmark,
        FileItemAction.copyPath,
      ]);
    });

    test('groups never decrease along the default order', () {
      final groups = FileItemAction.values.map((a) => a.group).toList();

      expect(groups, [
        0, 0, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5, 6, //
      ]);
    });

    test('with the default quick row, the list keeps its original groups', () {
      final groups = FileItemAction.values
          .where((a) => !FileItemAction.defaultQuickActions.contains(a))
          .map((a) => a.group)
          .toList();

      expect(groups, [0, 0, 1, 2, 2, 2, 2, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5]);
    });

    test('every action has a label and survives a JSON round trip', () {
      final l10n = AppLocalizationsEn();
      for (final action in FileItemAction.values) {
        expect(action.getLocalizedLabel(l10n), isNotEmpty, reason: '$action');
        expect(FileItemAction.fromJson(action.toJson()), action);
      }
    });

    test('go to location leads the order and copy path sits just above delete', () {
      expect(FileItemAction.values.first, FileItemAction.goToLocation);
      final delete = FileItemAction.values.indexOf(FileItemAction.delete);
      expect(FileItemAction.values[delete - 1], FileItemAction.copyPath);
    });

    test('fromJson ignores unknown and null names', () {
      expect(FileItemAction.fromJson('noSuchAction'), isNull);
      expect(FileItemAction.fromJson(null), isNull);
    });
  });
}
