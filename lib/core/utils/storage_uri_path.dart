/// A filesystem path for a storage or vault [uri], for showing or copying.
///
/// Android hands out SAF document/tree URIs for anything the user picked
/// (`content://com.android.externalstorage.documents/tree/primary%3ADocs`),
/// which is not something a person can read or paste into another app. For
/// the shared-storage provider the document id is `<volume>:<relative path>`,
/// which maps straight back to a path:
///
///  * `primary:Docs/x`  -> `/storage/emulated/0/Docs/x`
///  * `home:Docs`       -> `/storage/emulated/0/Documents/Docs`
///  * `1234-ABCD:Docs`  -> `/storage/1234-ABCD/Docs`
///
/// `file://` URIs lose their scheme. Anything else (a plain path, `usb:`,
/// another provider's URI, a string that does not parse) comes back as given,
/// since guessing a path for it would be wrong.
String readablePathFromUri(String uri) {
  if (uri.startsWith('/')) return uri;
  final Uri parsed;
  try {
    parsed = Uri.parse(uri);
  } on FormatException {
    return uri;
  }
  if (parsed.scheme == 'file') {
    // Uri.path stays percent-encoded; the segments are decoded.
    if (parsed.pathSegments.isEmpty) return uri;
    return _withoutTrailingSlash('/${parsed.pathSegments.join('/')}');
  }
  if (parsed.scheme != 'content' ||
      parsed.authority != 'com.android.externalstorage.documents') {
    return uri;
  }
  final segments = parsed.pathSegments;
  // A tree URI can carry a document inside it
  // (`tree/<id>/document/<id>`); the document is the more specific one.
  final docId = _idAfter(segments, 'document') ?? _idAfter(segments, 'tree');
  if (docId == null) return uri;
  final colon = docId.indexOf(':');
  if (colon == -1) return uri;
  final volume = docId.substring(0, colon);
  final relative = docId.substring(colon + 1);
  final String root;
  if (volume.toLowerCase() == 'primary') {
    root = '/storage/emulated/0';
  } else if (volume.toLowerCase() == 'home') {
    root = '/storage/emulated/0/Documents';
  } else if (volume.isEmpty) {
    return uri;
  } else {
    root = '/storage/$volume';
  }
  final rel = relative.replaceAll(RegExp(r'^/+|/+$'), '');
  return rel.isEmpty ? root : '$root/$rel';
}

String? _idAfter(List<String> segments, String marker) {
  final i = segments.indexOf(marker);
  if (i == -1 || i + 1 >= segments.length) return null;
  return segments[i + 1];
}

String _withoutTrailingSlash(String path) =>
    path.length > 1 && path.endsWith('/')
    ? path.substring(0, path.length - 1)
    : path;
