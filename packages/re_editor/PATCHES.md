# Local changes

This is the `re_editor` 0.10.0 package used by the app, with its upstream
license and README retained.

`lib/src/code_chunk.dart` skips isolate-based chunk analysis when given
`NonCodeChunkAnalyzer`. The upstream controller otherwise sends every line
to an isolate even though this analyzer always returns an empty chunk list.
Large files use this analyzer to avoid a second full-document copy.

`lib/src/_code_paragraph.dart` bounds the native text-paragraph cache to the
most recent 512 lines. Evicted paragraphs are left for Dart to collect because
the active render pass can still hold references to them. The upstream cache
grew for every line visited while scrolling. `lib/src/code_lines.dart` caches
segment offsets and uses binary search for line lookup. `lib/src/_code_field.dart`
uses fixed-height positioning when scrolling backward in unwrapped mode, so it
does not measure every skipped line.
