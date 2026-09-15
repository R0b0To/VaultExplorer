/// What tapping a file in the browser should do next, decided from the
/// file's extension, any saved per-extension preference, and a couple of
/// booleans -- with no I/O, no BuildContext, and no widget state.
///
/// Extracted from `_FileBrowserScreenState._handleFileTap`'s dispatch
/// chain (the "content-open dispatch" cluster flagged but not executed in
/// the original file-browser-screen decomposition; tech-debt audit,
/// Sept 2026 / this pass). This is exactly the kind of logic that's easy
/// to get subtly wrong -- extension normalization already produced one
/// real bug in the neighboring preference-saving code -- and had zero
/// test coverage in its widget-trapped form. As a sealed class, the
/// widget's `switch` over the result is exhaustiveness-checked by the
/// compiler: adding a new [FileOpenAction] variant without updating every
/// call site is a compile error, not a silently-ignored case.
sealed class FileOpenAction {
  const FileOpenAction();
}

class OpenInEditor extends FileOpenAction {
  const OpenInEditor();
}

class OpenInMediaViewer extends FileOpenAction {
  const OpenInMediaViewer();
}

class OpenInPdfViewer extends FileOpenAction {
  const OpenInPdfViewer();
}

class OpenInHtmlViewer extends FileOpenAction {
  const OpenInHtmlViewer();
}

class OpenInMarkdownViewer extends FileOpenAction {
  const OpenInMarkdownViewer();
}

/// Hand off to a system app -- either the one already remembered for this
/// extension ([packageName] set), or the platform's own app picker
/// ([packageName] null, covering both the "needs a system app for a local
/// file" case and an explicit `'external'` preference).
class OpenWithSystemApp extends FileOpenAction {
  final String? packageName;
  const OpenWithSystemApp({this.packageName});
}

/// No preference, and the extension doesn't match anything built in --
/// ask the user via `OpenWithDialog`.
class ShowOpenWithDialog extends FileOpenAction {
  const ShowOpenWithDialog();
}

/// [ext] is the already-lowercased, dot-and-whitespace-stripped extension
/// (see `_handleFileTap`'s own normalization). [extensionPreference] is
/// the saved choice for that extension, if any (`'editor'`, `'media'`,
/// `'pdf'`, `'html'`, `'markdown'`, `'external'`, or `'package:<name>'`).
/// [needsSystemAppForLocal] and [isSupportedMedia] are pre-computed by the
/// caller (the former depends on `widget.container.isLocalStorage`, the
/// latter on `MediaViewerConstants`) since neither belongs in a function
/// with no container/media-type knowledge of its own.
///
/// Branch order matters and matches `_handleFileTap`'s original
/// if/else-if chain exactly: [needsSystemAppForLocal] short-circuits
/// everything else first, then a saved preference (checked in the same
/// order the old chain checked it), then -- only with no preference, or
/// one that matched nothing above -- the extension-based fallback.
FileOpenAction decideFileOpenAction({
  required String ext,
  required String? extensionPreference,
  required bool needsSystemAppForLocal,
  required bool isSupportedMedia,
}) {
  if (needsSystemAppForLocal) return const OpenWithSystemApp();
  final pref = extensionPreference;
  if (pref == 'editor') return const OpenInEditor();
  if (pref == 'media') return const OpenInMediaViewer();
  if (pref == 'pdf') return const OpenInPdfViewer();
  if (pref == 'html') return const OpenInHtmlViewer();
  if (pref == 'markdown') return const OpenInMarkdownViewer();
  if (pref != null && pref.startsWith('package:')) {
    return OpenWithSystemApp(packageName: pref.substring(8));
  }
  if (pref == 'external') return const OpenWithSystemApp();
  if (isSupportedMedia) return const OpenInMediaViewer();
  if (ext == 'pdf') return const OpenInPdfViewer();
  if (ext == 'html' || ext == 'htm') return const OpenInHtmlViewer();
  if (ext == 'md' || ext == 'markdown') return const OpenInMarkdownViewer();
  return const ShowOpenWithDialog();
}
