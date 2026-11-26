import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/file_open_dispatch.dart';

void main() {
  group('isExternalAppPreference', () {
    test('is true for the system picker and for a remembered app', () {
      expect(isExternalAppPreference('external'), isTrue);
      expect(isExternalAppPreference('package:com.example.viewer'), isTrue);
    });

    test('is false for in-app viewers and for no preference', () {
      for (final pref in [
        null,
        '',
        'editor',
        'media',
        'pdf',
        'html',
        'comic',
        'epub',
        'installer',
        'archive',
        'markdown',
      ]) {
        expect(isExternalAppPreference(pref), isFalse, reason: '$pref');
      }
    });

    test('agrees with decideFileOpenAction about which preferences go to a '
        'system app', () {
      for (final pref in ['external', 'package:com.example.viewer']) {
        final action = decideFileOpenAction(
          ext: 'xyz',
          extensionPreference: pref,
          needsSystemAppForLocal: false,
          isSupportedMedia: false,
        );
        expect(action, isA<OpenWithSystemApp>());
        expect(isExternalAppPreference(pref), isTrue);
      }
    });
  });
}
