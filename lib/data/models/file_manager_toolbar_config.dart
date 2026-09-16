import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/grid_aspect_ratio.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

enum FileDetailColumn {
  date,
  size,
  type;

  String get label => switch (this) {
        FileDetailColumn.date => 'Date',
        FileDetailColumn.size => 'Size',
        FileDetailColumn.type => 'Type',
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        FileDetailColumn.date => l10n.sortFieldDate,
        FileDetailColumn.size => l10n.sortFieldSize,
        FileDetailColumn.type => l10n.sortFieldType,
      };

  IconData get icon => switch (this) {
        FileDetailColumn.date => Icons.schedule_rounded,
        FileDetailColumn.size => Icons.data_usage_rounded,
        FileDetailColumn.type => Icons.category_outlined,
      };

  String toJson() => name;

  static FileDetailColumn? fromJson(String? value) {
    for (final c in FileDetailColumn.values) {
      if (c.name == value) return c;
    }
    return null;
  }
}

class FileManagerToolbarConfig {
  final List<FileManagerAction> order;
  final Set<FileManagerAction> hidden;
  final bool showBreadcrumbBar;
  final bool showStatsBar;
  final bool showBookmarkBar;
  final bool showHiddenFiles;
  final bool showMediaCarousel;
  final bool autoStartPlaylistMode;
  final bool rememberPerFolderLayout;
  final bool autoHideAppBar;
  final Map<String, String> folderLayoutModes;
  final Map<String, String> folderGridAspectRatios;
  final List<FileDetailColumn> detailColumnsOrder;
  final Set<FileDetailColumn> hiddenDetailColumns;
  final bool showGridFileNames;
  final GridAspectRatio gridAspectRatio;
  final bool showListThumbnails;
  final bool showItemActionsMenu;
  final LongFileNameDisplayMode longFileNameDisplayMode;
  final double listZoomLevel;
  final int gridColumnsPortrait;
  final int gridColumnsLandscape;
  final int masonryColumnsPortrait;
  final int masonryColumnsLandscape;
  final PlaylistTransitionEffect playlistTransitionEffect;
  final ThumbnailCacheMode defaultThumbnailCacheMode;
  final ThumbnailQuality defaultThumbnailQuality;

  const FileManagerToolbarConfig({
    required this.order,
    required this.hidden,
    this.showBreadcrumbBar = true,
    this.showStatsBar = true,
    this.showBookmarkBar = true,
    this.showHiddenFiles = false,
    this.showMediaCarousel = true,
    this.autoStartPlaylistMode = true,
    this.rememberPerFolderLayout = true,
    this.autoHideAppBar = true,
    this.folderLayoutModes = const {},
    this.folderGridAspectRatios = const {},
    this.detailColumnsOrder = const [
      FileDetailColumn.date,
      FileDetailColumn.size,
      FileDetailColumn.type,
    ],
    this.hiddenDetailColumns = const {FileDetailColumn.type},
    this.showGridFileNames = true,
    this.gridAspectRatio = GridAspectRatio.square,
    this.showListThumbnails = true,
    this.showItemActionsMenu = true,
    this.longFileNameDisplayMode = LongFileNameDisplayMode.ellipsizeEnd,
    this.listZoomLevel = 1.0,
    this.gridColumnsPortrait = 3,
    this.gridColumnsLandscape = 5,
    this.masonryColumnsPortrait = 2,
    this.masonryColumnsLandscape = 4,
    this.playlistTransitionEffect = PlaylistTransitionEffect.slide,
    this.defaultThumbnailCacheMode = ThumbnailCacheMode.disabled,
    this.defaultThumbnailQuality = ThumbnailQuality.defaultQuality,
  });

  factory FileManagerToolbarConfig.defaults() => const FileManagerToolbarConfig(
        order: [
          FileManagerAction.search,
          FileManagerAction.add,
          FileManagerAction.viewToggle,
          FileManagerAction.sort,
          FileManagerAction.filter,
          FileManagerAction.playMedia,
        ],
        hidden: {},
        showBreadcrumbBar: true,
        showStatsBar: true,
        showBookmarkBar: true,
        showHiddenFiles: false,
        showMediaCarousel: true,
        autoStartPlaylistMode: true,
        rememberPerFolderLayout: true,
        autoHideAppBar: true,
        folderLayoutModes: {},
        folderGridAspectRatios: {},
        detailColumnsOrder: [
          FileDetailColumn.date,
          FileDetailColumn.size,
          FileDetailColumn.type,
        ],
        hiddenDetailColumns: {FileDetailColumn.type},
        showGridFileNames: true,
        gridAspectRatio: GridAspectRatio.square,
        showListThumbnails: true,
        showItemActionsMenu: true,
        longFileNameDisplayMode: LongFileNameDisplayMode.ellipsizeEnd,
        listZoomLevel: 1.0,
        gridColumnsPortrait: 3,
        gridColumnsLandscape: 5,
        masonryColumnsPortrait: 2,
        masonryColumnsLandscape: 4,
        playlistTransitionEffect: PlaylistTransitionEffect.slide,
        defaultThumbnailCacheMode: ThumbnailCacheMode.disabled,
        defaultThumbnailQuality: ThumbnailQuality.defaultQuality,
      );

  List<FileManagerAction> get visible =>
      order.where((a) => !hidden.contains(a)).toList(growable: false);
  List<FileDetailColumn> get visibleDetailColumns => detailColumnsOrder
      .where((c) => !hiddenDetailColumns.contains(c))
      .toList(growable: false);

  GridAspectRatio getGridAspectRatioForFolder(String containerUri, String dirPath) {
    if (rememberPerFolderLayout) {
      final key = '$containerUri:$dirPath';
      final saved = folderGridAspectRatios[key];
      if (saved != null) {
        return GridAspectRatio.fromJson(saved);
      }
    }
    return gridAspectRatio;
  }

  FileManagerToolbarConfig copyWith({
    List<FileManagerAction>? order,
    Set<FileManagerAction>? hidden,
    bool? showBreadcrumbBar,
    bool? showStatsBar,
    bool? showBookmarkBar,
    bool? showHiddenFiles,
    bool? showMediaCarousel,
    bool? autoStartPlaylistMode,
    bool? rememberPerFolderLayout,
    bool? autoHideAppBar,
    Map<String, String>? folderLayoutModes,
    Map<String, String>? folderGridAspectRatios,
    List<FileDetailColumn>? detailColumnsOrder,
    Set<FileDetailColumn>? hiddenDetailColumns,
    bool? showGridFileNames,
    GridAspectRatio? gridAspectRatio,
    bool? showListThumbnails,
    bool? showItemActionsMenu,
    LongFileNameDisplayMode? longFileNameDisplayMode,
    double? listZoomLevel,
    int? gridColumnsPortrait,
    int? gridColumnsLandscape,
    int? masonryColumnsPortrait,
    int? masonryColumnsLandscape,
    PlaylistTransitionEffect? playlistTransitionEffect,
    ThumbnailCacheMode? defaultThumbnailCacheMode,
    ThumbnailQuality? defaultThumbnailQuality,
  }) =>
      FileManagerToolbarConfig(
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
        showBreadcrumbBar: showBreadcrumbBar ?? this.showBreadcrumbBar,
        showStatsBar: showStatsBar ?? this.showStatsBar,
        showBookmarkBar: showBookmarkBar ?? this.showBookmarkBar,
        showHiddenFiles: showHiddenFiles ?? this.showHiddenFiles,
        showMediaCarousel: showMediaCarousel ?? this.showMediaCarousel,
        autoStartPlaylistMode:
            autoStartPlaylistMode ?? this.autoStartPlaylistMode,
        rememberPerFolderLayout:
            rememberPerFolderLayout ?? this.rememberPerFolderLayout,
        autoHideAppBar: autoHideAppBar ?? this.autoHideAppBar,
        folderLayoutModes: folderLayoutModes ?? this.folderLayoutModes,
        folderGridAspectRatios:
            folderGridAspectRatios ?? this.folderGridAspectRatios,
        detailColumnsOrder: detailColumnsOrder ?? this.detailColumnsOrder,
        hiddenDetailColumns: hiddenDetailColumns ?? this.hiddenDetailColumns,
        showGridFileNames: showGridFileNames ?? this.showGridFileNames,
        gridAspectRatio: gridAspectRatio ?? this.gridAspectRatio,
        showListThumbnails: showListThumbnails ?? this.showListThumbnails,
        showItemActionsMenu: showItemActionsMenu ?? this.showItemActionsMenu,
        longFileNameDisplayMode:
            longFileNameDisplayMode ?? this.longFileNameDisplayMode,
        listZoomLevel: listZoomLevel ?? this.listZoomLevel,
        gridColumnsPortrait: gridColumnsPortrait ?? this.gridColumnsPortrait,
        gridColumnsLandscape:
            gridColumnsLandscape ?? this.gridColumnsLandscape,
        masonryColumnsPortrait:
            masonryColumnsPortrait ?? this.masonryColumnsPortrait,
        masonryColumnsLandscape:
            masonryColumnsLandscape ?? this.masonryColumnsLandscape,
        playlistTransitionEffect:
            playlistTransitionEffect ?? this.playlistTransitionEffect,
        defaultThumbnailCacheMode:
            defaultThumbnailCacheMode ?? this.defaultThumbnailCacheMode,
        defaultThumbnailQuality:
            defaultThumbnailQuality ?? this.defaultThumbnailQuality,
      );

  Map<String, dynamic> toJson() => {
        'order': order.map((a) => a.toJson()).toList(),
        'hidden': hidden.map((a) => a.toJson()).toList(),
        'showBreadcrumbBar': showBreadcrumbBar,
        'showStatsBar': showStatsBar,
        'showBookmarkBar': showBookmarkBar,
        'showHiddenFiles': showHiddenFiles,
        'showMediaCarousel': showMediaCarousel,
        'autoStartPlaylistMode': autoStartPlaylistMode,
        'rememberPerFolderLayout': rememberPerFolderLayout,
        'autoHideAppBar': autoHideAppBar,
        'folderLayoutModes': folderLayoutModes,
        'folderGridAspectRatios': folderGridAspectRatios,
        'detailColumnsOrder':
            detailColumnsOrder.map((c) => c.toJson()).toList(),
        'hiddenDetailColumns':
            hiddenDetailColumns.map((c) => c.toJson()).toList(),
        'showGridFileNames': showGridFileNames,
        'gridAspectRatio': gridAspectRatio.toJson(),
        'showListThumbnails': showListThumbnails,
        'showItemActionsMenu': showItemActionsMenu,
        'longFileNameDisplayMode': longFileNameDisplayMode.toJson(),
        'listZoomLevel': listZoomLevel,
        'gridColumnsPortrait': gridColumnsPortrait,
        'gridColumnsLandscape': gridColumnsLandscape,
        'masonryColumnsPortrait': masonryColumnsPortrait,
        'masonryColumnsLandscape': masonryColumnsLandscape,
        'playlistTransitionEffect': playlistTransitionEffect.toJson(),
        'defaultThumbnailCacheMode': defaultThumbnailCacheMode.toJson(),
        'defaultThumbnailQuality': defaultThumbnailQuality.toJson(),
      };

  factory FileManagerToolbarConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return FileManagerToolbarConfig.defaults();
    final rawOrder = (j['order'] as List<dynamic>? ?? [])
        .map((v) => FileManagerAction.fromJson(v as String?))
        .whereType<FileManagerAction>()
        .toList();
    for (final a in FileManagerAction.values) {
      if (!rawOrder.contains(a)) rawOrder.add(a);
    }
    final hidden = (j['hidden'] as List<dynamic>? ?? [])
        .map((v) => FileManagerAction.fromJson(v as String?))
        .whereType<FileManagerAction>()
        .toSet();
    final rawDetailColumns = (j['detailColumnsOrder'] as List<dynamic>? ?? [])
        .map((v) => FileDetailColumn.fromJson(v as String?))
        .whereType<FileDetailColumn>()
        .toList();
    for (final c in FileDetailColumn.values) {
      if (!rawDetailColumns.contains(c)) rawDetailColumns.add(c);
    }
    final hiddenDetailColumns = j.containsKey('hiddenDetailColumns')
        ? (j['hiddenDetailColumns'] as List<dynamic>? ?? [])
            .map((v) => FileDetailColumn.fromJson(v as String?))
            .whereType<FileDetailColumn>()
            .toSet()
        : const {FileDetailColumn.type};
    final rawFolderLayoutModes = (j['folderLayoutModes'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as String),
        ) ??
        const <String, String>{};
    final rawFolderGridAspectRatios =
        (j['folderGridAspectRatios'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v as String),
        ) ??
        const <String, String>{};
    final defaultThumbnailCacheMode =
        ThumbnailCacheMode.fromJson(
          j['defaultThumbnailCacheMode'] as String?,
        ) ??
        ThumbnailCacheMode.disabled;
    final defaultThumbnailQuality =
        ThumbnailQuality.fromJson(j['defaultThumbnailQuality']);
    final longFileNameDisplayMode =
        LongFileNameDisplayMode.fromJson(
          j['longFileNameDisplayMode'] as String?,
        ) ??
        LongFileNameDisplayMode.ellipsizeEnd;

    return FileManagerToolbarConfig(
      order: rawOrder,
      hidden: hidden,
      showBreadcrumbBar: j['showBreadcrumbBar'] as bool? ?? true,
      showStatsBar: j['showStatsBar'] as bool? ?? true,
      showBookmarkBar: j['showBookmarkBar'] as bool? ?? true,
      showHiddenFiles: j['showHiddenFiles'] as bool? ?? false,
      showMediaCarousel: j['showMediaCarousel'] as bool? ?? true,
      autoStartPlaylistMode: j['autoStartPlaylistMode'] as bool? ?? true,
      rememberPerFolderLayout: j['rememberPerFolderLayout'] as bool? ?? true,
      autoHideAppBar: j['autoHideAppBar'] as bool? ?? true,
      folderLayoutModes: rawFolderLayoutModes,
      folderGridAspectRatios: rawFolderGridAspectRatios,
      detailColumnsOrder: rawDetailColumns.isEmpty
          ? const [
              FileDetailColumn.date,
              FileDetailColumn.size,
              FileDetailColumn.type,
            ]
          : rawDetailColumns,
      hiddenDetailColumns: hiddenDetailColumns,
      showGridFileNames: j['showGridFileNames'] as bool? ?? true,
      gridAspectRatio: GridAspectRatio.fromJson(j['gridAspectRatio'] as String?),
      showListThumbnails: j['showListThumbnails'] as bool? ?? true,
      showItemActionsMenu: j['showItemActionsMenu'] as bool? ?? true,
      longFileNameDisplayMode: longFileNameDisplayMode,
      listZoomLevel: (j['listZoomLevel'] as num?)?.toDouble() ?? 1.0,
      gridColumnsPortrait: (j['gridColumnsPortrait'] as num?)?.toInt() ?? 3,
      gridColumnsLandscape: (j['gridColumnsLandscape'] as num?)?.toInt() ?? 5,
      masonryColumnsPortrait:
          (j['masonryColumnsPortrait'] as num?)?.toInt() ?? 2,
      masonryColumnsLandscape:
          (j['masonryColumnsLandscape'] as num?)?.toInt() ?? 4,
      playlistTransitionEffect: PlaylistTransitionEffect.fromJson(
        j['playlistTransitionEffect'] as String?,
      ),
      defaultThumbnailCacheMode: defaultThumbnailCacheMode,
      defaultThumbnailQuality: defaultThumbnailQuality,
    );
  }
}