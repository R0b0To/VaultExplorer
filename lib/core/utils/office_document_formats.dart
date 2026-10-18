/// File formats the built-in document viewer can open.
///
/// The native converter (`officeviewer/OfficeDocumentConverter.kt`) decides
/// the real format from the file's *content*, so a wrongly named file still
/// opens; this list only decides which taps are routed to the viewer. Keep
/// it in step with the converters when a format is added.
///
/// Deliberately not listed: legacy binary `.doc` / `.xls` (no reader for
/// them), `.rtf`, and `.pdf` / `.html` / `.md` (they have their own viewers).
abstract final class OfficeDocumentFormats {
  const OfficeDocumentFormats._();

  /// Word, PowerPoint, Excel (OOXML and their macro-enabled / template
  /// variants), legacy PowerPoint 97-2003, and OpenDocument text,
  /// presentations and spreadsheets (documents and templates).
  static const Set<String> extensions = {
    'docx', 'docm', 'dotx', 'dotm',
    'pptx', 'pptm', 'ppsx', 'ppsm', 'potx', 'potm',
    'ppt', 'pps', 'pot',
    'xlsx', 'xlsm', 'xltx', 'xltm',
    'odt', 'ott', 'odp', 'otp', 'ods', 'ots',
  };

  /// Documents larger than this are not previewed: the file is read into
  /// memory, converted natively, and handed to the WebView, so the limit
  /// bounds peak memory (the converter enforces its own, stricter, limits on
  /// what a package may inflate to).
  static const int maxBytes = 40 * 1024 * 1024;

  /// [ext] may carry a leading dot and any case (`'.DOCX'`).
  static bool isSupportedExtension(String ext) {
    final clean = ext.trim().toLowerCase().replaceFirst(RegExp(r'^\.+'), '');
    return extensions.contains(clean);
  }

  static bool isSupportedName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return false;
    return isSupportedExtension(fileName.substring(dot + 1));
  }
}
