import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/data/models/grid_aspect_ratio.dart';
import 'package:vaultexplorer/data/models/grid_corner_style.dart';
import 'package:vaultexplorer/data/models/long_file_name_display_mode.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/thumbnail_settings.dart';
import 'package:vaultexplorer/data/models/media_viewer_toolbar_config.dart';
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

  /// When true, switching the file-list layout mode puts every
  /// pinch-adjustable size (list zoom, grid and masonry column counts) back
  /// at its default -- see [withDefaultSizes].
  final bool resetSizeOnLayoutChange;
  final bool autoHideAppBar;
  final bool useFabForToolbar;
  final bool bottomSelectionBar;
  final Map<String, String> folderLayoutModes;
  final Map<String, String> folderGridAspectRatios;
  final Map<String, String> folderSortModes;
  final List<FileDetailColumn> detailColumnsOrder;
  final Set<FileDetailColumn> hiddenDetailColumns;
  final bool showGridFileNames;
  final GridAspectRatio gridAspectRatio;

  /// Corner shape of grid/masonry cards (applies to both views).
  final GridCornerStyle gridCornerStyle;

  /// Gap between grid/masonry cards in logical px (0 = touching). Applies to
  /// both views.
  final int gridSpacing;
  static const int defaultGridSpacing = 8;
  static const int minGridSpacing = 0;
  static const int maxGridSpacing = 24;

  final bool showListThumbnails;
  final bool showItemActionsMenu;

  /// Whether tapping a list row's leading icon/thumbnail toggles that item's
  /// selection. Off: the icon is part of the row and a tap opens the item;
  /// selecting then starts with a long press.
  final bool selectByIcon;

  /// Whether file names are listed with their extension ("report.pdf") or
  /// without ("report"). Folders have no extension and are unaffected.
  final bool showFileExtensions;
  final LongFileNameDisplayMode longFileNameDisplayMode;
  final double listZoomLevel;
  final int gridColumnsPortrait;
  final int gridColumnsLandscape;
  final int masonryColumnsPortrait;
  final int masonryColumnsLandscape;
  final PlaylistTransitionEffect playlistTransitionEffect;
  /// The app-wide thumbnail default: what every vault that has no thumbnail
  /// settings of its own ("Use global default") uses.
  final ThumbnailCacheMode defaultThumbnailCacheMode;
  final ThumbnailQuality defaultThumbnailQuality;

  /// The thumbnail settings shared by Local Storage and the decoy file
  /// manager. Deliberately a slot of its own rather than a fallback to the
  /// vault default -- see `resolveThumbnailSettings`.
  final ThumbnailCacheMode localStorageThumbnailCacheMode;
  final ThumbnailQuality localStorageThumbnailQuality;
  final MediaViewerToolbarConfig mediaViewerToolbarConfig;

  /// How file and folder icons, their backgrounds and names look in the
  /// file manager. See [FileManagerSkin].
  final FileManagerSkin skin;

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
    this.resetSizeOnLayoutChange = true,
    this.autoHideAppBar = true,
    this.useFabForToolbar = false,
    this.bottomSelectionBar = false,
    this.folderLayoutModes = const {},
    this.folderGridAspectRatios = const {},
    this.folderSortModes = const {},
    this.detailColumnsOrder = const [
      FileDetailColumn.date,
      FileDetailColumn.size,
      FileDetailColumn.type,
    ],
    this.hiddenDetailColumns = const {FileDetailColumn.type},
    this.showGridFileNames = true,
    this.gridAspectRatio = GridAspectRatio.square,
    this.gridCornerStyle = GridCornerStyle.rounded,
    this.gridSpacing = defaultGridSpacing,
    this.showListThumbnails = true,
    this.showItemActionsMenu = true,
    this.selectByIcon = true,
    this.showFileExtensions = true,
    this.longFileNameDisplayMode = LongFileNameDisplayMode.ellipsizeEnd,
    this.listZoomLevel = 1.0,
    this.gridColumnsPortrait = 3,
    this.gridColumnsLandscape = 5,
    this.masonryColumnsPortrait = 2,
    this.masonryColumnsLandscape = 4,
    this.playlistTransitionEffect = PlaylistTransitionEffect.slide,
    this.defaultThumbnailCacheMode = ThumbnailCacheMode.disabled,
    this.defaultThumbnailQuality = ThumbnailQuality.defaultQuality,
    this.localStorageThumbnailCacheMode = ThumbnailCacheMode.disabled,
    this.localStorageThumbnailQuality = ThumbnailQuality.defaultQuality,
    this.mediaViewerToolbarConfig = const MediaViewerToolbarConfig(),
    this.skin = FileManagerSkin.classic,
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
        resetSizeOnLayoutChange: true,
        autoHideAppBar: true,
        useFabForToolbar: false,
        bottomSelectionBar: false,
        folderLayoutModes: {},
        folderGridAspectRatios: {},
        folderSortModes: {},
        detailColumnsOrder: [
          FileDetailColumn.date,
          FileDetailColumn.size,
          FileDetailColumn.type,
        ],
        hiddenDetailColumns: {FileDetailColumn.type},
        showGridFileNames: true,
        gridAspectRatio: GridAspectRatio.square,
        gridCornerStyle: GridCornerStyle.rounded,
        gridSpacing: defaultGridSpacing,
        showListThumbnails: true,
        showItemActionsMenu: true,
        selectByIcon: true,
        showFileExtensions: true,
        longFileNameDisplayMode: LongFileNameDisplayMode.ellipsizeEnd,
        listZoomLevel: 1.0,
        gridColumnsPortrait: 3,
        gridColumnsLandscape: 5,
        masonryColumnsPortrait: 2,
        masonryColumnsLandscape: 4,
        playlistTransitionEffect: PlaylistTransitionEffect.slide,
        defaultThumbnailCacheMode: ThumbnailCacheMode.disabled,
        defaultThumbnailQuality: ThumbnailQuality.defaultQuality,
        localStorageThumbnailCacheMode: ThumbnailCacheMode.disabled,
        localStorageThumbnailQuality: ThumbnailQuality.defaultQuality,
        mediaViewerToolbarConfig: const MediaViewerToolbarConfig(),
        skin: FileManagerSkin.classic,
      );

  /// [defaultThumbnailCacheMode] + [defaultThumbnailQuality] as one value.
  ThumbnailSettings get defaultThumbnails => ThumbnailSettings(
        cacheMode: defaultThumbnailCacheMode,
        quality: defaultThumbnailQuality,
      );

  /// The Local Storage / decoy slot as one value.
  ThumbnailSettings get localStorageThumbnails => ThumbnailSettings(
        cacheMode: localStorageThumbnailCacheMode,
        quality: localStorageThumbnailQuality,
      );

  List<FileManagerAction> get visible =>
      order.where((a) => !hidden.contains(a)).toList(growable: false);

  List<FileDetailColumn> get visibleDetailColumns => detailColumnsOrder
      .where((c) => !hiddenDetailColumns.contains(c))
      .toList(growable: false);

  /// Copy with every pinch-adjustable size -- list zoom and the grid /
  /// masonry column counts, portrait and landscape -- back at its default.
  /// Used when [resetSizeOnLayoutChange] is on and the layout mode changes.
  /// Reads the values from [FileManagerToolbarConfig.defaults] so the
  /// defaults stay defined in one place.
  FileManagerToolbarConfig withDefaultSizes() {
    final d = FileManagerToolbarConfig.defaults();
    return copyWith(
      listZoomLevel: d.listZoomLevel,
      gridColumnsPortrait: d.gridColumnsPortrait,
      gridColumnsLandscape: d.gridColumnsLandscape,
      masonryColumnsPortrait: d.masonryColumnsPortrait,
      masonryColumnsLandscape: d.masonryColumnsLandscape,
    );
  }

  /// Shared key format for every per-folder override map
  /// ([folderLayoutModes], [folderGridAspectRatios], [folderSortModes]) so
  /// all call sites disambiguate folders the same way -- a container's URI
  /// followed by the directory's path within it. Centralized here instead
  /// of being rebuilt inline at each call site so a future map can't drift
  /// onto a subtly different key format.
  static String folderKey(String containerUri, String dirPath) =>
      '$containerUri:$dirPath';

  GridAspectRatio getGridAspectRatioForFolder(
      String containerUri, String dirPath) {
    if (rememberPerFolderLayout) {
      final saved = folderGridAspectRatios[folderKey(containerUri, dirPath)];
      if (saved != null) {
        return GridAspectRatio.fromJson(saved);
      }
    }
    return gridAspectRatio;
  }

  /// Raw (undecoded) per-folder sort value for [containerUri]/[dirPath], or
  /// null when there's no saved override yet or per-folder memory is off.
  /// Returned raw (rather than decoded to a `SortBy`) so this model doesn't
  /// need to depend on the browser feature's `SortBy` type -- callers decode
  /// it with `decodeFolderSortState` (see mixins/sort_mixin.dart).
  String? getRawFolderSortMode(String containerUri, String dirPath) {
    if (!rememberPerFolderLayout) return null;
    return folderSortModes[folderKey(containerUri, dirPath)];
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
    bool? resetSizeOnLayoutChange,
    bool? autoHideAppBar,
    bool? useFabForToolbar,
    bool? bottomSelectionBar,
    Map<String, String>? folderLayoutModes,
    Map<String, String>? folderGridAspectRatios,
    Map<String, String>? folderSortModes,
    List<FileDetailColumn>? detailColumnsOrder,
    Set<FileDetailColumn>? hiddenDetailColumns,
    bool? showGridFileNames,
    GridAspectRatio? gridAspectRatio,
    GridCornerStyle? gridCornerStyle,
    int? gridSpacing,
    bool? showListThumbnails,
    bool? showItemActionsMenu,
    bool? selectByIcon,
    bool? showFileExtensions,
    LongFileNameDisplayMode? longFileNameDisplayMode,
    double? listZoomLevel,
    int? gridColumnsPortrait,
    int? gridColumnsLandscape,
    int? masonryColumnsPortrait,
    int? masonryColumnsLandscape,
    PlaylistTransitionEffect? playlistTransitionEffect,
    ThumbnailCacheMode? defaultThumbnailCacheMode,
    ThumbnailQuality? defaultThumbnailQuality,
    ThumbnailCacheMode? localStorageThumbnailCacheMode,
    ThumbnailQuality? localStorageThumbnailQuality,
    MediaViewerToolbarConfig? mediaViewerToolbarConfig,
    FileManagerSkin? skin,
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
        resetSizeOnLayoutChange:
            resetSizeOnLayoutChange ?? this.resetSizeOnLayoutChange,
        autoHideAppBar: autoHideAppBar ?? this.autoHideAppBar,
        useFabForToolbar: useFabForToolbar ?? this.useFabForToolbar,
        bottomSelectionBar: bottomSelectionBar ?? this.bottomSelectionBar,
        folderLayoutModes: folderLayoutModes ?? this.folderLayoutModes,
        folderGridAspectRatios:
            folderGridAspectRatios ?? this.folderGridAspectRatios,
        folderSortModes: folderSortModes ?? this.folderSortModes,
        detailColumnsOrder: detailColumnsOrder ?? this.detailColumnsOrder,
        hiddenDetailColumns: hiddenDetailColumns ?? this.hiddenDetailColumns,
        showGridFileNames: showGridFileNames ?? this.showGridFileNames,
        gridAspectRatio: gridAspectRatio ?? this.gridAspectRatio,
        gridCornerStyle: gridCornerStyle ?? this.gridCornerStyle,
        gridSpacing: (gridSpacing ?? this.gridSpacing)
            .clamp(minGridSpacing, maxGridSpacing),
        showListThumbnails: showListThumbnails ?? this.showListThumbnails,
        showItemActionsMenu: showItemActionsMenu ?? this.showItemActionsMenu,
        selectByIcon: selectByIcon ?? this.selectByIcon,
        showFileExtensions: showFileExtensions ?? this.showFileExtensions,
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
        localStorageThumbnailCacheMode: localStorageThumbnailCacheMode ??
            this.localStorageThumbnailCacheMode,
        localStorageThumbnailQuality:
            localStorageThumbnailQuality ?? this.localStorageThumbnailQuality,
        mediaViewerToolbarConfig:
            mediaViewerToolbarConfig ?? this.mediaViewerToolbarConfig,
        skin: skin ?? this.skin,
      );

  // -- Which export each field belongs to -------------------------------------
  //
  // Every key of [toJson] is in exactly one of these three sets (a test
  // enforces it), so a new option has to be classified when it is added.

  /// Look and layout of the file manager: toolbar buttons and their order,
  /// which bars are shown, list/grid/masonry sizing and style, and the
  /// media viewer's button layout. Travels with App skin -> Export.
  static const Set<String> interfaceKeys = {
    'order',
    'hidden',
    'showBreadcrumbBar',
    'showStatsBar',
    'showBookmarkBar',
    'showMediaCarousel',
    'autoHideAppBar',
    'useFabForToolbar',
    'bottomSelectionBar',
    'detailColumnsOrder',
    'hiddenDetailColumns',
    'showGridFileNames',
    'gridAspectRatio',
    'gridCornerStyle',
    'gridSpacing',
    'showListThumbnails',
    'showItemActionsMenu',
    'showFileExtensions',
    'longFileNameDisplayMode',
    'listZoomLevel',
    'gridColumnsPortrait',
    'gridColumnsLandscape',
    'masonryColumnsPortrait',
    'masonryColumnsLandscape',
    'playlistTransitionEffect',
    'skin',
  };

  /// How the file manager behaves rather than how it looks. Travels with
  /// Settings -> Export.
  static const Set<String> behaviorKeys = {
    'showHiddenFiles',
    'selectByIcon',
    'autoStartPlaylistMode',
    'rememberPerFolderLayout',
    'resetSizeOnLayoutChange',
    'defaultThumbnailCacheMode',
    'defaultThumbnailQuality',
    'localStorageThumbnailCacheMode',
    'localStorageThumbnailQuality',
  };

  /// Keyed by `containerUri:dirPath`, i.e. per-container path data. Never
  /// exported (see [SettingsBackupService]); the import side keeps whatever
  /// this device already has.
  static const Set<String> perFolderKeys = {
    'folderLayoutModes',
    'folderGridAspectRatios',
    'folderSortModes',
  };

  /// The nested media viewer config is split between the two exports, so it is
  /// handled by its own `interfaceToJson`/`behaviorToJson`.
  static const String _mediaViewerKey = 'mediaViewerToolbarConfig';

  Map<String, dynamic> interfaceToJson() {
    final all = toJson();
    return {
      for (final key in interfaceKeys) key: all[key],
      _mediaViewerKey: mediaViewerToolbarConfig.interfaceToJson(),
    };
  }

  Map<String, dynamic> behaviorToJson() {
    final all = toJson();
    return {
      for (final key in behaviorKeys) key: all[key],
      _mediaViewerKey: mediaViewerToolbarConfig.behaviorToJson(),
    };
  }

  /// A copy of this with the layout taken from [other]. Behavior and the
  /// per-folder maps of this device are kept.
  FileManagerToolbarConfig withInterfaceFrom(FileManagerToolbarConfig other) =>
      FileManagerToolbarConfig.fromJson({
        ...toJson(),
        ...other.interfaceToJson(),
        _mediaViewerKey: mediaViewerToolbarConfig
            .withInterfaceFrom(other.mediaViewerToolbarConfig)
            .toJson(),
      });

  /// A copy of this with the behavior taken from [other]. Layout and the
  /// per-folder maps of this device are kept.
  FileManagerToolbarConfig withBehaviorFrom(FileManagerToolbarConfig other) =>
      FileManagerToolbarConfig.fromJson({
        ...toJson(),
        ...other.behaviorToJson(),
        _mediaViewerKey: mediaViewerToolbarConfig
            .withBehaviorFrom(other.mediaViewerToolbarConfig)
            .toJson(),
      });

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
        'resetSizeOnLayoutChange': resetSizeOnLayoutChange,
        'autoHideAppBar': autoHideAppBar,
        'useFabForToolbar': useFabForToolbar,
        'bottomSelectionBar': bottomSelectionBar,
        'folderLayoutModes': folderLayoutModes,
        'folderGridAspectRatios': folderGridAspectRatios,
        'folderSortModes': folderSortModes,
        'detailColumnsOrder':
            detailColumnsOrder.map((c) => c.toJson()).toList(),
        'hiddenDetailColumns':
            hiddenDetailColumns.map((c) => c.toJson()).toList(),
        'showGridFileNames': showGridFileNames,
        'gridAspectRatio': gridAspectRatio.toJson(),
        'gridCornerStyle': gridCornerStyle.toJson(),
        'gridSpacing': gridSpacing,
        'showListThumbnails': showListThumbnails,
        'showItemActionsMenu': showItemActionsMenu,
        'selectByIcon': selectByIcon,
        'showFileExtensions': showFileExtensions,
        'longFileNameDisplayMode': longFileNameDisplayMode.toJson(),
        'listZoomLevel': listZoomLevel,
        'gridColumnsPortrait': gridColumnsPortrait,
        'gridColumnsLandscape': gridColumnsLandscape,
        'masonryColumnsPortrait': masonryColumnsPortrait,
        'masonryColumnsLandscape': masonryColumnsLandscape,
        'playlistTransitionEffect': playlistTransitionEffect.toJson(),
        'defaultThumbnailCacheMode': defaultThumbnailCacheMode.toJson(),
        'defaultThumbnailQuality': defaultThumbnailQuality.toJson(),
        'localStorageThumbnailCacheMode': localStorageThumbnailCacheMode.toJson(),
        'localStorageThumbnailQuality': localStorageThumbnailQuality.toJson(),
        'mediaViewerToolbarConfig': mediaViewerToolbarConfig.toJson(),
        'skin': skin.toJson(),
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
    final rawFolderLayoutModes =
        (j['folderLayoutModes'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v as String),
            ) ??
            const <String, String>{};
    final rawFolderGridAspectRatios =
        (j['folderGridAspectRatios'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v as String),
            ) ??
            const <String, String>{};
    final rawFolderSortModes =
        (j['folderSortModes'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v as String),
            ) ??
            const <String, String>{};
    final defaultThumbnailCacheMode = ThumbnailCacheMode.fromJson(
          j['defaultThumbnailCacheMode'] as String?,
        ) ??
        ThumbnailCacheMode.disabled;
    final defaultThumbnailQuality =
        ThumbnailQuality.fromJson(j['defaultThumbnailQuality']);
    // Configs saved before Local Storage had a thumbnail slot of its own
    // used the app-wide default for it, so an absent slot is seeded from the
    // default's value: upgrading changes nothing about how Local Storage
    // looks, and from then on the two are independent.
    final localStorageThumbnailCacheMode = j.containsKey(
          'localStorageThumbnailCacheMode',
        )
        ? (ThumbnailCacheMode.fromJson(
              j['localStorageThumbnailCacheMode'] as String?,
            ) ??
            defaultThumbnailCacheMode)
        : defaultThumbnailCacheMode;
    final localStorageThumbnailQuality =
        j.containsKey('localStorageThumbnailQuality')
            ? ThumbnailQuality.fromJson(j['localStorageThumbnailQuality'])
            : defaultThumbnailQuality;
    final longFileNameDisplayMode = LongFileNameDisplayMode.fromJson(
          j['longFileNameDisplayMode'] as String?,
        ) ??
        LongFileNameDisplayMode.ellipsizeEnd;
    final mediaViewerConfig = j.containsKey('mediaViewerToolbarConfig')
        ? MediaViewerToolbarConfig.fromJson(
            j['mediaViewerToolbarConfig'] as Map<String, dynamic>?,
          )
        : MediaViewerToolbarConfig.defaults();

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
      resetSizeOnLayoutChange: j['resetSizeOnLayoutChange'] as bool? ?? true,
      autoHideAppBar: j['autoHideAppBar'] as bool? ?? true,
      useFabForToolbar: j['useFabForToolbar'] as bool? ?? false,
      bottomSelectionBar: j['bottomSelectionBar'] as bool? ?? false,
      folderLayoutModes: rawFolderLayoutModes,
      folderGridAspectRatios: rawFolderGridAspectRatios,
      folderSortModes: rawFolderSortModes,
      detailColumnsOrder: rawDetailColumns.isEmpty
          ? const [
              FileDetailColumn.date,
              FileDetailColumn.size,
              FileDetailColumn.type,
            ]
          : rawDetailColumns,
      hiddenDetailColumns: hiddenDetailColumns,
      showGridFileNames: j['showGridFileNames'] as bool? ?? true,
      gridAspectRatio:
          GridAspectRatio.fromJson(j['gridAspectRatio'] as String?),
      // Absent in configs saved before these options existed -> the
      // original look (rounded, 8px gaps).
      gridCornerStyle:
          GridCornerStyle.fromJson(j['gridCornerStyle'] as String?),
      gridSpacing: ((j['gridSpacing'] as num?)?.toInt() ?? defaultGridSpacing)
          .clamp(minGridSpacing, maxGridSpacing),
      showListThumbnails: j['showListThumbnails'] as bool? ?? true,
      showItemActionsMenu: j['showItemActionsMenu'] as bool? ?? true,
      // Absent in configs saved before these options existed -> the original
      // behavior (icon taps select; names shown in full).
      selectByIcon: j['selectByIcon'] as bool? ?? true,
      showFileExtensions: j['showFileExtensions'] as bool? ?? true,
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
      localStorageThumbnailCacheMode: localStorageThumbnailCacheMode,
      localStorageThumbnailQuality: localStorageThumbnailQuality,
      mediaViewerToolbarConfig: mediaViewerConfig,
      // Absent in configs saved before skins existed -> classic.
      skin: FileManagerSkin.fromJson(j['skin']),
    );
  }
}