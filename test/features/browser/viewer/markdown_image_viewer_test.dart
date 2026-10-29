import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_image_cache.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/markdown_image.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/markdown_image_viewer.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

// Valid 4x2 RGB PNG.
final Uint8List _png4x2 = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAQAAAACCAIAAADwyuo0AAAAEElEQVR4nGM4YWQERwzIHAB+qglhzEG8IAAAAABJRU5ErkJggg==',
);

class _FakeToolbarService extends FileManagerToolbarService {
  @override
  Future<FileManagerToolbarConfig> load() async =>
      FileManagerToolbarConfig.defaults();

  @override
  Future<void> save(FileManagerToolbarConfig config) async {}
}

MountedContainer _container() => MountedContainer(
      volId: 1,
      uri: 'file:///vault.hc',
      displayName: 'Vault',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000000,
      freeSpace: 500000,
    );

MarkdownImageCache _cache() => MarkdownImageCache(
      readAll: (path) async => _png4x2,
      readHead: (path, length) async => _png4x2,
    );

Widget _host(MarkdownImageCache cache, {required bool zoomable}) {
  return ProviderScope(
    overrides: [
      fileManagerToolbarServiceProvider.overrideWithValue(
        _FakeToolbarService(),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarkdownImage(
            container: _container(),
            resolvedPath: '/a.png',
            alt: 'A red block',
            cache: cache,
            zoomable: zoomable,
          ),
        ),
      ),
    ),
  );
}

/// Loads the image into [cache], shows the preview and opens the viewer.
Future<void> _openViewer(WidgetTester tester, MarkdownImageCache cache) async {
  await tester.runAsync(() => cache.loadBytes('/a.png'));
  await tester.pumpWidget(_host(cache, zoomable: true));
  await tester.tap(find.byType(MarkdownImage));
  await tester.pumpAndSettle();
  expect(find.byType(MarkdownImageViewer), findsOneWidget);
}

double _scale(WidgetTester tester) => tester
    .widget<InteractiveViewer>(find.byType(InteractiveViewer))
    .transformationController!
    .value
    .getMaxScaleOnAxis();

Future<void> _doubleTapAt(WidgetTester tester, Offset position) async {
  await tester.tapAt(position);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(position);
  await tester.pumpAndSettle();
}

/// Lets pending timers (dismiss safety net, zoom pill auto-hide) run out.
Future<void> _flushTimers(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 3));

void main() {
  testWidgets('tapping a zoomable image opens the viewer; close dismisses it',
      (tester) async {
    final cache = _cache();
    addTearDown(cache.dispose);
    await _openViewer(tester, cache);

    expect(find.text('A red block'), findsOneWidget); // caption

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownImageViewer), findsNothing);
  });

  testWidgets('an image that is not zoomable ignores taps', (tester) async {
    final cache = _cache();
    addTearDown(cache.dispose);
    await tester.runAsync(() => cache.loadBytes('/a.png'));

    await tester.pumpWidget(_host(cache, zoomable: false));
    await tester.tap(find.byType(MarkdownImage));
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownImageViewer), findsNothing);
  });

  testWidgets('double-tap zooms in with a zoom pill; tapping the pill resets',
      (tester) async {
    final cache = _cache();
    addTearDown(cache.dispose);
    await _openViewer(tester, cache);
    expect(_scale(tester), closeTo(1.0, 0.001));

    await _doubleTapAt(tester, tester.getCenter(find.byType(InteractiveViewer)));
    expect(_scale(tester), closeTo(3.5, 0.01));
    expect(find.text('350%'), findsOneWidget);

    await tester.tap(find.text('350%'));
    await tester.pumpAndSettle();
    expect(_scale(tester), closeTo(1.0, 0.01));

    await _flushTimers(tester);
  });

  testWidgets('double-tap again resets the zoom', (tester) async {
    final cache = _cache();
    addTearDown(cache.dispose);
    await _openViewer(tester, cache);
    final center = tester.getCenter(find.byType(InteractiveViewer));

    await _doubleTapAt(tester, center);
    expect(_scale(tester), closeTo(3.5, 0.01));
    await _doubleTapAt(tester, center);
    expect(_scale(tester), closeTo(1.0, 0.01));

    await _flushTimers(tester);
  });

  testWidgets('double-tap in the black margin does not zoom', (tester) async {
    final cache = _cache();
    addTearDown(cache.dispose);
    await _openViewer(tester, cache);

    // A 4:2 image on the 800x600 test surface leaves 100px bars top/bottom.
    final viewer = tester.getRect(find.byType(InteractiveViewer));
    await _doubleTapAt(tester, Offset(viewer.center.dx, viewer.top + 20));

    expect(_scale(tester), closeTo(1.0, 0.001));
    await _flushTimers(tester);
  });

  for (final entry in {
    'down': const Offset(0, 300),
    'up': const Offset(0, -300),
    'left': const Offset(-300, 0),
    'right': const Offset(300, 0),
  }.entries) {
    testWidgets('swiping ${entry.key} dismisses the viewer', (tester) async {
      final cache = _cache();
      addTearDown(cache.dispose);
      await _openViewer(tester, cache);

      await tester.drag(find.byType(InteractiveViewer), entry.value);
      await tester.pumpAndSettle();
      await _flushTimers(tester);

      expect(find.byType(MarkdownImageViewer), findsNothing);
    });
  }

  testWidgets('a zoomed image is panned, not dismissed, by a drag',
      (tester) async {
    final cache = _cache();
    addTearDown(cache.dispose);
    await _openViewer(tester, cache);

    await _doubleTapAt(tester, tester.getCenter(find.byType(InteractiveViewer)));
    expect(_scale(tester), closeTo(3.5, 0.01));

    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 300));
    await tester.pumpAndSettle();
    await _flushTimers(tester);

    expect(find.byType(MarkdownImageViewer), findsOneWidget);
  });

  testWidgets('a short, slow drag springs back instead of dismissing',
      (tester) async {
    final cache = _cache();
    addTearDown(cache.dispose);
    await _openViewer(tester, cache);

    // Released after a pull of well under 5% of the screen: it springs back.
    await tester.drag(find.byType(InteractiveViewer), const Offset(0, 8));
    await tester.pumpAndSettle();
    await _flushTimers(tester);

    expect(find.byType(MarkdownImageViewer), findsOneWidget);
  });
}
