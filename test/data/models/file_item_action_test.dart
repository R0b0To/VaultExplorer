import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/file_item_action.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

void main() {
  group('FileItemAction', () {
    test('the quick actions are exactly share, copy, move and delete', () {
      expect(
        FileItemAction.values.where((a) => a.isQuickAction).toSet(),
        {
          FileItemAction.share,
          FileItemAction.copy,
          FileItemAction.move,
          FileItemAction.delete,
        },
      );
    });

    test('quick actions keep their share, copy, move, delete order', () {
      final quick = FileItemAction.values
          .where((a) => a.isQuickAction)
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
          .where((a) => !a.isQuickAction)
          .toList();

      expect(list, [
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
      ]);
    });

    test('list actions only change group at the original group boundaries', () {
      final groups = FileItemAction.values
          .where((a) => !a.isQuickAction)
          .map((a) => a.group)
          .toList();

      expect(groups, [0, 1, 2, 2, 2, 2, 3, 3, 4, 4, 4, 4, 4, 5, 5]);
    });

    test('every action has a label and survives a JSON round trip', () {
      final l10n = AppLocalizationsEn();
      for (final action in FileItemAction.values) {
        expect(action.getLocalizedLabel(l10n), isNotEmpty, reason: '$action');
        expect(FileItemAction.fromJson(action.toJson()), action);
      }
    });

    test('fromJson ignores unknown and null names', () {
      expect(FileItemAction.fromJson('noSuchAction'), isNull);
      expect(FileItemAction.fromJson(null), isNull);
    });
  });
}
