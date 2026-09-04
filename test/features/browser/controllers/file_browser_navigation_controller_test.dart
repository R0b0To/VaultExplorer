// ignore: depend_on_referenced_packages
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';
import 'package:vaultexplorer/data/models/browser_layout_mode.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart';

MountedContainer _testContainer(int volId) => MountedContainer(
      volId: volId,
      uri: 'file:///vault$volId.hc',
      displayName: 'Vault $volId',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
      containerFormat: 'veracrypt',
    );

/// Builds a minimal valid in-memory zip (one file, one subfolder with a
/// file in it) so archive-open tests can exercise the real
/// ArchiveService/ArchiveContext parsing path rather than a fake.
Uint8List _testArchiveBytes() {
  final archive = Archive();
  archive.addFile(
    ArchiveFile.string('readme.txt', 'hello from the archive'),
  );
  archive.addFile(
    ArchiveFile.string('sub/nested.txt', 'nested file contents'),
  );
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;

  // Per-test overrides the mock handler can read without needing a new
  // handler installed per test.
  List<String>? dirListingResponse;
  Object? dirListingError;
  List<int>? spaceInfoResponse;
  Uint8List? archiveBytesResponse;
  Object? archiveFileError;

  setUp(() {
    dirListingResponse = null;
    dirListingError = null;
    spaceInfoResponse = null;
    archiveBytesResponse = null;
    archiveFileError = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'listDirectory':
          if (dirListingError != null) throw dirListingError!;
          return dirListingResponse ?? <String>[];
        case 'getSpaceInfo':
          return spaceInfoResponse;
        case 'getFileSize':
          if (archiveFileError != null) throw archiveFileError!;
          return archiveBytesResponse?.length ?? 0;
        case 'readFileChunk':
          if (archiveFileError != null) throw archiveFileError!;
          return archiveBytesResponse;
        case ChannelMethods.archiveScanVault:
        case ChannelMethods.archiveScanLocal:
          if (archiveFileError != null) throw archiveFileError!;
          final entries = <Map<String, dynamic>>[];
          if (archiveBytesResponse != null) {
            final zip = ZipDecoder().decodeBytes(archiveBytesResponse!);
            final dirs = <String>{};
            int index = 0;
            for (final f in zip) {
              final path = f.name;
              entries.add({
                'index': index++,
                'path': path,
                'name': path.split('/').last,
                'isDirectory': f.isDirectory,
                'isDir': f.isDirectory,
                'size': f.size,
                'sizeBytes': f.size,
                'compressedSize': f.size,
                'modifiedSecs': 0,
                'modified': 0,
                'isEncrypted': false,
              });
              final parts = path.split('/');
              if (parts.length > 1) {
                dirs.add(parts.first);
              }
            }
            for (final d in dirs) {
              if (!entries.any((e) => e['path'] == d)) {
                entries.add({
                  'index': index++,
                  'path': d,
                  'name': d,
                  'isDirectory': true,
                  'isDir': true,
                  'size': 0,
                  'sizeBytes': 0,
                  'compressedSize': 0,
                  'modifiedSecs': 0,
                  'modified': 0,
                  'isEncrypted': false,
                });
              }
            }
          }
          return {
            'status': ArchiveOpenStatus.ok.index, // 0 as int
            'errorMessage': '',
            'isSolid': false,
            'entries': entries.isNotEmpty
                ? entries
                : [
                    {
                      'index': 0,
                      'path': 'readme.txt',
                      'name': 'readme.txt',
                      'isDirectory': false,
                      'isDir': false,
                      'size': 23,
                      'sizeBytes': 23,
                      'compressedSize': 23,
                      'modifiedSecs': 0,
                      'modified': 0,
                      'isEncrypted': false,
                    },
                    {
                      'index': 1,
                      'path': 'sub',
                      'name': 'sub',
                      'isDirectory': true,
                      'isDir': true,
                      'size': 0,
                      'sizeBytes': 0,
                      'compressedSize': 0,
                      'modifiedSecs': 0,
                      'modified': 0,
                      'isEncrypted': false,
                    },
                    {
                      'index': 2,
                      'path': 'sub/nested.txt',
                      'name': 'nested.txt',
                      'isDirectory': false,
                      'isDir': false,
                      'size': 20,
                      'sizeBytes': 20,
                      'compressedSize': 20,
                      'modifiedSecs': 0,
                      'modified': 0,
                      'isEncrypted': false,
                    },
                  ],
          };
      }
      return null;
    });

    container = ProviderContainer();
    ArchiveService.configure(
      container.read(vaultFileIoApiProvider),
      container.read(vaultArchiveApiProvider),
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('FileBrowserNavigation Controller Tests', () {
    test('initRoot seeds a single root path segment', () {
      final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
      notifier.initRoot(rootLabel: 'Vault');

      final state = container.read(fileBrowserNavigationProvider(1));
      expect(state.pathStack, hasLength(1));
      expect(state.pathStack.first.label, 'Vault');
      expect(state.pathStack.first.fatPath, '');
      expect(state.atRoot, isTrue);
      expect(state.currentDirPath, '');
    });

    test('initRoot is a no-op once the stack is already seeded', () {
      final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
      notifier.initRoot(rootLabel: 'Vault');
      notifier.enterDirectory(
        const RawEntry(name: 'docs', isDir: true, sizeBytes: 0, modifiedSecs: 0),
        newPath: 'docs',
      );
      notifier.initRoot(rootLabel: 'Should not reset');

      final state = container.read(fileBrowserNavigationProvider(1));
      expect(state.pathStack, hasLength(2));
      expect(state.pathStack.first.label, 'Vault');
    });

    group('path stack push/pop', () {
      test('enterDirectory pushes a segment and marks loading', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        const entry = RawEntry(name: 'Photos', isDir: true, sizeBytes: 0, modifiedSecs: 0);
        notifier.enterDirectory(entry, newPath: 'Photos');

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(state.pathStack, hasLength(2));
        expect(state.pathStack.last.label, 'Photos');
        expect(state.pathStack.last.fatPath, 'Photos');
        expect(state.currentDirPath, 'Photos');
        expect(state.atRoot, isFalse);
        expect(state.isLoading, isTrue);
        expect(state.currentItems, isEmpty);
        expect(state.currentFilter, isNull);
      });

      test('enterDirectory captures the parent listing as a back-gesture preview', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        dirListingResponse = ['F|1|1|root-file.txt'];
        await notifier.loadDirectoryContents(_testContainer(1), '');

        const entry = RawEntry(name: 'Photos', isDir: true, sizeBytes: 0, modifiedSecs: 0);
        notifier.enterDirectory(entry, newPath: 'Photos');

        final enteredSegment = container.read(fileBrowserNavigationProvider(1)).pathStack.last;
        expect(enteredSegment.previewItems?.map((e) => e.name), ['root-file.txt']);
        expect(enteredSegment.previewLayoutMode, BrowserLayoutMode.list);

        subscription.close();
      });

      test('navigateUp pops the stack and returns the new path', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        notifier.enterDirectory(
          const RawEntry(name: 'Photos', isDir: true, sizeBytes: 0, modifiedSecs: 0),
          newPath: 'Photos',
        );

        final returned = notifier.navigateUp();

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(returned, '');
        expect(state.pathStack, hasLength(1));
        expect(state.currentDirPath, '');
        expect(state.atRoot, isTrue);
        expect(state.isLoading, isTrue);
      });

      test('navigateUp at root is a no-op and returns null', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        final returned = notifier.navigateUp();

        expect(returned, isNull);
        expect(container.read(fileBrowserNavigationProvider(1)).pathStack, hasLength(1));
      });

      test('jumpTo truncates the stack to the target index', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        notifier.enterDirectory(
          const RawEntry(name: 'A', isDir: true, sizeBytes: 0, modifiedSecs: 0),
          newPath: 'A',
        );
        notifier.enterDirectory(
          const RawEntry(name: 'B', isDir: true, sizeBytes: 0, modifiedSecs: 0),
          newPath: 'A/B',
        );

        final returned = notifier.jumpTo(0);

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(returned, '');
        expect(state.pathStack, hasLength(1));
      });

      test('jumpTo at the current (last) index is a no-op and returns null', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        notifier.enterDirectory(
          const RawEntry(name: 'A', isDir: true, sizeBytes: 0, modifiedSecs: 0),
          newPath: 'A',
        );

        expect(notifier.jumpTo(1), isNull);
        expect(notifier.jumpTo(5), isNull);
        expect(notifier.jumpTo(-1), isNull);
      });
    });

    group('directory loading, error status, space updates', () {
      test('loadDirectoryContents populates currentItems and clears isLoading', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        dirListingResponse = ['F|100|1000|file1.txt', 'D|0|1000|Photos'];

        await notifier.loadDirectoryContents(_testContainer(1), '');

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(state.isLoading, isFalse);
        expect(state.currentItems, hasLength(2));
        expect(state.currentItems.map((e) => e.name), containsAll(['file1.txt', 'Photos']));
        expect(state.isListingTruncated, isFalse);

        subscription.close();
      });

      test('loadDirectoryContents filters System: sentinel entries and flags truncation', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        dirListingResponse = ['F|100|1000|file1.txt', 'System:TRUNCATED'];

        await notifier.loadDirectoryContents(_testContainer(1), '');

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(state.currentItems, hasLength(1));
        expect(state.isListingTruncated, isTrue);

        subscription.close();
      });

      test('loadDirectoryContents surfaces failures by rethrowing, not by setting status', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        dirListingError = PlatformException(code: 'ERR', message: 'boom');

        await expectLater(
          () => notifier.loadDirectoryContents(_testContainer(1), ''),
          throwsA(isA<PlatformException>()),
        );

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(state.isLoading, isFalse);
        expect(state.statusMessage, isNull);

        subscription.close();
      });

      test('loadDirectoryContents updates freeSpace from a valid space-info response', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        dirListingResponse = [];
        spaceInfoResponse = [1000000, 250000];

        await notifier.loadDirectoryContents(_testContainer(1), '');
        await Future<void>.delayed(Duration.zero);

        expect(container.read(fileBrowserNavigationProvider(1)).freeSpace, 250000);

        subscription.close();
      });

      test('loadDirectoryContents ignores a stale space-info response after a newer load started', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        dirListingResponse = [];
        spaceInfoResponse = [1000000, 999];
        await notifier.loadDirectoryContents(_testContainer(1), '');

        spaceInfoResponse = [1000000, 111];
        await notifier.loadDirectoryContents(_testContainer(1), '');
        await Future<void>.delayed(Duration.zero);

        expect(container.read(fileBrowserNavigationProvider(1)).freeSpace, 111);

        subscription.close();
      });

      test('setFreeSpace/setLoading/setStatus/setFilter/setContainerLocked set state directly', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);

        notifier.setFreeSpace(42);
        expect(container.read(fileBrowserNavigationProvider(1)).freeSpace, 42);
        notifier.setFreeSpace(null);
        expect(container.read(fileBrowserNavigationProvider(1)).freeSpace, isNull);

        notifier.setLoading(true);
        expect(container.read(fileBrowserNavigationProvider(1)).isLoading, isTrue);

        notifier.setStatus('failed', error: true);
        var state = container.read(fileBrowserNavigationProvider(1));
        expect(state.statusMessage, 'failed');
        expect(state.statusIsError, isTrue);
        notifier.clearStatus();
        state = container.read(fileBrowserNavigationProvider(1));
        expect(state.statusMessage, isNull);
        expect(state.statusIsError, isFalse);

        notifier.setFilter('rep');
        expect(container.read(fileBrowserNavigationProvider(1)).currentFilter, 'rep');
        notifier.setFilter(null);
        expect(container.read(fileBrowserNavigationProvider(1)).currentFilter, isNull);

        notifier.setContainerLocked(true);
        expect(container.read(fileBrowserNavigationProvider(1)).isContainerLocked, isTrue);
      });

      test('removeItemsByName drops matching entries case-insensitively', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        dirListingResponse = ['F|1|1|Keep.txt', 'F|1|1|Delete.txt'];
        await notifier.loadDirectoryContents(_testContainer(1), '');

        notifier.removeItemsByName({'delete.txt'});

        final names = container.read(fileBrowserNavigationProvider(1)).currentItems.map((e) => e.name);
        expect(names, ['Keep.txt']);

        subscription.close();
      });
    });

    group('archive opening, navigation, and exit', () {
      test('openArchive parses a real zip and lists its root', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        archiveBytesResponse = _testArchiveBytes();

        await notifier.openArchive(_testContainer(1), 'backup.zip', 'backup.zip');

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(state.archiveContext, isNotNull);
        expect(state.pathStack, hasLength(2));
        expect(state.pathStack.last.isArchiveRoot, isTrue);
        expect(state.currentDirPath, 'backup.zip');
        expect(state.isLoading, isFalse);
        expect(state.currentItems.map((e) => e.name), containsAll(['readme.txt', 'sub']));

        subscription.close();
      });

      test('navigating into an archive subfolder lists that subfolder', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        archiveBytesResponse = _testArchiveBytes();
        await notifier.openArchive(_testContainer(1), 'backup.zip', 'backup.zip');

        notifier.enterDirectory(
          const RawEntry(name: 'sub', isDir: true, sizeBytes: 0, modifiedSecs: 0),
          newPath: 'backup.zip/sub',
        );
        await notifier.loadDirectoryContents(_testContainer(1), 'backup.zip/sub');

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(state.currentItems.map((e) => e.name), ['nested.txt']);

        subscription.close();
      });

      test('closeArchive disposes and clears the archive context', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        archiveBytesResponse = _testArchiveBytes();
        await notifier.openArchive(_testContainer(1), 'backup.zip', 'backup.zip');
        expect(container.read(fileBrowserNavigationProvider(1)).archiveContext, isNotNull);

        notifier.closeArchive();

        expect(container.read(fileBrowserNavigationProvider(1)).archiveContext, isNull);

        subscription.close();
      });

      test('navigateUp out of an open archive closes it', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        archiveBytesResponse = _testArchiveBytes();
        await notifier.openArchive(_testContainer(1), 'backup.zip', 'backup.zip');

        notifier.navigateUp();

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(state.archiveContext, isNull);
        expect(state.atRoot, isTrue);

        subscription.close();
      });

      test('navigateToPath closes an open archive before rebuilding the stack', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        archiveBytesResponse = _testArchiveBytes();
        await notifier.openArchive(_testContainer(1), 'backup.zip', 'backup.zip');

        notifier.navigateToPath(_testContainer(1), 'Elsewhere', isDir: true, rootLabel: 'Vault');

        expect(container.read(fileBrowserNavigationProvider(1)).archiveContext, isNull);

        subscription.close();
      });

      test('a failed archive open rethrows and clears isLoading', () async {
        final subscription = container.listen(fileBrowserNavigationProvider(1), (_, _) {});
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        archiveFileError = PlatformException(code: 'READ_FAIL', message: 'Failed to read archive');

        await expectLater(
          () => notifier.openArchive(_testContainer(1), 'backup.zip', 'backup.zip'),
          throwsA(isA<PlatformException>()),
        );

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(state.isLoading, isFalse);
        expect(state.archiveContext, isNull);

        subscription.close();
      });
    });

    group('deep path navigation (navigateToPath)', () {
      test('navigateToPath for a folder rebuilds the full stack and returns the path', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        final returned = notifier.navigateToPath(
          _testContainer(1),
          'A/B/C',
          isDir: true,
          rootLabel: 'Vault',
        );

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(returned, 'A/B/C');
        expect(state.pathStack.map((s) => s.label), ['Vault', 'A', 'B', 'C']);
        expect(state.pathStack.map((s) => s.fatPath), ['', 'A', 'A/B', 'A/B/C']);
        expect(state.currentDirPath, 'A/B/C');
      });

      test('navigateToPath for a file rebuilds the stack to the parent and returns the parent path', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        final returned = notifier.navigateToPath(
          _testContainer(1),
          'A/B/document.txt',
          isDir: false,
          rootLabel: 'Vault',
        );

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(returned, 'A/B');
        expect(state.pathStack.map((s) => s.label), ['Vault', 'A', 'B']);
        expect(state.currentDirPath, 'A/B');
      });

      test('navigateToPath for a root-level file returns an empty parent path', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        final returned = notifier.navigateToPath(
          _testContainer(1),
          'document.txt',
          isDir: false,
          rootLabel: 'Vault',
        );

        expect(returned, '');
        expect(container.read(fileBrowserNavigationProvider(1)).pathStack, hasLength(1));
      });
    });

    group('back-gesture preview transitions and cancellations', () {
      test('startBackGesture at root returns false and leaves state untouched', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');

        expect(notifier.startBackGesture(0.1), isFalse);
        expect(container.read(fileBrowserNavigationProvider(1)).backGestureProgress, isNull);
      });

      test('startBackGesture captures the parent preview and target path', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        notifier.enterDirectory(
          const RawEntry(name: 'A', isDir: true, sizeBytes: 0, modifiedSecs: 0),
          newPath: 'A',
        );

        final started = notifier.startBackGesture(0.2);

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(started, isTrue);
        expect(state.backGestureProgress, 0.2);
        expect(state.backGesturePreviewDirPath, '');
        expect(state.backGesturePreviewAtRoot, isTrue);
      });

      test('updateBackGestureProgress updates only the progress value', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        notifier.enterDirectory(
          const RawEntry(name: 'A', isDir: true, sizeBytes: 0, modifiedSecs: 0),
          newPath: 'A',
        );
        notifier.startBackGesture(0.1);

        notifier.updateBackGestureProgress(0.7);

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(state.backGestureProgress, 0.7);
        expect(state.backGesturePreviewDirPath, '');
      });

      test('cancelBackGesture and clearBackGesturePreview both clear all preview fields', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        notifier.enterDirectory(
          const RawEntry(name: 'A', isDir: true, sizeBytes: 0, modifiedSecs: 0),
          newPath: 'A',
        );
        notifier.startBackGesture(0.5);

        notifier.cancelBackGesture();
        var state = container.read(fileBrowserNavigationProvider(1));
        expect(state.backGestureProgress, isNull);
        expect(state.backGesturePreviewDirPath, isNull);
        expect(state.backGesturePreviewAtRoot, isFalse);

        notifier.startBackGesture(0.5);
        notifier.clearBackGesturePreview();
        state = container.read(fileBrowserNavigationProvider(1));
        expect(state.backGestureProgress, isNull);
      });

      test('commitBackGesture snaps progress to 1.0 without clearing the preview', () {
        final notifier = container.read(fileBrowserNavigationProvider(1).notifier);
        notifier.initRoot(rootLabel: 'Vault');
        notifier.enterDirectory(
          const RawEntry(name: 'A', isDir: true, sizeBytes: 0, modifiedSecs: 0),
          newPath: 'A',
        );
        notifier.startBackGesture(0.5);

        notifier.commitBackGesture();

        final state = container.read(fileBrowserNavigationProvider(1));
        expect(state.backGestureProgress, 1.0);
        expect(state.backGesturePreviewDirPath, '');
      });
    });

    test('state is isolated per volId', () {
      final notifier1 = container.read(fileBrowserNavigationProvider(1).notifier);
      final notifier2 = container.read(fileBrowserNavigationProvider(2).notifier);

      notifier1.initRoot(rootLabel: 'Vault 1');
      notifier2.initRoot(rootLabel: 'Vault 2');
      notifier1.enterDirectory(
        const RawEntry(name: 'OnlyIn1', isDir: true, sizeBytes: 0, modifiedSecs: 0),
        newPath: 'OnlyIn1',
      );
      notifier1.setContainerLocked(true);

      final state1 = container.read(fileBrowserNavigationProvider(1));
      final state2 = container.read(fileBrowserNavigationProvider(2));

      expect(state1.pathStack.first.label, 'Vault 1');
      expect(state1.pathStack, hasLength(2));
      expect(state1.isContainerLocked, isTrue);

      expect(state2.pathStack.first.label, 'Vault 2');
      expect(state2.pathStack, hasLength(1));
      expect(state2.isContainerLocked, isFalse);
    });
  });
}