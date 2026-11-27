import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/desktop_media/desktop_media_controls.dart';

void main() {
  group('desktopMediaDisplayInfo', () {
    test('names and tags go out only when file names are allowed', () {
      final shown = desktopMediaDisplayInfo(
        showFileNames: true,
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
      );
      expect(shown.title, 'Song');
      expect(shown.artist, 'Artist');
      expect(shown.album, 'Album');
    });

    test('otherwise only a neutral line that does not say "vault"', () {
      final shown = desktopMediaDisplayInfo(
        showFileNames: false,
        title: 'secret-plans.mp3',
        artist: 'Someone',
        album: 'Private',
      );
      expect(shown.title, kGenericMediaTitle);
      expect(shown.artist, isEmpty);
      expect(shown.album, isEmpty);
      expect(kGenericMediaTitle.toLowerCase(), isNot(contains('vault')));
    });
  });

  group('DesktopMediaState', () {
    test('seeking needs an active session with a known duration', () {
      expect(const DesktopMediaState.inactive().canSeek, isFalse);
      expect(const DesktopMediaState(active: true).canSeek, isFalse);
      expect(
        const DesktopMediaState(
          active: true,
          duration: Duration(minutes: 3),
        ).canSeek,
        isTrue,
      );
    });
  });
}
