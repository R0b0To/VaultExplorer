import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';
import 'package:vaultexplorer/data/models/playlist_transition_effect.dart';
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
  final bool showMediaCarousel;
  final bool autoStartPlaylistMode;
  final List<FileDetailColumn> detailColumnsOrder;
  final Set<FileDetailColumn> hiddenDetailColumns;
  final bool showGridFileNames;
  final bool showListThumbnails;
  final double listZoomLevel;
  final int gridColumnsPortrait;
  final int gridColumnsLandscape;
  final int masonryColumnsPortrait;
  final int masonryColumnsLandscape;
  final PlaylistTransitionEffect playlistTransitionEffect;

  const FileManagerToolbarConfig({
    required this.order,
    required this.hidden,
    this.showBreadcrumbBar = true,
    this.showStatsBar = true,
    this.showMediaCarousel = true,
    this.autoStartPlaylistMode = false,
    this.detailColumnsOrder = const [
      FileDetailColumn.date,
      FileDetailColumn.size,
      FileDetailColumn.type,
    ],
    this.hiddenDetailColumns = const {FileDetailColumn.type},
    this.showGridFileNames = true,
    this.showListThumbnails = true,
    this.listZoomLevel = 1.0,
    this.gridColumnsPortrait = 3,
    this.gridColumnsLandscape = 5,
    this.masonryColumnsPortrait = 2,
    this.masonryColumnsLandscape = 4,
    this.playlistTransitionEffect = PlaylistTransitionEffect.slide,
  });

  factory FileManagerToolbarConfig.defaults() => const FileManagerToolbarConfig(
        order: [
          FileManagerAction.search,
          FileManagerAction.add,
          FileManagerAction.viewToggle,
          FileManagerAction.sort,
          FileManagerAction.playMedia,
        ],
        hidden: {},
        showBreadcrumbBar: true,
        showStatsBar: true,
        showMediaCarousel: true,
        autoStartPlaylistMode: false,
        detailColumnsOrder: [
          FileDetailColumn.date,
          FileDetailColumn.size,
          FileDetailColumn.type,
        ],
        hiddenDetailColumns: {FileDetailColumn.type},
        showGridFileNames: true,
        showListThumbnails: true,
        listZoomLevel: 1.0,
        gridColumnsPortrait: 3,
        gridColumnsLandscape: 5,
        masonryColumnsPortrait: 2,
        masonryColumnsLandscape: 4,
        playlistTransitionEffect: PlaylistTransitionEffect.slide,
      );

  List<FileManagerAction> get visible =>
      order.where((a) => !hidden.contains(a)).toList(growable: false);

  List<FileDetailColumn> get visibleDetailColumns => detailColumnsOrder
      .where((c) => !hiddenDetailColumns.contains(c))
      .toList(growable: false);

  FileManagerToolbarConfig copyWith({
    List<FileManagerAction>? order,
    Set<FileManagerAction>? hidden,
    bool? showBreadcrumbBar,
    bool? showStatsBar,
    bool? showMediaCarousel,
    bool? autoStartPlaylistMode,
    List<FileDetailColumn>? detailColumnsOrder,
    Set<FileDetailColumn>? hiddenDetailColumns,
    bool? showGridFileNames,
    bool? showListThumbnails,
    double? listZoomLevel,
    int? gridColumnsPortrait,
    int? gridColumnsLandscape,
    int? masonryColumnsPortrait,
    int? masonryColumnsLandscape,
    PlaylistTransitionEffect? playlistTransitionEffect,
  }) =>
      FileManagerToolbarConfig(
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
        showBreadcrumbBar: showBreadcrumbBar ?? this.showBreadcrumbBar,
        showStatsBar: showStatsBar ?? this.showStatsBar,
        showMediaCarousel: showMediaCarousel ?? this.showMediaCarousel,
        autoStartPlaylistMode:
            autoStartPlaylistMode ?? this.autoStartPlaylistMode,
        detailColumnsOrder: detailColumnsOrder ?? this.detailColumnsOrder,
        hiddenDetailColumns: hiddenDetailColumns ?? this.hiddenDetailColumns,
        showGridFileNames: showGridFileNames ?? this.showGridFileNames,
        showListThumbnails: showListThumbnails ?? this.showListThumbnails,
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
      );

  Map<String, dynamic> toJson() => {
        'order': order.map((a) => a.toJson()).toList(),
        'hidden': hidden.map((a) => a.toJson()).toList(),
        'showBreadcrumbBar': showBreadcrumbBar,
        'showStatsBar': showStatsBar,
        'showMediaCarousel': showMediaCarousel,
        'autoStartPlaylistMode': autoStartPlaylistMode,
        'detailColumnsOrder':
            detailColumnsOrder.map((c) => c.toJson()).toList(),
        'hiddenDetailColumns':
            hiddenDetailColumns.map((c) => c.toJson()).toList(),
        'showGridFileNames': showGridFileNames,
        'showListThumbnails': showListThumbnails,
        'listZoomLevel': listZoomLevel,
        'gridColumnsPortrait': gridColumnsPortrait,
        'gridColumnsLandscape': gridColumnsLandscape,
        'masonryColumnsPortrait': masonryColumnsPortrait,
        'masonryColumnsLandscape': masonryColumnsLandscape,
        'playlistTransitionEffect': playlistTransitionEffect.toJson(),
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
    return FileManagerToolbarConfig(
      order: rawOrder,
      hidden: hidden,
      showBreadcrumbBar: j['showBreadcrumbBar'] as bool? ?? true,
      showStatsBar: j['showStatsBar'] as bool? ?? true,
      showMediaCarousel: j['showMediaCarousel'] as bool? ?? true,
      autoStartPlaylistMode: j['autoStartPlaylistMode'] as bool? ?? false,
      detailColumnsOrder: rawDetailColumns.isEmpty
          ? const [
              FileDetailColumn.date,
              FileDetailColumn.size,
              FileDetailColumn.type,
            ]
          : rawDetailColumns,
      hiddenDetailColumns: hiddenDetailColumns,
      showGridFileNames: j['showGridFileNames'] as bool? ?? true,
      showListThumbnails: j['showListThumbnails'] as bool? ?? true,
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
    );
  }
}