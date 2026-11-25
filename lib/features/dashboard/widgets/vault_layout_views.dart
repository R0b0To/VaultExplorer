import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/platform_features.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/core/widgets/menus/context_menu_region.dart';
import 'package:vaultexplorer/data/models/app_storage_vault_uri.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/browser/widgets/file_name_label.dart';
import 'package:vaultexplorer/features/dashboard/widgets/auto_lock_indicator.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_card.dart';
import 'package:vaultexplorer/features/settings/long_file_name_display_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Shared description of one vault
// ─────────────────────────────────────────────────────────────────────────────

/// What the compact dashboard layouts (grid, list, details) need to draw one
/// vault, read once from the list item so that all of them agree on the icon,
/// the colours, the state text and the usage figures.
///
/// The card layout keeps its own widgets ([ContainerCard] and
/// [SavedContainerCard]); this mirrors what they show.
class VaultEntryInfo {
  const VaultEntryInfo._({
    required this.item,
    required this.isUsb,
    required this.inAppStorage,
    required this.format,
    required this.total,
    required this.free,
    required this.container,
  });

  factory VaultEntryInfo.of(VaultListItem item) => switch (item) {
    MountedVaultItem(:final container) => VaultEntryInfo._(
      item: item,
      isUsb: container.uri.startsWith('usb:'),
      inAppStorage: false,
      format: container.format,
      total: container.totalSpace,
      free: container.freeSpace,
      container: container,
    ),
    LockedVaultItem(:final record) => VaultEntryInfo._(
      item: item,
      isUsb: item.uri.startsWith('usb:'),
      inAppStorage: AppStorageVaultUri.isAppStorage(item.uri),
      format: ContainerFormat.fromWire(record.containerFormat),
      total: 0,
      free: 0,
      container: null,
    ),
  };

  final VaultListItem item;
  final bool isUsb;
  final bool inAppStorage;
  final ContainerFormat format;
  final int total;
  final int free;

  /// Set only while the vault is unlocked.
  final MountedContainer? container;

  String get name => item.name;
  bool get isMounted => item.isMounted;

  /// Whether the capacity of the vault is known (unlocked vaults only).
  bool get hasSpace => isMounted && total > 0;

  double get usedFraction =>
      hasSpace ? ((total - free) / total).clamp(0.0, 1.0).toDouble() : 0.0;

  /// The one-line state shown under the name: free space of an unlocked vault,
  /// otherwise why it is locked. Same texts as the card layout.
  String statusLabel(BuildContext context) {
    final l10n = context.l10n;
    if (isMounted) {
      return hasSpace
          ? l10n.containerSpaceSummary(formatBytes(free), formatBytes(total))
          : l10n.volMountedSummary(container?.volId ?? 0);
    }
    if (isUsb) return l10n.usbDriveLockedLabel;
    if (inAppStorage) {
      return '${l10n.lockedContainerLabel} · ${l10n.storageLocationAppStorage}';
    }
    return l10n.lockedContainerLabel;
  }
}

class _Tints {
  const _Tints({
    required this.card,
    required this.iconBg,
    required this.iconFg,
  });

  final Color card;
  final Color iconBg;
  final Color iconFg;
}

/// The same colours the card layout gives an unlocked and a locked vault.
_Tints _tintsOf(BuildContext context, VaultEntryInfo e) {
  final cs = Theme.of(context).colorScheme;
  if (!e.isMounted) {
    return _Tints(
      card: cs.surfaceContainerHigh,
      iconBg: cs.surfaceContainerHighest,
      iconFg: cs.onSurfaceVariant,
    );
  }
  final isLight = cs.brightness == Brightness.light;
  final cardBg = Color.alphaBlend(
    isLight
        ? cs.primaryContainer.withValues(alpha: 0.55)
        : cs.primaryContainer.withValues(alpha: 0.35),
    cs.surfaceContainerHigh,
  );
  return _Tints(
    card: SkinAreaScope.colorOf(
      context,
      SkinToken.surfaceCardActive,
      fallback: cardBg,
    ),
    iconBg: cs.primaryContainer,
    iconFg: cs.onPrimaryContainer,
  );
}

Widget _formatIcon(VaultEntryInfo e, Color color, double size) => e.isUsb
    ? Icon(Icons.usb_rounded, size: size, color: color)
    : ContainerFormatIcon(format: e.format, size: size, color: color);

/// The rounded icon square of a vault, with the auto-lock badge on its corner.
class _EntryAvatar extends StatelessWidget {
  const _EntryAvatar({
    required this.entry,
    required this.record,
    required this.settings,
    required this.size,
    required this.iconSize,
    required this.radius,
    this.showBadge = true,
  });

  final VaultEntryInfo entry;
  final ContainerRecord? record;
  final AppSettings settings;
  final double size;
  final double iconSize;
  final double radius;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final tints = _tintsOf(context, entry);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: tints.iconBg,
            borderRadius: BorderRadius.circular(radius),
          ),
          child: Center(child: _formatIcon(entry, tints.iconFg, iconSize)),
        ),
        if (showBadge && entry.isMounted)
          Positioned(
            right: -3,
            bottom: -3,
            child: AutoLockIconBadge(record: record, settings: settings),
          ),
      ],
    );
  }
}

/// The thin usage bar. Unlocked vaults without a known capacity show an empty
/// track; locked ones only reserve the height, so tiles keep one height.
class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.entry, this.height = 4});

  final VaultEntryInfo entry;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!entry.isMounted) return SizedBox(height: height);
    final isLight = cs.brightness == Brightness.light;
    final track = isLight
        ? cs.primary.withValues(alpha: 0.12)
        : cs.onPrimaryContainer.withValues(alpha: 0.15);
    if (!entry.hasSpace) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(100),
        child: Container(height: height, color: track),
      );
    }
    final fraction = entry.usedFraction;
    return ClipRRect(
      borderRadius: BorderRadius.circular(100),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: fraction),
        duration: AppMotion.long1,
        curve: AppMotion.standard,
        builder: (context, animated, _) => LinearProgressIndicator(
          value: animated,
          minHeight: height,
          backgroundColor: track,
          valueColor: AlwaysStoppedAnimation<Color>(
            vaultUsageBarColor(fraction, cs),
          ),
        ),
      ),
    );
  }
}

/// Common inputs and actions of the three compact layouts.
abstract class _VaultEntryView extends ConsumerWidget {
  const _VaultEntryView({
    super.key,
    required this.item,
    required this.record,
    required this.appSettings,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onLocked,
  });

  final VaultListItem item;
  final ContainerRecord? record;
  final AppSettings appSettings;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<int> onLocked;

  /// The lock button of an unlocked vault, nothing for a locked one.
  Widget? lockButton(VaultEntryInfo e, double size) {
    final container = e.container;
    if (container == null) return null;
    return ContainerLockButton(
      container: container,
      onLocked: onLocked,
      size: size,
    );
  }

  /// The three-dots menu. Desktop opens the same actions with a right-click.
  Widget? moreButton(VaultEntryInfo e) => PlatformFeatures.isDesktop
      ? null
      : VaultMoreMenuButton(
          onEdit: onEdit,
          onDelete: onDelete,
          isMounted: e.isMounted,
          deletesFiles: e.inAppStorage,
        );

  void openMenu(BuildContext context, VaultEntryInfo e, Offset position) =>
      showVaultCardMenu(
        context,
        position,
        onEdit: onEdit,
        onDelete: onDelete,
        deletesFiles: e.inAppStorage,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Grid: vertical tile
// ─────────────────────────────────────────────────────────────────────────────

/// A vertical tile: big icon, name, state and usage bar -- the icon view of a
/// file manager's drives page.
class VaultGridTile extends _VaultEntryView {
  const VaultGridTile({
    super.key,
    required super.item,
    required super.record,
    required super.appSettings,
    required super.onOpen,
    required super.onEdit,
    required super.onDelete,
    required super.onLocked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = VaultEntryInfo.of(item);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tints = _tintsOf(context, e);
    final nameMode = ref.watch(longFileNameDisplayModeProvider);
    final lock = lockButton(e, 30);
    final more = moreButton(e);

    return ContextMenuRegion(
      onOpen: (pos) => openMenu(context, e, pos),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: tints.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: InkWell(
          onTap: onOpen,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _EntryAvatar(
                      entry: e,
                      record: record,
                      settings: appSettings,
                      size: 60,
                      iconSize: 30,
                      radius: 20,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: FileNameLabel(
                        text: e.name,
                        mode: nameMode,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      e.statusLabel(context),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontSize: 11.5,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _UsageBar(entry: e),
                  ],
                ),
              ),
              if (more != null) Positioned(top: 2, left: 2, child: more),
              if (lock != null) Positioned(top: 6, right: 6, child: lock),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// List: dense row
// ─────────────────────────────────────────────────────────────────────────────

/// A dense row: small icon, name and state, the lock button at the end.
class VaultListTile extends _VaultEntryView {
  const VaultListTile({
    super.key,
    required super.item,
    required super.record,
    required super.appSettings,
    required super.onOpen,
    required super.onEdit,
    required super.onDelete,
    required super.onLocked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = VaultEntryInfo.of(item);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final tints = _tintsOf(context, e);
    final nameMode = ref.watch(longFileNameDisplayModeProvider);
    final lock = lockButton(e, 32);
    final more = moreButton(e);

    return ContextMenuRegion(
      onOpen: (pos) => openMenu(context, e, pos),
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: tints.card,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md + 2),
        ),
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _EntryAvatar(
                  entry: e,
                  record: record,
                  settings: appSettings,
                  size: 38,
                  iconSize: 22,
                  radius: 12,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FileNameLabel(
                        text: e.name,
                        mode: nameMode,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        e.statusLabel(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 11.5,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (lock != null) ...[const SizedBox(width: 8), lock],
                if (more != null) ...[const SizedBox(width: 2), more],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Details: table row + header
// ─────────────────────────────────────────────────────────────────────────────

/// Which columns of the details table fit a given width. The header and every
/// row ask the same instance, so they always line up.
class VaultDetailsColumns {
  const VaultDetailsColumns._({
    required this.compact,
    required this.showFormat,
    required this.showState,
    required this.showFree,
    required this.showTotal,
    required this.showUsage,
  });

  /// Below this width a table is no use: rows fall back to the list look.
  static const double compactBelow = 520;

  static const double formatWidth = 104;
  static const double stateWidth = 96;
  static const double freeWidth = 92;
  static const double totalWidth = 92;
  static const double usageWidth = 148;
  static const double actionsWidth = 80;
  static const double columnGap = 12;

  factory VaultDetailsColumns.forWidth(double width) {
    if (width < compactBelow) {
      return const VaultDetailsColumns._(
        compact: true,
        showFormat: false,
        showState: false,
        showFree: false,
        showTotal: false,
        showUsage: false,
      );
    }
    return VaultDetailsColumns._(
      compact: false,
      showFormat: width >= 920,
      showState: true,
      showFree: true,
      showTotal: width >= 760,
      showUsage: width >= 640,
    );
  }

  final bool compact;
  final bool showFormat;
  final bool showState;
  final bool showFree;
  final bool showTotal;
  final bool showUsage;
}

/// The header row above the details table. Hidden when the table is compact.
class VaultDetailsHeader extends StatelessWidget {
  const VaultDetailsHeader({super.key, required this.width});

  /// Width of the row, excluding the list's side padding.
  final double width;

  @override
  Widget build(BuildContext context) {
    final cols = VaultDetailsColumns.forWidth(width);
    if (cols.compact) return const SizedBox.shrink();
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    Widget cell(String text, double w) => SizedBox(
      width: w,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
    const gap = SizedBox(width: VaultDetailsColumns.columnGap);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(
        children: [
          // Room of the icon in the rows below.
          const SizedBox(width: 32 + 12),
          Expanded(
            child: Text(
              l10n.sortFieldName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
          if (cols.showFormat) ...[
            gap,
            cell(l10n.formatLabel, VaultDetailsColumns.formatWidth),
          ],
          if (cols.showState) ...[
            gap,
            cell(l10n.vaultSyncSortStatus, VaultDetailsColumns.stateWidth),
          ],
          if (cols.showFree) ...[
            gap,
            cell(l10n.dashboardColumnFree, VaultDetailsColumns.freeWidth),
          ],
          if (cols.showTotal) ...[
            gap,
            cell(l10n.totalSizeLabel, VaultDetailsColumns.totalWidth),
          ],
          if (cols.showUsage) ...[
            gap,
            cell(l10n.dashboardColumnUsage, VaultDetailsColumns.usageWidth),
          ],
          gap,
          const SizedBox(width: VaultDetailsColumns.actionsWidth),
        ],
      ),
    );
  }
}

/// One row of the details table. On a narrow width it turns into a flat
/// two-line row so a phone still gets something readable.
class VaultDetailsRow extends _VaultEntryView {
  const VaultDetailsRow({
    super.key,
    required super.item,
    required super.record,
    required super.appSettings,
    required super.onOpen,
    required super.onEdit,
    required super.onDelete,
    required super.onLocked,
    required this.width,
  });

  /// Width of the row, excluding the list's side padding.
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = VaultEntryInfo.of(item);
    final cols = VaultDetailsColumns.forWidth(width);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final nameMode = ref.watch(longFileNameDisplayModeProvider);
    final l10n = context.l10n;
    final lock = lockButton(e, 30);
    final more = moreButton(e);

    final cellStyle = textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontSize: 12,
      height: 1.2,
    );
    Widget cell(String text, double w) => SizedBox(
      width: w,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: cellStyle,
      ),
    );
    const gap = SizedBox(width: VaultDetailsColumns.columnGap);
    const dash = '—';

    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FileNameLabel(
          text: e.name,
          mode: nameMode,
          style: textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
        // The table says the state in its own column.
        if (cols.compact) ...[
          const SizedBox(height: 1),
          Text(
            e.statusLabel(context),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: cellStyle,
          ),
        ],
      ],
    );

    final row = Row(
      children: [
        _EntryAvatar(
          entry: e,
          record: record,
          settings: appSettings,
          size: 32,
          iconSize: 18,
          radius: 10,
        ),
        const SizedBox(width: 12),
        Expanded(child: nameBlock),
        if (cols.showFormat) ...[
          gap,
          cell(e.format.label, VaultDetailsColumns.formatWidth),
        ],
        if (cols.showState) ...[
          gap,
          cell(
            e.isMounted ? l10n.vaultStatusUnlocked : l10n.vaultStatusLocked,
            VaultDetailsColumns.stateWidth,
          ),
        ],
        if (cols.showFree) ...[
          gap,
          cell(
            e.hasSpace ? formatBytes(e.free) : dash,
            VaultDetailsColumns.freeWidth,
          ),
        ],
        if (cols.showTotal) ...[
          gap,
          cell(
            e.hasSpace ? formatBytes(e.total) : dash,
            VaultDetailsColumns.totalWidth,
          ),
        ],
        if (cols.showUsage) ...[
          gap,
          SizedBox(
            width: VaultDetailsColumns.usageWidth,
            child: e.hasSpace
                ? Row(
                    children: [
                      Expanded(child: _UsageBar(entry: e)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${(e.usedFraction * 100).round()}%',
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          style: cellStyle,
                        ),
                      ),
                    ],
                  )
                : Text(dash, style: cellStyle),
          ),
        ],
        gap,
        SizedBox(
          width: VaultDetailsColumns.actionsWidth,
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [if (lock != null) lock, if (more != null) more],
            ),
          ),
        ),
      ],
    );

    return ContextMenuRegion(
      onOpen: (pos) => openMenu(context, e, pos),
      child: Material(
        color: e.isMounted
            ? cs.primaryContainer.withValues(alpha: 0.18)
            : Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: cs.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
            ),
            alignment: AlignmentDirectional.centerStart,
            child: row,
          ),
        ),
      ),
    );
  }
}
