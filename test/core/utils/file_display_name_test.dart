import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/file_display_name.dart';

void main() {
  group('stripFileExtension', () {
    test('drops the last extension', () {
      expect(stripFileExtension('report.pdf'), 'report');
      expect(stripFileExtension('photo.final.JPG'), 'photo.final');
    });

    test('drops both parts of a compressed tarball', () {
      expect(stripFileExtension('backup.tar.gz'), 'backup');
      expect(stripFileExtension('Backup.TAR.XZ'), 'Backup');
      expect(stripFileExtension('v1.2.tar.zst'), 'v1.2');
    });

    test('a plain .tar is just an extension', () {
      expect(stripFileExtension('backup.tar'), 'backup');
    });

    test('keeps names with no extension', () {
      expect(stripFileExtension('README'), 'README');
      expect(stripFileExtension(''), '');
    });

    test('keeps dotfiles whole', () {
      expect(stripFileExtension('.bashrc'), '.bashrc');
      expect(stripFileExtension('..hidden'), '..hidden');
    });

    test('a dotfile with an extension keeps its leading dot', () {
      expect(stripFileExtension('.env.local'), '.env');
    });

    test('keeps a trailing dot', () {
      expect(stripFileExtension('draft.'), 'draft.');
    });

    test('does not mistake a sentence for an extension', () {
      expect(
        stripFileExtension('Meeting 2024.05.12 notes'),
        'Meeting 2024.05.12 notes',
      );
    });

    test('works with non-latin names', () {
      expect(stripFileExtension('書類.docx'), '書類');
    });
  });
}
