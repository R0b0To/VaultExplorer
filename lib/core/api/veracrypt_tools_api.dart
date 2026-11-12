import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

/// A failure of a VeraCrypt volume tool; [message] is already user-readable (it comes from the native layer).
class VeraCryptToolsException implements Exception {
  const VeraCryptToolsException(this.code, this.message);

  final String code;
  final String message;

  bool get isIncorrectPassword => code == 'PASSWORD_INCORRECT';

  @override
  String toString() => message;
}

/// Free space at the end of a standard volume, as measured for a hidden volume.
typedef HiddenHostInfo = ({int fsKind, int clusterSize, int maxHiddenBytes});

/// What happened to the file system inside a volume after an expand / grow request (Kotlin: fsStatusName).
enum FileSystemGrowResult {
  grown,
  alreadyFills,
  unsupported,
  needsCheck,
  failed,
  notRun;

  static FileSystemGrowResult parse(String? name) => switch (name) {
        'grown' => grown,
        'already_fills' => alreadyFills,
        'unsupported' => unsupported,
        'needs_check' => needsCheck,
        'not_run' => notRun,
        _ => failed, // 'failed', 'busy' and anything unknown
      };
}

class FileSystemGrowInfo {
  const FileSystemGrowInfo(this.result, this.fileSystemName);

  factory FileSystemGrowInfo.fromMap(Map<Object?, Object?>? raw) => FileSystemGrowInfo(
        FileSystemGrowResult.parse(raw?['fsStatus'] as String?),
        (raw?['fsName'] as String?) ?? '',
      );

  final FileSystemGrowResult result;

  /// "NTFS", "ext4", "exFAT", ... or empty when the file system wasn't recognised.
  final String fileSystemName;
}

/// Desktop-VeraCrypt volume operations on an existing container: volume expansion and
/// creating a hidden volume inside an existing standard volume ("direct mode").
class VeraCryptToolsApi {
  const VeraCryptToolsApi(this._channel);

  final MethodChannel _channel;

  Future<({String uri, String displayName})?> pickContainer() async {
    final raw = await _channel.invokeMethod<Map<Object?, Object?>>(ChannelMethods.pickContainer);
    if (raw == null) return null;
    return (uri: raw['uri'] as String, displayName: raw['displayName'] as String);
  }

  Future<List<KeyfileRef>> pickKeyfiles() async {
    final raw = await _channel.invokeMethod<List<Object?>>(ChannelMethods.pickKeyfiles);
    if (raw == null) return [];
    return raw
        .cast<Map<Object?, Object?>>()
        .map((m) => (uri: m['uri'] as String, displayName: m['displayName'] as String))
        .toList();
  }

  /// Grows a standard VeraCrypt file container to [newSizeBytes] and, with [growFileSystem], the file system inside
  /// into the added space (NTFS and ext2/3/4; FAT/exFAT can't be grown in place). The container is expanded even when
  /// the file system step reports anything but [FileSystemGrowResult.grown].
  Future<FileSystemGrowInfo> expandContainer({
    required String uri,
    String password = '',
    int pim = 0,
    int cipherId = 255,
    int hashId = 255,
    List<String> keyfilePaths = const [],
    required int newSizeBytes,
    bool initFreeSpace = true,
    bool growFileSystem = true,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(ChannelMethods.expandVeraCryptContainer, {
        'uri': uri,
        'password': password,
        'pim': pim,
        'cipherId': cipherId,
        'hashId': hashId,
        'keyfilePaths': keyfilePaths,
        'newSizeBytes': newSizeBytes,
        'initFreeSpace': initFreeSpace,
        'growFileSystem': growFileSystem,
      });
      return FileSystemGrowInfo.fromMap(raw);
    } on PlatformException catch (e) {
      throw VeraCryptToolsException(e.code, e.message ?? e.code);
    }
  }

  /// Grows only the file system of a standard volume that was expanded earlier, into the space it doesn't use yet.
  Future<FileSystemGrowInfo> growFileSystem({
    required String uri,
    String password = '',
    int pim = 0,
    int cipherId = 255,
    int hashId = 255,
    List<String> keyfilePaths = const [],
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(ChannelMethods.growVeraCryptFileSystem, {
        'uri': uri,
        'password': password,
        'pim': pim,
        'cipherId': cipherId,
        'hashId': hashId,
        'keyfilePaths': keyfilePaths,
      });
      return FileSystemGrowInfo.fromMap(raw);
    } on PlatformException catch (e) {
      throw VeraCryptToolsException(e.code, e.message ?? e.code);
    }
  }

  /// Reads the outer volume's cluster map and returns the largest hidden volume that fits at its end.
  Future<HiddenHostInfo> analyzeHiddenHost({
    required String uri,
    String password = '',
    int pim = 0,
    int cipherId = 255,
    int hashId = 255,
    List<String> keyfilePaths = const [],
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(ChannelMethods.analyzeHiddenVolumeHost, {
        'uri': uri,
        'password': password,
        'pim': pim,
        'cipherId': cipherId,
        'hashId': hashId,
        'keyfilePaths': keyfilePaths,
      });
      return (
        fsKind: (raw?['fsKind'] as num?)?.toInt() ?? 0,
        clusterSize: (raw?['clusterSize'] as num?)?.toInt() ?? 0,
        maxHiddenBytes: (raw?['maxHiddenBytes'] as num?)?.toInt() ?? 0,
      );
    } on PlatformException catch (e) {
      throw VeraCryptToolsException(e.code, e.message ?? e.code);
    }
  }

  /// Adds a hidden volume of [hiddenSizeBytes] to the existing standard volume at [uri].
  Future<void> createHiddenInExisting({
    required String uri,
    String outerPassword = '',
    int outerPim = 0,
    int outerCipherId = 255,
    int outerHashId = 255,
    List<String> outerKeyfilePaths = const [],
    required String hiddenPassword,
    int hiddenPim = 0,
    String hiddenFileSystem = 'exFAT',
    required int hiddenSizeBytes,
    int hiddenCipherId = 0,
    int hiddenHashId = 0,
    List<String> hiddenKeyfilePaths = const [],
    bool quickFormat = false,
  }) async {
    try {
      await _channel.invokeMethod<bool>(ChannelMethods.createHiddenVolumeInExisting, {
        'uri': uri,
        'outerPassword': outerPassword,
        'outerPim': outerPim,
        'outerCipherId': outerCipherId,
        'outerHashId': outerHashId,
        'outerKeyfilePaths': outerKeyfilePaths,
        'hiddenPassword': hiddenPassword,
        'hiddenPim': hiddenPim,
        'hiddenFileSystem': hiddenFileSystem,
        'hiddenSizeBytes': hiddenSizeBytes,
        'hiddenCipherId': hiddenCipherId,
        'hiddenHashId': hiddenHashId,
        'hiddenKeyfilePaths': hiddenKeyfilePaths,
        'quickFormat': quickFormat,
      });
    } on PlatformException catch (e) {
      throw VeraCryptToolsException(e.code, e.message ?? e.code);
    }
  }
}
