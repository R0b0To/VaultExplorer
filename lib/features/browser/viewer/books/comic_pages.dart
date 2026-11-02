import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';

/// The reading order of a comic archive: its image entries, in natural
/// (numeric-aware) path order, minus the metadata droppings archivers leave
/// behind (`__MACOSX/`, dot-files such as `._001.jpg`).
List<String> comicPageNames(Iterable<BookEntry> entries) {
  final names = <String>[
    for (final entry in entries)
      if (_isPage(entry.name)) entry.name,
  ];
  names.sort(naturalCompare);
  return names;
}

bool _isPage(String name) {
  final parts = name.split('/');
  for (final part in parts) {
    if (part.isEmpty) continue;
    if (part.startsWith('.') || part == '__MACOSX') return false;
  }
  return MediaViewerConstants.isImage(parts.last);
}

final _chunk = RegExp(r'\d+|\D+');
final _leadingZeros = RegExp(r'^0+');

/// Case-insensitive comparison where digit runs compare by value, so
/// `page2.jpg` < `page10.jpg` and `001.jpg` < `002.jpg` < `010.jpg`.
int naturalCompare(String a, String b) {
  final left = _chunk.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final right = _chunk.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  final shared = left.length < right.length ? left.length : right.length;
  for (var i = 0; i < shared; i++) {
    final x = left[i];
    final y = right[i];
    final bothNumeric = _isDigit(x.codeUnitAt(0)) && _isDigit(y.codeUnitAt(0));
    int order;
    if (bothNumeric) {
      final xs = x.replaceFirst(_leadingZeros, '');
      final ys = y.replaceFirst(_leadingZeros, '');
      order = xs.length != ys.length
          ? xs.length.compareTo(ys.length)
          : xs.compareTo(ys);
    } else {
      order = x.compareTo(y);
    }
    if (order != 0) return order;
  }
  final byLength = left.length.compareTo(right.length);
  return byLength != 0 ? byLength : a.compareTo(b);
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
