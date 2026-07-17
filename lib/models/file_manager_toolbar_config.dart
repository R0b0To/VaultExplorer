import 'file_manager_action.dart';

/// User-customizable ordering/visibility of the file browser's action bar
/// (Search / Add / View toggle / Sort / Play Media).
///
/// [order] always contains every [FileManagerAction] value exactly once.
/// Hidden actions deliberately stay in [order] (rather than being removed)
/// so the customize-toolbar settings screen can still show them — grayed
/// out, in their last position — and let the user turn them back on
/// without losing where they were.
class FileManagerToolbarConfig {
  final List<FileManagerAction> order;
  final Set<FileManagerAction> hidden;
  final bool showBreadcrumbBar;
  final bool showStatsBar;

  const FileManagerToolbarConfig({
    required this.order,
    required this.hidden,
    this.showBreadcrumbBar = true,
    this.showStatsBar = true,
  });

  /// Default toolbar: every action visible, in a sensible default order.
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
      );

  /// Actions to actually render, in display order, with hidden ones removed.
  List<FileManagerAction> get visible =>
      order.where((a) => !hidden.contains(a)).toList(growable: false);

  FileManagerToolbarConfig copyWith({
    List<FileManagerAction>? order,
    Set<FileManagerAction>? hidden,
    bool? showBreadcrumbBar,
    bool? showStatsBar,
  }) =>
      FileManagerToolbarConfig(
        order: order ?? this.order,
        hidden: hidden ?? this.hidden,
        showBreadcrumbBar: showBreadcrumbBar ?? this.showBreadcrumbBar,
        showStatsBar: showStatsBar ?? this.showStatsBar,
      );

  Map<String, dynamic> toJson() => {
        'order': order.map((a) => a.toJson()).toList(),
        'hidden': hidden.map((a) => a.toJson()).toList(),
        'showBreadcrumbBar': showBreadcrumbBar,
        'showStatsBar': showStatsBar,
      };

  factory FileManagerToolbarConfig.fromJson(Map<String, dynamic>? j) {
    if (j == null) return FileManagerToolbarConfig.defaults();

    final rawOrder = (j['order'] as List<dynamic>? ?? [])
        .map((v) => FileManagerAction.fromJson(v as String?))
        .whereType<FileManagerAction>()
        .toList();

    // Guards against a config saved by an older app version that predates
    // a newly-added action: append anything missing at the end so it's
    // still reachable, rather than silently vanishing because it wasn't
    // in the persisted list.
    for (final a in FileManagerAction.values) {
      if (!rawOrder.contains(a)) rawOrder.add(a);
    }

    final hidden = (j['hidden'] as List<dynamic>? ?? [])
        .map((v) => FileManagerAction.fromJson(v as String?))
        .whereType<FileManagerAction>()
        .toSet();

    return FileManagerToolbarConfig(
      order: rawOrder,
      hidden: hidden,
      showBreadcrumbBar: j['showBreadcrumbBar'] as bool? ?? true,
      showStatsBar: j['showStatsBar'] as bool? ?? true,
    );
  }
}
