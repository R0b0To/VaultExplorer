import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_screen.dart';
import 'package:vaultexplorer/features/settings/app_settings_screen.dart';
import 'package:vaultexplorer/features/tools/tools_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final ValueNotifier<List<MountedContainer>> _mountedNotifier =
      ValueNotifier(const []);
  final GlobalKey<VaultDashboardState> _dashboardKey =
      GlobalKey<VaultDashboardState>();

  @override
  void dispose() {
    _mountedNotifier.dispose();
    super.dispose();
  }

  void _onTabTap(int newIndex) {
    if (_index != newIndex) {
      setState(() => _index = newIndex);
      if (newIndex == 0) {
        _dashboardKey.currentState?.reloadDashboard();
      }
    }
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
          const AppSettingsScreen(),
        ],
      ),
      bottomNavigationBar: Material(
        color: cs.surfaceContainer,
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 68,
            child: Row(
              children: [
                _MainBottomBarItem(
                  icon: Icons.lock_outline_rounded,
                  selectedIcon: Icons.lock_rounded,
                  label: context.l10n.navBarVaultsLabel,
                  selected: _index == 0,
                  onTap: () => _onTabTap(0),
                ),
                _MainBottomBarItem(
                  icon: Icons.build_outlined,
                  selectedIcon: Icons.build_rounded,
                  label: context.l10n.navBarToolsLabel,
                  selected: _index == 1,
                  onTap: () => _onTabTap(1),
                ),
                _MainBottomBarItem(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                  label: context.l10n.settingsTooltip,
                  selected: _index == 2,
                  onTap: () => _onTabTap(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  softWrap: false,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}