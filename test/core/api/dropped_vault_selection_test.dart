import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/dropped_vault_selection.dart';

// What a drop on the dashboard means for the add-a-vault sheet: container files (one or several, like a
// multi-select in the picker), a single vault folder, or nothing usable.

DroppedPathInfo _file(String name) =>
    (uri: '/data/$name', displayName: name, isDirectory: false, format: null);

DroppedPathInfo _folder(String name, {String? format}) =>
    (uri: '/data/$name', displayName: name, isDirectory: true, format: format);

void main() {
  test('one container file', () {
    final plan = planDroppedSelection([_file('vault.hc')]);

    expect(plan, isA<DroppedFiles>());
    expect((plan as DroppedFiles).files.single.displayName, equals('vault.hc'));
  });

  test('several files are the parts of one container, in the order dropped', () {
    final plan = planDroppedSelection([_file('big.001'), _file('big.002')]);

    expect(plan, isA<DroppedFiles>());
    expect(
      (plan as DroppedFiles).files.map((f) => f.displayName).toList(),
      equals(['big.001', 'big.002']),
    );
  });

  test('a single folder carries the detected vault format', () {
    final plan = planDroppedSelection([_folder('notes', format: 'cryptomator')]);

    expect(plan, isA<DroppedFolder>());
    final folder = plan as DroppedFolder;
    expect(folder.uri, equals('/data/notes'));
    expect(folder.format, equals('cryptomator'));
  });

  test('a folder that is not a vault is still reported as a folder, without a format', () {
    final plan = planDroppedSelection([_folder('photos')]);

    expect(plan, isA<DroppedFolder>());
    expect((plan as DroppedFolder).format, isNull);
  });

  test('nothing, several folders, or files with a folder are not supported', () {
    expect(planDroppedSelection(const []), isA<DroppedUnsupported>());
    expect(
      planDroppedSelection([_folder('a', format: 'gocryptfs'), _folder('b', format: 'cryfs')]),
      isA<DroppedUnsupported>(),
    );
    expect(
      planDroppedSelection([_file('vault.hc'), _folder('a', format: 'gocryptfs')]),
      isA<DroppedUnsupported>(),
    );
  });
}
