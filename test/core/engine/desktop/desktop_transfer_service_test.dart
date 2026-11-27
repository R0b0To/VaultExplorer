import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_staging_manager.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_transfer_service.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:ve_desktop_transfer/ve_desktop_transfer.dart';

MountedContainer _vaultContainer({int volId = 2}) => MountedContainer(
  uri: '/containers/secret.hc',
  displayName: 'Secret Vault',
  volId: volId,
  rootFiles: const ['docs'],
  mountedAt: DateTime(2026),
  totalSpace: 1000,
  freeSpace: 500,
);

Future<void> _waitUntil(
  Future<bool> Function() condition, {
  required String description,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!(await condition())) {
    if (stopwatch.elapsed >= timeout) {
      fail('Timed out waiting for $description');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory tempRoot;
  late DesktopStagingManager staging;
  late DesktopTransferService service;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('ve_xfer_svc_test_');
    staging = DesktopStagingManager(baseDirOverride: tempRoot, pidOverride: 5150);
    service = DesktopTransferService.forTesting(staging: staging);
  });

  tearDown(() async {
    await service.dispose();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('createManifest for encrypted vault allocates lazy empty staging batch', () async {
    final vault = _vaultContainer(volId: 4);
    final result = await service.createManifest(
      items: [
        DesktopTransferEntry(
          container: vault,
          vaultPath: 'photos/img.png',
          name: 'img.png',
          isDir: false,
          sizeBytes: 2048,
          modifiedSecs: 1700000000,
        ),
      ],
      isClipboard: false,
      preferVirtualStream: true,
    );

    expect(result, isNotNull);
    expect(result!.batch, isNotNull);
    expect(result.manifest.volId, 4);
    expect(result.manifest.stagingDir, result.batch!.dirPath);
    expect(result.manifest.preferVirtualStream, isTrue);
    expect(result.manifest.isSensitive, isTrue);
    expect(result.manifest.items.single.localPath, isNull);
    expect(result.manifest.items.single.vaultPath, 'photos/img.png');
    expect(result.batch!.realized, isFalse);
  });

  test('createManifest for LocalStorage resolves host paths with zero staging', () async {
    final localRoot = p.join(tempRoot.path, 'local_storage');
    final localContainer = buildLocalStorageContainer(
      rootPath: localRoot,
      displayName: 'Local',
    );

    final result = await service.createManifest(
      items: [
        DesktopTransferEntry(
          container: localContainer,
          vaultPath: 'notes/todo.txt',
          name: 'todo.txt',
          isDir: false,
          sizeBytes: 64,
          modifiedSecs: 1700000000,
        ),
      ],
      isClipboard: true,
      preferVirtualStream: true,
    );

    expect(result, isNotNull);
    expect(result!.batch, isNull);
    expect(staging.activeBatches, isEmpty);
    expect(result.manifest.volId, -1);
    expect(result.manifest.stagingDir, '');
    expect(result.manifest.preferVirtualStream, isFalse);
    expect(result.manifest.isSensitive, isFalse);
    expect(
      result.manifest.items.single.localPath,
      p.normalize(p.join(localRoot, 'notes/todo.txt')),
    );
  });

  test('retainImportPaths pins realized staging batch until released', () async {
    var inUseProbeCalls = 0;
    final fastStaging = DesktopStagingManager(
      baseDirOverride: tempRoot,
      defaultGracePeriod: const Duration(milliseconds: 15),
      drainPollInterval: const Duration(milliseconds: 15),
      pidOverride: 5151,
    );
    final svc = DesktopTransferService.forTesting(staging: fastStaging);
    fastStaging.configurePlatformHooks(
      isBatchInUse: (dirPath) async {
        inUseProbeCalls++;
        return svc.isStagingDirPinned(dirPath);
      },
    );

    final batch = await fastStaging.createBatch(volId: 7, isClipboard: false);
    final stagedFile = File(p.join(batch.dirPath, 'photo.jpg'));
    await stagedFile.writeAsString('image-bytes');

    expect(svc.containsStagedPath([stagedFile.path]), isTrue);
    expect(svc.containsStagedPath([p.join(tempRoot.path, 'external.jpg')]), isFalse);

    final pins = svc.retainImportPaths([stagedFile.path]);
    expect(pins, [batch.dirPath]);
    fastStaging.markRealized(batch.batchId, isDrag: true);
    await fastStaging.onDragTransferFinished(batch.batchId, immediateIfUnused: true);

    await _waitUntil(
      () async => inUseProbeCalls >= 2,
      description: 'the staging pin to be checked by the drain poll',
    );
    expect(await stagedFile.exists(), isTrue);
    expect(inUseProbeCalls, greaterThanOrEqualTo(2));

    svc.releaseImportPaths(pins);
    await _waitUntil(
      () async => !(await stagedFile.exists()),
      description: 'staging cleanup after releasing the import pin',
    );
    expect(await stagedFile.exists(), isFalse);
    await svc.dispose();
  });

  test('encodeClipboardImagePayload decodes 1x1 PNG into RGBA + PNG payload', () async {
    // Valid 1x1 red RGBA PNG.
    final tinyPng = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
    );
    final payload = await DesktopTransferService.encodeClipboardImagePayload(
      Uint8List.fromList(tinyPng),
      sensitive: true,
    );

    expect(payload, isNotNull);
    expect(payload!.width, 1);
    expect(payload.height, 1);
    expect(payload.rgbaBytes.length, 4);
    expect(payload.pngBytes, orderedEquals(tinyPng));
    expect(payload.sensitive, isTrue);
  });

  test('hasExternalClipboardChangedSinceWatermark detects external changes cleanly', () {
    const own = ClipboardInspectResult(
      hasFiles: true,
      isOwnFiles: true,
      ownBatchId: '5150_1',
      filePaths: [],
      hasImage: false,
    );
    expect(service.hasExternalClipboardChangedSinceWatermark(own), isFalse);

    const extFiles = ClipboardInspectResult(
      hasFiles: true,
      isOwnFiles: false,
      ownBatchId: null,
      filePaths: ['C:/Temp/a.txt'],
      hasImage: false,
    );
    expect(service.hasExternalClipboardChangedSinceWatermark(extFiles), isTrue);

    const extImage = ClipboardInspectResult(
      hasFiles: false,
      isOwnFiles: false,
      ownBatchId: null,
      filePaths: [],
      hasImage: true,
    );
    expect(service.hasExternalClipboardChangedSinceWatermark(extImage), isTrue);
  });

  test('pasteImagePngToContainer writes unique PNG to LocalStorage without overwriting collisions', () async {
    final localRoot = Directory(p.join(tempRoot.path, 'local_paste'));
    await localRoot.create(recursive: true);
    final localContainer = buildLocalStorageContainer(
      rootPath: localRoot.path,
      displayName: 'Local',
    );
    final api = const VaultFileIoApi(MethodChannel('ve_test_unused'));
    final pngBytes = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==',
      ),
    );

    final created = await service.pasteImagePngToContainer(
      container: localContainer,
      targetDirPath: 'screenshots',
      fileIoApi: api,
      pngBytes: pngBytes,
    );

    expect(created, isNotNull);
    expect(created!, startsWith('pasted_image_'));
    expect(created, endsWith('.png'));
    final written = File(p.join(localRoot.path, 'screenshots', created));
    expect(await written.exists(), isTrue);
    expect(await written.readAsBytes(), orderedEquals(pngBytes));
  });

  test('isSameOriginDrop matches only recent drag into the same folder', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('vaultexplorer/desktop_transfer');
    String? capturedStagingDir;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'initialize') {
            return <Object?, Object?>{'supported': true, 'backend': 'test'};
          }
          if (call.method == 'startDrag') {
            final manifest = (call.arguments as Map)['manifest'] as Map;
            capturedStagingDir = manifest['stagingDir'] as String?;
            return 'copied';
          }
          return null;
        });

    try {
      final vault = _vaultContainer(volId: 3);
      final svc = DesktopTransferService.forTesting(staging: staging);
      final result = await svc.startOutboundDrag(
        viewId: 0,
        items: [
          DesktopTransferEntry(
            container: vault,
            vaultPath: 'work/doc.pdf',
            name: 'doc.pdf',
            isDir: false,
            sizeBytes: 128,
            modifiedSecs: 1700000000,
          ),
        ],
      );
      expect(result, 'copied');
      expect(capturedStagingDir, isNotNull);
      final stagedPath = p.join(capturedStagingDir!, 'doc.pdf');

      expect(
        svc.isSameOriginDrop([stagedPath], destVolId: 3, destDirPath: 'work'),
        isTrue,
      );
      expect(
        svc.isSameOriginDrop([stagedPath], destVolId: 3, destDirPath: 'other'),
        isFalse,
      );
      expect(
        svc.isSameOriginDrop([stagedPath], destVolId: 4, destDirPath: 'work'),
        isFalse,
      );
      await svc.dispose();
    } finally {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });
}
