import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

class EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const EmptyState({super.key, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.lock_outline_rounded,
      title: context.l10n.noContainersYetTitle,
      message: context.l10n.dashboardEmptyStateMessage,
      actionLabel: context.l10n.addVaultFabLabel,
      onAction: onAdd,
    );
  }
}