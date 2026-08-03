import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// One entry in the decoy reader's "recent files" list.
///
/// This is purely cosmetic decoy-reader state -- it exists only so "Doc
/// Viewer" looks and behaves like a real, previously-used PDF reader. It
/// carries no vault linkage of any kind (just a SAF `content://` Uri and a
/// display name), which is exactly why it's fine for it to live in a plain
/// JSON file rather than secure storage: unlike Discrete Mode's on/off
/// state (deliberately *not* persisted anywhere, see
/// `DisguiseModeApi.getMode`), a list of "PDFs this reader app opened"
/// reveals nothing about the vault and is the kind of thing a real PDF
/// reader would have anyway.
class DecoyRecentFile {
  final String uri;
  final String displayName;
  final DateTime openedAt;

  const DecoyRecentFile({
    required this.uri,
    required this.displayName,
    required this.openedAt,
  });

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'displayName': displayName,
    'openedAt': openedAt.millisecondsSinceEpoch,
  };

  factory DecoyRecentFile.fromJson(Map<String, dynamic> j) => DecoyRecentFile(
    uri: j['uri'] as String? ?? '',
    displayName: j['displayName'] as String? ?? 'Document.pdf',
    openedAt: DateTime.fromMillisecondsSinceEpoch(
      j['openedAt'] as int? ?? 0,
    ),
  );
}

/// Caps how many recent entries are kept, oldest dropped first.
const int _kMaxRecents = 20;

/// Loads/saves the decoy reader's recent-files list. Static, file-backed,
/// same shape as `AppSettingsService` -- see that class's doc comment for
/// the precedent this follows.
class DiscreteModeRepository {
  static Future<File> get _recentsFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/discrete_mode_recents.json');
  }

  static Future<List<DecoyRecentFile>> loadRecents() async {
    try {
      final file = await _recentsFile;
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(DecoyRecentFile.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Records [file] as most-recently-opened, de-duplicating by uri and
  /// trimming to [_kMaxRecents].
  static Future<void> recordOpened(DecoyRecentFile file) async {
    try {
      final current = await loadRecents();
      final next = [
        file,
        ...current.where((r) => r.uri != file.uri),
      ].take(_kMaxRecents).toList();
      final recentsFile = await _recentsFile;
      await recentsFile.writeAsString(
        jsonEncode(next.map((r) => r.toJson()).toList()),
      );
    } catch (_) {
      // Best-effort, same as AppSettingsService.saveSettings -- a failure
      // to remember a recent file should never block opening it.
    }
  }

  /// Removes a single entry by [uri] from recents.
  static Future<void> removeRecent(String uri) async {
    try {
      final current = await loadRecents();
      final next = current.where((r) => r.uri != uri).toList();
      final recentsFile = await _recentsFile;
      if (next.isEmpty) {
        if (await recentsFile.exists()) await recentsFile.delete();
      } else {
        await recentsFile.writeAsString(
          jsonEncode(next.map((r) => r.toJson()).toList()),
        );
      }
    } catch (_) {}
  }

  static Future<void> clearRecents() async {
    try {
      final file = await _recentsFile;
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
