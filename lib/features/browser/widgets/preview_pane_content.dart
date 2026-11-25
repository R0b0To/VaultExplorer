import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/media_playback_paths.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/library/tags/audio_tag_reader.dart';
import 'package:vaultexplorer/features/library/tags/byte_source.dart';
import 'package:vaultexplorer/features/library/tags/tag_models.dart';

/// What the desktop preview pane can show for a selected file.
enum PreviewPaneKind {
  /// Nothing beyond the generic thumbnail and details.
  none,
  image,
  video,

  /// Playable audio, with the cover art and tags read from the file.
  audio,

  /// Known text-like extensions: plain text, source code, markup, CSV, logs...
  text,

  /// An extension the app does not recognise. The start of the file is sniffed
  /// and shown as text only when it really is text.
  unknownText,

  /// TrueType / OpenType fonts, rendered with a specimen.
  font,
}

const Set<String> _fontPreviewExtensions = {'ttf', 'otf'};

/// Spreadsheet-kind files that are nevertheless plain text.
const Set<String> _extraTextExtensions = {'csv', 'tsv'};

/// Picks how [name] is previewed in the pane.
///
/// Vault items (passwords, cards, ...), encrypted files, key stores and other
/// binary kinds are deliberately [PreviewPaneKind.none]: their contents must
/// never be rendered just because the row was selected.
PreviewPaneKind previewPaneKindFor(String name) {
  if (MediaViewerConstants.isImage(name)) return PreviewPaneKind.image;
  if (MediaViewerConstants.isVideo(name)) return PreviewPaneKind.video;
  if (MediaViewerConstants.isAudio(name)) return PreviewPaneKind.audio;

  final dot = name.lastIndexOf('.');
  final rawExt = dot < 0 ? '' : name.substring(dot + 1);
  final ext = rawExt.toLowerCase();
  // Vault-item extensions are case-sensitive enum names ("paymentCard").
  if (vaultIconForExt(rawExt) != null) return PreviewPaneKind.none;
  if (_fontPreviewExtensions.contains(ext)) return PreviewPaneKind.font;
  if (_extraTextExtensions.contains(ext)) return PreviewPaneKind.text;
  return switch (fileKindOf(name)) {
    FileKind.text || FileKind.code || FileKind.web => PreviewPaneKind.text,
    FileKind.generic => PreviewPaneKind.unknownText,
    _ => PreviewPaneKind.none,
  };
}

// ── Text ─────────────────────────────────────────────────────────────────────

/// Only the start of a file is read for the preview.
const int _maxTextPreviewBytes = 48 * 1024;

/// True when [bytes] (a file's first bytes) are not text: a NUL byte, or more
/// than one byte in ten being a control character other than whitespace/ESC.
bool _looksBinary(Uint8List bytes) {
  final n = math.min(bytes.length, 4096);
  var control = 0;
  for (var i = 0; i < n; i++) {
    final c = bytes[i];
    if (c == 0) return true;
    if (c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D && c != 0x0C && c != 0x1B) {
      control++;
    }
  }
  return control * 10 > n;
}

/// Where to cut [b] (valid from [start]) so a multi-byte UTF-8 sequence that
/// was split by the read limit is dropped instead of decoding to U+FFFD.
int _trimPartialUtf8(Uint8List b, int start, int end) {
  var i = end - 1;
  var back = 0;
  while (i >= start && back < 3 && (b[i] & 0xC0) == 0x80) {
    i--;
    back++;
  }
  if (i < start) return end;
  final lead = b[i];
  final int need;
  if (lead >= 0xF0) {
    need = 4;
  } else if (lead >= 0xE0) {
    need = 3;
  } else if (lead >= 0xC0) {
    need = 2;
  } else {
    need = 1;
  }
  return (end - i) < need ? i : end;
}

String _decodeUtf16(Uint8List b, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 2; i + 1 < b.length; i += 2) {
    units.add(littleEndian ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(units);
}

/// Decodes the first bytes of a file for display, or returns null when they are
/// not text.
///
/// Understands UTF-8 (with or without BOM) and BOM-marked UTF-16 without any
/// platform channel. [truncated] says the bytes are only a prefix of the file,
/// so a cut-off trailing character is dropped. With [strict], text containing
/// many invalid UTF-8 sequences is rejected too (used for files whose
/// extension does not say they are text).
@visibleForTesting
String? decodePreviewText(
  Uint8List bytes, {
  required bool truncated,
  bool strict = false,
}) {
  if (bytes.isEmpty) return null;
  String text;
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    text = _decodeUtf16(bytes, littleEndian: true);
  } else if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    text = _decodeUtf16(bytes, littleEndian: false);
  } else {
    if (_looksBinary(bytes)) return null;
    final start =
        bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF
        ? 3
        : 0;
    final end = truncated
        ? _trimPartialUtf8(bytes, start, bytes.length)
        : bytes.length;
    text = utf8.decode(
      Uint8List.sublistView(bytes, start, end),
      allowMalformed: true,
    );
    if (strict && text.isNotEmpty) {
      var bad = 0;
      for (final r in text.runes) {
        if (r == 0xFFFD) bad++;
      }
      if (bad * 50 > text.length) return null;
    }
  }
  return text.replaceAll('\r\n', '\n');
}

class _TextPreview {
  final String text;
  final bool truncated;

  const _TextPreview(this.text, this.truncated);
}

/// The start of a text file, in a selectable monospace view.
///
/// Shows [poster] (the thumbnail) while the file is read and whenever it turns
/// out not to be text, so a mislabelled or unknown binary never shows garbage.
class PreviewPaneText extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;
  final int sizeBytes;

  /// True when the extension did not say this is text: the bytes are checked
  /// strictly before anything is shown.
  final bool sniff;
  final Widget poster;

  const PreviewPaneText({
    super.key,
    required this.container,
    required this.filePath,
    required this.sizeBytes,
    required this.poster,
    this.sniff = false,
  });

  @override
  ConsumerState<PreviewPaneText> createState() => _PreviewPaneTextState();
}

class _PreviewPaneTextState extends ConsumerState<PreviewPaneText> {
  late final Future<_TextPreview?> _future;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<_TextPreview?> _load() async {
    final size = widget.sizeBytes;
    if (size <= 0) return null;
    final api = ref.read(vaultFileIoApiProvider);
    // Sniffing needs only enough to tell text from binary.
    final want = math.min(size, widget.sniff ? 8 * 1024 : _maxTextPreviewBytes);
    final builder = BytesBuilder(copy: false);
    var offset = 0;
    try {
      while (offset < want) {
        final chunk = await api.readFileChunk(
          widget.container,
          widget.filePath,
          offset,
          want - offset,
        );
        if (chunk == null || chunk.isEmpty) break;
        builder.add(chunk);
        offset += chunk.length;
      }
    } catch (_) {
      return null;
    }
    final bytes = builder.takeBytes();
    final truncated = size > bytes.length;
    final text = decodePreviewText(
      bytes,
      truncated: truncated,
      strict: widget.sniff,
    );
    if (text == null) return null;
    return _TextPreview(text, truncated);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_TextPreview?>(
    future: _future,
    builder: (context, snapshot) {
      final preview = snapshot.data;
      if (preview == null) return widget.poster;
      final cs = Theme.of(context).colorScheme;
      return ColoredBox(
        color: cs.surfaceContainerLowest,
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              width: double.infinity,
              child: SelectableText(
                preview.truncated ? '${preview.text}\n…' : preview.text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.4,
                  color: cs.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

// ── Fonts ────────────────────────────────────────────────────────────────────

const int _maxFontPreviewBytes = 8 * 1024 * 1024;

/// A type specimen for a TrueType / OpenType font file.
///
/// The font is registered with the engine under a private family name; the
/// engine has no way to unregister it, so each file is loaded at most once per
/// session (and only up to [_maxFontPreviewBytes]).
class PreviewPaneFont extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;
  final int sizeBytes;
  final Widget poster;

  const PreviewPaneFont({
    super.key,
    required this.container,
    required this.filePath,
    required this.sizeBytes,
    required this.poster,
  });

  @override
  ConsumerState<PreviewPaneFont> createState() => _PreviewPaneFontState();
}

class _PreviewPaneFontState extends ConsumerState<PreviewPaneFont> {
  static final Set<String> _loadedFamilies = <String>{};

  late final Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<String?> _load() async {
    final size = widget.sizeBytes;
    if (size <= 0 || size > _maxFontPreviewBytes) return null;
    final family =
        'vx_preview_${widget.container.volId}_${widget.filePath.hashCode}_$size';
    if (_loadedFamilies.contains(family)) return family;
    try {
      final bytes = await ref
          .read(vaultFileIoApiProvider)
          .readWholeFile(widget.container, widget.filePath);
      if (bytes == null || bytes.isEmpty) return null;
      final loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loadedFamilies.add(family);
      return family;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _future,
    builder: (context, snapshot) {
      final family = snapshot.data;
      if (family == null) return widget.poster;
      final color = Theme.of(context).colorScheme.onSurface;
      TextStyle style(double size) =>
          TextStyle(fontFamily: family, fontSize: size, color: color);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aa Bb Cc', style: style(44)),
                const SizedBox(height: 12),
                Text(
                  'The quick brown fox jumps over the lazy dog',
                  style: style(20),
                ),
                const SizedBox(height: 12),
                Text(
                  'ABCDEFGHIJKLMNOPQRSTUVWXYZ\n'
                  'abcdefghijklmnopqrstuvwxyz\n'
                  '0123456789 !?&@#%()[]{}',
                  style: style(15),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ── Audio ────────────────────────────────────────────────────────────────────

class _PreviewByteSource implements ByteSource {
  final VaultFileIoApi _api;
  final MountedContainer _container;
  final String _path;
  final int _size;

  _PreviewByteSource(this._api, this._container, this._path, this._size);

  @override
  int get length => _size;

  @override
  Future<Uint8List?> read(int offset, int count) =>
      _api.readFileChunk(_container, _path, offset, count);
}

/// Inline audio player for the desktop preview pane.
///
/// Shows the embedded cover (or [poster]) with the title and artist from the
/// file's tags. Nothing is opened until the user presses play, so clicking
/// through a folder of songs does not start a player for each one; the player
/// is disposed when the selection changes.
class PreviewPaneAudio extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;
  final int sizeBytes;
  final Widget poster;

  const PreviewPaneAudio({
    super.key,
    required this.container,
    required this.filePath,
    required this.sizeBytes,
    required this.poster,
  });

  @override
  ConsumerState<PreviewPaneAudio> createState() => _PreviewPaneAudioState();
}

class _PreviewPaneAudioState extends ConsumerState<PreviewPaneAudio> {
  NativeVideoController? _controller;
  bool _starting = false;
  double? _dragMs;
  AudioTags? _tags;
  Uint8List? _cover;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTags());
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_onTick);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _loadTags() async {
    if (widget.sizeBytes <= 0) return;
    final source = _PreviewByteSource(
      ref.read(vaultFileIoApiProvider),
      widget.container,
      widget.filePath,
      widget.sizeBytes,
    );
    try {
      final tags = await AudioTagReader.read(source, fileName: widget.filePath);
      if (!mounted) return;
      setState(() => _tags = tags);
      if (!tags.hasCover) return;
      final art = await AudioTagReader.readCover(
        source,
        fileName: widget.filePath,
      );
      if (!mounted || art == null) return;
      setState(() => _cover = art.bytes);
    } catch (_) {
      // Tags and cover are decoration; playback does not depend on them.
    }
  }

  Future<void> _start() async {
    if (_starting || _controller != null) return;
    setState(() => _starting = true);
    // The app has a single native player; background audio lets go of it first.
    if (BackgroundPlaybackHost.instance.needsRelease) {
      await BackgroundPlaybackHost.instance.closeAndWait();
      if (!mounted) return;
    }
    final container = widget.container;
    final controller = NativeVideoController(
      volId: container.volId,
      filePath: nativePlaybackPathFor(container, widget.filePath),
      isLocalStorage: container.isLocalStorage,
      autoPlay: true,
    );
    controller.addListener(_onTick);
    setState(() {
      _controller = controller;
      _starting = false;
    });
    await controller.initialize();
    if (!mounted || !identical(_controller, controller)) return;
    await controller.play();
  }

  Future<void> _togglePlay(NativeVideoController controller) async {
    final value = controller.value;
    if (value.isPlaying) {
      await controller.pause();
      return;
    }
    // A finished track starts over instead of doing nothing.
    if (value.duration > Duration.zero &&
        value.position >= value.duration - const Duration(milliseconds: 250)) {
      await controller.seekTo(Duration.zero);
    }
    await controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final controller = _controller;
    final cover = _cover;
    return ColoredBox(
      color: cs.surfaceContainerHigh,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 150;
          final narrow = constraints.maxWidth < 200;
          return Stack(
            fit: StackFit.expand,
            children: [
              if (cover != null)
                Image.memory(
                  cover,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (context, error, stackTrace) => widget.poster,
                )
              else
                widget.poster,
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xCC000000)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!compact) _buildTitle(context),
                      if (controller != null && !controller.value.hasError)
                        _buildControls(context, controller, narrow: narrow)
                      else
                        const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              if (controller == null)
                Center(child: _buildPlayButton())
              else if (controller.value.hasError)
                Center(
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: cs.error,
                    size: 36,
                  ),
                )
              else if (!controller.value.isInitialized)
                const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final tags = _tags;
    final title = tags?.title?.trim() ?? '';
    final artist = tags == null ? '' : tags.artists.join(', ');
    final album = tags?.album?.trim() ?? '';
    final subtitle = [artist, album].where((s) => s.isNotEmpty).join(' · ');
    if (title.isEmpty && subtitle.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 24, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayButton() => Material(
    color: Colors.black54,
    shape: const CircleBorder(),
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: _start,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: _starting
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
      ),
    ),
  );

  Widget _buildControls(
    BuildContext context,
    NativeVideoController controller, {
    required bool narrow,
  }) {
    final value = controller.value;
    final durationMs = value.duration.inMilliseconds.toDouble();
    final positionMs = (_dragMs ?? value.position.inMilliseconds.toDouble())
        .clamp(0.0, durationMs > 0 ? durationMs : 1.0);
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          color: Colors.white,
          iconSize: 22,
          icon: Icon(
            value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          ),
          onPressed: value.isInitialized ? () => _togglePlay(controller) : null,
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              min: 0,
              max: durationMs > 0 ? durationMs : 1.0,
              value: positionMs,
              onChanged: durationMs > 0
                  ? (v) => setState(() => _dragMs = v)
                  : null,
              onChangeEnd: (v) async {
                setState(() => _dragMs = null);
                await controller.seekTo(Duration(milliseconds: v.round()));
              },
            ),
          ),
        ),
        if (!narrow)
          Padding(
            padding: const EdgeInsets.only(right: 10, left: 4),
            child: Text(
              '${formatClockDuration(Duration(milliseconds: positionMs.round()))} / ${formatClockDuration(value.duration)}',
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ),
      ],
    );
  }
}
