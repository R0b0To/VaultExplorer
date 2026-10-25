import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';

part 'file_manager_toolbar_service.g.dart';

const _secure = AppSecureStorage.instance;

/// Storage key for the whole [FileManagerToolbarConfig] blob. Kept behind
/// [AppSecureStorage] rather than a plain file because [folderLayoutModes]/
/// [FileManagerToolbarConfig.folderGridAspectRatios]/`folderSortModes` are
/// keyed by `containerUri:dirPath` (see
/// [FileManagerToolbarConfig.folderKey]) -- genuinely per-container path
/// data, the same category of thing [SettingsBackupService]'s export
/// already leaves out. Encrypting the whole blob is simpler and more
/// robust than trying to selectively encrypt just those three maps while
/// leaving the rest of the config in a plain file.
const _kToolbarConfigBlob = 'file_manager_toolbar_blob_v1';

@Riverpod(keepAlive: true)
FileManagerToolbarService fileManagerToolbarService(Ref ref) =>
    FileManagerToolbarService();

/// Loads/saves the user's customized file-browser action-bar layout (see
/// [FileManagerToolbarConfig]).
///
/// Backed by [AppSecureStorage] (Keystore-backed AES/GCM, see
/// SecureStorageHandlers.kt) rather than a plain JSON file, for the reason
/// given on [_kToolbarConfigBlob] above. Its lifetime is owned by the
/// keep-alive Riverpod provider, making the in-memory cache overridable in
/// tests without a global singleton.
class FileManagerToolbarService {
  FileManagerToolbarService();

  FileManagerToolbarConfig? _cache;

  /// Where this config lived before the switch to [_kToolbarConfigBlob]
  /// above. Consulted only by [_migrateLegacyConfig], once per install, to
  /// move an existing user's toolbar layout (including its per-folder
  /// container-URI/path maps) into the encrypted store; deleted once
  /// migrated so plaintext doesn't linger alongside the encrypted copy.
  static Future<File> get _legacyDataFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/file_manager_toolbar.json');
  }

  /// One-time migration from [_legacyDataFile] to [_kToolbarConfigBlob].
  /// Returns null (caller falls back to [FileManagerToolbarConfig.defaults])
  /// when there's no legacy file -- i.e. this is a fresh install, not an
  /// upgrade, so there's nothing to migrate.
  Future<FileManagerToolbarConfig?> _migrateLegacyConfig() async {
    final legacy = await _legacyDataFile;
    if (!await legacy.exists()) return null;
    final raw =
        jsonDecode(await legacy.readAsString()) as Map<String, dynamic>;
    final config = FileManagerToolbarConfig.fromJson(raw);
    await _secure.write(
      key: _kToolbarConfigBlob,
      value: jsonEncode(config.toJson()),
    );
    try {
      await legacy.delete();
    } catch (_) {
      // Best-effort: the encrypted copy written above is the source of
      // truth from here on regardless (load checks it first, every time),
      // so a failed delete only leaves a stale, never-read plaintext file
      // (with its container URIs and folder paths) behind rather than
      // losing anything.
    }
    return config;
  }

  /// The first read, while it is still running. The file browser asks for
  /// the config from two places at the same moment on open; sharing one read
  /// means one decrypt instead of two.
  Future<FileManagerToolbarConfig>? _loading;

  Future<FileManagerToolbarConfig> load() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _loading ??= _readFromStorage().whenComplete(() {
      _loading = null;
    });
  }

  Future<FileManagerToolbarConfig> _readFromStorage() async {
    try {
      final blob = await _secure.read(key: _kToolbarConfigBlob);
      if (blob != null) {
        _cache = FileManagerToolbarConfig.fromJson(
          jsonDecode(blob) as Map<String, dynamic>,
        );
      } else {
        _cache =
            await _migrateLegacyConfig() ?? FileManagerToolbarConfig.defaults();
      }
    } catch (_) {
      _cache = FileManagerToolbarConfig.defaults();
    }
    return _cache!;
  }

  Future<void> save(FileManagerToolbarConfig config) async {
    _cache = config;
    try {
      await _secure.write(
        key: _kToolbarConfigBlob,
        value: jsonEncode(config.toJson()),
      );
    } catch (_) {
      // _cache above already reflects the new config for this session; a
      // failed write here only risks it not surviving an app restart.
    }
  }

  /// Forces the next [load] to re-read from persisted (encrypted) storage.
  void invalidate() => _cache = null;
}
