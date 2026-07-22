import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';

/// Loads/saves the user's customized file-browser action-bar layout (see
/// [FileManagerToolbarConfig]).
///
/// Kept as its own tiny JSON-file-backed singleton — parallel in spirit to
/// [ContainerRepository]/[AppSettingsService] — so wiring this in doesn't
/// require touching either of those files. If you'd rather fold this into
/// [AppSettings] later, this class's `load`/`save` surface is small enough
/// to swap out without touching any call site.
class FileManagerToolbarService {
  FileManagerToolbarService._();
  static final instance = FileManagerToolbarService._();

  FileManagerToolbarConfig? _cache;

  static Future<File> get _dataFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/file_manager_toolbar.json');
  }

  Future<FileManagerToolbarConfig> load() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _dataFile;
      if (await file.exists()) {
        final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        _cache = FileManagerToolbarConfig.fromJson(raw);
      } else {
        _cache = FileManagerToolbarConfig.defaults();
      }
    } catch (_) {
      _cache = FileManagerToolbarConfig.defaults();
    }
    return _cache!;
  }

  Future<void> save(FileManagerToolbarConfig config) async {
    _cache = config;
    try {
      final file = await _dataFile;
      await file.writeAsString(jsonEncode(config.toJson()));
    } catch (_) {}
  }

  /// Forces the next [load] to re-read from disk.
  void invalidate() => _cache = null;
}
