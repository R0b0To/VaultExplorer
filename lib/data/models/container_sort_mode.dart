import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// How container cards are ordered on the dashboard.
///
/// [manual] preserves the user's own drag-and-drop ordering
/// ([_recordsOrder] in vault_dashboard.dart) — this is the only mode in
/// which [ReorderableListView] dragging is actually enabled; the other
/// modes derive a fresh order on every build, so manual drag reordering
/// would just get silently overwritten.
enum ContainerSortMode {
  manual,
  unlockStatus,
  nameAZ,
  newest,
  oldest;

  String get label => switch (this) {
        ContainerSortMode.manual => 'Manual (drag to reorder)',
        ContainerSortMode.unlockStatus => 'Unlock status (unlocked first)',
        ContainerSortMode.nameAZ => 'Name (A–Z)',
        ContainerSortMode.newest => 'Newest first',
        ContainerSortMode.oldest => 'Oldest first',
      };

  String getLocalizedLabel(AppLocalizations l10n) => switch (this) {
        ContainerSortMode.manual => l10n.sortContainersModeManual,
        ContainerSortMode.unlockStatus => l10n.sortContainersModeUnlockStatus,
        ContainerSortMode.nameAZ => l10n.sortContainersModeNameAZ,
        ContainerSortMode.newest => l10n.sortContainersModeNewest,
        ContainerSortMode.oldest => l10n.sortContainersModeOldest,
      };

  String toJson() => name;

  static ContainerSortMode fromJson(String? value) => switch (value) {
        'manual' => ContainerSortMode.manual,
        'unlockStatus' => ContainerSortMode.unlockStatus,
        'nameAZ' => ContainerSortMode.nameAZ,
        'newest' => ContainerSortMode.newest,
        'oldest' => ContainerSortMode.oldest,
        _ => ContainerSortMode.manual,
      };
}
