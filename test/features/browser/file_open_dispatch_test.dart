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

   test("'markdown' opens the editor", () {
      final action = decideFileOpenAction(
        ext: 'md',
        extensionPreference: 'markdown',
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenInEditor>());
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

     test("'md' and 'markdown' both open the editor", () {
      for (final ext in ['md', 'markdown']) {
        final action = decideFileOpenAction(
          ext: ext,
          extensionPreference: null,
          needsSystemAppForLocal: false,
          isSupportedMedia: false,
        );
        expect(action, isA<OpenInEditor>(), reason: 'ext=$ext');
      }
    });

    test('.apk with no preference asks installer vs. ZIP', () {
      final action = decideFileOpenAction(
        ext: 'apk',
        extensionPreference: null,
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<ShowApkOpenChooser>());
    });

    test("a remembered 'installer' choice installs the .apk", () {
      final action = decideFileOpenAction(
        ext: 'apk',
        extensionPreference: 'installer',
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<InstallApk>());
    });

    test("a remembered 'archive' choice opens the .apk as a ZIP", () {
      final action = decideFileOpenAction(
        ext: 'apk',
        extensionPreference: 'archive',
        needsSystemAppForLocal: false,
        isSupportedMedia: false,
      );
      expect(action, isA<OpenAsArchive>());
    });

    test("'installer' / 'archive' are ignored for any other extension", () {
      // Only the APK chooser ever saves these; a stray value (hand-edited
      // settings) must not install or archive-scan an unrelated file.
      for (final pref in ['installer', 'archive']) {
        final action = decideFileOpenAction(
          ext: 'xyz',
          extensionPreference: pref,
          needsSystemAppForLocal: false,
          isSupportedMedia: false,
        );
        expect(action, isA<ShowOpenWithDialog>(), reason: 'pref=$pref');
      }
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

  group('decideFileOpenAction — built-in document viewer', () {
    FileOpenAction decide(String ext, {String? pref, bool local = false}) =>
        decideFileOpenAction(
          ext: ext,
          extensionPreference: pref,
          needsSystemAppForLocal: local,
          isSupportedMedia: false,
        );

    test('every supported Office / OpenDocument extension opens in it', () {
      for (final ext in const [
        'docx', 'docm', 'dotx', 'pptx', 'ppsx', 'potx', 'ppt', 'pps',
        'xlsx', 'xlsm', 'xltx', 'odt', 'ott', 'odp', 'otp', 'ods', 'ots',
      ]) {
        expect(decide(ext), isA<OpenInDocumentViewer>(), reason: ext);
      }
    });

    test("a saved 'document' preference opens it, for supported types", () {
      expect(decide('docx', pref: 'document'), isA<OpenInDocumentViewer>());
    });

    test("'document' on an unsupported extension falls through", () {
      // A stale or hand-edited value must not send an unreadable file to a
      // viewer that cannot render it.
      expect(decide('xyz', pref: 'document'), isA<ShowOpenWithDialog>());
      expect(decide('doc', pref: 'document'), isA<ShowOpenWithDialog>());
    });

    test('an explicit preference for another app still wins', () {
      expect(decide('docx', pref: 'external'), isA<OpenWithSystemApp>());
      expect(decide('xlsx', pref: 'editor'), isA<OpenInEditor>());
      final pkg = decide('pptx', pref: 'package:com.example.office');
      expect((pkg as OpenWithSystemApp).packageName, 'com.example.office');
    });

    test('formats without a reader still ask (legacy .doc / .xls, .rtf)', () {
      for (final ext in const ['doc', 'xls', 'rtf', 'pages', 'numbers']) {
        expect(decide(ext), isA<ShowOpenWithDialog>(), reason: ext);
      }
    });

    test('works for local storage too (bytes are read, not shared)', () {
      expect(decide('docx', local: true), isA<OpenInDocumentViewer>());
    });
  });
}
