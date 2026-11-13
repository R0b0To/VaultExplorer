import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/vault_symlink.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

MountedContainer cryptomatorContainer({bool readOnly = false, String format = 'cryptomator'}) =>
    MountedContainer(
      uri: 'content://tree/vault',
      displayName: 'Vault',
      volId: 7,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      containerFormat: format,
      readOnly: readOnly,
    );

VaultSymlink link(String name) =>
    VaultSymlink(name: name, targetBytes: 6, modifiedSecs: 0);

/// An in-memory stand-in for the symlink-related part of [VaultFileIoApi].
class FakeSymlinkFileIo implements VaultFileIoApi {
  List<VaultSymlink> links = [];

  /// What [hiddenEntryCount] reports; the notice banner only shows while this is above zero.
  int hidden = 0;
  int listCalls = 0;
  bool createResult = true;
  bool deleteResult = true;
  bool renameResult = true;
  final List<(String, String)> created = [];
  final List<String> deleted = [];
  final List<(String, String)> renamed = [];

  @override
  Future<List<VaultSymlink>> listVaultSymlinks(MountedContainer container, String dirPath) async {
    listCalls++;
    return List.of(links);
  }

  /// What [resolveVaultPhysicalPath] answers, keyed by the path (or "path|nofollow" for followLast: false).
  /// Anything not listed resolves to itself.
  final Map<String, String?> physical = {};
  final List<(String, bool)> physicalCalls = [];

  /// Raw listing lines the target picker sees, keyed by folder.
  final Map<String, List<String>> browserListings = {};

  @override
  Future<String?> resolveVaultPhysicalPath(
    MountedContainer container,
    String path, {
    bool followLast = true,
  }) async {
    physicalCalls.add((path, followLast));
    final key = followLast ? path : '$path|nofollow';
    return physical.containsKey(key) ? physical[key] : path;
  }

  @override
  Future<List<String>?> listDirectoryForBrowser(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async => browserListings[dirPath] ?? const [];

  @override
  Future<int> hiddenEntryCount(MountedContainer container, String dirPath) async => hidden;

  @override
  Future<String?> readVaultSymlink(MountedContainer container, String path) async => 'target-of-$path';

  @override
  Future<bool> createVaultSymlink(MountedContainer container, String path, String target) async {
    created.add((path, target));
    return createResult;
  }

  @override
  Future<bool> deleteFile(MountedContainer container, String fileName) async {
    deleted.add(fileName);
    if (deleteResult) links.removeWhere((l) => fileName == l.name || fileName.endsWith('/${l.name}'));
    return deleteResult;
  }

  @override
  Future<bool> renameFile(MountedContainer container, String oldPath, String newPath) async {
    renamed.add((oldPath, newPath));
    if (renameResult) {
      final oldName = oldPath.split('/').last;
      final newName = newPath.split('/').last;
      links = [for (final l in links) l.name == oldName ? link(newName) : l];
    }
    return renameResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records content-change notifications and lets a test fire them to the registered listeners.
class FakeOperationService implements FileOperationService {
  final List<int> notified = [];
  final List<void Function(VolumeContentChange)> listeners = [];

  @override
  void addVolumeContentChangedListener(void Function(VolumeContentChange change) listener) =>
      listeners.add(listener);

  @override
  void removeVolumeContentChangedListener(void Function(VolumeContentChange change) listener) =>
      listeners.remove(listener);

  @override
  void notifyVolumeContentChanged(int volId) {
    notified.add(volId);
    for (final l in List.of(listeners)) {
      l(VolumeContentChange(volId: volId, opId: 0));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
