import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_path_codec.dart';

BreadcrumbPathCodec _local(String root) =>
    BreadcrumbPathCodec.forStorage(rootUri: root, isLocalStorage: true);

String? _r(BreadcrumbPathCodec c, String input, [String cur = '']) {
  final t = c.resolve(input, cur);
  if (t == null) return null;
  return t.outside ? '<outside>' : t.relative;
}

void main() {
  group('vault', () {
    const c = BreadcrumbPathCodec.vault();
    test('format', () {
      expect(c.format(''), '/');
      expect(c.format('a/b'), '/a/b');
    });
    test('resolve absolute and relative', () {
      expect(_r(c, '/a/b'), 'a/b');
      expect(_r(c, '/'), '');
      expect(_r(c, 'x', 'a/b'), 'a/b/x');
      expect(_r(c, '..', 'a/b'), 'a');
      expect(_r(c, '..'), '<outside>');
      expect(_r(c, '/a/../..'), '<outside>');
      expect(_r(c, '   '), isNull);
    });
    test('non-local storage is vault style', () {
      final s = BreadcrumbPathCodec.forStorage(
        rootUri: 'content://com.example.provider/tree/x',
        isLocalStorage: true,
      );
      expect(s.isRealPath, isFalse);
    });
  });

  group('posix root', () {
    final c = _local('/storage/emulated/0');
    test('format', () {
      expect(c.format(''), '/storage/emulated/0');
      expect(c.format('Download/x'), '/storage/emulated/0/Download/x');
    });
    test('resolve', () {
      expect(_r(c, '/storage/emulated/0/Download'), 'Download');
      expect(_r(c, '/storage/emulated/0/'), '');
      expect(_r(c, '/storage/emulated/0/a/../b'), 'b');
      expect(_r(c, '/storage/emulated/1/a'), '<outside>');
      expect(_r(c, '/storage/emulated'), '<outside>');
      expect(_r(c, '/sdcard/DCIM'), 'DCIM');
      expect(_r(c, 'DCIM', 'Pictures'), 'Pictures/DCIM');
      expect(_r(c, '"/storage/emulated/0/x y"'), 'x y');
    });
  });

  group('windows', () {
    final home = _local(r'C:\Users\me');
    final drive = _local(r'D:\');
    test('format', () {
      expect(home.format(''), r'C:\Users\me');
      expect(home.format('Docs/a'), r'C:\Users\me\Docs\a');
      expect(drive.format(''), r'D:\');
      expect(drive.format('x'), r'D:\x');
    });
    test('resolve', () {
      expect(_r(home, r'C:\Users\me\Docs'), 'Docs');
      expect(_r(home, r'c:/users/ME/Docs/'), 'Docs');
      expect(_r(home, r'C:\Users'), '<outside>');
      expect(_r(home, r'D:\x'), '<outside>');
      expect(_r(home, r'"C:\Users\me\a b"'), 'a b');
      expect(_r(home, r'\Docs'), 'Docs');
      expect(_r(drive, r'D:\'), '');
      expect(_r(drive, r'd:\x\..\y'), 'y');
    });
  });
}
