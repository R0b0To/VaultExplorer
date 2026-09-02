// A [FileBrowserPinsBookmarksController] persistence backend for decoy
// mode's local-storage container, kept entirely separate from
// [ContainerRepository]'s containers_v2.json.
//
// Why this can't just reuse ContainerRepository: that file is exactly what
// VaultDashboardController.loadAll() reads to populate the real vault
// dashboard. If a decoy-mode bookmark/pin ever got persisted through it,
// a ContainerRecord for the local-storage pseudo-container would show up
// as a bogus, unopenable tile on the *real* dashboard after a genuine
// unlock -- a direct leak of "decoy mode was used" defeating the entire
// point of Mask Mode. This service's own small JSON file never mixes with
// that data.
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

typedef DecoyLocalMarks = ({Set<String> pinnedPaths, List<String> bookmarkPaths});

const _emptyMarks = (pinnedPaths: <String>{}, bookmarkPaths: <String>[]);

class DecoyLocalMarksService {
  const DecoyLocalMarksService();

  static Future<File> get _dataFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/decoy_local_marks.json');
  }

  Future<DecoyLocalMarks> load() async {
    try {
      final file = await _dataFile;
      if (!await file.exists()) return _emptyMarks;
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return _emptyMarks;
      return (
        pinnedPaths: Set<String>.from((raw['pinnedPaths'] as List?) ?? const []),
        bookmarkPaths: List<String>.from((raw['bookmarkPaths'] as List?) ?? const []),
      );
    } catch (_) {
      return _emptyMarks;
    }
  }

  Future<void> save(DecoyLocalMarks marks) async {
    try {
      final file = await _dataFile;
      await file.writeAsString(
        jsonEncode({
          'pinnedPaths': marks.pinnedPaths.toList(),
          'bookmarkPaths': marks.bookmarkPaths,
        }),
      );
    } catch (_) {
      // Best-effort, same as ContainerRepository.save's callers treat it.
    }
  }
}
