import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/services/thumbnail_refresh_signal.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

void main() {
  group('ThumbnailRefreshSignal', () {
    test('publishes the exact mounted container and target path', () {
      final container = MountedContainer(
        uri: 'vault://test',
        displayName: 'Test',
        volId: 42,
        rootFiles: const [],
        mountedAt: DateTime.utc(2026, 1, 2),
        totalSpace: 100,
        freeSpace: 50,
      );

      ThumbnailRefreshSignal.invalidate(container, 'photos/original.jpg');

      final change = ThumbnailRefreshSignal.invalidation.value;
      expect(change, isNotNull);
      expect(change!.volId, 42);
      expect(
        change.mountedAtMillis,
        container.mountedAt.millisecondsSinceEpoch,
      );
      expect(change.filePath, 'photos/original.jpg');
    });

    test('each invalidation emits a new generation', () {
      final container = MountedContainer(
        uri: 'vault://test',
        displayName: 'Test',
        volId: 43,
        rootFiles: const [],
        mountedAt: DateTime.utc(2026, 1, 3),
        totalSpace: 100,
        freeSpace: 50,
      );

      ThumbnailRefreshSignal.invalidate(container, 'image.jpg');
      final first = ThumbnailRefreshSignal.invalidation.value!.generation;
      ThumbnailRefreshSignal.invalidate(container, 'image.jpg');
      final second = ThumbnailRefreshSignal.invalidation.value!.generation;

      expect(second, greaterThan(first));
    });
  });
}
