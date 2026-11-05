import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

MountedContainer _vault({
  required int volId,
  required String name,
  bool readOnly = false,
}) => MountedContainer(
  volId: volId,
  uri: 'file:///v$volId.hc',
  displayName: name,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000000,
  freeSpace: 500000,
  containerFormat: 'veracrypt',
  readOnly: readOnly,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;
  late ProviderSubscription<StorageAnalyzerState> subscription;

  // The fake volume: folder path -> wire-format listing.
  //   docs/        report.pdf (300), notes.txt (50)
  //   media/       clip.mp4 (5000), photos/ a.jpg (700), b.png (200)
  //   empty/
  //   cache.tmp (7)
  //   readme (10)
  late Map<String, List<String>> volume;

  setUp(() {
    volume = {
      '': [
        'D|0|0|docs',
        'D|0|0|media',
        'D|0|0|empty',
        'F|7|0|cache.tmp',
        'F|10|0|readme',
      ],
      'docs': ['F|300|0|report.pdf', 'F|50|0|notes.txt'],
      'media': ['F|5000|0|clip.mp4', 'D|0|0|photos'],
      'media/photos': ['F|700|0|a.jpg', 'F|200|0|b.png'],
    };

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getSpaceInfo') return [1000000, 500000];
          if (call.method == 'listDirectory') {
            final args = call.arguments as Map<Object?, Object?>;
            return volume[args['dirPath'] as String] ?? <String>[];
          }
          return null;
        });

    container = ProviderContainer();
    subscription = container.listen(storageAnalyzerProvider, (_, _) {});
  });

  tearDown(() {
    subscription.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  StorageAnalyzer controller() =>
      container.read(storageAnalyzerProvider.notifier);
  StorageAnalyzerState state() => container.read(storageAnalyzerProvider);

  Future<void> scanned() async {
    await controller().selectTarget(_vault(volId: 1, name: 'Vault 1'));
  }

  group('scan', () {
    test('builds the folder tree and the summaries derived from it', () async {
      await scanned();
      final s = state();

      expect(s.loading, isFalse);
      expect(s.tree, isNotNull);
      expect(s.tree!.totalBytes, 6267);
      expect(s.scannedCount, 7);
      expect(s.truncated, isFalse);
      expect(s.hasUnreadable, isFalse);
      expect(s.totalBytes, 1000000);
      expect(s.freeBytes, 500000);

      expect(s.heaviest.first.name, 'clip.mp4');
      expect(s.breakdown.first.category, StorageCategory.videos);
      expect(s.currentPath, '');
      expect(s.currentNode!.children.first.name, 'media');
    });

    test('suggests cleanup for temp files and empty folders', () async {
      await scanned();
      final kinds = state().cleanup.map((c) => c.kind).toSet();

      expect(kinds, contains(CleanupKind.tempFiles));
      expect(kinds, contains(CleanupKind.emptyFolders));
    });

    test('a newer scan supersedes one still in flight', () async {
      final first = controller().selectTarget(_vault(volId: 1, name: 'A'));
      final second = controller().selectTarget(_vault(volId: 2, name: 'B'));
      await Future.wait([first, second]);

      expect(state().selected?.volId, 2);
      expect(state().loading, isFalse);
      expect(state().tree, isNotNull);
    });

    test('emptying the mounted list clears the results', () async {
      await scanned();
      controller().onMountedListChanged(const []);

      expect(state().selected, isNull);
      expect(state().tree, isNull);
    });
  });

  group('navigation', () {
    test('openFolder and goUp move through the tree', () async {
      await scanned();

      controller().openFolder('media');
      expect(state().currentPath, 'media');
      expect(state().currentNode!.sizeBytes, 5900);

      controller().openFolder('media/photos');
      expect(state().currentPath, 'media/photos');

      controller().goUp();
      expect(state().currentPath, 'media');
      controller().goUp();
      expect(state().currentPath, '');
      controller().goUp(); // already at the root
      expect(state().currentPath, '');
    });

    test('files and unknown paths are not navigable', () async {
      await scanned();
      controller().openFolder('readme');
      expect(state().currentPath, '');
      controller().openFolder('does/not/exist');
      expect(state().currentPath, '');
    });
  });

  group('selection', () {
    test('toggles, and a selected folder swallows what is inside it', () async {
      await scanned();
      final c = controller();

      c.toggleSelected('docs');
      c.toggleSelected('docs/report.pdf');
      expect(state().selectedPaths, hasLength(2));
      expect(state().hasSelection, isTrue);
      expect(state().selection.nodes.map((n) => n.path).toList(), ['docs']);
      expect(state().selection.bytes, 350);

      c.toggleSelected('docs');
      expect(state().selection.nodes.map((n) => n.path).toList(), [
        'docs/report.pdf',
      ]);

      c.clearSelection();
      expect(state().hasSelection, isFalse);
    });

    test('the root cannot be selected', () async {
      await scanned();
      controller().toggleSelected('');
      expect(state().hasSelection, isFalse);
    });

    test('addSelected and setSelected', () async {
      await scanned();
      final c = controller();
      c.addSelected(['readme', 'docs']);
      c.addSelected(['readme', 'cache.tmp']);
      expect(state().selectedPaths, hasLength(3));

      c.setSelected(['docs']);
      expect(state().selectedPaths, {'docs'});
    });
  });

  group('filters and lists', () {
    test(
      'type filter is held in state and lists that type largest first',
      () async {
        await scanned();
        final c = controller();

        c.setTypeFilter(StorageCategory.images);
        expect(state().typeFilter, StorageCategory.images);
        expect(
          c.filesOfType(StorageCategory.images).map((f) => f.name).toList(),
          ['a.jpg', 'b.png'],
        );

        c.setTypeFilter(null);
        expect(state().typeFilter, isNull);
      },
    );

    test('topFiles lists the biggest files first', () async {
      await scanned();
      final names = controller().topFiles(limit: 3).map((f) => f.name).toList();
      expect(names, ['clip.mp4', 'a.jpg', 'report.pdf']);
    });

    test('cached lists are keyed by their limit', () async {
      await scanned();
      final c = controller();
      expect(c.topFiles(limit: 2), hasLength(2));
      expect(c.topFiles(limit: 5), hasLength(5));
      expect(c.topFiles(), hasLength(7)); // default limit covers every file
    });

    test('sort is held in state', () async {
      await scanned();
      controller().setSort(StorageSort.name);
      expect(state().sort, StorageSort.name);
    });
  });

  group('refreshFolder', () {
    test('rereads one folder and updates every total above it', () async {
      await scanned();
      volume['docs'] = ['F|9000|0|report.pdf'];

      await controller().refreshFolder('docs');

      final s = state();
      expect(s.busy, isFalse);
      expect(s.tree!.find('docs')!.sizeBytes, 9000);
      expect(s.tree!.totalBytes, 6267 - 350 + 9000);
      // the untouched folder was not rescanned
      expect(s.tree!.find('media')!.sizeBytes, 5900);
      // and 'docs' now outranks 'media'
      expect(s.currentNode!.children.first.name, 'docs');
    });

    test('keeps the selection of items that still exist', () async {
      await scanned();
      controller().setSelected(['readme', 'docs/notes.txt']);
      volume['docs'] = ['F|300|0|report.pdf']; // notes.txt is gone

      await controller().refreshFolder('docs');

      expect(state().selectedPaths, {'readme'});
    });

    test('a folder that vanished sends the view back to an ancestor', () async {
      await scanned();
      controller().openFolder('media/photos');
      volume['media'] = ['F|5000|0|clip.mp4']; // photos/ is gone

      await controller().refreshFolder('media');

      expect(state().currentPath, 'media');
    });
  });

  group('deleteNodes', () {
    test('refuses on a read-only volume without touching anything', () async {
      await controller().selectTarget(
        _vault(volId: 3, name: 'RO', readOnly: true),
      );
      final node = state().tree!.find('readme')!;

      final result = await controller().deleteNodes([
        node,
      ], AppLocalizationsEn());

      expect(result.readOnly, isTrue);
      expect(result.deleted, 0);
      expect(state().canModify, isFalse);
      expect(state().tree!.find('readme'), isNotNull);
      expect(state().busy, isFalse);
    });

    test('an empty request does nothing', () async {
      await scanned();
      final result = await controller().deleteNodes(
        const [],
        AppLocalizationsEn(),
      );
      expect(result.deleted, 0);
      expect(result.readOnly, isFalse);
      expect(state().busy, isFalse);
    });
  });
}
