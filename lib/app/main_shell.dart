import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_screen.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';

/// Top-level two-tab shell: [VaultDashboard] ("Vaults") and [ToolsScreen]
/// ("Tools"), switched by a bottom bar that also holds a centered "Add
/// vault" button -- see the Tools-page design note's "Primary Navigation
/// Structure" section for why a bottom bar (not top tabs) replaced the
/// earlier idea (top tabs would have competed visually with
/// [VaultDashboard]'s own app bar title/search/Mask Mode trigger,
/// ADR-028).
///
/// The "Add vault" action used to be a [FloatingActionButton.extended] on
/// [VaultDashboard]'s own [Scaffold], reachable only from the Vaults tab.
/// It now lives here instead, as a plain button in the middle of the
/// bottom bar's row -- no floating/docked FAB, no notch, just a third
/// item alongside the two tabs -- so it's one tap away regardless of
/// which tab is showing. [_dashboardKey] reaches into [VaultDashboard]'s
/// state to trigger the same "Mount / USB / Create" menu that FAB used
/// to open -- see [VaultDashboardActions].
///
/// [_mountedNotifier] is the single live list of mounted volumes both tabs
/// see: [VaultDashboard] writes to it (via its `mountedNotifier` param)
/// every time its own `_mounted` list changes, and [ToolsScreen] reads it
/// (via `mountedContainers`) for the Storage Analyzer's target picker and
/// the Repair wizard's "choose a mounted volume" step. Neither tab tracks
/// mounted-volume state independently.
///
/// Not reachable from Mask Mode / Disguise Mode: `_DisguiseModeGate`
/// (`lib/app/vault_explorer_app.dart`) routes decoy mode straight to
/// `DecoyArchiveExplorerScreen` instead of `LockGateScreen` → [MainShell],
/// so the Tools tab structurally never appears there -- no extra
/// hide-when-disguised logic needed on this end.
///
/// An [IndexedStack] (not a route switch) keeps both tabs alive across
/// switches, so browsing state in the Vaults tab and any in-flight
/// Tools-tab sheet survive a tab change instead of rebuilding from scratch.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final ValueNotifier<List<MountedContainer>> _mountedNotifier =
      ValueNotifier(const []);

  /// Typed as the public [VaultDashboardActions] interface (not the
  /// private `_VaultDashboardState`) so this file can call
  /// [VaultDashboardActions.showAddVaultMenu] without needing to name a
  /// class it isn't allowed to see.
  final GlobalKey<State<VaultDashboard>> _dashboardKey =
      GlobalKey<State<VaultDashboard>>();

  @override
  void dispose() {
    _mountedNotifier.dispose();
    super.dispose();
  }

 void _onAddVaultTap() {
    (_dashboardKey.currentState as VaultDashboardActions?)?.showAddVaultMenu();
  }


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          VaultDashboard(key: _dashboardKey, mountedNotifier: _mountedNotifier),
          ToolsScreen(mountedContainers: _mountedNotifier),
        ],
      ),
      bottomNavigationBar: Material(
        color: cs.surfaceContainer,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                _MainBottomBarItem(
                  icon: Icons.lock_outline_rounded,
                  selectedIcon: Icons.lock_rounded,
                  label: context.l10n.navBarVaultsLabel,
                  selected: _index == 0,
                  onTap: () => setState(() => _index = 0),
                ),
                _MainBottomBarItem(
                  icon: Icons.add_rounded,
                  selectedIcon: Icons.add_rounded,
                  label: context.l10n.addVaultFabLabel,
                  selected: false,
                  onTap: _onAddVaultTap,
                ),
                _MainBottomBarItem(
                  icon: Icons.build_outlined,
                  selectedIcon: Icons.build_rounded,
                  label: context.l10n.navBarToolsLabel,
                  selected: _index == 1,
                  onTap: () => setState(() => _index = 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tab in [MainShell]'s bottom bar -- a stand-in for
/// [NavigationDestination] (which needs a full destinations list, leaving
/// no room for the "Add vault" button in between), styled to match: a
/// pill-shaped selected indicator behind the icon, primary-tinted icon
/// and label when selected, muted otherwise.
class _MainBottomBarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _MainBottomBarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6), // Reduced from 10 to 6
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? cs.secondaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(selected ? selectedIcon : icon, color: color, size: 22),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}