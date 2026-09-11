import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/share_import/share_import_flow.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

// --- In-memory test fake ---
//
// Mirrors the _RecordingFileIoApi pattern in
// test/features/browser/transfer_placeholder_test.dart: extend the real
// VaultFileIoApi (it's a concrete class wrapping a MethodChannel, not an
// abstract interface) and override only the handful of methods the
// share-import flow actually calls, so every other inherited method still
// goes through the real (in these tests, unmocked-and-unused) channel.
class _FakeVaultFileIoApi extends VaultFileIoApi {
  _FakeVaultFileIoApi() : super(const MethodChannel('test/share-import'));

  ImportPickResult? prepareShareImportResult;
  int importFilesReturnValue = 1;

  final cancelledPendingRequests = <int>[];
  final cancelledPickTokens = <int>[];
  final importFilesCalls = <
      ({
        MountedContainer container,
        String targetPath,
        int opId,
        int pickToken,
        Map<String, String> conflictPlan,
      })>[];

  @override
  Future<ImportPickResult?> prepareShareImport(
    MountedContainer container,
    String targetPath,
  ) async =>
      prepareShareImportResult;

  @override
  Future<void> cancelPendingShareRequest() async {
    cancelledPendingRequests.add(1);
  }

  @override
  Future<void> cancelPickedImport(int pickToken) async {
    cancelledPickTokens.add(pickToken);
  }

  @override
  Future<int> importFiles(
    MountedContainer container,
    String targetPath,
    int opId,
    int pickToken, {
    Map<String, String> conflictPlan = const {},
  }) async {
    importFilesCalls.add((
      container: container,
      targetPath: targetPath,
      opId: opId,
      pickToken: pickToken,
      conflictPlan: conflictPlan,
    ));
    return importFilesReturnValue;
  }
}

MountedContainer _testContainer() => MountedContainer(
      uri: 'content://test-vault',
      displayName: 'My Vault',
      volId: 7,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
    );

/// Pumps a minimal MaterialApp with a single button whose onPressed calls
/// [presentIncomingShareImport], and returns the button's key so the test
/// can tap it. Deliberately not rendering anything from
/// ShareDestinationSheet itself -- see the "backing out" test below for why.
Future<Key> _pumpTrigger(
  WidgetTester tester,
  ProviderContainer container,
) async {
  const key = ValueKey('trigger');
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              key: key,
              onPressed: () => presentIncomingShareImport(
                context,
                ref,
                (items: const <IncomingShareItem>[]),
              ),
              child: const Text('share'),
            ),
          ),
        ),
      ),
    ),
  );
  return key;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final l10n = AppLocalizationsEn();

  group('shareImportNeedsAttention', () {
    test('flags failed, diskFull, and completedWithErrors', () {
      expect(shareImportNeedsAttention(FileOperationStatus.failed), isTrue);
      expect(shareImportNeedsAttention(FileOperationStatus.diskFull), isTrue);
      expect(
        shareImportNeedsAttention(FileOperationStatus.completedWithErrors),
        isTrue,
      );
    });

    test('does not flag completed, cancelled, pending, or running', () {
      expect(shareImportNeedsAttention(FileOperationStatus.completed), isFalse);
      expect(shareImportNeedsAttention(FileOperationStatus.cancelled), isFalse);
      expect(shareImportNeedsAttention(FileOperationStatus.pending), isFalse);
      expect(shareImportNeedsAttention(FileOperationStatus.running), isFalse);
    });
  });

  group('buildShareImportConflictEntries', () {
    test('matches each conflict to its picked item by name', () {
      const items = [
        ClipboardItem(path: 'photo.jpg', isDir: false, sizeBytes: 2048),
        ClipboardItem(path: 'notes.txt', isDir: false, sizeBytes: 128),
      ];
      const conflicts = [(name: 'photo.jpg', destIsDir: false)];

      final entries = buildShareImportConflictEntries(
        conflicts: conflicts,
        items: items,
      );

      expect(entries, hasLength(1));
      expect(entries.single.item.path, 'photo.jpg');
      expect(entries.single.item.sizeBytes, 2048);
      expect(entries.single.destIsDir, isFalse);
    });

    test(
      'falls back to a zero-size synthetic item when the conflicting name '
      'is not among the picked items',
      () {
        final entries = buildShareImportConflictEntries(
          conflicts: const [(name: 'ExistingFolder', destIsDir: true)],
          items: const [],
        );

        expect(entries, hasLength(1));
        expect(entries.single.item.path, 'ExistingFolder');
        expect(entries.single.item.sizeBytes, 0);
        expect(entries.single.destIsDir, isTrue);
      },
    );

    test('handles multiple conflicts independently', () {
      const items = [
        ClipboardItem(path: 'a.png', isDir: false, sizeBytes: 10),
        ClipboardItem(path: 'b.png', isDir: false, sizeBytes: 20),
      ];
      const conflicts = [
        (name: 'a.png', destIsDir: false),
        (name: 'b.png', destIsDir: false),
      ];

      final entries = buildShareImportConflictEntries(
        conflicts: conflicts,
        items: items,
      );

      expect(entries, hasLength(2));
      expect(entries.map((e) => e.item.path), ['a.png', 'b.png']);
    });
  });

  group('presentIncomingShareImport', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets(
      'backing out of the destination picker (no selection) cancels the '
      'pending share and closes the share-target activity, without ever '
      'needing ShareDestinationSheet itself to build',
      (tester) async {
        final recordedPops = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          recordedPops.add(call);
          return null;
        });

        final fakeApi = _FakeVaultFileIoApi();
        final container = ProviderContainer(
          overrides: [vaultFileIoApiProvider.overrideWithValue(fakeApi)],
        );
        addTearDown(container.dispose);

        final key = await _pumpTrigger(tester, container);

        await tester.tap(find.byKey(key));
        // Navigator.push installs the route synchronously as part of
        // handling the tap (before any frame is pumped) -- popping it here
        // with `null`, before ever calling tester.pump(), means
        // ShareDestinationSheet's builder is never invoked at all, so this
        // test never has to satisfy its own (much larger, unrelated)
        // provider dependency tree.
        Navigator.of(tester.element(find.byKey(key))).pop<CryptoDestination>(null);
        await tester.pumpAndSettle();

        expect(fakeApi.cancelledPendingRequests, hasLength(1));
        expect(
          recordedPops.where((c) => c.method == 'SystemNavigator.pop'),
          hasLength(1),
        );
        expect(fakeApi.importFilesCalls, isEmpty);
      },
    );

    testWidgets(
      'choosing a non-vault (external) destination cancels the pending '
      'share without closing the app',
      (tester) async {
        final recordedPops = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          recordedPops.add(call);
          return null;
        });

        final fakeApi = _FakeVaultFileIoApi();
        final container = ProviderContainer(
          overrides: [vaultFileIoApiProvider.overrideWithValue(fakeApi)],
        );
        addTearDown(container.dispose);

        final key = await _pumpTrigger(tester, container);

        await tester.tap(find.byKey(key));
        const externalDestination = CryptoDestination.external(
          displayName: 'Downloads',
          externalPath: '/storage/emulated/0/Download',
        );
        Navigator.of(tester.element(find.byKey(key)))
            .pop<CryptoDestination>(externalDestination);
        await tester.pumpAndSettle();

        expect(fakeApi.cancelledPendingRequests, hasLength(1));
        // Unlike the "no selection" case, backing out because the chosen
        // destination isn't a vault does not close the share-target
        // activity -- see the isVault/container/relativePath guard in
        // presentIncomingShareImport.
        expect(
          recordedPops.where((c) => c.method == 'SystemNavigator.pop'),
          isEmpty,
        );
        expect(fakeApi.importFilesCalls, isEmpty);
      },
    );

    testWidgets(
      'an expired pending share (prepareShareImport returns null) shows '
      'a warning and does not enqueue an import',
      (tester) async {
        final fakeApi = _FakeVaultFileIoApi()..prepareShareImportResult = null;
        final container = ProviderContainer(
          overrides: [vaultFileIoApiProvider.overrideWithValue(fakeApi)],
        );
        addTearDown(container.dispose);

        final key = await _pumpTrigger(tester, container);
        final vaultDestination = CryptoDestination.vault(
          displayName: 'My Vault',
          container: _testContainer(),
          relativePath: '',
        );

        await tester.tap(find.byKey(key));
        Navigator.of(tester.element(find.byKey(key)))
            .pop<CryptoDestination>(vaultDestination);
        await tester.pumpAndSettle();

        expect(find.text(l10n.shareImportExpiredMessage), findsOneWidget);
        expect(fakeApi.importFilesCalls, isEmpty);
      },
    );

    testWidgets(
      'a share with no conflicts enqueues the import against the chosen '
      'vault/folder and shows the importing-files message',
      (tester) async {
        const items = [
          ClipboardItem(path: 'vacation.jpg', isDir: false, sizeBytes: 4096),
        ];
        final fakeApi = _FakeVaultFileIoApi()
          ..prepareShareImportResult = (
            pickToken: 42,
            conflicts: const <ImportPickConflict>[],
            items: items,
          )
          ..importFilesReturnValue = 1;

        const engineChannel = MethodChannel('com.aeidolon.vaultexplorer/engine');
        final engineEvents = VaultEngineEvents()..registerHandler(engineChannel);
        final opSvc = FileOperationService.withEngineApis(
          engineEvents: engineEvents,
          fileIoApi: fakeApi,
          lifecycleApi: VaultLifecycleApi(engineChannel, engineEvents),
        );

        final container = ProviderContainer(
          overrides: [
            vaultFileIoApiProvider.overrideWithValue(fakeApi),
            fileOperationServiceProvider.overrideWithValue(opSvc),
          ],
        );
        addTearDown(container.dispose);

        final key = await _pumpTrigger(tester, container);
        final testContainer = _testContainer();
        final vaultDestination = CryptoDestination.vault(
          displayName: testContainer.displayName,
          container: testContainer,
          relativePath: 'Photos',
        );

        await tester.tap(find.byKey(key));
        Navigator.of(tester.element(find.byKey(key)))
            .pop<CryptoDestination>(vaultDestination);
        await tester.pumpAndSettle();

        expect(fakeApi.importFilesCalls, hasLength(1));
        final call = fakeApi.importFilesCalls.single;
        expect(call.container.uri, testContainer.uri);
        expect(call.targetPath, 'Photos');
        expect(call.pickToken, 42);
        expect(call.conflictPlan, isEmpty);

        expect(
          find.text(l10n.importingSharedFilesMessage(1, testContainer.displayName)),
          findsOneWidget,
        );
      },
    );
  });
}
