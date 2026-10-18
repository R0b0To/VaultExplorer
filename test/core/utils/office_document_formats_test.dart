import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/office_document_formats.dart';

void main() {
  group('OfficeDocumentFormats.isSupportedExtension', () {
    test('accepts supported extensions in any case, with or without a dot', () {
      expect(OfficeDocumentFormats.isSupportedExtension('docx'), isTrue);
      expect(OfficeDocumentFormats.isSupportedExtension('DOCX'), isTrue);
      expect(OfficeDocumentFormats.isSupportedExtension('.xlsx'), isTrue);
      expect(OfficeDocumentFormats.isSupportedExtension(' ODT '), isTrue);
    });

    test('rejects everything else', () {
      for (final ext in const ['', 'doc', 'xls', 'pdf', 'html', 'md', 'zip']) {
        expect(OfficeDocumentFormats.isSupportedExtension(ext), isFalse,
            reason: ext);
      }
    });

    test('covers all three OpenDocument families and legacy PowerPoint', () {
      for (final ext in const ['odt', 'odp', 'ods', 'ppt']) {
        expect(OfficeDocumentFormats.extensions, contains(ext));
      }
    });
  });

  group('OfficeDocumentFormats.isSupportedName', () {
    test('uses the last extension of the file name', () {
      expect(OfficeDocumentFormats.isSupportedName('report.final.docx'), isTrue);
      expect(OfficeDocumentFormats.isSupportedName('Budget 2026.XLSX'), isTrue);
    });

    test('no extension, trailing dot, or hidden-file names are not documents',
        () {
      expect(OfficeDocumentFormats.isSupportedName('docx'), isFalse);
      expect(OfficeDocumentFormats.isSupportedName('report.'), isFalse);
      expect(OfficeDocumentFormats.isSupportedName('notes.txt'), isFalse);
    });
  });
}
