import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/media_playback_paths.dart';

MountedContainer _container({required int volId, required String uri}) =>
    MountedContainer(
      volId: volId,
      uri: uri,
      displayName: 'Test',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000,
      freeSpace: 500,
    );

void main() {
  group('nativePlaybackPathFor', () {
    test('vault items stay relative to the container', () {
      final vault = _container(volId: 3, uri: 'file:///vault.hc');
      expect(nativePlaybackPathFor(vault, 'Music/a.mp3'), 'Music/a.mp3');
    });

    test('raw local storage joins relative paths onto the root', () {
      // Built with package:path so the expectation holds on any host OS.
      final root = p.absolute('local_root');
      final local = _container(volId: -1, uri: root);
      expect(
        nativePlaybackPathFor(local, 'a.mp4'),
        p.join(root, 'a.mp4'),
      );
    });

    test('raw local storage keeps absolute paths as they are', () {
      final root = p.absolute('local_root');
      final local = _container(volId: -1, uri: root);
      final absolute = p.join(root, 'Movies', 'a.mp4');
      expect(nativePlaybackPathFor(local, absolute), absolute);
    });

    test('SAF storage keeps full document URIs and prefixes relative ones', () {
      final saf = _container(volId: -2, uri: 'content://tree/primary');
      expect(
        nativePlaybackPathFor(saf, 'content://tree/primary/a.mp3'),
        'content://tree/primary/a.mp3',
      );
      expect(
        nativePlaybackPathFor(saf, '/Music/a.mp3'),
        'content://tree/primary/Music/a.mp3',
      );
    });
  });

  group('isResumePositionWorthKeeping', () {
    test('drops the very start and the very end', () {
      const duration = Duration(minutes: 10);
      expect(
        isResumePositionWorthKeeping(const Duration(seconds: 2), duration),
        isFalse,
      );
      expect(
        isResumePositionWorthKeeping(const Duration(seconds: 3), duration),
        isFalse,
      );
      expect(
        isResumePositionWorthKeeping(
          duration - const Duration(seconds: 2),
          duration,
        ),
        isFalse,
      );
    });

    test('keeps a position in the middle', () {
      expect(
        isResumePositionWorthKeeping(
          const Duration(minutes: 4),
          const Duration(minutes: 10),
        ),
        isTrue,
      );
    });

    test('keeps a position when the duration is unknown', () {
      expect(
        isResumePositionWorthKeeping(const Duration(minutes: 4), null),
        isTrue,
      );
    });
  });
}
