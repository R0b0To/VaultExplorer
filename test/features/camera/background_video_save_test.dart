import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/camera/background_video_save.dart';
import 'package:vaultexplorer/features/camera/camera_vault_service.dart';

class _FakeFileIoApi extends VaultFileIoApi {
  _FakeFileIoApi({this.listing = const []})
    : super(const MethodChannel('test/file-io'));

  final List<String> listing;
  final deleted = <String>[];

  @override
  Future<List<String>?> listDirectory(
    MountedContainer container,
    String dirPath, {
    bool refresh = false,
  }) async => listing;

  @override
  Future<bool> deleteFile(MountedContainer container, String fileName) async {
    deleted.add(fileName);
    return true;
  }
}

class _FakeLifecycleApi extends VaultLifecycleApi {
  _FakeLifecycleApi({this.finishWriteResult = true})
    : super(const MethodChannel('test/lifecycle'), VaultEngineEvents());

  final bool finishWriteResult;

  @override
  Future<bool> finishWrite(MountedContainer container, String fileName) async =>
      finishWriteResult;
}

MountedContainer _container({String format = 'veracrypt'}) => MountedContainer(
  volId: 7,
  uri: 'file:///vault.hc',
  displayName: 'Vault',
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000000,
  freeSpace: 500000,
  containerFormat: format,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/camera');
  late List<String> calls;
  late Map<String, Object?> lastSaveArgs;
  var saveResult = <String, Object?>{'success': true, 'cancelled': false};

  setUp(() {
    calls = [];
    lastSaveArgs = {};
    saveResult = {'success': true, 'cancelled': false};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'trimVideo':
              return {'videoPath': '/cache/trimmed.mp4'};
            case 'saveVideoToVault':
              lastSaveArgs = Map<String, Object?>.from(call.arguments as Map);
              return saveResult;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  BackgroundVideoSave job({
    required _FakeFileIoApi fileIo,
    _FakeLifecycleApi? lifecycle,
    MountedContainer? container,
    int trimStartMs = 0,
    int trimEndMs = 10000,
    int durationMs = 10000,
  }) {
    final c = container ?? _container();
    return BackgroundVideoSave(
      container: c,
      vaultService: CameraVaultService(
        container: c,
        targetDirPath: 'DCIM',
        fileIoApi: fileIo,
        lifecycleApi: lifecycle ?? _FakeLifecycleApi(),
      ),
      fileIoApi: fileIo,
      videoPath: '/cache/vx_vid_1.mp4',
      virtualPath: 'DCIM/VID_1.mp4',
      trimStartMs: trimStartMs,
      trimEndMs: trimEndMs,
      durationMs: durationMs,
      failureMessage: 'Failed',
    );
  }

  group('BackgroundVideoSave.estimateBytes', () {
    test('untrimmed clip keeps its full size', () {
      expect(
        BackgroundVideoSave.estimateBytes(
          sourceBytes: 1000,
          trimStartMs: 0,
          trimEndMs: 10000,
          durationMs: 10000,
        ),
        1000,
      );
    });

    test('trimmed clip is scaled by the kept share of the duration', () {
      expect(
        BackgroundVideoSave.estimateBytes(
          sourceBytes: 1000,
          trimStartMs: 2500,
          trimEndMs: 7500,
          durationMs: 10000,
        ),
        500,
      );
    });

    test('an unset end means "to the end of the clip"', () {
      expect(
        BackgroundVideoSave.estimateBytes(
          sourceBytes: 1000,
          trimStartMs: 5000,
          trimEndMs: 0,
          durationMs: 10000,
        ),
        500,
      );
    });

    test('unknown duration falls back to the source size', () {
      expect(
        BackgroundVideoSave.estimateBytes(
          sourceBytes: 1000,
          trimStartMs: 0,
          trimEndMs: 0,
          durationMs: 0,
        ),
        1000,
      );
    });
  });

  group('BackgroundVideoSave.run', () {
    test('saves, passes the operation id and wipes the recording', () async {
      final count = await job(fileIo: _FakeFileIoApi()).run(42);

      expect(count, 1);
      expect(calls, ['saveVideoToVault', 'discardVideo']);
      expect(lastSaveArgs['opId'], 42);
      expect(lastSaveArgs['volId'], 7);
      expect(lastSaveArgs['virtualPath'], 'DCIM/VID_1.mp4');
      expect(lastSaveArgs['videoPath'], '/cache/vx_vid_1.mp4');
    });

    test('trims first and saves the trimmed file', () async {
      await job(
        fileIo: _FakeFileIoApi(),
        trimStartMs: 1000,
        trimEndMs: 5000,
      ).run(1);

      expect(calls, ['trimVideo', 'saveVideoToVault', 'discardVideo']);
      expect(lastSaveArgs['videoPath'], '/cache/trimmed.mp4');
    });

    test('a failed write throws SAVE_FAILED, removes the partial file '
        'and still wipes the recording', () async {
      saveResult = {'success': false, 'cancelled': false};
      final fileIo = _FakeFileIoApi();

      await expectLater(
        job(fileIo: fileIo).run(1),
        throwsA(
          isA<PlatformException>()
              .having((e) => e.code, 'code', 'SAVE_FAILED')
              .having((e) => e.message, 'message', 'Failed'),
        ),
      );
      expect(fileIo.deleted, ['DCIM/VID_1.mp4']);
      expect(calls.last, 'discardVideo');
    });

    test('a cancelled write throws CANCELLED so the operation shows as '
        'cancelled rather than failed', () async {
      saveResult = {'success': false, 'cancelled': true};
      final fileIo = _FakeFileIoApi();

      await expectLater(
        job(fileIo: fileIo).run(1),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'CANCELLED'),
        ),
      );
      expect(fileIo.deleted, ['DCIM/VID_1.mp4']);
      expect(calls.last, 'discardVideo');
    });

    test('a failed finalize on a folder vault is a failed save', () async {
      final fileIo = _FakeFileIoApi();

      await expectLater(
        job(
          fileIo: fileIo,
          container: _container(format: 'cryptomator'),
          lifecycle: _FakeLifecycleApi(finishWriteResult: false),
        ).run(1),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'SAVE_FAILED'),
        ),
      );
      expect(fileIo.deleted, ['DCIM/VID_1.mp4']);
      expect(calls.last, 'discardVideo');
    });
  });

  group('CameraVaultService.nextAvailableName', () {
    test('skips names reserved by saves that are still in flight', () async {
      final fileIo = _FakeFileIoApi();
      final service = CameraVaultService(
        container: _container(),
        targetDirPath: 'DCIM',
        fileIoApi: fileIo,
        lifecycleApi: _FakeLifecycleApi(),
      );

      final first = await service.nextAvailableName(isPhoto: false);
      final second = await service.nextAvailableName(
        isPhoto: false,
        reserved: {first},
      );

      expect(second, isNot(first));
      expect(second, startsWith('VID_'));
    });
  });
}
