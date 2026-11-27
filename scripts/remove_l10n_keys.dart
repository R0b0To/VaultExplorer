// scripts/remove_l10n_keys.dart
//
// The counterpart of update_l10n_keys.dart: removes ARB keys that nothing
// references any more. A key's "@key" metadata entry is removed with it.
//
// Run from the project root, then regenerate the bindings:
//   dart run scripts/remove_l10n_keys.dart
//   flutter gen-l10n
import 'dart:convert';
import 'dart:io';

/// Keys with no reference in lib/, test/ or scripts/ when this list was made.
/// Delete a line to keep a key you still want.
const List<String> unusedKeys = [
  'pdfViewerSearchHint',
  'pdfViewerNoMatches',
  'pdfViewerPreviousMatch',
  'pdfViewerNextMatch',
  'layoutModeList',
  'layoutModeGrid',
  'unsavedChangesLabel',
  'savedToVault',
  'saveChangesTooltip',
  'autosavedAtLabel',
  'filesChooseDestinationTitle',
  'filesMoveHere',
  'filesCopyHere',
  'filesFilterTooltip',
  'filesFilterAll',
  'filesFilterImages',
  'filesFilterVideos',
  'filesFilterAudio',
  'filesFilterDocuments',
  'filesTextTooLarge',
  'filesTextSaved',
  'filesTextSaveFailed',
  'addStorageLocationSubtitle',
  'storageLocationUnresolvedError',
  'dashboardNavLabel',
  'cutTooltip',
  'galleryFoldersUseAll',
  'galleryFoldersApply',
];

void main() {
  final l10nDir = _findL10nDirectory();
  if (l10nDir == null) {
    stderr.writeln('Error: Could not find directory containing app_en.arb.');
    exit(1);
  }

  print('Targeting l10n directory: ${l10nDir.path}');

  final files = l10nDir
      .listSync()
      .whereType<File>()
      .where((file) {
        final name = file.uri.pathSegments.last;
        return name.startsWith('app_') && name.endsWith('.arb');
      })
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  var totalRemoved = 0;
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final jsonMap =
        json.decode(file.readAsStringSync()) as Map<String, dynamic>;

    var removed = 0;
    var modified = false;
    for (final key in unusedKeys) {
      if (jsonMap.remove(key) != null) {
        removed++;
        modified = true;
      }
      if (jsonMap.remove('@$key') != null) modified = true;
    }

    if (!modified) {
      print('Unchanged: $name');
      continue;
    }

    const encoder = JsonEncoder.withIndent('  ');
    file.writeAsStringSync('${encoder.convert(jsonMap)}\n');
    print('Updated: $name (removed $removed keys)');
    totalRemoved += removed;
  }

  print('\nRemoved $totalRemoved strings.');
  print('Run "flutter gen-l10n" to regenerate localization Dart bindings.');
}

Directory? _findL10nDirectory() {
  final candidates = [
    Directory('lib/l10n'),
    Directory('l10n'),
    Directory('../lib/l10n'),
  ];
  for (final dir in candidates) {
    if (dir.existsSync() && File('${dir.path}/app_en.arb').existsSync()) {
      return dir;
    }
  }
  return null;
}
