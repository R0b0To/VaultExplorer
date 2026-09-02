import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_file_manager_screen.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  bool hasAccess = false;
  bool requestAccessCalled = false;

  setUp(() {
    hasAccess = false;
    requestAccessCalled = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'hasAllFilesAccess':
          return hasAccess;
        case 'requestAllFilesAccess':
          requestAccessCalled = true;
          return true;
        case 'listDirectory':
          return <String>[];
        case 'getSpaceInfo':
          return [1000, 500];
        default:
          return null;
      }
    });
  });

  Widget buildTestWidget() {
    return const ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DecoyFileManagerScreen(),
      ),
    );
  }

  group('DecoyFileManagerScreen', () {
    testWidgets('shows permission empty state when storage access is missing', (tester) async {
      hasAccess = false;
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(FileBrowserScreen), findsNothing);
      expect(find.byIcon(Icons.folder_off_outlined), findsOneWidget);
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
    });

    testWidgets('triggers requestAllFilesAccess when grant button is tapped', (tester) async {
      hasAccess = false;
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final grantBtn = find.byIcon(Icons.lock_open_rounded);
      expect(grantBtn, findsOneWidget);
      await tester.tap(grantBtn);
      await tester.pumpAndSettle();

      expect(requestAccessCalled, isTrue);
    });

    testWidgets('mounts FileBrowserScreen when storage access is granted', (tester) async {
      hasAccess = true;
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(FileBrowserScreen), findsOneWidget);
    });
  });

  group('DecoyLocalRepository', () {
    test('lists files and directories correctly in directory', () async {
      const repo = DecoyLocalRepository();
      final tempDir = await Directory.systemTemp.createTemp('decoy_test_');
      try {
        final subDir = Directory('${tempDir.path}/subfolder');
        await subDir.create();
        final file1 = File('${tempDir.path}/sample.txt');
        await file1.writeAsString('hello world');
        final file2 = File('${tempDir.path}/image.png');
        await file2.writeAsBytes([0, 1, 2, 3]);

        final entries = await repo.listDirectory(tempDir.path);
        expect(entries.length, 3);

        final dirEntries = entries.where((e) => e.isDir).toList();
        final fileEntries = entries.where((e) => !e.isDir).toList();

        expect(dirEntries.length, 1);
        expect(dirEntries.first.name, 'subfolder');

        expect(fileEntries.length, 2);
        final fileNames = fileEntries.map((e) => e.name).toSet();
        expect(fileNames, containsAll({'sample.txt', 'image.png'}));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('returns empty list for non-existent path without throwing', () async {
      const repo = DecoyLocalRepository();
      final entries = await repo.listDirectory('/non/existent/path/for/test');
      expect(entries, isEmpty);
    });
  });
}
