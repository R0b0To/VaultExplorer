import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

MountedContainer _container({int volId = 1}) => MountedContainer(
  uri: 'content://test-container',
  displayName: 'Test Vault',
  volId: volId,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 100000000,
  freeSpace: 50000000,
);

class _RecordingFileIoApi extends VaultFileIoApi {
  _RecordingFileIoApi() : super(const MethodChannel('test/file-operation'));

  final cancelledImportIds = <int>[];

  @override
  Future<void> cancelImport(int opId) async {
    cancelledImportIds.add(opId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  final l10n = AppLocalizationsEn();
  late FileOperationService opSvc;

  setUp(() {
    final engineEvents = VaultEngineEvents()..registerHandler(channel);
    opSvc = FileOperationService.withEngineEvents(engineEvents);
  });

  group('RawEntry placeholder property', () {
    test('defaults isPlaceholder to false', () {
      final entry = RawEntry(
        name: 'file.txt',
        isDir: false,
        sizeBytes: 0,
        modifiedSecs: 0,
      );
      expect(entry.isPlaceholder, isFalse);
    });

    test('supports isPlaceholder: true', () {
      final entry = RawEntry(
        name: 'importing_photo.png',
        isDir: false,
        sizeBytes: 2048,
        modifiedSecs: 1700000000,
        isPlaceholder: true,
      );
      expect(entry.isPlaceholder, isTrue);
      expect(entry.name, 'importing_photo.png');
      expect(entry.sizeBytes, 2048);
    });

    test('equality and hashCode take isPlaceholder into account', () {
      final real = RawEntry(
        name: 'doc.pdf',
        isDir: false,
        sizeBytes: 100,
        modifiedSecs: 0,
        isPlaceholder: false,
      );
      final placeholder = RawEntry(
        name: 'doc.pdf',
        isDir: false,
        sizeBytes: 100,
        modifiedSecs: 0,
        isPlaceholder: true,
      );

      expect(real == placeholder, isFalse);
      expect(real.hashCode == placeholder.hashCode, isFalse);
    });

    test('parse sets isPlaceholder to false', () {
      final entry = RawEntry.parse('F|1024|1700000000|test.dat');
      expect(entry.isPlaceholder, isFalse);
    });
  });

  group('FileOperationService getActivePlaceholders', () {
    test(
      'routes an import cancellation through its injected file I/O API',
      () async {
        final engineEvents = VaultEngineEvents();
        final fileIoApi = _RecordingFileIoApi();
        final service = FileOperationService.withEngineApis(
          engineEvents: engineEvents,
          fileIoApi: fileIoApi,
          lifecycleApi: VaultLifecycleApi(
            const MethodChannel('test/file-operation'),
            engineEvents,
          ),
        );
        final importCompleter = Completer<int>();

        final operation = service.enqueueImport(
          dest: _container(),
          destDirPath: '',
          isFolder: false,
          performImport: (_) => importCompleter.future,
          l10n: l10n,
        );

        operation.requestCancel();
        await Future<void>.delayed(Duration.zero);

        expect(fileIoApi.cancelledImportIds, equals([operation.id]));

        importCompleter.complete(0);
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'returns placeholders for pending items in active import operation',
      () async {
        final dest = _container(volId: 10);

        opSvc.enqueueImport(
          dest: dest,
          destDirPath: 'SubFolder',
          items: [
            const ClipboardItem(path: 'pic1.jpg', isDir: false, sizeBytes: 100),
            const ClipboardItem(path: 'pic2.jpg', isDir: false, sizeBytes: 200),
            const ClipboardItem(path: 'DocsFolder', isDir: true, sizeBytes: 0),
          ],
          isFolder: false,
          performImport: (opId) async => 3,
          l10n: l10n,
        );

        final placeholders = opSvc.getActivePlaceholders(10, 'SubFolder');
        expect(placeholders, hasLength(3));
        expect(placeholders[0].name, 'pic1.jpg');
        expect(placeholders[0].isPlaceholder, isTrue);
        expect(placeholders[0].isDir, isFalse);
        expect(placeholders[1].name, 'pic2.jpg');
        expect(placeholders[1].isPlaceholder, isTrue);
        expect(placeholders[2].name, 'DocsFolder');
        expect(placeholders[2].isDir, isTrue);

        // Placeholders for another directory or volume should be empty
        expect(opSvc.getActivePlaceholders(10, 'OtherFolder'), isEmpty);
        expect(opSvc.getActivePlaceholders(99, 'SubFolder'), isEmpty);
      },
    );

    test('keeps a succeeded item as a placeholder until it is superseded, '
        'but drops one that failed or was skipped', () async {
      final dest = _container(volId: 20);

      // A Completer -- rather than an immediately-resolving async lambda --
      // lets this test control exactly when the overall import "finishes",
      // so the per-item events below are guaranteed to be processed while
      // the operation is still active. This mirrors production: native
      // streams "onImportItemFinished" for each item *before* its final
      // result.success(successCount) call resolves importFiles/importFolder
      // -- an immediately-resolving fake here would instead let the
      // operation's own completion microtask (already queued the moment
      // enqueueImport ran) fire before the simulated platform messages are
      // even dispatched, flipping the op to "completed" first.
      final completer = Completer<int>();
      final op = opSvc.enqueueImport(
        dest: dest,
        destDirPath: 'Photos',
        items: [
          const ClipboardItem(path: 'a.png', isDir: false, sizeBytes: 50),
          const ClipboardItem(path: 'b.png', isDir: false, sizeBytes: 60),
        ],
        isFolder: false,
        performImport: (opId) => completer.future,
        l10n: l10n,
      );

      expect(opSvc.getActivePlaceholders(20, 'Photos'), hasLength(2));

      final messageCodec = const StandardMethodCodec();
      Future<void> sendFinished({
        required String sourceName,
        required String resolvedName,
        required bool success,
      }) {
        final data = messageCodec.encodeMethodCall(
          MethodCall('onImportItemFinished', {
            'opId': op.id,
            'sourceName': sourceName,
            'resolvedName': resolvedName,
            'isDir': false,
            'success': success,
          }),
        );
        return TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'com.aeidolon.vaultexplorer/engine',
              data,
              (b) {},
            );
      }

      // a.png succeeds, but under a conflict-resolved name -- it must stay
      // visible as a placeholder (now under that resolved name) rather than
      // disappearing the instant the transfer finishes: the destination
      // folder's own reload is throttled, so dropping it immediately would
      // leave a gap where the item is neither a placeholder nor yet present
      // in the real listing -- a visible vanish-then-reappear shift.
      await sendFinished(
        sourceName: 'a.png',
        resolvedName: 'a (1).png',
        success: true,
      );
      var current = opSvc.getActivePlaceholders(20, 'Photos');
      expect(current, hasLength(2));
      expect(current.map((e) => e.name), containsAll(['a (1).png', 'b.png']));
      expect(current.every((e) => e.isPlaceholder), isTrue);
      // A still-in-flight item's date is left unset ("—" once formatted)
      // rather than "now", so it doesn't shift width when the real,
      // differently-shaped modified date replaces it later.
      expect(current.every((e) => e.modifiedSecs == 0), isTrue);

      // b.png fails -- no file is ever coming for it, so it's dropped
      // outright rather than lingering as a placeholder forever.
      await sendFinished(
        sourceName: 'b.png',
        resolvedName: 'b.png',
        success: false,
      );
      current = opSvc.getActivePlaceholders(20, 'Photos');
      expect(current, hasLength(1));
      expect(current.single.name, 'a (1).png');

      // Let the operation finish so it doesn't leak into other tests.
      completer.complete(1);
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('Placeholder merging and deduplication logic', () {
    test(
      'deduplicates placeholders whose items are already present in directory listing',
      () {
        final currentItems = [
          RawEntry(
            name: 'existing.txt',
            isDir: false,
            sizeBytes: 10,
            modifiedSecs: 0,
          ),
          RawEntry(
            name: 'imported.png',
            isDir: false,
            sizeBytes: 20,
            modifiedSecs: 0,
          ),
        ];

        final placeholders = [
          RawEntry(
            name: 'imported.png',
            isDir: false,
            sizeBytes: 20,
            modifiedSecs: 0,
            isPlaceholder: true,
          ),
          RawEntry(
            name: 'pending.png',
            isDir: false,
            sizeBytes: 30,
            modifiedSecs: 0,
            isPlaceholder: true,
          ),
        ];

        final existingNamesLower = currentItems
            .map((e) => e.name.toLowerCase())
            .toSet();
        final uniquePlaceholders = placeholders.where(
          (p) => !existingNamesLower.contains(p.name.toLowerCase()),
        );

        final combined = [...currentItems, ...uniquePlaceholders];

        expect(combined, hasLength(3));
        expect(combined.map((e) => e.name).toList(), [
          'existing.txt',
          'imported.png',
          'pending.png',
        ]);
        expect(combined[1].isPlaceholder, isFalse);
        expect(combined[2].isPlaceholder, isTrue);
      },
    );
  });
}
