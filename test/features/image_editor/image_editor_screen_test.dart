import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/image_editor/image_editor_screen.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

class _FakeVaultFileIoApi extends VaultFileIoApi {
  final Uint8List? bytesToReturn;
  _FakeVaultFileIoApi({this.bytesToReturn}) : super(const MethodChannel('test/file-io'));

  @override
  Future<Uint8List?> readWholeFile(MountedContainer container, String path) async {
    return bytesToReturn;
  }
}

void main() {
  final testContainer = MountedContainer(
    uri: 'file:///test_vault',
    displayName: 'Test Vault',
    volId: 1,
    containerFormat: 'veracrypt',
    rootFiles: const [],
    mountedAt: DateTime(2026, 1, 1),
    totalSpace: 1000000,
    freeSpace: 500000,
  );

  // Minimal 1x1 valid PNG
  final png1x1 = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  testWidgets('ImageEditorScreen mounts and loads without modifying provider during build', (tester) async {
    final fakeIo = _FakeVaultFileIoApi(bytesToReturn: png1x1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultFileIoApiProvider.overrideWithValue(fakeIo),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImageEditorScreen(
            container: testContainer,
            filePath: 'photos/sample.png',
          ),
        ),
      ),
    );

    // Initial frame builds loading indicator cleanly
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Allow post-frame callback and image decoding to complete
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // After loading, the edit screen controls are visible and loading indicator is gone
    expect(find.text('sample.png'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('ImageEditorScreen handles load failure gracefully', (tester) async {
    final fakeIo = _FakeVaultFileIoApi(bytesToReturn: Uint8List(0));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultFileIoApiProvider.overrideWithValue(fakeIo),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImageEditorScreen(
            container: testContainer,
            filePath: 'photos/corrupt.png',
          ),
        ),
      ),
    );

    // Initial loading indicator
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    // Loading indicator is gone and error UI is displayed
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('ImageEditorScreen tools row is always visible with all tools including Looks and no redundant bottom bar', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final fakeIo = _FakeVaultFileIoApi(bytesToReturn: png1x1);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultFileIoApiProvider.overrideWithValue(fakeIo),
        ],
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ImageEditorScreen(
            container: testContainer,
            filePath: 'photos/sample.png',
          ),
        ),
      ),
    );

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // Verify tools row is visible immediately and contains all tools including Looks
    expect(find.byIcon(Icons.filter_vintage_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);
    expect(find.byIcon(Icons.crop_rounded), findsOneWidget);
    expect(find.byIcon(Icons.brush_rounded), findsOneWidget);
    expect(find.byIcon(Icons.text_fields_rounded), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

    // Verify there is no redundant bottom navigation bar (no Tools/Looks/Export bottom tabs)
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);

    // Tap Redact tool
    await tester.ensureVisible(find.byIcon(Icons.visibility_off_outlined));
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pump();

    // Redact action bar displays Delete and Clear
    expect(find.byIcon(Icons.delete_rounded), findsOneWidget);
    expect(find.byIcon(Icons.delete_sweep_rounded), findsOneWidget);
  });
}
