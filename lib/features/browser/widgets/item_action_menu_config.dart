import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/file_item_action.dart';

/// Popup-menu `value` -> the configurable action it stands for. Values that
/// are not listed (select all, file info, ...) are not configurable and are
/// left alone by [applyItemActionMenuConfig].
const Map<String, FileItemAction> _actionForMenuValue = {
  'open_in_new_tab': FileItemAction.openInNewTab,
  'open_with_app': FileItemAction.openWith,
  'share': FileItemAction.share,
  'edit_image': FileItemAction.editImage,
  'edit_video': FileItemAction.editVideo,
  'edit_audio': FileItemAction.editAudio,
  'rename': FileItemAction.rename,
  'copy': FileItemAction.copy,
  'cut': FileItemAction.move,
  'compress': FileItemAction.archive,
  'export': FileItemAction.exportToDevice,
  'encrypt': FileItemAction.encrypt,
  'decrypt': FileItemAction.decrypt,
  'doc_provider': FileItemAction.docProvider,
  'sync_settings': FileItemAction.syncSettings,
  'pin': FileItemAction.pin,
  'unpin': FileItemAction.pin,
  'bookmark': FileItemAction.bookmark,
  'unbookmark': FileItemAction.bookmark,
};

/// Applies the user's item-action configuration to a selection-bar overflow
/// menu: drops the [hidden] actions and re-orders the rest by [order].
///
/// Only the configurable items move, and only among the slots they already
/// occupy, so unconfigurable items (select all at the top, file info at the
/// bottom) stay where the menu put them. Items that map to the same action
/// (pin / unpin) keep their relative order.
List<PopupMenuItem<String>> applyItemActionMenuConfig(
  List<PopupMenuItem<String>> items, {
  required List<FileItemAction> order,
  required Set<FileItemAction> hidden,
}) {
  final kept = <PopupMenuItem<String>>[
    for (final item in items)
      if (!hidden.contains(_actionForMenuValue[item.value])) item,
  ];

  final slots = <int>[
    for (var i = 0; i < kept.length; i++)
      if (_actionForMenuValue.containsKey(kept[i].value)) i,
  ];
  if (slots.length < 2) return kept;

  final rank = <FileItemAction, int>{
    for (var i = 0; i < order.length; i++) order[i]: i,
  };
  int rankOf(PopupMenuItem<String> item) =>
      rank[_actionForMenuValue[item.value]] ?? order.length;

  final movable = <({int rank, int index, PopupMenuItem<String> item})>[
    for (var n = 0; n < slots.length; n++)
      (rank: rankOf(kept[slots[n]]), index: n, item: kept[slots[n]]),
  ]..sort((a, b) {
      final byRank = a.rank.compareTo(b.rank);
      return byRank != 0 ? byRank : a.index.compareTo(b.index);
    });

  final result = List<PopupMenuItem<String>>.of(kept);
  for (var n = 0; n < slots.length; n++) {
    result[slots[n]] = movable[n].item;
  }
  return result;
}
