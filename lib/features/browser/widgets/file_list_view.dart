import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/file_manager_toolbar_config.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_group_index.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_layout.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_sliver.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/fast_scrollbar.dart';
import 'package:vaultexplorer/features/browser/widgets/file_tile.dart';
import 'package:vaultexplorer/features/browser/widgets/gallery_date_header.dart';
import 'package:vaultexplorer/features/browser/widgets/browser_item_drag.dart';
import 'package:vaultexplorer/features/browser/widgets/hold_range_select_container.dart';

/// Rejects list scroll drag deltas while a 2-finger pinch gesture is active
/// without detaching the Scrollable's DragGestureRecognizer.
class _ZoomScrollPhysics extends AlwaysScrollableScrollPhysics {
  final ValueGetter<bool> isZooming;

  const _ZoomScrollPhysics({required this.isZooming, super.parent});

  @override
  _ZoomScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ZoomScrollPhysics(
      isZooming: isZooming,
      parent: buildParent(ancestor),
    );
  }

  // DO NOT override shouldAcceptUserOffset! Returning false causes
  // ScrollableState.setCanDrag(false), which deletes the DragGestureRecognizer
  // from the list and permanently breaks touch scrolling.
  // Instead, absorb user offset deltas directly while zooming:
  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    if (isZooming()) return 0.0;
    return super.applyPhysicsToUserOffset(position, offset);
  }
}

class FileListView extends StatefulWidget {
  final List<RawEntry> items;
  final bool isSelectionMode;
  final bool isCompact;

  /// Two-row layout: filename on its own line, date and size stacked
  /// underneath on a second line instead of in aligned columns. Mutually
  /// exclusive with [isCompact] -- the caller picks at most one.
  final bool isDetailed;
  final Set<RawEntry> selectedItems;
  final List<FileDetailColumn> detailColumns;
  final LongFileNameDisplayMode longFileNameMode;
  final bool showItemActionsMenu;

  /// Whether file names are listed with their extension. See
  /// `FileManagerToolbarConfig.showFileExtensions`.
  final bool showFileExtensions;
  final ValueChanged<RawEntry> onDirTap;
  final ValueChanged<RawEntry> onFileTap;
  final ValueChanged<RawEntry> onItemLongPress;
  final ValueChanged<RawEntry>? onFileLongMenu;

  /// Called when the person taps directly on a row's leading icon/thumbnail
  /// rather than the row body -- toggles that item's selection instead of
  /// opening it. See `file_browser_screen.dart`'s `_handleIconTap`.
  final ValueChanged<RawEntry>? onIconTap;
  final ValueChanged<Set<RawEntry>>? onSelectionChanged;
  final bool enableFileDrag;
  final BrowserItemDropHandler? onFileDrop;
  final String? searchQuery;
  final bool Function(RawEntry entry)? isFolderMounted;
  final bool Function(RawEntry entry)? isPinned;
  final bool Function(RawEntry entry)? isBookmark;
  final bool Function(RawEntry entry)? isFolderSynced;
  final MountedContainer? container;
  final String currentDirPath;
  final ThumbnailCacheMode thumbnailCacheMode;
  final ThumbnailQuality thumbnailQuality;
  final bool showThumbnails;
  final double initialZoomLevel;
  final ValueChanged<double>? onZoomLevelChanged;
  final ScrollController? scrollController;
  final double bottomClearance;

  /// Set when [items] are being listed from inside an open archive rather
  /// than the real container filesystem -- see `file_tile.dart`'s
  /// `archiveContext` doc for what this changes about thumbnail fetching.
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;
  final SortBy? sortBy;
  final bool largeThumbnail;
  final bool groupByDate;

  /// Builds the sections when [groupByDate] is on. Null keeps the day
  /// sections ([computeDateGroups]); the gallery filter passes its own to
  /// group by month, folder, place, camera...
  ///
  /// The list handed over is already arranged so that each section is one run
  /// of it, and a new builder only takes effect with a new [items] list.
  final List<DateGroup<RawEntry>> Function(List<RawEntry> items)? groupBuilder;

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

  const FileListView({
    super.key,
    required this.items,
    required this.isSelectionMode,
    this.isCompact = false,
    this.isDetailed = false,
    this.largeThumbnail = false,
    this.groupByDate = false,
    this.groupBuilder,
    required this.selectedItems,
    this.detailColumns = const [FileDetailColumn.date, FileDetailColumn.size],
    this.longFileNameMode = LongFileNameDisplayMode.ellipsizeEnd,
    this.showItemActionsMenu = true,
    this.showFileExtensions = true,
    required this.onDirTap,
    required this.onFileTap,
    required this.onItemLongPress,
    this.onFileLongMenu,
    this.onIconTap,
    this.onSelectionChanged,
    this.enableFileDrag = false,
    this.onFileDrop,
    this.searchQuery,
    this.isFolderMounted,
    this.isPinned,
    this.isBookmark,
    this.isFolderSynced,
    this.container,
    this.currentDirPath = '',
    this.thumbnailCacheMode = ThumbnailCacheMode.appCache,
    this.thumbnailQuality = ThumbnailQuality.defaultQuality,
    this.showThumbnails = true,
    this.initialZoomLevel = 1.0,
    this.onZoomLevelChanged,
    this.scrollController,
    this.bottomClearance = 0.0,
    this.archiveContext,
    this.archiveRootPath,
    this.sortBy,
    this.containerFor,
    this.cacheModeFor,
    this.qualityFor,
  });

  @override
  State<FileListView> createState() => FileListViewState();
}

class FileListViewState extends State<FileListView> {
  /// Returns the geometries (top offset and height) in scroll-content coordinates
  /// for the items at [globalIndices] in `widget.items`.
  Map<int, ({double top, double height})> geometriesForGlobalIndices(
    Set<int> globalIndices,
  ) {
    final result = <int, ({double top, double height})>{};
    if (globalIndices.isEmpty) return result;

    final itemExtent = _computeItemExtent(_zoomLevel);

    if (widget.groupByDate) {
      // Same model the sliver lays out with, so a drag-select hit-tests
      // exactly what is on screen (and nothing is regrouped per pointer move).
      final groups = _groupsFor(widget.items);
      final model = _groupModelFor(_zoomLevel);
      if (model == null) return result;
      for (final index in globalIndices) {
        if (index < 0 || index >= groups.childOfGlobal.length) continue;
        final child = groups.childOfGlobal[index];
        if (child < 0 || child >= model.childCount) continue;
        result[index] = (top: model.tops[child], height: model.heights[child]);
      }
      return result;
    }

    for (final index in globalIndices) {
      if (index < 0 || index >= widget.items.length) continue;
      result[index] = (
        top: index * itemExtent,
        height: itemExtent,
      );
    }
    return result;
  }
  ThumbnailCacheMode _cacheModeOf(RawEntry entry) =>
      widget.cacheModeFor?.call(entry) ?? widget.thumbnailCacheMode;

  ThumbnailQuality _qualityOf(RawEntry entry) =>
      widget.qualityFor?.call(entry) ?? widget.thumbnailQuality;

  double _baselineScale = 1.0;
  late double _zoomLevel;
  final Map<RawEntry, int> _entryIndexMap = {};
  int _lastPointerCount = 0;
  bool _isZooming = false;
  bool _isAtBottomAnchor = false;
  bool _isAtTopAnchor = false;
  double _anchorCenterItemIndex = 0.0;

  // Grouped (gallery) mode: the whole list is ONE sliver whose geometry comes
  // from this host, not a sliver pair per day. A viewport lays out every one
  // of its slivers on every scrolled frame and builds at least one child in
  // each (flutter#49027), so a sliver per day makes every frame, and above all
  // every scrollbar jump, cost O(days). See gallery_sliver.dart.
  final GalleryLayoutHost _groupHost = GalleryLayoutHost(
    flow: GalleryFlow.list,
    columnCount: 1,
    spacing: 0,
  );
  GalleryGroupIndex<RawEntry>? _groups;
  String _groupHostKey = '';

  // Grouped pinch zoom keeps the child under the viewport centre in place.
  int _anchorChild = -1;
  double _anchorChildFraction = 0.0;

  @override
  void initState() {
    super.initState();
    _zoomLevel = widget.initialZoomLevel;
  }

  int? _findChildIndex(Key key) {
    if (key is ValueKey<RawEntry>) {
      if (_entryIndexMap.isEmpty && widget.items.isNotEmpty) {
        for (int i = 0; i < widget.items.length; i++) {
          _entryIndexMap[widget.items[i]] = i;
        }
      }
      return _entryIndexMap[key.value];
    }
    return null;
  }

  /// [_findChildIndex] for the grouped sliver, whose child indices also count
  /// the headers.
  int? _findGroupedChildIndex(GalleryGroupIndex<RawEntry> groups, Key key) {
    final global = _findChildIndex(key);
    if (global == null || global < 0 || global >= groups.childOfGlobal.length) {
      return null;
    }
    final child = groups.childOfGlobal[global];
    return child < 0 ? null : child;
  }

  /// The groups of `widget.items`, computed once per list (not per build, and
  /// not per geometry query): grouping reads a metadata subject for every file.
  /// A new [FileListView.groupBuilder] only takes effect with a new list.
  GalleryGroupIndex<RawEntry> _groupsFor(List<RawEntry> items) {
    final cached = _groups;
    if (cached != null && identical(cached.source, items)) return cached;
    return _groups = GalleryGroupIndex<RawEntry>(
      items,
      (widget.groupBuilder ?? computeDateGroups)(items),
    );
  }

  /// Height of a date header at [zoom] (the list scales its text with the
  /// zoom below the context this is computed from).
  double _headerExtentFor(double zoom) => galleryDateHeaderExtent(
    context,
    textScaler: TextScaler.linear(
      MediaQuery.textScalerOf(context).scale(1.0) * zoom,
    ),
  );

  /// Feeds the host with the current groups and sizes; invalidates it only
  /// when one of them changed.
  void _syncGroupHost(
    GalleryGroupIndex<RawEntry> groups,
    double itemExtent,
    double headerExtent,
  ) {
    final key = '${identityHashCode(groups)}|$itemExtent|$headerExtent';
    if (key == _groupHostKey) return;
    _groupHostKey = key;
    _groupHost
      ..rowExtent = itemExtent
      ..sections = [
        for (final g in groups.groups)
          GallerySection(itemCount: g.items.length, headerExtent: headerExtent),
      ]
      ..invalidate();
  }

  /// The grouped layout at [zoom], computed now rather than at the next layout
  /// pass (the pinch handler needs it to place the scroll offset before the
  /// frame is built). Null while there is nothing to lay out.
  GalleryLayoutModel? _groupModelFor(double zoom) {
    if (!widget.groupByDate) return null;
    final groups = _groupsFor(widget.items);
    _syncGroupHost(groups, _computeItemExtent(zoom), _headerExtentFor(zoom));
    // Rows span the full width and their height does not depend on it, so any
    // positive width gives the same offsets before the first layout pass.
    final cross = _groupHost.sliverCrossExtent > 0
        ? _groupHost.sliverCrossExtent
        : MediaQuery.sizeOf(context).width;
    final model = _groupHost.modelFor(cross);
    return model.childCount == 0 ? null : model;
  }

  @override
  void didUpdateWidget(covariant FileListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialZoomLevel != widget.initialZoomLevel) {
      _zoomLevel = widget.initialZoomLevel;
    }
    if (oldWidget.items != widget.items) {
      _entryIndexMap.clear();
    }
  }

  double _computeItemExtent(double zoom) {
    final textScaler = MediaQuery.textScalerOf(context);
    final effectiveTextScaler = TextScaler.linear(textScaler.scale(1.0) * zoom);
    final double baseContentHeight;
    if (widget.largeThumbnail) {
      baseContentHeight = (widget.isCompact ? 54.0 : 58.0) * zoom;
    } else {
      baseContentHeight = (widget.isCompact ? 32.0 : 44.0) * zoom;
    }
    final scaledTextHeight = effectiveTextScaler.scale(
      widget.isDetailed ? 46.0 : 24.0,
    );
    final contentHeight = math.max(baseContentHeight, scaledTextHeight);
    final verticalPadding = widget.largeThumbnail
        ? (widget.isCompact ? 12.0 : 16.0) * zoom
        : (widget.isCompact ? 8.0 : 20.0) * zoom;
    return (contentHeight + verticalPadding + 2.0).roundToDouble();
  }

  double _computeMaxScroll(double itemExtent, double viewport) {
    final totalHeight =
        (widget.items.length * itemExtent) + widget.bottomClearance + 8.0;
    return math.max(0.0, totalHeight - viewport);
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baselineScale = _zoomLevel;
    _lastPointerCount = details.pointerCount;
    _isZooming = true;

    final controller = widget.scrollController;
    if (controller != null && controller.hasClients) {
      final currentExtent = _computeItemExtent(_zoomLevel);
      final viewport = controller.position.viewportDimension;
      final maxScroll = controller.position.maxScrollExtent;
      final offset = controller.offset;

      _isAtTopAnchor = offset <= 24.0;
      _isAtBottomAnchor = offset >= (maxScroll - 24.0);

      if (!_isAtTopAnchor && !_isAtBottomAnchor) {
        final centerY = offset + (viewport / 2.0);
        _anchorCenterItemIndex = currentExtent > 0
            ? (centerY / currentExtent)
            : 0.0;
        _anchorChild = -1;
        if (widget.groupByDate) {
          final model = _groupModelFor(_zoomLevel);
          if (model != null) {
            final c = model.minChildForOffset(centerY);
            _anchorChild = c;
            final h = model.heights[c];
            _anchorChildFraction = h > 0
                ? ((centerY - model.tops[c]) / h).clamp(0.0, 1.0).toDouble()
                : 0.0;
          }
        }
      }
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) {
      if (_isZooming) {
        _handleScaleEnd(ScaleEndDetails(pointerCount: details.pointerCount));
      }
      _lastPointerCount = details.pointerCount;
      return;
    }

    if (!_isZooming || _lastPointerCount < 2) {
      _handleScaleStart(
        ScaleStartDetails(
          focalPoint: details.focalPoint,
          localFocalPoint: details.localFocalPoint,
          pointerCount: details.pointerCount,
        ),
      );
    }
    _lastPointerCount = details.pointerCount;

    final newZoom = (_baselineScale * details.scale).clamp(0.75, 2.0);
    if ((newZoom - _zoomLevel).abs() > 0.005) {
      setState(() {
        _zoomLevel = newZoom;
      });

      final controller = widget.scrollController;
      if (controller != null && controller.hasClients) {
        final newExtent = _computeItemExtent(newZoom);
        final viewport = controller.position.viewportDimension;
        final GalleryLayoutModel? groupModel = widget.groupByDate
            ? _groupModelFor(newZoom)
            : null;
        if (widget.groupByDate && groupModel == null) return;
        final trueMaxScroll = groupModel != null
            ? math.max(
                0.0,
                groupModel.maxExtent + widget.bottomClearance - viewport,
              )
            : _computeMaxScroll(newExtent, viewport);

        final double targetOffset;
        if (_isAtTopAnchor) {
          targetOffset = 0.0;
        } else if (_isAtBottomAnchor) {
          targetOffset = trueMaxScroll;
        } else if (groupModel != null) {
          final c = _anchorChild;
          if (c < 0 || c >= groupModel.childCount) {
            return;
          }
          final targetCenterY =
              groupModel.tops[c] + _anchorChildFraction * groupModel.heights[c];
          targetOffset = (targetCenterY - (viewport / 2.0))
              .clamp(0.0, trueMaxScroll)
              .toDouble();
        } else {
          final targetCenterY = _anchorCenterItemIndex * newExtent;
          targetOffset = (targetCenterY - (viewport / 2.0))
              .clamp(0.0, trueMaxScroll)
              .toDouble();
        }

        controller.jumpTo(targetOffset);
      }
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    if (!_isZooming) return;
    _isZooming = false;
    _lastPointerCount = 0;
    _isAtBottomAnchor = false;
    _isAtTopAnchor = false;
    widget.onZoomLevelChanged?.call(_zoomLevel);
  }

  bool _onScrollNotification(ScrollNotification notification) {
    // Disposed tiles already drop their queued request; cancelling the whole
    // visible tier also cancelled tiles still on screen (see masonry view).
    return false;
  }

  Widget _buildItemRow(BuildContext context, RawEntry entry, int index) {
    final isSelected = widget.selectedItems.contains(entry);
    final isPinned = widget.isPinned?.call(entry) ?? false;
    final isBookmark = widget.isBookmark?.call(entry) ?? false;
    final Widget tile;
    if (entry.isDir) {
      tile = DirectoryTile(
        key: ValueKey('dir:${entry.raw}:$isPinned:$isBookmark'),
        entry: entry,
        isSelectionMode: widget.isSelectionMode,
        isSelected: isSelected,
        isCompact: widget.isCompact,
        isDetailed: widget.isDetailed,
        largeThumbnail: widget.largeThumbnail,
        zoomLevel: _zoomLevel,
        detailColumns: widget.detailColumns,
        longFileNameMode: widget.longFileNameMode,
        searchQuery: widget.searchQuery,
        isDocumentProviderMounted: widget.isFolderMounted?.call(entry) ?? false,
        isPinned: isPinned,
        isBookmark: isBookmark,
        isSynced: widget.isFolderSynced?.call(entry) ?? false,
        container: (widget.containerFor?.call(entry) ?? widget.container),
        currentDirPath: widget.currentDirPath,
        cacheMode: _cacheModeOf(entry),
        quality: _qualityOf(entry),
        showThumbnailPreview: widget.showThumbnails,
        showItemActionsMenu: widget.showItemActionsMenu,
        onTap: () => widget.onDirTap(entry),
        onLongPress: () {},
        onMoreTap: widget.onFileLongMenu,
        onIconTap: widget.onIconTap == null ? null : () => widget.onIconTap!(entry),
      );
    } else {
      tile = FileTile(
        key: ValueKey('file:${entry.raw}:$isPinned:$isBookmark'),
        entry: entry,
        isSelectionMode: widget.isSelectionMode,
        isSelected: isSelected,
        isCompact: widget.isCompact,
        isDetailed: widget.isDetailed,
        largeThumbnail: widget.largeThumbnail,
        zoomLevel: _zoomLevel,
        detailColumns: widget.detailColumns,
        longFileNameMode: widget.longFileNameMode,
        searchQuery: widget.searchQuery,
        container: (widget.containerFor?.call(entry) ?? widget.container),
        currentDirPath: widget.currentDirPath,
        thumbnailCacheMode: _cacheModeOf(entry),
        thumbnailQuality: _qualityOf(entry),
        showThumbnail: widget.showThumbnails,
        isPinned: isPinned,
        isBookmark: isBookmark,
        showItemActionsMenu: widget.showItemActionsMenu,
        showFileExtensions: widget.showFileExtensions,
        onTap: () => widget.onFileTap(entry),
        onLongPress: () {},
        onLongMenu: widget.onFileLongMenu,
        onIconTap: widget.onIconTap == null ? null : () => widget.onIconTap!(entry),
        archiveContext: widget.archiveContext,
        archiveRootPath: widget.archiveRootPath,
      );
    }
    return HoldSelectableItem(
      key: ValueKey(entry),
      index: index,
      entry: entry,
      child: BrowserItemDragItem(
        entry: entry,
        container: (widget.containerFor?.call(entry) ?? widget.container),
        currentDirectory: widget.currentDirPath,
        visibleItems: widget.items,
        selectedItems: widget.selectedItems,
        isSelectionMode: widget.isSelectionMode,
        enabled: widget.enableFileDrag && widget.archiveContext == null,
        onItemLongPress: widget.onItemLongPress,
        onDrop: widget.onFileDrop,
        child: tile,
      ),
    );
  }

  Widget _buildGroupedChild(
    BuildContext context,
    GalleryGroupIndex<RawEntry> groups,
    int child,
  ) {
    final g = groups.childGroup[child];
    final local = groups.childLocal[child];
    final group = groups.groups[g];
    if (local < 0) {
      // The sliver gives the header a tight box of exactly the extent the
      // layout reserved; Align keeps the header at its natural size inside it.
      return Align(
        key: ValueKey('gallery_header:$g'),
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: GalleryDateHeader(
            title: group.label ?? formatDateGroupHeader(group.date, context),
            count: group.items.length,
          ),
        ),
      );
    }
    return _buildItemRow(context, group.items[local], group.globalIndices[local]);
  }

  /// Grouped (gallery) list: one sliver for every group, laid out from a
  /// pre-computed model (see [_groupHost]).
  Widget _buildDateGroupedListView(
    ScrollController? controller,
    double itemExtent,
    ScrollPhysics scrollPhysics,
  ) {
    final groups = _groupsFor(widget.items);
    _syncGroupHost(groups, itemExtent, _headerExtentFor(_zoomLevel));
    return CustomScrollView(
      controller: controller,
      cacheExtent: MediaQuery.sizeOf(context).height * 1.5,
      physics: scrollPhysics,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(bottom: widget.bottomClearance),
          sliver: GallerySliverGrid(
            host: _groupHost,
            delegate: SliverChildBuilderDelegate(
              (context, child) => _buildGroupedChild(context, groups, child),
              childCount: groups.childCount,
              addAutomaticKeepAlives: false,
              findChildIndexCallback: (key) =>
                  _findGroupedChildIndex(groups, key),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListView(ScrollController? controller, double itemExtent, ScrollPhysics scrollPhysics, int total) {
    return ListView.builder(
      controller: controller,
      cacheExtent: MediaQuery.sizeOf(context).height * 1.5,
      physics: scrollPhysics,
      itemExtent: itemExtent,
      findChildIndexCallback: _findChildIndex,
      padding: EdgeInsets.only(
        top: 0,
        bottom: widget.bottomClearance,
      ),
      itemCount: total,
      itemBuilder: (_, index) => _buildItemRow(context, widget.items[index], index),
    );
  }
  @override
  Widget build(BuildContext context) {
    final total = widget.items.length;
    final itemExtent = _computeItemExtent(_zoomLevel);
    final scrollPhysics = _ZoomScrollPhysics(isZooming: () => _isZooming);

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
      child: Column(
        children: [
          Expanded(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(
                  MediaQuery.textScalerOf(context).scale(1.0) * _zoomLevel,
                ),
              ),
              child: NotificationListener<ScrollNotification>(
                onNotification: _onScrollNotification,
                child: widget.scrollController == null
                    ? (widget.groupByDate
                        ? _buildDateGroupedListView(null, itemExtent, scrollPhysics)
                        : _buildListView(null, itemExtent, scrollPhysics, total))
                    : FastScrollbar(
                        controller: widget.scrollController!,
                        items: widget.items,
                        sortBy: widget.sortBy,
                        padding: EdgeInsets.only(
                          top: 0,
                          bottom: widget.bottomClearance,
                        ),
                        child: widget.groupByDate
                            ? _buildDateGroupedListView(
                                widget.scrollController,
                                itemExtent,
                                scrollPhysics,
                              )
                            : _buildListView(
                                widget.scrollController,
                                itemExtent,
                                scrollPhysics,
                                total,
                              ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
