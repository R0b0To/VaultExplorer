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

class _CollidingFileIoApi extends VaultFileIoApi {
  _CollidingFileIoApi(this.entries) : super(const MethodChannel('test/file-io'));

  final List<String> entries;

  @override
  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async => entries;
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

    group('nextAvailableAudioName', () {
      CameraVaultService serviceWith(List<String> entries) => CameraVaultService(
        container: _container(),
        targetDirPath: '',
        fileIoApi: _CollidingFileIoApi(entries),
        lifecycleApi: _FakeLifecycleApi(),
      );

      test('stamps the name with the given start time', () async {
        final name = await serviceWith(const []).nextAvailableAudioName(
          at: DateTime(2026, 3, 4, 5, 6, 7),
        );
        expect(name, 'AUD_20260304_050607.m4a');
      });

      test('defaults to an AUD_ prefix and .m4a extension', () async {
        final name = await serviceWith(const []).nextAvailableAudioName();
        expect(name, matches(RegExp(r'^AUD_\d{8}_\d{6}\.m4a$')));
      });

      test('adds a counter when the name is already taken', () async {
        final at = DateTime(2026, 3, 4, 5, 6, 7);
        final name = await serviceWith(const [
          'F|100|1000|AUD_20260304_050607.m4a',
          'F|100|1000|AUD_20260304_050607_1.m4a',
        ]).nextAvailableAudioName(at: at);
        expect(name, 'AUD_20260304_050607_2.m4a');
      });

      test('leaves photo and video naming unchanged', () async {
        final service = serviceWith(const []);
        expect(await service.nextAvailableName(isPhoto: true), startsWith('IMG_'));
        expect(await service.nextAvailableName(isPhoto: false), endsWith('.mp4'));
      });
    });
  });
}
