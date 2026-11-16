import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';

void main() {
  group('FileOperationService.nameWithTargetExtension', () {
    String name(String link, String target) =>
        FileOperationService.nameWithTargetExtension(link, target);

    test('a link with no extension gains the target\'s', () {
      expect(name('Holiday', 'IMG_0042.jpg'), 'Holiday.jpg');
    });

    test('a link that already ends with the target\'s extension is unchanged', () {
      expect(name('Holiday.jpg', 'IMG_0042.jpg'), 'Holiday.jpg');
    });

    test('the comparison ignores case, in both directions', () {
      expect(name('Holiday.JPG', 'IMG_0042.jpg'), 'Holiday.JPG');
      expect(name('Holiday.jpg', 'IMG_0042.JPG'), 'Holiday.jpg');
    });

    test('a different extension on the link is not mistaken for the target\'s', () {
      expect(name('notes.txt', 'scan.pdf'), 'notes.txt.pdf');
    });

    test('a dot inside the link name is not an extension', () {
      expect(name('v1.2 notes', 'notes.md'), 'v1.2 notes.md');
    });

    test('a target with no extension leaves the name alone', () {
      expect(name('Holiday', 'README'), 'Holiday');
      expect(name('Holiday', '.bashrc'), 'Holiday');
      expect(name('Holiday', 'trailing.'), 'Holiday');
    });

    test('a compound extension is kept whole', () {
      expect(name('backup', 'site.tar.gz'), 'backup.tar.gz');
      expect(name('backup.tar.gz', 'site.tar.gz'), 'backup.tar.gz');
      // Ends with the target's last extension already: left as named.
      expect(name('backup.gz', 'site.tar.gz'), 'backup.gz');
    });

    test('a name that is only a compound-looking suffix is not split', () {
      expect(name('x', '.tar.gz'), 'x.gz');
    });
  });
}
