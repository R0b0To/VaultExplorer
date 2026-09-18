import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/file_open_dispatch.dart';

void main() {
  group('decideFileOpenAction — needsSystemAppForLocal short-circuits everything', () {
    test('wins even over a saved preference that would otherwise apply', () {
      final action = decideFileOpenAction(
        ext: 'mp3',
        extensionPreference: 'editor',
        needsSystemAppForLocal: true,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenWithSystemApp>());
      expect((action as OpenWithSystemApp).packageName, isNull);
    });
  });

  group('decideFileOpenAction — saved preference, in priority order', () {
    test("'editor' opens the text editor", () {
      final action = decideFileOpenAction(
        ext: 'txt',
        extensionPreference: 'editor',
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenInEditor>());
    });

    test("'media' opens the media viewer", () {
      final action = decideFileOpenAction(
        ext: 'jpg',
        extensionPreference: 'media',
        needsSystemAppForLocal: false,
        isSupportedMedia: true,
      );
      expect(action, isA<OpenInMediaViewer>());
    });

    test("'pdf' opens the PDF viewer", () {
      final action = decideFileOpenAction(
        ext: 'pdf',
        extensionPreference: 'pdf',
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenInPdfViewer>());
    });

    test("'html' opens the HTML viewer", () {
      final action = decideFileOpenAction(
        ext: 'html',
        extensionPreference: 'html',
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenInHtmlViewer>());
    });

    test("'markdown' opens the Markdown viewer", () {
      final action = decideFileOpenAction(
        ext: 'md',
        extensionPreference: 'markdown',
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenInMarkdownViewer>());
    });

    test("'package:<name>' opens with that remembered app", () {
      final action = decideFileOpenAction(
        ext: 'epub',
        extensionPreference: 'package:com.example.reader',
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenWithSystemApp>());
      expect((action as OpenWithSystemApp).packageName, 'com.example.reader');
    });

    test("'external' opens the system app picker", () {
      final action = decideFileOpenAction(
        ext: 'docx',
        extensionPreference: 'external',
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenWithSystemApp>());
      expect((action as OpenWithSystemApp).packageName, isNull);
    });

    test('an unrecognized preference value falls through to the extension fallback, not the dialog directly', () {
      final action = decideFileOpenAction(
        ext: 'pdf',
        extensionPreference: 'some_stale_value',
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenInPdfViewer>());
    });
  });

  group('decideFileOpenAction — no preference, extension-based fallback', () {
    test('supported media opens the media viewer regardless of extension', () {
      final action = decideFileOpenAction(
        ext: 'weirdext',
        extensionPreference: null,
        needsSystemAppForLocal: false,
        isSupportedMedia: true,
      );
      expect(action, isA<OpenInMediaViewer>());
    });

    test("'pdf' extension opens the PDF viewer", () {
      final action = decideFileOpenAction(
        ext: 'pdf',
        extensionPreference: null,
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenInPdfViewer>());
    });

    test("'html' and 'htm' both open the HTML viewer", () {
      for (final ext in ['html', 'htm']) {
        final action = decideFileOpenAction(
          ext: ext,
          extensionPreference: null,
          needsSystemAppForLocal: false,
          isSupportedMedia: false,
        );
        expect(action, isA<OpenInHtmlViewer>(), reason: 'ext=$ext');
      }
    });

    test("'md' and 'markdown' both open the Markdown viewer", () {
      for (final ext in ['md', 'markdown']) {
        final action = decideFileOpenAction(
          ext: ext,
          extensionPreference: null,
          needsSystemAppForLocal: false,
          isSupportedMedia: false,
        );
        expect(action, isA<OpenInMarkdownViewer>(), reason: 'ext=$ext');
      }
    });

    test('.apk goes straight to the package installer', () {
      final action = decideFileOpenAction(
        ext: 'apk',
        extensionPreference: null,
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<InstallApk>());
    });

    test('a saved preference still beats the installer for .apk', () {
      // An APK is a ZIP, so pointing it at an archive tool or an APK
      // analyser is a legitimate thing to have chosen.
      final action = decideFileOpenAction(
        ext: 'apk',
        extensionPreference: 'package:com.example.apkinspector',
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenWithSystemApp>());
      expect(
        (action as OpenWithSystemApp).packageName,
        'com.example.apkinspector',
      );
    });

    test('anything else shows the open-with dialog', () {
      final action = decideFileOpenAction(
        ext: 'xyz',
        extensionPreference: null,
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<ShowOpenWithDialog>());
    });

    test('empty extension (no dot in filename) shows the open-with dialog', () {
      final action = decideFileOpenAction(
        ext: '',
        extensionPreference: null,
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<ShowOpenWithDialog>());
    });
  });
}
