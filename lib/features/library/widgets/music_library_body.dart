import 'dart:async' show unawaited;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_image_picker_dialog.dart';
import 'package:vaultexplorer/features/browser/widgets/fast_scrollbar.dart';
import 'package:vaultexplorer/features/library/controllers/library_providers.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/controllers/music_mode.dart';
import 'package:vaultexplorer/features/library/index/library_index.dart';
import 'package:vaultexplorer/features/library/index/library_scanner.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';
import 'package:vaultexplorer/features/library/screens/library_detail_screen.dart';
import 'package:vaultexplorer/features/library/widgets/library_cover.dart';
import 'package:vaultexplorer/features/library/widgets/library_widgets.dart';
import 'package:vaultexplorer/features/library/widgets/music_mode_actions.dart';
import 'package:vaultexplorer/features/library/widgets/music_mode_bar.dart';

/// One entry of the sort menu: a criterion index, or null for "reverse order".
class _SortChoice {
  final int? criterion;
  const _SortChoice(this.criterion);
}

/// Remembers the last sorted list so a rebuild that changes nothing relevant
/// (a progress tick, a view switch) does not sort tens of thousands of rows
/// again.
class _SortMemo<T> {
  Object? _index;
  String _query = '';
  Object? _by;
  bool _descending = false;
  List<T>? _result;

  List<T> get(
    Object index,
    String query,
    Object by,
    bool descending,
    List<T> Function() compute,
  ) {
    final hit = _result;
    if (hit != null &&
        identical(_index, index) &&
        _query == query &&
        _by == by &&
        _descending == descending) {
      return hit;
    }
    final fresh = compute();
    _index = index;
    _query = query;
    _by = by;
    _descending = descending;
    _result = fresh;
    return fresh;
  }

  /// Drops the remembered list, so a closed vault's tracks are not kept alive.
  void reset() {
    _index = null;
    _result = null;
  }
}

/// What one category shows: how many items, the widget, and the tracks a
/// "play" or "shuffle" from its header should start (in the order shown).
class _View {
  final int count;
  final Widget content;
  final List<LibraryTrack> Function() playTracks;

  const _View(this.count, this.content, this.playTracks);
}

/// The library views of music mode: Albums, Artists, Genres or Tracks (chosen
/// on the music bar), merged across every location that has music mode on, with
/// a discreet search, sorting, play and shuffle, and a draggable scrollbar.
class MusicLibraryBody extends ConsumerStatefulWidget {
  /// The location of the file manager tab this is shown in. Covers chosen by
  /// hand are saved with it.
  final MountedContainer container;
  final MusicLibrary library;
  final MusicModeEntry entry;

  const MusicLibraryBody({
    super.key,
    required this.container,
    required this.library,
    required this.entry,
  });

  @override
  ConsumerState<MusicLibraryBody> createState() => _MusicLibraryBodyState();
}

class _MusicLibraryBodyState extends ConsumerState<MusicLibraryBody> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searchOpen = false;
  String _query = '';

  AlbumSort _albumSort = AlbumSort.title;
  bool _albumDescending = false;
  ArtistSort _artistSort = ArtistSort.name;
  bool _artistDescending = false;
  TrackSort _trackSort = TrackSort.title;
  bool _trackDescending = false;
  FolderSort _folderSort = FolderSort.name;
  bool _folderDescending = false;
  final _albumMemo = _SortMemo<AlbumGroup>();
  final _artistMemo = _SortMemo<ArtistGroup>();
  final _trackMemo = _SortMemo<LibraryTrack>();
  final _folderMemo = _SortMemo<FolderGroup>();

  final _albumsScroll = ScrollController();
  final _artistsScroll = ScrollController();
  final _genresScroll = ScrollController();
  final _tracksScroll = ScrollController();
  final _foldersScroll = ScrollController();

  MusicHub get _hub => widget.library.hub;

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      if (_search.text != _query) setState(() => _query = _search.text);
    });
  }

  @override
  void dispose() {
    _albumMemo.reset();
    _artistMemo.reset();
    _trackMemo.reset();
    _folderMemo.reset();
    _foldersScroll.dispose();
    _albumsScroll.dispose();
    _artistsScroll.dispose();
    _genresScroll.dispose();
    _tracksScroll.dispose();
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_hub, widget.entry]),
      builder: (context, _) {
        final category = widget.entry.category;
        final index = _hub.index;
        final waiting = index.isEmpty;
        final view = waiting ? null : _viewFor(context, index, category);
        return Column(
          children: [
            _buildHeader(context, category, view),
            if (_hub.isScanning)
              _buildScanBanner(context)
            else
              _buildNotes(context),
            Expanded(
              child: _switchPage(
                category,
                waiting,
                view?.content ?? _buildEmpty(context),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The order of the tabs in the bar, which decides which way a page slides.
  static const _tabOrder = [
    MusicCategory.tracks,
    MusicCategory.albums,
    MusicCategory.artists,
    MusicCategory.genres,
    MusicCategory.folders,
  ];

  MusicCategory? _shown;
  int _slide = 1;

  /// Slides and fades from one library page to the next, towards the side the
  /// new tab is on, instead of cutting.
  Widget _switchPage(MusicCategory category, bool waiting, Widget content) {
    final from = _shown;
    if (from != null && from != category) {
      _slide = _tabOrder.indexOf(category) >= _tabOrder.indexOf(from) ? 1 : -1;
    }
    _shown = category;

    final key = ValueKey<Object>(waiting ? 'waiting' : category);
    return ClipRect(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, animation) {
          // The page coming in starts a little to the side it is on; the one
          // going out leaves towards the opposite side.
          final incoming = child.key == key;
          final dx = 0.12 * _slide;
          final offset = Tween<Offset>(
            begin: Offset(incoming ? dx : -dx, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: KeyedSubtree(key: key, child: content),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final l10n = context.l10n;
    if (_hub.isScanning) return const SizedBox.shrink();
    if (_hub.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return AppEmptyState(
      icon: Icons.music_off_rounded,
      title: l10n.libraryEmptyTitle,
      message: l10n.libraryEmptyMessage,
    );
  }

  // ── Header: summary, play, shuffle, search, sort ─────────────────────────

  String _summary(BuildContext context, MusicCategory category, int count) {
    final l10n = context.l10n;
    return switch (category) {
      MusicCategory.artists => l10n.libraryArtistCount(count),
      MusicCategory.genres => l10n.libraryGenreCount(count),
      MusicCategory.tracks => l10n.libraryTrackCount(count),
      MusicCategory.folders => l10n.libraryFolderCount(count),
      _ => l10n.libraryAlbumCount(count),
    };
  }

  Widget _buildHeader(
    BuildContext context,
    MusicCategory category,
    _View? view,
  ) {
    final l10n = context.l10n;
    final cs = context.colors;
    final searching = _searchOpen || _query.isNotEmpty;
    final canPlay = view != null && view.count > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.xs, 0),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Expanded(
              child: searching
                  ? TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      textInputAction: TextInputAction.search,
                      style: context.typography.bodyMedium,
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: l10n.librarySearchHint,
                        hintStyle: context.typography.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    )
                  : Text(
                      view == null
                          ? ''
                          : _summary(context, category, view.count),
                      style: context.typography.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
            ),
            if (searching)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l10n.close,
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  _search.clear();
                  setState(() => _searchOpen = false);
                },
              )
            else
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l10n.librarySearchHint,
                icon: const Icon(Icons.search_rounded, size: 20),
                onPressed: () {
                  setState(() => _searchOpen = true);
                  _searchFocus.requestFocus();
                },
              ),
            MusicModeMenuButton(
              entry: widget.entry,
              hub: _hub,
              compact: true,
              onEditFolders: () =>
                  unawaited(editMusicFolders(context, ref, widget.container)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l10n.libraryPlayAll,
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: canPlay ? () => _playShown(view) : null,
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l10n.libraryShuffleAll,
              icon: const Icon(Icons.shuffle_rounded, size: 20),
              onPressed: canPlay ? () => _playShown(view, shuffle: true) : null,
            ),
            if (category != MusicCategory.genres)
              _buildSortButton(context, category),
          ],
        ),
      ),
    );
  }

  void _playShown(_View view, {bool shuffle = false}) {
    playLibraryTracks(
      context,
      hub: _hub,
      tracks: view.playTracks(),
      shuffle: shuffle,
    );
  }

  List<String> _sortLabels(BuildContext context, MusicCategory category) {
    final l10n = context.l10n;
    switch (category) {
      case MusicCategory.artists:
        return [l10n.librarySortName, l10n.librarySortTrackCount];
      case MusicCategory.folders:
        return [
          l10n.librarySortName,
          l10n.librarySortTrackCount,
          l10n.librarySortRecentlyAdded,
        ];
      case MusicCategory.tracks:
        return [
          l10n.librarySortTitle,
          l10n.librarySortArtist,
          l10n.librarySortAlbum,
          l10n.librarySortLength,
          l10n.librarySortRecentlyAdded,
        ];
      default:
        return [
          l10n.librarySortTitle,
          l10n.librarySortArtist,
          l10n.librarySortYear,
          l10n.librarySortRecentlyAdded,
        ];
    }
  }

  int _currentSort(MusicCategory category) => switch (category) {
    MusicCategory.artists => _artistSort.index,
    MusicCategory.folders => _folderSort.index,
    MusicCategory.tracks => _trackSort.index,
    _ => _albumSort.index,
  };

  bool _currentDescending(MusicCategory category) => switch (category) {
    MusicCategory.artists => _artistDescending,
    MusicCategory.folders => _folderDescending,
    MusicCategory.tracks => _trackDescending,
    _ => _albumDescending,
  };

  Widget _buildSortButton(BuildContext context, MusicCategory category) {
    final l10n = context.l10n;
    return PopupMenuButton<_SortChoice>(
      tooltip: l10n.librarySortTooltip,
      icon: const Icon(Icons.sort_rounded, size: 20),
      onSelected: (choice) => _applySort(category, choice),
      itemBuilder: (context) {
        final labels = _sortLabels(context, category);
        final selected = _currentSort(category);
        return [
          for (var i = 0; i < labels.length; i++)
            CheckedPopupMenuItem<_SortChoice>(
              value: _SortChoice(i),
              checked: i == selected,
              child: Text(labels[i]),
            ),
          const PopupMenuDivider(),
          CheckedPopupMenuItem<_SortChoice>(
            value: const _SortChoice(null),
            checked: _currentDescending(category),
            child: Text(l10n.librarySortReverse),
          ),
        ];
      },
    );
  }

  /// Picking a criterion starts in its natural direction (newest and biggest
  /// first, names A to Z); "reverse" flips it.
  void _applySort(MusicCategory category, _SortChoice choice) {
    setState(() {
      final i = choice.criterion;
      switch (category) {
        case MusicCategory.artists:
          if (i == null) {
            _artistDescending = !_artistDescending;
          } else {
            _artistSort = ArtistSort.values[i];
            _artistDescending = _artistSort == ArtistSort.trackCount;
          }
        case MusicCategory.folders:
          if (i == null) {
            _folderDescending = !_folderDescending;
          } else {
            _folderSort = FolderSort.values[i];
            _folderDescending = _folderSort != FolderSort.name;
          }
        case MusicCategory.tracks:
          if (i == null) {
            _trackDescending = !_trackDescending;
          } else {
            _trackSort = TrackSort.values[i];
            _trackDescending =
                _trackSort == TrackSort.duration ||
                _trackSort == TrackSort.recentlyAdded;
          }
        default:
          if (i == null) {
            _albumDescending = !_albumDescending;
          } else {
            _albumSort = AlbumSort.values[i];
            _albumDescending = _albumSort == AlbumSort.recentlyAdded;
          }
      }
    });
  }

  // ── Status ───────────────────────────────────────────────────────────────

  Widget _buildScanBanner(BuildContext context) {
    final l10n = context.l10n;
    final p = _hub.progress;
    final String label;
    double? value;
    if (p != null && p.phase == LibraryScanPhase.reading) {
      label = l10n.libraryScanReading(p.read, p.toRead);
      value = p.toRead > 0 ? p.read / p.toRead : null;
    } else {
      label = l10n.libraryScanListing(p?.audioFilesFound ?? 0);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.xs, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typography.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: _hub.cancelAll,
                child: Text(l10n.libraryScanStop),
              ),
            ],
          ),
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: LinearProgressIndicator(value: value),
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
    );
  }

  Widget _buildNotes(BuildContext context) {
    final l10n = context.l10n;
    final lines = [
      if (_hub.walkIncomplete) l10n.libraryIncompleteNote,
      if (_hub.readFailures > 0)
        l10n.libraryReadFailuresNote(_hub.readFailures),
    ];
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 16,
            color: context.colors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              lines.join(' '),
              style: context.typography.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noResults(BuildContext context) => Center(
    child: Text(
      context.l10n.libraryNoResults,
      style: context.typography.bodyMedium?.copyWith(
        color: context.colors.onSurfaceVariant,
      ),
    ),
  );

  // ── Views ────────────────────────────────────────────────────────────────

  _View _viewFor(
    BuildContext context,
    LibraryIndex index,
    MusicCategory category,
  ) {
    return switch (category) {
      MusicCategory.artists => _artists(context, index),
      MusicCategory.genres => _genres(context, index),
      MusicCategory.tracks => _tracks(context, index),
      MusicCategory.folders => _folders(context, index),
      _ => _albums(context, index),
    };
  }

  /// Every track of [groups], each once, in the order the groups are shown.
  static List<LibraryTrack> _flatten(Iterable<List<LibraryTrack>> groups) {
    final seen = <String>{};
    return [
      for (final g in groups)
        for (final t in g)
          if (seen.add(t.key)) t,
    ];
  }

  String? _sourceLabel(LibraryTrack t) =>
      _hub.sourceCount > 1 ? _hub.containerOf(t.source)?.displayName : null;

  _View _albums(BuildContext context, LibraryIndex index) {
    final albums = _albumMemo.get(
      index,
      _query,
      _albumSort,
      _albumDescending,
      () {
        final found = index.searchAlbums(_query);
        if (_albumSort == AlbumSort.title && !_albumDescending) return found;
        return LibrarySorting.albums(
          found,
          _albumSort,
          descending: _albumDescending,
        );
      },
    );
    final covers = widget.library.covers;
    return _View(
      albums.length,
      albums.isEmpty
          ? _noResults(context)
          : FastScrollbar(
              controller: _albumsScroll,
              child: GridView.builder(
                key: const PageStorageKey('music-albums'),
                controller: _albumsScroll,
                padding: const EdgeInsets.all(AppSpacing.md),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 190,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.7,
                ),
                itemCount: albums.length,
                itemBuilder: (context, i) => LibraryAlbumTile(
                  album: albums[i],
                  covers: covers,
                  onTap: () => _openAlbum(albums[i]),
                  onPlay: () => playLibraryTracks(
                    context,
                    hub: _hub,
                    tracks: albums[i].tracks,
                  ),
                ),
              ),
            ),
      () => _flatten([for (final a in albums) a.tracks]),
    );
  }

  _View _artists(BuildContext context, LibraryIndex index) {
    final artists = _artistMemo.get(
      index,
      _query,
      _artistSort,
      _artistDescending,
      () {
        final found = index.searchArtists(_query);
        if (_artistSort == ArtistSort.name && !_artistDescending) return found;
        return LibrarySorting.artists(
          found,
          _artistSort,
          descending: _artistDescending,
        );
      },
    );
    final l10n = context.l10n;
    final covers = widget.library.covers;
    return _View(
      artists.length,
      artists.isEmpty
          ? _noResults(context)
          : FastScrollbar(
              controller: _artistsScroll,
              child: ListView.builder(
                key: const PageStorageKey('music-artists'),
                controller: _artistsScroll,
                itemCount: artists.length,
                itemBuilder: (context, i) {
                  final a = artists[i];
                  final albumCount = index.albumsOfArtist(a).length;
                  return ListTile(
                    contentPadding: const EdgeInsets.only(
                      left: AppSpacing.md,
                      right: AppSpacing.xs,
                    ),
                    leading: LibraryCover(
                      covers: covers,
                      track: a.coverTrack,
                      groupKey: artistCoverKey(a),
                      size: 48,
                      borderRadius: 24,
                      placeholderIcon: Icons.person_rounded,
                    ),
                    title: Text(
                      libraryArtistLabel(context, a.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${l10n.libraryAlbumCount(albumCount)} · ${l10n.libraryTrackCount(a.tracks.length)}',
                    ),
                    trailing: _quickPlay(a.tracks),
                    onTap: () => _openArtist(index, a),
                  );
                },
              ),
            ),
      () => _flatten([for (final a in artists) a.tracks]),
    );
  }

  _View _genres(BuildContext context, LibraryIndex index) {
    final genres = index.searchGenres(_query);
    final l10n = context.l10n;
    return _View(
      genres.length,
      genres.isEmpty
          ? _noResults(context)
          : FastScrollbar(
              controller: _genresScroll,
              child: ListView.builder(
                key: const PageStorageKey('music-genres'),
                controller: _genresScroll,
                itemCount: genres.length,
                itemBuilder: (context, i) {
                  final g = genres[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.only(
                      left: AppSpacing.md,
                      right: AppSpacing.xs,
                    ),
                    leading: const CircleAvatar(
                      child: Icon(Icons.piano_rounded),
                    ),
                    title: Text(
                      libraryGenreLabel(context, g.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(l10n.libraryTrackCount(g.tracks.length)),
                    trailing: _quickPlay(g.tracks),
                    onTap: () => _openGenre(index, g),
                  );
                },
              ),
            ),
      () => _flatten([for (final g in genres) g.tracks]),
    );
  }

  /// Small play and shuffle buttons at the end of a list row.
  Widget _quickPlay(List<LibraryTrack> tracks) {
    final l10n = context.l10n;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l10n.libraryPlayAll,
          icon: const Icon(Icons.play_arrow_rounded),
          onPressed: () =>
              playLibraryTracks(context, hub: _hub, tracks: tracks),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l10n.libraryShuffleAll,
          icon: const Icon(Icons.shuffle_rounded, size: 20),
          onPressed: () => playLibraryTracks(
            context,
            hub: _hub,
            tracks: tracks,
            shuffle: true,
          ),
        ),
      ],
    );
  }

  /// Folders that directly hold audio, nothing else: where the music lives, not
  /// a copy of the file tree.
  _View _folders(BuildContext context, LibraryIndex index) {
    final folders = _folderMemo.get(
      index,
      _query,
      _folderSort,
      _folderDescending,
      () {
        final found = index.searchFolders(_query);
        if (_folderSort == FolderSort.name && !_folderDescending) return found;
        return LibrarySorting.folders(
          found,
          _folderSort,
          descending: _folderDescending,
        );
      },
    );
    final l10n = context.l10n;
    final covers = widget.library.covers;
    return _View(
      folders.length,
      folders.isEmpty
          ? _noResults(context)
          : FastScrollbar(
              controller: _foldersScroll,
              child: ListView.builder(
                key: const PageStorageKey('music-folders'),
                controller: _foldersScroll,
                itemCount: folders.length,
                itemBuilder: (context, i) {
                  final f = folders[i];
                  final album = f.tracks.isEmpty
                      ? null
                      : index.albumOf(f.tracks.first);
                  final source = _hub.sourceCount > 1
                      ? _hub.containerOf(f.source)?.displayName
                      : null;
                  final where = [
                    if (f.parentPath.isNotEmpty) f.parentPath,
                    l10n.libraryTrackCount(f.tracks.length),
                    if (source != null) source,
                  ].join(' · ');
                  return ListTile(
                    contentPadding: const EdgeInsets.only(
                      left: AppSpacing.md,
                      right: AppSpacing.xs,
                    ),
                    leading: LibraryCover(
                      covers: covers,
                      track: album?.coverTrack ?? f.coverTrack,
                      groupKey: album == null ? null : albumCoverKey(album),
                      size: 48,
                      borderRadius: 8,
                      placeholderIcon: Icons.folder_rounded,
                    ),
                    title: Text(
                      _folderLabel(f),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      where,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: _quickPlay(f.tracks),
                    onTap: () => _openFolder(index, f),
                  );
                },
              ),
            ),
      () => _flatten([for (final f in folders) f.tracks]),
    );
  }

  /// A folder's name; the container's own name for files sitting in its root.
  String _folderLabel(FolderGroup f) {
    if (!f.isRoot) return f.name;
    return _hub.containerOf(f.source)?.displayName ?? '/';
  }

  _View _tracks(BuildContext context, LibraryIndex index) {
    final tracks = _trackMemo.get(
      index,
      _query,
      _trackSort,
      _trackDescending,
      () {
        final found = index.searchTracks(_query);
        if (_trackSort == TrackSort.title && !_trackDescending) return found;
        return LibrarySorting.tracks(
          found,
          _trackSort,
          descending: _trackDescending,
        );
      },
    );
    final covers = widget.library.covers;
    return _View(
      tracks.length,
      tracks.isEmpty
          ? _noResults(context)
          : FastScrollbar(
              controller: _tracksScroll,
              child: ListView.builder(
                key: const PageStorageKey('music-tracks'),
                controller: _tracksScroll,
                itemExtent: 72,
                itemCount: tracks.length,
                itemBuilder: (context, i) {
                  final t = tracks[i];
                  // Draw the album's cover, not the track's own, so every track
                  // of an album shares one cached picture instead of each
                  // reading its own.
                  final album = index.albumOf(t);
                  return LibraryTrackTile(
                    track: t,
                    covers: covers,
                    coverTrack: album?.coverTrack ?? (t.hasCover ? t : null),
                    coverGroupKey: album == null ? null : albumCoverKey(album),
                    sourceLabel: _sourceLabel(t),
                    onTap: () => playLibraryTracks(
                      context,
                      hub: _hub,
                      tracks: tracks,
                      startIndex: i,
                    ),
                  );
                },
              ),
            ),
      () => tracks,
    );
  }

  // ── Navigation and covers ────────────────────────────────────────────────

  void _push(Widget screen) {
    Navigator.of(
      context,
    ).push(LibraryDetailRoute<void>(builder: (_) => screen));
  }

  /// Back to the library itself, closing any folder / album / artist / genre
  /// screens that were opened over it.
  void _popDetails() {
    Navigator.of(context).popUntil((route) => route is! LibraryDetailRoute);
  }

  /// The music mode bar for the detail screens, so they keep the library's
  /// views one tap away (picking one returns to the library first).
  Widget _detailBar() => MusicModeBar(
    entry: widget.entry,
    hub: _hub,
    onSelectCategory: (category) {
      _popDetails();
      widget.entry.setCategory(category);
    },
    onToggleMode: () {
      _popDetails();
      unawaited(toggleMusicMode(context, ref, widget.container));
    },
    onEditFolders: () =>
        unawaited(editMusicFolders(context, ref, widget.container)),
  );

  void _openAlbum(AlbumGroup a) {
    final index = _hub.index;
    _push(
      LibraryDetailScreen(
        hub: _hub,
        modeBar: _detailBar(),
        covers: widget.library.covers,
        title: libraryAlbumTitle(context, a),
        subtitle: libraryAlbumSubtitle(context, a),
        coverTrack: a.coverTrack,
        tracks: a.tracks,
        numbered: true,
        placeholderIcon: Icons.album_rounded,
        coverKey: albumCoverKey(a),
        onChooseCover: () => _chooseCover(
          albumCoverKey(a),
          a.tracks.isEmpty ? null : a.tracks.first,
        ),
        coverOf: (t) => index.albumOf(t)?.coverTrack,
      ),
    );
  }

  void _openArtist(LibraryIndex index, ArtistGroup a) {
    _push(
      LibraryDetailScreen(
        hub: _hub,
        modeBar: _detailBar(),
        covers: widget.library.covers,
        title: libraryArtistLabel(context, a.name),
        subtitle: '',
        coverTrack: a.coverTrack,
        tracks: a.tracks,
        albums: index.albumsOfArtist(a),
        onOpenAlbum: _openAlbum,
        coverOf: (t) => index.albumOf(t)?.coverTrack,
        placeholderIcon: Icons.person_rounded,
        coverKey: artistCoverKey(a),
        onChooseCover: () => _chooseCover(
          artistCoverKey(a),
          a.tracks.isEmpty ? null : a.tracks.first,
        ),
      ),
    );
  }

  void _openFolder(LibraryIndex index, FolderGroup f) {
    _push(
      LibraryDetailScreen(
        hub: _hub,
        modeBar: _detailBar(),
        covers: widget.library.covers,
        title: _folderLabel(f),
        subtitle: f.parentPath,
        coverTrack: f.coverTrack,
        tracks: f.tracks,
        coverOf: (t) => index.albumOf(t)?.coverTrack,
        placeholderIcon: Icons.folder_rounded,
      ),
    );
  }

  void _openGenre(LibraryIndex index, GenreGroup g) {
    LibraryTrack? cover;
    for (final t in g.tracks) {
      if (t.hasCover) {
        cover = t;
        break;
      }
    }
    _push(
      LibraryDetailScreen(
        hub: _hub,
        modeBar: _detailBar(),
        covers: widget.library.covers,
        title: libraryGenreLabel(context, g.name),
        subtitle: '',
        coverTrack: cover,
        tracks: g.tracks,
        coverOf: (t) => index.albumOf(t)?.coverTrack,
        placeholderIcon: Icons.piano_rounded,
      ),
    );
  }

  /// Lets the person pick an image from this location's own files as the cover
  /// for [key], starting in the folder of [hint]'s file when it is in this
  /// location. The app has no internet, so this is how a missing cover is
  /// filled in.
  Future<void> _chooseCover(String key, LibraryTrack? hint) async {
    final home = widget.container;
    final fileIo = ref.read(vaultFileIoApiProvider);
    final covers = widget.library.covers;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);

    final startFile = (hint != null && hint.source == home.uri)
        ? hint.path
        : 'x';
    final picked = await showMarkdownImagePicker(
      context: context,
      container: home,
      markdownFilePath: startFile,
    );
    if (picked == null) return;

    final Uint8List? bytes = await fileIo.readWholeFile(home, picked);
    final saved = bytes != null && await covers.setCustom(home, key, bytes);
    if (!saved) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.musicCoverFailed)));
    }
  }
}
