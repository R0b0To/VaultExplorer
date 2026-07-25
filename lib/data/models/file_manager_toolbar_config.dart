import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/file_manager_action.dart';

enum FileDetailColumn {
  date,
  size,
  type;

  String get label => switch (this) {
        FileDetailColumn.date => 'Date',
        FileDetailColumn.size => 'Size',
        FileDetailColumn.type => 'Type',
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
  final List<FileDetailColumn> detailColumnsOrder;
  final Set<FileDetailColumn> hiddenDetailColumns;
  final bool showGridFileNames;

  const FileManagerToolbarConfig({
    required this.order,
    required this.hidden,
    this.showBreadcrumbBar = true,
    this.showStatsBar = true,
    this.showMediaCarousel = true,
    this.detailColumnsOrder = const [
      FileDetailColumn.date,
      FileDetailColumn.size,
      FileDetailColumn.type,
    ],
    this.hiddenDetailColumns = const {FileDetailColumn.type},
    this.showGridFileNames = true,
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
        detailColumnsOrder: [
          FileDetailColumn.date,
          FileDetailColumn.size,
          FileDetailColumn.type,
        ],
        hiddenDetailColumns: {FileDetailColumn.type},
        showGridFileNames: true,
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
    List<FileDetailColumn>? detailColumnsOrder,
    Set<FileDetailColumn>? hiddenDetailColumns,
    bool? showGridFileNames,
  }) =>
      FileManagerToolbarConfig(
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
        showBreadcrumbBar: showBreadcrumbBar ?? this.showBreadcrumbBar,
        showStatsBar: showStatsBar ?? this.showStatsBar,
        showMediaCarousel: showMediaCarousel ?? this.showMediaCarousel,
        detailColumnsOrder: detailColumnsOrder ?? this.detailColumnsOrder,
        hiddenDetailColumns: hiddenDetailColumns ?? this.hiddenDetailColumns,
        showGridFileNames: showGridFileNames ?? this.showGridFileNames,
      );

  Map<String, dynamic> toJson() => {
        'order': order.map((a) => a.toJson()).toList(),
        'hidden': hidden.map((a) => a.toJson()).toList(),
        'showBreadcrumbBar': showBreadcrumbBar,
        'showStatsBar': showStatsBar,
        'showMediaCarousel': showMediaCarousel,
        'detailColumnsOrder':
            detailColumnsOrder.map((c) => c.toJson()).toList(),
        'hiddenDetailColumns':
            hiddenDetailColumns.map((c) => c.toJson()).toList(),
        'showGridFileNames': showGridFileNames,
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
      detailColumnsOrder: rawDetailColumns.isEmpty
          ? const [
              FileDetailColumn.date,
              FileDetailColumn.size,
              FileDetailColumn.type,
            ]
          : rawDetailColumns,
      hiddenDetailColumns: hiddenDetailColumns,
      showGridFileNames: j['showGridFileNames'] as bool? ?? true,
    );
  }
}