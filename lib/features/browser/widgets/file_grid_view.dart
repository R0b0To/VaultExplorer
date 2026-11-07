import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/core/utils/file_display_name.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/thumbnail/async_thumbnail.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/grid_aspect_ratio.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/data/services/video_thumbnail_fetcher.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_layout.dart';
import 'package:vaultexplorer/features/browser/gallery/gallery_sliver.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';
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

class FileGridView extends StatefulWidget {
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
  final GridAspectRatio gridAspectRatio;
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

  final ArchiveContext? archiveContext;
  final String? archiveRootPath;
  final SortBy? sortBy;
  final bool groupByDate;

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

  const FileGridView({
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
    this.gridAspectRatio = GridAspectRatio.square,
    this.initialColumns = 3,
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
    this.archiveContext,
    this.archiveRootPath,
    this.sortBy,
    this.groupByDate = false,
    this.containerFor,
    this.cacheModeFor,
    this.qualityFor,
  });

  @override
  State<FileGridView> createState() => _FileGridViewState();
}

class _FileGridViewState extends State<FileGridView>
    with SingleTickerProviderStateMixin {
  MountedContainer _containerOf(RawEntry entry) =>
      widget.containerFor?.call(entry) ?? widget.container;

  ThumbnailCacheMode _cacheModeOf(RawEntry entry) =>
      widget.cacheModeFor?.call(entry) ?? widget.thumbnailCacheMode;

  Orientation? _lastOrientation;
  late int _crossAxisCount;
  double? _viewportWidth;
  double _baselineScale = 1.0;
  final Map<Key, int> _keyIndexMap = {};

  int? _anchorItemIndex;

  // The date-grouped layout: one sliver for every day (see GallerySliverGrid).
  final GalleryLayoutHost _groupHost = GalleryLayoutHost(
    flow: GalleryFlow.columns,
  );
  _GridGroups? _groups;
  String _groupHostKey = '';

  // Animation controller for clearly visible column morph transition
  late final AnimationController _morphController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _crossAxisCount = widget.initialColumns;
    _updateKeyIndexMap();

    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1.0,
    );
    _scaleAnimation = const AlwaysStoppedAnimation<double>(1.0);
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  void _updateKeyIndexMap() {
    _keyIndexMap.clear();
    for (int i = 0; i < widget.items.length; i++) {
      _keyIndexMap[ValueKey(widget.items[i])] = i;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.of(context).orientation;
    if (_lastOrientation != orientation) {
      _crossAxisCount = widget.initialColumns.clamp(_minColumns, _maxColumns);
      _lastOrientation = orientation;
    }
  }

  @override
  void didUpdateWidget(covariant FileGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialColumns != widget.initialColumns) {
      final newCols = widget.initialColumns.clamp(_minColumns, _maxColumns);
      if (newCols != _crossAxisCount) {
        _crossAxisCount = newCols;
      }
    }
    if (oldWidget.items != widget.items) {
      _updateKeyIndexMap();
    }
  }

  int get _minColumns => 1;

  int get _maxColumns {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? 7 : 4;
  }

  double _getViewportWidth(BuildContext context) {
    final width = _viewportWidth;
    return width != null && width.isFinite
        ? width
        : MediaQuery.sizeOf(context).width;
  }

  double _getTileWidth(int columns, BuildContext context) {
    final width = _getViewportWidth(context);
    return (width - 20 - (columns - 1) * widget.spacing) / columns;
  }

  double _getAspectRatio(int columns) {
    final previewRatio = widget.gridAspectRatio.ratio;
    if (!widget.showFileNames) {
      return previewRatio;
    }
    final tileWidth = _getTileWidth(columns, context);
    const labelHeight = 36.0;
    final previewHeight = tileWidth / previewRatio;
    final totalHeight = previewHeight + labelHeight;
    return tileWidth / totalHeight;
  }

  /// The thumbnail quality to request for the current grid. For an auto
  /// quality this is derived from the real pixel width of a cell (same
  /// geometry as the grid delegate below), so fewer columns => sharper
  /// thumbnails, matching how Fossify Gallery sizes them.
  ThumbnailQuality _effectiveQualityOf(RawEntry entry) {
    final q = widget.qualityFor?.call(entry) ?? widget.thumbnailQuality;
    if (!q.auto) return q;
    final tileWidth = _getTileWidth(_crossAxisCount, context);
    return q.resolveForCell(
      logicalWidth: tileWidth,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  double _getTileHeight(int columns) {
    final tileWidth = _getTileWidth(columns, context);
    final previewRatio = widget.gridAspectRatio.ratio;
    final labelHeight = widget.showFileNames ? 36.0 : 0.0;
    return (tileWidth / previewRatio) + labelHeight;
  }

  void _handleScaleStart(ScaleStartDetails details) {
    _baselineScale = 1.0;

    final controller = widget.scrollController;
    if (controller != null && controller.hasClients) {
      final currentTileHeight = _getTileHeight(_crossAxisCount);
      final rowHeight = currentTileHeight + widget.spacing;
      final viewport = controller.position.viewportDimension;
      final viewportCenter = controller.offset + (viewport / 2.0);
      final centerRow = math.max(
        0,
        ((viewportCenter - 12.0) / rowHeight).round(),
      );
      // Lock the center item index ONCE for the whole gesture so continuous zooming never drifts to 0
      _anchorItemIndex = (centerRow * _crossAxisCount).clamp(
        0,
        widget.items.length - 1,
      );
    }
  }

  void _changeColumns(int newColumns, double newBaseline) {
    HapticFeedback.selectionClick();

    final oldColumns = _crossAxisCount;
    final isZoomIn = newColumns < oldColumns;

    // Grouped mode keeps whatever is at the top of the screen in place through
    // the sliver's own layout pass; the row-estimate jump below is for the
    // plain grid.
    final groupedAnchor = widget.groupByDate
        ? _groupHost.captureTopAnchor()
        : null;
    setState(() {
      _crossAxisCount = newColumns;
      _baselineScale = newBaseline;
    });
    widget.onColumnCountChanged?.call(_crossAxisCount);

    // Snappy physical pop — NO black fade, 100% solid & bright at all times!
    final startScale = isZoomIn ? 0.90 : 1.10;
    _scaleAnimation = Tween<double>(begin: startScale, end: 1.0).animate(
      CurvedAnimation(parent: _morphController, curve: Curves.easeOutCubic),
    );
    _morphController.forward(from: 0.0);

    if (widget.groupByDate) {
      _groupHost.pendingAnchor = groupedAnchor;
      return;
    }

    final controller = widget.scrollController;
    final anchor = _anchorItemIndex;
    if (controller != null && controller.hasClients && anchor != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!controller.hasClients) return;
        final newTileHeight = _getTileHeight(newColumns);
        final newRowHeight = newTileHeight + widget.spacing;
        final targetRow = anchor ~/ newColumns;
        final targetRowCenter =
            12.0 + (targetRow * newRowHeight) + (newTileHeight / 2.0);
        final viewport = controller.position.viewportDimension;
        final maxScroll = controller.position.maxScrollExtent;
        final targetOffset = (targetRowCenter - (viewport / 2.0))
            .clamp(0.0, math.max<double>(0.0, maxScroll))
            .toDouble();
        controller.jumpTo(targetOffset);
      });
    }
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2) return;
    if (_anchorItemIndex == null) {
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
    if (factor > 1.18 && _crossAxisCount > _minColumns) {
      _changeColumns(_crossAxisCount - 1, scale);
    } else if (factor < 0.82 && _crossAxisCount < _maxColumns) {
      _changeColumns(_crossAxisCount + 1, scale);
    }
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _anchorItemIndex = null;
  }

  bool _onScrollNotification(ScrollNotification notification) {
    // Disposed tiles already drop their queued request; cancelling the whole
    // visible tier also cancelled tiles still on screen (see masonry view).
    return false;
  }

  Widget _buildItem(BuildContext context, RawEntry entry, int index) {
    return HoldSelectableItem(
      key: ValueKey(entry),
      index: index,
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
        child: entry.isDir
            ? _buildDirCell(context, entry)
            : _buildFileCell(context, entry),
      ),
    );
  }

  Widget _buildAnimatedGridView(ScrollController? controller, int total) {
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
      child: GridView.builder(
        controller: controller,
        cacheExtent: MediaQuery.sizeOf(context).height * 1.5,
        physics:
            const AlwaysScrollableScrollPhysics(), // Native scroll physics that cannot freeze
        findChildIndexCallback: (Key key) => _keyIndexMap[key],
        padding: EdgeInsets.fromLTRB(10, 12, 10, widget.bottomClearance),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _crossAxisCount,
          crossAxisSpacing: widget.spacing,
          mainAxisSpacing: widget.spacing,
          childAspectRatio: _getAspectRatio(_crossAxisCount),
        ),
        itemCount: total,
        itemBuilder: (context, index) {
          final entry = widget.items[index];
          return _buildItem(context, entry, index);
        },
      ),
    );
  }

  _GridGroups _groupsFor(List<RawEntry> items) {
    final cached = _groups;
    if (cached != null && identical(cached.source, items)) return cached;
    return _groups = _GridGroups(items, computeDateGroups(items));
  }

  void _syncGroupHost(_GridGroups groups, double aspect, double headerExtent) {
    final key =
        '${identityHashCode(groups)}|$_crossAxisCount|${widget.spacing}|$aspect|$headerExtent';
    if (key == _groupHostKey) return;
    _groupHostKey = key;
    _groupHost
      ..columnCount = _crossAxisCount
      ..spacing = widget.spacing
      ..sectionGap = 12.0
      ..sections = [
        for (final g in groups.groups)
          GallerySection(itemCount: g.items.length, headerExtent: headerExtent),
      ]
      ..ratioOf = ((_) => aspect)
      ..footerOf = null
      ..invalidate();
  }

  Widget _buildDateGroupedGridView(ScrollController? controller) {
    final groups = _groupsFor(widget.items);
    final aspect = _getAspectRatio(_crossAxisCount);
    _syncGroupHost(
      groups,
      aspect.isFinite && aspect > 0 ? aspect : 1.0,
      galleryDateHeaderExtent(context),
    );

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
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            // The last day's gap is not part of the sliver's extent.
            padding: EdgeInsets.fromLTRB(10, 0, 10, widget.bottomClearance + 12),
            // One sliver for every day, headers included: a sliver per day
            // makes the viewport lay out (and build a tile in) every one of
            // them on every scrolled frame.
            sliver: GallerySliverGrid(
              host: _groupHost,
              delegate: SliverChildBuilderDelegate(
                (context, child) {
                  final g = groups.childGroup[child];
                  final local = groups.childLocal[child];
                  final group = groups.groups[g];
                  if (local < 0) {
                    return Align(
                      key: ValueKey('gallery_header:$g'),
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: GalleryDateHeader(
                          title: formatDateGroupHeader(group.date, context),
                          count: group.items.length,
                          horizontalPadding: 6,
                        ),
                      ),
                    );
                  }
                  return _buildItem(
                    context,
                    group.items[local],
                    group.globalIndices[local],
                  );
                },
                childCount: groups.childCount,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : null;

        return HoldRangeSelectContainer(
          items: widget.items,
          selectedItems: widget.selectedItems,
          isSelectionMode: widget.isSelectionMode,
          onSelectionChanged: (newSelection) =>
              widget.onSelectionChanged?.call(newSelection),
          onLongPressSelect: (entry) => widget.onItemLongPress(entry),
          enableHoldDrag:
              widget.enableFileDrag && widget.archiveContext == null,
          onScaleStart: _handleScaleStart,
          onScaleUpdate: _handleScaleUpdate,
          onScaleEnd: _handleScaleEnd,
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScrollNotification,
            child: widget.scrollController == null
                ? (widget.groupByDate
                    ? _buildDateGroupedGridView(null)
                    : _buildAnimatedGridView(null, total))
                : FastScrollbar(
                    controller: widget.scrollController!,
                    items: widget.items,
                    sortBy: widget.sortBy,
                    padding: EdgeInsets.only(
                      top: 12,
                      bottom: widget.bottomClearance,
                    ),
                    child: widget.groupByDate
                        ? _buildDateGroupedGridView(widget.scrollController)
                        : _buildAnimatedGridView(
                            widget.scrollController,
                            total,
                          ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildDirCell(BuildContext context, RawEntry entry) {
    final isSelected = widget.selectedItems.contains(entry);
    final cs = Theme.of(context).colorScheme;
    final fullPath = widget.currentDirPath.isEmpty
        ? entry.name
        : '${widget.currentDirPath}/${entry.name}';
    final isMounted = widget.mountedFolderPaths.contains(fullPath);

    final iconSize = GridCardUtils.calculateIconSize(
      context,
      _crossAxisCount,
      spacing: widget.spacing,
      viewportWidth: _getViewportWidth(context),
    );
    final skin = FileManagerSkinScope.of(context);
    final folderIcon = Icon(
      skin.folderIcon,
      size: iconSize,
      color: isSelected ? cs.primary : skin.folderIconColor(cs),
    );

    return GridCardShell(
      cornerRadius: widget.cornerRadius,
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
              key: ValueKey(
                'folder_preview:${_containerOf(entry).uri}:$fullPath',
              ),
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

  Widget _buildFileCell(BuildContext context, RawEntry entry) {
    final cs = Theme.of(context).colorScheme;
    final cleanName = entry.name;
    final fullPath = widget.currentDirPath.isEmpty
        ? cleanName
        : '${widget.currentDirPath}/$cleanName';
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
      _crossAxisCount,
      spacing: widget.spacing,
      viewportWidth: _getViewportWidth(context),
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
        tag: 'media_hero_${_containerOf(entry).volId}_$fullPath',
        child: Material(
          type: MaterialType.transparency,
          child: _EncryptedImageGridThumb(
            container: _containerOf(entry),
            filePath: fullPath,
            cacheMode: _cacheModeOf(entry),
            quality: _effectiveQualityOf(entry),
            archiveContext: widget.archiveContext,
            archiveRootPath: widget.archiveRootPath,
          ),
        ),
      );
    } else if (isVid) {
      previewWidget = Hero(
        tag: 'media_hero_${_containerOf(entry).volId}_$fullPath',
        child: Material(
          type: MaterialType.transparency,
          child: _VideoThumb(
            container: _containerOf(entry),
            filePath: fullPath,
            cacheMode: _cacheModeOf(entry),
            quality: _effectiveQualityOf(entry),
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
          child: _ApkIconGridThumb(
            container: _containerOf(entry),
            filePath: fullPath,
            cacheMode: _cacheModeOf(entry),
            quality: _effectiveQualityOf(entry),
            fallbackIcon: skin.fileIcon(cleanName),
            fallbackColor: skin.fileIconColor(cs, cleanName),
            fallbackIconSize: iconSize,
          ),
        ),
      );
    } else if (isBook && widget.archiveContext == null) {
      // Same restriction as the APK above: a book nested inside an open
      // archive has no container/local path for the native side to open.
      previewWidget = _BookCoverGridThumb(
        container: _containerOf(entry),
        filePath: fullPath,
        cacheMode: _cacheModeOf(entry),
        quality: _effectiveQualityOf(entry),
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

class _EncryptedImageGridThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;

  const _EncryptedImageGridThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    this.archiveContext,
    this.archiveRootPath,
  });

  static Future<Uint8List> _fetch(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
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
      return bytes;
    }
    if (mode != ThumbnailCacheMode.disabled) {
      final cached = await thumbnailCache.fetch(
        container: container,
        filePath: path,
        mode: mode,
        quality: quality,
      );
      if (cached != null && cached.isNotEmpty) return cached;
    }
    Uint8List? thumbBytes = await fileIoApi.getImageThumbnailOrThrow(
      container,
      path,
      targetSize: quality.scaledSize(180),
      quality: quality.jpegQuality,
    );
    if (thumbBytes == null || thumbBytes.isEmpty) {
      final raw = await readRawThumbnailFallback(fileIoApi, container, path);
      if (raw.length < 200 * 1024) {
        thumbnailCache.cacheInMemory(container, path, raw, quality);
      }
      return raw;
    }
    thumbnailCache.cacheInMemory(container, path, thumbBytes, quality);
    if (mode != ThumbnailCacheMode.disabled) {
      unawaited(
        thumbnailCache.store(
          container: container,
          filePath: path,
          data: thumbBytes,
          mode: mode,
          quality: quality,
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

    return AsyncThumbnail(
      key: ValueKey('img:$filePath'),
      container: container,
      filePath: filePath,
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: ThumbnailConcurrency.imageLimiter,
      quality: quality,
      fetchFn: (c, p) => _fetch(
        thumbnailCache,
        fileIoApi,
        c,
        p,
        cacheMode,
        quality,
        archiveContext,
        archiveRootPath,
      ),
      debounce: const Duration(milliseconds: 30),
      syncLookup: () => thumbnailCache.peekMemory(container, filePath, quality),
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

class _VideoThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;
  final ArchiveContext? archiveContext;
  final String? archiveRootPath;

  const _VideoThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    this.archiveContext,
    this.archiveRootPath,
  });

  static Future<Uint8List> _fetch(
    ThumbnailCacheService thumbnailCache,
    VaultFileIoApi fileIoApi,
    MountedContainer container,
    String path,
    ThumbnailCacheMode mode,
    ThumbnailQuality quality,
    ArchiveContext? archiveContext,
    String? archiveRootPath,
  ) => VideoThumbnailFetcher.fetch(
    thumbnailCache,
    fileIoApi,
    container,
    path,
    mode: mode,
    quality: quality,
    targetSize: quality.scaledSize(180),
    archiveContext: archiveContext,
    archiveRootPath: archiveRootPath,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final cs = Theme.of(context).colorScheme;

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
            archiveContext,
            archiveRootPath,
          ),
          debounce: const Duration(milliseconds: 60),
          syncLookup: () =>
              thumbnailCache.peekMemory(container, filePath, quality),
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

class _ApkIconGridThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;

  final IconData fallbackIcon;
  final Color fallbackColor;
  final double fallbackIconSize;

  const _ApkIconGridThumb({
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

/// A book's cover as its grid tile, in place of the generic file-type icon.
///
/// Whatever has no cover to show -- an EPUB that names none, a "comic" that is
/// really a RAR -- keeps exactly that icon, so loading and failure both draw
/// the icon rather than a spinner or a broken-image glyph: most failures are
/// permanent, and a tile that spun and then switched to an icon would flicker
/// for every such book.
class _BookCoverGridThumb extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  final ThumbnailCacheMode cacheMode;
  final ThumbnailQuality quality;

  final IconData fallbackIcon;
  final Color fallbackColor;
  final double fallbackIconSize;

  const _BookCoverGridThumb({
    required this.container,
    required this.filePath,
    required this.cacheMode,
    required this.quality,
    required this.fallbackIcon,
    required this.fallbackColor,
    required this.fallbackIconSize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailCache = ref.read(thumbnailCacheServiceProvider);
    final bookApi = ref.read(vaultBookApiProvider);

    return AsyncThumbnail(
      key: ValueKey('book:$filePath'),
      container: container,
      filePath: filePath,
      cache: ThumbnailConcurrency.inFlightThumbnails,
      limiter: ThumbnailConcurrency.imageLimiter,
      quality: quality,
      fetchFn: (c, p) async => (await loadBookCoverThumbnail(
        thumbnailCache: thumbnailCache,
        bookApi: bookApi,
        container: c,
        path: p,
        mode: cacheMode,
        quality: quality,
      )).bytes,
      debounce: const Duration(milliseconds: 30),
      syncLookup: () => thumbnailCache.peekMemory(container, filePath, quality),
      cacheHeight: quality.scaledSize(180),
      // Covers are portrait and the cell is usually squarer: anchor to the top,
      // where the title is, so a crop trims the bottom rather than the middle.
      imageBuilder: (context, bytes, cacheHeight) => Image.memory(
        bytes,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
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

/// The date groups of a list, plus the map from a child index of the grouped
/// sliver (a header per group, then its items) back to a group and an item.
class _GridGroups {
  _GridGroups(this.source, this.groups)
    : childCount = source.length + groups.length,
      childGroup = Int32List(source.length + groups.length),
      childLocal = Int32List(source.length + groups.length) {
    var c = 0;
    for (var g = 0; g < groups.length; g++) {
      childGroup[c] = g;
      childLocal[c] = -1;
      c++;
      for (var j = 0; j < groups[g].items.length; j++) {
        childGroup[c] = g;
        childLocal[c] = j;
        c++;
      }
    }
  }

  final List<RawEntry> source;
  final List<DateGroup<RawEntry>> groups;
  final int childCount;

  /// Child index -> group.
  final Int32List childGroup;

  /// Child index -> index inside the group, or -1 for the group's header.
  final Int32List childLocal;
}
