import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';

part 'file_manager_toolbar_service.g.dart';

@Riverpod(keepAlive: true)
FileManagerToolbarService fileManagerToolbarService(Ref ref) =>
    FileManagerToolbarService();

/// Loads/saves the user's customized file-browser action-bar layout (see
/// [FileManagerToolbarConfig]).
///
/// This is a tiny JSON-file-backed service. Its lifetime is owned by the
/// keep-alive Riverpod provider, making the in-memory cache overridable in
/// tests without a global singleton.
class FileManagerToolbarService {
  FileManagerToolbarService();

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
        final raw =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
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
    } catch (_) {
      // _cache above already reflects the new config for this session; a
      // failed write here only risks it not surviving an app restart.
    }
  }

  /// Forces the next [load] to re-read from disk.
  void invalidate() => _cache = null;
}
