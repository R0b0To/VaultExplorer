import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/app_page_windows.dart';
import 'package:vaultexplorer/features/dashboard/widgets/quick_password_generator_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/container_repair_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/hash_verifier_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/header_backup_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/keyfile_passphrase_generator_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/single_file_crypto_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/storage_analyzer_screen.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_screen.dart';

/// Opens the password generator as a sheet. Nothing is returned to a caller:
/// from the toolbar the generator is a standalone helper, the result is
/// copied from the sheet itself.
Future<void> showQuickPasswordGenerator(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
    ),
    builder: (ctx) => const QuickPasswordGeneratorSheet(),
  );
}

enum _DashboardTool {
  keyfileGenerator,
  encryptFiles,
  hashVerifier,
  headerBackup,
  repair,
  storageAnalyzer,
  vaultSync,
  allTools,
}

void _openDashboardTool(
  BuildContext context,
  WidgetRef ref,
  _DashboardTool tool,
) {
    if (tool == _DashboardTool.allTools) {
      openToolsWindow(context);
      return;
    }
    final mounted = ValueNotifier(
      ref.read(vaultDashboardControllerProvider).mounted,
    );
    final Widget screen = switch (tool) {
      _DashboardTool.keyfileGenerator => KeyfilePassphraseGeneratorScreen(
        mountedContainers: mounted,
      ),
      _DashboardTool.encryptFiles => SingleFileCryptoSheet(
        mountedContainers: mounted,
      ),
      _DashboardTool.hashVerifier => HashVerifierSheet(
        mountedContainers: mounted,
      ),
      _DashboardTool.headerBackup => const HeaderBackupSheet(),
      _DashboardTool.repair => ContainerRepairSheet(mountedContainers: mounted),
      _DashboardTool.storageAnalyzer => StorageAnalyzerScreen(
        mountedContainers: mounted,
      ),
      _DashboardTool.vaultSync => VaultSyncScreen(mountedContainers: mounted),
      _DashboardTool.allTools => const SizedBox.shrink(),
    };
   Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SkinAreaScope(area: SkinArea.tools, child: screen),
      ),
    );
  }

List<Widget> buildDashboardToolsMenuItems(
  BuildContext context,
  WidgetRef ref,
) {
  final cs = Theme.of(context).colorScheme;
  final l10n = context.l10n;
  Widget entry(_DashboardTool tool, IconData icon, String label) =>
      MenuItemButton(
        leadingIcon: Icon(icon, size: 20, color: cs.onSurfaceVariant),
        onPressed: () => _openDashboardTool(context, ref, tool),
        child: Text(label),
      );
  return [
    entry(
      _DashboardTool.keyfileGenerator,
      Icons.key_rounded,
      l10n.keyfilePassphraseGeneratorTitle,
    ),
    entry(
      _DashboardTool.encryptFiles,
      Icons.enhanced_encryption_rounded,
      l10n.toolSingleFileCryptoTitle,
    ),
    entry(
      _DashboardTool.hashVerifier,
      Icons.verified_rounded,
      l10n.toolHashVerifierTitle,
    ),
    const Divider(height: 1),
    entry(
      _DashboardTool.headerBackup,
      Icons.settings_backup_restore_rounded,
      l10n.toolHeaderBackupTitle,
    ),
    entry(
      _DashboardTool.repair,
      Icons.build_rounded,
      l10n.toolContainerRepairTitle,
    ),
    entry(
      _DashboardTool.vaultSync,
      Icons.sync_alt_rounded,
      l10n.toolVaultSyncTitle,
    ),
    entry(
      _DashboardTool.storageAnalyzer,
      Icons.pie_chart_rounded,
      l10n.toolStorageAnalyzerTitle,
    ),
    const Divider(height: 1),
    entry(
      _DashboardTool.allTools,
      Icons.apps_rounded,
      l10n.navBarToolsLabel,
    ),
  ];
}

/// The vault tools worth having one click away on the desktop Vaults toolbar,
/// the same screens the Tools page lists. "All tools" opens that page.
///
/// The tools that work on an unlocked vault are handed the vaults unlocked
/// when the menu item is chosen.
class DashboardToolsMenuButton extends ConsumerWidget {
  const DashboardToolsMenuButton({super.key});

  PopupMenuItem<_DashboardTool> _item(
    ColorScheme cs,
    _DashboardTool tool,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<_DashboardTool>(
      value: tool,
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return PopupMenuButton<_DashboardTool>(
      icon: const Icon(Icons.handyman_outlined),
      tooltip: l10n.toolsScreenTitle,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
         onSelected: (tool) => _openDashboardTool(context, ref, tool),
      itemBuilder: (_) => [
        _item(
          cs,
          _DashboardTool.keyfileGenerator,
          Icons.key_rounded,
          l10n.keyfilePassphraseGeneratorTitle,
        ),
        _item(
          cs,
          _DashboardTool.encryptFiles,
          Icons.enhanced_encryption_rounded,
          l10n.toolSingleFileCryptoTitle,
        ),
        _item(
          cs,
          _DashboardTool.hashVerifier,
          Icons.verified_rounded,
          l10n.toolHashVerifierTitle,
        ),
        const PopupMenuDivider(),
        _item(
          cs,
          _DashboardTool.headerBackup,
          Icons.settings_backup_restore_rounded,
          l10n.toolHeaderBackupTitle,
        ),
        _item(
          cs,
          _DashboardTool.repair,
          Icons.build_rounded,
          l10n.toolContainerRepairTitle,
        ),
        _item(
          cs,
          _DashboardTool.vaultSync,
          Icons.sync_alt_rounded,
          l10n.toolVaultSyncTitle,
        ),
        _item(
          cs,
          _DashboardTool.storageAnalyzer,
          Icons.pie_chart_rounded,
          l10n.toolStorageAnalyzerTitle,
        ),
        const PopupMenuDivider(),
        _item(
          cs,
          _DashboardTool.allTools,
          Icons.apps_rounded,
          l10n.navBarToolsLabel,
        ),
      ],
    );
  }
}
