import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/camera/camera_vault_service.dart';

class _FakeFileIoApi extends VaultFileIoApi {
  _FakeFileIoApi() : super(const MethodChannel('test/file-io'));

  String? listedPath;

  @override
  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async {
    listedPath = dirPath;
    return const ['F|100|1000|existing.jpg'];
  }
}

class _FakeLifecycleApi extends VaultLifecycleApi {
  _FakeLifecycleApi()
      : super(
          const MethodChannel('test/lifecycle'),
          VaultEngineEvents(),
        );

  String? finalizedPath;

  @override
  Future<bool> finishWrite(MountedContainer container, String fileName) async {
    finalizedPath = fileName;
    return true;
  }
}

MountedContainer _container({String format = 'veracrypt'}) => MountedContainer(
  volId: 1,
  uri: 'file:///vault.hc',
  displayName: 'Vault',
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000000,
  freeSpace: 500000,
  containerFormat: format,
);

void main() {
  group('CameraVaultService', () {
    test('normalizes the target directory for paths and directory reads', () async {
      final fileIoApi = _FakeFileIoApi();
      final service = CameraVaultService(
        container: _container(),
        targetDirPath: '/Camera/2026/',
        fileIoApi: fileIoApi,
        lifecycleApi: _FakeLifecycleApi(),
      );

      expect(service.buildVirtualPath('photo.jpg'), 'Camera/2026/photo.jpg');
      expect(await service.nextAvailableName(isPhoto: true), startsWith('IMG_'));
      expect(fileIoApi.listedPath, 'Camera/2026');
    });

    test('finalizes writes only for filesystem-backed vault formats', () async {
      final lifecycleApi = _FakeLifecycleApi();
      final service = CameraVaultService(
        container: _container(format: 'cryptomator'),
        targetDirPath: '',
        fileIoApi: _FakeFileIoApi(),
        lifecycleApi: lifecycleApi,
      );

      await service.finalizeVaultWrite('camera/photo.jpg');
      expect(lifecycleApi.finalizedPath, 'camera/photo.jpg');
    });
  });
}
