import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:vaultexplorer/data/services/discrete_mode_repository.dart';

class _FakePathProviderPlatform extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProviderPlatform(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PathProviderPlatform originalPlatform;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('discrete_mode_repo_test_');
    originalPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProviderPlatform(tempDir.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = originalPlatform;
    tempDir.deleteSync(recursive: true);
  });

  test('loadRecents returns empty list when no file exists yet', () async {
    final recents = await DiscreteModeRepository.loadRecents();
    expect(recents, isEmpty);
  });

  test('recordOpened persists an entry that loadRecents can read back', () async {
    await DiscreteModeRepository.recordOpened(
      DecoyRecentFile(
        uri: 'content://a/one.pdf',
        displayName: 'one.pdf',
        openedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ),
    );

    final recents = await DiscreteModeRepository.loadRecents();

    expect(recents, hasLength(1));
    expect(recents.single.uri, 'content://a/one.pdf');
    expect(recents.single.displayName, 'one.pdf');
  });

  test('recordOpened de-duplicates by uri, moving the entry to the front', () async {
    await DiscreteModeRepository.recordOpened(
      DecoyRecentFile(
        uri: 'content://a/one.pdf',
        displayName: 'one.pdf',
        openedAt: DateTime.fromMillisecondsSinceEpoch(1000),
      ),
    );
    await DiscreteModeRepository.recordOpened(
      DecoyRecentFile(
        uri: 'content://b/two.pdf',
        displayName: 'two.pdf',
        openedAt: DateTime.fromMillisecondsSinceEpoch(2000),
      ),
    );
    await DiscreteModeRepository.recordOpened(
      DecoyRecentFile(
        uri: 'content://a/one.pdf',
        displayName: 'one.pdf (reopened)',
        openedAt: DateTime.fromMillisecondsSinceEpoch(3000),
      ),
    );

    final recents = await DiscreteModeRepository.loadRecents();

    expect(recents, hasLength(2));
    expect(recents.first.uri, 'content://a/one.pdf');
    expect(recents.first.displayName, 'one.pdf (reopened)');
  });

  test('clearRecents empties the list', () async {
    await DiscreteModeRepository.recordOpened(
      DecoyRecentFile(
        uri: 'content://a/one.pdf',
        displayName: 'one.pdf',
        openedAt: DateTime.now(),
      ),
    );

    await DiscreteModeRepository.clearRecents();

    expect(await DiscreteModeRepository.loadRecents(), isEmpty);
  });
}
