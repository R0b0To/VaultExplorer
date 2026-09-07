import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_card.dart';

/// Pinned entry point into real, unencrypted device storage, shown above
/// the vault list when [AppSettings.showLocalStorageCard] is on and the
/// app already holds all-files access (see [AppSettingsScreen]'s "Key
/// Storage & System Access" section for the toggle, and
/// [VaultDashboardState] for the live permission check that gates it).
///
/// Tapping it opens the exact same [FileBrowserScreen] used for an
/// unlocked vault, pointed at [buildLocalStorageContainer] instead of a
/// real container -- the same screen [DecoyFileManagerScreen] already
/// serves for the decoy's local explorer. That reuse is what makes this
/// useful: a cut/copy staged in an open vault can be pasted straight in
/// here (or vice versa) through [CrossContainerClipboard], the same way
/// it would between two vaults, without an OS document-picker round trip.
///
/// Deliberately styled differently from [ContainerCard] -- a distinct
/// icon and a neutral/secondary tint rather than the vault cards'
/// primary-tinted lock imagery -- so it never reads as "just another
/// vault": this content isn't encrypted, and the card shouldn't imply
/// otherwise.
class LocalStorageCard extends StatelessWidget {
  final VoidCallback onTap;
  const LocalStorageCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BaseContainerCard(
      onTap: onTap,
      icon: Icon(
        Icons.smartphone_rounded,
        size: 26,
        color: cs.onSecondaryContainer,
      ),
      iconBackgroundColor: cs.secondaryContainer,
      title: context.l10n.localStorageCardTitle,
      backgroundColor: cs.surfaceContainerHigh,
      trailingAction: Icon(
        Icons.chevron_right_rounded,
        color: cs.onSurfaceVariant,
      ),
    );
  }
}
