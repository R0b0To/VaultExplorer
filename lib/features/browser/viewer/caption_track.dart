// File: lib/features/browser/viewer/caption_track.dart
//
// Minimal, dependency-free SRT/WebVTT subtitle parsing plus a
// video_player-style caption widget. This replaces the video_player
// package, which was previously imported into media_player_widget.dart
// solely for SubRipCaptionFile/WebVTTCaptionFile/ClosedCaption -- pulling
// in an entire second video-playback engine's dependency surface (and
// reading, to anyone unfamiliar with the history, as if a second player
// were involved) just for its caption-parsing types. Actual playback here
// is handled by the video_player plugin -- see native_video_controller.dart
// -- but this parser stays as-is since it works fine independent of
// whichever engine is doing the decoding.

import 'package:flutter/material.dart';

@immutable
class Caption {
  final Duration start;
  final Duration end;
  final String text;
  const Caption({required this.start, required this.end, required this.text});
}

@immutable
class CaptionTrack {
  final List<Caption> captions;
  const CaptionTrack(this.captions);

  factory CaptionTrack.subRip(String data) => CaptionTrack(_parseCueBlocks(data, timestampSeparator: ','));

  factory CaptionTrack.webVtt(String data) {
    // Strip the leading "WEBVTT" header line (and any metadata after it up
    // to the first blank line) -- it isn't a cue and would otherwise be
    // mistaken for a malformed one and skipped anyway, but stripping it
    // explicitly keeps the parser's assumptions honest.
    final withoutHeader = data.replaceFirst(RegExp(r'^\uFEFF?WEBVTT[^\n]*\r?\n'), '');
    return CaptionTrack(_parseCueBlocks(withoutHeader, timestampSeparator: '.'));
  }

  static List<Caption> _parseCueBlocks(String data, {required String timestampSeparator}) {
    final captions = <Caption>[];
    final blocks = data.split(RegExp(r'\r?\n\r?\n+'));
    for (final block in blocks) {
      final lines = block.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;

      // The cue-timing line is usually the 2nd line (after a numeric SRT
      // index) but WebVTT allows omitting the index, so search for the
      // "-->" line rather than assuming a fixed position.
      final cueLineIndex = lines.indexWhere((l) => l.contains('-->'));
      if (cueLineIndex == -1) continue;

      final range = _parseTimeRange(lines[cueLineIndex], timestampSeparator);
      if (range == null) continue;

      final textLines = lines.sublist(cueLineIndex + 1);
      if (textLines.isEmpty) continue;

      captions.add(Caption(start: range.start, end: range.end, text: textLines.join('\n')));
    }
    return captions;
  }

  static _TimeRange? _parseTimeRange(String line, String timestampSeparator) {
    final parts = line.split('-->');
    if (parts.length != 2) return null;
    final start = _parseTimestamp(parts[0].trim(), timestampSeparator);
    // WebVTT cue settings (e.g. "align:start line:90%") can trail the end
    // timestamp on the same line -- only the first token is the timestamp.
    final endToken = parts[1].trim().split(RegExp(r'\s+')).first;
    final end = _parseTimestamp(endToken, timestampSeparator);
    if (start == null || end == null) return null;
    return _TimeRange(start, end);
  }


  static Duration? _parseTimestamp(String raw, String timestampSeparator) {
    final sepIndex = raw.lastIndexOf(timestampSeparator);
    if (sepIndex == -1) return null;

    final millisPart = raw.substring(sepIndex + 1);
    final millis = int.tryParse(millisPart.padRight(3, '0').substring(0, 3));

    final hmsParts = raw.substring(0, sepIndex).split(':');
    if (hmsParts.length < 2) return null;
    final fields = List<String>.from(hmsParts);
    final seconds = int.tryParse(fields.removeLast());
    final minutes = int.tryParse(fields.removeLast());
    final hours = fields.isNotEmpty ? int.tryParse(fields.removeLast()) : 0;

    if (millis == null || seconds == null || minutes == null || hours == null) return null;
    return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: millis);
  }
}

class _TimeRange {
  final Duration start;
  final Duration end;
  const _TimeRange(this.start, this.end);
}

/// Stand-in for video_player's `ClosedCaption` widget: renders [text] in a
/// translucent rounded pill near the bottom of the video, or nothing when
/// [text] is empty. Visual behavior intentionally mirrors the widget this
/// replaces so removing the video_player dependency has no UI-visible
/// effect.
class ClosedCaptionText extends StatelessWidget {
  final String text;
  final TextStyle textStyle;
  const ClosedCaptionText({super.key, required this.text, required this.textStyle});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: textStyle, textAlign: TextAlign.center),
      ),
    );
  }
}
