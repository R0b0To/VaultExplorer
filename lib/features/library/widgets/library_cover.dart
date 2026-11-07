import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/utils/bounded_semaphore.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/data/library_cover_cache.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';
import 'package:vaultexplorer/features/library/tags/audio_tag_reader.dart';
import 'package:vaultexplorer/features/library/tags/byte_source.dart';
import 'package:vaultexplorer/features/library/widgets/music_covers.dart';

/// Reads embedded cover pictures from one container's audio files.
///
/// Covers are fetched only when a tile is actually on screen, a few at a time,
/// and live in a memory-only cache that [dispose] empties. Nothing is written
/// to disk.
class LibraryCoverSource {
  final MountedContainer container;
  final VaultFileIoApi _fileIo;
  final LibraryCoverCache cache;
  final BoundedSemaphore _gate = BoundedSemaphore(3);

  LibraryCoverSource({
    required this.container,
    required this._fileIo,
    LibraryCoverCache? cache,
  }) : cache = cache ?? LibraryCoverCache();

  static String keyFor(LibraryTrack t) => '${t.key}|${t.size}|${t.modifiedSecs}';

  /// The track's cover bytes, or null when it has none or cannot be read.
  Future<Uint8List?> coverFor(LibraryTrack track) {
    return cache.load(keyFor(track), () async {
      await _gate.acquire();
      try {
        final art = await AudioTagReader.readCover(
          _ChunkSource(_fileIo, container, track.path, track.size),
          fileName: track.fileName,
        );
        return art?.bytes;
      } finally {
        _gate.release();
      }
    });
  }

  void dispose() => cache.clear();
}

class _ChunkSource implements ByteSource {
  final VaultFileIoApi _fileIo;
  final MountedContainer _container;
  final String _path;
  final int _size;

  _ChunkSource(this._fileIo, this._container, this._path, this._size);

  @override
  int get length => _size;

  @override
  Future<Uint8List?> read(int offset, int count) =>
      _fileIo.readFileChunk(_container, _path, offset, count);
}

/// A square cover that fills in once its picture has been read.
///
/// [groupKey] (an album or artist key) is checked first for a cover the person
/// chose by hand; otherwise the picture embedded in [track]'s file is used.
class LibraryCover extends StatefulWidget {
  final MusicCovers covers;

  /// The track to take an embedded picture from; null shows the placeholder.
  final LibraryTrack? track;

  /// Album or artist key for a hand-chosen cover (see `albumCoverKey`).
  final String? groupKey;
  final double? size;
  final double borderRadius;
  final IconData placeholderIcon;

  const LibraryCover({
    super.key,
    required this.covers,
    required this.track,
    this.groupKey,
    this.size,
    this.borderRadius = 8,
    this.placeholderIcon = Icons.music_note_rounded,
  });

  @override
  State<LibraryCover> createState() => _LibraryCoverState();
}

class _LibraryCoverState extends State<LibraryCover> {
  Uint8List? _bytes;
  String? _loadingKey;

  @override
  void initState() {
    super.initState();
    widget.covers.revision.addListener(_onRevision);
    _resolve();
  }

  @override
  void dispose() {
    widget.covers.revision.removeListener(_onRevision);
    super.dispose();
  }

  @override
  void didUpdateWidget(LibraryCover old) {
    super.didUpdateWidget(old);
    if (old.covers != widget.covers) {
      old.covers.revision.removeListener(_onRevision);
      widget.covers.revision.addListener(_onRevision);
    }
    final oldKey = old.track == null ? null : LibraryCoverSource.keyFor(old.track!);
    final newKey = widget.track == null ? null : LibraryCoverSource.keyFor(widget.track!);
    if (oldKey != newKey || old.groupKey != widget.groupKey || old.covers != widget.covers) {
      _resolve();
    }
  }

  void _onRevision() {
    if (!mounted) return;
    setState(_resolve);
  }

  void _resolve() {
    final custom = widget.covers.customFor(widget.groupKey);
    if (custom != null) {
      _bytes = custom;
      _loadingKey = null;
      return;
    }
    final track = widget.track;
    if (track == null || !track.hasCover) {
      _bytes = null;
      _loadingKey = null;
      return;
    }
    final source = widget.covers.sourceFor(track.source);
    if (source == null) {
      _bytes = null;
      _loadingKey = null;
      return;
    }
    final key = LibraryCoverSource.keyFor(track);
    if (source.cache.contains(key)) {
      _bytes = source.cache.peek(key);
      _loadingKey = null;
      return;
    }
    _bytes = null;
    _loadingKey = key;
    widget.covers.embeddedFor(track).then((bytes) {
      if (!mounted || _loadingKey != key) return;
      setState(() {
        _bytes = bytes;
        _loadingKey = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(widget.borderRadius);

    Widget placeholder() => ColoredBox(
          color: cs.surfaceContainerHighest,
          child: Center(
            child: Icon(
              widget.placeholderIcon,
              color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              size: widget.size == null ? 32 : widget.size! * 0.5,
            ),
          ),
        );

    final bytes = _bytes;
    final Widget content = bytes == null
        ? placeholder()
        : LayoutBuilder(
            builder: (context, constraints) {
              final dpr = MediaQuery.devicePixelRatioOf(context);
              final logical = widget.size ??
                  (constraints.maxWidth.isFinite ? constraints.maxWidth : 200.0);
              final px = (logical * dpr).round().clamp(64, 1024);
              return Image.memory(
                bytes,
                fit: BoxFit.cover,
                cacheWidth: px,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => placeholder(),
              );
            },
          );

    final framed = ClipRRect(borderRadius: radius, child: content);
    if (widget.size != null) {
      return SizedBox(width: widget.size, height: widget.size, child: framed);
    }
    return AspectRatio(aspectRatio: 1, child: framed);
  }
}
