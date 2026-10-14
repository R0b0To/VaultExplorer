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

`lib/src/_code_field.dart` bounds the backward scroll in wrapped mode. Walking
back measures one paragraph per line, which is exact but turned a scrollbar
drag or jump-to-start on a large file into thousands of paragraph layouts in
a single frame. It now walks at most `_kMaxExactBackwardLines` (in
`_consts.dart`) lines and otherwise jumps with the same fixed-height estimate
the forward jump already used.

`lib/src/code_indicator.dart` and `lib/src/_code_indicator.dart` add an opt-in
`DefaultCodeLineNumber.pinToViewportTop`. When a wrapped line starts above the
viewport its number stays at the top of the gutter until the line's last row
scrolls away, instead of disappearing with the line's first row.
