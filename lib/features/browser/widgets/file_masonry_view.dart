import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/services/playback_throttle_controller.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/core/utils/file_display_name.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/media_aspect_ratio_cache.dart';
import 'package:vaultexplorer/data/services/media_index/media_index.dart';
import 'package:vaultexplorer/data/services/media_index/media_index_providers.dart';
import 'package:vaultexplorer/data/services/media_index/media_index_service.dart';
import 'package:vaultexplorer/data/services/media_index/media_path_hash.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_layout.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_ratio_prefetcher.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_sliver.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/widgets/apk_icon_support.dart';
import 'package:vaultexplorer/features/browser/widgets/archive_thumbnail_support.dart';
import 'package:vaultexplorer/features/browser/widgets/book_cover_support.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drag.dart';
import 'package:vaultexplorer/features/browser/widgets/fast_scrollbar.dart';
import 'package:vaultexplorer/features/browser/widgets/folder_thumbnail_preview.dart';
import 'package:vaultexplorer/features/browser/widgets/gallery_date_header.dart';
import 'package:vaultexplorer/features/browser/widgets/grid_card_shell.dart';
import 'package:vaultexplorer/features/browser/widgets/hold_range_select_container.dart';
import 'package:vaultexplorer/features/browser/widgets/thumbnail_raw_fallback.dart';

class FileMasonryView extends ConsumerStatefulWidget {
  final MountedContainer container;
  final List<RawEntry> items;
  final bool isSelectionMode;
  final Set<RawEntry> selectedItems;
  final String currentDirPath;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;

  /// Card corner radius and the gap between cards, from the user's grid
  /// appearance settings. Defaults are the original look.
  final double cornerRadius;
  final double spacing;
  final bool showFileNames;

  /// Whether file names are captioned with their extension. Off hides it,
  /// except while a search is typed so a match inside it stays visible.
  final bool showFileExtensions;
  final LongFileNameDisplayMode longFileNameMode;
  final int initialColumns;
  final ValueChanged<int>? onColumnCountChanged;
  final ValueChanged<RawEntry> onDirTap;
  final ValueChanged<RawEntry> onFileTap;
  final ValueChanged<RawEntry> onItemLongPress;
  final ValueChanged<RawEntry>? onFileLongMenu;

  /// Whether cards show the 3-dots actions button (the same toggle the list
  /// layout uses).
  final bool showItemActionsMenu;
  final ValueChanged<Set<RawEntry>>? onSelectionChanged;
  final bool enableFileDrag;
  final BrowserItemDropHandler? onFileDrop;
  final String? searchQuery;
  final Set<String> mountedFolderPaths;
  final bool Function(RawEntry entry)? isPinned;
  final bool Function(RawEntry entry)? isBookmark;
  final bool Function(RawEntry entry)? isFolderSynced;
  final ScrollController? scrollController;
  final double bottomClearance;
  final bool groupByDate;

  final ArchiveContext? archiveContext;
  final String? archiveRootPath;
  final SortBy? sortBy;

  /// Resolves the container an entry lives in, for a listing that gathers
  /// files from several containers (the category browser). When null every
  /// entry belongs to [container], as in any ordinary folder listing.
  final MountedContainer Function(RawEntry entry)? containerFor;

  /// The thumbnail cache policy that applies to an entry, for a listing that
  /// mixes containers whose owners chose different policies (the category
  /// browser). When null every entry follows [thumbnailCacheMode].
  final ThumbnailCacheMode Function(RawEntry entry)? cacheModeFor;

  /// The thumbnail quality that applies to an entry, for a listing that
  /// mixes containers whose owners chose different qualities (the category
  /// browser). When null every entry follows [thumbnailQuality].
  final ThumbnailQuality Function(RawEntry entry)? qualityFor;

  const FileMasonryView({
    super.key,
    required this.container,
    required this.items,
    required this.isSelectionMode,
    required this.selectedItems,
    required this.currentDirPath,
    required this.thumbnailCacheMode,
    required this.thumbnailQuality,
    this.cornerRadius = 12.0,
    this.spacing = 8.0,
    this.showFileNames = true,
    this.showFileExtensions = true,
    this.longFileNameMode = LongFileNameDisplayMode.ellipsizeEnd,
    this.initialColumns = 2,
    this.onColumnCountChanged,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    this.onFileLongMenu,
    this.showItemActionsMenu = true,
    this.onSelectionChanged,
    this.enableFileDrag = false,
    this.onFileDrop,
    this.searchQuery,
    this.mountedFolderPaths = const {},
    this.isPinned,
    this.isBookmark,
    this.isFolderSynced,
    this.scrollController,
    this.bottomClearance = 0.0,
    this.groupByDate = false,
    this.archiveContext,
    this.archiveRootPath,
    this.sortBy,
    this.containerFor,
    this.cacheModeFor,
    this.qualityFor,
  });

  @override
  ConsumerState<FileMasonryView> createState() => _FileMasonryViewState();
}

class _FileMasonryViewState extends ConsumerState<FileMasonryView>
    with SingleTickerProviderStateMixin {
  /// How the masonry view lays tiles out. [GalleryFlow.rows] is the justified
  /// "mosaic" (every row fills the width, each tile keeps its picture's
  /// proportions); [GalleryFlow.columns] is the original column-based masonry.
  /// Everything else in this file works for either.
  static const GalleryFlow _flow = GalleryFlow.rows;

  MountedContainer _containerOf(RawEntry entry) =>
      widget.containerFor?.call(entry) ?? widget.container;

  ThumbnailCacheMode _cacheModeOf(RawEntry entry) =>
      widget.cacheModeFor?.call(entry) ?? widget.thumbnailCacheMode;

  Orientation? _lastOrientation;
  late int _columnCount;
  double _baselineScale = 1.0;
  late final ThumbnailCacheService _thumbnailCache;
  late final GalleryRatioPrefetcher _prefetcher;
  TextScaler _textScaler = TextScaler.noScaling;

  // ── Display model ──────────────────────────────────────────────────────────
  // Everything the layout needs, as flat arrays indexed by *display* index (the
  // order tiles appear in: the items themselves, or the date groups'
  // concatenation). Rebuilt when the items change, never per frame.
  final GalleryLayoutHost _host = GalleryLayoutHost(flow: _flow);
  List<RawEntry> _display = const [];

  /// Display index -> index in `widget.items` (null = identical, no grouping).
  Int32List? _displayGlobal;
  List<DateGroup<RawEntry>>? _groups;

  /// 0: icon/folder cell (always square, always captioned); 1: an image whose
  /// size can be probed from its headers; 2: other media (video, book cover,
  /// an image inside an archive) whose size is learned from its thumbnail.
  Uint8List _kind = Uint8List(0);
  Float32List _ratio = Float32List(0);

  /// 1 once [_ratio] is a real measurement rather than a default.
  Uint8List _known = Uint8List(0);
  List<GallerySection> _sections = const [];

  /// Child index -> display index (-1 = a date header); null when ungrouped,
  /// where child index == display index.
  Int32List? _childItem;
  Int32List? _childSection;
  int _childCount = 0;
  double _headerExtent = 56.0;

  // ── Ratio learning and reflow ──────────────────────────────────────────────
  bool _ratiosDirty = false;
  Timer? _flushTimer;
  Timer? _followTimer;
  bool _diskPreloadRunning = false;

  /// Only decides how a reflow is applied (see [GalleryLayoutHost.reflow]);
  /// nothing in this view waits for it to become false.
  bool _isScrolling = false;

  // ── The persisted media index ──────────────────────────────────────────────
  late final MediaIndexService _index;

  /// Display index -> [MediaPathHash] of the file (media items only).
  Int64List _pathHash = Int64List(0);

  /// 1 once this item's size is stored in the media index (loaded from it, or
  /// recorded into it), so a tile that is rebuilt does not look it up again.
  Uint8List _inIndex = Uint8List(0);

  /// Media items whose real size is not known yet.
  int _unknownVisuals = 0;

  /// The index of every container shown here has been loaded. Until then the
  /// view shows nothing (a moment, once per unlock) instead of a layout that
  /// would reshuffle when the stored sizes arrive.
  bool _indexReady = false;
  int _indexGeneration = 0;
  Map<String, (MountedContainer, ThumbnailCacheMode)> _indexTargets = const {};

  /// Kept for the whole pinch so continuous zooming cannot drift.
  GalleryAnchor? _zoomAnchor;

  /// The scroll offset this view was opened at (going back to a folder),
  /// until it has been reached. See [_restoreInitialScrollOffset].
  double? _pendingInitialOffset;
  int _initialOffsetAttemptsLeft = 0;

  // Animation controller for smooth column transition morph
  late final AnimationController _morphController;
  late Animation<double> _scaleAnimation;

  static const double _kSideInset = 10.0;
  static const double _kGroupGap = 12.0;

  // Rows can show a wide panorama or a tall portrait without cropping it to
  // death; the column flow always had a tighter range.
  static double get _minRatio => _flow == GalleryFlow.rows ? 0.4 : 0.5;
  static double get _maxRatio => _flow == GalleryFlow.rows ? 3.2 : 2.2;
  static const _iconRatio = 1.0;
  static const _imageDefaultRatio = 1.0;
  static const _videoDefaultRatio = 16.0 / 9.0;
  // Until a book's cover size is known (and for a book with no cover).
  static const _bookDefaultRatio = 2.0 / 3.0;

  @override
  void initState() {
    super.initState();
    _thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    _index = ref.read(mediaIndexServiceProvider);
    _columnCount = widget.initialColumns;
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    _prefetcher = GalleryRatioPrefetcher(probe: fileIoApi.probeImageDimensions);

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1.0,
    );
    _scaleAnimation = const AlwaysStoppedAnimation<double>(1.0);

    _rebuildDisplay();
    _scheduleInitialScrollOffsetRestore();
    _afterDisplayRebuilt();
  }

  @override
  void dispose() {
    _prefetcher.stop();
    _indexGeneration++;
    _flushTimer?.cancel();
    _followTimer?.cancel();
    _morphController.dispose();
    super.dispose();
  }

  /// Going back to a folder opens it with a controller whose
  /// `initialScrollOffset` is where the folder was left. The layout is exact
  /// from the first frame, so the offset is normally reached at once; this only
  /// re-applies it with `jumpTo` if the first layout ended up somewhere else.
  void _scheduleInitialScrollOffsetRestore() {
    final controller = widget.scrollController;
    if (controller == null || controller.hasClients) return;
    final target = controller.initialScrollOffset;
    if (target <= 0) return;
    _pendingInitialOffset = target;
    _initialOffsetAttemptsLeft = 10;
    WidgetsBinding.instance.addPostFrameCallback(_restoreInitialScrollOffset);
  }

  void _restoreInitialScrollOffset(Duration _) {
    final target = _pendingInitialOffset;
    final controller = widget.scrollController;
    if (!mounted || target == null || controller == null) {
      _pendingInitialOffset = null;
      return;
    }
    var reached = false;
    if (controller.hasClients && controller.position.hasContentDimensions) {
      final position = controller.position;
      final clamped = math.min(target, position.maxScrollExtent);
      if ((position.pixels - clamped).abs() > 0.5) controller.jumpTo(clamped);
      reached = (target - clamped).abs() <= 0.5;
    }
    if (reached || --_initialOffsetAttemptsLeft <= 0) {
      _pendingInitialOffset = null;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback(_restoreInitialScrollOffset);
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Runs for *every* MediaQuery change (the keyboard animating, for one), so
    // only touch the layout when something it depends on really changed.
    var layoutInputsChanged = false;
    final textScaler = MediaQuery.textScalerOf(context);
    if (textScaler != _textScaler) {
      _textScaler = textScaler;
      layoutInputsChanged = true;
    }
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != orientation) {
      _columnCount = widget.initialColumns.clamp(_minColumns, _maxColumns);
      _lastOrientation = orientation;
      layoutInputsChanged = true;
    }
    final headerExtent = _computeHeaderExtent(context);
    if (headerExtent != _headerExtent) {
      _headerExtent = headerExtent;
      _sections = _buildSections();
      layoutInputsChanged = true;
    }
    if (layoutInputsChanged) _syncHost();
  }

  @override
  void didUpdateWidget(covariant FileMasonryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialColumns != widget.initialColumns) {
      final newCols = widget.initialColumns.clamp(_minColumns, _maxColumns);
      if (newCols != _columnCount) {
        _changeColumns(newCols, 1.0);
      }
    }
    if (oldWidget.currentDirPath != widget.currentDirPath ||
        oldWidget.items != widget.items ||
        oldWidget.groupByDate != widget.groupByDate ||
        oldWidget.archiveContext != widget.archiveContext) {
      _rebuildDisplay();
      _afterDisplayRebuilt();
    } else if (oldWidget.thumbnailCacheMode != widget.thumbnailCacheMode) {
      // The caching mode decides whether the media index may be saved.
      _rebuildDisplay();
      _afterDisplayRebuilt();
    } else if (oldWidget.showFileNames != widget.showFileNames ||
        oldWidget.showItemActionsMenu != widget.showItemActionsMenu ||
        oldWidget.spacing != widget.spacing ||
        (oldWidget.onFileLongMenu == null) != (widget.onFileLongMenu == null)) {
      _syncHost();
    }
  }

  // ── Layout inputs ──────────────────────────────────────────────────────────

  String _fullPathOf(RawEntry entry) => widget.currentDirPath.isEmpty
      ? entry.name
      : '${widget.currentDirPath}/${entry.name}';

  int _globalIndexOf(int displayIndex) =>
      _displayGlobal == null ? displayIndex : _displayGlobal![displayIndex];

  double _clampRatio(double ratio) =>
      ratio.clamp(_minRatio, _maxRatio).toDouble();

  double _defaultRatioFor(String fileName) {
    if (MediaViewerConstants.isVideo(fileName)) {
      return _clampRatio(_videoDefaultRatio);
    }
    if (isBookWithCover(fileName)) return _clampRatio(_bookDefaultRatio);
    return _clampRatio(_imageDefaultRatio);
  }

  /// Height of the `GridCardShell` footer (the file-name row) under a preview.
  /// Only an estimate: the card is handed a fixed height and the preview takes
  /// whatever the real footer leaves.
  double _footerHeight(double tileWidth) {
    final lineHeight = _textScaler.scale(16.0);
    final hasMoreSlot =
        widget.showItemActionsMenu && widget.onFileLongMenu != null;
    if (hasMoreSlot) {
      final compact = tileWidth < 100;
      final slot = compact ? 24.0 + 8.0 : 28.0 + 6.0;
      return math.max(slot, lineHeight + 6.0);
    }
    return 18.0 + lineHeight;
  }

  double _footerOf(int displayIndex, double tileWidth) {
    final showName = _kind[displayIndex] == 0 || widget.showFileNames;
    return showName ? _footerHeight(tileWidth) : 0.0;
  }

  double _ratioOf(int displayIndex) => _ratio[displayIndex];

  /// Height of a date header: `GalleryDateHeader`'s padding plus one line of
  /// the title style, plus a little air above the first row of the day.
  double _computeHeaderExtent(BuildContext context) =>
      galleryDateHeaderExtent(context);

  List<GallerySection> _buildSections() {
    final groups = _groups;
    if (groups == null) return [GallerySection(itemCount: _display.length)];
    return [
      for (final g in groups)
        GallerySection(itemCount: g.items.length, headerExtent: _headerExtent),
    ];
  }

  /// Pushes the view's current settings into the layout host and invalidates it.
  void _syncHost() {
    _host
      ..columnCount = _columnCount
      ..spacing = widget.spacing
      ..sectionGap = _groups == null ? 0.0 : _kGroupGap
      ..minTileWidth = 72.0
      ..sections = _sections
      ..ratioOf = _ratioOf
      ..footerOf = _footerOf
      ..invalidate();
  }

  /// Rebuilds every per-item array for the current items. O(items); runs when
  /// the list changes, never while scrolling.
  void _rebuildDisplay() {
    final items = widget.items;
    List<RawEntry> display;
    Int32List? global;
    List<DateGroup<RawEntry>>? groups;
    if (widget.groupByDate) {
      groups = computeDateGroups(items);
      display = <RawEntry>[];
      global = Int32List(items.length);
      var k = 0;
      for (final g in groups) {
        for (var j = 0; j < g.items.length; j++) {
          display.add(g.items[j]);
          global[k++] = g.globalIndices[j];
        }
      }
    } else {
      display = items;
    }
    _display = display;
    _displayGlobal = global;
    _groups = groups;

    final n = display.length;
    _kind = Uint8List(n);
    _ratio = Float32List(n);
    _known = Uint8List(n);
    _pathHash = Int64List(n);
    _inIndex = Uint8List(n);
    _unknownVisuals = 0;

    // Sizes already learned for this directory: from the media index (valid
    // only for the file as it is now: same size, same modified time), else
    // from what this session has seen. One lookup per item, no path strings.
    final dirState = MediaPathHash.stateOfDir(widget.currentDirPath);
    final targets = <String, (MountedContainer, ThumbnailCacheMode)>{};
    final memoryLookups = <String, double? Function(String)>{};
    for (var i = 0; i < n; i++) {
      final entry = display[i];
      if (entry.isDir || !_hasVisualPreview(entry.name)) {
        _ratio[i] = _iconRatio;
        _known[i] = 1;
        continue;
      }
      final probeable =
          widget.archiveContext == null &&
          MediaViewerConstants.isImage(entry.name);
      _kind[i] = probeable ? 1 : 2;
      final container = _containerOf(entry);
      targets.putIfAbsent(container.uri, () => (container, _cacheModeOf(entry)));
      final hash = MediaPathHash.ofName(dirState, entry.name);
      _pathHash[i] = hash;

      final packed = _index.lookup(
        container,
        hash,
        entry.sizeBytes,
        entry.modifiedSecs,
      );
      if (packed != 0) {
        _ratio[i] = _clampRatio(
          MediaIndex.widthOf(packed) / MediaIndex.heightOf(packed),
        );
        _known[i] = 1;
        _inIndex[i] = 1;
        continue;
      }
      final lookup = memoryLookups.putIfAbsent(
        container.uri,
        () => MediaAspectRatioCache.lookupIn(container, widget.currentDirPath),
      );
      final learned = lookup(entry.name);
      if (learned != null) {
        _ratio[i] = _clampRatio(learned);
        _known[i] = 1;
      } else {
        _ratio[i] = _defaultRatioFor(entry.name);
        _unknownVisuals++;
      }
    }
    _indexTargets = targets;
    _indexReady = targets.values.every((t) => _index.isReady(t.$1));

    // Child index space: a header child per group, then its items.
    _sections = _buildSections();
    if (groups == null) {
      _childItem = null;
      _childSection = null;
      _childCount = n;
    } else {
      _childCount = n + groups.length;
      final childItem = Int32List(_childCount);
      final childSection = Int32List(_childCount);
      var c = 0;
      var item = 0;
      for (var s = 0; s < groups.length; s++) {
        childItem[c] = -1;
        childSection[c] = s;
        c++;
        for (var j = 0; j < groups[s].items.length; j++) {
          childItem[c] = item++;
          childSection[c] = s;
          c++;
        }
      }
      _childItem = childItem;
      _childSection = childSection;
    }

    _ratiosDirty = false;
    _flushTimer?.cancel();
    _syncHost();
  }

  // ── The media index ────────────────────────────────────────────────────────

  /// What the media index may do for [container]: nothing for phone storage
  /// (it must not get a hidden folder dropped into it), read but not write for
  /// a read-only vault or when thumbnail caching is off, otherwise read and
  /// save (inside the vault, see [MediaIndexService]).
  MediaIndexAccess _indexAccessFor(
    MountedContainer container,
    ThumbnailCacheMode mode,
  ) {
    if (container.isLocalStorage) return MediaIndexAccess.memoryOnly;
    if (container.readOnly || mode == ThumbnailCacheMode.disabled) {
      return MediaIndexAccess.readOnly;
    }
    return MediaIndexAccess.readWrite;
  }

  /// Everything that has to happen after [_rebuildDisplay]: make sure the media
  /// index of every container shown is loaded (instantly after the first time
  /// per unlock), then start measuring what it does not know.
  void _afterDisplayRebuilt() {
    final generation = ++_indexGeneration;
    final futures = <Future<void>>[];
    for (final (container, mode) in _indexTargets.values) {
      futures.add(_index.attach(container, _indexAccessFor(container, mode)));
    }
    if (_indexReady) {
      _startProbing();
      _ensureFollowTimer();
      return;
    }
    unawaited(() async {
      final loaded = Future.wait(futures);
      // Normally this takes a few milliseconds. If the storage is slow, do not
      // keep the screen empty: show the layout with default shapes and bring in
      // the stored sizes (an anchored reflow) when they arrive.
      final slow = Completer<void>();
      final timer = Timer(const Duration(milliseconds: 400), () {
        if (!slow.isCompleted) slow.complete();
      });
      await Future.any([loaded, slow.future]);
      timer.cancel();
      if (!mounted || generation != _indexGeneration) return;
      final allLoaded = _indexTargets.values.every((t) => _index.isReady(t.$1));
      if (allLoaded) {
        _hydrateFromIndex();
        _syncHost();
      }
      _indexReady = true;
      setState(() {});
      if (allLoaded) {
        _startProbing();
        _ensureFollowTimer();
        return;
      }
      await loaded;
      if (!mounted || generation != _indexGeneration) return;
      _hydrateFromIndex();
      _ratiosDirty = true;
      _scheduleFlush();
      _startProbing();
      _ensureFollowTimer();
    }());
  }

  /// Takes the sizes the index has for items that were built before it was
  /// loaded.
  void _hydrateFromIndex() {
    for (var i = 0; i < _display.length; i++) {
      if (_kind[i] == 0 || _inIndex[i] == 1) continue;
      final entry = _display[i];
      final packed = _index.lookup(
        _containerOf(entry),
        _pathHash[i],
        entry.sizeBytes,
        entry.modifiedSecs,
      );
      if (packed == 0) continue;
      if (_known[i] == 0) _unknownVisuals--;
      _ratio[i] = _clampRatio(
        MediaIndex.widthOf(packed) / MediaIndex.heightOf(packed),
      );
      _known[i] = 1;
      _inIndex[i] = 1;
    }
  }

  /// Remembers a measured size for later sessions (and the media viewer).
  void _remember(
    int displayIndex,
    RawEntry entry,
    MountedContainer container,
    String fullPath,
    int width,
    int height,
  ) {
    MediaAspectRatioCache.put(container, fullPath, width, height);
    final sameEntry =
        displayIndex >= 0 &&
        displayIndex < _display.length &&
        identical(_display[displayIndex], entry);
    if (sameEntry && _inIndex[displayIndex] == 1) return;
    final hash = sameEntry
        ? _pathHash[displayIndex]
        : MediaPathHash.ofPath(fullPath);
    _index.record(
      container,
      hash,
      entry.sizeBytes,
      entry.modifiedSecs,
      width,
      height,
    );
    if (sameEntry) _inIndex[displayIndex] = 1;
  }

  // ── Learning ratios ────────────────────────────────────────────────────────

  /// Records a measured size for display item [displayIndex]. Cheap and safe to
  /// call from `build`: it only updates arrays and schedules a flush.
  void _applyRatio(int displayIndex, double rawRatio) {
    if (displayIndex < 0 || displayIndex >= _ratio.length) return;
    final ratio = _clampRatio(rawRatio);
    if (_known[displayIndex] == 1 &&
        (_ratio[displayIndex] - ratio).abs() < 0.004) {
      return;
    }
    if (_known[displayIndex] == 0 && _kind[displayIndex] != 0) {
      _unknownVisuals--;
    }
    _known[displayIndex] = 1;
    _ratio[displayIndex] = ratio;
    _ratiosDirty = true;
    _scheduleFlush();
  }

  /// A thumbnail finished decoding for [entry]: its size is the truth.
  void _onSizeKnown(
    int displayIndex,
    RawEntry entry,
    String fullPath,
    int width,
    int height, {
    required MountedContainer container,
  }) {
    if (width <= 0 || height <= 0) return;
    final sameEntry =
        displayIndex >= 0 &&
        displayIndex < _display.length &&
        identical(_display[displayIndex], entry);
    if (sameEntry && _known[displayIndex] == 1) {
      // Tiles report their size every time they are built: the common case is
      // that nothing is new.
      final same =
          (_ratio[displayIndex] - _clampRatio(width / height)).abs() < 0.004;
      if (same && _inIndex[displayIndex] == 1) return;
      if (!same) _inIndex[displayIndex] = 0;
    }
    _remember(displayIndex, entry, container, fullPath, width, height);
    if (sameEntry) _applyRatio(displayIndex, width / height);
  }

  /// Sizes from the header probe.
  void _onProbed(int displayIndex, int width, int height) {
    if (!mounted || displayIndex >= _display.length) return;
    final entry = _display[displayIndex];
    _remember(
      displayIndex,
      entry,
      _containerOf(entry),
      _fullPathOf(entry),
      width,
      height,
    );
    _applyRatio(displayIndex, width / height);
  }

  void _learnFromMemoryCache(int displayIndex, RawEntry entry, String path) {
    final cached = _thumbnailCache.peekMemoryWithSize(
      _containerOf(entry),
      path,
      widget.thumbnailQuality,
    );
    if (cached == null) return;
    final w = cached.$2;
    final h = cached.$3;
    if (w == null || h == null || w <= 0 || h <= 0) return;
    _remember(displayIndex, entry, _containerOf(entry), path, w, h);
    _applyRatio(displayIndex, w / h);
  }

  void _scheduleFlush([Duration delay = const Duration(milliseconds: 100)]) {
    if (_flushTimer?.isActive ?? false) return;
    _flushTimer = Timer(delay, _flush);
  }

  /// Applies the sizes learned since the last flush. Never waits for a scroll
  /// to end: what is on screen is correct as soon as this runs.
  ///
  /// While the user scrolls, the layout is recomputed from the top row on
  /// screen downwards and everything above keeps its exact position (see
  /// [GalleryLayoutHost.reflow]): tiles on screen get their right shape at
  /// once, nothing the user can see moves vertically, and no scroll correction
  /// is needed (a fling would overwrite one). The rows above are refreshed as
  /// soon as the scroll stops, with an anchor on the tile at the top of the
  /// screen, so that pass moves nothing visible either.
  void _flush() {
    if (!mounted) return;
    if (!_ratiosDirty && !_host.hasStalePrefix) return;
    final width = _host.sliverCrossExtent;
    if (width <= 0) {
      _scheduleFlush(const Duration(milliseconds: 60));
      return;
    }
    final result = _host.reflow(
      crossExtent: width,
      freezeAboveViewport: _isScrolling,
    );
    _ratiosDirty = false;
    if (result == GalleryReflowResult.applied) setState(() {});
    // Keep refreshing the rows above while scrolling goes on (the top row
    // moves, and so does the part that is up to date).
    if (_host.hasStalePrefix) _scheduleFlush(const Duration(milliseconds: 120));
  }

  // ── Following the viewport ─────────────────────────────────────────────────
  // Sizes are measured continuously around whatever is on screen: the header
  // probe has its own follow loop, and this timer covers what it cannot read
  // (videos, book covers) from thumbnails that already exist. None of it waits
  // for scrolling to stop.
  static const _windowBefore = 60;
  static const _windowAfter = 200;

  int _focusIndex() {
    final model = _host.current;
    if (model == null || model.childCount == 0) return 0;
    var c = model.minChildForOffset(_host.sliverScrollOffset);
    if (model.itemOfChild[c] < 0 && c + 1 < model.childCount) c++;
    return math.max(0, model.itemOfChild[c]);
  }

  void _ensureFollowTimer() {
    if (_unknownVisuals <= 0) {
      _followTimer?.cancel();
      _followTimer = null;
      return;
    }
    _followTimer ??= Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _followTick(),
    );
  }

  void _followTick() {
    if (!mounted) return;
    if (_unknownVisuals <= 0) {
      _ensureFollowTimer();
      return;
    }
    final first = _focusIndex();
    final start = math.max(0, first - _windowBefore);
    final end = math.min(_display.length, first + _windowAfter);
    _prewarmMemoryCache(start, end);
    if (!_diskPreloadRunning) unawaited(_preloadDiskAspectRatios(start, end));
  }

  void _startProbing() {
    if (!_indexReady || _display.isEmpty) return;
    _prefetcher.start(
      follow: true,
      itemCount: _display.length,
      wantsProbe: (i) =>
          _kind[i] == 1 && _known[i] == 0 && !_display[i].isPlaceholder,
      targetOf: (i) {
        final entry = _display[i];
        return GalleryProbeTarget(_containerOf(entry), _fullPathOf(entry));
      },
      focusIndex: _focusIndex,
      onResult: _onProbed,
      paused: () => PlaybackThrottleController.isPlaybackActive.value,
    );
  }

  void _prewarmMemoryCache(int start, int end) {
    for (var i = start; i < end; i++) {
      if (_kind[i] == 0 || _known[i] == 1) continue;
      final entry = _display[i];
      _learnFromMemoryCache(i, entry, _fullPathOf(entry));
    }
  }

  /// Sizes stored next to already-generated thumbnails, for media the header
  /// probe cannot read (videos, book covers). Reads are sequential and yield
  /// between them so frames and real thumbnail requests are not starved.
  Future<void> _preloadDiskAspectRatios(int start, int end) async {
    _diskPreloadRunning = true;
    try {
      final quality = widget.thumbnailQuality;
      var sinceYield = 0;
      for (var i = start; i < end && i < _display.length; i++) {
        if (_kind[i] != 2 || _known[i] == 1) continue;
        if (!mounted || PlaybackThrottleController.isPlaybackActive.value) {
          return;
        }
        final entry = _display[i];
        final mode = _cacheModeOf(entry);
        if (mode == ThumbnailCacheMode.disabled || entry.isPlaceholder) {
          continue;
        }
        final container = _containerOf(entry);
        final fullPath = _fullPathOf(entry);
        try {
          final cached = await _thumbnailCache.fetchWithSize(
            container: container,
            filePath: fullPath,
            mode: mode,
            quality: quality,
          );
          final w = cached?.$2;
          final h = cached?.$3;
          if (w != null && h != null && w > 0 && h > 0) {
            _onSizeKnown(i, entry, fullPath, w, h, container: container);
          }
        } catch (e) {
          VeLog.w(
            'FileMasonryView',
            'Size prefetch failed for ${VeLog.censorName(fullPath)}',
            e,
          );
        }
        if (++sinceYield >= 4) {
          sinceYield = 0;
          await Future<void>.delayed(const Duration(milliseconds: 8));
        }
      }
    } finally {
      _diskPreloadRunning = false;
    }
  }

  // ── Zoom ───────────────────────────────────────────────────────────────────

  /// Auto-aware quality for cells built in [build]; see the grid view's
  /// equivalent. A row's tiles are about one cell high and as wide as their
  /// picture is, so the cell width is stretched by a typical landscape ratio
  /// before it is turned into a thumbnail size.
  ThumbnailQuality _effectiveQualityOf(RawEntry entry) {
    final q = widget.qualityFor?.call(entry) ?? widget.thumbnailQuality;
    if (!q.auto) return q;
    final width = MediaQuery.sizeOf(context).width;
    final cellWidth =
        (width - 2 * _kSideInset - (_columnCount - 1) * widget.spacing) /
        _columnCount;
    return q.resolveForCell(
      logicalWidth: _flow == GalleryFlow.rows ? cellWidth * 1.5 : cellWidth,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  int get _minColumns {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 2 : 1;
  }

  int get _maxColumns {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 6 : 3;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baselineScale = 1.0;
    // Pin what is under the fingers for the whole gesture, so continuous
    // zooming keeps it there instead of drifting (or snapping back to the top).
    _zoomAnchor = _host.captureAnchorAt(details.localFocalPoint.dy);
  }

  void _changeColumns(int newColumns, double newBaseline) {
    HapticFeedback.selectionClick();

    final oldColumns = _columnCount;
    final anchor = _zoomAnchor ?? _host.captureTopAnchor();
    _columnCount = newColumns;
    _baselineScale = newBaseline;
    _host.columnCount = newColumns;
    _host.invalidate();
    // Consumed by the sliver's next layout pass: the anchored tile stays put.
    _host.pendingAnchor = anchor;
    setState(() {});
    widget.onColumnCountChanged?.call(_columnCount);

    // Snappy physical pop — NO black fade, 100% solid & bright at all times!
    final isZoomIn = newColumns < oldColumns;
    final startScale = isZoomIn ? 0.90 : 1.10;

    _scaleAnimation = Tween<double>(begin: startScale, end: 1.0).animate(
      CurvedAnimation(parent: _morphController, curve: Curves.easeOutCubic),
    );
    _morphController.forward(from: 0.0);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    if (_zoomAnchor == null) {
      _handleScaleStart(
        ScaleStartDetails(
          focalPoint: details.focalPoint,
          localFocalPoint: details.localFocalPoint,
          pointerCount: details.pointerCount,
        ),
      );
    }

    final scale = details.scale;
    final factor = scale / _baselineScale;

    // Trigger column shift only on crossing threshold; no pre-threshold jitter
    if (factor > 1.18 && _columnCount > _minColumns) {
      _changeColumns(_columnCount - 1, scale);
    } else if (factor < 0.82 && _columnCount < _maxColumns) {
      _changeColumns(_columnCount + 1, scale);
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _zoomAnchor = null;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    // Tiles that scroll out of the viewport are disposed, which already
    // drops their *queued* request. (Cancelling the whole visible tier here
    // also cancelled tiles that were still on screen, which then retried
    // together and, after enough cancellations, showed the error icon.)
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _isScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _isScrolling = false;
      // The rows above the screen may be out of date (see _flush): bring them
      // up to date now that it can be done without anything visible moving.
      if (_ratiosDirty || _host.hasStalePrefix) {
        _scheduleFlush(const Duration(milliseconds: 30));
      }
    }
    return false;
  }

  // ── Building ───────────────────────────────────────────────────────────────

  Widget _buildItemCell(BuildContext context, int displayIndex) {
    final entry = _display[displayIndex];
    final fullPath = _fullPathOf(entry);
    if (_kind[displayIndex] != 0 && _known[displayIndex] == 0) {
      _learnFromMemoryCache(displayIndex, entry, fullPath);
    }

    final cell = entry.isDir
        ? _buildDirCell(context, entry, fullPath)
        : _buildFileCell(context, displayIndex, entry, fullPath);

    return HoldSelectableItem(
      index: _globalIndexOf(displayIndex),
      entry: entry,
      child: BrowserItemDragItem(
        entry: entry,
        container: _containerOf(entry),
        currentDirectory: widget.currentDirPath,
        visibleItems: widget.items,
        selectedItems: widget.selectedItems,
        isSelectionMode: widget.isSelectionMode,
        enabled: widget.enableFileDrag && widget.archiveContext == null,
        onItemLongPress: widget.onItemLongPress,
        onDrop: widget.onFileDrop,
        child: cell,
      ),
    );
  }

  Widget _buildChild(BuildContext context, int child) {
    final childItem = _childItem;
    if (childItem == null) return _buildItemCell(context, child);
    final displayIndex = childItem[child];
    if (displayIndex >= 0) return _buildItemCell(context, displayIndex);
    final group = _groups![_childSection![child]];
    return Align(
      key: ValueKey('gallery_header:${_childSection![child]}'),
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: GalleryDateHeader(
          title: formatDateGroupHeader(group.date, context),
          count: group.items.length,
          horizontalPadding: 16.0 - _kSideInset,
        ),
      ),
    );
  }

  Widget _buildScrollView(ScrollController? controller) {
    return AnimatedBuilder(
      animation: _morphController,
      builder: (context, child) {
        return ClipRect(
          child: Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: CustomScrollView(
        controller: controller,
        cacheExtent: MediaQuery.sizeOf(context).height * 1.5,
        physics:
            const AlwaysScrollableScrollPhysics(), // Native physics that cannot freeze
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              _kSideInset,
              // A date header brings its own air above it.
              _groups == null ? 12 : 0,
              _kSideInset,
              // The last group's gap is not part of the sliver's extent.
              widget.bottomClearance + (_groups == null ? 0 : _kGroupGap),
            ),
            // One sliver for every date group, headers included: see
            // GallerySliverGrid for why a sliver per group does not scale.
            sliver: GallerySliverGrid(
              host: _host,
              delegate: SliverChildBuilderDelegate(
                _buildChild,
                childCount: _childCount,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    if (total == 0) return const SizedBox.shrink();
    // The stored sizes of the media index are on their way (a moment, once per
    // unlock): a layout built without them would only be redone.
    if (!_indexReady) return const SizedBox.shrink();

    return HoldRangeSelectContainer(
      items: widget.items,
      selectedItems: widget.selectedItems,
      isSelectionMode: widget.isSelectionMode,
      onSelectionChanged: (newSelection) =>
          widget.onSelectionChanged?.call(newSelection),
      onLongPressSelect: (entry) => widget.onItemLongPress(entry),
      enableHoldDrag: widget.enableFileDrag && widget.archiveContext == null,
      onScaleStart: _handleScaleStart,
      onScaleUpdate: _handleScaleUpdate,
      onScaleEnd: _handleScaleEnd,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScrollNotification,
        child: widget.scrollController == null
            ? _buildScrollView(null)
            : FastScrollbar(
                controller: widget.scrollController!,
                items: widget.items,
                sortBy: widget.sortBy,
                padding: EdgeInsets.only(
                  top: 12,
                  bottom: widget.bottomClearance,
                ),
                child: _buildScrollView(widget.scrollController),
              ),
      ),
    );
  }

  /// Whether this file's cell is sized by decoded artwork (and so needs a
  /// real aspect ratio) rather than by a centred icon.
  bool _hasVisualPreview(String fileName) {
    final ext = fileName.split('.').last;
    if (vaultIconForExt(ext) != null) return false;
    if (widget.archiveContext != null &&
        MediaViewerConstants.isVideo(fileName)) {
      return false;
    }
    // Not for a book inside an open archive: no cover is fetched there (see
    // the build below), so it stays an icon cell like any other file.
    if (widget.archiveContext == null && isBookWithCover(fileName)) return true;
    return MediaViewerConstants.isImage(fileName) ||
        MediaViewerConstants.isVideo(fileName);
  }

  Widget _buildDirCell(BuildContext context, RawEntry entry, String fullPath) {
    final isSelected = widget.selectedItems.contains(entry);
    final cs = Theme.of(context).colorScheme;
    final isMounted = widget.mountedFolderPaths.contains(fullPath);

    final iconSize = GridCardUtils.calculateIconSize(
      context,
      _columnCount,
      spacing: widget.spacing,
    );
    final skin = FileManagerSkinScope.of(context);
    final folderIcon = Icon(
      skin.folderIcon,
      size: iconSize,
      color: isSelected ? cs.primary : skin.folderIconColor(cs),
    );

    return GridCardShell(
      cornerRadius: widget.cornerRadius,
      key: ValueKey(
        'dir:$fullPath:${widget.isPinned?.call(entry)}:${widget.isBookmark?.call(entry)}:$isMounted',
      ),
      // The gallery layout hands the card a fixed height.
      aspectRatio: null,
      cardColor: GridCardUtils.folderCardColor(cs, isMounted: false),
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      showFileName: true,
      isFolder: true,
      longFileNameMode: widget.longFileNameMode,
      isPinned: widget.isPinned?.call(entry) ?? false,
      isBookmark: widget.isBookmark?.call(entry) ?? false,
      isDocumentProviderMounted: isMounted,
      isSynced: widget.isFolderSynced?.call(entry) ?? false,
      isPlaceholder: entry.isPlaceholder,
      onTap: entry.isPlaceholder ? () {} : () => widget.onDirTap(entry),
      // Selection is owned by HoldRangeSelectContainer's hold recognizer
      // (400 ms, wins the arena before this 500 ms one); intentionally a no-op.
      onLongPress: () {},
      showMoreButton: widget.showItemActionsMenu,
      // Hidden by the shell while selecting / on placeholders, but still
      // passed so the name row keeps its slot for the button.
      onMoreTap: widget.onFileLongMenu == null
          ? null
          : () => widget.onFileLongMenu!(entry),
      preview: entry.isPlaceholder
          ? Center(child: folderIcon)
          : FolderThumbnailPreview(
              key: ValueKey('folder_preview:${_containerOf(entry).uri}:$fullPath'),
              container: _containerOf(entry),
              folderPath: fullPath,
              cacheMode: _cacheModeOf(entry),
              quality: _effectiveQualityOf(entry),
              iconSize: iconSize,
              child: folderIcon,
            ),
      label: entry.name,
      searchQuery: widget.searchQuery,
    );
  }

  Widget _buildFileCell(
    BuildContext context,
    int displayIndex,
    RawEntry entry,
    String fullPath,
  ) {
    final cs = Theme.of(context).colorScheme;
    final container = _containerOf(entry);
    final cacheMode = _cacheModeOf(entry);
    final cleanName = entry.name;
    final isSelected = widget.selectedItems.contains(entry);
    String displayName = cleanName;
    final ext = cleanName.split('.').last;
    final skin = FileManagerSkinScope.of(context);
    final vaultIcon = vaultIconForExt(ext);
    if (vaultIcon != null) {
      final nameParts = cleanName.split('.');
      if (nameParts.length > 1) {
        nameParts.removeLast();
        displayName = nameParts.join('.');
      }
    }
    final query = widget.searchQuery;
    if (!widget.showFileExtensions && (query == null || query.isEmpty)) {
      displayName = stripFileExtension(cleanName);
    }
    final isImg =
        MediaViewerConstants.isImage(cleanName) && !entry.isPlaceholder;
    final isVid =
        MediaViewerConstants.isVideo(cleanName) && !entry.isPlaceholder;
    final isApk = isApkFile(cleanName) && !entry.isPlaceholder;
    final isBook = isBookWithCover(cleanName) && !entry.isPlaceholder;
    final hasRealThumbnail = MediaViewerConstants.hasRealThumbnail(
      cleanName,
      insideArchive: widget.archiveContext != null,
      isPlaceholder: entry.isPlaceholder,
    );

    Widget previewWidget;
    final iconSize = GridCardUtils.calculateIconSize(
      context,
      _columnCount,
      spacing: widget.spacing,
    );

    if (vaultIcon != null) {
      previewWidget = Center(
        child: Icon(
          skin.fileIcon(cleanName),
          size: iconSize,
          color: skin.fileIconColor(cs, cleanName),
        ),
      );
    } else if (isImg) {
      previewWidget = Hero(
        tag: 'media_hero_${container.volId}_$fullPath',
        child: Material(
          type: MaterialType.transparency,
          child: _EncryptedImageMasonryThumb(
            container: container,
            filePath: fullPath,
            cacheMode: cacheMode,
            quality: _effectiveQualityOf(entry),
            onSizeKnown: (w, h) => _onSizeKnown(
              displayIndex,
              entry,
              fullPath,
              w,
              h,
              container: container,
            ),
            archiveContext: widget.archiveContext,
            archiveRootPath: widget.archiveRootPath,
          ),
        ),
      );
    } else if (isVid) {
      previewWidget = Hero(
        tag: 'media_hero_${container.volId}_$fullPath',
        child: Material(
          type: MaterialType.transparency,
          child: _VideoMasonryThumb(
            container: container,
            filePath: fullPath,
            cacheMode: cacheMode,
            quality: _effectiveQualityOf(entry),
            onSizeKnown: (w, h) => _onSizeKnown(
              displayIndex,
              entry,
              fullPath,
              w,
              h,
              container: container,
            ),
            archiveContext: widget.archiveContext,
            archiveRootPath: widget.archiveRootPath,
          ),
        ),
      );
    } else if (isApk && widget.archiveContext == null) {
      previewWidget = Center(
        child: SizedBox(
          width: iconSize,
          height: iconSize,
          child: _ApkIconMasonryThumb(
            container: container,
            filePath: fullPath,
            cacheMode: cacheMode,
            quality: _effectiveQualityOf(entry),
            fallbackIcon: skin.fileIcon(cleanName),
            fallbackColor: skin.fileIconColor(cs, cleanName),
            fallbackIconSize: iconSize,
          ),
        ),
      );
    } else if (isBook && widget.archiveContext == null) {
      previewWidget = _BookCoverMasonryThumb(
        container: container,
        filePath: fullPath,
        cacheMode: cacheMode,
        quality: _effectiveQualityOf(entry),
        onSizeKnown: (w, h) => _onSizeKnown(
          displayIndex,
          entry,
          fullPath,
          w,
          h,
          container: container,
        ),
        fallbackIcon: skin.fileIcon(cleanName),
        fallbackColor: skin.fileIconColor(cs, cleanName),
        fallbackIconSize: iconSize,
      );
    } else {
      previewWidget = Center(
        child: Icon(
          skin.fileIcon(cleanName),
          size: iconSize,
          color: skin.fileIconColor(cs, cleanName),
        ),
      );
    }

    return GridCardShell(
      cornerRadius: widget.cornerRadius,
      key: ValueKey(
        'file:$fullPath:${widget.isPinned?.call(entry)}:${widget.isBookmark?.call(entry)}',
      ),
      // The gallery layout hands the card a fixed height.
      aspectRatio: null,
      cardColor: GridCardUtils.folderCardColor(cs, isMounted: false),
      isSelected: isSelected,
      isSelectionMode: widget.isSelectionMode,
      showFileName: widget.showFileNames || !hasRealThumbnail,
      longFileNameMode: widget.longFileNameMode,
      isPinned: widget.isPinned?.call(entry) ?? false,
      isBookmark: widget.isBookmark?.call(entry) ?? false,
      isPlaceholder: entry.isPlaceholder,
      onTap: entry.isPlaceholder ? () {} : () => widget.onFileTap(entry),
      // Selection is owned by HoldRangeSelectContainer's hold recognizer
      // (400 ms, wins the arena before this 500 ms one); intentionally a no-op.
      onLongPress: () {},
      showMoreButton: widget.showItemActionsMenu,
      // Hidden by the shell while selecting / on placeholders, but still
      // passed so the name row keeps its slot for the button.
      onMoreTap: widget.onFileLongMenu == null
          ? null
          : () => widget.onFileLongMenu!(entry),
      preview: previewWidget,
      label: displayName,
      searchQuery: widget.searchQuery,
    );
  }
}

class _EncryptedImageMasonryThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final void Function(int width, int height) onSizeKnown;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;

  const _EncryptedImageMasonryThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.onSizeKnown,
    this.archiveContext,
    this.archiveRootPath,
  });

  static Future<void> _checkAndReportSizeFromBytes(
    MountedContainer container,
    String path,
    Uint8List bytes,
    void Function(int width, int height) onSizeKnown,
  ) async {
    if (bytes.isEmpty) return;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      onSizeKnown(frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
    } catch (e) {
      VeLog.w(
        'FileMasonryView',
        'Decode-for-size failed for ${VeLog.censorName(path)}',
        e,
      );
    }
  }

  static Future<Uint8List> _fetch(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
    void Function(int width, int height) onSizeKnown,
    ArchiveContext? archiveContext,
    String? archiveRootPath,
  ) async {
    if (archiveContext != null && archiveRootPath != null) {
      final bytes = await fetchArchiveEntryForThumbnail(
        archiveContext: archiveContext,
        archiveRootPath: archiveRootPath,
        fullPath: path,
        fileIoApi: fileIoApi,
        targetSize: quality.scaledSize(180),
        quality: quality.jpegQuality,
      );
      thumbnailCache.cacheInMemory(container, path, bytes, quality);
      await _checkAndReportSizeFromBytes(container, path, bytes, onSizeKnown);
      return bytes;
    }
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await thumbnailCache.fetchWithSize(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.$1.isNotEmpty) {
        final (bytes, width, height) = cached;
        if (width != null && height != null) {
          onSizeKnown(width, height);
        } else {
          await _checkAndReportSizeFromBytes(
            container,
            path,
            bytes,
            onSizeKnown,
          );
        }
        return bytes;
      }
    }
    final thumb = await fileIoApi.getImageThumbnailWithSize(
      container,
      path,
      targetSize: quality.scaledSize(180),
      quality: quality.jpegQuality,
    );
    final thumbBytes = thumb?.bytes;
    if (thumbBytes == null || thumbBytes.isEmpty) {
      final raw = await readRawThumbnailFallback(fileIoApi, container, path);
      if (raw.length < 200 * 1024) {
        thumbnailCache.cacheInMemory(container, path, raw, quality);
        await _checkAndReportSizeFromBytes(container, path, raw, onSizeKnown);
      }
      return raw;
    }
    onSizeKnown(thumb!.width, thumb.height);
    thumbnailCache.cacheInMemory(
      container,
      path,
      thumbBytes,
      quality,
      thumb.width,
      thumb.height,
    );
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        thumbnailCache.store(
          container: container,
          filePath: path,
          data: thumbBytes,
          mode: mode,
          quality: quality,
          width: thumb.width,
          height: thumb.height,
        ),
      );
    }
    return thumbBytes;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final cs = Theme.of(context).colorScheme;

    final syncEntry = thumbnailCache.peekMemoryWithSize(
      container,
      filePath,
      quality,
    );
    final syncBytes = syncEntry?.$1;
    if (syncEntry != null && syncEntry.$1.isNotEmpty) {
      final (bytes, width, height) = syncEntry;
      if (width != null && height != null) {
        onSizeKnown(width, height);
      } else {
        _checkAndReportSizeFromBytes(container, filePath, bytes, onSizeKnown);
      }
    }
    return AsyncThumbnail(
      key: ValueKey('img:$filePath'),
      container: container,
      filePath: filePath,
      quality: quality,
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: ThumbnailConcurrency.imageLimiter,
      fetchFn: (c, p) => _fetch(
        thumbnailCache,
        fileIoApi,
        c,
        p,
        cacheMode,
        quality,
        onSizeKnown,
        archiveContext,
        archiveRootPath,
      ),
      debounce: const Duration(milliseconds: 30),
      syncLookup: () => syncBytes,
      cacheHeight: quality.scaledSize(180),
      imageBuilder: (context, bytes, cacheHeight) => Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheHeight: cacheHeight,
        errorBuilder: (_, _, _) => _errorPlaceholder(cs),
      ),
      loadingBuilder: (context) => Container(
        color: cs.surfaceContainerLow,
        child: const SizedBox.expand(),
        ),
      errorBuilder: (context) => _errorPlaceholder(cs),
    );
  }

  Widget _errorPlaceholder(ColorScheme cs) => Container(
    color: cs.surfaceContainerLow,
    child: Center(
      child: Icon(
        Icons.broken_image_rounded,
        size: AppIconSize.feature,
        color: cs.outline,
      ),
    ),
  );
}

class _VideoMasonryThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final void Function(int width, int height) onSizeKnown;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;

  const _VideoMasonryThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.onSizeKnown,
    this.archiveContext,
    this.archiveRootPath,
  });

  static Future<void> _checkAndReportSizeFromBytes(
    MountedContainer container,
    String path,
    Uint8List bytes,
    void Function(int width, int height) onSizeKnown,
  ) async {
    if (bytes.isEmpty) return;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      onSizeKnown(frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
    } catch (e) {
      VeLog.w(
        'FileMasonryView',
        'Decode-for-size failed for ${VeLog.censorName(path)}',
        e,
      );
    }
  }

  static Future<Uint8List> _fetch(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
    void Function(int width, int height) onSizeKnown,
    ArchiveContext? archiveContext,
    String? archiveRootPath,
  ) => VideoThumbnailFetcher.fetchWithSize(
    thumbnailCache,
    fileIoApi,
    container,
    path,
    mode: mode,
    quality: quality,
    targetSize: quality.scaledSize(180),
    onSizeKnown: onSizeKnown,
    onUnknownSize: (bytes) =>
        _checkAndReportSizeFromBytes(container, path, bytes, onSizeKnown),
    archiveContext: archiveContext,
    archiveRootPath: archiveRootPath,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final cs = Theme.of(context).colorScheme;

    final syncEntry = thumbnailCache.peekMemoryWithSize(
      container,
      filePath,
      quality,
    );
    final syncBytes = syncEntry?.$1;
    if (syncEntry != null && syncEntry.$1.isNotEmpty) {
      final (bytes, width, height) = syncEntry;
      if (width != null && height != null) {
        onSizeKnown(width, height);
      } else {
        _checkAndReportSizeFromBytes(container, filePath, bytes, onSizeKnown);
      }
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        AsyncThumbnail(
          key: ValueKey('vid:$filePath'),
          container: container,
          filePath: filePath,
          quality: quality,
          cache: ThumbnailConcurrency.inFlightThumbnails,
          limiter: ThumbnailConcurrency.videoLimiter,
          fetchFn: (c, p) => _fetch(
            thumbnailCache,
            fileIoApi,
            c,
            p,
            cacheMode,
            quality,
            onSizeKnown,
            archiveContext,
            archiveRootPath,
          ),
          debounce: const Duration(milliseconds: 60),
          syncLookup: () => syncBytes,
          cacheHeight: quality.scaledSize(180),
          imageBuilder: (context, bytes, cacheHeight) => Image.memory(
            bytes,
            fit: BoxFit.cover,
            cacheHeight: cacheHeight,
            errorBuilder: (_, _, _) => _errorPlaceholder(cs),
          ),
          loadingBuilder: (context) => Container(
            color: cs.surfaceContainerLow,
            child: const SizedBox.expand(),
            ),
          errorBuilder: (context) => _errorPlaceholder(cs),
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              Icons.play_circle_outline_rounded,
              size: AppIconSize.action,
              color: cs.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorPlaceholder(ColorScheme cs) => Container(
    color: cs.surfaceContainerLow,
    child: Center(
      child: Icon(
        Icons.broken_image_rounded,
        size: AppIconSize.feature,
        color: cs.outline,
      ),
    ),
  );
}

class _ApkIconMasonryThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;

  final IconData fallbackIcon;
  final Color fallbackColor;
  final double fallbackIconSize;

  const _ApkIconMasonryThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.fallbackIconSize,
  });

  static Future<Uint8List> _fetch(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
  ) async {
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await thumbnailCache.fetch(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }
    final bytes = await fetchApkIconForThumbnail(
      container: container,
      filePath: path,
      fileIoApi: fileIoApi,
    );
    thumbnailCache.cacheInMemory(container, path, bytes, quality);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        thumbnailCache.store(
          container: container,
          filePath: path,
          data: bytes,
          mode: mode,
          quality: quality,
        ),
      );
    }
    return bytes;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);

    return AsyncThumbnail(
      key: ValueKey('apk:$filePath'),
      container: container,
      filePath: filePath,
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: ThumbnailConcurrency.imageLimiter,
      quality: quality,
      fetchFn: (c, p) =>
          _fetch(thumbnailCache, fileIoApi, c, p, cacheMode, quality),
      debounce: const Duration(milliseconds: 30),
      syncLookup: () => thumbnailCache.peekMemory(container, filePath, quality),
      cacheHeight: quality.scaledSize(180),
      imageBuilder: (context, bytes, cacheHeight) => Image.memory(
        bytes,
        fit: BoxFit.contain,
        cacheHeight: cacheHeight,
        errorBuilder: (_, _, _) => _fallbackWidget(),
      ),
      loadingBuilder: (context) => const SizedBox.expand(),
      errorBuilder: (context) => _fallbackWidget(),
    );
  }

  Widget _fallbackWidget() => Center(
    child: Icon(fallbackIcon, size: fallbackIconSize, color: fallbackColor),
  );
}

/// A book's cover as its masonry tile. The cell is sized from the cover's own
/// aspect ratio, exactly as a photo's is (see [_EncryptedImageMasonryThumb]), so
/// the cover fills it uncropped. A book with no cover keeps its file-type icon
/// in a default portrait cell.
class _BookCoverMasonryThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final void Function(int width, int height) onSizeKnown;

  final IconData fallbackIcon;
  final Color fallbackColor;
  final double fallbackIconSize;

  const _BookCoverMasonryThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.onSizeKnown,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.fallbackIconSize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final bookApi = ref.read(vaultBookApiProvider);

    // A memory hit skips fetchFn entirely, so report its size here, as the
    // image tile does.
    final syncEntry = thumbnailCache.peekMemoryWithSize(
      container,
      filePath,
      quality,
    );
    final syncBytes = syncEntry?.$1;
    if (syncEntry != null && syncEntry.$1.isNotEmpty) {
      final (_, width, height) = syncEntry;
      if (width != null && height != null) onSizeKnown(width, height);
    }

    return AsyncThumbnail(
      key: ValueKey('book:$filePath'),
      container: container,
      filePath: filePath,
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: ThumbnailConcurrency.imageLimiter,
      quality: quality,
      fetchFn: (c, p) async {
        final thumb = await loadBookCoverThumbnail(
          thumbnailCache: thumbnailCache,
          bookApi: bookApi,
          container: c,
          path: p,
          mode: cacheMode,
          quality: quality,
        );
        if (thumb.width > 0 && thumb.height > 0) {
          onSizeKnown(thumb.width, thumb.height);
        }
        return thumb.bytes;
      },
      debounce: const Duration(milliseconds: 30),
      syncLookup: () => syncBytes,
      cacheHeight: quality.scaledSize(180),
      imageBuilder: (context, bytes, cacheHeight) => Image.memory(
        bytes,
        fit: BoxFit.cover,
        cacheHeight: cacheHeight,
        errorBuilder: (_, _, _) => _fallbackWidget(),
      ),
      loadingBuilder: (context) => _fallbackWidget(),
      errorBuilder: (context) => _fallbackWidget(),
    );
  }

  Widget _fallbackWidget() => Center(
    child: Icon(fallbackIcon, size: fallbackIconSize, color: fallbackColor),
  );
}
